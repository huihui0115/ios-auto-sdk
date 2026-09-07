# Changelog

All notable changes to AutoSDK are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.40.0] - 2026-09-07

### Added

- Automatic low-memory profile for devices with up to 2 GiB RAM, targeting iPhone 7:
  bounded node visits, image working buffers, script input and retained logs.
- Per-run finite iOS background assertions with exactly-once release and run-scoped
  expiration, memory-warning cancellation/cache release and serious-thermal protection.
- Native regression coverage for resource budgets, repeated/cyclic node walks,
  concurrent/cancelled captures and background/pressure lifecycle edge cases.

### Fixed

- Removed the built-in node traversal's recursive block retain cycle and enforced
  visit limits even when a selector never matches. Incomplete searches report errors.
- Image metadata is checked before built-in/file-image decoding; visual work is
  single-flight per built-in adapter, pixel buffers are cleaned up on early exits,
  matching has cancellation/work budgets, and cancelled captures cannot restore caches.
- Phone editor logs are bounded and batch-rendered. Replaced obsolete WDA performance
  advice and clarified cooperative cancellation, finite background time and untested
  iPhone 7 behavior. No entitlement, permanent keep-alive or automatic action replay is added.
- Native CI caught and fixed an autoreleased error escaping an inner pool during
  capture/node cancellation. HTTP regressions now isolate engines and synchronize
  cancellation with request start instead of relying on a sleeping utility worker.

## [1.39.0] - 2026-09-07

### Added

- Extension 0.14.0: a Chinese activity-bar device dashboard with LAN scan cards,
  one-click add/connect, reconnect/re-pair, a sample script, run/selection/stop,
  Inspector, logs and bundled offline help. Manual-IP/USB remain advanced fallbacks.
- Host-owned action allowlist and opaque scan keys; cancellation, duplicate-click,
  workspace-change and running-script guards; real Webview and activation regressions.
- Optional isolated Chromium smoke test validates CSP, clickable controls and
  240/320px sidebar layouts without requiring a real phone.

### Fixed

- Empty VS Code windows can save pairing safely; failed secret writes restore
  the previous global URL. Sidebar actions run the displayed JS/TS editor after
  focus moves, and reject closed editors and untrusted workspaces.
- Chinese Inspector controls and button-first HTML/extension documentation.
- Bootstrap remains 61262 / 61440 UTF-16 units; no runtime API or native behavior changes.

## [1.38.2] - 2026-09-07

### Fixed

- Extension 0.13.1 compares normalized pairing URLs: Bonjour omits the trailing
  slash while VS Code settings save URL.href. Freshly added devices now enter
  automatic connection testing/recovery, with workspace and phone guards intact.
- Two regression tests cover canonical-target equality and the real recovery
  entry condition. Extension tests: 123. Native code is unchanged from v1.38.1,
  whose full iOS simulator test and IPA build/publish passed.

## [1.38.1] - 2026-09-07

### Fixed

- A queued timeout-watchdog callback now checks the run's completion gate before
  stopping the engine or cancelling the adapter, so it cannot affect a newer run.
- Native tests fence the shared script and main queues during setup/teardown;
  timed-out callbacks no longer leak into another test. The bridge-loop stop
  test waits for actual adapter activity instead of a fixed background sleep.
- Cold-start UIKit/JSC functional tests have explicit non-performance budgets.
  v1.38.0 simulator runs exposed this test isolation issue; its 12 new location
  and callback-gate tests all passed, but IPA publication was correctly blocked.

Extension remains 0.13.0. Bootstrap remains 61262 / 61440 UTF-16 code units.

## [1.38.0] - 2026-09-07

### Added

- VS Code extension 0.13.0: explicit Run Selected Code, with empty/multi-selection
  safety and TypeScript language-mode support for untitled/non-TS filenames.
- Deterministic native callback/location tests and executable Webview-controller
  regression tests covering selection changes, cancellation and stale results.

### Fixed

- Location/VPN waits now use a shared 50 ms cooperative cancellation gate with
  monotonic deadlines. Location setup rechecks expiry after manager creation,
  stops updates on cleanup, avoids the blocking main-thread services preflight,
  and wraps CoreLocation errors in AutoSDKErrorDomain with underlying details.
- Inspector no longer restores obsolete request IDs or overwrites a newer
  selection/manual code edit; empty snapshots clear stale code and hidden
  requests always finish their busy lifecycle.
- Bonjour synchronous failures/cancellation no longer leave timers/browsers
  alive; known devices can refresh addresses at the result limit. Pairing
  recovery cannot overwrite a subsequently selected phone/workspace.
- Swift Package Manager explicitly links SQLite, matching CocoaPods.
- Removed obsolete WDA activation guidance and refreshed the product comparison
  around real workflows and explicit capability limits. Bootstrap unchanged:
  61262 / 61440 UTF-16 code units.

## [1.37.0] - 2026-08-20

### Added

- Upgraded the VS Code extension to 0.12.0 with cancellable multi-iPhone Bonjour
  discovery, in-place token re-entry/retry, and a direct Wi-Fi add action when
  editor Run is used before a device is configured.

### Changed

- Migrated iOS CI to macOS 15, Xcode 15/16-compatible result diagnostics, and
  the Node 24 artifact/Pages actions; diagnostics now run only when the XCTest
  step itself fails.
- Consolidated quick-start guidance into `docs/index.html`, capability-guarded
  its first screenshot example, and clarified free-signing and cross-app
  Inspector boundaries.

### Fixed

- Propagated nested bridge failures through `execSync`, async `getResult`, and
  `join` instead of returning a misleading value with an empty outer
  `lastError`; corrected the `AutoThreadHandle.join()` TypeScript result type.
- Kept Bonjour discovery listening long enough to collect slower second phones,
  avoided duplicate connection-error dialogs, and renamed the Inspector's
  pixel-sampling mode from Point to Color.

## [1.36.1] - 2026-08-20

### Fixed

- Made the native low-power and location-state regression tests deterministic by
  injecting raw system state in XCTest instead of consulting a cold simulator's
  live CoreLocation service. Production builds still query the real iOS APIs.

## [1.36.0] - 2026-08-20

### Added

- Added `vpn.status/connect/disconnect/openSettings` for the Personal VPN
  configuration owned by the host app, with bounded preference loading,
  truthful status values, and actionable errors for missing entitlement or
  profile configuration.
- Added `system.openSettings(panel)` for common iOS Settings destinations,
  `device.isLowPowerModeEnabled()`, `location.isEnabled()`, and
  `location.getAuthorizationStatus()`.

### Changed

- Reorganized the Device & System API documentation into one deduplicated
  section and upgraded the VS Code extension to 0.11.0 with completion coverage
  for every declared `AutoDeviceAPI` method plus the new VPN/system helpers.
- Linked NetworkExtension and CoreLocation consistently for Swift Package
  Manager and CocoaPods while keeping the Personal VPN entitlement an explicit
  host-app signing requirement.

### Fixed

- Fixed one-shot location access to wait for the first authorization callback,
  distinguish a temporary no-fix result from real permission/configuration
  failures, and clean up safely across hard timeouts.
- Added the missing location usage description to the template and stopped the
  native bridge from silently discarding CoreLocation errors.

## [1.35.2] - 2026-08-20

### Fixed

- Replaced the nonexistent Network.framework `nw_listener_set_service` call
  with an official Bonjour advertise descriptor and
  `nw_listener_set_advertise_descriptor`, restoring Xcode compilation while
  preserving the authenticated `_autosdk._tcp` discovery flow.

## [1.35.1] - 2026-08-20

### Fixed

- Made USB helper discovery use `path.win32` or `path.posix` according to the
  requested target platform instead of the machine running the test. This fixes
  macOS release validation while preserving Windows `iproxy` sibling lookup.
- Prevented VSIX dependency generation from linking the repository root into
  `node_modules`; verification now rejects that packaging regression.

### Changed

- Upgraded the VS Code extension patch version to 0.10.1 and added a portable
  POSIX-path regression assertion.

## [1.35.0] - 2026-08-20

### Added

- Added `_autosdk._tcp` Bonjour advertising whenever authenticated Wi-Fi
  debugging is enabled. The template publishes a stable per-installation name
  and declares the required local-network service without exposing its token.
- Added bounded multicast-DNS discovery to the VS Code extension. The normal
  status-bar flow now scans the LAN, lists AutoSDK iPhones, saves the selected
  identity, and immediately tests the connection.

