#import "include/AutoUIKitAdapter.h"
#import "include/AutoSDKError.h"
#import <UIKit/UIKit.h>
#import <Vision/Vision.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <math.h>
#include <stdint.h>
#include <stdlib.h>

static const size_t AutoUIKitMaxPixelBufferBytes = 64 * 1024 * 1024;
static const NSUInteger AutoUIKitMaxColorPoints = 4096;
static const NSUInteger AutoUIKitMaxColorOffsets = 256;
static const NSUInteger AutoUIKitDefaultColorCandidates = 200000;
static const NSUInteger AutoUIKitMaxColorCandidates = 5000000;
static const NSUInteger AutoUIKitDefaultColorComparisons = 50000000;
static const NSUInteger AutoUIKitMaxColorComparisons = 500000000;
static const NSUInteger AutoUIKitMaxFindVisitedViews = 50000;
static const NSUInteger AutoUIKitMaxNodeStringLength = 4096;

static NSError *AutoUIKitError(NSString *message) {
    return [NSError errorWithDomain:AutoSDKErrorDomain
                                code:AutoSDKErrorAutomationFailed
                            userInfo:@{NSLocalizedDescriptionKey: message}];
}

static NSError *AutoUIKitCancelledError(NSString *message) {
    return [NSError errorWithDomain:AutoSDKErrorDomain
                                code:AutoSDKErrorScriptCancelled
                            userInfo:@{NSLocalizedDescriptionKey: message ?: @"Visual operation was cancelled."}];
}

static NSError *AutoUIKitElementError(NSString *message) {
    return [NSError errorWithDomain:AutoSDKErrorDomain
                                code:AutoSDKErrorElementNotFound
                            userInfo:@{NSLocalizedDescriptionKey: message}];
}

static NSError *AutoUIKitConfigurationError(NSString *message) {
    return [NSError errorWithDomain:AutoSDKErrorDomain
                                code:AutoSDKErrorInvalidConfiguration
                            userInfo:@{NSLocalizedDescriptionKey: message}];
}

static BOOL AutoUIKitRequireMainThread(NSError **error) {
    if (NSThread.isMainThread) return YES;
    if (error) *error = AutoUIKitError(@"UIKit automation operations must run on the main thread.");
    return NO;
}

static BOOL AutoUIKitIsNumber(id value) {
    return [value isKindOfClass:NSNumber.class] && isfinite([value doubleValue]);
}

static double AutoUIKitDouble(id value, double fallback) {
    if (!AutoUIKitIsNumber(value)) return fallback;
    double number = [value doubleValue];
    return isfinite(number) ? number : fallback;
}

static CGFloat AutoUIKitSafeScale(CGFloat scale) {
    return isfinite(scale) && scale > 0 ? scale : 1;
}

static BOOL AutoUIKitPointIsFinite(CGPoint point) {
    return isfinite(point.x) && isfinite(point.y);
}

static BOOL AutoUIKitRectIsFinite(CGRect rect) {
    return isfinite(rect.origin.x) && isfinite(rect.origin.y) &&
           isfinite(rect.size.width) && isfinite(rect.size.height);
}

static NSUInteger AutoUIKitUnsigned(id value, NSUInteger fallback) {
    double number = AutoUIKitDouble(value, -1);
    if (number < 0 || number > (double)NSUIntegerMax) return fallback;
    return (NSUInteger)number;
}

static NSUInteger AutoUIKitWorkBudget(id value, NSUInteger fallback, NSUInteger minimum, NSUInteger maximum) {
    NSUInteger budget = AutoUIKitUnsigned(value, fallback);
    if (budget == 0) budget = fallback;
    return MIN(maximum, MAX(minimum, budget));
}

static BOOL AutoUIKitBool(id value, BOOL fallback) {
    return AutoUIKitIsNumber(value) ? [value boolValue] : fallback;
}

static BOOL AutoUIKitRegionIsValid(id region) {
    if (region == nil || region == NSNull.null) return YES;
    if (![region isKindOfClass:NSDictionary.class]) return NO;
    for (NSString *key in @[@"x", @"y", @"width", @"height"]) {
        if (((NSDictionary *)region)[key] != nil && !AutoUIKitIsNumber(((NSDictionary *)region)[key])) return NO;
    }
    BOOL hasWidth = ((NSDictionary *)region)[@"width"] != nil;
    BOOL hasHeight = ((NSDictionary *)region)[@"height"] != nil;
    BOOL hasOrigin = ((NSDictionary *)region)[@"x"] != nil || ((NSDictionary *)region)[@"y"] != nil;
    if (hasWidth != hasHeight) return NO;
    if (hasOrigin && !hasWidth) return NO;
    if (hasWidth && (AutoUIKitDouble(((NSDictionary *)region)[@"width"], 0) <= 0 ||
                     AutoUIKitDouble(((NSDictionary *)region)[@"height"], 0) <= 0)) return NO;
    return YES;
}

static UIWindow *AutoUIKitActiveWindow(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive || ![scene isKindOfClass:UIWindowScene.class]) continue;
        NSArray<UIWindow *> *windows = ((UIWindowScene *)scene).windows;
        for (UIWindow *window in windows) if (window.isKeyWindow) return window;
        for (UIWindow *window in windows) if (!window.hidden && window.alpha > 0) return window;
    }
    for (UIWindow *window in UIApplication.sharedApplication.windows) if (window.isKeyWindow) return window;
    for (UIWindow *window in UIApplication.sharedApplication.windows) if (!window.hidden && window.alpha > 0) return window;
    return UIApplication.sharedApplication.windows.firstObject;
}

static NSString *AutoUIKitViewText(UIView *view) {
    if ([view isKindOfClass:UILabel.class]) return ((UILabel *)view).text;
    if ([view isKindOfClass:UITextField.class]) return ((UITextField *)view).text;
    if ([view isKindOfClass:UITextView.class]) return ((UITextView *)view).text;
    if ([view isKindOfClass:UIButton.class]) {
        UIButton *button = (UIButton *)view;
        return button.currentTitle ?: [button titleForState:UIControlStateNormal];
    }
    return view.accessibilityValue ?: view.accessibilityLabel;
}

static NSString *AutoUIKitDescriptorString(NSString *value, BOOL *truncated) {
    if (![value isKindOfClass:NSString.class]) return nil;
    if (value.length <= AutoUIKitMaxNodeStringLength) return value;
    if (truncated) *truncated = YES;
    NSUInteger prefixLength = AutoUIKitMaxNodeStringLength;
    unichar last = [value characterAtIndex:prefixLength - 1];
    unichar next = [value characterAtIndex:prefixLength];
    if (last >= 0xD800 && last <= 0xDBFF && next >= 0xDC00 && next <= 0xDFFF) prefixLength -= 1;
    return [value substringToIndex:prefixLength];
}

static id AutoUIKitUnwrapSelector(id selector) {
    for (NSUInteger depth = 0; depth < 32; depth++) {
        if (![selector isKindOfClass:NSDictionary.class]) break;
        id nested = ((NSDictionary *)selector)[@"selector"];
        if (!nested || nested == selector) break;
        selector = nested;
    }
    return selector;
}

static id AutoUIKitValidatedSelector(id selector, NSError **error) {
    NSHashTable *visited = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
    id current = selector;
    for (NSUInteger depth = 0; depth < 32; depth++) {
        if (![current isKindOfClass:NSDictionary.class]) break;
        if ([visited containsObject:current]) {
            if (error) *error = AutoUIKitConfigurationError(@"UIKit selector contains a cycle.");
            return nil;
        }
        [visited addObject:current];
        NSDictionary *dictionary = current;
        if (dictionary.count > 64) {
            if (error) *error = AutoUIKitConfigurationError(@"UIKit selector contains too many fields.");
            return nil;
        }
        id nested = dictionary[@"selector"];
        if (!nested) break;
        if (depth == 31) {
            if (error) *error = AutoUIKitConfigurationError(@"UIKit selector nesting exceeds 32 levels.");
            return nil;
        }
        current = nested;
    }
    if ([current isKindOfClass:NSString.class]) {
        NSUInteger length = [(NSString *)current length];
        if (length == 0 || length > AutoUIKitMaxNodeStringLength) {
            if (error) *error = AutoUIKitConfigurationError(@"UIKit string selector must contain 1 to 4096 characters.");
            return nil;
        }
        return current;
    }
    if (![current isKindOfClass:NSDictionary.class]) {
        if (error) *error = AutoUIKitConfigurationError(@"UIKit selector must be a string or object.");
        return nil;
    }
    NSDictionary *query = current;
    for (NSString *key in @[@"handle", @"uid", @"id", @"label", @"name", @"text", @"value", @"type"]) {
        id value = query[key];
        if (value && (![value isKindOfClass:NSString.class] || [(NSString *)value length] == 0 ||
                      [(NSString *)value length] > AutoUIKitMaxNodeStringLength)) {
            if (error) *error = AutoUIKitConfigurationError([NSString stringWithFormat:@"UIKit selector field '%@' must contain 1 to 4096 characters.", key]);
            return nil;
        }
    }
    for (NSString *key in @[@"idMatch", @"idRegex", @"labelMatch", @"labelRegex", @"nameMatch", @"nameRegex",
                              @"textMatch", @"textRegex", @"valueMatch", @"valueRegex", @"typeMatch", @"typeRegex"]) {
        id value = query[key];
        if (value && (![value isKindOfClass:NSString.class] || [(NSString *)value length] == 0 ||
                      [(NSString *)value length] > 1024)) {
            if (error) *error = AutoUIKitConfigurationError([NSString stringWithFormat:@"UIKit regex selector field '%@' must contain 1 to 1024 characters.", key]);
            return nil;
        }
    }
    for (NSString *key in @[@"enabled", @"enable", @"visible", @"selected", @"accessible", @"includeInvisible"]) {
        id value = query[key];
        if (value && !AutoUIKitIsNumber(value)) {
            if (error) *error = AutoUIKitConfigurationError([NSString stringWithFormat:@"UIKit selector field '%@' must be boolean.", key]);
            return nil;
        }
    }
    for (NSString *key in @[@"index", @"depth", @"childCount", @"childcount", @"maxResults", @"maxVisited"]) {
        id value = query[key];
        double number = AutoUIKitDouble(value, -1);
        if (value && (!AutoUIKitIsNumber(value) || number < 0 || number > (double)NSUIntegerMax || floor(number) != number)) {
            if (error) *error = AutoUIKitConfigurationError([NSString stringWithFormat:@"UIKit selector field '%@' must be a non-negative integer.", key]);
            return nil;
        }
    }
    id boundsValue = query[@"bounds"];
    if (boundsValue) {
        if (![boundsValue isKindOfClass:NSDictionary.class]) {
            if (error) *error = AutoUIKitConfigurationError(@"UIKit selector bounds must be an object.");
            return nil;
        }
        NSDictionary *bounds = boundsValue;
        for (NSString *key in @[@"x", @"y", @"width", @"height"]) {
            if (!AutoUIKitIsNumber(bounds[key])) {
                if (error) *error = AutoUIKitConfigurationError(@"UIKit selector bounds require finite x, y, width, and height values.");
                return nil;
            }
        }
        if (AutoUIKitDouble(bounds[@"width"], -1) < 0 || AutoUIKitDouble(bounds[@"height"], -1) < 0) {
            if (error) *error = AutoUIKitConfigurationError(@"UIKit selector bounds dimensions cannot be negative.");
            return nil;
        }
        id mode = bounds[@"mode"];
        if (mode && (![mode isKindOfClass:NSString.class] ||
                     ![@[@"intersects", @"contains", @"inside"] containsObject:mode])) {
            if (error) *error = AutoUIKitConfigurationError(@"UIKit selector bounds mode must be intersects, contains, or inside.");
            return nil;
        }
    }
    return query;
}

static BOOL AutoUIKitViewIsVisible(UIView *view) {
    for (UIView *current = view; current; current = current.superview) {
        if (current.hidden || current.alpha <= 0.01) return NO;
    }
    UIWindow *window = view.window;
    if (!window) return NO;
    CGRect convertedBounds = [view convertRect:view.bounds toView:window];
    if (!AutoUIKitRectIsFinite(convertedBounds) || !AutoUIKitRectIsFinite(window.bounds)) return NO;
    CGRect visibleRect = CGRectIntersection(convertedBounds, window.bounds);
    if (CGRectIsNull(visibleRect) || CGRectIsEmpty(visibleRect)) return NO;
    for (UIView *ancestor = view.superview; ancestor && ancestor != window; ancestor = ancestor.superview) {
        if (!ancestor.clipsToBounds) continue;
        CGRect clipRect = [ancestor convertRect:ancestor.bounds toView:window];
        if (!AutoUIKitRectIsFinite(clipRect)) return NO;
        visibleRect = CGRectIntersection(visibleRect, clipRect);
        if (CGRectIsNull(visibleRect) || CGRectIsEmpty(visibleRect)) return NO;
    }
    return YES;
}

static BOOL AutoUIKitViewIsEnabled(UIView *view) {
    return ![view isKindOfClass:UIControl.class] || ((UIControl *)view).enabled;
}

static BOOL AutoUIKitViewIsSelected(UIView *view) {
    if ([view isKindOfClass:UIControl.class]) return ((UIControl *)view).selected;
    if ([view isKindOfClass:UITableViewCell.class]) return ((UITableViewCell *)view).selected;
    if ([view isKindOfClass:UICollectionViewCell.class]) return ((UICollectionViewCell *)view).selected;
    return NO;
}

static NSUInteger AutoUIKitViewDepth(UIView *view) {
    NSUInteger depth = 0;
    for (UIView *current = view.superview; current; current = current.superview) depth++;
    return depth;
}

static NSUInteger AutoUIKitViewIndex(UIView *view) {
    NSUInteger index = [view.superview.subviews indexOfObjectIdenticalTo:view];
    return index == NSNotFound ? 0 : index;
}

static const void *AutoUIKitHandleKey = &AutoUIKitHandleKey;

static NSMapTable<NSString *, UIView *> *AutoUIKitHandleRegistry(void) {
    static NSMapTable<NSString *, UIView *> *registry;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        registry = [NSMapTable strongToWeakObjectsMapTable];
    });
    return registry;
}

static NSString *AutoUIKitHandleForView(UIView *view) {
    NSString *handle = objc_getAssociatedObject(view, AutoUIKitHandleKey);
    if (!handle) {
        handle = NSUUID.UUID.UUIDString;
        objc_setAssociatedObject(view, AutoUIKitHandleKey, handle, OBJC_ASSOCIATION_COPY_NONATOMIC);
    }
    @synchronized (AutoUIKitHandleRegistry()) {
        [AutoUIKitHandleRegistry() setObject:view forKey:handle];
    }
    return handle;
}

static NSString *AutoUIKitExistingHandleForView(UIView *view) {
    return objc_getAssociatedObject(view, AutoUIKitHandleKey);
}

static UIView *AutoUIKitViewForHandle(NSString *handle) {
    if (![handle isKindOfClass:NSString.class] || handle.length == 0) return nil;
    @synchronized (AutoUIKitHandleRegistry()) {
        return [AutoUIKitHandleRegistry() objectForKey:handle];
    }
}

static NSString *AutoUIKitFriendlyType(UIView *view) {
    if ([view isKindOfClass:UIButton.class]) return @"Button";
    if ([view isKindOfClass:UILabel.class]) return @"StaticText";
    if ([view isKindOfClass:UITextField.class]) return @"TextField";
    if ([view isKindOfClass:UITextView.class]) return @"TextView";
    if ([view isKindOfClass:UIImageView.class]) return @"Image";
    if ([view isKindOfClass:UISwitch.class]) return @"Switch";
    if ([view isKindOfClass:UISlider.class]) return @"Slider";
    if ([view isKindOfClass:UITableViewCell.class] || [view isKindOfClass:UICollectionViewCell.class]) return @"Cell";
    if ([view isKindOfClass:UIScrollView.class]) return @"ScrollView";
    return NSStringFromClass(view.class);
}

static BOOL AutoUIKitStringMatches(NSString *actual, id expected) {
    return [expected isKindOfClass:NSString.class] && actual && [actual isEqualToString:expected];
}

static BOOL AutoUIKitRegexMatches(NSString *actual, id pattern) {
    if (![pattern isKindOfClass:NSString.class] || !actual) return NO;
    if ([(NSString *)pattern length] == 0 || [(NSString *)pattern length] > 1024 || actual.length > 16384) return NO;
    static NSCache<NSString *, id> *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [NSCache new];
        cache.countLimit = 128;
    });
    id cached = [cache objectForKey:pattern];
    if (cached == NSNull.null) return NO;
    NSRegularExpression *expression = [cached isKindOfClass:NSRegularExpression.class] ? cached : nil;
    if (!cached) {
        expression = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
        [cache setObject:expression ?: NSNull.null forKey:pattern];
    }
    if (!expression) return NO;
    return [expression firstMatchInString:actual options:0 range:NSMakeRange(0, actual.length)] != nil;
}

