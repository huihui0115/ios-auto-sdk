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

@interface AutoWDAHTTPAdapter (AutoSDKTests)
- (id)requestPath:(NSString *)path method:(NSString *)method body:(NSDictionary *)body error:(NSError **)error;
- (id)requestSessionSuffix:(NSString *)suffix method:(NSString *)method body:(NSDictionary *)body error:(NSError **)error;
- (id)requestSessionSuffix:(NSString *)suffix method:(NSString *)method body:(NSDictionary *)body usedSession:(NSString **)usedSession error:(NSError **)error;
- (void)invalidateVisualCaches;
- (NSString *)elementPath:(NSString *)elementId session:(NSString *)sessionId suffix:(NSString *)suffix;
- (NSDictionary *)elementInfoFromPayload:(NSDictionary *)payload;
- (NSUInteger)currentOperationCancellationGeneration;
- (BOOL)installCancellationContextForGeneration:(NSUInteger)generation;
- (void)clearCancellationContext;
- (id)requestCleanupPath:(NSString *)path method:(NSString *)method body:(NSDictionary *)body error:(NSError **)error;
- (BOOL)operationWasCancelledSinceGeneration:(NSUInteger)generation;
@end

@interface AutoBlockingSessionWDAAdapter : AutoWDAHTTPAdapter
@property (nonatomic, strong) dispatch_semaphore_t requestStarted;
@property (nonatomic, strong) dispatch_semaphore_t allowResponse;
@property (nonatomic, assign) NSInteger sessionRequestCount;
@property (nonatomic, assign) NSInteger cleanupRequestCount;
@property (nonatomic, assign) NSUInteger cleanupCancellationGeneration;
@end

