const assert = require('node:assert/strict');
const test = require('node:test');
const { generatedCode, inputText, nodeAction, ocrRegion, point, selectorObject } = require('../inspector-input');

test('inspector coordinates and OCR regions reject non-finite or unsafe values', () => {
  assert.deepEqual(point('12.5', 20), { x: 12.5, y: 20 });
  assert.throws(() => point(Infinity, 20), /finite number/);
  assert.throws(() => point(-1, 20), /between 0/);
  assert.deepEqual(ocrRegion({ x: 1, y: 2, width: 3, height: 4, mode: 'attacker' }), { x: 1, y: 2, width: 3, height: 4 });
  assert.throws(() => ocrRegion({ x: 1, y: 2, width: 0, height: 4 }), /greater than zero/);
});

test('inspector selectors, actions, and editable text are bounded', () => {
  assert.deepEqual(selectorObject({ id: 'login' }), { id: 'login' });
  assert.throws(() => selectorObject([]), /JSON object/);
  assert.throws(() => selectorObject({ id: 'x'.repeat(17 * 1024) }), /16 KB/);
  assert.equal(nodeAction('click'), 'click');
  assert.throws(() => nodeAction('launch'), /click, input, or scroll/);
  assert.equal(generatedCode('auto.clickPoint(1, 2);'), 'auto.clickPoint(1, 2);');
  assert.throws(() => generatedCode('x'.repeat(65 * 1024)), /64 KB/);
  assert.throws(() => inputText('x'.repeat(65 * 1024)), /64 KB/);
});
