# AutoScript vs AutoSDK

Audit date: 2026-08-05

> AutoScript（用户常简称为 ascript）是一款面向 iOS 用户的 JavaScript
> 自动化脚本工具，以独立 App 形态分发（TrollStore/免越狱通道），自带脚本
> 列表、编辑器、控制台与日志，并提供系统级 API（剪贴板、亮度、音量、
> 振动、打开 URL、主屏幕、锁屏、解锁等）。本文按「最终用户工具 vs 开发者
> SDK」的定位差异来对比，不把同名 API 当作等价能力。

## 核心定位差异

| 维度 | AutoScript | AutoSDK |
| --- | --- | --- |
| 产品形态 | 独立脚本 App，安装即用 | 嵌入宿主 App 的 SDK，需构建自己的 IPA |
| 使用对象 | 最终用户 / 脚本作者 | 开发者 / 集成方 |
| 脚本运行环境 | 工具自己的进程 + 系统级权限通道 | 宿主 App 进程；宿主内 UIKit 直接自动化，跨 App 需 WDA Runner |
| 脚本来源 | App 内脚本列表 / 文件导入 | Bundle 脚本、部署脚本、VS Code 插件发送 |
| 开发与调试 | App 内编辑器 + 控制台日志 | VS Code 插件：补全/片段、截图与节点 Inspector、图像/颜色/OCR 测试、USB/Wi-Fi WebSocket 调试 |
| 分发路径 | 用户直接安装工具 | 开发者通过 GitHub Actions 远程构建 IPA，再装到自己的设备 |
| 上手速度 | 装 App 即可写脚本 | 需要构建（远程构建约 4 分钟）+ TrollStore 安装 + 可选 WDA 配置 |

## API 覆盖对比（已确认面）

| 能力 | AutoScript 风格 | AutoSDK 现状 |
| --- | --- | --- |
| 剪贴板 | getClipboard / setClipboard | ✅ device.getClipboard / setClipboard（1 MiB 上限） |
| 屏幕亮度 | getBrightness / setBrightness | ✅ device.getBrightness / setBrightness（0~1 校验） |
| 系统音量 | getVolume | ✅ device.getVolume（只读，0~1） |
| 振动 | vibrate | ✅ device.vibrate（时长建议值，封顶） |
| 打开 URL | openURL | ✅ auto/app.openURL（http(s)+安全自定义 scheme） |
| 主屏幕/锁屏/解锁 | homeScreen / lock / unlock | ✅ app.homeScreen / lock / unlock（WDA 适配器实现） |
| 当前前台应用 | currentPackage | ✅ app.current() / currentApp()（WDA activeAppInfo） |
| 音量键/屏幕状态 | 音量加/减键、屏幕亮灭查询 | ✅ device.volumeUp / volumeDown / isScreenOn（WDA 按键注入） |
| 触摸/节点 | 跨 App 点击、滑动、节点树 | 宿主内 AutoUIKitAdapter 直接；跨 App 走 WDA 适配器 |
| 图色/OCR | 截图、找色、找图、OCR | ✅ 截图、像素、找色、多色、找图、Vision OCR |
| 文件/存储 | 沙盒文件 CRUD、命名存储 | ✅ 受限根目录 CRUD、命名 JSON 存储 |
| HTTP | 请求/JSON/下载 | ✅ 受控 HTTP + 主机白名单 + 大小上限 |
| 定时器 | setTimeout / setInterval | ✅ 协作式定时器 + 取消 |
| 提示/日志 | toast / toastLog | ✅ 内置 toast 悬浮提示 + toastLog，宿主可覆盖注册 |
| 系统配置开关 | 工具内开关 | allowSystemControl（默认开）等配置项 |
| 相册/媒体 | 保存图片/视频/截图到相册 | ✅ media.saveImage / saveImageBase64 / saveVideo / saveScreenshot，iOS 授权弹窗 + allowMediaLibrary 开关 |
| 内存信息 | 内存占用/可用 | ✅ device.getMemoryInfo（total/free/appUsed 字节） |
| 分辨率适配 | setScreenMetrics / getScreenMetrics | ✅ setScreenMetrics(width,height) + metrics.point(x,y) + device.width/height |
| 多指手势 | 双指缩放/自定义复杂手势 | ✅ auto.gesture / multiGesture / pinch（WDA 适配器真实触摸注入，capabilities.multiTouch）|
| 随机/中心点击 | 无标准封装 | ✅ auto.clickCenter / auto.clickRandom（坐标取整，防检测） |
| 工具函数 | uuid / base64 编码 | ✅ uuid()/uniqueId()、base64.encode/decode（UTF-8 安全） |
| JSON 快捷请求 | httpGetJson | ✅ http.getJSON（parseJson:true） |
| 文件移动/状态 | move / rename / writeLines | ✅ file.move / rename / writeLines；file.stat / getSize / isDir / isFile |

## 缺失但仍需要通道的部分

- 跨 App 的真实触摸：AutoUIKitAdapter 无法注入系统级触摸，必须依赖
  WDA/XCTest 兼容 Runner（项目提供 AutoWDAHTTPAdapter 客户端）。
- 连续屏幕流、断点调试器、模块加载器、纯 JS 死循环的硬中断：均未实现，
  与 EasyClick 对比文档中的缺口一致。
- 系统权限通道：剪贴板/亮度/音量/振动是宿主进程内系统 API，主屏幕/锁屏/
  解锁依赖适配器支持（WDA Runner 提供）。

## 别人能否快速开发自己的自动化脚本？

**能，但取决于使用者的角色。** 三类典型用法：

1. **纯脚本作者（最快路径）**：拿到仓库后，
   - 在 `Examples/TemplateApp/Scripts/` 里放自己的 `.js`（或 VS Code 插件
     发送/部署脚本）；
   - 运行 `node tools/auto-sdk.mjs build-remote` 让 GitHub Actions 构建
     IPA（约 4 分钟）；
   - TrollStore 安装，用 VS Code 插件连上调试、逐行跑、截图查节点。
   - 门槛：需要 GitHub 账号与一次构建配置，比 AutoScript「装 App 即用」多
     一步构建，但脚本写法与 AutoScript 风格高度一致。

2. **宿主 App 开发者**：把 AutoSDK 通过 SPM/CocoaPods 集成进自己的 App，
   注册一个 `AutoAutomationAdapter`，即可让脚本访问宿主 UI、文件、存储、
   HTTP 与系统能力，并把整套脚本能力作为自己产品的功能。

3. **需要跨 App 自动化**：在设备上运行 WDA 兼容 Runner，把
   `AutoWDAHTTPAdapter` 配置进宿主 App，即可获得跨 App 点击、节点、
   主屏幕/锁屏/解锁等能力。

**结论**：AutoSDK 面向的是「想要自己产品的脚本能力」的开发者；AutoScript
面向的是「直接使用现成工具」的最终用户。若你的朋友只想写脚本而不想碰
构建，AutoScript 更省事；若他们想把自己的自动化做成可分发 App 或嵌入
现有 App，AutoSDK 是更合适的起点。快速上手的完整步骤见
[`QUICK_START.md`](QUICK_START.md)。
