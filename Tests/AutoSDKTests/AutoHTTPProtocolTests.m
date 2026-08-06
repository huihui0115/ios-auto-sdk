#import <XCTest/XCTest.h>
@import AutoSDK;
#import <UIKit/UIKit.h>

// Deterministic in-process HTTP endpoint backed by a registered NSURLProtocol.
// Only http://autosdk.test requests are intercepted, so no real network traffic
// is produced and adapter tests that talk to local or remote hosts are
// unaffected. This exercises the engine's real shared NSURLSession paths
// (data tasks, download tasks, redirects, byte limits, timeouts and remote
// script downloads) without a network stack.
@interface AutoTestHTTPProtocol : NSURLProtocol
@end

static NSString *const AutoTestHTTPHost = @"autosdk.test";
static NSString *const AutoTestHTTPBase = @"http://autosdk.test";

@implementation AutoTestHTTPProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    return [request.URL.scheme.lowercaseString isEqualToString:@"http"] &&
           [request.URL.host.lowercaseString isEqualToString:AutoTestHTTPHost];
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }

+ (BOOL)requestIsCacheEquivalent:(NSURLRequest *)a toRequest:(NSURLRequest *)b { return NO; }

- (void)startLoading {
    NSString *path = self.request.URL.path ?: @"/";
    if ([path isEqualToString:@"/slow"] || [path isEqualToString:@"/slow-script.js"]) {
        return; // Never respond; tests cancel the task or wait for the timeout.
    }
    NSInteger status = 200;
    NSDictionary *headers = @{ @"Content-Type": @"application/octet-stream" };
    NSData *body = [NSData data];
    if ([path isEqualToString:@"/final"]) {
        body = [@"{\"message\":\"你好，AutoSDK\",\"n\":42}" dataUsingEncoding:NSUTF8StringEncoding];
        headers = @{ @"Content-Type": @"application/json; charset=utf-8" };
    } else if ([path isEqualToString:@"/text"]) {
        body = [@"你好，世界" dataUsingEncoding:NSUTF8StringEncoding];
        headers = @{ @"Content-Type": @"text/plain; charset=utf-8" };
    } else if ([path isEqualToString:@"/redirect"]) {
        status = 302;
        headers = @{ @"Location": [AutoTestHTTPBase stringByAppendingString:@"/final"] };
        body = [NSData data];
    } else if ([path isEqualToString:@"/echo"]) {
        body = self.request.HTTPBody;
        if (!body && self.request.HTTPBodyStream) {
            NSInputStream *stream = self.request.HTTPBodyStream;
            [stream open];
            NSMutableData *streamedBody = [NSMutableData data];
            uint8_t buffer[4096];
            NSInteger read = 0;
            while ((read = [stream read:buffer maxLength:sizeof(buffer)]) > 0) {
                [streamedBody appendBytes:buffer length:(NSUInteger)read];
            }
            [stream close];
            body = streamedBody;
        }
        body = body ?: [NSData data];
        NSString *contentType = self.request.allHTTPHeaderFields[@"Content-Type"];
        headers = @{ @"Content-Type": contentType ?: @"application/octet-stream" };
    } else if ([path isEqualToString:@"/inspect"]) {
        NSData *inspectBody = self.request.HTTPBody;
        if (!inspectBody && self.request.HTTPBodyStream) {
            NSInputStream *stream = self.request.HTTPBodyStream;
            [stream open];
            NSMutableData *streamedBody = [NSMutableData data];
            uint8_t buffer[4096];
            NSInteger read = 0;
            while ((read = [stream read:buffer maxLength:sizeof(buffer)]) > 0) {
                [streamedBody appendBytes:buffer length:(NSUInteger)read];
            }
            [stream close];
            inspectBody = streamedBody;
        }
        NSString *inspectText = [[NSString alloc] initWithData:(inspectBody ?: [NSData data]) encoding:NSUTF8StringEncoding] ?: @"";
        NSDictionary *inspect = @{
            @"method": self.request.HTTPMethod ?: @"",
            @"url": self.request.URL.absoluteString ?: @"",
            @"cookie": self.request.allHTTPHeaderFields[@"Cookie"] ?: @"",
            @"contentType": self.request.allHTTPHeaderFields[@"Content-Type"] ?: @"",
            @"body": inspectText
        };
        NSError *inspectError = nil;
        body = [NSJSONSerialization dataWithJSONObject:inspect options:0 error:&inspectError] ?: [NSData data];
        headers = @{ @"Content-Type": @"application/json; charset=utf-8" };
    } else if ([path isEqualToString:@"/large"]) {
        body = [NSMutableData dataWithLength:64 * 1024];
    } else if ([path isEqualToString:@"/script.js"]) {
        body = [@"40+2;" dataUsingEncoding:NSUTF8StringEncoding];
        headers = @{ @"Content-Type": @"text/javascript; charset=utf-8" };
    }
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL
                                                              statusCode:status
                                                             HTTPVersion:@"HTTP/1.1"
                                                            headerFields:headers];
    id<NSURLProtocolClient> client = self.client;
    [client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [client URLProtocol:self didLoadData:body];
    [client URLProtocolDidFinishLoading:self];
}

