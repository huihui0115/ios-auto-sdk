# Windows + 免费签名安装（无需巨魔）

不需要 Mac，也不需要 TrollStore。Xcode 仍然负责编译 iOS 源码，所以仓库使用
GitHub Actions 的 macOS runner 构建一个**未签名 IPA**；手机上用 Apple ID
免费签名工具完成最终安装（对标 AScript / kuaijs 的免巨魔分发路线）。

## 1. 远程构建

把仓库推到 GitHub。在 Windows 上用 CLI 触发构建并自动下载 IPA：

```powershell
gh auth login
node tools/auto-sdk.mjs build-remote --repo OWNER/REPO --output .distAutoSDKTemplate.ipa
```

辅助脚本会下载到临时目录，校验 ZIP 中央目录包含 `Payload/*.app` 后才会覆盖
目标文件；构建失败或产物损坏时保留原有 IPA 不动。

当前目录是 `gh repo view` 能识别的 Git 检出时，`--repo OWNER/REPO` 可省略。
VS Code 插件里本地目录不是 Git 检出时，配置 `autosdk.repository`。
**AutoSDK: Build IPA** 命令使用同一套辅助逻辑，等待匹配的 workflow 完成后
下载 IPA。它的进度通知可取消；插件只终止自己启动的构建进程树。

也可以在 GitHub 网页 **Actions → Build AutoSDK IPA → Run workflow** 手动触发。
workflow 会：

1. 跑静态检查与 iOS 模拟器 XCTest 全量测试（macOS runner）。
2. 安装 XcodeGen 并从 `project.yml` 生成 `AutoSDKTemplate.xcodeproj`。
3. 以 `iphoneos` 目标、禁用代码签名构建。
4. 打包 `Payload/AutoSDKTemplate.app` 为 `AutoSDKTemplate.ipa`。
5. 把 IPA 上传为 `AutoSDKTemplate-ipa` 工件。

Windows 上从完成的 workflow 下载工件并解出 IPA 即可。**不需要付费开发者账号**：
用免费 Apple ID 签名就能装（见下）。

## 2. 安装到 iPhone（免费签名）

把 IPA 传到手机（iCloud 云盘 / LocalSend / 微信文件均可）。用以下任一工具以
你的 Apple ID 免费签名安装：

| 工具 | 平台 | 说明 |
| --- | --- | --- |
| [Sideloadly](https://sideloadly.io) | Windows/Mac | 手动签名安装，最简单直接 |
| [AltStore](https://altstore.io) | Mac/Windows | 自动续签（需电脑常开） |
| [SideStore](https://sidestore.io) | iOS + 电脑 | 手机端续签，无需电脑常开 |
| [Feather](https://github.com/khcrysalis/Feather) | iOS/电脑 | 图形化签名工具 |

以 Sideloadly 为例：

1. 电脑安装 Sideloadly，iPhone USB 连接，输入 Apple ID。
2. 选择 `AutoSDKTemplate.ipa` → 开始安装。
3. iPhone 上 设置 → 通用 → VPN 与设备管理 → 信任你的开发者证书。
4. 打开 `AutoSDKTemplate`：主界面列出内置脚本，显示调试地址与 token。

> 免费签名的限制：7 天过期需重签；同一 Apple ID 最多同时 3 个签名 App。
> App 本体（脚本引擎 / 图色 OCR / 相册 / 文件 / HTTP / 存储 / 悬浮窗 / 宿主
> App 内自动化）全部可用；跨 App 控件自动化需要额外激活 WDA（XCTest 激活
> 路线见 [NO_TROLLSTORE.md](NO_TROLLSTORE.md)）。

## 3. 跑脚本

模板自带 `Examples/TemplateApp/Scripts/hello.js`。增改 JS 后推送新提交、
重新触发 workflow、安装新 IPA 即可。模板 UI 支持脚本列表、Run、Stop、
执行日志，以及 VS Code 需要的调试 token。

VS Code 连上后，**Run Current Script** 直接执行打开的 JS/TS 文件（无需重装
IPA）；**Send Current Script to Device** 把文件存进 App 沙盒；
**Manage Device Scripts** 列出 / 运行 / 删除已部署脚本。Wi-Fi 直连或
USB 端口转发（iproxy）都支持。

## 4. 下一步

- 跨 App 控件自动化（对标 AScript Agent 模式）：见
  [NO_TROLLSTORE.md](NO_TROLLSTORE.md) 的路线 B（XCTest 激活 WDA）。
- 企业签名分发（免 7 天续签）：用企业开发者证书签名 IPA，用户信任企业开发者
  即可安装。
- 发布清单与包名修改：见 [MARKET_RELEASE.md](MARKET_RELEASE.md)。
