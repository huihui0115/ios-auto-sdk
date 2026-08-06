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
| Touch | coordinate click, double click, long press, pressure, multi-touch, swipe, drag | selector activation, coordinate activation, double activation, scroll-view swipe, direction-swipe helpers (up/down/left/right), long-press drag, child-count | UIKit adapter cannot inject real touches, long press, pressure, multi-touch, or cross-app gestures; a WDA/private adapter is required |
| Nodes | exact/regex selectors, XPath, chained filters, all/one, parent/child/siblings, fetch filters, locked XML trees, and phone-side execution | host-app stable handles plus WDA selectors, attributes, bounds, `/source`-derived parent/child/siblings, wait and scroll | No `lockNodeFromXml`, phone-side locked XML execution, or guaranteed cross-snapshot WDA handles |
| Screenshot/color | stream capture, compare/find color, multi-color, non-color search | PNG/region screenshot, pixel read, single-color find, one-capture multi-point compare, multi-color pattern search, findNotColor | No stream capture, transparent-color template mode, or reusable image object |
| Image matching | OpenCV template matching and image transformations | bounded two-stage CoreGraphics similarity match, phone-side template deployment, clip/scale/gray/binaryzation/rotate pixel pipeline, Inspector testing | Not OpenCV-grade; no scale/rotation invariant match or cvFindImage (OpenCV) |
| OCR/AI vision | phone/controller OCR APIs, multiple OCR engines, YOLO, and AI-agent workflows | on-device Apple Vision OCR with confidence and screen-point bounds | No selectable OCR model, custom model, YOLO runtime, AI agent, or batch image-object API |
| Input/app control | input-method APIs, helper APIs, Home/app lifecycle and process operations | host text replacement plus WDA app launch/activate/terminate/state/current helpers, installed-app list, prefix launch, and home-screen/lock/unlock endpoints | No system input method or UIKit-adapter cross-app lifecycle control |
| Device | screen/model/OS/battery, app list, serial, orientation, charging | public device/app/screen/battery/orientation information (incl. 宽x高 text), installed-app list, clipboard/brightness/volume/vibration, and WDA home-screen/lock/unlock | No serial number, reboot, install/uninstall, or process control |
| Media | save images/videos to the camera roll through the agent | add-only Photos writes for sandbox images, base64 images, videos and screenshots (`media.*`), region screenshot (`screenshotRegion`), gated by `allowMediaLibrary` and an iOS authorization prompt; requires `NSPhotoLibraryAddUsageDescription`. **Round 8:** `media.deleteAllPhotos/deleteAllVideos/deleteAllMedia` clear the camera roll (read-write Photos access, returns deleted count) | No album-object API, batch import, photo picker, or camera/QR capture |
| Files | sandbox file CRUD, lines, copy, Excel | UTF-8/base64 reads, atomic write, append, list, mkdir, copy/move/rename/remove below a confined root, line operations (lineCount/getLineText/insertLineText/resetLineText), Excel (xlsx/csv), ZIP (zip/unzip/readFileInZip), plist read/write | No file upload picker, or access outside the configured sandbox root |
| Storage | named typed key-value stores | named persistent JSON stores plus EasyClick-style typed wrappers | No database/JDBC layer; 1 MiB default namespace limit |
| HTTP | generic requests, GET/POST/JSON, download, WebSocket | guarded HTTP methods, JSON/binary responses, host allowlist, response limit, sandbox download | Synchronous JS facade, no multipart/form upload, cookie jar API, proxy API, or script WebSocket client |
| Timers/threads | timeout/interval, async/sync thread APIs, workers | cooperative `sleep`, timeout/interval queues drained before completion, parallel `execAsync/execSync` threads (join/getResult/cancel, up to 8), native URLSession work | No retained event loop after script completion or worker runtime |
| External transports/services | BLE events, OTG HID, Aux remote assistance, JDBC MySQL, and network-verification services | authenticated WebSocket debugging over loopback/USB or opt-in Wi-Fi, guarded HTTP, and an optional WDA HTTP adapter | No BLE/OTG/Aux controller, JDBC driver, or EasyClick service integration; the WDA adapter still needs a separately running Runner |
| IDE/debug | IDE, live screen, node panel, logs, remote execution | VS Code completion/snippets, safe single-file TypeScript transpilation, persistent Wi-Fi/USB-forwarded connection, visual screenshot/node Inspector, node/image/color/OCR tests, code generation, deployed script/asset management, and Actions build/download | No continuous video stream, breakpoint debugger, TypeScript module bundler, package manager, or verified real-device tunnel session |
| Deployment | signed EasyClick agent/IPA products, proxy IPA, Bluetooth and OTG HID paths | template app, unsigned IPA workflow (free Apple ID signing), optional separately installed WDA client | Not compiled or tested on Xcode, a real iPhone, or a TrollStore-installed WDA Runner in this Windows workspace |

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
- Cross-app automation: `AutoWDAHTTPAdapter` is included as a client, but a
  separately running WDA/XCTest-compatible Runner still has to work on the
  target iOS version.
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
3. Validate a separately signed WDA/iOS-Tagent Runner with `AutoWDAHTTPAdapter` for real touch and cross-app nodes.
4. Replace the basic matcher with an optional OpenCV-backed adapter.
5. Add workers/parallel JavaScript contexts and a safe execution interrupt mechanism.
6. Upgrade point-in-time screenshots and node JSON into a continuous visual inspector.

