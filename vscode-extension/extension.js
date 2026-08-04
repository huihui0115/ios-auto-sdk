const vscode = require('vscode');
const path = require('path');
const { spawn } = require('child_process');
const fs = require('fs');
const { CoalescingRunner } = require('./coalescing-runner');
const { DeviceClient } = require('./device-client');
const { connectionCredentials, tokenForConfiguration, updateConnectionConfiguration } = require('./connection-settings');
const { generatedCode, inputText, nodeAction, ocrRegion, point, selectorObject } = require('./inspector-input');
const { inspectorHtml } = require('./inspector-view');
const { terminateOwnedProcess } = require('./process-lifecycle');
const { deployedAssetName, deployedScriptName, transpileScript } = require('./script-tools');
const { UsbTunnel } = require('./usb-tunnel');

let extensionContext;
let channel;
let deviceClient;
let usbTunnel;
let connectionStatus;
let inspectorPanel;
let inspectorAbortController;
let inspectorRefreshRunner;
let lastScriptEditor;
const activeBuildProcesses = new Set();

const API_COMPLETIONS = [
  ['auto.click(selector)', 'Activate the first matching node.'],
  ['auto.clickPoint(x, y)', 'Activate the host-app control at screen coordinates.'],
  ['auto.doubleClickPoint(x, y, intervalSeconds)', 'Activate a coordinate twice.'],
  ['auto.longClick(selector, durationSeconds)', 'Long press through an adapter that supports real touch injection.'],
  ['auto.swipe(x1, y1, x2, y2, durationSeconds)', 'Swipe or scroll between screen coordinates.'],
  ['auto.input(selector, text)', 'Replace text in a matching input.'],
  ['auto.setText(selector, text)', 'EasyClick-compatible alias for input.'],
  ['auto.getText(selector)', 'Read text from the first matching node.'],
  ['auto.sleep(milliseconds)', 'Pause cooperatively and remain cancellable.'],
  ['auto.findElement(selector)', 'Return one stable node descriptor or null.'],
  ['auto.findElements(selector)', 'Return all matching node descriptors.'],
  ['auto.exists(selector)', 'Test whether a node exists.'],
  ['auto.waitFor(selector, timeoutMs)', 'Wait for a node or fail with a timeout.'],
  ['auto.getAttribute(selector, name)', 'Read a node attribute.'],
  ['auto.getBounds(selector)', 'Read point-coordinate node bounds.'],
  ['auto.getChildren(selector)', 'Return direct child descriptors.'],
  ['auto.getParent(selector)', 'Return the parent descriptor.'],
  ['auto.getSiblings(node)', 'Return sibling descriptors.'],
  ['auto.getPreviousSiblings(node)', 'Return siblings before the node.'],
  ['auto.getNextSiblings(node)', 'Return siblings after the node.'],
  ['auto.getChild(node, index)', 'Return one direct child.'],
  ['auto.scrollIntoView(selector)', 'Scroll a matching node into view.'],
  ['auto.clickCenter(node)', 'Activate the center of a node.'],
  ['auto.clickRandom(node)', 'Activate a random inset point in a node.'],
  ['auto.screenshot()', 'Return a PNG screenshot as base64.'],
  ['auto.saveImageToAlbum(path)', 'Save a sandbox image file to the iOS photo library.'],
  ['auto.saveImageBase64ToAlbum(base64)', 'Save a base64 image to the iOS photo library.'],
  ['auto.saveVideoToAlbum(path)', 'Save a sandbox video file to the iOS photo library.'],
  ['auto.saveScreenshotToAlbum()', 'Capture and save the current screen to the iOS photo library.'],
  ['auto.findImage(templatePath, options)', 'Find an image template.'],
  ['auto.findColor(color, region, options)', 'Find one color.'],
  ['auto.findMultiColor(color, offsets, region, options)', 'Find a base color plus relative color offsets.'],
  ['auto.getPixelColor(x, y)', 'Read one screenshot pixel.'],
  ['auto.compareColors(points, options)', 'Compare several screenshot points in one capture.'],
  ['auto.cmpColor(points, options)', 'EasyClick-compatible alias for compareColors.'],
  ['auto.ocr(region)', 'Run on-device Vision OCR.'],
  ['auto.http(url, options)', 'Perform a controlled synchronous HTTP request.'],
  ['auto.httpGet(url, options)', 'Perform a GET request.'],
  ['auto.httpPost(url, body, options)', 'Perform a POST request.'],
  ['auto.storage(name)', 'Open a persistent named JSON store.'],
  ['auto.launchApp(bundleId)', 'Launch an application through a capable adapter.'],
  ['auto.activateApp(bundleId)', 'Bring an application to the foreground.'],
  ['auto.terminateApp(bundleId)', 'Terminate an application through a capable adapter.'],
  ['auto.appState(bundleId)', 'Read the WDA application state code.'],
  ['auto.capabilities()', 'Inspect the current adapter and runtime capabilities.'],
  ['auto.time()', 'Return the current Unix time in milliseconds.'],
  ['auto.randomInt(min, max)', 'Return a random integer in an inclusive range.'],
  ['setTimeout(callback, milliseconds)', 'Run a callback before script completion after a delay.'],
  ['setInterval(callback, milliseconds)', 'Repeat a callback until cancelled, stopped, or timed out.'],
  ['clearTimeout(timerId)', 'Cancel a timeout.'],
  ['clearInterval(timerId)', 'Cancel an interval.'],
  ['cancelTimeout(timerId)', 'EasyClick-compatible alias for clearTimeout.'],
  ['cancelInterval(timerId)', 'EasyClick-compatible alias for clearInterval.'],
  ['file.sandboxDir()', 'Return the configured AutoSDK sandbox directory.'],
  ['file.resolvePath(path)', 'Resolve a relative sandbox path.'],
  ['file.exists(path)', 'Test whether a sandbox path exists.'],
  ['file.readFile(path)', 'Read a UTF-8 file below the AutoSDK sandbox root.'],
  ['file.readBase64(path)', 'Read a sandbox file as base64.'],
  ['file.readLines(path)', 'Read a bounded UTF-8 file as lines.'],
  ['file.readLine(path, index)', 'Read one line from a bounded UTF-8 file.'],
  ['file.writeFile(path, text)', 'Atomically write a UTF-8 file.'],
  ['file.writeBase64(path, base64)', 'Decode base64 into a sandbox file.'],
  ['file.create(path)', 'Create or truncate an empty sandbox file.'],
  ['file.appendText(path, text)', 'Append UTF-8 text to a sandbox file.'],
  ['file.appendLine(path, text)', 'Append a line to a UTF-8 file.'],
  ['file.deleteLine(path, index)', 'Remove one line from a UTF-8 file.'],
  ['file.list(path)', 'Return bounded metadata for a sandbox directory.'],
  ['file.listDir(path)', 'List a sandbox directory.'],
  ['file.mkdir(path)', 'Create a sandbox directory recursively.'],
  ['file.mkdirs(path)', 'Create a sandbox directory recursively.'],
  ['file.remove(path)', 'Remove a sandbox file or bounded directory tree.'],
  ['file.deleteAllFile(path)', 'Remove a file or directory below the sandbox root.'],
  ['file.copy(source, destination, overwrite)', 'Copy a sandbox file or directory.'],
  ['storages.create(name)', 'Open an EasyClick-style persistent store.'],
  ['device.getDeviceInfo()', 'Return device, app, screen, battery and adapter information.'],
  ['device.getScreenWidth()', 'Return screen width in points.'],
  ['device.getScreenHeight()', 'Return screen height in points.'],
  ['device.getScale()', 'Return screen pixel scale.'],
  ['device.getModel()', 'Return the public iOS model name.'],
  ['device.getOSVersion()', 'Return the iOS version.'],
  ['device.getDeviceName()', 'Return the public iOS device name.'],
  ['device.getBattery()', 'Return battery percentage when available.'],
  ['device.isCharging()', 'Return whether the device is charging.'],
  ['device.getOrientation()', 'Return the current interface orientation.'],
  ['http.request(url, options)', 'Perform a controlled HTTP request.'],
  ['http.get(url, options)', 'Perform a GET request.'],
  ['http.post(url, body, options)', 'Perform a POST request.'],
  ['http.postJSON(url, body, options)', 'EasyClick-compatible JSON POST alias.'],
  ['http.downloadFile(url, path, options)', 'Download a response into the AutoSDK sandbox.'],
  ['image.findImage(templatePath, options)', 'Find an image template.'],
  ['image.findColor(color, region, options)', 'Find a color in a screenshot region.'],
  ['image.findMultiColor(color, offsets, region, options)', 'Find a multi-point color pattern.'],
  ['image.pixel(x, y)', 'Read one screenshot pixel.'],
  ['image.screenshot()', 'Return a PNG screenshot as base64.'],
  ['image.saveToAlbum(path)', 'Save a sandbox image file to the iOS photo library.'],
  ['image.saveBase64ToAlbum(base64)', 'Save a base64 image to the iOS photo library.'],
  ['image.saveScreenshotToAlbum()', 'Capture and save the current screen to the iOS photo library.'],
  ['image.cmpColor(points, options)', 'Compare several colors in one screenshot.'],
  ['media.saveImage(path)', 'Save a sandbox image file to the iOS photo library.'],
  ['media.saveImageBase64(base64)', 'Save a base64 image to the iOS photo library.'],
  ['media.saveVideo(path)', 'Save a sandbox video file to the iOS photo library.'],
  ['media.saveScreenshot()', 'Capture and save the current screen to the iOS photo library.'],
  ['app.launch(bundleId)', 'Launch an application through a capable adapter.'],
  ['app.activate(bundleId)', 'Bring an application to the foreground.'],
  ['app.terminate(bundleId)', 'Terminate an application through a capable adapter.'],
  ['app.state(bundleId)', 'Read the WDA application state code.'],
  ['clickPoint(x, y)', 'Global coordinate activation alias.'],
  ['doubleClickPoint(x, y, intervalSeconds)', 'Global coordinate double activation alias.'],
  ['swipeToPoint(x1, y1, x2, y2, durationSeconds)', 'Global swipe alias.'],
  ['sleep(milliseconds)', 'Global cooperative sleep alias.'],
  ['random(min, max)', 'Return a random integer in an inclusive range.'],
  ['logd(...values)', 'Write a debug-level script log entry.'],
  ['logi(...values)', 'Write an info-level script log entry.'],
  ['logw(...values)', 'Write a warning-level script log entry.'],
  ['loge(...values)', 'Write an error-level script log entry.']
];