@implementation AutoBlockingSessionWDAAdapter
- (instancetype)initWithBaseURL:(NSURL *)baseURL {
    self = [super initWithBaseURL:baseURL];
    if (self) {
        _requestStarted = dispatch_semaphore_create(0);
        _allowResponse = dispatch_semaphore_create(0);
    }
    return self;
}
- (id)requestPath:(NSString *)path method:(NSString *)method body:(NSDictionary *)body error:(NSError **)error {
    if ([path isEqualToString:@"/session"] && [method isEqualToString:@"POST"]) {
        @synchronized (self) { self.sessionRequestCount += 1; }
        dispatch_semaphore_signal(self.requestStarted);
        dispatch_semaphore_wait(self.allowResponse, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
        return @{ @"sessionId": @"mock-session", @"value": @{} };
    }
    if ([method isEqualToString:@"DELETE"] && [path hasPrefix:@"/session/"]) {
        @synchronized (self) {
            self.cleanupRequestCount += 1;
            self.cleanupCancellationGeneration = [self currentOperationCancellationGeneration];
        }
    }
    return @{ @"value": @{} };
}
@end

@interface AutoBlockingLongClickWDAAdapter : AutoWDAHTTPAdapter
@property (nonatomic, strong) dispatch_semaphore_t boundsStarted;
@property (nonatomic, strong) dispatch_semaphore_t allowBounds;
@end

@implementation AutoBlockingLongClickWDAAdapter
- (instancetype)initWithBaseURL:(NSURL *)baseURL {
    self = [super initWithBaseURL:baseURL];
    if (self) {
        _boundsStarted = dispatch_semaphore_create(0);
        _allowBounds = dispatch_semaphore_create(0);
    }
    return self;
}
- (NSDictionary *)boundsForSelector:(id)selector error:(NSError **)error {
    dispatch_semaphore_signal(self.boundsStarted);
    dispatch_semaphore_wait(self.allowBounds, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
    return @{ @"centerX": @20, @"centerY": @30 };
}
@end

@interface AutoSettingsWDAAdapter : AutoWDAHTTPAdapter
@property (nonatomic, strong) dispatch_semaphore_t settingsRequestStarted;
@property (nonatomic, strong) dispatch_semaphore_t allowFirstSettingsResponse;
@property (nonatomic, assign) NSInteger settingsRequestCount;
@property (nonatomic, assign) NSInteger settingsFailuresRemaining;
@property (nonatomic, assign) NSInteger settingsHTTPStatus;
@property (nonatomic, assign) NSInteger cleanupRequestCount;
@property (nonatomic, assign) NSUInteger cleanupCancellationGeneration;
@property (nonatomic, copy) NSDictionary *lastAppliedSettings;
@end

@implementation AutoSettingsWDAAdapter
- (instancetype)initWithBaseURL:(NSURL *)baseURL {
    self = [super initWithBaseURL:baseURL];
    if (self) {
        _settingsRequestStarted = dispatch_semaphore_create(0);
        _allowFirstSettingsResponse = dispatch_semaphore_create(0);
    }
    return self;
}
- (id)requestPath:(NSString *)path method:(NSString *)method body:(NSDictionary *)body error:(NSError **)error {
    if ([path isEqualToString:@"/session"] && [method isEqualToString:@"POST"]) {
        return @{ @"sessionId": @"settings-session", @"value": @{} };
    }
    if ([path hasSuffix:@"/appium/settings"] && [method isEqualToString:@"POST"]) {
        NSInteger requestIndex = 0;
        @synchronized (self) {
            self.settingsRequestCount += 1;
            requestIndex = self.settingsRequestCount;
            self.lastAppliedSettings = body[@"settings"];
        }
        if (requestIndex == 1) {
            dispatch_semaphore_signal(self.settingsRequestStarted);
            dispatch_semaphore_wait(self.allowFirstSettingsResponse,
                                    dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
        }
        BOOL shouldFail = NO;
        NSInteger statusCode = 0;
        @synchronized (self) {
            shouldFail = self.settingsFailuresRemaining > 0;
            if (shouldFail) self.settingsFailuresRemaining -= 1;
            statusCode = self.settingsHTTPStatus;
        }
        if (statusCode > 0) {
            if (error) *error = [NSError errorWithDomain:AutoSDKErrorDomain
                                                     code:AutoSDKErrorAutomationFailed
                                                 userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"WDA returned HTTP %ld.", (long)statusCode],
                                                             @"AutoWDAHTTPStatus": @(statusCode) }];
            return nil;
        }
        if (shouldFail) {
            if (error) *error = [NSError errorWithDomain:AutoSDKErrorDomain
                                                     code:AutoSDKErrorAutomationFailed
                                                 userInfo:@{ NSLocalizedDescriptionKey: @"Temporary settings transport failure." }];
            return nil;
        }
        return @{ @"value": @{} };
    }
    if ([method isEqualToString:@"DELETE"] && [path hasPrefix:@"/session/"]) {
        @synchronized (self) {
            self.cleanupRequestCount += 1;
            self.cleanupCancellationGeneration = [self currentOperationCancellationGeneration];
        }
        return @{ @"value": @{} };
    }
    return @{ @"value": @{} };
}
@end

@interface AutoMockWDAAdapter : AutoWDAHTTPAdapter
@property (nonatomic, copy) NSString *sourceXML;
@property (nonatomic, copy) NSArray *elementsValue;
@property (nonatomic, strong) id elementValue;
@property (nonatomic, assign) BOOL elementMissing;
@property (nonatomic, assign) NSInteger sourceRequestCount;
@property (nonatomic, strong) dispatch_semaphore_t sourceRequestStarted;
@property (nonatomic, strong) dispatch_semaphore_t allowSourceResponse;
@end

@implementation AutoMockWDAAdapter
- (id)requestSessionSuffix:(NSString *)suffix method:(NSString *)method body:(NSDictionary *)body usedSession:(NSString **)usedSession error:(NSError **)error {
    if (usedSession) *usedSession = @"mock-session";
    return [self requestSessionSuffix:suffix method:method body:body error:error];
}
- (id)requestSessionSuffix:(NSString *)suffix method:(NSString *)method body:(NSDictionary *)body error:(NSError **)error {
    if ([suffix isEqualToString:@"/source"]) {
        self.sourceRequestCount += 1;
        if (self.sourceRequestStarted) dispatch_semaphore_signal(self.sourceRequestStarted);
        if (self.allowSourceResponse) {
            dispatch_semaphore_wait(self.allowSourceResponse, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
        }
        return @{@"value": self.sourceXML ?: @""};
    }
    if ([suffix isEqualToString:@"/elements"] && self.elementsValue) return @{@"value": self.elementsValue};
    if ([suffix isEqualToString:@"/element"]) {
        if (self.elementMissing) {
            if (error) *error = [NSError errorWithDomain:AutoSDKErrorDomain
                                                     code:AutoSDKErrorElementNotFound
                                                 userInfo:@{ NSLocalizedDescriptionKey: @"no such element",
                                                             @"AutoWDAProtocolError": @"no such element" }];
            return nil;
        }
        return @{@"value": self.elementValue ?: @{}};
    }
    if (error) *error = [NSError errorWithDomain:AutoSDKErrorDomain
                                             code:AutoSDKErrorAutomationFailed
                                         userInfo:@{NSLocalizedDescriptionKey: @"Unexpected mock WDA request."}];
    return nil;
}
@end

@interface AutoScreenshotCancellationWDAAdapter : AutoWDAHTTPAdapter
@property (nonatomic, assign) BOOL blocksNextCancellationCheck;
@property (nonatomic, strong) dispatch_semaphore_t cancellationCheckReached;
@property (nonatomic, strong) dispatch_semaphore_t allowCancellationCheck;
@end

@implementation AutoScreenshotCancellationWDAAdapter
- (instancetype)initWithBaseURL:(NSURL *)baseURL {
    self = [super initWithBaseURL:baseURL];
    if (self) {
        _cancellationCheckReached = dispatch_semaphore_create(0);
        _allowCancellationCheck = dispatch_semaphore_create(0);
    }
    return self;
}
- (BOOL)operationWasCancelledSinceGeneration:(NSUInteger)generation {
    BOOL cancelled = [super operationWasCancelledSinceGeneration:generation];
    BOOL shouldBlock = NO;
    @synchronized (self) {
        shouldBlock = self.blocksNextCancellationCheck;
        self.blocksNextCancellationCheck = NO;
    }
    if (shouldBlock) {
        dispatch_semaphore_signal(self.cancellationCheckReached);
        dispatch_semaphore_wait(self.allowCancellationCheck,
                                dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
    }
    return cancelled;
}
- (id)requestSessionSuffix:(NSString *)suffix method:(NSString *)method body:(NSDictionary *)body error:(NSError **)error {
    if ([suffix isEqualToString:@"/screenshot"]) return @{ @"value": @"Y2FjaGVk" };
    return @{ @"value": @{} };
}
@end

@interface AutoSystemControlWDAAdapter : AutoWDAHTTPAdapter
@property (nonatomic, copy) NSString *lastSystemPath;
@property (nonatomic, copy) NSString *lastSystemMethod;
@end

@implementation AutoSystemControlWDAAdapter
- (id)requestPath:(NSString *)path method:(NSString *)method body:(NSDictionary *)body error:(NSError **)error {
    if ([path hasSuffix:@"/wda/homescreen"] || [path hasSuffix:@"/wda/lock"] || [path hasSuffix:@"/wda/unlock"]) {
        self.lastSystemPath = [path copy];
        self.lastSystemMethod = [method copy];
        return @{ @"value": @{} };
    }
    if ([path isEqualToString:@"/session"] && [method isEqualToString:@"POST"]) {
        return @{ @"sessionId": @"system-session", @"value": @{} };
    }
    return @{ @"value": @{} };
}
@end

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

- (void)testWDASessionCreationDoesNotHoldStateLockAcrossNetwork {
    AutoBlockingSessionWDAAdapter *adapter = [[AutoBlockingSessionWDAAdapter alloc]
        initWithBaseURL:[NSURL URLWithString:@"http://127.0.0.1:8100"]];
    XCTestExpectation *created = [self expectationWithDescription:@"session created"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        XCTAssertTrue([adapter startSession:&error]);
        XCTAssertNil(error);
        [created fulfill];
    });
    XCTAssertEqual(dispatch_semaphore_wait(adapter.requestStarted,
                                           dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)), 0);
    NSDate *started = NSDate.date;
    NSDictionary *info = [adapter deviceInfo];
    XCTAssertEqualObjects(info[@"adapter"], @"WDAHTTP");
    XCTAssertLessThan([NSDate.date timeIntervalSinceDate:started], 0.1);
    dispatch_semaphore_signal(adapter.allowResponse);
    [self waitForExpectationsWithTimeout:2 handler:nil];
}

- (void)testConcurrentWDAStartSessionUsesOneNetworkRequest {
    AutoBlockingSessionWDAAdapter *adapter = [[AutoBlockingSessionWDAAdapter alloc]
        initWithBaseURL:[NSURL URLWithString:@"http://127.0.0.1:8100"]];
    XCTestExpectation *first = [self expectationWithDescription:@"first session caller"];
    XCTestExpectation *second = [self expectationWithDescription:@"second session caller"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        XCTAssertTrue([adapter startSession:nil]);
        [first fulfill];
    });
    XCTAssertEqual(dispatch_semaphore_wait(adapter.requestStarted,
                                           dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)), 0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        XCTAssertTrue([adapter startSession:nil]);
        [second fulfill];
    });
    dispatch_semaphore_signal(adapter.allowResponse);
    [self waitForExpectationsWithTimeout:2 handler:nil];
    XCTAssertEqual(adapter.sessionRequestCount, 1);
}

