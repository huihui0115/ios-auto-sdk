# AutoSDK VS Code Extension

This extension edits JavaScript or TypeScript scripts, provides AutoSDK API
completion and snippets, transpiles TypeScript before sending, tests a device
connection, deploys/runs/manages phone scripts, captures screenshots, opens a
visual node/image/color inspector, and builds/downloads the AutoSDK IPA
through GitHub Actions.

TypeScript annotations and other single-file syntax are transpiled. Files that
use `import` or `export` are rejected with a clear error because the phone
runtime does not provide `require`, package resolution, or a module bundler.

The SDK repository also includes `types/autosdk.d.ts` and `jsconfig.json` for
full workspace type information in addition to the extension's completion
provider. The focused `device.` completion list covers every method declared
by `AutoDeviceAPI`, including system state and switch-related helpers; a
declaration-parity test prevents future methods from silently disappearing
from the menu. Personal VPN and Settings entries keep the same iOS permission
limits described by the generated SDK documentation.

## Install locally on Windows

From the repository root:

```powershell
cd vscode-extension
npm install
npx @vscode/vsce package --out autosdk-vscode-0.12.0.vsix
code --install-extension .\autosdk-vscode-0.12.0.vsix --force
```

Packaging and repository helper commands require Node.js 22+ on PATH. An
installed VSIX runs in VS Code's extension host and includes its `ws` runtime
dependency.

The normal setup is direct Wi-Fi:

1. Put VS Code and the iPhone on the same trusted LAN, keep the AutoSDK app open,
   enable Wi-Fi debugging, and allow the iOS local-network prompt.
2. Click **AutoSDK: scan Wi-Fi iPhone** in the status bar, or run **AutoSDK: Scan
   Wi-Fi and Add iPhone** from the Command Palette.
3. Select the Bonjour-discovered phone. Enter the token displayed by the app on
   first pairing; the extension saves the stable broadcast identity and tests the
   connection. Later scans reconnect with one selection even if the DHCP address changes.
4. Open a `.js` or `.ts` file, right-click in the editor, and choose
   **AutoSDK: Run Current Script**. The editor title also has a play button.

Discovery uses the `_autosdk._tcp` Bonjour service and does not broadcast the
debug token. The scan keeps collecting after the first response so multiple
phones can be selected, and its progress notification can be cancelled. If a
connection test fails, choose **Re-enter Token** or **Retry Connection** without
scanning again. Running from the editor before setup offers **Scan Wi-Fi and Add
iPhone** directly. If multicast DNS is blocked, choose **Enter IP Address** and enter
either `192.168.1.25` or the complete `ws://192.168.1.25:9001` address shown by
the app. No `iproxy`, USB cable, or libimobiledevice install is needed for Wi-Fi.

The manual **AutoSDK: Configure Device Connection** command remains available.
Connection setup keeps
the token in VS Code SecretStorage and binds it to the configured URL and
workspace. A rediscovered phone may safely rebind the workspace token only when
its stable Bonjour identity matches; selecting a different phone asks for its
token. The legacy plaintext
`autosdk.debugToken` setting is never read; saving a connection removes any
leftover value from the workspace and global settings:

```json
{
  "autosdk.debugUrl": "ws://192.168.1.25:9001",
  "autosdk.connectionTimeout": 300000
}
```

USB remains an advanced fallback through **AutoSDK: Search USB iPhone
(Advanced)**. USB discovery uses `idevice_id` and optional `ideviceinfo`,
preferring tools beside the configured `iproxy` executable. The extension can
manage the forwarder with **AutoSDK: Start USB Tunnel** and
**AutoSDK: Stop USB Tunnel**. Install `iproxy` from a Windows libimobiledevice
distribution and keep it on PATH, or set `autosdk.iproxyPath` to the executable.
The local port comes from `autosdk.debugUrl`; `autosdk.usbDevicePort` defaults
to 9001, and `autosdk.usbDeviceUdid` selects one phone when several are attached.
Current `iproxy` uses `-u UDID`; set `autosdk.iproxyUdidStyle` to `legacy` only
for an older Windows build that expects the UDID as its final argument.
Run **AutoSDK: Test Device Connection** after starting the tunnel. Sideloading
alone does not install `iproxy` or create the tunnel. Without `iproxy`, use
direct Wi-Fi, another usbmuxd forwarder, or bundled scripts in the TemplateApp.