function outputChannel() {
  if (!channel) channel = vscode.window.createOutputChannel('AutoSDK');
  return channel;
}

function configuration() {
  return vscode.workspace.getConfiguration('autosdk');
}

function workspaceCredentialScope() {
  if (vscode.workspace.workspaceFile) return vscode.workspace.workspaceFile.toString();
  const folders = (vscode.workspace.workspaceFolders || [])
    .map(folder => folder.uri.toString())
    .sort();
  return folders.length ? folders.join('\n') : 'empty-window';
}

function currentScript() {
  const editor = vscode.window.activeTextEditor;
  if (!editor) throw new Error('Open a JavaScript or TypeScript script first.');
  if (editor.document.languageId !== 'javascript' && editor.document.languageId !== 'typescript') {
    throw new Error('The active editor is not a JavaScript or TypeScript file.');
  }
  const source = transpileScript(editor.document.getText(), editor.document.fileName, editor.document.languageId);
  return { name: path.basename(editor.document.fileName), source, identity: editor.document.uri.toString() };
}

async function sendRequest(payload, options = {}) {
  if (!deviceClient) throw new Error('AutoSDK device client is not active.');
  const timeoutSetting = Number(configuration().get('connectionTimeout'));
  const configured = Number.isFinite(timeoutSetting)
    ? Math.min(3600000, Math.max(1000, timeoutSetting))
    : 300000;
  const timeouts = { ping: 5000, deviceInfo: 10000, capabilities: 10000, stop: 10000,
    screenshot: 45000, nodes: 45000, inspectSnapshot: 60000, pixelColor: 45000, findImage: 90000, testOCR: 90000,
    nodeAction: 45000, putScript: 30000, listScripts: 15000, deleteScript: 15000, runStored: configured,
    putAsset: 30000, listAssets: 15000, deleteAsset: 15000 };
  return deviceClient.request(payload, {
    timeoutMs: timeouts[payload.type] || configured,
    signal: options.signal
  });
}

