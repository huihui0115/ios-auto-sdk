#import "AutoSystemOperations.h"
#import "include/AutoSDKError.h"
#include <math.h>

static NSError *AutoMakeError(AutoSDKErrorCode code, NSString *message, NSError *underlying) {
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithObject:message forKey:NSLocalizedDescriptionKey];
    if (underlying) info[NSUnderlyingErrorKey] = underlying;
    return [NSError errorWithDomain:AutoSDKErrorDomain code:code userInfo:info];
}

@interface AutoPendingSystemOperation ()
@property (nonatomic, strong) NSCondition *condition;
@property (nonatomic, copy) AutoSystemCancellation cancellation;
@property (nonatomic, assign) NSTimeInterval deadline;
@property (nonatomic, assign) BOOL completed;
@property (nonatomic, strong, readwrite) id result;
@property (nonatomic, strong) NSError *failure;
@end

@implementation AutoPendingSystemOperation
- (instancetype)initWithTimeout:(NSTimeInterval)timeout cancellation:(AutoSystemCancellation)cancellation {
    self = [super init];
    if (self) {
        _condition = [NSCondition new];
        _cancellation = [cancellation copy];
        _deadline = NSProcessInfo.processInfo.systemUptime + (isfinite(timeout) ? MAX(0, timeout) : 0);
    }
    return self;
}
- (BOOL)canContinueLocked {
    return !self.completed && !(self.cancellation && self.cancellation()) &&
        NSProcessInfo.processInfo.systemUptime < self.deadline;
}
- (BOOL)isActive {
    [self.condition lock];
    BOOL active = [self canContinueLocked];
    [self.condition unlock];
    return active;
}
- (void)completeWithResult:(id)result error:(NSError *)error {
    [self.condition lock];
    if ([self canContinueLocked]) {
        self.result = result;
        self.failure = error;
        self.completed = YES;
        [self.condition signal];
    }
    [self.condition unlock];
}
- (BOOL)waitWithError:(NSError **)error {
    [self.condition lock];
    while ([self canContinueLocked]) {
        NSTimeInterval remaining = self.deadline - NSProcessInfo.processInfo.systemUptime;
        [self.condition waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:MIN(0.05, MAX(0, remaining))]];
    }
    BOOL cancelled = self.cancellation && self.cancellation();
    BOOL finished = self.completed && !cancelled;
    self.completed = YES; // Close the gate before returning, including on timeout.
    if (!finished) self.result = nil;
    if (error) *error = cancelled ? AutoMakeError(AutoSDKErrorScriptCancelled, @"Script cancelled.", nil) : self.failure;
    self.cancellation = nil; // A system callback may retain this gate after the script ends.
    [self.condition unlock];
    return finished;
}
@end

@interface AutoLocationRequest : NSObject <CLLocationManagerDelegate>
@property (nonatomic, strong) AutoPendingSystemOperation *operation;
@property (nonatomic, strong) id<AutoLocationManaging> manager;
@property (nonatomic, assign) BOOL requestedLocation;
- (void)startForAuthorization:(CLAuthorizationStatus)status;
- (void)cleanup;
@end

@implementation AutoLocationRequest
- (void)startForAuthorization:(CLAuthorizationStatus)status {
    if (![self.operation isActive]) return;
    if (status == kCLAuthorizationStatusAuthorizedAlways || status == kCLAuthorizationStatusAuthorizedWhenInUse) {
        if (!self.requestedLocation) {
            self.requestedLocation = YES;
            [self.manager requestLocation];
        }
    } else if (status == kCLAuthorizationStatusDenied || status == kCLAuthorizationStatusRestricted) {
        [self.operation completeWithResult:nil error:AutoMakeError(AutoSDKErrorAutomationFailed, @"Location permission denied.", nil)];
    }
}
- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager {
    [self startForAuthorization:manager.authorizationStatus];
}
- (void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status {
    [self startForAuthorization:status];
}
- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    [self.operation completeWithResult:locations.lastObject error:nil];
}
- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    BOOL noFix = [error.domain isEqualToString:kCLErrorDomain] && error.code == kCLErrorLocationUnknown;
    NSError *failure = noFix ? nil : AutoMakeError(AutoSDKErrorAutomationFailed,
        @"Unable to obtain location. Check Location Services and the host app's permission.", error);
    [self.operation completeWithResult:nil error:failure];
}
- (void)cleanup {
    self.manager.delegate = nil;
    [self.manager stopUpdatingLocation];
    self.manager = nil;
}
@end

NSDictionary *AutoGetLocationSnapshot(double timeoutMs, AutoSystemCancellation cancellation,
                                      AutoLocationManagerFactory factory, BOOL hasUsageDescription,
                                      NSError **error) {
    if (NSThread.isMainThread) {
        if (error) *error = AutoMakeError(AutoSDKErrorAutomationUnavailable, @"Location cannot be awaited on the main thread.", nil);
        return nil;
    }
    AutoLocationRequest *request = [AutoLocationRequest new];
    request.operation = [[AutoPendingSystemOperation alloc] initWithTimeout:timeoutMs / 1000.0 cancellation:cancellation];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (![request.operation isActive]) return;
        if (!hasUsageDescription) {
            [request.operation completeWithResult:nil error:AutoMakeError(AutoSDKErrorAutomationFailed,
                @"NSLocationWhenInUseUsageDescription is missing from the host app Info.plist.", nil)];
            return;
        }
        // Do not synchronously query locationServicesEnabled on the UI thread.
        // Authorization and requestLocation's delegate report denial/disabled services.
        request.manager = factory ? factory() : (id<AutoLocationManaging>)[CLLocationManager new];
        if (![request.operation isActive]) { [request cleanup]; return; }
        request.manager.desiredAccuracy = kCLLocationAccuracyBest;
        request.manager.delegate = request;
        CLAuthorizationStatus status = request.manager.authorizationStatus;
        // Manager initialization/status lookup can outlast the worker's deadline.
        if (![request.operation isActive]) { [request cleanup]; return; }
        if (status == kCLAuthorizationStatusNotDetermined) [request.manager requestWhenInUseAuthorization];
        else [request startForAuthorization:status];
    });
    [request.operation waitWithError:error];
    CLLocation *location = request.operation.result;
    dispatch_async(dispatch_get_main_queue(), ^{ [request cleanup]; });
    if (!location) return nil;
    return @{
        @"latitude": @(location.coordinate.latitude), @"longitude": @(location.coordinate.longitude),
        @"altitude": @(location.altitude), @"horizontalAccuracy": @(location.horizontalAccuracy),
        @"verticalAccuracy": @(location.verticalAccuracy), @"course": @(location.course),
        @"speed": @(location.speed), @"timestamp": @([location.timestamp timeIntervalSince1970] * 1000.0)
    };
}
