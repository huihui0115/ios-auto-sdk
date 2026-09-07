#import "AutoResourcePolicy.h"
#import "include/AutoSDKError.h"
#import <ImageIO/ImageIO.h>

BOOL AutoUsesLowMemoryProfile(uint64_t physicalMemory) {
    return physicalMemory == 0 || physicalMemory <= 2ULL * 1024 * 1024 * 1024;
}
NSUInteger AutoDecodedImageBudget(uint64_t physicalMemory) {
    return (AutoUsesLowMemoryProfile(physicalMemory) ? 16 : 32) * 1024 * 1024;
}
BOOL AutoImageFitsBudget(size_t width, size_t height, NSUInteger budget) {
    // Division first avoids overflow; a RGBA buffer is only part of peak memory.
    return width > 0 && height > 0 && width <= 16384 && height <= 16384 &&
        width <= budget / 4 && height <= budget / (width * 4);
}
CGImageRef AutoCreateBudgetedImage(NSData *data, NSUInteger budget) {
    if (data.length == 0 || data.length > 16 * 1024 * 1024 || budget == 0) return NULL;
    NSDictionary *options = @{ (__bridge NSString *)kCGImageSourceShouldCache: @NO };
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, (__bridge CFDictionaryRef)options);
    if (!source) return NULL;
    NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL));
    size_t width = [properties[(__bridge NSString *)kCGImagePropertyPixelWidth] unsignedLongLongValue];
    size_t height = [properties[(__bridge NSString *)kCGImagePropertyPixelHeight] unsignedLongLongValue];
    CGImageRef image = NULL;
    if (AutoImageFitsBudget(width, height, budget)) {
        image = CGImageSourceCreateImageAtIndex(source, 0, (__bridge CFDictionaryRef)options);
        if (image && !AutoImageFitsBudget(CGImageGetWidth(image), CGImageGetHeight(image), budget)) {
            CGImageRelease(image); image = NULL;
        }
    }
    CFRelease(source);
    return image;
}

NSArray<NSDictionary *> *AutoBoundedNodeWalk(id root, NSUInteger maxNodes, NSUInteger maxDepth,
    NSUInteger maxResults, AutoNodeDescription describe, NSArray *(^children)(id),
    BOOL (^filter)(NSDictionary *), BOOL (^cancelled)(void), NSError **error) {
    maxNodes = MIN(MAX(maxNodes, 1), 10000);
    maxDepth = MIN(MAX(maxDepth, 1), 60);
    maxResults = maxResults > 0 ? MIN(maxResults, maxNodes) : maxNodes;
    NSMutableArray *pending = [NSMutableArray arrayWithObject:@[root, @"", @"", @0, @0]];
    NSMutableArray *results = [NSMutableArray array];
    NSUInteger visited = 0;
    BOOL truncated = NO;
    NSError *walkError = nil;
    while (pending.count > 0) {
        @autoreleasepool {
            if (cancelled()) {
                walkError = [NSError errorWithDomain:AutoSDKErrorDomain code:AutoSDKErrorScriptCancelled
                    userInfo:@{NSLocalizedDescriptionKey: @"Built-in adapter: accessibility walk was cancelled."}];
                break;
            }
            if (visited >= maxNodes) { truncated = YES; break; }
            NSArray *frame = pending.lastObject;
            [pending removeLastObject];
            id element = frame[0];
            NSString *path = frame[1];
            NSUInteger depth = [frame[3] unsignedIntegerValue];
            visited++;
            NSDictionary *descriptor = describe(element, path, frame[2], depth, [frame[4] unsignedIntegerValue]);
            if (!filter || filter(descriptor)) {
                [results addObject:descriptor];
                if (results.count >= maxResults && !cancelled()) return results;
            }
            if (cancelled()) {
                walkError = [NSError errorWithDomain:AutoSDKErrorDomain code:AutoSDKErrorScriptCancelled
                    userInfo:@{NSLocalizedDescriptionKey: @"Built-in adapter: accessibility walk was cancelled."}];
                break;
            }
            NSArray *descendants = children(element) ?: @[];
            if (descendants.count == 0) continue;
            if (depth >= maxDepth) { truncated = YES; continue; }
            // Drop the end of pending work to preserve preorder priority for this branch.
            NSUInteger available = maxNodes - visited;
            NSUInteger count = MIN(descendants.count, available);
            if (count < descendants.count) truncated = YES;
            while (pending.count > available - count) { [pending removeObjectAtIndex:0]; truncated = YES; }
            for (NSUInteger index = count; index > 0; index--) {
                NSUInteger childIndex = index - 1;
                NSString *childPath = path.length ? [NSString stringWithFormat:@"%@.%lu", path, (unsigned long)childIndex]
                    : [NSString stringWithFormat:@"%lu", (unsigned long)childIndex];
                [pending addObject:@[descendants[childIndex], childPath, descriptor[@"handle"] ?: @"", @(depth + 1), @(childIndex)]];
            }
        }
    }
    if (walkError) { if (error) *error = walkError; return nil; }
    // Never present a budget-limited search as a definitive absence.
    if (truncated && filter) {
        if (error) *error = [NSError errorWithDomain:AutoSDKErrorDomain code:AutoSDKErrorAutomationFailed
            userInfo:@{NSLocalizedDescriptionKey: @"Node search reached its visit/depth budget; narrow the query or page before retrying."}];
        return nil;
    }
    return results;
}