- (void)testInvalidatedWDAStartResponseUsesCurrentGenerationForCleanup {
    AutoBlockingSessionWDAAdapter *adapter = [[AutoBlockingSessionWDAAdapter alloc]
        initWithBaseURL:[NSURL URLWithString:@"http://127.0.0.1:8100"]];
    XCTestExpectation *finished = [self expectationWithDescription:@"invalidated session response"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        XCTAssertFalse([adapter startSession:&error]);
        XCTAssertEqual(error.code, AutoSDKErrorAutomationFailed);
        [finished fulfill];
    });
    XCTAssertEqual(dispatch_semaphore_wait(adapter.requestStarted,
                                           dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)), 0);
    [adapter invalidateSession];
    [adapter cancelCurrentOperations];
    dispatch_semaphore_signal(adapter.allowResponse);
    [self waitForExpectationsWithTimeout:2 handler:nil];
    XCTAssertEqual(adapter.cleanupRequestCount, 1);
    XCTAssertEqual(adapter.cleanupCancellationGeneration, 1);
}

- (void)testChangingWDABundleUsesCurrentGenerationForSessionCleanup {
    AutoBlockingSessionWDAAdapter *adapter = [[AutoBlockingSessionWDAAdapter alloc]
        initWithBaseURL:[NSURL URLWithString:@"http://127.0.0.1:8100"]];
    dispatch_semaphore_signal(adapter.allowResponse);
    XCTAssertTrue([adapter startSession:nil]);
    XCTAssertTrue([adapter installCancellationContextForGeneration:42]);
    @try {
        adapter.applicationBundleId = @"com.example.changed";
    } @finally {
        [adapter clearCancellationContext];
    }
    XCTAssertEqual(adapter.cleanupRequestCount, 1);
    XCTAssertEqual(adapter.cleanupCancellationGeneration, 1);
}

- (void)testConcurrentWDASettingsApplicationUsesOneNetworkRequest {
    AutoSettingsWDAAdapter *adapter = [[AutoSettingsWDAAdapter alloc]
        initWithBaseURL:[NSURL URLWithString:@"http://127.0.0.1:8100"]];
    XCTAssertTrue([adapter startSession:nil]);
    adapter.sessionSettings = @{ @"animationCoolOffTimeout": @0.2 };
    XCTestExpectation *first = [self expectationWithDescription:@"first settings caller"];
    XCTestExpectation *second = [self expectationWithDescription:@"second settings caller"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        XCTAssertTrue([adapter applySessionSettings:nil]);
        [first fulfill];
    });
    XCTAssertEqual(dispatch_semaphore_wait(adapter.settingsRequestStarted,
                                           dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)), 0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        XCTAssertTrue([adapter applySessionSettings:nil]);
        [second fulfill];
    });
    dispatch_semaphore_signal(adapter.allowFirstSettingsResponse);
    [self waitForExpectationsWithTimeout:2 handler:nil];
    XCTAssertEqual(adapter.settingsRequestCount, 1);
}

