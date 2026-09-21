const vscode = require('vscode');
const path = require('path');
const { spawn } = require('child_process');
const fs = require('fs');
const { DeviceHome } = require('./device-home');
const { buildDeviceHealth, readDeviceHealth, healthReportText } = require('./device-health');
const { deviceHomeHtml } = require('./device-home-view');
const { REENTER_TOKEN, RETRY_CONNECTION, SCAN_WIFI_DEVICE, connectWithRecovery, connectionTargetIsCurrent, runErrorActions } = require('./connection-recovery');
const { DeviceClient } = require('./device-client');
const { canonicalDebugUrl, connectionCredentials, normalizeWifiDebugUrl, tokenForConfiguration, updateConnectionConfiguration } = require('./connection-settings');
const { languageProviders, insertAPI } = require('./api-tools');
const { discoverUsbDevices } = require('./device-discovery');
const { generatedCode, inputText } = require('./inspector-input');
const { InspectorService, maxNodes, responseError } = require('./inspector-service');
const { InspectorSession } = require('./inspector-session');
const { inspectorHtml } = require('./inspector-view');
const { terminateOwnedProcess } = require('./process-lifecycle');
const { deployedAssetName, deployedScriptName, editorScript } = require('./script-tools');
const { UsbTunnel } = require('./usb-tunnel');
const { discoverWifiDevices } = require('./wifi-discovery');

let extensionContext;
let channel;
let deviceClient;
let usbTunnel;
let connectionStatus;
let inspectorPanel;
let inspectorService;
let inspectorSession;
let lastScriptEditor;
let deviceHome;
let deviceHomeView;
let scriptRunning = false;
const activeBuildProcesses = new Set();

// Generated from SDK declarations and the Chinese API reference; no second hand-maintained list.

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

