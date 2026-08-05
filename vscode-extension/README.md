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
provider.

## Install locally on Windows

From the repository root:

```powershell
cd vscode-extension
npm install
npx @vscode/vsce package --out autosdk-vscode-0.5.0.vsix
code --install-extension .\autosdk-vscode-0.5.0.vsix --force
```

Packaging and repository helper commands require Node.js 22+ on PATH. An
installed VSIX runs in VS Code's extension host and includes its `ws` runtime
dependency. Configure the device URL and token through **AutoSDK: Configure
Device Connection**. The command keeps
the token in VS Code SecretStorage and binds it to the configured URL and
workspace. Changing either requires configuring the connection again, which
prevents another workspace from redirecting a saved token. The legacy plaintext
`autosdk.debugToken` setting is never read; saving a connection removes any
leftover value from the workspace and global settings:

```json
{
  "autosdk.debugUrl": "ws://127.0.0.1:9001",
  "autosdk.connectionTimeout": 300000
}
```

The extension can manage this forwarder with **AutoSDK: Start USB Tunnel** and
**AutoSDK: Stop USB Tunnel**. Install `iproxy` from a Windows libimobiledevice
distribution and keep it on PATH, or set `autosdk.iproxyPath` to the executable.
The local port comes from `autosdk.debugUrl`; `autosdk.usbDevicePort` defaults
to 9001, and `autosdk.usbDeviceUdid` selects one phone when several are attached.
Current `iproxy` uses `-u UDID`; set `autosdk.iproxyUdidStyle` to `legacy` only
for an older Windows build that expects the UDID as its final argument.
Run **AutoSDK: Test Device Connection** after starting the tunnel. Sideloading
alone does not install `iproxy` or create the tunnel. Without `iproxy`, use
direct Wi-Fi, another usbmuxd forwarder, or bundled scripts in the TemplateApp.

The template app also supports direct Wi-Fi debugging. Put Windows and the
iPhone on the same trusted Wi-Fi network, allow the app's local-network prompt,
and enter the `ws://IPHONE_WIFI_ADDRESS:9001` URL and installation token displayed by
the app in **AutoSDK: Configure Device Connection**. Wi-Fi mode does not need
`iproxy`; switching to Wi-Fi stops a tunnel managed by the extension.
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
the recognized words immediately. UIKit mode inspects the host app. WDA mode
can inspect and operate other apps that WDA can access.

**AutoSDK: Run Current Script** executes the editor contents immediately.
**AutoSDK: Send Current Script to Device** stores a transpiled `.js` copy in
the app sandbox without running it. **AutoSDK: Manage Device Scripts** lists,
runs, or deletes those deployed files.