### Changed

- Made direct Wi-Fi the default plugin workflow and moved USB/libimobiledevice
  discovery to an advanced command. Manual setup now accepts a bare phone IP
  and adds `ws://` plus port 9001 automatically.
- Upgraded the VS Code extension to 0.10.0 and expanded its suite from 90 to 97
  tests.

### Fixed

- Reuses a saved SecretStorage token only when the rediscovered Bonjour identity
  matches, allowing one-selection reconnect after DHCP address changes without
  leaking credentials to another phone.
- Device identity settings now roll back together if connection persistence
  fails midway.
- Excluded the temporary npm cache from VSIX packaging, reducing the verified
  plugin artifact from 47 MB to 1.75 MB.

## [1.34.0] - 2026-08-20

### Added

- Added **AutoSDK: Search and Add iPhone**, which discovers USB devices with
  bounded, shell-free `idevice_id` / `ideviceinfo` calls, saves the selected
  UDID, starts the managed tunnel, and tests the connection.
- Added direct Wi-Fi fallback when USB tools or devices are unavailable.
- Added **Run Current Script** to JavaScript/TypeScript editor context menus
  and the editor title bar.

### Changed

- Changed the disconnected status-bar action to open device discovery and
  upgraded the VS Code extension to 0.9.0.
- Expanded the extension suite from 83 to 90 tests.

### Fixed

- Avoided prefilling a token from a different USB phone and restored the
  previous UDID if saving the new connection fails.

## [1.33.0] - 2026-08-20

### Added

- Added one canonical offline developer site at `docs/index.html` with seven
  task-focused guides, 14 API modules, global search, module filters, deep
  links, mobile navigation, theme switching, and copyable examples.
- Added generation checks that require all 263 API examples to parse as
  JavaScript and all API entries to appear in the canonical site.

### Changed

- Consolidated the old portal, tutorial, developer site, and API cards into
  one generated entry point and removed the three redundant HTML documents.
- Made `generate-api-reference.mjs` metadata-only and simplified `npm run docs`
  to generate the canonical site once.

### Fixed

- Corrected the `file.writeFile` newline example and two `node` examples that
  shadowed the global namespace.
- Documented `http.getJSON` as returning `AutoHTTPResponse`, with parsed data
  available through `response.json`.

## [1.32.0] - 2026-08-20

### Added

- Added focused completion coverage for `thread`, `utils`, `ocr`, `ws`,
  `sqlite`, `yolo`, `location`, `colors`, `speech`, `pasteboard`, `json`,
  `floatLog`, `metrics`, and `base64`, including `action` / `string` aliases.
- Added the missing `speech` namespace TypeScript declaration.

### Fixed

- Replaced the VS Code completion provider's hard-coded namespace allowlist
  with a tested pure model and split 25 grouped signatures into valid,
  independently insertable snippets.
- Made Inspector selection keys independent of selector-property order and
  generated the smallest unique readable selector, adding `type` only when
  needed to disambiguate a match against the full correlated snapshot rather
  than only the current selector-result subset.
- Moved Inspector selector/point/OCR/image/color script generation into its
  pure model with deterministic escaping and regression coverage.
- Upgraded the VS Code extension to 0.8.0 and expanded its suite to 83 tests.

## [1.31.0] - 2026-08-20

### Added

- Added an Inspector **Cancel** button and `Escape` shortcut that abort the
  active client request, drops queued stale work, and immediately restores the
  panel controls.
- Added `autosdk.inspectorActionRefreshDelay` (`0...5000` ms, default `400`) so
  click/input/scroll refreshes can wait for target-app animations to settle.

### Fixed

- Prevented superseded, hidden, disposed, or cancelled Inspector requests from
  committing `lastSnapshot` and becoming the next exported snapshot.
- Clamped Webview screen picks to valid `0...width-1` / `0...height-1` pixels,
  rejected zero-area hit targets, and preferred the deepest later node when
  equal-size controls overlap.
- Silently consumed late responses for explicitly aborted device requests while
  retaining diagnostics for genuinely unknown responses; the ignore set is
  bounded to 128 request IDs.
- Upgraded the VS Code extension to 0.7.0 and extended regression/verification
  coverage for cancellation, lifecycle commits, geometry, and delay bounds.

## [1.30.2] - 2026-08-11

### Fixed

- Fixed standalone Xcode/Swift Package compilation of the generated bootstrap
  translation unit by importing `AutoBootstrapScript.h` from the generator.
- Extended verification so regenerated bootstrap Objective-C always carries its
  Foundation-backed declaration while preserving the single-source JS contract.
- Fixed the next Xcode compile blockers in `AutoEngine.m`: SQLite pointers are
  boxed in `NSValue`, the media downloader is forward-declared, and speech no
  longer boxes the `void` result of `speakUtterance:`.
- Replaced the nonexistent `VNRecognizeObjectsRequest` with the public iOS 15+
  `VNClassifyImageRequest`; the legacy `yolo.detect` entry now honestly returns
  bounded full-image classifications rather than fabricated object boxes.
- Fixed runtime XCTest failures found after compilation: `deleteAllFile` now
  accepts files as well as directories, `auto.node` is wired, `auto.click`
  preserves its public arity, and notification setup contains unavailable-host
  Objective-C exceptions instead of terminating the process.
- Completed the same XCTest pass by wiring `auto.screen`/`auto.floatLog`, treating
  `{files, formData}` as POST options when passed as the second argument, and
  bypassing notification-center setup when no `.app`/`.appex` host exists.

## [1.30.1] - 2026-08-11

### Fixed

- Fixed Xcode 15.4 ARC compilation of the built-in Accessibility adapter by using
  explicit Core Foundation bridges and Objective-C-compatible child collections.
- Corrected the built-in node selector's case-insensitive `type` comparison,
  whose previous logical-not precedence could invert the match result.
- Added verification anchors so unsafe AX pointer generics/casts cannot silently
  return in a later release.

## [1.30.0] - 2026-08-11

### Changed

- **VS Code 插件 0.6.0 / Inspector 结构重构（Round 60）**：把设备可视化协议、
  Inspector 会话状态和 Webview 节点/坐标模型从 `extension.js` 拆到
  `inspector-service.js`、`inspector-session.js` 与 `media/inspector-model.js`，
  普通截图、节点 JSON 与可视化面板共用严格的协议校验。
- 截图、节点、点色、OCR、找图和节点动作统一经过串行可视化通道，适配手机端
  单重任务限制；同类排队请求只保留最新结果，避免并发 `device busy` 和迟到响应
  覆盖新状态。旧的无调用方 `CoalescingRunner` 已删除。

### Added

- Inspector Webview 请求/响应增加 requestId 关联与忙碌状态；刷新后按稳定
  nodeId/handle 恢复节点选择。
- 新增 `autosdk.inspectorMaxNodes`（1...2000，默认 1000）和 **Export** 操作，
  可导出包含 PNG base64、节点树、设备信息、snapshotId 和耗时的单文件 JSON 快照。
- 插件新增采集服务、会话队列和几何/选择器模型测试；插件测试 64 项。

### Fixed

- 修复 Inspector 与独立截图/节点命令可能同时发起重请求、触发手机端
  `The device is busy processing earlier debug requests` 的竞态。
- 修复旧响应可能晚于新刷新返回并覆盖节点列表、选中项或图像结果的问题。
- 同步修正文档中的旧函数统计和 no-WDA XPath 支持说明；bootstrap 保持
  60526/61440（余量 914），脚本 API 与原生运行时零改动。

## [1.29.0] - 2026-08-07

### Added

- **TrollAutoScript 对标补齐（Round 59）**：以 `docs.trollautoscript.com` sitemap（315 页）做模块级盘点后补齐最后高频缺口：
  - `string.atrim(text)`：去除全部空白（含字符串中间），全局 `atrim` 同步导出。
  - `isInteger(text)`：`isIntrger` 的正确拼写别名（两者等价，保留旧名兼容）。
  - `string.random(len, chars)`：随机字符串，等价全局 `randomString(len, chars)`。
  - `pasteboard.read() / pasteboard.write(text)`：剪贴板命名空间，兼容既有 `getPasteboard/setPasteboard` 全局函数。
  - `json.encode(value) / json.decode(text)`：JSON 命名空间，decode 解析失败返回 null 不抛异常。
  - `device.setBacklightLevel(value) / device.backlightLevel()`：背光别名（与 setBrightness/getBrightness 同源），`auto.*` 代理自动可达。
