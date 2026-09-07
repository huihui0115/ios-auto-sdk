#import <XCTest/XCTest.h>
@import AutoSDK;
#import <UIKit/UIKit.h>
#import "../../Sources/AutoSDK/AutoResourcePolicy.h"
#import "../../Sources/AutoSDK/AutoBackgroundLease.h"

@interface AutoResourcePolicyTests : XCTestCase
@end
@implementation AutoResourcePolicyTests
- (void)testLowMemoryPolicyAndOverflowSafeDimensions {
    XCTAssertTrue(AutoUsesLowMemoryProfile(2ULL * 1024 * 1024 * 1024));
    XCTAssertTrue(AutoUsesLowMemoryProfile(0));
    XCTAssertFalse(AutoUsesLowMemoryProfile(3ULL * 1024 * 1024 * 1024));
    XCTAssertEqual(AutoDecodedImageBudget(2ULL * 1024 * 1024 * 1024), 16 * 1024 * 1024);
    XCTAssertTrue(AutoImageFitsBudget(750, 1334, 16 * 1024 * 1024));
    XCTAssertFalse(AutoImageFitsBudget(16384, 16384, 16 * 1024 * 1024));
    XCTAssertFalse(AutoImageFitsBudget(SIZE_MAX, SIZE_MAX, NSUIntegerMax));
    XCTAssertFalse(AutoImageFitsBudget(0, 1, 64));
    XCTAssertFalse(AutoImageFitsBudget(4, 4, 63));
    XCTAssertTrue(AutoImageFitsBudget(4, 4, 64));
}
- (void)testImageMetadataBudgetRejectsBeforePixelDecode {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(4, 4), YES, 1);
    [UIColor.redColor setFill]; UIRectFill(CGRectMake(0, 0, 4, 4));
    NSData *png = UIImagePNGRepresentation(UIGraphicsGetImageFromCurrentImageContext());
    UIGraphicsEndImageContext();
    CGImageRef rejected = AutoCreateBudgetedImage(png, 63);
    XCTAssertEqual(rejected, NULL);
    if (rejected) CGImageRelease(rejected);
    CGImageRef accepted = AutoCreateBudgetedImage(png, 64);
    XCTAssertNotEqual(accepted, NULL);
    if (accepted) CGImageRelease(accepted);
    XCTAssertEqual(AutoCreateBudgetedImage([@"not an image" dataUsingEncoding:NSUTF8StringEncoding], 64), NULL);
}
- (NSArray *)walk:(NSDictionary *)tree nodes:(NSUInteger)nodes depth:(NSUInteger)depth results:(NSUInteger)results
           filter:(BOOL (^)(NSDictionary *))filter visits:(NSMutableArray *)visits cancelled:(BOOL (^)(void))cancelled error:(NSError **)error {
    return AutoBoundedNodeWalk(tree, nodes, depth, results,
        ^NSDictionary *(id node, NSString *path, NSString *parent, NSUInteger depth, NSUInteger index) {
            [visits addObject:node[@"name"]];
            return @{ @"name": node[@"name"], @"handle": [@"axb:" stringByAppendingString:path], @"parent": parent, @"depth": @(depth), @"index": @(index) };
        }, ^NSArray *(id node) { return node[@"children"] ?: @[]; }, filter, cancelled ?: ^BOOL { return NO; }, error);
}
- (NSDictionary *)tree {
    return @{ @"name": @"root", @"children": @[
        @{ @"name": @"a", @"children": @[@{ @"name": @"a1" }] }, @{ @"name": @"b" }] };
}
- (void)testWalkPreservesPreorderAndHandles {
    NSMutableArray *visits = [NSMutableArray array]; NSError *error = nil;
    NSArray *result = [self walk:self.tree nodes:10 depth:10 results:10 filter:nil visits:visits cancelled:nil error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(visits, (@[@"root", @"a", @"a1", @"b"]));
    XCTAssertEqualObjects(result[2][@"handle"], @"axb:0.0");
    XCTAssertEqualObjects(result[2][@"parent"], @"axb:0");
}
- (void)testFilteredMissCannotTraversePastVisitBudget {
    NSMutableArray *visits = [NSMutableArray array]; NSError *error = nil;
    NSArray *result = [self walk:self.tree nodes:2 depth:10 results:1 filter:^BOOL(NSDictionary *node) { return NO; }
        visits:visits cancelled:nil error:&error];
    XCTAssertNil(result); XCTAssertEqual(visits.count, 2u); XCTAssertNotNil(error);
    XCTAssertEqual(error.code, AutoSDKErrorAutomationFailed);
    XCTAssertEqualObjects(visits, (@[@"root", @"a"]));
}
- (void)testDepthLimitedMissReportsIncompleteSearch {
    NSError *error = nil;
    XCTAssertNil([self walk:self.tree nodes:10 depth:1 results:1 filter:^BOOL(NSDictionary *node) { return NO; }
        visits:[NSMutableArray array] cancelled:nil error:&error]);
    XCTAssertNotNil(error);
}
- (void)testCompleteFilteredMissReturnsEmptyResultsWithoutBudgetError {
    NSMutableArray *visits = [NSMutableArray array]; NSError *error = nil;
    NSArray *result = [self walk:self.tree nodes:10 depth:10 results:1 filter:^BOOL(NSDictionary *node) { return NO; }
        visits:visits cancelled:nil error:&error];
    XCTAssertNotNil(result); XCTAssertEqual(result.count, 0u);
    XCTAssertEqual(visits.count, 4u); XCTAssertNil(error);
}
- (void)testFirstMatchStopsWithoutExpandingRemainingTree {
    NSMutableArray *visits = [NSMutableArray array]; NSError *error = nil;
    NSArray *result = [self walk:self.tree nodes:2 depth:1 results:1 filter:^BOOL(NSDictionary *node) { return [node[@"name"] isEqual:@"a"]; }
        visits:visits cancelled:nil error:&error];
    XCTAssertEqual(result.count, 1u); XCTAssertNil(error); XCTAssertEqual(visits.count, 2u);
}
- (void)testCancellationDuringMatchDoesNotReturnSuccess {
    __block BOOL stop = NO; NSError *error = nil;
    NSArray *result = [self walk:self.tree nodes:10 depth:10 results:1 filter:^BOOL(NSDictionary *node) { stop = YES; return YES; }
        visits:[NSMutableArray array] cancelled:^BOOL { return stop; } error:&error];
    XCTAssertNil(result); XCTAssertEqual(error.code, AutoSDKErrorScriptCancelled);
}
- (void)testRepeatedWalksReleaseTheirResults {
    __weak NSArray *lastResult;
    for (NSUInteger i = 0; i < 200; i++) {
        @autoreleasepool {
            NSArray *result = [self walk:self.tree nodes:10 depth:10 results:10 filter:nil
                visits:[NSMutableArray array] cancelled:nil error:nil];
            lastResult = result; XCTAssertNotNil(lastResult);
        }
        XCTAssertNil(lastResult);
    }
}
- (void)testHighFanoutAndCycleStayWithinBudget {
    NSMutableArray *children = [NSMutableArray array];
    for (NSUInteger i = 0; i < 2000; i++) [children addObject:@{ @"name": @"child" }];
    NSMutableArray *visits = [NSMutableArray array]; NSError *error = nil;
    [self walk:@{ @"name": @"root", @"children": children } nodes:16 depth:10 results:1 filter:^BOOL(NSDictionary *node) { return NO; }
        visits:visits cancelled:nil error:&error];
    XCTAssertEqual(visits.count, 16u); XCTAssertNotNil(error);
    __block NSUInteger count = 0;
    NSArray *result = AutoBoundedNodeWalk(@1, 8, 60, 1,
        ^NSDictionary *(id node, NSString *path, NSString *parent, NSUInteger depth, NSUInteger index) { count++; return @{ @"handle": path }; },
        ^NSArray *(id node) { return @[node]; }, ^BOOL(NSDictionary *node) { return NO; }, ^BOOL { return NO; }, &error);
    XCTAssertNil(result); XCTAssertEqual(count, 8u);
}
- (void)testBackgroundLeaseNormalFinishAndLateExpiration {
    __block dispatch_block_t expire; __block NSUInteger ends = 0, expirations = 0;
    AutoBackgroundLease *lease = [[AutoBackgroundLease alloc] initWithBegin:^UIBackgroundTaskIdentifier(dispatch_block_t handler) { expire = handler; return 42; }
        end:^(UIBackgroundTaskIdentifier identifier) { XCTAssertEqual(identifier, 42u); ends++; } expiration:^{ expirations++; }];
    [lease finish]; [lease finish]; expire();
    XCTAssertEqual(ends, 1u); XCTAssertEqual(expirations, 0u);
}
- (void)testBackgroundLeaseExpirationIsExactlyOnce {
    __block dispatch_block_t expire; __block NSUInteger ends = 0, expirations = 0;
    AutoBackgroundLease *lease = [[AutoBackgroundLease alloc] initWithBegin:^UIBackgroundTaskIdentifier(dispatch_block_t handler) { expire = handler; return 43; }
        end:^(UIBackgroundTaskIdentifier identifier) { ends++; } expiration:^{ expirations++; }];
    dispatch_apply(10, dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^(size_t index) { expire(); });
    [lease finish]; XCTAssertEqual(ends, 1u); XCTAssertEqual(expirations, 1u);
}
- (void)testBackgroundLeaseHandlesSynchronousExpiration {
    __block NSUInteger ends = 0, expirations = 0;
    AutoBackgroundLease *lease = [[AutoBackgroundLease alloc] initWithBegin:^UIBackgroundTaskIdentifier(dispatch_block_t handler) { handler(); return 44; }
        end:^(UIBackgroundTaskIdentifier identifier) { ends++; } expiration:^{ expirations++; }];
    [lease finish]; XCTAssertEqual(ends, 1u); XCTAssertEqual(expirations, 1u);
}
- (void)testDeniedBackgroundLeaseNeverEndsInvalidIdentifier {
    __block NSUInteger ends = 0;
    AutoBackgroundLease *lease = [[AutoBackgroundLease alloc] initWithBegin:^UIBackgroundTaskIdentifier(dispatch_block_t handler) { return UIBackgroundTaskInvalid; }
        end:^(UIBackgroundTaskIdentifier identifier) { ends++; } expiration:^{}];
    [lease finish]; XCTAssertEqual(ends, 0u);
}
- (void)testBackgroundLeaseDeallocationBalancesAssertion {
    __block NSUInteger ends = 0;
    @autoreleasepool {
        __unused AutoBackgroundLease *lease = [[AutoBackgroundLease alloc] initWithBegin:^UIBackgroundTaskIdentifier(dispatch_block_t handler) { return 45; }
            end:^(UIBackgroundTaskIdentifier identifier) { ends++; } expiration:^{}];
    }
    XCTAssertEqual(ends, 1u);
}
@end
