# Changelog

All notable changes to AutoSDK are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- **Round 11: 拼音 / 悬浮绘制 / 悬浮球 / 节点保持。** 新增 `toPinYin(text)`（系统级
  CFStringTransform 拼音转换，无第三方依赖，"你好"→"nihao"）与 `strings.toPinYin`；
  新增 `screenDraw.*` 悬浮绘制（init/setBorderWidth/setBorderColor/setTitle/show/
  move/hide，边框+标题，触摸穿透）；新增 `floatBall.show/move/hide/isShow` 悬浮球
  （可拖动、点击显示标题 toast）与全局别名 `setFloatBallPoint(x,y)`；新增
  `node.keep/unkeep/keptCount` 与全局 `keepNode/unkeepNode`（对标
  TrollAutoScript node.keep/unkeep）；新增 `strings.stripUtf8Bom`/`strings.fromUnicode`
  （BOM 清洗、\uXXXX 还原）。修复文档生成器中 14 处历史中文损坏条目；本地 API 文档
  同步更新（198 个函数，新增悬浮窗口分类）。
- **Round 9: plist / webView / AES-128。** 新增 `file.readPlist/writePlist` 与全局
  `plist.read/plist.write`（XML plist，NSData→base64、NSDate→毫秒）；新增
  `webView.init/show/hidden/eval/release` 悬浮 WKWebView（对标 TrollAutoScript
  webView 模块）；新增 `strings.aes128Encrypt/aes128Decrypt`（AES-128-ECB+PKCS7，
  CommonCrypto）与全局简写；新增 `restartScript()` 停止后重跑当前脚本（引擎记录
  当前脚本源码）。本地 API 文档同步更新（192 个函数）。
- **Round 8: 相册清空 + 对标 TrollAutoScript。** 新增
  `media.deleteAllPhotos()/deleteAllVideos()/deleteAllMedia()`（读写真机权限、返回
  删除数量，全局简写同名）；新增字符串工具 `strings.*`（trim/ltrim/rtrim/split/
  chars/toHex/fromHex/isUpper/isLower/isNumber/isIntrger/isLetter/isChinese/isEmail/
  isLink/base64Encode/base64Decode）与全局简写；新增 `sha256()/sha512()`
  （CommonCrypto）；新增 `alert(message,title?)` 原生弹窗与 `exit()` 停止脚本；
  新增文件行操作 `file.lineCount/getLineText/insertLineText/resetLineText`。新增
  [`docs/TROLLAUTOSCRIPT_COMPARISON.md`](docs/TROLLAUTOSCRIPT_COMPARISON.md) 模块级
  对标表，本地 API 文档同步更新（189 个函数）。
- **EasyClick benchmark round 7: real parallel threads and quick helpers.** New
  execAsync(fn, ...args) runs a function in a fresh JSContext on a real
  background thread (sharing the automation bridge), returning an AutoThread
  handle with join() / isFinished() / getResult() / cancel(); execSync()
  blocks until the thread returns while staying interruptible; cancelThread /
  stopAllThreads / isCancelled control threads (up to 8 concurrent, all
  stopped when the script ends). Per-thread cancellation is honored at bridge
  calls, sleeps and timer boundaries. Also adds longClickPoint(x, y, ms),
  getRangeInt(min, max), getRatio(percent), and getOneNodeInfo/getNodeInfo
  aliases. API reference grows to 180 documented functions.
- **EasyClick benchmark round 6: Excel reading and device/app identity.** New
  file.readExcelAllRow(path, sheetIndex?) parses XLSX workbooks with a
  built-in ZIP+XML reader (shared strings, numeric cells, GBK-safe entry
  lookup) or falls back to UTF-8 CSV, returning header-keyed objects;
  file.readExcelRow(path, sheetIndex?, row?) returns one row as an array
  (0-based, null when out of range), with the same 32 MiB budget gate.
  device.getDeviceId() exposes identifierForVendor, getDeviceAlias()
  mirrors the device name, getSerialNo() returns null (iOS sandbox cannot
  read the hardware serial), and getAppVersion()/getPackageName() expose
  the host app version and bundle id (also app.* and globals). API
  reference grows to 174 documented functions.
- **EasyClick benchmark round 5: native ZIP engine.** New
  file.zip(dest, sources) builds a ZIP archive from files and folders
  (raw DEFLATE with CRC32, automatic store fallback, GBK/UTF-8 name
  decoding); file.unzip(zipPath, dest) extracts with path-traversal
  rejection and byte-budget limits; file.readFileInZip(zipPath, entry)
  reads one entry without landing it (UTF-8 text, Base64 for binary,
  null for directories). All three are also exposed as global zip() /
  unzip() / readFileInZip(). Encrypted archives are rejected explicitly.
  API reference grows to 169 documented functions.
