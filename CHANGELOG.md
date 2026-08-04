# Changelog

All notable changes to AutoSDK are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Fixed

- **The private JSC execution-time API is no longer used.**
  `JSContextGroupSetExecutionTimeLimit` /
  `JSContextGroupClearExecutionTimeLimit` (weak-linked, undocumented) were
  observed to hang the JavaScript VM on the iOS 17.4 simulator, stalling the
  whole test run. The SDK now relies on the cooperative stop flag plus the
  wall-clock watchdog: `auto.sleep`, bridge calls and timer callbacks are
  interrupted promptly, while a pure-JS `while(true){}` loop that never
  crosses the bridge can keep the CPU busy until the process is terminated.
  `interruptibleScripts` remains accepted for compatibility. See
  `docs/SCRIPT_EXECUTION.md`.
- **HTTP tests can intercept the shared session again.** The engine-wide
  `NSURLSession` used the ephemeral configuration, which ignores
  `NSURLProtocol` classes registered with `+[NSURLProtocol registerClass:]`,
  so the in-process `autosdk.test` test harness could not see any request.
  The shared session now uses the default configuration (caches, cookies and
  credential storage explicitly disabled) and accepts an internal
  `urlProtocolClasses` config key so hosts and tests can inject
  `NSURLProtocol` subclasses deterministically before first use.
- **Stale bridge errors no longer leak into the next script.** `lastError`
  is cleared whenever a script starts successfully, so a failure from a
  previous bridge call cannot be reported as the current run's result.
- **Path-like input returns a precise error.** A missing `.js` file or path
  (e.g. `missing.js`, `scripts/nested.js`) now fails with
  `AutoSDKErrorScriptNotFound` instead of being evaluated as JavaScript.
  The heuristic keeps valid one-line source like `1/2` running as code.
- **Redirect policy is explicit and documented.** When no host allowlist is
  configured, HTTP and remote-script redirects may follow any `http`/`https`
  host; HTTPS-to-HTTP downgrades and non-http(s) schemes are always rejected.
  The repository verification rule now encodes this policy.
- **`auto` proxy reserved keys no longer dispatch to native methods.**
  `auto.then`, `auto.toJSON`, `auto.toString`, `auto.valueOf`,
  `auto.catch`, `auto.constructor`, `auto.__proto__` and similar keys
  return `undefined`, so promise interop and `JSON.stringify(auto)` cannot
  trigger unknown native calls or crash.
- **Template app matches its documentation.** `Examples/TemplateApp` now
  registers the `toast` native method shown in the README and used by
  `Scripts/hello.js`.
- **Inline source ending in `.js` is no longer mistaken for a missing
  path.** A trailing comment such as `// main.js` no longer returns
  `AutoSDKErrorScriptNotFound`; the `.js` suffix only implies a path when
  the input is path-shaped (no whitespace, no JavaScript syntax characters).
- **Inspector selector results clear stale overlays.** Testing a selector
  now removes any previous image-match highlight and region selection, so
  the screenshot overlay always reflects the current result set.
- **Extension command coverage is enforced.** Repository verification and
  the extension wiring tests assert that every contributed
  `autosdk.*` command is registered, so a renamed or dropped command
  fails CI instead of surfacing as a missing command at runtime.

### Changed

- **`scriptTimeout` is the total execution budget including timers.** One
  `runScript` keeps running until the timer queue drains; `setInterval`
  keeps the run alive until `stopScript` or `scriptTimeout`. Documented in
  `README.md`, `docs/PERFORMANCE.md` and `docs/SCRIPT_EXECUTION.md`.
- **`AutoMainThreadAdapterProxy` caches adapter capabilities once** and
  reads them lock-free afterwards on the hot path.
- **`AutoBootstrapScript` moved to its own file**
  (`Sources/AutoSDK/AutoBootstrapScript.m` + private header), keeping
  `AutoEngine.m` smaller and navigable.
- **Script sleeps and element polling no longer busy-spin.** The script
  thread's run loop usually has no sources on modern JavaScriptCore, so
  `auto.sleep`/`waitFor` now fall back to a real thread sleep when
  `runMode:` services nothing. Older runtimes that attach a
  `CFRunLoopTimer` keep the previous blocking behavior.
- **VS Code extension no longer reads plaintext `autosdk.debugToken`.**
  SecretStorage is the only credential source; the deprecated setting is not
  read at runtime and leftover values are removed when a connection is saved.
  The setting was removed from `package.json`.
- **The script timeout watchdog is a one-shot dispatch timer** instead of a
  blocking wait, so a long-running script no longer occupies a global utility
  thread for the whole budget.
- **Script results are bounded.** The evaluated `value` is converted with
  depth/size budgets (24 levels, 50,000 container entries, 1 MiB per string);
  oversized nodes become `__autosdkTruncated` markers.
- **Console message truncation never splits UTF-16 surrogate pairs.**
- **HTTP and remote scripts reuse one keep-alive session.** `invokeHTTP`
  and remote-script downloads share one engine-wide `NSURLSession` (created
  once and never invalidated per request), so TLS sessions and HTTP
  connections survive between calls instead of paying a new handshake per
  request. Redirect enforcement is routed per task through
  `AutoHTTPRedirectRouter` and remains host-allowlist aware.
- **HTTP paths now have regression coverage.** A registered `NSURLProtocol`
  serves deterministic in-process endpoints (`http://autosdk.test`) covering
  data requests, downloads, redirects, response byte limits, timeouts,
  remote-script loading, and cancellation.

### Added

- Regression tests: pure-JS loop timeout, timer-callback loop timeout
  (including that the engine stays usable afterwards), missing-path errors,
  division expression `1/2` disambiguation, and proxy reserved-key /
  `JSON.stringify(auto)` behavior.
- `docs/SCRIPT_EXECUTION.md`: run lifecycle, input classification, timeout
  and interruption model, timer semantics, result shape and error codes.
- Regression tests: inline source ending in `.js`, stop-before-evaluation
  pure-JS loop, and oversized array results.
- `Tests/AutoSDKTests/AutoHTTPProtocolTests.m`: in-process `NSURLProtocol`
  HTTP coverage for the shared session.

### Notes

- iOS source changes are validated by the repository static checks
  (`npm run verify`) and the Node tool tests; compilation and simulator
  tests run on macOS via `.github/workflows/ios-build.yml`.

## 1.1.2

Version metadata (`AutoSDKVersionString`, CocoaPods `AutoSDK.podspec`,
`package.json`) is aligned at 1.1.2. Earlier release history is not tracked
in this file.
