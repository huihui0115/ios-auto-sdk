#!/usr/bin/env node
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import vm from 'node:vm';
import { APIS } from './generate-api-reference.mjs';

const root = resolve(import.meta.dirname, '..');
const failures = [];

function read(path) {
  return readFileSync(resolve(root, path), 'utf8');
}

function check(condition, message) {
  if (!condition) failures.push(message);
}

function checkNodeSyntax(path) {
  const result = spawnSync(process.execPath, ['--check', resolve(root, path)], {
    encoding: 'utf8',
    windowsHide: true
  });
  check(result.status === 0, `${path}: ${result.stderr.trim() || 'Node syntax check failed'}`);
}

function parseJSON(path) {
  try {
    return JSON.parse(read(path));
  } catch (error) {
    failures.push(`${path}: invalid JSON (${error.message})`);
    return {};
  }
}

function sourceFiles(directory) {
  const result = [];
  for (const entry of readdirSync(resolve(root, directory), { withFileTypes: true })) {
    const relative = `${directory}/${entry.name}`;
    if (entry.isDirectory()) result.push(...sourceFiles(relative));
    else if (/\.(h|m)$/.test(entry.name)) result.push(relative);
  }
  return result;
}

// ObjC static function definitions must be uniquely named within a translation unit
// (forward declarations are allowed; definitions ending with '{' are not duplicated).
function collectStaticDefinitions(source) {
  const definitions = [];
  const staticPattern = /\bstatic\s+/g;
  let match;
  while ((match = staticPattern.exec(source))) {
    let i = match.index + match[0].length;
    let parenIndex = -1;
    for (; i < source.length; i += 1) {
      const ch = source[i];
      if (ch === ';' || ch === '{' || ch === '}') break;
      if (ch === '(') { parenIndex = i; break; }
    }
    if (parenIndex < 0) continue;
    let j = parenIndex - 1;
    while (j >= 0 && /\s/.test(source[j])) j -= 1;
    const nameEnd = j + 1;
    while (j >= 0 && /[A-Za-z0-9_]/.test(source[j])) j -= 1;
    const name = source.slice(j + 1, nameEnd);
    if (!name) continue;
    let depth = 1;
    i = parenIndex + 1;
    let closeIndex = -1;
    for (; i < source.length; i += 1) {
      const ch = source[i];
      if (ch === '(') depth += 1;
      else if (ch === ')') { depth -= 1; if (depth === 0) { closeIndex = i; break; } }
    }
    if (closeIndex < 0) continue;
    i = closeIndex + 1;
    while (i < source.length && /\s/.test(source[i])) i += 1;
    if (source[i] === '{') definitions.push(name);
    staticPattern.lastIndex = closeIndex + 1;
  }
  return definitions;
}
for (const sourcePath of sourceFiles('Sources')) {
  const seen = new Map();
  for (const name of collectStaticDefinitions(read(sourcePath))) {
    const line = read(sourcePath).slice(0, read(sourcePath).indexOf(name)).split('\n').length;
    if (seen.has(name)) {
      check(false, `${sourcePath}: duplicate static function definition '${name}' (line ${seen.get(name)} and ${line})`);
    }
    seen.set(name, line);
  }
}
function checkBalancedSource(path) {
  const source = read(path);
  const stack = [];
  const opening = new Set(['(', '[', '{']);
  const matching = { ')': '(', ']': '[', '}': '{' };
  let state = 'code';
  for (let index = 0; index < source.length; index += 1) {
    const character = source[index];
    const next = source[index + 1];
    if (state === 'lineComment') {
      if (character === '\n') state = 'code';
      continue;
    }
    if (state === 'blockComment') {
      if (character === '*' && next === '/') { state = 'code'; index += 1; }
      continue;
    }
    if (state === 'string' || state === 'character') {
      if (character === '\\') { index += 1; continue; }
      if ((state === 'string' && character === '"') || (state === 'character' && character === "'")) state = 'code';
      continue;
    }
    if (character === '/' && next === '/') { state = 'lineComment'; index += 1; continue; }
    if (character === '/' && next === '*') { state = 'blockComment'; index += 1; continue; }
    if (character === '"') { state = 'string'; continue; }
    if (character === "'") { state = 'character'; continue; }
    if (opening.has(character)) stack.push(character);
    else if (matching[character] && stack.pop() !== matching[character]) {
      failures.push(`${path}: mismatched '${character}' near character ${index}`);
      return;
    }
  }
  check(state === 'code' || state === 'lineComment', `${path}: unterminated string or block comment`);
  check(stack.length === 0, `${path}: unbalanced delimiter '${stack.at(-1)}'`);
}

for (const path of ['tools/auto-sdk.mjs', 'tools/debug-client.mjs', 'vscode-extension/extension.js', 'vscode-extension/connection-recovery.js', 'vscode-extension/device-client.js', 'vscode-extension/script-tools.js', 'vscode-extension/usb-tunnel.js', 'vscode-extension/wifi-discovery.js', 'vscode-extension/inspector-service.js', 'vscode-extension/inspector-session.js', 'vscode-extension/inspector-view.js', 'vscode-extension/media/inspector-model.js', 'vscode-extension/media/inspector.js', 'tools/init-project.mjs', 'tools/doctor.mjs']) {
  checkNodeSyntax(path);
}
const debugClientSource = read('tools/debug-client.mjs');
check(debugClientSource.includes('parsedURL.hash'), 'CLI debug URLs must reject fragments that are never sent to WebSocket servers');
const buildTool = read('tools/auto-sdk.mjs');
check(buildTool.includes("displayTitle || '').includes(requestId)") && !buildTool.includes('createdAt >= startedAt'), 'Remote builds must match only their unique request ID');
check(buildTool.includes('async function validateIPA') && buildTool.includes('ZIP_END_OF_CENTRAL_DIRECTORY') &&
      buildTool.includes('Payload\\/[^/]+\\.app\\/') && buildTool.includes('replaceOutputFile'),
      'Builds must validate IPA ZIP contents and replace output files through a recoverable temporary path');
check(buildTool.includes('MAX_CAPTURE_BYTES') && buildTool.includes('produced more than'),
      'Remote build helper command output must have a bounded capture buffer');
check(buildTool.includes('MAX_ARTIFACT_ENTRIES') && buildTool.includes('scheme must not contain path separators'),
      'Build tooling must bound IPA entry counts and keep archive paths inside the output directory');
check(buildTool.includes("process.platform !== 'darwin'") &&
      buildTool.includes('auto-sdk build-remote'),
      'Local build must reject non-macOS hosts with a build-remote hint');
const debugClient = read('tools/debug-client.mjs');
check(debugClient.includes('MAX_SCRIPT_BYTES') && debugClient.includes('metadata.size > MAX_SCRIPT_BYTES') &&
      debugClient.includes('MAX_RESPONSE_BYTES') && debugClient.includes('response.ok !== true'),
      'Debug CLI must bound script files and reject malformed or oversized responses');

const rootPackage = parseJSON('package.json');
check(rootPackage.scripts?.init && rootPackage.scripts?.doctor && rootPackage.scripts?.docs,
      'package.json must expose init/doctor/docs scripts');
const rootLock = parseJSON('package-lock.json');
const extensionPackage = parseJSON('vscode-extension/package.json');
const extensionLock = parseJSON('vscode-extension/package-lock.json');
parseJSON('vscode-extension/snippets/javascript.json');
const jsConfig = parseJSON('jsconfig.json');
const typeDefinitions = read('types/autosdk.d.ts');
check(jsConfig.compilerOptions?.checkJs === true &&
      JSON.stringify(jsConfig.compilerOptions?.lib) === JSON.stringify(['ES2017']),
      'JavaScript tooling must type-check against JavaScriptCore rather than browser DOM globals');
check(typeDefinitions.includes('parentId?: string | null') && typeDefinitions.includes('verifiedCandidates?: number') &&
      typeDefinitions.includes('scannedCandidates?: number') && typeDefinitions.includes('comparedPixels?: number') &&
      typeDefinitions.includes('maxComparedPixels?: number'),
      'Type definitions must include node hierarchy and bounded image/color-match metadata');
check(typeDefinitions.includes('declare function cancelTimeout') &&
      typeDefinitions.includes('declare function cancelInterval') &&
      typeDefinitions.includes('interface AutoConsole'),
      'Type definitions must describe the JavaScriptCore console and timer aliases');
check(typeDefinitions.includes('stat(path: string): AutoFileStat | null') && typeDefinitions.includes('interface AutoFileStat') &&
      typeDefinitions.includes('currentApp(): string | null'),
      'Type definitions must declare file stat helpers and the foreground-app query');
check(typeDefinitions.includes('volumeUp(): boolean') && typeDefinitions.includes('volumeDown(): boolean') &&
      typeDefinitions.includes('isScreenOn(): boolean'),
      'Type definitions must declare device volume keys and screen-state queries');
check(['getDeviceInfo','getScreenWidth','getScreenHeight','getScale','getModel','getOSVersion',
      'getDeviceName','getBattery','isCharging','getOrientation','getDeviceId','getDeviceAlias',
      'getSerialNo','volumeUp','volumeDown','getMemoryInfo','isRunning','isDir','isFile']
      .every(n => typeDefinitions.includes('declare function ' + n)),
      'Type definitions must declare the device/app/file global shorthands');
check(typeDefinitions.includes('getJSON(url: string') &&
      typeDefinitions.includes('width(): number') &&
      typeDefinitions.includes('declare function setScreenMetrics') &&
      typeDefinitions.includes('declare const metrics: AutoMetrics') &&
      typeDefinitions.includes('declare function randomInt') &&
      typeDefinitions.includes('interface AutoBase64') &&
      typeDefinitions.includes('declare function openURL'),
      'Type definitions must declare metrics, uuid/base64, getJSON, device shortcuts, and missing globals');

const podspec = read('AutoSDK.podspec');
const versionSource = read('Sources/AutoSDK/AutoSDKVersion.m');
check(podspec.includes(`s.version          = '${rootPackage.version}'`), 'SDK version differs between package.json and AutoSDK.podspec');
check(versionSource.includes(`"${rootPackage.version}"`), 'SDK version differs between package.json and AutoSDKVersion.m');

