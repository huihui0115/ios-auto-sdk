#import <XCTest/XCTest.h>
@import AutoSDK;
#import "../../Sources/AutoSDK/AutoAccessibilityControl.h"

static BOOL fakeEnabled;
static BOOL fakeReject;
static NSUInteger fakeWrites;
@interface AutoFakeAssistiveTouch : NSObject
+ (BOOL)isEnabled;
+ (void)setEnabled:(BOOL)enabled;
@end
@implementation AutoFakeAssistiveTouch
+ (BOOL)isEnabled { return fakeEnabled; }
+ (void)setEnabled:(BOOL)enabled { fakeWrites++; if (!fakeReject) fakeEnabled = enabled; }
@end
@interface AutoInvalidAssistiveTouch : NSObject
+ (id)isEnabled;
@end
@implementation AutoInvalidAssistiveTouch
+ (id)isEnabled { return @YES; }
@end
@interface AutoAccessibilityControlTests : XCTestCase
@end
@implementation AutoAccessibilityControlTests
- (void)setUp { [super setUp]; fakeEnabled = NO; fakeReject = NO; fakeWrites = 0; }
- (void)testEnableDisableAndIdempotentReadback {
    NSError *error = nil;
    XCTAssertEqualObjects(AutoAssistiveTouchState(AutoFakeAssistiveTouch.class), @NO);
    XCTAssertTrue(AutoSetAssistiveTouchEnabled(AutoFakeAssistiveTouch.class, YES, &error));
    XCTAssertTrue(AutoSetAssistiveTouchEnabled(AutoFakeAssistiveTouch.class, YES, &error));
    XCTAssertEqual(fakeWrites, 1u);
    XCTAssertTrue(AutoSetAssistiveTouchEnabled(AutoFakeAssistiveTouch.class, NO, &error));
    XCTAssertEqual(fakeWrites, 2u);
    XCTAssertNil(error);
}
- (void)testRejectedSetterDoesNotClaimSuccessOrRetry {
    fakeReject = YES;
    NSError *error = nil;
    XCTAssertFalse(AutoSetAssistiveTouchEnabled(AutoFakeAssistiveTouch.class, YES, &error));
    XCTAssertEqual(fakeWrites, 1u);
    XCTAssertEqual(error.code, AutoSDKErrorAutomationFailed);
    XCTAssertEqualObjects(AutoAssistiveTouchState(AutoFakeAssistiveTouch.class), @NO);
}
- (void)testMissingOrChangedSPIIsUnknownNotDisabled {
    XCTAssertNil(AutoAssistiveTouchState(Nil));
    XCTAssertNil(AutoAssistiveTouchState(AutoInvalidAssistiveTouch.class));
    NSError *error = nil;
    XCTAssertFalse(AutoSetAssistiveTouchEnabled(Nil, YES, &error));
    XCTAssertEqual(error.code, AutoSDKErrorAutomationUnavailable);
    XCTAssertFalse(AutoSetAssistiveTouchEnabled(AutoInvalidAssistiveTouch.class, YES, &error));
}
- (void)testSystemPolicyBlocksScriptWrite {
    AutoEngine *engine = [AutoEngine new];
    [engine initWithConfig:@{ @"scriptTimeout": @30, @"allowSystemControl": @NO }];
    XCTestExpectation *done = [self expectationWithDescription:@"permission"];
    [engine runScript:@"device.setAssistiveTouchEnabled(true);" completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(result);
        XCTAssertEqual(error.code, AutoSDKErrorInvalidConfiguration);
        [done fulfill];
    }];
    [self waitForExpectationsWithTimeout:30 handler:nil];
}
- (void)testScriptRejectsStringBooleanBeforeChangingSystem {
    AutoEngine *engine = [AutoEngine new];
    [engine initWithConfig:@{ @"scriptTimeout": @30 }];
    XCTestExpectation *done = [self expectationWithDescription:@"boolean"];
    [engine runScript:@"device.setAssistiveTouchEnabled('false');" completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(result);
        XCTAssertEqual(error.code, AutoSDKErrorInvalidConfiguration);
        [done fulfill];
    }];
    [self waitForExpectationsWithTimeout:30 handler:nil];
}
@end
