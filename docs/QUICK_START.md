# 快速开始（第三方上手）

本仓库是一套可复用的 iOS 自动化脚本框架。别人拿到仓库后，按下面路径
大约 10 分钟就能跑通「写脚本 → 构建 IPA → 安装 → 调试运行」。更完整的
Windows 流程见 [`WINDOWS_SIDELOAD.md`](WINDOWS_SIDELOAD.md)。

## 你需要什么

- 一个 GitHub 账号（用于远程构建，无需 Mac）
- 一台 iPhone + 免费签名工具（AltStore / Sideloadly / SideStore / Feather）
- 一台 Windows 电脑（写脚本 + 调试，可选装 VS Code 插件）

## 1. 构建模板 App（约 4 分钟）
> 不想自己构建？直接到仓库 [Releases 页](https://github.com/huihui0115/ios-auto-sdk/releases) 下载最新 AutoSDKTemplate.ipa（免费签名安装，无需巨魔）和 VS Code 插件 vsix，跳过本节直接进入「安装到 iPhone」。

```powershell
# 把仓库推到自己的 GitHub 仓库后
gh auth login
node tools/auto-sdk.mjs build-remote --repo 你的账号/你的仓库 --output .\dist\AutoSDKTemplate.ipa
```

或直接在 GitHub 页面 **Actions → Build AutoSDK IPA → Run workflow**，
完成后下载 `AutoSDKTemplate-ipa` 工件里的 IPA。

## 2. 安装到 iPhone

把 IPA 传到手机（iCloud 云盘 / LocalSend / 文件传输均可），在「文件」App
用 Sideloadly/AltStore 以 Apple ID 免费签名安装（7 天过期重签一次），装好后在「设置 → 通用 → VPN 与设备管理」信任开发者证书。打开
`AutoSDKTemplate`，界面上会列出内置脚本并显示调试地址与 token。

## 3. 写自己的脚本

最简单的方式：编辑 `Examples/TemplateApp/Scripts/` 下的 `.js`，推送到
GitHub 重新构建安装。两个现成示例：

- `hello.js`：首次运行演示（设备信息、沙盒文件、存储、定时器、系统能力）
- `demo-api.js`：API 全家桶演示（不依赖特定界面，直接看返回结果）- `gesture-demo.js`：滑动、自定义手势、多指与捏合（需内置 no-WDA 适配器 `multiTouch`）
- `vision-demo.js`：截图、取色、找色、多色比较、OCR、模板找图
- `media-demo.js`：把截图/图片写入 iOS 相册（需 `mediaLibraryWrite`）

脚本风格与 AutoScript/Auto.js 高度一致：

```javascript
const info = device.getDeviceInfo();          // 设备信息
file.writeText("demo/a.txt", "hi");           // 沙盒文件
storages.create("cfg").put("key", 1);         // 命名存储
auto.click({ label: "登录", type: "Button" }); // 点击（宿主内）
device.setClipboard("text");                  // 系统剪贴板
auto.openURL("https://example.com");          // 打开 URL
app.homeScreen();                             // 回主屏幕（内置 no-WDA 适配器）
device.volumeUp();                             // 音量加（需适配器硬件按键能力）
```

完整 API 参考：

- 脚本 API 总览：[README 脚本 API 段](../README.md)
- 文件/存储/设备/系统能力：[`FILE_STORAGE_DEVICE_API.md`](FILE_STORAGE_DEVICE_API.md)
- HTTP：[`HTTP_API.md`](HTTP_API.md)
- 节点操作：[`NODE_OPERATIONS.md`](NODE_OPERATIONS.md)
- 执行语义（超时/定时器/错误码）：[`SCRIPT_EXECUTION.md`](SCRIPT_EXECUTION.md)

## 4. 用 VS Code 调试（可选但推荐）

安装 `vscode-extension/` 目录的插件（见 [vscode-extension/README](../vscode-extension/README.md)）：

1. 电脑和 iPhone 进入同一可信局域网，在 App 设置中开启 Wi-Fi 调试并允许“本地网络”权限；
2. 点击状态栏 **AutoSDK: scan Wi-Fi iPhone**，或运行 **AutoSDK: Scan Wi-Fi and Add iPhone**；
3. 选择局域网广播发现的手机；首次输入 App 显示的 token，之后同一手机可一键重连，IP 改变也无需重新配对；
4. 打开 `.js` / `.ts` 文件，在编辑区右键 **AutoSDK: Run Current Script**；
5. **AutoSDK: Capture Screenshot / Inspect Nodes** 可视化调试。局域网禁用 mDNS 时选择 **Enter IP Address** 手动输入手机 IP；USB 隧道仅作为高级备用。

## 5. 把脚本能力嵌进自己的 App

不限于模板 App：通过 SPM 或 CocoaPods 集成 `AutoSDK`，实现
`AutoAutomationAdapter`，即可在自己的 App 里获得同样的脚本运行时、文件/
存储/HTTP/系统能力与调试通道（集成示例见 `Examples/TemplateApp`）。

## 常见问题

- **想自动化别的 App？** 内置 no-WDA 适配器默认开启（需 TrollStore/开发者签名
  构建，见 `docs/NO_WDA_ARCHITECTURE.md`）；App Store 安全构建用 UIKit 适配器，仅宿主 App 内。
- **脚本无限循环卡死？** 公共 JavaScriptCore 无法硬中断纯 JS 死循环；
  桥接调用与定时器都会响应 `stopScript`/超时，极端情况重启 App。
- **想让别人不碰构建直接用？** 本项目定位是「开发者的 SDK」。若要给最终
  用户即装即用，需把脚本入口做成自己 App 的功能；脚本本身可直接复用。