static BOOL AutoUIKitBooleanMatches(BOOL actual, id expected) {
    return !expected || (AutoUIKitIsNumber(expected) && actual == [expected boolValue]);
}

static BOOL AutoUIKitViewMatches(UIView *view, id selector) {
    if ([selector isKindOfClass:NSString.class]) {
        if (!AutoUIKitViewIsVisible(view)) return NO;
        NSString *text = AutoUIKitViewText(view);
        return AutoUIKitStringMatches(view.accessibilityIdentifier, selector) ||
               AutoUIKitStringMatches(view.accessibilityLabel, selector) ||
               AutoUIKitStringMatches(text, selector);
    }
    if (![selector isKindOfClass:NSDictionary.class]) return NO;
    NSDictionary *query = selector;
    BOOL hasCondition = NO;
    id handle = query[@"handle"] ?: query[@"uid"];
    BOOL hasHandleCondition = handle != nil;
    if (handle) {
        hasCondition = YES;
        if (!AutoUIKitStringMatches(AutoUIKitExistingHandleForView(view), handle)) return NO;
    }
    id identifier = query[@"id"];
    if (identifier) { hasCondition = YES; if (!AutoUIKitStringMatches(view.accessibilityIdentifier, identifier)) return NO; }
    id identifierMatch = query[@"idMatch"] ?: query[@"idRegex"];
    if (identifierMatch) { hasCondition = YES; if (!AutoUIKitRegexMatches(view.accessibilityIdentifier, identifierMatch)) return NO; }
    id label = query[@"label"];
    if (label) {
        hasCondition = YES;
        if (!AutoUIKitStringMatches(view.accessibilityLabel, label) && !AutoUIKitStringMatches(AutoUIKitViewText(view), label)) return NO;
    }
    id labelMatch = query[@"labelMatch"] ?: query[@"labelRegex"];
    if (labelMatch) {
        hasCondition = YES;
        if (!AutoUIKitRegexMatches(view.accessibilityLabel, labelMatch) && !AutoUIKitRegexMatches(AutoUIKitViewText(view), labelMatch)) return NO;
    }
    id name = query[@"name"] ?: query[@"text"];
    if (name) {
        hasCondition = YES;
        if (!AutoUIKitStringMatches(view.accessibilityLabel, name) && !AutoUIKitStringMatches(AutoUIKitViewText(view), name)) return NO;
    }
    id nameMatch = query[@"nameMatch"] ?: query[@"nameRegex"] ?: query[@"textMatch"] ?: query[@"textRegex"];
    if (nameMatch) {
        hasCondition = YES;
        if (!AutoUIKitRegexMatches(view.accessibilityLabel, nameMatch) && !AutoUIKitRegexMatches(AutoUIKitViewText(view), nameMatch)) return NO;
    }
    id value = query[@"value"];
    if (value) {
        hasCondition = YES;
        if (!AutoUIKitStringMatches(view.accessibilityValue, value) && !AutoUIKitStringMatches(AutoUIKitViewText(view), value)) return NO;
    }
    id valueMatch = query[@"valueMatch"] ?: query[@"valueRegex"];
    if (valueMatch) {
        hasCondition = YES;
        if (!AutoUIKitRegexMatches(view.accessibilityValue, valueMatch) && !AutoUIKitRegexMatches(AutoUIKitViewText(view), valueMatch)) return NO;
    }
    id type = query[@"type"];
    if (type) {
        hasCondition = YES;
        if (!AutoUIKitStringMatches(AutoUIKitFriendlyType(view), type) && !AutoUIKitStringMatches(NSStringFromClass(view.class), type)) return NO;
    }
    id typeMatch = query[@"typeMatch"] ?: query[@"typeRegex"];
    if (typeMatch) {
        hasCondition = YES;
        if (!AutoUIKitRegexMatches(AutoUIKitFriendlyType(view), typeMatch) && !AutoUIKitRegexMatches(NSStringFromClass(view.class), typeMatch)) return NO;
    }
    id enabled = query[@"enabled"] ?: query[@"enable"];
    if (enabled) { hasCondition = YES; if (!AutoUIKitBooleanMatches(AutoUIKitViewIsEnabled(view), enabled)) return NO; }
    id visible = query[@"visible"];
    if (visible) { hasCondition = YES; if (!AutoUIKitBooleanMatches(AutoUIKitViewIsVisible(view), visible)) return NO; }
    else if (!hasHandleCondition && !AutoUIKitViewIsVisible(view) && !AutoUIKitBool(query[@"includeInvisible"], NO)) return NO;
    id selected = query[@"selected"];
    if (selected) { hasCondition = YES; if (!AutoUIKitBooleanMatches(AutoUIKitViewIsSelected(view), selected)) return NO; }
    id accessible = query[@"accessible"];
    if (accessible) { hasCondition = YES; if (!AutoUIKitBooleanMatches(view.isAccessibilityElement, accessible)) return NO; }
    id index = query[@"index"];
    if (index) { hasCondition = YES; if (!AutoUIKitIsNumber(index) || AutoUIKitViewIndex(view) != AutoUIKitUnsigned(index, NSUIntegerMax)) return NO; }
    id depth = query[@"depth"];
    if (depth) { hasCondition = YES; if (!AutoUIKitIsNumber(depth) || AutoUIKitViewDepth(view) != AutoUIKitUnsigned(depth, NSUIntegerMax)) return NO; }
    id childCount = query[@"childCount"] ?: query[@"childcount"];
    if (childCount) { hasCondition = YES; if (!AutoUIKitIsNumber(childCount) || view.subviews.count != AutoUIKitUnsigned(childCount, NSUIntegerMax)) return NO; }
    NSDictionary *boundsQuery = [query[@"bounds"] isKindOfClass:NSDictionary.class] ? query[@"bounds"] : nil;
    if (boundsQuery) {
        hasCondition = YES;
        for (NSString *key in @[@"x", @"y", @"width", @"height"]) {
            if (boundsQuery[key] != nil && !AutoUIKitIsNumber(boundsQuery[key])) return NO;
        }
        UIWindow *window = view.window ?: AutoUIKitActiveWindow();
        CGRect actual = window ? [view convertRect:view.bounds toView:window] : view.frame;
        CGRect expected = CGRectMake(AutoUIKitDouble(boundsQuery[@"x"], 0), AutoUIKitDouble(boundsQuery[@"y"], 0),
                                     AutoUIKitDouble(boundsQuery[@"width"], 0), AutoUIKitDouble(boundsQuery[@"height"], 0));
        if (!AutoUIKitRectIsFinite(actual) || expected.size.width < 0 || expected.size.height < 0) return NO;
        NSString *mode = [boundsQuery[@"mode"] isKindOfClass:NSString.class] ? boundsQuery[@"mode"] : @"intersects";
        if ([mode isEqualToString:@"contains"]) {
            if (!CGRectContainsRect(expected, actual)) return NO;
        } else if ([mode isEqualToString:@"inside"]) {
            if (!CGRectContainsRect(actual, expected)) return NO;
        } else if (!CGRectIntersectsRect(actual, expected)) return NO;
    }
    return hasCondition;
}

static UIView *AutoUIKitFindInView(UIView *root,
                                   id selector,
                                   BOOL (^shouldCancel)(void),
                                   BOOL *cancelled,
                                   BOOL *truncated) {
    if (cancelled) *cancelled = NO;
    if (truncated) *truncated = NO;
    if (!root) return nil;
    NSMutableArray<UIView *> *views = [NSMutableArray arrayWithObject:root];
    NSMutableArray<NSNumber *> *nextChildIndexes = [NSMutableArray arrayWithObject:@(root.subviews.count)];
    NSUInteger visitedCount = 0, traversalSteps = 0;
    BOOL expansionTruncated = NO;
    while (views.count > 0 && visitedCount < AutoUIKitMaxFindVisitedViews) {
        if ((traversalSteps++ & 0xFF) == 0 && shouldCancel && shouldCancel()) {
            if (cancelled) *cancelled = YES;
            return nil;
        }
        UIView *view = views.lastObject;
        NSUInteger nextChildIndex = nextChildIndexes.lastObject.unsignedIntegerValue;
        if (nextChildIndex > 0) {
            if (visitedCount + views.count >= AutoUIKitMaxFindVisitedViews) {
                expansionTruncated = YES;
                nextChildIndexes[nextChildIndexes.count - 1] = @0;
                continue;
            }
            nextChildIndex -= 1;
            nextChildIndexes[nextChildIndexes.count - 1] = @(nextChildIndex);
            UIView *subview = view.subviews[nextChildIndex];
            [views addObject:subview];
            [nextChildIndexes addObject:@(subview.subviews.count)];
            continue;
        }
        [views removeLastObject];
        [nextChildIndexes removeLastObject];
        visitedCount += 1;
        @autoreleasepool {
            if (AutoUIKitViewMatches(view, selector)) return view;
        }
    }
    if ((views.count > 0 || expansionTruncated) && truncated) *truncated = YES;
    return nil;
}

static BOOL AutoUIKitCollectInView(UIView *root,
                                   id selector,
                                   NSUInteger maximum,
                                   NSUInteger maximumVisited,
                                   NSMutableArray<UIView *> *result,
                                   NSMutableArray<NSNumber *> *resultIndexes,
                                   NSMutableArray<NSNumber *> *resultDepths,
                                   BOOL (^shouldCancel)(void),
                                   BOOL *cancelled) {
    if (cancelled) *cancelled = NO;
    if (!root || result.count >= maximum) return NO;
    NSMutableArray<UIView *> *views = [NSMutableArray arrayWithObject:root];
    NSMutableArray<NSNumber *> *nextChildIndexes = [NSMutableArray arrayWithObject:@(root.subviews.count)];
    NSMutableArray<NSNumber *> *siblingIndexes = [NSMutableArray arrayWithObject:@0];
    NSUInteger visitedCount = 0, traversalSteps = 0;
    BOOL expansionTruncated = NO;
    while (views.count > 0 && result.count < maximum && visitedCount < maximumVisited) {
        if ((traversalSteps++ & 0xFF) == 0 && shouldCancel && shouldCancel()) {
            if (cancelled) *cancelled = YES;
            return NO;
        }
        UIView *view = views.lastObject;
        NSUInteger nextChildIndex = nextChildIndexes.lastObject.unsignedIntegerValue;
        if (nextChildIndex > 0) {
            if (visitedCount + views.count >= maximumVisited) {
                expansionTruncated = YES;
                nextChildIndexes[nextChildIndexes.count - 1] = @0;
                continue;
            }
            nextChildIndex -= 1;
            nextChildIndexes[nextChildIndexes.count - 1] = @(nextChildIndex);
            UIView *subview = view.subviews[nextChildIndex];
            [views addObject:subview];
            [nextChildIndexes addObject:@(subview.subviews.count)];
            [siblingIndexes addObject:@(nextChildIndex)];
            continue;
        }
        NSUInteger depth = views.count - 1;
        NSUInteger siblingIndex = siblingIndexes.lastObject.unsignedIntegerValue;
        [views removeLastObject];
        [nextChildIndexes removeLastObject];
        [siblingIndexes removeLastObject];
        visitedCount += 1;
        BOOL matches = NO;
        @autoreleasepool { matches = AutoUIKitViewMatches(view, selector); }
        if (matches) {
            [result addObject:view];
            [resultIndexes addObject:@(siblingIndex)];
            [resultDepths addObject:@(depth)];
        }
    }
    return result.count < maximum && (views.count > 0 || expansionTruncated);
}

static UIView *AutoUIKitFindView(id selector, BOOL (^shouldCancel)(void), NSError **error) {
    id unwrapped = AutoUIKitValidatedSelector(selector, error);
    if (!unwrapped) return nil;
    if (shouldCancel && shouldCancel()) {
        if (error) *error = AutoUIKitCancelledError(@"UIKit node lookup was cancelled.");
        return nil;
    }
    UIWindow *window = AutoUIKitActiveWindow();
    if (!window) {
        if (error) *error = AutoUIKitError(@"No active application window is available.");
        return nil;
    }
    NSString *handle = [unwrapped isKindOfClass:NSDictionary.class]
        ? ([unwrapped[@"handle"] isKindOfClass:NSString.class] ? unwrapped[@"handle"] : unwrapped[@"uid"])
        : nil;
    if ([handle isKindOfClass:NSString.class] && handle.length > 0) {
        UIView *handledView = AutoUIKitViewForHandle(handle);
        if (shouldCancel && shouldCancel()) {
            if (error) *error = AutoUIKitCancelledError(@"UIKit node lookup was cancelled.");
            return nil;
        }
        if (handledView.window == window && AutoUIKitViewMatches(handledView, unwrapped)) return handledView;
        if (error) *error = AutoUIKitElementError(@"The UIKit node handle is stale or no longer belongs to the active window.");
        return nil;
    }
    BOOL cancelled = NO, truncated = NO;
    UIView *view = AutoUIKitFindInView(window, unwrapped, shouldCancel, &cancelled, &truncated);
    if (!view && cancelled) {
        if (error) *error = AutoUIKitCancelledError(@"UIKit node lookup was cancelled.");
        return nil;
    }
    if (view && shouldCancel && shouldCancel()) {
        if (error) *error = AutoUIKitCancelledError(@"UIKit node lookup was cancelled.");
        return nil;
    }
    if (!view && truncated) {
        if (error) *error = AutoUIKitError(@"The view hierarchy exceeds the findElement safety limit.");
        return nil;
    }
    if (!view && error) *error = AutoUIKitElementError(@"No view matches the selector.");
    return view;
}

static NSDictionary *AutoUIKitElementInfoWithMetadata(UIView *view,
                                                       UIWindow *window,
                                                       NSUInteger index,
                                                       NSUInteger depth,
                                                       BOOL visible) {
    CGRect bounds = [view convertRect:view.bounds toView:window];
    BOOL boundsValid = AutoUIKitRectIsFinite(bounds);
    if (!boundsValid) bounds = CGRectZero;
    BOOL contentTruncated = NO;
    NSString *identifier = AutoUIKitDescriptorString(view.accessibilityIdentifier, &contentTruncated);
    NSString *label = AutoUIKitDescriptorString(view.accessibilityLabel, &contentTruncated);
    NSString *accessibilityValue = AutoUIKitDescriptorString(view.accessibilityValue, &contentTruncated);
    NSString *text = AutoUIKitDescriptorString(AutoUIKitViewText(view), &contentTruncated);
    NSString *handle = AutoUIKitHandleForView(view);
    NSString *parentHandle = view.superview ? AutoUIKitHandleForView(view.superview) : nil;
    NSMutableDictionary *info = [@{ @"selector": @{ @"handle": handle },
                                    @"handle": handle,
                                    @"uid": handle,
                                    @"nodeId": handle,
                                    @"parentId": parentHandle ?: NSNull.null,
                                    @"id": identifier ?: [NSNull null],
                                    @"label": label ?: [NSNull null],
                                    @"name": label ?: (text ?: [NSNull null]),
                                    @"value": accessibilityValue ?: (text ?: [NSNull null]),
                                    @"text": text ?: [NSNull null],
                                    @"contentTruncated": @(contentTruncated),
                                    @"type": AutoUIKitFriendlyType(view) ?: @"",
                                    @"className": NSStringFromClass(view.class) ?: @"",
                                    @"enabled": @(AutoUIKitViewIsEnabled(view)),
                                    @"selected": @(AutoUIKitViewIsSelected(view)),
                                    @"accessible": @(view.isAccessibilityElement),
                                    @"visible": @(visible),
                                    @"boundsValid": @(boundsValid),
                                    @"index": @(index),
                                    @"order": @(index),
                                    @"depth": @(depth),
                                    @"childCount": @(view.subviews.count),
                                    @"bounds": @{ @"x": @(bounds.origin.x), @"y": @(bounds.origin.y),
                                                  @"width": @(bounds.size.width), @"height": @(bounds.size.height),
                                                  @"centerX": @(CGRectGetMidX(bounds)), @"centerY": @(CGRectGetMidY(bounds)) } } mutableCopy];
    return info;
}

static NSDictionary *AutoUIKitElementInfo(UIView *view, id selector, UIWindow *window) {
    (void)selector;
    return AutoUIKitElementInfoWithMetadata(view, window, AutoUIKitViewIndex(view),
                                             AutoUIKitViewDepth(view), AutoUIKitViewIsVisible(view));
}

typedef struct {
    CGContextRef context;
    uint8_t *bytes;
    size_t width;
    size_t height;
    size_t bytesPerRow;
} AutoUIKitPixelImage;

static CGColorSpaceRef AutoUIKitPixelColorSpace(void) {
    static CGColorSpaceRef colorSpace;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        if (!colorSpace) colorSpace = CGColorSpaceCreateDeviceRGB();
    });
    return colorSpace;
}