function runScript(script) {
  return sendRequest({ type: 'run', script: script.source });
}

async function runCurrentScript() {
  const channel = outputChannel();
  channel.show(true);
  try {
    if (!vscode.workspace.isTrusted) throw new Error('Trust this workspace before running its scripts on the iPhone.');
    const script = currentScript();
    channel.appendLine(`Running ${script.name}...`);
    const response = await runScript(script);
    if (!response.ok) throw new Error(responseError(response));
    channel.appendLine(JSON.stringify(response, null, 2));
    vscode.window.showInformationMessage(`AutoSDK finished ${script.name}.`);
  } catch (error) {
    channel.appendLine(error.stack || error.message);
    vscode.window.showErrorMessage(`AutoSDK: ${error.message}`);
  }
}

async function deployCurrentScript() {
  const channel = outputChannel();
  channel.show(true);
  try {
    if (!vscode.workspace.isTrusted) throw new Error('Trust this workspace before sending its scripts to the iPhone.');
    const script = currentScript();
    const name = deployedScriptName(script.name, script.identity);
    channel.appendLine(`Deploying ${name}...`);
    const response = await sendRequest({ type: 'putScript', name, script: script.source });
    if (!response.ok) throw new Error(responseError(response));
    channel.appendLine(JSON.stringify(response, null, 2));
    vscode.window.showInformationMessage(`AutoSDK saved ${name} on the iPhone.`);
  } catch (error) {
    channel.appendLine(error.stack || error.message);
    vscode.window.showErrorMessage(`AutoSDK: ${error.message}`);
  }
}

async function manageDeviceScripts() {
  try {
    const response = await sendRequest({ type: 'listScripts' });
    if (!response.ok || !Array.isArray(response.scripts)) throw new Error(responseError(response));
    if (!response.scripts.length) {
      vscode.window.showInformationMessage('No AutoSDK scripts are deployed on the iPhone.');
      return;
    }
    const selected = await vscode.window.showQuickPick(response.scripts.map(script => ({
      label: `$(file-code) ${script.name}`,
      description: `${Number(script.sizeBytes || 0).toLocaleString()} bytes`,
      script
    })), { placeHolder: 'Choose a deployed AutoSDK script' });
    if (!selected) return;
    const action = await vscode.window.showQuickPick([
      { label: '$(play) Run', action: 'run' },
      { label: '$(trash) Delete', action: 'delete' }
    ], { placeHolder: selected.script.name });
    if (!action) return;
    if (action.action === 'delete') {
      const confirmed = await vscode.window.showWarningMessage(
        `Delete ${selected.script.name} from the iPhone?`,
        { modal: true },
        'Delete'
      );
      if (confirmed !== 'Delete') return;
      const removed = await sendRequest({ type: 'deleteScript', name: selected.script.name });
      if (!removed.ok) throw new Error(responseError(removed));
      vscode.window.showInformationMessage(`AutoSDK deleted ${selected.script.name}.`);
      return;
    }
    outputChannel().show(true);
    outputChannel().appendLine(`Running deployed script ${selected.script.name}...`);
    const result = await sendRequest({ type: 'runStored', name: selected.script.name });
    if (!result.ok) throw new Error(responseError(result));
    outputChannel().appendLine(JSON.stringify(result, null, 2));
    vscode.window.showInformationMessage(`AutoSDK finished ${selected.script.name}.`);
  } catch (error) {
    outputChannel().appendLine(error.stack || error.message);
    vscode.window.showErrorMessage(`AutoSDK: ${error.message}`);
  }
}