- (void)testWDASettingsGenerationAppliesNewestConfiguration {
    AutoSettingsWDAAdapter *adapter = [[AutoSettingsWDAAdapter alloc]
        initWithBaseURL:[NSURL URLWithString:@"http://127.0.0.1:8100"]];
    XCTAssertTrue([adapter startSession:nil]);
    adapter.sessionSettings = @{ @"animationCoolOffTimeout": @0.2 };
    XCTestExpectation *applied = [self expectationWithDescription:@"newest settings applied"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        XCTAssertTrue([adapter applySessionSettings:nil]);
        [applied fulfill];
    });
    XCTAssertEqual(dispatch_semaphore_wait(adapter.settingsRequestStarted,
                                           dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)), 0);
    adapter.sessionSettings = @{ @"animationCoolOffTimeout": @0.5 };
    dispatch_semaphore_signal(adapter.allowFirstSettingsResponse);
    [self waitForExpectationsWithTimeout:2 handler:nil];
    XCTAssertEqual(adapter.settingsRequestCount, 2);
    XCTAssertEqualObjects(adapter.lastAppliedSettings[@"animationCoolOffTimeout"], @0.5);
}

- (void)testTransientWDASettingsFailureIsRetriedAutomatically {
    AutoSettingsWDAAdapter *adapter = [[AutoSettingsWDAAdapter alloc]
        initWithBaseURL:[NSURL URLWithString:@"http://127.0.0.1:8100"]];
    XCTAssertTrue([adapter startSession:nil]);
    adapter.sessionSettings = @{ @"animationCoolOffTimeout": @0.2 };
    adapter.settingsFailuresRemaining = 1;
    dispatch_semaphore_signal(adapter.allowFirstSettingsResponse);
    NSDictionary *handle = @{ @"elementId": @"existing-element", @"sessionId": @"settings-session" };
    XCTAssertNotNil([adapter elementInfoForSelector:handle error:nil]);
    XCTAssertNotNil([adapter elementInfoForSelector:handle error:nil]);
    XCTAssertEqual(adapter.settingsRequestCount, 2);
}

- (void)testUnsupportedWDASettingsHTTPStatusIsRemembered {
    AutoSettingsWDAAdapter *adapter = [[AutoSettingsWDAAdapter alloc]
        initWithBaseURL:[NSURL URLWithString:@"http://127.0.0.1:8100"]];
    XCTAssertTrue([adapter startSession:nil]);
    adapter.sessionSettings = @{ @"animationCoolOffTimeout": @0.2 };
    adapter.settingsHTTPStatus = 404;
    dispatch_semaphore_signal(adapter.allowFirstSettingsResponse);
    NSDictionary *handle = @{ @"elementId": @"existing-element", @"sessionId": @"settings-session" };
    XCTAssertNotNil([adapter elementInfoForSelector:handle error:nil]);
    XCTAssertNotNil([adapter elementInfoForSelector:handle error:nil]);
    XCTAssertEqual(adapter.settingsRequestCount, 1);
}

- (void)testCancelledWDAStartCleansUpWithTheCurrentGeneration {
    AutoSettingsWDAAdapter *adapter = [[AutoSettingsWDAAdapter alloc]
        initWithBaseURL:[NSURL URLWithString:@"http://127.0.0.1:8100"]];
    adapter.sessionSettings = @{ @"animationCoolOffTimeout": @0.2 };
    XCTestExpectation *finished = [self expectationWithDescription:@"cancelled session start"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        XCTAssertFalse([adapter startSession:&error]);
        XCTAssertEqual(error.code, AutoSDKErrorScriptCancelled);
        [finished fulfill];
    });
    XCTAssertEqual(dispatch_semaphore_wait(adapter.settingsRequestStarted,
                                           dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)), 0);
    [adapter cancelCurrentOperations];
    dispatch_semaphore_signal(adapter.allowFirstSettingsResponse);
    [self waitForExpectationsWithTimeout:2 handler:nil];
    XCTAssertEqual(adapter.cleanupRequestCount, 1);
    XCTAssertEqual(adapter.cleanupCancellationGeneration, 1);
}

- (void)testWDACancellationContextsAreIsolatedPerAdapter {
    AutoWDAHTTPAdapter *first = [[AutoWDAHTTPAdapter alloc]
        initWithBaseURL:[NSURL URLWithString:@"http://127.0.0.1:8100"]];
    AutoWDAHTTPAdapter *second = [[AutoWDAHTTPAdapter alloc]
        initWithBaseURL:[NSURL URLWithString:@"http://127.0.0.1:8100"]];
    XCTAssertTrue([first installCancellationContextForGeneration:42]);
    @try {
        XCTAssertEqual([first currentOperationCancellationGeneration], 42);
        XCTAssertEqual([second currentOperationCancellationGeneration], 0);
        XCTAssertTrue([second installCancellationContextForGeneration:7]);
        @try {
            XCTAssertEqual([first currentOperationCancellationGeneration], 42);
            XCTAssertEqual([second currentOperationCancellationGeneration], 7);
        } @finally {
            [second clearCancellationContext];
        }
    } @finally {
        [first clearCancellationContext];
    }
    XCTAssertEqual([first currentOperationCancellationGeneration], 0);
    XCTAssertEqual([second currentOperationCancellationGeneration], 0);
}

- (void)testWDALongClickDoesNotContinueAfterCancellationBetweenRequests {
    AutoBlockingLongClickWDAAdapter *adapter = [[AutoBlockingLongClickWDAAdapter alloc]
        initWithBaseURL:[NSURL URLWithString:@"http://127.0.0.1:8100"]];
    XCTestExpectation *finished = [self expectationWithDescription:@"cancelled long click"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        XCTAssertFalse([adapter longClick:@{ @"id": @"button" } duration:0.5 error:&error]);
        XCTAssertEqual(error.code, AutoSDKErrorScriptCancelled);
        [finished fulfill];
    });
    XCTAssertEqual(dispatch_semaphore_wait(adapter.boundsStarted,
                                           dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)), 0);
    [adapter cancelCurrentOperations];
    dispatch_semaphore_signal(adapter.allowBounds);
    [self waitForExpectationsWithTimeout:2 handler:nil];
}

