# 与 AScript（ascript.cn）对比

> 对标日期：2026-08-05。AScript iOS 是运行在 iPhone/iPad 上的 **Python** 自动化引擎，主打
> **免越狱 / 免签名 / 免开发者账号**（企业签名分发 + XCTest 激活 / ESP32 HID）。AutoSDK 是
> **JavaScript** 引擎 + VS Code 调试的自动化 SDK。本文按"引擎形态 / 运行模式 / 模块函数"三层对比。

## 一、引擎与形态

| 对比项 | AScript iOS | AutoSDK |
| --- | --- | --- |
| 脚本语言 | Python（内置 requests / threading / open 等） | JavaScript（JavaScriptCore，ES5+ 常用语法，可 TS 转译） |
| 开发工具 | PyCharm / VS Code / WebIDE 插件 | VS Code 插件（补全、运行、截图、节点检查、调试） |
| App 分发 | 企业签名（信任企业开发者） | 当前：unsigned IPA（免费签名安装，无需巨魔）；详见 [NO_TROLLSTORE.md](NO_TROLLSTORE.md) |
| 控件自动化 | Agent 模式（XCTest 注入，no-WDA）+ WDA 模式 | WDA HTTP 适配器（AutoWDAHTTPAdapter）+ 进程内 UIKit 适配器 |
| 图色/OCR | 通用模块，WDA/HID 双模式可用 | 本地 Vision OCR + 像素/找色/找图（引擎内实现，不依赖 WDA） |
| 系统能力 | Python 系统模块 | device.* / system 能力 + 扩展适配器 |
| 硬件外设 | ESP32 蓝牙 HID（可选） | 无（远期可对标 HID） |

## 二、运行模式对比

| 模式 | AScript | AutoSDK 现状 | 免巨魔改造 |
| --- | --- | --- | --- |
| 免签名安装 | 企业证书（信任即可） | 免费签名安装（AltStore/Sideloadly/SideStore） | 免费签名（AltStore/Sideloadly/SideStore）或企业签名 |
| 控件自动化（免巨魔） | Agent 模式：XCTest 注入激活，iOS 15+，需开发者模式，关机失效 | 依赖独立运行的 WDA（XCTest 激活） | XCTest 激活 WDA（复用 AutoWDAHTTPAdapter） |
| 物理触控（免开发者模式） | HID 模式：ESP32 蓝牙 + 系统录屏 | 无 | 远期：ESP32 固件 + Broadcast Extension |
| 进程内自动化 | 不支持 | AutoUIKitAdapter（宿主 App 内点击/输入/滚动/节点/OCR） | 已支持，免费签名即可用 |

## 三、模块函数对照

### action（触控）

| AScript | AutoSDK | 说明 |
| --- | --- | --- |
| action.click(x, y, duration=20, jitter=0) | click(x, y, jitter?) / clickPoint(x, y) / longClickPoint(x, y, ms) | ✅ 坐标拟人点击（jitter 随机偏移）|
| action.click_random(x1,y1,x2,y2) | clickRandomPoint(x1,y1,x2,y2) / clickRandom(x1,y1,x2,y2) | ✅ 区域随机点击（防检测）|
| action.slide(x1,y1,x2,y2,duration) | swipe(x1,y1,x2,y2,duration) | ✅ 滑动 |
| action.slide_path(points, ...) | slidePath(points, ms) / slide_path | ✅ 连续轨迹：按距离分配每段耗时 |
| action.double_tap | doubleClickPoint(x, y) | ✅ 双击 |
| action.touch_and_slide | touchAndSlide(x1,y1,x2,y2,ms) | ✅ 两点直线滑动 |
| action.input / keys | input(selector, text) / setText | ✅ 输入 |
| action.key_press / key_press_hid | 无 | ❌ 系统按键（WDA 仅支持音量键；HID 模式可全键） |
| action.home | homeScreen() | ✅ 回到主屏（需 WDA systemActions） |
| action.slide_up/down/left/right | swipeUp/swipeDown/swipeLeft/swipeRight | ✅ 方向滑动 |
| action 命名空间（action.click / action.slide_path / ...）| action.*（g.action = auto 全部触摸/输入/滑动能力）| ✅ 全局 action 命名空间，写法与 AScript 一致 |

