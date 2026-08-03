# Runtime performance

The SDK keeps the default automation behavior compatible while reducing
temporary allocations and repeated WDA work.

## What is optimized

- WDA `/source` is parsed once for the short parent/child/sibling query window.
  The tree is invalidated after touch, input, scrolling, app lifecycle changes,
  and session restarts, and is released automatically when the window expires.
- WDA window dimensions are reused for two seconds. This avoids an extra
  `/window/size` request for every color, image, or OCR operation.
- WDA screenshot reuse is opt-in (`screenshotCacheDuration`) because animated
  screens can make a cached frame incorrect.
- Screenshot, source-tree, and window-size cache ages now begin after a
  successful capture/request. Slow WDA calls therefore do not consume the
  cache lifetime before the value becomes usable. Changing a cache duration
  immediately releases the previous cached value.
- Vision, PNG decoding, source parsing, and pixel matching run inside local
  autorelease pools. This keeps temporary UIKit/CoreGraphics objects from
  accumulating until the next event-loop turn.
- UIKit visual operations consume the renderer's `UIImage` directly. PNG
  encoding is deferred until a script explicitly requests `screenshot()`,
  avoiding an encode/decode round trip for image, color, and OCR calls.
- UIKit capture is serialized on the main thread, while image/color scans and
  Vision OCR continue on the caller's background queue. This keeps expensive
  pixel and recognition work from blocking UI event delivery.
- Image matching caps the combined template plus screenshot RGBA working set
  at 64 MiB and rejects templates larger than the ROI before allocating pixel
  buffers. Matching exits early when the requested similarity is no longer
  possible. File-backed templates use
  `imageWithContentsOfFile:` and a dedicated 32-entry/32 MiB `NSCache`, so
  repeated templates avoid disk decoding without entering UIKit's unbounded
  global `imageNamed:` cache. File size and modification time are part of the
  key, so replacing a template invalidates it automatically.
- Script logs are bounded to 1,000 entries, 16 KB per message, and 8 MiB of
  retained message text by default. `maxLogEntries`, `maxLogMessageLength`,
  and `maxLogBytes` have hard caps of 10,000, 256 KiB, and 32 MiB so an
  accidental diagnostic configuration cannot exhaust phone memory.
- The JavaScript timer queue accepts at most 10,000 active timers and clamps a
  delay/interval to one hour, preventing accidental loops from retaining an
  unbounded number of callbacks. Clearing a queued timer removes its cancellation
  marker immediately, so repeated create/clear cycles do not grow retained state.
- Automation, file, storage, HTTP, device, image, app, console, native extension,
  and timer entry points check script cancellation before crossing the bridge.
  A loop that repeatedly calls SDK APIs therefore exits on its next call after
  `stopScript`; JavaScript that never calls any SDK API remains subject to the
  public JavaScriptCore hard-interruption limitation.
- Regex selectors use a bounded 128-entry `NSCache` in both adapters, avoiding
  recompilation for every view or source-tree node. Invalid expressions are
  cached as failures and patterns over 1,024 characters are rejected, avoiding
  repeated parser work during large-tree scans.
- UIKit single-node, multi-node, snapshot, and scroll-view fallback traversals
  cap both visited views and temporary DFS stack growth. A high-fanout view
  hierarchy therefore cannot bypass the node budget with one large expansion.
- Template matching starts with a one-pixel origin step, limits coarse
  candidates to 200,000 by default, and accepts `maxCandidates` up to
  5,000,000. A region is searched in pixel coordinates, and the adaptive step
  only changes the coarse scan when the region exceeds the budget; promising
  candidates are still verified at the requested threshold. Region-limited image and
  single-color searches allocate an RGBA buffer for the ROI instead of the
  complete screenshot. Image and color scan steps are bounded to 1-1,024 to
  prevent integer overflow from malformed options.
  Coarse and exact verification calls now share one hard candidate budget;
  exact verification is capped at 4,096 calls and responses expose
  `coarseCandidates`, `verifiedCandidates`, and `truncated`. Transparent PNG
  template pixels are ignored and partial alpha is weighted after
  unpremultiplication.
  Matching now also has a worst-case comparison budget (`maxComparedPixels`,
  50 million by default and 500 million hard maximum). If adaptive stepping or
  the pixel budget leaves positions unchecked, a failed result reports
  `truncated: true` instead of claiming an exhaustive miss.
- `findColor` and `findMultiColor` default to a 200,000 `maxCandidates` budget
  (configurable from 1,000-5,000,000) and a 50 million actual-comparison budget
  (`maxComparedPixels`, maximum 500 million). Multi-color comparisons count
  the base pixel and every checked offset, so a 256-offset pattern cannot turn
  one candidate budget into unbounded CPU work. Bounded misses report
  `truncated`, `scannedCandidates`, `comparedPixels`, and `effectiveStep`.
  Multi-color offsets are parsed and converted to pixel values once before scanning.
  `compareColors` accepts at most 4,096 points and `findMultiColor` at most 256
  offsets, bounding script-controlled CPU and temporary allocation.
- Vision OCR supports `mode: "fast"` and `mode: "accurate"`. Fast mode turns
  language correction off unless `languageCorrection` is explicitly supplied.
  `maxResults` defaults to and is capped at 1,000 to prevent an unusually dense
  frame from growing the result array without bound. OCR also rejects a request image over
  the 64 MiB pixel budget (after ROI cropping). Invalid language/custom-word
  entries are ignored, and Vision exceptions are converted to SDK errors.
