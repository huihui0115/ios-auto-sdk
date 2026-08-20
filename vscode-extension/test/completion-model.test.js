const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const { callableSignatures, completionEntries, namespaceBeforeCursor, snippetForSignature } = require('../completion-model');

const entries = [
  ['strings.toHex(text) / fromHex(hex)', 'Hex helpers.'],
  ['sqlite.open(path) / query(handle, sql, params)', 'SQLite helpers.'],
  ['globalCall(value)', 'Global helper.']
];

test('completion model expands grouped signatures and inherits their namespace', () => {
  assert.deepEqual(callableSignatures(entries[0][0]), ['strings.toHex(text)', 'strings.fromHex(hex)']);
  assert.deepEqual(callableSignatures('keepNode(node) / unkeepNode(node)'), ['keepNode(node)', 'unkeepNode(node)']);
});

test('completion model recognizes any namespace without a hard-coded allowlist', () => {
  assert.equal(namespaceBeforeCursor('const rows = sqlite.'), 'sqlite');
  assert.deepEqual(
    completionEntries(entries, 'const rows = sqlite.').map(item => item.signature),
    ['sqlite.open(path)', 'sqlite.query(handle, sql, params)']
  );
  assert.deepEqual(completionEntries(entries, 'unknown.'), []);
});

test('completion model emits valid snippets for grouped and optional arguments', () => {
  assert.equal(snippetForSignature('sqlite.query(handle, sql, params?)', 'sqlite'), 'query(${1:handle}, ${2:sql}, ${3:params?})');
  assert.equal(snippetForSignature('floatLog.clear()', 'floatLog'), 'clear()');
});

test('completion model maps compatible namespace aliases without duplicating source data', () => {
  const candidates = completionEntries(entries, 'string.', { string: 'strings' });
  assert.deepEqual(candidates.map(item => item.signature), ['string.toHex(text)', 'string.fromHex(hex)']);
  assert.equal(candidates[1].insertText, 'fromHex(${1:hex})');
});

test('completion model deduplicates expanded callable signatures', () => {
  const duplicates = [['ws.close(handle) / close(handle)', 'Close.']];
  assert.deepEqual(completionEntries(duplicates, 'ws.').map(item => item.signature), ['ws.close(handle)']);
});

test('production completion data covers every supported module namespace', () => {
  const source = fs.readFileSync(path.join(__dirname, '..', 'extension.js'), 'utf8');
  const start = source.indexOf('const API_COMPLETIONS = [');
  const end = source.indexOf('\n];', start);
  assert.ok(start >= 0 && end > start, 'completion table must remain readable');
  const productionEntries = Function(source.slice(start, end + 3)
    .replace('const API_COMPLETIONS =', 'return'))();
  const aliases = { action: 'auto', string: 'strings' };
  const namespaces = [
    'auto', 'action', 'file', 'storages', 'device', 'http', 'image', 'app', 'media',
    'strings', 'string', 'screen', 'webView', 'screenDraw', 'floatBall', 'floatLog',
    'plist', 'node', 'metrics', 'base64', 'thread', 'utils', 'ocr', 'ws', 'sqlite',
    'yolo', 'location', 'colors', 'speech', 'pasteboard', 'json'
  ];
  for (const namespace of namespaces) {
    assert.ok(completionEntries(productionEntries, `${namespace}.`, aliases).length > 0,
      `${namespace}. must have focused completions`);
  }
  const all = completionEntries(productionEntries, '');
  assert.ok(all.length > productionEntries.length, 'grouped rows must expand into individual calls');
  assert.ok(all.every(item => !item.signature.includes(' / ')), 'no completion may contain a grouped signature');
});