- (void)testWDASourceDerivedNodeRelationships {
    AutoMockWDAAdapter *adapter = [[AutoMockWDAAdapter alloc] initWithBaseURL:[NSURL URLWithString:@"http://127.0.0.1:8100"]];
    adapter.sourceXML = @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
        @"<XCUIElementTypeApplication type=\"XCUIElementTypeApplication\" name=\"Example\" x=\"0\" y=\"0\" width=\"390\" height=\"844\" enabled=\"true\" visible=\"true\">"
        @"<XCUIElementTypeOther type=\"XCUIElementTypeOther\" name=\"form\" x=\"0\" y=\"40\" width=\"390\" height=\"200\" enabled=\"true\" visible=\"true\">"
        @"<XCUIElementTypeButton type=\"XCUIElementTypeButton\" name=\"login\" label=\"Login\" x=\"20\" y=\"80\" width=\"120\" height=\"44\" enabled=\"true\" visible=\"true\"/>"
        @"<XCUIElementTypeStaticText type=\"XCUIElementTypeStaticText\" name=\"status\" label=\"Ready\" x=\"20\" y=\"140\" width=\"120\" height=\"20\" enabled=\"true\" visible=\"true\"/>"
        @"</XCUIElementTypeOther></XCUIElementTypeApplication>";
    NSError *error = nil;
    NSArray *children = [adapter childrenForSelector:@{@"id": @"form"} error:&error];
    XCTAssertNil(error);
    XCTAssertEqual(children.count, 2);
    NSDictionary *button = children.firstObject;
    XCTAssertEqualObjects(button[@"sourceDerived"], @YES);
    XCTAssertEqualObjects(button[@"type"], @"XCUIElementTypeButton");
    XCTAssertEqualObjects(button[@"bounds"][@"x"], @20);
    XCTAssertEqualObjects(button[@"bounds"][@"y"], @80);
    XCTAssertEqualObjects(button[@"bounds"][@"width"], @120);
    XCTAssertEqualObjects(button[@"bounds"][@"height"], @44);
    XCTAssertNotNil(button[@"nodeId"]);
    XCTAssertNotEqualObjects(button[@"parentId"], NSNull.null);
    XCTAssertTrue([button[@"selector"][@"xpath"] hasSuffix:@"/XCUIElementTypeButton[1]"]);
    NSDictionary *parent = [adapter parentForSelector:button error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(parent[@"name"], @"form");
}

- (void)testWDASourceRelationshipsSurviveWithCachingDisabled {
    AutoMockWDAAdapter *adapter = [[AutoMockWDAAdapter alloc] initWithBaseURL:[NSURL URLWithString:@"http://127.0.0.1:8100"]];
    adapter.sourceCacheDuration = 0;
    adapter.sourceXML = @"<XCUIElementTypeApplication name=\"Example\"><XCUIElementTypeOther name=\"form\"><XCUIElementTypeButton name=\"login\"/></XCUIElementTypeOther></XCUIElementTypeApplication>";
    NSError *error = nil;
    NSDictionary *parent = [adapter parentForSelector:@{ @"id": @"login" } error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(parent[@"name"], @"form");
    NSArray *children = [adapter childrenForSelector:@{ @"id": @"form" } error:&error];
    XCTAssertNil(error);
    XCTAssertEqual(children.count, 1);
    XCTAssertEqualObjects(children.firstObject[@"name"], @"login");
    XCTAssertEqualObjects(children.firstObject[@"selector"][@"xpath"],
                          @"/XCUIElementTypeApplication[1]/XCUIElementTypeOther[1]/XCUIElementTypeButton[1]");
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

- (void)testWDASourceSnapshotCacheAvoidsDuplicateParses {
    AutoMockWDAAdapter *adapter = [[AutoMockWDAAdapter alloc] initWithBaseURL:[NSURL URLWithString:@"http://127.0.0.1:8100"]];
    adapter.sourceCacheDuration = 1.0;
    adapter.sourceXML = @"<XCUIElementTypeApplication name=\"Example\"><XCUIElementTypeOther name=\"form\"><XCUIElementTypeButton name=\"login\"/></XCUIElementTypeOther></XCUIElementTypeApplication>";
    NSError *error = nil;
    XCTAssertNotNil([adapter childrenForSelector:@{ @"id": @"form" } error:&error]);
    XCTAssertNotNil([adapter parentForSelector:@{ @"id": @"login" } error:&error]);
    XCTAssertNil(error);
    XCTAssertEqual(adapter.sourceRequestCount, 1);
}

- (void)testWDASourceSingleFlightSharesConcurrentRequest {
    AutoMockWDAAdapter *adapter = [[AutoMockWDAAdapter alloc] initWithBaseURL:[NSURL URLWithString:@"http://127.0.0.1:8100"]];
    adapter.sourceCacheDuration = 1.0;
    adapter.sourceXML = @"<XCUIElementTypeApplication name=\"Example\"><XCUIElementTypeButton name=\"login\"/></XCUIElementTypeApplication>";
    adapter.sourceRequestStarted = dispatch_semaphore_create(0);
    adapter.allowSourceResponse = dispatch_semaphore_create(0);
    XCTestExpectation *first = [self expectationWithDescription:@"first source"];
    XCTestExpectation *second = [self expectationWithDescription:@"second source"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        XCTAssertNotNil([adapter childrenForSelector:@{@"name": @"Example"} error:nil]);
        [first fulfill];
    });
    XCTAssertEqual(dispatch_semaphore_wait(adapter.sourceRequestStarted,
                                           dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)), 0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        XCTAssertNotNil([adapter childrenForSelector:@{@"name": @"Example"} error:nil]);
        [second fulfill];
    });
    dispatch_semaphore_signal(adapter.allowSourceResponse);
    [self waitForExpectationsWithTimeout:2 handler:nil];
    XCTAssertEqual(adapter.sourceRequestCount, 1);
}

