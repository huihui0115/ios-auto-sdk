# Lua framework audit

> ⚠️ 注意（v1.17.0）：`AutoWDAHTTPAdapter` 已移除，跨 App 自动化统一走内置 no-WDA 适配器（`AutoBuiltinAdapter`，见 `docs/NO_WDA_ARCHITECTURE.md`）。本文涉及 WDA 的内容为历史存档。

Audit date: 2026-08-02

## The project that was checked

The public repository [sky5566jf/LuaTouch](https://github.com/sky5566jf/LuaTouch)
describes itself as a TrollStore Lua automation tool and depends on DeviceKit.
It is a useful example of why the scripting language and the automation
executor must be evaluated separately.

The current source contains the following important details:

- `LuaTouch.swift` implements `simulateTouch` with
  `UIApplication.shared.windows.first`, `hitTest`, and direct
  `touchesBegan`/`touchesEnded` calls. Its own comment calls this a simplified
  fallback and says a real implementation needs XCUITest.
- `simulateSwipe`, `simulatePinch`, and `simulateKeyPress` are empty
  placeholders in the checked revision.
- `captureScreen` renders the first application window. That is not a global
  SpringBoard or another-app screen capture API.
- The Lua bridge provides convenience functions for files, HTTP, clipboard,
  and app URL opening, but it does not provide a WDA node tree, XPath, OCR, or
  a cross-process accessibility session.

So this kind of project can run without WDA because it is either a host-app
demo, a coordinate-script facade, or an unfinished private-executor shell.
Lua itself does not grant cross-app touch, screen capture, node traversal, or
process control permissions.

## What this means for AutoSDK

AutoSDK keeps the execution boundary explicit:

```text
JavaScript (or a future Lua facade)
        |
AutoAutomationAdapter
        |
AutoUIKitAdapter       -> public UIKit APIs, host app only
AutoWDAHTTPAdapter      -> separate WDA-compatible Runner, cross-app if it works
private adapter         -> optional experimental HID/Accessibility executor
```

The WDA adapter now reuses its HTTP connection and performs image matching,
color search, and Vision OCR locally on WDA screenshots. This makes screenshot
processing faster without pretending that the SDK owns XCTest or private
entitlements. Parent/child node relationships remain unavailable through the
WDA adapter unless a runner-specific source-tree implementation is added;
stable element handles must not be invented from XML snapshots.

## TrollStore recommendation

For a TrollStore build, ship the host-app path first and treat cross-app WDA as
a separately installed Runner that must pass a real-device `/status`,
`/source`, screenshot, and click smoke test. A Lua syntax layer can be added
over the same adapter later, but replacing JavaScript with Lua cannot remove
the Runner or private-permission requirement.
