const assert = require('node:assert/strict');
const test = require('node:test');
const { InspectorService, maxNodes, responseError } = require('../inspector-service');

const PNG = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]).toString('base64');

test('InspectorService validates and normalizes one correlated snapshot', async () => {
  const requests = [];
  const service = new InspectorService(async (payload, options) => {
    requests.push({ payload, options });
    return {
      ok: true,
      protocolVersion: 2,
      snapshotId: 'snapshot-1',
      capturedAtMs: 123,
      durationMs: 45,
      pngBase64: PNG,
      nodes: [{ nodeId: 'root' }],
      deviceInfo: { model: 'iPhone' },
      truncated: false
    };
  });
  const controller = new AbortController();
  const snapshot = await service.snapshot({ maxNodes: 9999, signal: controller.signal });

  assert.equal(requests[0].payload.type, 'inspectSnapshot');
  assert.equal(requests[0].payload.options.maxNodes, 2000);
  assert.equal(requests[0].options.signal, controller.signal);
  assert.equal(snapshot.snapshotId, 'snapshot-1');
  assert.deepEqual(snapshot.nodes, [{ nodeId: 'root' }]);
  assert.equal(snapshot.pngBase64, PNG);
});

test('InspectorService shares strict validation across screenshots and node captures', async () => {
  const invalidPng = new InspectorService(async () => ({ ok: true, pngBase64: 'not-an-image' }));
  await assert.rejects(invalidPng.screenshot(), /non-PNG screenshot data/);

  const invalidNodes = new InspectorService(async () => ({ ok: true, nodes: [null] }));
  await assert.rejects(invalidNodes.nodes(), /malformed node/);

  const deviceFailure = new InspectorService(async () => ({ ok: false, error: 'device busy' }));
  await assert.rejects(deviceFailure.nodes(), /device busy/);
});

test('Inspector protocol limits and errors remain bounded', () => {
  assert.equal(maxNodes('invalid'), 1000);
  assert.equal(maxNodes(0), 1);
  assert.equal(maxNodes(Infinity), 1000);
  assert.equal(maxNodes(5000), 2000);
  assert.equal(responseError({ error: 'x'.repeat(3000) }).length, 2051);
});

test('InspectorService serializes all visual requests across command and panel consumers', async () => {
  let releaseScreenshot;
  const screenshotGate = new Promise(resolve => { releaseScreenshot = resolve; });
  const calls = [];
  const service = new InspectorService(async payload => {
    calls.push(payload.type);
    if (payload.type === 'screenshot') {
      await screenshotGate;
      return { ok: true, pngBase64: PNG };
    }
    return { ok: true, nodes: [] };
  });

  const screenshot = service.screenshot();
  const nodes = service.nodes();
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(calls, ['screenshot']);
  releaseScreenshot();
  await Promise.all([screenshot, nodes]);
  assert.deepEqual(calls, ['screenshot', 'nodes']);
});
