#import <XCTest/XCTest.h>
@import AutoSDK;

@interface AutoEngine (RuntimeDiagnosticsTests)
- (void)handleDebugRequest:(NSDictionary *)request response:(AutoDebugResponseHandler)response;
- (NSDictionary *)capabilityInfo;
- (void)requestStopForRun:(NSUUID *)identifier reason:(NSString *)reason code:(NSString *)code;
- (void)finishWithResult:(NSDictionary *)result error:(NSError *)error completion:(AutoScriptCompletion)completion;
@end

@interface AutoLegacyDiagnosticAdapter : AutoUIKitAdapter
@end
@implementation AutoLegacyDiagnosticAdapter
- (NSData *)screenshotWithError:(NSError **)error { return [@"png" dataUsingEncoding:NSUTF8StringEncoding]; }
- (NSArray *)nodeSnapshotWithMaxResults:(NSUInteger)limit error:(NSError **)error { return @[@{ @"nodeId": @"root" }]; }
@end
@interface AutoBudgetDiagnosticAdapter : AutoLegacyDiagnosticAdapter
@property (nonatomic, copy) NSDictionary *budget;
@end
@implementation AutoBudgetDiagnosticAdapter
- (NSArray *)nodeSnapshotWithMaxResults:(NSUInteger)limit metadata:(NSDictionary **)metadata error:(NSError **)error {
    if (metadata) *metadata = self.budget;
    return [super nodeSnapshotWithMaxResults:limit error:error];
}
@end