async function configureDevice() {
  const current = configuration();
  const credentialScope = workspaceCredentialScope();
  const savedToken = await tokenForConfiguration(current, extensionContext.secrets, credentialScope);
  const connection = await vscode.window.showQuickPick([
    {
      label: '$(radio-tower) Wi-Fi direct',
      description: 'Use the ws:// address displayed by the AutoSDK app',
      mode: 'wifi'
    },
    {
      label: '$(plug) USB tunnel',
      description: 'Use iproxy or another usbmuxd forwarder on port 9001',
      mode: 'usb'
    }
  ], {
    placeHolder: 'Choose how Windows connects to the iPhone',
    matchOnDescription: true
  });
  if (!connection) return;
  const configuredUrl = String(current.get('debugUrl') || '');
  const defaultUrl = connection.mode === 'usb'
    ? 'ws://127.0.0.1:9001'
    : (/^wss?:\/\/(?!127\.0\.0\.1|localhost|\[::1\])/i.test(configuredUrl) ? configuredUrl : 'ws://192.168.1.2:9001');
  const url = await vscode.window.showInputBox({
    prompt: connection.mode === 'wifi'
      ? 'Enter the Wi-Fi debug URL displayed by the AutoSDK app'
      : 'AutoSDK USB tunnel URL',
    value: defaultUrl,
    validateInput(value) {
      try {
        const parsed = new URL(value);
        if (parsed.protocol !== 'ws:' && parsed.protocol !== 'wss:') return 'Use a ws:// or wss:// URL.';
        if (!parsed.hostname || !parsed.port) return 'Include the iPhone address and debug port.';
        if (parsed.username || parsed.password) return 'Do not put credentials in the URL; enter the debug token separately.';
        if (parsed.hash) return 'Do not include a #fragment in the device URL.';
        const loopback = ['127.0.0.1', 'localhost', '::1', '[::1]'].includes(parsed.hostname);
        if (connection.mode === 'wifi' && loopback) {
          return 'Wi-Fi mode requires the iPhone address displayed by the AutoSDK app.';
        }
        if (connection.mode === 'usb' && (parsed.protocol !== 'ws:' || !loopback)) {
          return 'USB mode requires a local ws://127.0.0.1:PORT tunnel URL.';
        }
        return undefined;
      } catch (_) {
        return 'Enter a valid WebSocket URL.';
      }
    }
  });
  if (!url) return;
  const token = await vscode.window.showInputBox({
    prompt: 'AutoSDK debug token',
    password: true,
    value: savedToken,
    validateInput(value) {
      if (!value) return 'Enter the installation token displayed by the AutoSDK app.';
      if (Buffer.byteLength(value, 'utf8') > 1024) return 'The debug token must not exceed 1024 UTF-8 bytes.';
      if (connection.mode === 'wifi' && value.length < 16) return 'Wi-Fi tokens must contain at least 16 characters.';
      return undefined;
    }
  });
  if (token === undefined) return;
  if (credentialScope !== workspaceCredentialScope()) {
    vscode.window.showErrorMessage('AutoSDK: The workspace changed while configuring the device. Run the command again.');
    return;
  }
  try {
    const result = await updateConnectionConfiguration(
      current,
      extensionContext.secrets,
      token,
      url,
      credentialScope,
      vscode.ConfigurationTarget.Workspace,
      [
        { target: vscode.ConfigurationTarget.Global, inspectKey: 'globalValue' },
        { target: vscode.ConfigurationTarget.WorkspaceFolder, inspectKey: 'workspaceFolderValue' }
      ]
    );
    if (result.plaintextCleanupErrors.length) {
      vscode.window.showWarningMessage('AutoSDK connected, but the old plaintext debug token could not be removed from one or more VS Code settings scopes. Remove autosdk.debugToken manually.');
    }
  } catch (error) {
    vscode.window.showErrorMessage(`AutoSDK could not save the device connection: ${error.message}`);
    return;
  }
  deviceClient?.disconnect('Device connection settings changed.');
  if (connection.mode === 'wifi' && usbTunnel?.running) await stopUsbTunnel();
  const action = await vscode.window.showInformationMessage(
    'AutoSDK device connection saved.',
    ...(connection.mode === 'usb' ? ['Start USB Tunnel'] : [])
  );
  if (action === 'Start USB Tunnel') await startUsbTunnel();
}

function usbTunnelOptions() {
  const current = configuration();
  let parsed;
  try {
    parsed = new URL(String(current.get('debugUrl') || ''));
  } catch (_) {
    throw new Error('Configure a valid AutoSDK USB URL first.');
  }
  if (parsed.protocol !== 'ws:' || !['127.0.0.1', 'localhost', '::1', '[::1]'].includes(parsed.hostname)) {
    throw new Error('USB tunneling requires autosdk.debugUrl to use ws://127.0.0.1:PORT.');
  }
  return {
    executable: String(current.get('iproxyPath') || 'iproxy'),
    localPort: Number(parsed.port),
    devicePort: Number(current.get('usbDevicePort')) || 9001,
    udid: String(current.get('usbDeviceUdid') || ''),
    udidStyle: String(current.get('iproxyUdidStyle') || 'modern')
  };
}

async function startUsbTunnel() {
  const channel = outputChannel();
  channel.show(true);
  try {
    if (!vscode.workspace.isTrusted) throw new Error('Trust this workspace before starting its configured USB tunnel executable.');
    const result = await usbTunnel.start(usbTunnelOptions());
    channel.appendLine(`${result.alreadyRunning ? 'Using' : 'Started'} USB tunnel: ${result.commandLine}`);
    vscode.window.showInformationMessage(result.alreadyRunning ? 'AutoSDK USB tunnel is already running.' : 'AutoSDK USB tunnel started.');
  } catch (error) {
    channel.appendLine(`USB tunnel failed: ${error.stack || error.message}`);
    vscode.window.showErrorMessage(`AutoSDK USB tunnel failed: ${error.message}`);
  }
}