- (void)testWaitingWDASourceRequestDoesNotRestartAfterCancellation {
    AutoMockWDAAdapter *adapter = [[AutoMockWDAAdapter alloc] initWithBaseURL:[NSURL URLWithString:@"http://127.0.0.1:8100"]];
    adapter.sourceXML = @"<XCUIElementTypeApplication name=\"Example\"><XCUIElementTypeButton name=\"login\"/></XCUIElementTypeApplication>";
    adapter.sourceRequestStarted = dispatch_semaphore_create(0);
    adapter.allowSourceResponse = dispatch_semaphore_create(0);
    dispatch_semaphore_t secondContextInstalled = dispatch_semaphore_create(0);
    XCTestExpectation *first = [self expectationWithDescription:@"active source cancelled"];
    XCTestExpectation *second = [self expectationWithDescription:@"waiting source cancelled"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        XCTAssertNil([adapter nodeSnapshotWithMaxResults:10 error:&error]);
        XCTAssertEqual(error.code, AutoSDKErrorScriptCancelled);
        [first fulfill];
    });
    XCTAssertEqual(dispatch_semaphore_wait(adapter.sourceRequestStarted,
                                           dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)), 0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSUInteger generation = [adapter currentOperationCancellationGeneration];
        XCTAssertTrue([adapter installCancellationContextForGeneration:generation]);
        dispatch_semaphore_signal(secondContextInstalled);
        @try {
            NSError *error = nil;
            XCTAssertNil([adapter nodeSnapshotWithMaxResults:10 error:&error]);
            XCTAssertEqual(error.code, AutoSDKErrorScriptCancelled);
        } @finally {
            [adapter clearCancellationContext];
        }
        [second fulfill];
    });
    XCTAssertEqual(dispatch_semaphore_wait(secondContextInstalled,
                                           dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)), 0);
    [adapter cancelCurrentOperations];
    dispatch_semaphore_signal(adapter.allowSourceResponse);
    [self waitForExpectationsWithTimeout:2 handler:nil];
    XCTAssertEqual(adapter.sourceRequestCount, 1);
}

- (void)testWDASourceInvalidationDuringRequestDoesNotCacheStaleTree {
    AutoMockWDAAdapter *adapter = [[AutoMockWDAAdapter alloc] initWithBaseURL:[NSURL URLWithString:@"http://127.0.0.1:8100"]];
    adapter.sourceCacheDuration = 1.0;
    adapter.sourceXML = @"<XCUIElementTypeApplication name=\"Example\"><XCUIElementTypeButton name=\"login\"/></XCUIElementTypeApplication>";
    adapter.sourceRequestStarted = dispatch_semaphore_create(0);
    adapter.allowSourceResponse = dispatch_semaphore_create(0);
    XCTestExpectation *first = [self expectationWithDescription:@"stale source completes"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        XCTAssertNotNil([adapter childrenForSelector:@{@"name": @"Example"} error:nil]);
        [first fulfill];
    });
    XCTAssertEqual(dispatch_semaphore_wait(adapter.sourceRequestStarted,
                                           dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)), 0);
    [adapter invalidateVisualCaches];
    dispatch_semaphore_signal(adapter.allowSourceResponse);
    [self waitForExpectationsWithTimeout:2 handler:nil];
    adapter.sourceRequestStarted = nil;
    adapter.allowSourceResponse = nil;
    XCTAssertNotNil([adapter childrenForSelector:@{@"name": @"Example"} error:nil]);
    XCTAssertEqual(adapter.sourceRequestCount, 2);
}

- (void)testWDASourceInvalidationDoesNotRestoreStaleWindowSize {
    AutoMockWDAAdapter *adapter = [[AutoMockWDAAdapter alloc] initWithBaseURL:[NSURL URLWithString:@"http://127.0.0.1:8100"]];
    adapter.sourceCacheDuration = 1.0;
    adapter.sourceXML = @"<XCUIElementTypeApplication width=\"100\" height=\"200\"><XCUIElementTypeButton name=\"login\"/></XCUIElementTypeApplication>";
    adapter.sourceRequestStarted = dispatch_semaphore_create(0);
    adapter.allowSourceResponse = dispatch_semaphore_create(0);
    XCTestExpectation *finished = [self expectationWithDescription:@"stale source window size"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        XCTAssertNotNil([adapter nodeSnapshotWithMaxResults:10 error:nil]);
        [finished fulfill];
    });
    XCTAssertEqual(dispatch_semaphore_wait(adapter.sourceRequestStarted,
                                           dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)), 0);
    [adapter invalidateVisualCaches];
    dispatch_semaphore_signal(adapter.allowSourceResponse);
    [self waitForExpectationsWithTimeout:2 handler:nil];
    NSValue *cachedWindow = [adapter valueForKey:@"windowSizeCache"];
    XCTAssertTrue(CGSizeEqualToSize(cachedWindow.CGSizeValue, CGSizeZero));
}