The template app advertises its stable development-only Bonjour name only while
Wi-Fi debugging is active. Wi-Fi mode does not need `iproxy`; switching to
Wi-Fi stops a tunnel managed by the extension.
Guest-network client isolation may block direct access.
Keep the TemplateApp foregrounded and the iPhone unlocked: free signing does not
prevent iOS from suspending an ordinary app after it is backgrounded.

The **AutoSDK: Build IPA** command runs the repository's
`tools/auto-sdk.mjs build-remote` helper. It waits for the matching workflow,
downloads the configured artifact, and asks where to save the IPA. Configure
`autosdk.repositoryPath` when the open workspace is not the SDK repository;
set `autosdk.repository` to `owner/repository` when the local folder is not a
Git checkout. Otherwise the helper detects the repository with GitHub CLI.
`autosdk.workflowRef`, `autosdk.artifactName`, and `autosdk.buildTimeout` are
available for non-default Actions setups.
The notification progress can be cancelled; on Windows the extension terminates
only the build process tree it started. Active build helpers are also terminated
when the extension host stops.
The command only runs repository code after the VS Code workspace is trusted.
Running or deploying an editor script and starting the configured `iproxy`
executable also require workspace trust. Connection tests, screenshots, and
node inspection remain available in limited untrusted-workspace mode; executable
and repository path settings are restricted there.

The client keeps at most eight commands pending, matching the phone-side peer
limit, heartbeats the active connection, and reconnects on the next command
after a disconnect. It deliberately does
not replay interrupted commands, because replaying a click or script could
duplicate side effects.

After connecting, use **AutoSDK: Open Visual Inspector** for a consistent
screenshot and node-tree snapshot, selector/image/color tests, and generated
click code. Selecting a local PNG/JPEG deploys a hashed copy into the phone's
`debug-assets` directory before testing, so generated `auto.findImage` code
uses a real persistent path. Region mode can execute bounded fast OCR and show
the recognized words immediately. UIKit mode inspects the host app. The
built-in no-WDA mode can inspect another app only when a TrollStore or
enterprise-signed host remains running and
`auto.capabilities().automation.nodes`, `.screenshot`, and the required action
capability (for example `.click`) report true. An ordinary free-signed Wi-Fi
session must keep the TemplateApp foregrounded and therefore does not promise
cross-app Inspector access after iOS suspends it in the background.

The Inspector uses one serialized visual-operation lane shared with the plain
screenshot and node commands. Screenshot, node, pixel, OCR, and image-match
requests therefore cannot collide with the phone's single heavy-debug-request
limit; queued requests of the same kind keep only the newest result. Webview
messages carry request IDs, so a late response cannot overwrite a newer
selection or exported snapshot. Stable node IDs preserve the selected row
across refreshes. **Cancel** (or `Escape`) releases a long-running Inspector
wait and drops queued stale work. Screen-edge picks are clamped to valid pixel
indices, and equal-size overlapping nodes prefer the deepest control. Set
`autosdk.inspectorMaxNodes` to `1...2000` (default `1000`) to tune snapshot
size. Set `autosdk.inspectorActionRefreshDelay` to `0...5000` ms (default `400`)
when the target app needs more or less animation settling time after click,
input, or scroll. **Export snapshot** saves one portable JSON bundle containing
the correlated PNG base64, node tree, device information, snapshot ID, and
timing.

The implementation is split by responsibility: `inspector-service.js`
validates and serializes device protocol calls, `inspector-session.js` owns
panel lifecycle and request correlation, and `media/inspector-model.js` holds
the DOM-independent geometry, selector, and generated-script model used by the
webview and tests. `completion-model.js` expands grouped API signatures into
independent snippets and discovers namespaces from the completion data, so new
modules cannot silently fall back to an unrelated all-API list.

**AutoSDK: Run Current Script** executes the editor contents immediately.
**AutoSDK: Send Current Script to Device** stores a transpiled `.js` copy in
the app sandbox without running it. **AutoSDK: Manage Device Scripts** lists,
runs, or deletes those deployed files.
