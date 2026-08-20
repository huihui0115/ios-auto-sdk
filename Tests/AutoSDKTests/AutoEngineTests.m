#import <XCTest/XCTest.h>
@import AutoSDK;
#import <UIKit/UIKit.h>

@interface AutoTestAdapter : NSObject <AutoAutomationAdapter>
@property (nonatomic, assign) NSInteger clickCount;
@property (nonatomic, assign) NSInteger cancellationCount;
@end

@implementation AutoTestAdapter
- (BOOL)click:(id)selector error:(NSError **)error { self.clickCount += 1; return YES; }
- (BOOL)clickAtX:(CGFloat)x y:(CGFloat)y error:(NSError **)error { self.clickCount += 1; return YES; }
- (BOOL)doubleClickAtX:(CGFloat)x y:(CGFloat)y interval:(NSTimeInterval)interval error:(NSError **)error { self.clickCount += 2; return YES; }
- (BOOL)longClick:(id)selector duration:(NSTimeInterval)duration error:(NSError **)error { return YES; }
- (BOOL)swipeFromX:(CGFloat)x1 y:(CGFloat)y1 toX:(CGFloat)x2 y:(CGFloat)y2 duration:(NSTimeInterval)duration error:(NSError **)error { return YES; }
- (BOOL)input:(id)selector text:(NSString *)text error:(NSError **)error { return YES; }
- (NSString *)textForSelector:(id)selector error:(NSError **)error { return @"hello"; }
- (NSData *)screenshotWithError:(NSError **)error { return [@"png" dataUsingEncoding:NSUTF8StringEncoding]; }
- (NSDictionary *)findImageAtPath:(NSString *)templatePath options:(NSDictionary *)options error:(NSError **)error { return @{@"found": @YES}; }
- (NSArray *)ocrInRegion:(NSDictionary *)region error:(NSError **)error { return @[@{@"text": @"hello"}]; }
- (NSDictionary *)deviceInfo { return @{@"test": @YES}; }
- (BOOL)exists:(id)selector error:(NSError **)error { return YES; }
- (NSDictionary *)elementInfoForSelector:(id)selector error:(NSError **)error { return @{@"selector": selector ?: [NSNull null], @"id": @"button", @"type": @"Button"}; }
- (NSArray *)elementsInfoForSelector:(id)selector error:(NSError **)error { return @[[self elementInfoForSelector:selector error:error]]; }
- (NSArray *)nodeSnapshotWithMaxResults:(NSUInteger)maxResults error:(NSError **)error {
    return @[@{ @"nodeId": @"root", @"parentId": NSNull.null, @"depth": @0,
                @"type": @"Window", @"bounds": @{ @"x": @0, @"y": @0, @"width": @100, @"height": @100 } }];
}
- (id)attribute:(NSString *)attribute forSelector:(id)selector error:(NSError **)error { return [attribute isEqualToString:@"type"] ? @"Button" : @"value"; }
- (NSDictionary *)boundsForSelector:(id)selector error:(NSError **)error { return @{@"x": @0, @"y": @0, @"width": @100, @"height": @44}; }
- (NSArray *)childrenForSelector:(id)selector error:(NSError **)error { return @[@{@"id": @"child"}]; }
- (NSDictionary *)parentForSelector:(id)selector error:(NSError **)error { return @{@"id": @"root"}; }
- (BOOL)scrollIntoView:(id)selector error:(NSError **)error { return YES; }
- (NSDictionary *)findColor:(id)color region:(NSDictionary *)region options:(NSDictionary *)options error:(NSError **)error { return @{@"found": @YES, @"x": @10, @"y": @20}; }
- (NSDictionary *)pixelColorAtX:(CGFloat)x y:(CGFloat)y error:(NSError **)error { return @{@"x": @(x), @"y": @(y), @"hex": @"#FF0000", @"r": @255, @"g": @0, @"b": @0}; }
- (BOOL)compareColors:(NSArray *)points options:(NSDictionary *)options error:(NSError **)error { return YES; }
- (NSDictionary *)findMultiColor:(id)color offsets:(NSArray *)offsets region:(NSDictionary *)region options:(NSDictionary *)options error:(NSError **)error { return @{@"found": @YES, @"x": @10, @"y": @20}; }
- (BOOL)launchApplicationWithBundleId:(NSString *)bundleId error:(NSError **)error { return bundleId.length > 0; }
- (BOOL)activateApplicationWithBundleId:(NSString *)bundleId error:(NSError **)error { return bundleId.length > 0; }
- (BOOL)terminateApplicationWithBundleId:(NSString *)bundleId error:(NSError **)error { return bundleId.length > 0; }
- (NSNumber *)applicationStateForBundleId:(NSString *)bundleId error:(NSError **)error { return bundleId.length > 0 ? @4 : nil; }
- (NSDictionary *)capabilities { return @{@"scope": @"test", @"nodes": @YES}; }
- (void)cancelCurrentOperations { self.cancellationCount += 1; }
@end

@interface AutoMainThreadTestAdapter : AutoTestAdapter
@property (nonatomic, assign) BOOL pixelCalledOnMainThread;
@end

@implementation AutoMainThreadTestAdapter
- (NSDictionary *)capabilities { return @{@"scope": @"test", @"requiresMainThread": @YES}; }
- (NSDictionary *)pixelColorAtX:(CGFloat)x y:(CGFloat)y error:(NSError **)error {
    self.pixelCalledOnMainThread = NSThread.isMainThread;
    return [super pixelColorAtX:x y:y error:error];
}
@end

@interface AutoUIKitAdapter (AutoSDKTests)
- (UIImage *)threadSafeCapturedImageForOperationGeneration:(NSUInteger)operationGeneration error:(NSError **)error;
- (BOOL)operationWasCancelledSinceGeneration:(NSUInteger)generation;
@end

@interface AutoStaticImageUIKitAdapter : AutoUIKitAdapter
@property (nonatomic, strong) UIImage *testImage;
@end

@implementation AutoStaticImageUIKitAdapter
- (UIImage *)threadSafeCapturedImageForOperationGeneration:(NSUInteger)operationGeneration error:(NSError **)error {
    (void)operationGeneration;
    (void)error;
    return self.testImage;
}
@end

@interface AutoCancelledUIKitAdapter : AutoUIKitAdapter
@end

@implementation AutoCancelledUIKitAdapter
- (BOOL)operationWasCancelledSinceGeneration:(NSUInteger)generation {
    (void)generation;
    return YES;
}
@end

static UIImage *AutoTestRGBAImage(NSUInteger width, NSUInteger height, const uint8_t *bytes) {
    NSData *data = [NSData dataWithBytes:bytes length:width * height * 4];
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGImageRef imageRef = CGImageCreate(width, height, 8, 32, width * 4, colorSpace,
                                       kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big,
                                       provider, NULL, NO, kCGRenderingIntentDefault);
    UIImage *image = imageRef ? [UIImage imageWithCGImage:imageRef scale:1 orientation:UIImageOrientationUp] : nil;
    if (imageRef) CGImageRelease(imageRef);
    if (colorSpace) CGColorSpaceRelease(colorSpace);
    if (provider) CGDataProviderRelease(provider);
    return image;
}

@interface AutoEngineTests : XCTestCase
@end

@interface AutoEngine (AutoSDKTests)
- (void)handleDebugRequest:(NSDictionary<NSString *, id> *)request response:(AutoDebugResponseHandler)response;
- (NSDictionary<NSString *, id> *)capabilityInfo;
@end