- (void)testWDAScreenshotCacheHitRechecksCancellationUnderLock {
    AutoScreenshotCancellationWDAAdapter *adapter = [[AutoScreenshotCancellationWDAAdapter alloc]
        initWithBaseURL:[NSURL URLWithString:@"http://127.0.0.1:8100"]];
    adapter.screenshotCacheDuration = 1.0;
    XCTAssertNotNil([adapter screenshotWithError:nil]);
    adapter.blocksNextCancellationCheck = YES;

    XCTestExpectation *finished = [self expectationWithDescription:@"cancelled cached screenshot"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        XCTAssertNil([adapter screenshotWithError:&error]);
        XCTAssertEqual(error.code, AutoSDKErrorScriptCancelled);
        [finished fulfill];
    });
    XCTAssertEqual(dispatch_semaphore_wait(adapter.cancellationCheckReached,
                                           dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)), 0);
    [adapter cancelCurrentOperations];
    dispatch_semaphore_signal(adapter.allowCancellationCheck);
    [self waitForExpectationsWithTimeout:2 handler:nil];
}

- (void)testWDASourceParserUsesTypeIndexesAndRejectsOversizedTrees {
    AutoMockWDAAdapter *adapter = [[AutoMockWDAAdapter alloc] initWithBaseURL:[NSURL URLWithString:@"http://127.0.0.1:8100"]];
    adapter.sourceXML = @"<XCUIElementTypeApplication name=\"Example\"><XCUIElementTypeOther name=\"one\"/><XCUIElementTypeOther name=\"two\"/></XCUIElementTypeApplication>";
    NSError *error = nil;
    NSArray *children = [adapter childrenForSelector:@{ @"name": @"Example" } error:&error];
    XCTAssertNil(error);
    XCTAssertEqual(children.count, 2);
    XCTAssertEqualObjects(children[0][@"index"], @0);
    XCTAssertEqualObjects(children[1][@"index"], @1);

    adapter.sourceMaxNodes = 2;
    error = nil;
    XCTAssertNil([adapter childrenForSelector:@{ @"name": @"Example" } error:&error]);
    XCTAssertNotNil(error);
    XCTAssertTrue([error.localizedDescription containsString:@"node limit"]);

    adapter.sourceMaxNodes = 50000;
    adapter.sourceMaxBytes = 64;
    error = nil;
    XCTAssertNil([adapter childrenForSelector:@{ @"name": @"Example" } error:&error]);
    XCTAssertNotNil(error);
    XCTAssertTrue([error.localizedDescription containsString:@"byte limit"]);
}

- (void)testWDAElementResultsAreBounded {
    AutoMockWDAAdapter *adapter = [[AutoMockWDAAdapter alloc] initWithBaseURL:[NSURL URLWithString:@"http://127.0.0.1:8100"]];
    NSMutableArray *elements = [NSMutableArray arrayWithCapacity:2500];
    for (NSUInteger index = 0; index < 2500; index++) {
        [elements addObject:@{ @"element-6066-11e4-a52e-4f735466cecf": [NSString stringWithFormat:@"element-%lu", (unsigned long)index] }];
    }
    adapter.elementsValue = elements;
    NSError *error = nil;
    NSArray *defaultResults = [adapter elementsInfoForSelector:@{ @"type": @"Button" } error:&error];
    XCTAssertNil(error);
    XCTAssertEqual(defaultResults.count, 500);
    XCTAssertEqualObjects(defaultResults.firstObject[@"sessionId"], @"mock-session");
    NSArray *boundedResults = [adapter elementsInfoForSelector:@{ @"type": @"Button", @"maxResults": @999999 } error:&error];
    XCTAssertNil(error);
    XCTAssertEqual(boundedResults.count, 2000);
}

- (void)testWDARejectsCyclicDeepAndOversizedSelectors {
    AutoWDAHTTPAdapter *adapter = [[AutoWDAHTTPAdapter alloc]
        initWithBaseURL:[NSURL URLWithString:@"http://127.0.0.1:8100"]];

    NSMutableDictionary *selfCycle = [NSMutableDictionary dictionary];
    selfCycle[@"selector"] = selfCycle;
    NSError *error = nil;
    XCTAssertFalse([adapter exists:selfCycle error:&error]);
    XCTAssertEqual(error.code, AutoSDKErrorInvalidConfiguration);
    XCTAssertTrue([error.localizedDescription containsString:@"cycle"]);
    [selfCycle removeObjectForKey:@"selector"];

    NSMutableDictionary *first = [NSMutableDictionary dictionary];
    NSMutableDictionary *second = [NSMutableDictionary dictionary];
    first[@"selector"] = second;
    second[@"selector"] = first;
    error = nil;
    XCTAssertFalse([adapter exists:first error:&error]);
    XCTAssertEqual(error.code, AutoSDKErrorInvalidConfiguration);
    [first removeAllObjects];
    [second removeAllObjects];

    id nested = @{ @"id": @"button" };
    for (NSUInteger index = 0; index < 33; index++) nested = @{ @"selector": nested };
    error = nil;
    XCTAssertFalse([adapter exists:nested error:&error]);
    XCTAssertEqual(error.code, AutoSDKErrorInvalidConfiguration);
    XCTAssertTrue([error.localizedDescription containsString:@"32 levels"]);

    NSString *oversized = [@"x" stringByPaddingToLength:8193 withString:@"x" startingAtIndex:0];
    error = nil;
    XCTAssertFalse([adapter exists:@{ @"id": oversized } error:&error]);
    XCTAssertEqual(error.code, AutoSDKErrorInvalidConfiguration);

    error = nil;
    NSDictionary *fractionalIndexSelector = @{ @"type": @"Button", @"index": @1.5 };
    XCTAssertFalse([adapter exists:fractionalIndexSelector error:&error]);
    XCTAssertEqual(error.code, AutoSDKErrorInvalidConfiguration);
    error = nil;
    NSDictionary *incompleteBoundsSelector = @{ @"bounds": @{ @"x": @0, @"y": @0, @"width": @10 } };
    XCTAssertFalse([adapter exists:incompleteBoundsSelector error:&error]);
    XCTAssertEqual(error.code, AutoSDKErrorInvalidConfiguration);
}