- 文档生成器新增对应函数卡与示例，文档 263 函数 / 28 页。

### Fixed

- 修复 bootstrap 初始化顺序 bug：`stringsApi` 扩展赋值原位于尾部别名区，晚于全局导出 `forEach` 执行，导致 `g.atrim`/`g.isInteger` 为 undefined；已移至导出列表之前。
- bootstrap 60088→60526/61440（余量 914B）；Node 测试 87 项全部通过。

## [1.28.0] - 2026-08-07

### Added

- **lastError() API（复盘建议落实）**：返回最近一次原生调用失败的错误对象
  `{code, message, domain?, underlying?}`，无错误返回 null。用于区分「函数正常
  返回 false」与「调用失败返回 false」（execSync/http/sqlite 等场景）。
  原生侧新增 `invokeLastError` 桥接（含 NSUnderlyingError 透传）。
- **gx 批量别名助手（三轮压缩）**：`function gx(o,n){n.forEach(...)}` 统一 81 个
  同名全局导出（base 48 + deviceApi 12 + fileApi 11 + appApi 3 + mediaApi 7），
  bootstrap 61391→60088/61440，预算余量从 49B 恢复到 1352B。
- **真机验证清单更新**：确认 GitHub Actions（macos-14：verify + npm test +
  Xcode 模拟器测试 + IPA 打包 + Release）每次 push 自动覆盖原生编译；
  R53-R58 真机抽查项记入 AI_HANDOFF。

### Fixed

- 修复 bootstrap.test.mjs 历史嵌套问题：Round 56 的位图测试因插入点错误被嵌套进
  isRunning 测试内部（TAP 计划 1..85 与 tests 86 不符），已还原为顶层测试。
## [1.27.0] - 2026-08-07

### Added

- 全项目复盘审计轮：系统审计文件沙盒、zip 解压、HTTP 重定向策略、调试服务帧解析、
  SQLite 句柄管理、内置适配器 CoreFoundation 资源配对，均确认无问题。

### Fixed

- **execSync 返回值破坏（真机 bug）**：原生 sync 模式直接返回裸结果，旧 JS 包装
  对 object/array 结果取 `.result` 属性导致静默返回 undefined；现在 execSync
  直返原生值（失败时为 false），Node 测试 mock 同步改为真实契约并新增对象返回值回归断言。
- **定时器回调异常中断 drain 循环**：任一定时器回调抛异常会终止整个 drainTimers，
  连累同轮所有后续定时器；现在 try/catch 隔离单个回调异常并经 console.error 上报，
  其余定时器照常执行（interval 也照常续订）。
- **execAsync 内存增长**：完成的异步线程对象持有 JSContext 直到脚本停止；
  长脚本大量短任务会持续累积。现在线程完成后立即释放 JSContext（结果/错误已提取，
  join/getResult/cancel 语义不变）。
## [1.26.0] - 2026-08-07

### Added

- **位图模型（EasyClick 对标，路径句柄语义）**：
  - `image.readBitmap(path)`：加载位图句柄 `{path, isBitmap}`；
  - `image.saveBitmap(bitmap, dest)`：位图另存为（复制底层文件）；
  - `image.bitmapBase64(bitmap)` / `image.base64Bitmap(base64, path)`：Base64 互转；
  - `image.bitmapToImage(bitmap)`：解包为沙盒路径；
  - `image.getBitmapPixelColor(bitmap, x, y)`：取位图像素颜色；
  - 句柄可直接传给 image.compress/clip/scale/gray/rotate/pixelAt/toBase64/
    getWidth/getHeight/getSize（_ff 与尺寸查询自动解包）；ocr.newOcr 实例方法同样支持。
  - 语义说明：EasyClick 位图是内存对象，本 SDK 采用沙盒文件句柄——能力等价、零额外内存；
    EasyClick scaleBitmap/rotateBitmap/clipBitmap 由 image.scale(handle,...,dest) 等文件落盘等价覆盖，
    releaseBitmap 因无内存驻留不再需要。
- **二轮压缩重构（-334B）**：fileApi/deviceApi 的 EasyClick 别名（readFile/writeFile/
  readAllLines/getLineText/md5File/sha1File/mkdirs/getSandBoxDir/getSandBoxFilePath/
  getDeviceInfo）由自转发包装改为 guard 后直接引用赋值（且保持别名===原函数的恒等性）；
  getPixelColor/getColor/base64.encode/decode/time 改直接引用；新增 bp/bh/fb 句柄助手。

### Fixed

- 无行为性 bug 修复（本轮 83 项 Node 测试全绿，含新位图往返测试）。
## [1.25.0] - 2026-08-07

### Added

- **http.head / http.patch REST 动词**：`http.head(url, options?)`、`http.patch(url, body?, options?)`，
  与 get/post/put/delete 一致走统一 guard 与 options 通道，REST 全家桶补齐。
- **http.requestEx(url, options?)**：EasyClick 兼容别名，与 http() 完全等价，
  返回完整响应对象（status/headers/body）。
- **ocr.newOcr(defaults?) OCR 引擎实例**（EasyClick 对标）：实例方法
  `ocrImage(path, options?)` / `ocrBitmap(bitmap, options?)` / `ocr(path, options?)`
  对沙盒图片文件做 Vision OCR（经 screenshotPath 通道，而非当前屏幕），
  每次调用自动合并实例默认参数；ocrBitmap 接受路径或 {path} 句柄。
- **bootstrap 压缩重构**：删除 guard 前 6 处死重别名与 getJSON 重复定义，
  get/post/put/delete 内联函数统一为 `function hv(m,b)` 动词工厂，净省 328B
  （61416→61283/61440，余 157B），为后续功能腾出预算。

### Fixed

- **文档生成器 bug**：ocrClick 示例卡混入一行无关映射表项
  （`'ocrBaidu(...)': '...'`），用户复制示例即语法错误，已清除。
## [1.24.0] - 2026-08-07

### Added

- **http.put / http.delete REST 便捷别名**（对标 AScript/EasyClick HTTP 全家桶）：
  - `http.put(url, body?, options?)`：自动带 body 的 PUT 请求；
  - `http.delete(url, options?)`：DELETE 请求；
  - 与既有 `http.get/getJSON/post/postJSON` 一致，均走统一 guard 与 options 通道；
  - d.ts、api-reference、devdocs、verify 锚点、Node 测试（81 个）同步。
- **对标 ascript.cn/docs/ios API 分类审计**：AScript 14 大分类（application/action/
  node/screen/ui/webwindow/http/thread/db/file/media/cloud/system/python），本项目
  15 类全覆盖，无类目级缺口（见 docs/EASYCLICK_COMPARISON.md Round 54 记录）。

### Fixed

- **HTTP multipart Content-Disposition 头注入漏洞**：表单字段名、文件字段名、上传
  fileName（lastPathComponent）此前未经校验直接拼入 Content-Disposition 头，
  含引号或 CR/LF 控制字符的恶意/异常名称可注入任意 HTTP 头、走私请求体；
  新增 `AutoHTTPFieldNameIsValid()`（拒绝引号与一切控制字符），在全部 3 处上传点
  统一拦截并返回明确错误（安全审计修复，行为对合法名称零影响）。
## [1.23.0] - 2026-08-06

### Added

- **内置 no-WDA 适配器支持 xpath 子集**（此前直接报错拒绝，对标 AScript/EasyClick 的最大剩余缺口）：
  - `AutoBuiltinXPathToQuery` 把单步 xpath 翻译为原生查询键：`//Button`、`//*`、
    `//*[@text='确认']`、`//*[contains(@text,'确认')]`、`starts-with()/ends-with()`、
    `[@a='x' and @b='y']` 组合、位置下标 `//ScrollView[2]`；
  - 属性映射 @text/@label/@name/@value/@id/@type/@index/@depth；contains/starts/ends
    走正则转义后的 *Match 通道，值里的括号/引号/`and` 均被正确处理；
  - 有界设计：xpath 512 字符上限、单谓词块、单步（禁嵌套路径）、未知属性/未加引号
    文本值/非法节点名全部显式报错；`predicate` 仍不支持（清晰错误）；
  - `capabilities` 新增 `xpathSubset` 键；选择器 API 卡片、devdocs 选择器指南与 FAQ 同步。

