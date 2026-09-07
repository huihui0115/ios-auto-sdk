# AutoSDK AI 交接手册（换 AI 前先读这里）

> 用途：任何新接手本项目的 AI，先读本文件 + 根目录 `AGENTS.md`，
> 再读 `docs/EASYCLICK_COMPARISON.md` 的能力差距表。本文档描述架构、
> 现状、工作流、坑和待办，确保换人后能无缝继续迭代。
> 最后更新：Round 74（v1.38.1，2026-09-07）。

---

## 1. 项目是什么

嵌入式 iOS JavaScript 自动化 SDK（对标 EasyClick iOS / AScript iOS /
TrollAutoScript / AutoJS / kuaijs）。核心思路：

- 宿主 App 内嵌一个 **JavaScriptCore**，加载内置 bootstrap JS（60KB 以内），
  提供 250+ 个脚本函数（点击、滑动、节点、图色、OCR、YOLO、文件、存储、
  HTTP、SQLite、线程、定位、相册、悬浮窗等）。
- 脚本通过 **bridge 对象**（`__bridge`）调用原生方法：`invokeClick`、
  `invokeDevice`、`invokeFile`、`invokeHTTP`、`invokeNodeSnapshot`、
  `invokeExecAsync`、`invokeNative`（通用 name/arguments 通道）等约 84 个。
- 宿主 App 是普通 App（免越狱）；**Round 46 起跨 App 自动化主路线是内置
  no-WDA 适配器 `AutoBuiltinAdapter`**（IOHIDEvent 真实触摸注入 + AXUIElement
  系统级控件查询 + SpringBoard 应用控制，全部私有 API 运行时 dlopen/dlsym
  解析，不链接私有框架），对标 AScript Agent 模式；外部 WDA/XCTest 适配器（`AutoWDAHTTPAdapter`）
  已在 Round 47 **完全移除**（无回退）。触摸注入与系统级 AX 需要
  允许私有 API 的构建（TrollStore/开发者签名），详见
  `docs/NO_WDA_ARCHITECTURE.md`。

## 2. 架构速览

```
JS 脚本 (Examples/TemplateApp/Scripts/*.js)
   │
   ▼
JavaScriptCore (AutoEngine.m evaluateScript)
   │  加载 AutoBootstrapScript()（bootstrap 初始化 g.xxx 全部 API）
   │  每轮执行前调用 drainTimers 刷新定时器/协程
   ▼
bridge (__bridge 对象，JSValue block)
   ├── invokeClick / invokeClickPoint / invokeSwipe / invokeInput ...
   ├── invokeDevice / invokeMedia / invokeApp / invokeNative(name, args)
   ├── invokeFile / invokeStorage / invokeHTTP
   ├── invokeNodeSnapshot / invokePixelColor / invokeFindColorEx ...
   ├── invokeOCR / invokeExecAsync / invokeExecOp / invokeCapabilities
   ▼
原生实现 (AutoEngine.m / AutoScriptSupport.m / AutoHTTPSupport.m)
   ├── UIKit 适配器（宿主 App 内自动化）AutoUIKitAdapter
   ├── 内置 no-WDA 适配器（唯一跨 App 路线）AutoBuiltinAdapter
   │      IOHIDEvent 触摸注入 + 系统级 AX 控件 + SpringBoard 应用控制
   └── 不可用回退 AutoUnavailableAdapter
```

## 3. 仓库地图

