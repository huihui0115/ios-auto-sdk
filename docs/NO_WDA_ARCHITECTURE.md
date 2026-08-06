# 内置 no-WDA 架构（AutoBuiltinAdapter）

> Round 46（v1.16.0）起，AutoSDK 的战略路径从"外挂 WDA"切换为"内置 no-WDA"，
> 对齐 AScript Agent 模式 / kuaijs 的主流方案。**Round 47（v1.17.0）：外部 WDA
> 适配器（AutoWDAHTTPAdapter）已完全移除**，不再保留任何回退；内置 no-WDA
> 是唯一跨 App 路线。

## 1. 为什么放弃外部 WDA

| 维度 | 外部 WDA | 内置 no-WDA |
| --- | --- | --- |
| 依赖 | 需另装常驻的 WebDriverAgent/XCTest Runner | 无外部进程 |
| 签名 | WDA 需 Xcode + 开发者账号（免费签 7 天过期） | 宿主 App 一次签名即可 |
| 延迟 | 每步操作走 HTTP 往返 | 进程内直调，毫秒级 |
| 稳定性 | WDA 崩溃/会话失效需要重建 | 无会话概念 |
| 用户体验 | 多 App 切换、保活、端口转发 | 开箱即用 |

no-WDA 不是"零特权"：它把信任要求从"WDA + 开发者账号"换成
"特签宿主 App（TrollStore / 企业签）+ 私有接口"。App Store 正规分发做不到
跨 App 注入，这是平台红线，所有同类产品（AScript/kuaijs/EasyClick 新版）
都走特签分发渠道。

## 2. 实现（Sources/AutoSDK/AutoBuiltinAdapter.m）

所有私有符号一律 **dlopen/dlsym 运行时解析**，不链接任何私有框架、不引用
私有头文件；符号缺失时操作返回清晰错误，capabilities 如实降级。

| 能力 | 私有接口 | 降级行为 |
| --- | --- | --- |
| 真实触摸注入（点击/双击/长按/滑动/多指手势） | IOKit：IOHIDEventSystemClientCreate / IOHIDEventCreateDigitizerEvent / IOHIDEventSystemClientDispatchEvent | capabilities.realTouchInjection=NO，触摸类操作报 unavailable |
| 系统级控件树查询 | Accessibility：AXUIElementCreateSystemWide / AXUIElementCopyAttributeValue / PerformAction / SetAttributeValue | nodes=NO，选择器操作报 unavailable |
| 应用启动 | LSApplicationWorkspace.openApplicationWithBundleID / SpringBoardServices.SBSLaunchApplicationWithIdentifier | 报 unavailable |
| 应用终止 | BackBoardServices.BKSTerminateApplication | 报 unavailable |
| 前台应用/已装应用 | SBSCopyFrontmostApplicationDisplayIdentifier / LSApplicationWorkspace.allInstalledApplications | 报 unavailable |
| Home/锁屏/解锁 | SBSLaunchApplicationWithIdentifier(com.apple.springboard) / SBSLockDevice / SBSOpenSensitiveURLAndUnlock | 报 unavailable |
| 全屏截图 | UIKit.UIGetScreenImage，失败回退宿主窗口截图 | 仅宿主窗口范围 |
| OCR / 图色 | Vision + 自研位图扫描（基于截图） | 随截图能力降级 |

节点句柄格式 `axb:<child.index.path>`，从系统级根节点按子节点索引路径重放
解析（UI 变化后会失效，需重新查询——与 WDA /source 句柄同级别的稳定性，
capabilities.stableNodeHandles=NO 已如实标注）。

## 3. 启用方式

宿主模板 App 配置 `AutoSDKAdapter`（NSUserDefaults 或 Info.plist）：

- 默认 / `BUILTIN` / `BUILTIN-NOWDA` / `NOWDA` → 内置 no-WDA 适配器（唯一跨 App 路线）
- `UIKIT` → AutoUIKitAdapter（仅宿主 App 内，App Store 安全）
- `WDA` / `WDAHTTP` 值已随适配器在 v1.17.0 移除。

可选配置：`AutoSDKMaxSnapshotNodes`（默认 5000）、
`AutoSDKMaxSnapshotDepth`（默认 30）、`AutoSDKScreenshotCacheDuration`。

## 4. 签名与授权要求（部署侧，必须满足）

1. 分发渠道：TrollStore 或企业签名（用户侧免开发者账号、免 Xcode）。
2. 触摸注入与跨 App 无障碍读取依赖签名上下文携带的 entitlement 与
   系统信任级别；不同 iOS 大版本的可用面可能变化（AScript 以"支持最新
   iOS 26+"作为维护承诺，我们也遵循同样的版本跟进策略）。
3. App Store 构建请保持 `AutoUIKitAdapter`（无私有调用，审核安全）。

## 5. 验证计划（待真机执行）

静态检查已在 Windows 侧通过（verify 锚点覆盖关键符号与接线）。真机验证清单：

1. TrollStore 安装模板 App，`AutoSDKAdapter=BUILTIN`。
2. `capabilities()` 核对 realTouchInjection / nodes / crossApp 为真。
3. 坐标点击/滑动/长按/双指 pinch（对照录屏验证落点）。
4. 跨 App 控件查询：在系统设置/第三方 App 内 text/label/id/type 匹配。
5. launch/terminate/homeScreen/lock/unlock/applist。
6. 全屏截图 + OCR + findColor/compareColors/findMultiColor。
7. iOS 15 / 16 / 17 / 18 / 26 各跑一遍冒烟脚本，记录私有接口可用面差异。

## 6. 已知限制（诚实标注）

- `findImage`（模板匹配）内置适配器尚未实现，返回清晰错误；用图色/OCR
  方案替代，或临时切换 UIKit 适配器（仅宿主 App 内）。
- xpath/predicate 选择器内置不支持（用 text/label/id/type + Match 正则）。
- 硬件按键注入（音量键等）暂不支持；home 通过 SpringBoard 跳转实现。
- 节点句柄非稳定句柄，UI 变化后需重新查询。
