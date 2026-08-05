# AutoSDK

这是一个面向第三方 iOS App 的客户端自动化 SDK MVP。它不是最终 App，也不包含后台设备管理或结果回传服务。
> ⬇️ 预编译下载：GitHub [Releases](https://github.com/huihui0115/ios-auto-sdk/releases) 提供模板 App 的 IPA（AutoSDKTemplate.ipa：TrollStore 直接装，也可用 AltStore/Sideloadly 免费签名安装，免巨魔）与 VS Code 插件（autosdk-vscode-*.vsix），不想自己构建可直接下载。
> 🌐 在线文档：<https://huihui0115.github.io/ios-auto-sdk/>（docs/ 自动部署到 GitHub Pages）。

## 当前能力

- Objective-C 友好的 `AutoEngine` 单例入口
- JavaScriptCore 执行本地脚本、Bundle 脚本和远程 URL
- 全局 `auto` API：点击、滑动、输入、稳定节点查询、图色、截图、OCR、沙盒文件、命名存储、设备信息和受控 HTTP
- 系统能力（`allowSystemControl` 可开关）：剪贴板读写、屏幕亮度、系统音量、振动、打开 URL；WDA Runner 额外支持主屏幕/锁屏/解锁、音量键、屏幕状态
- 相册（`allowMediaLibrary` 可开关）：保存沙盒图片、视频、Base64 图片或截图到 iOS“照片”，并支持 `media.deleteAllPhotos/deleteAllVideos/deleteAllMedia` 清空相册（返回删除数量）
- plist 读写：`file.readPlist/writePlist` 与全局 `plist.read/plist.write`（XML plist）
- 悬浮 webView：`webView.init/show/hidden/eval/release`（WKWebView）
- 加密与字符串：`strings.aes128Encrypt/aes128Decrypt`、`sha256/sha512` 及 20+ 字符串工具
- Native 方法注册：`registerNativeMethod:handler:`
- 取消、超时、JS 异常和适配器错误统一转换为 `NSError`，成功结果包含 `value` 和 `logs`
- 脚本可取消：`stopScript`/`scriptTimeout` 在桥接调用、`auto.sleep` 和定时器回调处协作式中断脚本
- CocoaPods 和 Swift Package Manager 接入骨架
- 基于公共 API 的 `AutoUIKitAdapter`，可直接自动化宿主 App 自己的 UIKit 视图

> 📖 中文图文教程（离线网页版，双击即开）：[docs/guide/index.html](docs/guide/index.html)（安装 → 连接 → 第一行代码 → 调试）。
> 🆚 对标文档：[`docs/EASYCLICK_COMPARISON.md`](docs/EASYCLICK_COMPARISON.md)（EasyClick）、[`docs/TROLLAUTOSCRIPT_COMPARISON.md`](docs/TROLLAUTOSCRIPT_COMPARISON.md)（TrollAutoScript）、[`docs/ASCRIPT_COMPARISON.md`](docs/ASCRIPT_COMPARISON.md)（AScript）、[`docs/AUTOSCRIPT_COMPARISON.md`](docs/AUTOSCRIPT_COMPARISON.md)（AutoScript）。
> 🚀 免巨魔路线（对标 AScript/kuaijs）：[`docs/NO_TROLLSTORE.md`](docs/NO_TROLLSTORE.md)——免费签名安装 / XCTest 激活 WDA / HID 模式。
> 🚀 想快速上手？先看 [`docs/QUICK_START.md`](docs/QUICK_START.md)（第三方 10 分钟跑通
> 「写脚本 → 构建 IPA → 安装 → 调试」）。与 AutoScript 的定位/能力对比见
> [`docs/AUTOSCRIPT_COMPARISON.md`](docs/AUTOSCRIPT_COMPARISON.md)。

## 集成

### Swift Package Manager

在 Xcode 中添加本仓库 URL，选择 `AutoSDK` 产品。SDK 需要 iOS 14+，并链接
`JavaScriptCore`、`UIKit`、`Photos` 等系统框架。

### CocoaPods

```ruby
pod 'AutoSDK', :path => '../AutoSDK'
```

### 配置自动化适配器

宿主 App 必须实现 `AutoAutomationAdapter`，把 `click`、控件查找、截图等操作转发到自己的 XCTest/WDA 层：

```objc
AutoEngine *engine = AutoEngine.sharedEngine;
[engine configureWithConfig:@{ @"scriptTimeout": @300,
                               @"allowFileAccess": @YES,
                               @"allowFileWrite": @YES }];
[engine setAutomationAdapter:[AutoUIKitAdapter new]];
[engine runScript:[[NSBundle mainBundle] pathForResource:@"hello" ofType:@"js"]
        completion:^(NSDictionary *result, NSError *error) {
    NSLog(@"result=%@ error=%@", result, error);
}];
```

常用配置项：`scriptTimeout`（秒，默认 300）、`maxScriptBytes`（默认 5 MB、硬上限 64 MB）、`maxLogEntries`、`maxLogMessageLength`、`maxLogBytes`、`allowRemoteScripts`（默认 `NO`）、`allowedRemoteScriptHosts`、`remoteScriptTimeout`、`allowNetwork`（默认 `NO`）、`allowedNetworkHosts`、`maxHTTPRequestBytes`、`maxHTTPResponseBytes`、`allowFileAccess`、`allowFileWrite`、`fileRoot`、`maxFileReadBytes`、`maxFileWriteBytes`、`maxFileCopyBytes`、`maxFileListItems`、`maxFileOperationItems`、`maxFileLineCount`、`allowStorage`、`maxStorageBytes`、`maxStorageEntries`、`allowMediaLibrary`、`maxMediaBytes`、`maxMediaImageBytes`、`debugLogging` 和 `interruptibleScripts`（为兼容保留，脚本中断为协作式：桥接调用、`auto.sleep` 和定时器回调处生效；纯 JS 无限循环可能持续占用 CPU）。文件与存储默认只能访问 App 沙盒中的 AutoSDK 专用范围。宿主 App 如需相册写入，必须在自身 `Info.plist` 声明 `NSPhotoLibraryAddUsageDescription`。

### 本地调试服务器

开发模式下可配置 `debugServerEnabled: @YES`、`debugPort: @9001` 和一个随机的 `debugToken`。服务器默认只绑定回环接口；设置 `debugAllowWiFi: @YES` 后可从同一可信 Wi-Fi 网络直接连接。Wi-Fi 模式要求至少 16 个字符的 token，并且宿主 App 必须声明 `NSLocalNetworkUsageDescription`。WebSocket 每条命令都必须携带 token：

```json
{"id":"1","token":"...","type":"run","script":"console.log('hello')"}
```

支持 `ping`、`deviceInfo`、`capabilities`、`screenshot`、`nodes`、`run`/`runScript` 和 `stop`。调试服务器默认关闭，建议只在 Debug 或企业签名构建中开启。

完整协议见 [`docs/DEBUG_PROTOCOL.md`](docs/DEBUG_PROTOCOL.md)，PC 端可使用 `npm run debug -- --token <token>` 连接。

没有设置适配器时，SDK 使用 `AutoUnavailableAdapter` 并返回明确错误，不会假装执行 UI 操作。

`AutoUIKitAdapter` 支持 `id`、`label`、`type`、`value` 及组合选择器，可完成宿主 App 内点击、输入、滚动、节点查询、截图和 Vision OCR。需要跨 App 时可使用 [`AutoWDAHTTPAdapter`](Sources/AutoSDK/include/AutoWDAHTTPAdapter.h)，连接设备上单独运行的 WDA-compatible Runner；它不把 XCTest 私有代码伪装成普通 SDK，也不保证 TrollStore 能在每个 iOS 版本启动 Runner。

## 脚本 API
> 📚 交互式 API 速查（分类导航 + 搜索 + 一键复制可运行示例）：[docs/api-reference.html](docs/api-reference.html)，浏览器双击即开。

```javascript
auto.click({label: "登录", type: "Button"});
auto.longClick({id: "row"}, 0.8);
auto.swipe(100, 600, 100, 100, 0.3);
auto.input({id: "email"}, "dev@example.com");
auto.setText({id: "email"}, "dev@example.com");
auto.sleep(500);
const text = auto.getText({label: "标题"});
const pngBase64 = auto.screenshot();
const match = auto.findImage("button.png", {threshold: 0.9});
const pixel = auto.findColor("#ff3b30", {x: 0, y: 0, width: 320, height: 200}, {tolerance: 12});
const words = auto.ocr({x: 0, y: 0, width: 320, height: 200});
const node = auto.findElement({id: "login-button"});
const nodes = auto.findElements({labelMatch: "登.*", visible: true, maxResults: 20});
const exists = auto.exists({label: "登录"});
auto.waitFor({id: "welcome-title"}, 5000);
const bounds = auto.getBounds(node);
const children = auto.getChildren({id: "form"});
const parent = auto.getParent(node);
const siblings = auto.getSiblings(node);
auto.scrollIntoView({id: "submit"});
const colorsMatch = auto.compareColors([{x: 10, y: 20, color: "#ff3b30"}]);
const response = auto.http("https://example.com/api", {method: "GET", timeout: 10000});
file.writeFile("reports/latest.txt", response.body);
const settings = storages.create("settings");
settings.putBoolean("enabled", true);
setTimeout(() => console.log("timer fired"), 100);
console.log(device.getDeviceInfo(), auto.capabilities());
auto.toast("自定义方法由 Native 注册");
```

`setTimeout`/`setInterval` 在脚本主代码返回后继续执行，`runScript` 的完成回调会等定时器队列排空后才触发；`setInterval` 会持续运行，需调用 `stopScript`（或等待 `scriptTimeout` 超时）才会停止。`scriptTimeout` 是包含定时器回调在内的总执行预算。
新增 EasyClick 风格的坐标适配与常用工具：`setScreenMetrics(width, height)` 按设计稿设置分辨率基准，配合 `getScreenMetrics()`、`metrics.point(x, y)` 适配多机型；另有 `uuid()`、`base64.encode/decode`、`http.getJSON`、`auto.clickCenter/clickRandom`、`auto.getChild/getSiblings` 等封装。全部 160+ 函数见上方交互式速查（206 个函数、12 个分类，每卡带 EasyClick/AutoJS 对标与可复制示例）。

`findImage` 使用适配器实现的模板相似度匹配，`findColor` 使用 RGBA 容差扫描；`AutoUIKitAdapter` 的 `ocr` 使用系统 Vision 框架离线执行。`AutoWDAHTTPAdapter` 会把 WDA 截图拉回 SDK 进程后执行图色和 Vision OCR，不需要 OpenCV，但仍然需要单独可用的 WDA Runner。

节点对象是带稳定弱关联句柄的可序列化描述，不会强持有 UIKit 对象；可以把 `findElement` 返回值再次传给 `getText`、`getBounds`、`getParent` 等 API。视图销毁后句柄自动失效。HTTP 默认关闭，需显式配置 `allowNetwork: @YES`，请求仅允许 `http` 和 `https`。

节点 API 的字段和返回结构见 [`docs/NODE_OPERATIONS.md`](docs/NODE_OPERATIONS.md)，HTTP 请求见 [`docs/HTTP_API.md`](docs/HTTP_API.md)。
文件、存储和设备模块见 [`docs/FILE_STORAGE_DEVICE_API.md`](docs/FILE_STORAGE_DEVICE_API.md)。与 EasyClick iOS USB/脱机版官方文档的逐类差距见 [`docs/EASYCLICK_COMPARISON.md`](docs/EASYCLICK_COMPARISON.md)，与 AutoScript 的定位与能力对比见 [`docs/AUTOSCRIPT_COMPARISON.md`](docs/AUTOSCRIPT_COMPARISON.md)，第三方快速上手见 [`docs/QUICK_START.md`](docs/QUICK_START.md)。脚本执行的整体语义（输入分类、执行生命周期、超时与中断、定时器排空、错误码）见 [`docs/SCRIPT_EXECUTION.md`](docs/SCRIPT_EXECUTION.md)。

默认禁止远程脚本。只有显式配置 `@{"allowRemoteScripts": @YES}` 后，`http://` 或 `https://` URL 才会被加载；生产环境建议只允许 HTTPS，并在适配器或宿主层做签名校验。

脚本中的 `console.log`、`console.warn` 和 `console.error` 会出现在成功结果的 `logs` 数组中，元素格式为 `{"level": "log", "message": "..."}`。
脚本失败时，同样的日志会放入 `NSError.userInfo[@"logs"]`。

## 重要限制

普通 App 进程不能稳定调用 Apple 未公开的 XCTest/WDA 私有接口。生产集成应将
真实 WDA/XCTest 代码放在宿主自己的开发/企业签名目标中，并实现适配器；不要把
私有符号、未授权的 USB 隧道或后台设备管理默认打进 App Store 构建。

Windows 环境无法编译 iOS Framework。请在 macOS + Xcode 14+ 上执行：

```bash
swift build
xcodebuild -scheme AutoSDK -destination 'generic/platform=iOS' build
```

模板 App 的源码和 XcodeGen 配置位于 `Examples/TemplateApp`。在 macOS 执行 `xcodegen generate` 后即可打开 `AutoSDKTemplate.xcodeproj`。

没有 Mac 时，可直接使用 GitHub Actions 构建 TrollStore IPA；Windows 下可运行
`node tools/auto-sdk.mjs build-remote --repo OWNER/REPO --output .\\dist\\AutoSDKTemplate.ipa`，步骤见 [`docs/WINDOWS_TROLLSTORE.md`](docs/WINDOWS_TROLLSTORE.md)。
如果当前目录是已登录 GitHub CLI 可识别的 Git 仓库，可省略 `--repo`。提交前可运行
`npm run verify` 执行仓库级静态检查。

VS Code 插件源码位于 [`vscode-extension`](vscode-extension)。它支持 JS/TS 脚本发送与停止、截图保存、宿主 App 节点 JSON 快照、API 补全、代码片段，以及等待并下载 GitHub Actions 构建产物。安装及手机连接限制见 [`vscode-extension/README.md`](vscode-extension/README.md)。

通过 USB 时可在 VS Code 执行 **AutoSDK: Start USB Tunnel**，插件会管理自身启动的 `iproxy` 进程；也可手动执行 `iproxy 9001 9001`。通过 Wi-Fi 时可直接配置 TemplateApp 显示的 `ws://手机IP:9001` 和 debug token。

版本更新记录见 [`CHANGELOG.md`](CHANGELOG.md)。
