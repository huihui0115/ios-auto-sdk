const assert = require('node:assert/strict');
const test = require('node:test');
const { InspectorSession, LatestTaskQueue } = require('../inspector-session');

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
