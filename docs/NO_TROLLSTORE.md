# 免巨魔（No-TrollStore）改造方案

> 对标 AScript / kuaijs 的市场方向：不需要 TrollStore（巨魔），不需要越狱、不需要开发者账号，
> 普通用户也能装、能用。本文说明 AutoSDK 当前为什么依赖 TrollStore、以及三条免巨魔路线。

## 一、现状：为什么现在需要 TrollStore

AutoSDK 模板 App 是一个 **unsigned IPA**：

- App 本体（JS 引擎 / 图色 OCR / 媒体 / 文件 / HTTP / 存储 / 悬浮窗）**不依赖任何特殊权限**，
  任意签名都能运行。
- 跨 App 的**控件自动化**依赖一个独立运行的 **WebDriverAgent（WDA）服务**（`http://127.0.0.1:8100`）。
  在免越狱设备上让 WDA 跑起来，需要系统级权限——TrollStore 正是通过给 WDA 注入
  `platform-application` 等 entitlement 来做到这一点。**这是唯一真正依赖 TrollStore 的部分。**

结论：**App 本体无需改动即可免巨魔；要免巨魔，关键是换一条"让 WDA 跑起来"的路径。**

## 二、路线 A：免费签名安装（最快落地，今天就能用）

用你自己的 Apple ID 免费签名安装 unsigned IPA，7 天过期后重签一次即可。

| 工具 | 平台 | 特点 |
| --- | --- | --- |
| [AltStore](https://altstore.io) | Mac/Windows | 最流行，自动续签（需电脑常开） |
| [Sideloadly](https://sideloadly.io) | Windows/Mac | 手动签名安装，简单直接 |
| [SideStore](https://sidestore.io) | iOS + 电脑 | 手机端续签，无需电脑常开 |
| [TrollHelper/Feather](https://github.com/khcrysalis/Feather) | iOS/电脑 | 图形化签名工具 |

步骤（以 Sideloadly 为例）：

1. 下载 `AutoSDKTemplate.ipa`（GitHub Releases 或 CI 产物）。
2. 电脑安装 Sideloadly，iPhone USB 连接，输入 Apple ID。
3. 选择 IPA → 开始安装。iPhone 上 设置 → 通用 → VPN与设备管理 → 信任开发者。
4. 打开 App 即可使用：**脚本引擎、图色 OCR、相册媒体、文件/HTTP/存储、悬浮窗、
   AutoUIKitAdapter（宿主 App 内自动化）全部可用。**

> 免费签名的限制：7 天过期需重签；同一 Apple ID 最多 3 个签名 App；无 WDA 时
> 跨 App 控件自动化不可用（见路线 B）。

## 三、路线 B：XCTest 激活 WDA（对标 AScript Agent 模式，完整控件自动化）

AScript 的"免越狱 Agent 模式"原理：App 用**企业签名/免费签名**安装，然后用激活工具
（USB 连接 + 开启开发者模式）注入运行 WDA 的 **XCTest 进程**，激活后 WDA 在
`127.0.0.1:8100` 提供控件 API。**AutoSDK 的 AutoWDAHTTPAdapter 完全复用这套链路。**

| 项 | 要求 |
| --- | --- |
| 系统 | iOS 15+（支持最新系统） |
| 前置 | 设置 → 隐私与安全性 → 开发者模式（开启） |
| 激活工具 | Windows 或 Mac 上运行（本项目规划中，见下文"待开发"） |
| 激活后 | 可拔 USB；**关机后失效，需重新激活** |

### 待开发：AutoSDK 激活工具（ActivationTool）

1. **WDA XCUITest bundle 构建**（CI 可产出）：在 macOS runner 上编译一个
   WebDriverAgent 的 `.xctest` bundle，作为构建产物上传。
2. **Windows 激活器**：基于 [go-ios](https://github.com/danielpaulus/go-ios)
   （开源，Windows 可用）实现：
   - USB 连接设备 → 安装 App → 运行 `xctest run` 注入 WDA bundle；
   - 等待 `8100` 端口就绪 → 提示激活成功。
3. **Mac 激活脚本**：用 `xcodebuild test-without-building` 注入（对标 AScript 的 Xcode 方案）。
4. App 端无需改动：设置里 WDA URL 指向 `http://127.0.0.1:8100` 即可。

> 该路线的工程量主要在激活工具，仓库内已有的 `AutoWDAHTTPAdapter`、调试服务器、
> VS Code 插件全部直接复用，不需要改架构。

## 四、路线 C（远期）：HID 硬件模式（对标 AScript HID / kuaijs HID）

| 项 | 说明 |
| --- | --- |
| 原理 | ESP32 蓝牙芯片模拟鼠标键盘（物理触控，不可被拦截）+ 系统录屏（Broadcast Extension）截图 |
| 优点 | 不需要开发者模式、不需要 WDA、不需要任何签名，iOS 13+ |
| 成本 | ESP32-C3 约 9~20 元 |
| 工作项 | ESP32 固件（Bluetooth HID）+ iOS Broadcast Extension + 引擎触控/截图适配层 |

此模式需要硬件与固件工程，作为后续里程碑推进。

## 五、无 WDA 时的能力矩阵（免费签名即可用）

| 能力 | 免费签名（无 WDA） | + XCTest 激活 WDA |
| --- | --- | --- |
| JS 脚本引擎 / 定时器 / 线程 | ✅ | ✅ |
| 图色：截屏 / 找色 / 找图 / 像素 | ✅ | ✅ |
| OCR（本地 Vision） | ✅ | ✅ |
| 文件 / 存储 / HTTP / 压缩 / Excel / plist | ✅ | ✅ |
| 相册读写（save/delete） | ✅ | ✅ |
| 悬浮窗（webView / screenDraw / floatBall） | ✅ | ✅ |
| 剪贴板 / 亮度 / 音量 / 振动 | ✅ | ✅ |
| 宿主 App 内自动化（AutoUIKitAdapter） | ✅ | ✅ |
| 跨 App 控件查找 / 点击 / 输入 | ❌ | ✅ |
| 跨 App 应用控制（launch/terminate/state） | ❌ | ✅ |

## 六、落地清单

- [x] 确认 App 本体无 entitlements，unsigned IPA 可被免费签名工具直接安装
- [x] 文档：本方案 + [ASCRIPT_COMPARISON.md](ASCRIPT_COMPARISON.md)
- [ ] CI 产出 WDA XCUITest bundle 工件（macOS runner）
- [ ] Windows 激活工具（go-ios `xctest run`）
- [ ] Mac 激活脚本（xcodebuild test-without-building）
- [ ] 企业签名打包脚本（可选，若持有企业证书）
- [ ] HID 模式（远期：ESP32 固件 + Broadcast Extension）