async function stopUsbTunnel() {
  try {
    const stopped = await usbTunnel?.stop();
    if (stopped) {
      deviceClient?.disconnect('USB tunnel stopped.');
      vscode.window.showInformationMessage('AutoSDK USB tunnel stopped.');
    } else {
      vscode.window.showInformationMessage('AutoSDK has no managed USB tunnel running.');
    }
  } catch (error) {
    outputChannel().appendLine(`USB tunnel stop failed: ${error.stack || error.message}`);
    vscode.window.showErrorMessage(`AutoSDK could not stop the USB tunnel: ${error.message}`);
  }
}

function responseError(response) {
  return typeof response?.error === 'string' ? response.error : JSON.stringify(response?.error || response);
}

async function testConnection() {
  const channel = outputChannel();
  channel.show(true);
  try {
    const pong = await sendRequest({ type: 'ping' });
    if (!pong.ok) throw new Error(responseError(pong));
    const response = await sendRequest({ type: 'deviceInfo' });
    if (!response.ok) throw new Error(responseError(response));
    const capabilityResponse = await sendRequest({ type: 'capabilities' });
    if (!capabilityResponse.ok) throw new Error(responseError(capabilityResponse));
    channel.appendLine(JSON.stringify(response.deviceInfo, null, 2));
    channel.appendLine(JSON.stringify(capabilityResponse.capabilities, null, 2));
    vscode.window.showInformationMessage('AutoSDK device connection is ready.');
  } catch (error) {
    channel.appendLine(error.stack || error.message);
    vscode.window.showErrorMessage(`AutoSDK connection failed: ${error.message}`);
  }
}

async function stopScript() {
  try {
    const response = await sendRequest({ type: 'stop' });
    if (!response.ok) throw new Error(responseError(response));
    vscode.window.showInformationMessage('AutoSDK stop requested.');
  } catch (error) {
    vscode.window.showErrorMessage(`AutoSDK stop failed: ${error.message}`);
  }
}

async function captureScreenshot() {
  try {
    const response = await sendRequest({ type: 'screenshot' });
    if (!response.ok || !response.pngBase64) throw new Error(responseError(response));
    const root = vscode.workspace.workspaceFolders?.[0]?.uri;
    const destination = await vscode.window.showSaveDialog({
      defaultUri: root ? vscode.Uri.joinPath(root, 'autosdk-screenshot.png') : undefined,
      filters: { 'PNG images': ['png'] },
      saveLabel: 'Save AutoSDK Screenshot'
    });
    if (!destination) return;
    await vscode.workspace.fs.writeFile(destination, Buffer.from(response.pngBase64, 'base64'));
    await vscode.commands.executeCommand('vscode.open', destination);
  } catch (error) {
    vscode.window.showErrorMessage(`AutoSDK screenshot failed: ${error.message}`);
  }
}

async function inspectNodes() {
  try {
    const response = await sendRequest({ type: 'nodes' });
    if (!response.ok || !Array.isArray(response.nodes)) throw new Error(responseError(response));
    const document = await vscode.workspace.openTextDocument({
      language: 'json',
      content: JSON.stringify(response.nodes, null, 2)
    });
    await vscode.window.showTextDocument(document, { preview: true });
  } catch (error) {
    vscode.window.showErrorMessage(`AutoSDK node inspection failed: ${error.message}`);
  }
}

function updateConnectionStatus(state, detail) {
  if (!connectionStatus) return;
  const labels = {
    connecting: '$(sync~spin) AutoSDK: connecting',
    ready: '$(debug-alt) AutoSDK: ready',
    disconnected: '$(debug-disconnect) AutoSDK: disconnected'
  };
  connectionStatus.text = labels[state] || labels.disconnected;
  connectionStatus.tooltip = detail || 'AutoSDK device connection';
  connectionStatus.backgroundColor = state === 'disconnected'
    ? new vscode.ThemeColor('statusBarItem.warningBackground')
    : undefined;
  connectionStatus.show();
}

function postInspector(panel, message) {
  if (!panel || inspectorPanel !== panel) return;
  try {
    void Promise.resolve(panel.webview.postMessage(message)).catch(() => {});
  } catch (_) { /* panel was disposed between the identity check and post */ }
}

async function captureInspector(panel, signal) {
  postInspector(panel, { type: 'loading', message: 'Capturing device snapshot...' });
  try {
    const snapshot = await sendRequest(
      { type: 'inspectSnapshot', options: { maxNodes: 1000 } },
      { signal }
    );
    if (!snapshot.ok || !snapshot.pngBase64) throw new Error(responseError(snapshot));
    if (!Array.isArray(snapshot.nodes)) throw new Error('Device returned an invalid node snapshot.');
    if (!snapshot.deviceInfo) throw new Error('Device returned no device information.');
    postInspector(panel, {
      type: 'snapshot',
      pngBase64: snapshot.pngBase64,
      nodes: snapshot.nodes,
      deviceInfo: snapshot.deviceInfo,
      snapshotId: snapshot.snapshotId,
      durationMs: snapshot.durationMs,
      truncated: Boolean(snapshot.truncated)
    });
  } catch (error) {
    if (error.name === 'AbortError') return;
    postInspector(panel, { type: 'error', message: error.message });
  }
}

function refreshInspector(panel) {
  if (panel !== inspectorPanel || !inspectorRefreshRunner) return Promise.resolve(false);
  return inspectorRefreshRunner.request();
}