// --- API reference completeness: every declared function must be documented ---
{
  const apiSource = read('tools/generate-api-reference.mjs');
  const documented = new Set();
  for (const sigMatch of apiSource.matchAll(/sig:['"]([^'"]+)['"]/g)) {
    for (const part of sigMatch[1].split('/')) {
      const root = part.trim().match(/^[A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*)*/);
      if (root) documented.add(root[0].split('.').pop());
    }
    for (const chain of sigMatch[1].matchAll(/\)\s*\.\s*([A-Za-z_$][\w$]*)\s*\(/g)) documented.add(chain[1]);
  }
  for (const exampleMatch of apiSource.matchAll(/example:`([\s\S]*?)`\s*\}/g)) {
    for (const call of exampleMatch[1].matchAll(/(?:^|[^A-Za-z_$])([A-Za-z_$][\w$]*)\.([A-Za-z_$][\w$]*)\s*\(/g)) {
      documented.add(call[2]);
    }
  }
  const declared = new Set();
  for (const match of typeDefinitions.matchAll(/declare function\s+([A-Za-z_$][\w$]*)\s*\(/g)) declared.add(match[1]);
  const interfacePattern = /interface\s+[A-Za-z_$][\w$]*\s*\{/g;
  let interfaceMatch;
  while ((interfaceMatch = interfacePattern.exec(typeDefinitions))) {
    const start = interfaceMatch.index + interfaceMatch[0].length;
    let depth = 1;
    let index = start;
    for (; index < typeDefinitions.length && depth > 0; index += 1) {
      if (typeDefinitions[index] === '{') depth += 1;
      else if (typeDefinitions[index] === '}') depth -= 1;
    }
    const body = typeDefinitions.slice(start, index - 1);
    for (const method of body.matchAll(/(?:^|[;\n])\s*([A-Za-z_$][\w$]*)\s*\(/g)) declared.add(method[1]);
  }
  const aliases = new Set(['auto', 'console', 'file', 'storages', 'device', 'http', 'image', 'media', 'app', 'metrics', 'base64', 'store']);
  const undocumented = [...declared].filter(name => !documented.has(name) && !aliases.has(name)).sort();
  check(undocumented.length === 0,
        `API reference must document every declared function; missing: ${undocumented.join(', ')}`);
}check(/double AutoSDKVersionNumber = \d+\.\d+;/.test(versionSource),
      'AutoSDKVersionNumber must stay a valid C double (major.minor only)');
check(rootLock.name === rootPackage.name && rootLock.version === rootPackage.version &&
      rootLock.packages?.['']?.name === rootPackage.name && rootLock.packages?.['']?.version === rootPackage.version,
      'Root package-lock.json is missing or inconsistent with package.json');

const developerDocs = read('docs/index.html');
const developerDocsGenerator = read('tools/generate-devdocs.mjs');
const rootReadme = read('README.md');
const autoScriptComparison = read('docs/AUTOSCRIPT_COMPARISON.md');
check((developerDocs.match(/class="api-entry"/g) || []).length === APIS.length,
      'canonical developer docs must render every API function (' + APIS.length + ')');
check(developerDocs.includes('page-quickstart') && developerDocs.includes('page-api-touch') &&
      developerDocs.includes('page-api-speech') && developerDocs.includes('可视化检查器') &&
      developerDocs.includes('data-copy=') && developerDocs.includes('globalSearch') &&
      developerDocs.includes('menuButton'),
      'canonical developer docs must keep guides, all API modules, search, copy and mobile navigation');
check(!existsSync('docs/api-reference.html') && !existsSync('docs/devdocs/index.html') &&
      !existsSync('docs/guide/index.html'),
      'redundant legacy HTML documentation must stay removed');
check(!existsSync('docs/QUICK_START.md') &&
      !rootReadme.includes('docs/QUICK_START.md') &&
      !autoScriptComparison.includes('QUICK_START.md') &&
      rootReadme.includes('docs/index.html#/quickstart'),
      'quick-start guidance must use the single canonical HTML documentation entry');
check(developerDocsGenerator.includes('caps.automation.screenshot === true') &&
      developerDocsGenerator.includes('typeof image === "string"') &&
      developerDocsGenerator.includes('跨 App 不是普通签名默认能力'),
      'canonical guides must capability-guard screenshots and describe truthful Inspector boundaries');
for (const [index, api] of APIS.entries()) {
  try {
    new vm.Script(api.example);
  } catch (error) {
    check(false, `API example ${index} (${api.sig}) must parse as JavaScript: ${error.message}`);
  }
}
// Round 47: external WDA support is removed; the built-in no-WDA adapter is the only cross-app path.
check(!existsSync('Sources/AutoSDK/AutoWDAHTTPAdapter.m') && !existsSync('Sources/AutoSDK/include/AutoWDAHTTPAdapter.h'),
      'AutoWDAHTTPAdapter must stay removed; the built-in no-WDA adapter is the only cross-app path');
check(read('docs/LUA_FRAMEWORK_AUDIT.md').includes('LuaTouch'), 'Lua framework audit document is missing');
const templatePlist = read('Examples/TemplateApp/App/Info.plist');
check(templatePlist.includes('NSAllowsLocalNetworking') && templatePlist.includes('NSBonjourServices') &&
      templatePlist.includes('_autosdk._tcp'),
      'Template must allow local networking and declare AutoSDK Bonjour discovery');
check(templatePlist.includes('AutoSDKAdapter') && templatePlist.includes('BUILTIN') && !templatePlist.includes('AutoSDKWDAURL'),
      'Template must default to the built-in no-WDA adapter and carry no WDA configuration');
check(extensionLock.version === extensionPackage.version, 'VS Code extension version differs from package-lock.json');
check(extensionLock.packages?.['']?.version === extensionPackage.version, 'VS Code extension root lock version is inconsistent');
const extensionVsixName = `autosdk-vscode-${extensionPackage.version}.vsix`;
const buildWorkflow = read('.github/workflows/ios-build.yml');
const extensionReadme = read('vscode-extension/README.md');
check(buildWorkflow.split(extensionVsixName).length - 1 === 4 &&
      extensionReadme.includes(extensionVsixName) &&
      developerDocs.includes(extensionVsixName),
      'VS Code extension version must match its READMEs/guides and all workflow artifact/release names');
check(!extensionReadme.includes('inspect and operate any app') &&
      extensionReadme.includes('auto.capabilities().automation.nodes') &&
      extensionReadme.includes('ordinary free-signed Wi-Fi'),
      'VS Code Inspector documentation must state signing, capability and background limits');
check(extensionPackage.private === true && extensionPackage.license === 'UNLICENSED',
      'VS Code extension package must remain private and unlicensed for npm publication');
check(extensionPackage.contributes?.commands?.some(item => item.command === 'autosdk.startUsbTunnel') &&
      extensionPackage.contributes?.commands?.some(item => item.command === 'autosdk.stopUsbTunnel') &&
      extensionPackage.contributes?.commands?.some(item => item.command === 'autosdk.discoverDevice') &&
      extensionPackage.contributes?.commands?.some(item => item.command === 'autosdk.discoverUsbDevice'),
      'VS Code extension must expose Wi-Fi discovery plus advanced USB tunnel commands');
check(extensionPackage.dependencies?.['bonjour-service'] === '1.4.4',
      'VS Code Wi-Fi discovery must pin its Bonjour implementation');
check(!extensionPackage.dependencies?.['auto-sdk-tools'] && !extensionLock.packages?.['..'],
      'VS Code extension must not package the repository root as a linked dependency');
check(read('vscode-extension/.vscodeignore').includes('.npm-cache/**'),
      'VSIX packaging must exclude temporary npm caches');
check(extensionPackage.contributes?.menus?.['editor/context']?.some(item =>
        item.command === 'autosdk.runCurrentScript' && item.when.includes('javascript') && item.when.includes('typescript')) &&
      extensionPackage.contributes?.menus?.['editor/title']?.some(item => item.command === 'autosdk.runCurrentScript'),
      'VS Code extension must expose run actions in script editor context and title menus');
check(extensionPackage.contributes?.configuration?.properties?.['autosdk.connectionTimeout']?.maximum === 3600000 &&
      extensionPackage.contributes?.configuration?.properties?.['autosdk.buildTimeout']?.maximum === 21600 &&
      extensionPackage.contributes?.configuration?.properties?.['autosdk.inspectorMaxNodes']?.minimum === 1 &&
      extensionPackage.contributes?.configuration?.properties?.['autosdk.inspectorMaxNodes']?.maximum === 2000 &&
      extensionPackage.contributes?.configuration?.properties?.['autosdk.inspectorActionRefreshDelay']?.minimum === 0 &&
      extensionPackage.contributes?.configuration?.properties?.['autosdk.inspectorActionRefreshDelay']?.maximum === 5000,
      'VS Code extension timeouts and Inspector collection settings must be bounded');

const extensionSource = read('vscode-extension/extension.js');
const connectionRecoverySource = read('vscode-extension/connection-recovery.js');
const contributedCommandIds = extensionPackage.contributes?.commands?.map(item => item.command) || [];
for (const command of contributedCommandIds) {
  check(extensionSource.includes("registerCommand('" + command + "'"),
        'Extension must register contributed command ' + command);
}
const inspectorSource = read('vscode-extension/media/inspector.js');
check(/type === 'selectorResult'[\s\S]{0,800}state\.match = null[\s\S]{0,200}elements\.selection\.hidden = true/.test(inspectorSource),
      'Inspector selector results must clear stale match overlays and region selections');
const inspectorServiceSource = read('vscode-extension/inspector-service.js');
const inspectorSessionSource = read('vscode-extension/inspector-session.js');
const inspectorModelSource = read('vscode-extension/media/inspector-model.js');
const deviceDiscoverySource = read('vscode-extension/device-discovery.js');
const wifiDiscoverySource = read('vscode-extension/wifi-discovery.js');
check(extensionSource.includes('new InspectorService(sendRequest)') && extensionSource.includes('new InspectorSession({') &&
      !extensionSource.includes("type: 'inspectSnapshot'"),
      'Extension commands must delegate Inspector protocol and session state to focused modules');
check(extensionSource.includes('discoverUsbDevices({') && extensionSource.includes("registerCommand('autosdk.discoverUsbDevice'") &&
      deviceDiscoverySource.includes('shell: false') && deviceDiscoverySource.includes("'idevice_id'") &&
      deviceDiscoverySource.includes('MAX_TOOL_OUTPUT_BYTES'),
      'USB discovery must remain bounded, shell-free and wired to its advanced command');
check(extensionSource.includes('discover: discoverWifiDevices') &&
      read('vscode-extension/device-home.js').includes('this.options.discover({ signal: controller.signal })') &&
      extensionSource.includes("registerCommand('autosdk.discoverDevice'") &&
      wifiDiscoverySource.includes("type: 'autosdk'") && wifiDiscoverySource.includes('MAX_DISCOVERED_DEVICES') &&
      wifiDiscoverySource.includes('MAX_DISCOVERY_TIMEOUT_MS') &&
      wifiDiscoverySource.includes('DISCOVERY_SETTLE_MS = 1200') &&
      wifiDiscoverySource.includes("error.name = 'AbortError'"),
      'Wi-Fi discovery must remain bounded, cancellable and scan only the AutoSDK Bonjour service');
check(extensionPackage.contributes?.views?.autosdk?.some(view => view.id === 'autosdk.devices' && view.type === 'webview') &&
      extensionSource.includes("registerWebviewViewProvider('autosdk.devices'") &&
      read('vscode-extension/device-home-view.js').includes('搜索 Wi-Fi 手机') &&
      read('vscode-extension/media/device-home.js').includes("send('connect', device.key)"),
      'VS Code must provide a graphical device sidebar with host-owned scan selections');
check(inspectorServiceSource.includes('this.visualTail.then(task, task)') &&
      inspectorServiceSource.includes("type: 'inspectSnapshot'") && inspectorServiceSource.includes('MAX_PNG_BASE64_LENGTH'),
      'Inspector service must serialize and validate device visual requests');
check(inspectorSessionSource.includes('class LatestTaskQueue') && inspectorSessionSource.includes('this.queue.schedule') &&
      inspectorSessionSource.includes('isCurrent()') && inspectorSessionSource.includes("message.type === 'cancelOperations'") &&
      inspectorSessionSource.includes('!signal.aborted') && inspectorSessionSource.includes('actionRefreshDelay'),
      'Inspector session must serialize, cancel, and suppress stale visual work');
check(inspectorSource.includes('state.latestRequests') && inspectorSource.includes('state.busyRequests') &&
      inspectorSource.includes("send('cancel', 'cancelOperations')") && inspectorModelSource.includes('selectionIndex') &&
      inspectorModelSource.includes('selectorForNode') && inspectorModelSource.includes('width - 1'),
      'Inspector webview must correlate/cancel responses and keep bounded testable selection logic');

const engineSource = read('Sources/AutoSDK/AutoEngine.m');
check(engineSource.includes('AutoAppSchemeForName') && engineSource.includes('isEqualToString:@"getappscheme"') &&
      engineSource.includes('isEqualToString:@"launchbyscheme"'),
      'Engine must keep the built-in App URL scheme lookup and launch ops');
check(engineSource.includes('hasTorch') && engineSource.includes('torchMode'),
      'Engine must keep the native flashlight/torch device op');
check(engineSource.includes('waitPollInterval') && engineSource.includes('pollInterval * 1.5'), 'waitFor must use bounded polling backoff');
check(engineSource.includes('NSError *destinationError = nil;') && engineSource.includes('&destinationError'),
      'HTTP download destination validation must declare its error pointer');
check(engineSource.includes('AutoPayloadHasFiniteNumbers') && engineSource.includes('maxScreenshotBytes'), 'script numeric inputs and screenshots must be bounded');
check(engineSource.includes('maximumTotalBytes') && engineSource.includes('retainedMessageBytes') &&
      engineSource.includes('@"maxLogBytes"'),
      'Retained script logs must have a hard total byte budget');
check(engineSource.includes('AutoSQLiteOperation') && engineSource.includes('AutoSQLiteCloseAll') &&
      engineSource.includes('sqlite3_open_v2') && engineSource.includes('sqlite3_prepare_v2') &&
      engineSource.includes('@"sqO"') && engineSource.includes('@"sqC"') && engineSource.includes('@"yoloD"'),
      'Native engine must implement the sqlite database module and yolo-compatible image classification');
check(engineSource.includes('AutoScriptHMACSHA1Hex') && engineSource.includes('AutoScriptHMACSHA256Hex') &&
      engineSource.includes('@"hmac1"') && engineSource.includes('@"hmac256"'),
      'Native engine must dispatch hmacSHA1/hmacSHA256');
check(read('Sources/AutoSDK/AutoScriptSupport.m').includes('kCCHmacAlgSHA1') &&
      read('Sources/AutoSDK/AutoScriptSupport.m').includes('kCCHmacAlgSHA256') &&
      read('Sources/AutoSDK/AutoScriptSupport.m').includes('CCHmac('),
      'AutoScriptSupport must implement HMAC-SHA1/SHA256 with CommonCrypto');
const systemOperationsSource = read('Sources/AutoSDK/AutoSystemOperations.m');
check(engineSource.includes('AutoGetLocationSnapshot') && engineSource.includes('CLLocationManager') &&
      systemOperationsSource.includes('requestLocation') && engineSource.includes('@"locGet"') &&
      systemOperationsSource.includes('kCLAuthorizationStatusDenied') &&
      engineSource.includes('objectForInfoDictionaryKey:@"NSLocationWhenInUseUsageDescription"') &&
      systemOperationsSource.includes('kCLAuthorizationStatusNotDetermined') &&
      systemOperationsSource.includes('locationManagerDidChangeAuthorization') &&
      systemOperationsSource.includes('kCLErrorLocationUnknown') &&
      systemOperationsSource.includes('[request.operation isActive]') &&
      systemOperationsSource.includes('waitWithError:') &&
      systemOperationsSource.includes('stopUpdatingLocation') &&
      systemOperationsSource.includes('NSUnderlyingErrorKey') &&
      !systemOperationsSource.includes('[CLLocationManager locationServicesEnabled]') &&
      engineSource.includes('NSError *locationError = nil') &&
      read('Examples/TemplateApp/App/Info.plist').includes('<key>NSLocationWhenInUseUsageDescription</key>'),
      'Native location queries must await authorization, preserve real errors, bound races and ship a template usage description');
check(engineSource.includes('AutoLoadPersonalVPNManager') &&
      engineSource.includes('loadFromPreferencesWithCompletionHandler') &&
      engineSource.includes('startVPNTunnelAndReturnError') &&
      engineSource.includes('stopVPNTunnel') &&
      engineSource.includes('initWithTimeout:5 cancellation:cancellation') &&
      engineSource.includes('AutoLoadPersonalVPNManager(^BOOL { return [self invokeIsStopped]; }') &&
      engineSource.includes('NSThread.isMainThread') &&
      engineSource.includes('NEVPNErrorConfigurationReadWriteFailed') &&
      engineSource.includes('verify the host entitlement and saved profile') &&
      engineSource.includes('AutoVPNStatusName'),
      'Personal VPN control must load a host-owned configuration with bounded, truthful error handling');
check(systemOperationsSource.includes('systemUptime') && systemOperationsSource.includes('MIN(0.05,') &&
      systemOperationsSource.includes('AutoSDKErrorScriptCancelled') &&
      read('Package.swift').includes('.linkedLibrary("sqlite3")'),
      'System waits must be cancellable and SPM must explicitly link SQLite');
check(extensionPackage.contributes?.menus?.['editor/context']?.some(item =>
        item.command === 'autosdk.runSelection' && item.when.includes('editorHasSelection')) &&
      inspectorSource.includes('selectionRevision') && inspectorSource.includes('requestSelections'),
      'Editor selection runs and selection-scoped Inspector results must remain available');
check(engineSource.includes('AutoSystemSettingsURL') &&
      engineSource.includes('page.length > 32') &&
      engineSource.includes('@"App-prefs:root=General&path=VPN"') &&
      engineSource.includes('UIApplicationOpenSettingsURLString') &&
      engineSource.includes('isEqualToString:@"lowPowerMode"') &&
      engineSource.includes('isEqualToString:@"locationAuthorization"'),
      'System switch helpers must whitelist bounded settings panels and expose reliable public states');
check(read('Package.swift').includes('.linkedFramework("NetworkExtension")') &&
      read('Package.swift').includes('.linkedFramework("CoreLocation")') &&
      podspec.includes("'NetworkExtension'") && podspec.includes("'CoreLocation'"),
      'SPM and CocoaPods must link the VPN and location frameworks used by system helpers');
check(engineSource.includes('base64EncodedStringWithOptions:0') &&
      engineSource.includes('case SQLITE_BLOB'),
      'SQLite BLOB values must round-trip as base64 strings');
check(engineSource.includes('AutoSQLiteNextHandle++') && engineSource.includes('[AutoSQLiteLock lock];') &&
      engineSource.includes('NSMutableDictionary<NSNumber *, NSValue *> *AutoSQLiteHandles') &&
      !engineSource.includes('NSMutableDictionary<NSNumber *, sqlite3 *>'),
      'SQLite handle allocation must be synchronized and C pointers must be boxed for ARC');
check(engineSource.includes('VNClassifyImageRequest') && engineSource.includes('AutoDetectObjects') &&
      !engineSource.includes('VNRecognizeObjectsRequest'),
      'Native engine must classify images through a public on-device Vision request');
check(engineSource.includes('UNUserNotificationCenter.currentNotificationCenter') &&
      engineSource.includes('NSBundle.mainBundle.bundlePath.pathExtension.lowercaseString') &&
      engineSource.includes('@catch (NSException *exception)'),
      'Native notifications must not terminate extension or XCTest processes without an application host');
check(engineSource.includes('AutoSQLiteCloseAll();') && engineSource.includes('AutoWebSocketCloseAll();'),
      'Script stop must close sqlite handles alongside WebSocket connections');
check(engineSource.includes('#import <sqlite3.h>'),
      'Native engine must import the sqlite3 C library');
check(podspec.includes("s.libraries        = 'z', 'sqlite3'"),
      'AutoSDK.podspec must link the sqlite3 library');
check(typeDefinitions.includes('interface AutoSQLiteAPI') && typeDefinitions.includes('interface AutoYoloAPI') &&
      typeDefinitions.includes('declare const sqlite: AutoSQLiteAPI') &&
      typeDefinitions.includes('declare const yolo: AutoYoloAPI') &&
      typeDefinitions.includes('declare function yoloDetect(') &&
      typeDefinitions.includes('detectByFilePath(imagePath: string)'),
      'Type definitions must declare the sqlite and yolo modules');
check(engineSource.includes('fileWriteEnabled = fileReadEnabled &&') &&
      engineSource.includes('@"fileWrite": @(fileWriteEnabled)'),
      'File-write capability must require both file access and file-write permission');
check(engineSource.includes('@"allowSystemControl"') && engineSource.includes('@"systemControl"') &&
      engineSource.includes('AutoSystemURLSchemeAllowed') && engineSource.includes('AutoSystemClipboardByteLimit') &&
      engineSource.includes('isEqualToString:@"openurl"'),
      'System control must be configurable, capability-reported, bounded, and URL schemes validated');
const bootstrapSource = read('Sources/AutoSDK/AutoBootstrapScript.m');
check(bootstrapSource.startsWith('#import "AutoBootstrapScript.h"'),
      'Generated AutoBootstrapScript.m must import its Foundation-backed declaration');
// Decode concatenated ObjC string literals so content checks are immune to chunk splitting.
const bootstrapScript = (() => {
  const bsStart = bootstrapSource.indexOf('return @"');
  const bsTerm = '"})(this);"';
  const bsAt = bsStart >= 0 ? bootstrapSource.indexOf(bsTerm, bsStart) : -1;
  if (bsAt < 0) return '';
  const bsBlock = bootstrapSource.slice(bsStart, bsAt + bsTerm.length);
  return [...bsBlock.matchAll(/@?"((?:\\.|[^"\\])*)"/g)].map(m => JSON.parse('"' + m[1] + '"')).join('');
})();
check(bootstrapScript.includes("dvf('clipboardGet')") && bootstrapScript.includes("_dv('clipboardSet'") &&
      bootstrapScript.includes("dvf('brightnessGet')") && bootstrapScript.includes("_dv('brightnessSet'") &&
      bootstrapScript.includes("dvf('volumeGet')") && bootstrapScript.includes("_dv('vibrate'") &&
      bootstrapScript.includes("_av('openURL'") && bootstrapScript.includes("avf('homescreen')") &&
      bootstrapScript.includes('g.openURL=') && bootstrapScript.includes('homeScreen:avf'),
      'Bootstrap must expose clipboard, brightness, volume, vibration, openURL and home-screen operations with globals');
check(bootstrapScript.includes("keepScreenOn:function(value)") && bootstrapScript.includes("_dv('keepScreenOn'") &&
      bootstrapScript.includes('g.keepScreenOn=deviceApi.keepScreenOn'),
      'Bootstrap must expose device.keepScreenOn and its global alias');
check(bootstrapScript.includes("loadHTML:function(token,html)") && bootstrapScript.includes("_nn('webViewLoadHTML'"),
      'Bootstrap must expose webView.loadHTML');
check(bootstrapScript.includes('function ocrFind(') && bootstrapScript.includes('g.ocr=base.ocr') &&
      bootstrapScript.includes('g.ocrClick=ocrClick') && bootstrapScript.includes('g.ocrText=ocrText'),
      'Bootstrap must expose ocrClick/ocrText convenience helpers and the ocr global');
check(bootstrapScript.includes('function ocrBaidu(') && bootstrapScript.includes('g.ocrBaidu=ocrBaidu') &&
      bootstrapScript.includes('g.ocrBaiduText=ocrBaiduText'),
      'Bootstrap must expose the Baidu OCR convenience wrapper');
check(bootstrapScript.includes("scanCode:function(p){return _nn('scanCode',[String(p||'')]);}") &&
      bootstrapScript.includes('g.scanCode=screenApi.scanCode'),
      'Bootstrap must expose scanCode barcode/QR detection and its global alias');
check(bootstrapScript.includes("wsApi={connect:function(u){return _nn('wsConnect'") &&
      bootstrapScript.includes("poll:function(h){return _nn('wsPoll'") &&
      bootstrapScript.includes("send:function(h,t){return _nn('wsSend'") &&
      bootstrapScript.includes("close:function(h){return _nn('wsClose'") &&
      bootstrapScript.includes('g.ws=wsApi'),
      'Bootstrap must expose the WebSocket client and its global alias');
check(bootstrapScript.includes("sqliteApi={open:function(p){return _nn('sqO'") &&
      bootstrapScript.includes("exec:function(h,s,a){return _nn('sqE'") &&
      bootstrapScript.includes("query:function(h,s,a){return _nn('sqQ'") &&
      bootstrapScript.includes("close:function(h){return _nn('sqC'") &&
      bootstrapScript.includes('g.sqlite=sqliteApi'),
      'Bootstrap must expose the sqlite database module');
check(bootstrapScript.includes("yoloApi={detect:function(p){return _nn('yoloD'") &&
      bootstrapScript.includes('yoloApi.detectByFilePath=yoloApi.detect') &&
      bootstrapScript.includes('g.yolo=yoloApi') && bootstrapScript.includes('g.yoloDetect=yoloApi.detect'),
      'Bootstrap must expose the yolo object-detection module and its global alias');
check(bootstrapScript.includes('function _ff(o,s,sub,d,a)') && bootstrapScript.includes('function _pc(x,y)') &&
      !bootstrapScript.includes("bridge.invokeFile({operation:'imageProcess'"),
      'Bootstrap must route image file/pixel calls through the compact _ff/_pc helpers');
check(bootstrapScript.includes("hmacSHA1:hsh2('hmac1')") &&
      bootstrapScript.includes("hmacSHA256:hsh2('hmac256')") &&
      bootstrapScript.includes('g.hmacSHA1=stringsApi.hmacSHA1') && bootstrapScript.includes('g.hmacSHA256=stringsApi.hmacSHA256'),
      'Bootstrap must expose hmacSHA1/hmacSHA256 and their global aliases');
check(bootstrapScript.includes("var locApi={getLocation:function(t){return _nn('locGet'") &&
      bootstrapScript.includes("isEnabled:dvf('locationServices')") &&
      bootstrapScript.includes("getAuthorizationStatus:dvf('locationAuthorization')") &&
      bootstrapScript.includes("var vpnApi={status:dvf('vpnStatus')") &&
      bootstrapScript.includes("_dv('vpnSet',true,'value')") &&
      bootstrapScript.includes("var systemApi={openSettings:function(p)") &&
      bootstrapScript.includes('g.location=locApi;g.vpn=vpnApi;g.system=systemApi') &&
      bootstrapScript.includes("isLowPowerModeEnabled:dvf('lowPowerMode')"),
      'Bootstrap must expose location, Personal VPN and common system-switch helpers');

check(bootstrapScript.includes('function pCol(c){if(typeof c===\'number\')return c>>>0;') &&
      bootstrapScript.includes('function int2Hex(c){var n=pCol(c);') &&
      bootstrapScript.includes('var colorsApi={parseColor:pCol') &&
      bootstrapScript.includes('g.colors=colorsApi') && bootstrapScript.includes('g.parseColor=pCol') &&
      bootstrapScript.includes('g.int2Hex=int2Hex') && bootstrapScript.includes('g.hex2Int=pCol') &&
      bootstrapScript.includes('g.rgb=colorsApi.rgb') && bootstrapScript.includes('g.argb=colorsApi.argb'),
      'Bootstrap must expose the EasyClick-compatible color tools (parseColor/int2Hex/hex2Int/rgb/argb)');
check(bootstrapScript.includes('function dvf(k){return function(){return _dv(k);};}') &&
      bootstrapScript.includes('g.thread=threadApi') && bootstrapScript.includes('g.utils=utilsApi') &&
      bootstrapScript.includes('g.getPasteboard=') && bootstrapScript.includes('g.setPasteboard=') &&
      bootstrapScript.includes('g.openUrl=') && bootstrapScript.includes('g.uploadToAlbum=') &&
      bootstrapScript.includes('g.childcount=') && bootstrapScript.includes('deviceApi.applist=') &&
      bootstrapScript.includes('deviceApi.getOrientationNoAuto=') && bootstrapScript.includes('deviceApi.getDeviceMsg=') &&
      bootstrapScript.includes('imageApi.captureFullScreen='),
      'Bootstrap must expose EasyClick thread/utils namespaces and global aliases (getPasteboard/openUrl/uploadToAlbum/childcount)');
check(bootstrapScript.includes("stringsApi.atrim=function(s){return SS(s).replace(/\\s+/g,'');};") &&
      bootstrapScript.includes('stringsApi.isInteger=stringsApi.isIntrger;') &&
      bootstrapScript.includes('stringsApi.random=base.randomString;') &&
      bootstrapScript.includes('deviceApi.setBacklightLevel=deviceApi.setBrightness;') &&
      bootstrapScript.includes('deviceApi.backlightLevel=deviceApi.getBrightness;') &&
      bootstrapScript.includes('g.pasteboard={read:deviceApi.getClipboard,write:deviceApi.setClipboard};') &&
      bootstrapScript.includes('g.json={encode:JSON.stringify,decode:function(s){try{return JSON.parse(SS(s));}catch(e){return null;}}};') &&
      bootstrapScript.includes("'isEmail','isLink','atrim','isInteger'].forEach(function(n){g[n]=stringsApi[n];});"),
      'Bootstrap must expose round 59 TrollAutoScript parity aliases (atrim/isInteger/string.random/pasteboard/json/backlight)');
check(bootstrapScript.includes("['getDeviceInfo','getScreenWidth','getScreenHeight','getScale','getModel','getOSVersion','getDeviceName','getBattery','isCharging','getOrientation','getDeviceId','getDeviceAlias','getSerialNo','volumeUp','volumeDown','getMemoryInfo','vibrateLong','vibrateShort'].forEach(function(n){g[n]=deviceApi[n];})"),
      'Bootstrap must export deviceApi shorthand globals');

check(bootstrapScript.includes('function _dv(') && bootstrapScript.includes('function _md(') && bootstrapScript.includes('function _nn('),
      'Bootstrap must define the compact bridge helpers');
check(bootstrapScript.includes('getLanguage:dvf(\'language\')') &&
      bootstrapScript.includes('getUptime:dvf(\'uptime\')') &&
      bootstrapScript.includes("['getAppVersion','getPackageName','getLanguage','getCountry','getLocale','getTimezone','getUptime','getNetworkType','isWifi'].forEach(function(n){g[n]=deviceApi[n];})"),
      'Bootstrap must expose locale/timezone/uptime device getters');
check(bootstrapScript.includes("getNetworkType:dvf('networkType')") &&
      bootstrapScript.includes("isWifi:dvf('isWifi')") &&
      bootstrapScript.includes("['getAppVersion','getPackageName','getLanguage','getCountry','getLocale','getTimezone','getUptime','getNetworkType','isWifi'].forEach(function(n){g[n]=deviceApi[n];})"),
      'Bootstrap must expose network type helpers');
check(bootstrapScript.includes("getFrontmostApp:avf('current')") &&
      bootstrapScript.includes("g.getFrontmostApp=appApi.getFrontmostApp"),
      'Bootstrap must expose app.getFrontmostApp and its global alias');
check(bootstrapScript.includes("getAppScheme:function(name){return _av('getAppScheme'") &&
      bootstrapScript.includes("launchByScheme:function(name){return _av('launchByScheme'") &&
      bootstrapScript.includes("g.getAppScheme=appApi.getAppScheme") && bootstrapScript.includes("g.launchByScheme=appApi.launchByScheme"),
      'Bootstrap must expose app.getAppScheme/launchByScheme and their global aliases');
check(bootstrapScript.includes("setFlashlight:function(on){return _dv('flashlight'") &&
      bootstrapScript.includes("g.torch=deviceApi.setFlashlight") && bootstrapScript.includes("g.flashlight=deviceApi.setFlashlight"),
      'Bootstrap must expose flashlight/torch and their global aliases');
check(bootstrapScript.includes("openSettings:avf('openSettings')") &&
      bootstrapScript.includes("openAppStore:function(appId){return _av('openAppStore'") && bootstrapScript.includes('g.openAppSetting=appApi.openSettings'),
      'Bootstrap must expose openSettings/openAppSetting/openAppStore');
check(bootstrapScript.includes('var speechApi=') && bootstrapScript.includes("_nn('speak',[") &&
      bootstrapScript.includes("_nn('speechStop',[])") && bootstrapScript.includes('g.speak=speechApi.speak'),
      'Bootstrap must expose speak/speechStop and the speech namespace');
check(bootstrapScript.includes("_md('saveImage'") && bootstrapScript.includes("_md('saveImageBase64'") &&
      bootstrapScript.includes("_md('saveVideo'") && bootstrapScript.includes("_md('saveScreenshot'") &&
      bootstrapScript.includes('var mediaApi=') && bootstrapScript.includes('g.media=mediaApi') &&
      bootstrapScript.includes('saveImageToAlbum:function') && bootstrapScript.includes('saveVideoToAlbum:function'),
      'Bootstrap must wire photo-library media operations and aliases');
check(bootstrapScript.includes('var screenDrawApi=') && bootstrapScript.includes('screenDrawInit') &&
      bootstrapScript.includes('var floatBallApi=') && bootstrapScript.includes('floatBallShow') &&
      bootstrapScript.includes('g.screenDraw=screenDrawApi') && bootstrapScript.includes('g.floatBall=floatBallApi') &&
      bootstrapScript.includes('g.setFloatBallPoint=') && bootstrapScript.includes('var nodeApi=') &&
      bootstrapScript.includes('keptNodes') && bootstrapScript.includes('toPinYin:function') &&
      bootstrapScript.includes('stripUtf8Bom:function') && bootstrapScript.includes('fromUnicode:function') &&
      bootstrapScript.includes('nodeApi.at') && bootstrapScript.includes('invokeNodeSnapshot') &&
      bootstrapScript.includes('var floatLogApi=') && bootstrapScript.includes('floatLogShow'),
      'Bootstrap must expose screenDraw, floatBall, node.keep/unkeep, node.at, nodeSnapshot, floatLog and pinyin/BOM/unicode string helpers');
check(engineSource.includes('screenDrawInit') && engineSource.includes('floatBallShow') &&
      engineSource.includes('ensureOverlayWindow') && engineSource.includes('AutoScriptToPinYin') &&
      engineSource.includes('hasPrefix:@"screenDraw"') && engineSource.includes('hasPrefix:@"floatBall"') &&
      engineSource.includes('hasPrefix:@"floatLog"') && engineSource.includes('invokeNodeSnapshot') &&
      engineSource.includes('floatLogTextView') && engineSource.includes('floatLogLines'),
      'Engine must dispatch overlay operations, floatLog and node snapshots to native implementations');
check(read('Sources/AutoSDK/AutoScriptSupport.m').includes('CFStringTransform') &&
      read('Sources/AutoSDK/AutoScriptSupport.m').includes('kCFStringTransformToLatin') &&
      read('Sources/AutoSDK/AutoScriptSupport.m').includes('kCFStringTransformStripCombiningMarks'),
      'toPinYin must use the system Latin transform with combining marks stripped');
check(bootstrapScript.includes('formatDate:function') && bootstrapScript.includes('sleepRandom=function') &&
      bootstrapScript.includes('startWith:function') && bootstrapScript.includes('padZero:function') &&
      bootstrapScript.includes('isInstalled:function') && bootstrapScript.includes('getTotalMemory=function') &&
      bootstrapScript.includes('getLineCount=fileApi.lineCount') && bootstrapScript.includes('g.formatDate=stringsApi.formatDate') &&
      bootstrapScript.includes('g.sleepRandom=base.sleepRandom') && bootstrapScript.includes('g.isInstalled=appApi.isInstalled'),
      'Bootstrap must expose date formatting, sleepRandom, string helpers, isInstalled and memory aliases');
check(engineSource.includes('deviceMemoryInfo') && engineSource.includes('isEqualToString:@"memory"'),
      'Engine must expose device memory information');
check(engineSource.includes('isEqualToString:@"toast"') && engineSource.includes('AutoShowToast'),
      'Engine must provide a built-in toast fallback for unregistered hosts');
check(engineSource.includes('[nativePayload[@"arguments"] isKindOfClass:NSArray.class]'),
      'The built-in toast must parse arguments with a bracketed message send');
check(bootstrapScript.includes('getMemoryInfo:dvf(' + '\'' + 'memory') && bootstrapScript.includes("dvf('memory')") &&
      bootstrapScript.includes('writeLines:function') && bootstrapScript.includes("callFile('move'") &&
      bootstrapScript.includes('rename:function') && bootstrapScript.includes('base.toast=function') &&
      bootstrapScript.includes('base.toastLog=function') && bootstrapScript.includes('g.toast=base.toast'),
      'Bootstrap must expose memory info, file move/rename/writeLines, and toast helpers');
check(read('Sources/AutoSDK/AutoScriptSupport.m').includes('isEqualToString:@"move"') &&
      read('Sources/AutoSDK/AutoScriptSupport.m').includes('Unable to move path.'),
      'Sandbox file operations must support move with overwrite semantics');
check(bootstrapScript.includes('activeTimerCount>=10000') && bootstrapScript.includes("RangeError('Too many active timers')"), 'JavaScript timers must be bounded');
check(bootstrapScript.includes('activeTimers[id]') && bootstrapScript.includes('delete activeTimers[id]'), 'Timers must support cancellation from inside an active interval callback');
check(bootstrapScript.includes('function pushTimer') && bootstrapScript.includes('function popTimer') &&
      !bootstrapScript.includes('timers.sort(') && !bootstrapScript.includes('timers.shift()'),
      'Timer draining must use a bounded priority heap instead of repeated full-array sorting');
check(bootstrapScript.includes('cancelled[id]=true') && bootstrapScript.includes('delete cancelled[timer.id]'), 'Queued timer cancellation must not leak cancellation markers');
check(bootstrapScript.includes('function ensureRunning()') && bootstrapScript.includes('guardMethods(base)') &&
      bootstrapScript.includes('ensureRunning();return _nn(Str(key)'),
      'Script stop must reject subsequent automation and native bridge calls');
check(bootstrapScript.includes('delete g.__bridge;delete g.__console') &&
      engineSource.includes('[drainTimers callWithArguments:@[]]') &&
      !bootstrapScript.includes('evaluateScript:@"__autoDrainTimers();"'),
      'Bootstrap internals and timer draining must not remain user-overridable globals');
check(bootstrapScript.includes('g.randomInt=base.randomInt') &&
      bootstrapScript.includes('if(max==null){max=min;min=0;}') &&
      bootstrapScript.includes("replace(/[^A-Za-z0-9+/=_-]/g,'')") &&
      !bootstrapScript.includes('indexOf(str.charAt(i++))'),
      'Bootstrap random() must accept a single bound and base64 decode must handle unpadded input correctly');
check(engineSource.includes('hasSuffix:@".js"') && engineSource.includes('!containsWhitespace') &&
      engineSource.includes('!containsCodeCharacters'),
      'Path detection must not reject inline source that merely ends in .js');
check(!engineSource.includes('JSContextGroupSetExecutionTimeLimit') &&
      !engineSource.includes('JSContextGroupClearExecutionTimeLimit'),
      'The private JSC execution-time API must not be used; pure-JS loops are cooperative-only');
check(engineSource.includes('__autosdkTruncated') && engineSource.includes('AutoMaxResultNodes'),
      'Script result conversion must be bounded');
check(engineSource.includes('dispatch_source_set_event_handler(watchdog') &&
      engineSource.includes('dispatch_source_cancel(watchdog)'),
      'The script timeout watchdog must be a cancellable one-shot timer, not a blocked thread');
check(!engineSource.includes('[[context.exception toString] toObject]'), 'JavaScript exception formatting must not send toObject to NSString');
check(engineSource.includes('com.autosdk.javascript') && engineSource.includes('AutoMainThreadAdapterProxy'), 'JavaScript execution must stay off the UI thread while UIKit calls are marshalled safely');
check(read('Sources/AutoSDK/include/AutoEngine.h').includes('configureWithConfig:') &&
      read('Sources/AutoSDK/include/AutoEngine.h').includes('objc_method_family(none)') &&
      engineSource.includes('[self configureWithConfig:config]'),
      'Configuration API must avoid treating the legacy void initWithConfig selector as an ARC initializer');
check(engineSource.includes('AutoValidatedHostAllowlist') &&
      engineSource.includes('hasHostAllowlist ? allowedHosts : nil'),
      'HTTP redirects must use a validated allowlist when configured and otherwise follow same-scheme redirects');
const httpSupportSource = read('Sources/AutoSDK/AutoHTTPSupport.m');
check(httpSupportSource.includes('originalScheme') && httpSupportSource.includes('isEqualToString:@"https"'), 'HTTP redirects must reject HTTPS downgrade');
check(read('Sources/AutoSDK/include/AutoHTTPSupport.h').includes('AutoHTTPRedirectRouter') &&
      engineSource.includes('#import "AutoHTTPSupport.h"'),
      'Shared HTTP redirect routing must be imported by the engine');
check(engineSource.includes('AutoHTTPSharedSession(') && engineSource.includes('AutoHTTPSharedRouter()') &&
      engineSource.includes('dispatch_once') && engineSource.includes('defaultSessionConfiguration') &&
      engineSource.includes('configuration.protocolClasses') && engineSource.includes('urlProtocolClasses'),
      'Shared HTTP session must accept injected NSURLProtocol classes via the urlProtocolClasses config key');
check(read('Tests/AutoSDKTests/AutoHTTPProtocolTests.m').includes('mergedConfig[@\"urlProtocolClasses\"]') &&
      read('Tests/AutoSDKTests/AutoHTTPProtocolTests.m').includes('AutoTestHTTPProtocol.class'),
      'HTTP protocol tests must inject their NSURLProtocol class through configuration');
check(engineSource.includes('setPolicy:policy forTask:') && engineSource.includes('removePolicyForTask:'),
      'Per-task redirect policies must be registered before resume and removed after completion');
{
  const sharedStart = engineSource.indexOf('static NSURLSession *AutoHTTPSharedSession');
  const sharedReturn = engineSource.indexOf('return session;', sharedStart);
  const sharedBlock = sharedStart >= 0 && sharedReturn > sharedStart
    ? engineSource.slice(sharedStart, sharedReturn + 15) : '';
  check(sharedBlock.length > 0 && !sharedBlock.includes('invalidateAndCancel') && !sharedBlock.includes('finishTasksAndInvalidate'),
        'The shared HTTP session must never be invalidated per request');
}
check(engineSource.includes('maxHTTPRequestBytes') && engineSource.includes('countOfBytesExpectedToReceive'), 'HTTP request and response memory must be bounded before decoding');
check(engineSource.includes('responseData.length > maximumResponseBytes') &&
      engineSource.includes('countOfBytesExpectedToReceive') && engineSource.includes('countOfBytesReceived'),
      'HTTP response bytes must be bounded during transfer and again before decoding');
check(!engineSource.includes('AutoHTTPDataDelegate') && !engineSource.includes('AutoHTTPRedirectDelegate'),
      'Legacy per-request HTTP delegate classes must be removed in favor of the shared session');
check(engineSource.includes('downloadTaskWithRequest:request') && engineSource.includes('AutoScriptInstallDownloadedFile'), 'HTTP file downloads must bypass in-memory base64 transport');
check(engineSource.includes('[manager removeItemAtURL:stagingURL error:nil]'),
      'Failed HTTP staging copies must remove partial temporary files');
check(engineSource.includes('includeBody') && engineSource.includes('includeBase64') && engineSource.includes('parseJSON'), 'HTTP response representations must be independently optional');
check(engineSource.includes('requestHeaders.count > 128') && engineSource.includes('length] > 8192'), 'HTTP request headers must be bounded');
check(engineSource.includes('responseHeaderBytes') && engineSource.includes('headers.count >= 256'), 'HTTP response header copies must be bounded');
check(engineSource.includes('downloadTaskWithRequest:remoteRequest') && engineSource.includes('NSDataReadingMappedIfSafe'), 'Remote scripts must use a size-monitored temporary download on the shared session');
check(engineSource.includes('cancelBeforeStart = self.stopRequested') && engineSource.includes('self.activeAdapter = runAdapter'), 'Script cancellation and adapter selection must use the active run snapshot');
check(engineSource.includes('[scriptAdapter cancelCurrentOperations]'), 'Script timeouts must cancel active native adapter work');
check(engineSource.includes('executionFinished') &&
      engineSource.includes('if (executionFinished) return;') &&
      engineSource.includes('@synchronized (executionState)') &&
      engineSource.includes('systemUptime >= executionDeadline'),
      'Script timeout completion must not race with cancellation or poison the next run');
check(engineSource.includes('if (!self.running && !self.scriptTask) return;'),
      'Stopping an idle engine must not cancel shared adapter operations');
check((engineSource.match(/if \(!\[self ensureScriptRunning\]\) return @NO;/g) || []).length >= 30,
  'Every Objective-C JavaScript bridge entry point must re-check cancellation');
check(engineSource.includes('valueWithNewErrorFromMessage:@"Script cancelled."'),
  'Native bridge cancellation must abort the current JavaScript evaluation');
check(engineSource.includes('downloadAbandoned') && engineSource.includes('stagedDownloadURL') &&
      engineSource.includes('abandonDownload();'),
  'HTTP downloads must stage before installing and clean up after cancellation');
check(engineSource.includes('debugServerConfiguration') &&
      engineSource.includes('debugServerGeneration') &&
      engineSource.includes('debugServerStartCompletions'),
      'Debug server reconfiguration and concurrent starts must use serialized generation state');
check(engineSource.includes('AutoBoolean') && engineSource.includes('AutoPermission') && engineSource.includes('AutoFiniteDouble') &&
      engineSource.includes('AutoBoundedPositiveInteger'),
      'Script and debug option parsing must reject unsafe Objective-C numeric coercions');
check(engineSource.includes('@"inspectSnapshot"') && engineSource.includes('@"protocolVersion"') && engineSource.includes('@"snapshotId"'), 'Debug protocol must expose a consistent inspector snapshot');
check(engineSource.includes('@"pixelColor"') && engineSource.includes('@"findImage"') && engineSource.includes('AutoDebugTemplateByteLimit'), 'Debug protocol must expose bounded pixel and image tests');
check(engineSource.includes('@"putScript"') && engineSource.includes('@"runStored"') && engineSource.includes('AutoDebugScriptName'), 'Debug protocol must support safe deployed-script management');
check((engineSource.match(/\[name hasPrefix:@"\."\]/g) || []).length >= 2,
      'Deployed script and asset names must reject hidden files omitted by management listings');
check(engineSource.includes('@"nodeAction"') && engineSource.includes('@"scroll"'), 'Debug protocol must support authenticated inspector node actions');
const scriptSupport = read('Sources/AutoSDK/AutoScriptSupport.m');
check(scriptSupport.includes('AutoSupportByteLimit') && scriptSupport.includes('maxFileWriteBytes'), 'File and storage byte limits must have hard maximums');
check(scriptSupport.includes('maxStorageEntries') &&
      scriptSupport.includes('data.length > maximumBytes') &&
      scriptSupport.includes('removeObjectForKey:defaultsKey'),
      'Script storage must bound entries before decoding and remain recoverable when corrupt');
check(bootstrapScript.includes('x1:x1,y1:y1,x2:x2,y2:y2') && bootstrapScript.includes('g.app=appApi'), 'AutoBootstrapScript is missing swipe coordinates or app lifecycle bindings');
const uiKitAdapter = read('Sources/AutoSDK/AutoUIKitAdapter.m');
check(uiKitAdapter.includes('AutoUIKitHandleRegistry') && uiKitAdapter.includes('strongToWeakObjectsMapTable'), 'UIKit node handles must use a weak direct lookup registry');
check(uiKitAdapter.includes('expression ?: NSNull.null') && uiKitAdapter.includes('length] > 1024'), 'UIKit regex cache must retain invalid bounded patterns');
check(uiKitAdapter.includes('depth < 32') && uiKitAdapter.includes('actual.length > 16384') &&
      uiKitAdapter.includes('[(NSString *)color length] > 32'),
      'UIKit selector unwrapping, regex inputs, and color strings must have hard work bounds');
check(uiKitAdapter.includes('AutoUIKitTemplateImage') && uiKitAdapter.includes('totalCostLimit = 32 * 1024 * 1024'), 'UIKit template cache must be bounded');
check(uiKitAdapter.includes('NSMutableArray<NSNumber *> *nextChildIndexes') && uiKitAdapter.includes('AutoUIKitPixelImageMakeRegion'), 'UIKit hierarchy and ROI scans must avoid recursive traversal and full-frame buffers');
check(uiKitAdapter.includes('AutoUIKitMaxFindVisitedViews') && uiKitAdapter.includes('The view hierarchy exceeds the findElement safety limit.'),
      'UIKit single-node lookup must have a bounded view traversal');
check(uiKitAdapter.includes('lookupError.code != AutoSDKErrorElementNotFound'),
      'UIKit exists must suppress only ordinary missing-element errors');
check(uiKitAdapter.includes('expansionTruncated') && uiKitAdapter.includes('visitedCount + views.count >= AutoUIKitMaxFindVisitedViews'),
      'UIKit single-node lookup must bound deep traversal without retaining high-fanout sibling stacks');
check(uiKitAdapter.includes('static UIScrollView *AutoUIKitFindScrollView') &&
      uiKitAdapter.includes('visitedCount < AutoUIKitMaxFindVisitedViews'),
      'UIKit scroll-view fallback lookup must have a bounded traversal');
check(uiKitAdapter.includes('AutoUIKitColorOffset') && uiKitAdapter.includes('AutoUIKitMaxColorOffsets'), 'UIKit multi-color offsets must be precompiled and bounded');
check(uiKitAdapter.includes('AutoUIKitPixelByteCount') && uiKitAdapter.includes('combined pixel-buffer limit'), 'UIKit image matching must bound its combined pixel working set');
check(uiKitAdapter.includes('verifiedCandidates') && uiKitAdapter.includes('alphaWeight'), 'UIKit image matching must bound verification and honor template alpha');
check(uiKitAdapter.includes('capturedImageForOperationGeneration') && uiKitAdapter.includes('screenshotCacheImage'), 'UIKit visual operations must avoid PNG encode/decode round trips');
check(uiKitAdapter.includes('threadSafeCapturedImageForOperationGeneration') && engineSource.includes('backgroundVisualOperation'), 'UIKit image and OCR processing must keep only capture work on the main thread');
check(uiKitAdapter.includes('visualOperationLock') && uiKitAdapter.includes('operationCancellationGeneration') &&
      uiKitAdapter.includes('activeVisionRequests') && uiKitAdapter.includes('AutoUIKitDefaultColorCandidates') &&
      uiKitAdapter.includes('AutoUIKitDefaultColorComparisons'),
      'UIKit visual work, Vision cancellation, and color scans must be serialized and bounded');
check(uiKitAdapter.includes('Double click was cancelled.') &&
      uiKitAdapter.includes('Swipe was cancelled.') &&
      uiKitAdapter.includes('[scrollView.layer removeAllAnimations]') &&
      uiKitAdapter.includes('presentationLayer.bounds.origin'),
      'UIKit composite gestures must stop promptly after cancellation');
check(uiKitAdapter.includes('self.screenshotCacheImage == image') &&
      uiKitAdapter.includes('self.screenshotCacheGeneration == captureGeneration') &&
      uiKitAdapter.includes('operationGeneration != self.operationCancellationGeneration'),
      'UIKit screenshot data must be cached only for the image and cancellation generation that produced it');
check(uiKitAdapter.includes('self.screenshotCacheData = nil;') &&
      uiKitAdapter.includes('Screenshot capture was cancelled.'),
      'UIKit cancellation must invalidate cached frames and reject cancelled capture writeback');
check(uiKitAdapter.includes('AutoUIKitElementInfoWithMetadata') &&
      uiKitAdapter.includes('UIKit node snapshot was cancelled.') &&
      uiKitAdapter.includes('pendingViews.count - 1'),
      'UIKit snapshots must reuse traversal metadata and cooperate with cancellation');
check(uiKitAdapter.includes('AutoUIKitMaxNodeStringLength = 4096') &&
      uiKitAdapter.includes('@"contentTruncated"'),
      'UIKit serialized node descriptors must bound unusually large text fields');
check(uiKitAdapter.includes('requiredRegion') && uiKitAdapter.includes('minimumOffsetX') &&
      uiKitAdapter.includes('multi-color region pixel buffer'),
      'UIKit multi-color matching must allocate only the search ROI plus offset extent');
check(uiKitAdapter.includes('AutoUIKitColorPoint') &&
      uiKitAdapter.includes('color comparison region pixel buffer') &&
      uiKitAdapter.includes('CGRectMake(scaledX, scaledY, 1, 1)'),
      'UIKit point and multi-point color reads must avoid full-frame RGBA buffers');
check(uiKitAdapter.includes('examinedLanguages = MIN((NSUInteger)64') &&
      uiKitAdapter.includes('examinedWords = MIN((NSUInteger)1000'),
      'UIKit OCR option parsing must bound invalid language and custom-word inputs');
check(uiKitAdapter.includes('@"nodeId"') && uiKitAdapter.includes('@"parentId"') && read('Sources/AutoSDK/AutoBuiltinAdapter.m').includes('@"parentHandle"'),
      'Node snapshots must expose hierarchy identifiers');
const debugServerSource = read('Sources/AutoSDK/AutoDebugServer.m');
check(debugServerSource.includes('(void)retainedData') && debugServerSource.includes('dispatch_data_create_concat'), 'Debug transport must retain and concatenate framed data without a full payload copy');
check(debugServerSource.includes('nw_interface_type_cellular') && debugServerSource.includes('nw_interface_type_loopback') && debugServerSource.includes('token.length < 16'), 'Debug transport must restrict and authenticate Wi-Fi listeners');
check(debugServerSource.includes('nw_advertise_descriptor_create_bonjour_service') &&
      debugServerSource.includes('nw_listener_set_advertise_descriptor') &&
      debugServerSource.includes('"_autosdk._tcp"') &&
      engineSource.includes('debugServiceName'),
      'Wi-Fi debug transport must publish a stable AutoSDK Bonjour service without exposing its token');
check(debugServerSource.includes('strongSelf.peers.count < 8') && debugServerSource.includes('acceptedPeer') && debugServerSource.includes('authenticationRejected') && debugServerSource.includes('!strongSelf.authenticated'), 'Debug transport must atomically bound peers and reject unauthenticated connections');
check(debugServerSource.includes('pendingStartCompletion') && debugServerSource.includes('stopped before it became ready'), 'Stopping a starting debug listener must complete its start callback');
check(debugServerSource.includes('failedPeers') && !debugServerSource.includes('if (startCompletion) startCompletion(AutoDebugError(AutoSDKErrorDebugServerFailed, @"Debug listener failed.", AutoNSErrorFromNWError(error)));\n            [strongSelf stop]'), 'A failed listener must not stop a newer reentrant listener');
check(debugServerSource.includes('Debug request timed out.') &&
      debugServerSource.includes('pendingRequests') &&
      debugServerSource.includes('completeRequestWithKey') &&
      debugServerSource.includes('isKindOfClass:NSDictionary.class'),
      'Debug requests must time out once and reject malformed handler responses');
check(debugServerSource.includes('AutoDebugRequestTimeout') &&
      debugServerSource.includes('request[@"timeoutMs"]') &&
      debugServerSource.includes('@"runStored"'),
      'Debug request deadlines must cover one-hour scripts and honor bounded client budgets');
check(scriptSupport.includes('AutoFileOperationLock') && scriptSupport.includes('@synchronized (AutoFileOperationLock())'), 'Sandbox file operations must serialize size checks and mutations');
check(scriptSupport.includes('maxFileCopyBytes') && scriptSupport.includes('maxFileListItems') && scriptSupport.includes('maxFileOperationItems'), 'Sandbox directory operations must have byte and item budgets');
check(scriptSupport.includes('maxFileLineCount') && bootstrapScript.includes("callFile('readLines'"), 'Line reads must be bounded before creating JavaScript strings');
check(scriptSupport.includes('.autosdk-download-') && scriptSupport.includes('removeItemAtURL:staging'), 'Staged copies and downloads must be cleaned up on failure');
check(!read('Examples/TemplateApp/App/AppDelegate.m').includes('debug token: %@'), 'Template must not write the complete debug token to the system log');
check(!read('Examples/TemplateApp/README.md').includes('debug token: %@') && !read('Examples/TemplateApp/README.md').includes('per-launch token'), 'Template documentation must not recommend logging or rotating the installation token every launch');
check(!read('docs/DEBUG_PROTOCOL.md').includes('debug token: %@'), 'Debug protocol documentation must not recommend logging the complete token');
check(templatePlist.includes('NSLocalNetworkUsageDescription') && templatePlist.includes('AutoSDKDebugAllowWiFi'), 'Template must declare and configure local-network debugging');
check(templatePlist.includes('CFBundleDocumentTypes') && templatePlist.includes('LSSupportsOpeningDocumentsInPlace') &&
      templatePlist.includes('public.javascript') && templatePlist.includes('UTImportedTypeDeclarations'),
      'Template must declare JS/text document types so Files can open scripts in the app');
const listSource = read('Examples/TemplateApp/App/ScriptListViewController.m');
check(listSource.includes('#import "ScriptEditorViewController.h"') && listSource.includes('#import "SettingsViewController.h"') &&
      listSource.includes('#import "AutoTemplateSettings.h"') && listSource.includes('#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>'),
      'Script list must import the editor, settings, and template configuration headers');
check(listSource.includes('UIDocumentPickerViewController') && listSource.includes('initForOpeningContentTypes:') &&
      listSource.includes('UIActivityViewController') && listSource.includes('renameDeployedScriptNamed:') && listSource.includes('toName:') &&
      listSource.includes('deployedScriptContentNamed:') && listSource.includes('AutoSDKScriptsChanged'),
      'Script list must support import, export, rename, and refresh-on-change');
check(!listSource.includes('AutoTemplateWiFiIPv4Address'), 'Wi-Fi address lookup must live in AutoTemplateSettings, not the list controller');
const editorSource = read('Examples/TemplateApp/App/ScriptEditorViewController.m');
check(editorSource.includes('saveDeployedScriptNamed:name script:') && editorSource.includes('initWithScriptName:') &&
      editorSource.includes('onSaved') && editorSource.includes('keyboardWillChange:'),
      'Script editor must save deployed scripts, run, and avoid the keyboard');
const settingsSource = read('Examples/TemplateApp/App/SettingsViewController.m');
check(settingsSource.includes('AutoSDKVersionString') && settingsSource.includes('applyEngineConfiguration') &&
      settingsSource.includes('wifiToggled:') && settingsSource.includes('builtinToggled:'),
      'Settings must show the SDK version and re-apply adapter configuration');
const templateSettingsSource = read('Examples/TemplateApp/App/AutoTemplateSettings.m');
check(templateSettingsSource.includes('makeAutomationAdapter') && templateSettingsSource.includes('applyEngineConfiguration') &&
      templateSettingsSource.includes('wifiIPv4Address') && !templateSettingsSource.includes('registerNativeMethod:@"toast"'),
      'Template configuration must build adapters and rely on the engine built-in toast');
const builtinAdapterSource = read('Sources/AutoSDK/AutoBuiltinAdapter.m');
const resourcePolicySource = read('Sources/AutoSDK/AutoResourcePolicy.m');
const backgroundLeaseSource = read('Sources/AutoSDK/AutoBackgroundLease.m');
check(resourcePolicySource.includes('AutoUsesLowMemoryProfile') &&
      resourcePolicySource.includes('width <= budget / 4') &&
      resourcePolicySource.indexOf('CGImageSourceCopyPropertiesAtIndex') < resourcePolicySource.indexOf('CGImageSourceCreateImageAtIndex') &&
      resourcePolicySource.includes('visited++') && resourcePolicySource.includes('maxNodes - visited') &&
      resourcePolicySource.includes('truncated && filter') && !builtinAdapterSource.includes('walkBlock'),
      'Low-memory image preflight and iterative node traversal must bound visits, pending nodes and incomplete filtered searches');
check(builtinAdapterSource.includes('performVisualOperation:') && builtinAdapterSource.includes('[self.visualLock tryLock]') &&
      builtinAdapterSource.includes('generation == self.cancellationGeneration') &&
      builtinAdapterSource.includes('cleanup(AutoBuiltinBitmapFree)') && builtinAdapterSource.includes('comparisonBudget'),
      'Built-in visual work must reject concurrent capture, discard cancelled cache commits and release bounded buffers');
check(backgroundLeaseSource.includes('if (self.closed) return') && backgroundLeaseSource.includes('alreadyClosed') &&
      engineSource.includes('requestStopForRun:identifier') && engineSource.includes('activeRunIdentifier isEqual:identifier') &&
      engineSource.includes('UIApplicationDidReceiveMemoryWarningNotification') &&
      engineSource.includes('NSProcessInfoThermalStateSerious') && engineSource.includes('bounded[@"maxLogBytes"]') &&
      templateSettingsSource.includes('lowMemory ? 1500') && settingsSource.includes('低内存保护已自动启用'),
      'Finite background leases, resource-pressure stops and low-memory template defaults must stay wired');
check(existsSync(resolve(root, 'Tests/AutoSDKTests/AutoResourcePolicyTests.m')) &&
      existsSync(resolve(root, 'Tests/AutoSDKTests/AutoLowMemoryLifecycleTests.m')),
      'Resource policy and lifecycle regressions must remain covered by native tests');
check(builtinAdapterSource.includes('IOHIDEventSystemClientCreate') &&
      builtinAdapterSource.includes('IOHIDEventCreateDigitizerEvent') &&
      builtinAdapterSource.includes('IOHIDEventSystemClientDispatchEvent') &&
      builtinAdapterSource.includes('AXUIElementCreateSystemWide') &&
      builtinAdapterSource.includes('LSApplicationWorkspace') &&
      builtinAdapterSource.includes('SBSLockDevice') &&
      builtinAdapterSource.includes('BKSTerminateApplication') &&
      builtinAdapterSource.includes('@"scope": @"systemWide"') &&
      !builtinAdapterSource.includes('#import <Accessibility/') &&
      !builtinAdapterSource.includes('#import <IOKit/'),
      'Built-in no-WDA adapter must resolve IOHID/Accessibility/SpringBoard symbols at runtime without linking private frameworks');
check(!builtinAdapterSource.includes('NSArray<AutoAXElementRef>') &&
      builtinAdapterSource.includes('(__bridge NSArray *)frameValue') &&
      builtinAdapterSource.includes('(__bridge CFTypeRef)children[childIndex]') &&
      !builtinAdapterSource.includes('![descriptor[@"type"] caseInsensitiveCompare:type]'),
      'Built-in Accessibility traversal must use ARC-safe CF bridges and an unambiguous type comparison');
check(builtinAdapterSource.includes('AutoBuiltinMaxImageComparisons') &&
      builtinAdapterSource.includes('@"findImage": @YES'),
      'Built-in adapter must implement bounded template image matching and report the capability');
check(builtinAdapterSource.includes('AutoBuiltinBundleIdForAppName') &&
      builtinAdapterSource.includes('com.tencent.xin'),
      'Built-in adapter must resolve popular app names to bundle ids (AScript app_start parity)');
check(builtinAdapterSource.includes('screenPNGWithOptions:') &&
      uiKitAdapter.includes('screenImageHonoringCachedPath:') &&
      engineSource.includes('AutoEngineScreenPNG') &&
      engineSource.includes('cachedScreenPath'),
      'Screen cache screenshotPath must be honored by builtin/UIKit adapters and findColorEx/findNotColor scans');
check(bootstrapScript.includes('bridge.invokeFindColorEx(cachedOptions(') &&
      bootstrapScript.includes('bridge.invokeFindNotColor(cachedOptions(') &&
      bootstrapScript.includes('g.waitFor=base.waitFor') &&
      bootstrapScript.includes('g.currentPackage=') &&
      bootstrapScript.includes('g.setClip=deviceApi.setClipboard') &&
      bootstrapScript.includes('g.getClip=deviceApi.getClipboard'),
      'Bootstrap must wire the screenshot cache into findColorEx/findNotColor and expose waitFor/currentPackage/setClip/getClip globals');
check(engineSource.includes('AutoSQLiteMaxRows') &&
      engineSource.includes('rows.count < AutoSQLiteMaxRows') &&
      engineSource.includes('sqlite accepts one statement per call'),
      'SQLite query rows must be bounded and multi-statement SQL must be rejected explicitly');
check(engineSource.includes('AutoHTTPFieldNameIsValid') &&
      engineSource.includes('Upload file names must not contain quotes or control characters'),
      'Multipart field and file names must be validated against header injection');
check(bootstrapScript.includes("httpApi.put=hv('PUT',1)") &&
      bootstrapScript.includes("httpApi.delete=hv('DELETE')") &&
      bootstrapScript.includes("httpApi.head=hv('HEAD')") &&
      bootstrapScript.includes("httpApi.patch=hv('PATCH',1)") &&
      bootstrapScript.includes('httpApi.requestEx=httpApi;') &&
      bootstrapScript.includes('function hv(m,b){') &&
      bootstrapScript.includes('body.files||body.formData'),
      'Bootstrap http module must expose put/delete/head/patch/requestEx via the shared verb helper');
check(bootstrapScript.includes('base.ocr.newOcr=function(d){'),
      'Bootstrap ocr module must expose the newOcr engine-instance factory');
check(bootstrapScript.includes('function bp(b){return b&&b.path||b;}') &&
      bootstrapScript.includes('readBitmap:bh') &&
      bootstrapScript.includes('base64Bitmap:function(x,p)'),
      'Bootstrap image module must expose the path-handle bitmap model helpers');
check(bootstrapScript.includes('fileApi.readFile=fileApi.readText') &&
      bootstrapScript.includes('deviceApi.getDeviceInfo=deviceApi.info'),
      'EasyClick file/device aliases must be rebuilt after guarding to stay in budget');
check(builtinAdapterSource.includes('AutoBuiltinXPathToQuery') &&
      builtinAdapterSource.includes('AutoBuiltinSplitXPathConditions') &&
      builtinAdapterSource.includes('"xpathSubset"') &&
      builtinAdapterSource.includes('Built-in xpath subset supports a single //Type step only'),
      'Built-in adapter must translate the bounded xpath subset into native query keys');
check(read('Sources/AutoSDK/include/AutoSDK.h').includes('#import "AutoBuiltinAdapter.h"') &&
      templateSettingsSource.includes('AutoBuiltinAdapter *adapter = [AutoBuiltinAdapter new]') &&
      !templateSettingsSource.includes('AutoWDAHTTPAdapter') &&
      !read('Sources/AutoSDK/include/AutoSDK.h').includes('AutoWDAHTTPAdapter'),
      'Built-in no-WDA adapter must be the default template adapter with no WDA remnants');
const engineHeader = read('Sources/AutoSDK/include/AutoEngine.h');
check(engineHeader.includes('saveDeployedScriptNamed:') && engineHeader.includes('deployedScriptContentNamed:') &&
      engineHeader.includes('renameDeployedScriptNamed:'), 'Engine must expose deployed-script save/read/rename APIs');
const appDelegateSource = read('Examples/TemplateApp/App/AppDelegate.m');
check(appDelegateSource.includes('openURL:') && appDelegateSource.includes('options:') && appDelegateSource.includes('saveDeployedScriptNamed:'),
      'AppDelegate must import opened JS files into the deployed-scripts sandbox');
const bootstrapStart = bootstrapSource.indexOf('NSString *AutoBootstrapScript(void) {');
const bootstrapReturn = bootstrapSource.indexOf('return @"', bootstrapStart);
const bootstrapTerminator = '"})(this);"';
const bootstrapTerminatorAt = bootstrapSource.indexOf(bootstrapTerminator, bootstrapReturn);
const bootstrapEnd = bootstrapTerminatorAt >= 0 ? bootstrapTerminatorAt + bootstrapTerminator.length : -1;
check(bootstrapStart >= 0 && bootstrapReturn >= 0 && bootstrapEnd >= 0, 'Unable to locate AutoBootstrapScript');
if (bootstrapReturn >= 0 && bootstrapEnd >= 0) {
  const bootstrapBlock = bootstrapSource.slice(bootstrapReturn, bootstrapEnd);
  const literals = [...bootstrapBlock.matchAll(/@?"((?:\\.|[^"\\])*)"/g)];
  try {
    const script = literals.map(match => JSON.parse(`"${match[1]}"`)).join('');
    check(script.length <= 60 * 1024, 'AutoBootstrapScript must stay under the 64 KiB JavaScriptCore literal budget');
    const canonicalSource = read('tools/bootstrap-source.js').replace(/^\uFEFF/, '').replace(/\r\n/g, '\n');
    check(script === canonicalSource, 'AutoBootstrapScript.m must match tools/bootstrap-source.js; run npm run regenerate:bootstrap');
    const compiledBootstrap = new vm.Script(script, { filename: 'AutoBootstrapScript.js' });
    check(script.includes('g.auto='), 'AutoBootstrapScript does not install the auto global');
    let stopped = false;
    let lastHTTPOptions;
    let lastOCROptions;
    let lastDeviceOperation;
    let lastAppOperation;
    let lastMediaOperation;
    let lastFileOperation;
    const context = vm.createContext({
      __bridge: new Proxy({}, { get: (_, key) => {
        if (key === 'invokeIsStopped') return () => stopped;
        if (key === 'invokeHTTP') return value => { lastHTTPOptions = value; return {}; };
        if (key === 'invokeOCR') return value => { lastOCROptions = value; return []; };
        if (key === 'invokeFile') return value => { lastFileOperation = value; if (value.operation === 'readLines') return ['first', 'second']; if (value.operation === 'list') return [{ name: 'a.txt', path: '/sandbox/a.txt', isDirectory: false }]; return true; };
        if (key === 'invokeDevice') return value => { lastDeviceOperation = value; return value.operation === 'info' ? { model: 'test' } : true; };
        if (key === 'invokeApp') return value => { lastAppOperation = value; return true; };
        if (key === 'invokeMedia') return value => { lastMediaOperation = value; return true; };
        return () => false;
      } }),
      __console: { log() {}, warn() {}, error() {} }
    });
    const drainTimers = compiledBootstrap.runInContext(context);
    check(typeof drainTimers === 'function' && context.__bridge === undefined &&
          context.__console === undefined && context.__autoDrainTimers === undefined,
          'Bootstrap must return a private timer drain and remove native bridge globals');
    check(context.auto?.http === context.http && context.http?.request === context.http,
          'HTTP callable aliases must retain their documented function identity');
    check(context.http?.get === context.http?.httpGet && context.http?.get === context.http?.httpGetDefault,
          'HTTP GET aliases must retain their function identity');
    check(context.http?.post === context.http?.httpPost && context.http?.post === context.http?.postJSON,
          'HTTP POST aliases must retain their function identity');
    check(context.http?.downloadFile === context.http?.downloadFileDefault,
          'HTTP download aliases must retain their function identity');
    check(context.http?.requestEx === context.http &&
          typeof context.http?.head === 'function' && typeof context.http?.patch === 'function',
          'HTTP requestEx/head/patch must be exposed on the http facade');
    context.http.head('https://example.invalid');
    check(lastHTTPOptions?.method === 'HEAD', 'http.head must issue HEAD requests');
    context.http.patch('https://example.invalid', { a: 1 });
    check(lastHTTPOptions?.method === 'PATCH' && lastHTTPOptions?.body?.a === 1,
          'http.patch must issue PATCH requests with a body');
    const ocrInstance = context.ocr.newOcr({ language: 'zh' });
    ocrInstance.ocrImage('shots/ocr.png');
    check(lastOCROptions?.screenshotPath === 'shots/ocr.png' && lastOCROptions?.language === 'zh',
          'ocr.newOcr instances must merge defaults and OCR image files via screenshotPath');
    check(context.file?.readFile === context.file?.readText &&
          context.device?.getDeviceInfo === context.device?.info,
          'File and device aliases must keep their documented function identity');
    const bitmapHandle = context.image.readBitmap('/sandbox/a.png');
    check(bitmapHandle?.path === '/sandbox/a.png' && bitmapHandle?.isBitmap === true,
          'image.readBitmap must return a path-handle bitmap object');
    context.image.bitmapBase64(bitmapHandle);
    check(lastFileOperation?.operation === 'readBase64' && lastFileOperation?.path === '/sandbox/a.png',
          'image.bitmapBase64 must unwrap handles to their sandbox path');
    context.image.base64Bitmap('QUFBQ==', '/sandbox/b.png');
    check(lastFileOperation?.operation === 'writeBase64' && lastFileOperation?.path === '/sandbox/b.png',
          'image.base64Bitmap must write base64 data and return a handle');
    context.image.saveBitmap(bitmapHandle, '/sandbox/c.png');
    check(lastFileOperation?.operation === 'copy' && lastFileOperation?.destination === '/sandbox/c.png',
          'image.saveBitmap must copy the handle path to the destination');
    context.image.getBitmapPixelColor(bitmapHandle, 1, 2);
    check(lastFileOperation?.operation === 'imagePixelAt' && lastFileOperation?.path === '/sandbox/a.png' &&
          lastFileOperation?.args?.x === 1 && lastFileOperation?.args?.y === 2,
          'image.getBitmapPixelColor must route through imagePixelAt with unwrapped path');
    check(context.auto?.storage === context.storages?.create,
          'Storage factory aliases must retain their function identity');
    check(context.http?.length === 2 && context.http?.get?.length === 2 &&
          context.auto?.click?.length === 1 && context.file?.readFile?.length === 1,
          'Guard wrappers must preserve public function arity');
    const options = { headers: { accept: 'application/json' } };
    context.http.get('https://example.invalid', options);
    check(options.method === undefined && lastHTTPOptions?.method === 'GET',
          'HTTP convenience methods must not mutate caller options');
    context.http.get('https://example.invalid?existing=1', { params: { b: 2 }, cookies: { sid: 'x' }, files: { shot: 'a.png' }, formData: { note: 'hi' } });
    check(lastHTTPOptions?.url === 'https://example.invalid?existing=1&b=2',
          'HTTP params must merge into the query string without clobbering existing parameters');
    check(lastHTTPOptions?.cookies?.sid === 'x' && lastHTTPOptions?.files?.shot === 'a.png' &&
          lastHTTPOptions?.formData?.note === 'hi',
          'HTTP cookies, files and formData must be forwarded through invokeHTTP');
    context.http.get('https://example.invalid', { params: { a: 1 } });
    check(lastHTTPOptions?.url === 'https://example.invalid?a=1',
          'HTTP params must append a clean query string when the URL has none');
    const detachedReadAllLines = context.file.readAllLines;
    const detachedDeviceInfo = context.device.getDeviceInfo;
    check(detachedReadAllLines('test.txt').length === 2 && detachedDeviceInfo().model === 'test',
          'Public file and device methods must remain callable when extracted');
    context.device.setClipboard('hello');
    check(lastDeviceOperation?.operation === 'clipboardSet' && lastDeviceOperation?.text === 'hello',
          'device.setClipboard must forward the clipboardSet operation with text');
    context.device.setBrightness(0.5);
    check(lastDeviceOperation?.operation === 'brightnessSet' && lastDeviceOperation?.value === 0.5,
          'device.setBrightness must forward the brightnessSet operation with a value');
    context.device.vibrate(300);
    check(lastDeviceOperation?.operation === 'vibrate' && lastDeviceOperation?.duration === 300,
          'device.vibrate must forward the advisory duration');
    context.app.homeScreen();
    check(lastAppOperation?.operation === 'homescreen', 'app.homeScreen must forward the homescreen operation');
    context.app.lock();
    check(lastAppOperation?.operation === 'lock', 'app.lock must forward the lock operation');
    context.app.unlock();
    check(lastAppOperation?.operation === 'unlock', 'app.unlock must forward the unlock operation');
    context.openURL('https://example.com');
    check(lastAppOperation?.operation === 'openURL' && lastAppOperation?.url === 'https://example.com',
          'openURL must forward the url through invokeApp');
    context.media.saveImage('shots/a.png');
    check(lastMediaOperation?.operation === 'saveImage' && lastMediaOperation?.path === 'shots/a.png',
          'media.saveImage must forward the saveImage operation with a path');
    context.media.saveImageBase64('QUFBQQ==');
    check(lastMediaOperation?.operation === 'saveImageBase64' && lastMediaOperation?.base64 === 'QUFBQQ==',
          'media.saveImageBase64 must forward base64 image data');
    context.media.saveVideo('videos/a.mp4');
    check(lastMediaOperation?.operation === 'saveVideo' && lastMediaOperation?.path === 'videos/a.mp4',
          'media.saveVideo must forward the saveVideo operation with a path');
    context.media.saveScreenshot();
    check(lastMediaOperation?.operation === 'saveScreenshot', 'media.saveScreenshot must forward the saveScreenshot operation');
    check(typeof context.media?.saveImage === 'function' && typeof context.media?.saveScreenshot === 'function' &&
          typeof context.auto?.saveImageToAlbum === 'function' && typeof context.auto?.saveScreenshotToAlbum === 'function' &&
          typeof context.saveImageToAlbum === 'function' && typeof context.saveScreenshotToAlbum === 'function' &&
          typeof context.image?.saveToAlbum === 'function' && typeof context.image?.saveScreenshotToAlbum === 'function',
          'Media methods must be exposed on media, auto, image, and as globals');
    check(typeof context.device?.getClipboard === 'function' && typeof context.device?.getBrightness === 'function' &&
          typeof context.device?.getVolume === 'function' && typeof context.getClipboard === 'function' &&
          typeof context.getBrightness === 'function' && typeof context.vibrate === 'function',
          'System control aliases must be exposed on device and as globals');
    context.device.getMemoryInfo();
    check(lastDeviceOperation?.operation === 'memory', 'device.getMemoryInfo must forward the memory operation');
    check(typeof context.device?.vibrateLong === 'function' && typeof context.device?.vibrateShort === 'function' &&
          typeof context.vibrateLong === 'function' && typeof context.vibrateShort === 'function',
          'Vibration aliases must be exposed on device and as globals');
    context.vibrateLong();
    check(lastDeviceOperation?.operation === 'vibrate' && lastDeviceOperation?.duration === 500,
          'vibrateLong must forward a 500ms vibrate operation');
    context.vibrateShort();
    check(lastDeviceOperation?.operation === 'vibrate' && lastDeviceOperation?.duration === 50,
          'vibrateShort must forward a 50ms vibrate operation');
    const removedEntries = context.file.deleteAllFile('/sandbox');
    check(removedEntries === 1 && lastFileOperation?.operation === 'remove' && lastFileOperation?.path === '/sandbox/a.txt',
          'file.deleteAllFile must recursively remove every listed directory entry');
    const matchSelector = context.selector().idMatch('cell-1').typeMatch('Button').textMatch('^OK$').nameMatch('Save').labelMatch('OK').valueMatch('v1');
    check(matchSelector._q.idMatch === 'cell-1' && matchSelector._q.typeMatch === 'Button' && matchSelector._q.textMatch === '^OK$' &&
          matchSelector._q.nameMatch === 'Save' && matchSelector._q.labelMatch === 'OK' && matchSelector._q.valueMatch === 'v1',
          'Selector match aliases must fill the regex query fields');
    check(context.selector().textContains('a.b')._q.textMatch === '.*a' + '\\' + '.' + 'b.*',
          'Selector contains helpers must escape regex metacharacters');
    context.file.writeLines('demo/lines.txt', ['one', 'two']);
    check(typeof context.file?.move === 'function' && typeof context.file?.rename === 'function' &&
          typeof context.file?.writeLines === 'function',
          'File API must expose writeLines, move and rename');
    context.toast('hello');
    check(typeof context.toastLog === 'function' && typeof context.toast === 'function' &&
          typeof context.auto?.toast === 'function' && typeof context.auto?.toastLog === 'function',
          'toast and toastLog must be exposed on auto and as globals');
    let firedTimers = 0;
    for (let index = 0; index < 1000; index += 1) context.setTimeout(() => { firedTimers += 1; }, 0);
    const cancelledTimer = context.setTimeout(() => { firedTimers = -100000; }, 0);
    context.clearTimeout(cancelledTimer);
    drainTimers();
    check(firedTimers === 1000, 'Timer heap must execute due timers once and skip cancelled timers');
    stopped = true;
    let cancelledTimerCall = false;
    try { context.clearTimeout(1); } catch (_) { cancelledTimerCall = true; }
    check(cancelledTimerCall, 'Timer cancellation APIs must cooperate with script stop requests');
  } catch (error) {
    failures.push(`AutoBootstrapScript: ${error.message}`);
  }
}

const workflow = read('.github/workflows/ios-build.yml');
for (const requiredText of ['workflow_dispatch:', 'requestId:', 'runs-on: macos-15', 'xcodebuild test', 'CODE_SIGNING_ALLOWED=NO', 'actions/upload-artifact@v7']) {
  check(workflow.includes(requiredText), `.github/workflows/ios-build.yml is missing ${requiredText}`);
}
check(extensionSource.includes('testConnection({ showFailure: false })') &&
      extensionSource.includes('runErrorActions(error)') &&
      connectionRecoverySource.includes('REENTER_TOKEN') &&
      connectionRecoverySource.includes('RETRY_CONNECTION') &&
      connectionRecoverySource.includes('SCAN_WIFI_DEVICE'),
      'Wi-Fi add and one-click run must expose in-place connection recovery');
check(workflow.includes("github.event_name == 'workflow_dispatch' && (inputs.requestId || github.run_id) || github.ref"),
      'Concurrent remote build requests must not cancel each other');
check(workflow.includes('@vscode/vsce package') && workflow.includes(`autosdk-vscode-${extensionPackage.version}.vsix`) &&
      workflow.includes('upload-pages-artifact@v5') && workflow.includes('deploy-pages@v5'),
      'CI must package the VS Code extension and deploy docs to GitHub Pages');
check(workflow.includes('id: ios_tests') &&
      (workflow.match(/steps\.ios_tests\.outcome == 'failure'/g) || []).length === 2 &&
      workflow.includes('No xcresult bundle was produced.') &&
      workflow.includes('legacy_object=(object --legacy)') &&
      workflow.includes('xcresulttool get "${legacy_object[@]}"') &&
      workflow.includes('xcresulttool export "${legacy_object[@]}"') &&
      workflow.includes('| unique | .[:200][]') &&
      workflow.includes("sort | sed -n '1,20p'") &&
      !workflow.includes('| head -'),
      'iOS test diagnostics must be scoped, Xcode-compatible and safe under pipefail');
check(!workflow.includes('actions/upload-artifact@v5') &&
      !workflow.includes('actions/upload-pages-artifact@v3') &&
      !workflow.includes('actions/deploy-pages@v4') &&
      !workflow.includes('runs-on: macos-14'),
      'CI must use Node 24 artifact actions and a supported macOS runner');
const templateProject = read('Examples/TemplateApp/project.yml');
check(templateProject.includes('AutoSDKTests:') && templateProject.includes('bundle.unit-test'), 'Template XcodeGen project must include the XCTest target');
check(!/^\t/m.test(workflow), '.github/workflows/ios-build.yml contains tab indentation');

check(read('Examples/TemplateApp/App/Info.plist').includes('NSPhotoLibraryAddUsageDescription'),
      'Template Info.plist must declare NSPhotoLibraryAddUsageDescription');
check(read('Package.swift').includes('.linkedFramework("Photos")') &&
      read('AutoSDK.podspec').includes("'Photos'"),
      'Package manifests must link the Photos framework');
check(typeDefinitions.includes('interface AutoMediaAPI') &&
      typeDefinitions.includes('saveImageBase64(base64: string): boolean') &&
      typeDefinitions.includes('saveScreenshotToAlbum(): boolean'),
      'Type definitions must describe the photo-library media API');

check(read('LICENSE').includes('AUTOSDK SOFTWARE LICENSE'), 'Root LICENSE file must describe the commercial SDK license');
check(read('vscode-extension/LICENSE.txt').includes('AUTOSDK SOFTWARE LICENSE'),
      'Extension license must reference the repository root license');
check(developerDocs.includes('AutoSDK 开发文档'),
      'docs/index.html must remain the canonical GitHub Pages developer site');
check(read('Sources/AutoSDK/AutoBootstrapScript.m').includes('bridge.invokeTouch({fingers:normalized})') &&
      bootstrapScript.includes('base.gesture=function(actions)') &&
      bootstrapScript.includes('base.multiGesture=function(fingers)') &&
      bootstrapScript.includes('base.pinch=function(x,y,scale,duration)') &&
      bootstrapScript.includes('g.pinch=base.pinch'),
      'Bootstrap must expose gesture, multiGesture and pinch on auto and as globals');
check(bootstrapScript.includes('base.touchDown=function(x,y,i)') &&
      bootstrapScript.includes('base.touchMove=function(x,y,i)') &&
      bootstrapScript.includes('base.touchUp=function(i)') &&
      bootstrapScript.includes('g.touchUp=base.touchUp'),
      'Bootstrap must expose EasyClick-style touchDown/touchMove/touchUp primitives');
check(bootstrapScript.includes("if(!normalized[t].length)throw new Error('gesture finger track must contain at least one action.')"),
      'Bootstrap gesture must reject empty finger tracks');
check(typeDefinitions.includes('interface AutoGestureAPI') &&
      typeDefinitions.includes('gesture(actions: AutoGestureAction[]): boolean') &&
      typeDefinitions.includes('pinch(x: number, y: number, scale: number, durationMs?: number): boolean') &&
      typeDefinitions.includes('declare function gesture('),
      'Type definitions must describe the multi-touch gesture API');
check(read('Sources/AutoSDK/include/AutoAutomationAdapter.h').includes('performMultiTouch:'),
      'Adapter protocol must declare performMultiTouch');
check(builtinAdapterSource.includes('performMultiTouch:') && builtinAdapterSource.includes('@"multiTouch": @(touchReady)'),
      'Built-in no-WDA adapter must implement multi-touch gestures and report the capability');
check(bootstrapScript.includes('base.md5=function(s)') &&
      bootstrapScript.includes('base.sha1=function(s)') &&
      bootstrapScript.includes("callFile('imageSize'") &&
      bootstrapScript.includes("callFile('md5File'") &&
      bootstrapScript.includes("callFile('sha1File'") &&
      bootstrapScript.includes('getSize:function(p){return fileApi.imageSize(bp(p));}') &&
      bootstrapScript.includes('g.md5=base.md5'),
      'Bootstrap must expose string hashes, file image size and file hashes');
check(bootstrapScript.includes('deleteAllFile:function(p){if(!fileApi.exists(p))return 0;if(fileApi.isFile(p))return fileApi.remove(p)?1:0;') &&
      bootstrapScript.includes('if(e.isDirectory)n+=fileApi.deleteAllFile(e.path);') &&
      bootstrapScript.includes('base.node=nodeApi;') &&
      bootstrapScript.includes('base.screen=screenApi;base.floatLog=floatLogApi;') &&
      bootstrapScript.includes("deviceApi.vibrateLong=function(){return deviceApi.vibrate(500);}") &&
      bootstrapScript.includes("deviceApi.vibrateShort=function(){return deviceApi.vibrate(50);}") &&
      bootstrapScript.includes("'vibrateLong','vibrateShort'].forEach") &&
      bootstrapScript.includes('var clog=function(){consoleBridge.log(formatLog(arguments));};') &&
      bootstrapScript.includes('findColors:cmpC,isColors:cmpC,cmpColor:cmpC,') &&
      bootstrapScript.includes('fileApi.readFile=fileApi.readText;') &&
      bootstrapScript.includes('fileApi.writeFile=fileApi.writeText;') &&
      bootstrapScript.includes("lines.join('\\n')") &&
      !bootstrapScript.includes('String.fromCharCode(10)'),
      'Bootstrap must keep EasyClick deleteAllFile semantics, vibration aliases and compact file aliases');
check(typeDefinitions.includes('deleteAllFile(path: string): number') &&
      typeDefinitions.includes('vibrateLong(): boolean') &&
      typeDefinitions.includes('vibrateShort(): boolean'),
      'Type definitions must describe deleteAllFile count result and vibration aliases');
check(bootstrapScript.includes("function ss(k){return function(v){return this.set(k,Str(v));};}") &&
      bootstrapScript.includes("function sx(k){return function(v){return this.set(k,'.*'+regEscape(v)+'.*');};}") &&
      bootstrapScript.includes("Selector.prototype.idMatch=ss('idMatch');") &&
      bootstrapScript.includes("Selector.prototype.typeMatch=ss('typeMatch');") &&
      bootstrapScript.includes("Selector.prototype.textMatch=ss('textMatch');") &&
      bootstrapScript.includes("Selector.prototype.nameMatch=ss('nameMatch');") &&
      bootstrapScript.includes("Selector.prototype.labelMatch=ss('labelMatch');") &&
      bootstrapScript.includes("Selector.prototype.valueMatch=ss('valueMatch');"),
      'Bootstrap must expose EasyClick-style selector match aliases via the ss/sx factories');
check(typeDefinitions.includes('idMatch(value: string): AutoSelectorBuilder') &&
      typeDefinitions.includes('typeMatch(value: string): AutoSelectorBuilder') &&
      typeDefinitions.includes('textMatch(pattern: string): AutoSelectorBuilder') &&
      typeDefinitions.includes('nameMatch(pattern: string): AutoSelectorBuilder') &&
      typeDefinitions.includes('labelMatch(pattern: string): AutoSelectorBuilder') &&
      typeDefinitions.includes('valueMatch(pattern: string): AutoSelectorBuilder'),
      'Type definitions must describe the EasyClick selector match aliases');
check(bootstrapScript.includes("function dp(n,v){Object.defineProperty(node,n,{value:v,configurable:!0});}") &&
      bootstrapScript.includes("function nr(n,f,multi){dp(n,function(){var r=f(raw);return multi?(r||[]).map(wrapNode):wrapNode(r);});}") &&
      bootstrapScript.includes("nr('children',base.getChildren,1);") &&
      bootstrapScript.includes("nr('siblings',base.getSiblings,1);") &&
      bootstrapScript.includes("nr('nextSiblings',base.getNextSiblings,1);") &&
      bootstrapScript.includes("nr('previousSiblings',base.getPreviousSiblings,1);") &&
      bootstrapScript.includes("nr('parent',base.getParent);") &&
      bootstrapScript.includes("nr('allChildren',function(s){var out=[];function walk(list){for(var i=0;i<list.length;i++){out.push(list[i]);walk(base.getChildren(list[i])||[]);}}walk(base.getChildren(s)||[]);return out;},1);") &&
      bootstrapScript.includes("dp('set_text',node.setText);") &&
      bootstrapScript.includes("dp('clear_text',node.clearText);"),
      'Bootstrap must expose EasyClick node relation methods (incl. allChildren) via the dp/nr factories');
check(typeDefinitions.includes('children(): AutoNodeObject[]') &&
      typeDefinitions.includes('allChildren(): AutoNodeObject[]') &&
      typeDefinitions.includes('nextSiblings(): AutoNodeObject[]') &&
      typeDefinitions.includes('previousSiblings(): AutoNodeObject[]'),
      'Type definitions must describe node relation methods');
check(typeDefinitions.includes('md5(text: string): string') &&
      typeDefinitions.includes('sha1(text: string): string') &&
      typeDefinitions.includes('imageSize(path: string): { width: number; height: number; pixelWidth: number; pixelHeight: number; scale: number } | null') &&
      typeDefinitions.includes('md5File(path: string): string'),
      'Type definitions must describe hashes and image dimensions');
check(read('Sources/AutoSDK/AutoScriptSupport.m').includes('AutoScriptMD5Hex(NSData *data)') &&
      read('Sources/AutoSDK/AutoScriptSupport.m').includes('CGImageSourceCreateWithData') &&
      read('Sources/AutoSDK/AutoEngine.m').includes('[name isEqualToString:@"md5"]'),
      'Native support must implement MD5/SHA1 digests and image-size metadata');
check(bootstrapScript.includes('base.screenshotRegion=function(x,y,w,h)') &&
      bootstrapScript.includes('base.childCount=function(s)') &&
      bootstrapScript.includes('base.randomString=function(len,chars)') &&
      bootstrapScript.includes('base.randomCharNumber=function(len)') &&
      bootstrapScript.includes('base.drag=function(x1,y1,x2,y2,duration)') &&
      bootstrapScript.includes('base.launchAppByPrefix=function(prefix)') &&
      bootstrapScript.includes('g.screenshotRegion=base.screenshotRegion') &&
      bootstrapScript.includes('g.launchAppByPrefix=base.launchAppByPrefix'),
      'Bootstrap must expose screenshotRegion, childCount, randomString, drag and launchAppByPrefix');
check(bootstrapScript.includes('getScreenWidthHeightText:function(){return deviceApi.getScreenWidth()') &&
      typeDefinitions.includes('getScreenWidthHeightText(): string') &&
      typeDefinitions.includes('screenshotRegion(x: number, y: number, width: number, height: number): string | null') &&
      typeDefinitions.includes('launchByPrefix(bundleIdPrefix: string): boolean') &&
      typeDefinitions.includes('declare function drag(x1: number, y1: number, x2: number, y2: number, durationMs?: number): boolean'),
      'Type definitions must describe region screenshots, prefix launch, drag and helpers');
check(read('Sources/AutoSDK/AutoEngine.m').includes('invokeScreenshotRegion:(JSValue *)payload') &&
      read('Sources/AutoSDK/AutoEngine.m').includes('CGImageCreateWithImageInRect'),
      'Engine must implement region screenshots with CoreGraphics cropping');
check(bootstrapScript.includes('base.swipeUp=function(percent,duration)') &&
      bootstrapScript.includes('base.swipeDown=function(percent,duration)') &&
      bootstrapScript.includes('base.swipeLeft=function(percent,duration)') &&
      bootstrapScript.includes('base.swipeRight=function(percent,duration)') &&
      bootstrapScript.includes('g.swipeUp=base.swipeUp') &&
      bootstrapScript.includes('g.swipeRight=base.swipeRight'),
      'Bootstrap must expose direction swipe helpers on auto and as globals');
check(bootstrapScript.includes("avf('appList')") &&
      typeDefinitions.includes('appList(): Array<{ bundleId: string; name: string }>') &&
      typeDefinitions.includes('installedApps(): Array<{ bundleId: string; name: string }>') &&
      typeDefinitions.includes('declare function swipeUp(percent?: number, durationMs?: number): boolean') &&
      typeDefinitions.includes('declare function swipeDown(percent?: number, durationMs?: number): boolean'),
      'Type definitions must describe direction swipes and installed-app listing');
check(builtinAdapterSource.includes('installedApplicationsWithError:') &&
      read('Sources/AutoSDK/AutoEngine.m').includes('installedApplicationsWithError:&error'),
      'Built-in adapter and engine must implement the installed-apps query');
check(bootstrapScript.includes('base.execAsync=function(fn)') &&
      bootstrapScript.includes('base.execSync=function(fn)') &&
      bootstrapScript.includes('base.longClickPoint=function(x,y,duration)') &&
      typeDefinitions.includes('interface AutoThread') &&
      typeDefinitions.includes('execAsync(fn: Function, ...args: unknown[]): AutoThread | null') &&
      read('Sources/AutoSDK/AutoEngine.m').includes('invokeExecAsync:(JSValue *)payload') &&
      read('Sources/AutoSDK/AutoEngine.m').includes('threadCancelled'),
      'Bootstrap and engine must expose real parallel exec threads with per-thread cancellation');
check(bootstrapScript.includes('base.execSync=function(fn){var args=arr(arguments,1);return bridge.invokeExecAsync('),
      'execSync must return the native sync result verbatim so object/array results survive');
check(bootstrapScript.includes("try{apply(timer.fn,g,timer.args);}catch(e){consoleBridge.error('Timer error: '+(e&&e.message||e));}"),
      'Timer callback exceptions must be isolated so one bad timer cannot abort the drain loop');
check(engineSource.includes('thread.finished = YES;') && engineSource.includes('thread.context = nil;'),
      'Finished exec threads must release their JSContext to avoid unbounded memory growth');
check(bootstrapScript.includes('g.lastError=function(){return bridge.invokeLastError();};') &&
      engineSource.includes('- (id)invokeLastError;') && engineSource.includes('NSUnderlyingErrorKey'),
      'lastError() must expose the last native error for failure disambiguation');
check(bootstrapScript.includes('function gx(o,n){n.forEach(function(k){g[k]=o[k];});}') &&
      bootstrapScript.includes("gx(base,['") && bootstrapScript.includes("gx(deviceApi,['"),
      'Bulk alias helper gx must keep the export section compact');
check(read('Sources/AutoSDK/AutoEngine.m').includes('invokeTouch:(JSValue *)payload') &&
      read('Sources/AutoSDK/AutoEngine.m').includes('performMultiTouch:fingers error:&error'),
      'Engine must bridge invokeTouch to the adapter performMultiTouch');
for (const scriptPath of ['Examples/TemplateApp/Scripts/hello.js', 'Examples/TemplateApp/Scripts/demo-api.js', 'Examples/TemplateApp/Scripts/gesture-demo.js', 'Examples/TemplateApp/Scripts/vision-demo.js', 'Examples/TemplateApp/Scripts/media-demo.js']) {
  try {
    new vm.Script(read(scriptPath), { filename: scriptPath });
  } catch (error) {
    failures.push(`${scriptPath}: invalid JavaScript (${error.message})`);
  }
}
check(read('Examples/TemplateApp/Scripts/hello.js').includes('device.setClipboard') &&
      read('Examples/TemplateApp/Scripts/demo-api.js').includes('auto.capabilities().http'),
      'Template bundled scripts must exercise device/system APIs and guard HTTP by capability');
check(builtinAdapterSource.includes('@"appList": @(appListReady)') &&
      builtinAdapterSource.includes('@"appLifecycle": @(appControlReady)') &&
      builtinAdapterSource.includes('@"systemActions": @(systemActionsReady)'),
      'Built-in adapter capabilities must advertise app list, lifecycle, and system actions');
check(read('Examples/TemplateApp/Scripts/demo-api.js').includes('swipeUp(0.4, 250)') &&
      read('Examples/TemplateApp/Scripts/demo-api.js').includes('app.appList()') &&
      read('Examples/TemplateApp/Scripts/demo-api.js').includes('caps.appList === true'),
      'Template demo must exercise direction swipes and the installed-app list behind capability guards');
check(read('Examples/TemplateApp/Scripts/gesture-demo.js').includes('multiTouch === true') &&
      read('Examples/TemplateApp/Scripts/vision-demo.js').includes('.ocr === true') &&
      read('Examples/TemplateApp/Scripts/media-demo.js').includes('mediaLibraryWrite === true'),
      'Template bundled scripts must cover gesture, vision and photo-library demos with capability guards');

for (const path of [...sourceFiles('Sources/AutoSDK'), ...sourceFiles('Tests'), ...sourceFiles('Examples/TemplateApp/App')]) {
  const source = read(path);
  check(!/<<<<<<<|=======|>>>>>>>/.test(source), `${path}: unresolved conflict marker`);
  checkBalancedSource(path);
}

if (failures.length > 0) {
  console.error(failures.map(message => `- ${message}`).join('\n'));
  process.exitCode = 1;
} else {
  console.log('AutoSDK verification passed.');
}
