# EasyClick iOS capability comparison

Audit date: 2026-09-07 (Round 73; current workflow review: [QUALITY_AUDIT.md](QUALITY_AUDIT.md))

Official references:

- EasyClick iOS USB documentation: <https://ieasyclick.com/iosdocs/>
- EasyClick iOS USB API index: <https://ieasyclick.com/iosdocs/zh-cn/funcs>
- EasyClick iOS offline documentation: <https://ieasyclick.com/iostjdocs/>
- EasyClick iOS offline API index: <https://ieasyclick.com/iostjdocs/zh-cn/funcs>

AutoSDK is an embedded runtime, not an EasyClick-compatible controller. The
comparison therefore separates API coverage from execution scope. A method is
not marked complete when its name exists but its underlying iOS capability is
unavailable.

## Capability matrix

| Area | EasyClick official surface | AutoSDK status | Remaining gap |
| --- | --- | --- | --- |
| Script runtime | start/stop, pause, restart, exception callbacks, modules, NPM/TypeScript | JavaScriptCore run/stop, native extension methods, logs, remote or bundled scripts | No module loader, pause/restart, worker runtime, or preemptive termination of an infinite pure-JS loop |
| Touch | coordinate click, double click, long press, pressure, multi-touch, swipe, drag | selector activation, coordinate activation, double activation, scroll-view swipe, direction-swipe helpers (up/down/left/right), long-press drag, child-count; **Round 46:** built-in no-WDA adapter (`AutoBuiltinAdapter`) injects real IOHIDEvent digitizer touches system-wide (tap/long-press/swipe/drag plus W3C multi-touch gesture playback) without any external WDA Runner; **Round 50:** EasyClick-style staged touch primitives `touchDown(x,y,finger?)/touchMove(x,y,finger?)/touchUp(finger?)` (per-finger staging, `touchUp()` flushes all staged fingers in one multi-touch playback) | Host-app UIKit adapter still cannot inject touches; the built-in adapter resolves private IOHIDEvent symbols at runtime, so it needs a private-API-permitted build (TrollStore/dev-signed) and real-device validation; pressure/force not implemented yet |
| Nodes | exact/regex selectors, XPath, chained filters, all/one, parent/child/siblings, fetch filters, locked XML trees, and phone-side execution | host-app stable handles, selectors, attributes, bounds and parent/child/sibling traversal (incl. EasyClick-style node.children()/allChildren()/parent()/siblings()/nextSiblings()/previousSiblings() relation methods), wait and scroll; **Round 46:** built-in AXUIElement system-wide node queries (text/label/name/value/id/type plus regex variants, bounds, enabled/selected/depth/index filters, relation traversal) across apps with no WDA | **Round 53:** built-in AX path translates a bounded xpath subset (//Type[@attr='v'], contains/starts-with/ends-with, `and` combos, positional `[n]`, attrs text/label/name/value/id/type/index/depth; 512-char cap, single step) into native query keys; predicate still rejected with a clear error. No `lockNodeFromXml`, phone-side locked XML execution, or guaranteed cross-snapshot transient handles |
| Screenshot/color | stream capture, compare/find color, multi-color, non-color search | PNG/region screenshot, pixel read, single-color find, one-capture multi-point compare, multi-color pattern search, findNotColor | **Round 51:** `screen.cache(true)` contract fixed end-to-end — builtin/UIKit adapters and findColorEx/findNotColor scans now honor `screenshotPath` (sandbox-confined PNG reuse); cache also covers findColorEx/findNotColor. No stream capture, transparent-color template mode, or reusable image object |
| Image matching | OpenCV template matching and image transformations | bounded two-stage CoreGraphics similarity match, phone-side template deployment, clip/scale/gray/binaryzation/rotate pixel pipeline, Inspector testing; **Round 56:** EasyClick-parity bitmap model via sandbox path handles (readBitmap/saveBitmap/bitmapBase64/base64Bitmap/bitmapToImage/getBitmapPixelColor; handles auto-unwrap in all image ops); **Round 49:** built-in no-WDA adapter template matching on system-wide screenshots (bounded coarse-to-fine, similarity default 0.9) | Not OpenCV-grade; no scale/rotation invariant match or cvFindImage (OpenCV) |
| OCR/AI vision | phone/controller OCR APIs, multiple OCR engines, YOLO, and AI-agent workflows | on-device Apple Vision OCR with confidence and screen-point bounds; legacy `yolo.detect` name provides bounded iOS 15+ whole-image Vision classification | No real bounding-box detector or bundled/custom Core ML model, selectable OCR model, AI agent, or batch image-object API |
| Input/app control | input-method APIs, helper APIs, Home/app lifecycle and process operations | host text replacement; built-in app launch/activate/terminate/state/current helpers, installed-app list, prefix launch, and home-screen/lock/unlock operations; **Round 46:** built-in adapter launches/terminates apps and reads the frontmost bundle id through LSApplicationWorkspace/SpringBoard/BackBoard private APIs, locks the device and opens Settings URLs without WDA | No system input method; built-in app control needs private-API-permitted signing and real-device validation |
| Device | screen/model/OS/battery, app list, serial, orientation, charging and common system controls | public device/app/screen/battery/orientation information (incl. 宽x高 text), installed-app list, clipboard/brightness/volume/vibration/torch, Low Power Mode and Location Services state, per-app location authorization, `getSerialNo()` (returns null: iOS hides hardware serial), and built-in no-WDA home-screen/lock/unlock; **Round 70:** `vpn.status/connect/disconnect` manages only the host app's preconfigured Personal VPN and `system.openSettings(panel)` opens common Settings panels best-effort | No reboot, install/uninstall, arbitrary third-party/MDM VPN profile management, or silent Wi-Fi/Bluetooth/cellular/airplane-mode switching; Personal VPN requires the host entitlement and a previously saved enabled configuration |
| Media | save images/videos to the camera roll through the agent | add-only Photos writes for sandbox images, base64 images, videos and screenshots (`media.*`), region screenshot (`screenshotRegion`), gated by `allowMediaLibrary` and an iOS authorization prompt; requires `NSPhotoLibraryAddUsageDescription`. **Round 8:** `media.deleteAllPhotos/deleteAllVideos/deleteAllMedia` clear the camera roll (read-write Photos access, returns deleted count) | No album-object API, batch import, photo picker, or camera/QR capture |
| Files | sandbox file CRUD, lines, copy, Excel | UTF-8/base64 reads, atomic write, append, list, mkdir, copy/move/rename/remove below a confined root, EasyClick-style deleteAllFile (recursive directory clear returning removed-entry count), line operations (lineCount/getLineText/insertLineText/resetLineText), Excel (xlsx/csv), ZIP (zip/unzip/readFileInZip), plist read/write | No file upload picker, or access outside the configured sandbox root |
| Storage | named typed key-value stores | named persistent JSON stores plus EasyClick-style typed wrappers, plus a local SQLite module (`sqlite.open/exec/query/close`, sandbox-confined, positional-param binding, **Round 52:** 查询结果封顶 10 万行、多语句 SQL 显式报错) | No JDBC layer; 1 MiB default namespace limit |
| HTTP | generic requests, GET/POST/JSON, download, WebSocket | guarded HTTP methods (incl. **Round 54-55:** `http.put/delete/head/patch` REST wrappers + `http.requestEx` EasyClick alias), JSON/binary responses, multipart/form upload (`files`/`formData`, **Round 54:** field/file names validated against header injection), host allowlist, response limit, sandbox download, WebSocket client (`ws.*`) | Synchronous JS facade, no cookie jar API or proxy API |
| Timers/threads | timeout/interval, async/sync thread APIs, workers | cooperative `sleep`, timeout/interval queues drained before completion, parallel `execAsync/execSync` threads (join/getResult/cancel, up to 8), native URLSession work | No retained event loop after script completion or worker runtime |
| External transports/services | BLE events, OTG HID, Aux remote assistance, JDBC MySQL, and network-verification services | authenticated WebSocket debugging over loopback/USB or opt-in Wi-Fi, and guarded HTTP | No BLE/OTG/Aux controller, JDBC driver, or EasyClick service integration; cross-app automation uses the built-in no-WDA adapter (external WDA removed in v1.17.0) |
| IDE/debug | IDE, live screen, node panel, logs, remote execution | VS Code completion/snippets, safe single-file TypeScript transpilation, Bonjour LAN scan/add with stable Wi-Fi identity and one-selection reconnect after initial token pairing, manual-IP and advanced USB fallbacks, editor context/title one-click run plus explicit selection-only JS/TS execution, persistent authenticated connection, correlated screenshot+node Inspector, serialized node/image/color/OCR tests, request-ID and selection-revision stale-response protection, stable selection recovery, cancellable waits, configurable action-settle delay, valid edge-pixel mapping, portable snapshot export, code generation, deployed script/asset management, and Actions build/download | No continuous video stream, breakpoint debugger, TypeScript module bundler, package manager, or verified real-device Wi-Fi session |
| Deployment | signed EasyClick agent/IPA products, proxy IPA, Bluetooth and OTG HID paths | template app, macOS CI-verified unsigned IPA workflow (free Apple ID signing), built-in no-WDA adapter as the only cross-app engine (private symbols resolved at runtime, no linked private frameworks; external WDA removed in v1.17.0) | Built-in adapter requires a private-API-permitted build (TrollStore or developer signing) for touch injection and system-wide AX; Xcode simulator builds/tests pass, but private APIs still require real-iPhone validation |

## Round 73 quality iteration

Round 75 / v1.38.2 / extension 0.13.1 normalizes the saved/discovered URL before
checking the pairing target; 123 extension tests. Round 74's 90 native tests,
IPA build and release succeeded (Actions run 34094825945).

Round 74 / v1.38.1 follows up on CI: isolate shared-engine test queues, trigger
stop tests from actual adapter activity, and prevent a finished run's queued
watchdog from cancelling the next run. No tests are skipped.

SDK v1.38.0 / extension 0.13.0: selection-only runs, TypeScript language-mode fixes,
selection-scoped Inspector results and hidden-request cleanup, Bonjour startup/cancellation
cleanup and address refresh at capacity, pairing-target guards, cancellable location/VPN
waits, CoreLocation error wrapping, explicit SPM SQLite linking, and obsolete WDA guide removal.
Baseline: 88 Node + 121 extension tests; 90 native XCTest cases (12 newly added, deterministic
system-operation tests). Bootstrap unchanged at 61262 / 61440. See [audit](QUALITY_AUDIT.md)
for verified scope and unresolved real-device/architecture gaps.

## Current quality assessment

The following surfaces are implemented with explicit constraints and are the
best candidates for real use after an Xcode build and device test:

- JavaScript loading, execution result envelopes, logging and cooperative stop.
- Host-app UIKit node descriptors with stable handles.
- Sandboxed file operations and named JSON storage.
- Guarded HTTP requests with size and host restrictions.
- Vision OCR and basic screen color operations.
- Authenticated WebSocket debugging over loopback/USB or an explicitly enabled trusted Wi-Fi network.
- Reliable Low Power Mode, Location Services and per-app location-authorization state queries.

The following surfaces must not be described as production-complete yet:

- `AutoUIKitAdapter.longClick`: intentionally returns an unsupported error.
- Cross-app automation: the built-in no-WDA adapter (`AutoBuiltinAdapter`)
  is the only engine, but it calls private IOHIDEvent/AX/SpringBoard APIs
  resolved at runtime; it needs a private-API-permitted build and has not yet
  been validated on a real device. The external WDA adapter was removed in
  v1.17.0 and will not return.
- Transient node handles and coordinate snapshots must be refreshed after UI changes.
- Template matching: improved, but still a CoreGraphics matcher rather than OpenCV.
- Script timeout: cooperative native calls stop, but an infinite pure-JS loop
  cannot currently be preempted safely.
- Debug transport and Objective-C changes pass the macOS/Xcode simulator CI;
  private-API behavior and the physical Wi-Fi/USB tunnel still need a real-device test.
- `vpn.*` is limited to the Personal VPN configuration owned and pre-saved by
  the host app; it requires the Personal VPN entitlement. `system.openSettings`
  uses best-effort Settings deep links and never proves or silently changes a
  Wi-Fi, Bluetooth, cellular, hotspot or airplane-mode switch.

## Prioritized remaining work

1. Install the unsigned IPA with free Apple ID signing and verify the debug server through direct Wi-Fi or a loopback `iproxy` tunnel.
2. Validate the built-in no-WDA adapter on a real device (IOHIDEvent touch injection, system-wide AX queries, SpringBoard app control); external WDA support was removed in v1.17.0 and is not coming back.
3. Replace the basic matcher with an optional OpenCV-backed adapter.
4. Extend cancellation consistency across existing parallel contexts; explore a safe pure-JS execution interrupt mechanism.
5. Continue real-device validation and performance tuning for large Inspector snapshots.

## 函数级覆盖清单（2026-09-07）

唯一开发文档 `docs/index.html` 收录 259 个可运行示例（259 个 API 条目），分 14 个模块，
每项包含参数、返回值与一键复制示例：

| 分类 | 函数数 | 亮点 |
| --- | --- | --- |
| 日志与调试 | 10 | console 分级、toast/toastLog、alert/exit/restartScript、sleep、lastError |
| 触摸与节点 | 45 | 坐标/节点点击、滑动/手势/pinch、输入、节点查询（getChild/getSiblings/clickCenter/clickRandom）、node.keep/unkeep |
| 图色与OCR | 31 | 截图/区域截图、找图、找色、多点找色、findNotColor、像素（screen.getColor/getColorRGB/getColorHex）、多点比对（findColors/isColors）、OCR、二维码/条形码识别 scanCode |
| App与应用控制 | 21 | launch/activate/terminate/state/openURL/homeScreen/current/appList/isInstalled/getAppName/isRunning/锁屏解锁 |
| 设备与系统 | 30 | 屏幕/电量/方向/内存、剪贴板/亮度/音量/振动/手电、Personal VPN 有限控制、系统设置页、低电量与定位状态 |
| 坐标与屏幕 | 5 | setScreenMetrics/getScreenMetrics/metrics.point/device 尺寸 |
| 文件 | 39 | 沙盒 CRUD、行操作、复制/移动/重命名、stat、Excel、ZIP、plist |
| 存储 | 11 | 命名 typed store |
| 网络HTTP | 11 | get/post/postJSON/getJSON/download/通用请求、WebSocket（ws.connect/poll/send/close） |
| 相册媒体 | 11 | saveImage/saveImageBase64/saveVideo/saveScreenshot/deleteAllPhotos/deleteAllVideos/deleteAllMedia/playMp3/stopMp3/相册权限 |
| 定时器与工具 | 24 | 定时器、execAsync/execSync、thread/utils、uuid、base64、哈希/AES、随机数、颜色工具 |
| 字符串工具 | 17 | trim/split/chars/hex/类型判断/拼音 toPinYin/BOM 清洗/Unicode 还原/HMAC 签名 |
| 悬浮窗口 | 3 | screenDraw 屏幕绘制、floatBall 悬浮球（可拖动、setFloatBallPoint 别名） |
| 语音朗读 | 1 | speak/tts/speechStop/stopSpeak 与 speech 命名空间 |

本轮新增（Round 72）：**调试接入、线程错误与发布链可靠性**——VS Code 插件 0.12.0 在第一台 Bonjour 响应后继续收集多机且扫描可取消；首次或已有 token 失败均可原地重输/重试，未配置设备就右键运行可直接进入 Wi-Fi 扫描；Inspector 的 Point 取色模式更名为 Color。子 JSContext 的原生桥失败现在通过 `execSync`、async `getResult` 和 `join` 正确传播，`AutoThreadHandle.join()` 类型同步修正；CI 迁到 macOS 15、Xcode 15/16 兼容诊断和 Node 24 Actions；快速上手统一到唯一 `docs/index.html`，首段截图示例带 capability 守卫。bootstrap 61262/61440（余 178），文档 259 项、Node 测试 88 项、原生 XCTest 78 项、插件测试 105 项；

本轮新增（Round 71）：**iOS 系统状态测试稳定性修复**——不新增或改变公开 API；原生 XCTest 通过私有 provider 注入低电量、定位服务和原始定位授权枚举，覆盖全部五种授权状态及未知值回退，不再依赖冷启动模拟器的实时 TCC/CoreLocation daemon；生产 provider 默认为空，仍读取真实 `NSProcessInfo` / `CLLocationManager` 状态；bootstrap 61262/61440（余 178），文档 259 项、Node 测试 88 项、原生 XCTest 75 项、插件测试 97 项；

本轮新增（Round 70）：**设备与系统常用入口 + VS Code 补全闭环**——新增 `vpn.status/connect/disconnect/openSettings`，只读取和控制宿主 App 自己通过 Personal VPN entitlement 预存的已启用配置，不创建、选择或删除其他 VPN App/MDM 配置；新增 `system.openSettings(panel)` best-effort 打开 VPN/Wi-Fi/蓝牙/蜂窝/热点/飞行模式/定位/电池等设置页，明确不静默切换全局开关；新增 `device.isLowPowerModeEnabled()`、`location.isEnabled()` 与 `location.getAuthorizationStatus()`；VS Code `device.` 候选补齐完整 `AutoDeviceAPI` 并加入声明一致性回归测试；整理重复设备卡后文档为 259 个可运行条目，bootstrap 61262/61440（余 178），Node 测试 88 项、插件测试 97 项；

本轮新增（Round 69）：**Bonjour 原生编译热修**——按 Apple Network.framework 正式 C API 创建 `nw_advertise_descriptor_t` 并通过 `nw_listener_set_advertise_descriptor` 发布 `_autosdk._tcp`，替换不存在的 `nw_listener_set_service` 调用，恢复 Xcode 构建；局域网广播扫描、一键添加和身份配对语义不变；

本轮新增（Round 68）：**macOS 发布验证热修**——插件升级 0.10.1；USB 高级备用搜索的工具路径从宿主系统 `path` 改为按目标平台显式选择 `path.win32` / `path.posix`，修复在 macOS CI 中验证 Windows `iproxy` 路径时同目录候选错误，并增加 POSIX 路径回归断言；Wi-Fi Bonjour 主链语义不变；

本轮新增（Round 67）：**Wi-Fi Bonjour 广播扫描与一键重连**——TemplateApp 在 Wi-Fi 调试开启时发布 `_autosdk._tcp` 服务，使用稳定的每安装实例名称且绝不广播 token；插件升级 0.10.0，断开状态栏默认扫描局域网并列出手机，首次选择输入 token 后将 SecretStorage 凭据与稳定广播身份绑定，之后即使 DHCP 地址改变也可一键选择重连；手动添加支持只输入 IP 并自动补 `ws://` 与 9001 端口，USB/libimobiledevice 搜索移为高级命令；mDNS 扫描限制 15 秒/64 台设备，插件测试 97 项，bootstrap 零改动；

本轮新增（Round 66）：**设备搜索/添加与编辑器一键运行**——插件升级 0.9.0；新增 `Search and Add iPhone`，以有界、无 shell 的 `idevice_id` 搜索 USB 手机并用 `ideviceinfo` 读取名称，优先复用 `iproxy` 同目录工具；选中后保存 UDID、启动托管隧道、自动测试连接，缺工具/无设备时直接回退 Wi-Fi；断开状态栏变为 add iPhone 入口，JS/TS 编辑器右键菜单与标题栏新增运行按钮；跨设备不预填旧 token、保存失败回滚 UDID；插件测试 90 项，bootstrap 零改动；

本轮新增（Round 65）：**HTML 开发文档单入口重构**——将旧门户、图文教程、开发站和 API 卡片合并为唯一 `docs/index.html`，按主流自动化文档的信息架构提供 7 篇任务指南、14 个模块、263 个 API 条目；新增全局搜索（键盘导航）、模块过滤/索引、函数深链接、折叠详情、明暗主题、移动导航和离线复制，删除 3 份重复/过时 HTML；修复 `file.writeFile` 换行、`node` 命名空间遮蔽和 `http.getJSON` 返回值文档错误；verify 固化 263 个示例语法与单入口完整性；

本轮新增（Round 64）：**VS Code 补全与 Inspector 代码生成闭环**——插件升级 0.8.0；补全提供器移除易漂移的命名空间硬编码，新增纯 `completion-model` 自动从候选识别模块，覆盖 thread/utils/ocr/ws/sqlite/yolo/location/colors/speech/pasteboard/json/floatLog/metrics/base64 及 action/string 别名；25 组以 `/` 合写的旧签名拆为独立有效 Snippet，避免插入语法损坏代码；Inspector selector 稳定键改为属性有序序列化，跨快照不再因 JSON 键顺序变化丢选择，生成选择器以完整相关快照而非过滤结果集判定唯一性、仅歧义时附加 type；选择器/坐标/OCR/找图/点色生成代码全部下沉纯模型并验证转义；补齐 speech 命名空间 d.ts；插件测试 83 项，bootstrap 零改动（60782/61440，余 658）；
本轮新增（Round 63）：**VS Code Inspector 生命周期与取消链加固**——插件升级 0.7.0；新增 Cancel 按钮与 Escape 快捷键，中止当前客户端等待并淘汰所有排队旧任务；`lastSnapshot` 仅在请求仍为当前、面板可见且 signal 未取消时提交，解决取消/隐藏/销毁后的迟到结果污染下次导出；新增 `autosdk.inspectorActionRefreshDelay`（0...5000ms，默认 400ms）适配点击/输入/滚动后的动画；屏幕右/下边缘坐标限制到 `width-1/height-1`，零面积节点不参与命中，同 bounds 时优先更深且更晚的节点；DeviceClient 对显式取消的迟到响应静默回收（ID 集合上限 128），未知/超时孤儿仍报告；插件测试 72 项，bootstrap 与脚本 API 零改动（60782/61440，余 658）；
本轮新增（Round 62）：**Xcode 编译与 XCTest 链热修**——`tools/regenerate-bootstrap.mjs` 现在固定为生成的 `AutoBootstrapScript.m` 导入 `AutoBootstrapScript.h`，解决 Swift Package/Xcode 将源文件作为独立翻译单元编译时 `NSString` 未声明的问题；继续修复 `AutoEngine.m` 的 SQLite C 指针 Objective-C 泛型/ARC、媒体下载函数声明顺序、TTS `void` 装箱和不存在的 `VNRecognizeObjectsRequest`；旧 `yolo.detect` 命名保留兼容，但语义诚实调整为 iOS 15+ 公共 `VNClassifyImageRequest` 全图分类（最多 20 标签、rect 为全图），真实边界框检测仍需用户提供 Core ML 模型；XCTest 运行后进一步修复 `deleteAllFile(file)`、`auto.node/auto.screen/auto.floatLog` 接线、`auto.click.length`、POST multipart 二参兼容和无宿主通知中心异常；verify 同步固化上述约束，bootstrap 60782/61440（余 658）；
本轮新增（Round 61）：**Xcode 15.4 ARC 发布热修**——修复内置 no-WDA Accessibility 遍历中 CFTypeRef 到 Objective-C 对象缺少显式桥接、以不合法的 `NSArray<AutoAXElementRef>` 承载 C 指针等编译阻断；子节点遍历统一以 Objective-C 对象持有、使用时 `__bridge` 回 AX 引用，句柄重放时显式 `CFRetain`；同时修正 `type` 选择器逻辑非优先级导致的匹配反转，并加入 verify 回归锚点；bootstrap、脚本 API 与 VS Code 插件 0.6.0 均不变；
本轮新增（Round 60）：**VS Code 插件与截图/节点采集调试工具重构**——插件 0.6.0 将设备可视化协议、Inspector 会话调度和 Webview 几何/选择器模型拆为独立模块；普通截图、节点 JSON 和可视化 Inspector 共用一个重任务串行通道，匹配设备端“一次只处理一个 screenshot/nodes/pixel/findImage/OCR 重请求”的约束，消除并发 `device busy`；同类待处理操作只保留最新结果，所有 Webview 消息以 requestId 关联，迟到响应不再覆盖新状态；刷新后按稳定 nodeId/handle 恢复选择；新增 `autosdk.inspectorMaxNodes`（1...2000）和包含 PNG base64、节点树、设备信息、snapshotId/耗时的可移植 JSON 快照导出；删除旧无调用方 CoalescingRunner，插件测试 64 项，bootstrap 与脚本 API 零改动（60526/61440）；
本轮新增（Round 59）：**TrollAutoScript 文档对标 + 补齐最后高频缺口**——以 `docs.trollautoscript.com/sitemap.xml`（315 页 SSR 文档）做模块级功能盘点（设备 37/字符串 29/节点 21/图片 19/应用 17/屏幕 15 等）。新增：(1) `string.atrim`（去除全部空白含中间）+ `isInteger`（isIntrger 正确拼写别名，全局与 string 命名空间同步导出）+ `string.random(len, chars)`（等价全局 randomString），字符串谓词/工具补齐；(2) `pasteboard.read/write` 命名空间（对标 TrollAutoScript pasteboard 模块，兼容既有 getPasteboard/setPasteboard 全局函数）；(3) `json.encode/decode` 命名空间（decode 解析失败返回 null 不抛异常）；(4) `device.setBacklightLevel/backlightLevel` 背光别名（与 setBrightness/getBrightness 同源，auto.* 代理自动可达）。修复一个初始化顺序 bug：stringsApi 扩展赋值若放在尾部别名区会晚于全局导出 forEach，导致 g.atrim=undefined，已移至导出列表之前。bootstrap 60088→60526/61440（余量 914B），Node 测试 87 项，文档 263 函数；当时记录为缺口的 `vpn.*` 已在 Round 70 补上宿主自有 Personal VPN 的有限状态/连接控制，但任意配置创建/选择/删除、飞行模式/移动数据静默开关、app.installIpa/uninstall、mobile.sendMessage/reboot/shutdown、硬件按键 key.*、coreML/paddle 本地模型托管、clear.keychain、AssistiveTouch 仍不承诺；
本轮新增（Round 58）：**落实复盘建议**——(1) 新增 `lastError()` API：返回最近一次原生调用失败的 {code, message, domain?, underlying?}（无错误返回 null），彻底解决 execSync/http/sqlite 等「正常返回 false 与失败返回 false 无法区分」的语义问题，原生侧新增 invokeLastError 桥接；(2) 三轮压缩：gx(o,names) 批量别名助手统一 81 个同名全局导出（base 48 + device 12 + file 11 + app 3 + media 7），bootstrap 61391→60088/61440，预算余量从 49B 恢复到 1352B；(3) 真机验证路径：确认 CI（macos-14 模拟器测试+IPA 打包）每次 push 自动覆盖原生编译，真机验证清单更新至 R53-R58；Node 测试 86 项，文档 261 函数；
本轮新增（Round 57）：**全项目复盘审计 + 三个真 bug 修复**——(1) 修复 `execSync` 返回值破坏：原生 sync 模式返回裸结果，旧 JS 包装对 object/array 结果取 `.result` 导致返回 undefined（真机静默丢数据），现直返原生值（含失败 false 语义），Node mock 同步改为真实契约；(2) 修复定时器 drain 脆性：任一定时器回调抛异常会中断整个 drainTimers 循环、连累后续定时器，现 try/catch 隔离并走 consoleBridge.error 上报；(3) 修复 execAsync 内存增长：完成的线程对象持有 JSContext 直到脚本停止，现完成后立即置空释放（结果/错误已提取，join/getResult 不受影响）。审计确认无问题项：文件沙盒（NUL 拒绝+符号链接解析+root+/ 前缀防 /sandbox-evil+root 自身限制在 App 容器内）、zip（.. 组件/绝对路径/二次 resolve/条目与总量上限）、HTTP 重定向（禁 https→http 降级、禁非 http(s) scheme、allowlist、weak 表+锁）、调试服务帧解析（强制掩码、1MB 上限、控制帧 125B、RSV/分片拒绝）、sqlite（句柄表+锁+停止时统一 closeAll）、内置适配器 CF 资源配对；bootstrap 61391/61440（余 49B），测试 84 项；
本轮新增（Round 56）：**位图模型（路径句柄）+ 二轮压缩**——(1) EasyClick 位图 API 对标落地：`image.readBitmap(path)` 返回 `{path,isBitmap}` 句柄，`saveBitmap/bitmapBase64/base64Bitmap/bitmapToImage/getBitmapPixelColor` 全齐；句柄可直接传给 image.compress/clip/scale/gray/rotate/pixelAt/toBase64/getWidth/getHeight（_ff 与尺寸查询自动解包），EasyClick 的 scaleBitmap/rotateBitmap/clipBitmap 语义由 image.scale(handle,w,h,dest) 等以文件落盘方式等价覆盖，releaseBitmap 因无内存驻留而不需要；(2) 压缩第二轮：fileApi/deviceApi 自转发包装改为 guard 后直接引用别名（省 208B）、getPixelColor/getColor/encode/decode/time 改直接引用（省 126B），合计 -334B，抵消位图功能后净增 93B（61283→61376/61440，余 64B）；(3) toBase64 与 ocr.newOcr 统一走 bp() 解包；Node 测试 83 项，文档 260 函数；
本轮新增（Round 55）：**bootstrap 压缩重构 + REST 补全 + OCR 引擎实例**——(1) 压缩：删除 guard 前的 6 处死重别名（guard 后统一重建）、删除 getJSON 重复定义、get/post/put/delete 内联函数统一为 `function hv(m,b)` 动词工厂，净省 328B；(2) 新增 `http.head(url, options?)` / `http.patch(url, body?, options?)` REST 动词与 `http.requestEx`（EasyClick 兼容别名，与 http() 等价返回完整响应对象），REST 全家桶补齐；(3) 新增 `ocr.newOcr(defaults?)` 引擎实例（EasyClick 对标）：实例 `ocrImage(path)/ocrBitmap(bitmap)/ocr(path)` 对沙盒图片文件做 Vision OCR（经 screenshotPath 通道），自动合并默认参数；(4) 修复文档生成器 bug：ocrClick 示例卡混入一行无关映射表项（复制即语法错误）已清除；bootstrap 61283/61440（余 157B），Node 测试 82 项，文档 259 函数；
本轮新增（Round 54）：**HTTP 审计与加固**——审计 invokeHTTP 全链路（请求构建/响应/下载）发现并修复 multipart 头注入漏洞：formData 字段名、file 字段名、上传文件名直接拼进 Content-Disposition，此前未校验引号/控制字符，新增 `AutoHTTPFieldNameIsValid`（禁引号+CR/LF 等控制字符）三处接入；**新增 `http.put(url, body?, options?)` / `http.delete(url, options?)`**（AutoJS REST 动词对齐，+215B，61416/61440）；**开发文档对标**：抓取 ascript.cn/docs/ios API 目录比对——14 个分类（application/action/node/screen/ui/http/thread/db/file/media/cloud_control/system 等）我方 15 分类全覆盖，无分类级缺口；
本轮新增（Round 53）：**内置 no-WDA 适配器补齐 xpath 子集**（此前直接报错拒绝）——`AutoBuiltinXPathToQuery` 把有界 xpath 子集翻译成原生查询键：单步 `//Type`/`//*`、`@text/@label/@name/@value/@id/@type/@index/@depth` 精确匹配、`contains()/starts-with()/ends-with()`（正则转义后走 *Match 通道）、`and` 组合（引号感知切分）、位置下标 `//ScrollView[2]`；512 字符上限、单谓词块、嵌套路径/未知属性/未加引号文本值全部显式报错；capabilities 新增 `xpathSubset`；同步更新选择器卡片/devdocs 选择器指南/FAQ；
本轮新增（Round 52）：**SQLite 加固**——`sqlite.query` 结果集封顶 10 万行（防大表 SELECT 撑爆内存），多语句 SQL（一次传多条 `;` 分隔语句）从「静默只执行第一条」改为显式报错提示拆分调用；**devdocs 对标 AScript 文档再补 3 篇散文指南**：图色识别（找色/找图/OCR/YOLO 实战 + screen.cache 用法）、发布程序（内置脚本/远程脚本/签名矩阵/上架清单，对齐 AScript「发布程序」页）、常见问题 FAQ（签名/降级/xpath/分辨率适配/死循环停止/调试，25→28 页）；verify 新增 SQLite 有界锚点；
本轮新增（Round 51）：**修复 screen.cache(true) 端到端断链 bug**——此前 bootstrap 传 `screenshotPath` 但原生从不读取，缓存形同虚设；现在内置适配器新增 `screenPNGWithOptions:`（findColor/compareColors/findMultiColor/findImage/ocr 全部接入）、UIKit 适配器新增 `screenImageHonoringCachedPath:`（findColor/findImage/ocr 接入）、引擎 `AutoEngineScanColorPoints` 新增 `cachedScreenPath` 参数（findColorEx/findNotColor 接入），路径限定 App 沙箱内、文件缺失自动回退实时截图；bootstrap 侧 findColorEx/findNotColor 经 `cachedOptions` 注入缓存路径（图色缓存覆盖面补全）；**其他修复**：`parseColor` 只剥离**开头**的 `#`/`0x` 前缀（原正则会误删字符串中间的 `0x`）、`strings.padStart/padEnd` 空填充串死循环防护；**新增对标全局**：`waitFor(selector, timeout?)`（EasyClick waitNode/AutoJS waitFor）、`currentPackage()`（AutoJS，返回前台 bundleId）、`setClip/getClip`（AutoJS 剪贴板别名）；**压缩 -204B**（cachedRegion 去重、touchAndSlide/appApi/imageApi/speechApi 包装函数改引用委托，61405→61201/61440）；Node 测试 81 项、文档 258 函数卡片（签名扩展示例覆盖新别名）；
本轮新增（Round 50）：bootstrap 新增 EasyClick 风格低级触摸原语 `touchDown/touchMove/touchUp`（按 finger 编号分指暂存，touchUp() 无参时同时抬起全部已按下手指，可组合自定义多指手势/拖拽；+510B，61405/61440）；修复内置适配器 findImage 外层循环未检查比较次数上限导致超限后仍空转的 bug；devdocs 新增「高级指南」分组（多线程/数据库/网络通信三篇散文教程，对齐 AScript 文档结构）；d.ts/文档卡片/verify 锚点/测试同步（Node 测试 80 项，文档 258 函数）；
本轮新增（Round 49）：内置 no-WDA 适配器补齐两大缺口——`findImage` 模板匹配（系统级截图 + 有界两阶段粗→细匹配，similarity/region/maxCandidates 可配，比较次数封顶 60M，capabilities.findImage 如实报 YES）；`app.launch/terminate/appState` 接受常用 App 中文名（60+ 内置启动库，对标 AScript `system.app_start("微信")`）；文档/卡片/verify 锚点同步；零 bootstrap 改动（60895/61440）；
本轮新增（Round 48）：旧版 AScript 风格开发文档站上线（R65 已合并到 `docs/index.html`；侧栏分类树 + 开始/控件检索散文页 + 15 个 API 分类页，257 函数全量渲染，参数表/返回值/一键复制示例、顶栏搜索 + hash 路由，单文件离线）；同时修复 `speech`/`base64` 两个分类未进入旧版渲染器的问题；
本轮新增（Round 47）：完全移除外部 WDA 适配器（AutoWDAHTTPAdapter 及其测试/verify 锚点/模板配置/文档）——内置 no-WDA 成为唯一跨 App 路线，避免双路线维护成本；内置 capabilities 补 `appList`/`appLifecycle`/`systemActions` 键（运行时探测）；模板 App 默认 BUILTIN，设置页改为“内置 no-WDA / UIKit”开关；Node 侧测试仍 79 项，原生 Xcode 测试删除 24 个 WDA 专用用例（剩 58+14 项）、文档措辞全量同步；零 bootstrap 改动（60895/61440）；
本轮新增（Round 46）：内置 no-WDA 适配器 `AutoBuiltinAdapter` 上线——IOHIDEvent 真实触摸注入（系统级，支持多点 W3C 手势时序回放）、AXUIElement 系统级控件查询（跨 App，毫秒级）、SpringBoard/BackBoard/LSApplicationWorkspace 应用控制（启动/终止/前台/锁屏/设置页，**Round 49 起接受常用 App 中文名，60+ 启动库对标 AScript app_start**）、UIGetScreenImage 截图 + Vision OCR + **有界模板找图**；外部 WDA 依赖降级为 legacy 回退，主路线不再需要 WDA Runner（对标 AScript Agent no-WDA / kuaijs）；新架构文档 docs/NO_WDA_ARCHITECTURE.md；本轮零 bootstrap JS 改动（60895/61440）；
本轮新增（Round 45）：`node.allChildren()` 递归子孙遍历（EasyClick 语义补齐）；dp helper 压缩 -405B（60895/61440），并修复 boundsInfo 无 bounds 节点刷新 rect/center 时的 TypeError；测试 79 项；
本轮新增（Round 44）：节点对象新增 EasyClick 关系方法 `children()/parent()/siblings()/nextSiblings()/previousSiblings()`（返回包装节点，可链式操作）；nr 工厂挂载；文档 257 函数、测试 78 项；
本轮新增（Round 43）：Selector 链补齐 EasyClick match 别名 `idMatch/typeMatch/textMatch/nameMatch/labelMatch/valueMatch`（原生早已支持对应查询键）；ss/sx 工厂压缩 -264B（61091/61440）；测试 77 项；
本轮新增（Round 42）：`deleteAllFile(path)` 修复为 EasyClick 语义（递归清空目录、返回删除条目数）；`device.vibrateLong()/vibrateShort()` + 全局别名（对标 AutoJS）；bootstrap 压缩 -79B（别名委托 + clog/cmpC 闭包去重，61355/61440）；文档 256 函数、测试 76 项；
本轮新增（Round 40）：`thread.*`/`utils.*` 命名空间（EasyClick 兼容）、全局别名 `getPasteboard/setPasteboard/openUrl/uploadToAlbum/childcount`、`device.applist/getOrientationNoAuto/getDeviceMsg`、`image.captureFullScreen`；bootstrap 再压缩 880B（dvf/avf/hsh helper），文档 254 函数、测试 75 项；
本轮新增（Round 14）：`screen.*` EasyClick 兼容图色模块（getColor/getColorRGB/getColorHex + 找图找色/OCR/截图入口）、全局别名 `screen`/`string`、`app.getAppName`/`app.isRunning`；
本轮新增（Round 12）：`formatDate/dateFormat`（yyyy/MM/dd/HH/mm/ss/SSS/E 星期）、`sleepRandom` 随机睡眠、
`strings.*` 查找/截取/补位/format 系列、`app.isInstalled`、内存别名；
（Round 11 对标 TrollAutoScript）：`toPinYin`、`screenDraw.*` 悬浮绘制、
`floatBall.*` 悬浮球与 `setFloatBallPoint`、`node.keep/unkeep`、`stripUtf8Bom`/`fromUnicode`；
同时修复了文档生成器中 14 处历史中文损坏条目。