@implementation AutoEngineTests
- (void)testFileWriteCapabilityRequiresFileAccess {
    AutoEngine *engine = AutoEngine.sharedEngine;
    [engine initWithConfig:@{ @"allowFileAccess": @NO, @"allowFileWrite": @YES }];
    NSDictionary *disabled = [engine capabilityInfo];
    XCTAssertEqualObjects(disabled[@"fileRead"], @NO);
    XCTAssertEqualObjects(disabled[@"fileWrite"], @NO);

    [engine initWithConfig:@{ @"allowFileAccess": @YES, @"allowFileWrite": @NO }];
    NSDictionary *readOnly = [engine capabilityInfo];
    XCTAssertEqualObjects(readOnly[@"fileRead"], @YES);
    XCTAssertEqualObjects(readOnly[@"fileWrite"], @NO);
}

- (void)testRetainedScriptLogsHonorTheTotalByteBudget {
    AutoEngine *engine = AutoEngine.sharedEngine;
    [engine initWithConfig:@{ @"scriptTimeout": @5,
                              @"maxLogEntries": @100,
                              @"maxLogMessageLength": @100,
                              @"maxLogBytes": @16 }];
    XCTestExpectation *expectation = [self expectationWithDescription:@"bounded retained logs"];
    [engine runScript:@"console.log('1234567890'); console.log('abcdefghij'); 1;"
             completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(error);
        XCTAssertEqual([result[@"logs"] count], (NSUInteger)1);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];
}