async function insertGeneratedCode(code) {
  const validatedCode = generatedCode(code);
  if (!validatedCode) return;
  const editor = lastScriptEditor || vscode.window.visibleTextEditors.find(candidate =>
    candidate.document.languageId === 'javascript' || candidate.document.languageId === 'typescript');
  if (!editor) throw new Error('Open a JavaScript or TypeScript script before inserting code.');
  const applied = await editor.edit(builder => {
    const selection = editor.selection;
    const value = validatedCode.endsWith('\n') ? validatedCode : `${validatedCode}\n`;
    if (selection.isEmpty) builder.insert(selection.active, value);
    else builder.replace(selection, value);
  });
  if (!applied) throw new Error('VS Code refused the generated code edit. The document may have changed or become read-only.');
  await vscode.window.showTextDocument(editor.document, editor.viewColumn, false);
}

async function testImageFromFile(panel, signal) {
  const selected = await vscode.window.showOpenDialog({
    canSelectMany: false,
    filters: { 'Image templates': ['png', 'jpg', 'jpeg'] },
    openLabel: 'Test AutoSDK Image'
  });
  if (!selected?.length) return;
  if (signal.aborted) return;
  const metadata = await vscode.workspace.fs.stat(selected[0]);
  if ((metadata.type & vscode.FileType.File) === 0) throw new Error('Choose a PNG or JPEG file, not a directory.');
  if (metadata.size > 512 * 1024) throw new Error('Image template exceeds the 512 KB debug limit. Crop or compress it first.');
  const data = await vscode.workspace.fs.readFile(selected[0]);
  if (signal.aborted) return;
  if (data.byteLength > 512 * 1024) throw new Error('Image template exceeds the 512 KB debug limit. Crop or compress it first.');
  const name = deployedAssetName(path.basename(selected[0].fsPath), selected[0].toString());
  const dataBase64 = Buffer.from(data).toString('base64');
  postInspector(panel, { type: 'loading', message: `Deploying and testing ${name}...` });
  const deployed = await sendRequest({ type: 'putAsset', name, dataBase64 }, { signal });
  if (!deployed.ok) throw new Error(responseError(deployed));
  const response = await sendRequest({
    type: 'findImage',
    assetName: name,
    options: { threshold: 0.9, maxCandidates: 100000, maxComparedPixels: 50000000 }
  }, { signal });
  if (!response.ok) throw new Error(responseError(response));
  postInspector(panel, { type: 'imageResult', match: response.match || { found: false }, assetPath: deployed.path });
}

async function openInspector() {
  const editor = vscode.window.activeTextEditor;
  if (editor && (editor.document.languageId === 'javascript' || editor.document.languageId === 'typescript')) lastScriptEditor = editor;
  if (inspectorPanel) {
    const wasVisible = inspectorPanel.visible;
    inspectorPanel.reveal(vscode.ViewColumn.Beside, true);
    if (wasVisible) await refreshInspector(inspectorPanel);
    return;
  }
  const panel = vscode.window.createWebviewPanel(
    'autosdkInspector',
    'AutoSDK Inspector',
    vscode.ViewColumn.Beside,
    {
      enableScripts: true,
      retainContextWhenHidden: false,
      localResourceRoots: [extensionContext.extensionUri]
    }
  );
  inspectorPanel = panel;
  let abortController = new AbortController();
  const refreshRunner = new CoalescingRunner(() => captureInspector(panel, abortController.signal));
  inspectorAbortController = abortController;
  inspectorRefreshRunner = refreshRunner;
  let nodeActionInFlight = false;
  panel.webview.html = inspectorHtml(panel.webview, extensionContext.extensionUri);
  panel.onDidChangeViewState(event => {
    if (!event.webviewPanel.visible) {
      abortController.abort();
      refreshRunner.cancelPending();
    } else if (abortController.signal.aborted) {
      abortController = new AbortController();
      if (inspectorPanel === panel) inspectorAbortController = abortController;
    }
  });
  panel.onDidDispose(() => {
    abortController.abort();
    refreshRunner.dispose();
    if (inspectorPanel === panel) {
      inspectorPanel = undefined;
      inspectorAbortController = undefined;
      inspectorRefreshRunner = undefined;
    }
  });
  panel.webview.onDidReceiveMessage(async message => {
    try {
      if (!message || typeof message !== 'object') return;
      const signal = abortController.signal;
      if (message.type === 'ready' || message.type === 'refresh') await refreshInspector(panel);
      else if (message.type === 'testSelector') {
        const selector = selectorObject(message.selector);
        const response = await sendRequest({ type: 'nodes', selector }, { signal });
        if (!response.ok || !Array.isArray(response.nodes)) throw new Error(responseError(response));
        postInspector(panel, { type: 'selectorResult', nodes: response.nodes });
      } else if (message.type === 'testImage') await testImageFromFile(panel, signal);
      else if (message.type === 'testOCR') {
        const region = ocrRegion(message.region);
        const response = await sendRequest(
          { type: 'testOCR', region: { ...region, mode: 'fast', maxResults: 100 } },
          { signal }
        );
        if (!response.ok || !Array.isArray(response.items)) throw new Error(responseError(response));
        postInspector(panel, { type: 'ocrResult', items: response.items, region });
      }
      else if (message.type === 'pixelColor') {
        const coordinates = point(message.x, message.y);
        const response = await sendRequest({ type: 'pixelColor', ...coordinates }, { signal });
        if (!response.ok) throw new Error(responseError(response));
        postInspector(panel, { type: 'pixelColor', color: response.color });
      } else if (message.type === 'nodeAction') {
        if (nodeActionInFlight) throw new Error('A node action is already in progress.');
        nodeActionInFlight = true;
        try {
          const payload = { type: 'nodeAction', action: nodeAction(message.action) };
          if (message.selector !== undefined) payload.selector = selectorObject(message.selector);
          if (message.x !== undefined || message.y !== undefined) {
            Object.assign(payload, point(message.x, message.y));
          }
          if (!payload.selector && payload.x === undefined) throw new Error('Node action requires a selector or point.');
          if (!payload.selector && payload.action !== 'click') {
            throw new Error('Only coordinate clicks can omit a selector.');
          }
          if (payload.action === 'input' && !payload.selector) throw new Error('Node input requires a selector.');
          if (payload.action === 'input') {
            const text = await vscode.window.showInputBox({
              prompt: 'Text to enter on the selected iPhone node',
              validateInput(value) {
                try { inputText(value); return undefined; }
                catch (error) { return error.message; }
              }
            });
            if (text === undefined) return;
            payload.text = inputText(text);
          }
          const response = await sendRequest(payload, { signal });
          if (!response.ok) throw new Error(responseError(response));
          postInspector(panel, { type: 'notice', message: `${payload.action} completed` });
          await new Promise(resolve => setTimeout(resolve, 250));
          if (signal.aborted) return;
          await refreshInspector(panel);
        } finally {
          nodeActionInFlight = false;
        }
      } else if (message.type === 'copyCode') {
        await vscode.env.clipboard.writeText(generatedCode(message.code));
        postInspector(panel, { type: 'notice', message: 'Code copied' });
      } else if (message.type === 'insertCode') {
        await insertGeneratedCode(message.code);
        postInspector(panel, { type: 'notice', message: 'Code inserted' });
      }
    } catch (error) {
      if (error.name === 'AbortError') return;
      postInspector(panel, { type: 'error', message: error.message });
    }
  });
}