### Fixed

- xpath 翻译器条件路由：`@text='contains(x)'` 这类「值里带括号」的等值条件曾被误判为
  函数调用而报错，现按 `=` 与 `(` 的先后正确路由。

## [1.22.0] - 2026-08-06

### Added

- **devdocs 对标 AScript 再补 3 篇指南**（25→28 页）：
  - 「图色识别」：findColor/findColorEx/findImage/OCR/YOLO 实战 + screen.cache 用法；
  - 「发布程序」：内置脚本/远程脚本分发、签名矩阵（免费签/TrollStore/企业签/App Store）、
    上架前检查清单（对齐 AScript 的「发布程序」页）；
  - 「常见问题 FAQ」：签名降级、xpath 支持范围、分辨率适配、死循环停止、调试入口。

### Fixed

- **SQLite 结果集封顶**：`sqlite.query` 最多返回 10 万行（`AutoSQLiteMaxRows`），
  防止大表 SELECT 撑爆内存/序列化。
- **SQLite 多语句显式报错**：此前一次传入多条 `;` 分隔语句会静默只执行第一条，
  现在 prepare 后检查 tail，发现剩余语句立即报错提示拆分调用。

## [1.21.0] - 2026-08-06

### Added

- **截图缓存端到端生效**：`screen.cache(true)` 传入的 `screenshotPath` 现在被原生真正
  读取——内置适配器新增 `screenPNGWithOptions:`（findColor/compareColors/findMultiColor/
  findImage/ocr 接入），UIKit 适配器新增 `screenImageHonoringCachedPath:`（findColor/
  findImage/ocr 接入），引擎 `AutoEngineScanColorPoints` 新增 `cachedScreenPath` 参数
  （findColorEx/findNotColor 接入）；路径限定 App 沙箱内，缓存文件缺失时自动回退实时截图。
- **findColorEx/findNotColor 纳入缓存**：bootstrap 经 `cachedOptions` 为两者注入
  `screenshotPath`，screen/image/base 三侧入口全部复用同一张缓存截图。
- **新增对标全局函数**：`waitFor(selector, timeout?)`（EasyClick waitNode / AutoJS waitFor）、
  `currentPackage()`（AutoJS，前台 App bundleId）、`setClip/getClip`（AutoJS 剪贴板别名）。
  d.ts/API 卡片/verify 锚点/Node 测试同步（测试 81 项）。

### Fixed

- `parseColor/int2Hex/hex2Int`：原正则 `/^#|0x/i` 会剥掉字符串**中间**的 `0x`
  （如 `f0xf0f` 被误解析），现只剥离开头的 `#`/`0x` 前缀。
- `strings.padStart/padEnd`：填充串传空字符串时 `while` 死循环，现直接返回原串。

### Changed

- bootstrap 压缩 -204B（61405→61201/61440）：删除重复的 `cachedRegion`（与 cachedOptions
  完全相同）、`touchAndSlide`/`appApi.openURL`/`appApi.getAppVersion`/`appApi.getPackageName`/
  `imageApi.toBase64`/`imageApi.findColorCount`/`speechApi.tts`/`speechApi.stopSpeak`
  包装函数改为引用委托。

## [1.20.0] - 2026-08-06

### Added

- **EasyClick 风格低级触摸原语 `touchDown/touchMove/touchUp`**：按 finger 编号
  分指暂存（默认 0），`touchUp()` 无参时同时抬起全部已按下手指（一次 multiGesture
  回放），可组合拖拽、长按移动、自定义多指手势；d.ts/API 卡片/verify 锚点/Node 测试
  同步（测试 80 项，文档 258 函数）。bootstrap 61405/61440。
- **devdocs 新增「高级指南」分组**（对齐 AScript 文档结构）：多线程（execAsync/
  定时器）、数据库（sqlite）、网络通信（http/downloadFile）三篇可直接复制运行的
  散文教程；侧栏分组变为 开始/控件检索/高级指南/API 参考。

### Fixed

- 内置 no-WDA 适配器 `findImage`：外层扫描循环未检查比较次数上限，达到
  `AutoBuiltinMaxImageComparisons` 后仍继续空转迭代，现外层循环同样受上限约束。

## [1.19.0] - 2026-08-06

### Added

- **内置 no-WDA 适配器模板找图 `findImage`**：系统级截图 + 有界两阶段匹配
  （粗采样定位→全像素验证，逐通道容差 24），`similarity`/`threshold` 默认 0.9、
  `region` 限定区域、`maxCandidates` 默认 64（上限 512），像素比较总数封顶
  60M 保证有界；返回 {found, x, y, width, height, centerX, centerY, similarity}
  （点坐标）。capabilities 的 `findImage` 如实报 YES。
- **App 中文名启动库**：内置 60+ 常用应用 name→bundleId 映射（微信/支付宝/淘宝/
  京东/拼多多/抖音/快手/哔哩哔哩/美团/高德/钉钉/设置/相机/Safari…），
  `app.launch("微信")` / `app.terminate("淘宝")` / `app.appState("抖音")` 直接可用，
  对标 AScript `system.app_start("微信")`；传 bundleId 行为不变。

### Changed

- 文档同步：NO_WDA_ARCHITECTURE 已知限制更新（findImage 已实现）、
  EASYCLICK 对比矩阵图色/应用控制行、api-reference 卡片 desc、
  MARKET_RELEASE 已知边界。verify 新增两个内置适配器锚点。

### Notes

- 零 bootstrap JS 改动（60895/61440，余 545B）；Node 测试 79 项；
  内置适配器真机验证仍为下轮优先待办。

## [1.18.0] - 2026-08-06

### Added

- **AScript 风格开发文档站** `docs/devdocs/index.html`（`npm run docs` 生成）：
  左侧分类树（开始 / 控件检索 / 15 个 API 分类）+ 8 个散文页（介绍、安装与签名、
  连接与调试、第一行代码、工程结构、选择器、控件对象、控件查找器）+ 257 个函数块
  （签名/描述/参数表/返回值/一键复制可运行示例/每分类调试提示）；顶栏全文搜索、
  hash 路由、暗色主题、单文件离线。对标 ascript.cn/docs/ios 的文档体验。
- 门户 `docs/index.html` 与 README 增加文档站入口；verify 增加文档站锚点
  （函数块数 == APIS 数、散文页/复制按钮存在）。

### Fixed

- **文档渲染遗漏**：`speech`（TTS）与 `base64` 两个分类不在 CATEGORIES，
  对应函数卡片在 api-reference.html 从未渲染——speech 补进 CATEGORIES，
  base64 归入"定时器与工具"，257 个函数现在全部可见。

### Notes

- 零 bootstrap 改动（60895/61440，余 545B）；Node 测试 79 项；
  内置 no-WDA 适配器真机验证仍为下轮优先待办。

## [1.17.0] - 2026-08-06

### Removed

- **外部 WDA 适配器完全移除**：`AutoWDAHTTPAdapter.h/.m`（~1300 行客户端）、
  24 个 WDA 专用 Xcode 测试、42 个 verify 锚点、模板 App 的 WDA 配置分支与
  Info.plist 的 `AutoSDKWDA*` 键、`docs/WDA_ADAPTER.md`。内置 no-WDA
  （`AutoBuiltinAdapter`）从此是**唯一**跨 App 路线，不再保留 legacy 回退，
  避免双路线维护成本（用户决策：只做内置 no-WDA）。

### Added

- **内置 capabilities 补齐**：新增 `appList`/`appLifecycle`/`systemActions`
  键，按运行时私有符号解析结果如实报告（此前只有 WDA 适配器报告这些键，
  导致 demo/脚本的 capability 门控在内置适配器下误判）。
- **verify 防回退锚点**：断言 WDA 文件不存在、AutoSDK.h/模板无 WDA 残留、
  模板默认 BUILTIN。

### Changed

- **模板 App**：`makeAutomationAdapter` 简化为"默认内置、UIKIT 显式回退"；
  设置页 WDA 区块（URL/BundleID/超时/Apply）替换为单一
  "Built-in no-WDA adapter" 开关；Info.plist 默认 `AutoSDKAdapter=BUILTIN`。
