#import <XCTest/XCTest.h>
@import AutoSDK;
#import "../../Sources/AutoSDK/AutoSystemOperations.h"

// No live CLLocationManager, locationd, entitlement, or permission dialog in tests.
@interface AutoFakeLocationManager : NSObject <AutoLocationManaging>
@property (nonatomic, weak) id<CLLocationManagerDelegate> delegate;
@property (nonatomic, assign) CLLocationAccuracy desiredAccuracy;
@property (nonatomic, assign) CLAuthorizationStatus authorizationStatus;
@property (nonatomic, assign) NSUInteger requests;
@property (nonatomic, assign) NSUInteger prompts;
@property (nonatomic, assign) NSUInteger stops;
@property (nonatomic, assign) BOOL grantAuthorization;
@property (nonatomic, strong) CLLocation *fix;
@property (nonatomic, strong) NSError *failure;
@property (nonatomic, copy) dispatch_block_t onRequest;
@property (nonatomic, copy) dispatch_block_t onPrompt;
@end

@implementation AutoFakeLocationManager
- (void)requestWhenInUseAuthorization {
    self.prompts += 1;
    if (self.onPrompt) self.onPrompt();
    if (self.grantAuthorization) {
        self.authorizationStatus = kCLAuthorizationStatusAuthorizedWhenInUse;
        [self.delegate locationManagerDidChangeAuthorization:(CLLocationManager *)self];
        [self.delegate locationManager:(CLLocationManager *)self didChangeAuthorizationStatus:self.authorizationStatus];
    }
}
- (void)requestLocation {
    self.requests += 1;
    if (self.onRequest) self.onRequest();
    if (self.failure) [self.delegate locationManager:(CLLocationManager *)self didFailWithError:self.failure];
    else if (self.fix) [self.delegate locationManager:(CLLocationManager *)self didUpdateLocations:@[self.fix]];
}
- (void)stopUpdatingLocation { self.stops += 1; }
@end

@interface AutoSystemOperationsTests : XCTestCase
@end

