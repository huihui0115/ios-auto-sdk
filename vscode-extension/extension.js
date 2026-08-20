const vscode = require('vscode');
const path = require('path');
const { spawn } = require('child_process');
const fs = require('fs');
const { DeviceClient } = require('./device-client');
const { connectionCredentials, tokenForConfiguration, updateConnectionConfiguration } = require('./connection-settings');
const { completionEntries } = require('./completion-model');
const { discoverUsbDevices } = require('./device-discovery');
const { generatedCode, inputText } = require('./inspector-input');
const { InspectorService, maxNodes, responseError } = require('./inspector-service');
const { InspectorSession } = require('./inspector-session');
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
let inspectorService;
let inspectorSession;
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
  ['auto.appState(bundleId)', 'Read the application state code.'],
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
  ['app.state(bundleId)', 'Read the application state code.'],
  ['clickPoint(x, y)', 'Global coordinate activation alias.'],
  ['doubleClickPoint(x, y, intervalSeconds)', 'Global coordinate double activation alias.'],
  ['swipeToPoint(x1, y1, x2, y2, durationSeconds)', 'Global swipe alias.'],
  ['sleep(milliseconds)', 'Global cooperative sleep alias.'],
  ['random(min, max)', 'Return a random integer in an inclusive range.'],
  ['logd(...values)', 'Write a debug-level script log entry.'],
  ['logi(...values)', 'Write an info-level script log entry.'],
  ['logw(...values)', 'Write a warning-level script log entry.'],
  ['loge(...values)', 'Write an error-level script log entry.'],
  ['media.deleteAllPhotos()', 'Delete every photo from the camera roll (read-write authorization).'],
  ['media.deleteAllVideos()', 'Delete every video from the camera roll (read-write authorization).'],
  ['media.deleteAllMedia()', 'Delete every photo and video from the camera roll.'],
  ['file.lineCount(path)', 'Count lines in a UTF-8 text file.'],
  ['file.getLineText(path, index)', 'Read one line by index.'],
  ['file.insertLineText(path, index, text)', 'Insert a line at an index.'],
  ['file.resetLineText(path, index, text)', 'Replace one line.'],
  ['file.readPlist(path)', 'Read an XML plist into a plain object.'],
  ['file.writePlist(path, value)', 'Write a JSON value as an XML plist.'],
  ['plist.read(path) / plist.write(path, value)', 'Global plist read/write aliases.'],
  ['strings.trim(text)', 'Trim whitespace from both ends.'],
  ['strings.split(text, separator)', 'Split a string into an array.'],
  ['strings.toHex(text) / fromHex(hex)', 'Hex encode and decode.'],
  ['strings.isChinese(text) / isEmail(text) / isLink(text)', 'String classification helpers.'],
  ['strings.md5(text) / sha1(text) / sha256(text) / sha512(text)', 'Message digest helpers.'],
  ['strings.base64Encode(text) / base64Decode(base64)', 'Base64 encode and decode.'],
  ['strings.aes128Encrypt(text, key) / aes128Decrypt(base64, key)', 'AES-128-ECB encryption helpers.'],
  ['strings.toPinYin(text)', 'Convert Chinese characters to pinyin (system transform).'],
  ['strings.stripUtf8Bom(text)', 'Remove a leading UTF-8 BOM character.'],
  ['strings.fromUnicode(text)', 'Restore \\uXXXX escape sequences to characters.'],
  ['toPinYin(text) / stripUtf8Bom(text) / fromUnicode(text)', 'Global string helper aliases.'],
  ['webView.init(url)', 'Create a floating WKWebView and return a token.'],
  ['webView.show(token, x, y, width, height)', 'Show the floating web view at a position.'],
  ['webView.eval(token, js)', 'Evaluate JavaScript inside the floating web view.'],
  ['webView.hidden(token) / webView.release(token)', 'Hide or release the floating web view.'],
  ['screenDraw.init()', 'Create a floating rectangle draw and return a token.'],
  ['screenDraw.setBorderWidth(token, width) / setBorderColor(token, color)', 'Style the draw border.'],
  ['screenDraw.setTitle(token, title)', 'Set the draw title label.'],
  ['screenDraw.show(token, x, y, w, h) / move(token, x, y) / hide(token)', 'Show, move, and hide the draw.'],
  ['floatBall.show(title, x, y)', 'Show the draggable floating ball.'],
  ['floatBall.move(x, y) / hide() / isShow()', 'Move, hide, or query the floating ball.'],
  ['setFloatBallPoint(x, y)', 'EasyClick-compatible floating ball alias.'],
  ['node.keep(node) / node.unkeep(node)', 'Register or release a node reference.'],
  ['keepNode(node) / unkeepNode(node)', 'Global node keep/unkeep aliases.'],
  ['alert(message, title)', 'Show a native alert dialog.'],
  ['exit()', 'Stop the current script immediately.'],
  ['restartScript()', 'Stop and re-run the current script.'],
  ['sha256(text) / sha512(text) / md5(text) / sha1(text)', 'Global hash aliases.'],
  ['formatDate(timestamp, pattern)', 'Format a millisecond timestamp as readable text (yyyy/MM/dd/HH/mm/ss/SSS/E).'],
  ['dateFormat(timestamp, pattern)', 'Alias of formatDate.'],
  ['sleepRandom(min, max)', 'Sleep a random number of milliseconds in an inclusive range.'],
  ['strings.startWith(text, prefix) / endWith(text, suffix) / contains(text, sub)', 'EasyClick-style string predicates.'],
  ['strings.indexOf(text, sub, from?) / lastIndexOf(text, sub)', 'Find a substring position.'],
  ['strings.substring(text, start, end?) / replaceAll(text, search, replacement)', 'Slice or replace substrings.'],
  ['strings.toUpperCase(text) / toLowerCase(text)', 'Change letter case.'],
  ['strings.join(array, sep) / repeat(text, count) / length(text)', 'Combine and measure strings.'],
  ['strings.padZero(text, length) / padStart(text, length, pad?) / padEnd(text, length, pad?)', 'Pad a string to a fixed width.'],
  ['strings.format(pattern, ...args)', 'Format with %s/%d/%f placeholders.'],
  ['app.isInstalled(bundleId)', 'Check whether an app is installed via the installed-app list.'],
  ['device.getTotalMemory() / getAvailableMemory() / getUsedMemory()', 'Memory aliases over getMemoryInfo().'],
  ['file.getLineCount(path)', 'Alias of file.lineCount.'],
  ['aes128Encrypt(text, key) / aes128Decrypt(base64, key)', 'Global AES-128 aliases.'],
  ['screen.getColor(x, y) / getColorRGB(x, y) / getColorHex(x, y)', 'EasyClick-compatible screen pixel color readers.'],
  ['screen.findImage(path, options) / findColor(color, region, options)', 'EasyClick-compatible image/color search entries.'],
  ['screen.findColorEx(colors, threshold, x, y, ex, ey, limit, direction)', 'EasyClick-compatible region multi-color search.'],
  ['screen.findNotColor(colors, threshold, x, y, ex, ey, limit, direction)', 'EasyClick-compatible region non-color search.'],
  ['screen.findMultiColor(color, offsets, region, options)', 'EasyClick-compatible multi-point color pattern search.'],
  ['screen.findColors(points, options) / isColors(points, options) / cmpColor(points, options)', 'EasyClick-compatible multi-point color compare.'],
  ['screen.ocr(options)', 'EasyClick-compatible OCR entry (on-device Vision).'],
  ['screen.screenshot()', 'EasyClick-compatible screenshot entry (PNG base64).'],
  ['app.getAppName(bundleId)', 'Resolve an app display name from the installed app list.'],
  ['app.isRunning(bundleId)', 'Check whether an app is running (state code >= 2).'],
  ['findColorCount(colors, threshold, x, y, ex, ey, maxCount)', 'Count matching color points (AScript CountingColor style).'],
  ['screen.findColorCount(colors, threshold, x, y, ex, ey, maxCount)', 'Screen-module color counting entry.'],
  ['image.findColorCount(colors, threshold, x, y, ex, ey, maxCount)', 'Image-module color counting entry.'],
  ['image.toBase64(path)', 'Read a sandbox image file as a Base64 string.'],
  ['metrics.set(width, height) / get() / x(value) / y(value) / point(x, y)', 'Scale design coordinates to the current screen.'],
  ['base64.encode(text) / decode(base64)', 'Encode or decode UTF-8 text with Base64.'],
  ['thread.execAsync(fn, ...args) / execSync(fn, ...args) / cancelThread(handle) / stopAll() / isCancelled()', 'Run and control cooperative script threads.'],
  ['utils.dataMd5(text) / fileMd5(path) / randomInt(min, max) / randomCharNumber(length) / getRangeInt(min, max) / getRatio(ratio)', 'Common hashing and random helpers.'],
  ['utils.zip(source, destination) / unzip(path, destination) / readFileInZip(path, name)', 'Archive helpers for sandbox files.'],
  ['utils.playMp3(path, volume, loop) / stopMp3() / deleteAllPhotos() / deleteAllVideos() / requestPhotoAuthorization()', 'Media utility helpers.'],
  ['ocr(options) / ocr.newOcr(defaults)', 'Run Vision OCR or create an OCR instance with defaults.'],
  ['ws.connect(url) / poll(handle) / send(handle, text) / close(handle)', 'Open and operate a WebSocket connection.'],
  ['sqlite.open(path) / exec(handle, sql, params) / query(handle, sql, params) / close(handle)', 'Open and query a sandbox SQLite database.'],
  ['yolo.detect(imagePath) / detectByFilePath(imagePath)', 'Run bounded on-device Vision image classification.'],
  ['location.getLocation(timeoutMs)', 'Read one bounded GPS fix.'],
  ['colors.parseColor(color) / toInt(color) / int2Hex(color) / toHex(color) / hex2Int(color) / rgb(r, g, b) / argb(a, r, g, b)', 'Parse and convert color values.'],
  ['speech.speak(text, options, stopWhenScriptEnd) / tts(text, options, stopWhenScriptEnd) / stop() / stopSpeak()', 'Speak text or stop active speech.'],
  ['pasteboard.read() / write(text)', 'Read or replace the iOS pasteboard text.'],
  ['json.encode(value) / decode(text)', 'Encode or safely decode JSON.'],
  ['floatLog.show(x, y, width, height) / log(text) / clear() / hide() / isShow() / destroy()', 'Control the on-device floating log window.'],
  ['node.find(selector) / findOne(selector) / findAll(selector) / at(x, y) / snapshot(maxResults) / keptCount()', 'Find nodes or capture a bounded node snapshot.'],
  ['webView.takeMessage(token) / injectBridge(token) / loadHTML(token, html)', 'Exchange messages with or update a floating web view.'],
  ['screenDraw.release(token) / clearAll()', 'Release floating drawing resources.'],
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