- **File stat helpers and foreground-app query.** New file.stat(path) /
  getSize / getModifiedTime / isDir / isFile (single stat bridge
  call, bounded by the same file-access gates) and app.current() /
  currentApp() (WDA /wda/activeAppInfo; embedded adapters report
  unavailable). API reference grows to 144 documented functions.
- **Direction swipe helpers.** New auto.swipeUp() / swipeDown() / swipeLeft()
  / swipeRight() (also exposed as globals), each computing screen-relative
  start/end coordinates from the device size, with a distance ratio
  (percent, default 0.5) and a millisecond duration (default 300 ms). The
  underlying swipe bridge call uses seconds, so the helpers convert units.
- **Installed-app list.** New app.appList() / installedApps() returns
  [{bundleId, name}] through the WDA /wda/apps endpoint; adapters that
  do not implement the new optional installedApplicationsWithError:
  protocol method report an explicit unavailable error. API reference
  grows to 149 documented functions.
- **EasyClick benchmark round: region screenshots, prefix launch, drag and utils.** New
  screenshotRegion(x, y, w, h) crops the screen capture natively (CoreGraphics)
  and returns the region PNG base64; launchAppByPrefix()/app.launchByPrefix()
  lists installed apps and launches the first bundleId match; drag() performs a
  long-press drag through the touch pipeline; childCount(), randomString() and
  randomCharNumber() add node-count and random-string helpers;
  device.getScreenWidthHeightText() returns "390x844". API reference grows to
  156 documented functions.
- **EasyClick benchmark round 4: image processing pipeline and find-not-color.** New
  image.clip(src, x, y, ex, ey, dest) / image.scale(src, w, h, dest) /
  image.gray(src, dest) / image.binaryzation(src, dest, threshold?) /
  image.rotate(src, degrees, dest) process image files through CoreGraphics
  and ImageIO with the same sandbox read/write gates as file.*; new
  image.pixelAt(src, x, y) samples a pixel color from a file, and
  image.getWidth/getHeight alias file.imageSize. New
  findNotColor(colors, threshold, x, y, ex, ey, limit, direction) returns
  screen points that do NOT match the given colors (change detection), sharing
  the findColorEx scan core. API reference grows to 166 documented functions.
- **EasyClick benchmark round 3: region multi-color, MP3 audio and photo authorization.** New
  findColorEx(colors, threshold, x, y, ex, ey, limit, direction) searches the
  current screen for every matching color point in a region and returns an
  array of {x, y} (EasyClick-style color pairs, 0-1 similarity, 1-8 scan
  orders); playMp3(path, volume, queue, stopWhenScriptEnd) and stopMp3() add
  system audio playback with an engine-owned player queue that survives script
  teardown when requested; media.getPhotoAuthorizationStatus() /
  media.requestPhotoAuthorization() expose photo-library permission state.
  API reference grows to 163 documented functions.
- **EasyClick benchmark round 2: hashes and image dimensions.** New md5(text) /
  sha1(text) built-in string digests (CommonCrypto), file.md5/md5File/sha1/
  sha1File sandbox-file digests, and file.imageSize(path) /
  image.getSize(path) returning logical/pixel dimensions via ImageIO. API
  reference grows to 160 documented functions.
- **Device volume keys and screen state.** New device.volumeUp(),
  device.volumeDown() and device.isScreenOn() (WDA /wda/pressButton and
  /wda/locked), gated by allowSystemControl; embedded adapters report
  unavailable instead of failing silently. API reference grows to 142
  documented functions.
- **Virtual-clock timer tests.** The bootstrap test sandbox now advances a
  virtual clock inside invokeSleep, so CI exercises the real wait-sleep-fire
  path deterministically, including interval cadence, one-shot sleeps, and
  stop-during-wait.
- **Bootstrap size/time guard.** `tools/bootstrap.test.mjs` asserts the
  embedded runtime stays under 64 KB and parses in under 1 s.

### Changed

- **Timers wait in one native sleep instead of 50 ms slices.** A one-second
  setTimeout now costs a single JSC-to-Objective-C round trip; the native
  sleep keeps its 20 ms interruptible run-loop pump, so stop requests still
  abort a pending wait promptly.
- **setScreenMetrics fixes the coordinate mapping at setup time.** After
  setScreenMetrics(w, h) the device size is captured once, so
  metrics.point/x/y no longer cross the native bridge per call; call
  setScreenMetrics again after a rotation to re-anchor the mapping.
