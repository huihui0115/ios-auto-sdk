const assert = require('node:assert/strict');
const { EventEmitter } = require('node:events');
const test = require('node:test');
const { DeviceClient, requestTimeoutMilliseconds } = require('../device-client');

test('loading the client does not load ws before the first default connection', () => {
  assert.equal(require.cache[require.resolve('ws')], undefined);
});

test('request timeouts reject non-finite values and stay bounded', () => {
  assert.equal(requestTimeoutMilliseconds(Infinity), 30000);
  assert.equal(requestTimeoutMilliseconds('invalid'), 30000);
  assert.equal(requestTimeoutMilliseconds(1), 1000);
  assert.equal(requestTimeoutMilliseconds(24 * 60 * 60 * 1000), 60 * 60 * 1000);
});

class FakeWebSocket extends EventEmitter {
  static CONNECTING = 0;
  static OPEN = 1;
  static CLOSING = 2;
  static CLOSED = 3;
  static instances = [];

  constructor(url, options) {
    super();
    this.url = url;
    this.options = options;
    this.readyState = FakeWebSocket.CONNECTING;
    this.sent = [];
    FakeWebSocket.instances.push(this);
  }

  open() {
    this.readyState = FakeWebSocket.OPEN;
    this.emit('open');
  }

  send(message, callback) {
    this.sent.push(message);
    if (callback) callback();
  }

  ping() {}

  close() {
    this.readyState = FakeWebSocket.CLOSING;
  }

  terminate() {
    this.readyState = FakeWebSocket.CLOSED;
    this.emit('close');
  }

  receive(response) {
    this.emit('message', Buffer.from(JSON.stringify(response)));
  }

  finishClose() {
    this.readyState = FakeWebSocket.CLOSED;
    this.emit('close');
  }
}

function createClient(credentials, options = {}) {
  FakeWebSocket.instances = [];
  return new DeviceClient({
    credentials: async () => credentials.value,
    WebSocket: FakeWebSocket,
    ...options
  });
}

async function nextSocket(index = 0) {
  while (!FakeWebSocket.instances[index]) {
    await new Promise(resolve => setImmediate(resolve));
  }
  return FakeWebSocket.instances[index];
}

test('a delayed close from an old socket does not destroy the replacement', async () => {
  const credentials = { value: { url: 'ws://old:9001', token: 'old-token' } };
  const client = createClient(credentials);
  const firstConnection = client.ensureConnected();
  const first = await nextSocket(0);
  first.open();
  await firstConnection;

  credentials.value = { url: 'ws://new:9001', token: 'new-token' };
  const secondConnection = client.ensureConnected();
  const second = await nextSocket(1);
  second.open();
  await secondConnection;
  first.finishClose();

  assert.equal(client.socket, second);
  const request = client.request({ type: 'ping' });
  await new Promise(resolve => setImmediate(resolve));
  const payload = JSON.parse(second.sent.at(-1));
  second.receive({ id: payload.id, ok: true });
  assert.deepEqual(await request, { id: payload.id, ok: true });
  client.dispose();
});

test('late responses after a timeout are reported as orphans', async () => {
  const events = [];
  const credentials = { value: { url: 'ws://phone:9001', token: 'token' } };
  const client = createClient(credentials, { onEvent: event => events.push(event) });
  const connection = client.ensureConnected();
  const socket = await nextSocket(0);
  socket.open();
  await connection;

  const request = client.request({ type: 'ping' }, { timeoutMs: 1 });
  await new Promise(resolve => setImmediate(resolve));
  const payload = JSON.parse(socket.sent[0]);
  await assert.rejects(request, /Timed out waiting for ping/);
  socket.receive({ id: payload.id, ok: true });
  assert.equal(events[0].type, 'orphanResponse');
  assert.equal(events[0].id, payload.id);
  assert.equal(events[0].response, undefined);
  assert.ok(events[0].payloadBytes > 0);
  client.dispose();
});