| 路径 | 说明 |
| --- | --- |
| `tools/bootstrap-source.js` | **bootstrap JS 唯一权威源**（改这里） |
| `tools/regenerate-bootstrap.mjs` | 重新编码进 .m（`npm run regenerate:bootstrap`） |
| `Sources/AutoSDK/AutoBootstrapScript.m` | 生成的 ObjC 字符串字面量（勿手改） |
| `Sources/AutoSDK/AutoEngine.m` | 原生引擎：JS 桥接、调度、节点/图色/OCR/线程/定位等（CRLF） |
| `Sources/AutoSDK/AutoScriptSupport.m` | 文件沙盒、HTTP 安全、HMAC、sqlite、yolo 等支持层 |
| `Sources/AutoSDK/AutoHTTPSupport.m` | HTTP 协议实现 |
| `Sources/AutoSDK/AutoDebugServer.m` | WebSocket 调试服务（VS Code 扩展对接） |
| `Sources/AutoSDK/AutoBuiltinAdapter.m` | 内置 no-WDA 适配器（IOHIDEvent 触摸注入 + 系统级 AX 查询 + SpringBoard/BackBoard 应用控制 + 截图/OCR，私有 API 全运行时解析，~76KB LF） |
| `Sources/AutoSDK/include/AutoBuiltinAdapter.h` | 内置适配器头（maxSnapshotNodes/maxSnapshotDepth/screenshotCacheDuration） |
| `docs/NO_WDA_ARCHITECTURE.md` | 内置 no-WDA 适配器架构/启用方式/签名要求/真机验证计划 |
| `types/autosdk.d.ts` | TypeScript 类型声明（与文档闭环） |
| `tools/verify.mjs` | 一致性断言（bootstrap/原生/d.ts/文档/版本） |
| `tools/bootstrap.test.mjs` | bootstrap 行为测试（Node vm + mock bridge） |
| `tools/generate-api-reference.mjs` | 手写 APIS/CATEGORIES 元数据，不直接生成 HTML |
| `tools/generate-devdocs.mjs` | 唯一文档站 → `docs/index.html`（指南+模块导航+搜索+过滤+复制） |
| `tools/devdocs-template.html` | 文档站 HTML/CSS/交互模板（零外部依赖、可离线打开） |
| `tools/bump-version.mjs` | 版本四件套同步 |
| `tools/auto-sdk.mjs` | build / build-remote（IPA 产物） |
| `vscode-extension/inspector-service.js` | VS Code 截图/节点/OCR/找图协议校验与全局重任务串行队列 |
| `vscode-extension/inspector-session.js` | Inspector 面板生命周期、请求关联、同类待处理任务去重 |
| `vscode-extension/media/inspector-model.js` | Webview 可单测的节点选择器、坐标与区域纯模型 |
| `vscode-extension/completion-model.js` | 无 VS Code 依赖的补全命名空间、复合签名与 Snippet 纯模型 |
| `vscode-extension/device-discovery.js` | 有界、无 shell 的 USB iPhone 搜索（idevice_id/ideviceinfo） |
| `vscode-extension/wifi-discovery.js` | 有界 Bonjour/mDNS 局域网扫描（`_autosdk._tcp`，默认 Wi-Fi 接入） |
| `tools/bootstrap-history/` | 历史改写脚本（仅参考，勿对新版本执行） |
| `Examples/TemplateApp/` | 宿主模板 App（含 Info.plist、脚本示例） |
| `docs/` | 对标审计（EASYCLICK/ASCRIPT/TROLLAUTOSCRIPT）、协议、发布、性能 |
| `Tests/` | 原生 Xcode 单元测试（AutoEngineTests / AutoHTTPProtocolTests） |

## 4. 当前状态（Round 74 / v1.38.1）

- HEAD：见 `git log -1`；分支 `main`；发布走 tag `vX.Y.Z`。
- bootstrap 解码 **61262 / 61440**（预算 60×1024 UTF-16 码元，余 178）。
- 文档 **259 个 API 条目 / 259 个可运行示例 / 14 个模块**；bootstrap/工具测试 **88 项**；原生 XCTest **90 项**；VS Code 插件 **0.13.0**，测试 **121 项**。
- 全部命令通过：`npm run verify`、`npm test`、`tsc --noEmit`、`npm run docs`、插件 `check/test`。
- **Round 74 CI 回归修复**：v1.38.0 新增 12 项原生测试通过，但旧共享引擎测试
  在冷启动/短等待超时后串入后续测试。现在 setup/teardown 等待脚本队列及主队列栅栏，
  停止测试由实际第三次 click 触发，功能烟测明确放宽冷启动预算；同时修复已完成
  脚本的迟到 watchdog 无条件停止下一次运行的竞态。v1.38.0 的失败标签保留，不覆写。
  GitHub CLI 在 Windows 沙盒中可能误报认证失败，使用受批准的正常主机调用可读取 CI 日志。
- **Round 73 整体审计**：新增 `AutoSystemOperations.h/.m` 管理可取消系统等待与一次性定位；
  定位/VPN 50ms 分片检查停止，定位移除主线程阻塞前置查询、迟到回调拒绝、统一错误。
  插件增加安全的选区运行，修复 Inspector 选择版本/隐藏 busy 生命周期、Bonjour 清理和配对目标切换；
  7 个测试执行真实 Webview 控制器，12 个原生假管理器/回调门闩测试不依赖 locationd。
  完整范围、竞品来源和剩余问题见 `docs/QUALITY_AUDIT.md`；不宣称真机验收已完成。
- **Round 46 战略转向**：放弃“必须外部 WDA”路线，新增内置 no-WDA 适配器
  `AutoBuiltinAdapter`（系统级触摸注入/控件查询/应用控制）。
- **Round 47 清场**：`AutoWDAHTTPAdapter` 及其全部测试/配置/verify 锚点/文档
  已完全移除；内置 no-WDA 是唯一跨 App 路线。模板 App 默认 BUILTIN，
  设置页为“内置 no-WDA / UIKit”开关；内置 capabilities 新增
  `appList`/`appLifecycle`/`systemActions` 键（运行时探测）。架构与签名要求见
  `docs/NO_WDA_ARCHITECTURE.md`。
- **Round 60 调试工具重构**：VS Code 插件 0.6.0 把可视化协议、会话调度和 Webview
  几何模型拆成独立模块；截图/节点/点色/OCR/找图共用串行重任务通道，响应按 requestId
  关联，同类排队请求仅保留最新结果；支持稳定节点选择恢复和相关快照 JSON 导出。
- **Round 61 Xcode 发布热修**：修复 `AutoBuiltinAdapter` 的 AX Core Foundation/Objective-C
  ARC 桥接与无效泛型声明，使 Xcode 15.4 能编译内置 no-WDA 适配器；同时修正节点
  `type` 选择器比较的逻辑非优先级错误，并由 verify 固化桥接约束。
