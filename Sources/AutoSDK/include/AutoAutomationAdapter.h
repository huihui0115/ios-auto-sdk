#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Host applications provide this adapter to connect AutoSDK to their
 * XCTest/WDA integration. The SDK itself remains independent of private APIs.
 */
@protocol AutoAutomationAdapter <NSObject>

- (BOOL)click:(id)selector error:(NSError * _Nullable * _Nullable)error;
- (BOOL)longClick:(id)selector duration:(NSTimeInterval)duration error:(NSError * _Nullable * _Nullable)error;
- (BOOL)swipeFromX:(CGFloat)x1
                 y:(CGFloat)y1
                toX:(CGFloat)x2
                 y:(CGFloat)y2
          duration:(NSTimeInterval)duration
             error:(NSError * _Nullable * _Nullable)error;
- (BOOL)input:(id)selector text:(NSString *)text error:(NSError * _Nullable * _Nullable)error;
- (nullable NSString *)textForSelector:(id)selector error:(NSError * _Nullable * _Nullable)error;
- (nullable NSData *)screenshotWithError:(NSError * _Nullable * _Nullable)error;
- (nullable NSDictionary<NSString *, id> *)findImageAtPath:(NSString *)templatePath
                                                  options:(nullable NSDictionary *)options
                                                     error:(NSError * _Nullable * _Nullable)error;
- (nullable NSArray<NSDictionary<NSString *, id> *> *)ocrInRegion:(nullable NSDictionary *)region
                                                            error:(NSError * _Nullable * _Nullable)error;
- (NSDictionary<NSString *, id> *)deviceInfo;

@optional
- (BOOL)clickAtX:(CGFloat)x y:(CGFloat)y error:(NSError * _Nullable * _Nullable)error;
- (BOOL)doubleClickAtX:(CGFloat)x
                     y:(CGFloat)y
              interval:(NSTimeInterval)interval
                 error:(NSError * _Nullable * _Nullable)error;
- (BOOL)exists:(id)selector error:(NSError * _Nullable * _Nullable)error;
- (nullable NSDictionary<NSString *, id> *)elementInfoForSelector:(id)selector
                                                              error:(NSError * _Nullable * _Nullable)error;
- (nullable NSArray<NSDictionary<NSString *, id> *> *)elementsInfoForSelector:(id)selector
                                                                         error:(NSError * _Nullable * _Nullable)error;
/** Returns a bounded flat snapshot whose descriptors retain depth/parent metadata when available. */
- (nullable NSArray<NSDictionary<NSString *, id> *> *)nodeSnapshotWithMaxResults:(NSUInteger)maxResults
                                                                             error:(NSError * _Nullable * _Nullable)error;
- (nullable id)attribute:(NSString *)attribute
               forSelector:(id)selector
                     error:(NSError * _Nullable * _Nullable)error;
- (nullable NSDictionary<NSString *, id> *)boundsForSelector:(id)selector
                                                       error:(NSError * _Nullable * _Nullable)error;
- (nullable NSArray<NSDictionary<NSString *, id> *> *)childrenForSelector:(id)selector
                                                                    error:(NSError * _Nullable * _Nullable)error;
- (nullable NSDictionary<NSString *, id> *)parentForSelector:(id)selector
                                                        error:(NSError * _Nullable * _Nullable)error;
- (BOOL)scrollIntoView:(id)selector error:(NSError * _Nullable * _Nullable)error;
- (nullable NSDictionary<NSString *, id> *)findColor:(id)color
                                              region:(nullable NSDictionary *)region
                                             options:(nullable NSDictionary *)options
                                               error:(NSError * _Nullable * _Nullable)error;
- (nullable NSDictionary<NSString *, id> *)pixelColorAtX:(CGFloat)x
                                                        y:(CGFloat)y
                                                    error:(NSError * _Nullable * _Nullable)error;
- (BOOL)compareColors:(NSArray<NSDictionary<NSString *, id> *> *)points
               options:(nullable NSDictionary *)options
                 error:(NSError * _Nullable * _Nullable)error;
- (nullable NSDictionary<NSString *, id> *)findMultiColor:(id)color
                                                    offsets:(NSArray *)offsets
                                                     region:(nullable NSDictionary *)region
                                                    options:(nullable NSDictionary *)options
                                                      error:(NSError * _Nullable * _Nullable)error;
- (BOOL)launchApplicationWithBundleId:(NSString *)bundleId error:(NSError * _Nullable * _Nullable)error;
- (BOOL)activateApplicationWithBundleId:(NSString *)bundleId error:(NSError * _Nullable * _Nullable)error;
- (BOOL)terminateApplicationWithBundleId:(NSString *)bundleId error:(NSError * _Nullable * _Nullable)error;
- (nullable NSNumber *)applicationStateForBundleId:(NSString *)bundleId error:(NSError * _Nullable * _Nullable)error;
- (nullable NSString *)currentApplicationWithError:(NSError * _Nullable * _Nullable)error;
- (nullable NSArray<NSDictionary<NSString *, id> *> *)installedApplicationsWithError:(NSError * _Nullable * _Nullable)error;
/** System-level UI actions. WDA runners expose these; most embedded adapters do not. */
- (BOOL)pressButtonWithName:(NSString *)name error:(NSError * _Nullable * _Nullable)error;
- (nullable NSNumber *)deviceLockedStateWithError:(NSError * _Nullable * _Nullable)error;
- (BOOL)goToHomeScreenWithError:(NSError * _Nullable * _Nullable)error;
- (BOOL)lockDeviceWithError:(NSError * _Nullable * _Nullable)error;
- (BOOL)unlockDeviceWithError:(NSError * _Nullable * _Nullable)error;
/**
 * Performs a multi-finger gesture. `fingers` is an array of finger tracks;
 * each track is an array of W3C pointer actions for that finger
 * (pointerMove / pointerDown / pointerUp / pause). Adapters that cannot
 * synthesize real touches return NO with an error.
 */
- (BOOL)performMultiTouch:(NSArray<NSArray<NSDictionary *> *> *)fingers
                    error:(NSError * _Nullable * _Nullable)error;
- (NSDictionary<NSString *, id> *)capabilities;
/** Cancels in-flight network/vision work when supported. Must be thread-safe. */
- (void)cancelCurrentOperations;

@end

/** An adapter that returns a clear error for UI operations. */
@interface AutoUnavailableAdapter : NSObject <AutoAutomationAdapter>
@end

NS_ASSUME_NONNULL_END