- (void)stopLoading {}

@end

// Minimal adapter for HTTP-only tests; UI operations are never exercised here.
@interface AutoHTTPTestAdapter : NSObject <AutoAutomationAdapter>
@end

@implementation AutoHTTPTestAdapter
- (BOOL)click:(id)selector error:(NSError **)error { return YES; }
- (BOOL)longClick:(id)selector duration:(NSTimeInterval)duration error:(NSError **)error { return YES; }
- (BOOL)swipeFromX:(CGFloat)x1 y:(CGFloat)y1 toX:(CGFloat)x2 y:(CGFloat)y2 duration:(NSTimeInterval)duration error:(NSError **)error { return YES; }
- (BOOL)input:(id)selector text:(NSString *)text error:(NSError **)error { return YES; }
- (NSString *)textForSelector:(id)selector error:(NSError **)error { return @"hello"; }
- (NSData *)screenshotWithError:(NSError **)error { return [NSData data]; }
- (NSDictionary *)findImageAtPath:(NSString *)templatePath options:(NSDictionary *)options error:(NSError **)error { return @{@"found": @YES}; }
- (NSArray *)ocrInRegion:(NSDictionary *)region error:(NSError **)error { return @[]; }
- (NSDictionary *)deviceInfo { return @{}; }
- (NSDictionary *)capabilities { return @{}; }
- (void)cancelCurrentOperations {}
@end

@interface AutoHTTPProtocolTests : XCTestCase
@end

@implementation AutoHTTPProtocolTests

- (void)setUp {
    [super setUp];
    [NSURLProtocol registerClass:AutoTestHTTPProtocol.class];
    [AutoEngine.sharedEngine setAutomationAdapter:[AutoHTTPTestAdapter new]];
}

- (void)tearDown {
    [NSURLProtocol unregisterClass:AutoTestHTTPProtocol.class];
    [super tearDown];
}

