const assert = require('node:assert/strict');
const test = require('node:test');
const {
  REENTER_TOKEN,
  RETRY_CONNECTION,
  SCAN_WIFI_DEVICE,
  connectWithRecovery,
  connectionTargetIsCurrent,
  runErrorActions
} = require('../connection-recovery');

test('discovery URLs still match after settings add the canonical trailing slash', () => {
  const expected = { scope: 'workspace', url: 'ws://192.168.1.2:9001', deviceId: 'phone' };
  assert.equal(connectionTargetIsCurrent({ ...expected, url: expected.url + '/' }, expected), true);
  assert.equal(connectionTargetIsCurrent({ ...expected, scope: 'other' }, expected), false);
  assert.equal(connectionTargetIsCurrent({ ...expected, deviceId: 'other' }, expected), false);
  assert.equal(connectionTargetIsCurrent({ ...expected, url: 'ws://192.168.1.3:9001' }, expected), false);
  assert.equal(connectionTargetIsCurrent({ ...expected, url: '' }, { ...expected, url: '' }), false);
});

test('a freshly discovered phone is tested rather than silently skipped', async () => {
  const expected = { scope: 'workspace', url: 'ws://192.168.1.2:9001', deviceId: 'phone' };
  const actual = { ...expected, url: expected.url + '/' }; let tests = 0;
  assert.equal(await connectWithRecovery({
    isCurrent: () => connectionTargetIsCurrent(actual, expected),
    testConnection: async () => { tests++; return true; },
    chooseAction: async () => undefined, replaceToken: async () => false
  }), true);
  assert.equal(tests, 1);
});

test('recovery stops when the selected phone changes during a dialog', async () => {
  let current = true; let replacements = 0;
  const connected = await connectWithRecovery({
    isCurrent: () => current,
    testConnection: async () => false,
    chooseAction: async () => { current = false; return REENTER_TOKEN; },
    replaceToken: async () => { replacements++; return true; }
  });
  assert.equal(connected, false);
  assert.equal(replacements, 0);
});

test('recovery does not report success for a connection whose scope changed', async () => {
  let current = true;
  assert.equal(await connectWithRecovery({
    isCurrent: () => current,
    testConnection: async () => { current = false; return true; },
    chooseAction: async () => { throw new Error('unexpected dialog'); },
    replaceToken: async () => false
  }), false);
});

test('an unconfigured run offers the normal Wi-Fi add action', () => {
  assert.deepEqual(
    runErrorActions(new Error('Run AutoSDK: Scan Wi-Fi and Add iPhone first.')),
    [SCAN_WIFI_DEVICE]
  );
  assert.deepEqual(
    runErrorActions(new Error('Configure an AutoSDK device URL first.')),
    [SCAN_WIFI_DEVICE]
  );
  assert.deepEqual(runErrorActions(new Error('The device rejected this script.')), []);
});

test('connection recovery retries without asking the user to scan again', async () => {
  let tests = 0;
  let tokenPrompts = 0;
  const actions = [RETRY_CONNECTION, REENTER_TOKEN];
  const connected = await connectWithRecovery({
    async testConnection() { tests += 1; return tests === 3; },
    async chooseAction() { return actions.shift(); },
    async replaceToken() { tokenPrompts += 1; return true; }
  });

  assert.equal(connected, true);
  assert.equal(tests, 3);
  assert.equal(tokenPrompts, 1);
});

test('connection recovery stops cleanly when token entry is cancelled', async () => {
  let tests = 0;
  const connected = await connectWithRecovery({
    async testConnection() { tests += 1; return false; },
    async chooseAction() { return REENTER_TOKEN; },
    async replaceToken() { return false; }
  });

  assert.equal(connected, false);
  assert.equal(tests, 1);
});