function currentScript(selectionOnly = false) {
  return editorScript(vscode.window.activeTextEditor, selectionOnly);
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

async function runCurrentScript(selectionOnly = false, editor = vscode.window.activeTextEditor) {
  if (scriptRunning) return vscode.window.showWarningMessage('脚本正在运行，请先停止或等待完成。');
  const channel = outputChannel();
  channel.show(true);
  try {
    if (!vscode.workspace.isTrusted) throw new Error('Trust this workspace before running its scripts on the iPhone.');
    const script = editorScript(editor, selectionOnly);
    scriptRunning = true;
    deviceHome?.setRunning(true);
    channel.appendLine(`Running ${script.name}...`);
    const response = await runScript(script);
    if (!response.ok) throw new Error(responseError(response));
    channel.appendLine(JSON.stringify(response, null, 2));
    vscode.window.showInformationMessage(`AutoSDK 已完成：${script.name}`);
  } catch (error) {
    channel.appendLine(error.stack || error.message);
    const action = await vscode.window.showErrorMessage(`AutoSDK: ${error.message}`, ...runErrorActions(error));
    if (action === SCAN_WIFI_DEVICE) await vscode.commands.executeCommand('autosdk.discoverDevice');
  } finally {
    scriptRunning = false;
    deviceHome?.setRunning(false);
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

async function saveDeviceConnection({ current, credentialScope, mode, token, url, usbDeviceUdid, wifiDeviceId }) {
  if (scriptRunning) throw new Error('脚本正在运行，请先停止后再切换手机。');
  const hasWorkspace = Boolean(vscode.workspace.workspaceFile || vscode.workspace.workspaceFolders?.length);
  const target = hasWorkspace ? vscode.ConfigurationTarget.Workspace : vscode.ConfigurationTarget.Global;
  const inspectKey = hasWorkspace ? 'workspaceValue' : 'globalValue';
  const deviceUpdates = [
    ['usbDeviceUdid', usbDeviceUdid],
    ['wifiDeviceId', wifiDeviceId]
  ].filter(([, value]) => value !== undefined).map(([key, value]) => ({
    key,
    value,
    previous: current.inspect?.(key)?.[inspectKey]
  }));
  const appliedUpdates = [];
  let result;
  try {
    for (const update of deviceUpdates) {
      await current.update(update.key, update.value, target);
      appliedUpdates.push(update);
    }
    result = await updateConnectionConfiguration(
      current,
      extensionContext.secrets,
      token,
      url,
      credentialScope,
      target,
      [
        { target: vscode.ConfigurationTarget.Global, inspectKey: 'globalValue' },
        { target: vscode.ConfigurationTarget.WorkspaceFolder, inspectKey: 'workspaceFolderValue' }
      ],
      inspectKey
    );
  } catch (error) {
    const rollbackErrors = [];
    for (const update of [...appliedUpdates].reverse()) {
      try {
        await current.update(update.key, update.previous, target);
      } catch (rollbackError) {
        rollbackErrors.push(`${update.key}: ${rollbackError.message}`);
      }
    }
    if (rollbackErrors.length) throw new Error(`${error.message} Restoring the previous device selection also failed: ${rollbackErrors.join('; ')}`);
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
    title: '首次连接手机 · 安全配对',
    prompt: '输入手机 AutoSDK 中显示的配对码（Debug Token），只需配对一次，不是代码。',
    password: true,
    value: savedToken,
    validateInput(value) {
      if (!value) return '请填写手机上显示的配对码。';
      if (Buffer.byteLength(value, 'utf8') > 1024) return '配对码过长，请检查是否复制了其他内容。';
      if (mode === 'wifi' && value.length < 16) return 'Wi-Fi 配对码至少 16 个字符，请复制完整内容。';
      return undefined;
    }
  });
}

async function testWifiConnectionWithRecovery({ current, credentialScope, url, wifiDeviceId = '' }) {
  const isCurrent = () => connectionTargetIsCurrent({ scope: workspaceCredentialScope(),
    url: configuration().get('debugUrl'), deviceId: configuration().get('wifiDeviceId') },
  { scope: credentialScope, url, deviceId: wifiDeviceId });
  return connectWithRecovery({
    isCurrent,
    testConnection: () => testConnection({ showFailure: false }),
    chooseAction: () => vscode.window.showWarningMessage(
      'AutoSDK could not connect to this iPhone. Correct the token or retry without scanning again.',
      REENTER_TOKEN,
      RETRY_CONNECTION
    ),
    replaceToken: async () => {
      const token = await promptDebugToken('wifi', '');
      if (token === undefined) return false;
      if (!isCurrent()) {
        vscode.window.showErrorMessage('AutoSDK: The workspace or selected iPhone changed. The old pairing was not overwritten.');
        return false;
      }
      try {
        await saveDeviceConnection({
          current,
          credentialScope,
          mode: 'wifi',
          token,
          url,
          usbDeviceUdid: '',
          wifiDeviceId
        });
        return true;
      } catch (error) {
        vscode.window.showErrorMessage(`AutoSDK could not update the debug token: ${error.message}`);
        return false;
      }
    }
  });
}

async function configureDevice(preferredMode) {
  const current = configuration();
  const credentialScope = workspaceCredentialScope();
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
    placeHolder: 'Choose how this computer connects to the iPhone',
    matchOnDescription: true
  });
  if (!connection) return;
  const configuredUrl = String(current.get('debugUrl') || '');
  const defaultUrl = connection.mode === 'usb'
    ? 'ws://127.0.0.1:9001'
    : (/^wss?:\/\/(?!127\.0\.0\.1|localhost|\[::1\])/i.test(configuredUrl) ? configuredUrl : '');
  const enteredUrl = await vscode.window.showInputBox({
    prompt: connection.mode === 'wifi'
      ? 'Enter the iPhone IP address or debug URL shown by the AutoSDK app'
      : 'AutoSDK USB tunnel URL',
    value: defaultUrl,
    placeHolder: connection.mode === 'wifi' ? '192.168.1.25 or ws://192.168.1.25:9001' : undefined,
    validateInput(value) {
      if (connection.mode === 'wifi') {
        try { normalizeWifiDebugUrl(value); return undefined; }
        catch (error) { return error.message; }
      }
      try {
        const parsed = new URL(value);
        if (parsed.protocol !== 'ws:' && parsed.protocol !== 'wss:') return 'Use a ws:// or wss:// URL.';
        if (!parsed.hostname || !parsed.port) return 'Include the iPhone address and debug port.';
        if (parsed.username || parsed.password) return 'Do not put credentials in the URL; enter the debug token separately.';
        if (parsed.hash) return 'Do not include a #fragment in the device URL.';
        const loopback = ['127.0.0.1', 'localhost', '::1', '[::1]'].includes(parsed.hostname);
        if (connection.mode === 'usb' && (parsed.protocol !== 'ws:' || !loopback)) {
          return 'USB mode requires a local ws://127.0.0.1:PORT tunnel URL.';
        }
        return undefined;
      } catch (_) {
        return 'Enter a valid WebSocket URL.';
      }
    }
  });
  if (enteredUrl === undefined) return;
  const url = connection.mode === 'wifi' ? normalizeWifiDebugUrl(enteredUrl) : enteredUrl;
  const savedToken = canonicalDebugUrl(configuredUrl) === canonicalDebugUrl(url)
    ? await tokenForConfiguration(current, extensionContext.secrets, credentialScope)
    : '';
  const token = await promptDebugToken(connection.mode, savedToken);
  if (token === undefined) return;
  if (credentialScope !== workspaceCredentialScope()) {
    vscode.window.showErrorMessage('AutoSDK: The workspace changed while configuring the device. Run the command again.');
    return;
  }
  try {
    await saveDeviceConnection({
      current,
      credentialScope,
      mode: connection.mode,
      token,
      url,
      usbDeviceUdid: connection.mode === 'wifi' ? '' : undefined,
      wifiDeviceId: ''
    });
  } catch (error) {
    vscode.window.showErrorMessage(`AutoSDK could not save the device connection: ${error.message}`);
    return;
  }
  if (connection.mode === 'wifi') {
    outputChannel().appendLine(`Saved Wi-Fi device ${canonicalDebugUrl(url)}; testing connection…`);
    await testWifiConnectionWithRecovery({ current, credentialScope, url });
    return;
  }
  const action = await vscode.window.showInformationMessage('AutoSDK device connection saved.', 'Start USB Tunnel');
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
  await vscode.commands.executeCommand('autosdk.devices.focus');
  await deviceHome?.scan();
}

