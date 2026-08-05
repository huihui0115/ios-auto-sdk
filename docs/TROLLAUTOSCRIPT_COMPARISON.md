# AutoSDK vs TrollAutoScript 对标

> 数据来源：TrollAutoScript 官方文档站（docs.trollautoscript.com，抓取日期 2026-08-05）。
> TrollAutoScript 是一个运行在 TrollStore 上的独立自动化工具，使用 Lua 5.4，
> 需要越狱通道（TrollStore）才能获得系统级权限；AutoSDK 是嵌入宿主 App 的
> Objective-C SDK，跨 App 自动化走 WDA Runner。两者定位不同，下表按
> 「能力模块」逐项对比 AutoSDK 现状。

图例：✅ 已有等价能力 ｜ 🟡 部分等价 ｜ ❌ 暂无（多数需私有 API / TrollStore 系统权限）

## 模块级对比

| TrollAutoScript 模块 | 官方函数 | AutoSDK 现状 |
| --- | --- | --- |
| 清理模块 clear.* | allPhotos / allKeychain / keychain / pasteboard / APP数据 / idfav / safariCookies | ✅ clear.allPhotos → `media.deleteAllPhotos()/deleteAllVideos()/deleteAllMedia()`（返回删除数量）；✅ pasteboard → `setClipboard("")`；❌ keychain/APP 数据/idfav/safariCookies 需私有 API 与系统权限 |
| 扩展 string 库 | trim/ltrim/rtrim/split/chars/toHex/fromHex/isUpper/isLower/isNumber/isIntrger/isLetter/isChinese/isEmail/isLink/md5/sha1/sha256/sha512/base64Encode/base64Decode/aes128Encrypt/aes128Decrypt/toPinYin/fromUnicode/stripUtf8Bom | ✅ `strings.*` 全部对齐（含 aes128Encrypt/aes128Decrypt、toPinYin 系统级拼音、fromUnicode、stripUtf8Bom）+ 全局简写 `trim()`/`isEmail()`/`sha256()`/`toPinYin()` 等；❌ fromGbk 暂无（GBK 表需私有/三方库） |
| 文件模块 file.* | list/reads/writes/addText/existe/size/md5/getLines/getLineText/lineCount/insertLineText/resetLineText | ✅ `file.list/readText/writeText/appendText/exists/getSize/md5/readLines`；✅ 本轮补齐 `lineCount/getLineText/insertLineText/resetLineText` 与全局简写；另有 copy/move/rename/zip/unzip/readExcel 等增强 |
| 系统模块 sys.* | toast/msleep/mtime/osVersion/palyAudio/usedMemory/availableMemory/processUsedMemory/version/alert/setFloatBallPoint | ✅ toast/sleep/time()/getOSVersion/playMp3/getMemoryInfo/capabilities/alert()；✅ `setFloatBallPoint(x,y)` → `floatBall.show("",x,y)`（悬浮球） |
| 线程模块 thread.* | create/timer/Cancel/state | ✅ `execAsync/execSync`（join/isFinished/cancel）、setTimeout/setInterval；❌ 线程状态查询 |
| 设备模块 device.*（38 项） | 亮度/音量/振动/方向/电池/内存/机型 等 | ✅ getBrightness/setBrightness/getVolume/vibrate/getOrientation/getBattery/getMemoryInfo/getModel/getOSVersion 等；❌ 飞行模式/闪光灯/WiFi MAC/蓝牙 MAC/蜂窝开关 等需私有 API |
| 屏幕模块 screen.* | getColor/getColorRGB/findImage/findColors/isColors/visionOcr/paddleOcr/TomatoOCR/loadImageFile/keep/unkeep | ✅ getPixelColor/findImage/findMultiColor/cmpColor/compareColors/OCR（Vision）；❌ paddleOcr/TomatoOCR（需模型）、loadImageFile/keep/unkeep |
| 图片对象模块 | clip/scale/gray/binarization/rotate/findImage/findColors/isColors/pngData/show/turnLeft/turnRight | ✅ `image.clip/scale/gray/binaryzation/rotate/pixelAt/findImage/findColor`；🟡 turnLeft/turnRight 可用 `image.rotate(90/270)`；❌ show（悬浮预览图片）、cvFindImage（OpenCV）、paddleOcr |
| 模拟触摸模块 | tap/down/move/up/msleep/press/radius/setpDelay | ✅ clickPoint/gesture（down/move/up/长按/滑动）/pinch/swipe；❌ 压力与半径定制（WDA 能力限制） |
| 模拟按键模块 key.* | press/down/up/sendText/inputText/clear | 🟡 `input(selector,text)/setText` 通过辅助功能输入；❌ 系统级硬件按键事件（仅 WDA 音量键） |
| 节点模块 node.* | byText/byClassName/byPath/GetText/GetFrame/GetPoint/GetSize/GetCenterPoint/GetSubNode/GetSuperNode/keep/unkeep/GetAlpha/GetHidden | ✅ findElement/findElements/exists/waitFor/getText/getBounds/getChildren/getParent/getChild/getSiblings/childCount/scrollIntoView；✅ 本轮补齐 `node.keep/unkeep`（JS 保持表）+ 全局 `keepNode/unkeepNode`；❌ GetAlpha/GetHidden、GetSuperClassName、byMatch 复杂匹配 |
| 应用模块 app.* | run/close/openUrl/version/frontBid/isRuning/isInstalled/installIpa/uninstall/dataPath/iconData/groupInfo/localizedName | ✅ launch/activate/terminate/state/current/openURL/getAppVersion/appList/homeScreen/lock/unlock；❌ installIpa/uninstall/isInstalled/dataPath/iconData/groupInfo 需私有 API |
| 剪贴板 pasteboard.* | read/write | ✅ device.getClipboard/setClipboard（1 MiB 上限） |
| HTTP http.* | get/post/download | ✅ http.get/post/getJSON/postJSON/downloadFile（白名单+大小上限） |
| JSON json.* | encode/decode | ✅ 原生 JSON.stringify/parse |
| 其他 | log/os.exit/restartScript | ✅ console.*/logd..loge；✅ `exit()` 停止脚本；✅ `restartScript()` 停止后重跑当前脚本 |
| webView 模块 | init/show/hidden/eval/release | ✅ `webView.init/show/hidden/eval/release`（悬浮 WKWebView，可指定位置尺寸） |
| 屏幕绘制 screenDraw | init/setBorderWidth/setBorderColor/setTitle/show/move/hide | ✅ `screenDraw.*` 全部对齐（悬浮框绘制，边框/标题/移动/隐藏，触摸穿透） |
| plist 模块 | read/write | ✅ `file.readPlist/writePlist` + 全局 `plist.read/plist.write`（XML plist，NSData→base64、NSDate→毫秒） |
| coreML / paddleYOLO | 模型编译/预测/目标检测 | ❌ 暂无（需模型文件与推理引擎） |
| VPN 模块 vpn.* | create/select/connect/deleteAll | ❌ 暂无（需系统 VPN 私有配置权限） |
| mobile 模块 | saveVideoFileToAlbum/zip 压缩解压/重启/关机/短信/通讯录增删 | ✅ saveVideoToAlbum/zip/unzip；❌ 重启/关机/短信/通讯录需私有 API |

## 结论

- **已对齐的高频能力**：相册增删、字符串工具、文件行操作、哈希编码、
  弹窗/退出、线程、HTTP、剪贴板、图色与 OCR、节点查询、应用控制。
- **私有 API 类缺口**（TrollStore/TrollAutoScript 依赖系统权限，SDK 公共 API
  无法安全实现）：清 keychain、清 APP 数据、IDFA、飞行模式、闪光灯、
  MAC 地址、VPN、短信、通讯录、安装/卸载 IPA、系统级按键与触摸压力。
  若宿主 App 以 TrollStore 方式签名且宿主提供这些 native 能力，可通过
  `registerNativeMethod:` 暴露给脚本。
- **可后续用公共 API 补齐**：fromGbk（GBK 码表）、paddleOcr/TomatoOCR（需模型）、coreML/paddleYOLO（需推理引擎）。
