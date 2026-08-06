# EasyClick iOS capability comparison

Audit date: 2026-08-05

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
| Touch | coordinate click, double click, long press, pressure, multi-touch, swipe, drag | selector activation, coordinate activation, double activation, scroll-view swipe, direction-swipe helpers (up/down/left/right), long-press drag, child-count; **Round 46:** built-in no-WDA adapter (`AutoBuiltinAdapter`) injects real IOHIDEvent digitizer touches system-wide (tap/long-press/swipe/drag plus W3C multi-touch gesture playback) without any external WDA Runner | Host-app UIKit adapter still cannot inject touches; the built-in adapter resolves private IOHIDEvent symbols at runtime, so it needs a private-API-permitted build (TrollStore/dev-signed) and real-device validation; pressure/force not implemented yet |
| Nodes | exact/regex selectors, XPath, chained filters, all/one, parent/child/siblings, fetch filters, locked XML trees, and phone-side execution | host-app stable handles plus WDA selectors, attributes, bounds, `/source`-derived parent/child/siblings (incl. EasyClick-style node.children()/allChildren()/parent()/siblings()/nextSiblings()/previousSiblings() relation methods), wait and scroll; **Round 46:** built-in AXUIElement system-wide node queries (text/label/name/value/id/type plus regex variants, bounds, enabled/selected/depth/index filters, relation traversal) across apps with no WDA | Built-in AX path rejects xpath/predicate selectors with a clear error; no `lockNodeFromXml`, phone-side locked XML execution, or guaranteed cross-snapshot WDA handles |
| Screenshot/color | stream capture, compare/find color, multi-color, non-color search | PNG/region screenshot, pixel read, single-color find, one-capture multi-point compare, multi-color pattern search, findNotColor | No stream capture, transparent-color template mode, or reusable image object |
| Image matching | OpenCV template matching and image transformations | bounded two-stage CoreGraphics similarity match, phone-side template deployment, clip/scale/gray/binaryzation/rotate pixel pipeline, Inspector testing | Not OpenCV-grade; no scale/rotation invariant match or cvFindImage (OpenCV) |
| OCR/AI vision | phone/controller OCR APIs, multiple OCR engines, YOLO, and AI-agent workflows | on-device Apple Vision OCR with confidence and screen-point bounds, plus on-device Vision object detection (`yolo.detect`, offline YOLO-style model, AScript YOLO parity) | No selectable/custom OCR model, AI agent, or batch image-object API |
| Input/app control | input-method APIs, helper APIs, Home/app lifecycle and process operations | host text replacement plus WDA app launch/activate/terminate/state/current helpers, installed-app list, prefix launch, and home-screen/lock/unlock endpoints; **Round 46:** built-in adapter launches/terminates apps and reads the frontmost bundle id through LSApplicationWorkspace/SpringBoard/BackBoard private APIs, locks the device and opens Settings URLs without WDA | No system input method; built-in app control needs private-API-permitted signing and real-device validation |
| Device | screen/model/OS/battery, app list, serial, orientation, charging | public device/app/screen/battery/orientation information (incl. 宽x高 text), installed-app list, clipboard/brightness/volume/vibration (vibrate + vibrateLong/vibrateShort aliases), `getSerialNo()` (returns null: iOS hides hardware serial from third-party apps), and WDA home-screen/lock/unlock | No reboot, install/uninstall, or process control |
| Media | save images/videos to the camera roll through the agent | add-only Photos writes for sandbox images, base64 images, videos and screenshots (`media.*`), region screenshot (`screenshotRegion`), gated by `allowMediaLibrary` and an iOS authorization prompt; requires `NSPhotoLibraryAddUsageDescription`. **Round 8:** `media.deleteAllPhotos/deleteAllVideos/deleteAllMedia` clear the camera roll (read-write Photos access, returns deleted count) | No album-object API, batch import, photo picker, or camera/QR capture |
| Files | sandbox file CRUD, lines, copy, Excel | UTF-8/base64 reads, atomic write, append, list, mkdir, copy/move/rename/remove below a confined root, EasyClick-style deleteAllFile (recursive directory clear returning removed-entry count), line operations (lineCount/getLineText/insertLineText/resetLineText), Excel (xlsx/csv), ZIP (zip/unzip/readFileInZip), plist read/write | No file upload picker, or access outside the configured sandbox root |
| Storage | named typed key-value stores | named persistent JSON stores plus EasyClick-style typed wrappers, plus a local SQLite module (`sqlite.open/exec/query/close`, sandbox-confined, positional-param binding) | No JDBC layer; 1 MiB default namespace limit |
| HTTP | generic requests, GET/POST/JSON, download, WebSocket | guarded HTTP methods, JSON/binary responses, multipart/form upload (`files`/`formData`), host allowlist, response limit, sandbox download, WebSocket client (`ws.*`) | Synchronous JS facade, no cookie jar API or proxy API |
| Timers/threads | timeout/interval, async/sync thread APIs, workers | cooperative `sleep`, timeout/interval queues drained before completion, parallel `execAsync/execSync` threads (join/getResult/cancel, up to 8), native URLSession work | No retained event loop after script completion or worker runtime |
| External transports/services | BLE events, OTG HID, Aux remote assistance, JDBC MySQL, and network-verification services | authenticated WebSocket debugging over loopback/USB or opt-in Wi-Fi, and guarded HTTP | No BLE/OTG/Aux controller, JDBC driver, or EasyClick service integration; cross-app automation uses the built-in no-WDA adapter (external WDA removed in v1.17.0) |
| IDE/debug | IDE, live screen, node panel, logs, remote execution | VS Code completion/snippets, safe single-file TypeScript transpilation, persistent Wi-Fi/USB-forwarded connection, visual screenshot/node Inspector, node/image/color/OCR tests, code generation, deployed script/asset management, and Actions build/download | No continuous video stream, breakpoint debugger, TypeScript module bundler, package manager, or verified real-device tunnel session |
| Deployment | signed EasyClick agent/IPA products, proxy IPA, Bluetooth and OTG HID paths | template app, unsigned IPA workflow (free Apple ID signing), built-in no-WDA adapter as the only cross-app engine (private symbols resolved at runtime, no linked private frameworks; external WDA removed in v1.17.0) | Built-in adapter requires a private-API-permitted build (TrollStore or developer signing) for touch injection and system-wide AX; not compiled or tested on Xcode or a real iPhone in this Windows workspace |

