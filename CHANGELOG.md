# Changelog

All notable changes to AutoSDK are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

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
