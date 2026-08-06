# Changelog

All notable changes to AutoSDK are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

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