- (void)runScript:(NSString *)script
      withConfig:(NSDictionary *)config
      completion:(void (^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion {
    NSMutableDictionary *mergedConfig = [NSMutableDictionary dictionaryWithDictionary:config ?: @{}];
    mergedConfig[@"urlProtocolClasses"] = @[AutoTestHTTPProtocol.class];
    [AutoEngine.sharedEngine initWithConfig:mergedConfig];
    [AutoEngine.sharedEngine runScript:script completion:completion];
}

- (void)testHTTPDataRequestParsesUTF8JSONBody {
    XCTestExpectation *expectation = [self expectationWithDescription:@"http get"];
    [self runScript:@"auto.http.get('http://autosdk.test/final');"
         withConfig:@{@"allowNetwork": @YES, @"scriptTimeout": @5}
         completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(error);
        XCTAssertEqualObjects(result[@"value"][@"status"], @200);
        XCTAssertEqualObjects(result[@"value"][@"json"][@"message"], @"你好，AutoSDK");
        XCTAssertEqualObjects(result[@"value"][@"json"][@"n"], @42);
        XCTAssertTrue([result[@"value"][@"body"] containsString:@"AutoSDK"]);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:5 handler:nil];
}

- (void)testRedirectRouterFollowsSameSchemeByDefault {
    // The shared session cannot follow a redirect produced by a custom
    // NSURLProtocol (the delegate is not consulted for protocol responses),
    // so the follow policy is verified directly against the router.
    AutoHTTPRedirectRouter *router = [AutoHTTPRedirectRouter new];
    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionTask *task = [session dataTaskWithURL:[NSURL URLWithString:@"http://autosdk.test/redirect"]];
    AutoHTTPRedirectPolicy *policy = [AutoHTTPRedirectPolicy new];
    policy.followsRedirects = YES;
    [router setPolicy:policy forTask:task];

    NSHTTPURLResponse *redirectResponse = [[NSHTTPURLResponse alloc] initWithURL:task.originalRequest.URL
                                                                      statusCode:302
                                                                     HTTPVersion:@"HTTP/1.1"
                                                                    headerFields:@{@"Location": @"http://autosdk.test/final"}];
    NSURLRequest *newRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://autosdk.test/final"]];
    __block NSURLRequest *approvedRequest = nil;
    [router URLSession:session task:task willPerformHTTPRedirection:redirectResponse newRequest:newRequest
     completionHandler:^(NSURLRequest * _Nullable request) { approvedRequest = request; }];
    XCTAssertNotNil(approvedRequest);
    XCTAssertEqualObjects(approvedRequest.URL.absoluteString, @"http://autosdk.test/final");
    [router removePolicyForTask:task];
}

- (void)testRedirectRouterBlocksUnsafeRedirects {
    AutoHTTPRedirectRouter *router = [AutoHTTPRedirectRouter new];
    NSURLSession *session = [NSURLSession sharedSession];
    AutoHTTPRedirectPolicy *policy = [AutoHTTPRedirectPolicy new];
    policy.followsRedirects = YES;

    NSURLSessionTask *downgradeTask = [session dataTaskWithURL:[NSURL URLWithString:@"https://autosdk.test/redirect"]];
    [router setPolicy:policy forTask:downgradeTask];
    NSHTTPURLResponse *downgradeResponse = [[NSHTTPURLResponse alloc] initWithURL:downgradeTask.originalRequest.URL
                                                                      statusCode:302
                                                                     HTTPVersion:@"HTTP/1.1"
                                                                    headerFields:@{@"Location": @"http://autosdk.test/final"}];
    NSURLRequest *downgradeRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://autosdk.test/final"]];
    __block NSURLRequest *approved = nil;
    [router URLSession:session task:downgradeTask willPerformHTTPRedirection:downgradeResponse newRequest:downgradeRequest
     completionHandler:^(NSURLRequest * _Nullable request) { approved = request; }];
    XCTAssertNil(approved, @"HTTPS-to-HTTP downgrades must be rejected");
    [router removePolicyForTask:downgradeTask];

    NSURLSessionTask *schemeTask = [session dataTaskWithURL:[NSURL URLWithString:@"http://autosdk.test/redirect"]];
    [router setPolicy:policy forTask:schemeTask];
    NSHTTPURLResponse *schemeResponse = [[NSHTTPURLResponse alloc] initWithURL:schemeTask.originalRequest.URL
                                                                   statusCode:302
                                                                  HTTPVersion:@"HTTP/1.1"
                                                                 headerFields:@{@"Location": @"file:///tmp/x"}];
    NSURLRequest *schemeRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:@"file:///tmp/x"]];
    approved = nil;
    [router URLSession:session task:schemeTask willPerformHTTPRedirection:schemeResponse newRequest:schemeRequest
     completionHandler:^(NSURLRequest * _Nullable request) { approved = request; }];
    XCTAssertNil(approved, @"Non-http(s) redirect targets must be rejected");
    [router removePolicyForTask:schemeTask];

    AutoHTTPRedirectPolicy *blockedPolicy = [AutoHTTPRedirectPolicy new];
    blockedPolicy.followsRedirects = NO;
    NSURLSessionTask *blockedTask = [session dataTaskWithURL:[NSURL URLWithString:@"http://autosdk.test/redirect"]];
    [router setPolicy:blockedPolicy forTask:blockedTask];
    NSHTTPURLResponse *blockedResponse = [[NSHTTPURLResponse alloc] initWithURL:blockedTask.originalRequest.URL
                                                                    statusCode:302
                                                                   HTTPVersion:@"HTTP/1.1"
                                                                  headerFields:@{@"Location": @"http://autosdk.test/final"}];
    NSURLRequest *blockedRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://autosdk.test/final"]];
    approved = nil;
    [router URLSession:session task:blockedTask willPerformHTTPRedirection:blockedResponse newRequest:blockedRequest
     completionHandler:^(NSURLRequest * _Nullable request) { approved = request; }];
    XCTAssertNil(approved, @"followRedirects:NO must block the redirect");
    [router removePolicyForTask:blockedTask];
}

