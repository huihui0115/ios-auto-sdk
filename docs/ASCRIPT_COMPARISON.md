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
| action.click(x, y, duration=20, jitter=0) | clickPoint(x, y) / longClickPoint(x, y, ms) | ✅ 坐标点击/长按 |
| action.click_random(x1,y1,x2,y2) | clickRandom(selector) / clickPoint(随机点) | ✅ 区域随机点击 |
| action.slide(x1,y1,x2,y2,duration) | swipe(x1,y1,x2,y2,duration) | ✅ 滑动 |
| action.slide_path(points, ...) | gesture(actions) | ✅ 连续轨迹（W3C 手势） |
| action.double_tap | doubleClickPoint(x, y) | ✅ 双击 |
| action.touch_and_slide | gesture（down→move→up） | ✅ 可用手势组合实现 |
| action.input / keys | input(selector, text) / setText | ✅ 输入 |
| action.key_press / key_press_hid | 无 | ❌ 系统按键（WDA 仅支持音量键；HID 模式可全键） |
| action.home | homeScreen() | ✅ 回到主屏（需 WDA systemActions） |
| action.slide_up/down/left/right | swipeUp/swipeDown/swipeLeft/swipeRight | ✅ 方向滑动 |

### screen（图色）

| AScript | AutoSDK | 说明 |
| --- | --- | --- |
| screen.capture() | screenshot() / screen.screenshot() | ✅ 截屏 |
| screen.size / screen.ori | device.getScreenWidth/Height、getOrientation | ✅ |
| screen.image_read / img / image_save | image.*（clip/scale/gray/rotate/pixelAt/saveToAlbum） | ✅ 图像读写处理 |
| screen.image_crop / image_rotate | image.clip / image.rotate | ✅ |
| screen.image_compress | 无 | 🟡 建议新增 image.compress（质量/尺寸压缩） |
| screen.image_to_base64 | base64.encode / image 转 base64 | ✅ 可组合实现 |
| screen.cache / is_cache | 无 | 🟡 截图缓存（性能优化） |
| FindColors.find(...) | screen.findColorEx / findMultiColor | ✅ 多点找色，返回 Point 可直接 click |
| FindImages.find(...) | findImage / screen.findImage | ✅ 找图（支持全分辨率） |
| CompareColors.compare(...) | compareColors / screen.isColors / cmpColor | ✅ 多点比色 |
| CountingColor.count(...) | 无 | 🟡 建议新增 findColorCount（颜色数量统计） |
| ocr（内置） | ocr() / screen.ocr() | ✅ 本地 Vision OCR |
| ocr-baidu / ocr-tomato / opencv / yolo | 无 | ❌ 第三方 OCR/模型（需模型与网络） |

### node（控件）

| AScript | AutoSDK | 说明 |
| --- | --- | --- |
| Selector().label("确定").find() / find_all() | findElement / findElements（id/label/type/text 选择器） | ✅ 控件查找 |
| Selector 约束链（text/type/desc/...） | 组合选择器 + getChild/getSiblings 遍历 | ✅ |
| Node.click / tap | click(selector) / clickCenter | ✅ |
| Node.tap_hold | longClick / longClickPoint | ✅ |
| Node.scroll / pinch | 无 | 🟡 控件内滚动/捏合（WDA 手势可组合） |
| Node.set_text / clear_text | input / setText / clearText | ✅ |
| Node.selected | 无 | 🟡 选中态查询（可通过 getAttribute 扩展） |
| Node.at(x, y) 按坐标取控件 | 无 | 🟡 建议新增（WDA element 按坐标定位） |

### system / device

| AScript | AutoSDK | 说明 |
| --- | --- | --- |
| app_start / app_stop / app_current / app_list / app_state | app.launch / terminate / current / appList / state | ✅ |
| scheme_start / open_url | app.openURL / openURL | ✅ |
| lock / unlock / is_locked | app.lock / unlock | ✅（WDA systemActions） |
| get_uuid / get_ios_version / get_ip_address | uuid() / getOSVersion() / 无 | 🟡 getIPAddress 建议新增 |
| get_device_id / name / model / battery | device.getDeviceId/Name/Model/Battery | ✅ |
| notify（本地通知） | 无 | 🟡 notify(title, body) 建议新增 |
| set_clipboard / get_clipboard | setClipboard / getClipboard | ✅ |
| KeyValue 存储 | storages.create(name) | ✅ |
| R.name/root/home/res/img/ui/assets/rel | file.getSandBoxDir / file.* | ✅ 沙盒路径助手等价 |
| reboot / deactivate / get_app_scheme | 无 | ❌ 需私有 API / 系统级 |

### media / http / thread / ui

| AScript | AutoSDK | 说明 |
| --- | --- | --- |
| audio_play / audio_stop | playMp3 / stopMp3 | ✅ |
| save_pic2photo / save_video2photo | media.saveImage / saveVideo / saveScreenshot | ✅ |
| requests 库 | http.get/post/getJSON/download | ✅ |
| threading 库 | execAsync / execSync / setTimeout / setInterval | ✅ |
| WebWindow（HTML UI + JS 双向通信） | webView.*（悬浮 WKWebView + eval） | ✅ |
| FloatWindow 悬浮日志窗 | console + 调试服务器；无悬浮日志窗 | 🟡 建议新增 floatLog 悬浮窗 |

## 四、AScript 有而 AutoSDK 没有的（缺口清单）

| 优先级 | 能力 | 难度 | 说明 |
| --- | --- | --- | --- |
| P0 | 免巨魔分发（免费签名 + 企业签名） | 低（文档/构建） | 现有 unsigned IPA 可直接被 AltStore/Sideloadly 签名 |
| P0 | XCTest 激活 WDA | 高 | 需 WDA xctest bundle + Windows/Mac 激活工具（go-ios） |
| P1 | notify(title, body) 本地通知 | 低 | UNUserNotificationCenter，公共 API |
| P1 | image.compress / image.toBase64 | 低 | 引擎内已有图像管线 |
| P1 | findColorCount（颜色计数） | 低 | 复用像素扫描 |
| P1 | device.getIPAddress() | 低 | 公共 API（getifaddrs） |
| P2 | Node.at(x,y)、控件 scroll/pinch、selected | 中 | WDA 元素能力扩展 |
| P2 | floatLog 悬浮日志窗 | 中 | WKWebView/悬浮视图封装 |
| P3 | 截图缓存 cache/is_cache | 中 | 引擎内状态 |
| P3 | ESP32 HID 硬件模式 | 高 | 固件 + Broadcast Extension |

> 结论：AutoSDK 与 AScript 在"图色/OCR/媒体/HTTP/线程/悬浮 UI"等能力上基本对齐，
> 主要差距在 **分发模式（免巨魔）** 与 **控件自动化激活方式（XCTest）**。
> 免巨魔改造路线见 [NO_TROLLSTORE.md](NO_TROLLSTORE.md)。
