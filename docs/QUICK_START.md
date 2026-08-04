# 快速开始（第三方上手）

本仓库是一套可复用的 iOS 自动化脚本框架。别人拿到仓库后，按下面路径
大约 10 分钟就能跑通「写脚本 → 构建 IPA → 安装 → 调试运行」。更完整的
Windows 流程见 [`WINDOWS_TROLLSTORE.md`](WINDOWS_TROLLSTORE.md)。

## 你需要什么

- 一个 GitHub 账号（用于远程构建，无需 Mac）
- 一台 iPhone（安装 TrollStore）
- 一台 Windows 电脑（写脚本 + 调试，可选装 VS Code 插件）

## 1. 构建模板 App（约 4 分钟）
> 不想自己构建？直接到仓库 [Releases 页](https://github.com/huihui0115/ios-auto-sdk/releases) 下载最新 AutoSDKTemplate.ipa（TrollStore 可直接安装）和 VS Code 插件 vsix，跳过本节直接进入「安装到 iPhone」。

```powershell
# 把仓库推到自己的 GitHub 仓库后
gh auth login
node tools/auto-sdk.mjs build-remote --repo 你的账号/你的仓库 --output .\dist\AutoSDKTemplate.ipa
```

或直接在 GitHub 页面 **Actions → Build TrollStore IPA → Run workflow**，
完成后下载 `AutoSDKTemplate-TrollStore` 工件里的 IPA。

## 2. 安装到 iPhone

把 IPA 传到手机（iCloud 云盘 / LocalSend / 文件传输均可），在「文件」App
里选择「共享/打开方式 → TrollStore」安装。装好后打开
`AutoSDKTemplate`，界面上会列出内置脚本并显示调试地址与 token。

## 3. 写自己的脚本

最简单的方式：编辑 `Examples/TemplateApp/Scripts/` 下的 `.js`，推送到
GitHub 重新构建安装。两个现成示例：

- `hello.js`：首次运行演示（设备信息、沙盒文件、存储、定时器、系统能力）
- `demo-api.js`：API 全家桶演示（不依赖特定界面，直接看返回结果）- `gesture-demo.js`：滑动、自定义手势、多指与捏合（需 WDA `multiTouch`）
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
app.homeScreen();                             // 回主屏幕（需 WDA 适配器）
device.volumeUp();                             // 音量加（需 WDA 适配器）
```

完整 API 参考：

- 脚本 API 总览：[README 脚本 API 段](../README.md)
- 文件/存储/设备/系统能力：[`FILE_STORAGE_DEVICE_API.md`](FILE_STORAGE_DEVICE_API.md)
- HTTP：[`HTTP_API.md`](HTTP_API.md)
- 节点操作：[`NODE_OPERATIONS.md`](NODE_OPERATIONS.md)
- 执行语义（超时/定时器/错误码）：[`SCRIPT_EXECUTION.md`](SCRIPT_EXECUTION.md)

## 4. 用 VS Code 调试（可选但推荐）

安装 `vscode-extension/` 目录的插件（见 [vscode-extension/README](../vscode-extension/README.md)）：

1. **AutoSDK: Configure Device Connection** 填入手机上的 `ws://IP:9001` 和 token；
2. **AutoSDK: Test Device Connection** 验证连接；
3. 打开 `.js` 文件，**AutoSDK: Run Current Script** 直接运行，无需重新构建；
4. **AutoSDK: Capture Screenshot / Inspect Nodes** 可视化调试；
5. 无 Mac 时用 **AutoSDK: Start USB Tunnel**（需 `iproxy`）或同 Wi-Fi 直连。

## 5. 把脚本能力嵌进自己的 App

不限于模板 App：通过 SPM 或 CocoaPods 集成 `AutoSDK`，实现
`AutoAutomationAdapter`，即可在自己的 App 里获得同样的脚本运行时、文件/
存储/HTTP/系统能力与调试通道（集成示例见 `Examples/TemplateApp`）。

## 常见问题

- **想自动化别的 App？** 需要设备上运行 WDA 兼容 Runner，并在宿主 App 里
  把适配器切到 `AutoWDAHTTPAdapter`（模板通过 `AutoSDKAdapter` 配置项切换）。
- **脚本无限循环卡死？** 公共 JavaScriptCore 无法硬中断纯 JS 死循环；
  桥接调用与定时器都会响应 `stopScript`/超时，极端情况重启 App。
- **想让别人不碰构建直接用？** 本项目定位是「开发者的 SDK」。若要给最终
  用户即装即用，需把脚本入口做成自己 App 的功能；脚本本身可直接复用。
