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
  const source = fs.readFileSync(path.join(__dirname, '..', 'inspector-session.js'), 'utf8');
  assert.match(source, /Only coordinate clicks can omit a selector/);
});

test('the extension delegates visual capture and Inspector state to focused modules', () => {
  const source = fs.readFileSync(path.join(__dirname, '..', 'extension.js'), 'utf8');
  assert.match(source, /new InspectorService\(sendRequest\)/);
  assert.match(source, /new InspectorSession\(/);
  assert.doesNotMatch(source, /type: 'inspectSnapshot'/);
});

test('the extension delegates completion parsing instead of hard-coding namespaces', () => {
  const source = fs.readFileSync(path.join(__dirname, '..', 'extension.js'), 'utf8');
  assert.match(source, /completionEntries\(API_COMPLETIONS, prefix/);
  assert.doesNotMatch(source, /namespaceMatch\s*=\s*prefix\.match/);
});

test('the Inspector exposes cancellation and a configurable post-action refresh delay', () => {
  const extension = fs.readFileSync(path.join(__dirname, '..', 'extension.js'), 'utf8');
  const view = fs.readFileSync(path.join(__dirname, '..', 'inspector-view.js'), 'utf8');
  const webview = fs.readFileSync(path.join(__dirname, '..', 'media', 'inspector.js'), 'utf8');
  const manifest = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'package.json'), 'utf8'));
  assert.match(extension, /actionRefreshDelay: configuration\(\)\.get\('inspectorActionRefreshDelay'\)/);
  assert.match(view, /id="cancel-operation"/);
  assert.match(webview, /send\('cancel', 'cancelOperations'\)/);
  assert.equal(manifest.contributes.configuration.properties['autosdk.inspectorActionRefreshDelay'].default, 400);
});

test('selector results keep the correlated snapshot tree as the uniqueness baseline', () => {
  const webview = fs.readFileSync(path.join(__dirname, '..', 'media', 'inspector.js'), 'utf8');
  assert.match(webview, /snapshotNodes:\s*\[\]/);
  assert.match(webview, /belongsToSnapshot \? state\.snapshotNodes : state\.nodes/);
  assert.doesNotMatch(webview, /state\.snapshotNodes\s*=\s*nodes;/);
});

test('every contributed extension command is registered', () => {
  const source = fs.readFileSync(path.join(__dirname, '..', 'extension.js'), 'utf8');
  const commands = [
    'autosdk.runCurrentScript', 'autosdk.sendCurrentScript', 'autosdk.manageScripts',
    'autosdk.configureDevice', 'autosdk.discoverDevice', 'autosdk.discoverUsbDevice', 'autosdk.startUsbTunnel', 'autosdk.stopUsbTunnel',
    'autosdk.testConnection', 'autosdk.stopScript', 'autosdk.captureScreenshot',
    'autosdk.inspectNodes', 'autosdk.openInspector', 'autosdk.buildIPA'
  ];
  for (const command of commands) {
    assert.match(source, new RegExp("registerCommand\\('" + command + "'"), command + ' must be registered');
  }
});

test('JavaScript and TypeScript editors expose one-click run actions', () => {
  const manifest = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'package.json'), 'utf8'));
  const contextRun = manifest.contributes.menus['editor/context'].find(item => item.command === 'autosdk.runCurrentScript');
  const titleRun = manifest.contributes.menus['editor/title'].find(item => item.command === 'autosdk.runCurrentScript');

  assert.match(contextRun.when, /editorLangId == javascript/);
  assert.match(contextRun.when, /editorLangId == typescript/);
  assert.equal(titleRun.when, contextRun.when);
});

test('an unconfigured one-click run can launch normal Wi-Fi discovery', () => {
  const source = fs.readFileSync(path.join(__dirname, '..', 'extension.js'), 'utf8');
  assert.match(source, /showErrorMessage\(`AutoSDK: \$\{error\.message\}`, \.\.\.runErrorActions\(error\)\)/);
  assert.match(source, /action === SCAN_WIFI_DEVICE\) await vscode\.commands\.executeCommand\('autosdk\.discoverDevice'\)/);
});

test('Wi-Fi connection tests share token and retry recovery for manual and discovered devices', () => {
  const source = fs.readFileSync(path.join(__dirname, '..', 'extension.js'), 'utf8');
  assert.equal((source.match(/testWifiConnectionWithRecovery\(\{/g) || []).length, 3);
  assert.match(source, /REENTER_TOKEN,\s*RETRY_CONNECTION/);
  assert.match(source, /testConnection\(\{ showFailure: false \}\)/);
  assert.match(source, /cancellable: true/);
  assert.doesNotMatch(source, /Choose how Windows connects/);
});

test('the Inspector labels pixel sampling as Color instead of a click point', () => {
  const viewSource = fs.readFileSync(path.join(__dirname, '..', 'inspector-view.js'), 'utf8');
  const webviewSource = fs.readFileSync(path.join(__dirname, '..', 'media', 'inspector.js'), 'utf8');
  assert.match(viewSource, /data-mode="point"[^>]*>Color<\/button>/);
  assert.doesNotMatch(viewSource, /data-mode="point"[^>]*>Point<\/button>/);
  assert.match(webviewSource, /state\.selectedIndex = -1;[\s\S]{0,240}setGenerated\(''\);[\s\S]{0,240}send\('pixel', 'pixelColor'/);
  assert.match(webviewSource, /message\.type === 'pixelColor'[\s\S]{0,180}setGenerated\(model\.codeForColor\(color\)\)/);
});

test('the disconnected status bar opens Wi-Fi discovery', () => {
  const source = fs.readFileSync(path.join(__dirname, '..', 'extension.js'), 'utf8');
  assert.match(source, /state === 'disconnected' \? 'autosdk\.discoverDevice' : 'autosdk\.testConnection'/);
  assert.match(source, /discoverWifiDevices\(\{ signal: controller\.signal \}\)/);
  assert.match(source, /discoverUsbDevices\(/);
});

test('the normal add flow is Wi-Fi first and keeps USB as an advanced command', () => {
  const manifest = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'package.json'), 'utf8'));
  const wifi = manifest.contributes.commands.find(item => item.command === 'autosdk.discoverDevice');
  const usb = manifest.contributes.commands.find(item => item.command === 'autosdk.discoverUsbDevice');
  assert.match(wifi.title, /Scan Wi-Fi/);
  assert.match(usb.title, /USB.*Advanced/);
  assert.equal(manifest.contributes.configuration.properties['autosdk.debugUrl'].default, '');
});
