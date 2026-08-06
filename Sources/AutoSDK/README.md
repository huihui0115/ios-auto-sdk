# AutoSDK

`AutoEngine` is the only class a host app needs to know. The SDK owns script
loading, JavaScriptCore execution, cancellation, and the JavaScript `auto`
facade. UI automation is provided by an `AutoAutomationAdapter` supplied by
the host app.

The adapter boundary is deliberate: system-wide automation uses private
symbols resolved at runtime inside `AutoBuiltinAdapter` (built-in no-WDA), so
the SDK links no private frameworks and stays deterministic and testable.
`AutoUIKitAdapter` covers host-app-only automation with public APIs.
