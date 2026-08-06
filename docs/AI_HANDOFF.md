# AutoSDK AI 交接手册（换 AI 前先读这里）

> 用途：任何新接手本项目的 AI，先读本文件 + 根目录 `AGENTS.md`，
> 再读 `docs/EASYCLICK_COMPARISON.md` 的能力差距表。本文档描述架构、
> 现状、工作流、坑和待办，确保换人后能无缝继续迭代。
> 最后更新：Round 41（v1.11.0，2026-08-06）。

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
- 不依赖越狱/巨魔签名：宿主 App 是普通 App，自动化能力受 iOS 沙盒限制，
  跨 App 操作通过可选的 WDA/XCTest 适配器（`AutoWDAHTTPAdapter`）。

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
   ├── WDA 适配器（跨 App，需外部 Runner）AutoWDAHTTPAdapter
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
| `types/autosdk.d.ts` | TypeScript 类型声明（与文档闭环） |
| `tools/verify.mjs` | 一致性断言（bootstrap/原生/d.ts/文档/版本） |
| `tools/bootstrap.test.mjs` | bootstrap 行为测试（Node vm + mock bridge） |
| `tools/generate-api-reference.mjs` | 手写 APIS 列表 → `docs/api-reference.html` |
| `tools/bump-version.mjs` | 版本四件套同步 |
| `tools/auto-sdk.mjs` | build / build-remote（IPA 产物） |
| `tools/bootstrap-history/` | 历史改写脚本（仅参考，勿对新版本执行） |
| `Examples/TemplateApp/` | 宿主模板 App（含 Info.plist、脚本示例） |
| `docs/` | 对标审计（EASYCLICK/ASCRIPT/TROLLAUTOSCRIPT）、协议、发布、性能 |
| `Tests/` | 原生 Xcode 单元测试（AutoEngineTests / AutoHTTPProtocolTests） |

## 4. 当前状态（Round 41 / v1.11.0）

- HEAD：见 `git log -1`；分支 `main`；发布走 tag `vX.Y.Z`。
- bootstrap 解码 **61434 / 61440**（预算 60×1024 UTF-16 码元）。
- 文档 **254 个函数 / 250 个可运行示例 / 13 个分类**；测试 **75 项**。
- 全部命令通过：`npm run verify`、`npm test`、`tsc --noEmit`、`npm run docs`。

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
- node 选择器链补全：`idMatch/nameMatch/typeMatch/labelMatch/valueMatch`、
  `allChildren/nextSiblings/previousSiblings/xpath` 等 EasyClick selector 方法。
- `touchDown/touchMove/touchUp` 手势原语别名（语义需谨慎，见
  `docs/EASYCLICK_COMPARISON.md` 触摸行）。
- `image.readBitmap/bitmapToImage/base64Bitmap/bitmapBase64/saveBitmap`
  位图对象模型（返回语义与 EasyClick 不同，需设计或明确文档标注）。
- `ocr.newOcr/ocrInstance.ocrBitmap/ocrImage` 实例化 OCR 引擎包装。
- `http.requestEx/agentRequestEx` 增强请求（agent 类不可行，requestEx 可考虑）。
- `vibrateLong/vibrateShort` 振动别名（之前因预算被砍，需先压缩）。
- `file.deleteAllFile(dir)` 目录批量删除（JS 层用 list+remove 实现）。

### 不可实现（记录为缺口即可）
- `imeApi.*`（需自建输入法）、`ecNetCard.*`/BLE/OTG/HID（硬件）、
  agent 远程调用、OpenCV 级 `matchTemplate`（当前 CoreGraphics）、
  实时触摸注入（UIKit 限制，需 WDA/私有适配器）、无限纯 JS 循环抢占停止。

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

## 10. 新 AI 接手第一步

1. 读本文件 + `AGENTS.md`。
2. `git log --oneline -3`、`git status` 确认基线。
3. 跑一遍 `npm run verify`、`npm test`、`npm run docs` 确认环境正常。
4. 打开 `docs/EASYCLICK_COMPARISON.md` 挑一个“可实现”缺口开始。
5. 按第 7.2 节闭环改，按第 7.4 节发布。