### screen（图色）

| AScript | AutoSDK | 说明 |
| --- | --- | --- |
| screen.capture() | screenshot() / screen.screenshot() | ✅ 截屏 |
| screen.size / screen.ori | device.getScreenWidth/Height、getOrientation | ✅ |
| screen.image_read / img / image_save | image.*（clip/scale/gray/rotate/pixelAt/saveToAlbum） | ✅ 图像读写处理 |
| screen.image_crop / image_rotate | image.clip / image.rotate | ✅ |
| screen.image_compress | image.compress(src, quality?, dest) | ✅ JPEG 质量压缩 |
| screen.image_to_base64 | base64.encode / image 转 base64 | ✅ 可组合实现 |
| screen.cache / is_cache | screen.cache(on) / screen.isCache() / clearCache() | ✅ 截图缓存：复用同一张截图，findImage/findColor/ocr 全部命中缓存 |
| FindColors.find(...) | screen.findColorEx / findMultiColor | ✅ 多点找色，返回 Point 可直接 click |
| FindImages.find(...) | findImage / screen.findImage | ✅ 找图（支持全分辨率） |
| CompareColors.compare(...) | compareColors / screen.isColors / cmpColor | ✅ 多点比色 |
| CountingColor.count(...) | findColorCount / screen.findColorCount | ✅ 颜色数量统计 |
| ocr（内置） | ocr() / screen.ocr() + ocrClick(text)/ocrText(text) | ✅ 本地 Vision OCR；按文字点击/查找 |
| ocr-baidu / ocr-tomato / opencv / yolo | 无 | ❌ 第三方 OCR/模型（需模型与网络） |

### node（控件）

| AScript | AutoSDK | 说明 |
| --- | --- | --- |
| Selector().label("确定").find() / find_all() | Selector() 链式 + findElement / node.find / node.findAll | ✅ Selector().text/desc/label/type...findOne/find/findAll |
| Selector 约束链（text/type/desc/...） | Selector().text().desc().type().clickable()...（全链式）| ✅ 已实现 |
| Node.click / tap | click(selector) / clickCenter | ✅ |
| Node.tap_hold | node.tap_hold(dur) / node.longClick(dur)（单位秒）| ✅ 长按秒语义（WDA）|
| Node.scroll / pinch | node.scroll(direction, distance) + base.pinch | ✅ 节点滚动 / 双指捏合 |
| Node.set_text / clear_text | input / setText / clearText | ✅ |
| Node.selected | node.selected() / node.attr("selected") | ✅ 选中态查询 |
| Node.at(x, y) 按坐标取控件 | node.at(x, y) / nodeAt(x, y) | ✅ 坐标命中：节点快照按包围盒筛选取最小面积 |

### system / device

| AScript | AutoSDK | 说明 |
| --- | --- | --- |
| app_start / app_stop / app_current / app_list / app_state | app.launch / terminate / current / appList / state | ✅ |
| scheme_start / open_url | app.openURL / openURL | ✅ |
| app_open_setting / app_store | app.openSettings() / openAppSetting() / app.openAppStore(appId) | ✅ 系统设置页 + App Store（itms-apps）|
| lock / unlock / is_locked / keep_screen_on | app.lock / app.unlock + device.isLocked / device.isScreenOn + device.keepScreenOn(on?) / keepScreenOn() | ✅（WDA systemActions + 防自动锁屏）|
| get_uuid / get_ios_version / get_ip_address | uuid() / getOSVersion() / device.getIPAddress() | ✅ 含局域网 IP |
| get_language / get_country / get_timezone / get_uptime | device.getLanguage()/getCountry()/getLocale()/getTimezone()/getUptime() | ✅ NSLocale + NSTimeZone + systemUptime |
| get_network_type / is_wifi | device.getNetworkType() / device.isWifi() | ✅ SCNetworkReachability：wifi/cellular/none |
| set_flashlight | device.setFlashlight(on?) / torch() / flashlight() | ✅ AVCaptureDevice 手电筒，对标 EasyClick setFlashlight() |
| get_device_id / name / model / battery | device.getDeviceId/Name/Model/Battery | ✅ |
| notify（本地通知） | notify(body, title?) | ✅ UNUserNotificationCenter 本地通知 |
| set_clipboard / get_clipboard | setClipboard / getClipboard | ✅ |
| KeyValue 存储 | storages.create(name) | ✅ |
| R.name/root/home/res/img/ui/assets/rel | file.getSandBoxDir / file.* | ✅ 沙盒路径助手等价 |
| reboot / deactivate | 无 | ❌ 需私有 API / 系统级 |
| get_app_scheme | app.getAppScheme(name) / launchByScheme(name) | ✅ 内置 40+ 常用 App URL Scheme 库（中文名/英文名/bundleId），对标 AScript 内置 scheme 库 |
| get_frontmost_app | app.getFrontmostApp() / getFrontmostApp() | ✅ 前台 bundleId |

