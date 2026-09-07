# 安装与跨 App 能力边界

更新：2026-09-07 / AutoSDK v1.38.0。

## 最短使用路径

下载发布页中的 IPA 与 VSIX → 按 [安装指南](WINDOWS_SIDELOAD.md) 签名安装
模板 App → 手机开启 Wi-Fi 调试 → VS Code 执行 Scan Wi-Fi and Add iPhone →
输入手机显示的 token → 编写脚本并右键运行。完整操作见
[唯一开发文档](index.html#/quickstart)。

## 安装成功不等于跨 App 自动化可用

- 未签名 IPA 必须先签名才能安装。普通签名可运行 JavaScript 和宿主允许的公共能力，
  不会自动获得系统级触摸、跨 App 节点或后台常驻权限。
- UIKit 适配器只操作宿主自己的界面。
- 唯一跨 App 路线是内置 AutoBuiltinAdapter：依赖私有 API、实际签名权限与系统版本。
  必须读取 auto.capabilities().automation，再在目标真机验证；不能仅凭“开发签名/
  企业签名/安装成功”承诺可用。宿主切到后台还可能被 iOS 挂起。
- v1.17.0 起已删除外部 WDA 客户端，不再提供或计划 WDA 激活器。
  HID 硬件模式也不是当前仓库已实现的能力。
- VPN 只管理宿主预存且启用的 Personal VPN 配置，需要对应 entitlement。
  设置页跳转不等于静默控制系统开关。

[能力与签名说明](index.html#/scope) · [内置架构](NO_WDA_ARCHITECTURE.md) ·
[本轮审计与后续优先级](QUALITY_AUDIT.md)

旧版 WDA/XCTest 激活方案已从本指南删除，历史内容可在 Git 中查看。
