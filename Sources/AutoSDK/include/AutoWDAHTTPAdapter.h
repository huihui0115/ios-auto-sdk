#import <Foundation/Foundation.h>
#import "AutoAutomationAdapter.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Adapter for a separately running WebDriverAgent-compatible HTTP server.
 *
 * This client deliberately does not link XCTest or private Apple frameworks.
 * The WDA Runner/iOS-Tagent process remains a separately signed target and
 * can be reached over the device loopback interface (normally port 8100).
 */
@interface AutoWDAHTTPAdapter : NSObject <AutoAutomationAdapter>

@property (nonatomic, readonly) NSURL *baseURL;
@property (nonatomic, copy, nullable) NSString *applicationBundleId;
@property (nonatomic, assign) NSTimeInterval requestTimeout;
@property (nonatomic, readonly, nullable) NSString *sessionId;

/**
 * Reuse a parsed /source tree for this short interval. A value of zero
 * disables the cache. The default is 0.15 seconds, which covers a parent /
 * child / sibling query without retaining a large tree for long.
 */
@property (nonatomic, assign) NSTimeInterval sourceCacheDuration;

/**
 * Maximum UTF-8 size accepted for a WDA /source response. The default is
 * 16 MiB; values are clamped to 32 MiB. A value of zero restores the default.
 */
@property (nonatomic, assign) NSUInteger sourceMaxBytes;

/**
 * Maximum nodes accepted while parsing a WDA /source response. The default
 * is 50,000; values are clamped to 200,000. A value of zero restores default.
 */
@property (nonatomic, assign) NSUInteger sourceMaxNodes;

/**
 * Reuse the last screenshot for this short interval. Disabled by default
 * because screenshots can become stale while an app animates.
 */
@property (nonatomic, assign) NSTimeInterval screenshotCacheDuration;

/**
 * Settings sent to the WDA /appium/settings endpoint after session creation.
 * Unsupported settings are ignored by default for compatibility with older
 * WDA-compatible runners.
 */
@property (nonatomic, copy) NSDictionary<NSString *, id> *sessionSettings;
@property (nonatomic, assign) BOOL ignoresUnsupportedSessionSettings;

- (instancetype)initWithBaseURL:(NSURL *)baseURL;
- (instancetype)initWithBaseURL:(NSURL *)baseURL
             applicationBundleId:(nullable NSString *)applicationBundleId
                          timeout:(NSTimeInterval)timeout NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/** Start a WDA session now. A session is also created lazily by operations. */
- (BOOL)startSession:(NSError * _Nullable * _Nullable)error;
/** Close the current WDA session. Safe to call more than once. */
- (void)invalidateSession;

/** Apply sessionSettings to the current session immediately. */
- (BOOL)applySessionSettings:(NSError * _Nullable * _Nullable)error;

/** WDA application lifecycle helpers. Bundle IDs must be explicit. */
- (BOOL)launchApplicationWithBundleId:(NSString *)bundleId error:(NSError * _Nullable * _Nullable)error;
- (BOOL)activateApplicationWithBundleId:(NSString *)bundleId error:(NSError * _Nullable * _Nullable)error;
- (BOOL)terminateApplicationWithBundleId:(NSString *)bundleId error:(NSError * _Nullable * _Nullable)error;
- (nullable NSNumber *)applicationStateForBundleId:(NSString *)bundleId error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