static BOOL AutoUIKitPixelByteCount(size_t width, size_t height, size_t *byteCount) {
    if (byteCount) *byteCount = 0;
    if (width == 0 || height == 0 || width > SIZE_MAX / 4) return NO;
    size_t bytesPerRow = width * 4;
    if (height > SIZE_MAX / bytesPerRow) return NO;
    if (byteCount) *byteCount = height * bytesPerRow;
    return YES;
}

static AutoUIKitPixelImage AutoUIKitPixelImageMake(CGImageRef image) {
    AutoUIKitPixelImage result = {0};
    if (!image) return result;
    result.width = CGImageGetWidth(image);
    result.height = CGImageGetHeight(image);
    size_t byteCount = 0;
    if (!AutoUIKitPixelByteCount(result.width, result.height, &byteCount)) return result;
    result.bytesPerRow = result.width * 4;
    if (byteCount > AutoUIKitMaxPixelBufferBytes) return (AutoUIKitPixelImage){0};
    result.bytes = calloc(result.height, result.bytesPerRow);
    if (!result.bytes) return (AutoUIKitPixelImage){0};
    CGColorSpaceRef colorSpace = AutoUIKitPixelColorSpace();
    if (!colorSpace) {
        free(result.bytes);
        return (AutoUIKitPixelImage){0};
    }
    result.context = CGBitmapContextCreate(result.bytes, result.width, result.height, 8, result.bytesPerRow,
                                           colorSpace, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    if (!result.context) {
        free(result.bytes);
        result.bytes = NULL;
        return result;
    }
    CGContextTranslateCTM(result.context, 0, result.height);
    CGContextScaleCTM(result.context, 1, -1);
    CGContextDrawImage(result.context, CGRectMake(0, 0, result.width, result.height), image);
    return result;
}

static AutoUIKitPixelImage AutoUIKitPixelImageMakeRegion(CGImageRef image,
                                                          CGRect region,
                                                          NSUInteger *originX,
                                                          NSUInteger *originY) {
    if (originX) *originX = 0;
    if (originY) *originY = 0;
    if (!image || !AutoUIKitRectIsFinite(region) || CGRectIsNull(region) || CGRectIsEmpty(region)) return (AutoUIKitPixelImage){0};
    size_t imageWidth = CGImageGetWidth(image), imageHeight = CGImageGetHeight(image);
    CGRect clipped = CGRectIntersection(region, CGRectMake(0, 0, imageWidth, imageHeight));
    if (CGRectIsNull(clipped) || CGRectIsEmpty(clipped)) return (AutoUIKitPixelImage){0};
    NSUInteger minX = MIN(imageWidth, (NSUInteger)MAX(0, floor(CGRectGetMinX(clipped))));
    NSUInteger minY = MIN(imageHeight, (NSUInteger)MAX(0, floor(CGRectGetMinY(clipped))));
    NSUInteger maxX = MIN(imageWidth, (NSUInteger)MAX(0, ceil(CGRectGetMaxX(clipped))));
    NSUInteger maxY = MIN(imageHeight, (NSUInteger)MAX(0, ceil(CGRectGetMaxY(clipped))));
    if (maxX <= minX || maxY <= minY) return (AutoUIKitPixelImage){0};
    if (originX) *originX = minX;
    if (originY) *originY = minY;
    if (minX == 0 && minY == 0 && maxX == imageWidth && maxY == imageHeight) {
        return AutoUIKitPixelImageMake(image);
    }
    CGImageRef cropped = CGImageCreateWithImageInRect(image, CGRectMake(minX, minY, maxX - minX, maxY - minY));
    if (!cropped) return (AutoUIKitPixelImage){0};
    AutoUIKitPixelImage result = AutoUIKitPixelImageMake(cropped);
    CGImageRelease(cropped);
    return result;
}

static void AutoUIKitPixelImageDestroy(AutoUIKitPixelImage *image) {
    if (image->context) CGContextRelease(image->context);
    free(image->bytes);
    *image = (AutoUIKitPixelImage){0};
}

static NSUInteger AutoUIKitAdaptedScanStep(NSUInteger width,
                                            NSUInteger height,
                                            NSUInteger step,
                                            NSUInteger maxCandidates) {
    step = MIN((NSUInteger)1024, MAX((NSUInteger)1, step));
    if (width == 0 || height == 0 || maxCandidates == 0) return step;
    maxCandidates = MIN((NSUInteger)5000000, MAX((NSUInteger)1000, maxCandidates));
    double columns = ceil((double)width / (double)step);
    double rows = ceil((double)height / (double)step);
    double estimatedCandidates = columns * rows;
    if (estimatedCandidates > (double)maxCandidates) {
        NSUInteger adaptiveStep = (NSUInteger)ceil((double)step * sqrt(estimatedCandidates / (double)maxCandidates));
        step = MIN((NSUInteger)1024, MAX(step, adaptiveStep));
    }
    return step;
}

typedef struct {
    NSInteger dx;
    NSInteger dy;
    uint8_t red;
    uint8_t green;
    uint8_t blue;
    CGFloat tolerance;
} AutoUIKitColorOffset;

typedef struct {
    NSUInteger x;
    NSUInteger y;
    uint8_t red;
    uint8_t green;
    uint8_t blue;
    CGFloat tolerance;
} AutoUIKitColorPoint;

static BOOL AutoUIKitParseColor(id color, uint8_t *red, uint8_t *green, uint8_t *blue) {
    if ([color isKindOfClass:NSArray.class] && [color count] >= 3) {
        if (!AutoUIKitIsNumber(color[0]) || !AutoUIKitIsNumber(color[1]) || !AutoUIKitIsNumber(color[2])) return NO;
        *red = (uint8_t)MIN(255, MAX(0, AutoUIKitDouble(color[0], 0)));
        *green = (uint8_t)MIN(255, MAX(0, AutoUIKitDouble(color[1], 0)));
        *blue = (uint8_t)MIN(255, MAX(0, AutoUIKitDouble(color[2], 0)));
        return YES;
    }
    if ([color isKindOfClass:NSDictionary.class]) {
        NSDictionary *dictionary = color;
        id r = dictionary[@"r"] ?: dictionary[@"red"];
        id g = dictionary[@"g"] ?: dictionary[@"green"];
        id b = dictionary[@"b"] ?: dictionary[@"blue"];
        if (AutoUIKitIsNumber(r) && AutoUIKitIsNumber(g) && AutoUIKitIsNumber(b)) {
            *red = (uint8_t)MIN(255, MAX(0, AutoUIKitDouble(r, 0)));
            *green = (uint8_t)MIN(255, MAX(0, AutoUIKitDouble(g, 0)));
            *blue = (uint8_t)MIN(255, MAX(0, AutoUIKitDouble(b, 0)));
            return YES;
        }
    }
    if (![color isKindOfClass:NSString.class] || [(NSString *)color length] > 32) return NO;
    NSString *value = [(NSString *)color stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([value hasPrefix:@"#"]) value = [value substringFromIndex:1];
    if ([value hasPrefix:@"0x"] || [value hasPrefix:@"0X"]) value = [value substringFromIndex:2];
    if (value.length != 6 && value.length != 8) return NO;
    unsigned long long number = 0;
    NSScanner *scanner = [NSScanner scannerWithString:value];
    if (![scanner scanHexLongLong:&number] || !scanner.isAtEnd) return NO;
    *red = (uint8_t)((number >> 16) & 0xff);
    *green = (uint8_t)((number >> 8) & 0xff);
    *blue = (uint8_t)(number & 0xff);
    return YES;
}

static CGRect AutoUIKitPixelRegion(NSDictionary *region, CGFloat scale, size_t width, size_t height) {
    BOOL hasWidth = region[@"width"] != nil;
    BOOL hasHeight = region[@"height"] != nil;
    CGFloat x = AutoUIKitDouble(region[@"x"], 0) * scale;
    CGFloat y = AutoUIKitDouble(region[@"y"], 0) * scale;
    CGFloat w = AutoUIKitDouble(region[@"width"], 0) * scale;
    CGFloat h = AutoUIKitDouble(region[@"height"], 0) * scale;
    if (!isfinite(x) || !isfinite(y) || !isfinite(w) || !isfinite(h)) return CGRectNull;
    CGRect bounds = CGRectMake(0, 0, width, height);
    if (!hasWidth && !hasHeight) return bounds;
    if (!hasWidth || !hasHeight || w <= 0 || h <= 0) return CGRectNull;
    return CGRectIntersection(CGRectMake(x, y, w, h), bounds);
}

static NSDictionary *AutoUIKitMatchResult(CGFloat x, CGFloat y, CGFloat width, CGFloat height, CGFloat scale) {
    scale = AutoUIKitSafeScale(scale);
    return @{ @"found": @YES,
              @"x": @(x / scale), @"y": @(y / scale),
              @"width": @(width / scale), @"height": @(height / scale),
              @"centerX": @((x + width / 2) / scale),
              @"centerY": @((y + height / 2) / scale) };
}

static UIImage *AutoUIKitTemplateImage(NSString *path) {
    if (![path isKindOfClass:NSString.class] || path.length == 0 || path.length > 4096) return nil;
    static NSCache<NSString *, UIImage *> *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [NSCache new];
        cache.countLimit = 32;
        cache.totalCostLimit = 32 * 1024 * 1024;
    });
    NSString *resolvedPath = nil;
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        resolvedPath = path.stringByStandardizingPath;
    } else {
        NSString *extension = path.pathExtension.length > 0 ? path.pathExtension : @"png";
        resolvedPath = [[NSBundle mainBundle] pathForResource:path.stringByDeletingPathExtension ofType:extension];
    }
    if (!resolvedPath) return [UIImage imageNamed:path];
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:resolvedPath error:nil];
    NSString *cacheKey = [NSString stringWithFormat:@"%@|%@|%@", resolvedPath,
                          attributes[NSFileSize] ?: @0,
                          attributes[NSFileModificationDate] ?: @0];
    UIImage *image = [cache objectForKey:cacheKey];
    if (image) return image;
    image = [UIImage imageWithContentsOfFile:resolvedPath];
    if (image) {
        CGImageRef imageRef = image.CGImage;
        size_t width = imageRef ? CGImageGetWidth(imageRef) : 0;
        size_t height = imageRef ? CGImageGetHeight(imageRef) : 0;
        NSUInteger cost = width > 0 && height <= NSUIntegerMax / width / 4 ? width * height * 4 : 1;
        [cache setObject:image forKey:cacheKey cost:cost];
    }
    return image;
}

static CGFloat AutoUIKitImageSimilarity(AutoUIKitPixelImage needle,
                                        AutoUIKitPixelImage haystack,
                                        NSUInteger originX,
                                        NSUInteger originY,
                                        NSUInteger stepX,
                                        NSUInteger stepY,
                                        NSUInteger offsetX,
                                        NSUInteger offsetY,
                                        CGFloat minimumSimilarity,
                                        BOOL (^shouldCancel)(void),
                                        BOOL *cancelled) {
    if (cancelled) *cancelled = NO;
    double sampleWeight = 0;
    double difference = 0;
    NSUInteger checkedSamples = 0;
    NSUInteger xStep = MAX(1, stepX), yStep = MAX(1, stepY);
    NSUInteger xOffset = MIN(offsetX, needle.width - 1), yOffset = MIN(offsetY, needle.height - 1);
    NSUInteger totalSamples = ((needle.width - 1 - xOffset) / xStep + 1) *
                              ((needle.height - 1 - yOffset) / yStep + 1);
    double maximumDifference = MAX(0, 1.0 - minimumSimilarity) * totalSamples;
    for (NSUInteger y = yOffset; y < needle.height; y += yStep) {
        for (NSUInteger x = xOffset; x < needle.width; x += xStep) {
            if ((checkedSamples++ & 0xFFF) == 0 && shouldCancel && shouldCancel()) {
                if (cancelled) *cancelled = YES;
                return 0;
            }
            const uint8_t *a = needle.bytes + y * needle.bytesPerRow + x * 4;
            const uint8_t *b = haystack.bytes + (originY + y) * haystack.bytesPerRow + (originX + x) * 4;
            if (a[3] == 0) continue;
            double alphaWeight = (double)a[3] / 255.0;
            if (b[3] == 0) {
                difference += alphaWeight;
                sampleWeight += alphaWeight;
                if (minimumSimilarity > 0 && difference > maximumDifference) return 0;
                continue;
            }
            double needleAlpha = MAX(1.0, (double)a[3]);
            double haystackAlpha = MAX(1.0, (double)b[3]);
            double redDifference = fabs(MIN(255.0, (double)a[0] * 255.0 / needleAlpha) -
                                        MIN(255.0, (double)b[0] * 255.0 / haystackAlpha));
            double greenDifference = fabs(MIN(255.0, (double)a[1] * 255.0 / needleAlpha) -
                                          MIN(255.0, (double)b[1] * 255.0 / haystackAlpha));
            double blueDifference = fabs(MIN(255.0, (double)a[2] * 255.0 / needleAlpha) -
                                         MIN(255.0, (double)b[2] * 255.0 / haystackAlpha));
            difference += alphaWeight * (redDifference + greenDifference + blueDifference) / (3.0 * 255.0);
            sampleWeight += alphaWeight;
            if (minimumSimilarity > 0 && difference > maximumDifference) return 0;
        }
    }
    return sampleWeight > 0 ? (CGFloat)MAX(0, 1.0 - difference / sampleWeight) : 0;
}

static inline uint8_t AutoUIKitUnpremultipliedComponent(const uint8_t *pixel, NSUInteger component) {
    uint8_t alpha = pixel[3];
    if (alpha == 0) return 0;
    if (alpha == 255) return pixel[component];
    return (uint8_t)MIN(255.0, round((double)pixel[component] * 255.0 / alpha));
}

static BOOL AutoUIKitPixelMatches(const uint8_t *pixel, uint8_t red, uint8_t green, uint8_t blue, CGFloat tolerance) {
    if (pixel[3] == 0) return NO;
    return fabs((double)AutoUIKitUnpremultipliedComponent(pixel, 0) - red) <= tolerance &&
           fabs((double)AutoUIKitUnpremultipliedComponent(pixel, 1) - green) <= tolerance &&
           fabs((double)AutoUIKitUnpremultipliedComponent(pixel, 2) - blue) <= tolerance;
}

static NSDictionary *AutoUIKitPixelColorResult(const uint8_t *pixel, CGFloat x, CGFloat y) {
    uint8_t red = AutoUIKitUnpremultipliedComponent(pixel, 0);
    uint8_t green = AutoUIKitUnpremultipliedComponent(pixel, 1);
    uint8_t blue = AutoUIKitUnpremultipliedComponent(pixel, 2);
    NSString *hex = [NSString stringWithFormat:@"#%02X%02X%02X", red, green, blue];
    return @{ @"x": @(x), @"y": @(y), @"r": @(red), @"g": @(green), @"b": @(blue),
              @"a": @(pixel[3]), @"hex": hex };
}

static UIScrollView *AutoUIKitFindScrollView(UIView *view) {
    if (!view) return nil;
    NSMutableArray<UIView *> *views = [NSMutableArray arrayWithObject:view];
    NSMutableArray<NSNumber *> *nextChildIndexes = [NSMutableArray arrayWithObject:@(view.subviews.count)];
    NSUInteger visitedCount = 1;
    if ([view isKindOfClass:UIScrollView.class]) return (UIScrollView *)view;
    while (views.count > 0 && visitedCount < AutoUIKitMaxFindVisitedViews) {
        UIView *candidate = views.lastObject;
        NSUInteger nextChildIndex = nextChildIndexes.lastObject.unsignedIntegerValue;
        if (nextChildIndex == 0) {
            [views removeLastObject];
            [nextChildIndexes removeLastObject];
            continue;
        }
        nextChildIndex -= 1;
        nextChildIndexes[nextChildIndexes.count - 1] = @(nextChildIndex);
        UIView *child = candidate.subviews[nextChildIndex];
        visitedCount += 1;
        if ([child isKindOfClass:UIScrollView.class]) return (UIScrollView *)child;
        [views addObject:child];
        [nextChildIndexes addObject:@(child.subviews.count)];
    }
    return nil;
}

static void AutoUIKitStopScrollAnimation(UIScrollView *scrollView, CGPoint fallbackOffset) {
    CALayer *presentationLayer = scrollView.layer.presentationLayer;
    BOOL hasPendingAnimation = scrollView.layer.animationKeys.count > 0;
    CGPoint visibleOffset = presentationLayer ? presentationLayer.bounds.origin :
                            (hasPendingAnimation ? fallbackOffset : scrollView.contentOffset);
    if (!AutoUIKitPointIsFinite(visibleOffset)) {
        visibleOffset = AutoUIKitPointIsFinite(fallbackOffset) ? fallbackOffset : CGPointZero;
    }
    [scrollView.layer removeAllAnimations];
    [scrollView setContentOffset:visibleOffset animated:NO];
}