- **Sleep and wait loops avoid per-iteration NSDate allocations.** The
  deadline is now a monotonic CFAbsoluteTimeGetCurrent value in
  invokeSleep and invokeWaitFor.

## [1.2.1] - 2026-08-04

### Added

- **API 参考补齐到 140 个函数并加自动一致性检查。** `docs/api-reference.html` 新增约 35 个缺失条目：device 屏幕/系统简写、app 生命周期、console 分级日志与计时、file 常用读写、storages 类型化存取与遍历、HTTP 别名、相册与 image 对象、随机数/uuid/定时器取消等，每条都带可直接复制的调试代码。`tools/verify.mjs` 新增回归检查：解析 `types/autosdk.d.ts` 的全部声明并断言每个函数都有文档条目。
- **`bump-version.mjs` 同步 `package-lock.json` 并修复 CHANGELOG 段落写入。** 版本提升现在一次性同步 package.json / package-lock.json / AutoSDK.podspec / AutoSDKVersion.m，且 CHANGELOG 的占位段落会真正写入。
- **Release 说明自动带 CHANGELOG。** CI 发布时自动提取当前版本对应的 CHANGELOG 段落作为 Release notes，并列出下载项（IPA + VS Code 插件）。
- **本地教程更新。** `docs/guide/index.html` 增加内置示例脚本表（含 gesture/vision/media）、capability 守卫写法、`npm run init`/`npm run doctor` 用法，以及文档中心/Releases/API 参考直达链接。

## [1.2.0] - 2026-08-05

### Added

- **CI 产物与在线文档。** 构建工作流额外打包 VS Code 插件（`autosdk-vscode-0.4.0.vsix`）并上传为构建工件、随 Release 发布；新增 GitHub Pages job 把 `docs/` 自动部署到 <https://huihui0115.github.io/ios-auto-sdk/>，`docs/index.html` 作为文档中心落地页。
- **一键品牌化。** `npm run init -- --bundle-id com.yourname.app --name "My App"` 一键修改模板工程的 bundle identifier 与显示名（`tools/init-project.mjs`）。
- **环境诊断。** `npm run doctor` 检查 Node/git/gh/iproxy、脚本语法、文档完整性、vsix、版本 tag 与本地 IPA（`tools/doctor.mjs`）。
- **示例脚本补全。** 新增 `gesture-demo.js`（滑动/手势/多指/捏合）、`vision-demo.js`（截图/取色/找色/多色比较/OCR/找图）、`media-demo.js`（截图与图片写入相册），全部按 capability 守卫。
- **平台提示与许可统一。** 本地 `build` 在非 macOS 上直接报错并提示改用 `build-remote`；`vscode-extension/LICENSE.txt` 改为引用仓库根 LICENSE。
- **下载直达链接。** README 与 `docs/QUICK_START.md` 增加 GitHub Releases 下载入口。

### Added

- **Multi-touch gesture API.** New `auto.gesture(actions)`, `auto.multiGesture(fingers)`
  and `auto.pinch(x, y, scale, duration?)` methods synthesize real multi-finger
  touches through the WDA `/actions` endpoint (W3C pointer actions). Exposed on
  `auto`, as globals, and in `types/autosdk.d.ts`; reported by
  `capabilities().multiTouch`. Adapters without real touch injection return an
  error. `AutoUIKitAdapter` intentionally does not implement it.
- **Version tooling.** `node tools/bump-version.mjs <x.y.z>` synchronizes the
  version across `package.json`, `AutoSDK.podspec` and `AutoSDKVersion.m` and
  prints the tag/publish commands.
- **Cross-platform regression tests.** `tools/bootstrap.test.mjs` runs the exact
  embedded JavaScript bootstrap in a Node vm with a mock bridge and verifies
  base64, randomInt, metrics, timers, storage, file, HTTP, gestures and stop
  behavior on any platform (CI included). 22 tests total.
- **Repository hygiene.** Added root `LICENSE`, `.editorconfig`, and a CI
  release job that attaches the built IPA to GitHub Releases on `v*` tags.

### Added

- **Photo library media API.** New `media.saveImage`, `media.saveImageBase64`,
  `media.saveVideo` and `media.saveScreenshot` methods (plus
  `auto.saveImageToAlbum`, `auto.saveImageBase64ToAlbum`,
  `auto.saveVideoToAlbum`, `auto.saveScreenshotToAlbum` and `image.*` aliases)
  write to the iOS Photos library after an add-only authorization prompt.
  Controlled by `allowMediaLibrary` (default on), `maxMediaBytes` (512 MiB
  default, 2 GiB hard maximum) and `maxMediaImageBytes` (64 MiB default,
  256 MiB hard maximum); hosts must declare `NSPhotoLibraryAddUsageDescription`.
  The capability is reported as `mediaLibraryWrite`.

