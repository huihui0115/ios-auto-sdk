# Script execution

This document describes how `AutoEngine` turns an input string into a
finished script run: how the input is classified, how scripts are executed,
how timeouts and cancellation interrupt them, how timers are drained, and
what the completion payload looks like. See `README.md` for integration and
`docs/PERFORMANCE.md` for the runtime's resource budgets.

## Run lifecycle

`runScript:` is single-flight: only one script can execute at a time, and a
second call while a run is active fails immediately with
`AutoSDKErrorAlreadyRunning`. Scripts run on a dedicated serial queue
(`com.autosdk.javascript`) so JavaScript never blocks the UI thread; UIKit
adapter calls are marshalled to the main thread by the SDK. The completion
block is always delivered on the main queue.

A run has four phases:

1. **Load** – `loadScript` classifies the input (URL, file, bundle resource,
   or inline source) and produces the UTF-8 source text.
2. **Bootstrap** – a fresh `JSContext` is created and the private bootstrap
   installs the global `auto`, `http`, `file`, `storage`/`storages`,
   `device`, `image`, `app`, `console` and timer APIs.
3. **Evaluate** – the user source runs. Bridge entry points check the stop
   flag and a watchdog enforces `scriptTimeout`.
4. **Drain timers** – after the top-level source returns, queued
   `setTimeout`/`setInterval` callbacks run until the queue is empty, the
   script is stopped, or the budget is exhausted.

## Input classification

`runScript:` accepts one string that may be:

- an `http://` or `https://` URL (requires `allowRemoteScripts: @YES`),
- a `file://` URL,
- an existing filesystem path,
- a bundle resource name (resolved with `pathForResource:ofType:`),
- JavaScript source text.

The classification order is:

| Input shape | Result |
| --- | --- |
| Empty string | `AutoSDKErrorScriptNotFound` ("Script source is empty.") |
| Contains `://` with a non-http(s)/file scheme | `AutoSDKErrorScriptReadFailed` (unsupported scheme) |
| `http(s)://` URL | Remote download (see below) |
| `file://` URL or existing path | File read, UTF-8, `maxScriptBytes` enforced |
| Bundle resource | Resource read, `maxScriptBytes` enforced |
| Path-like but does not exist | `AutoSDKErrorScriptNotFound` ("Script path does not exist.") |
| Everything else | Treated as JavaScript source text |

**Path detection.** A string that does not exist on disk is only treated as a
path when it clearly looks like one: it starts with `/`, `./`, `../`, `~/`
or `file:`, contains a `/` or `\\` separator together with alphabetic
characters and no JavaScript syntax characters (`(){};=+*%<>!?&|^'"\`,`),
or is a bare `.js` name with no whitespace and no JavaScript syntax
characters. A `.js` suffix alone never rejects inline source: a trailing
comment such as `// main.js` still evaluates as JavaScript. Valid one-line
source such as `1/2`
(division) or `answer: { 42; }` running as code while returning a precise
"path not found" error for `missing.js` or `scripts/nested.js`.

### Remote scripts

Remote loading is disabled by default. With `allowRemoteScripts: @YES`:

- The host must be in `allowedRemoteScriptHosts` (or `allowedNetworkHosts`)
  when a list is configured.
- `remoteScriptTimeout` bounds the download (default 30 s, hard cap 120 s).
- The download is streamed to a temporary file with a size monitor; exceeding
  `maxScriptBytes` cancels it (`AutoSDKErrorScriptTooLarge`).
- Redirects follow the same policy as `invokeHTTP`: restricted to the
  configured host list when one exists, otherwise any `http`/`https` host;
  HTTPS-to-HTTP downgrades and non-http(s) schemes are always rejected.
- Non-2xx status, invalid UTF-8, or a late cancellation surface as
  `AutoSDKErrorScriptReadFailed` / `AutoSDKErrorScriptCancelled`.

## Timeouts and interruption

**`scriptTimeout`** (seconds, default 300, hard cap 3600) is the total
wall-clock budget for one run, **including timer callbacks**. Two mechanisms
enforce it:

- **Watchdog.** A utility dispatch waits on a completion semaphore for the
  budget; on expiry it requests a stop and cancels in-flight adapter work.
  The run completes with `AutoSDKErrorScriptTimeout` and the engine remains
  usable for the next run.
- **JavaScriptCore execution-time limit** (`interruptibleScripts`, default
  YES). The SDK installs `JSContextGroupSetExecutionTimeLimit` before
  evaluating the source and keeps it installed while timers drain, so even a
  pure-JavaScript loop such as `while(true){}` – including inside a timer
  callback – is interrupted at the budget. The symbols are weak-linked: on
  runtimes that do not export them the limit is skipped and pure JS loops can
  only be interrupted at SDK bridge boundaries.

**`stopScript`** sets the stop flag, cancels the active network task and
adapter operations, and requests a hard interruption so a running pure-JS
loop exits within milliseconds. The completion then reports
`AutoSDKErrorScriptCancelled`. A stopped engine is immediately ready for the
next `runScript:`.