test('requests carry their bounded response budget to the device', async () => {
  const credentials = { value: { url: 'ws://phone:9001', token: 'token' } };
  const client = createClient(credentials);
  const connection = client.ensureConnected();
  const socket = await nextSocket(0);
  socket.open();
  await connection;

  const request = client.request({ type: 'run', script: '1' }, { timeoutMs: 12345 });
  await new Promise(resolve => setImmediate(resolve));
  const payload = JSON.parse(socket.sent[0]);
  assert.equal(payload.timeoutMs, 12345);
  socket.receive({ id: payload.id, ok: true });
  await request;
  client.dispose();
});

test('pending requests are capped', async () => {
  const credentials = { value: { url: 'ws://phone:9001', token: 'token' } };
  const client = createClient(credentials, { maxPending: 1 });
  const connection = client.ensureConnected();
  const socket = await nextSocket(0);
  socket.open();
  await connection;

  const first = client.request({ type: 'nodes' }, { timeoutMs: 5000 });
  await new Promise(resolve => setImmediate(resolve));
  await assert.rejects(client.request({ type: 'nodes' }), /Too many AutoSDK requests/);
  client.disconnect('test complete');
  await assert.rejects(first, /test complete/);
});

test('aborting a pending request frees its slot and ignores a late response', async () => {
  const events = [];
  const credentials = { value: { url: 'ws://phone:9001', token: 'token' } };
  const client = createClient(credentials, { maxPending: 1, onEvent: event => events.push(event) });
  const connection = client.ensureConnected();
  const socket = await nextSocket(0);
  socket.open();
  await connection;
  const controller = new AbortController();

  const request = client.request({ type: 'inspectSnapshot' }, { timeoutMs: 5000, signal: controller.signal });
  await new Promise(resolve => setImmediate(resolve));
  const payload = JSON.parse(socket.sent[0]);
  controller.abort();
  await assert.rejects(request, error => error.name === 'AbortError');
  assert.equal(client.pending.size, 0);
  assert.equal(client.ignoredResponses.size, 1);

  socket.receive({ id: payload.id, ok: true });
  assert.deepEqual(events, []);
  assert.equal(client.ignoredResponses.size, 0);
  client.dispose();
});

test('cancelled response IDs stay within the bounded ignore cache', async () => {
  const credentials = { value: { url: 'ws://phone:9001', token: 'token' } };
  const client = createClient(credentials);
  const connection = client.ensureConnected();
  const socket = await nextSocket(0);
  socket.open();
  await connection;

  for (let index = 0; index < 130; index += 1) {
    const controller = new AbortController();
    const request = client.request({ type: 'inspectSnapshot' }, { timeoutMs: 5000, signal: controller.signal });
    await new Promise(resolve => setImmediate(resolve));
    controller.abort();
    await assert.rejects(request, error => error.name === 'AbortError');
  }

  assert.equal(client.ignoredResponses.size, 128);
  client.dispose();
});

test('an already aborted request does not connect or occupy a pending slot', async () => {
  const credentials = { value: { url: 'ws://phone:9001', token: 'token' } };
  const client = createClient(credentials);
  const controller = new AbortController();
  controller.abort();

  await assert.rejects(client.request({ type: 'nodes' }, { signal: controller.signal }), error => error.name === 'AbortError');
  assert.equal(FakeWebSocket.instances.length, 0);
  assert.equal(client.pending.size, 0);
  client.dispose();
});

test('connection timeout and pending limits reject unsafe numeric values', async () => {
  const credentials = { value: { url: 'ws://phone:9001', token: 'token' } };
  const client = createClient(credentials, { maxPending: Infinity });
  const connection = client.ensureConnected(Number.NaN);
  const socket = await nextSocket(0);
  assert.equal(socket.options.handshakeTimeout, 10000);
  assert.equal(client.maxPending, 8);
  socket.open();
  await connection;
  client.dispose();
});

test('a request is not queued onto a socket replaced after connection', async () => {
  const credentials = { value: { url: 'ws://phone:9001', token: 'token' } };
  const client = createClient(credentials);
  const oldSocket = new FakeWebSocket('ws://old:9001');
  oldSocket.open();
  const replacement = new FakeWebSocket('ws://new:9001');
  replacement.open();
  client.socket = replacement;
  client.ensureConnected = async () => oldSocket;

  await assert.rejects(client.request({ type: 'ping' }), /connection changed/i);
  assert.equal(client.pending.size, 0);
  assert.equal(oldSocket.sent.length, 0);
  client.dispose();
});

