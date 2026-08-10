#import "include/AutoBuiltinAdapter.h"
#import "include/AutoSDKError.h"
#import <UIKit/UIKit.h>
#import <Vision/Vision.h>
#import <ImageIO/ImageIO.h>
#include <dlfcn.h>
#include <math.h>
#include <mach/mach_time.h>
#include <objc/message.h>
#include <objc/runtime.h>

#pragma mark - Constants and error helpers

static const NSUInteger AutoBuiltinDefaultMaxNodes = 5000;
static const NSUInteger AutoBuiltinDefaultMaxDepth = 30;
static const NSUInteger AutoBuiltinMaxNodeStringLength = 4096;
static const NSUInteger AutoBuiltinMaxColorPoints = 4096;
static const NSUInteger AutoBuiltinMaxColorCandidates = 2000000;
static const NSUInteger AutoBuiltinMaxOCRItems = 500;
static const NSUInteger AutoBuiltinMaxTemplateBytes = 8 * 1024 * 1024;
static const NSUInteger AutoBuiltinDefaultImageCandidates = 64;
static const NSUInteger AutoBuiltinMaxImageCandidates = 512;
static const NSUInteger AutoBuiltinMaxImageComparisons = 60000000;
static NSString * const AutoBuiltinHandlePrefix = @"axb:";

static NSString * const AutoBuiltinFrameworkAccessibility = @"/System/Library/Frameworks/Accessibility.framework/Accessibility";
static NSString * const AutoBuiltinFrameworkSpringBoardServices = @"/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices";
static NSString * const AutoBuiltinFrameworkBackBoardServices = @"/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices";
static NSString * const AutoBuiltinFrameworkIOKit = @"/System/Library/Frameworks/IOKit.framework/IOKit";
static NSString * const AutoBuiltinFrameworkUIKit = @"/System/Library/Frameworks/UIKit.framework/UIKit";

static NSError *AutoBuiltinError(AutoSDKErrorCode code, NSString *message) {
    return [NSError errorWithDomain:AutoSDKErrorDomain code:code
                           userInfo:@{ NSLocalizedDescriptionKey: message ?: @"Built-in adapter operation failed." }];
}

static NSError *AutoBuiltinUnavailable(NSString *what) {
    return AutoBuiltinError(AutoSDKErrorAutomationUnavailable,
        [NSString stringWithFormat:@"Built-in adapter: %@ is unavailable in this signing/entitlement context. "
                                     @"System-wide automation requires a TrollStore/enterprise-signed host app.", what]);
}

#pragma mark - Runtime-resolved private symbols

static void *AutoBuiltinFrameworkHandle(NSString *path) {
    static NSMutableDictionary<NSString *, NSValue *> *handles = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ handles = [NSMutableDictionary new]; });
    @synchronized (handles) {
        NSValue *cached = handles[path];
        if (cached) return cached.pointerValue;
        void *handle = dlopen(path.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
        handles[path] = [NSValue valueWithPointer:handle];
        return handle;
    }
}

static void *AutoBuiltinSymbol(NSString *frameworkPath, const char *name) {
    void *handle = AutoBuiltinFrameworkHandle(frameworkPath);
    if (!handle) return NULL;
    return dlsym(handle, name);
}

#pragma mark - IOHIDEvent touch injection

typedef struct { UInt32 hi; UInt32 lo; } AutoAbsoluteTime;

static AutoAbsoluteTime AutoAbsoluteTimeNow(void) {
    uint64_t now = mach_absolute_time();
    AutoAbsoluteTime t;
    t.hi = (UInt32)(now >> 32);
    t.lo = (UInt32)(now & 0xFFFFFFFFULL);
    return t;
}

typedef void *AutoHIDClientRef;
typedef void *AutoHIDEventRef;

typedef AutoHIDClientRef (*AutoHIDClientCreateFn)(CFAllocatorRef allocator);
typedef AutoHIDEventRef (*AutoHIDCreateDigitizerEventFn)(CFAllocatorRef allocator,
                                                         AutoAbsoluteTime timeStamp,
                                                         uint32_t transducerType,
                                                         uint32_t index,
                                                         uint32_t identity,
                                                         uint32_t eventMask,
                                                         uint32_t buttonMask,
                                                         Float32 x, Float32 y, Float32 z,
                                                         Float32 tipPressure, Float32 barrelPressure,
                                                         Boolean range, Boolean touch,
                                                         uint32_t options);
typedef void (*AutoHIDAppendEventFn)(AutoHIDEventRef parent, AutoHIDEventRef child);
typedef void (*AutoHIDSetIntegerValueFn)(AutoHIDEventRef event, uint32_t field, int32_t value);
typedef bool (*AutoHIDDispatchEventFn)(AutoHIDClientRef client, AutoHIDEventRef event);

/* Values from the public IOHIDEvent digitizer definitions. */
enum {
    AutoDigitizerTransducerFinger = 2,      /* kIOHIDDigitizerTransducerTypeHandFinger */
    AutoDigitizerEventDown        = 0x01,   /* kIOHIDDigitizerEventDown */
    AutoDigitizerEventDrag        = 0x02,   /* kIOHIDDigitizerEventDrag */
    AutoDigitizerEventTouch       = 0x04,   /* kIOHIDDigitizerEventTouch */
    AutoDigitizerEventPosition    = 0x08,   /* kIOHIDDigitizerEventPosition */
    AutoDigitizerEventFromIndex   = 0x20,   /* kIOHIDDigitizerEventFromIndex */
    AutoDigitizerEventIdentity    = 0x40    /* kIOHIDDigitizerEventIdentity */
};

@interface AutoBuiltinTouchEngine : NSObject {
    NSLock *_lock;
    AutoHIDClientRef _client;
    AutoHIDClientCreateFn _clientCreate;
    AutoHIDCreateDigitizerEventFn _createDigitizer;
    AutoHIDAppendEventFn _appendEvent;
    AutoHIDSetIntegerValueFn _setIntegerValue;
    AutoHIDDispatchEventFn _dispatchEvent;
    BOOL _resolved;
    BOOL _ready;
}
+ (instancetype)sharedEngine;
- (BOOL)isReady;
- (BOOL)dispatchFrameAtIndex:(uint32_t)index
                    identity:(uint32_t)identity
                           x:(CGFloat)x
                           y:(CGFloat)y
                    pressure:(CGFloat)pressure
                       phase:(NSInteger)phase; /* 0 down, 1 move, 2 up */
@end

@implementation AutoBuiltinTouchEngine

+ (instancetype)sharedEngine {
    static AutoBuiltinTouchEngine *engine = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ engine = [AutoBuiltinTouchEngine new]; });
    return engine;
}

- (instancetype)init {
    if ((self = [super init])) { _lock = [NSLock new]; }
    return self;
}

- (BOOL)isReady {
    [_lock lock];
    if (!_resolved) {
        _resolved = YES;
        _clientCreate = (AutoHIDClientCreateFn)AutoBuiltinSymbol(AutoBuiltinFrameworkIOKit, "IOHIDEventSystemClientCreate");
        _createDigitizer = (AutoHIDCreateDigitizerEventFn)AutoBuiltinSymbol(AutoBuiltinFrameworkIOKit, "IOHIDEventCreateDigitizerEvent");
        _appendEvent = (AutoHIDAppendEventFn)AutoBuiltinSymbol(AutoBuiltinFrameworkIOKit, "IOHIDEventAppendEvent");
        _setIntegerValue = (AutoHIDSetIntegerValueFn)AutoBuiltinSymbol(AutoBuiltinFrameworkIOKit, "IOHIDEventSetIntegerValue");
        _dispatchEvent = (AutoHIDDispatchEventFn)AutoBuiltinSymbol(AutoBuiltinFrameworkIOKit, "IOHIDEventSystemClientDispatchEvent");
        if (_clientCreate && _createDigitizer && _dispatchEvent) {
            _client = _clientCreate(kCFAllocatorDefault);
            _ready = (_client != NULL);
        }
    }
    BOOL ready = _ready;
    [_lock unlock];
    return ready;
}

- (BOOL)dispatchFrameAtIndex:(uint32_t)index
                    identity:(uint32_t)identity
                           x:(CGFloat)x
                           y:(CGFloat)y
                    pressure:(CGFloat)pressure
                       phase:(NSInteger)phase {
    if (![self isReady]) return NO;
    CGFloat scale = UIScreen.mainScreen.scale > 0 ? UIScreen.mainScreen.scale : 1;
    Float32 pixelX = (Float32)(x * scale);
    Float32 pixelY = (Float32)(y * scale);
    uint32_t eventMask;
    Boolean range;
    Boolean touch;
    Float32 tip = (Float32)pressure;
    if (phase == 0) {
        eventMask = AutoDigitizerEventDown | AutoDigitizerEventTouch | AutoDigitizerEventPosition |
                    AutoDigitizerEventFromIndex | AutoDigitizerEventIdentity;
        range = true; touch = true; if (tip <= 0) tip = 1.0f;
    } else if (phase == 1) {
        eventMask = AutoDigitizerEventDrag | AutoDigitizerEventTouch | AutoDigitizerEventPosition |
                    AutoDigitizerEventFromIndex | AutoDigitizerEventIdentity;
        range = true; touch = true; if (tip <= 0) tip = 1.0f;
    } else {
        eventMask = AutoDigitizerEventFromIndex | AutoDigitizerEventIdentity;
        range = false; touch = false; tip = 0.0f;
    }
    [_lock lock];
    BOOL ok = NO;
    if (_client && _createDigitizer) {
        AutoHIDEventRef event = _createDigitizer(kCFAllocatorDefault,
                                                 AutoAbsoluteTimeNow(),
                                                 AutoDigitizerTransducerFinger,
                                                 index, identity, eventMask, 0,
                                                 pixelX, pixelY, 0.0f, tip, 0.0f,
                                                 range, touch, 0);
        if (event) {
            ok = _dispatchEvent(_client, event);
            CFRelease((CFTypeRef)event);
        }
    }
    [_lock unlock];
    return ok;
}

@end

#pragma mark - Accessibility element engine

typedef const void *AutoAXElementRef;
typedef int32_t AutoAXError;
enum { AutoAXErrorSuccess = 0 };

typedef AutoAXElementRef (*AutoAXCreateSystemWideFn)(void);
typedef AutoAXError (*AutoAXCopyAttributeValueFn)(AutoAXElementRef element, CFStringRef attribute, CFTypeRef *value);
typedef AutoAXError (*AutoAXSetAttributeValueFn)(AutoAXElementRef element, CFStringRef attribute, CFTypeRef value);
typedef AutoAXError (*AutoAXPerformActionFn)(AutoAXElementRef element, CFStringRef action);

static CFStringRef const AutoAXAttributeChildren = CFSTR("AXChildren");
static CFStringRef const AutoAXAttributeLabel = CFSTR("AXLabel");
static CFStringRef const AutoAXAttributeValue = CFSTR("AXValue");
static CFStringRef const AutoAXAttributeRole = CFSTR("AXRole");
static CFStringRef const AutoAXAttributeIdentifier = CFSTR("AXIdentifier");
static CFStringRef const AutoAXAttributeFrame = CFSTR("AXFrame");
static CFStringRef const AutoAXAttributeEnabled = CFSTR("AXEnabled");
static CFStringRef const AutoAXAttributeSelected = CFSTR("AXSelected");
static CFStringRef const AutoAXAttributeFocused = CFSTR("AXFocused");
static CFStringRef const AutoAXActionPress = CFSTR("AXPress");
static CFStringRef const AutoAXActionScrollToVisible = CFSTR("AXScrollToVisible");

@interface AutoBuiltinAccessibilityEngine : NSObject {
    NSLock *_lock;
    AutoAXCreateSystemWideFn _createSystemWide;
    AutoAXCopyAttributeValueFn _copyAttributeValue;
    AutoAXSetAttributeValueFn _setAttributeValue;
    AutoAXPerformActionFn _performAction;
    BOOL _resolved;
}
+ (instancetype)sharedEngine;
- (BOOL)isAvailable;
- (nullable AutoAXElementRef)systemWideRoot CF_RETURNS_RETAINED;
- (nullable CFTypeRef)copyAttribute:(CFStringRef)attribute ofElement:(AutoAXElementRef)element CF_RETURNS_RETAINED;
- (BOOL)setValue:(CFTypeRef)value forAttribute:(CFStringRef)attribute ofElement:(AutoAXElementRef)element;
- (BOOL)performAction:(CFStringRef)action onElement:(AutoAXElementRef)element;
- (nullable NSArray *)copyChildrenOfElement:(AutoAXElementRef)element CF_RETURNS_RETAINED;
@end

@implementation AutoBuiltinAccessibilityEngine

+ (instancetype)sharedEngine {
    static AutoBuiltinAccessibilityEngine *engine = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ engine = [AutoBuiltinAccessibilityEngine new]; });
    return engine;
}

- (instancetype)init {
    if ((self = [super init])) { _lock = [NSLock new]; }
    return self;
}

