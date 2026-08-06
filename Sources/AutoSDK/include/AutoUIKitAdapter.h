#import <Foundation/Foundation.h>
#import "AutoAutomationAdapter.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Public-API adapter for automating views owned by the host application.
 * For cross-app automation use AutoBuiltinAdapter (built-in no-WDA) instead.
 */
@interface AutoUIKitAdapter : NSObject <AutoAutomationAdapter>
/** Reuse one rendered frame briefly; disabled by default for animated UIs. */
@property (nonatomic, assign) NSTimeInterval screenshotCacheDuration;
@end

NS_ASSUME_NONNULL_END