async function pairWifiDevice(device, forcePair = false) {
  const current = configuration();
  const credentialScope = workspaceCredentialScope();
  const previousUrl = canonicalDebugUrl(current.get('debugUrl'));
  const previousDeviceId = String(current.get('wifiDeviceId') || '');
  const savedToken = !forcePair && device.deviceId && previousDeviceId === device.deviceId
    ? await tokenForConfiguration(current, extensionContext.secrets, credentialScope) : '';
  const token = savedToken || await promptDebugToken('wifi', '');
  if (token === undefined) return false;
  if (credentialScope !== workspaceCredentialScope() || previousUrl !== canonicalDebugUrl(configuration().get('debugUrl')) ||
      previousDeviceId !== String(configuration().get('wifiDeviceId') || '')) {
    throw new Error('工作区或连接目标已改变，请重新选择手机。');
  }
  await saveDeviceConnection({ current, credentialScope, mode: 'wifi', token,
    url: device.url, usbDeviceUdid: '', wifiDeviceId: device.deviceId });
  await extensionContext.workspaceState.update('autosdk.selectedDevice', {
    scope: credentialScope, url: canonicalDebugUrl(device.url), name: device.name
  });
  deviceHome?.publish();
  return testConnection({ showFailure: false, showSuccess: false, throwOnFailure: true });
}

function sidebarEditor() {
  return lastScriptEditor && !lastScriptEditor.document.isClosed ? lastScriptEditor : undefined;
}

function homeContext() {
  const url = canonicalDebugUrl(configuration().get('debugUrl'));
  const selected = extensionContext.workspaceState.get('autosdk.selectedDevice');
  const editor = sidebarEditor();
  let address = '';
  try { address = new URL(url).host; } catch (_) { /* no valid configured address */ }
  return {
    configured: Boolean(url), address,
    deviceName: selected?.scope === workspaceCredentialScope() && selected.url === url ? selected.name : url ? '上次添加的手机' : '',
    scriptName: editor ? path.basename(editor.document.fileName) : '',
    canRun: Boolean(editor), canSelect: Boolean(editor && editor.selections.length === 1 && !editor.selection.isEmpty),
    trusted: vscode.workspace.isTrusted
  };
}

