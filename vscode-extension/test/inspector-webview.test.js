const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const test = require('node:test');
const model = require('../media/inspector-model');

// Execute the shipped Webview controller, not a copy of its state machine.
function webview() {
  class Element {
    constructor() {
      this.listeners = new Map(); this.children = []; this.value = ''; this.textContent = '';
      this.style = { setProperty() {} }; this.classList = { toggle() {} };
      this.dataset = {}; this.disabled = false; this.naturalWidth = 100; this.naturalHeight = 100;
    }
    addEventListener(type, callback) { this.listeners.set(type, callback); }
    emit(type, event = {}) { this.listeners.get(type)?.(event); }
    append(...items) { this.children.push(...items); }
    appendChild(item) { this.append(item); }
    replaceChildren() { this.children = []; }
    setAttribute() {}
    setPointerCapture() {}
    getBoundingClientRect() { return { left: 0, top: 0, width: 100, height: 100 }; }
  }
  const elements = new Map();
  const get = id => { if (!elements.has(id)) elements.set(id, new Element()); return elements.get(id); };
  const modes = ['node', 'point', 'region'].map(mode => { const item = new Element(); item.dataset.mode = mode; return item; });
  const window = new Element();
  const sent = [];
  const context = vm.createContext({
    document: { getElementById: get, createElement: () => new Element(), querySelectorAll: () => modes },
    window, AutoSDKInspectorModel: model, acquireVsCodeApi: () => ({ postMessage: message => sent.push(message) })
  });
  vm.runInContext(fs.readFileSync(path.join(__dirname, '../media/inspector.js'), 'utf8'), context);
  const reply = (request, type, payload = {}) => window.emit('message', { data: { ...request, type, ...payload } });
  const snapshot = (nodes = []) => reply(sent.findLast(item => item.operation === 'snapshot'), 'snapshot', {
    nodes, pngBase64: 'test', deviceInfo: { screenWidth: 100, screenHeight: 100 }
  });
  return { get, sent, reply, snapshot, mode: mode => modes.find(item => item.dataset.mode === mode).emit('click'),
    point: () => get('device-screen').emit('pointerdown', { clientX: 10, clientY: 10, pointerId: 1 }) };
}

const node = { nodeId: 'a', label: 'Continue', type: 'Button', bounds: { x: 0, y: 0, width: 40, height: 40 } };
const color = { x: 10, y: 10, hex: '#FF0000' };

test('late pixel results cannot overwrite a newly selected node', () => {
  const ui = webview(); ui.snapshot([node]); ui.mode('point'); ui.point();
  const pixel = ui.sent.at(-1);
  ui.mode('node'); ui.point();
  const selectedCode = ui.get('generated-code').value;
  assert.match(selectedCode, /Continue/);
  ui.reply(pixel, 'pixelColor', { color });
  assert.equal(ui.get('generated-code').value, selectedCode);
});

test('an older operationStart cannot resurrect an obsolete pixel request', () => {
  const ui = webview(); ui.snapshot(); ui.mode('point'); ui.point();
  const first = ui.sent.at(-1); ui.point(); const second = ui.sent.at(-1);
  ui.reply(first, 'operationStart'); ui.reply(first, 'pixelColor', { color });
  assert.equal(ui.get('generated-code').value, '');
  ui.reply(second, 'pixelColor', { color });
  assert.match(ui.get('generated-code').value, /compareColors/);
});

test('manual code editing is not overwritten by pending OCR/image/color work', () => {
  const ui = webview(); ui.snapshot(); ui.mode('point'); ui.point();
  const pixel = ui.sent.at(-1);
  ui.get('generated-code').value = 'log("edited");'; ui.get('generated-code').emit('input');
  ui.reply(pixel, 'pixelColor', { color });
  assert.equal(ui.get('generated-code').value, 'log("edited");');
});

test('empty refresh clears stale code and disables copy/insert', () => {
  const ui = webview(); ui.snapshot([node]); ui.point();
  assert.equal(ui.get('copy-code').disabled, false);
  ui.get('refresh').emit('click'); ui.snapshot([]);
  assert.equal(ui.get('generated-code').value, '');
  assert.equal(ui.get('selector').value, '');
  assert.equal(ui.get('copy-code').disabled, true);
  assert.equal(ui.get('insert-code').disabled, true);
});

test('selector test generates code for the result, not the previously selected node', () => {
  const ui = webview(); ui.snapshot([node]); ui.point();
  ui.get('selector').value = '{"label":"Back"}'; ui.get('selector').emit('input');
  ui.get('test-selector').emit('click');
  ui.reply(ui.sent.at(-1), 'selectorResult', { nodes: [{ ...node, nodeId: 'b', label: 'Back' }] });
  assert.match(ui.get('generated-code').value, /Back/);
  assert.doesNotMatch(ui.get('generated-code').value, /Continue/);
});

test('cancellation invalidates even a late snapshot and clears busy state', () => {
  const ui = webview(); ui.snapshot([node]);
  ui.get('refresh').emit('click'); const request = ui.sent.at(-1);
  ui.reply(request, 'operationStart'); ui.get('cancel-operation').emit('click');
  ui.reply(ui.sent.at(-1), 'cancelled');
  ui.reply(request, 'snapshot', { nodes: [], pngBase64: 'stale' });
  ui.reply(request, 'operationEnd');
  assert.equal(ui.get('screenshot').src, 'data:image/png;base64,test');
  assert.equal(ui.get('refresh').disabled, false);
});

test('switching away from a region disables OCR for the old region', () => {
  const ui = webview(); ui.snapshot(); ui.mode('region'); ui.point();
  ui.get('device-screen').emit('pointerup', { clientX: 50, clientY: 50 });
  assert.equal(ui.get('test-ocr').disabled, false);
  ui.mode('point');
  assert.equal(ui.get('test-ocr').disabled, true);
  assert.equal(ui.get('generated-code').value, '');
});
