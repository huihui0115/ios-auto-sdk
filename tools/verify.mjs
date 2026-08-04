#!/usr/bin/env node
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import vm from 'node:vm';

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

for (const path of ['tools/auto-sdk.mjs', 'tools/debug-client.mjs', 'vscode-extension/extension.js', 'vscode-extension/device-client.js', 'vscode-extension/script-tools.js', 'vscode-extension/usb-tunnel.js', 'vscode-extension/inspector-view.js', 'vscode-extension/media/inspector.js', 'tools/init-project.mjs', 'tools/doctor.mjs']) {
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

const wdaAdapter = read('Sources/AutoSDK/AutoWDAHTTPAdapter.m');
check(wdaAdapter.includes('#import <Vision/Vision.h>'), 'WDA adapter must keep local Vision OCR support');
check(wdaAdapter.includes('configuration.HTTPShouldUsePipelining = YES'), 'WDA adapter must reuse an HTTP session');
check(wdaAdapter.includes('/wda/element/') && wdaAdapter.includes('findColor:'), 'WDA adapter is missing WDA scroll or color support');
check(wdaAdapter.includes('@"ocr": @YES'), 'WDA adapter capabilities must report OCR support');
check(wdaAdapter.includes('AutoWDAErrorIsInvalidSession') && wdaAdapter.includes('requestSessionSuffix:'), 'WDA adapter must retry an invalid session once');
check(wdaAdapter.includes('AutoWDAErrorIsElementNotFound') && wdaAdapter.includes('requestSessionSuffix:@"/element"'), 'WDA exists must use a single-element lookup');
check(wdaAdapter.includes('AutoWDAUnwrapSelector') &&
      wdaAdapter.includes('AutoWDAMaxSelectorNestingDepth = 32') &&
      wdaAdapter.includes('WDA selector nesting contains a cycle.') &&
      wdaAdapter.includes('AutoWDAMaxSelectorTextLength'),
      'WDA selector unwrapping must reject cycles, excessive depth, and oversized fields centrally');
check(wdaAdapter.includes('AutoWDAErrorIsStaleElement') && wdaAdapter.includes('freshPayload'), 'WDA element actions must recover stale selector-backed handles');
check(wdaAdapter.includes('usedSession:&elementSession') && wdaAdapter.includes('session:item[@"sessionId"]'), 'WDA element actions must stay bound to the session that created each handle');
check(wdaAdapter.includes('- (NSString *)sessionId') && wdaAdapter.includes('- (NSDictionary<NSString *,id> *)sessionSettings'), 'WDA public session state getters must synchronize with mutation');
check(wdaAdapter.includes('AutoWDAHTTPRedirectDelegate') && wdaAdapter.includes('sameScheme && sameHost && originPort == targetPort'), 'WDA redirects must stay on the configured origin');
check(wdaAdapter.includes('/wda/apps/launch') && wdaAdapter.includes('@"appLifecycle": @YES'), 'WDA adapter is missing application lifecycle support');
check(wdaAdapter.includes('@"/wda/homescreen"') && wdaAdapter.includes('@"/wda/lock"') &&
      wdaAdapter.includes('@"/wda/unlock"') &&
      wdaAdapter.includes('goToHomeScreenWithError:') && wdaAdapter.includes('lockDeviceWithError:') &&
      wdaAdapter.includes('unlockDeviceWithError:') && wdaAdapter.includes('@"systemActions": @YES'),
      'WDA adapter must implement the optional system-level endpoint methods and report them');
check(wdaAdapter.includes('NSXMLParser') && wdaAdapter.includes('@"sourceDerived": @YES'), 'WDA adapter must mark source-derived node relationships');
check(wdaAdapter.includes('childTypeCounts') && wdaAdapter.includes('initWithMaxNodes') && wdaAdapter.includes('cachedXPath'), 'WDA source parser must use bounded type counters and lazy XPath storage');
check(wdaAdapter.includes('AutoWDAFindSourceNodeByAbsolutePath'), 'WDA source-derived XPath lookup must avoid full-tree scans');
check(wdaAdapter.includes('objc_precise_lifetime') && wdaAdapter.includes('retainingRoot:&retainedRoot'), 'Zero-duration WDA source queries must retain the hierarchy while using weak parent links');
check(wdaAdapter.includes('shouldResolveExternalEntities = NO') && wdaAdapter.includes('sourceMaxBytes'), 'WDA source parser must bound XML input');
check(wdaAdapter.includes('AutoWDAMaxSourceDepth = 1024') &&
      wdaAdapter.includes('shouldCancelLookup') &&
      wdaAdapter.includes('WDA node lookup was cancelled.'),
      'WDA source trees and selector scans must have depth and cancellation limits');
check(wdaAdapter.includes('@"maxCandidates"') && wdaAdapter.includes('@"maxResults"'), 'WDA adapter must expose bounded image/OCR work');
check(wdaAdapter.includes('(double)step * sqrt'), 'WDA adaptive image step must enforce the candidate budget');
check(wdaAdapter.includes('AutoWDATemplateImage') && wdaAdapter.includes('totalCostLimit = 32 * 1024 * 1024'), 'WDA template cache must be bounded');
check(wdaAdapter.includes('AutoWDAPixelImageMakeRegion') && wdaAdapter.includes('AutoWDAColorOffset'), 'WDA color/image scans must use ROI buffers and precompiled offsets');
check(wdaAdapter.includes('AutoWDAPixelByteCount') && wdaAdapter.includes('combined pixel-buffer limit'), 'WDA image matching must bound its combined pixel working set');
check(wdaAdapter.includes('verifiedCandidates') && wdaAdapter.includes('@"truncated"'), 'WDA image verification work must be explicitly bounded');
check(wdaAdapter.includes('@"mode"') && wdaAdapter.includes('Vision OCR failed'), 'WDA adapter must expose OCR modes and isolate Vision errors');
check(wdaAdapter.includes('AutoWDAMaxHTTPResponseBytes') && wdaAdapter.includes('AutoWDAMaxScreenshotBytes'), 'WDA responses and screenshots must be size-bounded');
check(wdaAdapter.includes('AutoWDAMaxHTTPRequestBytes') &&
      wdaAdapter.includes('completedResponseData = nil') &&
      wdaAdapter.includes('__weak NSURLSessionDataTask *weakTask'),
      'WDA requests must be bounded and temporary response/task references released promptly');
check(wdaAdapter.includes('initWithBase64EncodedString:value options:0') &&
      !wdaAdapter.includes('NSDataBase64DecodingIgnoreUnknownCharacters'),
      'WDA screenshots must reject malformed base64 responses');
check(wdaAdapter.includes('task.countOfBytesExpectedToReceive') && wdaAdapter.includes('MAX((NSUInteger)1, AutoWDAUnsigned(region[@"maxResults"], 1000))'), 'WDA transfers and default OCR result count must be bounded');
check(wdaAdapter.includes('operationCancellationGeneration') &&
      wdaAdapter.includes('cancelledBeforeStart') &&
      wdaAdapter.includes('[self.activeTasks addObject:task]') &&
      wdaAdapter.includes('[task resume]'),
      'WDA request creation and cancellation must be linearized with a generation');
check(wdaAdapter.includes('visualOperationLock') && wdaAdapter.includes('activeVisionRequests') &&
      wdaAdapter.includes('scannedCandidates') && wdaAdapter.includes('comparedPixels'),
      'WDA visual work, Vision cancellation, and color comparisons must be bounded');
check(wdaAdapter.includes('settingsApplicationLock') && wdaAdapter.includes('settingsGeneration') &&
      wdaAdapter.includes('settingsAppliedGeneration') && wdaAdapter.includes('settingsAttemptedGeneration'),
      'WDA session settings must be single-flight and configuration-generation aware');
check(wdaAdapter.includes('AutoWDAOperationCancellationThreadKey') &&
      wdaAdapter.includes('operationCancellationThreadKey') &&
      wdaAdapter.includes('operationCleanupTimeoutThreadKey') &&
      wdaAdapter.includes('requestCleanupPath') &&
      wdaAdapter.includes('installCancellationContextForGeneration') &&
      wdaAdapter.includes('ownsCancellationContext'),
      'WDA composite requests must propagate per-adapter cancellation to nested requests');
check(wdaAdapter.includes('AutoWDAErrorIsUnsupportedCommand') && wdaAdapter.includes('remembersAttempt'),
      'WDA settings retries must distinguish unsupported settings from transient failures');
check(wdaAdapter.includes('invalidateVisualCachesLocked') &&
      wdaAdapter.includes('[self invalidateVisualCachesLocked]'),
      'WDA session transitions must invalidate visual cache generations atomically');
check(wdaAdapter.includes('windowSizeCacheGeneration') &&
      wdaAdapter.includes('self.windowSizeCacheGeneration == requestGeneration') &&
      wdaAdapter.includes('self.windowSizeCacheGeneration == windowRequestGeneration'),
      'WDA window-size cache writes must reject results invalidated during visual or source requests');
check(wdaAdapter.includes('statusCode == 405') && wdaAdapter.includes('statusCode == 501') &&
      wdaAdapter.includes('statusCode == 404 && !AutoWDAErrorIsInvalidSession(error)'),
      'WDA settings must remember bare unsupported-endpoint HTTP responses');
check(wdaAdapter.includes('parser.shouldCancel') && wdaAdapter.includes('cancelledAfterParse'),
      'WDA source parsing and cache commits must remain cancellation-aware');
check(wdaAdapter.includes('operationGeneration != self.operationCancellationGeneration') &&
      wdaAdapter.includes('@"Screenshot was cancelled."'),
      'WDA screenshot cache hits must re-check cancellation while holding the cache lock');
check(wdaAdapter.includes('expression ?: NSNull.null') && wdaAdapter.includes('length] > 1024'), 'WDA regex cache must retain invalid bounded patterns');
check(wdaAdapter.includes('AutoWDADouble(value[@"x"], NAN)') &&
      wdaAdapter.includes('width < 0 || height < 0'),
      'WDA element bounds must reject null, non-finite, and negative values');
check(read('docs/LUA_FRAMEWORK_AUDIT.md').includes('LuaTouch'), 'Lua framework audit document is missing');
const templatePlist = read('Examples/TemplateApp/App/Info.plist');
check(templatePlist.includes('NSAllowsLocalNetworking'), 'Template must allow loopback WDA networking');
check(templatePlist.includes('AutoSDKAdapter') && templatePlist.includes('AutoSDKWDAURL'), 'Template must expose WDA adapter configuration');
check(extensionLock.version === extensionPackage.version, 'VS Code extension version differs from package-lock.json');
check(extensionLock.packages?.['']?.version === extensionPackage.version, 'VS Code extension root lock version is inconsistent');
check(extensionPackage.private === true && extensionPackage.license === 'UNLICENSED',
      'VS Code extension package must remain private and unlicensed for npm publication');
check(extensionPackage.contributes?.commands?.some(item => item.command === 'autosdk.startUsbTunnel') &&
      extensionPackage.contributes?.commands?.some(item => item.command === 'autosdk.stopUsbTunnel'),
      'VS Code extension must expose managed USB tunnel commands');
check(extensionPackage.contributes?.configuration?.properties?.['autosdk.connectionTimeout']?.maximum === 3600000 &&
      extensionPackage.contributes?.configuration?.properties?.['autosdk.buildTimeout']?.maximum === 21600,
      'VS Code extension timeouts must be bounded');

const extensionSource = read('vscode-extension/extension.js');
const contributedCommandIds = extensionPackage.contributes?.commands?.map(item => item.command) || [];
for (const command of contributedCommandIds) {
  check(extensionSource.includes("registerCommand('" + command + "'"),
        'Extension must register contributed command ' + command);
}
const inspectorSource = read('vscode-extension/media/inspector.js');
check(/type === 'selectorResult'[\s\S]{0,800}state\.match = null[\s\S]{0,200}elements\.selection\.hidden = true/.test(inspectorSource),
      'Inspector selector results must clear stale match overlays and region selections');

const engineSource = read('Sources/AutoSDK/AutoEngine.m');
check(engineSource.includes('waitPollInterval') && engineSource.includes('pollInterval * 1.5'), 'waitFor must use bounded polling backoff');
check(engineSource.includes('NSError *destinationError = nil;') && engineSource.includes('&destinationError'),
      'HTTP download destination validation must declare its error pointer');
check(engineSource.includes('AutoPayloadHasFiniteNumbers') && engineSource.includes('maxScreenshotBytes'), 'script numeric inputs and screenshots must be bounded');
check(engineSource.includes('maximumTotalBytes') && engineSource.includes('retainedMessageBytes') &&
      engineSource.includes('@"maxLogBytes"'),
      'Retained script logs must have a hard total byte budget');
check(engineSource.includes('fileWriteEnabled = fileReadEnabled &&') &&
      engineSource.includes('@"fileWrite": @(fileWriteEnabled)'),
      'File-write capability must require both file access and file-write permission');
check(engineSource.includes('@"allowSystemControl"') && engineSource.includes('@"systemControl"') &&
      engineSource.includes('AutoSystemURLSchemeAllowed') && engineSource.includes('AutoSystemClipboardByteLimit') &&
      engineSource.includes('isEqualToString:@"openurl"'),
      'System control must be configurable, capability-reported, bounded, and URL schemes validated');
const bootstrapSource = read('Sources/AutoSDK/AutoBootstrapScript.m');
check(bootstrapSource.includes("operation:'clipboardGet'") && bootstrapSource.includes("operation:'clipboardSet'") &&
      bootstrapSource.includes("operation:'brightnessGet'") && bootstrapSource.includes("operation:'brightnessSet'") &&
      bootstrapSource.includes("operation:'volumeGet'") && bootstrapSource.includes("operation:'vibrate'") &&
      bootstrapSource.includes("operation:'openURL'") && bootstrapSource.includes("operation:'homescreen'") &&
      bootstrapSource.includes('g.openURL=') && bootstrapSource.includes('homeScreen:function()'),
      'Bootstrap must expose clipboard, brightness, volume, vibration, openURL and home-screen operations with globals');
check(bootstrapSource.includes("operation:'saveImage'") && bootstrapSource.includes("operation:'saveImageBase64'") &&
      bootstrapSource.includes("operation:'saveVideo'") && bootstrapSource.includes("operation:'saveScreenshot'") &&
      bootstrapSource.includes('var mediaApi=') && bootstrapSource.includes('g.media=mediaApi') &&
      bootstrapSource.includes('saveImageToAlbum:function') && bootstrapSource.includes('saveVideoToAlbum:function'),
      'Bootstrap must wire photo-library media operations and aliases');
check(engineSource.includes('deviceMemoryInfo') && engineSource.includes('isEqualToString:@"memory"'),
      'Engine must expose device memory information');
check(engineSource.includes('isEqualToString:@"toast"') && engineSource.includes('AutoShowToast'),
      'Engine must provide a built-in toast fallback for unregistered hosts');
check(engineSource.includes('[nativePayload[@"arguments"] isKindOfClass:NSArray.class]'),
      'The built-in toast must parse arguments with a bracketed message send');
check(bootstrapSource.includes('getMemoryInfo:function') && bootstrapSource.includes("operation:'memory'") &&
      bootstrapSource.includes('writeLines:function') && bootstrapSource.includes("callFile('move'") &&
      bootstrapSource.includes('rename:function') && bootstrapSource.includes('base.toast=function') &&
      bootstrapSource.includes('base.toastLog=function') && bootstrapSource.includes('g.toast=base.toast'),
      'Bootstrap must expose memory info, file move/rename/writeLines, and toast helpers');
check(read('Sources/AutoSDK/AutoScriptSupport.m').includes('isEqualToString:@"move"') &&
      read('Sources/AutoSDK/AutoScriptSupport.m').includes('Unable to move path.'),
      'Sandbox file operations must support move with overwrite semantics');
check(bootstrapSource.includes('activeTimerCount>=10000') && bootstrapSource.includes("RangeError('Too many active timers')"), 'JavaScript timers must be bounded');
check(bootstrapSource.includes('activeTimers[id]') && bootstrapSource.includes('delete activeTimers[id]'), 'Timers must support cancellation from inside an active interval callback');
check(bootstrapSource.includes('function pushTimer') && bootstrapSource.includes('function popTimer') &&
      !bootstrapSource.includes('timers.sort(') && !bootstrapSource.includes('timers.shift()'),
      'Timer draining must use a bounded priority heap instead of repeated full-array sorting');
check(bootstrapSource.includes('cancelled[id]=true') && bootstrapSource.includes('delete cancelled[timer.id]'), 'Queued timer cancellation must not leak cancellation markers');
check(bootstrapSource.includes('function ensureRunning()') && bootstrapSource.includes('guardMethods(base)') &&
      bootstrapSource.includes('ensureRunning();return bridge.invokeNative'),
      'Script stop must reject subsequent automation and native bridge calls');
check(bootstrapSource.includes('delete g.__bridge;delete g.__console') &&
      engineSource.includes('[drainTimers callWithArguments:@[]]') &&
      !bootstrapSource.includes('evaluateScript:@"__autoDrainTimers();"'),
      'Bootstrap internals and timer draining must not remain user-overridable globals');
check(bootstrapSource.includes('g.randomInt=base.randomInt') &&
      bootstrapSource.includes('if(max==null){max=min;min=0;}') &&
      bootstrapSource.includes("replace(/[^A-Za-z0-9+/=_-]/g,'')") &&
      !bootstrapSource.includes('indexOf(str.charAt(i++))'),
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
check(!engineSource.includes('[session invalidateAndCancel]') && !engineSource.includes('finishTasksAndInvalidate'),
      'The shared HTTP session must never be invalidated per request');
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
check(bootstrapSource.includes('x1:x1,y1:y1,x2:x2,y2:y2') && bootstrapSource.includes('g.app=appApi'), 'AutoBootstrapScript is missing swipe coordinates or app lifecycle bindings');
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
check(uiKitAdapter.includes('@"nodeId"') && uiKitAdapter.includes('@"parentId"') && wdaAdapter.includes('@"nodeId"'), 'Node snapshots must expose hierarchy identifiers');
const debugServerSource = read('Sources/AutoSDK/AutoDebugServer.m');
check(debugServerSource.includes('(void)retainedData') && debugServerSource.includes('dispatch_data_create_concat'), 'Debug transport must retain and concatenate framed data without a full payload copy');
check(debugServerSource.includes('nw_interface_type_cellular') && debugServerSource.includes('nw_interface_type_loopback') && debugServerSource.includes('token.length < 16'), 'Debug transport must restrict and authenticate Wi-Fi listeners');
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
check(scriptSupport.includes('maxFileLineCount') && bootstrapSource.includes("callFile('readLines'"), 'Line reads must be bounded before creating JavaScript strings');
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
      settingsSource.includes('wifiToggled:') && settingsSource.includes('wdaToggled:'),
      'Settings must show the SDK version and re-apply adapter configuration');
const templateSettingsSource = read('Examples/TemplateApp/App/AutoTemplateSettings.m');
check(templateSettingsSource.includes('makeAutomationAdapter') && templateSettingsSource.includes('applyEngineConfiguration') &&
      templateSettingsSource.includes('wifiIPv4Address') && !templateSettingsSource.includes('registerNativeMethod:@"toast"'),
      'Template configuration must build adapters and rely on the engine built-in toast');
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
    const compiledBootstrap = new vm.Script(script, { filename: 'AutoBootstrapScript.js' });
    check(script.includes('g.auto='), 'AutoBootstrapScript does not install the auto global');
    let stopped = false;
    let lastHTTPOptions;
    let lastDeviceOperation;
    let lastAppOperation;
    let lastMediaOperation;
    const context = vm.createContext({
      __bridge: new Proxy({}, { get: (_, key) => {
        if (key === 'invokeIsStopped') return () => stopped;
        if (key === 'invokeHTTP') return value => { lastHTTPOptions = value; return {}; };
        if (key === 'invokeFile') return value => value.operation === 'readLines' ? ['first', 'second'] : true;
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
    check(context.auto?.storage === context.storages?.create,
          'Storage factory aliases must retain their function identity');
    check(context.http?.length === 2 && context.http?.get?.length === 2 &&
          context.auto?.click?.length === 1 && context.file?.readFile?.length === 1,
          'Guard wrappers must preserve public function arity');
    const options = { headers: { accept: 'application/json' } };
    context.http.get('https://example.invalid', options);
    check(options.method === undefined && lastHTTPOptions?.method === 'GET',
          'HTTP convenience methods must not mutate caller options');
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
for (const requiredText of ['workflow_dispatch:', 'requestId:', 'xcodebuild test', 'CODE_SIGNING_ALLOWED=NO', 'actions/upload-artifact@v4']) {
  check(workflow.includes(requiredText), `.github/workflows/ios-build.yml is missing ${requiredText}`);
}
check(workflow.includes("github.event_name == 'workflow_dispatch' && (inputs.requestId || github.run_id) || github.ref"),
      'Concurrent remote build requests must not cancel each other');
check(workflow.includes('@vscode/vsce package') && workflow.includes('autosdk-vscode-0.4.0.vsix') &&
      workflow.includes('upload-pages-artifact@v3') && workflow.includes('deploy-pages@v4'),
      'CI must package the VS Code extension and deploy docs to GitHub Pages');
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
check(read('docs/index.html').includes('AutoSDK 文档中心'),
      'docs/index.html landing page must exist for GitHub Pages');
check(read('Sources/AutoSDK/AutoBootstrapScript.m').includes('bridge.invokeTouch({fingers:normalized})') &&
      bootstrapSource.includes('base.gesture=function(actions)') &&
      bootstrapSource.includes('base.multiGesture=function(fingers)') &&
      bootstrapSource.includes('base.pinch=function(x,y,scale,duration)') &&
      bootstrapSource.includes('g.pinch=base.pinch'),
      'Bootstrap must expose gesture, multiGesture and pinch on auto and as globals');
check(bootstrapSource.includes("if(!normalized[t].length)throw new Error('gesture finger track must contain at least one action.')"),
      'Bootstrap gesture must reject empty finger tracks');
check(typeDefinitions.includes('interface AutoGestureAPI') &&
      typeDefinitions.includes('gesture(actions: AutoGestureAction[]): boolean') &&
      typeDefinitions.includes('pinch(x: number, y: number, scale: number, durationMs?: number): boolean') &&
      typeDefinitions.includes('declare function gesture('),
      'Type definitions must describe the multi-touch gesture API');
check(read('Sources/AutoSDK/include/AutoWDAHTTPAdapter.h').includes('performMultiTouch:') &&
      read('Sources/AutoSDK/include/AutoAutomationAdapter.h').includes('performMultiTouch:'),
      'Adapter headers must declare performMultiTouch');
check(read('Sources/AutoSDK/AutoWDAHTTPAdapter.m').includes('@"/actions" method:@"POST" body:body') &&
      wdaAdapter.includes('@"multiTouch": @YES'),
      'WDA adapter must implement multi-touch gestures and report the capability');
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
