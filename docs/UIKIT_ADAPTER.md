# UIKit Adapter

`AutoUIKitAdapter` is a public-API implementation for automating the host
application's own UIKit view hierarchy. It is useful for embedded workflows,
demo applications, and development builds that do not require cross-app access.

```objc
AutoEngine *engine = AutoEngine.sharedEngine;
AutoUIKitAdapter *adapter = [AutoUIKitAdapter new];
adapter.screenshotCacheDuration = 0; // Use a small value only for static screens.
[engine setAutomationAdapter:adapter];
```

## Selectors

A string matches `accessibilityIdentifier`, `accessibilityLabel`, or visible
text. An object combines exact, regex, state, structure and bounds fields:

```javascript
auto.click({id: "login-button"});
auto.input({label: "Email", type: "TextField"}, "dev@example.com");
const title = auto.getText({value: "Welcome", type: "StaticText"});
const buttons = auto.findElements({labelMatch: "Sign.*", enabled: true, maxResults: 20});
```

Friendly types include `Button`, `StaticText`, `TextField`, `TextView`,
`Image`, `Switch`, `Slider`, `Cell`, and `ScrollView`. UIKit class names are
also accepted.

## Supported operations

- `click`: activates `UIControl`, `UISwitch`, or an accessibility action.
- `input`: updates `UITextField` and `UITextView` and emits change events.
- `swipe`: scrolls the scroll view beneath the start coordinate.
- `screenshot`: captures the active application window as PNG.
- `ocr`: runs an on-device Vision text request. Use `mode: "fast"` for lower
  latency or `mode: "accurate"` for the legacy precise behavior; `maxResults`
  defaults to and is capped at 1,000 to bound result allocation.
- `findImage`: performs bounded template similarity matching using CoreGraphics.
  Relative paths resolve to a bundled resource first, then to the configured
  AutoSDK file root. Absolute paths are accepted only inside one of those two
  roots.
- `findColor`: scans RGBA pixels with a configurable tolerance. Region-limited
  searches allocate a pixel buffer for the region rather than the full frame;
  the scan defaults to 200,000 candidate origins and 50 million actual pixel
  comparisons. `maxCandidates` and `maxComparedPixels` can tune those limits.
- `getPixelColor`, `compareColors`, and `findMultiColor`: use one screenshot
  per operation and return point coordinates. Multi-color offsets are parsed
  once before scanning (up to 256); comparisons accept up to 4,096 points.
- node queries: `findElement`, `exists`, `getAttribute`, `getBounds`,
  `getChildren`, `getParent`, and `scrollIntoView`. Hierarchy scans use an
  explicit stack so deeply nested views cannot overflow the native call stack.

Internal image, color, and OCR operations work directly from the rendered
`UIImage`; they do not encode and immediately decode an intermediate PNG.
Pixel-buffer and Vision processing is serialized across script and Inspector
requests to avoid concurrent 64 MiB working sets. Stopping a script cancels
queued scans, checks active pixel loops cooperatively, and cancels an active
Vision request.

Screenshot reuse is disabled by default. When enabled for a static screen, the
short cache is invalidated after clicks, input, swipes, and scrolling.

UIKit has no public API for synthesizing arbitrary long-press touches or
driving another application. `longClick` and cross-app operations therefore
return explicit errors; use a host-provided WDA adapter for those operations.
`clickPoint` and `doubleClickPoint` activate the hit-tested host control; they
do not claim to synthesize low-level touch events. Inspect this distinction at
runtime with `auto.capabilities()`.