- **文档全量同步**：README/QUICK_START/MARKET_RELEASE/NO_WDA_ARCHITECTURE/
  NODE_OPERATIONS/PERFORMANCE/WINDOWS_SIDELOAD 等改为内置唯一路线叙述；
  历史审计文档（ASCRIPT/AUTOSCRIPT/TROLLSTORE_WDA_LUA/LUA_FRAMEWORK_AUDIT/
  NO_TROLLSTORE）加 v1.17.0 归档 banner；docs 门户与教程页卡片更新；
  api-reference 卡片与 VS Code 扩展措辞去 WDA 化。

### Notes

- 零 bootstrap JS 改动（60895/61440，余 545B）；Node 测试 79 项不变；
  文档 257 函数不变。内置适配器真机验证仍为下轮优先待办。

## [1.16.0] - 2026-08-06

### Added

- **内置 no-WDA 适配器 `AutoBuiltinAdapter`**：跨 App 自动化主路线，不再依赖外部
  WDA Runner（对标 AScript Agent no-WDA 模式 / kuaijs）：
  - **IOHIDEvent 真实触摸注入**：系统级 digitizer 事件（tap/长按/滑动/拖拽），
    W3C 多点手势时序回放（performMultiTouch 按相对 duration 毫秒播放）。
  - **AXUIElement 系统级控件查询**：跨 App 毫秒级检索，支持
    text/label/name/value/id/type 及各自正则匹配、enabled/selected/depth/index/bounds
    过滤与关系遍历；句柄 `axb:<索引路径>`，描述符键与 UIKit 适配器一致。
  - **应用控制**：LSApplicationWorkspace 已装应用列表、SpringBoard 启动、
    BackBoard 终止、前台 bundleId 检测、锁屏、打开系统设置页（App-prefs 解锁）。
  - **截图与图色**：UIGetScreenImage 系统级截图（宿主窗口回退），
    pixelColor/findColor/compareColors/findMultiColor 位图扫描，Vision OCR。
  - 所有私有符号 dlopen/dlsym 运行时解析，不链接任何私有框架；
    capabilities 按运行时解析结果如实降级（scope=systemWide, adapter=builtin）。
- **模板 App**：`makeAutomationAdapter` 支持 `BUILTIN`/`BUILTIN-NOWDA`/`NOWDA`，
  新增配置键 AutoSDKMaxSnapshotNodes/AutoSDKMaxSnapshotDepth/AutoSDKScreenshotCacheDuration。
- **文档**：新架构文档 `docs/NO_WDA_ARCHITECTURE.md`（架构/能力表/启用方式/
  签名要求/真机验证计划/已知限制）；README 与 MARKET_RELEASE 改为内置优先叙述。

### Changed

- **WDA 降级**：`AutoWDAHTTPAdapter` 保留为 legacy 回退，不再是跨 App 主路线。
- **verify**：新增内置适配器静态锚点（IOHID/AX/SpringBoard 符号、scope systemWide、
  禁止静态 import 私有框架头、模板 BUILTIN 接线）。

### Notes

- 触摸注入与系统级 AX 需允许私有 API 的构建（TrollStore/开发者签名）；
  真机验证列入下轮待办。本轮零 bootstrap JS 改动（60895/61440，余 545B）。

## [1.15.0] - 2026-08-06

### Added

- **node.allChildren()**：EasyClick 语义的递归子孙遍历——返回节点下所有层级
  子孙（深度优先），全部为包装节点。
- **测试**：新增 allChildren 递归用例与 boundsInfo 回归用例（共 79 项）；
  测试 mock 的 invokeGetChildren 升级为按 handle 返回层级数据。

### Fixed

- **boundsInfo 潜在 TypeError**：rect/center 原先以不可重定义方式挂载，
  无 bounds 节点首次 boundsInfo() 刷新时会抛 TypeError；dp helper 统一改为
  configurable 定义，重定义安全。

### Changed

- **bootstrap 压缩 -405B（61300→60895，余 545B）**：wrapNode 内所有属性挂载
  统一走 dp(n,v) helper（configurable:!0），nr 工厂同步简化。

## [1.14.0] - 2026-08-06

### Added

- **EasyClick 节点关系方法**：节点对象新增 children()/parent()/siblings()/
  nextSiblings()/previousSiblings()，返回值均为包装好的节点对象（可继续
  .click()/.attr() 链式操作），对标 EasyClick node 关系遍历。
- **文档**：新增"节点关系遍历"卡片，共 257 个函数 / 257 个可运行示例；
  测试新增节点关系用例（共 78 项）。

### Changed

- **bootstrap 结构优化（+209B，余 140B）**：nr 工厂统一挂载节点关系方法；
  set_text/clear_text 改为直接引用 setText/clearText 函数（-113B 抵消）。

### Notes

- EasyClick allChildren()（递归所有子孙）语义不同，未并入本轮，留待后续。

## [1.13.0] - 2026-08-06

### Added

- **EasyClick 选择器 match 别名**：Selector 链新增 idMatch()/typeMatch()/
  textMatch()/nameMatch()/labelMatch()/valueMatch() 正则匹配方法（EasyClick
  node 选择器兼容；与已有 *Matches 方法同效，原生 UIKit/WDA 适配器早已支持
  idMatch/typeMatch 查询键）。
- **测试**：新增选择器 match 别名查询字段与正则转义用例（共 77 项）；verify
  增加 ss/sx 工厂与六个别名的形态锚点 + 运行时行为断言。

### Changed

- **bootstrap 压缩 -264B（61355→61091，余 349B）**：Selector 的 14 个
  set(k,Str(v)) 方法统一走 ss(k) 工厂、4 个 contains 方法统一走 sx(k) 工厂，
  为后续别名腾出预算。

## [1.12.0] - 2026-08-06

### Added

- **EasyClick 振动别名**：新增 device.vibrateLong()/device.vibrateShort() 及全局函数
  vibrateLong()/vibrateShort()（等价 vibrate(500)/vibrate(50)），对标 AutoJS
  vibrateLong/vibrateShort。
- **测试与校验扩展**：bootstrap.test mock list 改为基于真实 files 映射生成
  （含子目录条目）；新增 deleteAllFile 递归删除与 vibrateLong/vibrateShort 用例
  （共 76 项）。verify 运行时 invokeFile mock 支持 list 并记录最后一次文件操作，
  新增 Round 42 bootstrap 形态锚点与行为断言。
- **文档**：api-reference 重写 deleteAllFile 卡片（清空目录语义）、拆分
  file.remove 卡片、新增长振动/短振动卡片，共 256 个函数 / 256 个可运行示例。

### Fixed

- **deleteAllFile 语义 bug**：原实现只是 remove(path) 的单路径别名；现对齐
  EasyClick file.deleteAllFile(path) 语义——递归删除目录下所有文件与子目录
  （目录本身保留），返回删除条目总数；路径不是目录时返回 0。

### Changed

- **bootstrap 压缩 -79B（61434→61355，余 85B）**：fileApi 的
  readFile/writeFile/create/appendLine/md5File/sha1File/listDir/getSandBoxDir/
  getSandBoxFilePath/mkdirs 改为委托已有方法的别名；insertLineText/resetLineText
  的 join(String.fromCharCode(10)) 统一为 '\n'；console.log/debug/info 共享
  clog 闭包；screen.findColors/isColors/cmpColor 共享 cmpC 闭包。

## [1.11.0] - 2026-08-06

### Added

- **AI 交接文档。** 新增根目录 AGENTS.md（新 AI 自动读取的开发守则：铁律/命令/文件地图）与 docs/AI_HANDOFF.md（架构、仓库地图、当前状态、对标基线、已知缺口、7 节工作流、坑与注意事项、历轮主线）。README 增加入口。

- **bootstrap 单一权威源工具化。** 新增 tools/bootstrap-source.js（bootstrap JS 唯一权威源）与 tools/regenerate-bootstrap.mjs（重新编码进 AutoBootstrapScript.m，含 round-trip 与预算校验）；npm script regenerate:bootstrap；verify.mjs 增加“提交的 .m 必须与权威源完全一致”断言，杜绝手改漂移。

- **历史脚本入库。** tools/bootstrap-history/ 收录历轮 rewrite/extract/bracket 脚本与说明（仅参考，勿对当前版本执行）。

### Fixed

- 文档与工具链一致性：verify 新增单一源校验，防止 bootstrap-source.js 与 .m 失同步。

## [1.10.0] - 2026-08-06

### Added