- (void)testDebugVisualOperationHonorsThirdPartyMainThreadRequirement {
    AutoMainThreadTestAdapter *adapter = [AutoMainThreadTestAdapter new];
    AutoEngine *engine = AutoEngine.sharedEngine;
    [engine initWithConfig:@{}];
    [engine setAutomationAdapter:adapter];
    XCTestExpectation *expectation = [self expectationWithDescription:@"main-thread pixel"];
    [engine handleDebugRequest:@{ @"type": @"pixelColor", @"x": @1, @"y": @2 }
                       response:^(NSDictionary<NSString *,id> *response) {
        XCTAssertEqualObjects(response[@"ok"], @YES);
        XCTAssertTrue(adapter.pixelCalledOnMainThread);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];
}

- (void)testDebugNodeActionAndDeployedScriptLifecycle {
    AutoTestAdapter *adapter = [AutoTestAdapter new];
    AutoEngine *engine = AutoEngine.sharedEngine;
    [engine initWithConfig:@{}];
    [engine setAutomationAdapter:adapter];
    NSString *name = [NSString stringWithFormat:@"test-%@.js", NSUUID.UUID.UUIDString];

    XCTestExpectation *put = [self expectationWithDescription:@"put script"];
    [engine handleDebugRequest:@{ @"type": @"putScript", @"name": name, @"script": @"21 * 2;" }
                       response:^(NSDictionary<NSString *,id> *response) {
        XCTAssertEqualObjects(response[@"ok"], @YES);
        [put fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];

    NSError *listError = nil;
    NSArray<NSDictionary<NSString *, id> *> *scripts = [engine deployedScriptsWithError:&listError];
    XCTAssertNil(listError);
    NSPredicate *matchingName = [NSPredicate predicateWithFormat:@"name == %@", name];
    NSArray<NSDictionary<NSString *, id> *> *matchingScripts = [scripts filteredArrayUsingPredicate:matchingName];
    XCTAssertEqual(matchingScripts.count, 1);

    XCTestExpectation *run = [self expectationWithDescription:@"run stored"];
    [engine handleDebugRequest:@{ @"type": @"runStored", @"name": name }
                       response:^(NSDictionary<NSString *,id> *response) {
        XCTAssertEqualObjects(response[@"ok"], @YES);
        XCTAssertEqualObjects(response[@"result"][@"value"], @42);
        [run fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];

    XCTestExpectation *action = [self expectationWithDescription:@"node click"];
    [engine handleDebugRequest:@{ @"type": @"nodeAction", @"action": @"click", @"selector": @{@"id": @"button"} }
                       response:^(NSDictionary<NSString *,id> *response) {
        XCTAssertEqualObjects(response[@"ok"], @YES);
        [action fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];
    XCTAssertEqual(adapter.clickCount, 1);

    NSError *deleteError = nil;
    XCTAssertTrue([engine deleteDeployedScriptNamed:name error:&deleteError]);
    XCTAssertNil(deleteError);
}
- (void)testDeployedScriptSaveReadRenameDelete {
    AutoEngine *engine = AutoEngine.sharedEngine;
    [engine initWithConfig:@{}];
    NSString *unique = NSUUID.UUID.UUIDString;
    NSString *oldName = [NSString stringWithFormat:@"save-%@.js", unique];
    NSString *newName = [NSString stringWithFormat:@"renamed-%@.js", unique];
    NSString *clashName = [NSString stringWithFormat:@"clash-%@.js", unique];

    NSError *error = nil;
    XCTAssertFalse([engine saveDeployedScriptNamed:oldName script:@"" error:&error]);
    XCTAssertNotNil(error);
    error = nil;
    XCTAssertFalse([engine saveDeployedScriptNamed:@"../escape.js" script:@"1;" error:&error]);
    XCTAssertNotNil(error);
    error = nil;
    XCTAssertFalse([engine saveDeployedScriptNamed:@"no-extension" script:@"1;" error:&error]);
    XCTAssertNotNil(error);

    error = nil;
    XCTAssertTrue([engine saveDeployedScriptNamed:oldName script:@"7 * 6;" error:&error]);
    XCTAssertNil(error);
    error = nil;
    XCTAssertEqualObjects([engine deployedScriptContentNamed:oldName error:&error], @"7 * 6;");

    error = nil;
    XCTAssertFalse([engine renameDeployedScriptNamed:oldName toName:@"../escape.js" error:&error]);
    XCTAssertNotNil(error);
    error = nil;
    XCTAssertTrue([engine renameDeployedScriptNamed:oldName toName:newName error:&error]);
    XCTAssertNil(error);
    error = nil;
    XCTAssertNil([engine deployedScriptContentNamed:oldName error:&error]);
    error = nil;
    XCTAssertEqualObjects([engine deployedScriptContentNamed:newName error:&error], @"7 * 6;");

    error = nil;
    XCTAssertTrue([engine saveDeployedScriptNamed:clashName script:@"1;" error:&error]);
    error = nil;
    XCTAssertFalse([engine renameDeployedScriptNamed:newName toName:clashName error:&error]);
    XCTAssertNotNil(error);

    error = nil;
    XCTAssertTrue([engine deleteDeployedScriptNamed:newName error:&error]);
    XCTAssertTrue([engine deleteDeployedScriptNamed:clashName error:&error]);
}


- (void)testDebugImageAssetAndOCRLifecycle {
    AutoEngine *engine = AutoEngine.sharedEngine;
    [engine initWithConfig:@{}];
    [engine setAutomationAdapter:[AutoTestAdapter new]];
    NSString *name = [NSString stringWithFormat:@"template-%@.png", NSUUID.UUID.UUIDString];
    NSString *encoded = [[@"png-data" dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];

    XCTestExpectation *put = [self expectationWithDescription:@"put asset"];
    [engine handleDebugRequest:@{ @"type": @"putAsset", @"name": name, @"dataBase64": encoded }
                       response:^(NSDictionary<NSString *,id> *response) {
        XCTAssertEqualObjects(response[@"ok"], @YES);
        XCTAssertEqualObjects(response[@"path"], [@"debug-assets" stringByAppendingPathComponent:name]);
        [put fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];

    XCTestExpectation *find = [self expectationWithDescription:@"find deployed asset"];
    [engine handleDebugRequest:@{ @"type": @"findImage", @"assetName": name }
                       response:^(NSDictionary<NSString *,id> *response) {
        XCTAssertEqualObjects(response[@"ok"], @YES);
        XCTAssertEqualObjects(response[@"match"][@"found"], @YES);
        [find fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];

    XCTestExpectation *ocr = [self expectationWithDescription:@"test OCR"];
    [engine handleDebugRequest:@{ @"type": @"testOCR", @"region": @{@"x": @0, @"y": @0, @"width": @10, @"height": @10} }
                       response:^(NSDictionary<NSString *,id> *response) {
        XCTAssertEqualObjects(response[@"ok"], @YES);
        XCTAssertEqualObjects(response[@"count"], @1);
        [ocr fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];

    XCTestExpectation *remove = [self expectationWithDescription:@"delete asset"];
    [engine handleDebugRequest:@{ @"type": @"deleteAsset", @"name": name }
                       response:^(NSDictionary<NSString *,id> *response) {
        XCTAssertEqualObjects(response[@"ok"], @YES);
        [remove fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];
}

- (void)testDebugInspectorReturnsOneCorrelatedSnapshot {
    AutoEngine *engine = AutoEngine.sharedEngine;
    [engine initWithConfig:@{}];
    [engine setAutomationAdapter:[AutoTestAdapter new]];
    XCTestExpectation *expectation = [self expectationWithDescription:@"inspector snapshot"];
    [engine handleDebugRequest:@{ @"type": @"inspectSnapshot", @"options": @{ @"maxNodes": @10 } }
                       response:^(NSDictionary<NSString *,id> *response) {
        XCTAssertEqualObjects(response[@"ok"], @YES);
        XCTAssertEqualObjects(response[@"protocolVersion"], @2);
        XCTAssertTrue([response[@"snapshotId"] length] > 0);
        XCTAssertEqual([response[@"nodes"] count], 1);
        XCTAssertTrue([response[@"pngBase64"] length] > 0);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];
}

- (void)testUIKitAdapterReportsItsCapabilities {
    AutoUIKitAdapter *adapter = [AutoUIKitAdapter new];
    NSDictionary *info = [adapter deviceInfo];
    XCTAssertEqualObjects(info[@"adapter"], @"UIKit");
    XCTAssertTrue([info[@"screenScale"] doubleValue] > 0);
}

- (void)testUIKitDeviceInfoCanBeReadFromBackgroundThread {
    AutoUIKitAdapter *adapter = [AutoUIKitAdapter new];
    XCTestExpectation *finished = [self expectationWithDescription:@"background UIKit device info"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSDictionary *info = [adapter deviceInfo];
        XCTAssertEqualObjects(info[@"adapter"], @"UIKit");
        XCTAssertTrue([info[@"screenScale"] doubleValue] > 0);
        [finished fulfill];
    });
    [self waitForExpectationsWithTimeout:2 handler:nil];
}

- (void)testUIKitCancellationInvalidatesScreenshotCacheGenerations {
    AutoUIKitAdapter *adapter = [AutoUIKitAdapter new];
    [adapter setValue:[@"cached" dataUsingEncoding:NSUTF8StringEncoding] forKey:@"screenshotCacheData"];
    [adapter setValue:@123 forKey:@"screenshotCacheTimestamp"];
    NSUInteger operationGeneration = [[adapter valueForKey:@"operationCancellationGeneration"] unsignedIntegerValue];
    NSUInteger cacheGeneration = [[adapter valueForKey:@"screenshotCacheGeneration"] unsignedIntegerValue];

    [adapter cancelCurrentOperations];

    XCTAssertNil([adapter valueForKey:@"screenshotCacheData"]);
    XCTAssertEqual([[adapter valueForKey:@"screenshotCacheTimestamp"] doubleValue], 0);
    XCTAssertEqual([[adapter valueForKey:@"operationCancellationGeneration"] unsignedIntegerValue], operationGeneration + 1);
    XCTAssertEqual([[adapter valueForKey:@"screenshotCacheGeneration"] unsignedIntegerValue], cacheGeneration + 1);
}

- (void)testUIKitRejectsCyclicDeepAndOversizedSelectors {
    AutoUIKitAdapter *adapter = [AutoUIKitAdapter new];
    NSMutableDictionary *cycle = [NSMutableDictionary dictionary];
    cycle[@"selector"] = cycle;
    NSError *error = nil;
    XCTAssertFalse([adapter exists:cycle error:&error]);
    XCTAssertEqual(error.code, AutoSDKErrorInvalidConfiguration);
    XCTAssertTrue([error.localizedDescription containsString:@"cycle"]);
    [cycle removeAllObjects];

    id nested = @{ @"id": @"button" };
    for (NSUInteger index = 0; index < 33; index++) nested = @{ @"selector": nested };
    error = nil;
    XCTAssertFalse([adapter exists:nested error:&error]);
    XCTAssertEqual(error.code, AutoSDKErrorInvalidConfiguration);
    XCTAssertTrue([error.localizedDescription containsString:@"32 levels"]);

    NSString *oversized = [@"x" stringByPaddingToLength:4097 withString:@"x" startingAtIndex:0];
    error = nil;
    XCTAssertFalse([adapter exists:@{ @"id": oversized } error:&error]);
    XCTAssertEqual(error.code, AutoSDKErrorInvalidConfiguration);
}

- (void)testUIKitSingleNodeLookupHonorsCancellationBeforeTraversal {
    AutoCancelledUIKitAdapter *adapter = [AutoCancelledUIKitAdapter new];
    NSError *error = nil;
    XCTAssertFalse([adapter exists:@{ @"id": @"button" } error:&error]);
    XCTAssertEqual(error.code, AutoSDKErrorScriptCancelled);
}

- (void)testUIKitPixelReadUsesTopLeftCoordinatesAndUnpremultipliesRGBA {
    const uint8_t pixels[] = {
        255, 0, 0, 255,   0, 255, 0, 255,
        0, 0, 255, 255,   64, 32, 16, 128
    };
    AutoStaticImageUIKitAdapter *adapter = [AutoStaticImageUIKitAdapter new];
    adapter.testImage = AutoTestRGBAImage(2, 2, pixels);
    XCTAssertNotNil(adapter.testImage);

    NSError *error = nil;
    NSDictionary *topLeft = [adapter pixelColorAtX:0 y:0 error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(topLeft[@"hex"], @"#FF0000");

    NSDictionary *bottomRight = [adapter pixelColorAtX:1 y:1 error:&error];
    XCTAssertNil(error);
    XCTAssertEqualWithAccuracy([bottomRight[@"r"] doubleValue], 128, 1);
    XCTAssertEqualWithAccuracy([bottomRight[@"g"] doubleValue], 64, 1);
    XCTAssertEqualWithAccuracy([bottomRight[@"b"] doubleValue], 32, 1);
    XCTAssertEqualObjects(bottomRight[@"a"], @128);
}

- (void)testUIKitOpaqueBlackTemplateDoesNotMatchTransparentTarget {
    const uint8_t transparent[] = { 0, 0, 0, 0 };
    const uint8_t opaqueBlack[] = { 0, 0, 0, 255 };
    AutoStaticImageUIKitAdapter *adapter = [AutoStaticImageUIKitAdapter new];
    adapter.testImage = AutoTestRGBAImage(1, 1, transparent);
    UIImage *template = AutoTestRGBAImage(1, 1, opaqueBlack);
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"autosdk-template-%@.png", NSUUID.UUID.UUIDString]];
    XCTAssertTrue([UIImagePNGRepresentation(template) writeToFile:path atomically:YES]);
    @try {
        NSError *error = nil;
        NSDictionary *result = [adapter findImageAtPath:path options:@{ @"threshold": @0.99 } error:&error];
        XCTAssertNil(error);
        XCTAssertEqualObjects(result[@"found"], @NO);
    } @finally {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    }
}

- (void)testUIKitRejectsIncompleteAndNonPositiveVisualRegions {
    const uint8_t red[] = { 255, 0, 0, 255 };
    AutoStaticImageUIKitAdapter *adapter = [AutoStaticImageUIKitAdapter new];
    adapter.testImage = AutoTestRGBAImage(1, 1, red);

    NSError *error = nil;
    XCTAssertNil([adapter findColor:@"#FF0000" region:@{ @"x": @0 } options:nil error:&error]);
    XCTAssertNotNil(error);
    error = nil;
    NSDictionary *nonPositiveRegion = @{ @"x": @0, @"y": @0, @"width": @0, @"height": @1 };
    XCTAssertNil([adapter findColor:@"#FF0000"
                             region:nonPositiveRegion
                            options:nil
                              error:&error]);
    XCTAssertNotNil(error);
}

- (void)testDebugServerRejectsMissingToken {
    AutoDebugServer *server = [AutoDebugServer new];
    XCTestExpectation *expectation = [self expectationWithDescription:@"configuration rejection"];
    [server startWithPort:9001 token:@"" requestHandler:^(NSDictionary *request, AutoDebugResponseHandler response) {
        response(@{@"ok": @YES});
    } completion:^(NSError *error) {
        XCTAssertEqual(error.code, AutoSDKErrorInvalidConfiguration);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:1 handler:nil];
}

- (void)testWiFiDebugServerRejectsWeakToken {
    AutoDebugServer *server = [AutoDebugServer new];
    XCTestExpectation *expectation = [self expectationWithDescription:@"Wi-Fi token rejection"];
    [server startWithPort:9001 token:@"short" allowsWiFi:YES requestHandler:^(NSDictionary *request, AutoDebugResponseHandler response) {
        response(@{@"ok": @YES});
    } completion:^(NSError *error) {
        XCTAssertEqual(error.code, AutoSDKErrorInvalidConfiguration);
        XCTAssertTrue([error.localizedDescription containsString:@"at least 16"]);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:1 handler:nil];
}

- (void)testWiFiDebugServerRejectsOversizedBonjourName {
    AutoDebugServer *server = [AutoDebugServer new];
    XCTestExpectation *expectation = [self expectationWithDescription:@"Bonjour name rejection"];
    NSString *name = [@"x" stringByPaddingToLength:64 withString:@"x" startingAtIndex:0];
    [server startWithPort:9001 token:@"strong-development-token" allowsWiFi:YES serviceName:name requestHandler:^(NSDictionary *request, AutoDebugResponseHandler response) {
        response(@{@"ok": @YES});
    } completion:^(NSError *error) {
        XCTAssertEqual(error.code, AutoSDKErrorInvalidConfiguration);
        XCTAssertTrue([error.localizedDescription containsString:@"Bonjour"]);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:1 handler:nil];
}

- (void)testDebugServerRejectsOversizedToken {
    AutoDebugServer *server = [AutoDebugServer new];
    XCTestExpectation *expectation = [self expectationWithDescription:@"oversized token rejection"];
    NSString *token = [@"x" stringByPaddingToLength:1025 withString:@"x" startingAtIndex:0];
    [server startWithPort:9001 token:token requestHandler:^(NSDictionary *request, AutoDebugResponseHandler response) {
        response(@{@"ok": @YES});
    } completion:^(NSError *error) {
        XCTAssertEqual(error.code, AutoSDKErrorInvalidConfiguration);
        XCTAssertTrue([error.localizedDescription containsString:@"1024"]);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:1 handler:nil];
}

- (void)testStoppingAStartingDebugServerCompletesTheStartRequestOnce {
    AutoDebugServer *server = [AutoDebugServer new];
    XCTestExpectation *expectation = [self expectationWithDescription:@"start cancellation"];
    [server startWithPort:19001 token:@"local-token" requestHandler:^(NSDictionary *request, AutoDebugResponseHandler response) {
        response(@{@"ok": @YES});
    } completion:^(NSError *error) {
        if (error) XCTAssertEqual(error.code, AutoSDKErrorDebugServerFailed);
        [expectation fulfill];
    }];
    [server stop];
    [self waitForExpectationsWithTimeout:1 handler:nil];
}

- (void)testEquivalentConcurrentDebugServerStartsShareTheirResult {
    AutoEngine *engine = AutoEngine.sharedEngine;
    [engine initWithConfig:@{ @"debugToken": @"local-token" }];
    XCTestExpectation *first = [self expectationWithDescription:@"first invalid start"];
    XCTestExpectation *second = [self expectationWithDescription:@"second invalid start"];
    [engine startDebugServerWithPort:0 completion:^(NSError *error) {
        XCTAssertEqual(error.code, AutoSDKErrorInvalidConfiguration);
        [first fulfill];
    }];
    [engine startDebugServerWithPort:0 completion:^(NSError *error) {
        XCTAssertEqual(error.code, AutoSDKErrorInvalidConfiguration);
        [second fulfill];
    }];
    [self waitForExpectationsWithTimeout:1 handler:nil];
    [engine stopDebugServer];
}

- (void)testScriptRunsThroughJavaScriptBridge {
    AutoTestAdapter *adapter = [AutoTestAdapter new];
    AutoEngine *engine = AutoEngine.sharedEngine;
    [engine initWithConfig:@{@"scriptTimeout": @5}];
    [engine setAutomationAdapter:adapter];
    XCTestExpectation *expectation = [self expectationWithDescription:@"script completion"];
    [engine runScript:@"console.log('start'); auto.click({id:'button'}); auto.clickPoint(10,20); auto.doubleClickPoint(10,20); auto.getText({id:'title'}); const n=auto.findElement({id:'button'}); auto.findElements({type:'Button'}); auto.exists(n); auto.getAttribute(n,'type'); auto.getBounds(n); auto.getChildren(n); auto.getParent(n); auto.waitFor(n,100); auto.scrollIntoView(n); auto.findColor('#ff0000'); auto.getPixelColor(10,20); auto.compareColors([{x:10,y:20,color:'#ff0000'}]); auto.findMultiColor('#ff0000',[]); auto.ocr(); auto.app.launch('com.example.target'); auto.activateApp('com.example.target'); auto.app.terminate('com.example.target'); const hit=auto.node.at(10,20); auto.node.snapshot(10); auto.screen.cache(true); const cached=auto.screen.isCache(); auto.screen.cache(false); auto.floatLog.show(10,20,120,100); auto.floatLog.log('bridge-ok'); const logVisible=auto.floatLog.isShow(); auto.floatLog.hide(); auto.floatLog.destroy(); const state=auto.appState('com.example.target'); state;" completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(error);
        XCTAssertEqualObjects(result[@"success"], @YES);
        XCTAssertEqualObjects(result[@"logs"][0][@"message"], @"start");
        XCTAssertEqualObjects(result[@"value"], @4);
        XCTAssertEqual(adapter.clickCount, 4);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];
}

- (void)testStopScriptIsANoOpWhileEngineIsIdle {
    AutoTestAdapter *adapter = [AutoTestAdapter new];
    AutoEngine *engine = AutoEngine.sharedEngine;
    [engine initWithConfig:@{}];
    [engine setAutomationAdapter:adapter];
    [engine stopScript];
    XCTAssertEqual(adapter.cancellationCount, 0);
    XCTAssertFalse(engine.isRunning);
}

- (void)testTimedOutScriptDoesNotCancelTheNextRun {
    AutoEngine *engine = AutoEngine.sharedEngine;
    AutoTestAdapter *adapter = [AutoTestAdapter new];
    [engine initWithConfig:@{ @"scriptTimeout": @0.03 }];
    [engine setAutomationAdapter:adapter];

    XCTestExpectation *timedOut = [self expectationWithDescription:@"script timeout"];
    [engine runScript:@"auto.sleep(100); 1;" completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(result);
        XCTAssertEqual(error.code, AutoSDKErrorScriptTimeout);
        [timedOut fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];

    [engine initWithConfig:@{ @"scriptTimeout": @5 }];
    XCTestExpectation *nextRun = [self expectationWithDescription:@"run after timeout"];
    [engine runScript:@"42;" completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(error);
        XCTAssertEqualObjects(result[@"value"], @42);
        [nextRun fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];
}

- (void)testBridgeSleepLoopIsInterruptedByScriptTimeout {
    AutoEngine *engine = AutoEngine.sharedEngine;
    AutoTestAdapter *adapter = [AutoTestAdapter new];
    [engine initWithConfig:@{ @"scriptTimeout": @0.5 }];
    [engine setAutomationAdapter:adapter];

    XCTestExpectation *timedOut = [self expectationWithDescription:@"bridge sleep loop timeout"];
    [engine runScript:@"while(true){auto.sleep(50);}" completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(result);
        XCTAssertEqual(error.code, AutoSDKErrorScriptTimeout);
        [timedOut fulfill];
    }];
    [self waitForExpectationsWithTimeout:5 handler:nil];

    [engine initWithConfig:@{ @"scriptTimeout": @5 }];
    XCTestExpectation *nextRun = [self expectationWithDescription:@"run after bridge loop timeout"];
    [engine runScript:@"40+2;" completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(error);
        XCTAssertEqualObjects(result[@"value"], @42);
        [nextRun fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];
}

- (void)testTimerCallbackBridgeLoopIsInterruptedByScriptTimeout {
    AutoEngine *engine = AutoEngine.sharedEngine;
    AutoTestAdapter *adapter = [AutoTestAdapter new];
    [engine initWithConfig:@{ @"scriptTimeout": @0.5 }];
    [engine setAutomationAdapter:adapter];

    XCTestExpectation *timedOut = [self expectationWithDescription:@"timer bridge loop timeout"];
    [engine runScript:@"setTimeout(function(){ while(true){auto.sleep(50);} }, 0); 1;" completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(result);
        XCTAssertEqual(error.code, AutoSDKErrorScriptTimeout);
        [timedOut fulfill];
    }];
    [self waitForExpectationsWithTimeout:5 handler:nil];

    [engine initWithConfig:@{ @"scriptTimeout": @5 }];
    XCTestExpectation *nextRun = [self expectationWithDescription:@"run after timer bridge loop timeout"];
    [engine runScript:@"42;" completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(error);
        XCTAssertEqualObjects(result[@"value"], @42);
        [nextRun fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];
}

- (void)testAmbiguousInputDistinguishesPathsFromSource {
    AutoEngine *engine = AutoEngine.sharedEngine;
    [engine initWithConfig:@{ @"scriptTimeout": @5 }];
    [engine setAutomationAdapter:[AutoTestAdapter new]];

    XCTestExpectation *divisionExpectation = [self expectationWithDescription:@"division expression"];
    [engine runScript:@"1/2" completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(error);
        XCTAssertEqualObjects(result[@"value"], @0.5);
        [divisionExpectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];

    [engine initWithConfig:@{ @"scriptTimeout": @5 }];
    XCTestExpectation *pathExpectation = [self expectationWithDescription:@"separator path rejection"];
    [engine runScript:@"scripts/nested.js" completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(result);
        XCTAssertEqual(error.code, AutoSDKErrorScriptNotFound);
        [pathExpectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];
}

- (void)testTrailingJsCommentIsNotTreatedAsMissingPath {
    AutoEngine *engine = AutoEngine.sharedEngine;
    [engine initWithConfig:@{ @"scriptTimeout": @5 }];
    [engine setAutomationAdapter:[AutoTestAdapter new]];

    XCTestExpectation *singleLine = [self expectationWithDescription:@"one-line source ending in .js"];
    [engine runScript:@"console.log('x'); // main.js" completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(error);
        XCTAssertEqualObjects(result[@"success"], @YES);
        [singleLine fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];

    [engine initWithConfig:@{ @"scriptTimeout": @5 }];
    XCTestExpectation *multiLine = [self expectationWithDescription:@"source whose last line is a .js comment"];
    [engine runScript:@"42; // run.js" completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(error);
        XCTAssertEqualObjects(result[@"value"], @42);
        [multiLine fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];
}

- (void)testStopBeforeEvaluationInterruptsBridgeSleepLoop {
    AutoEngine *engine = AutoEngine.sharedEngine;
    [engine initWithConfig:@{ @"scriptTimeout": @1 }];
    [engine setAutomationAdapter:[AutoTestAdapter new]];

    XCTestExpectation *stopped = [self expectationWithDescription:@"bridge sleep loop stopped before evaluation"];
    [engine runScript:@"while(true){auto.sleep(50);}" completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(result);
        XCTAssertEqual(error.code, AutoSDKErrorScriptCancelled);
        [stopped fulfill];
    }];
    // runScript: has already passed its synchronous stop check, so this stop
    // deterministically lands before the evaluation's first bridge call.
    [engine stopScript];
    [self waitForExpectationsWithTimeout:3 handler:nil];
}

- (void)testOversizedScriptResultsAreBounded {
    AutoEngine *engine = AutoEngine.sharedEngine;
    [engine initWithConfig:@{ @"scriptTimeout": @5 }];
    [engine setAutomationAdapter:[AutoTestAdapter new]];

    XCTestExpectation *largeArray = [self expectationWithDescription:@"oversized array result is replaced by a marker"];
    [engine runScript:@"Array.from({length: 60000}, function(_, i){ return i; })" completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(error);
        NSDictionary *value = result[@"value"];
        XCTAssertEqualObjects(value[@"__autosdkTruncated"], @YES);
        XCTAssertEqualObjects(value[@"reason"], @"elementCount");
        XCTAssertEqualObjects(value[@"count"], @60000);
        [largeArray fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];

    [engine initWithConfig:@{ @"scriptTimeout": @5 }];
    XCTestExpectation *smallArray = [self expectationWithDescription:@"small arrays pass through unchanged"];
    [engine runScript:@"[1, 2, 3]" completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(error);
        XCTAssertEqualObjects(result[@"value"], (@[@1, @2, @3]));
        [smallArray fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];
}

- (void)testScriptBridgeRejectsNonFiniteCoordinates {
    AutoEngine *engine = AutoEngine.sharedEngine;
    [engine initWithConfig:@{ @"scriptTimeout": @5 }];
    [engine setAutomationAdapter:[AutoTestAdapter new]];
    XCTestExpectation *expectation = [self expectationWithDescription:@"numeric validation"];
    [engine runScript:@"auto.clickPoint(NaN, 20);" completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(result);
        XCTAssertEqual(error.code, AutoSDKErrorInvalidConfiguration);
        XCTAssertTrue([error.localizedDescription containsString:@"finite"]);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];
}

- (void)testHTTPBootstrapAliasesPreserveCompatibility {
    AutoEngine *engine = AutoEngine.sharedEngine;
    [engine initWithConfig:@{ @"scriptTimeout": @5 }];
    [engine setAutomationAdapter:[AutoTestAdapter new]];
    XCTestExpectation *expectation = [self expectationWithDescription:@"HTTP aliases"];
    NSString *script = @"({autoGlobal:auto.http===http,requestSelf:http.request===http,autoRequest:auto.http.request===http,getAliases:http.get===http.httpGet&&http.get===http.httpGetDefault,postAliases:http.post===http.httpPost&&http.post===http.postJSON,downloadAlias:http.downloadFile===http.downloadFileDefault,storageAlias:auto.storage===storages.create,methods:[typeof http.get,typeof http.post,typeof http.downloadFile].join(','),lengths:[http.length,http.get.length,auto.click.length,file.readFile.length].join(','),proxyReserved:auto.then===undefined&&auto.toJSON===undefined&&auto.toString===undefined&&auto.valueOf===undefined&&auto.catch===undefined&&auto.hasOwnProperty===undefined&&auto.__proto__===undefined,proxyStringifyOk:(function(){try{JSON.stringify(auto);return true;}catch(e){return false;}})()})";
    [engine runScript:script completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(error);
        XCTAssertEqualObjects(result[@"value"][@"autoGlobal"], @YES);
        XCTAssertEqualObjects(result[@"value"][@"requestSelf"], @YES);
        XCTAssertEqualObjects(result[@"value"][@"autoRequest"], @YES);
        XCTAssertEqualObjects(result[@"value"][@"getAliases"], @YES);
        XCTAssertEqualObjects(result[@"value"][@"postAliases"], @YES);
        XCTAssertEqualObjects(result[@"value"][@"downloadAlias"], @YES);
        XCTAssertEqualObjects(result[@"value"][@"storageAlias"], @YES);
        XCTAssertEqualObjects(result[@"value"][@"methods"], @"function,function,function");
        XCTAssertEqualObjects(result[@"value"][@"lengths"], @"2,2,1,1");
        XCTAssertEqualObjects(result[@"value"][@"proxyReserved"], @YES);
        XCTAssertEqualObjects(result[@"value"][@"proxyStringifyOk"], @YES);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];
}

- (void)testStopInterruptsARepeatedAutomationBridgeLoop {
    AutoEngine *engine = AutoEngine.sharedEngine;
    [engine initWithConfig:@{ @"scriptTimeout": @5 }];
    [engine setAutomationAdapter:[AutoTestAdapter new]];
    XCTestExpectation *expectation = [self expectationWithDescription:@"bridge loop cancellation"];
    [engine runScript:@"while (true) { auto.click({id:'button'}); }" completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(result);
        XCTAssertEqual(error.code, AutoSDKErrorScriptCancelled);
        [expectation fulfill];
    }];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [NSThread sleepForTimeInterval:0.05];
        [engine stopScript];
    });
    [self waitForExpectationsWithTimeout:2 handler:nil];
}

- (void)testNativeMethodAndRemoteScriptPolicy {
    AutoEngine *engine = AutoEngine.sharedEngine;
    [engine initWithConfig:@{@"scriptTimeout": @5}];
    [engine registerNativeMethod:@"echo" handler:^id(NSArray *args) {
        return args.firstObject ?: [NSNull null];
    }];
    XCTestExpectation *nativeExpectation = [self expectationWithDescription:@"native completion"];
    [engine runScript:@"auto.echo('ok');" completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(error);
        XCTAssertEqualObjects(result[@"value"], @"ok");
        [nativeExpectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];

    XCTestExpectation *remoteExpectation = [self expectationWithDescription:@"remote rejection"];
    [engine runScript:@"https://example.com/script.js" completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(result);
        XCTAssertEqual(error.code, AutoSDKErrorScriptReadFailed);
        [remoteExpectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];

    XCTestExpectation *pathExpectation = [self expectationWithDescription:@"missing path"];
    [engine runScript:@"missing.js" completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(result);
        XCTAssertEqual(error.code, AutoSDKErrorScriptNotFound);
        [pathExpectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];

    [engine initWithConfig:@{@"scriptTimeout": @5}];
    XCTestExpectation *networkExpectation = [self expectationWithDescription:@"network policy"];
    [engine runScript:@"auto.http('https://example.com');" completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(result);
        XCTAssertEqual(error.code, AutoSDKErrorNetworkDisabled);
        [networkExpectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];

    [engine initWithConfig:@{@"maxScriptBytes": @4}];
    XCTestExpectation *sizeExpectation = [self expectationWithDescription:@"size rejection"];
    [engine runScript:@"12345" completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(result);
        XCTAssertEqual(error.code, AutoSDKErrorScriptTooLarge);
        [sizeExpectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];

    [engine initWithConfig:@{@"scriptTimeout": @5}];
    XCTestExpectation *cancelExpectation = [self expectationWithDescription:@"cancel completion"];
    [engine runScript:@"auto.sleep(1000);" completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(result);
        XCTAssertEqual(error.code, AutoSDKErrorScriptCancelled);
        [cancelExpectation fulfill];
    }];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [NSThread sleepForTimeInterval:0.05];
        [engine stopScript];
    });
    [self waitForExpectationsWithTimeout:2 handler:nil];
}

- (void)testJavaScriptLabelIsNotTreatedAsAURLScheme {
    AutoEngine *engine = AutoEngine.sharedEngine;
    [engine initWithConfig:@{@"scriptTimeout": @5}];
    XCTestExpectation *expectation = [self expectationWithDescription:@"labeled JavaScript completion"];
    [engine runScript:@"answer: { 42; }" completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(error);
        XCTAssertEqualObjects(result[@"value"], @42);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];
}

- (void)testJavaScriptExceptionsReturnErrorsWithoutCrashing {
    AutoEngine *engine = AutoEngine.sharedEngine;
    [engine initWithConfig:@{ @"scriptTimeout": @5 }];
    XCTestExpectation *expectation = [self expectationWithDescription:@"JavaScript exception"];
    [engine runScript:@"throw new Error('boom-marker');" completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(result);
        XCTAssertEqual(error.code, AutoSDKErrorJavaScriptException);
        XCTAssertTrue([error.localizedDescription containsString:@"boom-marker"]);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];
}

- (void)testIntervalCanCancelItself {
    AutoEngine *engine = AutoEngine.sharedEngine;
    [engine initWithConfig:@{ @"scriptTimeout": @5 }];
    XCTestExpectation *expectation = [self expectationWithDescription:@"self-cancelling interval"];
    NSString *script = @"const state={count:0};let timer=null;timer=setInterval(function(){state.count++;clearInterval(timer);},1);state;";
    [engine runScript:script completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(error);
        XCTAssertEqualObjects(result[@"value"][@"count"], @1);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];
}

- (void)testScriptCannotReplaceInternalTimerDrainOrAccessNativeBridge {
    AutoEngine *engine = AutoEngine.sharedEngine;
    [engine initWithConfig:@{ @"scriptTimeout": @5 }];
    XCTestExpectation *expectation = [self expectationWithDescription:@"private bootstrap internals"];
    NSString *script = @"const state={internal:[typeof __bridge,typeof __console,typeof __autoDrainTimers].join(','),timer:false};__autoDrainTimers=function(){throw new Error('replaced drain');};setTimeout(function(){state.timer=true;},1);state;";
    [engine runScript:script completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(error);
        XCTAssertEqualObjects(result[@"value"][@"internal"], @"undefined,undefined,undefined");
        XCTAssertEqualObjects(result[@"value"][@"timer"], @YES);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];
}


- (void)testSandboxFilesStorageAndCapabilities {
    AutoEngine *engine = AutoEngine.sharedEngine;
    [engine initWithConfig:@{@"scriptTimeout": @5}];
    XCTestExpectation *expectation = [self expectationWithDescription:@"support modules"];
    NSString *script = @"file.writeFile('tests/runtime.txt','first');"
                        "file.appendLine('tests/runtime.txt','second');"
                        "const text=file.readFile('tests/runtime.txt');"
                        "const lines=file.readLines('tests/runtime.txt');"
                        "file.writeFile('tests/copy-source.txt','copy-value');"
                        "file.writeFile('tests/copy-destination.txt','old-value');"
                        "const copied=file.copy('tests/copy-source.txt','tests/copy-destination.txt',true);"
                        "const copiedText=file.readFile('tests/copy-destination.txt');"
                        "const store=storages.create('runtime-tests');"
                        "store.clear();store.putString('value','saved');"
                        "const result={text:text,lines:lines,copied:copied,copiedText:copiedText,stored:store.getString('value'),runtime:auto.capabilities().runtime,os:device.getOSVersion(),timer:false};"
                        "setTimeout(function(){result.timer=true;},5);"
                        "file.deleteAllFile('tests/runtime.txt');file.deleteAllFile('tests/copy-source.txt');file.deleteAllFile('tests/copy-destination.txt');store.clear();result;";
    [engine runScript:script completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(error);
        XCTAssertEqualObjects(result[@"value"][@"text"], @"firstsecond\n");
        XCTAssertEqualObjects(result[@"value"][@"lines"], (@[@"firstsecond", @""]));
        XCTAssertEqualObjects(result[@"value"][@"copied"], @YES);
        XCTAssertEqualObjects(result[@"value"][@"copiedText"], @"copy-value");
        XCTAssertEqualObjects(result[@"value"][@"stored"], @"saved");
        XCTAssertEqualObjects(result[@"value"][@"runtime"], @"JavaScriptCore");
        XCTAssertTrue([result[@"value"][@"os"] length] > 0);
        XCTAssertEqualObjects(result[@"value"][@"timer"], @YES);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];
}

- (void)testConfigurationSnapshotAndInvalidPermissionTypesFailClosed {
    AutoEngine *engine = AutoEngine.sharedEngine;
    NSMutableArray *hosts = [NSMutableArray arrayWithObject:@"api.example.invalid"];
    NSMutableDictionary *config = [@{ @"allowedNetworkHosts": hosts,
                                       @"allowFileAccess": @"yes",
                                       @"allowFileWrite": @YES,
                                       @"allowStorage": @[] } mutableCopy];
    XCTAssertNoThrow([engine configureWithConfig:config]);
    [hosts removeAllObjects];
    config[@"allowedNetworkHosts"] = @[];

    NSDictionary *snapshot = [engine valueForKey:@"config"];
    XCTAssertEqualObjects(snapshot[@"allowedNetworkHosts"], @[@"api.example.invalid"]);
    NSDictionary *capabilities = [engine capabilityInfo];
    XCTAssertEqualObjects(capabilities[@"fileRead"], @NO);
    XCTAssertEqualObjects(capabilities[@"fileWrite"], @NO);
    XCTAssertEqualObjects(capabilities[@"storage"], @NO);
}

- (void)testInvalidBridgeOptionTypesReturnErrorsInsteadOfNativeExceptions {
    AutoEngine *engine = AutoEngine.sharedEngine;
    [engine configureWithConfig:@{ @"scriptTimeout": @5, @"waitPollInterval": @{} }];
    [engine setAutomationAdapter:[AutoTestAdapter new]];
    XCTestExpectation *waitExpectation = [self expectationWithDescription:@"invalid wait options"];
    [engine runScript:@"auto.waitFor({id:'button'}, {});" completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(error);
        XCTAssertEqualObjects(result[@"value"], @YES);
        [waitExpectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];

    XCTestExpectation *attributeExpectation = [self expectationWithDescription:@"invalid attribute"];
    [engine runScript:@"auto.getAttribute({id:'button'}, null);" completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(result);
        XCTAssertEqual(error.code, AutoSDKErrorInvalidConfiguration);
        [attributeExpectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];
}

- (void)testStorageClearRecoversCorruptDataAndEntryLimitIsEnforced {
    NSString *storageName = @"corrupt-recovery-test";
    NSString *defaultsKey = [@"AutoSDK.storage." stringByAppendingString:storageName];
    [NSUserDefaults.standardUserDefaults setObject:@"not-data" forKey:defaultsKey];

    AutoEngine *engine = AutoEngine.sharedEngine;
    [engine configureWithConfig:@{ @"scriptTimeout": @5, @"maxStorageEntries": @1 }];
    XCTestExpectation *recovered = [self expectationWithDescription:@"storage recovery"];
    NSString *script = [NSString stringWithFormat:
        @"const s=storages.create('%@');s.clear();s.put('first',1);s.get('first');", storageName];
    [engine runScript:script completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(error);
        XCTAssertEqualObjects(result[@"value"], @1);
        [recovered fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];

    XCTestExpectation *limited = [self expectationWithDescription:@"storage entry limit"];
    script = [NSString stringWithFormat:
        @"const s=storages.create('%@');s.put('second',2);", storageName];
    [engine runScript:script completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(result);
        XCTAssertEqual(error.code, AutoSDKErrorStorageFailed);
        [limited fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:defaultsKey];
}

- (void)testTimerHeapExecutesAndCancelsLargeBatches {
    AutoEngine *engine = AutoEngine.sharedEngine;
    [engine configureWithConfig:@{ @"scriptTimeout": @5 }];
    XCTestExpectation *expectation = [self expectationWithDescription:@"timer heap"];
    NSString *script = @"let count=0;for(let i=0;i<2000;i++)setTimeout(function(){count++;},0);"
                        "const cancelled=setTimeout(function(){count=-1;},0);clearTimeout(cancelled);"
                        "const result={get count(){return count;}};result;";
    [engine runScript:script completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(error);
        XCTAssertEqualObjects(result[@"value"][@"count"], @2000);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:3 handler:nil];
}

- (void)testInvalidDeployedScriptCompletionReturnsOnMainQueue {
    AutoEngine *engine = AutoEngine.sharedEngine;
    XCTestExpectation *expectation = [self expectationWithDescription:@"deployed script validation"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [engine runDeployedScriptNamed:@"../invalid.js" completion:^(NSDictionary *result, NSError *error) {
            XCTAssertTrue(NSThread.isMainThread);
            XCTAssertNil(result);
            XCTAssertEqual(error.code, AutoSDKErrorInvalidConfiguration);
            [expectation fulfill];
        }];
    });
    [self waitForExpectationsWithTimeout:2 handler:nil];
}

- (void)testSystemControlCapabilityReflectsConfiguration {
    AutoEngine *engine = AutoEngine.sharedEngine;
    [engine initWithConfig:@{ @"allowSystemControl": @NO }];
    XCTAssertEqualObjects([engine capabilityInfo][@"systemControl"], @NO);
    [engine initWithConfig:@{}];
    XCTAssertEqualObjects([engine capabilityInfo][@"systemControl"], @YES);
}

- (void)testSystemControlDisabledFailsClosedInScripts {
    AutoEngine *engine = AutoEngine.sharedEngine;
    [engine initWithConfig:@{ @"scriptTimeout": @5, @"allowSystemControl": @NO }];
    [engine setAutomationAdapter:[AutoTestAdapter new]];
    XCTestExpectation *brightness = [self expectationWithDescription:@"brightness disabled"];
    [engine runScript:@"device.setBrightness(0.5);" completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(result);
        XCTAssertEqual(error.code, AutoSDKErrorInvalidConfiguration);
        [brightness fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];
    XCTestExpectation *clipboard = [self expectationWithDescription:@"clipboard disabled"];
    [engine runScript:@"device.setClipboard('text');" completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(result);
        XCTAssertEqual(error.code, AutoSDKErrorInvalidConfiguration);
        [clipboard fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];
}

- (void)testMediaLibraryCapabilityReflectsConfiguration {
    AutoEngine *engine = AutoEngine.sharedEngine;
    [engine initWithConfig:@{ @"allowMediaLibrary": @NO }];
    XCTAssertEqualObjects([engine capabilityInfo][@"mediaLibraryWrite"], @NO);
    [engine initWithConfig:@{}];
    XCTAssertEqualObjects([engine capabilityInfo][@"mediaLibraryWrite"], @YES);
}

- (void)testMediaLibraryDisabledFailsClosedInScripts {
    AutoEngine *engine = AutoEngine.sharedEngine;
    [engine initWithConfig:@{ @"scriptTimeout": @5, @"allowMediaLibrary": @NO }];
    [engine setAutomationAdapter:[AutoTestAdapter new]];
    XCTestExpectation *expectation = [self expectationWithDescription:@"media disabled"];
    [engine runScript:@"media.saveImage('x.png');" completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(result);
        XCTAssertEqual(error.code, AutoSDKErrorInvalidConfiguration);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];
}

- (void)testMediaSaveRejectsInvalidInputsBeforePhotoAccess {
    AutoEngine *engine = AutoEngine.sharedEngine;
    [engine initWithConfig:@{ @"scriptTimeout": @5 }];
    [engine setAutomationAdapter:[AutoTestAdapter new]];
    XCTestExpectation *emptyPath = [self expectationWithDescription:@"media empty path"];
    [engine runScript:@"media.saveImage('');" completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(result);
        XCTAssertEqual(error.code, AutoSDKErrorInvalidConfiguration);
        [emptyPath fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];
    XCTestExpectation *invalidBase64 = [self expectationWithDescription:@"media invalid base64"];
    [engine runScript:@"media.saveImageBase64('not-base64!');" completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(result);
        XCTAssertEqual(error.code, AutoSDKErrorFileOperationFailed);
        [invalidBase64 fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];
}

- (void)testOpenURLRejectsUnsafeSchemes {
    AutoEngine *engine = AutoEngine.sharedEngine;
    [engine initWithConfig:@{ @"scriptTimeout": @5 }];
    [engine setAutomationAdapter:[AutoTestAdapter new]];
    XCTestExpectation *expectation = [self expectationWithDescription:@"unsafe openURL"];
    [engine runScript:@"auto.openURL('file:///etc/passwd');" completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(result);
        XCTAssertEqual(error.code, AutoSDKErrorInvalidConfiguration);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];
}

- (void)testOpenURLHTTPSchemeReturnsSystemResult {
    AutoEngine *engine = AutoEngine.sharedEngine;
    [engine initWithConfig:@{ @"scriptTimeout": @5 }];
    [engine setAutomationAdapter:[AutoTestAdapter new]];
    XCTestExpectation *expectation = [self expectationWithDescription:@"openURL result"];
    [engine runScript:@"auto.openURL('https://example.com');" completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(error);
        XCTAssertTrue([result[@"value"] isKindOfClass:NSNumber.class],
                      @"https URLs must pass the scheme check and reach the system");
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];
}

- (void)testSystemAppActionsRequireAdapterSupport {
    AutoEngine *engine = AutoEngine.sharedEngine;
    [engine initWithConfig:@{ @"scriptTimeout": @5 }];
    [engine setAutomationAdapter:[AutoTestAdapter new]];
    XCTestExpectation *expectation = [self expectationWithDescription:@"unsupported homescreen"];
    [engine runScript:@"app.homeScreen();" completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(result);
        XCTAssertEqual(error.code, AutoSDKErrorAutomationUnavailable);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];
}

- (void)testBuiltInToastFallbackAndHostOverride {
    AutoEngine *engine = AutoEngine.sharedEngine;
    [engine initWithConfig:@{ @"scriptTimeout": @5 }];
    [engine setAutomationAdapter:[AutoTestAdapter new]];
    XCTestExpectation *fallback = [self expectationWithDescription:@"built-in toast"];
    [engine runScript:@"var ok = toast('hello'); ok;" completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(error);
        XCTAssertEqualObjects(result[@"value"], @YES);
        [fallback fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];

    [engine registerNativeMethod:@"toast" handler:^id(NSArray *args) { return @42; }];
    XCTestExpectation *override = [self expectationWithDescription:@"host toast override"];
    [engine runScript:@"var v = toast('x'); v;" completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(error);
        XCTAssertEqualObjects(result[@"value"], @42);
        [override fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];
}

- (void)testDeviceMemoryInfoIsExposed {
    AutoEngine *engine = AutoEngine.sharedEngine;
    [engine initWithConfig:@{ @"scriptTimeout": @5 }];
    XCTestExpectation *expectation = [self expectationWithDescription:@"memory info"];
    [engine runScript:@"device.getMemoryInfo();" completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(error);
        XCTAssertTrue([result[@"value"][@"totalBytes"] unsignedLongLongValue] > 0);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];
}

- (void)testFileWriteLinesMoveAndRename {
    AutoEngine *engine = AutoEngine.sharedEngine;
    [engine initWithConfig:@{ @"scriptTimeout": @5 }];
    XCTestExpectation *expectation = [self expectationWithDescription:@"file move"];
    NSString *script = @"file.writeLines('demo/lines.txt', ['one', 'two']);"
                        "const lines = file.readLines('demo/lines.txt');"
                        "file.move('demo/lines.txt', 'demo/moved.txt');"
                        "const moved = file.exists('demo/moved.txt');"
                        "const gone = !file.exists('demo/lines.txt');"
                        "file.rename('demo/moved.txt', 'renamed.txt');"
                        "const renamed = file.exists('demo/renamed.txt');"
                        "file.deleteAllFile('demo/lines.txt');file.deleteAllFile('demo/moved.txt');file.deleteAllFile('demo/renamed.txt');"
                        "({ lines: lines, moved: moved, gone: gone, renamed: renamed });";
    [engine runScript:script completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(error);
        XCTAssertEqualObjects(result[@"value"][@"lines"], (@[@"one", @"two"]));
        XCTAssertEqualObjects(result[@"value"][@"moved"], @YES);
        XCTAssertEqualObjects(result[@"value"][@"gone"], @YES);
        XCTAssertEqualObjects(result[@"value"][@"renamed"], @YES);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];
}

- (void)testDeviceInfoRemainsAvailableWhenSystemControlIsDisabled {
    AutoEngine *engine = AutoEngine.sharedEngine;
    [engine initWithConfig:@{ @"scriptTimeout": @5, @"allowSystemControl": @NO }];
    [engine setAutomationAdapter:[AutoTestAdapter new]];
    XCTestExpectation *expectation = [self expectationWithDescription:@"device info gated off"];
    [engine runScript:@"device.getModel();" completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(error);
        XCTAssertTrue([result[@"value"] length] > 0);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];
}

- (void)testDeviceIPAddressIsExposed {
    AutoEngine *engine = AutoEngine.sharedEngine;
    [engine initWithConfig:@{ @"scriptTimeout": @5 }];
    XCTestExpectation *expectation = [self expectationWithDescription:@"ip address"];
    [engine runScript:@"device.getIPAddress();" completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(error);
        XCTAssertTrue(result[@"value"] == nil || [result[@"value"] isKindOfClass:NSString.class] || [result[@"value"] isKindOfClass:NSNull.class],
                      @"getIPAddress must return a string, null or NSNull");
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];
}

- (void)testNotifyNativeMethodIsExposed {
    AutoEngine *engine = AutoEngine.sharedEngine;
    [engine initWithConfig:@{ @"scriptTimeout": @5 }];
    XCTestExpectation *expectation = [self expectationWithDescription:@"notify"];
    [engine runScript:@"notify('hello', 'AutoSDK');" completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(error);
        XCTAssertEqualObjects(result[@"value"], @YES);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:2 handler:nil];
}

- (void)testImageCompressWritesJPEG {
    AutoEngine *engine = AutoEngine.sharedEngine;
    [engine initWithConfig:@{ @"scriptTimeout": @10 }];
    XCTestExpectation *expectation = [self expectationWithDescription:@"image compress"];
    NSString *script =
        @"file.writeBase64('demo/one.png', 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');"
         "const out = image.compress('demo/one.png', 0.5, 'demo/one-compressed.jpg');"
         "const size = out ? file.stat(out).size : -1;"
         "file.deleteAllFile('demo/one.png');file.deleteAllFile('demo/one-compressed.jpg');"
         "({ out: out, size: size });";
    [engine runScript:script completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(error);
        XCTAssertTrue([result[@"value"][@"out"] isKindOfClass:NSString.class], @"compress must return the destination path");
        XCTAssertTrue([result[@"value"][@"size"] unsignedLongLongValue] > 0, @"compressed file must exist");
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:4 handler:nil];
}

@end