- **Round 62 Xcode 链热修**：生成器为 `AutoBootstrapScript.m` 自动导入声明头，
  解决 Swift Package/Xcode 将其作为独立翻译单元编译时无法识别 `NSString` 的问题；
  同时修复 `AutoEngine.m` 的 SQLite C 指针泛型、无效 Vision 类型、媒体函数声明顺序与
  `void` 装箱错误，以及 XCTest 揭出的单文件删除、`auto.node` 接线、click arity 和通知
  无宿主异常；补齐 `auto.screen`/`auto.floatLog` 与 POST multipart 二参兼容；bootstrap
  为 **60782/61440**（余 658）。
- **Round 63 Inspector 稳定性迭代**：VS Code 插件 0.7.0 新增 Cancel/Escape 取消、
  有界动作后刷新延迟；取消/隐藏/销毁/被替代的任务不再提交或导出陈旧快照；屏幕边缘
  坐标限定为有效像素，重叠同尺寸节点优先最深控件；显式取消请求的迟到响应静默回收，
  其 ID 集合上限 128，真实未知响应仍保留诊断。bootstrap 与脚本 API 零改动。
- **Round 64 插件补全与 Inspector 生成链修复**：插件 0.8.0 将命名空间识别、复合
  签名拆分和 Snippet 生成提取到纯模型；补齐 14 个缺失模块及 `action`/`string`
  别名的定向候选，25 组历史复合签名不再生成损坏代码。Inspector 使用规范化
  selector 键恢复选择，并以完整相关快照而非过滤结果集验证最小唯一选择器；所有生成脚本进入纯模型回归测试；
  `speech` 命名空间补齐 TypeScript 声明。bootstrap 零改动。
- **Round 65 HTML 开发文档收敛**：把门户、图文教程、开发站和 API 卡片合并为
  唯一 `docs/index.html`；新站提供 7 篇任务指南、14 个 API 模块、263 个条目，
  支持全局搜索、模块过滤、深链接、移动导航、明暗主题和离线复制。删除 3 份重复
  HTML，修正 `http.getJSON` 返回值及 3 个不可直接使用的 API 示例；verify 新增
  示例语法、条目全量与旧入口不得回归的约束。
- **Round 66 设备接入与一键运行**：插件 0.9.0 新增 USB iPhone 搜索/添加命令，
  使用有界、无 shell 的 `idevice_id` / `ideviceinfo` 子进程，优先复用 `iproxy`
  同目录工具；选择手机后保存 UDID、启动托管隧道并自动测试，失败可直接回退 Wi-Fi。
  断开状态栏改为“add iPhone”，JS/TS 编辑器新增右键运行和标题栏播放按钮；跨设备
  不复用旧 token，连接保存失败会回滚 UDID。插件测试 90 项，bootstrap 零改动。
- **Round 67 Wi-Fi 广播发现与一键重连**：插件 0.10.0 把 Wi-Fi 调试升为默认入口，
  TemplateApp 在 Wi-Fi 调试开启时通过 Network.framework 发布 `_autosdk._tcp`
  Bonjour 服务，稳定服务名不携带 token；插件用有界 mDNS 扫描列出手机，首次输入
  token 后把 SecretStorage 凭据与稳定广播身份关联，后续 DHCP 地址变化仍可一键
  重连。手动地址支持只输手机 IP，USB 搜索降为高级备用。插件测试 97 项。
- **Round 68 macOS 发布验证热修**：插件 0.10.1 的 USB 备用工具路径改为按目标
  平台选择 `path.win32` / `path.posix`，修复 Windows 本地测试通过但 macOS CI
  无法解析 `C:\...\iproxy.exe` 同目录工具的跨平台错误，并增加 POSIX 路径回归断言。
- **Round 69 Bonjour 原生编译热修**：将不存在的 `nw_listener_set_service` 替换为
  Apple Network.framework 的 `nw_advertise_descriptor_create_bonjour_service` 与
  `nw_listener_set_advertise_descriptor` 正式调用，解除 Xcode 编译阻断；插件行为与
  `_autosdk._tcp` 广播协议不变。
- **Round 70 设备与系统常用入口**：新增 `vpn.status/connect/disconnect/openSettings`
  管理宿主 App 自己通过 Personal VPN entitlement 预存的 `NEVPNManager` 配置；它不读取、
  选择或控制其他 VPN App/MDM 配置。`system.openSettings(panel)` 以 best-effort 方式打开
  VPN/Wi-Fi/蓝牙/蜂窝/飞行模式等设置页，但不静默修改系统开关；新增低电量模式、定位
  总开关与本 App 定位授权状态查询。VS Code 的 `device.` 补全现覆盖完整
  `AutoDeviceAPI`，并由类型声明一致性测试防止再次漏项；插件版本为 **0.11.0**。
