# AutoSDK AI 交接手册（换 AI 前先读这里）

> 用途：任何新接手本项目的 AI，先读本文件 + 根目录 `AGENTS.md`，
> 再读 `docs/EASYCLICK_COMPARISON.md` 的能力差距表。本文档描述架构、
> 现状、工作流、坑和待办，确保换人后能无缝继续迭代。
> 最后更新：Round 58（v1.28.0，2026-08-07）。

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
| `tools/generate-api-reference.mjs` | 手写 APIS 列表 → `docs/api-reference.html`（导出 APIS/CATEGORIES） |
| `tools/generate-devdocs.mjs` | AScript 风格文档站 → `docs/devdocs/index.html`（侧栏树+散文页+函数页+搜索+复制+调试提示） |
| `tools/bump-version.mjs` | 版本四件套同步 |
| `tools/auto-sdk.mjs` | build / build-remote（IPA 产物） |
| `tools/bootstrap-history/` | 历史改写脚本（仅参考，勿对新版本执行） |
| `Examples/TemplateApp/` | 宿主模板 App（含 Info.plist、脚本示例） |
| `docs/` | 对标审计（EASYCLICK/ASCRIPT/TROLLAUTOSCRIPT）、协议、发布、性能 |
| `Tests/` | 原生 Xcode 单元测试（AutoEngineTests / AutoHTTPProtocolTests） |

## 4. 当前状态（Round 47 / v1.17.0）

- HEAD：见 `git log -1`；分支 `main`；发布走 tag `vX.Y.Z`。
- bootstrap 解码 **60895 / 61440**（预算 60×1024 UTF-16 码元）。
- 文档 **257 个函数 / 257 个可运行示例 / 13 个分类**；测试 **79 项**。
- 全部命令通过：`npm run verify`、`npm test`、`tsc --noEmit`、`npm run docs`。
- **Round 46 战略转向**：放弃“必须外部 WDA”路线，新增内置 no-WDA 适配器
  `AutoBuiltinAdapter`（系统级触摸注入/控件查询/应用控制）。
- **Round 47 清场**：`AutoWDAHTTPAdapter` 及其全部测试/配置/verify 锚点/文档
  已完全移除；内置 no-WDA 是唯一跨 App 路线。模板 App 默认 BUILTIN，
  设置页为“内置 no-WDA / UIKit”开关；内置 capabilities 新增
  `appList`/`appLifecycle`/`systemActions` 键（运行时探测）。架构与签名要求见
  `docs/NO_WDA_ARCHITECTURE.md`。

已实现能力（详见 `docs/api-reference.html` 每张卡的对标标注）：
触摸/节点（含 WDA selector）、图色（findColor/findColorEx/findMultiColor/
findNotColor/findImage/cmpColor/isColors）、像素（screen.getColor 系列）、
颜色工具（parseColor/int2Hex/hex2Int/rgb/argb）、OCR（Apple Vision +
Baidu）、YOLO（Vision 离线）、文件（沙盒 CRUD/行操作/Excel/ZIP/plist）、
存储（typed store）、SQLite、HTTP（get/post/JSON/multipart/download +
host allowlist）、WebSocket 客户端、线程（execAsync/execSync + thread
命名空间）、定时器、定位（CLLocationManager 一次性）、相册（保存/清空 +
权限）、媒体（mp3）、剪贴板/亮度/音量/振动/手电、悬浮窗（floatLog/
floatBall/screenDraw）、webView 悬浮网页、AES/HMAC/MD5/SHA、拼音、
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

### 不可实现（记录为缺口即可）
- `imeApi.*`（需自建输入法）、`ecNetCard.*`/BLE/OTG/HID（硬件）、
  agent 远程调用、OpenCV 级 `matchTemplate`（当前 CoreGraphics）、
  无限纯 JS 循环抢占停止。（实时触摸注入已由 Round 46 内置适配器解决。）

### Round 46 内置适配器真机验证待办（下轮优先）
- 真机验证 IOHIDEvent 触摸注入（需允许私有 API 的签名：TrollStore/开发者证书；
  App Store 构建会被审核拒绝，capabilities 会如实降级报告）。
- 真机验证系统级 AX 控件查询（跨 App 毫秒级检索）与 SpringBoard 应用控制
  （launch/terminate/前台/锁屏/设置页解锁）。
- `findImage` 已于 Round 49 实现（有界两阶段模板匹配）；
  xpath 子集已于 Round 53 实现（单步 //Type[@attr='v'] 等翻译为原生查询键）；predicate 仍返回清晰错误。
- 验证模板 App `AutoSDKAdapter=BUILTIN` 配置接线与 capabilities 降级路径。
- 注：每次 push main/tag 都会触发 GitHub Actions（macos-14：verify+npm test+
  Xcode 模拟器测试+IPA 打包+Release），原生代码的编译与模拟器行为已被 CI 覆盖；
  真机专属项仅剩私有 API 行为（IOHIDEvent/AX/SpringBoard）。
- R53-R58 新增待真机抽查：xpath 子集实机控件命中、ocr.newOcr 对文件 OCR、
  位图句柄过 image 操作链、execSync 对象返回值、lastError() 错误读取。

### 工程质量待办
- 原生 `Tests/` 目前只有 AutoEngineTests / AutoHTTPProtocolTests，可在
  macOS/Xcode 环境扩充；Windows 环境以 `npm test`（Node 端）为主。
- `docs/PERFORMANCE.md` 记录了图色/OCR 预算，新增原生能力时保持有界。
- 每轮更新 `docs/EASYCLICK_COMPARISON.md` 的矩阵与计数，避免文档漂移。

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
  原生能力以 verify 锚点断言 + Xcode 实机为准。

## 9. 历轮主线（git log 可查）

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
- R48（v1.18.0）：**AScript 风格开发文档站** `docs/devdocs/index.html`（22 页：开始/控件检索散文页 +
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
3. 跑一遍 `npm run verify`、`npm test`、`npm run docs` 确认环境正常。
4. 打开 `docs/EASYCLICK_COMPARISON.md` 挑一个“可实现”缺口开始。
5. 按第 7.2 节闭环改，按第 7.4 节发布。