## Current quality assessment

The following surfaces are implemented with explicit constraints and are the
best candidates for real use after an Xcode build and device test:

- JavaScript loading, execution result envelopes, logging and cooperative stop.
- Host-app UIKit node descriptors with stable handles.
- Sandboxed file operations and named JSON storage.
- Guarded HTTP requests with size and host restrictions.
- Vision OCR and basic screen color operations.
- Authenticated WebSocket debugging over loopback/USB or an explicitly enabled trusted Wi-Fi network.

The following surfaces must not be described as production-complete yet:

- `AutoUIKitAdapter.longClick`: intentionally returns an unsupported error.
- Cross-app automation: the built-in no-WDA adapter (`AutoBuiltinAdapter`)
  is the only engine, but it calls private IOHIDEvent/AX/SpringBoard APIs
  resolved at runtime; it needs a private-API-permitted build and has not yet
  been validated on a real device. The external WDA adapter was removed in
  v1.17.0 and will not return.
- WDA parent/child/sibling nodes: derived from a point-in-time `/source` XML
  snapshot and represented by XPath, so they must be refreshed after UI changes.
- Template matching: improved, but still a CoreGraphics matcher rather than OpenCV.
- Script timeout: cooperative native calls stop, but an infinite pure-JS loop
  cannot currently be preempted safely.
- Debug transport and all Objective-C changes: static checks passed on Windows,
  but an iOS compiler and a real-device test have not run.

## Prioritized remaining work

1. Run the GitHub Actions iOS build and fix every compiler warning/error.
2. Install the unsigned IPA with free Apple ID signing and verify the debug server through direct Wi-Fi or a loopback `iproxy` tunnel.
3. Validate the built-in no-WDA adapter on a real device (IOHIDEvent touch injection, system-wide AX queries, SpringBoard app control); external WDA support was removed in v1.17.0 and is not coming back.
4. Replace the basic matcher with an optional OpenCV-backed adapter.
5. Add workers/parallel JavaScript contexts and a safe execution interrupt mechanism.
6. Upgrade point-in-time screenshots and node JSON into a continuous visual inspector.

## 函数级覆盖清单（2026-08-06）

交互式速查 `docs/api-reference.html` 收录 257 个可运行示例（257 个函数），分 13 个分类，
每张函数卡带 EasyClick/AutoJS 对标函数与一键复制示例：

