#import "AutoBackgroundLease.h"

@interface AutoBackgroundLease ()
@property (nonatomic) UIBackgroundTaskIdentifier identifier;
@property (nonatomic) BOOL closed;
@property (nonatomic, copy) void (^endTask)(UIBackgroundTaskIdentifier);
@property (nonatomic, copy) dispatch_block_t expiration;
@end
@implementation AutoBackgroundLease
+ (instancetype)leaseWithExpiration:(dispatch_block_t)expiration {
    UIApplication *application = [NSBundle.mainBundle.bundlePath.pathExtension isEqualToString:@"appex"]
        ? nil : UIApplication.sharedApplication;
    return [[self alloc] initWithBegin:^UIBackgroundTaskIdentifier(dispatch_block_t handler) {
        return application ? [application beginBackgroundTaskWithName:@"AutoSDK script" expirationHandler:handler] : UIBackgroundTaskInvalid;
    } end:^(UIBackgroundTaskIdentifier identifier) {
        [application endBackgroundTask:identifier];
    } expiration:expiration];
}
- (instancetype)initWithBegin:(UIBackgroundTaskIdentifier (^)(dispatch_block_t))begin
                          end:(void (^)(UIBackgroundTaskIdentifier))end expiration:(dispatch_block_t)expiration {
    if ((self = [super init])) {
        _identifier = UIBackgroundTaskInvalid;
        _endTask = [end copy];
        _expiration = [expiration copy];
        __weak AutoBackgroundLease *weakSelf = self;
        UIBackgroundTaskIdentifier identifier = begin(^{ [weakSelf expire]; });
        BOOL alreadyClosed;
        @synchronized (self) { alreadyClosed = self.closed; if (!alreadyClosed) self.identifier = identifier; }
        // UIKit may expire synchronously before begin returns its identifier.
        if (alreadyClosed && identifier != UIBackgroundTaskInvalid) end(identifier);
    }
    return self;
}
- (void)expire {
    dispatch_block_t expiration;
    UIBackgroundTaskIdentifier identifier;
    @synchronized (self) {
        if (self.closed) return;
        self.closed = YES;
        expiration = self.expiration;
        self.expiration = nil;
        identifier = self.identifier;
        self.identifier = UIBackgroundTaskInvalid;
    }
    if (identifier != UIBackgroundTaskInvalid) self.endTask(identifier);
    if (expiration) expiration();
}
- (void)finish {
    UIBackgroundTaskIdentifier identifier;
    @synchronized (self) {
        if (self.closed) return;
        self.closed = YES;
        identifier = self.identifier;
        self.identifier = UIBackgroundTaskInvalid;
        self.expiration = nil;
    }
    if (identifier != UIBackgroundTaskInvalid) self.endTask(identifier);
}
- (void)dealloc { [self finish]; }
@end
