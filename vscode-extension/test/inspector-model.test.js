const assert = require('node:assert/strict');
const test = require('node:test');
const model = require('../media/inspector-model');

test('Inspector model chooses the smallest node under a screen point', () => {
  const nodes = [
    { nodeId: 'window', bounds: { x: 0, y: 0, width: 300, height: 600 } },
    { nodeId: 'button', bounds: { x: 20, y: 40, width: 100, height: 50 } }
  ];
  assert.equal(model.indexAtPoint(nodes, { x: 30, y: 50 }), 1);
  assert.equal(model.indexAtPoint(nodes, { x: 500, y: 500 }), -1);
});

test('Inspector model prefers the deepest later node when bounds overlap exactly', () => {
  const nodes = [
    { nodeId: 'parent', depth: 2, bounds: { x: 10, y: 10, width: 80, height: 40 } },
    { nodeId: 'child-a', depth: 3, bounds: { x: 10, y: 10, width: 80, height: 40 } },
    { nodeId: 'child-b', depth: 3, bounds: { x: 10, y: 10, width: 80, height: 40 } },
    { nodeId: 'empty', depth: 4, bounds: { x: 20, y: 20, width: 0, height: 0 } }
  ];
  assert.equal(model.indexAtPoint(nodes, { x: 20, y: 20 }), 2);
});

test('Inspector model preserves stable node selection across snapshots', () => {
  const previous = { nodeId: 'button' };
  const nodes = [{ nodeId: 'root' }, { nodeId: 'button' }];
  assert.equal(model.nodeKey(previous), 'nodeId:button');
  assert.equal(model.selectionIndex(nodes, model.nodeKey(previous)), 1);
});

test('Inspector model prefers a unique readable selector and maps screen geometry', () => {
  const nodes = [
    { id: 'login', type: 'Button', label: 'Login' },
    { label: 'Login', type: 'Text' }
  ];
  assert.deepEqual(model.selectorForNode(nodes[0], nodes), { id: 'login', type: 'Button' });
  assert.deepEqual(
    model.pointFromClient(60, 120, { left: 10, top: 20, width: 100, height: 200 }, { width: 200, height: 400 }),
    { x: 100, y: 200 }
  );
  assert.deepEqual(model.regionBetween({ x: 50, y: 80 }, { x: 10, y: 20 }), { x: 10, y: 20, width: 40, height: 60 });
});

test('Inspector model clamps right and bottom edges to valid pixel indices', () => {
  assert.deepEqual(
    model.pointFromClient(110, 220, { left: 10, top: 20, width: 100, height: 200 }, { width: 200, height: 400 }),
    { x: 199, y: 399 }
  );
  assert.deepEqual(
    model.pointFromClient(-10, -20, { left: 10, top: 20, width: 100, height: 200 }, { width: 200, height: 400 }),
    { x: 0, y: 0 }
  );
});
