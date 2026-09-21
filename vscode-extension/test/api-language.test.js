const assert = require('node:assert/strict');
const test = require('node:test');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');
const ts = require('typescript');
const { catalog, snippet, completions, callHelp, hoverEntry } = require('../api-language');
const { apiItems, insertAPI, languageProviders } = require('../api-tools');

test('namespace and partial names stay focused, including aliases and nested modules', () => {
  for (const prefix of ['device.', 'device.get', 'device?.get', 'action.device.get', 'string.to']) {
    const names = completions(prefix).map(item => item.name);
    assert.ok(names.length, prefix);
    assert.ok(names.every(name => name.startsWith(prefix.replace('?.', '.'))), prefix);
  }
  for (const prefix of ['unknown.get', 'fn().', 'items[0].']) assert.deepEqual(completions(prefix), [], prefix);
  assert.equal(completions('device.getBr')[0].insertText, 'getBrightness()');
  assert.equal(completions('device.getBr')[0].replaceLength, 5);
});

test('comments, strings and template text do not offer executable completions', () => {
  for (const source of ['// device.', '/* device.', '"device.', "'device.", '`device.', '/* multiline\n device.', 'logd("device.")']) {
    const offset = source.indexOf('device.') + 7;
    assert.deepEqual(completions(source, offset), [], source);
  }
  assert.ok(completions('// ignored\ndevice.get').length);
  assert.equal(completions('x'.repeat(1024 * 1024 + 1)).length, 0);
});

test('all generated snippets parse without optional markers, type annotations or ellipsis', () => {
  for (const entry of catalog) {
    const plain = snippet(entry).replace(/\$\{\d+\|([^}]+)\|\}/g, (_, choices) => choices.split(',')[0])
      .replace(/\$\{\d+:((?:\\.|[^}])*)\}/g, (_, value) => value.replace(/\\([\\}$])/g, '$1'));
    assert.doesNotThrow(() => new vm.Script(plain), `${entry.name}: ${plain}`);
  }
  assert.equal(snippet(catalog.find(entry => entry.name === 'system.openSettings')), 'system.openSettings()');
  assert.match(snippet(catalog.find(entry => entry.name === 'device.setAssistiveTouchEnabled')), /true,false/);
});

test('signature help counts nested expressions, callback types and overloads', () => {
  for (const text of ['http.post("url", { a: [1,2] }, ', 'http.post("url", fn(1, 2), ']) {
    const help = callHelp(text, text.length);
    assert.equal(help.parameter, 2);
    assert.equal(help.entries[0].name, 'http.post');
  }
  const text = 'device.setAssistiveTouchEnabled(';
  assert.equal(callHelp(text, text.length).entries[0].parameters[0].type, 'boolean');
  assert.equal(callHelp('device.getBrightness()', 22), undefined);
  assert.match(hoverEntry('device.setAssistiveTouchEnabled(false)', 10).documentation, /签名权限/);
});

test('every declared global/module callable is represented, including uncommon functions', () => {
  const file = path.resolve(__dirname, '../../types/autosdk.d.ts');
  const program = ts.createProgram([file], { noLib: true });
  const checker = program.getTypeChecker(), source = program.getSourceFile(file);
  const names = new Set(catalog.map(entry => entry.name));
  function check(name, type, depth = 0) {
    if (type.getCallSignatures().length) assert.ok(names.has(name), name);
    if (depth === 2) return;
    for (const property of type.getProperties()) {
      const node = property.valueDeclaration || property.declarations?.[0];
      if (node?.getSourceFile() === source) check(`${name}.${property.name}`, checker.getTypeOfSymbolAtLocation(property, node), depth + 1);
    }
  }
  for (const node of source.statements) {
    if (ts.isFunctionDeclaration(node)) check(node.name.text, checker.getTypeAtLocation(node.name));
    if (ts.isVariableStatement(node)) for (const declaration of node.declarationList.declarations) check(declaration.name.text, checker.getTypeAtLocation(declaration.name));
  }
  assert.ok(names.has('device.setAssistiveTouchEnabled'));
  assert.ok(names.has('sqlite.query'));
  assert.ok(names.has('ocr.newOcr'));
});

test('generated catalog calls resolve to real bootstrap functions, not just declarations', () => {
  const source = fs.readFileSync(path.resolve(__dirname, '../../tools/bootstrap-source.js'), 'utf8');
  const context = { __bridge: {}, __console: { log() {}, warn() {}, error() {} } };
  vm.runInNewContext(source, context);
  for (const entry of catalog) {
    assert.equal(typeof entry.name.split('.').reduce((value, key) => value?.[key], context), 'function', entry.name);
  }
});

test('function picker has distinct on/off actions and never runs a script', async () => {
  const items = apiItems(), inserted = [];
  assert.equal(items.find(item => item.label.startsWith('关闭系统小白点')).insertion, 'device.setAssistiveTouchEnabled(false)');
  assert.equal(items.find(item => item.label.startsWith('打开系统小白点')).insertion, 'device.setAssistiveTouchEnabled(true)');
  const editor = { document: { version: 1 }, selection: { isEqual: () => true }, insertSnippet: async value => inserted.push(value.value) };
  const vscode = { SnippetString: class { constructor(value) { this.value = value; } }, window: {
    showQuickPick: async values => values[1], showWarningMessage: () => assert.fail('unexpected warning')
  } };
  await insertAPI(() => editor, vscode);
  assert.deepEqual(inserted, ['device.setAssistiveTouchEnabled(false)']);
  vscode.window.showQuickPick = async values => { editor.document.version++; return values[0]; };
  let warned = false; vscode.window.showWarningMessage = () => { warned = true; };
  await insertAPI(() => editor, vscode);
  assert.equal(warned, true); assert.equal(inserted.length, 1);
});

test('language providers register completion, hover and signature help', () => {
  const providers = {};
  const vscode = { languages: Object.fromEntries(['CompletionItem', 'Hover', 'SignatureHelp'].map(kind =>
    [`register${kind}Provider`, (languages, provider) => { providers[kind] = provider; return { dispose() {} }; }])) };
  assert.equal(languageProviders(vscode).length, 3);
  assert.ok(providers.SignatureHelp.provideSignatureHelp);
});
