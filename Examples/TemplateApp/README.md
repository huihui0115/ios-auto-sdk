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
- System demo: bundled `Scripts/system-demo.js` reports Low Power Mode,
  Location Services and this app's location authorization, demonstrates
  best-effort Settings navigation, and reports Personal VPN failures through
  `lastError()` instead of pretending a system switch changed.

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

## System settings and Personal VPN

`system.openSettings(panel)` can request common iOS Settings panels such as
VPN, Wi-Fi, Bluetooth, cellular, airplane mode, location and battery. Except
for the public app-settings URL, these routes rely on best-effort Settings
deep links. iOS may reject or redirect them; a `true` result means only that
the open request was accepted, never that a Wi-Fi, Bluetooth, cellular,
hotspot or airplane-mode switch changed.

`vpn.status/connect/disconnect` uses `NEVPNManager.sharedManager` and manages
only the Personal VPN configuration owned and previously saved by this host
app. To enable it, add the Personal VPN capability to the App ID and target,
sign with a matching provisioning profile, then have the host create, save
and enable its configuration. The template does not create a VPN profile and
cannot select, delete or control configurations owned by another VPN app or
MDM. Without the entitlement, loading returns `false`; with the entitlement
but no saved profile, `status()` normally reports `invalid` and `connect()`
returns `false`. Inspect `lastError()` after a false result.

`device.isLowPowerModeEnabled()` and `location.isEnabled()` are read-only
system-state queries. `location.getAuthorizationStatus()` reports this app's
authorization. `location.getLocation()` additionally requires
`NSLocationWhenInUseUsageDescription`, which the template declares; changing
the device-wide Location Services switch still requires the user in Settings.

## Files integration

`App/Info.plist` declares:

- `CFBundleDocumentTypes` for `public.javascript` and `public.plain-text`
  (`.js`, `.txt`) so Files offers “Open With AutoSDK Template”.
- `UTImportedTypeDeclarations` for `.mjs`.
- `LSSupportsOpeningDocumentsInPlace`.
- `NSLocationWhenInUseUsageDescription` for `location.getLocation()`.

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