- **Round 71 iOS CI 稳定性修复**：低电量、定位总开关和定位授权映射的原生
  回归测试改为注入原始系统状态，不再依赖冷启动模拟器的实时 `locationd`；生产默认
  provider 为 `nil`，仍调用真实 `NSProcessInfo` / `CLLocationManager` API。新增覆盖全部
  授权枚举及未知值回退的确定性测试，原生 XCTest 共 **75 项**，公开 API 与插件不变。
- **Round 72 调试与发布可靠性迭代**：插件 0.12.0 的 Bonjour 扫描在首台响应后继续
  收集多机并支持取消；首次/旧 token 失败可原地重输或重试，未配置就右键运行可直接
  扫描添加。原生线程把子 JSContext 的桥失败传播到 `execSync/getResult/join`，不再返回
  误导值并丢失 `lastError`；原生 XCTest **78 项**。CI 迁到 macOS 15 与 Node 24 Actions，
  Xcode 15/16 诊断兼容；快速上手统一为唯一 HTML 入口。bootstrap/公开 API 数量不变。

已实现能力（详见唯一 HTML 文档入口 `docs/index.html`）：
触摸/节点（含 WDA selector）、图色（findColor/findColorEx/findMultiColor/
findNotColor/findImage/cmpColor/isColors）、像素（screen.getColor 系列）、
颜色工具（parseColor/int2Hex/hex2Int/rgb/argb）、OCR（Apple Vision +
Baidu）、YOLO 兼容入口（iOS 15+ Vision 全图分类，非边界框检测器）、文件（沙盒 CRUD/行操作/Excel/ZIP/plist）、
存储（typed store）、SQLite、HTTP（get/post/JSON/multipart/download +
host allowlist）、WebSocket 客户端、线程（execAsync/execSync + thread
命名空间）、定时器、定位（CLLocationManager 一次性）、相册（保存/清空 +
权限）、媒体（mp3）、剪贴板/亮度/音量/振动/手电、悬浮窗（floatLog/
floatBall/screenDraw）、Personal VPN 有限控制、系统设置页入口、低电量/定位状态、
webView 悬浮网页、AES/HMAC/MD5/SHA、拼音、
屏幕尺寸适配（setScreenMetrics）、utils 工具命名空间、device 全局简写等。

## 5. 对标基线

官方参考（每轮迭代去拉一遍函数清单做差集）：
- EasyClick iOS：<https://ieasyclick.com/iosdocs/zh-cn/funcs>（页面是 SPA，
  直接抓 `/iosdocs/funcs/{device,utils,file,http,image,node,ocr,storage,thread,yolo,event,apphelper,ime,netcard}-api`
  的静态 HTML，h2 标题即 `模块.函数`）。
- AScript iOS：<https://www.ascript.cn/docs/ios/intro>（部分路径 403，需 UA）。
- TrollAutoScript：<https://docs.trollautoscript.com/docs/whatis>。
- kuaijs：<https://www.kuaijs.com/>。
- 差距审计：`docs/EASYCLICK_COMPARISON.md`（含能力矩阵 + 每类缺口）、
  `docs/ASCRIPT_COMPARISON.md`、`docs/TROLLAUTOSCRIPT_COMPARISON.md`。

## 6. 已知缺口 / 待办（下轮优先）

### 可实现（JS 别名/封装，注意 60KB 预算）

- ~~`touchDown/touchMove/touchUp`~~ 已完成（Round 50，分指暂存 + touchUp() 全抬）。
- ~~`image.readBitmap/bitmapToImage/base64Bitmap/bitmapBase64/saveBitmap`~~
  已完成（Round 56，路径句柄模型；getBitmapPixelColor 一并补齐；文档已标注语义差异）。
- ~~`ocr.newOcr/ocrInstance.ocrBitmap/ocrImage`~~ 已完成（Round 55，实例合并默认参数，ocrImage 对沙盒图片文件 OCR）。
- ~~`http.requestEx`~~ 已完成（Round 55，等价 http() 别名）；`agentRequestEx` 属 agent 远程类，记录为不可实现。
- ~~`string.atrim/isInteger/string.random`、`pasteboard.read/write`、`json.encode/decode`、`device.setBacklightLevel/backlightLevel`~~ 已完成（Round 59，TrollAutoScript 对标补齐）。Round 70 进一步补充宿主自有 Personal VPN 的状态/连接/断开和设置页入口；任意 VPN 配置创建/选择/删除、静默切换飞行模式/Wi-Fi/蓝牙/蜂窝、installIpa/uninstall、硬件按键、coreML/paddle 托管仍不承诺。

### 不可实现（记录为缺口即可）
- `imeApi.*`（需自建输入法）、`ecNetCard.*`/BLE/OTG/HID（硬件）、
  agent 远程调用、OpenCV 级 `matchTemplate`（当前 CoreGraphics）、
  任意第三方 VPN 配置管理、系统网络/飞行模式静默切换、无限纯 JS 循环抢占停止。
  （实时触摸注入已由 Round 46 内置适配器解决；常用系统开关可通过
  `system.openSettings` 引导用户手动修改。）

### Round 46 内置适配器真机验证待办（下轮优先）
- 真机验证 IOHIDEvent 触摸注入（需允许私有 API 的签名：TrollStore/开发者证书；
  App Store 构建会被审核拒绝，capabilities 会如实降级报告）。
