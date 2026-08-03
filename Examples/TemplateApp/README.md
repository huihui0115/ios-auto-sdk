# AutoSDK Template App

Generate and open the example project on macOS:

```bash
brew install xcodegen
cd Examples/TemplateApp
xcodegen generate
open AutoSDKTemplate.xcodeproj
```

The generated project links the repository's local Swift package, bundles the
scripts in `Scripts`, and presents a script list with run, stop, and log views.

The following is the minimal integration used by a template application:

```objc
@import AutoSDK;

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    AutoEngine *engine = AutoEngine.sharedEngine;
    [engine setAutomationAdapter:[AutoUIKitAdapter new]];
    NSString *debugToken = [NSUserDefaults.standardUserDefaults stringForKey:@"AutoSDKDebugToken"];
    if (debugToken.length < 16) {
        debugToken = NSUUID.UUID.UUIDString;
        [NSUserDefaults.standardUserDefaults setObject:debugToken forKey:@"AutoSDKDebugToken"];
    }
    [engine configureWithConfig:@{
        @"scriptTimeout": @300,
        @"debugServerEnabled": @YES,
        @"debugToken": debugToken,
        @"debugAllowWiFi": @YES,
        @"allowFileAccess": @YES,
        @"allowFileWrite": @YES
    }];
    [engine registerNativeMethod:@"toast" handler:^id(NSArray *args) {
        NSLog(@"toast: %@", args.firstObject);
        return @YES;
    }];
    return YES;
}
```

`AutoUIKitAdapter` automates only views owned by this application. Replace it
with a separately signed XCTest/WDA adapter when cross-application automation
is required.

The template can select the adapter without changing `AppDelegate.m`. Set
`AutoSDKAdapter` to `WDA` in `App/Info.plist` (or in `NSUserDefaults` at launch),
then configure `AutoSDKWDAURL`, `AutoSDKWDABundleId`, and
`AutoSDKWDATimeout`. The default WDA URL is `http://127.0.0.1:8100`. The
template still needs a separately signed WDA-compatible Runner running on the
phone; selecting `WDA` does not embed XCTest or create that Runner.

Call `runScript:completion:` from a button or a development-only script list.
Never expose script execution or a debug transport in a production App Store
build unless the app's security and distribution model explicitly allows it.

The bundled template enables `AutoSDKDebugAllowWiFi` and includes the required
`NSLocalNetworkUsageDescription`. On a trusted Wi-Fi network its log panel
shows the phone's `ws://` URL and the installation token. Keep the token in a
development-only UI or protected storage; do not write it to the system log. Set
`AutoSDKDebugAllowWiFi` to `false` to restore loopback-only USB-tunnel mode.
Direct Wi-Fi debugging is authenticated but unencrypted and is intended only
for development.

For a local PC debug client, enable `debugServerEnabled`, set a random
`debugToken`, and send authenticated WebSocket JSON commands such as:

```json
{"id":"1","token":"<debugToken>","type":"run","script":"auto.sleep(100)"}
```