@interface AutoRuntimeDiagnosticsTests : XCTestCase
@end
@implementation AutoRuntimeDiagnosticsTests
- (AutoEngine *)engine {
    AutoEngine *engine = [AutoEngine new];
    [engine configureWithConfig:@{}];
    [engine setAutomationAdapter:[AutoLegacyDiagnosticAdapter new]];
    return engine;
}
- (void)testRuntimeHealthSchemaAndHonestCancellationCapability {
    AutoEngine *engine = self.engine;
    NSDictionary *info = [engine getDeviceInfo], *health = info[@"runtimeHealth"];
    XCTAssertEqualObjects(info[@"sdkVersion"], [NSString stringWithUTF8String:(const char *)AutoSDKVersionString]);
    XCTAssertEqualObjects(health[@"schemaVersion"], @1);
    XCTAssertEqualObjects(health[@"running"], @NO);
    XCTAssertEqualObjects(health[@"backgroundPolicy"], @"finite");
    XCTAssertEqualObjects(health[@"backgroundLeaseActive"], @NO);
    XCTAssertEqualObjects(health[@"lastRun"], @{});
    XCTAssertTrue([health[@"sampledAtMs"] doubleValue] > 0);
    XCTAssertTrue([health[@"decodedImageBudgetMiB"] unsignedIntegerValue] > 0);
    XCTAssertEqualObjects([engine capabilityInfo][@"interruptibleScripts"], @NO);
    XCTAssertEqualObjects([engine capabilityInfo][@"cooperativeCancellation"], @YES);
}
- (void)testCompletedRunAppearsOnlyAfterFinishing {
    AutoEngine *engine = self.engine;
    XCTestExpectation *done = [self expectationWithDescription:@"completed health"];
    [engine runScript:@"21 * 2;" completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(error);
        NSDictionary *health = [engine getDeviceInfo][@"runtimeHealth"];
        XCTAssertEqualObjects(health[@"lastRun"][@"reasonCode"], @"completed");
        XCTAssertEqualObjects(health[@"running"], @NO);
        XCTAssertEqualObjects(health[@"backgroundLeaseActive"], @NO);
        [done fulfill];
    }];
    [self waitForExpectationsWithTimeout:10 handler:nil];
}
- (void)testRunFailureDoesNotExposeScriptOrErrorInHealth {
    AutoEngine *engine = self.engine;
    XCTestExpectation *done = [self expectationWithDescription:@"failure health"];
    [engine runScript:@"throw new Error('DIAGNOSTIC_SECRET');" completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNotNil(error);
        NSDictionary *health = [engine getDeviceInfo][@"runtimeHealth"];
        XCTAssertEqualObjects(health[@"lastRun"][@"reasonCode"], @"failed");
        XCTAssertFalse([health.description containsString:@"DIAGNOSTIC_SECRET"]);
        [done fulfill];
    }];
    [self waitForExpectationsWithTimeout:10 handler:nil];
}
- (void)testFirstStopReasonWinsAndOldRunCannotChangeIt {
    AutoEngine *engine = self.engine; NSUUID *run = NSUUID.UUID;
    [engine setValue:@YES forKey:@"running"];
    [engine setValue:run forKey:@"activeRunIdentifier"];
    [engine requestStopForRun:NSUUID.UUID reason:@"old" code:@"backgroundExpired"];
    XCTAssertEqualObjects([engine getDeviceInfo][@"runtimeHealth"][@"stopRequested"], @NO);
    [engine requestStopForRun:run reason:@"secret pressure detail" code:@"memoryPressure"];
    [engine stopScript];
    [engine requestStopForRun:run reason:@"late expiration" code:@"backgroundExpired"];
    [engine finishWithResult:nil error:[NSError errorWithDomain:AutoSDKErrorDomain code:AutoSDKErrorScriptCancelled userInfo:nil] completion:nil];
    NSDictionary *health = [engine getDeviceInfo][@"runtimeHealth"];
    XCTAssertEqualObjects(health[@"lastRun"][@"reasonCode"], @"memoryPressure");
    XCTAssertFalse([health.description containsString:@"secret"]);
}
- (void)testTimeoutCodeFromAnotherDomainIsNotMisclassified {
    AutoEngine *engine = self.engine;
    [engine finishWithResult:nil error:[NSError errorWithDomain:@"custom" code:AutoSDKErrorScriptTimeout userInfo:nil] completion:nil];
    XCTAssertEqualObjects([engine getDeviceInfo][@"runtimeHealth"][@"lastRun"][@"reasonCode"], @"failed");
    [engine finishWithResult:nil error:[NSError errorWithDomain:AutoSDKErrorDomain code:AutoSDKErrorScriptTimeout userInfo:nil] completion:nil];
    XCTAssertEqualObjects([engine getDeviceInfo][@"runtimeHealth"][@"lastRun"][@"reasonCode"], @"scriptTimeout");
}
- (void)checkSnapshotAdapter:(AutoLegacyDiagnosticAdapter *)adapter completeness:(NSString *)completeness {
    AutoEngine *engine = self.engine; [engine setAutomationAdapter:adapter];
    XCTestExpectation *done = [self expectationWithDescription:completeness];
    [engine handleDebugRequest:@{ @"type": @"inspectSnapshot", @"options": @{ @"maxNodes": @1000 } } response:^(NSDictionary *response) {
        XCTAssertEqualObjects(response[@"ok"], @YES);
        XCTAssertEqualObjects(response[@"completeness"], completeness);
        XCTAssertEqual([response[@"nodes"] count], 1u);
        XCTAssertEqualObjects(response[@"truncated"], @([completeness isEqualToString:@"limited"]));
        [done fulfill];
    }];
    [self waitForExpectationsWithTimeout:10 handler:nil];
}
- (void)testInspectorLegacyAdapterNeverClaimsComplete {
    [self checkSnapshotAdapter:[AutoLegacyDiagnosticAdapter new] completeness:@"unknown"];
}
- (void)testInspectorPropagatesDepthLimitBelowRequestedCount {
    AutoBudgetDiagnosticAdapter *adapter = [AutoBudgetDiagnosticAdapter new];
    adapter.budget = @{ @"truncated": @YES, @"limitReasons": @[@"depthLimit"], @"visitedCount": @1 };
    [self checkSnapshotAdapter:adapter completeness:@"limited"];
}
- (void)testInspectorOnlyClaimsCompleteWithExplicitMetadata {
    AutoBudgetDiagnosticAdapter *adapter = [AutoBudgetDiagnosticAdapter new];
    adapter.budget = @{};
    [self checkSnapshotAdapter:adapter completeness:@"unknown"];
    adapter.budget = @{ @"truncated": @NO };
    [self checkSnapshotAdapter:adapter completeness:@"complete"];
}
@end