### Fixed

- **The private JSC execution-time API is no longer used.**
  `JSContextGroupSetExecutionTimeLimit` /
  `JSContextGroupClearExecutionTimeLimit` (weak-linked, undocumented) were
  observed to hang the JavaScript VM on the iOS 17.4 simulator, stalling the
  whole test run. The SDK now relies on the cooperative stop flag plus the
  wall-clock watchdog: `auto.sleep`, bridge calls and timer callbacks are
  interrupted promptly, while a pure-JS `while(true){}` loop that never
  crosses the bridge can keep the CPU busy until the process is terminated.
  `interruptibleScripts` remains accepted for compatibility. See
  `docs/SCRIPT_EXECUTION.md`.
- **HTTP tests can intercept the shared session again.** The engine-wide
  `NSURLSession` used the ephemeral configuration, which ignores
  `NSURLProtocol` classes registered with `+[NSURLProtocol registerClass:]`,
  so the in-process `autosdk.test` test harness could not see any request.
  The shared session now uses the default configuration (caches, cookies and
  credential storage explicitly disabled) and accepts an internal
  `urlProtocolClasses` config key so hosts and tests can inject
  `NSURLProtocol` subclasses deterministically before first use.
- **Stale bridge errors no longer leak into the next script.** `lastError`
  is cleared whenever a script starts successfully, so a failure from a
  previous bridge call cannot be reported as the current run's result.
- **Path-like input returns a precise error.** A missing `.js` file or path
  (e.g. `missing.js`, `scripts/nested.js`) now fails with
  `AutoSDKErrorScriptNotFound` instead of being evaluated as JavaScript.
  The heuristic keeps valid one-line source like `1/2` running as code.
- **Redirect policy is explicit and documented.** When no host allowlist is
  configured, HTTP and remote-script redirects may follow any `http`/`https`
  host; HTTPS-to-HTTP downgrades and non-http(s) schemes are always rejected.
  The repository verification rule now encodes this policy.
- **`auto` proxy reserved keys no longer dispatch to native methods.**
  `auto.then`, `auto.toJSON`, `auto.toString`, `auto.valueOf`,
  `auto.catch`, `auto.constructor`, `auto.__proto__` and similar keys
  return `undefined`, so promise interop and `JSON.stringify(auto)` cannot
  trigger unknown native calls or crash.
- **Template app matches its documentation.** `Examples/TemplateApp` now
  registers the `toast` native method shown in the README and used by
  `Scripts/hello.js`.
- **Inline source ending in `.js` is no longer mistaken for a missing
  path.** A trailing comment such as `// main.js` no longer returns
  `AutoSDKErrorScriptNotFound`; the `.js` suffix only implies a path when
  the input is path-shaped (no whitespace, no JavaScript syntax characters).
- **Inspector selector results clear stale overlays.** Testing a selector
  now removes any previous image-match highlight and region selection, so
  the screenshot overlay always reflects the current result set.
- **Extension command coverage is enforced.** Repository verification and
  the extension wiring tests assert that every contributed
  `autosdk.*` command is registered, so a renamed or dropped command
  fails CI instead of surfacing as a missing command at runtime.

### Changed

- **`scriptTimeout` is the total execution budget including timers.** One
  `runScript` keeps running until the timer queue drains; `setInterval`
  keeps the run alive until `stopScript` or `scriptTimeout`. Documented in
  `README.md`, `docs/PERFORMANCE.md` and `docs/SCRIPT_EXECUTION.md`.
- **`AutoMainThreadAdapterProxy` caches adapter capabilities once** and
  reads them lock-free afterwards on the hot path.
- **`AutoBootstrapScript` moved to its own file**
  (`Sources/AutoSDK/AutoBootstrapScript.m` + private header), keeping
  `AutoEngine.m` smaller and navigable.
- **Script sleeps and element polling no longer busy-spin.** The script
  thread's run loop usually has no sources on modern JavaScriptCore, so
  `auto.sleep`/`waitFor` now fall back to a real thread sleep when
  `runMode:` services nothing. Older runtimes that attach a
  `CFRunLoopTimer` keep the previous blocking behavior.
- **VS Code extension no longer reads plaintext `autosdk.debugToken`.**
  SecretStorage is the only credential source; the deprecated setting is not
  read at runtime and leftover values are removed when a connection is saved.
  The setting was removed from `package.json`.