- 真机验证系统级 AX 控件查询（跨 App 毫秒级检索）与 SpringBoard 应用控制
  （launch/terminate/前台/锁屏/设置页解锁）。
- `findImage` 已于 Round 49 实现（有界两阶段模板匹配）；
  xpath 子集已于 Round 53 实现（单步 //Type[@attr='v'] 等翻译为原生查询键）；predicate 仍返回清晰错误。
- 验证模板 App `AutoSDKAdapter=BUILTIN` 配置接线与 capabilities 降级路径。
- 注：每次 push main/tag 都会触发 GitHub Actions（macos-15：verify+npm test+
  Xcode 模拟器测试+IPA 打包+Release），原生代码的编译与模拟器行为已被 CI 覆盖；
  真机专属项仅剩私有 API 行为（IOHIDEvent/AX/SpringBoard）。
- R53-R59 新增待真机抽查：xpath 子集实机控件命中、ocr.newOcr 对文件 OCR、
  位图句柄过 image 操作链、execSync 对象返回值、lastError() 错误读取、
  pasteboard 读写（含无权限时返回）、setBacklightLevel 真机亮度生效。

### 工程质量待办
- 原生 `Tests/` 包含 AutoEngineTests / AutoHTTPProtocolTests / AutoSystemOperationsTests，可在
  macOS/Xcode 环境扩充；Windows 环境以 `npm test`（Node 端）为主。
- `docs/PERFORMANCE.md` 记录了图色/OCR 预算，新增原生能力时保持有界。
- 每轮更新 `docs/EASYCLICK_COMPARISON.md` 的矩阵与计数，避免文档漂移。
- Round 73 已修复定位前置查询/迟到 setup、错误 domain 和定位/VPN 短分片取消；
  下一步专项覆盖其他旧 HTTP/适配器等待的子线程 cancel 一致性，并完成真机权限/后台验收。
- 无设备列表、工程打包器、视频流与断点调试；Pages 探测失败仍需区分禁用与权限/网络问题。

## 7. 核心工作流

### 7.1 改 bootstrap（最常见）
1. 编辑 `tools/bootstrap-source.js`（单行 minified，用 `;` 分隔语句）。
2. `npm run regenerate:bootstrap`（重新编码 + round-trip + 预算校验）。
3. `npm test` 加/跑用例；`npm run verify` 必须过。
4. 若超预算：先在 source 里压缩别处（参考历史：dvf/avf/hsh/forEach helper）。

### 7.2 加一个新函数（完整闭环）
1. bootstrap-source.js：定义函数/别名 + `g.xxx=...` 导出。
2. `types/autosdk.d.ts`：`declare function` 或 interface 方法。
3. `tools/generate-api-reference.mjs`：加 APIS.push 卡片（sig 必须覆盖新名字，
   否则 verify 报 missing）。
4. `tools/bootstrap.test.mjs`：加行为测试。
5. `tools/verify.mjs`：如需可加字符串锚点断言（锚点文本必须与 source 一致）。
6. 跑 `npm run verify` / `npm test` / `tsc` / `npm run docs`。
7. 更新 `docs/EASYCLICK_COMPARISON.md` 计数与“本轮新增”。

### 7.3 改原生（AutoEngine.m / AutoScriptSupport.m）
- 文件是 **CRLF**，Node 模板字符串替换时先 `.replace(/\n/g,'\r\n')`。
- 新增桥接操作遵循现有 dispatch 模式（`@"xxOp"` 字符串开关）。
- 改动后必须 `npm run verify`（verify 里有大量原生锚点断言）。

### 7.4 版本发布
1. `node tools/bump-version.mjs X.Y.Z`（同步 package.json/lock/podspec/Version.m）。
2. 手工重写 CHANGELOG 的 `[X.Y.Z]` 占位块（bump 会插入损坏块）。
3. `docs/MARKET_RELEASE.md` 里把 tag 行改成 vX.Y.Z。
4. `git add -A; git commit -m "Feat: round N - ... (vX.Y.Z)"`。
5. `git tag vX.Y.Z; git push origin main vX.Y.Z`。
6. 发布流程详见 `docs/MARKET_RELEASE.md`、`docs/WINDOWS_SIDELOAD.md`。

## 8. 坑与注意事项

- **行尾**：仓库 CRLF/LF 混用（每个文件可能不同区域不同）。读文件后替换前
  必须验证唯一性（`split(old).length-1===1`）。
- **PowerShell**：无 `&&`；中文/多行逻辑写 `.mjs` 到 `$env:TEMP` 执行；
  `git push` 的 stderr 会显示红字，看 `main -> main` 和 `[new tag]` 判断成功。
- **预算口径**：61440 是 UTF-16 `script.length`（verify 同口径），不是 UTF-8 字节
  （含中文正则时 UTF-8 会更大，勿混用）。
- **d.ts ↔ 文档闭环**：文档扫描是“d.ts 声明必须被文档覆盖”，不是反向。
- **历史脚本勿重跑**：`tools/bootstrap-history/*` 假设旧起点，对当前版本
  会二次应用。当前唯一入口是 `regenerate-bootstrap.mjs`。