- (void)testRedirectRouterEnforcesHostAllowlist {
    AutoHTTPRedirectRouter *router = [AutoHTTPRedirectRouter new];
    NSURLSession *session = [NSURLSession sharedSession];
    AutoHTTPRedirectPolicy *policy = [AutoHTTPRedirectPolicy new];
    policy.followsRedirects = YES;
    policy.allowedHosts = @[@"autosdk.test"];

    NSURLSessionTask *allowedTask = [session dataTaskWithURL:[NSURL URLWithString:@"http://autosdk.test/redirect"]];
    [router setPolicy:policy forTask:allowedTask];
    NSHTTPURLResponse *allowedResponse = [[NSHTTPURLResponse alloc] initWithURL:allowedTask.originalRequest.URL
                                                                    statusCode:302
                                                                   HTTPVersion:@"HTTP/1.1"
                                                                  headerFields:@{@"Location": @"http://autosdk.test/final"}];
    NSURLRequest *allowedRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://autosdk.test/final"]];
    __block NSURLRequest *approved = nil;
    [router URLSession:session task:allowedTask willPerformHTTPRedirection:allowedResponse newRequest:allowedRequest
     completionHandler:^(NSURLRequest * _Nullable request) { approved = request; }];
    XCTAssertNotNil(approved);
    XCTAssertEqualObjects(approved.URL.absoluteString, @"http://autosdk.test/final");
    [router removePolicyForTask:allowedTask];

    NSURLSessionTask *deniedTask = [session dataTaskWithURL:[NSURL URLWithString:@"http://autosdk.test/redirect"]];
    [router setPolicy:policy forTask:deniedTask];
    NSHTTPURLResponse *deniedResponse = [[NSHTTPURLResponse alloc] initWithURL:deniedTask.originalRequest.URL
                                                                   statusCode:302
                                                                  HTTPVersion:@"HTTP/1.1"
                                                                 headerFields:@{@"Location": @"http://example.com/final"}];
    NSURLRequest *deniedRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://example.com/final"]];
    approved = nil;
    [router URLSession:session task:deniedTask willPerformHTTPRedirection:deniedResponse newRequest:deniedRequest
     completionHandler:^(NSURLRequest * _Nullable request) { approved = request; }];
    XCTAssertNil(approved, @"Redirects outside the allowlist must be rejected");
    [router removePolicyForTask:deniedTask];
}

- (void)testHTTPRedirectCanBeDisabledPerRequest {
    XCTestExpectation *expectation = [self expectationWithDescription:@"redirect blocked"];
    [self runScript:@"auto.http.get('http://autosdk.test/redirect',{followRedirects:false});"
         withConfig:@{@"allowNetwork": @YES, @"scriptTimeout": @5}
         completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(error);
        XCTAssertEqualObjects(result[@"value"][@"status"], @302);
        XCTAssertTrue([result[@"value"][@"url"] containsString:@"/redirect"]);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:5 handler:nil];
}

- (void)testHTTPResponseByteLimitIsEnforced {
    XCTestExpectation *expectation = [self expectationWithDescription:@"response limit"];
    [self runScript:@"auto.http.get('http://autosdk.test/large');"
         withConfig:@{@"allowNetwork": @YES, @"maxHTTPResponseBytes": @200, @"scriptTimeout": @5}
         completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(result);
        XCTAssertEqual(error.code, AutoSDKErrorNetworkFailed);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:5 handler:nil];
}

- (void)testHTTPTimeoutIsEnforced {
    XCTestExpectation *expectation = [self expectationWithDescription:@"http timeout"];
    [self runScript:@"auto.http.get('http://autosdk.test/slow',{timeout:100});"
         withConfig:@{@"allowNetwork": @YES, @"scriptTimeout": @5}
         completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(result);
        XCTAssertEqual(error.code, AutoSDKErrorNetworkFailed);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:5 handler:nil];
}

- (void)testHTTPJSONBodyIsSentWithContentType {
    XCTestExpectation *expectation = [self expectationWithDescription:@"post echo"];
    [self runScript:@"auto.http.post('http://autosdk.test/echo',{a:1,b:'x'});"
         withConfig:@{@"allowNetwork": @YES, @"scriptTimeout": @5}
         completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(error);
        XCTAssertEqualObjects(result[@"value"][@"json"][@"a"], @1);
        XCTAssertEqualObjects(result[@"value"][@"json"][@"b"], @"x");
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:5 handler:nil];
}

- (void)testHTTPDownloadWritesSandboxFile {
    XCTestExpectation *expectation = [self expectationWithDescription:@"download"];
    [self runScript:@"auto.http.downloadFile('http://autosdk.test/final','tests/http-download.json');"
         withConfig:@{@"allowNetwork": @YES, @"allowFileWrite": @YES, @"scriptTimeout": @5}
         completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(error);
        XCTAssertEqualObjects(result[@"value"], @YES);
        NSString *documents = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        NSString *downloadedPath = [[documents stringByAppendingPathComponent:@"AutoSDK"]
            stringByAppendingPathComponent:@"tests/http-download.json"];
        NSString *content = [NSString stringWithContentsOfFile:downloadedPath encoding:NSUTF8StringEncoding error:nil];
        XCTAssertTrue([content containsString:@"你好，AutoSDK"]);
        [[NSFileManager defaultManager] removeItemAtPath:downloadedPath error:nil];
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:5 handler:nil];
}

