#import "include/AutoAutomationAdapter.h"
#import "include/AutoSDKError.h"

static NSError *AutoUnavailableError(void) {
    return [NSError errorWithDomain:AutoSDKErrorDomain
                                code:AutoSDKErrorAutomationUnavailable
                            userInfo:@{NSLocalizedDescriptionKey: @"No automation adapter has been configured."}];
}

@implementation AutoUnavailableAdapter
- (BOOL)click:(id)selector error:(NSError **)error { if (error) *error = AutoUnavailableError(); return NO; }
- (BOOL)longClick:(id)selector duration:(NSTimeInterval)duration error:(NSError **)error { if (error) *error = AutoUnavailableError(); return NO; }
- (BOOL)swipeFromX:(CGFloat)x1 y:(CGFloat)y1 toX:(CGFloat)x2 y:(CGFloat)y2 duration:(NSTimeInterval)duration error:(NSError **)error { if (error) *error = AutoUnavailableError(); return NO; }
- (BOOL)input:(id)selector text:(NSString *)text error:(NSError **)error { if (error) *error = AutoUnavailableError(); return NO; }
- (NSString *)textForSelector:(id)selector error:(NSError **)error { if (error) *error = AutoUnavailableError(); return nil; }
- (NSData *)screenshotWithError:(NSError **)error { if (error) *error = AutoUnavailableError(); return nil; }
- (NSDictionary *)findImageAtPath:(NSString *)templatePath options:(NSDictionary *)options error:(NSError **)error { if (error) *error = AutoUnavailableError(); return nil; }
- (NSArray *)ocrInRegion:(NSDictionary *)region error:(NSError **)error { if (error) *error = AutoUnavailableError(); return nil; }
- (NSDictionary *)deviceInfo { return @{}; }
- (BOOL)exists:(id)selector error:(NSError **)error { if (error) *error = AutoUnavailableError(); return NO; }
- (NSDictionary *)elementInfoForSelector:(id)selector error:(NSError **)error { if (error) *error = AutoUnavailableError(); return nil; }
- (id)attribute:(NSString *)attribute forSelector:(id)selector error:(NSError **)error { if (error) *error = AutoUnavailableError(); return nil; }
- (NSDictionary *)boundsForSelector:(id)selector error:(NSError **)error { if (error) *error = AutoUnavailableError(); return nil; }
- (NSArray *)childrenForSelector:(id)selector error:(NSError **)error { if (error) *error = AutoUnavailableError(); return nil; }
- (NSDictionary *)parentForSelector:(id)selector error:(NSError **)error { if (error) *error = AutoUnavailableError(); return nil; }
- (BOOL)scrollIntoView:(id)selector error:(NSError **)error { if (error) *error = AutoUnavailableError(); return NO; }
- (NSDictionary *)findColor:(id)color region:(NSDictionary *)region options:(NSDictionary *)options error:(NSError **)error { if (error) *error = AutoUnavailableError(); return nil; }
- (BOOL)clickAtX:(CGFloat)x y:(CGFloat)y error:(NSError **)error { if (error) *error = AutoUnavailableError(); return NO; }
- (BOOL)doubleClickAtX:(CGFloat)x y:(CGFloat)y interval:(NSTimeInterval)interval error:(NSError **)error { if (error) *error = AutoUnavailableError(); return NO; }
- (NSArray *)elementsInfoForSelector:(id)selector error:(NSError **)error { if (error) *error = AutoUnavailableError(); return nil; }
- (NSDictionary *)pixelColorAtX:(CGFloat)x y:(CGFloat)y error:(NSError **)error { if (error) *error = AutoUnavailableError(); return nil; }
- (BOOL)compareColors:(NSArray *)points options:(NSDictionary *)options error:(NSError **)error { if (error) *error = AutoUnavailableError(); return NO; }
- (NSDictionary *)findMultiColor:(id)color offsets:(NSArray *)offsets region:(NSDictionary *)region options:(NSDictionary *)options error:(NSError **)error { if (error) *error = AutoUnavailableError(); return nil; }
- (NSDictionary *)capabilities { return @{ @"scope": @"none", @"crossApp": @NO }; }
@end