- **版本一致性**：verify 会检查四件套版本号；`bump-version.mjs` 会自动同步。
- **测试隔离**：bootstrap 测试在 Node vm 里跑 mock bridge，不连真机；
  低电量/定位系统状态的模拟器回归测试使用原始值注入，不依赖实时 TCC/CoreLocation
  daemon；原生真值仍以 verify 锚点 + Xcode 真机抽查为准。

## 9. 历轮主线（git log 可查）

- R74（v1.38.1）：共享引擎 XCTest 生命周期隔离、确定性循环停止触发、迟到 watchdog 完成门禁。

- R73（v1.38.0）：系统等待模块化、选区运行、Inspector 选择级迟到结果防护、
  Bonjour 生命周期/配对切换回归、显式 SQLite 链接；删除过期 WDA 安装方案。

- R72（v1.37.0）：**调试、错误传播与发布链可靠性**——插件 0.12.0 支持可取消的
  多 iPhone 广播收集、token 原地重输/重试、未配置运行直达扫描，并把 Inspector
  取色模式明确命名为 Color；子 JSContext 的桥失败通过 execSync/async result/join
  正确外传，类型同步；CI 迁到 macOS 15、Xcode 15/16 兼容诊断及 Node 24 Actions；
  快速上手统一到唯一 HTML。bootstrap 61262/61440，文档 259 项、Node 测试 88 项、
  原生 XCTest 78 项、插件测试 105 项。
- R71（v1.36.1）：**iOS 系统状态测试稳定性修复**——把低电量、定位服务与定位授权
  的原生测试改为私有 provider 注入原始值，覆盖五种授权状态和未知枚举回退，消除冷
  模拟器 `locationd` 对发布 CI 的非确定性依赖；生产默认路径与 Round 70 完全一致，
  无新增公开 API，原生 XCTest 75 项。
- R70（v1.36.0）：**设备与系统常用入口 + 补全闭环**——新增宿主自有 Personal VPN
  状态/连接/断开与设置页入口（需 entitlement 和预存配置），新增 best-effort 常用设置页、
  低电量模式、定位总开关和本 App 定位授权查询；不伪装成静默系统开关。VS Code
  `device.` 补全覆盖完整 `AutoDeviceAPI` 并加入一致性测试；文档去重为 259 个卡片，
  bootstrap 61262/61440（余 178），Node 测试 88 项，插件测试 97 项。
- R69（v1.35.2）：**Bonjour 原生编译热修**——按 Apple Network.framework C API
  先创建 Bonjour advertise descriptor，再绑定 listener，恢复 iOS/Xcode 构建；
  局域网扫描、一键添加、SecretStorage token 配对与编辑器运行流程保持不变。
- R68（v1.35.1）：**macOS 发布验证热修**——插件 0.10.1 修复 USB 备用发现中
  目标平台与宿主平台路径语义混用，Windows/POSIX 工具同目录候选现在跨平台稳定，
  解除 Round 66 起的 CI 验证阻断。
- R67（v1.35.0）：**Wi-Fi Bonjour 广播与一键重连**——TemplateApp 发布
  `_autosdk._tcp` 稳定身份，插件 0.10.0 默认扫描局域网、选择添加并测试；首次 token
  配对后按广播身份安全复用，支持 DHCP 地址变化，广播不含 token；手动输入只需手机
  IP，USB/libimobiledevice 保留为高级命令；插件测试 97 项。
- R66（v1.34.0）：**设备搜索与编辑器一键运行**——插件 0.9.0 新增 USB iPhone
  搜索/添加、自动隧道/连接测试、Wi-Fi 回退、断开状态栏入口，以及 JS/TS 右键与
  标题栏运行；设备发现有输出/超时边界且禁用 shell，插件测试 90 项。
- R65（v1.33.0）：**HTML 开发文档单入口重构**——生成唯一 `docs/index.html`，
  合并 7 篇任务指南、14 个模块和 263 个 API 条目；新增搜索/过滤/深链接/主题/
  移动导航/离线复制，删除 3 份旧 HTML；修正 4 处示例/返回值并新增文档完整性校验。
- R64（v1.32.0）：**VS Code 补全与 Inspector 生成链修复**——插件 0.8.0 新增
  可测试 completion model，自动识别命名空间并拆开 25 组复合签名；补齐新模块候选；
  Inspector 规范化 selector 键、以完整相关快照生成最小唯一选择器并集中单测代码生成；
  插件测试 83 项，bootstrap 零改动（60782/61440）。
- R36（v1.6.0）：device 全局简写 20 个。
- R37（v1.7.0）：YOLO 检测 + SQLite；_ff/_pc 压缩。
- R38（v1.8.0）：GPS 定位（一次性 fix）+ HMAC；导出压缩。
- R39（v1.9.0）：EasyClick 颜色工具 + location Info.plist 崩溃守卫。
- R40（v1.10.0）：thread/utils 命名空间 + 全局别名；dvf/avf/hsh 压缩 880B。
- R41（v1.11.0）：AI 交接文档 + bootstrap 单一权威源工具化（本手册）。
- R42（v1.12.0）：deleteAllFile 语义修复（递归清空目录 + 返回条目数）、
  vibrateLong/vibrateShort；别名委托/clog/cmpC 压缩 -79B（余 85B）。