static BOOL AutoUIKitActivateView(UIView *view, NSError **error) {
    if (!AutoUIKitViewIsVisible(view)) {
        if (error) *error = AutoUIKitError(@"The matched view is not visible in the active window.");
        return NO;
    }
    if ([view isKindOfClass:UIControl.class] && !((UIControl *)view).enabled) {
        if (error) *error = AutoUIKitError(@"The matched control is disabled.");
        return NO;
    }
    if ([view isKindOfClass:UISwitch.class]) {
        UISwitch *control = (UISwitch *)view;
        [control setOn:!control.isOn animated:YES];
        [control sendActionsForControlEvents:UIControlEventValueChanged];
        return YES;
    }
    if ([view isKindOfClass:UIControl.class] && ((UIControl *)view).enabled) {
        [(UIControl *)view sendActionsForControlEvents:UIControlEventTouchUpInside];
        return YES;
    }
    if ([view accessibilityActivate]) return YES;
    if (error) *error = AutoUIKitError(@"The matched view does not expose a public activation action.");
    return NO;
}

@interface AutoUIKitAdapter ()
@property (nonatomic, strong, nullable) NSData *screenshotCacheData;
@property (nonatomic, strong, nullable) UIImage *screenshotCacheImage;
@property (nonatomic, assign) NSTimeInterval screenshotCacheTimestamp;
@property (nonatomic, assign) NSUInteger screenshotCacheGeneration;
@property (nonatomic, strong) NSRecursiveLock *visualOperationLock;
@property (nonatomic, assign) NSUInteger operationCancellationGeneration;
@property (nonatomic, strong) NSMutableSet<VNRequest *> *activeVisionRequests;
- (UIView *)findViewForSelector:(id)selector operationGeneration:(NSUInteger)operationGeneration error:(NSError **)error;
- (UIImage *)capturedImageForOperationGeneration:(NSUInteger)operationGeneration error:(NSError **)error;
- (UIImage *)threadSafeCapturedImageForOperationGeneration:(NSUInteger)operationGeneration error:(NSError **)error;
- (NSUInteger)currentOperationCancellationGeneration;
- (BOOL)operationWasCancelledSinceGeneration:(NSUInteger)generation;
@end

@implementation AutoUIKitAdapter

@synthesize screenshotCacheDuration = _screenshotCacheDuration;

- (instancetype)init {
    self = [super init];
    if (self) {
        _screenshotCacheDuration = 0;
        _visualOperationLock = [NSRecursiveLock new];
        _visualOperationLock.name = @"com.autosdk.uikit.visual-processing";
        _activeVisionRequests = [NSMutableSet set];
    }
    return self;
}

- (NSUInteger)currentOperationCancellationGeneration {
    @synchronized (self) { return self.operationCancellationGeneration; }
}

- (BOOL)operationWasCancelledSinceGeneration:(NSUInteger)generation {
    @synchronized (self) { return generation != self.operationCancellationGeneration; }
}

- (UIView *)findViewForSelector:(id)selector operationGeneration:(NSUInteger)operationGeneration error:(NSError **)error {
    return AutoUIKitFindView(selector, ^BOOL{
        return [self operationWasCancelledSinceGeneration:operationGeneration];
    }, error);
}

- (void)cancelCurrentOperations {
    NSArray<VNRequest *> *visionRequests = nil;
    @synchronized (self) {
        self.operationCancellationGeneration += 1;
        self.screenshotCacheGeneration += 1;
        self.screenshotCacheData = nil;
        self.screenshotCacheImage = nil;
        self.screenshotCacheTimestamp = 0;
        visionRequests = self.activeVisionRequests.allObjects;
    }
    for (VNRequest *request in visionRequests) [request cancel];
}

- (void)setScreenshotCacheDuration:(NSTimeInterval)screenshotCacheDuration {
    NSTimeInterval value = isfinite(screenshotCacheDuration) && screenshotCacheDuration > 0
        ? MIN(screenshotCacheDuration, 2.0)
        : 0;
    @synchronized (self) {
        if (_screenshotCacheDuration == value) return;
        _screenshotCacheDuration = value;
        self.screenshotCacheGeneration += 1;
        self.screenshotCacheData = nil;
        self.screenshotCacheImage = nil;
        self.screenshotCacheTimestamp = 0;
    }
}

- (NSTimeInterval)screenshotCacheDuration {
    @synchronized (self) { return _screenshotCacheDuration; }
}

- (void)invalidateScreenshotCache {
    @synchronized (self) {
        self.screenshotCacheData = nil;
        self.screenshotCacheImage = nil;
        self.screenshotCacheTimestamp = 0;
        self.screenshotCacheGeneration += 1;
    }
}

- (BOOL)click:(id)selector error:(NSError **)error {
    NSUInteger operationGeneration = [self currentOperationCancellationGeneration];
    if (!AutoUIKitRequireMainThread(error)) return NO;
    UIView *view = [self findViewForSelector:selector operationGeneration:operationGeneration error:error];
    if (!view) return NO;
    if ([self operationWasCancelledSinceGeneration:operationGeneration]) {
        if (error) *error = AutoUIKitCancelledError(@"UIKit click was cancelled.");
        return NO;
    }
    BOOL success = AutoUIKitActivateView(view, error);
    if (success) [self invalidateScreenshotCache];
    return success;
}

- (BOOL)clickAtX:(CGFloat)x y:(CGFloat)y error:(NSError **)error {
    if (!AutoUIKitRequireMainThread(error)) return NO;
    if (!isfinite(x) || !isfinite(y)) {
        if (error) *error = AutoUIKitError(@"Click coordinates must be finite.");
        return NO;
    }
    UIWindow *window = AutoUIKitActiveWindow();
    if (!window) {
        if (error) *error = AutoUIKitError(@"No active application window is available.");
        return NO;
    }
    if (!CGRectContainsPoint(window.bounds, CGPointMake(x, y))) {
        if (error) *error = AutoUIKitError(@"Click coordinates are outside the active window.");
        return NO;
    }
    UIView *view = [window hitTest:CGPointMake(x, y) withEvent:nil];
    if (!view) {
        if (error) *error = AutoUIKitElementError(@"No view exists at the requested coordinates.");
        return NO;
    }
    for (UIView *candidate = view; candidate; candidate = candidate.superview) {
        if ([candidate isKindOfClass:UIControl.class] || candidate.isAccessibilityElement) {
            BOOL success = AutoUIKitActivateView(candidate, error);
            if (success) [self invalidateScreenshotCache];
            return success;
        }
    }
    BOOL success = AutoUIKitActivateView(view, error);
    if (success) [self invalidateScreenshotCache];
    return success;
}

- (BOOL)doubleClickAtX:(CGFloat)x y:(CGFloat)y interval:(NSTimeInterval)interval error:(NSError **)error {
    NSUInteger operationGeneration = [self currentOperationCancellationGeneration];
    if ([self operationWasCancelledSinceGeneration:operationGeneration]) {
        if (error) *error = AutoUIKitCancelledError(@"Double click was cancelled.");
        return NO;
    }
    if (!isfinite(interval)) {
        if (error) *error = AutoUIKitError(@"Double-click interval must be finite.");
        return NO;
    }
    if (![self clickAtX:x y:y error:error]) return NO;
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:MAX(0.01, MIN(0.5, interval))];
    while ([deadline timeIntervalSinceNow] > 0) {
        if ([self operationWasCancelledSinceGeneration:operationGeneration]) {
            if (error) *error = AutoUIKitCancelledError(@"Double click was cancelled.");
            return NO;
        }
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:MIN(0.01, [deadline timeIntervalSinceNow])]];
    }
    if ([self operationWasCancelledSinceGeneration:operationGeneration]) {
        if (error) *error = AutoUIKitCancelledError(@"Double click was cancelled.");
        return NO;
    }
    return [self clickAtX:x y:y error:error];
}

- (BOOL)longClick:(id)selector duration:(NSTimeInterval)duration error:(NSError **)error {
    NSUInteger operationGeneration = [self currentOperationCancellationGeneration];
    if (!AutoUIKitRequireMainThread(error)) return NO;
    if (![self findViewForSelector:selector operationGeneration:operationGeneration error:error]) return NO;
    if (error) *error = AutoUIKitError(@"UIKit does not provide a public API for synthesizing long-press touch events.");
    return NO;
}

- (BOOL)swipeFromX:(CGFloat)x1
                 y:(CGFloat)y1
                toX:(CGFloat)x2
                 y:(CGFloat)y2
          duration:(NSTimeInterval)duration
             error:(NSError **)error {
    NSUInteger operationGeneration = [self currentOperationCancellationGeneration];
    if (!AutoUIKitRequireMainThread(error)) return NO;
    if ([self operationWasCancelledSinceGeneration:operationGeneration]) {
        if (error) *error = AutoUIKitCancelledError(@"Swipe was cancelled.");
        return NO;
    }
    if (!isfinite(x1) || !isfinite(y1) || !isfinite(x2) || !isfinite(y2) || !isfinite(duration)) {
        if (error) *error = AutoUIKitError(@"Swipe coordinates and duration must be finite.");
        return NO;
    }
    UIWindow *window = AutoUIKitActiveWindow();
    if (!window) { if (error) *error = AutoUIKitError(@"No active application window is available."); return NO; }
    if (!CGRectContainsPoint(window.bounds, CGPointMake(x1, y1))) {
        if (error) *error = AutoUIKitError(@"Swipe start coordinates are outside the active window.");
        return NO;
    }
    UIView *hit = [window hitTest:CGPointMake(x1, y1) withEvent:nil];
    UIScrollView *scrollView = nil;
    for (UIView *view = hit; view; view = view.superview) {
        if ([view isKindOfClass:UIScrollView.class]) { scrollView = (UIScrollView *)view; break; }
    }
    if (!scrollView) scrollView = AutoUIKitFindScrollView(window);
    if (!scrollView) { if (error) *error = AutoUIKitError(@"No scroll view is available for swipe."); return NO; }
    UIEdgeInsets inset = scrollView.adjustedContentInset;
    if (!isfinite(inset.top) || !isfinite(inset.left) || !isfinite(inset.bottom) || !isfinite(inset.right) ||
        !isfinite(scrollView.contentSize.width) || !isfinite(scrollView.contentSize.height) ||
        !AutoUIKitRectIsFinite(scrollView.bounds) || !AutoUIKitPointIsFinite(scrollView.contentOffset) ||
        scrollView.contentSize.width < 0 || scrollView.contentSize.height < 0) {
        if (error) *error = AutoUIKitError(@"The scroll view contains invalid geometry.");
        return NO;
    }
    CGFloat minX = -inset.left;
    CGFloat minY = -inset.top;
    CGFloat maxX = MAX(minX, scrollView.contentSize.width - scrollView.bounds.size.width + inset.right);
    CGFloat maxY = MAX(minY, scrollView.contentSize.height - scrollView.bounds.size.height + inset.bottom);
    CGPoint initialOffset = scrollView.contentOffset;
    CGPoint target = CGPointMake(MIN(maxX, MAX(minX, scrollView.contentOffset.x + x1 - x2)),
                                 MIN(maxY, MAX(minY, scrollView.contentOffset.y + y1 - y2)));
    if (!AutoUIKitPointIsFinite(target)) {
        if (error) *error = AutoUIKitError(@"The swipe target is invalid.");
        return NO;
    }
    NSTimeInterval animationDuration = MIN(10, MAX(0, duration));
    [UIView animateWithDuration:animationDuration delay:0 options:UIViewAnimationOptionCurveLinear | UIViewAnimationOptionBeginFromCurrentState animations:^{
        scrollView.contentOffset = target;
    } completion:nil];
    if (animationDuration > 0) {
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:animationDuration];
        while ([deadline timeIntervalSinceNow] > 0) {
            if ([self operationWasCancelledSinceGeneration:operationGeneration]) {
                AutoUIKitStopScrollAnimation(scrollView, initialOffset);
                if (error) *error = AutoUIKitCancelledError(@"Swipe was cancelled.");
                return NO;
            }
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:MIN(0.02, [deadline timeIntervalSinceNow])]];
        }
    }
    if ([self operationWasCancelledSinceGeneration:operationGeneration]) {
        AutoUIKitStopScrollAnimation(scrollView, initialOffset);
        if (error) *error = AutoUIKitCancelledError(@"Swipe was cancelled.");
        return NO;
    }
    [self invalidateScreenshotCache];
    return YES;
}

- (BOOL)input:(id)selector text:(NSString *)text error:(NSError **)error {
    NSUInteger operationGeneration = [self currentOperationCancellationGeneration];
    if (!AutoUIKitRequireMainThread(error)) return NO;
    UIView *view = [self findViewForSelector:selector operationGeneration:operationGeneration error:error];
    if (view && [self operationWasCancelledSinceGeneration:operationGeneration]) {
        if (error) *error = AutoUIKitCancelledError(@"UIKit text input was cancelled.");
        return NO;
    }
    if ([view isKindOfClass:UITextField.class]) {
        UITextField *field = (UITextField *)view;
        if (!field.enabled) {
            if (error) *error = AutoUIKitError(@"The matched text field is disabled.");
            return NO;
        }
        field.text = text ?: @"";
        [field sendActionsForControlEvents:UIControlEventEditingChanged];
        [self invalidateScreenshotCache];
        return YES;
    }
    if ([view isKindOfClass:UITextView.class]) {
        UITextView *textView = (UITextView *)view;
        if (!textView.editable) {
            if (error) *error = AutoUIKitError(@"The matched text view is not editable.");
            return NO;
        }
        textView.text = text ?: @"";
        [[NSNotificationCenter defaultCenter] postNotificationName:UITextViewTextDidChangeNotification object:textView];
        [self invalidateScreenshotCache];
        return YES;
    }
    if (view && error) *error = AutoUIKitError(@"The matched view is not a text input.");
    return NO;
}

- (NSString *)textForSelector:(id)selector error:(NSError **)error {
    NSUInteger operationGeneration = [self currentOperationCancellationGeneration];
    if (!AutoUIKitRequireMainThread(error)) return nil;
    UIView *view = [self findViewForSelector:selector operationGeneration:operationGeneration error:error];
    return view ? AutoUIKitViewText(view) : nil;
}

- (BOOL)exists:(id)selector error:(NSError **)error {
    NSUInteger operationGeneration = [self currentOperationCancellationGeneration];
    if (!AutoUIKitRequireMainThread(error)) return NO;
    NSError *lookupError = nil;
    BOOL found = [self findViewForSelector:selector operationGeneration:operationGeneration error:&lookupError] != nil;
    if (!found && lookupError && lookupError.code != AutoSDKErrorElementNotFound && error) *error = lookupError;
    return found;
}

- (NSDictionary<NSString *,id> *)elementInfoForSelector:(id)selector error:(NSError **)error {
    NSUInteger operationGeneration = [self currentOperationCancellationGeneration];
    if (!AutoUIKitRequireMainThread(error)) return nil;
    UIWindow *window = AutoUIKitActiveWindow();
    UIView *view = [self findViewForSelector:selector operationGeneration:operationGeneration error:error];
    return view && window ? AutoUIKitElementInfo(view, selector, window) : nil;
}

- (NSArray<NSDictionary<NSString *,id> *> *)elementsInfoForSelector:(id)selector error:(NSError **)error {
    NSUInteger operationGeneration = [self currentOperationCancellationGeneration];
    if (!AutoUIKitRequireMainThread(error)) return nil;
    UIWindow *window = AutoUIKitActiveWindow();
    if (!window) {
        if (error) *error = AutoUIKitError(@"No active application window is available.");
        return nil;
    }
    NSUInteger maximum = 500;
    id unwrapped = AutoUIKitValidatedSelector(selector, error);
    if (!unwrapped) return nil;
    if ([unwrapped isKindOfClass:NSDictionary.class] && AutoUIKitUnsigned(unwrapped[@"maxResults"], 0) > 0) {
        maximum = MIN(2000, AutoUIKitUnsigned(unwrapped[@"maxResults"], 0));
    }
    NSUInteger maximumVisited = MAX((NSUInteger)5000, MIN((NSUInteger)50000, maximum * 20));
    if ([unwrapped isKindOfClass:NSDictionary.class] && AutoUIKitUnsigned(unwrapped[@"maxVisited"], 0) > 0) {
        maximumVisited = MIN((NSUInteger)50000, MAX((NSUInteger)1000, AutoUIKitUnsigned(unwrapped[@"maxVisited"], 0)));
    }
    NSMutableArray<UIView *> *views = [NSMutableArray array];
    NSMutableArray<NSNumber *> *viewIndexes = [NSMutableArray array];
    NSMutableArray<NSNumber *> *viewDepths = [NSMutableArray array];
    BOOL cancelled = NO;
    BOOL visitLimitReached = AutoUIKitCollectInView(window, unwrapped, maximum, maximumVisited, views,
                                                    viewIndexes, viewDepths, ^BOOL{
        return [self operationWasCancelledSinceGeneration:operationGeneration];
    }, &cancelled);
    if (cancelled || [self operationWasCancelledSinceGeneration:operationGeneration]) {
        if (error) *error = AutoUIKitCancelledError(@"UIKit node search was cancelled.");
        return nil;
    }
    if (visitLimitReached) {
        if (error) *error = AutoUIKitError(@"UIKit node search exceeded maxVisited before reaching maxResults. Narrow the selector or region.");
        return nil;
    }
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:views.count];
    NSUInteger index = 0;
    for (UIView *view in views) {
        if ((index & 0x7F) == 0 && [self operationWasCancelledSinceGeneration:operationGeneration]) {
            if (error) *error = AutoUIKitCancelledError(@"UIKit node search was cancelled.");
            return nil;
        }
        [result addObject:AutoUIKitElementInfoWithMetadata(view, window,
            viewIndexes[index].unsignedIntegerValue, viewDepths[index].unsignedIntegerValue,
            AutoUIKitViewIsVisible(view))];
        index += 1;
    }
    if ([self operationWasCancelledSinceGeneration:operationGeneration]) {
        if (error) *error = AutoUIKitCancelledError(@"UIKit node search was cancelled.");
        return nil;
    }
    return result;
}

