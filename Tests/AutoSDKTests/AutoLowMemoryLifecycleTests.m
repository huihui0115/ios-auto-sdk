#import <XCTest/XCTest.h>
#import <UIKit/UIKit.h>
@import AutoSDK;

@interface AutoEngine (ResourceTestAccess)
- (void)requestStopForRun:(NSUUID *)identifier reason:(NSString *)reason;
- (void)handleResourcePressure:(NSNotification *)notification;
@end

@interface AutoCaptureProbe : AutoBuiltinAdapter
@property (nonatomic) NSUInteger captures;
@property (nonatomic, copy) dispatch_block_t duringCapture;
@end
@implementation AutoCaptureProbe
- (NSData *)systemWideScreenshotImageWithError:(NSError **)error {
    self.captures++;
    if (self.duringCapture) self.duringCapture();
    return [@"captured frame" dataUsingEncoding:NSUTF8StringEncoding];
}
@end

@interface AutoLowMemoryLifecycleTests : XCTestCase
@end
@implementation AutoLowMemoryLifecycleTests
- (void)testMemoryWarningAndDisablingCacheReleaseOldScreenshot {
    AutoCaptureProbe *adapter = [AutoCaptureProbe new];
    adapter.screenshotCacheDuration = 5;
    XCTAssertNotNil([adapter screenshotWithError:nil]);
    XCTAssertNotNil([adapter screenshotWithError:nil]);
    XCTAssertEqual(adapter.captures, 1u);
    [adapter releaseCachedResources];
    XCTAssertNil([adapter valueForKey:@"cachedScreenshot"]);
    XCTAssertNotNil([adapter screenshotWithError:nil]);
    XCTAssertEqual(adapter.captures, 2u);
    adapter.screenshotCacheDuration = 0;
    XCTAssertNil([adapter valueForKey:@"cachedScreenshot"]);
    XCTAssertNotNil([adapter screenshotWithError:nil]);
    XCTAssertNotNil([adapter screenshotWithError:nil]);
    XCTAssertEqual(adapter.captures, 4u);
}
- (void)testCancelledCaptureCannotRepopulateCacheAndNextCaptureWorks {
    AutoCaptureProbe *adapter = [AutoCaptureProbe new];
    adapter.screenshotCacheDuration = 5;
    __weak AutoCaptureProbe *weakAdapter = adapter;
    adapter.duringCapture = ^{ [weakAdapter releaseCachedResources]; };
    NSError *error = nil;
    XCTAssertNil([adapter screenshotWithError:&error]);
    XCTAssertEqual(error.code, AutoSDKErrorScriptCancelled);
    XCTAssertNil([adapter valueForKey:@"cachedScreenshot"]);
    adapter.duringCapture = nil;
    error = nil;
    XCTAssertNotNil([adapter screenshotWithError:&error]);
    XCTAssertNil(error);
    XCTAssertEqual(adapter.captures, 2u);
}
- (void)testConcurrentVisualOperationFailsFastWithoutMainThreadDeadlock {
    AutoCaptureProbe *adapter = [AutoCaptureProbe new];
    dispatch_semaphore_t entered = dispatch_semaphore_create(0);
    dispatch_semaphore_t resume = dispatch_semaphore_create(0);
    adapter.duringCapture = ^{
        dispatch_semaphore_signal(entered);
        dispatch_semaphore_wait(resume, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
    };
    XCTestExpectation *done = [self expectationWithDescription:@"first capture completes"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        NSError *error = nil;
        XCTAssertNotNil([adapter screenshotWithError:&error]);
        XCTAssertNil(error);
        [done fulfill];
    });
    XCTAssertEqual(dispatch_semaphore_wait(entered, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)), 0);
    NSError *error = nil;
    XCTAssertNil([adapter screenshotWithError:&error]);
    XCTAssertEqual(error.code, AutoSDKErrorAutomationFailed);
    dispatch_semaphore_signal(resume);
    [self waitForExpectations:@[done] timeout:6];
    XCTAssertEqual(adapter.captures, 1u);
}
- (void)testCaptureExceptionReleasesVisualGate {
    AutoCaptureProbe *adapter = [AutoCaptureProbe new];
    adapter.duringCapture = ^{ @throw [NSException exceptionWithName:@"Capture failure" reason:@"test" userInfo:nil]; };
    NSError *error = nil;
    XCTAssertNil([adapter screenshotWithError:&error]);
    XCTAssertEqual(error.code, AutoSDKErrorAutomationFailed);
    adapter.duringCapture = nil;
    error = nil;
    XCTAssertNotNil([adapter screenshotWithError:&error]);
    XCTAssertNil(error);
}
- (void)testLateBackgroundExpirationCannotCancelAnotherRun {
    AutoEngine *engine = [AutoEngine new];
    NSUUID *current = NSUUID.UUID;
    [engine setValue:@YES forKey:@"running"];
    [engine setValue:current forKey:@"activeRunIdentifier"];
    [engine requestStopForRun:NSUUID.UUID reason:@"old run"];
    XCTAssertFalse([[engine valueForKey:@"stopRequested"] boolValue]);
    [engine requestStopForRun:current reason:@"current run expired"];
    XCTAssertTrue([[engine valueForKey:@"stopRequested"] boolValue]);
    XCTAssertEqualObjects([engine valueForKey:@"stopReason"], @"current run expired");
    [engine setValue:@NO forKey:@"running"];
    [engine setValue:@NO forKey:@"stopRequested"];
    [engine requestStopForRun:current reason:@"already finished"];
    XCTAssertFalse([[engine valueForKey:@"stopRequested"] boolValue]);
}
- (void)testMemoryPressureStopsActiveRunAndReleasesCache {
    AutoEngine *engine = [AutoEngine new];
    AutoCaptureProbe *adapter = [AutoCaptureProbe new];
    adapter.screenshotCacheDuration = 5;
    [adapter screenshotWithError:nil];
    [engine configureWithConfig:@{ @"adapter": adapter }];
    [engine setValue:adapter forKey:@"activeAdapter"];
    [engine setValue:NSUUID.UUID forKey:@"activeRunIdentifier"];
    [engine setValue:@YES forKey:@"running"];
    [engine handleResourcePressure:[NSNotification notificationWithName:UIApplicationDidReceiveMemoryWarningNotification object:nil]];
    XCTAssertTrue([[engine valueForKey:@"stopRequested"] boolValue]);
    XCTAssertNil([adapter valueForKey:@"cachedScreenshot"]);
    XCTAssertTrue([[engine valueForKey:@"stopReason"] containsString:@"low memory"]);
    [engine setValue:@NO forKey:@"running"];
}
@end