- R43（v1.13.0）：EasyClick 选择器 match 别名（idMatch/typeMatch/textMatch/
  nameMatch/labelMatch/valueMatch）；ss/sx 工厂压缩 -264B（余 349B）。
- R44（v1.14.0）：节点关系方法 children/parent/siblings/nextSiblings/
  previousSiblings（nr 工厂）；set_text/clear_text 引用化（余 140B）。
- R45（v1.15.0）：node.allChildren() 递归子孙；dp helper 压缩 -405B +
  修复 boundsInfo 不可重定义 TypeError（余 545B）。
- R46（v1.16.0）：**内置 no-WDA 适配器 AutoBuiltinAdapter**（IOHIDEvent 真实
  触摸注入 + AXUIElement 系统级控件查询 + SpringBoard/BackBoard/LS 应用控制 +
  UIGetScreenImage 截图 + Vision OCR；私有 API 全 dlopen/dlsym 运行时解析）；
  外部 WDA 依赖降级 legacy；模板 App BUILTIN 接线；新文档
  docs/NO_WDA_ARCHITECTURE.md；零 bootstrap 改动（60895/61440，余 545B）。
- R63（v1.31.0）：**Inspector 生命周期与取消链加固**——插件 0.7.0 新增 Cancel/Escape、
  `inspectorActionRefreshDelay`（0...5000ms）；只允许当前未取消操作提交 `lastSnapshot`；
  修复屏幕边界像素越界、同 bounds 父节点误命中和取消迟到响应误报；插件测试 72 项，
  bootstrap 零改动（60782/61440）。
- R62（v1.30.2）：**bootstrap 独立翻译单元编译热修**——只修改权威生成器，令生成的
  `AutoBootstrapScript.m` 导入 `AutoBootstrapScript.h`，修复 Xcode/Swift Package 下
  `NSString` 未声明的编译阻断；继续修复 Xcode 揭出的 SQLite 指针泛型/ARC、媒体函数
  前置声明、TTS `void` 装箱和不存在的 Vision 请求类型；`yolo.detect` 明确为 iOS 15+
  全图分类兼容入口（最多 20 标签，不伪装为真实目标检测）；XCTest 阶段继续修复
  `deleteAllFile(file)`、`auto.node.at`、click arity 和无宿主通知异常；verify 固化约束，
  后续补齐 `auto.screen`/`auto.floatLog` 与 POST multipart 二参兼容；bootstrap
  60782/61440（余 658）。
- R61（v1.30.1）：**Xcode 15.4 ARC 发布热修**——内置 AX 遍历改用显式 CF 桥接与
  Objective-C 合法数组类型，修复远端模拟器编译阻断；修正节点 `type` 大小写不敏感匹配
  的逻辑非优先级错误；verify 新增回归锚点，bootstrap 与 VS Code 插件版本不变。
- R60（v1.30.0）：**VS Code 插件与截图/节点 Inspector 重构**——插件升至 0.6.0；
  `InspectorService` 统一校验并串行 screenshot/nodes/inspectSnapshot/pixel/OCR/findImage，
  避免设备单重任务限制产生 busy 冲突；`InspectorSession` 统一面板生命周期、requestId
  关联和同类任务去重；Webview 几何/选择器拆成纯模型，刷新后按稳定 nodeId 保留选择；
  新增 `inspectorMaxNodes`（1...2000）与相关快照 JSON 导出；删除旧无调用方
  CoalescingRunner；插件测试 64 项，bootstrap 零改动（60526/61440）。
- R59（v1.29.0）：**TrollAutoScript 对标补齐**——sitemap（315 页）模块级盘点后补最后高频缺口：
  string.atrim/isInteger（isIntrger 拼写别名）/string.random、pasteboard.read/write、
  json.encode/decode（失败返回 null）、device.setBacklightLevel/backlightLevel；
  修复初始化顺序 bug（stringsApi 扩展赋值须在全局导出 forEach 之前）；
  bootstrap 60088→60526/61440（余 914B）；测试 87 项，文档 263 函数。
- R58（v1.28.0）：**落实复盘建议**——新增 lastError() API（原生 invokeLastError，
  区分正常 false 与失败 false）；gx 批量别名助手压缩 81 个同名导出，bootstrap
  61391→60088/61440（余 1352B）；修复测试文件历史嵌套 bug；CI 覆盖确认与
  真机验证清单更新；测试 86 项，文档 261 函数。
- R57（v1.27.0）：**全项目复盘审计轮**——修复三个真 bug：execSync 对象/数组返回值
  被旧包装吞掉（直返原生值）、定时器回调异常中断整个 drain 循环（try/catch 隔离）、
  execAsync 完成线程持有 JSContext 不释放（完成后置空）；系统审计确认文件沙盒/zip/
  HTTP 重定向/调试帧解析/sqlite/CF 资源均无问题；bootstrap 61391/61440，测试 84 项。