- (NSArray<NSDictionary<NSString *,id> *> *)nodeSnapshotWithMaxResults:(NSUInteger)maxResults error:(NSError **)error {
    NSUInteger operationGeneration = [self currentOperationCancellationGeneration];
    if (!AutoUIKitRequireMainThread(error)) return nil;
    UIWindow *window = AutoUIKitActiveWindow();
    if (!window) {
        if (error) *error = AutoUIKitError(@"No active application window is available.");
        return nil;
    }
    NSUInteger maximum = MIN((NSUInteger)2000, MAX((NSUInteger)1, maxResults));
    NSMutableArray<NSDictionary<NSString *, id> *> *result = [NSMutableArray arrayWithCapacity:MIN(maximum, (NSUInteger)500)];
    NSMutableArray<UIView *> *pendingViews = [NSMutableArray arrayWithObject:window];
    NSMutableArray<NSNumber *> *nextChildIndexes = [NSMutableArray arrayWithObject:@(NSUIntegerMax)];
    NSMutableArray<NSNumber *> *siblingIndexes = [NSMutableArray arrayWithObject:@0];
    NSUInteger visitedCount = 0;
    while (pendingViews.count > 0 && result.count < maximum && visitedCount < AutoUIKitMaxFindVisitedViews) {
        UIView *view = pendingViews.lastObject;
        NSUInteger nextChildIndex = nextChildIndexes.lastObject.unsignedIntegerValue;
        if (nextChildIndex == NSUIntegerMax) {
            nextChildIndexes[nextChildIndexes.count - 1] = @0;
            visitedCount += 1;
            if ((visitedCount & 0x7F) == 0 && [self operationWasCancelledSinceGeneration:operationGeneration]) {
                if (error) *error = AutoUIKitCancelledError(@"UIKit node snapshot was cancelled.");
                return nil;
            }
            BOOL visible = AutoUIKitViewIsVisible(view);
            [result addObject:AutoUIKitElementInfoWithMetadata(view, window,
                siblingIndexes.lastObject.unsignedIntegerValue, pendingViews.count - 1, visible)];
            if (view.subviews.count == 0) {
                [pendingViews removeLastObject];
                [nextChildIndexes removeLastObject];
                [siblingIndexes removeLastObject];
            }
            continue;
        }
        if (nextChildIndex < view.subviews.count) {
            nextChildIndexes[nextChildIndexes.count - 1] = @(nextChildIndex + 1);
            UIView *child = view.subviews[nextChildIndex];
            [pendingViews addObject:child];
            [nextChildIndexes addObject:@(NSUIntegerMax)];
            [siblingIndexes addObject:@(nextChildIndex)];
        } else {
            [pendingViews removeLastObject];
            [nextChildIndexes removeLastObject];
            [siblingIndexes removeLastObject];
        }
    }
    if ([self operationWasCancelledSinceGeneration:operationGeneration]) {
        if (error) *error = AutoUIKitCancelledError(@"UIKit node snapshot was cancelled.");
        return nil;
    }
    if (pendingViews.count > 0 && result.count < maximum) {
        if (error) *error = AutoUIKitError(@"UIKit node snapshot exceeded the hierarchy traversal safety limit.");
        return nil;
    }
    return result;
}

- (id)attribute:(NSString *)attribute forSelector:(id)selector error:(NSError **)error {
    NSUInteger operationGeneration = [self currentOperationCancellationGeneration];
    if (!AutoUIKitRequireMainThread(error)) return nil;
    if (![attribute isKindOfClass:NSString.class] || attribute.length == 0 || attribute.length > 128) {
        if (error) *error = AutoUIKitError(@"Element attribute name must contain 1 to 128 characters.");
        return nil;
    }
    UIWindow *window = AutoUIKitActiveWindow();
    UIView *view = [self findViewForSelector:selector operationGeneration:operationGeneration error:error];
    if (!view || !window) return nil;
    NSString *name = attribute.lowercaseString;
    NSString *text = AutoUIKitViewText(view);
    if ([name isEqualToString:@"id"] || [name isEqualToString:@"accessibilityidentifier"]) return view.accessibilityIdentifier ?: NSNull.null;
    if ([name isEqualToString:@"label"] || [name isEqualToString:@"accessibilitylabel"]) return view.accessibilityLabel ?: NSNull.null;
    if ([name isEqualToString:@"name"]) return view.accessibilityLabel ?: (text ?: NSNull.null);
    if ([name isEqualToString:@"value"] || [name isEqualToString:@"accessibilityvalue"]) return view.accessibilityValue ?: (text ?: NSNull.null);
    if ([name isEqualToString:@"text"]) return text ?: NSNull.null;
    if ([name isEqualToString:@"type"]) return AutoUIKitFriendlyType(view) ?: @"";
    if ([name isEqualToString:@"classname"]) return NSStringFromClass(view.class) ?: @"";
    NSDictionary *info = AutoUIKitElementInfo(view, selector, window);
    if ([name isEqualToString:@"handle"] || [name isEqualToString:@"uid"] ||
        [name isEqualToString:@"enabled"] || [name isEqualToString:@"selected"] ||
        [name isEqualToString:@"accessible"] || [name isEqualToString:@"visible"] ||
        [name isEqualToString:@"index"] || [name isEqualToString:@"depth"] ||
        [name isEqualToString:@"childcount"] || [name isEqualToString:@"bounds"]) {
        return [name isEqualToString:@"childcount"] ? info[@"childCount"] : info[name];
    }
    if (error) *error = AutoUIKitError([NSString stringWithFormat:@"Unsupported element attribute: %@", attribute]);
    return nil;
}

- (NSDictionary<NSString *,id> *)boundsForSelector:(id)selector error:(NSError **)error {
    NSDictionary *info = [self elementInfoForSelector:selector error:error];
    return info[@"bounds"];
}

- (NSArray<NSDictionary<NSString *,id> *> *)childrenForSelector:(id)selector error:(NSError **)error {
    NSUInteger operationGeneration = [self currentOperationCancellationGeneration];
    if (!AutoUIKitRequireMainThread(error)) return nil;
    UIWindow *window = AutoUIKitActiveWindow();
    UIView *view = [self findViewForSelector:selector operationGeneration:operationGeneration error:error];
    if (!view || !window) return nil;
    NSUInteger maximum = 500;
    id unwrapped = AutoUIKitUnwrapSelector(selector);
    if ([unwrapped isKindOfClass:NSDictionary.class] && AutoUIKitUnsigned(unwrapped[@"maxResults"], 0) > 0) {
        maximum = MIN(2000, AutoUIKitUnsigned(unwrapped[@"maxResults"], 0));
    }
    BOOL includeInvisible = [unwrapped isKindOfClass:NSDictionary.class] &&
                            AutoUIKitBool(unwrapped[@"includeInvisible"], NO);
    NSMutableArray *children = [NSMutableArray arrayWithCapacity:MIN(maximum, view.subviews.count)];
    NSUInteger examinedChildren = 0;
    for (UIView *child in view.subviews) {
        if ((examinedChildren++ & 0x7F) == 0 &&
            [self operationWasCancelledSinceGeneration:operationGeneration]) {
            if (error) *error = AutoUIKitCancelledError(@"UIKit child lookup was cancelled.");
            return nil;
        }
        if (includeInvisible || AutoUIKitViewIsVisible(child)) {
            [children addObject:AutoUIKitElementInfo(child, selector, window)];
        }
        if (children.count >= maximum) break;
    }
    if ([self operationWasCancelledSinceGeneration:operationGeneration]) {
        if (error) *error = AutoUIKitCancelledError(@"UIKit child lookup was cancelled.");
        return nil;
    }
    return children;
}

- (NSDictionary<NSString *,id> *)parentForSelector:(id)selector error:(NSError **)error {
    NSUInteger operationGeneration = [self currentOperationCancellationGeneration];
    if (!AutoUIKitRequireMainThread(error)) return nil;
    UIWindow *window = AutoUIKitActiveWindow();
    UIView *view = [self findViewForSelector:selector operationGeneration:operationGeneration error:error];
    UIView *parent = view.superview;
    return parent && window ? AutoUIKitElementInfo(parent, selector, window) : nil;
}

- (BOOL)scrollIntoView:(id)selector error:(NSError **)error {
    NSUInteger operationGeneration = [self currentOperationCancellationGeneration];
    if (!AutoUIKitRequireMainThread(error)) return NO;
    UIWindow *window = AutoUIKitActiveWindow();
    UIView *view = [self findViewForSelector:selector operationGeneration:operationGeneration error:error];
    if (!view || !window) return NO;
    NSMutableArray<UIScrollView *> *scrollViews = [NSMutableArray array];
    for (UIView *parent = view.superview; parent; parent = parent.superview) {
        if ([parent isKindOfClass:UIScrollView.class]) [scrollViews addObject:(UIScrollView *)parent];
    }
    if (scrollViews.count == 0) {
        if (error) *error = AutoUIKitError(@"The element is not inside a scroll view.");
        return NO;
    }
    for (UIScrollView *scrollView in scrollViews) {
        if ([self operationWasCancelledSinceGeneration:operationGeneration]) {
            if (error) *error = AutoUIKitCancelledError(@"UIKit scroll-into-view was cancelled.");
            return NO;
        }
        CGRect rect = [view convertRect:view.bounds toView:scrollView];
        if (!AutoUIKitRectIsFinite(rect) || CGRectIsNull(rect) || CGRectIsEmpty(rect)) {
            if (error) *error = AutoUIKitError(@"The element has invalid scroll geometry.");
            return NO;
        }
        [scrollView scrollRectToVisible:rect animated:NO];
        [scrollView layoutIfNeeded];
    }
    [self invalidateScreenshotCache];
    if (!AutoUIKitViewIsVisible(view)) {
        if (error) *error = AutoUIKitError(@"The scroll view could not make the element visible.");
        return NO;
    }
    return YES;
}

- (UIImage *)capturedImageForOperationGeneration:(NSUInteger)operationGeneration error:(NSError **)error {
    if (!AutoUIKitRequireMainThread(error)) return nil;
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    __block NSUInteger captureGeneration = 0;
    @synchronized (self) {
        if (operationGeneration != self.operationCancellationGeneration) {
            if (error) *error = AutoUIKitCancelledError(@"Screenshot capture was cancelled.");
            return nil;
        }
        if (self.screenshotCacheDuration > 0 && self.screenshotCacheImage &&
            now - self.screenshotCacheTimestamp <= self.screenshotCacheDuration) return self.screenshotCacheImage;
        captureGeneration = self.screenshotCacheGeneration;
    }
    UIWindow *window = AutoUIKitActiveWindow();
    if (!window) { if (error) *error = AutoUIKitError(@"No active application window is available."); return nil; }
    if (!AutoUIKitRectIsFinite(window.bounds) || CGRectIsNull(window.bounds) || CGRectIsEmpty(window.bounds)) {
        if (error) *error = AutoUIKitError(@"The active application window has invalid bounds.");
        return nil;
    }
    UIImage *image = nil;
    @try {
        UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
        format.scale = AutoUIKitSafeScale(window.screen.scale);
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithBounds:window.bounds format:format];
        image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
            if (![window drawViewHierarchyInRect:window.bounds afterScreenUpdates:YES]) {
                [window.layer renderInContext:context.CGContext];
            }
        }];
    } @catch (NSException *exception) {
        if (error) *error = AutoUIKitError([NSString stringWithFormat:@"Screenshot rendering failed: %@", exception.reason ?: @"unknown error"]);
        return nil;
    }
    if (!image) {
        if (error) *error = AutoUIKitError(@"Unable to render the application window.");
        return nil;
    }
    __block NSUInteger generation = 0;
    __block NSTimeInterval duration = 0;
    __block BOOL cancelled = NO;
    @synchronized (self) {
        cancelled = operationGeneration != self.operationCancellationGeneration;
        duration = self.screenshotCacheDuration;
        if (!cancelled && duration > 0 && self.screenshotCacheGeneration == captureGeneration) {
            self.screenshotCacheImage = image;
            self.screenshotCacheData = nil;
            self.screenshotCacheTimestamp = NSProcessInfo.processInfo.systemUptime;
            generation = ++self.screenshotCacheGeneration;
        }
    }
    if (cancelled) {
        if (error) *error = AutoUIKitCancelledError(@"Screenshot capture was cancelled.");
        return nil;
    }
    if (duration > 0 && generation > 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            @synchronized (self) {
                if (self.screenshotCacheGeneration == generation) {
                    self.screenshotCacheData = nil;
                    self.screenshotCacheImage = nil;
                    self.screenshotCacheTimestamp = 0;
                    self.screenshotCacheGeneration += 1;
                }
            }
        });
    }
    return image;
}

- (UIImage *)threadSafeCapturedImageForOperationGeneration:(NSUInteger)operationGeneration error:(NSError **)error {
    if (NSThread.isMainThread) return [self capturedImageForOperationGeneration:operationGeneration error:error];
    __block UIImage *image = nil;
    __block NSError *captureError = nil;
    dispatch_sync(dispatch_get_main_queue(), ^{
        image = [self capturedImageForOperationGeneration:operationGeneration error:&captureError];
    });
    if (!image && error) *error = captureError ?: AutoUIKitError(@"Unable to capture the application window.");
    return image;
}

- (NSData *)screenshotWithError:(NSError **)error {
    NSUInteger operationGeneration = [self currentOperationCancellationGeneration];
    @autoreleasepool {
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    @synchronized (self) {
        if (self.screenshotCacheDuration > 0 && self.screenshotCacheData &&
            now - self.screenshotCacheTimestamp <= self.screenshotCacheDuration) {
            if (operationGeneration != self.operationCancellationGeneration) {
                if (error) *error = AutoUIKitCancelledError(@"Screenshot was cancelled.");
                return nil;
            }
            return self.screenshotCacheData;
        }
    }
    UIImage *image = [self threadSafeCapturedImageForOperationGeneration:operationGeneration error:error];
    if (!image) return nil;
    [self.visualOperationLock lock];
    @try {
    if ([self operationWasCancelledSinceGeneration:operationGeneration]) {
        if (error) *error = AutoUIKitCancelledError(@"Screenshot encoding was cancelled.");
        return nil;
    }
    __block NSUInteger captureGeneration = 0;
    @synchronized (self) {
        if (self.screenshotCacheDuration > 0 && self.screenshotCacheImage == image) {
            captureGeneration = self.screenshotCacheGeneration;
        }
    }
    NSData *data = UIImagePNGRepresentation(image);
    if (!data) {
        if (error && !*error) *error = AutoUIKitError(@"Unable to encode screenshot as PNG.");
        return nil;
    }
    @synchronized (self) {
        if (operationGeneration != self.operationCancellationGeneration) {
            if (error) *error = AutoUIKitCancelledError(@"Screenshot encoding was cancelled.");
            return nil;
        }
        if (captureGeneration > 0 && self.screenshotCacheDuration > 0 &&
            self.screenshotCacheGeneration == captureGeneration && self.screenshotCacheImage == image) {
            self.screenshotCacheData = data;
        }
    }
    return data;
    } @catch (NSException *exception) {
        if (error) *error = AutoUIKitError([NSString stringWithFormat:@"Screenshot encoding failed: %@", exception.reason ?: @"unknown error"]);
        return nil;
    } @finally {
        [self.visualOperationLock unlock];
    }
    }
}

