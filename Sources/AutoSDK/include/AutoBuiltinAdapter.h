#import <Foundation/Foundation.h>
#import "AutoAutomationAdapter.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Built-in no-WDA adapter: system-wide automation without an external
 * WebDriverAgent process or XCTest runner.
 *
 * Implementation strategy (mirrors the current AScript/kuaijs agent model):
 *  - Real touch injection through IOHIDEvent private APIs.
 *  - Element queries through the system-wide Accessibility API.
 *  - Application control through LSApplicationWorkspace / SpringBoardServices /
 *    BackBoardServices private symbols.
 *
 * Every private symbol is resolved at runtime with dlopen/dlsym; the adapter
 * never links private frameworks and never needs private headers. When a
 * symbol, entitlement, or OS capability is missing, the affected operation
 * returns a clear error and `capabilities` reports the degraded state, so
 * scripts can adapt at runtime.
 *
 * Deployment note: system-wide operation requires the host app to be
 * distributed with elevated trust (TrollStore / enterprise-style signing with
 * the matching entitlements). A plain App Store build will fall back to
 * host-app-only behavior for most operations.
 */
@interface AutoBuiltinAdapter : NSObject <AutoAutomationAdapter>

/** Maximum number of elements returned by one accessibility walk (default 5000). */
@property (nonatomic, assign) NSUInteger maxSnapshotNodes;
/** Maximum traversal depth for accessibility walks (default 30). */
@property (nonatomic, assign) NSUInteger maxSnapshotDepth;
/** Screenshot cache duration in seconds (0 disables caching). */
@property (nonatomic, assign) NSTimeInterval screenshotCacheDuration;

@end

NS_ASSUME_NONNULL_END