## 函数级覆盖清单（2026-08-06）

交互式速查 `docs/api-reference.html` 收录 243 个可运行示例（245 个函数），分 13 个分类，
每张函数卡带 EasyClick/AutoJS 对标函数与一键复制示例：

| 分类 | 函数数 | 亮点 |
| --- | --- | --- |
| 日志与调试 | 9 | console 分级、toast/toastLog、alert/exit/restartScript、sleep |
| 触摸与节点 | 43 | 坐标/节点点击、滑动/手势/pinch、输入、节点查询（getChild/getSiblings/clickCenter/clickRandom）、node.keep/unkeep |
| 图色与OCR | 29 | 截图/区域截图、找图、找色、多点找色、findNotColor、像素（screen.getColor/getColorRGB/getColorHex）、多点比对（findColors/isColors）、OCR、二维码/条形码识别 scanCode |
| App与应用控制 | 21 | launch/activate/terminate/state/openURL/homeScreen/current/appList/isInstalled/getAppName/isRunning/锁屏解锁 |
| 设备与系统 | 29 | 屏幕、电量、方向、剪贴板、亮度、音量、振动、内存、机型、系统版本、设备ID |
| 坐标与屏幕 | 5 | setScreenMetrics/getScreenMetrics/metrics.point/device 尺寸 |
| 文件 | 38 | 沙盒 CRUD、行操作、复制/移动/重命名、stat、Excel、ZIP、plist |
| 存储 | 10 | 命名 typed store |
| 网络HTTP | 10 | get/post/postJSON/getJSON/download/通用请求 |
| 相册媒体 | 11 | saveImage/saveImageBase64/saveVideo/saveScreenshot/deleteAllPhotos/deleteAllVideos/deleteAllMedia/playMp3/stopMp3/相册权限 |
| 定时器与工具 | 21 | 定时器、execAsync/execSync 线程、uuid、base64、sha 系列、AES-128、random |
| 字符串工具 | 14 | trim/split/chars/hex/类型判断/拼音 toPinYin/BOM 清洗/Unicode 还原 |
| 悬浮窗口 | 3 | screenDraw 屏幕绘制、floatBall 悬浮球（可拖动、setFloatBallPoint 别名） |

本轮新增（Round 14）：`screen.*` EasyClick 兼容图色模块（getColor/getColorRGB/getColorHex + 找图找色/OCR/截图入口）、全局别名 `screen`/`string`、`app.getAppName`/`app.isRunning`；
本轮新增（Round 12）：`formatDate/dateFormat`（yyyy/MM/dd/HH/mm/ss/SSS/E 星期）、`sleepRandom` 随机睡眠、
`strings.*` 查找/截取/补位/format 系列、`app.isInstalled`、内存别名；
（Round 11 对标 TrollAutoScript）：`toPinYin`、`screenDraw.*` 悬浮绘制、
`floatBall.*` 悬浮球与 `setFloatBallPoint`、`node.keep/unkeep`、`stripUtf8Bom`/`fromUnicode`；
同时修复了文档生成器中 14 处历史中文损坏条目。