async function performHomeAction(action, device) {
  if ((action === 'run' || action === 'runSelection') && !sidebarEditor()) {
    throw new Error('请先打开脚本，或点击「新建示例脚本」。');
  }
  switch (action) {
    case 'connect': return pairWifiDevice(device);
    case 'reconnect': return testConnection({ showFailure: false, showSuccess: false, throwOnFailure: true });
    case 'pair': if (!configuration().get('wifiDeviceId') && configuration().get('usbDeviceUdid')) return configureDevice('usb');
      return pairWifiDevice({ url: configuration().get('debugUrl'),
      deviceId: configuration().get('wifiDeviceId') || '', name: homeContext().deviceName }, true);
    case 'disconnect': deviceClient?.disconnect('用户断开连接。'); return;
    case 'newScript': return newScript();
    case 'functions': return insertAPI(sidebarEditor, vscode);
    case 'run': return runCurrentScript(false, sidebarEditor());
    case 'runSelection': return runCurrentScript(true, sidebarEditor());
    case 'stop': return stopScript();
    case 'inspector': return openInspector();
    case 'logs': return outputChannel().show(true);
    case 'help': return vscode.commands.executeCommand('markdown.showPreview', vscode.Uri.joinPath(extensionContext.extensionUri, 'START_HERE.md'));
    case 'manual': return configureDevice('wifi');
    case 'usb': return discoverUsbDevice();
  }
}

async function newScript() {
  const document = await vscode.workspace.openTextDocument({ language: 'javascript',
    content: '// 点击「运行整个脚本」，或在这里右键运行。\n// 这是脚本示例，连接手机不需要写代码。\nlogd("AutoSDK 连接成功");\nlogd(JSON.stringify(device.getDeviceInfo(), null, 2));\n' });
  const editor = await vscode.window.showTextDocument(document, { preview: false });
  lastScriptEditor = editor;
  deviceHome?.publish();
}

function resolveDeviceHome(view) {
  deviceHomeView = view;
  view.webview.options = { enableScripts: true,
    localResourceRoots: [vscode.Uri.joinPath(extensionContext.extensionUri, 'media')] };
  const subscription = view.webview.onDidReceiveMessage(message => deviceHome?.receive(message));
  const visibility = view.onDidChangeVisibility(() => { if (view.visible) deviceHome?.publish(); else deviceHome?.cancelHealth(); });
  view.onDidDispose(() => {
    deviceHome?.cancelHealth();
    subscription.dispose(); visibility.dispose();
    if (deviceHomeView === view) deviceHomeView = undefined;
  });
  view.webview.html = deviceHomeHtml(view.webview, extensionContext.extensionUri);
}

