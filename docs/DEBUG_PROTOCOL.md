# AutoSDK Debug Protocol

The debug server is disabled by default. Configure a strong random token:

```objc
NSString *debugToken = NSUUID.UUID.UUIDString;
// Present this only in a development UI or another protected setup flow.
// Do not write the complete token to the system log.
[[AutoEngine sharedEngine] configureWithConfig:@{
    @"debugServerEnabled": @YES,
    @"debugPort": @9001,
    @"debugToken": debugToken,
    @"debugAllowWiFi": @YES,
    @"debugLogging": @YES
}];
```

The server binds to the loopback interface unless `debugAllowWiFi` is `YES`.
Wi-Fi mode retains loopback access, accepts direct local-network connections,
explicitly prohibits cellular interfaces, and requires a token containing at
least 16 characters. Debug tokens are limited to 1024 UTF-8 bytes. Add
`NSLocalNetworkUsageDescription` to the host app, keep both devices on the same
trusted network, and connect to `ws://IPHONE_WIFI_ADDRESS:9001`. Every request
must contain `id`, `token`, and `type`. Responses copy the request `id`, allowing
a client to correlate concurrent requests. `id` must be a non-empty string of
at most 128 characters (and 512 UTF-8 bytes); `type` must be a non-empty string
of at most 64 characters. The transport is development-only
and does not encrypt WebSocket traffic, so do not expose it on an untrusted LAN.

Clients may include `timeoutMs` to advertise their response budget. The device
clamps it to `1...3,600,000` milliseconds. Script commands default to the
engine's one-hour maximum; other commands default to six minutes. A client may
still time out earlier and discard a late response. Client cancellation only
stops the local wait: an already-running device-side heavy operation may finish
in the background, and an immediate retry can receive `device busy` until it
releases the single-heavy-request slot. The VS Code Inspector drops cancelled
queued work and silently consumes the explicitly cancelled request's eventual
response while continuing to report genuinely unknown response IDs.

## Commands

Ping:

```json
{"id":"1","token":"...","type":"ping"}
```

Device information:

```json
{"id":"2","token":"...","type":"deviceInfo"}
```

Runtime and adapter capabilities:

```json
{"id":"3","token":"...","type":"capabilities"}
```

Capture the host app as a base64 PNG:

```json
{"id":"4","token":"...","type":"screenshot"}
```

Capture a consistent screenshot, node tree, and device-information snapshot:

```json
{"id":"4a","token":"...","type":"inspectSnapshot","options":{"maxNodes":1000}}
```

The response includes `protocolVersion`, `snapshotId`, `capturedAtMs`,
`durationMs`, `pngBase64`, `deviceInfo`, a pre-order `nodes` array, and a
`truncated` flag. Nodes expose `nodeId`, `parentId`, `depth`, `order`, bounds,
attributes, and a transient selector. `maxNodes` is clamped to `1...2000`.

Capture visible host-app UIKit node descriptors. An optional compound selector
uses the same fields as `auto.findElements`:

```json
{"id":"5","token":"...","type":"nodes","selector":{"type":"Button","maxResults":200}}
```

Inspect a pixel or test a temporary image template without first deploying it:

```json
{"id":"5a","token":"...","type":"pixelColor","x":120,"y":320}
{"id":"5b","token":"...","type":"findImage","templatePngBase64":"...","options":{"threshold":0.9,"maxCandidates":200000}}
```

Debug image templates are limited to 512 KB after base64 decoding.

Deploy a reusable PNG/JPEG asset, test it by name, list it, or remove it:

```json
{"id":"5f","token":"...","type":"putAsset","name":"login-a1b2c3d4.png","dataBase64":"..."}
{"id":"5g","token":"...","type":"findImage","assetName":"login-a1b2c3d4.png","options":{"threshold":0.9,"maxComparedPixels":50000000}}
{"id":"5h","token":"...","type":"listAssets"}
{"id":"5i","token":"...","type":"deleteAsset","name":"login-a1b2c3d4.png"}
```

Assets stay in `debug-assets` below the configured sandbox root. The VS Code
Inspector deploys the selected local template before testing it, so generated
`auto.findImage("debug-assets/...")` code refers to a real phone-side file.

Run bounded OCR in a selected screen region:

```json
{"id":"5j","token":"...","type":"testOCR","region":{"x":20,"y":100,"width":300,"height":160,"mode":"fast","maxResults":100}}
```

Test an immediate node action using a transient selector returned by the
snapshot. Coordinate fallback is accepted only for `click`:

```json
{"id":"5c","token":"...","type":"nodeAction","action":"click","selector":{"xpath":"/..."}}
{"id":"5d","token":"...","type":"nodeAction","action":"input","selector":{"id":"email"},"text":"user@example.com"}
{"id":"5e","token":"...","type":"nodeAction","action":"scroll","selector":{"id":"submit"}}
```

Run JavaScript:

```json
{"id":"6","token":"...","type":"run","script":"console.log('hello')"}
```

Deploy and manage scripts in the app sandbox:

```json
{"id":"6a","token":"...","type":"putScript","name":"login.js","script":"console.log('saved')"}
{"id":"6b","token":"...","type":"listScripts"}
{"id":"6c","token":"...","type":"runStored","name":"login.js"}
{"id":"6d","token":"...","type":"deleteScript","name":"login.js"}
```

Deployed names are flat ASCII `.js` filenames and deployed source is limited
to 768 KB. Files stay inside the configured AutoSDK sandbox and respect
`allowFileAccess`/`allowFileWrite`.

Stop the active script:

```json
{"id":"7","token":"...","type":"stop"}
```

The transport accepts client-masked text frames up to 1 MB and handles ping,
pong, and close frames. Fragmented messages and binary commands are rejected.
Each peer accepts at most eight in-flight commands and only one
heavy screenshot/node/pixel/image/OCR command at a time. Larger bursts receive a
correlated busy response instead of accumulating work on the phone. Outbound
JSON is limited to 32 MB.

To bound network backpressure, a peer is disconnected if its queued outbound
frames exceed 40 MB. A client should discard its pending requests after a
disconnect and reconnect on the next command; the VS Code client does this.
Peers with no in-flight command and no inbound frames for 90 seconds are closed
so abandoned Wi-Fi or USB sessions cannot permanently consume the eight-peer
limit. The VS Code client's 20-second heartbeat keeps a healthy idle session
open.

JavaScriptCore runs on a dedicated serial queue, so a pure JavaScript loop does
not freeze the app UI. Public JavaScriptCore does not provide a reliable hard
interrupt API: a script such as `while (true) {}` can still occupy that script
queue until the app process is restarted. Cooperative scripts are cancelled at
bridge calls, sleeps, timers, waits, and network polls.

For a USB workflow, leave `debugAllowWiFi` disabled, forward the device loopback
port with `tidevice` or an equivalent development tunnel, then run:

```bash
npm run debug -- --token <token> --script "console.log('connected')"
```

On Windows, an environment variable avoids exposing the token in the process
command line, and `--script-file` avoids the Windows command-line length limit:

```powershell
$env:AUTOSDK_DEBUG_TOKEN = '<token>'
npm run debug -- --script-file .\scripts\login.js
```

For Wi-Fi, no USB forwarder is needed:

```bash
npm run debug -- --url ws://192.168.1.25:9001 --token <token> --script "console.log('connected')"
```