- (void)testRemoteScriptDownloadRuns {
    XCTestExpectation *expectation = [self expectationWithDescription:@"remote script"];
    [self runScript:@"http://autosdk.test/script.js"
         withConfig:@{@"allowRemoteScripts": @YES, @"scriptTimeout": @5}
         completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(error);
        XCTAssertEqualObjects(result[@"value"], @42);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:5 handler:nil];
}

- (void)testStopScriptCancelsRemoteDownload {
    XCTestExpectation *expectation = [self expectationWithDescription:@"cancel remote"];
    [self runScript:@"http://autosdk.test/slow-script.js"
         withConfig:@{@"allowRemoteScripts": @YES, @"remoteScriptTimeout": @10, @"scriptTimeout": @5}
         completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(result);
        XCTAssertEqual(error.code, AutoSDKErrorScriptCancelled);
        [expectation fulfill];
    }];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [NSThread sleepForTimeInterval:0.1];
        [AutoEngine.sharedEngine stopScript];
    });
    [self waitForExpectationsWithTimeout:5 handler:nil];
}

- (void)testHTTPSameSessionServesConsecutiveRequests {
    // Two sequential requests over the same shared session: the second request
    // must still resolve through the registered protocol after the first one
    // completed, proving the session is not invalidated per request.
    XCTestExpectation *first = [self expectationWithDescription:@"first request"];
    [self runScript:@"auto.http.get('http://autosdk.test/text');"
         withConfig:@{@"allowNetwork": @YES, @"scriptTimeout": @5}
         completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(error);
        XCTAssertEqualObjects(result[@"value"][@"body"], @"你好，世界");
        [first fulfill];
    }];
    [self waitForExpectationsWithTimeout:5 handler:nil];

    XCTestExpectation *second = [self expectationWithDescription:@"second request"];
    [self runScript:@"auto.http.get('http://autosdk.test/final');"
         withConfig:@{@"allowNetwork": @YES, @"scriptTimeout": @5}
         completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(error);
        XCTAssertEqualObjects(result[@"value"][@"json"][@"n"], @42);
        [second fulfill];
    }];
    [self waitForExpectationsWithTimeout:5 handler:nil];
}

- (void)testHTTPMultipartUploadEchoesBoundaryAndFile {
    XCTestExpectation *expectation = [self expectationWithDescription:@"multipart upload"];
    NSString *script =
        @"file.writeText('tests/up.txt', 'upload-payload-123');"
         "const r = http.post('http://autosdk.test/inspect', { files: { file: 'tests/up.txt' }, formData: { note: 'hi' } });"
         "file.deleteAllFile('tests/up.txt');"
         "({ body: r.body, json: r.json });";
    [self runScript:script
         withConfig:@{@"allowNetwork": @YES, @"allowFileWrite": @YES, @"scriptTimeout": @5}
         completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(error);
        NSDictionary *json = result[@"value"][@"json"];
        NSString *contentType = json[@"contentType"] ?: @"";
        NSString *body = json[@"body"] ?: @"";
        XCTAssertTrue([contentType containsString:@"multipart/form-data; boundary="], @"Content-Type must be multipart with a boundary");
        XCTAssertTrue([body containsString:@"name=\"note\""] && [body containsString:@"hi"], @"formData field must be included");
        XCTAssertTrue([body containsString:@"name=\"file\"; filename=\"up.txt\""], @"file part must carry the field name and filename");
        XCTAssertTrue([body containsString:@"upload-payload-123"], @"file content must be uploaded");
        XCTAssertTrue([body hasSuffix:@"--\r\n"] || [body containsString:@"--AutoSDKBoundary"], @"multipart body must be terminated");
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:5 handler:nil];
}

- (void)testHTTPCookiesAndParamsForwarded {
    XCTestExpectation *expectation = [self expectationWithDescription:@"cookies and params"];
    NSString *script =
        @"const r = http.get('http://autosdk.test/inspect?existing=1', { params: { b: 2 }, cookies: { sid: 'abc' } });"
         "({ url: r.json.url, cookie: r.json.cookie });";
    [self runScript:script
         withConfig:@{@"allowNetwork": @YES, @"scriptTimeout": @5}
         completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(error);
        XCTAssertEqualObjects(result[@"value"][@"url"], @"http://autosdk.test/inspect?existing=1&b=2");
        XCTAssertEqualObjects(result[@"value"][@"cookie"], @"sid=abc");
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:5 handler:nil];
}

@end