All SDK bridge entry points (automation, HTTP, file, storage, device, app,
console, native extensions and timers) check the stop flag before crossing
the bridge, so a loop that repeatedly calls SDK APIs exits on its next call.

## Timers

The bootstrap provides `setTimeout`/`clearTimeout` (aliases
`cancelTimeout`) and `setInterval`/`clearInterval` (aliases
`cancelInterval`). Timers are scheduled in a bounded priority heap:

- at most 10,000 active timers (`RangeError` beyond that),
- delays/intervals are clamped to one hour,
- a timer can cancel itself from inside its callback,
- cancelled timers never fire and leave no cancellation markers behind.

A run completes only after the timer queue drains, so a pending
`setTimeout` keeps the run alive. `setInterval` therefore runs until
`stopScript` or `scriptTimeout`. Intervals that only call SDK APIs are
also bounded by the same budgets.

## Result and logs

A successful completion receives a dictionary with:

| Key | Value |
| --- | --- |
| `success` | `@YES` |
| `value` | The evaluated JavaScript value converted to Objective-C (or `NSNull`/`nil`); oversized results are replaced with an `__autosdkTruncated` marker |
| `logs` | Array of `{"level": "log"|"warn"|"error", "message": "..."}` entries |
| `durationMs` | Wall-clock duration of the run |

**Result bounds.** The conversion of `value` is bounded to 24 nesting
levels, 50,000 container entries and 1 MiB per string. Oversized top-level
arrays and strings are detected before conversion; nested nodes that exceed a
budget are replaced during the walk. Replaced nodes are dictionaries with
`__autosdkTruncated: true`, `reason` and the offending
`count`/`length`/`depth`, so a script returning `new Array(1e8)`
cannot force an unbounded bridge allocation.

On failure the completion receives `nil` result and an `NSError` in
`AutoSDKErrorDomain`; the same `logs` array is attached under
`error.userInfo[@"logs"]`.

## Error codes

| Code | Meaning |
| --- | --- |
| `AutoSDKErrorInvalidConfiguration` | Invalid option types or values in the config snapshot |
| `AutoSDKErrorAlreadyRunning` | `runScript:` called while another script is active |
| `AutoSDKErrorScriptNotFound` | Empty input or a path-like string that does not exist |
| `AutoSDKErrorScriptReadFailed` | Remote/file read failure, unsupported scheme, non-UTF-8 |
| `AutoSDKErrorScriptTooLarge` | Input or remote download exceeds `maxScriptBytes` |
| `AutoSDKErrorScriptTimeout` | `scriptTimeout` budget exhausted (watchdog or JSC limit) |
| `AutoSDKErrorScriptCancelled` | `stopScript` (or a stop requested by the debug server) |
| `AutoSDKErrorJavaScriptException` | Uncaught exception thrown by the script |
| `AutoSDKErrorAutomationUnavailable` | Adapter does not support the requested operation |
| `AutoSDKErrorAutomationFailed` | Adapter reported a failure for the operation |
| `AutoSDKErrorWaitTimeout` | `waitFor` polling budget exhausted |
| `AutoSDKErrorElementNotFound` | A node lookup matched nothing |
| `AutoSDKErrorNetworkDisabled` | `allowNetwork` is off |
| `AutoSDKErrorNetworkFailed` | HTTP request/download failure or timeout |
| `AutoSDKErrorFileAccessDenied` | File operation outside the configured sandbox |
| `AutoSDKErrorFileOperationFailed` | File read/write/copy failure |
| `AutoSDKErrorStorageFailed` | Named storage failure (including corrupt recovery) |
| `AutoSDKErrorDebugServerFailed` | Debug server could not start |
| `AutoSDKErrorDebugUnauthorized` | Debug request failed token authentication |

## Configuration reference (execution)

| Key | Default | Meaning |
| --- | --- | --- |
| `scriptTimeout` | 300 | Total seconds budget, clamped to 3600; includes timers |
| `interruptibleScripts` | YES | Install the JSC execution-time limit for pure-JS loops |
| `maxScriptBytes` | 5 MB | Source/remote size limit (hard cap 64 MB) |
| `allowRemoteScripts` | NO | Permit `http(s)://` script loading |
| `allowedRemoteScriptHosts` | – | Optional exact host allowlist for remote scripts |
| `remoteScriptTimeout` | 30 | Remote download timeout in seconds (cap 120) |
| `waitPollInterval` | 0.05 | `waitFor` polling interval, clamped 0.01–0.25 s |
| `maxLogEntries` | 1000 | Retained console entries (cap 10,000) |
| `maxLogMessageLength` | 16 KB | Per-message cap (cap 256 KB) |
| `maxLogBytes` | 8 MB | Total retained log bytes (cap 32 MB) |
| `debugLogging` | NO | Also forward console output to the system log |

File, storage, HTTP and adapter configuration are documented in
`docs/FILE_STORAGE_DEVICE_API.md`, `docs/HTTP_API.md` and
`docs/UIKIT_ADAPTER.md` / `docs/WDA_ADAPTER.md`.
