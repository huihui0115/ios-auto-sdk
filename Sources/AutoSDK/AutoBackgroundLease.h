#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
// One finite assertion per run. Injection keeps expiration tests independent of UIKit state.
@interface AutoBackgroundLease : NSObject
+ (instancetype)leaseWithExpiration:(dispatch_block_t)expiration;
- (instancetype)initWithBegin:(UIBackgroundTaskIdentifier (^)(dispatch_block_t))begin
                          end:(void (^)(UIBackgroundTaskIdentifier))end
                   expiration:(dispatch_block_t)expiration;
- (void)finish;
@end
NS_ASSUME_NONNULL_END