- R56（v1.26.0）：**位图模型（路径句柄）落地**——image.readBitmap 返回 {path,isBitmap}
  句柄，saveBitmap/bitmapBase64/base64Bitmap/bitmapToImage/getBitmapPixelColor 补齐
  EasyClick 位图 API；句柄在全部 image 操作中自动解包（bp/bh/fb helper + _ff 解包）；
  二轮压缩（guard 后别名引用 + 直接引用转换）-334B；bootstrap 61376/61440（余 64B），
  测试 83 项，文档 260 函数。
- R55（v1.25.0）：**压缩重构 + REST 补全 + OCR 引擎实例**——删除 guard 前 6 处死重别名、
  getJSON 重复定义，get/post/put/delete 统一为 hv 动词工厂（净省 328B）；新增
  http.head/http.patch/http.requestEx（EasyClick/REST 对标）与 ocr.newOcr(defaults?)
  引擎实例（ocrImage/ocrBitmap/ocr 走 screenshotPath 对图片文件 OCR）；修复文档
  生成器 ocrClick 示例混入垃圾行 bug；bootstrap 61283/61440（余 157B），测试 82 项。
- R54（v1.24.0）：**HTTP 安全审计 + REST 便捷别名**——修复 multipart Content-Disposition
  头注入（表单字段名/文件名未校验引号与控制字符，新增 AutoHTTPFieldNameIsValid
  在 3 处上传点统一拦截）；bootstrap 新增 http.put(url, body?, options?) /
  http.delete(url, options?)（+215B，61416/61440，仅剩 24B，下轮先压缩）；
  对标 ascript.cn/docs/ios API 14 大分类，本项目 15 类全覆盖无类目级缺口。
- R53（v1.23.0）：**内置 no-WDA 补齐 xpath 子集**——AutoBuiltinXPathToQuery 把单步
  //Type[@attr='v']/contains/starts-with/ends-with/and 组合/位置下标翻译成原生查询键
  （512 字符上限、未知语法显式报错、capabilities.xpathSubset）；选择器卡片/devdocs/FAQ 同步。
- R52（v1.22.0）：SQLite 加固（查询结果封顶 10 万行；多语句 SQL 显式报错，
  不再静默只跑第一条）；devdocs 补 3 篇指南（图色识别/发布程序/FAQ，28 页，
  对齐 AScript 文档结构）；verify 新锚点；零 bootstrap 改动（61201/61440）。
- R51（v1.21.0）：**修复 screen.cache 端到端断链**（原生从不读 screenshotPath →
  内置/UIKit 适配器 + findColorEx/findNotColor 扫描全部接入，沙箱限定 + 缺失回退）；
  修 parseColor 中缀 0x 误剥、padStart/padEnd 空串死循环；新增全局 waitFor/
  currentPackage/setClip/getClip；bootstrap 压缩 -204B（61201/61440）；测试 81 项。
- R50（v1.20.0）：bootstrap 补 EasyClick 低级触摸原语 touchDown/touchMove/touchUp
  （分指暂存、touchUp() 全抬，61405/61440）；修 findImage 外层循环比较上限 bug；
  devdocs 新增「高级指南」组（多线程/数据库/网络通信）；测试 80 项、文档 258 函数。
- R49（v1.19.0）：内置 no-WDA 适配器补 `findImage`（有界两阶段模板匹配，
  capabilities.findImage=YES）+ App 中文名启动库（60+，launch/terminate/
  appState 通用）；verify 锚点 + 文档/卡片同步。零 bootstrap 改动。
- R48（v1.18.0）：**旧版 AScript 风格开发文档站**（R65 已合并到 `docs/index.html`；22 页：开始/控件检索散文页 +
  15 个 API 分类页，257 函数全渲染，每函数带参数表/返回值/一键复制示例/调试提示；
  顶栏搜索 + 侧栏树 + hash 路由，单文件离线）。顺带修复两个文档渲染 bug：
  `speech`（TTS）与 `base64` 两个分类不在 CATEGORIES 导致卡片从未渲染。
- R47（v1.17.0）：**完全移除外部 WDA**（AutoWDAHTTPAdapter.h/.m、~760 行测试、
  42 个 verify 锚点、模板 WDA 配置与 Info.plist 键、docs/WDA_ADAPTER.md）；
  内置 no-WDA 为唯一跨 App 路线；内置 capabilities 补 appList/appLifecycle/
  systemActions（运行时探测）；模板默认 BUILTIN、设置页内置/UIKit 开关；
  全部文档/教程/扩展措辞同步。零 bootstrap 改动（60895/61440）。

## 10. 新 AI 接手第一步

1. 读本文件 + `AGENTS.md`。
2. `git log --oneline -3`、`git status` 确认基线。
3. 跑一遍 `npm run verify`、`npm test`、`npm run docs`，以及插件目录的 `npm run check` / `npm test` 确认环境正常。
4. 打开 `docs/EASYCLICK_COMPARISON.md` 挑一个“可实现”缺口开始。
5. 按第 7.2 节闭环改，按第 7.4 节发布。
