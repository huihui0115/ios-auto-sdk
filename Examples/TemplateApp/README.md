# AutoSDK Template App

A ready-to-brand iOS automation host built on AutoSDK. It runs on-device
JavaScript, edits scripts on the phone, imports/exports them through the Files
app, and connects to a PC debug client over WebSocket.

## Build

```bash
brew install xcodegen
cd Examples/TemplateApp
xcodegen generate
open AutoSDKTemplate.xcodeproj
```

The generated project links the repository's local Swift package and bundles
the scripts in `Scripts`.

## What the template does

- Script list: shows bundled scripts plus scripts stored in the app sandbox
  (`debug-scripts/`), with run, stop, refresh, and swipe-to-delete.
- On-device editor: create, edit, save, run, and stop JavaScript. Saved
  scripts are validated (`*.js`, safe file name, 768 KB limit) and appear in
  the list immediately.
- Import: pick a `.js`/`.mjs`/`.txt` file from Files (toolbar folder button)
  or use “Open With AutoSDK Template” from Files. Imported files are copied
  into the sandbox.
- Export: share any script through the system share sheet (AirDrop, Files,
  Mail, ...) with the toolbar action button.
- Rename: rename a deployed script; the engine rejects name collisions.
- Settings: shows the debug WebSocket URL and token, toggles Wi-Fi debug mode,
  and switches between the built-in no-WDA adapter (default, cross-app) and
  the host-app UIKit adapter. Toggling re-creates the automation adapter and
  re-applies engine config.
- Debug: with `AutoSDKDebugAllowWiFi`, the app advertises `_autosdk._tcp`
  through Bonjour and the log panel shows the phone's `ws://` URL and
  installation token for the VS Code extension or `npm run debug`.

## Integration notes

The template wires the engine through `AutoTemplateSettings` instead of
duplicating setup in `AppDelegate.m`:

```objc
@import AutoSDK;

// AppDelegate.m
- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    [AutoTemplateSettings applyEngineConfiguration];
    // ... root navigation controller with ScriptListViewController
    return YES;
}
```

The default adapter is `AutoBuiltinAdapter`, the built-in no-WDA engine:
IOHIDEvent touch injection, system-wide accessibility node queries, and
SpringBoard app control, with every private symbol resolved at runtime
(`docs/NO_WDA_ARCHITECTURE.md`). It requires a private-API-permitted build
(TrollStore or developer signing). Set `AutoSDKAdapter` to `UIKIT` in
`App/Info.plist` or `NSUserDefaults` to restrict automation to views owned
by this application with the public-API `AutoUIKitAdapter`.

## Files integration

`App/Info.plist` declares:

- `CFBundleDocumentTypes` for `public.javascript` and `public.plain-text`
  (`.js`, `.txt`) so Files offers “Open With AutoSDK Template”.
- `UTImportedTypeDeclarations` for `.mjs`.
- `LSSupportsOpeningDocumentsInPlace`.

`AppDelegate.m` handles `application:openURL:options:` and imports the opened
file into `debug-scripts/`.

## Security

The bundled template enables `AutoSDKDebugAllowWiFi` and includes
`NSLocalNetworkUsageDescription`. On a trusted Wi-Fi network the settings page
shows the phone's `ws://` URL and installation token. Keep the token in the
settings UI only; do not log it. Set `AutoSDKDebugAllowWiFi` to `false` to
restore loopback-only USB-tunnel mode. Wi-Fi debugging is authenticated but
unencrypted and intended only for development.
The Bonjour announcement contains a stable installation name and port, never
the token; custom host apps must list `_autosdk._tcp` in `NSBonjourServices`.

See `docs/MARKET_RELEASE.md` for the distribution checklist before shipping a
signed build.