### media / http / thread / ui

| AScript | AutoSDK | 说明 |
| --- | --- | --- |
| audio_play / audio_stop | audioPlay(path,vol) / audioStop(id)（playMp3 为兼容别名）| ✅ 按 ID 多路播放/单独停止 |
| speak（TTS 朗读） | speak(text, options?) / tts() / speechStop() / speech.* | ✅ AVSpeechSynthesizer，免联网，支持语速/音量/语言 |
| save_pic2photo / save_video2photo | media.saveImage(path或URL) / saveVideo / saveScreenshot | ✅ 支持 http(s) URL 自动下载 |
| requests 库 | http.get/post/getJSON/download + cookies/params/multipart 上传（files/formData） | ✅ 对标 requests 会话能力 |
| threading 库 | execAsync / execSync / setTimeout / setInterval | ✅ |
| WebWindow（HTML UI + JS 双向通信） | webView.*（悬浮 WKWebView + eval + takeMessage/injectBridge + loadHTML） | ✅ JS→脚本消息通道；loadHTML 直接加载本地 HTML 字符串 |
| FloatWindow 悬浮日志窗 | floatLog.show/log/clear/hide/destroy | ✅ 悬浮日志窗：可拖动、保留最近 200 行 |

## 四、AScript 有而 AutoSDK 没有的（缺口清单）

| 优先级 | 能力 | 难度 | 说明 |
| --- | --- | --- | --- |
| P0 | 免巨魔分发（免费签名 + 企业签名） | 低（文档/构建） | 现有 unsigned IPA 可直接被 AltStore/Sideloadly 签名 |
| P0 | XCTest 激活 WDA | 高 | 需 WDA xctest bundle + Windows/Mac 激活工具（go-ios） |
| ~~P1~~ ✅ | notify(body, title?) 本地通知 | 低 | 已实现：UNUserNotificationCenter |
| ~~P1~~ ✅ | image.compress / image.toBase64 | 低 | 已实现：JPEG 质量压缩 + Base64 |
| ~~P1~~ ✅ | findColorCount（颜色计数） | 低 | 已实现：复用像素扫描 |
| ~~P1~~ ✅ | device.getIPAddress() | 低 | 已实现：getifaddrs（en0/en1） |
| ~~P2~~ ✅ | Node.at(x,y)、控件 scroll、selected | 中 | 已实现：node.at + Node 对象（click/scroll/selected/rect）；pinch 已有手势级 base.pinch |
| ~~P2~~ ✅ | floatLog 悬浮日志窗 | 中 | 已实现：UITextView 悬浮窗（floatLog.show/log/clear） |
| ~~P3~~ ✅ | 截图缓存 cache/is_cache | 中 | 已实现：screen.cache/isCache + screenshotPath 源图 |
| P3 | ESP32 HID 硬件模式 | 高 | 固件 + Broadcast Extension |

> 结论：AutoSDK 与 AScript 在"图色/OCR/媒体/HTTP/线程/悬浮 UI"等能力上基本对齐，
> 主要差距在 **分发模式（免巨魔）** 与 **控件自动化激活方式（XCTest）**。
> 免巨魔改造路线见 [NO_TROLLSTORE.md](NO_TROLLSTORE.md)。