| 分类 | 函数数 | 亮点 |
| --- | --- | --- |
| 日志与调试 | 9 | console 分级、toast/toastLog、alert/exit/restartScript、sleep |
| 触摸与节点 | 43 | 坐标/节点点击、滑动/手势/pinch、输入、节点查询（getChild/getSiblings/clickCenter/clickRandom）、node.keep/unkeep |
| 图色与OCR | 30 | 截图/区域截图、找图、找色、多点找色、findNotColor、像素（screen.getColor/getColorRGB/getColorHex）、多点比对（findColors/isColors）、OCR、二维码/条形码识别 scanCode |
| App与应用控制 | 21 | launch/activate/terminate/state/openURL/homeScreen/current/appList/isInstalled/getAppName/isRunning/锁屏解锁 |
| 设备与系统 | 33 | 屏幕、电量、方向、剪贴板、亮度、音量、振动、内存、机型、系统版本、设备ID、GPS 定位 |
| 坐标与屏幕 | 5 | setScreenMetrics/getScreenMetrics/metrics.point/device 尺寸 |
| 文件 | 38 | 沙盒 CRUD、行操作、复制/移动/重命名、stat、Excel、ZIP、plist |
| 存储 | 11 | 命名 typed store |
| 网络HTTP | 11 | get/post/postJSON/getJSON/download/通用请求、WebSocket（ws.connect/poll/send/close） |
| 相册媒体 | 11 | saveImage/saveImageBase64/saveVideo/saveScreenshot/deleteAllPhotos/deleteAllVideos/deleteAllMedia/playMp3/stopMp3/相册权限 |
| 定时器与工具 | 21 | 定时器、execAsync/execSync 线程、uuid、base64、sha 系列、AES-128、random |
| 字符串工具 | 15 | trim/split/chars/hex/类型判断/拼音 toPinYin/BOM 清洗/Unicode 还原/HMAC 签名 |
| 颜色工具 | 5 | parseColor/int2Hex/hex2Int/toInt/toHex/rgb/argb（EasyClick 兼容，支持 #RGB/#RRGGBB/0x/数字） |
| 线程与工具模块 | 14 | thread.execAsync/execSync/cancelThread/stopAll/isCancelled、utils.dataMd5/fileMd5/randomInt/getRangeInt/getRatio/zip/unzip/readFileInZip/playMp3/stopMp3/deleteAllPhotos/deleteAllVideos/requestPhotoAuthorization、全局别名 getPasteboard/setPasteboard/openUrl/uploadToAlbum/childcount |
| 悬浮窗口 | 3 | screenDraw 屏幕绘制、floatBall 悬浮球（可拖动、setFloatBallPoint 别名） |

本轮新增（Round 48）：AScript 风格开发文档站 `docs/devdocs/index.html` 上线（侧栏分类树 + 开始/控件检索散文页 + 15 个 API 分类页，257 函数全量渲染，参数表/返回值/一键复制可运行示例/每分类调试提示，顶栏搜索 + hash 路由，单文件离线，对标 ascript.cn/docs/ios 文档体验）；修复 `speech`/`base64` 两个分类未进 CATEGORIES 导致 api-reference.html 从未渲染其卡片的 bug；
本轮新增（Round 47）：完全移除外部 WDA 适配器（AutoWDAHTTPAdapter 及其测试/verify 锚点/模板配置/文档）——内置 no-WDA 成为唯一跨 App 路线，避免双路线维护成本；内置 capabilities 补 `appList`/`appLifecycle`/`systemActions` 键（运行时探测）；模板 App 默认 BUILTIN，设置页改为“内置 no-WDA / UIKit”开关；Node 侧测试仍 79 项，原生 Xcode 测试删除 24 个 WDA 专用用例（剩 58+14 项）、文档措辞全量同步；零 bootstrap 改动（60895/61440）；
本轮新增（Round 46）：内置 no-WDA 适配器 `AutoBuiltinAdapter` 上线——IOHIDEvent 真实触摸注入（系统级，支持多点 W3C 手势时序回放）、AXUIElement 系统级控件查询（跨 App，毫秒级）、SpringBoard/BackBoard/LSApplicationWorkspace 应用控制（启动/终止/前台/锁屏/设置页）、UIGetScreenImage 截图 + Vision OCR；外部 WDA 依赖降级为 legacy 回退，主路线不再需要 WDA Runner（对标 AScript Agent no-WDA / kuaijs）；新架构文档 docs/NO_WDA_ARCHITECTURE.md；本轮零 bootstrap JS 改动（60895/61440）；
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