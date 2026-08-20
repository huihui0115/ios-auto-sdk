const assert = require('node:assert/strict');
const test = require('node:test');
const { InspectorSession, LatestTaskQueue, actionRefreshDelay } = require('../inspector-session');

function deferred() {
  let resolve;
  const promise = new Promise(done => { resolve = done; });
  return { promise, resolve };
}

function snapshot(id) {
  return {
    protocolVersion: 2,
    snapshotId: id,
    capturedAtMs: 1,
    durationMs: 2,
    pngBase64: 'iVBORw0KGgo=',
    nodes: [{ nodeId: 'root' }],
    deviceInfo: { model: 'iPhone' },
    truncated: false
  };
}

test('LatestTaskQueue serializes different visual operations', async () => {
  const gate = deferred();
  const calls = [];
  const queue = new LatestTaskQueue();
  const first = queue.schedule('snapshot', async () => { calls.push('snapshot'); await gate.promise; });
  const second = queue.schedule('selector', async () => { calls.push('selector'); });
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(calls, ['snapshot']);
  gate.resolve();
  await Promise.all([first, second]);
  assert.deepEqual(calls, ['snapshot', 'selector']);
});

test('LatestTaskQueue drops superseded work that has not started', async () => {
  const gate = deferred();
  const calls = [];
  const queue = new LatestTaskQueue();
  const blocker = queue.schedule('blocker', () => gate.promise);
  const stale = queue.schedule('pixel', async () => { calls.push('stale'); });
  const latest = queue.schedule('pixel', async () => { calls.push('latest'); });
  gate.resolve();
  assert.equal(await stale, false);
  assert.equal(await latest, true);
  await blocker;
  assert.deepEqual(calls, ['latest']);
});

test('InspectorSession serializes snapshot and selector collection through one device lane', async () => {
  const gate = deferred();
  const calls = [];
  const messages = [];
  const service = {
    async snapshot() { calls.push('snapshot'); await gate.promise; return snapshot('s1'); },
    async nodes() { calls.push('nodes'); return [{ nodeId: 'button' }]; }
  };
  const session = new InspectorSession({ service, postMessage: message => messages.push(message) });
  const capture = session.handleMessage({ type: 'refresh', requestId: 'refresh-1' });
  const selector = session.handleMessage({ type: 'testSelector', requestId: 'selector-1', selector: { id: 'button' } });
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(calls, ['snapshot']);
  gate.resolve();
  await Promise.all([capture, selector]);
  assert.deepEqual(calls, ['snapshot', 'nodes']);
  assert.ok(messages.some(message => message.type === 'snapshot' && message.requestId === 'refresh-1'));
  assert.ok(messages.some(message => message.type === 'selectorResult' && message.requestId === 'selector-1'));
  session.dispose();
});

test('InspectorSession suppresses an obsolete refresh result and keeps the newest snapshot', async () => {
  const firstGate = deferred();
  const messages = [];
  let calls = 0;
  const service = {
    async snapshot() {
      calls += 1;
      if (calls === 1) await firstGate.promise;
      return snapshot(`s${calls}`);
    }
  };
  const session = new InspectorSession({ service, postMessage: message => messages.push(message) });
  const first = session.refresh('refresh-1');
  await new Promise(resolve => setImmediate(resolve));
  const second = session.refresh('refresh-2');
  firstGate.resolve();
  await Promise.all([first, second]);

  const snapshots = messages.filter(message => message.type === 'snapshot');
  assert.equal(calls, 2);
  assert.deepEqual(snapshots.map(message => message.requestId), ['refresh-2']);
  assert.equal(session.lastSnapshot.snapshotId, 's2');
  session.dispose();
});

test('InspectorSession never commits a snapshot that finishes after disposal', async () => {
  const gate = deferred();
  const messages = [];
  const service = { async snapshot() { await gate.promise; return snapshot('stale'); } };
  const session = new InspectorSession({ service, postMessage: message => messages.push(message) });
  const pending = session.refresh('refresh-stale');
  await new Promise(resolve => setImmediate(resolve));
  session.dispose();
  gate.resolve();
  await pending;

  assert.equal(session.lastSnapshot, undefined);
  assert.equal(messages.some(message => message.type === 'snapshot'), false);
});

test('InspectorSession cancels active and queued work and immediately accepts a fresh request', async () => {
  const gate = deferred();
  const signals = [];
  const messages = [];
  let calls = 0;
  const service = {
    async snapshot(options) {
      calls += 1;
      signals.push(options.signal);
      if (calls === 1) await gate.promise;
      return snapshot(calls === 1 ? 'stale' : 'fresh');
    }
  };
  const session = new InspectorSession({ service, postMessage: message => messages.push(message) });
  const stale = session.refresh('refresh-stale');
  await new Promise(resolve => setImmediate(resolve));
  await session.handleMessage({ type: 'cancelOperations', requestId: 'cancel-1' });
  assert.equal(signals[0].aborted, true);
  const fresh = session.refresh('refresh-fresh');
  gate.resolve();
  await Promise.all([stale, fresh]);

  assert.equal(calls, 2);
  assert.equal(signals[1].aborted, false);
  assert.equal(session.lastSnapshot.snapshotId, 'fresh');
  assert.deepEqual(messages.filter(message => message.type === 'snapshot').map(message => message.requestId), ['refresh-fresh']);
  assert.ok(messages.some(message => message.type === 'cancelled' && message.requestId === 'cancel-1'));
  session.dispose();
});

test('InspectorSession uses the bounded action refresh delay and exports a clean snapshot', async () => {
  const delays = [];
  const service = {
    async nodeAction() {},
    async snapshot() { return snapshot('after-action'); }
  };
  const session = new InspectorSession({
    service,
    postMessage() {},
    actionRefreshDelay: 725.9,
    async delay(milliseconds, signal) { delays.push({ milliseconds, signal }); }
  });
  await session.handleMessage({
    type: 'nodeAction', requestId: 'action-1', action: 'click', selector: { id: 'login' }
  });

  assert.equal(session.actionRefreshDelay, 725);
  assert.equal(delays[0].milliseconds, 725);
  assert.equal(delays[0].signal.aborted, false);
  assert.equal(session.lastSnapshot.snapshotId, 'after-action');
  assert.equal(Object.hasOwn(session.lastSnapshot, 'notice'), false);
  session.dispose();
});

test('Inspector action refresh delay rejects unsafe numeric settings', () => {
  assert.equal(actionRefreshDelay('invalid'), 400);
  assert.equal(actionRefreshDelay(-1), 0);
  assert.equal(actionRefreshDelay(99999), 5000);
  assert.equal(actionRefreshDelay(Infinity), 400);
});
