#import <Foundation/Foundation.h>
@class AutoEngine;

NS_ASSUME_NONNULL_BEGIN

/** Shared template configuration: adapter selection, runtime config, debug token. */
@interface AutoTemplateSettings : NSObject

/** Builds the automation adapter from NSUserDefaults overrides plus Info.plist. */
+ (id)makeAutomationAdapter;
/** Re-applies adapter, configuration, and native methods to the shared engine. */
+ (void)applyEngineConfiguration;
/** The en0 IPv4 address used for Wi-Fi debug connections. */
+ (nullable NSString *)wifiIPv4Address;

@end

NS_ASSUME_NONNULL_END
