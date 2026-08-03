const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

test('the plain node inspection command uses the JSON document handler', () => {
  const source = fs.readFileSync(path.join(__dirname, '..', 'extension.js'), 'utf8');
  assert.match(source, /registerCommand\('autosdk\.inspectNodes', inspectNodes\)/);
  assert.match(source, /registerCommand\('autosdk\.openInspector', openInspector\)/);
});

test('the inspector rejects non-click coordinate actions before sending them', () => {
  const source = fs.readFileSync(path.join(__dirname, '..', 'extension.js'), 'utf8');
  assert.match(source, /Only coordinate clicks can omit a selector/);
});
