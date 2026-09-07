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
| SDK 版本 | `package.json`、`package-lock.json`、`AutoSDK.podspec`、`Sources/AutoSDK/AutoSDKVersion.m`、`CHANGELOG.md` | 版本四件套保持同步，并补完整 CHANGELOG |
| Personal VPN（可选） | Apple Developer App ID、描述文件与宿主 App `.entitlements` | 仅使用 `vpn.status/connect/disconnect` 时启用 Personal VPN capability；宿主还必须自行预存并启用自己的 `NEVPNManager` 配置。SDK 不创建配置，也不能控制其他 VPN App/MDM 配置 |

## 2. 已内置、无需再配

- `CFBundleDocumentTypes`：`.js` / `.txt` 可从 Files “打开方式”导入；
  `UTImportedTypeDeclarations` 覆盖 `.mjs`。
- `LSSupportsOpeningDocumentsInPlace`。
- `NSLocalNetworkUsageDescription`、`NSAllowsLocalNetworking` 和
  `NSLocationWhenInUseUsageDescription`。
- `AutoSDKDebugAllowWiFi`（默认 `true`，可改成 `false` 强制 USB 回环模式）。
- 设备端工作流：脚本列表、编辑器、保存/重命名/删除、导入/导出、
  设置页（Debug URL/Token/适配器切换）。
- 内置 `toast` / `toastLog`（无需宿主注册 native 方法）。

## 3. 构建与签名

```bash
# 1) 本地静态检查、文档生成与单元测试（Windows 也行）
npm run verify
npm test
npx -y -p typescript@5.6.3 tsc -p jsconfig.json --noEmit
npm run docs
npm --prefix vscode-extension run check
npm --prefix vscode-extension test

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
- Personal VPN：必须使用包含对应 entitlement 的 App ID、签名证书与描述文件；
  普通未配置的模板、仅链接 `NetworkExtension` 框架或补写 Info.plist 都不会自动
  获得 VPN 权限，也不会自动生成 VPN 配置。

## 4. 真机验证清单（每次发版前人工执行）

1. Xcode 真机编译：`xcodebuild -scheme AutoSDKTemplate -destination <device> build`。
2. 安装后启动，确认脚本列表显示 `hello.js`、`demo-api.js` 和
   `system-demo.js` 三个内置脚本。
3. 点 ▶ 运行 `hello.js`，日志出现设备信息，无异常退出。
4. 编辑器：新建脚本 → 保存 → 出现在列表 → 可运行；重启 App 后仍在。
5. 导入：Files 里用“打开方式”选一个 `.js`，或列表工具栏文件夹按钮导入，
   确认导入后立即可运行。
6. 导出：分享到 Files/隔空投送，确认内容完整。
7. 重命名/删除：重名时给出明确错误；删除后列表刷新。
8. 设置页：确认 Debug URL/Token 显示；Wi-Fi 开关切换后日志面板地址变化。
9. 跨 App 模式：内置 no-WDA（AutoSDKAdapter=BUILTIN 为默认，需特签构建，见 docs/NO_WDA_ARCHITECTURE.md）：
   capabilities() 核对 realTouchInjection/nodes/crossApp 后运行跨 App 脚本。WDA 已于 v1.17.0 移除，无回退。
10. 运行 `system-demo.js`：确认低电量模式、定位服务总开关和本 App 定位授权
    返回合理状态；`system.openSettings("vpn")` 只负责打开设置页，不应声称已切换
    VPN/Wi-Fi/蓝牙/蜂窝/飞行模式。
11. Personal VPN：默认无 entitlement/预存配置的构建调用 `vpn.status/connect`
    应返回 false 且 `lastError()` 给出明确原因；如果发布包启用了 Personal VPN，
    需先由宿主保存并启用自己的配置，再验证 status/connect/disconnect。不得用其他
    VPN App 或 MDM 配置冒充成功。
12. 回环：关 Wi-Fi 开关后，`npm run debug -- --token <token>` 走 USB 隧道
    能连上并运行脚本。
13. 卸载重装，确认沙盒脚本清空、无残留。

## 5. 已知边界（写进应用内说明，避免售后）

- 跨 App 自动化唯一路线为内置 no-WDA 适配器，其系统级能力依赖特签信任上下文，需按 docs/NO_WDA_ARCHITECTURE.md 完成真机验证；
  v1.17.0 起外部 WDA 适配器已移除，无 legacy 回退。
- `AutoUIKitAdapter` 只能自动化本 App 自己的 UIKit 视图。
- 内置 no-WDA 适配器模板找图已支持（Round 49，有界两阶段）；xpath 支持 Round 53 的有界单步子集，predicate/嵌套路径和硬件按键注入仍受限。
- Wi-Fi 调试未加密（仅 token 认证），只建议在可信网络使用。
- `vpn.status/connect/disconnect` 只管理宿主 App 自己的 Personal VPN 配置，要求
  entitlement 与预存配置；它不是系统所有 VPN 配置的管理器。
- `system.openSettings(panel)` 是 best-effort 设置页深链。iOS 版本或策略可能拒绝
  并触发回退；返回 true 只表示系统接受打开页面的请求，不代表任何开关已经改变。
  AutoSDK 不提供 Wi-Fi、蓝牙、蜂窝、热点或飞行模式的静默切换。
- 脚本引擎不是沙盒外的完整浏览器：无 DOM/网络不受控能力，HTTP 默认关闭。

## 6. 发版动作

1. 更新版本号四件套（`package.json`、`package-lock.json`、podspec、Version.m）并同步 CHANGELOG（见上表）。
2. 跑一遍第 3 节的静态检查和 CI 构建。
3. 人工过一遍第 4 节清单。
4. 把未签名 IPA 上传商店/分发后台，附上第 5 节说明。
5. 打 tag：`git tag v1.40.0; git push origin main v1.40.0`。