- **EasyClick thread/utils 命名空间。** 对标 EasyClick thread/utils 模块：thread.execAsync/execSync/cancelThread/stopAll/isCancelled；utils.dataMd5/fileMd5/randomInt/randomCharNumber/getRangeInt/getRatio/zip/unzip/readFileInZip/playMp3/stopMp3/deleteAllPhotos/deleteAllVideos/requestPhotoAuthorization。

- **EasyClick 全局别名。** getPasteboard/setPasteboard 剪贴板、openUrl 打开链接、uploadToAlbum 保存图片到相册、childcount 子节点数；device.applist 应用列表、device.getOrientationNoAuto 方向、device.getDeviceMsg 设备信息；image.captureFullScreen 全屏截图。文档 254 函数，测试 75 项。

### Changed

- **bootstrap 再压缩 880B。** dvf/avf 收敛 deviceApi/appApi 44 处零参 getter，hsh/hsh2 收敛 md5/sha/hmac 系列，arr helper 微缩，布尔参数精简；新增功能后解码 61434/61440（仍低于 60KB 预算）。

### Fixed

- **verify/测试/类型/文档同步。** verify.mjs 断言更新为压缩后文本并新增 thread/utils/别名检查；d.ts 增加 AutoThreadAPI/AutoUtilsAPI 与全局别名；bootstrap 测试新增 round40 用例；EASYCLICK_COMPARISON 增加线程与工具模块行。

## [1.9.0] - 2026-08-06

### Added

- **EasyClick 颜色工具（parseColor/int2Hex/hex2Int/rgb/argb）。** 对标 EasyClick 颜色 API：parseColor/toInt/hex2Int 支持数字、#RGB、#RRGGBB、0x 前缀（无效返回 null）；int2Hex/toHex 输出 #rrggbb；rgb/argb 合成 32 位颜色值；colors 命名空间 + 全局函数双入口。文档 252 函数，测试 74 项。

- **bootstrap 导出再压缩。** 新增 arr() helper 收敛 6 处 slice 调用；stringsApi 三段单条导出改为 forEach 批量导出（trim/ltrim/rtrim/split/chars/toHex/fromHex/isUpper/isLower/isNumber/isIntrger/isLetter/isChinese/isEmail/isLink、startWith/endWith/contains/padZero、toPinYin/stripUtf8Bom/fromUnicode）。

### Fixed

- **修复 location 授权崩溃。** AutoGetLocationSnapshot 调用 requestWhenInUseAuthorization 前先检查宿主 Info.plist 是否声明 NSLocationWhenInUseUsageDescription（未声明直接返回错误，不再触发 NSInvalidArgumentException 崩溃）；权限未决定时先请求授权再定位，已授权直接 requestLocation。

- **verify/测试/类型同步。** verify.mjs 增加颜色与 location 守卫断言；d.ts 增加 AutoColorsAPI；bootstrap 测试新增颜色用例。

## [1.8.0] - 2026-08-06

### Added

- **GPS 定位（location.getLocation(timeoutMs?)）。** 对标 kuaijs/AutoJS location 模块：一次性定位（CLLocationManager requestLocation + 有界等待），返回 {latitude, longitude, altitude, horizontalAccuracy, verticalAccuracy, course, speed, timestamp}；默认 5000ms（500～30000）；宿主 App 需 Info.plist 声明 NSLocationWhenInUseUsageDescription，权限被拒/定位关闭返回 null。
- **HMAC 签名（hmacSHA1/hmacSHA256）。** 对标 AScript crypto / AutoJS crypto：CommonCrypto CCHmac 实现，返回十六进制小写字符串；strings.hmacSHA1/hmacSHA256 与全局函数等价。
- **bootstrap 导出收敛压缩。** deviceApi 两段同名单条导出改为 forEach 批量导出 + 删除 3 处重复导出（swipeToPoint/md5/sha1），净减 240B（61348 → 61108）。
- **SQLite 修复。** BLOB 值改为 base64 字符串返回（避免 NSData 桥接歧义）；句柄分配计数加锁（多线程安全）。

## [1.7.0] - 2026-08-06

## [1.7.0] - 2026-08-06

### Added

- **YOLO 目标检测（yolo.detect / yolo.detectByFilePath / yoloDetect）。** 设备端 Vision 内置物体识别模型（YOLO 风格、全离线、免 API Key、免模型文件），对标 AScript YOLO；返回 [{label, confidence, rect}]，rect 为图片像素坐标（左上原点）；d.ts/文档/verify/测试同步，文档 249 函数，测试 71 项。
- **SQLite 本地数据库（sqlite.open/exec/query/close）。** iOS 内置 libsqlite3，对标 EasyClick/AutoJS sqlite 模块：open 打开或创建沙盒内 .db 并返回句柄；exec 执行增删改返回 {changes, lastInsertRowId}；query 执行 SELECT 返回按列名取值的对象数组；? 占位参数自动绑定（防注入）；脚本停止自动关闭全部连接；podspec 链接 sqlite3。
- **bootstrap 体积压缩。** 新增 _ff/_pc 紧凑桥接 helper（invokeFile 7 处 + invokePixelColor 4 处收敛），新增功能后解码 61226 → 61348（仍低于 60KB 预算）。
- **对标文档修正。** EasyClick 对比表：multipart/form 上传（files/formData）与 WebSocket 客户端已支持、YOLO/sqlite 能力补齐、getSerialNo 在 iOS 返回 null 的说明。

## [1.6.0] - 2026-08-06

### Added

- **设备查询全局简写补齐（20 个）。** deviceApi 成员补全局导出（EasyClick/AScript 全局风格）：
  getDeviceInfo/getScreenWidth/getScreenHeight/getScale/getModel/getOSVersion/getDeviceName/getBattery/isCharging/getOrientation/
  getDeviceId/getDeviceAlias/getSerialNo/volumeUp/volumeDown/getMemoryInfo/isRunning/isDir/isFile；d.ts/文档/verify/测试同步，测试 69 项。
- **文档修正：getOrientation 返回方向名称字符串**（portrait/landscapeLeft/landscapeRight/portraitUpsideDown），非角度数字；d.ts 返回类型同步为 string。

## [1.5.0] - 2026-08-06

### Added

- **WebSocket 客户端（ws.connect/poll/send/close）。** 轮询式 WebSocket（NSURLSessionWebSocketTask），对标 AScript WebSocket 与 kuaijs 云控：
  connect 建立 ws:// 或 wss:// 连接并返回句柄；poll 取事件 {type: open|message|close|error, text?}；send 发送文本帧；close 关闭。
  消息队列上限 512 条（防内存膨胀），脚本停止时自动关闭全部连接；d.ts/文档/verify/测试同步，测试 67 项。
