# TrollStore, WDA and Lua automation

> ⚠️ 注意（v1.17.0）：`AutoWDAHTTPAdapter` 已移除，跨 App 自动化统一走内置 no-WDA 适配器（`AutoBuiltinAdapter`，见 `docs/NO_WDA_ARCHITECTURE.md`）。本文涉及 WDA 的内容为历史存档。

Audit date: 2026-08-02

## 结论

TrollStore 可以永久安装带额外 Entitlements 的 IPA，但它仍是 jailed app
环境。它不等于完整越狱，也不会自动提供 XCTest Runner、testmanagerd、SpringBoard
注入或 LaunchDaemon 能力。

因此要分清三条路线：

| 路线 | 是否需要 WDA | 能否跨 App | 适合当前项目 |
| --- | ---: | ---: | --- |
| AutoUIKitAdapter | 否 | 否，只控制宿主 App | 默认、稳定、公开 UIKit API |
| 独立 WDA/iOS-Tagent + AutoWDAHTTPAdapter | 是 | 是，取决于 Runner 是否能在设备上工作 | TrollStore 下最容易验证的跨 App 路线 |
| 私有 HID/Accessibility 执行器 | 否 | 理论上可以 | 仅作为实验适配器，必须真机验证 |

AutoWDAHTTPAdapter 只实现客户端，不把 XCTest 或私有符号链接进 SDK。使用时
仍需单独安装并启动一个 WDA-compatible Runner，例如 Appium WDA 或
AirtestProject 的 iOS-Tagent。默认连接地址是设备本机的
http://127.0.0.1:8100。

    AutoWDAHTTPAdapter *wda =
        [[AutoWDAHTTPAdapter alloc] initWithBaseURL:
            [NSURL URLWithString:@"http://127.0.0.1:8100"]
            applicationBundleId:@"com.example.target"
            timeout:15];
    [engine setAutomationAdapter:wda];

这条路线不要求 SDK 自己包含 WDA，但要求 WDA Runner 以独立应用或测试运行时
成功启动。TrollStore 能否在具体 iOS 版本上启动该 Runner，必须在真机验证；
不能仅凭 IPA 能安装就推断跨 App 自动化已经可用。

## “更快、可内嵌”的 WDA 变体

公开可核对的变体主要是 WDA 的 fork 或重新打包，而不是脱离 XCTest 的新官方
引擎：

- [Appium WebDriverAgent](https://github.com/appium/WebDriverAgent) 仍以
  WebDriverAgentRunner 和 XCTest.framework 为核心。
- [AirtestProject/iOS-Tagent](https://github.com/AirtestProject/iOS-Tagent) 是
  面向 Airtest 的 WDA fork，改动了协议和适配，但 README 仍要求 Xcode 构建
  Runner，并通过 iproxy 或 wdaproxy 连接。
- 网络上所谓“Standalone WDA”通常是把 Runner 重新打包成可点开的 IPA，或
  搭配去掉调试符号的预构建包。它可能省去电脑上的 xcodebuild，但没有改变
  XCTest/testmanagerd 的权限前提，也不代表能被可靠地内嵌到普通 App。

所以“内嵌 WDA”应理解为“同一产品交付一个 WDA Runner/服务组件”，而不是把
WebDriverAgentLib 静态链接进任意 App 后就获得跨 App 控制。

## Lua 框架为什么看起来不需要 WDA

我们还核对了公开的 [LuaTouch](https://github.com/sky5566jf/LuaTouch) 项目。
它的 Lua 只是脚本层；当前源码中的 `simulateSwipe`、`simulatePinch` 和
`simulateKeyPress` 是占位函数，触摸实现也明确标注为简化 fallback，截图只渲染
宿主 App 的窗口，并没有 WDA 节点树或可验证的跨 App 执行器。详细记录见
[`docs/LUA_FRAMEWORK_AUDIT.md`](LUA_FRAMEWORK_AUDIT.md)。

AutoTouch 官方 Lua 文档写明它需要 Jailbreak，并提供
touchDown/touchMove/touchUp、appRun/appKill、截图、找色、找图和 OCR。
XXTouch FAQ 也明确写明必须取得完整系统权限。

这类产品通常是下面的架构：

    Lua/Python 脚本
            |
    本地服务或脚本引擎
            |
    越狱 tweak / root daemon / 私有 Accessibility 或 HID API
            |
    SpringBoard、BackBoard、目标 App

Lua 只是脚本语言；真正提供全局触摸、跨 App 截图和节点树的是底层权限。
例如公开的逆向资料会使用 IOHIDEventSystemClientDispatchEvent，并要求
com.apple.hid.manager.user-access-protected 等私有权限。没有正确权限时，
HID 事件通常会被系统静默丢弃；仅把 Lua 换成 JavaScript 不会改变这一点。

TrollStore 场景可以尝试同类私有执行器，但必须逐设备验证：

1. Entitlement 是否被 CoreTrust 保留并实际生效。
2. iOS 版本是否允许 HID dispatch、跨进程 Accessibility 和屏幕捕获。
3. 是否能常驻运行；TrollStore 本身不能替代越狱 LaunchDaemon。
4. 目标 App 是否需要注入或 task_for_pid，以及系统是否拒绝该操作。

当前 SDK 不会默认声明这些能力。私有执行器一旦验证成功，应实现
AutoAutomationAdapter，并通过 capabilities 显式报告 crossApp、
realTouchInjection、requiresWDA: false 和支持的节点/图色功能。

## 真机验证顺序

1. 先单独安装 WDA/iOS-Tagent Runner，确认它能启动并返回 /status。
2. 在手机本机或 USB 隧道访问 /source、/screenshot 和一个点击接口。
3. 在 AutoSDK 中使用 AutoWDAHTTPAdapter，检查 auto.capabilities()。
4. 最后再验证 TrollStore 私有 HID 方案；失败时仍保留 WDA 或宿主 App 路线。

参考：

- [AutoTouch Lua Guide](https://docs.autotouch.net/lua/)
- [XXTouch iOS FAQ](https://docs.xxtou.ch/FAQ/faq-0034.html)
- [TrollStore](https://github.com/opa334/TrollStore)
- [TrollStore WDA installation issue](https://github.com/opa334/TrollStore/issues/742)