- **The script timeout watchdog is a one-shot dispatch timer** instead of a
  blocking wait, so a long-running script no longer occupies a global utility
  thread for the whole budget.
- **Script results are bounded.** The evaluated `value` is converted with
  depth/size budgets (24 levels, 50,000 container entries, 1 MiB per string);
  oversized nodes become `__autosdkTruncated` markers.
- **Console message truncation never splits UTF-16 surrogate pairs.**
- **HTTP and remote scripts reuse one keep-alive session.** `invokeHTTP`
  and remote-script downloads share one engine-wide `NSURLSession` (created
  once and never invalidated per request), so TLS sessions and HTTP
  connections survive between calls instead of paying a new handshake per
  request. Redirect enforcement is routed per task through
  `AutoHTTPRedirectRouter` and remains host-allowlist aware.
- **HTTP paths now have regression coverage.** A registered `NSURLProtocol`
  serves deterministic in-process endpoints (`http://autosdk.test`) covering
  data requests, downloads, redirects, response byte limits, timeouts,
  remote-script loading, and cancellation.

### Added

- **Built-in toast.** `toast(message)` / `toastLog(message)` no longer
  depend on the template's registered native method: the engine shows a short
  overlay in the host window by default, and hosts can still override it.
- **Device memory information.** `device.getMemoryInfo()` returns
  `totalBytes` / `freeBytes` / `appUsedBytes` from Mach APIs.
- **File move/rename/writeLines.** `file.move` (native, same budgets and
  guards as copy), `file.rename` and `file.writeLines` wrappers.
- **Narrower system-control gate.** `allowSystemControl: @NO` no longer
  disables read-only device information (`device.getModel()`,
  `device.getMemoryInfo()`, screen size); only clipboard, brightness,
  volume, vibration and URL opening are gated.

- **Third-party onboarding.** New `docs/QUICK_START.md` walks a newcomer
  from clone to installed IPA and debugged script in about ten minutes;
  `docs/AUTOSCRIPT_COMPARISON.md` compares positioning and API coverage with
  the AutoScript-style standalone tool. The README links both.
- **Self-contained template scripts.** `hello.js` no longer depends on UI
  that does not exist in the template; `demo-api.js` exercises device,
  sandbox files, storage, cooperative timers, and system control without
  specific UI, and guards HTTP behind the reported capability.
- **WDA system-action capability.** `AutoWDAHTTPAdapter` reports
  `systemActions: @YES` so scripts can detect home-screen/lock/unlock
  support through `auto.capabilities()`.

- **System control APIs.** `device` gains `getClipboard` / `setClipboard`,
  `getBrightness` / `setBrightness`, `getVolume` and `vibrate`; `app` and the
  top-level `auto` / globals gain `openURL`, `homeScreen`, `lock` and
  `unlock`. Clipboard text is capped at 1 MiB, brightness is validated to
  0...1, and `openURL` rejects file/data/javascript/ftp/websocket schemes
  while allowing `http(s)` and safe custom schemes. All operations are gated
  by the new `allowSystemControl` config key (default `YES`) and reported as
  the `systemControl` capability.
- **WDA system endpoints.** `AutoWDAHTTPAdapter` implements the optional
  `goToHomeScreenWithError:` / `lockDeviceWithError:` /
  `unlockDeviceWithError:` adapter methods via `/wda/homescreen`, `/wda/lock`
  and `/wda/unlock`; adapters that do not implement them return
  `AutoSDKErrorAutomationUnavailable`.

- Regression tests: pure-JS loop timeout, timer-callback loop timeout
  (including that the engine stays usable afterwards), missing-path errors,
  division expression `1/2` disambiguation, and proxy reserved-key /
  `JSON.stringify(auto)` behavior.
- `docs/SCRIPT_EXECUTION.md`: run lifecycle, input classification, timeout
  and interruption model, timer semantics, result shape and error codes.
- Regression tests: inline source ending in `.js`, stop-before-evaluation
  pure-JS loop, and oversized array results.
- `Tests/AutoSDKTests/AutoHTTPProtocolTests.m`: in-process `NSURLProtocol`
  HTTP coverage for the shared session.

### Notes

- iOS source changes are validated by the repository static checks
  (`npm run verify`) and the Node tool tests; compilation and simulator
  tests run on macOS via `.github/workflows/ios-build.yml`.

## 1.1.2

Version metadata (`AutoSDKVersionString`, CocoaPods `AutoSDK.podspec`,
`package.json`) is aligned at 1.1.2. Earlier release history is not tracked
in this file.