- (BOOL)isAvailable {
    [_lock lock];
    if (!_resolved) {
        _resolved = YES;
        _createSystemWide = (AutoAXCreateSystemWideFn)AutoBuiltinSymbol(AutoBuiltinFrameworkAccessibility, "AXUIElementCreateSystemWide");
        _copyAttributeValue = (AutoAXCopyAttributeValueFn)AutoBuiltinSymbol(AutoBuiltinFrameworkAccessibility, "AXUIElementCopyAttributeValue");
        _setAttributeValue = (AutoAXSetAttributeValueFn)AutoBuiltinSymbol(AutoBuiltinFrameworkAccessibility, "AXUIElementSetAttributeValue");
        _performAction = (AutoAXPerformActionFn)AutoBuiltinSymbol(AutoBuiltinFrameworkAccessibility, "AXUIElementPerformAction");
    }
    BOOL available = (_createSystemWide && _copyAttributeValue);
    [_lock unlock];
    return available;
}

- (AutoAXElementRef)systemWideRoot {
    if (![self isAvailable]) return NULL;
    return _createSystemWide();
}

- (CFTypeRef)copyAttribute:(CFStringRef)attribute ofElement:(AutoAXElementRef)element {
    if (!element || !_copyAttributeValue) return NULL;
    CFTypeRef value = NULL;
    if (_copyAttributeValue(element, attribute, &value) != AutoAXErrorSuccess) return NULL;
    return value;
}

- (BOOL)setValue:(CFTypeRef)value forAttribute:(CFStringRef)attribute ofElement:(AutoAXElementRef)element {
    if (!element || !_setAttributeValue || !value) return NO;
    return _setAttributeValue(element, attribute, value) == AutoAXErrorSuccess;
}

- (BOOL)performAction:(CFStringRef)action onElement:(AutoAXElementRef)element {
    if (!element || !_performAction) return NO;
    return _performAction(element, action) == AutoAXErrorSuccess;
}

- (NSArray *)copyChildrenOfElement:(AutoAXElementRef)element {
    CFTypeRef children = [self copyAttribute:AutoAXAttributeChildren ofElement:element];
    if (!children) return nil;
    NSArray *result = nil;
    if (CFGetTypeID(children) == CFArrayGetTypeID()) {
        result = CFBridgingRelease(children);
    } else {
        CFRelease(children);
    }
    return result;
}

@end

#pragma mark - SpringBoard / app control symbols

typedef CFStringRef (*AutoSBSCopyFrontmostFn)(void);
typedef void (*AutoSBSLockDeviceFn)(void);
typedef Boolean (*AutoSBSLaunchWithBundleIdFn)(CFStringRef bundleId);
typedef Boolean (*AutoSBSOpenSensitiveURLOptionsFn)(CFURLRef url, Boolean unlock);
typedef void (*AutoBKSTerminateApplicationFn)(CFStringRef bundleId, Boolean unknown);

static Boolean AutoBuiltinLaunchBundleId(NSString *bundleId) {
    if (bundleId.length == 0) return false;
    AutoSBSLaunchWithBundleIdFn launch =
        (AutoSBSLaunchWithBundleIdFn)AutoBuiltinSymbol(AutoBuiltinFrameworkSpringBoardServices, "SBSLaunchApplicationWithIdentifier");
    if (launch) {
        return launch((__bridge CFStringRef)bundleId);
    }
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    if (workspaceClass && [workspaceClass respondsToSelector:@selector(defaultWorkspace)]) {
        id workspace = [workspaceClass performSelector:@selector(defaultWorkspace)];
        SEL openSelector = NSSelectorFromString(@"openApplicationWithBundleID:");
        if ([workspace respondsToSelector:openSelector]) {
            [workspace performSelector:openSelector withObject:bundleId];
            return true;
        }
    }
    return false;
}

static BOOL AutoBuiltinTerminateBundleId(NSString *bundleId) {
    if (bundleId.length == 0) return NO;
    AutoBKSTerminateApplicationFn terminate =
        (AutoBKSTerminateApplicationFn)AutoBuiltinSymbol(AutoBuiltinFrameworkBackBoardServices, "BKSTerminateApplication");
    if (terminate) {
        terminate((__bridge CFStringRef)bundleId, true);
        return YES;
    }
    return NO;
}

static NSString *AutoBuiltinFrontmostBundleId(void) {
    AutoSBSCopyFrontmostFn frontmost =
        (AutoSBSCopyFrontmostFn)AutoBuiltinSymbol(AutoBuiltinFrameworkSpringBoardServices, "SBSCopyFrontmostApplicationDisplayIdentifier");
    if (!frontmost) return nil;
    CFStringRef identifier = frontmost();
    if (!identifier) return nil;
    return (NSString *)CFBridgingRelease(identifier);
}

static NSArray<NSString *> *AutoBuiltinInstalledBundleIds(void) {
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    if (!workspaceClass || ![workspaceClass respondsToSelector:@selector(defaultWorkspace)]) return nil;
    id workspace = [workspaceClass performSelector:@selector(defaultWorkspace)];
    SEL listSelector = NSSelectorFromString(@"allInstalledApplications");
    if (![workspace respondsToSelector:listSelector]) return nil;
    id proxies = [workspace performSelector:listSelector];
    if (![proxies isKindOfClass:NSArray.class]) return nil;
    NSMutableArray<NSString *> *bundleIds = [NSMutableArray array];
    SEL identifierSelector = NSSelectorFromString(@"applicationIdentifier");
    for (id proxy in (NSArray *)proxies) {
        if ([proxy respondsToSelector:identifierSelector]) {
            id identifier = [proxy performSelector:identifierSelector];
            if ([identifier isKindOfClass:NSString.class] && [identifier length] > 0) {
                [bundleIds addObject:identifier];
            }
        }
    }
    return bundleIds;
}

#pragma mark - Bitmap helpers

typedef struct {
    uint8_t *bytes;
    size_t width;
    size_t height;
    size_t bytesPerRow;
} AutoBuiltinBitmap;

static void AutoBuiltinBitmapFree(AutoBuiltinBitmap *bitmap) {
    if (bitmap->bytes) free(bitmap->bytes);
    bitmap->bytes = NULL;
}

static BOOL AutoBuiltinBitmapFromPNGData(NSData *data, AutoBuiltinBitmap *bitmap) {
    memset(bitmap, 0, sizeof(AutoBuiltinBitmap));
    CGImageSourceRef source = CGImageSourceCreateWithData((CFDataRef)data, NULL);
    if (!source) return NO;
    CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
    CFRelease(source);
    if (!image) return NO;
    size_t width = CGImageGetWidth(image);
    size_t height = CGImageGetHeight(image);
    if (width == 0 || height == 0 || width > 16384 || height > 16384) {
        CGImageRelease(image);
        return NO;
    }
    size_t bytesPerRow = width * 4;
    uint8_t *bytes = (uint8_t *)calloc(bytesPerRow * height, 1);
    if (!bytes) {
        CGImageRelease(image);
        return NO;
    }
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(bytes, width, height, 8, bytesPerRow, colorSpace,
                                                 kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(colorSpace);
    if (!context) {
        free(bytes);
        CGImageRelease(image);
        return NO;
    }
    CGContextDrawImage(context, CGRectMake(0, 0, (CGFloat)width, (CGFloat)height), image);
    CGContextRelease(context);
    CGImageRelease(image);
    bitmap->bytes = bytes;
    bitmap->width = width;
    bitmap->height = height;
    bitmap->bytesPerRow = bytesPerRow;
    return YES;
}

static NSDictionary *AutoBuiltinPixelColorResult(const uint8_t *pixel, CGFloat x, CGFloat y) {
    CGFloat alpha = pixel[3] > 0 ? (CGFloat)pixel[3] / 255.0 : 1.0;
    uint8_t red = (uint8_t)MIN(255, (int)round(pixel[0] / alpha));
    uint8_t green = (uint8_t)MIN(255, (int)round(pixel[1] / alpha));
    uint8_t blue = (uint8_t)MIN(255, (int)round(pixel[2] / alpha));
    NSString *hex = [NSString stringWithFormat:@"#%02X%02X%02X", red, green, blue];
    return @{ @"x": @(x), @"y": @(y), @"r": @(red), @"g": @(green), @"b": @(blue),
              @"a": @(pixel[3]), @"hex": hex };
}

static BOOL AutoBuiltinParseColor(id color, uint8_t *red, uint8_t *green, uint8_t *blue) {
    NSString *text = nil;
    if ([color isKindOfClass:NSString.class]) {
        text = [(NSString *)color stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if ([text hasPrefix:@"#"]) text = [text substringFromIndex:1];
        if ([text hasPrefix:@"0x"] || [text hasPrefix:@"0X"]) text = [text substringFromIndex:2];
        unsigned int value = 0;
        NSScanner *scanner = [NSScanner scannerWithString:text];
        if (![scanner scanHexInt:&value]) return NO;
        if (text.length == 3) {
            *red = (uint8_t)(((value >> 8) & 0xF) * 17);
            *green = (uint8_t)(((value >> 4) & 0xF) * 17);
            *blue = (uint8_t)((value & 0xF) * 17);
        } else {
            *red = (uint8_t)((value >> 16) & 0xFF);
            *green = (uint8_t)((value >> 8) & 0xFF);
            *blue = (uint8_t)(value & 0xFF);
        }
        return YES;
    }
    if ([color isKindOfClass:NSNumber.class]) {
        unsigned int value = [color unsignedIntValue];
        *red = (uint8_t)((value >> 16) & 0xFF);
        *green = (uint8_t)((value >> 8) & 0xFF);
        *blue = (uint8_t)(value & 0xFF);
        return YES;
    }
    return NO;
}

static double AutoBuiltinDouble(id value, double fallback) {
    return [value isKindOfClass:NSNumber.class] ? [value doubleValue] : fallback;
}

static NSString *AutoBuiltinStringOrNil(id value) {
    return [value isKindOfClass:NSString.class] ? value : nil;
}

#pragma mark - Adapter

@interface AutoBuiltinAdapter ()
@property (atomic, assign) NSUInteger cancellationGeneration;
@property (atomic, strong, nullable) NSData *cachedScreenshot;
@property (atomic, strong, nullable) NSDate *cachedScreenshotAt;
@property (atomic, assign) CGFloat cachedScreenshotScale;
@end

@implementation AutoBuiltinAdapter

@synthesize maxSnapshotNodes = _maxSnapshotNodes;
@synthesize maxSnapshotDepth = _maxSnapshotDepth;
@synthesize screenshotCacheDuration = _screenshotCacheDuration;

- (instancetype)init {
    if ((self = [super init])) {
        _maxSnapshotNodes = AutoBuiltinDefaultMaxNodes;
        _maxSnapshotDepth = AutoBuiltinDefaultMaxDepth;
        _screenshotCacheDuration = 0;
    }
    return self;
}

- (void)cancelCurrentOperations {
    self.cancellationGeneration += 1;
}

- (BOOL)operationCancelledSince:(NSUInteger)generation {
    return self.cancellationGeneration != generation;
}

#pragma mark Accessibility walk and descriptor construction

- (nullable NSDictionary *)boundsFromAXFrame:(CFTypeRef)frameValue {
    if (!frameValue) return nil;
    CGRect frame = CGRectZero;
    if (CFGetTypeID(frameValue) == CFArrayGetTypeID()) {
        NSArray *components = (__bridge NSArray *)frameValue;
        if (components.count >= 4) {
            frame = CGRectMake([components[0] doubleValue], [components[1] doubleValue],
                               [components[2] doubleValue], [components[3] doubleValue]);
        } else {
            return nil;
        }
    } else {
        /* AXValue holding a CGRect; resolve AXValueGetValue from Accessibility at runtime. */
        typedef bool (*AutoAXValueGetValueFn)(CFTypeRef value, uint32_t type, void *valuePtr);
        static AutoAXValueGetValueFn getValue = NULL;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            getValue = (AutoAXValueGetValueFn)AutoBuiltinSymbol(AutoBuiltinFrameworkAccessibility, "AXValueGetValue");
        });
        enum { AutoAXValueCGRectType = 2 }; /* kAXValueCGRectType */
        if (!getValue || !getValue(frameValue, AutoAXValueCGRectType, &frame)) {
            return nil;
        }
    }
    return @{ @"x": @(frame.origin.x), @"y": @(frame.origin.y),
              @"width": @(frame.size.width), @"height": @(frame.size.height),
              @"centerX": @(frame.origin.x + frame.size.width / 2.0),
              @"centerY": @(frame.origin.y + frame.size.height / 2.0) };
}

- (NSString *)stringFromAXValue:(CFTypeRef)value {
    if (!value) return @"";
    if (CFGetTypeID(value) == CFStringGetTypeID()) {
        NSString *text = (__bridge NSString *)value;
        return text.length > AutoBuiltinMaxNodeStringLength ? [text substringToIndex:AutoBuiltinMaxNodeStringLength] : text;
    }
    if (CFGetTypeID(value) == CFNumberGetTypeID()) {
        return [NSString stringWithFormat:@"%@", (__bridge NSNumber *)value];
    }
    return @"";
}

