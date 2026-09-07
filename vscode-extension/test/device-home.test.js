const assert = require('node:assert/strict');
const test = require('node:test');
const { DeviceHome, connectionHelp } = require('../device-home');

const phone = { name: '我的 iPhone', address: '192.168.1.2', port: 9001, url: 'ws://192.168.1.2:9001', deviceId: 'phone-1' };
function harness(overrides = {}) {
  const states = [], calls = [], errors = [];
  const home = new DeviceHome({ context: () => ({ configured: false }), publish: state => states.push(state),
    discover: async () => [phone], perform: async (...args) => { calls.push(args); return true; },
    log: error => errors.push(error), ...overrides });
  return { home, states, calls, errors };
}
function deferred() { let resolve, reject; const promise = new Promise((a, b) => { resolve = a; reject = b; }); return { promise, resolve, reject }; }

test('scan renders safe cards and connects only a host-owned device', async () => {
  const { home, calls } = harness(); await home.scan();
  const card = home.snapshot().devices[0];
  assert.equal(card.name, phone.name);
  assert.equal('url' in card, false);
  await home.receive({ action: 'connect', key: card.key, url: 'ws://attacker:9001' });
  assert.equal(calls[0][1], phone);
  assert.match(home.snapshot().message, /已连接/);
});

test('unknown commands, forged keys and stale scan cards are rejected', async () => {
  const { home, calls } = harness(); await home.scan(); const key = home.snapshot().devices[0].key;
  await home.scan();
  for (const message of [null, 'connect', { action: 'executeCommand' }, { action: 'connect', key }, { action: 'connect', key: '999:0' }]) await home.receive(message);
  assert.equal(calls.length, 0);
});

test('cancelled discovery cannot reinsert late devices', async () => {
  const result = deferred(); const { home } = harness({ discover: () => result.promise });
  const pending = home.scan(); await home.receive({ action: 'cancelScan' });
  result.resolve([phone]); await pending;
  assert.equal(home.snapshot().scanning, false); assert.equal(home.snapshot().devices.length, 0);
});

test('workspace changes invalidate a previous scan and its keys', async () => {
  const result = deferred(); const { home } = harness({ discover: () => result.promise });
  const pending = home.scan(); home.reset(); result.resolve([phone]); await pending;
  assert.equal(home.snapshot().devices.length, 0); assert.match(home.snapshot().message, /工作区/);
});

test('duplicate connection clicks are ignored but stop and logs remain usable', async () => {
  const gate = deferred(); const calls = [];
  const { home } = harness({ perform: async action => { calls.push(action); if (action === 'connect') await gate.promise; return true; } });
  await home.scan(); const request = { action: 'connect', key: home.snapshot().devices[0].key };
  const pending = home.receive(request); await home.receive(request);
  await home.receive({ action: 'stop' }); await home.receive({ action: 'logs' });
  assert.deepEqual(calls, ['connect', 'stop', 'logs']); gate.resolve(); await pending;
  assert.equal(home.snapshot().busy, false);
});

test('running scripts prevent device switching, repeated runs and new scans', async () => {
  const { home, calls } = harness(); await home.scan(); home.setRunning(true);
  await home.scan();
  for (const action of ['connect', 'disconnect', 'run', 'runSelection', 'inspector', 'manual']) await home.receive({ action, key: home.snapshot().devices[0].key });
  await home.receive({ action: 'stop' }); assert.deepEqual(calls.map(call => call[0]), ['stop']);
});

test('failure gives actionable Chinese recovery without exposing token text', async () => {
  const { home, errors } = harness({ perform: async () => { throw new Error('auth token SECRET rejected'); } });
  await home.receive({ action: 'reconnect' });
  assert.match(home.snapshot().message, /重新配对/); assert.doesNotMatch(home.snapshot().message, /SECRET/);
  assert.equal(errors.length, 1); assert.equal(home.snapshot().busy, false);
  assert.match(connectionHelp(new Error('ETIMEDOUT')), /同一 Wi-Fi/);
});

test('a workspace reset during pairing does not publish the old success', async () => {
  const gate = deferred(); const { home } = harness({ perform: () => gate.promise });
  const pending = home.receive({ action: 'reconnect' }); home.reset(); gate.resolve(true); await pending;
  assert.match(home.snapshot().message, /工作区/); assert.equal(home.snapshot().busy, false);
});

test('empty scan and dropped connection have useful next steps', async () => {
  const { home } = harness({ discover: async () => [] }); await home.scan();
  assert.match(home.snapshot().message, /本地网络/);
  home.setConnection('ready'); home.setConnection('disconnected'); assert.match(home.snapshot().message, /重试/);
});

test('dispose aborts discovery and stops all later publications', async () => {
  const gate = deferred(); let signal;
  const { home, states } = harness({ discover: options => { signal = options.signal; return gate.promise; } });
  const pending = home.scan(); home.dispose(); const count = states.length;
  gate.resolve([phone]); await pending; await home.receive({ action: 'scan' });
  assert.equal(signal.aborted, true); assert.equal(states.length, count);
});