test('a synchronous WebSocket construction failure does not poison reconnects', async () => {
  const states = [];
  const credentials = { value: { url: 'ws://phone:9001', token: 'token' } };
  class ThrowingWebSocket {
    static OPEN = 1;
    constructor() { throw new Error('invalid URL'); }
  }
  const client = new DeviceClient({
    credentials: async () => credentials.value,
    WebSocket: ThrowingWebSocket,
    onState: (state, detail) => states.push({ state, detail })
  });

  await assert.rejects(client.ensureConnected(), /Cannot connect to ws:\/\/phone:9001: invalid URL/);
  await assert.rejects(client.ensureConnected(), /Cannot connect to ws:\/\/phone:9001: invalid URL/);
  assert.equal(client.connecting, undefined);
  assert.equal(states.filter(state => state.state === 'disconnected').length, 2);
  client.dispose();
});

test('device URLs reject embedded credentials before constructing a socket', async () => {
  const credentials = { value: { url: 'ws://user:password@phone:9001', token: 'token' } };
  const client = createClient(credentials);

  await assert.rejects(client.ensureConnected(), /Do not put credentials/);
  assert.equal(FakeWebSocket.instances.length, 0);
  client.dispose();
});

test('device URLs reject fragments before constructing a socket', async () => {
  const credentials = { value: { url: 'ws://phone:9001/#unexpected', token: 'token' } };
  const client = createClient(credentials);

  await assert.rejects(client.ensureConnected(), /must not contain a fragment/);
  assert.equal(FakeWebSocket.instances.length, 0);
  client.dispose();
});

test('request rejects signal-shaped objects that cannot remove listeners', async () => {
  const credentials = { value: { url: 'ws://phone:9001', token: 'token' } };
  const client = createClient(credentials);

  await assert.rejects(client.request({ type: 'nodes' }, { signal: { aborted: false } }), /must be an AbortSignal/);
  assert.equal(FakeWebSocket.instances.length, 0);
  client.dispose();
});

test('explicit disconnect terminates an open socket immediately', async () => {
  const credentials = { value: { url: 'ws://phone:9001', token: 'token' } };
  const client = createClient(credentials);
  const connection = client.ensureConnected();
  const socket = await nextSocket(0);
  socket.open();
  await connection;

  client.disconnect('switching network');
  assert.equal(socket.readyState, FakeWebSocket.CLOSED);
  assert.equal(client.socket, undefined);
  assert.equal(client.url, '');
  assert.equal(client.token, '');
});

test('a natural socket close clears credentials retained in memory', async () => {
  const credentials = { value: { url: 'ws://phone:9001', token: 'sensitive-token' } };
  const client = createClient(credentials);
  const connection = client.ensureConnected();
  const socket = await nextSocket(0);
  socket.open();
  await connection;

  socket.finishClose();
  assert.equal(client.url, '');
  assert.equal(client.token, '');
  client.dispose();
  client.dispose();
});

test('settings changed during credential loading cannot revive an old connection', async () => {
  let releaseCredentials;
  const waiting = new Promise(resolve => { releaseCredentials = resolve; });
  const client = new DeviceClient({
    credentials: async () => {
      await waiting;
      return { url: 'ws://old:9001', token: 'old-token' };
    },
    WebSocket: FakeWebSocket
  });
  FakeWebSocket.instances = [];

  const connection = client.ensureConnected();
  client.disconnect('settings changed');
  releaseCredentials();
  await assert.rejects(connection, /settings changed while credentials were loading/i);
  assert.equal(FakeWebSocket.instances.length, 0);
  client.dispose();
});

test('disposing during credential loading cannot create a socket afterward', async () => {
  let releaseCredentials;
  const waiting = new Promise(resolve => { releaseCredentials = resolve; });
  const client = new DeviceClient({
    credentials: async () => {
      await waiting;
      return { url: 'ws://phone:9001', token: 'token' };
    },
    WebSocket: FakeWebSocket
  });
  FakeWebSocket.instances = [];

  const connection = client.ensureConnected();
  client.dispose();
  releaseCredentials();
  await assert.rejects(connection, /device client has stopped/i);
  assert.equal(FakeWebSocket.instances.length, 0);
});
