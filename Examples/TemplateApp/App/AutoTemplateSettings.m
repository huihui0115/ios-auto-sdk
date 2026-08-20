#import "AutoTemplateSettings.h"
@import AutoSDK;
#import <UIKit/UIKit.h>
#include <arpa/inet.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <string.h>

@implementation AutoTemplateSettings

+ (NSString *)debugServiceName {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSString *deviceID = [defaults stringForKey:@"AutoSDKDebugDeviceID"];
    if (deviceID.length < 8) {
        deviceID = NSUUID.UUID.UUIDString;
        [defaults setObject:deviceID forKey:@"AutoSDKDebugDeviceID"];
    }
    NSString *compactID = [deviceID stringByReplacingOccurrencesOfString:@"-" withString:@""];
    NSString *suffix = compactID.length >= 8 ? [compactID substringToIndex:8] : compactID;
    NSString *deviceName = [[UIDevice.currentDevice.name componentsSeparatedByCharactersInSet:NSCharacterSet.controlCharacterSet] componentsJoinedByString:@""];
    if (deviceName.length == 0) deviceName = @"AutoSDK iPhone";
    NSString *name = [NSString stringWithFormat:@"%@ · %@", deviceName, suffix];
    if ([name lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 63) {
        name = [NSString stringWithFormat:@"AutoSDK-%@", suffix];
    }
    return name;
}

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
    BOOL useUIKit = configuredName.length > 0 &&
        [configuredName caseInsensitiveCompare:@"UIKIT"] == NSOrderedSame;
    if (useUIKit) {
        AutoUIKitAdapter *adapter = [AutoUIKitAdapter new];
        id screenshotCache = [NSUserDefaults.standardUserDefaults objectForKey:@"AutoSDKScreenshotCacheDuration"] ?: [bundle objectForInfoDictionaryKey:@"AutoSDKScreenshotCacheDuration"];
        if ([screenshotCache isKindOfClass:NSNumber.class]) adapter.screenshotCacheDuration = [screenshotCache doubleValue];
        return adapter;
    }
    // Default: built-in no-WDA adapter (system-wide touch injection + accessibility).
    AutoBuiltinAdapter *adapter = [AutoBuiltinAdapter new];
    id maxNodes = [NSUserDefaults.standardUserDefaults objectForKey:@"AutoSDKMaxSnapshotNodes"] ?: [bundle objectForInfoDictionaryKey:@"AutoSDKMaxSnapshotNodes"];
    if ([maxNodes isKindOfClass:NSNumber.class] && [maxNodes unsignedIntegerValue] > 0) adapter.maxSnapshotNodes = [maxNodes unsignedIntegerValue];
    id maxDepth = [NSUserDefaults.standardUserDefaults objectForKey:@"AutoSDKMaxSnapshotDepth"] ?: [bundle objectForInfoDictionaryKey:@"AutoSDKMaxSnapshotDepth"];
    if ([maxDepth isKindOfClass:NSNumber.class] && [maxDepth unsignedIntegerValue] > 0) adapter.maxSnapshotDepth = [maxDepth unsignedIntegerValue];
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
    config[@"debugServiceName"] = [self debugServiceName];
    config[@"debugLogging"] = @YES;
#endif
    [engine configureWithConfig:config];
}

@end