- (NSDictionary *)descriptorForElement:(AutoAXElementRef)element
                                  path:(NSString *)path
                          parentHandle:(NSString *)parentHandle
                                 depth:(NSUInteger)depth
                                 index:(NSUInteger)index
                                engine:(AutoBuiltinAccessibilityEngine *)engine {
    AutoBuiltinAccessibilityEngine *ax = engine;
    CFTypeRef labelValue = [ax copyAttribute:AutoAXAttributeLabel ofElement:element];
    CFTypeRef roleValue = [ax copyAttribute:AutoAXAttributeRole ofElement:element];
    CFTypeRef valueValue = [ax copyAttribute:AutoAXAttributeValue ofElement:element];
    CFTypeRef identifierValue = [ax copyAttribute:AutoAXAttributeIdentifier ofElement:element];
    CFTypeRef frameValue = [ax copyAttribute:AutoAXAttributeFrame ofElement:element];
    CFTypeRef enabledValue = [ax copyAttribute:AutoAXAttributeEnabled ofElement:element];
    CFTypeRef selectedValue = [ax copyAttribute:AutoAXAttributeSelected ofElement:element];
    NSString *label = [self stringFromAXValue:labelValue];
    NSString *role = [self stringFromAXValue:roleValue];
    NSString *valueText = [self stringFromAXValue:valueValue];
    NSString *identifier = [self stringFromAXValue:identifierValue];
    NSDictionary *bounds = [self boundsFromAXFrame:frameValue];
    if (labelValue) CFRelease(labelValue);
    if (roleValue) CFRelease(roleValue);
    if (valueValue) CFRelease(valueValue);
    if (identifierValue) CFRelease(identifierValue);
    if (frameValue) CFRelease(frameValue);
    NSMutableDictionary *descriptor = [NSMutableDictionary dictionary];
    descriptor[@"handle"] = [AutoBuiltinHandlePrefix stringByAppendingString:path];
    descriptor[@"name"] = label;
    descriptor[@"label"] = label;
    descriptor[@"value"] = valueText;
    descriptor[@"type"] = role;
    descriptor[@"id"] = identifier;
    descriptor[@"enabled"] = @([self boolFromAXValue:enabledValue fallback:YES]);
    descriptor[@"selected"] = @([self boolFromAXValue:selectedValue fallback:NO]);
    descriptor[@"depth"] = @(depth);
    descriptor[@"index"] = @(index);
    if (parentHandle.length > 0) descriptor[@"parentHandle"] = parentHandle;
    if (bounds) descriptor[@"bounds"] = bounds;
    if (enabledValue) CFRelease(enabledValue);
    if (selectedValue) CFRelease(selectedValue);
    return descriptor;
}

- (BOOL)boolFromAXValue:(CFTypeRef)value fallback:(BOOL)fallback {
    if (!value) return fallback;
    if (CFGetTypeID(value) == CFBooleanGetTypeID()) return CFBooleanGetValue((CFBooleanRef)value);
    return fallback;
}

/**
 * Walks the system-wide accessibility tree depth-first with bounded
 * depth/node budgets. `onlyMatching` optionally filters descriptors with a
 * block (used by element queries); the walk still visits every node.
 */
- (nullable NSArray<NSDictionary *> *)walkWithMaxResults:(NSUInteger)maxResults
                                                  filter:(BOOL (^_Nullable)(NSDictionary *descriptor))filter
                                                   error:(NSError **)error {
    AutoBuiltinAccessibilityEngine *ax = [AutoBuiltinAccessibilityEngine sharedEngine];
    AutoAXElementRef root = [ax systemWideRoot];
    if (!root) {
        if (error) *error = AutoBuiltinUnavailable(@"accessibility element queries");
        return nil;
    }
    NSUInteger maxNodes = self.maxSnapshotNodes > 0 ? self.maxSnapshotNodes : AutoBuiltinDefaultMaxNodes;
    NSUInteger maxDepth = self.maxSnapshotDepth > 0 ? self.maxSnapshotDepth : AutoBuiltinDefaultMaxDepth;
    NSUInteger generation = self.cancellationGeneration;
    NSMutableArray<NSDictionary *> *results = [NSMutableArray array];
    __block BOOL budgetExceeded = NO;

    void (^__block walkBlock)(AutoAXElementRef, NSString *, NSString *, NSUInteger, NSUInteger) = nil;
    void (^walkImpl)(AutoAXElementRef, NSString *, NSString *, NSUInteger, NSUInteger) =
        ^(AutoAXElementRef element, NSString *path, NSString *parentHandle, NSUInteger depth, NSUInteger index) {
            if (budgetExceeded || [self operationCancelledSince:generation]) return;
            NSDictionary *descriptor = [self descriptorForElement:element path:path parentHandle:parentHandle
                                                            depth:depth index:index engine:ax];
            if (!filter || filter(descriptor)) {
                [results addObject:descriptor];
                if (maxResults > 0 && results.count >= maxResults) {
                    budgetExceeded = YES;
                    return;
                }
            }
            if (depth >= maxDepth) return;
            NSArray *children = [ax copyChildrenOfElement:element];
            NSUInteger childIndex = 0;
            for (id childObject in children) {
                if (budgetExceeded || [self operationCancelledSince:generation]) break;
                AutoAXElementRef child = (__bridge const void *)childObject;
                NSString *childPath = path.length > 0
                    ? [NSString stringWithFormat:@"%@.%lu", path, (unsigned long)childIndex]
                    : [NSString stringWithFormat:@"%lu", (unsigned long)childIndex];
                walkBlock(child, childPath, descriptor[@"handle"], depth + 1, childIndex);
                childIndex += 1;
            }
        };
    walkBlock = walkImpl;
    walkBlock(root, @"", nil, 0, 0);
    CFRelease(root);
    if ([self operationCancelledSince:generation]) {
        if (error) *error = AutoBuiltinError(AutoSDKErrorScriptCancelled, @"Built-in adapter: accessibility walk was cancelled.");
        return nil;
    }
    return results;
}

/** Resolves an axb: handle by replaying its child-index path from the root. */
- (nullable AutoAXElementRef)resolveHandle:(NSString *)handle error:(NSError **)error CF_RETURNS_RETAINED {
    if (![handle isKindOfClass:NSString.class] || ![handle hasPrefix:AutoBuiltinHandlePrefix]) {
        if (error) *error = AutoBuiltinError(AutoSDKErrorElementNotFound, @"Built-in adapter: handle must start with axb:.");
        return NULL;
    }
    AutoBuiltinAccessibilityEngine *ax = [AutoBuiltinAccessibilityEngine sharedEngine];
    AutoAXElementRef current = [ax systemWideRoot];
    if (!current) {
        if (error) *error = AutoBuiltinUnavailable(@"accessibility element queries");
        return NULL;
    }
    NSString *path = [handle substringFromIndex:AutoBuiltinHandlePrefix.length];
    if (path.length == 0) return current;
    for (NSString *component in [path componentsSeparatedByString:@"."]) {
        NSUInteger childIndex = component.integerValue;
        NSArray *children = [ax copyChildrenOfElement:current];
        AutoAXElementRef next = childIndex < children.count
            ? (AutoAXElementRef)CFRetain((__bridge CFTypeRef)children[childIndex])
            : NULL;
        CFRelease(current);
        if (!next) {
            if (error) *error = AutoBuiltinError(AutoSDKErrorElementNotFound, @"Built-in adapter: accessibility handle is stale; re-query the element.");
            return NULL;
        }
        current = next;
    }
    return current;
}

#pragma mark Selector matching

static NSString *AutoBuiltinRegexEscape(NSString *value) {
    NSMutableString *escaped = [NSMutableString stringWithCapacity:value.length + 8];
    for (NSUInteger i = 0; i < value.length; i++) {
        unichar c = [value characterAtIndex:i];
        if (strchr("\\.+*?()[]{}^$|", c)) [escaped appendFormat:@"\\%C", c];
        else [escaped appendString:[NSString stringWithCharacters:&c length:1]];
    }
    return escaped;
}

static NSString *AutoBuiltinXPathAttributeKey(NSString *attribute, NSError **error) {
    NSString *name = attribute.lowercaseString;
    if ([name isEqualToString:@"text"]) return @"text";
    if ([name isEqualToString:@"label"] || [name isEqualToString:@"name"]) return @"label";
    if ([name isEqualToString:@"value"]) return @"value";
    if ([name isEqualToString:@"id"] || [name isEqualToString:@"identifier"]) return @"id";
    if ([name isEqualToString:@"type"]) return @"type";
    if ([name isEqualToString:@"index"]) return @"index";
    if ([name isEqualToString:@"depth"]) return @"depth";
    if (error) *error = AutoBuiltinError(AutoSDKErrorInvalidConfiguration,
        [NSString stringWithFormat:@"Built-in xpath subset supports @text/@label/@name/@value/@id/@type/@index/@depth only (got @%@).", attribute]);
    return nil;
}

static NSArray<NSString *> *AutoBuiltinSplitXPathConditions(NSString *predicate) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    NSMutableString *current = [NSMutableString string];
    unichar quote = 0;
    for (NSUInteger i = 0; i < predicate.length; i++) {
        unichar c = [predicate characterAtIndex:i];
        if (quote) {
            [current appendString:[NSString stringWithCharacters:&c length:1]];
            if (c == quote) quote = 0;
            continue;
        }
        if (c == '\'' || c == '"') {
            quote = c;
            [current appendString:[NSString stringWithCharacters:&c length:1]];
            continue;
        }
        if (c == 'a' && i + 3 <= predicate.length &&
            [predicate compare:@"and" options:0 range:NSMakeRange(i, 3)] == NSOrderedSame &&
            (i == 0 || [predicate characterAtIndex:i - 1] == ' ') &&
            (i + 3 == predicate.length || [predicate characterAtIndex:i + 3] == ' ')) {
            [parts addObject:current];
            current = [NSMutableString string];
            i += 3;
            continue;
        }
        [current appendString:[NSString stringWithCharacters:&c length:1]];
    }
    [parts addObject:current];
    return parts;
}

static BOOL AutoBuiltinXPathValueIsQuoted(NSString *valuePart, NSString **outValue) {
    if (valuePart.length < 2) return NO;
    unichar first = [valuePart characterAtIndex:0];
    if ((first != '\'' && first != '"') || [valuePart characterAtIndex:valuePart.length - 1] != first) return NO;
    *outValue = [valuePart substringWithRange:NSMakeRange(1, valuePart.length - 2)];
    return YES;
}

