const assert = require('node:assert/strict');
const { EventEmitter } = require('node:events');
const test = require('node:test');
const { UsbTunnel, portNumber } = require('../usb-tunnel');

class FakeChild extends EventEmitter {
  constructor() {
    super();
    this.stdout = new EventEmitter();
    this.stderr = new EventEmitter();
    this.exitCode = null;
    this.killed = false;
  }

  kill() {
    this.killed = true;
    this.exitCode = 0;
    queueMicrotask(() => this.emit('close', 0, null));
    return true;
  }
}

class StubbornChild extends FakeChild {
  kill() {
    this.killed = true;
    return true;
  }
}

function fakeSpawner() {
  const calls = [];
  const children = [];
  const spawn = (command, args, options) => {
    const child = new FakeChild();
    calls.push({ command, args, options });
    children.push(child);
    queueMicrotask(() => child.emit('spawn'));
    return child;
  };
  return { spawn, calls, children };
}

test('USB tunnel validates TCP ports', () => {
  assert.equal(portNumber('9001', 'port'), 9001);
  assert.throws(() => portNumber(0, 'port'), /between 1 and 65535/);
  assert.throws(() => portNumber('1.5', 'port'), /between 1 and 65535/);
});

test('USB tunnel rejects UDID values that could be interpreted as options', async () => {
  const fake = fakeSpawner();
  const tunnel = new UsbTunnel({ spawn: fake.spawn, startupGraceMs: 1 });

  await assert.rejects(tunnel.start({ localPort: 9001, devicePort: 9001, udid: '--help' }), /UDID must start/);
  assert.equal(fake.calls.length, 0);
  tunnel.dispose();
});

test('USB tunnel starts iproxy without a shell and reuses the same process', async () => {
  const fake = fakeSpawner();
  const tunnel = new UsbTunnel({ spawn: fake.spawn, startupGraceMs: 1 });
  const first = await tunnel.start({ executable: 'C:\\Tools\\iproxy.exe', localPort: 9001, devicePort: 9001, udid: 'phone-id' });
  const second = await tunnel.start({ executable: 'C:\\Tools\\iproxy.exe', localPort: 9001, devicePort: 9001, udid: 'phone-id' });

  assert.equal(first.alreadyRunning, false);
  assert.equal(second.alreadyRunning, true);
  assert.equal(fake.calls.length, 1);
  assert.deepEqual(fake.calls[0].args, ['-u', 'phone-id', '9001', '9001']);
  assert.equal(fake.calls[0].options.shell, false);
  await tunnel.stop();
  assert.equal(fake.children[0].killed, true);
});

test('USB tunnel supports old iproxy builds with trailing UDIDs', async () => {
  const fake = fakeSpawner();
  const tunnel = new UsbTunnel({ spawn: fake.spawn, startupGraceMs: 1 });
  await tunnel.start({ localPort: 9001, devicePort: 9001, udid: 'phone-id', udidStyle: 'legacy' });

  assert.deepEqual(fake.calls[0].args, ['9001', '9001', 'phone-id']);
  await tunnel.stop();
});

test('USB tunnel reports an early iproxy exit and clears its state', async () => {
  const fake = fakeSpawner();
  const tunnel = new UsbTunnel({ spawn: fake.spawn, startupGraceMs: 20 });
  const started = tunnel.start({ localPort: 9001, devicePort: 9001 });
  await new Promise(resolve => setImmediate(resolve));
  fake.children[0].exitCode = 2;
  fake.children[0].emit('close', 2, null);

  await assert.rejects(started, /exited while starting/);
  assert.equal(tunnel.running, false);
});

test('USB tunnel replaces only the process it owns when settings change', async () => {
  const fake = fakeSpawner();
  const tunnel = new UsbTunnel({ spawn: fake.spawn, startupGraceMs: 1 });
  await tunnel.start({ localPort: 9001, devicePort: 9001 });
  await tunnel.start({ localPort: 9002, devicePort: 9001 });

  assert.equal(fake.children[0].killed, true);
  assert.equal(fake.children[1].killed, false);
  assert.equal(fake.calls.length, 2);
  tunnel.dispose();
  assert.equal(fake.children[1].killed, true);
});

test('concurrent starts wait for startup validation before reusing a process', async () => {
  const fake = fakeSpawner();
  const tunnel = new UsbTunnel({ spawn: fake.spawn, startupGraceMs: 10 });
  const first = tunnel.start({ localPort: 9001, devicePort: 9001 });
  const second = tunnel.start({ localPort: 9001, devicePort: 9001 });

  assert.equal((await first).alreadyRunning, false);
  assert.equal((await second).alreadyRunning, true);
  assert.equal(fake.calls.length, 1);
  await tunnel.stop();
});

test('a stop timeout retains ownership and prevents a replacement process', async () => {
  const calls = [];
  const children = [];
  const spawn = (command, args, options) => {
    const child = new StubbornChild();
    calls.push({ command, args, options });
    children.push(child);
    queueMicrotask(() => child.emit('spawn'));
    return child;
  };
  const tunnel = new UsbTunnel({ spawn, startupGraceMs: 1 });
  await tunnel.start({ localPort: 9001, devicePort: 9001 });

  await assert.rejects(tunnel.stop(1), /Timed out waiting for iproxy to stop/);
  assert.equal(tunnel.child, children[0]);
  assert.equal(children[0].listenerCount('close'), 1);
  await assert.rejects(tunnel.start({ localPort: 9002, devicePort: 9001 }), /Timed out waiting for iproxy to stop/);
  assert.equal(calls.length, 1);
  children[0].exitCode = 0;
  children[0].emit('close', 0, null);
  tunnel.dispose();
});

test('a runtime child-process error does not lose ownership of a live tunnel', async () => {
  const fake = fakeSpawner();
  const output = [];
  const tunnel = new UsbTunnel({ spawn: fake.spawn, startupGraceMs: 1, onOutput: value => output.push(value) });
  await tunnel.start({ localPort: 9001, devicePort: 9001 });

  fake.children[0].emit('error', new Error('temporary process error'));
  assert.equal(tunnel.child, fake.children[0]);
  assert.equal(tunnel.running, true);
  assert.match(output.join(''), /temporary process error/);
  await tunnel.stop();
});

test('a delayed close from an exited tunnel cannot invalidate its replacement', async () => {
  const fake = fakeSpawner();
  const exits = [];
  const tunnel = new UsbTunnel({ spawn: fake.spawn, startupGraceMs: 1, onExit: event => exits.push(event) });
  await tunnel.start({ localPort: 9001, devicePort: 9001 });
  fake.children[0].exitCode = 1;

  await tunnel.start({ localPort: 9002, devicePort: 9001 });
  fake.children[0].emit('close', 1, null);

  assert.equal(tunnel.child, fake.children[1]);
  assert.equal(exits[0].expected, true);
  await tunnel.stop();
});
