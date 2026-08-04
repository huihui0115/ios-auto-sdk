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

for (const path of ['tools/auto-sdk.mjs', 'tools/debug-client.mjs', 'vscode-extension/extension.js', 'vscode-extension/device-client.js', 'vscode-extension/script-tools.js', 'vscode-extension/usb-tunnel.js', 'vscode-extension/inspector-view.js', 'vscode-extension/media/inspector.js']) {
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
const debugClient = read('tools/debug-client.mjs');
check(debugClient.includes('MAX_SCRIPT_BYTES') && debugClient.includes('metadata.size > MAX_SCRIPT_BYTES') &&
      debugClient.includes('MAX_RESPONSE_BYTES') && debugClient.includes('response.ok !== true'),
      'Debug CLI must bound script files and reject malformed or oversized responses');

const rootPackage = parseJSON('package.json');
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

const podspec = read('AutoSDK.podspec');
const versionSource = read('Sources/AutoSDK/AutoSDKVersion.m');
check(podspec.includes(`s.version          = '${rootPackage.version}'`), 'SDK version differs between package.json and AutoSDK.podspec');
check(versionSource.includes(`"${rootPackage.version}"`), 'SDK version differs between package.json and AutoSDKVersion.m');
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
const bootstrapSource = read('Sources/AutoSDK/AutoBootstrapScript.m');
check(engineSource.includes('waitPollInterval') && engineSource.includes('pollInterval * 1.5'), 'waitFor must use bounded polling backoff');
check(engineSource.includes('AutoPayloadHasFiniteNumbers') && engineSource.includes('maxScreenshotBytes'), 'script numeric inputs and screenshots must be bounded');
check(engineSource.includes('maximumTotalBytes') && engineSource.includes('retainedMessageBytes') &&
      engineSource.includes('@"maxLogBytes"'),
      'Retained script logs must have a hard total byte budget');
check(engineSource.includes('fileWriteEnabled = fileReadEnabled &&') &&
      engineSource.includes('@"fileWrite": @(fileWriteEnabled)'),
      'File-write capability must require both file access and file-write permission');
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
check(engineSource.includes('hasSuffix:@".js"') && engineSource.includes('!containsWhitespace') &&
      engineSource.includes('!containsCodeCharacters'),
      'Path detection must not reject inline source that merely ends in .js');
check(engineSource.includes('AutoJSContextGroupSetExecutionTimeLimit(group, 0.001, NULL, NULL)') &&
      engineSource.includes('if ([self shouldStop])'),
      'Installed script interruption must re-check the stop flag so stopScript cannot race the install');
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
check(read('Sources/AutoSDK/AutoHTTPSupport.h').includes('AutoHTTPRedirectRouter') &&
      engineSource.includes('#import "AutoHTTPSupport.h"'),
      'Shared HTTP redirect routing must be imported by the engine');
check(engineSource.includes('AutoHTTPSharedSession()') && engineSource.includes('AutoHTTPSharedRouter()') &&
      engineSource.includes('dispatch_once') && engineSource.includes('ephemeralSessionConfiguration'),
      'HTTP requests must reuse one shared keep-alive session created exactly once');
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
    const context = vm.createContext({
      __bridge: new Proxy({}, { get: (_, key) => {
        if (key === 'invokeIsStopped') return () => stopped;
        if (key === 'invokeHTTP') return value => { lastHTTPOptions = value; return {}; };
        if (key === 'invokeFile') return value => value.operation === 'readLines' ? ['first', 'second'] : true;
        if (key === 'invokeDevice') return value => value.operation === 'info' ? { model: 'test' } : false;
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
const templateProject = read('Examples/TemplateApp/project.yml');
check(templateProject.includes('AutoSDKTests:') && templateProject.includes('bundle.unit-test'), 'Template XcodeGen project must include the XCTest target');
check(!/^\t/m.test(workflow), '.github/workflows/ios-build.yml contains tab indentation');

for (const path of ['Examples/TemplateApp/App/Info.plist', 'tools/ExportOptions.plist']) {
  const plist = read(path);
  check(plist.includes('<?xml') && plist.includes('<plist') && plist.includes('</plist>'), `${path}: malformed plist envelope`);
}

for (const path of [...sourceFiles('Sources/AutoSDK'), ...sourceFiles('Tests')]) {
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