static BOOL AutoBuiltinParseXPathCondition(NSString *rawCondition, NSMutableDictionary *query, NSError **error) {
    NSString *condition = [rawCondition stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (condition.length == 0 || condition.length > 256) {
        if (error) *error = AutoBuiltinError(AutoSDKErrorInvalidConfiguration, @"Built-in xpath condition must be 1-256 characters.");
        return NO;
    }
    NSRange paren = [condition rangeOfString:@"("];
    NSRange eq = [condition rangeOfString:@"="];
    if (paren.location != NSNotFound && (eq.location == NSNotFound || paren.location < eq.location)) {
        NSString *fn = [[condition substringToIndex:paren.location] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].lowercaseString;
        if (![condition hasSuffix:@")"]) {
            if (error) *error = AutoBuiltinError(AutoSDKErrorInvalidConfiguration, @"Built-in xpath function call must end with ')'.");
            return NO;
        }
        NSString *inner = [condition substringWithRange:NSMakeRange(paren.location + 1, condition.length - paren.location - 2)];
        NSRange comma = [inner rangeOfString:@","];
        if (comma.location == NSNotFound) {
            if (error) *error = AutoBuiltinError(AutoSDKErrorInvalidConfiguration, @"Built-in xpath function needs (@attr,'value') arguments.");
            return NO;
        }
        NSString *attrPart = [[inner substringToIndex:comma.location] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        NSString *valuePart = [[inner substringFromIndex:comma.location + 1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (![attrPart hasPrefix:@"@"]) {
            if (error) *error = AutoBuiltinError(AutoSDKErrorInvalidConfiguration, @"Built-in xpath function first argument must be @attribute.");
            return NO;
        }
        NSString *key = AutoBuiltinXPathAttributeKey([attrPart substringFromIndex:1], error);
        if (!key) return NO;
        if ([key isEqualToString:@"index"] || [key isEqualToString:@"depth"]) {
            if (error) *error = AutoBuiltinError(AutoSDKErrorInvalidConfiguration, @"Built-in xpath contains()/starts-with()/ends-with() cannot target @index/@depth.");
            return NO;
        }
        NSString *value = nil;
        if (!AutoBuiltinXPathValueIsQuoted(valuePart, &value)) {
            if (error) *error = AutoBuiltinError(AutoSDKErrorInvalidConfiguration, @"Built-in xpath function value must be a quoted string.");
            return NO;
        }
        NSString *escaped = AutoBuiltinRegexEscape(value);
        if ([fn isEqualToString:@"contains"]) query[[key stringByAppendingString:@"Match"]] = escaped;
        else if ([fn isEqualToString:@"starts-with"]) query[[key stringByAppendingString:@"Match"]] = [@"^" stringByAppendingString:escaped];
        else if ([fn isEqualToString:@"ends-with"]) query[[key stringByAppendingString:@"Match"]] = [escaped stringByAppendingString:@"$"];
        else {
            if (error) *error = AutoBuiltinError(AutoSDKErrorInvalidConfiguration, @"Built-in xpath supports contains()/starts-with()/ends-with() only.");
            return NO;
        }
        return YES;
    }
    if (eq.location == NSNotFound) {
        if (error) *error = AutoBuiltinError(AutoSDKErrorInvalidConfiguration, @"Built-in xpath condition must look like @attr='value' or contains(@attr,'value').");
        return NO;
    }
    NSString *attrPart = [[condition substringToIndex:eq.location] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    NSString *valuePart = [[condition substringFromIndex:eq.location + 1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (![attrPart hasPrefix:@"@"]) {
        if (error) *error = AutoBuiltinError(AutoSDKErrorInvalidConfiguration, @"Built-in xpath condition left side must be @attribute.");
        return NO;
    }
    NSString *key = AutoBuiltinXPathAttributeKey([attrPart substringFromIndex:1], error);
    if (!key) return NO;
    NSString *quotedValue = nil;
    if (AutoBuiltinXPathValueIsQuoted(valuePart, &quotedValue)) {
        if ([key isEqualToString:@"index"] || [key isEqualToString:@"depth"]) {
            query[key] = @([quotedValue integerValue]);
        } else {
            query[key] = quotedValue;
        }
        return YES;
    }
    if ([key isEqualToString:@"index"] || [key isEqualToString:@"depth"]) {
        NSCharacterSet *nonDigits = [NSCharacterSet.decimalDigitCharacterSet invertedSet];
        if (valuePart.length == 0 || [valuePart rangeOfCharacterFromSet:nonDigits].location != NSNotFound) {
            if (error) *error = AutoBuiltinError(AutoSDKErrorInvalidConfiguration, @"Built-in xpath @index/@depth need integer values.");
            return NO;
        }
        query[key] = @([valuePart integerValue]);
        return YES;
    }
    if (error) *error = AutoBuiltinError(AutoSDKErrorInvalidConfiguration, @"Built-in xpath text attribute values must be quoted.");
    return NO;
}

/** Translates the supported xpath subset (//Type[@attr='v' and contains(@attr,'v')][n])
 *  into native query keys. Unsupported syntax returns nil with a descriptive error. */
static NSDictionary *AutoBuiltinXPathToQuery(NSString *xpath, NSInteger *positionalIndex, NSError **error) {
    *positionalIndex = 0;
    if (xpath.length == 0 || xpath.length > 512) {
        if (error) *error = AutoBuiltinError(AutoSDKErrorInvalidConfiguration, @"Built-in xpath must be 1-512 characters.");
        return nil;
    }
    if (![xpath hasPrefix:@"//"] ||
        [xpath rangeOfString:@"/" options:0 range:NSMakeRange(2, xpath.length - 2)].location != NSNotFound) {
        if (error) *error = AutoBuiltinError(AutoSDKErrorInvalidConfiguration, @"Built-in xpath subset supports a single //Type step only (no nested paths).");
        return nil;
    }
    NSString *rest = [xpath substringFromIndex:2];
    NSString *nodeTest = rest;
    NSString *predicate = nil;
    NSRange open = [rest rangeOfString:@"["];
    if (open.location != NSNotFound) {
        if (![rest hasSuffix:@"]"] || open.location + 1 >= rest.length - 1) {
            if (error) *error = AutoBuiltinError(AutoSDKErrorInvalidConfiguration, @"Built-in xpath predicate must be a single [...] block.");
            return nil;
        }
        nodeTest = [rest substringToIndex:open.location];
        predicate = [rest substringWithRange:NSMakeRange(open.location + 1, rest.length - open.location - 2)];
    }
    nodeTest = [nodeTest stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (nodeTest.length == 0) {
        if (error) *error = AutoBuiltinError(AutoSDKErrorInvalidConfiguration, @"Built-in xpath needs a node test such as //* or //Button.");
        return nil;
    }
    NSMutableDictionary *query = [NSMutableDictionary dictionary];
    if (![nodeTest isEqualToString:@"*"]) {
        if ([nodeTest rangeOfString:@"[^A-Za-z0-9_]" options:NSRegularExpressionSearch].location != NSNotFound) {
            if (error) *error = AutoBuiltinError(AutoSDKErrorInvalidConfiguration, @"Built-in xpath node test must be * or an identifier (letters/digits/underscore).");
            return nil;
        }
        query[@"type"] = nodeTest;
    }
    if (predicate.length > 0) {
        NSString *trimmedPredicate = [predicate stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        NSCharacterSet *nonDigits = [NSCharacterSet.decimalDigitCharacterSet invertedSet];
        if (trimmedPredicate.length > 0 && [trimmedPredicate rangeOfCharacterFromSet:nonDigits].location == NSNotFound) {
            NSInteger position = [trimmedPredicate integerValue];
            if (position < 1) {
                if (error) *error = AutoBuiltinError(AutoSDKErrorInvalidConfiguration, @"Built-in xpath positional predicate starts at 1.");
                return nil;
            }
            *positionalIndex = position;
            return query;
        }
        for (NSString *condition in AutoBuiltinSplitXPathConditions(trimmedPredicate)) {
            if (!AutoBuiltinParseXPathCondition(condition, query, error)) return nil;
        }
    }
    return query;
}

- (BOOL)text:(NSString *)text matchesPattern:(NSString *)pattern {
    if (pattern.length == 0) return YES;
    if (text.length == 0) return NO;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:NULL];
    if (!regex) return NO;
    NSRange range = NSMakeRange(0, text.length);
    return [regex firstMatchInString:text options:0 range:range] != nil;
}

- (BOOL)descriptor:(NSDictionary *)descriptor matchesQuery:(NSDictionary *)query error:(NSError **)error {
    NSString *handle = AutoBuiltinStringOrNil(query[@"handle"]);
    if (handle.length > 0 && ![descriptor[@"handle"] isEqualToString:handle]) return NO;

    NSString *text = AutoBuiltinStringOrNil(query[@"text"]);
    if (text.length > 0 &&
        ![descriptor[@"label"] isEqualToString:text] &&
        ![descriptor[@"value"] isEqualToString:text]) return NO;

    NSString *textMatch = AutoBuiltinStringOrNil(query[@"textMatch"]);
    if (textMatch.length > 0 &&
        ![self text:descriptor[@"label"] matchesPattern:textMatch] &&
        ![self text:descriptor[@"value"] matchesPattern:textMatch]) return NO;

    NSString *label = AutoBuiltinStringOrNil(query[@"label"]) ?: AutoBuiltinStringOrNil(query[@"name"]);
    if (label.length > 0 && ![descriptor[@"label"] isEqualToString:label]) return NO;

    NSString *labelMatch = AutoBuiltinStringOrNil(query[@"labelMatch"]) ?: AutoBuiltinStringOrNil(query[@"nameMatch"]);
    if (labelMatch.length > 0 && ![self text:descriptor[@"label"] matchesPattern:labelMatch]) return NO;

    NSString *value = AutoBuiltinStringOrNil(query[@"value"]);
    if (value.length > 0 && ![descriptor[@"value"] isEqualToString:value]) return NO;

    NSString *valueMatch = AutoBuiltinStringOrNil(query[@"valueMatch"]);
    if (valueMatch.length > 0 && ![self text:descriptor[@"value"] matchesPattern:valueMatch]) return NO;

    NSString *identifier = AutoBuiltinStringOrNil(query[@"id"]);
    if (identifier.length > 0 && ![descriptor[@"id"] isEqualToString:identifier]) return NO;

    NSString *idMatch = AutoBuiltinStringOrNil(query[@"idMatch"]);
    if (idMatch.length > 0 && ![self text:descriptor[@"id"] matchesPattern:idMatch]) return NO;

    NSString *type = AutoBuiltinStringOrNil(query[@"type"]);
    if (type.length > 0 &&
        [descriptor[@"type"] caseInsensitiveCompare:type] != NSOrderedSame) return NO;

    NSString *typeMatch = AutoBuiltinStringOrNil(query[@"typeMatch"]);
    if (typeMatch.length > 0 && ![self text:descriptor[@"type"] matchesPattern:typeMatch]) return NO;

    id enabled = query[@"enabled"];
    if ([enabled isKindOfClass:NSNumber.class] &&
        [descriptor[@"enabled"] boolValue] != [enabled boolValue]) return NO;

    id selected = query[@"selected"];
    if ([selected isKindOfClass:NSNumber.class] &&
        [descriptor[@"selected"] boolValue] != [selected boolValue]) return NO;

    id depth = query[@"depth"];
    if ([depth isKindOfClass:NSNumber.class] &&
        [descriptor[@"depth"] integerValue] != [depth integerValue]) return NO;

    id index = query[@"index"];
    if ([index isKindOfClass:NSNumber.class] &&
        [descriptor[@"index"] integerValue] != [index integerValue]) return NO;

    NSDictionary *boundsQuery = [query[@"bounds"] isKindOfClass:NSDictionary.class] ? query[@"bounds"] : nil;
    if (boundsQuery) {
        NSDictionary *bounds = [descriptor[@"bounds"] isKindOfClass:NSDictionary.class] ? descriptor[@"bounds"] : nil;
        if (!bounds) return NO;
        if (fabs([bounds[@"x"] doubleValue] - AutoBuiltinDouble(boundsQuery[@"x"], 0)) > 0.5) return NO;
        if (fabs([bounds[@"y"] doubleValue] - AutoBuiltinDouble(boundsQuery[@"y"], 0)) > 0.5) return NO;
        if (fabs([bounds[@"width"] doubleValue] - AutoBuiltinDouble(boundsQuery[@"width"], 0)) > 0.5) return NO;
        if (fabs([bounds[@"height"] doubleValue] - AutoBuiltinDouble(boundsQuery[@"height"], 0)) > 0.5) return NO;
    }

    if (AutoBuiltinStringOrNil(query[@"predicate"]).length > 0) {
        if (error) *error = AutoBuiltinError(AutoSDKErrorAutomationUnavailable,
            @"Built-in adapter does not support predicate selectors; xpath supports a bounded subset (//Type[@attr='value']); use text/label/id/type match fields.");
        return NO;
    }
    return YES;
}

/** Resolves a selector into descriptors via one bounded accessibility walk. */
- (nullable NSArray<NSDictionary *> *)descriptorsForSelector:(id)selector error:(NSError **)error {
    NSDictionary *query = nil;
    if ([selector isKindOfClass:NSString.class]) {
        query = @{ @"text": selector };
    } else if ([selector isKindOfClass:NSDictionary.class]) {
        query = selector;
    } else {
        if (error) *error = AutoBuiltinError(AutoSDKErrorAutomationFailed, @"Built-in adapter: selector must be a string or object.");
        return nil;
    }
    NSInteger xpathPosition = 0;
    if (AutoBuiltinStringOrNil(query[@"xpath"]).length > 0) {
        NSError *xpathError = nil;
        NSDictionary *translated = AutoBuiltinXPathToQuery(query[@"xpath"], &xpathPosition, &xpathError);
        if (!translated) {
            if (error) *error = xpathError;
            return nil;
        }
        NSMutableDictionary *merged = [query mutableCopy];
        [merged removeObjectForKey:@"xpath"];
        [merged addEntriesFromDictionary:translated];
        query = merged;
    }
    NSString *handle = AutoBuiltinStringOrNil(query[@"handle"]);
    if (handle.length > 0 && [handle hasPrefix:AutoBuiltinHandlePrefix]) {
        AutoAXElementRef element = [self resolveHandle:handle error:error];
        if (!element) return nil;
        AutoBuiltinAccessibilityEngine *ax = [AutoBuiltinAccessibilityEngine sharedEngine];
        NSDictionary *descriptor = [self descriptorForElement:element path:[handle substringFromIndex:AutoBuiltinHandlePrefix.length]
                                                 parentHandle:nil depth:0 index:0 engine:ax];
        CFRelease(element);
        return @[descriptor];
    }
    NSError *queryError = nil;
    NSArray<NSDictionary *> *all = [self walkWithMaxResults:0 filter:nil error:&queryError];
    if (!all) {
        if (error) *error = queryError;
        return nil;
    }
    NSMutableArray<NSDictionary *> *matches = [NSMutableArray array];
    for (NSDictionary *descriptor in all) {
        NSError *matchError = nil;
        if ([self descriptor:descriptor matchesQuery:query error:&matchError]) {
            [matches addObject:descriptor];
        } else if (matchError) {
            if (error) *error = matchError;
            return nil;
        }
    }
    if (xpathPosition > 0) {
        if ((NSInteger)matches.count < xpathPosition) return @[];
        return @[matches[xpathPosition - 1]];
    }
    return matches;
}

#pragma mark Required protocol methods

- (BOOL)click:(id)selector error:(NSError **)error {
    NSArray<NSDictionary *> *matches = [self descriptorsForSelector:selector error:error];
    if (!matches) return NO;
    NSDictionary *descriptor = matches.firstObject;
    if (!descriptor) {
        if (error) *error = AutoBuiltinError(AutoSDKErrorElementNotFound, @"Built-in adapter: no element matched the selector.");
        return NO;
    }
    NSDictionary *bounds = descriptor[@"bounds"];
    if (![bounds isKindOfClass:NSDictionary.class]) {
        if (error) *error = AutoBuiltinError(AutoSDKErrorAutomationFailed, @"Built-in adapter: matched element has no bounds.");
        return NO;
    }
    return [self clickAtX:[bounds[@"centerX"] doubleValue] y:[bounds[@"centerY"] doubleValue] error:error];
}

- (BOOL)longClick:(id)selector duration:(NSTimeInterval)duration error:(NSError **)error {
    NSArray<NSDictionary *> *matches = [self descriptorsForSelector:selector error:error];
    if (!matches) return NO;
    NSDictionary *descriptor = matches.firstObject;
    if (!descriptor) {
        if (error) *error = AutoBuiltinError(AutoSDKErrorElementNotFound, @"Built-in adapter: no element matched the selector.");
        return NO;
    }
    NSDictionary *bounds = descriptor[@"bounds"];
    if (![bounds isKindOfClass:NSDictionary.class]) {
        if (error) *error = AutoBuiltinError(AutoSDKErrorAutomationFailed, @"Built-in adapter: matched element has no bounds.");
        return NO;
    }
    CGFloat x = [bounds[@"centerX"] doubleValue];
    CGFloat y = [bounds[@"centerY"] doubleValue];
    NSTimeInterval hold = duration > 0 ? duration : 1.0;
    return [self holdAtX:x y:y duration:hold error:error];
}

- (BOOL)swipeFromX:(CGFloat)x1 y:(CGFloat)y1 toX:(CGFloat)x2 y:(CGFloat)y2 duration:(NSTimeInterval)duration error:(NSError **)error {
    NSTimeInterval total = duration > 0 ? duration : 0.3;
    NSUInteger steps = MAX((NSUInteger)2, (NSUInteger)ceil(total / 0.016));
    if (![self dispatchTouchPath:@[@{@"x": @(x1), @"y": @(y1)}] steps:steps to:@[@{@"x": @(x2), @"y": @(y2)}] duration:total error:error]) {
        return NO;
    }
    return YES;
}

- (BOOL)input:(id)selector text:(NSString *)text error:(NSError **)error {
    NSArray<NSDictionary *> *matches = [self descriptorsForSelector:selector error:error];
    if (!matches) return NO;
    NSDictionary *descriptor = matches.firstObject;
    if (!descriptor) {
        if (error) *error = AutoBuiltinError(AutoSDKErrorElementNotFound, @"Built-in adapter: no element matched the selector.");
        return NO;
    }
    NSString *handle = descriptor[@"handle"];
    AutoAXElementRef element = [self resolveHandle:handle error:error];
    if (!element) return NO;
    AutoBuiltinAccessibilityEngine *ax = [AutoBuiltinAccessibilityEngine sharedEngine];
    CFStringRef newText = (CFStringRef)CFBridgingRetain(text ?: @"");
    BOOL ok = [ax setValue:newText forAttribute:AutoAXAttributeValue ofElement:element];
    CFRelease(newText);
    CFRelease(element);
    if (!ok) {
        if (error) *error = AutoBuiltinError(AutoSDKErrorAutomationFailed,
            @"Built-in adapter: element rejected AXValue assignment (keyboard-only fields may need coordinate tapping).");
    }
    return ok;
}

- (NSString *)textForSelector:(id)selector error:(NSError **)error {
    NSArray<NSDictionary *> *matches = [self descriptorsForSelector:selector error:error];
    if (!matches) return nil;
    NSDictionary *descriptor = matches.firstObject;
    if (!descriptor) {
        if (error) *error = AutoBuiltinError(AutoSDKErrorElementNotFound, @"Built-in adapter: no element matched the selector.");
        return nil;
    }
    NSString *label = descriptor[@"label"];
    return label.length > 0 ? label : descriptor[@"value"];
}

- (NSDictionary<NSString *, id> *)deviceInfo {
    UIDevice *device = UIDevice.currentDevice;
    UIScreen *screen = UIScreen.mainScreen;
    return @{ @"model": device.model ?: @"iPhone",
              @"systemName": device.systemName ?: @"iOS",
              @"systemVersion": device.systemVersion ?: @"",
              @"name": device.name ?: @"",
              @"identifierForVendor": device.identifierForVendor.UUIDString ?: @"",
              @"screenWidth": @(screen.bounds.size.width),
              @"screenHeight": @(screen.bounds.size.height),
              @"screenScale": @(screen.scale),
              @"adapter": @"builtin" };
}

#pragma mark Touch synthesis

- (NSError *)touchUnavailableError {
    return AutoBuiltinUnavailable(@"IOHIDEvent touch injection");
}

- (BOOL)dispatchTouchPath:(NSArray<NSDictionary *> *)fromPoints
                    steps:(NSUInteger)steps
                       to:(NSArray<NSDictionary *> *)toPoints
                 duration:(NSTimeInterval)duration
                    error:(NSError **)error {
    AutoBuiltinTouchEngine *touch = [AutoBuiltinTouchEngine sharedEngine];
    if (![touch isReady]) {
        if (error) *error = [self touchUnavailableError];
        return NO;
    }
    NSUInteger generation = self.cancellationGeneration;
    NSTimeInterval stepDuration = steps > 1 ? duration / (NSTimeInterval)(steps - 1) : 0;
    for (NSUInteger finger = 0; finger < fromPoints.count; finger++) {
        CGFloat x = [fromPoints[finger][@"x"] doubleValue];
        CGFloat y = [fromPoints[finger][@"y"] doubleValue];
        if (![touch dispatchFrameAtIndex:(uint32_t)(finger + 1) identity:(uint32_t)(finger + 1)
                                       x:x y:y pressure:1.0 phase:0]) {
            if (error) *error = AutoBuiltinError(AutoSDKErrorAutomationFailed, @"Built-in adapter: touch down frame was rejected.");
            return NO;
        }
    }
    for (NSUInteger step = 1; step < steps; step++) {
        if ([self operationCancelledSince:generation]) {
            if (error) *error = AutoBuiltinError(AutoSDKErrorScriptCancelled, @"Built-in adapter: gesture was cancelled.");
            return NO;
        }
        CGFloat progress = (CGFloat)step / (CGFloat)MAX((NSUInteger)1, steps - 1);
        for (NSUInteger finger = 0; finger < fromPoints.count; finger++) {
            CGFloat x1 = [fromPoints[finger][@"x"] doubleValue];
            CGFloat y1 = [fromPoints[finger][@"y"] doubleValue];
            CGFloat x2 = finger < toPoints.count ? [toPoints[finger][@"x"] doubleValue] : x1;
            CGFloat y2 = finger < toPoints.count ? [toPoints[finger][@"y"] doubleValue] : y1;
            [touch dispatchFrameAtIndex:(uint32_t)(finger + 1) identity:(uint32_t)(finger + 1)
                                      x:x1 + (x2 - x1) * progress
                                      y:y1 + (y2 - y1) * progress
                               pressure:1.0 phase:1];
        }
        if (stepDuration > 0) usleep((useconds_t)(stepDuration * 1000000.0));
    }
    for (NSUInteger finger = 0; finger < fromPoints.count; finger++) {
        CGFloat x = finger < toPoints.count ? [toPoints[finger][@"x"] doubleValue] : [fromPoints[finger][@"x"] doubleValue];
        CGFloat y = finger < toPoints.count ? [toPoints[finger][@"y"] doubleValue] : [fromPoints[finger][@"y"] doubleValue];
        [touch dispatchFrameAtIndex:(uint32_t)(finger + 1) identity:(uint32_t)(finger + 1)
                                  x:x y:y pressure:0.0 phase:2];
    }
    return YES;
}

- (BOOL)clickAtX:(CGFloat)x y:(CGFloat)y error:(NSError **)error {
    return [self dispatchTouchPath:@[@{@"x": @(x), @"y": @(y)}] steps:2
                                to:@[@{@"x": @(x), @"y": @(y)}] duration:0.05 error:error];
}

- (BOOL)doubleClickAtX:(CGFloat)x y:(CGFloat)y interval:(NSTimeInterval)interval error:(NSError **)error {
    if (![self clickAtX:x y:y error:error]) return NO;
    NSTimeInterval gap = interval > 0 ? interval : 0.08;
    usleep((useconds_t)(gap * 1000000.0));
    return [self clickAtX:x y:y error:error];
}

- (BOOL)holdAtX:(CGFloat)x y:(CGFloat)y duration:(NSTimeInterval)duration error:(NSError **)error {
    AutoBuiltinTouchEngine *touch = [AutoBuiltinTouchEngine sharedEngine];
    if (![touch isReady]) {
        if (error) *error = [self touchUnavailableError];
        return NO;
    }
    if (![touch dispatchFrameAtIndex:1 identity:1 x:x y:y pressure:1.0 phase:0]) {
        if (error) *error = AutoBuiltinError(AutoSDKErrorAutomationFailed, @"Built-in adapter: touch down frame was rejected.");
        return NO;
    }
    usleep((useconds_t)(MAX(0.05, duration) * 1000000.0));
    [touch dispatchFrameAtIndex:1 identity:1 x:x y:y pressure:0.0 phase:2];
    return YES;
}

- (BOOL)performMultiTouch:(NSArray<NSArray<NSDictionary *> *> *)fingers error:(NSError **)error {
    if (![fingers isKindOfClass:NSArray.class] || fingers.count == 0 || fingers.count > 10) {
        if (error) *error = AutoBuiltinError(AutoSDKErrorAutomationFailed, @"Built-in adapter: multi-touch needs 1 to 10 finger tracks.");
        return NO;
    }
    AutoBuiltinTouchEngine *touch = [AutoBuiltinTouchEngine sharedEngine];
    if (![touch isReady]) {
        if (error) *error = [self touchUnavailableError];
        return NO;
    }
    /*
     * Tracks use W3C pointer actions with relative durations (milliseconds):
     * pointerMove interpolates toward x/y over its duration, pointerDown/up
     * act at the current position, pause simply waits. Per-finger timelines
     * are expanded into absolutely timed frames, merged across fingers, and
     * dispatched in time order.
     */
    NSMutableArray<NSDictionary *> *frames = [NSMutableArray array];
    for (NSUInteger finger = 0; finger < fingers.count; finger++) {
        NSArray<NSDictionary *> *track = fingers[finger];
        if (![track isKindOfClass:NSArray.class] || track.count == 0 || track.count > 4096) {
            if (error) *error = AutoBuiltinError(AutoSDKErrorAutomationFailed, @"Built-in adapter: finger track must contain 1 to 4096 actions.");
            return NO;
        }
        CGFloat cursorX = 0, cursorY = 0;
        NSTimeInterval cursorTime = 0;
        BOOL isDown = NO;
        for (NSDictionary *action in track) {
            if (![action isKindOfClass:NSDictionary.class]) continue;
            NSString *type = AutoBuiltinStringOrNil(action[@"type"]) ?: @"pause";
            NSTimeInterval duration = AutoBuiltinDouble(action[@"duration"], 0) / 1000.0;
            if (duration < 0) duration = 0;
            if (duration > 60) duration = 60;
            if ([type isEqualToString:@"pointerMove"]) {
                CGFloat targetX = AutoBuiltinDouble(action[@"x"], cursorX);
                CGFloat targetY = AutoBuiltinDouble(action[@"y"], cursorY);
                NSUInteger steps = duration > 0 ? MAX((NSUInteger)2, (NSUInteger)ceil(duration / 0.016)) : 1;
                for (NSUInteger step = 1; step <= steps; step++) {
                    CGFloat progress = (CGFloat)step / (CGFloat)steps;
                    [frames addObject:@{ @"at": @(cursorTime + duration * progress),
                                         @"finger": @(finger),
                                         @"phase": @(isDown ? 1 : 1),
                                         @"pressure": @(isDown ? 1.0 : 0.0),
                                         @"x": @(cursorX + (targetX - cursorX) * progress),
                                         @"y": @(cursorY + (targetY - cursorY) * progress) }];
                }
                cursorX = targetX; cursorY = targetY;
                cursorTime += duration;
            } else if ([type isEqualToString:@"pointerDown"]) {
                isDown = YES;
                [frames addObject:@{ @"at": @(cursorTime), @"finger": @(finger), @"phase": @0,
                                     @"pressure": @1.0, @"x": @(cursorX), @"y": @(cursorY) }];
                cursorTime += 0.01;
            } else if ([type isEqualToString:@"pointerUp"]) {
                isDown = NO;
                [frames addObject:@{ @"at": @(cursorTime), @"finger": @(finger), @"phase": @2,
                                     @"pressure": @0.0, @"x": @(cursorX), @"y": @(cursorY) }];
                cursorTime += 0.01;
            } else { /* pause */
                cursorTime += duration;
            }
        }
        if (isDown) {
            [frames addObject:@{ @"at": @(cursorTime), @"finger": @(finger), @"phase": @2,
                                 @"pressure": @0.0, @"x": @(cursorX), @"y": @(cursorY) }];
        }
    }
    [frames sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        double at = [a[@"at"] doubleValue] - [b[@"at"] doubleValue];
        if (fabs(at) < 0.000001) return NSOrderedSame;
        return at < 0 ? NSOrderedAscending : NSOrderedDescending;
    }];
    NSUInteger generation = self.cancellationGeneration;
    NSTimeInterval dispatched = 0;
    for (NSDictionary *frame in frames) {
        if ([self operationCancelledSince:generation]) {
            if (error) *error = AutoBuiltinError(AutoSDKErrorScriptCancelled, @"Built-in adapter: gesture was cancelled.");
            return NO;
        }
        NSTimeInterval at = [frame[@"at"] doubleValue];
        if (at > dispatched) {
            usleep((useconds_t)((at - dispatched) * 1000000.0));
            dispatched = at;
        }
        [touch dispatchFrameAtIndex:(uint32_t)([frame[@"finger"] unsignedIntValue] + 1)
                           identity:(uint32_t)([frame[@"finger"] unsignedIntValue] + 1)
                                  x:[frame[@"x"] doubleValue]
                                  y:[frame[@"y"] doubleValue]
                           pressure:[frame[@"pressure"] doubleValue]
                              phase:[frame[@"phase"] integerValue]];
    }
    return YES;
}

#pragma mark Element queries

- (BOOL)exists:(id)selector error:(NSError **)error {
    NSArray<NSDictionary *> *matches = [self descriptorsForSelector:selector error:error];
    if (!matches) return NO;
    return matches.count > 0;
}

- (NSDictionary<NSString *, id> *)elementInfoForSelector:(id)selector error:(NSError **)error {
    NSArray<NSDictionary *> *matches = [self descriptorsForSelector:selector error:error];
    if (!matches) return nil;
    NSDictionary *descriptor = matches.firstObject;
    if (!descriptor && error) *error = AutoBuiltinError(AutoSDKErrorElementNotFound, @"Built-in adapter: no element matched the selector.");
    return descriptor;
}

- (NSArray<NSDictionary<NSString *, id> *> *)elementsInfoForSelector:(id)selector error:(NSError **)error {
    NSArray<NSDictionary *> *matches = [self descriptorsForSelector:selector error:error];
    if (!matches) return nil;
    return matches;
}

- (NSArray<NSDictionary<NSString *, id> *> *)nodeSnapshotWithMaxResults:(NSUInteger)maxResults error:(NSError **)error {
    NSUInteger limit = maxResults > 0 ? maxResults : self.maxSnapshotNodes;
    return [self walkWithMaxResults:limit filter:nil error:error];
}

- (id)attribute:(NSString *)attribute forSelector:(id)selector error:(NSError **)error {
    NSDictionary *descriptor = [self elementInfoForSelector:selector error:error];
    if (!descriptor) return nil;
    NSString *name = [attribute isKindOfClass:NSString.class] ? attribute : @"";
    if ([name isEqualToString:@"name"] || [name isEqualToString:@"label"]) return descriptor[@"label"];
    if ([name isEqualToString:@"value"]) return descriptor[@"value"];
    if ([name isEqualToString:@"type"] || [name isEqualToString:@"role"]) return descriptor[@"type"];
    if ([name isEqualToString:@"id"]) return descriptor[@"id"];
    if ([name isEqualToString:@"enabled"]) return descriptor[@"enabled"];
    if ([name isEqualToString:@"selected"]) return descriptor[@"selected"];
    if ([name isEqualToString:@"bounds"]) return descriptor[@"bounds"];
    return descriptor[name];
}

- (NSDictionary<NSString *, id> *)boundsForSelector:(id)selector error:(NSError **)error {
    NSDictionary *descriptor = [self elementInfoForSelector:selector error:error];
    if (!descriptor) return nil;
    NSDictionary *bounds = [descriptor[@"bounds"] isKindOfClass:NSDictionary.class] ? descriptor[@"bounds"] : nil;
    if (!bounds && error) *error = AutoBuiltinError(AutoSDKErrorAutomationFailed, @"Built-in adapter: matched element has no bounds.");
    return bounds;
}

- (NSArray<NSDictionary<NSString *, id> *> *)childrenForSelector:(id)selector error:(NSError **)error {
    NSDictionary *descriptor = [self elementInfoForSelector:selector error:error];
    if (!descriptor) return nil;
    NSString *handle = descriptor[@"handle"];
    AutoAXElementRef element = [self resolveHandle:handle error:error];
    if (!element) return nil;
    AutoBuiltinAccessibilityEngine *ax = [AutoBuiltinAccessibilityEngine sharedEngine];
    NSArray *children = [ax copyChildrenOfElement:element];
    CFRelease(element);
    NSMutableArray<NSDictionary *> *result = [NSMutableArray array];
    NSString *basePath = [handle hasPrefix:AutoBuiltinHandlePrefix] ? [handle substringFromIndex:AutoBuiltinHandlePrefix.length] : @"";
    NSUInteger index = 0;
    for (id childObject in children) {
        AutoAXElementRef child = (__bridge const void *)childObject;
        NSString *childPath = basePath.length > 0 ? [NSString stringWithFormat:@"%@.%lu", basePath, (unsigned long)index]
                                                  : [NSString stringWithFormat:@"%lu", (unsigned long)index];
        [result addObject:[self descriptorForElement:child path:childPath parentHandle:handle depth:1 index:index engine:ax]];
        index += 1;
    }
    return result;
}

- (NSDictionary<NSString *, id> *)parentForSelector:(id)selector error:(NSError **)error {
    NSArray<NSDictionary *> *all = [self walkWithMaxResults:0 filter:nil error:error];
    if (!all) return nil;
    NSArray<NSDictionary *> *matches = [self descriptorsForSelector:selector error:error];
    if (!matches) return nil;
    NSDictionary *descriptor = matches.firstObject;
    if (!descriptor) {
        if (error) *error = AutoBuiltinError(AutoSDKErrorElementNotFound, @"Built-in adapter: no element matched the selector.");
        return nil;
    }
    NSString *parentHandle = descriptor[@"parentHandle"];
    if (parentHandle.length == 0) return nil;
    for (NSDictionary *candidate in all) {
        if ([candidate[@"handle"] isEqualToString:parentHandle]) return candidate;
    }
    return nil;
}

- (BOOL)scrollIntoView:(id)selector error:(NSError **)error {
    NSArray<NSDictionary *> *matches = [self descriptorsForSelector:selector error:error];
    if (!matches) return NO;
    NSDictionary *descriptor = matches.firstObject;
    if (!descriptor) {
        if (error) *error = AutoBuiltinError(AutoSDKErrorElementNotFound, @"Built-in adapter: no element matched the selector.");
        return NO;
    }
    AutoAXElementRef element = [self resolveHandle:descriptor[@"handle"] error:error];
    if (!element) return NO;
    AutoBuiltinAccessibilityEngine *ax = [AutoBuiltinAccessibilityEngine sharedEngine];
    BOOL ok = [ax performAction:AutoAXActionScrollToVisible onElement:element];
    if (!ok) ok = [ax performAction:AutoAXActionPress onElement:element];
    CFRelease(element);
    if (!ok && error) *error = AutoBuiltinError(AutoSDKErrorAutomationFailed, @"Built-in adapter: element supports no scroll-to-visible action.");
    return ok;
}

#pragma mark Application control

static NSString *AutoBuiltinBundleIdForAppName(NSString *name) {
    static NSDictionary<NSString *, NSString *> *table = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        table = @{ @"微信": @"com.tencent.xin", @"QQ": @"com.tencent.mqq", @"TIM": @"com.tencent.tim",
            @"企业微信": @"com.tencent.ww", @"支付宝": @"com.alipay.iphoneclient",
            @"淘宝": @"com.taobao.taobao4iphone", @"闲鱼": @"com.taobao.fleamarket",
            @"京东": @"com.360buy.jdmobile", @"拼多多": @"com.xunmeng.pinduoduo",
            @"抖音": @"com.ss.iphone.ugc.Aweme", @"快手": @"com.gifshow.kuaishou",
            @"哔哩哔哩": @"tv.danmaku.bilian", @"微博": @"com.sina.weibo",
            @"小红书": @"com.xingin.discover", @"知乎": @"com.zhihu.ios", @"豆瓣": @"com.douban.frodo",
            @"美团": @"com.meituan.imeituan", @"饿了么": @"me.ele.ios.eleme", @"滴滴": @"com.xiaojukeji.didi",
            @"高德地图": @"com.autonavi.amap", @"高德": @"com.autonavi.amap", @"百度地图": @"com.baidu.map",
            @"百度": @"com.baidu.BaiduMobile", @"网易云音乐": @"com.netease.cloudmusic",
            @"QQ音乐": @"com.tencent.QQMusic", @"酷狗音乐": @"com.kugou.kugou",
            @"爱奇艺": @"com.qiyi.iphone", @"优酷": @"com.youku.YouKu", @"腾讯视频": @"com.tencent.live4iphone",
            @"芒果TV": @"com.hunantv.mgo", @"携程": @"com.ctrip.ctrip", @"去哪儿": @"com.qunar.iphoneclient",
            @"铁路12306": @"com.chinarailway.global", @"12306": @"com.chinarailway.global",
            @"顺丰": @"com.sf.courier", @"招商银行": @"cmb.pb", @"工商银行": @"com.icbc.iphone",
            @"建设银行": @"com.ccb.ccbiphone", @"中国银行": @"com.chinamworld.bocmbci",
            @"农业银行": @"com.abchina.bank", @"钉钉": @"com.laiwang.DingTalk", @"飞书": @"com.bytedance.lark",
            @"WPS": @"cn.wps.moffice_eng", @"微信读书": @"com.tencent.weread", @"QQ邮箱": @"com.tencent.qqmail",
            @"设置": @"com.apple.Preferences", @"相册": @"com.apple.mobileslideshow",
            @"照片": @"com.apple.mobileslideshow", @"相机": @"com.apple.camera",
            @"Safari": @"com.apple.mobilesafari", @"浏览器": @"com.apple.mobilesafari",
            @"邮件": @"com.apple.MobileMail", @"信息": @"com.apple.MobileSMS", @"电话": @"com.apple.mobilephone",
            @"地图": @"com.apple.Maps", @"App Store": @"com.apple.AppStore", @"快捷指令": @"com.apple.shortcuts",
            @"时钟": @"com.apple.mobiletimer", @"计算器": @"com.apple.calculator",
            @"备忘录": @"com.apple.mobilenotes", @"日历": @"com.apple.mobilecal",
            @"文件": @"com.apple.DocumentsApp", @"音乐": @"com.apple.music" };
    });
    NSString *key = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return key.length > 0 ? table[key] : nil;
}

- (BOOL)launchApplicationWithBundleId:(NSString *)bundleId error:(NSError **)error {
    NSString *resolved = AutoBuiltinBundleIdForAppName(bundleId) ?: bundleId;
    if (!AutoBuiltinLaunchBundleId(resolved)) {
        if (error) *error = AutoBuiltinUnavailable(@"application launch (LSApplicationWorkspace/SpringBoardServices)");
        return NO;
    }
    return YES;
}

- (BOOL)activateApplicationWithBundleId:(NSString *)bundleId error:(NSError **)error {
    return [self launchApplicationWithBundleId:bundleId error:error];
}

- (BOOL)terminateApplicationWithBundleId:(NSString *)bundleId error:(NSError **)error {
    NSString *resolved = AutoBuiltinBundleIdForAppName(bundleId) ?: bundleId;
    if (!AutoBuiltinTerminateBundleId(resolved)) {
        if (error) *error = AutoBuiltinUnavailable(@"application termination (BKSTerminateApplication)");
        return NO;
    }
    return YES;
}

- (NSNumber *)applicationStateForBundleId:(NSString *)bundleId error:(NSError **)error {
    NSString *frontmost = AutoBuiltinFrontmostBundleId();
    if (!frontmost) {
        if (error) *error = AutoBuiltinUnavailable(@"application state queries (SBSCopyFrontmostApplicationDisplayIdentifier)");
        return nil;
    }
    /* 4 = running in foreground (matches the WDA/XCUIApplication convention). */
    NSString *resolved = AutoBuiltinBundleIdForAppName(bundleId) ?: bundleId;
    return [frontmost isEqualToString:resolved] ? @4 : @1;
}

- (NSString *)currentApplicationWithError:(NSError **)error {
    NSString *frontmost = AutoBuiltinFrontmostBundleId();
    if (!frontmost && error) *error = AutoBuiltinUnavailable(@"frontmost app queries (SBSCopyFrontmostApplicationDisplayIdentifier)");
    return frontmost;
}

- (NSArray<NSDictionary<NSString *, id> *> *)installedApplicationsWithError:(NSError **)error {
    NSArray<NSString *> *bundleIds = AutoBuiltinInstalledBundleIds();
    if (!bundleIds) {
        if (error) *error = AutoBuiltinUnavailable(@"installed app listing (LSApplicationWorkspace)");
        return nil;
    }
    NSMutableArray<NSDictionary *> *apps = [NSMutableArray array];
    for (NSString *bundleId in bundleIds) {
        [apps addObject:@{ @"bundleId": bundleId }];
    }
    return apps;
}

- (BOOL)pressButtonWithName:(NSString *)name error:(NSError **)error {
    NSString *button = [name isKindOfClass:NSString.class] ? name.lowercaseString : @"";
    if ([button isEqualToString:@"home"]) return [self goToHomeScreenWithError:error];
    if (error) *error = AutoBuiltinUnavailable([NSString stringWithFormat:@"hardware button '%@' injection", name]);
    return NO;
}

- (NSNumber *)deviceLockedStateWithError:(NSError **)error {
    if (error) *error = AutoBuiltinUnavailable(@"lock state queries");
    return nil;
}

- (BOOL)goToHomeScreenWithError:(NSError **)error {
    if (!AutoBuiltinLaunchBundleId(@"com.apple.springboard")) {
        if (error) *error = AutoBuiltinUnavailable(@"home screen (SpringBoardServices)");
        return NO;
    }
    return YES;
}

- (BOOL)lockDeviceWithError:(NSError **)error {
    AutoSBSLockDeviceFn lock = (AutoSBSLockDeviceFn)AutoBuiltinSymbol(AutoBuiltinFrameworkSpringBoardServices, "SBSLockDevice");
    if (!lock) {
        if (error) *error = AutoBuiltinUnavailable(@"device lock (SBSLockDevice)");
        return NO;
    }
    lock();
    return YES;
}

- (BOOL)unlockDeviceWithError:(NSError **)error {
    AutoSBSOpenSensitiveURLOptionsFn openAndUnlock =
        (AutoSBSOpenSensitiveURLOptionsFn)AutoBuiltinSymbol(AutoBuiltinFrameworkSpringBoardServices, "SBSOpenSensitiveURLAndUnlock");
    if (!openAndUnlock) {
        if (error) *error = AutoBuiltinUnavailable(@"device unlock (SBSOpenSensitiveURLAndUnlock)");
        return NO;
    }
    CFURLRef settingsURL = CFURLCreateWithString(kCFAllocatorDefault, CFSTR("App-prefs:"), NULL);
    if (!settingsURL) {
        if (error) *error = AutoBuiltinError(AutoSDKErrorAutomationFailed, @"Built-in adapter: unable to build unlock URL.");
        return NO;
    }
    Boolean ok = openAndUnlock(settingsURL, true);
    CFRelease(settingsURL);
    return ok ? YES : NO;
}

#pragma mark Screenshot and visual operations

- (nullable NSData *)systemWideScreenshotImageWithError:(NSError **)error {
    typedef UIImage *(*AutoUIGetScreenImageFn)(void);
    AutoUIGetScreenImageFn getScreenImage =
        (AutoUIGetScreenImageFn)AutoBuiltinSymbol(AutoBuiltinFrameworkUIKit, "UIGetScreenImage");
    if (getScreenImage) {
        UIImage *image = getScreenImage();
        if (image) {
            NSData *png = UIImagePNGRepresentation(image);
            if (png.length > 0) return png;
        }
    }
    __block NSData *captured = nil;
    if (NSThread.isMainThread) {
        captured = [self hostWindowScreenshot];
    } else {
        dispatch_sync(dispatch_get_main_queue(), ^{ captured = [self hostWindowScreenshot]; });
    }
    if (captured.length > 0) return captured;
    if (error) *error = AutoBuiltinUnavailable(@"system-wide screenshots (UIGetScreenImage)");
    return nil;
}

- (nullable NSData *)hostWindowScreenshot {
    UIWindow *window = nil;
    for (UIWindow *candidate in UIApplication.sharedApplication.windows) {
        if (!candidate.hidden) { window = candidate; break; }
    }
    if (!window) window = UIApplication.sharedApplication.keyWindow;
    if (!window) return nil;
    UIGraphicsBeginImageContextWithOptions(window.bounds.size, NO, window.screen.scale);
    BOOL drew = [window drawViewHierarchyInRect:window.bounds afterScreenUpdates:NO];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (!drew || !image) return nil;
    return UIImagePNGRepresentation(image);
}

- (NSData *)screenshotWithError:(NSError **)error {
    if (self.screenshotCacheDuration > 0) {
        NSData *cached = self.cachedScreenshot;
        NSDate *cachedAt = self.cachedScreenshotAt;
        if (cached.length > 0 && cachedAt &&
            [NSDate.date timeIntervalSinceDate:cachedAt] < self.screenshotCacheDuration) {
            return cached;
        }
    }
    NSData *png = [self systemWideScreenshotImageWithError:error];
    if (png.length > 0 && self.screenshotCacheDuration > 0) {
        self.cachedScreenshot = png;
        self.cachedScreenshotAt = NSDate.date;
    }
    return png;
}

- (NSData *)screenPNGWithOptions:(NSDictionary *)options error:(NSError **)error {
    id cachedPath = [options isKindOfClass:NSDictionary.class] ? options[@"screenshotPath"] : nil;
    if ([cachedPath isKindOfClass:NSString.class]) {
        NSString *path = (NSString *)cachedPath;
        NSString *sandboxPrefix = [NSHomeDirectory() stringByAppendingString:@"/"];
        if (path.length > 0 && [path isAbsolutePath] && [path hasPrefix:sandboxPrefix]) {
            NSData *cached = [NSData dataWithContentsOfFile:path];
            if (cached.length > 0) return cached;
        }
    }
    return [self screenshotWithError:error];
}

- (NSDictionary *)pixelColorAtX:(CGFloat)x y:(CGFloat)y error:(NSError **)error {
    NSData *png = [self screenshotWithError:error];
    if (!png) return nil;
    AutoBuiltinBitmap bitmap;
    if (!AutoBuiltinBitmapFromPNGData(png, &bitmap)) {
        if (error) *error = AutoBuiltinError(AutoSDKErrorAutomationFailed, @"Built-in adapter: unable to decode screenshot bitmap.");
        return nil;
    }
    CGFloat scale = UIScreen.mainScreen.scale > 0 ? UIScreen.mainScreen.scale : 1;
    size_t pixelX = (size_t)MAX(0, MIN((NSInteger)bitmap.width - 1, (NSInteger)llround(x * scale)));
    size_t pixelY = (size_t)MAX(0, MIN((NSInteger)bitmap.height - 1, (NSInteger)llround(y * scale)));
    const uint8_t *pixel = bitmap.bytes + pixelY * bitmap.bytesPerRow + pixelX * 4;
    NSDictionary *result = AutoBuiltinPixelColorResult(pixel, x, y);
    AutoBuiltinBitmapFree(&bitmap);
    return result;
}

- (NSDictionary *)findColor:(id)color region:(NSDictionary *)region options:(NSDictionary *)options error:(NSError **)error {
    uint8_t targetRed = 0, targetGreen = 0, targetBlue = 0;
    if (!AutoBuiltinParseColor(color, &targetRed, &targetGreen, &targetBlue)) {
        if (error) *error = AutoBuiltinError(AutoSDKErrorAutomationFailed, @"Built-in adapter: invalid color selector.");
        return nil;
    }
    NSData *png = [self screenPNGWithOptions:options error:error];
    if (!png) return nil;
    AutoBuiltinBitmap bitmap;
    if (!AutoBuiltinBitmapFromPNGData(png, &bitmap)) {
        if (error) *error = AutoBuiltinError(AutoSDKErrorAutomationFailed, @"Built-in adapter: unable to decode screenshot bitmap.");
        return nil;
    }
    CGFloat scale = UIScreen.mainScreen.scale > 0 ? UIScreen.mainScreen.scale : 1;
    double tolerance = AutoBuiltinDouble(options[@"tolerance"], 12);
    size_t startX = (size_t)MAX(0, MIN((NSInteger)bitmap.width, (NSInteger)llround(AutoBuiltinDouble(region[@"x"], 0) * scale)));
    size_t startY = (size_t)MAX(0, MIN((NSInteger)bitmap.height, (NSInteger)llround(AutoBuiltinDouble(region[@"y"], 0) * scale)));
    size_t endX = (size_t)MAX(startX, MIN((NSInteger)bitmap.width, (NSInteger)llround((AutoBuiltinDouble(region[@"x"], 0) + AutoBuiltinDouble(region[@"width"], (CGFloat)bitmap.width / scale)) * scale)));
    size_t endY = (size_t)MAX(startY, MIN((NSInteger)bitmap.height, (NSInteger)llround((AutoBuiltinDouble(region[@"y"], 0) + AutoBuiltinDouble(region[@"height"], (CGFloat)bitmap.height / scale)) * scale)));
    NSUInteger generation = self.cancellationGeneration;
    NSDictionary *found = nil;
    NSUInteger candidates = 0;
    for (size_t y = startY; y < endY && !found; y++) {
        if ([self operationCancelledSince:generation]) break;
        const uint8_t *row = bitmap.bytes + y * bitmap.bytesPerRow;
        for (size_t x = startX; x < endX; x++) {
            const uint8_t *pixel = row + x * 4;
            if (fabs((double)pixel[0] - targetRed) <= tolerance &&
                fabs((double)pixel[1] - targetGreen) <= tolerance &&
                fabs((double)pixel[2] - targetBlue) <= tolerance) {
                found = AutoBuiltinPixelColorResult(pixel, (CGFloat)x / scale, (CGFloat)y / scale);
                break;
            }
            candidates += 1;
            if (candidates > AutoBuiltinMaxColorCandidates) break;
        }
    }
    AutoBuiltinBitmapFree(&bitmap);
    if ([self operationCancelledSince:generation] && error) {
        *error = AutoBuiltinError(AutoSDKErrorScriptCancelled, @"Built-in adapter: color search was cancelled.");
        return nil;
    }
    return found;
}

- (BOOL)compareColors:(NSArray<NSDictionary *> *)points options:(NSDictionary *)options error:(NSError **)error {
    if (![points isKindOfClass:NSArray.class] || points.count == 0 || points.count > AutoBuiltinMaxColorPoints) {
        if (error) *error = AutoBuiltinError(AutoSDKErrorAutomationFailed, @"Built-in adapter: compareColors needs 1 to 4096 points.");
        return NO;
    }
    NSData *png = [self screenPNGWithOptions:options error:error];
    if (!png) return NO;
    AutoBuiltinBitmap bitmap;
    if (!AutoBuiltinBitmapFromPNGData(png, &bitmap)) {
        if (error) *error = AutoBuiltinError(AutoSDKErrorAutomationFailed, @"Built-in adapter: unable to decode screenshot bitmap.");
        return NO;
    }
    CGFloat scale = UIScreen.mainScreen.scale > 0 ? UIScreen.mainScreen.scale : 1;
    double tolerance = AutoBuiltinDouble(options[@"tolerance"], 12);
    BOOL allMatch = YES;
    for (NSDictionary *point in points) {
        uint8_t targetRed = 0, targetGreen = 0, targetBlue = 0;
        if (!AutoBuiltinParseColor(point[@"color"], &targetRed, &targetGreen, &targetBlue)) {
            AutoBuiltinBitmapFree(&bitmap);
            if (error) *error = AutoBuiltinError(AutoSDKErrorAutomationFailed, @"Built-in adapter: invalid compareColors point color.");
            return NO;
        }
        size_t x = (size_t)MAX(0, MIN((NSInteger)bitmap.width - 1, (NSInteger)llround(AutoBuiltinDouble(point[@"x"], 0) * scale)));
        size_t y = (size_t)MAX(0, MIN((NSInteger)bitmap.height - 1, (NSInteger)llround(AutoBuiltinDouble(point[@"y"], 0) * scale)));
        const uint8_t *pixel = bitmap.bytes + y * bitmap.bytesPerRow + x * 4;
        if (fabs((double)pixel[0] - targetRed) > tolerance ||
            fabs((double)pixel[1] - targetGreen) > tolerance ||
            fabs((double)pixel[2] - targetBlue) > tolerance) {
            allMatch = NO;
            break;
        }
    }
    AutoBuiltinBitmapFree(&bitmap);
    return allMatch;
}

- (NSDictionary *)findMultiColor:(id)color offsets:(NSArray *)offsets region:(NSDictionary *)region options:(NSDictionary *)options error:(NSError **)error {
    uint8_t anchorRed = 0, anchorGreen = 0, anchorBlue = 0;
    if (!AutoBuiltinParseColor(color, &anchorRed, &anchorGreen, &anchorBlue)) {
        if (error) *error = AutoBuiltinError(AutoSDKErrorAutomationFailed, @"Built-in adapter: invalid multi-color anchor.");
        return nil;
    }
    if (![offsets isKindOfClass:NSArray.class] || offsets.count == 0 || offsets.count > AutoBuiltinMaxColorPoints) {
        if (error) *error = AutoBuiltinError(AutoSDKErrorAutomationFailed, @"Built-in adapter: multi-color needs 1 to 4096 offsets.");
        return nil;
    }
    NSData *png = [self screenPNGWithOptions:options error:error];
    if (!png) return nil;
    AutoBuiltinBitmap bitmap;
    if (!AutoBuiltinBitmapFromPNGData(png, &bitmap)) {
        if (error) *error = AutoBuiltinError(AutoSDKErrorAutomationFailed, @"Built-in adapter: unable to decode screenshot bitmap.");
        return nil;
    }
    CGFloat scale = UIScreen.mainScreen.scale > 0 ? UIScreen.mainScreen.scale : 1;
    double tolerance = AutoBuiltinDouble(options[@"tolerance"], 12);
    size_t startX = (size_t)MAX(0, MIN((NSInteger)bitmap.width, (NSInteger)llround(AutoBuiltinDouble(region[@"x"], 0) * scale)));
    size_t startY = (size_t)MAX(0, MIN((NSInteger)bitmap.height, (NSInteger)llround(AutoBuiltinDouble(region[@"y"], 0) * scale)));
    size_t endX = (size_t)MAX(startX, MIN((NSInteger)bitmap.width, (NSInteger)llround((AutoBuiltinDouble(region[@"x"], 0) + AutoBuiltinDouble(region[@"width"], (CGFloat)bitmap.width / scale)) * scale)));
    size_t endY = (size_t)MAX(startY, MIN((NSInteger)bitmap.height, (NSInteger)llround((AutoBuiltinDouble(region[@"y"], 0) + AutoBuiltinDouble(region[@"height"], (CGFloat)bitmap.height / scale)) * scale)));
    NSDictionary *found = nil;
    NSUInteger candidates = 0;
    for (size_t y = startY; y < endY && !found; y++) {
        const uint8_t *row = bitmap.bytes + y * bitmap.bytesPerRow;
        for (size_t x = startX; x < endX && !found; x++) {
            const uint8_t *pixel = row + x * 4;
            if (fabs((double)pixel[0] - anchorRed) > tolerance ||
                fabs((double)pixel[1] - anchorGreen) > tolerance ||
                fabs((double)pixel[2] - anchorBlue) > tolerance) continue;
            BOOL offsetsMatch = YES;
            for (NSDictionary *offset in offsets) {
                size_t offsetX = x + (size_t)MAX(0, llround(AutoBuiltinDouble(offset[@"dx"], 0) * scale));
                size_t offsetY = y + (size_t)MAX(0, llround(AutoBuiltinDouble(offset[@"dy"], 0) * scale));
                if (offsetX >= bitmap.width || offsetY >= bitmap.height) { offsetsMatch = NO; break; }
                uint8_t expectedRed = 0, expectedGreen = 0, expectedBlue = 0;
                if (!AutoBuiltinParseColor(offset[@"color"], &expectedRed, &expectedGreen, &expectedBlue)) { offsetsMatch = NO; break; }
                const uint8_t *offsetPixel = bitmap.bytes + offsetY * bitmap.bytesPerRow + offsetX * 4;
                if (fabs((double)offsetPixel[0] - expectedRed) > tolerance ||
                    fabs((double)offsetPixel[1] - expectedGreen) > tolerance ||
                    fabs((double)offsetPixel[2] - expectedBlue) > tolerance) { offsetsMatch = NO; break; }
            }
            if (offsetsMatch) {
                found = AutoBuiltinPixelColorResult(pixel, (CGFloat)x / scale, (CGFloat)y / scale);
                break;
            }
            candidates += 1;
            if (candidates > AutoBuiltinMaxColorCandidates) break;
        }
    }
    AutoBuiltinBitmapFree(&bitmap);
    return found;
}

- (NSDictionary *)findImageAtPath:(NSString *)templatePath options:(NSDictionary *)options error:(NSError **)error {
    options = [options isKindOfClass:NSDictionary.class] ? options : @{};
    NSData *templateData = [NSData dataWithContentsOfFile:templatePath
                                                  options:NSDataReadingMappedIfSafe
                                                    error:nil];
    if (templateData.length == 0 || templateData.length > AutoBuiltinMaxTemplateBytes) {
        if (error) *error = AutoBuiltinError(AutoSDKErrorAutomationFailed,
            @"Built-in adapter: unable to read the image template (missing or larger than 8 MB).");
        return nil;
    }
    AutoBuiltinBitmap needle;
    if (!AutoBuiltinBitmapFromPNGData(templateData, &needle)) {
        if (error) *error = AutoBuiltinError(AutoSDKErrorAutomationFailed,
            @"Built-in adapter: unable to decode the image template.");
        return nil;
    }
    NSData *png = [self screenPNGWithOptions:options error:error];
    if (!png) { AutoBuiltinBitmapFree(&needle); return nil; }
    AutoBuiltinBitmap hay;
    if (!AutoBuiltinBitmapFromPNGData(png, &hay)) {
        AutoBuiltinBitmapFree(&needle);
        if (error) *error = AutoBuiltinError(AutoSDKErrorAutomationFailed,
            @"Built-in adapter: unable to decode screenshot bitmap.");
        return nil;
    }
    CGFloat scale = UIScreen.mainScreen.scale > 0 ? UIScreen.mainScreen.scale : 1;
    size_t minX = 0, minY = 0, maxX = hay.width, maxY = hay.height;
    NSDictionary *region = [options[@"region"] isKindOfClass:NSDictionary.class] ? options[@"region"] : nil;
    if (region) {
        CGFloat rx = [region[@"x"] doubleValue] * scale, ry = [region[@"y"] doubleValue] * scale;
        CGFloat rw = [region[@"width"] doubleValue] * scale, rh = [region[@"height"] doubleValue] * scale;
        if (rw > 0 && rh > 0) {
            minX = (size_t)MAX(0, (NSInteger)floor(rx));
            minY = (size_t)MAX(0, (NSInteger)floor(ry));
            maxX = MIN(hay.width, (size_t)ceil(rx + rw));
            maxY = MIN(hay.height, (size_t)ceil(ry + rh));
        }
    }
    double threshold = [options[@"similarity"] respondsToSelector:@selector(doubleValue)] ? [options[@"similarity"] doubleValue] :
                       ([options[@"threshold"] respondsToSelector:@selector(doubleValue)] ? [options[@"threshold"] doubleValue] : 0.9);
    threshold = MIN(1.0, MAX(0.5, threshold));
    NSUInteger maxCandidates = [options[@"maxCandidates"] respondsToSelector:@selector(unsignedIntegerValue)] ? [options[@"maxCandidates"] unsignedIntegerValue] : AutoBuiltinDefaultImageCandidates;
    maxCandidates = MAX(1, MIN(maxCandidates, AutoBuiltinMaxImageCandidates));
    NSDictionary *result = @{ @"found": @NO };
    if (needle.width > 0 && needle.height > 0 &&
        needle.width <= (maxX - minX) && needle.height <= (maxY - minY)) {
        size_t step = (size_t)MAX(2, (NSInteger)llround(3 * scale));
        NSUInteger comparisons = 0;
        BOOL matched = NO;
        double matchedSim = 0; size_t matchedX = 0, matchedY = 0;
        for (size_t py = minY; py + needle.height <= maxY && !matched && comparisons < AutoBuiltinMaxImageComparisons; py += step) {
            for (size_t px = minX; px + needle.width <= maxX && !matched; px += step) {
                NSUInteger coarseMatch = 0, coarseTotal = 0;
                for (size_t ty = 0; ty < needle.height; ty += step) {
                    const uint8_t *nrow = needle.bytes + ty * needle.bytesPerRow;
                    const uint8_t *hrow = hay.bytes + (py + ty) * hay.bytesPerRow + px * 4;
                    for (size_t tx = 0; tx < needle.width; tx += step) {
                        const uint8_t *n = nrow + tx * 4;
                        const uint8_t *h = hrow + tx * 4;
                        if (abs((int)n[0] - (int)h[0]) <= 24 && abs((int)n[1] - (int)h[1]) <= 24 &&
                            abs((int)n[2] - (int)h[2]) <= 24) coarseMatch += 1;
                        coarseTotal += 1;
                        if (++comparisons >= AutoBuiltinMaxImageComparisons) break;
                    }
                    if (comparisons >= AutoBuiltinMaxImageComparisons) break;
                }
                if (comparisons >= AutoBuiltinMaxImageComparisons) break;
                if (coarseTotal > 0 && (double)coarseMatch / (double)coarseTotal >= threshold - 0.1) {
                    NSUInteger fineMatch = 0, fineTotal = 0;
                    BOOL stillPossible = YES;
                    for (size_t ty = 0; ty < needle.height && stillPossible; ty++) {
                        const uint8_t *nrow = needle.bytes + ty * needle.bytesPerRow;
                        const uint8_t *hrow = hay.bytes + (py + ty) * hay.bytesPerRow + px * 4;
                        for (size_t tx = 0; tx < needle.width; tx++) {
                            const uint8_t *n = nrow + tx * 4;
                            const uint8_t *h = hrow + tx * 4;
                            if (abs((int)n[0] - (int)h[0]) <= 24 && abs((int)n[1] - (int)h[1]) <= 24 &&
                                abs((int)n[2] - (int)h[2]) <= 24) fineMatch += 1;
                            fineTotal += 1;
                            if (++comparisons >= AutoBuiltinMaxImageComparisons) { stillPossible = NO; break; }
                            if (fineTotal > 1024 && (double)fineMatch / (double)fineTotal < threshold - 0.05) { stillPossible = NO; break; }
                        }
                    }
                    double fineSim = fineTotal > 0 ? (double)fineMatch / (double)fineTotal : 0;
                    if (stillPossible && fineSim >= threshold) {
                        matched = YES; matchedSim = fineSim; matchedX = px; matchedY = py;
                    }
                }
            }
        }
        if (matched) {
            result = @{ @"found": @YES,
                        @"x": @(matchedX / scale), @"y": @(matchedY / scale),
                        @"width": @(needle.width / scale), @"height": @(needle.height / scale),
                        @"centerX": @((matchedX + needle.width / 2.0) / scale),
                        @"centerY": @((matchedY + needle.height / 2.0) / scale),
                        @"similarity": @(matchedSim) };
        }
    }
    AutoBuiltinBitmapFree(&needle);
    AutoBuiltinBitmapFree(&hay);
    return result;
}

- (NSArray<NSDictionary<NSString *, id> *> *)ocrInRegion:(NSDictionary *)region error:(NSError **)error {
    NSData *png = [self screenPNGWithOptions:region error:error];
    if (!png) return nil;
    CGImageSourceRef source = CGImageSourceCreateWithData((CFDataRef)png, NULL);
    if (!source) {
        if (error) *error = AutoBuiltinError(AutoSDKErrorAutomationFailed, @"Built-in adapter: unable to decode screenshot for OCR.");
        return nil;
    }
    CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
    CFRelease(source);
    if (!image) {
        if (error) *error = AutoBuiltinError(AutoSDKErrorAutomationFailed, @"Built-in adapter: unable to prepare OCR image.");
        return nil;
    }
    CGFloat scale = UIScreen.mainScreen.scale > 0 ? UIScreen.mainScreen.scale : 1;
    CGImageRef requestImage = image;
    CGRect cropPoints = CGRectMake(AutoBuiltinDouble(region[@"x"], 0), AutoBuiltinDouble(region[@"y"], 0),
                                   AutoBuiltinDouble(region[@"width"], 0), AutoBuiltinDouble(region[@"height"], 0));
    if (cropPoints.size.width > 0 && cropPoints.size.height > 0) {
        CGRect cropPixels = CGRectMake(cropPoints.origin.x * scale, cropPoints.origin.y * scale,
                                       cropPoints.size.width * scale, cropPoints.size.height * scale);
        CGRect imageBounds = CGRectMake(0, 0, (CGFloat)CGImageGetWidth(image), (CGFloat)CGImageGetHeight(image));
        cropPixels = CGRectIntersection(cropPixels, imageBounds);
        if (!CGRectIsNull(cropPixels) && !CGRectIsEmpty(cropPixels)) {
            CGImageRef cropped = CGImageCreateWithImageInRect(image, cropPixels);
            if (cropped) {
                CGImageRelease(image);
                requestImage = cropped;
            }
        }
    }
    VNRecognizeTextRequest *request = [[VNRecognizeTextRequest alloc] init];
    request.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
    request.usesLanguageCorrection = NO;
    NSError *visionError = nil;
    size_t requestWidth = CGImageGetWidth(requestImage);
    size_t requestHeight = CGImageGetHeight(requestImage);
    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:requestImage options:@{}];
    BOOL ran = [handler performRequests:@[request] error:&visionError];
    CGImageRelease(requestImage);
    if (!ran) {
        if (error) *error = AutoBuiltinError(AutoSDKErrorAutomationFailed,
            visionError.localizedDescription ?: @"Built-in adapter: Vision OCR failed.");
        return nil;
    }
    NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
    for (VNRecognizedTextObservation *observation in request.results) {
        if (items.count >= AutoBuiltinMaxOCRItems) break;
        VNRecognizedText *candidate = [observation topCandidates:1].firstObject;
        if (candidate.string.length == 0) continue;
        CGRect box = observation.boundingBox; /* normalized, bottom-left origin */
        CGFloat pointX = cropPoints.origin.x + box.origin.x * cropPoints.size.width;
        CGFloat pointY = cropPoints.origin.y + (1.0 - box.origin.y - box.size.height) * cropPoints.size.height;
        CGFloat pointWidth = box.size.width * cropPoints.size.width;
        CGFloat pointHeight = box.size.height * cropPoints.size.height;
        [items addObject:@{ @"text": candidate.string,
                            @"confidence": @(candidate.confidence),
                            @"x": @(pointX), @"y": @(pointY),
                            @"width": @(pointWidth), @"height": @(pointHeight),
                            @"centerX": @(pointX + pointWidth / 2.0),
                            @"centerY": @(pointY + pointHeight / 2.0) }];
    }
    return items;
}

#pragma mark Capabilities

- (NSDictionary<NSString *, id> *)capabilities {
    BOOL touchReady = [AutoBuiltinTouchEngine sharedEngine].isReady;
    BOOL axReady = [AutoBuiltinAccessibilityEngine sharedEngine].isAvailable;
    BOOL appListReady = NSClassFromString(@"LSApplicationWorkspace") != nil;
    BOOL appControlReady = AutoBuiltinSymbol(AutoBuiltinFrameworkSpringBoardServices, "SBSLaunchApplicationWithIdentifier") != NULL;
    BOOL systemActionsReady = AutoBuiltinSymbol(AutoBuiltinFrameworkSpringBoardServices, "SBSLockDevice") != NULL &&
        AutoBuiltinSymbol(AutoBuiltinFrameworkSpringBoardServices, "SBSOpenSensitiveURLAndUnlock") != NULL;
    return @{ @"scope": @"systemWide",
              @"adapter": @"builtin",
              @"requiresMainThread": @NO,
              @"handlesVisualOperationThreads": @YES,
              @"crossApp": @YES,
              @"realTouchInjection": @(touchReady),
              @"click": @(touchReady),
              @"coordinateActivation": @(touchReady),
              @"doubleActivation": @(touchReady),
              @"longClick": @(touchReady),
              @"swipeScroll": @(touchReady),
              @"multiTouch": @(touchReady),
              @"nodes": @(axReady),
              @"xpathSubset": @(axReady),
              @"stableNodeHandles": @NO,
              @"screenshot": @YES,
              @"findColor": @YES,
              @"multiColor": @YES,
              @"findImage": @YES,
              @"opencv": @NO,
              @"ocr": @YES,
              @"appList": @(appListReady),
              @"appLifecycle": @(appControlReady),
              @"systemActions": @(systemActionsReady),
              @"note": @"Built-in no-WDA mode requires a TrollStore/enterprise-signed host app for system-wide operation." };
}

@end