async function saveDeviceConnection({ current, credentialScope, mode, token, url, usbDeviceUdid }) {
  const inspection = current.inspect?.('usbDeviceUdid');
  const previousUdid = inspection?.workspaceValue;
  let udidChanged = false;
  if (usbDeviceUdid !== undefined) {
    await current.update('usbDeviceUdid', usbDeviceUdid, vscode.ConfigurationTarget.Workspace);
    udidChanged = true;
  }
  let result;
  try {
    result = await updateConnectionConfiguration(
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
  } catch (error) {
    if (udidChanged) {
      try {
        await current.update('usbDeviceUdid', previousUdid, vscode.ConfigurationTarget.Workspace);
      } catch (rollbackError) {
        throw new Error(`${error.message} Restoring the previous USB device also failed: ${rollbackError.message}`);
      }
    }
    throw error;
  }
  if (result.plaintextCleanupErrors.length) {
    vscode.window.showWarningMessage('AutoSDK connected, but the old plaintext debug token could not be removed from one or more VS Code settings scopes. Remove autosdk.debugToken manually.');
  }
  deviceClient?.disconnect('Device connection settings changed.');
  if (mode === 'wifi' && usbTunnel?.running) await stopUsbTunnel();
}

async function promptDebugToken(mode, savedToken) {
  return vscode.window.showInputBox({
    prompt: 'AutoSDK debug token shown in the iPhone app',
    password: true,
    value: savedToken,
    validateInput(value) {
      if (!value) return 'Enter the installation token displayed by the AutoSDK app.';
      if (Buffer.byteLength(value, 'utf8') > 1024) return 'The debug token must not exceed 1024 UTF-8 bytes.';
      if (mode === 'wifi' && value.length < 16) return 'Wi-Fi tokens must contain at least 16 characters.';
      return undefined;
    }
  });
}

async function configureDevice(preferredMode) {
  const current = configuration();
  const credentialScope = workspaceCredentialScope();
  const savedToken = await tokenForConfiguration(current, extensionContext.secrets, credentialScope);
  const connection = preferredMode ? {
    mode: preferredMode
  } : await vscode.window.showQuickPick([
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
  const token = await promptDebugToken(connection.mode, savedToken);
  if (token === undefined) return;
  if (credentialScope !== workspaceCredentialScope()) {
    vscode.window.showErrorMessage('AutoSDK: The workspace changed while configuring the device. Run the command again.');
    return;
  }
  try {
    await saveDeviceConnection({ current, credentialScope, mode: connection.mode, token, url });
  } catch (error) {
    vscode.window.showErrorMessage(`AutoSDK could not save the device connection: ${error.message}`);
    return;
  }
  const action = await vscode.window.showInformationMessage(
    'AutoSDK device connection saved.',
    ...(connection.mode === 'usb' ? ['Start USB Tunnel'] : [])
  );
  if (action === 'Start USB Tunnel') await startUsbTunnel();
}

function loopbackUsbUrl(current) {
  try {
    const parsed = new URL(String(current.get('debugUrl') || ''));
    const loopback = ['127.0.0.1', 'localhost', '::1', '[::1]'].includes(parsed.hostname);
    if (parsed.protocol === 'ws:' && loopback && parsed.port) return `ws://127.0.0.1:${parsed.port}`;
  } catch (_) { /* use the standard local port */ }
  return 'ws://127.0.0.1:9001';
}

async function discoverDevice() {
  const channel = outputChannel();
  channel.show(true);
  try {
    if (!vscode.workspace.isTrusted) throw new Error('Trust this workspace before running local USB discovery tools.');
    const current = configuration();
    const result = await vscode.window.withProgress({
      location: vscode.ProgressLocation.Notification,
      title: 'AutoSDK: Searching for USB iPhones…',
      cancellable: false
    }, () => discoverUsbDevices({ iproxyPath: String(current.get('iproxyPath') || 'iproxy') }));
    channel.appendLine(`USB search via ${result.executable}: ${result.devices.length} iPhone(s) found.`);
    if (!result.devices.length) {
      const action = await vscode.window.showWarningMessage(
        'AutoSDK found no USB iPhone. Unlock the phone, trust this computer, and reconnect the cable.',
        'Search Again',
        'Add Wi-Fi Device'
      );
      if (action === 'Search Again') return discoverDevice();
      if (action === 'Add Wi-Fi Device') return configureDevice('wifi');
      return;
    }
    const selection = await vscode.window.showQuickPick([
      ...result.devices.map(device => ({
        label: `$(device-mobile) ${device.name}`,
        description: device.id,
        detail: 'USB · select to add, start the tunnel, and test the connection',
        device
      })),
      {
        label: '$(radio-tower) Add Wi-Fi device manually',
        description: 'Use the address displayed in the AutoSDK iPhone app',
        mode: 'wifi'
      }
    ], {
      placeHolder: 'Select an iPhone to add to this workspace',
      matchOnDescription: true,
      matchOnDetail: true
    });
    if (!selection) return;
    if (selection.mode === 'wifi') return configureDevice('wifi');
    const credentialScope = workspaceCredentialScope();
    const previousUdid = String(current.get('usbDeviceUdid') || '');
    const savedToken = previousUdid === selection.device.id
      ? await tokenForConfiguration(current, extensionContext.secrets, credentialScope)
      : '';
    const token = await promptDebugToken('usb', savedToken);
    if (token === undefined) return;
    if (credentialScope !== workspaceCredentialScope()) {
      vscode.window.showErrorMessage('AutoSDK: The workspace changed while adding the device. Run the command again.');
      return;
    }
    await saveDeviceConnection({
      current,
      credentialScope,
      mode: 'usb',
      token,
      url: loopbackUsbUrl(current),
      usbDeviceUdid: selection.device.id
    });
    const started = await startUsbTunnel();
    if (started) await testConnection();
  } catch (error) {
    channel.appendLine(`Device search failed: ${error.stack || error.message}`);
    const action = await vscode.window.showErrorMessage(
      `AutoSDK device search failed: ${error.message}`,
      'Add Wi-Fi Device'
    );
    if (action === 'Add Wi-Fi Device') await configureDevice('wifi');
  }
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
    return true;
  } catch (error) {
    channel.appendLine(`USB tunnel failed: ${error.stack || error.message}`);
    vscode.window.showErrorMessage(`AutoSDK USB tunnel failed: ${error.message}`);
    return false;
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
    return true;
  } catch (error) {
    channel.appendLine(error.stack || error.message);
    vscode.window.showErrorMessage(`AutoSDK connection failed: ${error.message}`);
    return false;
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
    const pngBase64 = await inspectorService.screenshot();
    const root = vscode.workspace.workspaceFolders?.[0]?.uri;
    const destination = await vscode.window.showSaveDialog({
      defaultUri: root ? vscode.Uri.joinPath(root, 'autosdk-screenshot.png') : undefined,
      filters: { 'PNG images': ['png'] },
      saveLabel: 'Save AutoSDK Screenshot'
    });
    if (!destination) return;
    await vscode.workspace.fs.writeFile(destination, Buffer.from(pngBase64, 'base64'));
    await vscode.commands.executeCommand('vscode.open', destination);
  } catch (error) {
    vscode.window.showErrorMessage(`AutoSDK screenshot failed: ${error.message}`);
  }
}

async function inspectNodes() {
  try {
    const nodes = await inspectorService.nodes();
    const document = await vscode.workspace.openTextDocument({
      language: 'json',
      content: JSON.stringify(nodes, null, 2)
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
    disconnected: '$(device-mobile) AutoSDK: add iPhone'
  };
  connectionStatus.text = labels[state] || labels.disconnected;
  connectionStatus.tooltip = detail || 'AutoSDK device connection';
  connectionStatus.command = state === 'disconnected' ? 'autosdk.discoverDevice' : 'autosdk.testConnection';
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

function refreshInspector(panel) {
  if (panel !== inspectorPanel || !inspectorSession) return Promise.resolve(false);
  return inspectorSession.refresh();
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

async function selectImageTemplate(signal) {
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
  return { name, dataBase64 };
}

async function saveInspectorSnapshot(snapshot) {
  const root = vscode.workspace.workspaceFolders?.[0]?.uri;
  const safeId = String(snapshot.snapshotId || Date.now()).replace(/[^A-Za-z0-9_.-]/g, '-').slice(0, 80);
  const destination = await vscode.window.showSaveDialog({
    defaultUri: root ? vscode.Uri.joinPath(root, `autosdk-snapshot-${safeId}.json`) : undefined,
    filters: { 'AutoSDK snapshots': ['json'] },
    saveLabel: 'Export AutoSDK Snapshot'
  });
  if (!destination) return false;
  const payload = Buffer.from(JSON.stringify({
    format: 'autosdk-inspector-snapshot',
    formatVersion: 1,
    ...snapshot
  }, null, 2), 'utf8');
  await vscode.workspace.fs.writeFile(destination, payload);
  await vscode.commands.executeCommand('vscode.open', destination);
  return true;
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
  const session = new InspectorSession({
    service: inspectorService,
    postMessage: message => postInspector(panel, message),
    maxNodes: maxNodes(configuration().get('inspectorMaxNodes')),
    actionRefreshDelay: configuration().get('inspectorActionRefreshDelay'),
    selectImage: selectImageTemplate,
    requestInput: () => vscode.window.showInputBox({
      prompt: 'Text to enter on the selected iPhone node',
      validateInput(value) {
        try { inputText(value); return undefined; }
        catch (error) { return error.message; }
      }
    }),
    copyCode: code => vscode.env.clipboard.writeText(code),
    insertCode: insertGeneratedCode,
    saveSnapshot: saveInspectorSnapshot
  });
  inspectorSession = session;
  panel.onDidChangeViewState(event => {
    session.setVisible(event.webviewPanel.visible);
  });
  panel.onDidDispose(() => {
    session.dispose();
    if (inspectorPanel === panel) {
      inspectorPanel = undefined;
      inspectorSession = undefined;
    }
  });
  panel.webview.onDidReceiveMessage(async message => {
    try {
      await session.handleMessage(message);
    } catch (error) {
      if (error.name === 'AbortError') return;
      const operations = {
        refresh: 'snapshot', ready: 'snapshot', testSelector: 'selector', testImage: 'image',
        testOCR: 'ocr', pixelColor: 'pixel', nodeAction: 'action', saveSnapshot: 'export',
        copyCode: 'code', insertCode: 'code', cancelOperations: 'cancel'
      };
      postInspector(panel, {
        type: 'error',
        operation: operations[message?.type] || 'inspector',
        requestId: typeof message?.requestId === 'string' && message.requestId.length <= 128
          ? message.requestId
          : undefined,
        message: error.message
      });
    }
  });
  panel.webview.html = inspectorHtml(panel.webview, extensionContext.extensionUri);
}

function completionProvider() {
  return {
    provideCompletionItems(document, position) {
      const prefix = document.lineAt(position.line).text.slice(0, position.character);
      return completionEntries(API_COMPLETIONS, prefix, { action: 'auto', string: 'strings' }).map(candidate => {
        const item = new vscode.CompletionItem(candidate.label, vscode.CompletionItemKind.Method);
        const { documentation, signature } = candidate;
        item.detail = signature;
        item.documentation = new vscode.MarkdownString(documentation);
        item.insertText = new vscode.SnippetString(candidate.insertText);
        return item;
      });
    }
  };
}

async function buildIPA() {
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
    saveLabel: 'Save AutoSDK IPA'
  });
  if (!destination) return;

  const settings = configuration();
  const workflow = String(settings.get('workflow') || 'Build AutoSDK IPA');
  const repository = String(settings.get('repository') || '');
  const ref = String(settings.get('workflowRef') || '');
  const artifact = String(settings.get('artifactName') || 'AutoSDKTemplate-ipa');
  const timeoutSetting = Number(settings.get('buildTimeout'));
  const timeout = Number.isFinite(timeoutSetting)
    ? Math.min(21600, Math.max(60, timeoutSetting))
    : 1800;
  const args = [toolPath, 'build-remote', '--output', destination.fsPath,
    '--workflow', workflow, '--artifact', artifact, '--timeout', String(timeout)];
  if (repository) args.push('--repo', repository);
  if (ref) args.push('--ref', ref);

  channel.appendLine(`Building AutoSDK IPA from ${cwd}...`);
  channel.appendLine(`Output: ${destination.fsPath}`);
  await vscode.window.withProgress({
    location: vscode.ProgressLocation.Notification,
    title: 'Building AutoSDK IPA',
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
        vscode.window.showInformationMessage('AutoSDK IPA downloaded.');
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
  connectionStatus.command = 'autosdk.discoverDevice';
  deviceClient = new DeviceClient({
    credentials: async () => connectionCredentials(configuration(), extensionContext.secrets, workspaceCredentialScope()),
    onState: updateConnectionStatus,
    onEvent: event => outputChannel().appendLine(`[protocol] ${JSON.stringify(event)}`)
  });
  inspectorService = new InspectorService(sendRequest);
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
  updateConnectionStatus('disconnected', 'Click to search for and add an iPhone.');
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
    vscode.commands.registerCommand('autosdk.discoverDevice', discoverDevice),
    vscode.commands.registerCommand('autosdk.startUsbTunnel', startUsbTunnel),
    vscode.commands.registerCommand('autosdk.stopUsbTunnel', stopUsbTunnel),
    vscode.commands.registerCommand('autosdk.testConnection', testConnection),
    vscode.commands.registerCommand('autosdk.stopScript', stopScript),
    vscode.commands.registerCommand('autosdk.captureScreenshot', captureScreenshot),
    vscode.commands.registerCommand('autosdk.inspectNodes', inspectNodes),
    vscode.commands.registerCommand('autosdk.openInspector', openInspector),
    vscode.languages.registerCompletionItemProvider([{ language: 'javascript' }, { language: 'typescript' }], completionProvider(), '.'),
    vscode.commands.registerCommand('autosdk.buildIPA', buildIPA)
  );
}

function deactivate() {
  for (const child of activeBuildProcesses) terminateOwnedProcess(child);
  activeBuildProcesses.clear();
  usbTunnel?.dispose();
  deviceClient?.dispose();
  inspectorSession?.dispose();
  inspectorPanel?.dispose();
  usbTunnel = undefined;
  deviceClient = undefined;
  inspectorService = undefined;
  inspectorPanel = undefined;
  inspectorSession = undefined;
  connectionStatus = undefined;
  lastScriptEditor = undefined;
  extensionContext = undefined;
  channel = undefined;
}

module.exports = { activate, deactivate };
