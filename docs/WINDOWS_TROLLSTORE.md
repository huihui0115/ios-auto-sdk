# Windows + TrollStore Workflow

A Mac is not required to install the template app. Xcode still has to compile
the iOS sources, so the repository uses a GitHub Actions macOS runner to build
an unsigned IPA. TrollStore performs the final installation on the phone.

## 1. Run the build

Push this repository to a GitHub repository. From Windows, the CLI can trigger
the build and download the IPA automatically:

```powershell
gh auth login
node tools/auto-sdk.mjs build-remote --repo OWNER/REPO --output .\dist\AutoSDKTemplate.ipa
```

The helper downloads into a temporary directory, verifies the ZIP central
directory contains `Payload/*.app`, and only then replaces the requested output
file. A failed or malformed artifact leaves an existing IPA untouched.

When the current directory is a Git checkout recognized by `gh repo view`,
`--repo OWNER/REPO` is optional. In the VS Code extension, set
`autosdk.repository` when the local folder is not a Git checkout. The
**AutoSDK: Build TrollStore IPA** command uses the same helper and waits for
the matching workflow before downloading the IPA. Its notification progress is
cancellable; the extension tracks and terminates only build process trees that
it started.

The same workflow can also be started from **Actions** by selecting
**Build TrollStore IPA** and choosing **Run workflow**. The workflow:

1. Runs the static checks and iOS simulator tests on macOS.
2. Installs XcodeGen and generates `AutoSDKTemplate.xcodeproj` from `project.yml`.
3. Builds for `iphoneos` with code signing disabled.
4. Packages `Payload/AutoSDKTemplate.app` as `AutoSDKTemplate.ipa`.
5. Uploads the IPA as the `AutoSDKTemplate-TrollStore` artifact.

Download the artifact from the completed workflow on Windows and extract the
IPA file. No Apple Developer account or signing certificate is required for
this TrollStore path.

## 2. Install on the iPhone

Transfer the IPA to the phone using iCloud Drive, LocalSend, a local HTTP
server, or another file-transfer method. In the iOS Files app, use Share/Open
In and select TrollStore, then confirm installation. The app is installed as
the `AutoSDKTemplate` bundle.

## 3. Run scripts

The template bundles `Examples/TemplateApp/Scripts/hello.js`. Add or edit JS,
push a new commit, run the workflow again, and install the updated IPA. The
template UI lists bundled scripts and exposes Run, Stop, execution logs, and
the debug token needed by VS Code.

After VS Code connects, **Run Current Script** executes the open JS/TS file
without rebuilding the IPA. **Send Current Script to Device** stores it in the
app sandbox, and **Manage Device Scripts** lists, runs, or deletes deployed
files. These commands work over either Wi-Fi or a USB port forward.

The workflow uses a Debug build so the local debug server is enabled. If a
Windows USB mux tool is available, forward the port:

```powershell
iproxy 9001 9001
```

The VS Code extension can start and stop this process with **AutoSDK: Start USB
Tunnel** and **AutoSDK: Stop USB Tunnel**. Install `iproxy` on Windows and keep
it on PATH, or configure `autosdk.iproxyPath`; optional
`autosdk.usbDeviceUdid` selects one attached phone. Current upstream `iproxy`
uses `-u UDID`; `autosdk.iproxyUdidStyle=legacy` supports older builds that
expect a trailing UDID. The extension only stops the process it started.
Concurrent start/stop commands are serialized, and a
process that does not exit before the stop timeout remains tracked so another
copy cannot accidentally be started on the same port. It then connects to
`ws://127.0.0.1:9001` using the token shown in the TemplateApp log panel.
`pymobiledevice3` or another usbmuxd
forwarder can still be used manually instead of `iproxy`.

`iproxy` is not bundled with the repository, VS Code extension, TrollStore, or
the IPA. If no compatible Windows build is installed, use direct Wi-Fi or run
a supported usbmuxd forwarder manually. USB pairing/trust must already succeed
between Windows and the unlocked iPhone.

### Wi-Fi connection

The template enables `AutoSDKDebugAllowWiFi` in its `Info.plist`. Connect the
iPhone and Windows PC to the same trusted Wi-Fi network, launch the template,
and allow the iOS local-network permission prompt. The app log panel displays a
URL such as `ws://192.168.1.25:9001` and the app's random installation token.
Run **AutoSDK: Configure Device Connection**, enter those values, then run
**AutoSDK: Test Device Connection**. No `iproxy` process is required for this
mode. Client isolation on guest Wi-Fi networks can prevent the connection.

## Important limitations

- TrollStore is an installer/signing mechanism; it does not provide XCTest or
  WDA privileges for automating other apps.
- `AutoUIKitAdapter` operates on views owned by the template app itself.
- Keep the TemplateApp foregrounded and the iPhone unlocked while using the
  UIKit adapter or its debug server. TrollStore does not grant unrestricted
  background execution, so iOS may suspend the app after it is backgrounded or
  the phone locks.
- `AutoWDAHTTPAdapter` can connect to a separately installed WDA-compatible
  Runner at `http://127.0.0.1:8100`, but the Runner still has to start and pass
  its own iOS/XCTest permission checks. Installing an IPA alone is not proof of
  cross-app automation.
- The template enables `NSAllowsLocalNetworking` for this loopback WDA HTTP
  path. It does not enable arbitrary cleartext Internet traffic.
- The WebSocket debug server remains loopback-only unless
  `debugAllowWiFi`/`AutoSDKDebugAllowWiFi` is enabled. Wi-Fi mode uses an
  authenticated but unencrypted `ws://` connection and must only be used on a
  trusted local network.
- The VS Code client sends heartbeats while connected. After a Wi-Fi change,
  sleep, app restart, tunnel exit, or token rotation, pending commands fail and
  the next command establishes a fresh connection; commands are not replayed
  automatically because clicks and script runs are not generally idempotent.
- The template creates a strong random debug token on first launch and keeps
  it for later reconnects. Reinstalling the app or clearing its data rotates
  the token; VS Code stores the configured value in SecretStorage bound to the
  configured URL and workspace. Re-run the configure command after changing
  either value; runtime connections ignore the deprecated plaintext token
  setting.
- Do not enable `allowNetwork` or a debug token in a production-distributed
  build unless the script source and endpoints are trusted.
- JavaScript runs away from the app UI thread, but public JavaScriptCore cannot
  hard-kill a pure `while (true) {}` loop. Stop/timeout remains cooperative for
  bridge calls; restart the app if pure JavaScript permanently occupies the
  script queue.
