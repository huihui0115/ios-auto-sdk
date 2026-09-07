const assert = require('node:assert/strict');
const test = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const phone = { deviceId: 'autosdk:1234abcd', name: '我的手机', url: 'ws://192.168.1.2:9001' };
function harness({ folder = false } = {}) {
  const values = new Map(), saved = new Map(), updates = [], sent = [], notices = [], handlers = {}, commands = new Map();
  const disposable = { dispose() {} };
  const channel = { show() {}, appendLine(value) { notices.push(value); }, append() {}, dispose() {} };
  const current = { get: key => values.get(key), inspect: key => ({ [folder ? 'workspaceValue' : 'globalValue']: values.get(key) }),
    update: async (key, value, target) => { if (!folder && target === 2) throw new Error('No workspace open'); values.set(key, value); updates.push({ key, value, target }); } };
  const selection = { isEmpty: false, start: { line: 1 } };
  const editor = { document: { languageId: 'javascript', fileName: 'Untitled-1', isClosed: false,
    uri: { toString: () => 'untitled:1' }, getText: range => range ? 'logd("selection");' : 'logd("whole");' }, selection, selections: [selection] };
  const vscode = {
    ConfigurationTarget: { Global: 1, Workspace: 2, WorkspaceFolder: 3 }, StatusBarAlignment: { Left: 1 }, ThemeColor: class {},
    Uri: { joinPath: (...parts) => parts.join('/') },
    window: { activeTextEditor: editor, createOutputChannel: () => channel, createStatusBarItem: () => ({ show() {}, dispose() {} }),
      showInputBox: async options => { notices.push(options); return 'long-test-pairing-token'; },
      showInformationMessage: async message => notices.push(message), showWarningMessage: async message => notices.push(message), showErrorMessage: async message => notices.push(message),
      onDidChangeActiveTextEditor: handler => { handlers.editor = handler; return disposable; },
      onDidChangeTextEditorSelection: () => disposable,
      registerWebviewViewProvider: () => disposable },
    workspace: { isTrusted: true, workspaceFolders: folder ? [{ uri: { toString: () => 'file:///test' } }] : undefined,
      getConfiguration: () => current, onDidChangeConfiguration: () => disposable,
      onDidCloseTextDocument: () => disposable, onDidGrantWorkspaceTrust: () => disposable,
      onDidChangeWorkspaceFolders: handler => { handlers.folders = handler; return disposable; } },
    commands: { registerCommand: (name, callback) => { commands.set(name, callback); return disposable; }, executeCommand: async () => {} },
    languages: { registerCompletionItemProvider: () => disposable }
  };
  const context = { subscriptions: [], extensionUri: '/extension',
    workspaceState: { get: key => saved.get(key), update: async (key, value) => saved.set(key, value) },
    secrets: { get: async key => saved.get(key), store: async (key, value) => saved.set(key, value), delete: async key => saved.delete(key) } };
  class Client {
    constructor(options) { this.options = options; }
    async request(payload) { const credentials = await this.options.credentials(); if (!credentials.token) throw new Error('auth token missing'); sent.push(payload); this.options.onState('ready'); return { ok: true, deviceInfo: {}, capabilities: {} }; }
    disconnect() { this.options.onState('disconnected'); }
    dispose() {}
  }
  const module = { exports: {} };
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../extension.js'), 'utf8') +
    '\nmodule.exports.testing = { pairWifiDevice, performHomeAction, homeContext, sidebarEditor };', {
    module, Buffer, URL, AbortController, console,
    require: name => name === 'vscode' ? vscode : name === './device-client' ? { DeviceClient: Client } :
      name === './usb-tunnel' ? { UsbTunnel: class { dispose() {} } } :
      ['./inspector-view', './device-home-view'].includes(name) ? {} :
      require(name.startsWith('./') ? path.join(__dirname, '..', name) : name)
  });
  module.exports.activate(context);
  return { api: module.exports.testing, vscode, values, updates, sent, notices, handlers, commands, editor, current };
}

test('actual extension pairs from an empty window without workspace settings errors', async () => {
  const h = harness(); assert.equal(await h.api.pairWifiDevice(phone), true);
  assert.equal(h.values.get('debugUrl'), 'ws://192.168.1.2:9001/');
  assert.ok(h.updates.filter(update => update.key !== 'debugToken').every(update => update.target === 1));
  assert.deepEqual(h.sent.map(item => item.type), ['ping', 'deviceInfo', 'capabilities']);
  assert.doesNotMatch(JSON.stringify(h.api.homeContext()), /long-test-pairing-token/);
});

test('same discovered phone at a new IP reuses pairing; another phone prompts again', async () => {
  const h = harness({ folder: true }); await h.api.pairWifiDevice(phone);
  await h.api.pairWifiDevice({ ...phone, url: 'ws://192.168.1.3:9001' });
  assert.equal(h.notices.filter(item => item?.password === true).length, 1);
  await h.api.pairWifiDevice({ ...phone, deviceId: 'different' });
  assert.equal(h.notices.filter(item => item?.password === true).length, 2);
  assert.ok(h.updates.filter(update => update.key !== 'debugToken').every(update => update.target === 2));
});

test('sidebar runs the displayed script and selection after editor focus moves away', async () => {
  const h = harness(); await h.api.pairWifiDevice(phone);
  h.vscode.window.activeTextEditor = undefined; h.handlers.editor(undefined);
  await h.api.performHomeAction('run'); await h.api.performHomeAction('runSelection');
  assert.deepEqual(h.sent.filter(item => item.type === 'run').map(item => item.script), ['logd("whole");', 'logd("selection");']);
});

test('closed editors and untrusted workspaces never send run requests', async () => {
  const h = harness(); await h.api.pairWifiDevice(phone);
  h.vscode.workspace.isTrusted = false; await h.api.performHomeAction('run');
  h.vscode.workspace.isTrusted = true; h.editor.document.isClosed = true;
  h.vscode.window.activeTextEditor = undefined; await assert.rejects(h.api.performHomeAction('run'), /新建示例脚本/);
  assert.equal(h.sent.some(item => item.type === 'run'), false); assert.equal(h.api.homeContext().canRun, false);
});

test('a workspace or target change during token entry cannot overwrite the new target', async () => {
  const h = harness(); h.vscode.window.showInputBox = async () => { h.values.set('debugUrl', 'ws://other:9001'); return 'long-test-pairing-token'; };
  await assert.rejects(h.api.pairWifiDevice(phone), /已改变/);
  assert.equal(h.values.get('debugUrl'), 'ws://other:9001'); assert.equal(h.updates.length, 0);
});

test('new home and example commands are registered by actual activation', () => {
  const h = harness(); assert.ok(h.commands.has('autosdk.openDeviceHome')); assert.ok(h.commands.has('autosdk.newScript'));
});
