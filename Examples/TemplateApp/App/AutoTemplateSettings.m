#import "AutoTemplateSettings.h"
@import AutoSDK;
#import <UIKit/UIKit.h>
#include <arpa/inet.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <string.h>

@implementation AutoTemplateSettings

+ (NSString *)wifiIPv4Address {
    struct ifaddrs *interfaces = NULL;
    if (getifaddrs(&interfaces) != 0 || !interfaces) return nil;
    NSString *result = nil;
    for (struct ifaddrs *item = interfaces; item; item = item->ifa_next) {
        if (!item->ifa_addr || item->ifa_addr->sa_family != AF_INET) continue;
        if ((item->ifa_flags & IFF_UP) == 0 || (item->ifa_flags & IFF_LOOPBACK) != 0) continue;
        if (strcmp(item->ifa_name, "en0") != 0) continue;
        char address[INET_ADDRSTRLEN] = {0};
        struct sockaddr_in *ipv4 = (struct sockaddr_in *)item->ifa_addr;
        if (inet_ntop(AF_INET, &ipv4->sin_addr, address, sizeof(address))) {
            result = [NSString stringWithUTF8String:address];
            break;
        }
    }
    freeifaddrs(interfaces);
    return result;
}

+ (id)makeAutomationAdapter {
    NSBundle *bundle = NSBundle.mainBundle;
    NSString *configuredName = [NSUserDefaults.standardUserDefaults stringForKey:@"AutoSDKAdapter"];
    if (configuredName.length == 0) configuredName = [bundle objectForInfoDictionaryKey:@"AutoSDKAdapter"];
    BOOL useBuiltin = configuredName.length > 0 &&
        ([configuredName caseInsensitiveCompare:@"BUILTIN"] == NSOrderedSame ||
         [configuredName caseInsensitiveCompare:@"BUILTIN-NOWDA"] == NSOrderedSame ||
         [configuredName caseInsensitiveCompare:@"NOWDA"] == NSOrderedSame);
    if (useBuiltin) {
        AutoBuiltinAdapter *adapter = [AutoBuiltinAdapter new];
        id maxNodes = [NSUserDefaults.standardUserDefaults objectForKey:@"AutoSDKMaxSnapshotNodes"] ?: [bundle objectForInfoDictionaryKey:@"AutoSDKMaxSnapshotNodes"];
        if ([maxNodes isKindOfClass:NSNumber.class] && [maxNodes unsignedIntegerValue] > 0) adapter.maxSnapshotNodes = [maxNodes unsignedIntegerValue];
        id maxDepth = [NSUserDefaults.standardUserDefaults objectForKey:@"AutoSDKMaxSnapshotDepth"] ?: [bundle objectForInfoDictionaryKey:@"AutoSDKMaxSnapshotDepth"];
        if ([maxDepth isKindOfClass:NSNumber.class] && [maxDepth unsignedIntegerValue] > 0) adapter.maxSnapshotDepth = [maxDepth unsignedIntegerValue];
        id screenshotCache = [NSUserDefaults.standardUserDefaults objectForKey:@"AutoSDKScreenshotCacheDuration"] ?: [bundle objectForInfoDictionaryKey:@"AutoSDKScreenshotCacheDuration"];
        if ([screenshotCache isKindOfClass:NSNumber.class]) adapter.screenshotCacheDuration = [screenshotCache doubleValue];
        return adapter;
    }
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

+ (void)applyEngineConfiguration {
    AutoEngine *engine = AutoEngine.sharedEngine;
    [engine setAutomationAdapter:[self makeAutomationAdapter]];
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
    [NSUserDefaults.standardUserDefaults setBool:allowWiFi forKey:@"AutoSDKDebugWiFiActive"];
    [NSUserDefaults.standardUserDefaults setInteger:debugPort forKey:@"AutoSDKDebugPort"];
    config[@"debugServerEnabled"] = @YES;
    config[@"debugPort"] = @(debugPort);
    config[@"debugToken"] = debugToken;
    config[@"debugAllowWiFi"] = @(allowWiFi);
    config[@"debugLogging"] = @YES;
#endif
    [engine configureWithConfig:config];
}

@end
