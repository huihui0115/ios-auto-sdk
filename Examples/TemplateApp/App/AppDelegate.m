#import "AppDelegate.h"
#import "ScriptListViewController.h"
#import <AutoSDK/AutoSDK.h>

static id<AutoAutomationAdapter> AutoTemplateAutomationAdapter(void) {
    NSBundle *bundle = NSBundle.mainBundle;
    NSString *configuredName = [NSUserDefaults.standardUserDefaults stringForKey:@"AutoSDKAdapter"];
    if (configuredName.length == 0) configuredName = [bundle objectForInfoDictionaryKey:@"AutoSDKAdapter"];
    BOOL useWDA = configuredName.length > 0 &&
        ([configuredName caseInsensitiveCompare:@"WDA"] == NSOrderedSame ||
         [configuredName caseInsensitiveCompare:@"WDAHTTP"] == NSOrderedSame);
    if (useWDA) {
        NSString *urlString = [NSUserDefaults.standardUserDefaults stringForKey:@"AutoSDKWDAURL"];
        if (urlString.length == 0) urlString = [bundle objectForInfoDictionaryKey:@"AutoSDKWDAURL"];
        NSURL *url = [NSURL URLWithString:urlString.length > 0 ? urlString : @"http://127.0.0.1:8100"];
        NSString *bundleId = [NSUserDefaults.standardUserDefaults stringForKey:@"AutoSDKWDABundleId"];
        if (bundleId.length == 0) bundleId = [bundle objectForInfoDictionaryKey:@"AutoSDKWDABundleId"];
        NSTimeInterval timeout = [NSUserDefaults.standardUserDefaults doubleForKey:@"AutoSDKWDATimeout"];
        if (timeout <= 0) timeout = [[bundle objectForInfoDictionaryKey:@"AutoSDKWDATimeout"] doubleValue];
        if (timeout <= 0) timeout = 15;
        NSString *scheme = url.scheme.lowercaseString;
        if (url.host.length > 0 && ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"])) {
            AutoWDAHTTPAdapter *adapter = [[AutoWDAHTTPAdapter alloc] initWithBaseURL:url
                                                                   applicationBundleId:bundleId
                                                                                timeout:timeout];
            id sourceCache = [NSUserDefaults.standardUserDefaults objectForKey:@"AutoSDKWDASourceCacheDuration"] ?: [bundle objectForInfoDictionaryKey:@"AutoSDKWDASourceCacheDuration"];
            if ([sourceCache isKindOfClass:NSNumber.class]) adapter.sourceCacheDuration = [sourceCache doubleValue];
            id screenshotCache = [NSUserDefaults.standardUserDefaults objectForKey:@"AutoSDKWDAScreenshotCacheDuration"] ?: [bundle objectForInfoDictionaryKey:@"AutoSDKWDAScreenshotCacheDuration"];
            if ([screenshotCache isKindOfClass:NSNumber.class]) adapter.screenshotCacheDuration = [screenshotCache doubleValue];
            id settings = [NSUserDefaults.standardUserDefaults objectForKey:@"AutoSDKWDASettings"] ?: [bundle objectForInfoDictionaryKey:@"AutoSDKWDASettings"];
            if ([settings isKindOfClass:NSDictionary.class]) adapter.sessionSettings = settings;
            id ignoreSettings = [NSUserDefaults.standardUserDefaults objectForKey:@"AutoSDKWDAIgnoreUnsupportedSettings"] ?: [bundle objectForInfoDictionaryKey:@"AutoSDKWDAIgnoreUnsupportedSettings"];
            if ([ignoreSettings isKindOfClass:NSNumber.class]) adapter.ignoresUnsupportedSessionSettings = [ignoreSettings boolValue];
            return adapter;
        }
        NSLog(@"[TemplateApp] Invalid WDA configuration; falling back to AutoUIKitAdapter.");
    }
    AutoUIKitAdapter *adapter = [AutoUIKitAdapter new];
    id screenshotCache = [NSUserDefaults.standardUserDefaults objectForKey:@"AutoSDKScreenshotCacheDuration"] ?: [bundle objectForInfoDictionaryKey:@"AutoSDKScreenshotCacheDuration"];
    if ([screenshotCache isKindOfClass:NSNumber.class]) adapter.screenshotCacheDuration = [screenshotCache doubleValue];
    return adapter;
}

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    AutoEngine *engine = AutoEngine.sharedEngine;
    [engine setAutomationAdapter:AutoTemplateAutomationAdapter()];
    NSMutableDictionary *config = [@{ @"scriptTimeout": @300,
                                      @"maxScriptBytes": @(5 * 1024 * 1024),
                                      @"allowRemoteScripts": @NO } mutableCopy];
#if DEBUG
    NSBundle *bundle = NSBundle.mainBundle;
    NSString *debugToken = [NSUserDefaults.standardUserDefaults stringForKey:@"AutoSDKDebugToken"];
    if (debugToken.length < 16) {
        debugToken = NSUUID.UUID.UUIDString;
        [NSUserDefaults.standardUserDefaults setObject:debugToken forKey:@"AutoSDKDebugToken"];
    }
    id configuredWiFi = [NSUserDefaults.standardUserDefaults objectForKey:@"AutoSDKDebugAllowWiFi"];
    if (!configuredWiFi) configuredWiFi = [bundle objectForInfoDictionaryKey:@"AutoSDKDebugAllowWiFi"];
    BOOL allowWiFi = [configuredWiFi boolValue];
    NSUInteger debugPort = 9001;
    NSLog(@"[TemplateApp] AutoSDK debug token is available in the app UI.");
    [NSUserDefaults.standardUserDefaults setBool:allowWiFi forKey:@"AutoSDKDebugWiFiActive"];
    [NSUserDefaults.standardUserDefaults setInteger:debugPort forKey:@"AutoSDKDebugPort"];
    config[@"debugServerEnabled"] = @YES;
    config[@"debugPort"] = @(debugPort);
    config[@"debugToken"] = debugToken;
    config[@"debugAllowWiFi"] = @(allowWiFi);
    config[@"debugLogging"] = @YES;
#endif
    [engine configureWithConfig:config];

    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    ScriptListViewController *scripts = [ScriptListViewController new];
    self.window.rootViewController = [[UINavigationController alloc] initWithRootViewController:scripts];
    [self.window makeKeyAndVisible];
    return YES;
}

@end