- (NSDictionary *)findImageAtPath:(NSString *)templatePath options:(NSDictionary *)options error:(NSError **)error {
    NSUInteger operationGeneration = [self currentOperationCancellationGeneration];
    @autoreleasepool {
    options = [options isKindOfClass:NSDictionary.class] ? options : @{};
    if (!AutoUIKitRegionIsValid(options[@"region"])) {
        if (error) *error = AutoUIKitError(@"Image search region must use finite coordinates and paired positive dimensions.");
        return nil;
    }
    NSString *path = templatePath;
    UIImage *template = AutoUIKitTemplateImage(path);
    CGImageRef templateCGImage = template.CGImage;
    size_t templateWidth = templateCGImage ? CGImageGetWidth(templateCGImage) : 0;
    size_t templateHeight = templateCGImage ? CGImageGetHeight(templateCGImage) : 0;
    size_t needleByteCount = 0;
    if (!template || !templateCGImage ||
        !AutoUIKitPixelByteCount(templateWidth, templateHeight, &needleByteCount) ||
        needleByteCount > AutoUIKitMaxPixelBufferBytes) {
        if (error && !*error) *error = AutoUIKitError(@"Unable to load or decode the image template.");
        return nil;
    }
    UIImage *screenImage = [self threadSafeCapturedImageForOperationGeneration:operationGeneration error:error];
    if (!screenImage) return nil;
    CGImageRef screenCGImage = screenImage.CGImage;
    if (!screenCGImage) {
        if (error && !*error) *error = AutoUIKitError(@"Unable to decode image matching inputs.");
        return nil;
    }
    AutoUIKitPixelImage needle = {0};
    AutoUIKitPixelImage haystack = {0};
    [self.visualOperationLock lock];
    @try {
    if ([self operationWasCancelledSinceGeneration:operationGeneration]) {
        if (error) *error = AutoUIKitCancelledError(@"Image search was cancelled.");
        return nil;
    }
    CGFloat scale = AutoUIKitSafeScale(screenImage.scale);
    CGRect search = AutoUIKitPixelRegion([options[@"region"] isKindOfClass:NSDictionary.class] ? options[@"region"] : @{},
                                         scale, CGImageGetWidth(screenCGImage), CGImageGetHeight(screenCGImage));
    if (CGRectIsNull(search) || CGRectIsEmpty(search)) return @{ @"found": @NO };
    NSUInteger searchMinX = (NSUInteger)floor(CGRectGetMinX(search));
    NSUInteger searchMinY = (NSUInteger)floor(CGRectGetMinY(search));
    NSUInteger searchMaxX = (NSUInteger)ceil(CGRectGetMaxX(search));
    NSUInteger searchMaxY = (NSUInteger)ceil(CGRectGetMaxY(search));
    size_t searchWidth = searchMaxX - searchMinX, searchHeight = searchMaxY - searchMinY;
    if (templateWidth > searchWidth || templateHeight > searchHeight) return @{ @"found": @NO };
    size_t haystackByteCount = 0;
    if (!AutoUIKitPixelByteCount(searchWidth, searchHeight, &haystackByteCount) ||
        needleByteCount > AutoUIKitMaxPixelBufferBytes ||
        haystackByteCount > AutoUIKitMaxPixelBufferBytes - needleByteCount) {
        if (error) *error = AutoUIKitError(@"Image matching exceeds the 64 MB combined pixel-buffer limit.");
        return nil;
    }
    NSUInteger haystackOriginX = 0, haystackOriginY = 0;
    needle = AutoUIKitPixelImageMake(templateCGImage);
    if (!needle.bytes) {
        AutoUIKitPixelImageDestroy(&needle);
        if (error) *error = AutoUIKitError(@"Unable to allocate the image template buffer.");
        return nil;
    }
    BOOL hasVisibleTemplatePixel = NO, templateScanCancelled = NO;
    NSUInteger visibleTemplateAnchorX = 0, visibleTemplateAnchorY = 0;
    NSUInteger templatePixelsScanned = 0;
    for (NSUInteger y = 0; y < needle.height && !hasVisibleTemplatePixel; y++) {
        for (NSUInteger x = 0; x < needle.width; x++) {
            if ((templatePixelsScanned++ & 0xFFF) == 0 &&
                [self operationWasCancelledSinceGeneration:operationGeneration]) {
                templateScanCancelled = YES;
                break;
            }
            if (needle.bytes[y * needle.bytesPerRow + x * 4 + 3] > 0) {
                hasVisibleTemplatePixel = YES;
                visibleTemplateAnchorX = x;
                visibleTemplateAnchorY = y;
                break;
            }
        }
        if (templateScanCancelled) break;
    }
    if (templateScanCancelled || !hasVisibleTemplatePixel) {
        AutoUIKitPixelImageDestroy(&needle);
        if (error) *error = templateScanCancelled
            ? AutoUIKitCancelledError(@"Image search was cancelled.")
            : AutoUIKitError(@"The image template contains no visible pixels.");
        return nil;
    }
    haystack = AutoUIKitPixelImageMakeRegion(screenCGImage, search, &haystackOriginX, &haystackOriginY);
    if (!haystack.bytes || needle.width > haystack.width || needle.height > haystack.height) {
        BOOL allocationFailed = !haystack.bytes;
        AutoUIKitPixelImageDestroy(&needle);
        AutoUIKitPixelImageDestroy(&haystack);
        if (allocationFailed && error) *error = AutoUIKitError(@"Unable to allocate the image search buffer.");
        return allocationFailed ? nil : @{ @"found": @NO };
    }
    CGFloat threshold = AutoUIKitDouble(options[@"threshold"], 0);
    if (threshold <= 0 || threshold > 1) threshold = 0.92;
    NSUInteger step = AutoUIKitUnsigned(options[@"step"], 0);
    if (step == 0) step = 1;
    step = MIN(step, (NSUInteger)1024);
    NSUInteger requestedStep = step;
    NSUInteger sampleX = MAX(1, needle.width / 16);
    NSUInteger sampleY = MAX(1, needle.height / 16);
    NSUInteger sampleOffsetX = visibleTemplateAnchorX % sampleX;
    NSUInteger sampleOffsetY = visibleTemplateAnchorY % sampleY;
    NSUInteger minX = 0, minY = 0;
    NSUInteger maxX = haystack.width >= needle.width ? haystack.width - needle.width + 1 : 0;
    NSUInteger maxY = haystack.height >= needle.height ? haystack.height - needle.height + 1 : 0;
    NSUInteger candidateWidth = maxX, candidateHeight = maxY;
    NSUInteger maxCandidates = AutoUIKitWorkBudget(options[@"maxCandidates"], 200000, 1000, 5000000);
    NSUInteger verificationLimit = MIN((NSUInteger)4096, MAX((NSUInteger)32, maxCandidates / 4));
    NSUInteger coarseLimit = MAX((NSUInteger)1, maxCandidates - verificationLimit);
    step = AutoUIKitAdaptedScanStep(candidateWidth, candidateHeight, step, coarseLimit);
    NSUInteger verifyStep = AutoUIKitUnsigned(options[@"verifyStep"], 0);
    if (verifyStep == 0) verifyStep = 1;
    verifyStep = MIN(verifyStep, MAX(1, MIN(needle.width, needle.height)));
    NSUInteger verifyOffsetX = visibleTemplateAnchorX % verifyStep;
    NSUInteger verifyOffsetY = visibleTemplateAnchorY % verifyStep;
    CGFloat coarseThreshold = MAX(0, threshold - 0.15);
    NSUInteger maxComparedPixels = AutoUIKitWorkBudget(options[@"maxComparedPixels"], 50000000, 100000, 500000000);
    NSUInteger coarsePixelCost = ((needle.width + sampleX - 1) / sampleX) * ((needle.height + sampleY - 1) / sampleY);
    NSUInteger verificationPixelCost = ((needle.width + verifyStep - 1) / verifyStep) * ((needle.height + verifyStep - 1) / verifyStep);
    NSUInteger comparedPixelBudget = 0;
    NSDictionary *result = nil;
    NSUInteger coarseCandidates = 0, verifiedCandidates = 0;
    BOOL truncated = NO, cancelled = NO;
    BOOL (^shouldCancelSimilarity)(void) = ^BOOL{
        return [self operationWasCancelledSinceGeneration:operationGeneration];
    };
    for (NSUInteger y = minY; y < maxY && !result && !truncated && !cancelled; y += step) {
        if ([self operationWasCancelledSinceGeneration:operationGeneration]) { cancelled = YES; break; }
        for (NSUInteger x = minX; x < maxX && !result; x += step) {
            if (coarseCandidates >= coarseLimit) { truncated = YES; break; }
            if (coarsePixelCost > maxComparedPixels - MIN(comparedPixelBudget, maxComparedPixels)) { truncated = YES; break; }
            coarseCandidates += 1;
            comparedPixelBudget += coarsePixelCost;
            BOOL similarityCancelled = NO;
            CGFloat coarseSimilarity = AutoUIKitImageSimilarity(needle, haystack, x, y, sampleX, sampleY,
                                                                 sampleOffsetX, sampleOffsetY,
                                                                 coarseThreshold, shouldCancelSimilarity,
                                                                 &similarityCancelled);
            if (similarityCancelled) { cancelled = YES; break; }
            if (coarseSimilarity < coarseThreshold) continue;
            NSUInteger refineMinX = x >= step - 1 ? MAX(minX, x - (step - 1)) : minX;
            NSUInteger refineMinY = y >= step - 1 ? MAX(minY, y - (step - 1)) : minY;
            NSUInteger refineMaxX = MIN(maxX, x + step);
            NSUInteger refineMaxY = MIN(maxY, y + step);
            for (NSUInteger candidateY = refineMinY; candidateY < refineMaxY && !result; candidateY++) {
                if ([self operationWasCancelledSinceGeneration:operationGeneration]) { cancelled = YES; break; }
                for (NSUInteger candidateX = refineMinX; candidateX < refineMaxX && !result; candidateX++) {
                    if (verifiedCandidates >= verificationLimit) { truncated = YES; break; }
                    if (verificationPixelCost > maxComparedPixels - MIN(comparedPixelBudget, maxComparedPixels)) { truncated = YES; break; }
                    verifiedCandidates += 1;
                    comparedPixelBudget += verificationPixelCost;
                    BOOL similarityCancelled = NO;
                    CGFloat similarity = AutoUIKitImageSimilarity(needle, haystack, candidateX, candidateY,
                                                                   verifyStep, verifyStep, verifyOffsetX, verifyOffsetY, threshold,
                                                                   shouldCancelSimilarity, &similarityCancelled);
                    if (similarityCancelled) { cancelled = YES; break; }
                    if (similarity >= threshold) {
                        NSMutableDictionary *match = [AutoUIKitMatchResult(candidateX + haystackOriginX,
                                                                           candidateY + haystackOriginY,
                                                                           needle.width, needle.height, scale) mutableCopy];
                        match[@"similarity"] = @(similarity);
                        match[@"coarseCandidates"] = @(coarseCandidates);
                        match[@"verifiedCandidates"] = @(verifiedCandidates);
                        match[@"comparedPixelBudget"] = @(comparedPixelBudget);
                        match[@"truncated"] = @NO;
                        result = match;
                    }
                }
                if (truncated || cancelled) break;
            }
            if (truncated || cancelled) break;
        }
    }
    if (!result && step > requestedStep) truncated = YES;
    AutoUIKitPixelImageDestroy(&needle);
    AutoUIKitPixelImageDestroy(&haystack);
    if (cancelled || [self operationWasCancelledSinceGeneration:operationGeneration]) {
        if (error) *error = AutoUIKitCancelledError(@"Image search was cancelled.");
        return nil;
    }
    return result ?: @{ @"found": @NO, @"truncated": @(truncated),
                        @"coarseCandidates": @(coarseCandidates),
                        @"verifiedCandidates": @(verifiedCandidates),
                        @"comparedPixelBudget": @(comparedPixelBudget) };
    } @catch (NSException *exception) {
        if (error) *error = AutoUIKitError([NSString stringWithFormat:@"UIKit image search failed: %@", exception.reason ?: @"unknown error"]);
        return nil;
    } @finally {
        AutoUIKitPixelImageDestroy(&needle);
        AutoUIKitPixelImageDestroy(&haystack);
        [self.visualOperationLock unlock];
    }
    }
}

- (NSDictionary *)findColor:(id)color region:(NSDictionary *)region options:(NSDictionary *)options error:(NSError **)error {
    NSUInteger operationGeneration = [self currentOperationCancellationGeneration];
    @autoreleasepool {
    if (!AutoUIKitRegionIsValid(region)) {
        if (error) *error = AutoUIKitError(@"Color search region must use finite coordinates and paired positive dimensions.");
        return nil;
    }
    options = [options isKindOfClass:NSDictionary.class] ? options : @{};
    uint8_t red = 0, green = 0, blue = 0;
    if (!AutoUIKitParseColor(color, &red, &green, &blue)) {
        if (error) *error = AutoUIKitError(@"Color must be #RRGGBB, [r,g,b], or {r,g,b}.");
        return nil;
    }
    UIImage *image = [self threadSafeCapturedImageForOperationGeneration:operationGeneration error:error];
    CGImageRef screenCGImage = image.CGImage;
    if (!screenCGImage) {
        if (error && !*error) *error = AutoUIKitError(@"Unable to decode the screenshot image.");
        return nil;
    }
    AutoUIKitPixelImage pixels = {0};
    [self.visualOperationLock lock];
    @try {
    if ([self operationWasCancelledSinceGeneration:operationGeneration]) {
        if (error) *error = AutoUIKitCancelledError(@"Color search was cancelled.");
        return nil;
    }
    CGFloat scale = AutoUIKitSafeScale(image.scale);
    CGRect search = AutoUIKitPixelRegion([region isKindOfClass:NSDictionary.class] ? region : @{}, scale,
                                         CGImageGetWidth(screenCGImage), CGImageGetHeight(screenCGImage));
    if (CGRectIsNull(search) || CGRectIsEmpty(search)) return @{ @"found": @NO };
    NSUInteger pixelOriginX = 0, pixelOriginY = 0;
    pixels = AutoUIKitPixelImageMakeRegion(screenCGImage, search, &pixelOriginX, &pixelOriginY);
    if (!pixels.bytes) {
        if (error && !*error) *error = AutoUIKitError(@"Unable to allocate a screenshot pixel buffer.");
        return nil;
    }
    if ([self operationWasCancelledSinceGeneration:operationGeneration]) {
        AutoUIKitPixelImageDestroy(&pixels);
        if (error) *error = AutoUIKitCancelledError(@"Color search was cancelled.");
        return nil;
    }
    CGFloat tolerance = AutoUIKitDouble(options[@"tolerance"], 8);
    tolerance = MIN(255, MAX(0, tolerance));
    NSUInteger requestedStep = AutoUIKitUnsigned(options[@"step"], 0);
    if (requestedStep == 0) requestedStep = 1;
    requestedStep = MIN(requestedStep, (NSUInteger)1024);
    NSUInteger maxCandidates = AutoUIKitWorkBudget(options[@"maxCandidates"], AutoUIKitDefaultColorCandidates,
                                                   1000, AutoUIKitMaxColorCandidates);
    NSUInteger maxComparedPixels = AutoUIKitWorkBudget(options[@"maxComparedPixels"], AutoUIKitDefaultColorComparisons,
                                                       100000, AutoUIKitMaxColorComparisons);
    NSDictionary *result = nil;
    NSUInteger step = AutoUIKitAdaptedScanStep(pixels.width, pixels.height, requestedStep, maxCandidates);
    NSUInteger minX = 0, minY = 0, maxX = pixels.width, maxY = pixels.height;
    NSUInteger scannedCandidates = 0, comparedPixels = 0;
    BOOL truncated = NO, cancelled = NO;
    for (NSUInteger y = minY; y < maxY && !result && !truncated && !cancelled; y += step) {
        for (NSUInteger x = minX; x < maxX && !result; x += step) {
            if (scannedCandidates >= maxCandidates || comparedPixels >= maxComparedPixels) { truncated = YES; break; }
            scannedCandidates += 1;
            comparedPixels += 1;
            if ((comparedPixels & 0xFFF) == 0 && [self operationWasCancelledSinceGeneration:operationGeneration]) {
                cancelled = YES;
                break;
            }
            const uint8_t *pixel = pixels.bytes + y * pixels.bytesPerRow + x * 4;
            if (AutoUIKitPixelMatches(pixel, red, green, blue, tolerance)) {
                NSMutableDictionary *match = [AutoUIKitMatchResult(x + pixelOriginX, y + pixelOriginY, 1, 1, scale) mutableCopy];
                match[@"scannedCandidates"] = @(scannedCandidates);
                match[@"comparedPixels"] = @(comparedPixels);
                match[@"effectiveStep"] = @(step);
                match[@"truncated"] = @NO;
                result = match;
                break;
            }
        }
    }
    if (!result && step > requestedStep) truncated = YES;
    AutoUIKitPixelImageDestroy(&pixels);
    if (cancelled || [self operationWasCancelledSinceGeneration:operationGeneration]) {
        if (error) *error = AutoUIKitCancelledError(@"Color search was cancelled.");
        return nil;
    }
    return result ?: @{ @"found": @NO, @"truncated": @(truncated),
                        @"scannedCandidates": @(scannedCandidates),
                        @"comparedPixels": @(comparedPixels), @"effectiveStep": @(step) };
    } @catch (NSException *exception) {
        if (error) *error = AutoUIKitError([NSString stringWithFormat:@"UIKit color search failed: %@", exception.reason ?: @"unknown error"]);
        return nil;
    } @finally {
        AutoUIKitPixelImageDestroy(&pixels);
        [self.visualOperationLock unlock];
    }
    }
}