- (void)testWDARejectsExcessivelyDeepSourceXML {
    AutoMockWDAAdapter *adapter = [[AutoMockWDAAdapter alloc]
        initWithBaseURL:[NSURL URLWithString:@"http://127.0.0.1:8100"]];
    NSMutableString *xml = [NSMutableString string];
    for (NSUInteger index = 0; index < 1025; index++) [xml appendString:@"<XCUIElementTypeOther>"];
    for (NSUInteger index = 0; index < 1025; index++) [xml appendString:@"</XCUIElementTypeOther>"];
    adapter.sourceXML = xml;
    NSError *error = nil;
    XCTAssertNil([adapter nodeSnapshotWithMaxResults:10 error:&error]);
    XCTAssertEqual(error.code, AutoSDKErrorAutomationFailed);
    XCTAssertTrue([error.localizedDescription containsString:@"1024-level"]);
}

- (void)testWDAComplexXPathBypassesSourceTreeConstruction {
    AutoMockWDAAdapter *adapter = [[AutoMockWDAAdapter alloc]
        initWithBaseURL:[NSURL URLWithString:@"http://127.0.0.1:8100"]];
    adapter.sourceXML = @"<XCUIElementTypeApplication/>";
    adapter.elementsValue = @[@{ @"element-6066-11e4-a52e-4f735466cecf": @"button" }];
    NSError *error = nil;
    NSArray *results = [adapter elementsInfoForSelector:@{ @"xpath": @"//XCUIElementTypeButton" } error:&error];
    XCTAssertNil(error);
    XCTAssertEqual(results.count, 1);
    XCTAssertEqual(adapter.sourceRequestCount, 0);
}

- (void)testWDAElementPathsStayBoundToTheirLookupSession {
    AutoWDAHTTPAdapter *adapter = [[AutoWDAHTTPAdapter alloc] initWithBaseURL:[NSURL URLWithString:@"http://127.0.0.1:8100"]];
    NSString *path = [adapter elementPath:@"element/id" session:@"session/one" suffix:@"/click"];
    XCTAssertEqualObjects(path, @"/session/session%2Fone/element/element%2Fid/click");
    NSDictionary *info = [adapter elementInfoFromPayload:@{ @"elementId": @"element-1",
                                                             @"sessionId": @"lookup-session",
                                                             @"selector": @{ @"id": @"login" } }];
    XCTAssertEqualObjects(info[@"sessionId"], @"lookup-session");
}

- (void)testWDAExistsUsesSingleElementLookup {
    AutoMockWDAAdapter *adapter = [[AutoMockWDAAdapter alloc] initWithBaseURL:[NSURL URLWithString:@"http://127.0.0.1:8100"]];
    adapter.elementValue = @{ @"element-6066-11e4-a52e-4f735466cecf": @"one" };
    NSError *error = nil;
    XCTAssertTrue([adapter exists:@{ @"id": @"login" } error:&error]);
    XCTAssertNil(error);
    adapter.elementMissing = YES;
    XCTAssertFalse([adapter exists:@{ @"id": @"missing" } error:&error]);
    XCTAssertNil(error);
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
    [engine runScript:@"console.log('start'); auto.click({id:'button'}); auto.clickPoint(10,20); auto.doubleClickPoint(10,20); auto.getText({id:'title'}); const n=auto.findElement({id:'button'}); auto.findElements({type:'Button'}); auto.exists(n); auto.getAttribute(n,'type'); auto.getBounds(n); auto.getChildren(n); auto.getParent(n); auto.waitFor(n,100); auto.scrollIntoView(n); auto.findColor('#ff0000'); auto.getPixelColor(10,20); auto.compareColors([{x:10,y:20,color:'#ff0000'}]); auto.findMultiColor('#ff0000',[]); auto.ocr(); auto.app.launch('com.example.target'); auto.activateApp('com.example.target'); auto.app.terminate('com.example.target'); const state=auto.appState('com.example.target'); state;" completion:^(NSDictionary *result, NSError *error) {
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

- (void)testWDASystemEndpointsPostToHomescreenLockAndUnlock {
    AutoSystemControlWDAAdapter *adapter = [[AutoSystemControlWDAAdapter alloc]
        initWithBaseURL:[NSURL URLWithString:@"http://127.0.0.1:8100"]];
    XCTAssertTrue([adapter startSession:nil]);
    NSError *error = nil;
    XCTAssertTrue([adapter goToHomeScreenWithError:&error]);
    XCTAssertNil(error);
    XCTAssertTrue([adapter.lastSystemPath hasSuffix:@"/wda/homescreen"]);
    XCTAssertEqualObjects(adapter.lastSystemMethod, @"POST");
    error = nil;
    XCTAssertTrue([adapter lockDeviceWithError:&error]);
    XCTAssertNil(error);
    XCTAssertTrue([adapter.lastSystemPath hasSuffix:@"/wda/lock"]);
    error = nil;
    XCTAssertTrue([adapter unlockDeviceWithError:&error]);
    XCTAssertNil(error);
    XCTAssertTrue([adapter.lastSystemPath hasSuffix:@"/wda/unlock"]);
    XCTAssertEqualObjects(adapter.lastSystemMethod, @"POST");
}

@end