async function discoverUsbDevice() {
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
      if (action === 'Search Again') return discoverUsbDevice();
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
      usbDeviceUdid: selection.device.id,
      wifiDeviceId: ''
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

async function testConnection({ showFailure = true, showSuccess = true, throwOnFailure = false } = {}) {
  const channel = outputChannel();
  if (showSuccess) channel.show(true);
  try {
    const pong = await sendRequest({ type: 'ping' });
    if (!pong.ok) throw new Error(responseError(pong));
    const healthGeneration = deviceHome?.healthGeneration;
    const response = await sendRequest({ type: 'deviceInfo' });
    if (!response.ok) throw new Error(responseError(response));
    const capabilityResponse = await sendRequest({ type: 'capabilities' });
    if (!capabilityResponse.ok) throw new Error(responseError(capabilityResponse));
    const report = buildDeviceHealth(response.deviceInfo, capabilityResponse.capabilities);
    deviceHome?.setHealth(report, healthGeneration);
    channel.appendLine(healthReportText(report));
    if (showSuccess) vscode.window.showInformationMessage('手机已连接，可以开始运行和采集。');
    return true;
  } catch (error) {
    channel.appendLine(error.stack || error.message);
    if (showFailure) vscode.window.showErrorMessage(`AutoSDK connection failed: ${error.message}`);
    if (throwOnFailure) throw error;
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
  deviceHome?.setConnection(state);
  if (!connectionStatus) return;
  const labels = {
    connecting: '$(sync~spin) AutoSDK: 正在连接',
    ready: '$(device-mobile) AutoSDK: 已连接',
    disconnected: '$(device-mobile) AutoSDK: 连接手机'
  };
  connectionStatus.text = labels[state] || labels.disconnected;
  connectionStatus.tooltip = '打开设备与调试：搜索手机、连接、运行、截图与节点';
  connectionStatus.command = 'autosdk.openDeviceHome';
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
    'AutoSDK 截图与节点',
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
  deviceHome = new DeviceHome({ context: homeContext, discover: discoverWifiDevices,
    health: options => readDeviceHealth(sendRequest, options),
    copyHealth: report => vscode.env.clipboard.writeText(healthReportText(report)),
    perform: performHomeAction, log: error => outputChannel().appendLine(error.stack || String(error)),
    publish: state => {
      try {
        if (deviceHomeView) void Promise.resolve(deviceHomeView.webview.postMessage({ type: 'state', state })).catch(() => {});
      } catch (_) { /* view disposed between state update and post */ }
    }
  });
  connectionStatus = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 50);
  connectionStatus.command = 'autosdk.openDeviceHome';
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
    deviceHome,
    vscode.window.registerWebviewViewProvider('autosdk.devices', { resolveWebviewView: resolveDeviceHome }),
    outputChannel(),
    connectionStatus,
    deviceClient,
    vscode.window.onDidChangeActiveTextEditor(editor => {
      if (editor && (editor.document.languageId === 'javascript' || editor.document.languageId === 'typescript')) lastScriptEditor = editor;
      deviceHome?.publish();
    }),
    vscode.window.onDidChangeTextEditorSelection(() => deviceHome?.publish()),
    vscode.workspace.onDidCloseTextDocument(() => deviceHome?.publish()),
    vscode.workspace.onDidGrantWorkspaceTrust(() => deviceHome?.publish()),
    vscode.workspace.onDidChangeConfiguration(event => {
      if (event.affectsConfiguration('autosdk.debugUrl') || event.affectsConfiguration('autosdk.debugToken')) {
        deviceClient?.disconnect('Device connection settings changed.');
      }
    }),
    vscode.workspace.onDidChangeWorkspaceFolders(() => {
      deviceClient?.disconnect('Workspace identity changed; configure the device connection again.');
      deviceHome?.reset();
    }),
    vscode.commands.registerCommand('autosdk.openDeviceHome', () => vscode.commands.executeCommand('autosdk.devices.focus')),
    vscode.commands.registerCommand('autosdk.newScript', newScript),
    vscode.commands.registerCommand('autosdk.runCurrentScript', () => runCurrentScript()),
    vscode.commands.registerCommand('autosdk.runSelection', () => runCurrentScript(true)),
    vscode.commands.registerCommand('autosdk.sendCurrentScript', deployCurrentScript),
    vscode.commands.registerCommand('autosdk.manageScripts', manageDeviceScripts),
    vscode.commands.registerCommand('autosdk.configureDevice', configureDevice),
    vscode.commands.registerCommand('autosdk.discoverDevice', discoverDevice),
    vscode.commands.registerCommand('autosdk.discoverUsbDevice', discoverUsbDevice),
    vscode.commands.registerCommand('autosdk.startUsbTunnel', startUsbTunnel),
    vscode.commands.registerCommand('autosdk.stopUsbTunnel', stopUsbTunnel),
    vscode.commands.registerCommand('autosdk.testConnection', testConnection),
    vscode.commands.registerCommand('autosdk.stopScript', stopScript),
    vscode.commands.registerCommand('autosdk.captureScreenshot', captureScreenshot),
    vscode.commands.registerCommand('autosdk.inspectNodes', inspectNodes),
    vscode.commands.registerCommand('autosdk.openInspector', openInspector),
    ...languageProviders(vscode),
    vscode.commands.registerCommand('autosdk.insertAPI', () => insertAPI(sidebarEditor, vscode)),
    vscode.commands.registerCommand('autosdk.buildIPA', buildIPA)
  );
}

function deactivate() {
  deviceHome?.dispose();
  deviceHome = undefined;
  deviceHomeView = undefined;
  scriptRunning = false;
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
