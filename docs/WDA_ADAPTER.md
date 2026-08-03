# WDA HTTP Adapter

`AutoWDAHTTPAdapter` is the SDK-side client for a separately installed
WebDriverAgent-compatible Runner. It does not link XCTest, private Apple
frameworks, or a testmanager client into the host app.

## Configuration

```objc
AutoWDAHTTPAdapter *adapter = [[AutoWDAHTTPAdapter alloc]
    initWithBaseURL:[NSURL URLWithString:@"http://127.0.0.1:8100"]
    applicationBundleId:@"com.example.target"
    timeout:15];
adapter.sourceCacheDuration = 0.15;
adapter.sourceMaxBytes = 16 * 1024 * 1024;
adapter.sourceMaxNodes = 50000;
adapter.screenshotCacheDuration = 0; // Keep zero when the UI is animating.
[AutoEngine.sharedEngine setAutomationAdapter:adapter];
```

The adapter accepts only `http` and `https`. Redirects are restricted to the
same scheme, host, and port as the configured URL. A WDA session is created on
demand and rebuilt once when the Runner reports `invalid session id`.
Selector-backed element handles are also re-located once after a
`stale element reference`; raw handles without a recovery selector are not.

## Supported script operations

The adapter supports selector lookup (`accessibility id`, XPath, iOS predicate,
and class chain), attributes, bounds, click, coordinate click, double click,
long press, swipe, text input, screenshot, image/color matching, multi-color
matching, Vision OCR, and node enumeration.

Application lifecycle helpers are exposed as:

```javascript
auto.app.launch("com.example.target");
auto.app.activate("com.example.target");
auto.app.terminate("com.example.target");
const state = auto.app.state("com.example.target");
```

The same methods are available as `auto.launchApp`, `auto.activateApp`,
`auto.terminateApp`, and `auto.appState`.

## Resource controls

Parent/child/sibling traversal uses a short-lived parsed `/source` snapshot.
The cache is invalidated after touch, input, scrolling, app lifecycle changes,
and session restarts, then released automatically. Set `sourceCacheDuration`
to `0` when a runner updates its hierarchy continuously.

`screenshotCacheDuration` is disabled by default. It can be set to a small
value (for example `0.05`) for scripts that read several pixels from the same
frame. It is also invalidated after UI actions. Image buffers are bounded to
avoid an unexpected large WDA response causing a large allocation.
Raw WDA JSON responses are cancelled when their known transfer size exceeds
40 MiB and checked again before parsing. Decoded screenshot payloads are
limited to 24 MiB before image processing begins. Session creation, screenshot,
and source fetches are single-flight, and cache writes are rejected when an
intervening UI operation changes the cache generation.

`/source` parsing is bounded to 16 MiB and 50,000 nodes by default (maximum
configurable values are 32 MiB and 200,000 nodes). Oversized or malformed
snapshots return a normal SDK error instead of retaining a partial tree.

For image matching, `findImage` accepts `region`, `step`, `verifyStep`,
`threshold`, and `maxCandidates`. The default candidate budget is 200,000;
the default origin step is one pixel, and the budget can be raised to
5,000,000. The matcher increases its sampling step for larger searches while
preserving final full-resolution verification around promising candidates. Image and
single-color ROI searches only allocate a pixel buffer for that ROI.

`findColor` and `findMultiColor` use the same 200,000 default candidate budget
and accept `maxCandidates` up to 5,000,000. They also enforce an actual pixel
comparison budget (`maxComparedPixels`, 50 million by default and 500 million
maximum), which includes every multi-color offset comparison. A bounded miss
returns `truncated`, `scannedCandidates`, `comparedPixels`, and `effectiveStep`
metadata. The multi-color matcher precompiles up to 256 offsets before
scanning, and `compareColors` accepts up to 4,096 points.

WDA visual work is serialized across script and Inspector requests so two
image/OCR jobs cannot allocate their maximum working sets concurrently. Stop
cancellation is generation-based: it covers tasks created concurrently with
the stop request, cooperatively interrupts pixel loops, and cancels active
Vision requests.

Vision OCR accepts `mode: "fast" | "accurate"` (the legacy `accurate` field is
still supported), `languageCorrection`, `languages`, `customWords`,
`minimumTextHeight`, and `maxResults`. Fast mode disables language correction
by default to reduce latency; set it explicitly when needed. `maxResults`
defaults to and is capped at 1,000.

WDA settings can be applied after session creation:

```objc
adapter.sessionSettings = @{
    @"shouldUseCompactResponses": @YES,
    @"animationCoolOffTimeout": @0.2
};
adapter.ignoresUnsupportedSessionSettings = YES;
```

The settings endpoint is optional for compatibility with older WDA-compatible
runners. Set `ignoresUnsupportedSessionSettings` to `NO` when a deployment must
enforce the requested settings. Concurrent requests share one settings update;
each update is tagged with a configuration generation, so a delayed response
cannot mark newer settings as applied. Explicit `applySessionSettings` calls do
not send a duplicate request when the current generation is already active. Bare
HTTP 404, 405, and 501 responses from the optional endpoint are treated as an
unsupported settings endpoint (except a response identified as an invalid
session), so older runners do not pay the failed-request cost on every action.

## Important limits

- The Runner must be separately signed, installed, and actually running on the
  device. TrollStore signing does not create XCTest or WDA privileges.
- Element handles are descriptive and may become invalid after a snapshot or
  session restart. The adapter re-finds selector-backed handles when possible.
- Parent, child, and sibling traversal is derived from the `/source` XML
  snapshot. Returned nodes are marked `sourceDerived` and use absolute XPath;
  they are not stable WDA element handles and should be re-fetched after the
  UI changes.
- Image matching is an SDK-side pixel matcher, not OpenCV. Add a dedicated
  OpenCV-backed adapter when scale/rotation-invariant matching is required.