- **bootstrap 别名压缩（String/Number → Str/Num）。** 机械替换 187 处 String(、130 处 Number(，bootstrap 解码 61209→60293
  （释放约 916 字符预算，配合 ws 后 60559，余量 881）；负向后顾正则避免误伤 toString( 等标识符，66 项既有测试全部保持绿色。

## [1.4.0] - 2026-08-06

### Added

- **二维码 / 条形码识别（scanCode）。** 新增 `scanCode(imagePath)` / `screen.scanCode(path)`：设备端 Vision 检测二维码与条码，
  返回 `[{text, symbology, bounds:{x,y,width,height}}]`（归一化坐标、左上原点），对标 AScript CodeScanner；
  原生 AutoEngine 新增 `AutoScanBarcodes`（64MB 图片上限、路径经 resolvePath 沙盒解析）；d.ts/文档/verify/测试同步，测试 66 项。
- **App URL Scheme 启动库扩充（40+ → 200+ App）。** `app.getAppScheme/launchByScheme` 原生映射从 254 键扩充到 682 键：
  新增苹果系统 App（设置/照片/相机/日历/备忘录/提醒/邮件/短信/电话/钱包/健康/家庭/快捷指令/TestFlight 等）、
  Microsoft/Google 套件、Zoom/Teams/Slack/Notion/Dropbox、Steam/Discord/Line/KakaoTalk/LinkedIn/Reddit/Snapchat/Pinterest、
  Prime Video/Disney+/HBO Max、国内 App（贴吧/闲鱼/唯品会/苏宁/猫眼/大麦/芒果TV/酷我/喜马拉雅/斗鱼/虎牙/陌陌/探探/百度网盘/腾讯地图/云闪付/去哪儿/Keep 等）。

### Changed

- **bootstrap httpApi 包装压缩。** get/post/downloadFile/getJSON 改用 `Object.assign({},options,默认值)` 内联形式，
  压缩 75 字符（bootstrap 解码 61227→61209）；行为等价（Object.assign 自动跳过 null/undefined 源）。
### Fixed

- **类型声明补齐（CI tsc 全绿）。** `types/autosdk.d.ts` 新增全局 `click(x, y, jitter)` 重载（运行时已支持、类型缺失）、`AutoSelectorBuilder._q` 内部字段声明；修复 `Examples/hello.js` 与全局 `nodeAt` 声明的变量冲突。


## [1.3.1] - 2026-08-06

### Fixed

- **Fix: ocrBaidu / ocrBaiduText 请求格式错误。** 百度 OCR 接口要求 `image=` 表单字段（`application/x-www-form-urlencoded`），
  此前以 `application/octet-stream` 原始 body 发送会被百度拒绝；现改为 POST body 传 `image=<base64>`（`+` 转义为 `%2B`），
  避免 `httpApi.post(url, body, options)` 第三参 body 被覆盖的问题。bootstrap 解码 61196→61201；
  测试补强（form 字段断言 + `+` 百分号编码断言）；verify 全绿，65 测试全绿。

## [1.3.0] - 2026-08-06

### Added
- **Round 32: 原生审计 + 对标文档刷新。** 深挖审计 AutoEngine/AutoScriptSupport：zip 路径穿越防护（`..`/绝对路径拒绝）、中央目录与 CRC/尺寸边界、图片裁剪零宽防护、HTTP 字节限制 clamp、NSNull→JS 桥接均健壮，无新增 bug；verify 新增原生侧静态断言（scheme 库 ops / 手电筒 torch / 前台应用）；刷新 `docs/EASYCLICK_COMPARISON.md` 覆盖清单（215→242 卡片，各分类计数对齐）与 `docs/ASCRIPT_COMPARISON.md` 缺口清单（标记 R27-R30 已实现项 + 剩余不可行项）。文档 244 条；测试 65 项全绿。
- **Round 31: 教程网页更新。** `docs/guide/index.html` 函数计数刷新为 244，新增「5.4 常用新能力速查」小节（手电筒 / App Scheme 库 / getFrontmostApp / 百度 OCR 的复制即用示例）；本轮无代码逻辑变更，verify/测试/文档全绿。
- **Round 30: 百度 OCR 封装。** 新增 `ocrBaidu(imageBase64, apiKey, secretKey, options?)` / `ocrBaiduText(...)`：自动获取 access_token 后直传图片 base64 调用百度通用文字识别，返回 `{text, lines}`；对标 AScript 第三方 OCR 能力（需自备百度智能云 Key 与 allowNetwork 权限）。bootstrap 解码体积 60057 → 61178（仍在 60KB 预算内），d.ts/文档/verify/测试同步。文档 244 条；测试 65 项全绿。
- **Round 29: bootstrap 压缩 + 前台应用查询。** 压缩 stringsApi（正则化 isUpper/isLower/isNumber/isIntrger/isLetter/isChinese + SS 取值助手），bootstrap 解码体积 61221 → 60057（释放约 1.1KB 预算）；新增 `app.getFrontmostApp()` / 全局 `getFrontmostApp()`（前台 bundleId，对标 AScript get_frontmost_app / EasyClick getFrontmostApp()），d.ts/文档/verify/测试同步。文档 243 条；测试 64 项全绿。
- **Round 28: App URL Scheme 库。** 新增 `app.getAppScheme(name)` / `app.launchByScheme(name)` 及全局简写（原生内置 40+ 常用 App 的 URL Scheme 映射，支持中文名/英文名/bundleId 查询，对标 AScript 内置 URL Scheme 启动库与 EasyClick getAppScheme()）；bootstrap 新增 `_av('getAppScheme'/`_av('launchByScheme')` 调用点与导出，d.ts/文档/verify/测试同步，`system-demo.js` 补充 scheme 演示。文档 242 条；测试 63 项全绿。
- **Round 27: 手电筒开关 API。** 新增 `device.setFlashlight(on?)` / `device.torch(on?)` / `device.flashlight(on?)` 及全局简写 `setFlashlight/torch/flashlight`（原生 AVCaptureDevice 闪光灯，默认开，需 allowSystemControl 权限），对标 EasyClick `setFlashlight()`；bootstrap 新增 `_dv('flashlight')` 调用点与导出，d.ts/文档/verify/测试同步，`system-demo.js` 补充手电筒演示。文档 241 条；测试 62 项全绿。
- **Round 26: 网络类型探测 + 调用点压缩 + OCR 空文本防护。** 新增 `device.getNetworkType()`（wifi/cellular/none，SCNetworkReachability）与 `device.isWifi()` 及全局简写，`getDeviceInfo()` 同步补 `networkType` 字段，对标 EasyClick getNetworkType()；bootstrap 新增 `_av` 紧凑 helper 收敛全部 `invokeApp` 调用点（15 处）；修复 `ocrClick/ocrText` 空文本会误匹配首个识别项的边界问题（空文本直接返回 false/null）；新增示例脚本 `Examples/TemplateApp/Scripts/system-demo.js`（speak/网络/时区/常亮/设置页）。verify 同步适配 `_av` 形态并新增网络 API 检查；文档 240 条；测试 61 项全绿。
- **Round 25: TTS 朗读 + 打开设置/App Store + 设备语言时区运行时。** 新增 `speak(text, options?)/tts()`（AVSpeechSynthesizer 系统朗读，免联网，支持 rate/volume/language 与脚本结束自动停止）与 `speechStop()/stopSpeak()` 及 `speech.*` 命名空间；新增 `app.openSettings()/openAppSetting()`（打开本 App 系统设置页）与 `app.openAppStore(appId)`（itms-apps 打开 App Store）；新增 `device.getLanguage()/getCountry()/getLocale()/getTimezone()/getUptime()` 并在 `getDeviceInfo` 中补齐 language/country/locale/timezone/uptimeSeconds 字段，对标 AScript get_language/get_country/get_timezone/app_open_setting/app_store/speak。verify 的 bootstrap 内容检查改为基于解码后的脚本（免疫字面量分块切分），并新增新 API 检查；文档 237→240 条；测试 60 项全绿。
- **Round 24: 桥接调用压缩重构 + 屏幕常亮 + webView.loadHTML + OCR 文字点击。** 重构 AutoBootstrapScript：新增 `_dv/_md/_nn` 紧凑桥接 helper（原生调用点从 38+49+12 处收敛为 3 个），脚本体积从 61859 字节压到 59606 字节（低于 60KB 预算，留出约 1.8KB 余量），删除 `deviceApi` 重复的 `isScreenOn` 与 `base` 中与 `deviceApi/mediaApi` 重复的成员（getClipboard/setClipboard/getBrightness/setBrightness/getVolume/vibrate/deleteAll*），`auto` 代理未命中时依次回退 `deviceApi/mediaApi/appApi/fileApi/imageApi` 再走原生兜底。新增 `device.keepScreenOn(on?)`（原生 `idleTimerDisabled`，需 allowSystemControl 权限）+ 全局 `keepScreenOn()`；新增 `webView.loadHTML(token, html)` 直接加载 HTML 字符串；新增全局 `ocrClick(text, timeoutMs?)`（OCR 命中文本即点击中心点）与 `ocrText(text, timeoutMs?)`（返回匹配项），并补 `g.ocr` 全局导出。d.ts 补齐 `isLocked/keepScreenOn/loadHTML/ocrClick/ocrText/ocr` 声明，API 文档补齐 Selector 全链式方法与新函数（234→237 条），verify 静态检查同步重构后的字面量并把 HTTP 会话检查限定在共享 session。测试 59 项全绿（新增 1 项覆盖新 API 与 auto 代理回退）。
- **Round 23: AScript 命名对齐与类型修复。** `Selector()` 新增 `find_one/find_once/find_all/wait_for` snake_case 终端别名；Node 对象新增 `set_text/clear_text` 别名；新增全局 `action.*` 命名空间（`action.click(x,y,jitter)`、`action.slide_path(points,ms)` 等，写法与 AScript 一致）；`screen.capture()` 截图别名。修复 `image.compress` 签名类型错误（可选参数 quality 后跟必选 dest 违反 TS 规则）：现支持 `compress(src, dest, quality?)` 标准写法并兼容旧 `compress(src, quality, dest)`；修复 d.ts `AutoNodeObject` 与 `AutoNode.selected` 属性/方法冲突（改用 `Omit`，全量 tsc 校验零错误，移除 `--skipLibCheck` 掩盖）。对标表补齐 Round 21 漏写行。测试 57 项全绿。
- **Round 22: 修复 longClick 单位 bug、媒体 URL 下载、webView 双向通道。** `node.tap_hold(d)/longClick(d)/click(d)` 的时长统一为秒（WDA 语义），修复默认 `1000` 被当作 1000 秒 clamp 成 60 秒长按的问题；`media.saveImage/saveVideo`（及 `playMp3/audioPlay`）支持 http(s) 远程 URL，自动下载到临时目录后处理（受 `maxMediaBytes` 限制，超时 90 秒），对标 AScript `save_pic2photo(url)`；webView 新增 `takeMessage(token)` 与 `injectBridge(token)`：页面通过 `window.webkit.messageHandlers.autosdk.postMessage(payload)` 发消息、脚本轮询 `takeMessage` 拉取，对标 WebWindow JS→脚本双向通道。文档/对标表/d.ts 同步，测试 56 项全绿。
- **Round 21: AScript 拟人操作 / Selector 链式 / 音频按 ID（234 函数）。** 新增 `Selector()` 链式选择器（`text/textContains/textStartsWith/textEndsWith/textMatches`、`desc/descContains/descMatches`、`label/labelContains/labelMatches`、`value/name/id/type`、`clickable/visible/enabled/selected`、`index/depth/bounds/xpath/predicate`，终端方法 `findOne/one/find/findAll/all/exists/waitFor/click/tap/longClick`），对标 AScript Selector；`click(x, y, jitter?)` 坐标拟人点击（jitter=true ±6px、数字=±N px）且兼容 `click(selector)`；`clickRandomPoint(x1,y1,x2,y2)` 与 `clickRandom(x1,y1,x2,y2)` 区域随机点击；`slidePath(points, ms)` 连续轨迹滑动（按距离分配每段耗时）+ `slide_path/touchAndSlide` 别名；原生 `audioPlay(path, volume?, stopWhenScriptEnd?)` 返回播放器 ID 并支持多路并行、`audioStop(id?)` 单独停止（`playMp3/stopMp3` 保留兼容）；`device.isLocked()` 锁屏状态查询。文档/对标表/d.ts 同步更新，测试 55 项全绿。
- **Round 20: AScript 控件/截图缓存/悬浮日志补齐（228 函数）。** 新增 `node.at(x, y)` 坐标直查控件与高级
  Node 对象（`node.find/findAll/snapshot`，节点带 `click/tap/tap_hold/longClick/scroll/setText/clearText/
  selected/exists/attr/rect/bounds/center/info` 方法与属性，对标 AScript Node.at + node 方法）；新增
  `screen.cache(on)/isCache()/clearCache()` 截图缓存（对标 AScript screen.cache，开启后
  screenshot/findImage/findColor/findMultiColor/findColors/ocr 复用同一张截图，原生新增 `screenshotPath`
  源图选项）；新增 `floatLog` 悬浮日志窗（对标 AScript FloatWindow，可拖动、保留最近 200 行）。新增原生
  `invokeNodeSnapshot` 桥接（复用 WDA/UIKit 节点快照，最大 2000 节点）。API 文档、类型声明、
  VS Code 补全、对标表与 3 组新回归测试同步更新。
- **Round 17/18: AScript requests 会话能力 + 系统功能补齐。** HTTP 模块对标 Python
  requests：新增 `cookies`（自动 Cookie 头）、`params/query`（自动拼查询串）、
  `files`（multipart 文件上传，支持 `formData` 表单字段），响应新增
  `cookies`（Set-Cookie 解析）；新增 `device.getIPAddress()`（getifaddrs，
  对标 AScript system.get_ip_address）、`notify(body, title?)`（本地通知，
  对标 AScript system.notify）、`image.compress(src, quality?, dest)`
  （JPEG 质量压缩，对标 AScript screen.image_compress）。类型声明、VS Code 补全、
  本地 API 文档（221 函数）与 XCTest 覆盖同步更新。

- **Round 16: 彻底移除 TrollStore 分发路径（对标 AScript / kuaijs 免巨魔）。**
  构建工作流改为 `Build AutoSDK IPA`，IPA 工件更名 `AutoSDKTemplate-ipa`；
  VS Code 插件命令 `AutoSDK: Build TrollStore IPA` 更名 `AutoSDK: Build IPA`
  （插件升至 0.5.0）；全部文档与教程的安装方式改为 Apple ID 免费签名
  （AltStore / Sideloadly / SideStore / Feather），
  `WINDOWS_TROLLSTORE.md` 重写为 `WINDOWS_SIDELOAD.md`；
  新增 [`docs/NO_TROLLSTORE.md`](docs/NO_TROLLSTORE.md) 落地页（免费签名 /
  XCTest 激活 WDA / HID 三条路线）；修复 CI 暴露的 2 个真实编译错误
  （`stopAllAudioPlayback` selector 未声明、`invokeMedia:` 相册删除分支
  `NSError` 未声明）。跨 App 控件自动化走 XCTest 激活 WDA 路线（规划中）。

- **Round 15: 对标 AScript（ascript.cn）+ 免巨魔路线。** 新增 `findColorCount`（颜色数量统计，对标
  AScript CountingColor）与 `image.toBase64(path)`（图片转 Base64，对标 image_to_base64），
  含 screen/image 模块入口与全局别名；新增
  [`docs/ASCRIPT_COMPARISON.md`](docs/ASCRIPT_COMPARISON.md)（AScript 逐模块函数对标）与
  [`docs/NO_TROLLSTORE.md`](docs/NO_TROLLSTORE.md)（免费签名安装 / XCTest 激活 WDA / HID 模式
  三条免巨魔路线，对标 AScript Agent 模式与 kuaijs）；修复 CI 在 macOS 上暴露的 3 个真实编译/
  测试问题（重复 static 函数名、id.count 点语法、日期测试时区依赖）。本地 API 文档同步更新：
  217 个函数。
- **Round 14: EasyClick 兼容 screen 取色模块 + 应用信息增强。** 新增
  `screen.*` 图色模块（EasyClick 兼容入口）：`screen.getColor(x,y)` 返回
  {r,g,b,a,hex}、`getColorRGB(x,y)` 返回 {r,g,b}、`getColorHex(x,y)` 返回
  #RRGGBB；`findImage/findColor/findColorEx/findNotColor/findMultiColor/
  findColors/isColors/cmpColor/ocr/screenshot` 与全局函数等价；新增全局别名
  `screen` 与 `string`（strings 模块）。新增 `app.getAppName(bundleId)`
  （查询应用显示名称）与 `app.isRunning(bundleId)`（state>=2 即运行中）。
  本地 API 文档同步更新：215 个函数；类型声明、VS Code 补全与示例同步。


- **Round 13: 悬浮层生命周期治理。** 新增 `screenDraw.release(token)`（释放单个绘制）
  与 `screenDraw.clearAll()`（清空全部绘制）；引擎在脚本结束/停止/退出时自动清理
  全部悬浮层（screenDraw + floatBall + 悬浮窗），避免脚本异常退出后 UI 残留；
  VS Code 插件升级到 0.4.2（补全列表新增日期/字符串/内存/安装判断等 13 条）。
- **Round 12: 日期格式化 / 随机睡眠 / 字符串增强 / 应用与内存别名。** 新增
  `formatDate(timestamp?, pattern?)` 与 `dateFormat`、`strings.formatDate`（支持
  yyyy/MM/dd/HH/mm/ss/SSS/E 中文星期）；新增 `sleepRandom(min, max)` 随机睡眠；
  `strings.*` 新增 startWith/endWith/contains/indexOf/lastIndexOf/substring/
  replaceAll/toUpperCase/toLowerCase/join/repeat/length/padZero/padStart/padEnd/
  format（%s/%d/%f），全局简写 startWith/endWith/contains/padZero；新增
  `app.isInstalled(bundleId)` 与全局 `isInstalled`（WDA 已装应用列表）；新增
  `device.getTotalMemory/getAvailableMemory/getUsedMemory` 内存别名与
  `file.getLineCount` 别名。本地 API 文档同步更新（206 个函数）。
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