@implementation AutoSystemOperationsTests
- (void)testCallbackGateKeepsOnlyFirstResult {
    AutoPendingSystemOperation *pending = [[AutoPendingSystemOperation alloc] initWithTimeout:1 cancellation:nil];
    [pending completeWithResult:@"first" error:nil];
    [pending completeWithResult:@"late" error:nil];
    NSError *error = nil;
    XCTAssertTrue([pending waitWithError:&error]);
    XCTAssertNil(error);
    XCTAssertEqualObjects(pending.result, @"first");
}
- (void)testCallbackGateTimeoutRejectsLateCallback {
    AutoPendingSystemOperation *pending = [[AutoPendingSystemOperation alloc] initWithTimeout:0.01 cancellation:nil];
    NSError *error = nil;
    XCTAssertFalse([pending waitWithError:&error]);
    [pending completeWithResult:@"late" error:nil];
    XCTAssertNil(pending.result);
    XCTAssertNil(error);
    XCTAssertFalse(pending.isActive);
}
- (void)testCallbackGateCancellationDoesNotWaitForSystemCallback {
    NSProgress *cancellation = [NSProgress progressWithTotalUnitCount:1];
    AutoPendingSystemOperation *pending = [[AutoPendingSystemOperation alloc] initWithTimeout:5 cancellation:^BOOL { return cancellation.cancelled; }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_MSEC), dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{ [cancellation cancel]; });
    NSTimeInterval start = NSProcessInfo.processInfo.systemUptime;
    NSError *error = nil;
    XCTAssertFalse([pending waitWithError:&error]);
    XCTAssertLessThan(NSProcessInfo.processInfo.systemUptime - start, 1.0);
    XCTAssertEqualObjects(error.domain, AutoSDKErrorDomain);
    XCTAssertEqual(error.code, AutoSDKErrorScriptCancelled);
    [pending completeWithResult:@YES error:nil];
    XCTAssertNil(pending.result);
}
- (void)testCallbackGatePreservesSystemError {
    AutoPendingSystemOperation *pending = [[AutoPendingSystemOperation alloc] initWithTimeout:1 cancellation:nil];
    NSError *original = [NSError errorWithDomain:@"test.preferences" code:7 userInfo:nil];
    [pending completeWithResult:nil error:original];
    NSError *error = nil;
    XCTAssertTrue([pending waitWithError:&error]);
    XCTAssertEqual(error, original);
}
- (void)fetch:(AutoFakeLocationManager *)manager timeout:(double)timeout cancellation:(AutoSystemCancellation)cancellation
        check:(void (^)(NSDictionary *, NSError *))check {
    XCTestExpectation *done = [self expectationWithDescription:@"one-shot location"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        NSError *error = nil;
        NSDictionary *result = AutoGetLocationSnapshot(timeout, cancellation, ^id<AutoLocationManaging> { return manager; }, YES, &error);
        dispatch_async(dispatch_get_main_queue(), ^{
            check(result, error);
            XCTAssertNil(manager.delegate);
            XCTAssertEqual(manager.stops, 1u);
            [done fulfill];
        });
    });
    [self waitForExpectations:@[done] timeout:3];
}
- (void)testLocationWaitsForFirstAuthorizationAndRequestsOnlyOnce {
    AutoFakeLocationManager *manager = [AutoFakeLocationManager new];
    manager.grantAuthorization = YES;
    manager.fix = [[CLLocation alloc] initWithLatitude:31.2 longitude:121.5];
    [self fetch:manager timeout:1000 cancellation:nil check:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(error);
        XCTAssertEqualObjects(result[@"latitude"], @31.2);
        XCTAssertEqual(manager.prompts, 1u);
        XCTAssertEqual(manager.requests, 1u);
    }];
}
- (void)testLocationErrorUsesSDKDomainAndPreservesUnderlyingError {
    AutoFakeLocationManager *manager = [AutoFakeLocationManager new];
    manager.authorizationStatus = kCLAuthorizationStatusAuthorizedWhenInUse;
    manager.failure = [NSError errorWithDomain:kCLErrorDomain code:kCLErrorDenied userInfo:nil];
    [self fetch:manager timeout:1000 cancellation:nil check:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(result);
        XCTAssertEqualObjects(error.domain, AutoSDKErrorDomain);
        XCTAssertEqual(error.code, AutoSDKErrorAutomationFailed);
        XCTAssertEqual(error.userInfo[NSUnderlyingErrorKey], manager.failure);
    }];
}
- (void)testLocationUnknownIsNullWithoutError {
    AutoFakeLocationManager *manager = [AutoFakeLocationManager new];
    manager.authorizationStatus = kCLAuthorizationStatusAuthorizedWhenInUse;
    manager.failure = [NSError errorWithDomain:kCLErrorDomain code:kCLErrorLocationUnknown userInfo:nil];
    [self fetch:manager timeout:1000 cancellation:nil check:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(result); XCTAssertNil(error);
    }];
}
- (void)testLocationTimeoutStopsUpdatesWithoutError {
    AutoFakeLocationManager *manager = [AutoFakeLocationManager new];
    manager.authorizationStatus = kCLAuthorizationStatusAuthorizedWhenInUse;
    [self fetch:manager timeout:100 cancellation:nil check:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(result); XCTAssertNil(error);
    }];
}
- (void)testLocationCancellationWhileAwaitingAuthorizationPreventsFix {
    AutoFakeLocationManager *manager = [AutoFakeLocationManager new];
    NSProgress *cancellation = [NSProgress progressWithTotalUnitCount:1];
    manager.onPrompt = ^{ [cancellation cancel]; };
    manager.grantAuthorization = YES;
    [self fetch:manager timeout:30000 cancellation:^BOOL { return cancellation.cancelled; } check:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(result);
        XCTAssertEqual(error.code, AutoSDKErrorScriptCancelled);
        XCTAssertEqual(manager.requests, 0u);
    }];
}
- (void)testLocationCancellationStopsPendingFix {
    AutoFakeLocationManager *manager = [AutoFakeLocationManager new];
    manager.authorizationStatus = kCLAuthorizationStatusAuthorizedWhenInUse;
    NSProgress *cancellation = [NSProgress progressWithTotalUnitCount:1];
    manager.onRequest = ^{ [cancellation cancel]; };
    [self fetch:manager timeout:30000 cancellation:^BOOL { return cancellation.cancelled; } check:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(result); XCTAssertEqual(error.code, AutoSDKErrorScriptCancelled);
    }];
}
- (void)testSlowManagerInitializationCannotPromptAfterTimeout {
    AutoFakeLocationManager *manager = [AutoFakeLocationManager new];
    dispatch_semaphore_t returned = dispatch_semaphore_create(0);
    XCTestExpectation *done = [self expectationWithDescription:@"late factory"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        NSError *error = nil;
        NSDictionary *result = AutoGetLocationSnapshot(100, nil, ^id<AutoLocationManaging> {
            // Keep the UI setup in-flight until the worker's deadline has passed.
            dispatch_semaphore_wait(returned, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC));
            return manager;
        }, YES, &error);
        dispatch_semaphore_signal(returned);
        dispatch_async(dispatch_get_main_queue(), ^{
            XCTAssertNil(result); XCTAssertNil(error);
            XCTAssertEqual(manager.prompts, 0u);
            XCTAssertEqual(manager.requests, 0u);
            XCTAssertNil(manager.delegate);
            [done fulfill];
        });
    });
    [self waitForExpectations:@[done] timeout:3];
}
- (void)testLocationRejectsMainThreadWait {
    NSError *error = nil;
    XCTAssertNil(AutoGetLocationSnapshot(100, nil, nil, YES, &error));
    XCTAssertEqual(error.code, AutoSDKErrorAutomationUnavailable);
}
@end
