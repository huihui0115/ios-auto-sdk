# 发布清单（Market Release Checklist）

本文档把 AutoSDK Template App 从“开发状态”变成“可分发状态”。它只负责
清单和验证步骤，不承诺任何商店的审核结果——iOS 上带脚本执行、本地调试
WebSocket 和跨 App 自动化的应用，App Store 审核风险较高，主流分发光
AltStore / Sideloadly / 侧载 / 企业签名更现实。

## 1. 发布前必须改的配置

| 项目 | 位置 | 说明 |
| --- | --- | --- |
| Bundle ID | `Examples/TemplateApp/project.yml` 的 `PRODUCT_BUNDLE_IDENTIFIER` | 改成你自己的反向域名，如 `com.yourname.autosdk` |
| 显示名 | `App/Info.plist` 的 `CFBundleDisplayName` | 改成市场名称，如 `Auto脚本` |
| 图标 | 添加 `App/Assets.xcassets`（xcodegen 会自动包含） | 至少 1024×1024，透明背景不支持 |
| 版本号 | `App/Info.plist` 的 `CFBundleShortVersionString` / `CFBundleVersion` | 每次发版递增 |
| SDK 版本 | `Sources/AutoSDK/AutoSDKVersion.m`、`package.json`、`CHANGELOG.md` | 三者保持同步 |

## 2. 已内置、无需再配

- `CFBundleDocumentTypes`：`.js` / `.txt` 可从 Files “打开方式”导入；
  `UTImportedTypeDeclarations` 覆盖 `.mjs`。
- `LSSupportsOpeningDocumentsInPlace`。
- `NSLocalNetworkUsageDescription` 和 `NSAllowsLocalNetworking`。
- `AutoSDKDebugAllowWiFi`（默认 `true`，可改成 `false` 强制 USB 回环模式）。
- 设备端工作流：脚本列表、编辑器、保存/重命名/删除、导入/导出、
  设置页（Debug URL/Token/适配器切换）。
- 内置 `toast` / `toastLog`（无需宿主注册 native 方法）。

## 3. 构建与签名

```bash
# 1) 本地静态检查 + 单元测试（Windows 也行）
node tools/verify.mjs
npm test
.\vscode-extension\node_modules\.bin\tsc -p jsconfig.json --noEmit

# 2) 在 macOS 上生成工程并打包
cd Examples/TemplateApp
xcodegen generate
xcodebuild -scheme AutoSDKTemplate -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

CI 也会做同样的事：GitHub 上手动触发 `Build AutoSDK IPA`
（workflow_dispatch），产物 `AutoSDKTemplate-ipa` 是一个未签名 IPA，
免费签名安装即可（无需巨魔）；测试诊断在 `AutoSDKTests-xcresult` 里。

- 免费签名（Sideloadly/AltStore）：用 Apple ID 签名安装，7 天续签一次。
- 真机调试 / 个人分发：需要你自己的 Developer 证书和描述文件，或
  AltStore/侧载工具。
- App Store：需要移除或深度改造调试服务器、脚本编辑器等能力，并接受
  审核不确定性；本文档不承诺 App Store 通过。

## 4. 真机验证清单（每次发版前人工执行）

1. Xcode 真机编译：`xcodebuild -scheme AutoSDKTemplate -destination <device> build`。
2. 安装后启动，确认脚本列表显示 `hello.js` / `demo-api.js` 两个内置脚本。
3. 点 ▶ 运行 `hello.js`，日志出现设备信息，无异常退出。
4. 编辑器：新建脚本 → 保存 → 出现在列表 → 可运行；重启 App 后仍在。
5. 导入：Files 里用“打开方式”选一个 `.js`，或列表工具栏文件夹按钮导入，
   确认导入后立即可运行。
6. 导出：分享到 Files/隔空投送，确认内容完整。
7. 重命名/删除：重名时给出明确错误；删除后列表刷新。
8. 设置页：确认 Debug URL/Token 显示；Wi-Fi 开关切换后日志面板地址变化。
9. 跨 App 模式：内置 no-WDA（AutoSDKAdapter=BUILTIN 为默认，需特签构建，见 docs/NO_WDA_ARCHITECTURE.md）：
   capabilities() 核对 realTouchInjection/nodes/crossApp 后运行跨 App 脚本。WDA 已于 v1.17.0 移除，无回退。
10. 回环：关 Wi-Fi 开关后，`npm run debug -- --token <token>` 走 USB 隧道
    能连上并运行脚本。
11. 卸载重装，确认沙盒脚本清空、无残留。

## 5. 已知边界（写进应用内说明，避免售后）

- 跨 App 自动化唯一路线为内置 no-WDA 适配器，其系统级能力依赖特签信任上下文，需按 docs/NO_WDA_ARCHITECTURE.md 完成真机验证；
  v1.17.0 起外部 WDA 适配器已移除，无 legacy 回退。
- `AutoUIKitAdapter` 只能自动化本 App 自己的 UIKit 视图。
- 内置 no-WDA 适配器模板找图已支持（Round 49，有界两阶段）；xpath/predicate 选择器仍不支持，硬件按键注入受限。
- Wi-Fi 调试未加密（仅 token 认证），只建议在可信网络使用。
- 脚本引擎不是沙盒外的完整浏览器：无 DOM/网络不受控能力，HTTP 默认关闭。

## 6. 发版动作

1. 更新版本号三件套（见上表）。
2. 跑一遍第 3 节的静态检查和 CI 构建。
3. 人工过一遍第 4 节清单。
4. 把未签名 IPA 上传商店/分发后台，附上第 5 节说明。
5. 打 tag：`git tag v1.24.0 && git push origin v1.24.0`。