- WDA source parsing uses an explicit traversal stack and per-parent type
  counters. This avoids repeated sibling scans and deep recursive calls. The
  source response is bounded to 16 MiB and 50,000 nodes by default, with
  configurable maximums of 32 MiB and 200,000 nodes. XPath strings are kept as
  path components and materialized only when a selector or returned node needs
  them, reducing retained memory for deep trees. SDK-generated absolute XPath
  handles are resolved one hierarchy level at a time instead of scanning every
  node.
- UIKit node handles are stored in a strong-key/weak-view registry. Reusing a
  returned node resolves its live view directly instead of scanning the full
  hierarchy and assigning handles to unrelated views. Full UIKit hierarchy
  searches use an explicit traversal stack, avoiding native stack exhaustion
  on unusually deep view trees.
- WDA JSON responses are cancelled when their known transfer size exceeds 40
  MiB and are capped again before parsing. Decoded WDA screenshots are limited
  to 24 MiB. Script/debug screenshot output defaults to 16 MiB with a 20 MiB
  hard configuration maximum, while the WebSocket response limit is 32 MiB.
- WDA session creation, screenshots, and source requests are single-flight.
  State locks are never held across session-creation HTTP waits, and cache
  generation checks prevent a response captured before a click/input from
  being committed after that operation invalidates the cache.
- WDA session settings are single-flight and configuration-generation aware.
  Concurrent session preparation waits on the same application lock; a late
  response for old settings is discarded and the newest generation is applied
  before the waiter proceeds.
- Image/color/OCR processing is serialized per adapter across scripts and
  Inspector requests. Cancellation generations close the WDA task-creation
  registration race, are polled every 4,096 local pixel comparisons, and cancel
  registered Vision requests. UIKit captures the frame before waiting for its
  processing lock to avoid a background-to-main-thread lock inversion.
  WDA composite visual and element requests carry their original cancellation
  generation into nested screenshot, window-size, session-recovery, and
  settings calls, so a stop between subrequests cannot start fresh network work.
- Script APIs check cancellation in both the JavaScript wrapper and every
  Objective-C bridge entry. If a stop lands between those checks, the native
  gate injects a JavaScript exception immediately instead of allowing the
  script to continue after a cancelled adapter call.
- UIKit debug screenshots capture the view on the main thread, then perform
  PNG and base64 encoding on the background adapter queue. Hidden UIKit
  subtrees are pruned from snapshots, and selector searches enforce a bounded
  `maxVisited` budget.
- Each debug peer accepts at most eight in-flight requests and one heavy
  screenshot/node/pixel/image/OCR request, preventing rapid Inspector refreshes from
  multiplying large temporary buffers.
- Script HTTP request bodies and responses default to 10 MiB limits with 64 MiB
  hard maximums. Normal response chunks are checked before being appended;
  callers can disable unused UTF-8, base64, and JSON representations.
  `http.downloadFile` uses a temporary download file and atomic sandbox install
  instead of routing the payload through JavaScript as base64. A completed
  transfer is staged first and installed only after the script thread confirms
  it was not cancelled, preventing a late callback from writing after timeout.
  Completed normal responses transfer their delegate buffer directly instead
  of copying a second full-size `NSData` before representation conversion.
- Remote scripts download to a temporary file instead of accumulating in a
  data-task buffer. Their default 5 MiB limit has a 64 MiB hard maximum; known
  oversized transfers are cancelled before the file is decoded as UTF-8.
- Script file reads check metadata before mapping data; text/base64 writes are
  checked before and after encoding. Reads and writes default to 10 MiB with
  64 MiB hard maximums. Copy, recursive removal, and directory listing have
  configurable byte/item budgets so one operation cannot enumerate or copy an
  unbounded tree while holding the file mutation lock. Named storage has a
  16 MiB hard maximum.
- The debug WebSocket transport composes a small frame header with the existing
  JSON `NSData` through `dispatch_data_create_concat`, avoiding a complete
  payload copy for screenshot and other large debug responses.
- `auto.waitFor` checks immediately, then uses a bounded 50 ms to 250 ms
  backoff. Set `waitPollInterval` in `AutoEngine` config to change the initial
  interval while keeping the overall timeout unchanged. WDA existence checks
  use the single-result `/element` endpoint, avoiding repeated allocation and
  transfer of every matching element during polling.
- Coordinate and duration arguments are checked for finite values in both the
  JavaScript bridge and adapters. Invalid `NaN`/`Infinity` input is rejected
  before CoreGraphics, UIKit animation, or WDA JSON serialization.

## Optional WDA settings

`AutoWDAHTTPAdapter.sessionSettings` is sent to `/appium/settings` after each
session is created. Useful settings are runner-dependent. For example:

```objc
adapter.sessionSettings = @{
    @"shouldUseCompactResponses": @YES,
    @"animationCoolOffTimeout": @0.2
};
```

Unsupported settings are ignored by default. Set
`ignoresUnsupportedSessionSettings = NO` when deployment consistency is more
important than compatibility with older WDA-compatible runners. Do not enable
snapshot depth/children limits without testing selectors used by the script
set, because those limits can hide nodes.

## Measurement

Apple recommends measuring energy and memory with Xcode Instruments on a real
device. The repository cannot perform that measurement on Windows without
Xcode, so the remaining numbers must be collected after TrollStore/WDA is
installed on the target iPhone. Record idle CPU, peak resident memory during
OCR/findImage, and request counts for repeated node traversal before and after
changing the cache durations.

References:

- https://developer.apple.com/library/archive/documentation/Performance/Conceptual/EnergyGuide-iOS/
- https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/MemoryMgmt/Articles/mmAutoreleasePools.html
- https://github.com/appium/WebDriverAgent
- https://github.com/AirtestProject/iOS-Tagent
- https://github.com/Tencent/MLeaksFinder (development-time leak detection)
- https://github.com/SDWebImage/SDWebImage (bounded image-cache patterns)
