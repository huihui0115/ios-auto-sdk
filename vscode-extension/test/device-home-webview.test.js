const assert = require('node:assert/strict');
const test = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function webview() {
  class Element {
    constructor() { this.dataset = {}; this.children = []; this.listeners = {}; }
    addEventListener(type, callback) { this.listeners[type] = callback; }
    emit(type, event) { this.listeners[type]?.(event); }
    append(...children) { this.children.push(...children); }
    replaceChildren() { this.children = []; }
    set innerHTML(_) { throw new Error('Untrusted content must not become HTML'); }
  }
  const elements = new Map(), sent = [], window = new Element();
  const get = id => { if (!elements.has(id)) elements.set(id, new Element()); return elements.get(id); };
  const ids = [...fs.readFileSync(path.join(__dirname, '../device-home-view.js'), 'utf8').matchAll(/data-action="([^"]+)"/g)].map(match => match[1]);
  const buttons = ids.map(id => { const button = get(id); button.dataset.action = id; return button; });
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../media/device-home.js'), 'utf8'), {
    document: { getElementById: get, createElement: () => new Element(), querySelectorAll: () => buttons },
    window, acquireVsCodeApi: () => ({ postMessage: message => sent.push(message) })
  });
  const update = patch => window.emit('message', { data: { type: 'state', state: {
    configured: true, trusted: true, connection: 'ready', canRun: true, canSelect: true,
    busy: false, running: false, scanning: false, devices: [], ...patch
  } } });
  return { get, sent, update };
}

test('real sidebar script requests state and wires Chinese action buttons', () => {
  const ui = webview(); assert.equal(ui.sent[0].action, 'ready'); ui.update({});
  for (const action of ['scan', 'run', 'runSelection', 'inspector', 'newScript', 'logs', 'help']) {
    ui.get(action).emit('click'); assert.equal(ui.sent.at(-1).action, action);
  }
});

test('unconfigured or untrusted sidebar cannot run; stop stays usable when busy', () => {
  const ui = webview(); ui.update({ connection: 'disconnected', configured: false });
  assert.equal(ui.get('run').disabled, true); assert.equal(ui.get('reconnect').hidden, true);
  ui.update({ trusted: false }); assert.equal(ui.get('run').disabled, true); assert.equal(ui.get('trust').hidden, false);
  ui.update({ busy: true, running: true });
  assert.equal(ui.get('stop').disabled, false); assert.equal(ui.get('inspector').disabled, true);
  assert.equal(ui.get('pair').disabled, true);
});

test('phone names are text only and clicks send opaque keys without addresses', () => {
  const ui = webview(); const name = '<img src=x onerror=steal()> 日本語 手机';
  ui.update({ devices: [{ name, address: '192.168.1.2:9001', key: '7:0' }] });
  const card = ui.get('devices').children[0]; assert.equal(card.children[0].textContent, name);
  card.children[2].emit('click'); const message = ui.sent.at(-1);
  assert.equal(message.action, 'connect'); assert.equal(message.key, '7:0'); assert.equal(message.url, undefined);
});

test('new state clears old results and disables selection-only run for empty selection', () => {
  const ui = webview(); ui.update({ devices: [{ name: 'iPhone', address: 'host', key: '1:0' }] });
  ui.update({ canSelect: false, scanning: true });
  assert.equal(ui.get('devices').children.length, 0); assert.equal(ui.get('runSelection').disabled, true);
  assert.equal(ui.get('cancelScan').hidden, false); assert.equal(ui.get('scan').disabled, true);
});
