# AutoSDK

`AutoEngine` is the only class a host app needs to know. The SDK owns script
loading, JavaScriptCore execution, cancellation, and the JavaScript `auto`
facade. UI automation is provided by an `AutoAutomationAdapter` supplied by
the host app.

The adapter boundary is deliberate: XCTest/WDA internals are private and vary
by Xcode/iOS version. Keep that integration in a separately signed target and
keep this runtime deterministic and testable.
