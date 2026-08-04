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

test('every contributed extension command is registered', () => {
  const source = fs.readFileSync(path.join(__dirname, '..', 'extension.js'), 'utf8');
  const commands = [
    'autosdk.runCurrentScript', 'autosdk.sendCurrentScript', 'autosdk.manageScripts',
    'autosdk.configureDevice', 'autosdk.startUsbTunnel', 'autosdk.stopUsbTunnel',
    'autosdk.testConnection', 'autosdk.stopScript', 'autosdk.captureScreenshot',
    'autosdk.inspectNodes', 'autosdk.openInspector', 'autosdk.buildTrollStoreIPA'
  ];
  for (const command of commands) {
    assert.match(source, new RegExp("registerCommand\\('" + command + "'"), command + ' must be registered');
  }
});