- (NSDictionary<NSString *,id> *)pixelColorAtX:(CGFloat)x y:(CGFloat)y error:(NSError **)error {
    NSUInteger operationGeneration = [self currentOperationCancellationGeneration];
    @autoreleasepool {
    if (!isfinite(x) || !isfinite(y)) {
        if (error) *error = AutoUIKitError(@"Pixel coordinates must be finite.");
        return nil;
    }
    UIImage *image = [self threadSafeCapturedImageForOperationGeneration:operationGeneration error:error];
    AutoUIKitPixelImage pixels = {0};
    [self.visualOperationLock lock];
    @try {
    if ([self operationWasCancelledSinceGeneration:operationGeneration]) {
        if (error) *error = AutoUIKitCancelledError(@"Pixel read was cancelled.");
        return nil;
    }
    CGFloat scale = AutoUIKitSafeScale(image.scale);
    double scaledX = floor((double)x * scale), scaledY = floor((double)y * scale);
    CGImageRef screenCGImage = image.CGImage;
    size_t imageWidth = screenCGImage ? CGImageGetWidth(screenCGImage) : 0;
    size_t imageHeight = screenCGImage ? CGImageGetHeight(screenCGImage) : 0;
    if (!isfinite(scaledX) || !isfinite(scaledY) || scaledX < 0 || scaledY < 0 ||
        scaledX >= (double)imageWidth || scaledY >= (double)imageHeight) {
        if (error) *error = AutoUIKitError(@"Pixel coordinates are outside the screenshot.");
        return nil;
    }
    pixels = AutoUIKitPixelImageMakeRegion(screenCGImage,
        CGRectMake(scaledX, scaledY, 1, 1), NULL, NULL);
    if (!pixels.bytes) {
        if (error && !*error) *error = AutoUIKitError(@"Unable to read the screenshot pixel.");
        return nil;
    }
    NSDictionary *result = AutoUIKitPixelColorResult(pixels.bytes, x, y);
    AutoUIKitPixelImageDestroy(&pixels);
    if ([self operationWasCancelledSinceGeneration:operationGeneration]) {
        if (error) *error = AutoUIKitCancelledError(@"Pixel read was cancelled.");
        return nil;
    }
    return result;
    } @catch (NSException *exception) {
        if (error) *error = AutoUIKitError([NSString stringWithFormat:@"UIKit pixel read failed: %@", exception.reason ?: @"unknown error"]);
        return nil;
    } @finally {
        AutoUIKitPixelImageDestroy(&pixels);
        [self.visualOperationLock unlock];
    }
    }
}

- (BOOL)compareColors:(NSArray<NSDictionary<NSString *,id> *> *)points options:(NSDictionary *)options error:(NSError **)error {
    NSUInteger operationGeneration = [self currentOperationCancellationGeneration];
    @autoreleasepool {
    options = [options isKindOfClass:NSDictionary.class] ? options : @{};
    if (![points isKindOfClass:NSArray.class] || points.count == 0) {
        if (error) *error = AutoUIKitError(@"compareColors requires at least one point.");
        return NO;
    }
    if (points.count > AutoUIKitMaxColorPoints) {
        if (error) *error = AutoUIKitError(@"compareColors accepts at most 4096 points.");
        return NO;
    }
    UIImage *image = [self threadSafeCapturedImageForOperationGeneration:operationGeneration error:error];
    AutoUIKitColorPoint *parsedPoints = NULL;
    AutoUIKitPixelImage pixels = {0};
    [self.visualOperationLock lock];
    @try {
    if ([self operationWasCancelledSinceGeneration:operationGeneration]) {
        if (error) *error = AutoUIKitCancelledError(@"Color comparison was cancelled.");
        return NO;
    }
    CGFloat scale = AutoUIKitSafeScale(image.scale);
    CGImageRef screenCGImage = image.CGImage;
    size_t imageWidth = screenCGImage ? CGImageGetWidth(screenCGImage) : 0;
    size_t imageHeight = screenCGImage ? CGImageGetHeight(screenCGImage) : 0;
    if (imageWidth == 0 || imageHeight == 0) {
        if (error && !*error) *error = AutoUIKitError(@"Unable to decode the screenshot image.");
        return NO;
    }
    CGFloat defaultTolerance = AutoUIKitDouble(options[@"tolerance"], 8);
    defaultTolerance = MIN(255, MAX(0, defaultTolerance));
    parsedPoints = calloc(points.count, sizeof(AutoUIKitColorPoint));
    if (!parsedPoints) {
        if (error) *error = AutoUIKitError(@"Unable to allocate color comparison points.");
        return NO;
    }
    NSUInteger minimumX = NSUIntegerMax, minimumY = NSUIntegerMax, maximumX = 0, maximumY = 0;
    NSUInteger pointIndex = 0;
    for (id object in points) {
        if ((pointIndex & 0xFF) == 0 && [self operationWasCancelledSinceGeneration:operationGeneration]) {
            free(parsedPoints); parsedPoints = NULL;
            if (error) *error = AutoUIKitCancelledError(@"Color comparison was cancelled.");
            return NO;
        }
        if (![object isKindOfClass:NSDictionary.class]) {
            free(parsedPoints); parsedPoints = NULL;
            if (error) *error = AutoUIKitError(@"Each compareColors point must be an object.");
            return NO;
        }
        NSDictionary *point = object;
        if (!AutoUIKitIsNumber(point[@"x"]) || !AutoUIKitIsNumber(point[@"y"])) {
            free(parsedPoints); parsedPoints = NULL;
            if (error) *error = AutoUIKitError(@"A compareColors point has invalid coordinates or color.");
            return NO;
        }
        double pointX = AutoUIKitDouble(point[@"x"], NAN);
        double pointY = AutoUIKitDouble(point[@"y"], NAN);
        if (!isfinite(pointX) || !isfinite(pointY)) {
            free(parsedPoints); parsedPoints = NULL;
            if (error) *error = AutoUIKitError(@"A compareColors point has invalid coordinates or color.");
            return NO;
        }
        double scaledX = floor(pointX * scale), scaledY = floor(pointY * scale);
        AutoUIKitColorPoint *parsedPoint = &parsedPoints[pointIndex];
        if (!isfinite(scaledX) || !isfinite(scaledY) || scaledX < 0 || scaledY < 0 ||
            scaledX >= (double)imageWidth || scaledY >= (double)imageHeight ||
            !AutoUIKitParseColor(point[@"color"], &parsedPoint->red, &parsedPoint->green, &parsedPoint->blue)) {
            free(parsedPoints); parsedPoints = NULL;
            if (error) *error = AutoUIKitError(@"A compareColors point has invalid coordinates or color.");
            return NO;
        }
        parsedPoint->x = (NSUInteger)scaledX;
        parsedPoint->y = (NSUInteger)scaledY;
        parsedPoint->tolerance = MIN(255, MAX(0, AutoUIKitDouble(point[@"tolerance"], defaultTolerance)));
        minimumX = MIN(minimumX, parsedPoint->x);
        minimumY = MIN(minimumY, parsedPoint->y);
        maximumX = MAX(maximumX, parsedPoint->x);
        maximumY = MAX(maximumY, parsedPoint->y);
        pointIndex += 1;
    }
    NSUInteger pixelOriginX = 0, pixelOriginY = 0;
    pixels = AutoUIKitPixelImageMakeRegion(screenCGImage,
        CGRectMake(minimumX, minimumY, maximumX - minimumX + 1, maximumY - minimumY + 1),
        &pixelOriginX, &pixelOriginY);
    if (!pixels.bytes) {
        free(parsedPoints); parsedPoints = NULL;
        if (error && !*error) *error = AutoUIKitError(@"Unable to allocate the color comparison region pixel buffer.");
        return NO;
    }
    BOOL matched = YES;
    for (NSUInteger index = 0; index < pointIndex; index++) {
        if ((index & 0xFF) == 0 && [self operationWasCancelledSinceGeneration:operationGeneration]) {
            AutoUIKitPixelImageDestroy(&pixels);
            free(parsedPoints); parsedPoints = NULL;
            if (error) *error = AutoUIKitCancelledError(@"Color comparison was cancelled.");
            return NO;
        }
        AutoUIKitColorPoint point = parsedPoints[index];
        const uint8_t *pixel = pixels.bytes + (point.y - pixelOriginY) * pixels.bytesPerRow +
                               (point.x - pixelOriginX) * 4;
        if (!AutoUIKitPixelMatches(pixel, point.red, point.green, point.blue, point.tolerance)) matched = NO;
        if (!matched) break;
    }
    AutoUIKitPixelImageDestroy(&pixels);
    free(parsedPoints); parsedPoints = NULL;
    if ([self operationWasCancelledSinceGeneration:operationGeneration]) {
        if (error) *error = AutoUIKitCancelledError(@"Color comparison was cancelled.");
        return NO;
    }
    return matched;
    } @catch (NSException *exception) {
        if (error) *error = AutoUIKitError([NSString stringWithFormat:@"UIKit color comparison failed: %@", exception.reason ?: @"unknown error"]);
        return NO;
    } @finally {
        AutoUIKitPixelImageDestroy(&pixels);
        free(parsedPoints);
        [self.visualOperationLock unlock];
    }
    }
}

- (NSDictionary<NSString *,id> *)findMultiColor:(id)color
                                          offsets:(NSArray *)offsets
                                           region:(NSDictionary *)region
                                            options:(NSDictionary *)options
                                              error:(NSError **)error {
    NSUInteger operationGeneration = [self currentOperationCancellationGeneration];
    @autoreleasepool {
    if (!AutoUIKitRegionIsValid(region)) {
        if (error) *error = AutoUIKitError(@"Multi-color search region must use finite coordinates and paired positive dimensions.");
        return nil;
    }
    options = [options isKindOfClass:NSDictionary.class] ? options : @{};
    uint8_t baseRed = 0, baseGreen = 0, baseBlue = 0;
    if (!AutoUIKitParseColor(color, &baseRed, &baseGreen, &baseBlue) || ![offsets isKindOfClass:NSArray.class]) {
        if (error) *error = AutoUIKitError(@"findMultiColor requires a base color and an offsets array.");
        return nil;
    }
    if (offsets.count > AutoUIKitMaxColorOffsets) {
        if (error) *error = AutoUIKitError(@"findMultiColor accepts at most 256 offsets.");
        return nil;
    }
    UIImage *image = [self threadSafeCapturedImageForOperationGeneration:operationGeneration error:error];
    if (!image.CGImage) {
        if (error && !*error) *error = AutoUIKitError(@"Unable to decode the screenshot image.");
        return nil;
    }
    AutoUIKitColorOffset *parsedOffsets = NULL;
    AutoUIKitPixelImage pixels = {0};
    [self.visualOperationLock lock];
    @try {
    if ([self operationWasCancelledSinceGeneration:operationGeneration]) {
        if (error) *error = AutoUIKitCancelledError(@"Multi-color search was cancelled.");
        return nil;
    }
    CGFloat scale = AutoUIKitSafeScale(image.scale);
    CGImageRef screenCGImage = image.CGImage;
    size_t imageWidth = CGImageGetWidth(screenCGImage), imageHeight = CGImageGetHeight(screenCGImage);
    parsedOffsets = offsets.count > 0 ? calloc(offsets.count, sizeof(AutoUIKitColorOffset)) : NULL;
    if (offsets.count > 0 && !parsedOffsets) {
        if (error) *error = AutoUIKitError(@"Unable to allocate multi-color offsets.");
        return nil;
    }
    BOOL invalidOffset = NO, impossibleOffset = NO;
    NSInteger minimumOffsetX = 0, minimumOffsetY = 0, maximumOffsetX = 0, maximumOffsetY = 0;
    for (NSUInteger index = 0; index < offsets.count; index++) {
        id offsetObject = offsets[index];
        CGFloat dx = NAN, dy = NAN, offsetTolerance = MIN(255, MAX(0, AutoUIKitDouble(options[@"tolerance"], 8)));
        id offsetColor = nil;
        if ([offsetObject isKindOfClass:NSArray.class] && [offsetObject count] >= 3) {
            dx = AutoUIKitDouble(offsetObject[0], NAN);
            dy = AutoUIKitDouble(offsetObject[1], NAN);
            offsetColor = offsetObject[2];
        } else if ([offsetObject isKindOfClass:NSDictionary.class]) {
            dx = AutoUIKitDouble(offsetObject[@"dx"] ?: offsetObject[@"x"], NAN);
            dy = AutoUIKitDouble(offsetObject[@"dy"] ?: offsetObject[@"y"], NAN);
            offsetColor = offsetObject[@"color"];
            if (offsetObject[@"tolerance"]) offsetTolerance = MIN(255, MAX(0, AutoUIKitDouble(offsetObject[@"tolerance"], offsetTolerance)));
        } else {
            invalidOffset = YES;
            break;
        }
        double pixelDX = round((double)dx * scale), pixelDY = round((double)dy * scale);
        if (!isfinite(dx) || !isfinite(dy) || !isfinite(pixelDX) || !isfinite(pixelDY) ||
            !AutoUIKitParseColor(offsetColor, &parsedOffsets[index].red, &parsedOffsets[index].green, &parsedOffsets[index].blue)) {
            invalidOffset = YES;
            break;
        }
        if (pixelDX < (double)NSIntegerMin || pixelDX > (double)NSIntegerMax ||
            pixelDY < (double)NSIntegerMin || pixelDY > (double)NSIntegerMax ||
            fabs(pixelDX) >= (double)imageWidth || fabs(pixelDY) >= (double)imageHeight) {
            impossibleOffset = YES;
            break;
        }
        parsedOffsets[index].dx = (NSInteger)pixelDX;
        parsedOffsets[index].dy = (NSInteger)pixelDY;
        parsedOffsets[index].tolerance = offsetTolerance;
        minimumOffsetX = MIN(minimumOffsetX, parsedOffsets[index].dx);
        minimumOffsetY = MIN(minimumOffsetY, parsedOffsets[index].dy);
        maximumOffsetX = MAX(maximumOffsetX, parsedOffsets[index].dx);
        maximumOffsetY = MAX(maximumOffsetY, parsedOffsets[index].dy);
    }
    if (invalidOffset || impossibleOffset) {
        free(parsedOffsets); parsedOffsets = NULL;
        if (invalidOffset && error) *error = AutoUIKitError(@"findMultiColor contains an invalid offset or color.");
        return invalidOffset ? nil : @{ @"found": @NO };
    }
    CGRect search = AutoUIKitPixelRegion([region isKindOfClass:NSDictionary.class] ? region : @{}, scale,
                                         imageWidth, imageHeight);
    if (CGRectIsNull(search) || CGRectIsEmpty(search)) {
        free(parsedOffsets); parsedOffsets = NULL;
        return @{ @"found": @NO };
    }
    CGFloat requiredMinX = CGRectGetMinX(search) + minimumOffsetX;
    CGFloat requiredMinY = CGRectGetMinY(search) + minimumOffsetY;
    CGFloat requiredMaxX = CGRectGetMaxX(search) + maximumOffsetX;
    CGFloat requiredMaxY = CGRectGetMaxY(search) + maximumOffsetY;
    CGRect requiredRegion = CGRectMake(requiredMinX, requiredMinY,
                                       requiredMaxX - requiredMinX, requiredMaxY - requiredMinY);
    NSUInteger pixelOriginX = 0, pixelOriginY = 0;
    pixels = AutoUIKitPixelImageMakeRegion(image.CGImage, requiredRegion,
                                                               &pixelOriginX, &pixelOriginY);
    if (!pixels.bytes) {
        free(parsedOffsets); parsedOffsets = NULL;
        if (error && !*error) *error = AutoUIKitError(@"Unable to allocate the multi-color region pixel buffer.");
        return nil;
    }
    if ([self operationWasCancelledSinceGeneration:operationGeneration]) {
        AutoUIKitPixelImageDestroy(&pixels);
        free(parsedOffsets); parsedOffsets = NULL;
        if (error) *error = AutoUIKitCancelledError(@"Multi-color search was cancelled.");
        return nil;
    }
    CGFloat tolerance = AutoUIKitDouble(options[@"tolerance"], 8);
    tolerance = MIN(255, MAX(0, tolerance));
    NSUInteger requestedStep = MIN((NSUInteger)1024, MAX(1, AutoUIKitUnsigned(options[@"step"], 1)));
    NSUInteger minX = MAX(0, (NSUInteger)floor(CGRectGetMinX(search)));
    NSUInteger minY = MAX(0, (NSUInteger)floor(CGRectGetMinY(search)));
    NSUInteger maxX = MIN(imageWidth, (NSUInteger)ceil(CGRectGetMaxX(search)));
    NSUInteger maxY = MIN(imageHeight, (NSUInteger)ceil(CGRectGetMaxY(search)));
    NSUInteger maxCandidates = AutoUIKitWorkBudget(options[@"maxCandidates"], AutoUIKitDefaultColorCandidates,
                                                   1000, AutoUIKitMaxColorCandidates);
    NSUInteger maxComparedPixels = AutoUIKitWorkBudget(options[@"maxComparedPixels"], AutoUIKitDefaultColorComparisons,
                                                       100000, AutoUIKitMaxColorComparisons);
    NSUInteger step = AutoUIKitAdaptedScanStep(maxX - minX, maxY - minY, requestedStep, maxCandidates);
    NSDictionary *result = nil;
    NSUInteger scannedCandidates = 0, comparedPixels = 0;
    BOOL truncated = NO, cancelled = NO;
    for (NSUInteger y = minY; y < maxY && !result && !truncated && !cancelled; y += step) {
        for (NSUInteger x = minX; x < maxX && !result; x += step) {
            if (scannedCandidates >= maxCandidates || comparedPixels >= maxComparedPixels) { truncated = YES; break; }
            scannedCandidates += 1;
            comparedPixels += 1;
            if ((comparedPixels & 0xFFF) == 0 && [self operationWasCancelledSinceGeneration:operationGeneration]) {
                cancelled = YES;
                break;
            }
            const uint8_t *basePixel = pixels.bytes + (y - pixelOriginY) * pixels.bytesPerRow +
                                       (x - pixelOriginX) * 4;
            if (!AutoUIKitPixelMatches(basePixel, baseRed, baseGreen, baseBlue, tolerance)) continue;
            BOOL allMatched = YES;
            for (NSUInteger index = 0; index < offsets.count; index++) {
                if (comparedPixels >= maxComparedPixels) { truncated = YES; allMatched = NO; break; }
                comparedPixels += 1;
                if ((comparedPixels & 0xFFF) == 0 && [self operationWasCancelledSinceGeneration:operationGeneration]) {
                    cancelled = YES; allMatched = NO; break;
                }
                AutoUIKitColorOffset offset = parsedOffsets[index];
                NSInteger targetX = (NSInteger)x + offset.dx;
                NSInteger targetY = (NSInteger)y + offset.dy;
                if (targetX < 0 || targetY < 0 || targetX >= (NSInteger)imageWidth || targetY >= (NSInteger)imageHeight) {
                    allMatched = NO;
                    break;
                }
                NSUInteger targetUX = (NSUInteger)targetX, targetUY = (NSUInteger)targetY;
                if (targetUX < pixelOriginX || targetUY < pixelOriginY ||
                    targetUX - pixelOriginX >= pixels.width || targetUY - pixelOriginY >= pixels.height) {
                    allMatched = NO;
                    break;
                }
                const uint8_t *pixel = pixels.bytes + (targetUY - pixelOriginY) * pixels.bytesPerRow +
                                       (targetUX - pixelOriginX) * 4;
                if (!AutoUIKitPixelMatches(pixel, offset.red, offset.green, offset.blue, offset.tolerance)) {
                    allMatched = NO;
                    break;
                }
            }
            if (allMatched) {
                NSMutableDictionary *match = [AutoUIKitMatchResult(x, y, 1, 1, scale) mutableCopy];
                match[@"scannedCandidates"] = @(scannedCandidates);
                match[@"comparedPixels"] = @(comparedPixels);
                match[@"effectiveStep"] = @(step);
                match[@"truncated"] = @NO;
                result = match;
            }
            if (truncated || cancelled) break;
        }
    }
    if (!result && step > requestedStep) truncated = YES;
    AutoUIKitPixelImageDestroy(&pixels);
    free(parsedOffsets); parsedOffsets = NULL;
    if (cancelled || [self operationWasCancelledSinceGeneration:operationGeneration]) {
        if (error) *error = AutoUIKitCancelledError(@"Multi-color search was cancelled.");
        return nil;
    }
    return result ?: @{ @"found": @NO, @"truncated": @(truncated),
                        @"scannedCandidates": @(scannedCandidates),
                        @"comparedPixels": @(comparedPixels), @"effectiveStep": @(step) };
    } @catch (NSException *exception) {
        if (error) *error = AutoUIKitError([NSString stringWithFormat:@"UIKit multi-color search failed: %@", exception.reason ?: @"unknown error"]);
        return nil;
    } @finally {
        AutoUIKitPixelImageDestroy(&pixels);
        free(parsedOffsets);
        [self.visualOperationLock unlock];
    }
    }
}

