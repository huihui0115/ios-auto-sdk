#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN
// Conservative policy for <= 2 GiB devices (including iPhone 7); not a process RSS guarantee.
BOOL AutoUsesLowMemoryProfile(uint64_t physicalMemory);
NSUInteger AutoDecodedImageBudget(uint64_t physicalMemory);
BOOL AutoImageFitsBudget(size_t width, size_t height, NSUInteger budget);
CGImageRef _Nullable AutoCreateBudgetedImage(NSData *data, NSUInteger budget) CF_RETURNS_RETAINED;

typedef NSDictionary * _Nonnull (^AutoNodeDescription)(id element, NSString *path, NSString *parent, NSUInteger depth, NSUInteger index);
// Iterative preorder DFS. Both visits and retained pending nodes are bounded.
NSArray<NSDictionary *> * _Nullable AutoBoundedNodeWalk(id root, NSUInteger maxNodes, NSUInteger maxDepth,
    NSUInteger maxResults, AutoNodeDescription describe, NSArray * _Nonnull (^children)(id),
    BOOL (^_Nullable filter)(NSDictionary *), BOOL (^cancelled)(void), NSError * _Nullable * _Nullable error);
NS_ASSUME_NONNULL_END