function completionProvider() {
  return {
    provideCompletionItems(document, position) {
      const prefix = document.lineAt(position.line).text.slice(0, position.character);
      const namespaceMatch = prefix.match(/\b(auto|file|storages|device|http|image|app)\.$/);
      const namespace = namespaceMatch?.[1];
      return API_COMPLETIONS.filter(([signature]) => !namespace || signature.startsWith(`${namespace}.`)).map(([signature, documentation]) => {
        const label = signature.slice(0, signature.indexOf('('));
        const item = new vscode.CompletionItem(label, vscode.CompletionItemKind.Method);
        item.detail = signature;
        item.documentation = new vscode.MarkdownString(documentation);
        const insertion = namespace ? signature.slice(namespace.length + 1) : signature;
        item.insertText = new vscode.SnippetString(insertion.replace(/\((.*)\)$/, (_, args) => {
          if (!args) return '()';
          return `(${args.split(', ').map((arg, index) => `\${${index + 1}:${arg}}`).join(', ')})`;
        }));
        return item;
      });
    }
  };
}

async function buildTrollStoreIPA() {
  const channel = outputChannel();
  channel.show(true);
  if (!vscode.workspace.isTrusted) {
    vscode.window.showErrorMessage('Trust this workspace before running its AutoSDK build helper.');
    return;
  }
  const configuredPath = configuration().get('repositoryPath');
  const workspacePath = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath;
  const cwd = configuredPath || workspacePath;
  if (!cwd) {
    vscode.window.showErrorMessage('Open the AutoSDK repository or configure autosdk.repositoryPath.');
    return;
  }
  const toolPath = path.join(cwd, 'tools', 'auto-sdk.mjs');
  if (!fs.existsSync(toolPath)) {
    vscode.window.showErrorMessage(`AutoSDK build tool was not found at ${toolPath}.`);
    return;
  }
  const defaultUri = vscode.workspace.workspaceFolders?.[0]?.uri
    ? vscode.Uri.joinPath(vscode.workspace.workspaceFolders[0].uri, 'dist', 'AutoSDKTemplate.ipa')
    : undefined;
  const destination = await vscode.window.showSaveDialog({
    defaultUri,
    filters: { 'iOS packages': ['ipa'] },
    saveLabel: 'Save AutoSDK TrollStore IPA'
  });
  if (!destination) return;

  const settings = configuration();
  const workflow = String(settings.get('workflow') || 'Build TrollStore IPA');
  const repository = String(settings.get('repository') || '');
  const ref = String(settings.get('workflowRef') || '');
  const artifact = String(settings.get('artifactName') || 'AutoSDKTemplate-TrollStore');
  const timeoutSetting = Number(settings.get('buildTimeout'));
  const timeout = Number.isFinite(timeoutSetting)
    ? Math.min(21600, Math.max(60, timeoutSetting))
    : 1800;
  const args = [toolPath, 'build-remote', '--output', destination.fsPath,
    '--workflow', workflow, '--artifact', artifact, '--timeout', String(timeout)];
  if (repository) args.push('--repo', repository);
  if (ref) args.push('--ref', ref);

  channel.appendLine(`Building TrollStore IPA from ${cwd}...`);
  channel.appendLine(`Output: ${destination.fsPath}`);
  await vscode.window.withProgress({
    location: vscode.ProgressLocation.Notification,
    title: 'Building AutoSDK TrollStore IPA',
    cancellable: true
  }, (_progress, cancellationToken) => new Promise(resolve => {
    let child;
    let cancelled = false;
    let settled = false;
    let spawned = false;
    let cancellationSubscription;
    const finish = () => {
      if (settled) return;
      settled = true;
      if (child) activeBuildProcesses.delete(child);
      cancellationSubscription?.dispose();
      resolve();
    };
    try {
      child = spawn('node', args, { cwd, shell: false, windowsHide: true });
    } catch (error) {
      channel.appendLine(`AutoSDK build failed to start: ${error.message}`);
      vscode.window.showErrorMessage(`AutoSDK build failed. Install Node.js 22+ and verify it is on PATH: ${error.message}`);
      finish();
      return;
    }
    activeBuildProcesses.add(child);
    child.once('spawn', () => { spawned = true; });
    cancellationSubscription = cancellationToken.onCancellationRequested(() => {
      if (cancelled) return;
      cancelled = true;
      channel.appendLine('Cancelling AutoSDK remote build...');
      terminateOwnedProcess(child);
    });
    child.stdout?.on('data', data => channel.append(data.toString()));
    child.stderr?.on('data', data => channel.append(data.toString()));
    child.once('error', error => {
      if (spawned) {
        channel.appendLine(`AutoSDK build process error: ${error.message}`);
        return;
      }
      channel.appendLine(`AutoSDK build failed to start: ${error.message}`);
      if (!cancelled) vscode.window.showErrorMessage(`AutoSDK build failed. Install Node.js 22+ and verify it is on PATH: ${error.message}`);
      finish();
    });
    child.once('close', code => {
      if (settled) return;
      if (cancelled) {
        channel.appendLine('AutoSDK remote build cancelled.');
      } else if (code === 0) {
        channel.appendLine(`IPA ready at ${destination.fsPath}`);
        vscode.window.showInformationMessage('AutoSDK TrollStore IPA downloaded.');
      } else {
        vscode.window.showErrorMessage(`AutoSDK remote build failed (${code ?? 'unknown'}). See the AutoSDK output.`);
      }
      finish();
    });
  }));
}