- (NSArray<NSDictionary<NSString *,id> *> *)ocrInRegion:(NSDictionary *)region error:(NSError **)error {
    NSUInteger operationGeneration = [self currentOperationCancellationGeneration];
    @autoreleasepool {
    if (!AutoUIKitRegionIsValid(region)) {
        if (error) *error = AutoUIKitError(@"OCR region must use finite coordinates and paired positive dimensions.");
        return nil;
    }
    region = [region isKindOfClass:NSDictionary.class] ? region : @{};
    UIImage *image = [self threadSafeCapturedImageForOperationGeneration:operationGeneration error:error];
    CGImageRef sourceImage = image.CGImage;
    if (!sourceImage) { if (error && !*error) *error = AutoUIKitError(@"Unable to create OCR image."); return nil; }
    CGImageRef croppedImage = NULL;
    VNRecognizeTextRequest *request = nil;
    [self.visualOperationLock lock];
    @try {
    @try {
    if ([self operationWasCancelledSinceGeneration:operationGeneration]) {
        if (error) *error = AutoUIKitCancelledError(@"OCR was cancelled.");
        return nil;
    }
    CGImageRef requestImage = sourceImage;
    CGFloat scale = AutoUIKitSafeScale(image.scale);
    CGRect cropPixels = CGRectMake(0, 0, CGImageGetWidth(sourceImage), CGImageGetHeight(sourceImage));
    BOOL hasCrop = AutoUIKitDouble(region[@"width"], 0) > 0 && AutoUIKitDouble(region[@"height"], 0) > 0;
    if (hasCrop) {
        CGRect crop = CGRectMake(AutoUIKitDouble(region[@"x"], 0) * scale,
                                 AutoUIKitDouble(region[@"y"], 0) * scale,
                                 AutoUIKitDouble(region[@"width"], 0) * scale,
                                 AutoUIKitDouble(region[@"height"], 0) * scale);
        CGRect imageBounds = CGRectMake(0, 0, CGImageGetWidth(sourceImage), CGImageGetHeight(sourceImage));
        crop = CGRectIntersection(crop, imageBounds);
        if (CGRectIsNull(crop) || CGRectIsEmpty(crop)) {
            if (error) *error = AutoUIKitError(@"OCR region does not intersect the screenshot.");
            return nil;
        }
        CGFloat cropMinX = floor(CGRectGetMinX(crop));
        CGFloat cropMinY = floor(CGRectGetMinY(crop));
        CGFloat cropMaxX = ceil(CGRectGetMaxX(crop));
        CGFloat cropMaxY = ceil(CGRectGetMaxY(crop));
        crop = CGRectMake(cropMinX, cropMinY, cropMaxX - cropMinX, cropMaxY - cropMinY);
        cropPixels = crop;
        croppedImage = CGImageCreateWithImageInRect(sourceImage, crop);
        if (!croppedImage) {
            if (error) *error = AutoUIKitError(@"Unable to crop the OCR image.");
            return nil;
        }
        requestImage = croppedImage;
    }
    size_t requestWidthPixels = CGImageGetWidth(requestImage);
    size_t requestHeightPixels = CGImageGetHeight(requestImage);
    BOOL imageSizeOverflow = requestWidthPixels > SIZE_MAX / 4 ||
        (requestWidthPixels > 0 && requestHeightPixels > SIZE_MAX / (requestWidthPixels * 4));
    BOOL imageTooLarge = imageSizeOverflow ||
        (requestWidthPixels > 0 && requestHeightPixels > 0 &&
         requestWidthPixels <= SIZE_MAX / 4 && requestHeightPixels <= SIZE_MAX / (requestWidthPixels * 4) &&
         requestWidthPixels * requestHeightPixels * 4 > AutoUIKitMaxPixelBufferBytes);
    if (requestWidthPixels == 0 || requestHeightPixels == 0 || imageTooLarge) {
        if (error) *error = AutoUIKitError(@"OCR image exceeds the 64 MB pixel limit.");
        return nil;
    }
    request = [VNRecognizeTextRequest new];
    NSString *mode = [region[@"mode"] isKindOfClass:NSString.class] ? [region[@"mode"] lowercaseString] : @"";
    BOOL accurate = [mode isEqualToString:@"fast"] ? NO :
                    ([mode isEqualToString:@"accurate"] ? YES :
                     (AutoUIKitIsNumber(region[@"accurate"]) ? AutoUIKitBool(region[@"accurate"], YES) : YES));
    request.recognitionLevel = accurate ? VNRequestTextRecognitionLevelAccurate : VNRequestTextRecognitionLevelFast;
    BOOL hasLanguageCorrection = region[@"languageCorrection"] != nil;
    request.usesLanguageCorrection = hasLanguageCorrection ? AutoUIKitBool(region[@"languageCorrection"], accurate) : accurate;
    if ([region[@"languages"] isKindOfClass:NSArray.class]) {
        NSMutableArray<NSString *> *languages = [NSMutableArray array];
        NSArray *requestedLanguages = region[@"languages"];
        NSUInteger examinedLanguages = MIN((NSUInteger)64, requestedLanguages.count);
        for (NSUInteger index = 0; index < examinedLanguages; index++) {
            id language = requestedLanguages[index];
            if ([language isKindOfClass:NSString.class] && [(NSString *)language length] > 0 && [(NSString *)language length] <= 32) [languages addObject:language];
            if (languages.count >= 8) break;
        }
        if (languages.count > 0) request.recognitionLanguages = languages;
    }
    if ([region[@"customWords"] isKindOfClass:NSArray.class]) {
        NSMutableArray<NSString *> *customWords = [NSMutableArray array];
        NSArray *requestedWords = region[@"customWords"];
        NSUInteger examinedWords = MIN((NSUInteger)1000, requestedWords.count);
        for (NSUInteger index = 0; index < examinedWords; index++) {
            id word = requestedWords[index];
            if ([word isKindOfClass:NSString.class] && [(NSString *)word length] > 0 && [(NSString *)word length] <= 256) [customWords addObject:word];
            if (customWords.count >= 100) break;
        }
        if (customWords.count > 0) request.customWords = customWords;
    }
    CGFloat minimumTextHeight = AutoUIKitDouble(region[@"minimumTextHeight"], 0);
    if (minimumTextHeight > 0) request.minimumTextHeight = MIN(1, minimumTextHeight);
    NSUInteger maxResults = AutoUIKitUnsigned(region[@"maxResults"], 0);
    if (maxResults == 0) maxResults = 1000;
    maxResults = MIN((NSUInteger)1000, maxResults);
    NSError *visionError = nil;
    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:requestImage options:@{}];
    BOOL cancelledBeforeVision = NO;
    @synchronized (self) {
        cancelledBeforeVision = operationGeneration != self.operationCancellationGeneration;
        if (!cancelledBeforeVision) [self.activeVisionRequests addObject:request];
    }
    if (cancelledBeforeVision) {
        if (error) *error = AutoUIKitCancelledError(@"OCR was cancelled.");
        return nil;
    }
    BOOL ok = NO;
    @try {
        ok = [handler performRequests:@[request] error:&visionError];
    } @catch (NSException *exception) {
        visionError = AutoUIKitError([NSString stringWithFormat:@"Vision OCR failed: %@", exception.reason ?: @"unknown error"]);
    }
    @synchronized (self) { [self.activeVisionRequests removeObject:request]; }
    NSMutableArray *items = [NSMutableArray array];
    if (ok) {
        NSUInteger observationIndex = 0;
        NSUInteger maximumExaminedObservations = MIN((NSUInteger)10000, maxResults * 10 + 100);
        for (VNRecognizedTextObservation *observation in request.results) {
            if (observationIndex >= maximumExaminedObservations) break;
            if ((observationIndex++ & 0x1F) == 0 &&
                [self operationWasCancelledSinceGeneration:operationGeneration]) break;
            @autoreleasepool {
            VNRecognizedText *candidate = [observation topCandidates:1].firstObject;
            if (!candidate) continue;
            CGRect box = observation.boundingBox;
            if (!AutoUIKitRectIsFinite(box)) continue;
            box = CGRectIntersection(box, CGRectMake(0, 0, 1, 1));
            if (CGRectIsNull(box) || CGRectIsEmpty(box)) continue;
            CGFloat requestWidth = CGImageGetWidth(requestImage);
            CGFloat requestHeight = CGImageGetHeight(requestImage);
            CGRect pointBounds = CGRectMake((cropPixels.origin.x + box.origin.x * requestWidth) / scale,
                                            (cropPixels.origin.y + (1.0 - CGRectGetMaxY(box)) * requestHeight) / scale,
                                            box.size.width * requestWidth / scale,
                                            box.size.height * requestHeight / scale);
            if (!AutoUIKitRectIsFinite(pointBounds)) continue;
            BOOL textTruncated = NO;
            NSString *recognizedText = AutoUIKitDescriptorString(candidate.string, &textTruncated) ?: @"";
            CGFloat confidence = isfinite(candidate.confidence) ? MIN(1, MAX(0, candidate.confidence)) : 0;
            [items addObject:@{ @"text": recognizedText,
                                @"textTruncated": @(textTruncated),
                                @"confidence": @(confidence),
                                @"bounds": @{ @"x": @(pointBounds.origin.x), @"y": @(pointBounds.origin.y),
                                              @"width": @(pointBounds.size.width), @"height": @(pointBounds.size.height),
                                              @"centerX": @(CGRectGetMidX(pointBounds)), @"centerY": @(CGRectGetMidY(pointBounds)) },
                                @"normalizedBounds": @{ @"x": @(box.origin.x), @"y": @(box.origin.y),
                                                         @"width": @(box.size.width), @"height": @(box.size.height) } }];
            if (items.count >= maxResults) break;
            }
        }
        if (items.count > 1) [items sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
            NSDictionary *a = left[@"bounds"];
            NSDictionary *b = right[@"bounds"];
            CGFloat yDifference = [a[@"y"] doubleValue] - [b[@"y"] doubleValue];
            if (fabs(yDifference) > 2) return yDifference < 0 ? NSOrderedAscending : NSOrderedDescending;
            CGFloat xDifference = [a[@"x"] doubleValue] - [b[@"x"] doubleValue];
            return xDifference < 0 ? NSOrderedAscending : (xDifference > 0 ? NSOrderedDescending : NSOrderedSame);
        }];
    }
    if ([self operationWasCancelledSinceGeneration:operationGeneration]) {
        if (error) *error = AutoUIKitCancelledError(@"OCR was cancelled.");
        return nil;
    }
    if (!ok) { if (error) *error = AutoUIKitError(visionError.localizedDescription ?: @"OCR failed."); return nil; }
    return items;
    } @catch (NSException *exception) {
        if (error) *error = AutoUIKitError([NSString stringWithFormat:@"Vision OCR failed: %@", exception.reason ?: @"unknown error"]);
        return nil;
    }
    } @finally {
        if (request) {
            @synchronized (self) { [self.activeVisionRequests removeObject:request]; }
        }
        if (croppedImage) CGImageRelease(croppedImage);
        [self.visualOperationLock unlock];
    }
    }
}

- (NSDictionary<NSString *,id> *)deviceInfo {
    if (!NSThread.isMainThread) {
        __block NSDictionary<NSString *, id> *info = nil;
        dispatch_sync(dispatch_get_main_queue(), ^{ info = [self deviceInfo]; });
        return info ?: @{};
    }
    UIWindow *window = AutoUIKitActiveWindow();
    UIScreen *screen = window.screen ?: UIScreen.mainScreen;
    CGRect screenBounds = AutoUIKitRectIsFinite(screen.bounds) ? screen.bounds : CGRectZero;
    return @{ @"adapter": @"UIKit",
              @"screenWidth": @(screenBounds.size.width),
              @"screenHeight": @(screenBounds.size.height),
              @"screenScale": @(AutoUIKitSafeScale(screen.scale)),
              @"screenshotCacheDuration": @(self.screenshotCacheDuration) };
}

- (NSDictionary<NSString *,id> *)capabilities {
    return @{ @"scope": @"hostApp",
              @"requiresMainThread": @YES,
              @"handlesVisualOperationThreads": @YES,
              @"crossApp": @NO,
              @"realTouchInjection": @NO,
              @"click": @YES,
              @"coordinateActivation": @YES,
              @"doubleActivation": @YES,
              @"longClick": @NO,
              @"swipeScroll": @YES,
              @"nodes": @YES,
              @"stableNodeHandles": @YES,
              @"screenshot": @YES,
              @"findColor": @YES,
              @"multiColor": @YES,
              @"findImage": @YES,
              @"opencv": @NO,
              @"ocr": @YES };
}

@end