function activate(context) {
  extensionContext = context;
  connectionStatus = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 50);
  connectionStatus.command = 'autosdk.testConnection';
  deviceClient = new DeviceClient({
    credentials: async () => connectionCredentials(configuration(), extensionContext.secrets, workspaceCredentialScope()),
    onState: updateConnectionStatus,
    onEvent: event => outputChannel().appendLine(`[protocol] ${JSON.stringify(event)}`)
  });
  usbTunnel = new UsbTunnel({
    onOutput: value => outputChannel().append(value),
    onExit: event => {
      outputChannel().appendLine(`USB tunnel closed (${event.detail}).`);
      if (!event.expected) {
        deviceClient?.disconnect('USB tunnel closed.');
        vscode.window.showWarningMessage(`AutoSDK USB tunnel closed (${event.detail}).`);
      }
    }
  });
  updateConnectionStatus('disconnected', 'Run AutoSDK: Test Device Connection.');
  const activeEditor = vscode.window.activeTextEditor;
  if (activeEditor && (activeEditor.document.languageId === 'javascript' || activeEditor.document.languageId === 'typescript')) lastScriptEditor = activeEditor;
  context.subscriptions.push(
    outputChannel(),
    connectionStatus,
    deviceClient,
    vscode.window.onDidChangeActiveTextEditor(editor => {
      if (editor && (editor.document.languageId === 'javascript' || editor.document.languageId === 'typescript')) lastScriptEditor = editor;
    }),
    vscode.workspace.onDidChangeConfiguration(event => {
      if (event.affectsConfiguration('autosdk.debugUrl') || event.affectsConfiguration('autosdk.debugToken')) {
        deviceClient?.disconnect('Device connection settings changed.');
      }
    }),
    vscode.workspace.onDidChangeWorkspaceFolders(() => {
      deviceClient?.disconnect('Workspace identity changed; configure the device connection again.');
    }),
    vscode.commands.registerCommand('autosdk.runCurrentScript', runCurrentScript),
    vscode.commands.registerCommand('autosdk.sendCurrentScript', deployCurrentScript),
    vscode.commands.registerCommand('autosdk.manageScripts', manageDeviceScripts),
    vscode.commands.registerCommand('autosdk.configureDevice', configureDevice),
    vscode.commands.registerCommand('autosdk.startUsbTunnel', startUsbTunnel),
    vscode.commands.registerCommand('autosdk.stopUsbTunnel', stopUsbTunnel),
    vscode.commands.registerCommand('autosdk.testConnection', testConnection),
    vscode.commands.registerCommand('autosdk.stopScript', stopScript),
    vscode.commands.registerCommand('autosdk.captureScreenshot', captureScreenshot),
    vscode.commands.registerCommand('autosdk.inspectNodes', inspectNodes),
    vscode.commands.registerCommand('autosdk.openInspector', openInspector),
    vscode.languages.registerCompletionItemProvider([{ language: 'javascript' }, { language: 'typescript' }], completionProvider(), '.'),
    vscode.commands.registerCommand('autosdk.buildTrollStoreIPA', buildTrollStoreIPA)
  );
}

function deactivate() {
  for (const child of activeBuildProcesses) terminateOwnedProcess(child);
  activeBuildProcesses.clear();
  usbTunnel?.dispose();
  deviceClient?.dispose();
  inspectorAbortController?.abort();
  inspectorRefreshRunner?.dispose();
  inspectorPanel?.dispose();
  usbTunnel = undefined;
  deviceClient = undefined;
  inspectorPanel = undefined;
  inspectorAbortController = undefined;
  inspectorRefreshRunner = undefined;
  connectionStatus = undefined;
  lastScriptEditor = undefined;
  extensionContext = undefined;
  channel = undefined;
}

module.exports = { activate, deactivate };
