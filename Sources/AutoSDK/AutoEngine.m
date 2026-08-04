#import "include/AutoEngine.h"
#import "include/AutoDebugServer.h"
#import "include/AutoSDKError.h"
#import "AutoScriptSupport.h"
#import "AutoBootstrapScript.h"
#import "AutoHTTPSupport.h"
#import <JavaScriptCore/JavaScriptCore.h>
#import <UIKit/UIKit.h>
#import <Photos/Photos.h>
#import <ImageIO/ImageIO.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <mach/mach.h>
#include <math.h>

@protocol AutoJSExport <JSExport>
- (id)invokeClick:(JSValue *)selector;
- (id)invokeClickPoint:(JSValue *)payload;
- (id)invokeDoubleClickPoint:(JSValue *)payload;
- (id)invokeLongClick:(JSValue *)payload;
- (id)invokeSwipe:(JSValue *)payload;
- (id)invokeInput:(JSValue *)payload;
- (id)invokeSleep:(NSNumber *)milliseconds;
- (id)invokeGetText:(JSValue *)selector;
- (id)invokeScreenshot;
- (id)invokeFindImage:(JSValue *)payload;
- (id)invokeFindColor:(JSValue *)payload;
- (id)invokePixelColor:(JSValue *)payload;
- (id)invokeCompareColors:(JSValue *)payload;
- (id)invokeFindMultiColor:(JSValue *)payload;
- (id)invokeHTTP:(JSValue *)payload;
- (id)invokeOCR:(JSValue *)region;
- (id)invokeExists:(JSValue *)selector;
- (id)invokeFindElement:(JSValue *)selector;
- (id)invokeFindElements:(JSValue *)selector;
- (id)invokeWaitFor:(JSValue *)payload;
- (id)invokeGetAttribute:(JSValue *)payload;
- (id)invokeGetBounds:(JSValue *)selector;
- (id)invokeGetChildren:(JSValue *)selector;
- (id)invokeGetParent:(JSValue *)selector;
- (id)invokeScrollIntoView:(JSValue *)selector;
- (id)invokeFile:(JSValue *)payload;
- (id)invokeStorage:(JSValue *)payload;
- (id)invokeDevice:(JSValue *)payload;
- (id)invokeMedia:(JSValue *)payload;
- (id)invokeCapabilities;
- (id)invokeApp:(JSValue *)payload;
- (id)invokeTouch:(JSValue *)payload;
- (BOOL)invokeIsStopped;
- (id)invokeNative:(JSValue *)payload;
@end

@protocol AutoConsoleExport <JSExport>
- (void)log:(JSValue *)value;
- (void)warn:(JSValue *)value;
- (void)error:(JSValue *)value;
@end

@class AutoEngine;

@interface AutoJSBridge : NSObject <AutoJSExport>
@property (nonatomic, weak) AutoEngine *engine;
@property (nonatomic, strong) id<AutoAutomationAdapter> adapter;
@property (nonatomic, copy) NSDictionary *config;
@property (nonatomic, strong) NSError *lastError;
@end

@interface AutoJSConsole : NSObject <AutoConsoleExport>
@property (nonatomic, strong) NSMutableArray<NSDictionary<NSString *, id> *> *entries;
@property (nonatomic, assign) BOOL emitToSystemLog;
@property (nonatomic, assign) NSUInteger maximumEntries;
@property (nonatomic, assign) NSUInteger maximumMessageLength;
@property (nonatomic, assign) NSUInteger maximumTotalBytes;
@property (nonatomic, assign) NSUInteger retainedMessageBytes;
@end


@interface AutoMainThreadAdapterProxy : NSProxy
@property (nonatomic, strong) id target;
@property (atomic, strong, nullable) NSDictionary *cachedCapabilities;
@property (atomic, assign) BOOL capabilitiesLoaded;
+ (instancetype)proxyWithTarget:(id)target;
@end

@interface AutoEngine ()
@property (nonatomic, readwrite, getter=isRunning) BOOL running;
@property (atomic, copy) NSDictionary *config;
@property (atomic, copy) NSArray<Class> *urlProtocolClasses;
@property (atomic, strong) id<AutoAutomationAdapter> adapter;
@property (nonatomic, strong) id<AutoAutomationAdapter> activeAdapter;
@property (nonatomic, strong) NSMutableDictionary<NSString *, AutoNativeMethodHandler> *nativeMethods;
@property (nonatomic, strong) NSURLSessionTask *scriptTask;
@property (nonatomic, strong) AutoDebugServer *debugServer;
@property (nonatomic, copy) NSDictionary *debugServerConfiguration;
@property (nonatomic, assign) BOOL debugServerStarting;
@property (nonatomic, assign) NSUInteger debugServerGeneration;
@property (nonatomic, strong) NSMutableArray *debugServerStartCompletions;
@property (nonatomic, strong) dispatch_queue_t debugServerQueue;
@property (nonatomic, strong) dispatch_queue_t scriptQueue;
@property (nonatomic, strong) dispatch_queue_t debugAdapterQueue;
@property (nonatomic, assign) BOOL stopRequested;
- (void)loadScript:(NSString *)value config:(NSDictionary *)config completion:(void (^)(NSString * _Nullable source, NSError * _Nullable error))completion;
- (void)evaluateScript:(NSString *)source config:(NSDictionary *)config adapter:(id<AutoAutomationAdapter>)adapter completion:(AutoScriptCompletion)completion;
- (void)finishWithResult:(NSDictionary * _Nullable)result error:(NSError * _Nullable)error completion:(AutoScriptCompletion)completion;
- (BOOL)shouldStop;
- (void)requestStop;
- (void)handleDebugRequest:(NSDictionary<NSString *, id> *)request response:(AutoDebugResponseHandler)response;
- (NSDictionary<NSString *, id> *)capabilityInfo;
- (void)performDebugAdapterBlock:(dispatch_block_t)block;
@end

static void *AutoDebugServerQueueKey = &AutoDebugServerQueueKey;

static void AutoDispatchDebugServerCompletions(NSArray *callbacks, NSError *error) {
    if (callbacks.count == 0) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        for (id callbackValue in callbacks) {
            void (^callback)(NSError *) = callbackValue;
            callback(error);
        }
    });
}

static NSError *AutoMakeError(AutoSDKErrorCode code, NSString *message, NSError * _Nullable underlying) {
    NSMutableDictionary *info = [@{NSLocalizedDescriptionKey: message} mutableCopy];
    if (underlying) info[NSUnderlyingErrorKey] = underlying;
    return [NSError errorWithDomain:AutoSDKErrorDomain code:code userInfo:info];
}

// Pumps the current run loop for at most duration seconds. The script
// thread's run loop usually has no sources (JavaScriptCore's modern execution
// time limit is dispatched on a GCD queue), so runMode: returns immediately
// and a naive pump would busy-spin a CPU core. When no source was serviced,
// fall back to a real thread sleep for the remainder of the slice.
static void AutoPumpRunLoopWithSleepFallback(NSTimeInterval duration) {
    if (duration <= 0) return;
    NSDate *sliceStart = [NSDate date];
    BOOL handled = [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                             beforeDate:[NSDate dateWithTimeIntervalSinceNow:duration]];
    if (!handled) {
        NSTimeInterval elapsed = -[sliceStart timeIntervalSinceNow];
        NSTimeInterval sleepRemainder = duration - elapsed;
        if (sleepRemainder > 0.001) {
            [NSThread sleepForTimeInterval:sleepRemainder];
        }
    }
}

// Bounds the Objective-C copy of a script's evaluated result so a script
// cannot force an unbounded bridge allocation (e.g. `new Array(1e8)`).
// Oversized top-level arrays and strings are detected before conversion;
// oversized nested nodes are replaced during the walk. Replaced nodes carry
// an `__autosdkTruncated` marker dictionary.
static const NSUInteger AutoMaxResultDepth = 24;
static const NSUInteger AutoMaxResultNodes = 50000;
static const NSUInteger AutoMaxResultStringLength = 1024 * 1024;

static id AutoBoundedResultObject(id object, NSUInteger depth);

static id AutoBoundedJSResult(JSValue *value) {
    if (!value || value.isUndefined || value.isNull) return [NSNull null];
    @try {
        if (value.isArray) {
            double length = [value[@"length"] toDouble];
            if (isfinite(length) && length > (double)AutoMaxResultNodes) {
                return @{ @"__autosdkTruncated": @YES, @"reason": @"elementCount", @"count": @((NSUInteger)length) };
            }
        } else if (value.isString) {
            double length = [value[@"length"] toDouble];
            if (isfinite(length) && length > (double)AutoMaxResultStringLength) {
                return @{ @"__autosdkTruncated": @YES, @"reason": @"stringLength", @"length": @((NSUInteger)length) };
            }
        }
    } @catch (__unused NSException *exception) {
        // Exotic values fall through to the post-conversion walk.
    }
    return AutoBoundedResultObject([value toObject] ?: [NSNull null], 0);
}

static id AutoBoundedResultObject(id object, NSUInteger depth) {
    if (depth > AutoMaxResultDepth) {
        return @{ @"__autosdkTruncated": @YES, @"reason": @"maxDepth", @"depth": @(depth - 1) };
    }
    if ([object isKindOfClass:NSString.class]) {
        NSString *string = object;
        if (string.length <= AutoMaxResultStringLength) return string;
        return @{ @"__autosdkTruncated": @YES, @"reason": @"stringLength", @"length": @(string.length) };
    }
    if ([object isKindOfClass:NSArray.class]) {
        NSArray *array = object;
        if (array.count > AutoMaxResultNodes) {
            return @{ @"__autosdkTruncated": @YES, @"reason": @"elementCount", @"count": @(array.count) };
        }
        NSMutableArray *bounded = [NSMutableArray arrayWithCapacity:array.count];
        for (id item in array) [bounded addObject:AutoBoundedResultObject(item, depth + 1)];
        return bounded;
    }
    if ([object isKindOfClass:NSDictionary.class]) {
        NSDictionary *dictionary = object;
        if (dictionary.count > AutoMaxResultNodes) {
            return @{ @"__autosdkTruncated": @YES, @"reason": @"entryCount", @"count": @(dictionary.count) };
        }
        NSMutableDictionary *bounded = [NSMutableDictionary dictionaryWithCapacity:dictionary.count];
        for (id key in dictionary) {
            if ([key isKindOfClass:NSString.class]) bounded[key] = AutoBoundedResultObject(dictionary[key], depth + 1);
        }
        return bounded;
    }
    return object;
}

static BOOL AutoHTTPHeaderNameIsValid(NSString *name) {
    if (name.length == 0) return NO;
    for (NSUInteger index = 0; index < name.length; index++) {
        unichar character = [name characterAtIndex:index];
        BOOL alphaNumeric = (character >= 'A' && character <= 'Z') ||
                            (character >= 'a' && character <= 'z') ||
                            (character >= '0' && character <= '9');
        BOOL tokenPunctuation = [@"!#$%&'*+-.^_`|~" rangeOfString:[NSString stringWithFormat:@"%C", character]].location != NSNotFound;
        if (!alphaNumeric && !tokenPunctuation) return NO;
    }
    return YES;
}

static BOOL AutoScriptValueLooksLikeURL(NSString *value) {
    NSRange separator = [value rangeOfString:@"://"];
    if (separator.location == NSNotFound || separator.location == 0) return NO;
    unichar first = [value characterAtIndex:0];
    BOOL firstIsLetter = (first >= 'A' && first <= 'Z') || (first >= 'a' && first <= 'z');
    if (!firstIsLetter) return NO;
    for (NSUInteger index = 1; index < separator.location; index++) {
        unichar character = [value characterAtIndex:index];
        BOOL valid = (character >= 'A' && character <= 'Z') ||
                     (character >= 'a' && character <= 'z') ||
                     (character >= '0' && character <= '9') ||
                     character == '+' || character == '-' || character == '.';
        if (!valid) return NO;
    }
    return YES;
}

static id AutoJSObject(JSValue *value) {
    if (!value || value.isUndefined || value.isNull) return [NSNull null];
    id object = [value toObject];
    return object ?: [NSNull null];
}

static NSDictionary *AutoPayload(JSValue *value) {
    id object = AutoJSObject(value);
    return [object isKindOfClass:NSDictionary.class] ? object : @{};
}

static BOOL AutoFiniteNumber(id value) {
    return [value isKindOfClass:NSNumber.class] && isfinite([value doubleValue]);
}

static BOOL AutoBoolean(id value, BOOL defaultValue) {
    return [value isKindOfClass:NSNumber.class] ? [value boolValue] : defaultValue;
}

static BOOL AutoPermission(NSDictionary *config, NSString *key, BOOL defaultValue) {
    id value = config[key];
    return value == nil ? defaultValue : AutoBoolean(value, NO);
}

static double AutoFiniteDouble(id value, double defaultValue) {
    return AutoFiniteNumber(value) ? [value doubleValue] : defaultValue;
}

static NSUInteger AutoBoundedPositiveInteger(id value,
                                             NSUInteger defaultValue,
                                             NSUInteger maximum) {
    double number = AutoFiniteDouble(value, 0);
    if (number <= 0 || number > (double)NSUIntegerMax) return defaultValue;
    return MIN((NSUInteger)number, maximum);
}

static NSArray<NSString *> *AutoValidatedHostAllowlist(id value,
                                                       BOOL *configured,
                                                       NSError **error) {
    if (configured) *configured = NO;
    if (value == nil) return @[];
    if (![value isKindOfClass:NSArray.class]) {
        if (error) *error = AutoMakeError(AutoSDKErrorInvalidConfiguration,
                                          @"Network host allowlists must be arrays of host strings.", nil);
        return nil;
    }
    NSArray *values = value;
    if (values.count == 0) return @[];
    if (configured) *configured = YES;
    if (values.count > 256) {
        if (error) *error = AutoMakeError(AutoSDKErrorInvalidConfiguration,
                                          @"Network host allowlists accept at most 256 hosts.", nil);
        return nil;
    }
    NSMutableArray<NSString *> *hosts = [NSMutableArray arrayWithCapacity:values.count];
    NSCharacterSet *invalidCharacters = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    for (id valueItem in values) {
        if (![valueItem isKindOfClass:NSString.class] || [valueItem length] == 0 ||
            [valueItem length] > 253 ||
            [valueItem rangeOfCharacterFromSet:invalidCharacters].location != NSNotFound ||
            [valueItem rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) {
            if (error) *error = AutoMakeError(AutoSDKErrorInvalidConfiguration,
                                              @"Network host allowlists contain an invalid host.", nil);
            return nil;
        }
        [hosts addObject:[valueItem copy]];
    }
    return [hosts copy];
}

static NSDictionary *AutoImmutableConfigSnapshot(NSDictionary *config) {
    if (![config isKindOfClass:NSDictionary.class]) return @{};
    NSMutableDictionary *snapshot = [NSMutableDictionary dictionaryWithCapacity:config.count];
    [config enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
        if (![key isKindOfClass:NSString.class] || !value) return;
        if ([value isKindOfClass:NSArray.class] || [value isKindOfClass:NSDictionary.class] ||
            [value isKindOfClass:NSSet.class] || [value isKindOfClass:NSString.class] ||
            [value isKindOfClass:NSData.class]) {
            snapshot[key] = [value copy];
        } else {
            snapshot[key] = value;
        }
        (void)stop;
    }];
    return [snapshot copy];
}

static BOOL AutoPayloadHasFiniteNumbers(NSDictionary *payload, NSArray<NSString *> *keys) {
    for (NSString *key in keys) if (!AutoFiniteNumber(payload[key])) return NO;
    return YES;
}

static NSUInteger AutoScreenshotByteLimit(NSDictionary *config) {
    double configuredValue = AutoFiniteNumber(config[@"maxScreenshotBytes"])
        ? [config[@"maxScreenshotBytes"] doubleValue]
        : 0;
    NSUInteger configured = configuredValue > 0 && configuredValue <= (double)NSUIntegerMax
        ? (NSUInteger)configuredValue
        : 0;
    return configured > 0 ? MIN(configured, (NSUInteger)(20 * 1024 * 1024)) : (NSUInteger)(16 * 1024 * 1024);
}

static const NSUInteger AutoDebugTemplateByteLimit = 512 * 1024;
static const NSUInteger AutoSystemClipboardByteLimit = 1024 * 1024;

// RFC 3986 scheme validation: http(s) always passes; known dangerous schemes
// are rejected; anything else must be a legal custom scheme (ALPHA *( ALPHA /
// DIGIT / "+" / "-" / "." )).
static BOOL AutoSystemURLSchemeAllowed(NSURL *url) {
    if (!url || url.scheme.length == 0 || url.scheme.length > 64) return NO;
    NSString *scheme = url.scheme.lowercaseString;
    if ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) return YES;
    NSSet *blocked = [NSSet setWithArray:@[@"file", @"data", @"javascript", @"about", @"ftp", @"ws", @"wss", @"itms-services"]];
    if ([blocked containsObject:scheme]) return NO;
    unichar first = [scheme characterAtIndex:0];
    if (!((first >= 'a' && first <= 'z') || (first >= 'A' && first <= 'Z'))) return NO;
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+-."];
    return [scheme rangeOfCharacterFromSet:allowed.invertedSet].location == NSNotFound;
}
static UILabel *AutoActiveToastLabel;
static void AutoShowToast(NSString *message) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ AutoShowToast(message); });
        return;
    }
    UIWindow *window = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            if (windowScene.activationState != UISceneActivationStateForegroundActive) continue;
            window = windowScene.windows.firstObject;
            if (window) break;
        }
    }
    if (!window) window = UIApplication.sharedApplication.keyWindow;
    UIView *container = window.rootViewController.view ?: window;
    if (!container) return;
    if (AutoActiveToastLabel) {
        [AutoActiveToastLabel.layer removeAllAnimations];
        [AutoActiveToastLabel removeFromSuperview];
        AutoActiveToastLabel = nil;
    }
    UILabel *label = [UILabel new];
    label.text = message;
    label.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    label.textColor = UIColor.whiteColor;
    label.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.75];
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;
    label.layer.cornerRadius = 10;
    label.clipsToBounds = YES;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
        [label.bottomAnchor constraintEqualToAnchor:container.safeAreaLayoutGuide.bottomAnchor constant:-56],
        [label.leadingAnchor constraintGreaterThanOrEqualToAnchor:container.leadingAnchor constant:20],
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:container.trailingAnchor constant:-20]
    ]];
    AutoActiveToastLabel = label;
    label.alpha = 0;
    [UIView animateWithDuration:0.15 animations:^{ label.alpha = 1; } completion:^(BOOL finished) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.25 animations:^{ label.alpha = 0; } completion:^(BOOL finished) {
                if (AutoActiveToastLabel == label) AutoActiveToastLabel = nil;
                [label removeFromSuperview];
            }];
        });
    }];
}

static const NSUInteger AutoDebugScriptByteLimit = 768 * 1024;
static const NSUInteger AutoDebugProtocolVersion = 2;
static const NSUInteger AutoDebugDefaultNodeLimit = 500;
static const NSUInteger AutoDebugMaximumNodeLimit = 2000;

static NSUInteger AutoConfiguredByteLimit(NSDictionary *config,
                                           NSString *key,
                                           NSUInteger defaultValue,
                                           NSUInteger hardMaximum) {
    id rawValue = [config isKindOfClass:NSDictionary.class] ? config[key] : nil;
    double number = AutoFiniteNumber(rawValue) ? [rawValue doubleValue] : 0;
    if (number <= 0 || number > (double)NSUIntegerMax) return defaultValue;
    return MIN((NSUInteger)number, hardMaximum);
}

static id AutoValueOnMainThread(id (^block)(void)) {
    if (!block) return nil;
    if (NSThread.isMainThread) return block();
    __block id value = nil;
    dispatch_sync(dispatch_get_main_queue(), ^{ value = block(); });
    return value;
}

static NSUInteger AutoMediaFileByteLimit(NSDictionary *config) {
    return AutoConfiguredByteLimit(config, @"maxMediaBytes",
                                   512 * 1024 * 1024, (NSUInteger)(2ull * 1024 * 1024 * 1024));
}

static NSUInteger AutoMediaImageByteLimit(NSDictionary *config) {
    return AutoConfiguredByteLimit(config, @"maxMediaImageBytes",
                                   64 * 1024 * 1024, 256 * 1024 * 1024);
}

static NSURL *AutoMediaSourceURL(id pathValue, NSDictionary *config, NSError **error) {
    if (![pathValue isKindOfClass:NSString.class] || [pathValue length] == 0) {
        if (error) *error = AutoMakeError(AutoSDKErrorInvalidConfiguration,
                                          @"Media source path must not be empty.", nil);
        return nil;
    }
    NSError *resolveError = nil;
    id resolved = AutoScriptFileOperation(@{ @"operation": @"resolvePath", @"path": pathValue },
                                          config ?: @{}, &resolveError);
    if (![resolved isKindOfClass:NSString.class]) {
        if (error) *error = resolveError ?: AutoMakeError(AutoSDKErrorFileAccessDenied,
                                                          @"Unable to resolve the media source path.", nil);
        return nil;
    }
    NSError *attributesError = nil;
    NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:resolved error:&attributesError];
    if (![attributes[NSFileType] isEqualToString:NSFileTypeRegular]) {
        if (error) *error = AutoMakeError(AutoSDKErrorFileOperationFailed,
                                          @"Media source must be an existing regular file.", attributesError);
        return nil;
    }
    unsigned long long size = [attributes[NSFileSize] unsignedLongLongValue];
    if (size == 0 || size > AutoMediaFileByteLimit(config ?: @{})) {
        if (error) *error = AutoMakeError(AutoSDKErrorFileOperationFailed,
                                          @"Media source is empty or exceeds maxMediaBytes.", nil);
        return nil;
    }
    return [NSURL fileURLWithPath:resolved];
}

static BOOL AutoMediaImageURLIsValid(NSURL *url) {
    if (!url) return NO;
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    BOOL valid = source && CGImageSourceGetCount(source) > 0;
    if (source) CFRelease(source);
    return valid;
}

static BOOL AutoEnsurePhotoLibraryWriteAccess(AutoEngine *engine,
                                              NSDictionary *config,
                                              NSError **error) {
    PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelAddOnly];
    if (status == PHAuthorizationStatusAuthorized || status == PHAuthorizationStatusLimited) return YES;
    if (status == PHAuthorizationStatusDenied || status == PHAuthorizationStatusRestricted) {
        if (error) *error = AutoMakeError(AutoSDKErrorFileAccessDenied,
                                          @"Photo library write access was denied. Enable Photos access in Settings.", nil);
        return NO;
    }

    id usageDescription = [NSBundle.mainBundle objectForInfoDictionaryKey:@"NSPhotoLibraryAddUsageDescription"];
    if (![usageDescription isKindOfClass:NSString.class] || [usageDescription length] == 0) {
        if (error) *error = AutoMakeError(AutoSDKErrorInvalidConfiguration,
                                          @"NSPhotoLibraryAddUsageDescription is required to save media.", nil);
        return NO;
    }

    __block PHAuthorizationStatus requestedStatus = PHAuthorizationStatusNotDetermined;
    dispatch_semaphore_t finished = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_main_queue(), ^{
        [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly handler:^(PHAuthorizationStatus newStatus) {
            requestedStatus = newStatus;
            dispatch_semaphore_signal(finished);
        }];
    });

    double configuredTimeout = AutoFiniteDouble(config[@"photoAuthorizationTimeout"], 60);
    NSTimeInterval timeout = configuredTimeout > 0 ? MIN(configuredTimeout, 300.0) : 60.0;
    NSTimeInterval deadline = NSProcessInfo.processInfo.systemUptime + timeout;
    while (dispatch_semaphore_wait(finished, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC))) != 0) {
        if ([engine shouldStop]) {
            if (error) *error = AutoMakeError(AutoSDKErrorScriptCancelled, @"Script cancelled.", nil);
            return NO;
        }
        if (NSProcessInfo.processInfo.systemUptime >= deadline) {
            if (error) *error = AutoMakeError(AutoSDKErrorAutomationFailed,
                                              @"Timed out waiting for photo library authorization.", nil);
            return NO;
        }
    }
    if (requestedStatus == PHAuthorizationStatusAuthorized || requestedStatus == PHAuthorizationStatusLimited) return YES;
    if (error) *error = AutoMakeError(AutoSDKErrorFileAccessDenied,
                                      @"Photo library write access was denied. Enable Photos access in Settings.", nil);
    return NO;
}

static NSString *AutoDebugScriptName(id value) {
    if (![value isKindOfClass:NSString.class]) return nil;
    NSString *name = value;
    if (name.length == 0 || name.length > 128 || [name hasPrefix:@"."] ||
        ![name.pathExtension.lowercaseString isEqualToString:@"js"] ||
        ![name.lastPathComponent isEqualToString:name]) return nil;
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"];
    return [name rangeOfCharacterFromSet:allowed.invertedSet].location == NSNotFound ? name : nil;
}

static NSString *AutoDebugScriptPath(NSString *name) {
    return [@"debug-scripts" stringByAppendingPathComponent:name];
}

static NSString *AutoDebugAssetName(id value) {
    if (![value isKindOfClass:NSString.class]) return nil;
    NSString *name = value;
    NSSet *extensions = [NSSet setWithArray:@[@"png", @"jpg", @"jpeg"]];
    if (name.length == 0 || name.length > 128 || [name hasPrefix:@"."] ||
        ![extensions containsObject:name.pathExtension.lowercaseString] ||
        ![name.lastPathComponent isEqualToString:name]) return nil;
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"];
    return [name rangeOfCharacterFromSet:allowed.invertedSet].location == NSNotFound ? name : nil;
}

static NSString *AutoDebugAssetPath(NSString *name) {
    return [@"debug-assets" stringByAppendingPathComponent:name];
}

// The engine reuses one keep-alive NSURLSession for every invokeHTTP and
// remote-script request instead of creating a session per request, so TLS
// sessions and HTTP connections survive between calls. The default
// configuration (not ephemeral/background) is required so NSURLProtocol
// classes registered with +[NSURLProtocol registerClass:] still intercept
// requests; caches and cookies are explicitly disabled below. Redirect
// enforcement stays per-task through AutoHTTPRedirectRouter; the session
// itself is never invalidated per request.
static AutoHTTPRedirectRouter *AutoHTTPSharedRouter(void) {
    static AutoHTTPRedirectRouter *router = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ router = [AutoHTTPRedirectRouter new]; });
    return router;
}

static NSURLSession *AutoHTTPSharedSession(NSArray<Class> *protocolClasses) {
    static NSURLSession *session = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.defaultSessionConfiguration;
        configuration.URLCache = nil;
        configuration.URLCredentialStorage = nil;
        configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        configuration.HTTPCookieStorage = nil;
        configuration.timeoutIntervalForRequest = 120;
        configuration.timeoutIntervalForResource = 120;
        if ([protocolClasses isKindOfClass:NSArray.class] && protocolClasses.count > 0) {
            configuration.protocolClasses = protocolClasses;
        }
        NSOperationQueue *delegateQueue = [NSOperationQueue new];
        delegateQueue.maxConcurrentOperationCount = 1;
        delegateQueue.name = @"com.autosdk.http-session";
        session = [NSURLSession sessionWithConfiguration:configuration
                                                delegate:AutoHTTPSharedRouter()
                                           delegateQueue:delegateQueue];
    });
    return session;
}

// Builds and validates the NSURLRequest for one invokeHTTP call. All request
// sizing, header, method and body checks live here so the data and download
// paths share identical validation. Returns nil and fills *error on failure.
static NSURLRequest *AutoBuildHTTPRequest(NSDictionary *data, NSURL *url, NSDictionary *config, NSError **error) {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = [data[@"method"] isKindOfClass:NSString.class] ? [data[@"method"] uppercaseString] : @"GET";
    NSSet *methods = [NSSet setWithArray:@[@"GET", @"POST", @"PUT", @"PATCH", @"DELETE", @"HEAD", @"OPTIONS"]];
    if (![methods containsObject:request.HTTPMethod]) {
        if (error) *error = AutoMakeError(AutoSDKErrorNetworkFailed, @"Unsupported HTTP method.", nil);
        return nil;
    }
    double timeoutMilliseconds = AutoFiniteDouble(data[@"timeout"], 0);
    NSTimeInterval timeout = (isfinite(timeoutMilliseconds) && timeoutMilliseconds > 0)
        ? MIN(timeoutMilliseconds / 1000.0, 120.0)
        : 30.0;
    request.timeoutInterval = timeout;
    NSUInteger maximumRequestBytes = AutoConfiguredByteLimit(config, @"maxHTTPRequestBytes",
                                                            10 * 1024 * 1024, 64 * 1024 * 1024);
    if ([data[@"headers"] isKindOfClass:NSDictionary.class]) {
        NSDictionary *requestHeaders = data[@"headers"];
        if (requestHeaders.count > 128) {
            if (error) *error = AutoMakeError(AutoSDKErrorNetworkFailed, @"HTTP requests accept at most 128 headers.", nil);
            return nil;
        }
        for (id rawKey in requestHeaders) {
            id value = requestHeaders[rawKey];
            if (![rawKey isKindOfClass:NSString.class] || [(NSString *)rawKey length] == 0 || [(NSString *)rawKey length] > 256 ||
                !AutoHTTPHeaderNameIsValid(rawKey) || ![value isKindOfClass:NSString.class] || [(NSString *)value length] > 8192 ||
                [rawKey rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound ||
                [value rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) {
                if (error) *error = AutoMakeError(AutoSDKErrorNetworkFailed, @"HTTP header names or values are invalid or too long.", nil);
                return nil;
            }
            [request setValue:value forHTTPHeaderField:rawKey];
        }
    }
    id body = data[@"body"];
    NSString *bodyBase64 = [data[@"bodyBase64"] isKindOfClass:NSString.class] ? data[@"bodyBase64"] : nil;
    if (bodyBase64) {
        NSUInteger maximumEncodedLength = (maximumRequestBytes / 3) * 4 + 4;
        if (bodyBase64.length > maximumEncodedLength) {
            if (error) *error = AutoMakeError(AutoSDKErrorNetworkFailed, @"Request body exceeds maxHTTPRequestBytes.", nil);
            return nil;
        }
        request.HTTPBody = [[NSData alloc] initWithBase64EncodedString:bodyBase64 options:0];
        if (!request.HTTPBody) {
            if (error) *error = AutoMakeError(AutoSDKErrorNetworkFailed, @"bodyBase64 is invalid.", nil);
            return nil;
        }
    } else if ([body isKindOfClass:NSString.class]) {
        if ([(NSString *)body lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > maximumRequestBytes) {
            if (error) *error = AutoMakeError(AutoSDKErrorNetworkFailed, @"Request body exceeds maxHTTPRequestBytes.", nil);
            return nil;
        }
        request.HTTPBody = [body dataUsingEncoding:NSUTF8StringEncoding];
    } else if ([body isKindOfClass:NSDictionary.class] || [body isKindOfClass:NSArray.class]) {
        NSError *bodyError = nil;
        @try {
            if (![NSJSONSerialization isValidJSONObject:body]) {
                if (error) *error = AutoMakeError(AutoSDKErrorNetworkFailed, @"Request body is not valid JSON.", nil);
                return nil;
            }
            request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:&bodyError];
        } @catch (NSException *exception) {
            if (error) *error = AutoMakeError(AutoSDKErrorNetworkFailed,
                                             exception.reason ?: @"Request body is not valid JSON.", nil);
            return nil;
        }
        if (bodyError) {
            if (error) *error = AutoMakeError(AutoSDKErrorNetworkFailed, @"Request body is not valid JSON.", bodyError);
            return nil;
        }
        if (![request valueForHTTPHeaderField:@"Content-Type"]) [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    }
    if (request.HTTPBody.length > maximumRequestBytes) {
        if (error) *error = AutoMakeError(AutoSDKErrorNetworkFailed, @"Request body exceeds maxHTTPRequestBytes.", nil);
        return nil;
    }
    return request;
}

@implementation AutoMainThreadAdapterProxy

+ (instancetype)proxyWithTarget:(id)target {
    AutoMainThreadAdapterProxy *proxy = [AutoMainThreadAdapterProxy alloc];
    proxy.target = target;
    return proxy;
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector {
    return [self.target methodSignatureForSelector:selector];
}

- (void)forwardInvocation:(NSInvocation *)invocation {
    id target = self.target;
    if (!target) return;
    [invocation retainArguments];
    SEL selector = invocation.selector;
    id<AutoAutomationAdapter> automationTarget = (id<AutoAutomationAdapter>)target;
    NSDictionary *capabilities = nil;
    if (!self.capabilitiesLoaded) {
        @synchronized (self) {
            if (!self.capabilitiesLoaded) {
                self.capabilitiesLoaded = YES;
                self.cachedCapabilities = [automationTarget respondsToSelector:@selector(capabilities)]
                    ? [automationTarget capabilities]
                    : nil;
            }
            capabilities = self.cachedCapabilities;
        }
    } else {
        capabilities = self.cachedCapabilities;
    }
    BOOL handlesVisualThreads = AutoBoolean(capabilities[@"handlesVisualOperationThreads"], NO);
    BOOL backgroundVisualOperation = handlesVisualThreads && (selector == @selector(screenshotWithError:) ||
        selector == @selector(findImageAtPath:options:error:) ||
        selector == @selector(findColor:region:options:error:) ||
        selector == @selector(pixelColorAtX:y:error:) ||
        selector == @selector(compareColors:options:error:) ||
        selector == @selector(findMultiColor:offsets:region:options:error:) ||
        selector == @selector(ocrInRegion:error:));
    if (NSThread.isMainThread || backgroundVisualOperation) {
        [invocation invokeWithTarget:target];
    } else {
        dispatch_sync(dispatch_get_main_queue(), ^{ [invocation invokeWithTarget:target]; });
    }
}

- (BOOL)respondsToSelector:(SEL)selector {
    return [self.target respondsToSelector:selector];
}

- (BOOL)conformsToProtocol:(Protocol *)protocol {
    return [self.target conformsToProtocol:protocol];
}

- (Class)class {
    return [self.target class];
}

@end

@implementation AutoJSBridge

- (id)failure:(NSError *)error {
    self.lastError = error;
    return @NO;
}

- (BOOL)ensureScriptRunning {
    if (![self.engine shouldStop]) {
        self.lastError = nil;
        return YES;
    }
    [self failure:AutoMakeError(AutoSDKErrorScriptCancelled, @"Script cancelled.", nil)];
    JSContext *context = JSContext.currentContext;
    if (context && !context.exception) {
        context.exception = [JSValue valueWithNewErrorFromMessage:@"Script cancelled." inContext:context];
    }
    return NO;
}

- (id)invokeClick:(JSValue *)selector {
    if (![self ensureScriptRunning]) return @NO;
    NSError *error = nil;
    BOOL ok = [self.adapter click:AutoJSObject(selector) error:&error];
    return ok ? @YES : [self failure:error ?: AutoMakeError(AutoSDKErrorAutomationFailed, @"Click failed.", nil)];
}

- (id)invokeClickPoint:(JSValue *)payload {
    if (![self ensureScriptRunning]) return @NO;
    if (![self.adapter respondsToSelector:@selector(clickAtX:y:error:)]) {
        return [self failure:AutoMakeError(AutoSDKErrorAutomationUnavailable, @"The automation adapter does not support coordinate clicks.", nil)];
    }
    NSDictionary *data = AutoPayload(payload);
    if (!AutoPayloadHasFiniteNumbers(data, @[@"x", @"y"])) {
        return [self failure:AutoMakeError(AutoSDKErrorInvalidConfiguration, @"clickPoint requires finite x and y values.", nil)];
    }
    NSError *error = nil;
    BOOL ok = [self.adapter clickAtX:[data[@"x"] doubleValue] y:[data[@"y"] doubleValue] error:&error];
    return ok ? @YES : [self failure:error ?: AutoMakeError(AutoSDKErrorAutomationFailed, @"Coordinate click failed.", nil)];
}

- (id)invokeDoubleClickPoint:(JSValue *)payload {
    if (![self ensureScriptRunning]) return @NO;
    if (![self.adapter respondsToSelector:@selector(doubleClickAtX:y:interval:error:)]) {
        return [self failure:AutoMakeError(AutoSDKErrorAutomationUnavailable, @"The automation adapter does not support coordinate double clicks.", nil)];
    }
    NSDictionary *data = AutoPayload(payload);
    if (!AutoPayloadHasFiniteNumbers(data, @[@"x", @"y"])) {
        return [self failure:AutoMakeError(AutoSDKErrorInvalidConfiguration, @"doubleClickPoint requires finite x and y values.", nil)];
    }
    id intervalValue = data[@"interval"];
    if (intervalValue && intervalValue != NSNull.null && !AutoFiniteNumber(intervalValue)) {
        return [self failure:AutoMakeError(AutoSDKErrorInvalidConfiguration, @"doubleClickPoint interval must be finite.", nil)];
    }
    NSTimeInterval interval = AutoFiniteNumber(intervalValue) ? [intervalValue doubleValue] : 0.1;
    if (interval <= 0) interval = 0.1;
    NSError *error = nil;
    BOOL ok = [self.adapter doubleClickAtX:[data[@"x"] doubleValue]
                                        y:[data[@"y"] doubleValue]
                                 interval:interval
                                    error:&error];
    return ok ? @YES : [self failure:error ?: AutoMakeError(AutoSDKErrorAutomationFailed, @"Coordinate double click failed.", nil)];
}

- (id)invokeLongClick:(JSValue *)payload {
    if (![self ensureScriptRunning]) return @NO;
    NSDictionary *data = AutoPayload(payload);
    id durationValue = data[@"duration"];
    if (durationValue && durationValue != NSNull.null && !AutoFiniteNumber(durationValue)) {
        return [self failure:AutoMakeError(AutoSDKErrorInvalidConfiguration, @"longClick duration must be finite.", nil)];
    }
    NSError *error = nil;
    BOOL ok = [self.adapter longClick:data[@"selector"] duration:AutoFiniteNumber(durationValue) ? [durationValue doubleValue] : 0 error:&error];
    return ok ? @YES : [self failure:error ?: AutoMakeError(AutoSDKErrorAutomationFailed, @"Long click failed.", nil)];
}

- (id)invokeSwipe:(JSValue *)payload {
    if (![self ensureScriptRunning]) return @NO;
    NSDictionary *data = AutoPayload(payload);
    if (!AutoPayloadHasFiniteNumbers(data, @[@"x1", @"y1", @"x2", @"y2"])) {
        return [self failure:AutoMakeError(AutoSDKErrorInvalidConfiguration, @"swipe requires finite coordinates.", nil)];
    }
    id durationValue = data[@"duration"];
    if (durationValue && durationValue != NSNull.null && !AutoFiniteNumber(durationValue)) {
        return [self failure:AutoMakeError(AutoSDKErrorInvalidConfiguration, @"swipe duration must be finite.", nil)];
    }
    NSError *error = nil;
    BOOL ok = [self.adapter swipeFromX:[data[@"x1"] doubleValue]
                                     y:[data[@"y1"] doubleValue]
                                    toX:[data[@"x2"] doubleValue]
                                     y:[data[@"y2"] doubleValue]
                              duration:AutoFiniteNumber(durationValue) ? [durationValue doubleValue] : 0
                                 error:&error];
    return ok ? @YES : [self failure:error ?: AutoMakeError(AutoSDKErrorAutomationFailed, @"Swipe failed.", nil)];
}

- (id)invokeInput:(JSValue *)payload {
    if (![self ensureScriptRunning]) return @NO;
    NSDictionary *data = AutoPayload(payload);
    NSError *error = nil;
    id textValue = data[@"text"];
    NSString *text = (!textValue || textValue == NSNull.null) ? @"" : [textValue description];
    BOOL ok = [self.adapter input:data[@"selector"] text:text error:&error];
    return ok ? @YES : [self failure:error ?: AutoMakeError(AutoSDKErrorAutomationFailed, @"Input failed.", nil)];
}

- (id)invokeSleep:(NSNumber *)milliseconds {
    if (![self ensureScriptRunning]) return @NO;
    double millisecondsValue = AutoFiniteDouble(milliseconds, 0);
    NSTimeInterval seconds = (isfinite(millisecondsValue) && millisecondsValue > 0)
        ? MIN(millisecondsValue / 1000.0, 3600.0)
        : 0;
    if (seconds > 0) {
        CFTimeInterval deadline = CFAbsoluteTimeGetCurrent() + seconds;
        while (![self.engine shouldStop]) {
            CFTimeInterval remaining = deadline - CFAbsoluteTimeGetCurrent();
            if (remaining <= 0) break;
            AutoPumpRunLoopWithSleepFallback(MIN(0.02, remaining));
        }
    }
    return [self.engine shouldStop] ? [self failure:AutoMakeError(AutoSDKErrorScriptCancelled, @"Script cancelled.", nil)] : @YES;
}

- (id)invokeGetText:(JSValue *)selector {
    if (![self ensureScriptRunning]) return @NO;
    NSError *error = nil;
    NSString *text = [self.adapter textForSelector:AutoJSObject(selector) error:&error];
    if (error) return [self failure:error];
    return text ?: [NSNull null];
}

- (id)invokeScreenshot {
    if (![self ensureScriptRunning]) return @NO;
    NSError *error = nil;
    NSData *data = [self.adapter screenshotWithError:&error];
    if (error) return [self failure:error];
    if (data.length > AutoScreenshotByteLimit(self.config ?: @{})) {
        return [self failure:AutoMakeError(AutoSDKErrorAutomationFailed, @"Screenshot exceeds maxScreenshotBytes.", nil)];
    }
    return data ? [data base64EncodedStringWithOptions:0] : [NSNull null];
}

- (id)invokeMedia:(JSValue *)payload {
    if (![self ensureScriptRunning]) return @NO;
    if (!AutoPermission(self.config, @"allowMediaLibrary", YES)) {
        return [self failure:AutoMakeError(AutoSDKErrorInvalidConfiguration,
                                           @"Photo library writes are disabled by configuration.", nil)];
    }

    @autoreleasepool {
    NSDictionary *data = AutoPayload(payload);
    NSString *operation = [data[@"operation"] isKindOfClass:NSString.class]
        ? [data[@"operation"] lowercaseString]
        : @"";
    NSURL *sourceURL = nil;
    UIImage *sourceImage = nil;
    BOOL isVideo = NO;
    NSError *error = nil;

    if ([operation isEqualToString:@"saveimage"] || [operation isEqualToString:@"savevideo"]) {
        sourceURL = AutoMediaSourceURL(data[@"path"], self.config ?: @{}, &error);
        if (!sourceURL) return [self failure:error];
        isVideo = [operation isEqualToString:@"savevideo"];
        if (!isVideo && !AutoMediaImageURLIsValid(sourceURL)) {
            return [self failure:AutoMakeError(AutoSDKErrorFileOperationFailed,
                                               @"Media source is not a supported image.", nil)];
        }
    } else if ([operation isEqualToString:@"saveimagebase64"]) {
        NSString *base64 = [data[@"base64"] isKindOfClass:NSString.class] ? data[@"base64"] : @"";
        NSUInteger maximum = AutoMediaImageByteLimit(self.config ?: @{});
        NSUInteger maximumEncodedLength = ((maximum + 2) / 3) * 4 + 4;
        if (base64.length == 0 || base64.length > maximumEncodedLength) {
            return [self failure:AutoMakeError(AutoSDKErrorFileOperationFailed,
                                               @"Image base64 is empty or exceeds maxMediaImageBytes.", nil)];
        }
        NSData *imageData = [[NSData alloc] initWithBase64EncodedString:base64 options:0];
        if (!imageData || imageData.length == 0 || imageData.length > maximum) {
            return [self failure:AutoMakeError(AutoSDKErrorFileOperationFailed,
                                               @"Image base64 is invalid or exceeds maxMediaImageBytes.", nil)];
        }
        sourceImage = [UIImage imageWithData:imageData];
        if (!sourceImage) {
            return [self failure:AutoMakeError(AutoSDKErrorFileOperationFailed,
                                               @"Image base64 does not contain a supported image.", nil)];
        }
    } else if ([operation isEqualToString:@"savescreenshot"]) {
        NSData *screenshot = [self.adapter screenshotWithError:&error];
        if (!screenshot || error) {
            return [self failure:error ?: AutoMakeError(AutoSDKErrorAutomationFailed,
                                                        @"Unable to capture a screenshot.", nil)];
        }
        if (screenshot.length > AutoScreenshotByteLimit(self.config ?: @{})) {
            return [self failure:AutoMakeError(AutoSDKErrorAutomationFailed,
                                               @"Screenshot exceeds maxScreenshotBytes.", nil)];
        }
        sourceImage = [UIImage imageWithData:screenshot];
        if (!sourceImage) {
            return [self failure:AutoMakeError(AutoSDKErrorAutomationFailed,
                                               @"Screenshot data is not a supported image.", nil)];
        }
    } else {
        return [self failure:AutoMakeError(AutoSDKErrorInvalidConfiguration,
                                           @"Unknown media operation.", nil)];
    }

    if (!AutoEnsurePhotoLibraryWriteAccess(self.engine, self.config ?: @{}, &error)) {
        return [self failure:error];
    }
    if (![self ensureScriptRunning]) return @NO;

    __block PHObjectPlaceholder *placeholder = nil;
    BOOL saved = [PHPhotoLibrary.sharedPhotoLibrary performChangesAndWait:^{
        PHAssetChangeRequest *request = nil;
        if (sourceImage) request = [PHAssetChangeRequest creationRequestForAssetFromImage:sourceImage];
        else if (isVideo) request = [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:sourceURL];
        else request = [PHAssetChangeRequest creationRequestForAssetFromImageAtFileURL:sourceURL];
        placeholder = request.placeholderForCreatedAsset;
    } error:&error];
    if (!saved || !placeholder) {
        return [self failure:AutoMakeError(AutoSDKErrorAutomationFailed,
                                           @"Unable to save media to the photo library.", error)];
    }
    return @YES;
    }
}

- (id)invokeFindImage:(JSValue *)payload {
    if (![self ensureScriptRunning]) return @NO;
    NSDictionary *data = AutoPayload(payload);
    NSError *error = nil;
    NSString *requestedPath = [data[@"templatePath"] isKindOfClass:NSString.class] ? data[@"templatePath"] : nil;
    if (requestedPath.length == 0) {
        return [self failure:AutoMakeError(AutoSDKErrorFileOperationFailed, @"findImage requires a template path.", nil)];
    }
    NSURL *bundleRoot = NSBundle.mainBundle.bundleURL.URLByStandardizingPath.URLByResolvingSymlinksInPath;
    NSURL *bundleCandidate = requestedPath.isAbsolutePath
        ? [NSURL fileURLWithPath:requestedPath]
        : [bundleRoot URLByAppendingPathComponent:requestedPath];
    bundleCandidate = bundleCandidate.URLByStandardizingPath.URLByResolvingSymlinksInPath;
    NSString *bundlePrefix = [bundleRoot.path stringByAppendingString:@"/"];
    BOOL isBundledFile = ([bundleCandidate.path isEqualToString:bundleRoot.path] || [bundleCandidate.path hasPrefix:bundlePrefix]) &&
                         [[NSFileManager defaultManager] fileExistsAtPath:bundleCandidate.path];
    NSString *templatePath = isBundledFile ? bundleCandidate.path : nil;
    if (!templatePath) {
        id resolved = AutoScriptFileOperation(@{ @"operation": @"resolvePath", @"path": requestedPath }, self.config ?: @{}, &error);
        templatePath = [resolved isKindOfClass:NSString.class] ? resolved : nil;
        if (!templatePath || error) return [self failure:error ?: AutoMakeError(AutoSDKErrorFileOperationFailed, @"Unable to resolve the image template path.", nil)];
    }
    NSDictionary *options = [data[@"options"] isKindOfClass:NSDictionary.class] ? data[@"options"] : @{};
    NSDictionary *result = [self.adapter findImageAtPath:templatePath
                                                 options:options
                                                    error:&error];
    return error ? [self failure:error] : (result ?: [NSNull null]);
}

- (id)invokeFindColor:(JSValue *)payload {
    if (![self ensureScriptRunning]) return @NO;
    if (![self.adapter respondsToSelector:@selector(findColor:region:options:error:)]) return [self failure:AutoMakeError(AutoSDKErrorAutomationUnavailable, @"The automation adapter does not support findColor.", nil)];
    NSDictionary *data = AutoPayload(payload);
    NSDictionary *region = [data[@"region"] isKindOfClass:NSDictionary.class] ? data[@"region"] : @{};
    NSDictionary *options = [data[@"options"] isKindOfClass:NSDictionary.class] ? data[@"options"] : @{};
    NSError *error = nil;
    NSDictionary *result = [self.adapter findColor:data[@"color"] region:region options:options error:&error];
    return error ? [self failure:error] : (result ?: [NSNull null]);
}

- (id)invokePixelColor:(JSValue *)payload {
    if (![self ensureScriptRunning]) return @NO;
    if (![self.adapter respondsToSelector:@selector(pixelColorAtX:y:error:)]) {
        return [self failure:AutoMakeError(AutoSDKErrorAutomationUnavailable, @"The automation adapter does not support pixel color reads.", nil)];
    }
    NSDictionary *data = AutoPayload(payload);
    if (!AutoPayloadHasFiniteNumbers(data, @[@"x", @"y"])) {
        return [self failure:AutoMakeError(AutoSDKErrorInvalidConfiguration, @"getPixelColor requires finite x and y values.", nil)];
    }
    NSError *error = nil;
    NSDictionary *result = [self.adapter pixelColorAtX:[data[@"x"] doubleValue] y:[data[@"y"] doubleValue] error:&error];
    return error ? [self failure:error] : (result ?: [NSNull null]);
}

- (id)invokeCompareColors:(JSValue *)payload {
    if (![self ensureScriptRunning]) return @NO;
    if (![self.adapter respondsToSelector:@selector(compareColors:options:error:)]) {
        return [self failure:AutoMakeError(AutoSDKErrorAutomationUnavailable, @"The automation adapter does not support multi-point color comparison.", nil)];
    }
    NSDictionary *data = AutoPayload(payload);
    NSArray *points = [data[@"points"] isKindOfClass:NSArray.class] ? data[@"points"] : @[];
    NSDictionary *options = [data[@"options"] isKindOfClass:NSDictionary.class] ? data[@"options"] : @{};
    NSError *error = nil;
    BOOL ok = [self.adapter compareColors:points options:options error:&error];
    return error ? [self failure:error] : @(ok);
}

- (id)invokeFindMultiColor:(JSValue *)payload {
    if (![self ensureScriptRunning]) return @NO;
    if (![self.adapter respondsToSelector:@selector(findMultiColor:offsets:region:options:error:)]) {
        return [self failure:AutoMakeError(AutoSDKErrorAutomationUnavailable, @"The automation adapter does not support multi-point color search.", nil)];
    }
    NSDictionary *data = AutoPayload(payload);
    NSArray *offsets = [data[@"offsets"] isKindOfClass:NSArray.class] ? data[@"offsets"] : @[];
    NSDictionary *region = [data[@"region"] isKindOfClass:NSDictionary.class] ? data[@"region"] : @{};
    NSDictionary *options = [data[@"options"] isKindOfClass:NSDictionary.class] ? data[@"options"] : @{};
    NSError *error = nil;
    NSDictionary *result = [self.adapter findMultiColor:data[@"color"]
                                                 offsets:offsets
                                                  region:region
                                                 options:options
                                                   error:&error];
    return error ? [self failure:error] : (result ?: [NSNull null]);
}

- (id)invokeHTTP:(JSValue *)payload {
    if (![self ensureScriptRunning]) return @NO;
    @autoreleasepool {
    if (!AutoBoolean(self.config[@"allowNetwork"], NO)) return [self failure:AutoMakeError(AutoSDKErrorNetworkDisabled, @"Network requests are disabled by configuration.", nil)];
    NSDictionary *data = AutoPayload(payload);
    NSString *urlString = [data[@"url"] isKindOfClass:NSString.class] ? data[@"url"] : @"";
    NSURL *url = [NSURL URLWithString:urlString];
    NSString *scheme = url.scheme.lowercaseString;
    if (!url || url.host.length == 0 || (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"])) return [self failure:AutoMakeError(AutoSDKErrorNetworkFailed, @"Only valid http:// and https:// URLs are supported.", nil)];
    BOOL hasHostAllowlist = NO;
    NSError *hostConfigurationError = nil;
    NSArray *allowedHosts = AutoValidatedHostAllowlist(self.config[@"allowedNetworkHosts"],
                                                       &hasHostAllowlist,
                                                       &hostConfigurationError);
    if (!allowedHosts) return [self failure:hostConfigurationError];
    if (hasHostAllowlist) {
        BOOL allowed = NO;
        for (id host in allowedHosts) {
            if ([host isKindOfClass:NSString.class] && [url.host caseInsensitiveCompare:host] == NSOrderedSame) { allowed = YES; break; }
        }
        if (!allowed) return [self failure:AutoMakeError(AutoSDKErrorNetworkDisabled, @"The request host is not in allowedNetworkHosts.", nil)];
    }
    NSUInteger maximumResponseBytes = AutoConfiguredByteLimit(self.config, @"maxHTTPResponseBytes",
                                                               10 * 1024 * 1024, 64 * 1024 * 1024);
    NSError *requestBuildError = nil;
    NSURLRequest *request = AutoBuildHTTPRequest(data, url, self.config, &requestBuildError);
    if (!request) return [self failure:requestBuildError];
    __block NSData *responseData = nil;
    __block NSHTTPURLResponse *httpResponse = nil;
    __block NSError *requestError = nil;
    dispatch_semaphore_t finished = dispatch_semaphore_create(0);
    AutoHTTPRedirectPolicy *policy = [AutoHTTPRedirectPolicy new];
    policy.followsRedirects = AutoBoolean(data[@"followRedirects"], YES);
    policy.allowedHosts = hasHostAllowlist ? allowedHosts : nil;
    NSURLSession *session = AutoHTTPSharedSession(self.engine.urlProtocolClasses);
    AutoHTTPRedirectRouter *router = AutoHTTPSharedRouter();
    NSString *downloadPath = [data[@"downloadPath"] isKindOfClass:NSString.class] ? data[@"downloadPath"] : nil;
    if (downloadPath) {
        NSError *destinationError = nil;
        if (downloadPath.length == 0 || !AutoScriptValidateDownloadDestination(downloadPath, self.config ?: @{}, &destinationError)) {
            return [self failure:destinationError ?: AutoMakeError(AutoSDKErrorFileOperationFailed, @"Download destination is invalid.", nil)];
        }
        NSUInteger maximumDownloadBytes = MIN(maximumResponseBytes,
                                               AutoScriptMaximumDownloadBytes(self.config ?: @{}));
        NSObject *downloadStateLock = [NSObject new];
        __block NSURL *stagedDownloadURL = nil;
        __block BOOL downloadAbandoned = NO;
        NSURLSessionDownloadTask *downloadTask = [session downloadTaskWithRequest:request
            completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
                httpResponse = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
                requestError = error;
                if (!requestError && location) {
                    NSDictionary *downloadAttributes = [[NSFileManager defaultManager]
                        attributesOfItemAtPath:location.path error:nil];
                    unsigned long long downloadedSize = [downloadAttributes[NSFileSize] unsignedLongLongValue];
                    if (downloadedSize > maximumDownloadBytes) {
                        requestError = AutoMakeError(AutoSDKErrorNetworkFailed, @"HTTP download exceeds its configured byte limit.", nil);
                    } else if (AutoBoolean(data[@"requireSuccess"], NO) &&
                               (httpResponse.statusCode < 200 || httpResponse.statusCode >= 300)) {
                        requestError = AutoMakeError(AutoSDKErrorNetworkFailed, @"HTTP download returned a non-success status.", nil);
                    } else {
                        NSURL *stagingURL = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]
                            URLByAppendingPathComponent:[NSString stringWithFormat:@"autosdk-http-%@.download", NSUUID.UUID.UUIDString]];
                        NSFileManager *manager = NSFileManager.defaultManager;
                        NSError *stagingError = nil;
                        BOOL staged = [manager moveItemAtURL:location toURL:stagingURL error:&stagingError];
                        if (!staged) {
                            stagingError = nil;
                            staged = [manager copyItemAtURL:location toURL:stagingURL error:&stagingError];
                        }
                        if (!staged) {
                            [manager removeItemAtURL:stagingURL error:nil];
                            requestError = AutoMakeError(AutoSDKErrorFileOperationFailed,
                                                         @"Unable to stage the HTTP download.", stagingError);
                        } else {
                            BOOL discard = NO;
                            @synchronized (downloadStateLock) {
                                discard = downloadAbandoned;
                                if (!discard) stagedDownloadURL = stagingURL;
                            }
                            if (discard) [manager removeItemAtURL:stagingURL error:nil];
                        }
                    }
                }
                dispatch_semaphore_signal(finished);
            }];
        void (^abandonDownload)(void) = ^{
            NSURL *staged = nil;
            @synchronized (downloadStateLock) {
                downloadAbandoned = YES;
                staged = stagedDownloadURL;
                stagedDownloadURL = nil;
            }
            if (staged) [NSFileManager.defaultManager removeItemAtURL:staged error:nil];
        };
        [router setPolicy:policy forTask:downloadTask];
        [downloadTask resume];
        NSDate *downloadDeadline = [NSDate dateWithTimeIntervalSinceNow:request.timeoutInterval + 1];
        BOOL downloadCompleted = NO;
        BOOL downloadTooLarge = NO;
        while (!downloadCompleted && [downloadDeadline timeIntervalSinceNow] > 0 && ![self.engine shouldStop]) {
            downloadCompleted = dispatch_semaphore_wait(finished, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.02 * NSEC_PER_SEC))) == 0;
            int64_t expectedBytes = downloadTask.countOfBytesExpectedToReceive;
            int64_t receivedBytes = downloadTask.countOfBytesReceived;
            if (!downloadCompleted && ((expectedBytes > 0 && (uint64_t)expectedBytes > maximumDownloadBytes) ||
                                       (receivedBytes > 0 && (uint64_t)receivedBytes > maximumDownloadBytes))) {
                downloadTooLarge = YES;
                [downloadTask cancel];
                break;
            }
            if (!downloadCompleted) AutoPumpRunLoopWithSleepFallback(0.01);
        }
        if (downloadTooLarge) {
            abandonDownload();
            [router removePolicyForTask:downloadTask];
            return [self failure:AutoMakeError(AutoSDKErrorNetworkFailed, @"HTTP download exceeds its configured byte limit.", nil)];
        }
        if (!downloadCompleted) {
            abandonDownload();
            [downloadTask cancel];
            [router removePolicyForTask:downloadTask];
            return [self failure:AutoMakeError([self.engine shouldStop] ? AutoSDKErrorScriptCancelled : AutoSDKErrorNetworkFailed,
                                               [self.engine shouldStop] ? @"Script cancelled." : @"HTTP download timed out.", nil)];
        }
        [router removePolicyForTask:downloadTask];
        if ([self.engine shouldStop]) {
            abandonDownload();
            return [self failure:AutoMakeError(AutoSDKErrorScriptCancelled, @"Script cancelled.", requestError)];
        }
        if (requestError) {
            abandonDownload();
            return [self failure:requestError];
        }
        if (!httpResponse || !stagedDownloadURL) {
            abandonDownload();
            return [self failure:AutoMakeError(AutoSDKErrorNetworkFailed,
                                               httpResponse ? @"HTTP download did not produce a file." : @"HTTP download did not return an HTTP response.", nil)];
        }
        BOOL installed = AutoScriptInstallDownloadedFile(stagedDownloadURL, downloadPath, self.config ?: @{}, &requestError);
        [NSFileManager.defaultManager removeItemAtURL:stagedDownloadURL error:nil];
        stagedDownloadURL = nil;
        if (!installed || requestError) return [self failure:requestError ?: AutoMakeError(AutoSDKErrorFileOperationFailed, @"Unable to install the HTTP download.", nil)];
        return @(installed);
    }
    // The shared session buffers completion-handler data tasks, so the byte
    // limit is enforced by the polling loop below (countOfBytes*) and then
    // re-checked against the completed buffer before any representation is
    // decoded. Cancelling on overrun also releases the buffered body.
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            httpResponse = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
            requestError = error;
            responseData = data;
            dispatch_semaphore_signal(finished);
        }];
    [router setPolicy:policy forTask:task];
    [task resume];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:request.timeoutInterval + 1];
    BOOL completed = NO;
    BOOL responseTooLarge = NO;
    while (!completed && [deadline timeIntervalSinceNow] > 0 && ![self.engine shouldStop]) {
        completed = dispatch_semaphore_wait(finished, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.02 * NSEC_PER_SEC))) == 0;
        int64_t expectedBytes = task.countOfBytesExpectedToReceive;
        int64_t receivedBytes = task.countOfBytesReceived;
        if (!completed && ((expectedBytes > 0 && (uint64_t)expectedBytes > maximumResponseBytes) ||
                           (receivedBytes > 0 && (uint64_t)receivedBytes > maximumResponseBytes))) {
            responseTooLarge = YES;
            [task cancel];
            break;
        }
        if (!completed) AutoPumpRunLoopWithSleepFallback(0.01);
    }
    if (responseTooLarge) {
        [router removePolicyForTask:task];
        return [self failure:AutoMakeError(AutoSDKErrorNetworkFailed, @"HTTP response exceeds maxHTTPResponseBytes.", nil)];
    }
    if (!completed) {
        [task cancel];
        [router removePolicyForTask:task];
        return [self failure:AutoMakeError([self.engine shouldStop] ? AutoSDKErrorScriptCancelled : AutoSDKErrorNetworkFailed, [self.engine shouldStop] ? @"Script cancelled." : @"HTTP request timed out.", nil)];
    }
    [router removePolicyForTask:task];
    if (responseData.length > maximumResponseBytes) return [self failure:AutoMakeError(AutoSDKErrorNetworkFailed, @"HTTP response exceeds maxHTTPResponseBytes.", nil)];
    if (requestError) {
        if ([self.engine shouldStop] && requestError.code == NSURLErrorCancelled) {
            return [self failure:AutoMakeError(AutoSDKErrorScriptCancelled, @"Script cancelled.", requestError)];
        }
        return [self failure:AutoMakeError(AutoSDKErrorNetworkFailed, requestError.localizedDescription ?: @"HTTP request failed.", requestError)];
    }
    if (!httpResponse) return [self failure:AutoMakeError(AutoSDKErrorNetworkFailed, @"HTTP request did not return an HTTP response.", nil)];
    if (responseData.length > maximumResponseBytes) return [self failure:AutoMakeError(AutoSDKErrorNetworkFailed, @"HTTP response exceeds maxHTTPResponseBytes.", nil)];
    BOOL includeBody = AutoBoolean(data[@"includeBody"], YES);
    BOOL includeBase64 = AutoBoolean(data[@"includeBase64"], YES);
    BOOL parseJSON = AutoBoolean(data[@"parseJson"], YES);
    NSString *bodyString = includeBody ? [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding] : nil;
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    NSUInteger responseHeaderBytes = 0;
    for (id key in httpResponse.allHeaderFields) {
        NSString *name = [key description] ?: @"";
        NSString *headerValue = [httpResponse.allHeaderFields[key] description] ?: @"";
        NSUInteger fieldBytes = [name lengthOfBytesUsingEncoding:NSUTF8StringEncoding] +
                                [headerValue lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        if (headers.count >= 256 || name.length > 1024 || headerValue.length > 16384 ||
            fieldBytes > 128 * 1024 || responseHeaderBytes > 128 * 1024 - fieldBytes) {
            return [self failure:AutoMakeError(AutoSDKErrorNetworkFailed, @"HTTP response headers exceed the configured safety limit.", nil)];
        }
        responseHeaderBytes += fieldBytes;
        headers[name] = headerValue;
    }
    NSInteger status = httpResponse.statusCode;
    NSMutableDictionary *result = [@{ @"status": @(status),
                                      @"statusCode": @(status),
                                      @"ok": @(status >= 200 && status < 300),
                                      @"url": httpResponse.URL.absoluteString ?: urlString,
                                      @"headers": headers,
                                      @"body": bodyString ?: @"",
                                      @"bodyBase64": includeBase64 && responseData ? [responseData base64EncodedStringWithOptions:0] : @"" } mutableCopy];
    if (parseJSON && responseData) {
        id json = [NSJSONSerialization JSONObjectWithData:responseData options:NSJSONReadingFragmentsAllowed error:nil];
        if (json) result[@"json"] = json;
    }
    return result;
    }
}

- (id)invokeOCR:(JSValue *)region {
    if (![self ensureScriptRunning]) return @NO;
    NSError *error = nil;
    id object = AutoJSObject(region);
    NSDictionary *options = [object isKindOfClass:NSDictionary.class] ? object : nil;
    NSArray *result = [self.adapter ocrInRegion:options error:&error];
    return error ? [self failure:error] : (result ?: @[]);
}

- (id)invokeExists:(JSValue *)selector {
    if (![self ensureScriptRunning]) return @NO;
    if (![self.adapter respondsToSelector:@selector(exists:error:)]) return [self failure:AutoMakeError(AutoSDKErrorAutomationUnavailable, @"The automation adapter does not support exists.", nil)];
    NSError *error = nil;
    BOOL exists = [self.adapter exists:AutoJSObject(selector) error:&error];
    return error ? [self failure:error] : @(exists);
}

- (id)invokeFindElement:(JSValue *)selector {
    if (![self ensureScriptRunning]) return @NO;
    if (![self.adapter respondsToSelector:@selector(elementInfoForSelector:error:)]) return [self failure:AutoMakeError(AutoSDKErrorAutomationUnavailable, @"The automation adapter does not support findElement.", nil)];
    NSError *error = nil;
    NSDictionary *element = [self.adapter elementInfoForSelector:AutoJSObject(selector) error:&error];
    if (error) return [self failure:error];
    return element ?: [NSNull null];
}

- (id)invokeFindElements:(JSValue *)selector {
    if (![self ensureScriptRunning]) return @NO;
    if (![self.adapter respondsToSelector:@selector(elementsInfoForSelector:error:)]) {
        return [self failure:AutoMakeError(AutoSDKErrorAutomationUnavailable, @"The automation adapter does not support findElements.", nil)];
    }
    NSError *error = nil;
    NSArray *elements = [self.adapter elementsInfoForSelector:AutoJSObject(selector) error:&error];
    return error ? [self failure:error] : (elements ?: @[]);
}

- (id)invokeWaitFor:(JSValue *)payload {
    if (![self ensureScriptRunning]) return @NO;
    if (![self.adapter respondsToSelector:@selector(exists:error:)]) return [self failure:AutoMakeError(AutoSDKErrorAutomationUnavailable, @"The automation adapter does not support waitFor.", nil)];
    NSDictionary *data = AutoPayload(payload);
    id selector = data[@"selector"] ?: [NSNull null];
    NSTimeInterval timeoutMilliseconds = AutoFiniteDouble(data[@"timeout"], 0);
    NSTimeInterval timeout = (isfinite(timeoutMilliseconds) && timeoutMilliseconds > 0)
        ? MIN(timeoutMilliseconds / 1000.0, 3600.0)
        : 10.0;
    CFTimeInterval deadline = CFAbsoluteTimeGetCurrent() + timeout;
    NSTimeInterval pollInterval = AutoFiniteDouble(self.config[@"waitPollInterval"], 0);
    if (!isfinite(pollInterval) || pollInterval <= 0) pollInterval = 0.05;
    pollInterval = MIN(0.25, MAX(0.01, pollInterval));
    while (![self.engine shouldStop]) {
        NSError *error = nil;
        if ([self.adapter exists:selector error:&error]) return @YES;
        if (error) return [self failure:error];
        CFTimeInterval remaining = deadline - CFAbsoluteTimeGetCurrent();
        if (remaining <= 0) break;
        NSTimeInterval delay = MIN(pollInterval, remaining);
        AutoPumpRunLoopWithSleepFallback(delay);
        pollInterval = MIN(0.25, pollInterval * 1.5);
    }
    if ([self.engine shouldStop]) return [self failure:AutoMakeError(AutoSDKErrorScriptCancelled, @"Script cancelled.", nil)];
    return [self failure:AutoMakeError(AutoSDKErrorWaitTimeout, @"Timed out waiting for the element.", nil)];
}

- (id)invokeGetAttribute:(JSValue *)payload {
    if (![self ensureScriptRunning]) return @NO;
    if (![self.adapter respondsToSelector:@selector(attribute:forSelector:error:)]) return [self failure:AutoMakeError(AutoSDKErrorAutomationUnavailable, @"The automation adapter does not support getAttribute.", nil)];
    NSDictionary *data = AutoPayload(payload);
    NSString *attribute = [data[@"attribute"] isKindOfClass:NSString.class] ? data[@"attribute"] : nil;
    if (attribute.length == 0 || attribute.length > 128) {
        return [self failure:AutoMakeError(AutoSDKErrorInvalidConfiguration,
                                           @"getAttribute requires an attribute name containing 1 to 128 characters.", nil)];
    }
    NSError *error = nil;
    id value = [self.adapter attribute:attribute forSelector:data[@"selector"] error:&error];
    return error ? [self failure:error] : (value ?: [NSNull null]);
}

- (id)invokeGetBounds:(JSValue *)selector {
    if (![self ensureScriptRunning]) return @NO;
    if (![self.adapter respondsToSelector:@selector(boundsForSelector:error:)]) return [self failure:AutoMakeError(AutoSDKErrorAutomationUnavailable, @"The automation adapter does not support getBounds.", nil)];
    NSError *error = nil;
    NSDictionary *bounds = [self.adapter boundsForSelector:AutoJSObject(selector) error:&error];
    return error ? [self failure:error] : (bounds ?: [NSNull null]);
}

- (id)invokeGetChildren:(JSValue *)selector {
    if (![self ensureScriptRunning]) return @NO;
    if (![self.adapter respondsToSelector:@selector(childrenForSelector:error:)]) return [self failure:AutoMakeError(AutoSDKErrorAutomationUnavailable, @"The automation adapter does not support getChildren.", nil)];
    NSError *error = nil;
    NSArray *children = [self.adapter childrenForSelector:AutoJSObject(selector) error:&error];
    return error ? [self failure:error] : (children ?: @[]);
}

- (id)invokeGetParent:(JSValue *)selector {
    if (![self ensureScriptRunning]) return @NO;
    if (![self.adapter respondsToSelector:@selector(parentForSelector:error:)]) return [self failure:AutoMakeError(AutoSDKErrorAutomationUnavailable, @"The automation adapter does not support getParent.", nil)];
    NSError *error = nil;
    NSDictionary *parent = [self.adapter parentForSelector:AutoJSObject(selector) error:&error];
    return error ? [self failure:error] : (parent ?: [NSNull null]);
}

- (id)invokeScrollIntoView:(JSValue *)selector {
    if (![self ensureScriptRunning]) return @NO;
    if (![self.adapter respondsToSelector:@selector(scrollIntoView:error:)]) return [self failure:AutoMakeError(AutoSDKErrorAutomationUnavailable, @"The automation adapter does not support scrollIntoView.", nil)];
    NSError *error = nil;
    BOOL ok = [self.adapter scrollIntoView:AutoJSObject(selector) error:&error];
    return ok ? @YES : [self failure:error ?: AutoMakeError(AutoSDKErrorAutomationFailed, @"Unable to scroll element into view.", nil)];
}

- (id)invokeFile:(JSValue *)payload {
    if (![self ensureScriptRunning]) return @NO;
    NSError *error = nil;
    id result = AutoScriptFileOperation(AutoPayload(payload), self.config ?: @{}, &error);
    return error ? [self failure:error] : (result ?: [NSNull null]);
}

- (id)invokeStorage:(JSValue *)payload {
    if (![self ensureScriptRunning]) return @NO;
    NSError *error = nil;
    id result = AutoScriptStorageOperation(AutoPayload(payload), self.config ?: @{}, &error);
    return error ? [self failure:error] : (result ?: [NSNull null]);
}

- (id)invokeDevice:(JSValue *)payload {
    if (![self ensureScriptRunning]) return @NO;
    NSDictionary *data = AutoPayload(payload);
    NSString *operation = [data[@"operation"] isKindOfClass:NSString.class] ? data[@"operation"] : @"info";
    if ([operation isEqualToString:@"info"]) {
        NSDictionary *info = AutoValueOnMainThread(^id{ return [self.engine getDeviceInfo]; });
        return info ?: @{};
    }
    if ([operation isEqualToString:@"clipboardGet"] || [operation isEqualToString:@"clipboardSet"] ||
        [operation isEqualToString:@"brightnessGet"] || [operation isEqualToString:@"brightnessSet"] ||
        [operation isEqualToString:@"volumeGet"] || [operation isEqualToString:@"vibrate"]) {
        if (!AutoPermission(self.config, @"allowSystemControl", YES)) {
            return [self failure:AutoMakeError(AutoSDKErrorInvalidConfiguration, @"System control is disabled by configuration.", nil)];
        }
    }
    if ([operation isEqualToString:@"memory"]) {
        return AutoValueOnMainThread(^id{ return [self.engine deviceMemoryInfo]; }) ?: @{};
    }
    if ([operation isEqualToString:@"clipboardGet"]) {
        return AutoValueOnMainThread(^id{
            NSString *clipboard = UIPasteboard.generalPasteboard.string;
            return clipboard ?: [NSNull null];
        });
    }
    if ([operation isEqualToString:@"clipboardSet"]) {
        NSString *text = [data[@"text"] isKindOfClass:NSString.class] ? data[@"text"] : @"";
        if ([text lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > AutoSystemClipboardByteLimit) {
            return [self failure:AutoMakeError(AutoSDKErrorInvalidConfiguration, @"Clipboard text exceeds the 1 MiB limit.", nil)];
        }
        AutoValueOnMainThread(^id{ UIPasteboard.generalPasteboard.string = text; return @YES; });
        return @YES;
    }
    if ([operation isEqualToString:@"brightnessGet"]) {
        return AutoValueOnMainThread(^id{ return @(UIScreen.mainScreen.brightness); });
    }
    if ([operation isEqualToString:@"brightnessSet"]) {
        double value = AutoFiniteDouble(data[@"value"], -1);
        if (!(value >= 0 && value <= 1)) {
            return [self failure:AutoMakeError(AutoSDKErrorInvalidConfiguration, @"Brightness must be between 0 and 1.", nil)];
        }
        AutoValueOnMainThread(^id{ UIScreen.mainScreen.brightness = value; return @YES; });
        return @YES;
    }
    if ([operation isEqualToString:@"volumeGet"]) {
        return AutoValueOnMainThread(^id{
            float volume = AVAudioSession.sharedInstance.outputVolume;
            return @(MIN(MAX(volume, 0), 1));
        });
    }
    if ([operation isEqualToString:@"vibrate"]) {
        double durationMs = AutoFiniteDouble(data[@"duration"], 0);
        if (!(durationMs >= 0)) {
            return [self failure:AutoMakeError(AutoSDKErrorInvalidConfiguration, @"Vibration duration must be non-negative.", nil)];
        }
        // The system sound API fires once; the duration is advisory and capped.
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
        return @YES;
    }
    NSDictionary *mapping = @{ @"screenWidth": @"screenWidth", @"screenHeight": @"screenHeight",
                               @"scale": @"screenScale", @"model": @"model", @"osVersion": @"systemVersion",
                               @"name": @"name", @"battery": @"batteryLevel", @"isCharging": @"isCharging",
                               @"orientation": @"orientation" };
    NSString *key = mapping[operation];
    if (!key) return [self failure:AutoMakeError(AutoSDKErrorAutomationFailed, @"Unknown device operation.", nil)];
    NSDictionary *info = AutoValueOnMainThread(^id{ return [self.engine getDeviceInfo]; });
    return info[key] ?: [NSNull null];
}

- (id)invokeApp:(JSValue *)payload {
    if (![self ensureScriptRunning]) return @NO;
    NSDictionary *data = AutoPayload(payload);
    NSString *operation = [data[@"operation"] isKindOfClass:NSString.class] ? [data[@"operation"] lowercaseString] : @"";
    NSError *error = nil;
    if ([operation isEqualToString:@"openurl"]) {
        if (!AutoPermission(self.config, @"allowSystemControl", YES)) {
            return [self failure:AutoMakeError(AutoSDKErrorInvalidConfiguration, @"System control is disabled by configuration.", nil)];
        }
        NSString *urlString = [data[@"url"] isKindOfClass:NSString.class] ? data[@"url"] : @"";
        NSURL *url = [NSURL URLWithString:urlString];
        if (!AutoSystemURLSchemeAllowed(url)) {
            return [self failure:AutoMakeError(AutoSDKErrorInvalidConfiguration, @"openURL only accepts http(s) URLs or custom URL schemes.", nil)];
        }
        return @([AutoValueOnMainThread(^id{ return @([UIApplication.sharedApplication openURL:url]); }) boolValue]);
    }
    if ([operation isEqualToString:@"homescreen"] || [operation isEqualToString:@"lock"] || [operation isEqualToString:@"unlock"]) {
        if (!AutoPermission(self.config, @"allowSystemControl", YES)) {
            return [self failure:AutoMakeError(AutoSDKErrorInvalidConfiguration, @"System control is disabled by configuration.", nil)];
        }
        SEL selector = NULL;
        if ([operation isEqualToString:@"homescreen"]) selector = @selector(goToHomeScreenWithError:);
        else if ([operation isEqualToString:@"lock"]) selector = @selector(lockDeviceWithError:);
        else if ([operation isEqualToString:@"unlock"]) selector = @selector(unlockDeviceWithError:);
        if (![self.adapter respondsToSelector:selector]) {
            return [self failure:AutoMakeError(AutoSDKErrorAutomationUnavailable,
                                               [NSString stringWithFormat:@"The automation adapter does not support the '%@' operation.", operation], nil)];
        }
        BOOL ok = ((BOOL (*)(id, SEL, NSError **))objc_msgSend)(self.adapter, selector, &error);
        return error ? [self failure:error] : @(ok);
    }
    NSString *bundleId = [data[@"bundleId"] isKindOfClass:NSString.class] ? data[@"bundleId"] : @"";
    if (bundleId.length == 0) return [self failure:AutoMakeError(AutoSDKErrorInvalidConfiguration, @"Application bundleId must not be empty.", nil)];
    if ([operation isEqualToString:@"launch"]) {
        if (![self.adapter respondsToSelector:@selector(launchApplicationWithBundleId:error:)]) {
            return [self failure:AutoMakeError(AutoSDKErrorAutomationUnavailable, @"The automation adapter does not support launching applications.", nil)];
        }
        BOOL ok = [self.adapter launchApplicationWithBundleId:bundleId error:&error];
        return error ? [self failure:error] : @(ok);
    }
    if ([operation isEqualToString:@"activate"]) {
        if (![self.adapter respondsToSelector:@selector(activateApplicationWithBundleId:error:)]) {
            return [self failure:AutoMakeError(AutoSDKErrorAutomationUnavailable, @"The automation adapter does not support activating applications.", nil)];
        }
        BOOL ok = [self.adapter activateApplicationWithBundleId:bundleId error:&error];
        return error ? [self failure:error] : @(ok);
    }
    if ([operation isEqualToString:@"terminate"]) {
        if (![self.adapter respondsToSelector:@selector(terminateApplicationWithBundleId:error:)]) {
            return [self failure:AutoMakeError(AutoSDKErrorAutomationUnavailable, @"The automation adapter does not support terminating applications.", nil)];
        }
        BOOL ok = [self.adapter terminateApplicationWithBundleId:bundleId error:&error];
        return error ? [self failure:error] : @(ok);
    }
    if ([operation isEqualToString:@"state"]) {
        if (![self.adapter respondsToSelector:@selector(applicationStateForBundleId:error:)]) {
            return [self failure:AutoMakeError(AutoSDKErrorAutomationUnavailable, @"The automation adapter does not support application state queries.", nil)];
        }
        NSNumber *state = [self.adapter applicationStateForBundleId:bundleId error:&error];
        return error ? [self failure:error] : (state ?: [NSNull null]);
    }
    return [self failure:AutoMakeError(AutoSDKErrorInvalidConfiguration, @"Unknown application operation.", nil)];
}

- (id)invokeCapabilities {
    if (![self ensureScriptRunning]) return @NO;
    return [self.engine capabilityInfo] ?: @{};
}

- (BOOL)invokeIsStopped {
    return [self.engine shouldStop];
}

- (id)invokeTouch:(JSValue *)payload {
    if (![self ensureScriptRunning]) return @NO;
    NSDictionary *data = AutoPayload(payload);
    NSArray *fingers = data[@"fingers"];
    if (![fingers isKindOfClass:NSArray.class] || fingers.count == 0) {
        return [self failure:AutoMakeError(AutoSDKErrorInvalidConfiguration, @"gesture requires at least one finger track.", nil)];
    }
    if (fingers.count > 10) {
        return [self failure:AutoMakeError(AutoSDKErrorInvalidConfiguration, @"gesture accepts at most 10 fingers.", nil)];
    }
    if (![self.adapter respondsToSelector:@selector(performMultiTouch:error:)]) {
        return [self failure:AutoMakeError(AutoSDKErrorAutomationUnavailable, @"The automation adapter does not support multi-touch gestures.", nil)];
    }
    NSError *error = nil;
    BOOL ok = [self.adapter performMultiTouch:fingers error:&error];
    return ok ? @YES : [self failure:error ?: AutoMakeError(AutoSDKErrorAutomationFailed, @"Multi-touch gesture failed.", nil)];
}
- (id)invokeNative:(JSValue *)payload {
    if (![self ensureScriptRunning]) return @NO;
    NSDictionary *nativePayload = AutoPayload(payload);
    NSString *name = [nativePayload[@"name"] isKindOfClass:NSString.class] ? nativePayload[@"name"] : nil;
    if (name.length == 0 || name.length > 128 ||
        [name rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) {
        return [self failure:AutoMakeError(AutoSDKErrorInvalidConfiguration,
                                           @"Native method name must contain 1 to 128 non-control characters.", nil)];
    }
    __block AutoNativeMethodHandler handler = nil;
    @synchronized (self.engine) { handler = [self.engine.nativeMethods[name] copy]; }
    if (!handler) {
        if ([name isEqualToString:@"toast"]) {
            id message = [nativePayload[@"arguments"] isKindOfClass:NSArray.class] ? [nativePayload[@"arguments"] firstObject] : nil;
            NSString *text = [message isKindOfClass:NSString.class] ? message : [message description];
            if (text.length == 0) text = @"";
            AutoShowToast(text);
            return @YES;
        }
        return [self failure:AutoMakeError(AutoSDKErrorAutomationFailed, [NSString stringWithFormat:@"Native method '%@' is not registered.", name], nil)];
    }
    id object = nativePayload[@"arguments"] ?: @[];
    NSArray *args = [object isKindOfClass:NSArray.class] ? object : @[];
    id value = AutoValueOnMainThread(^id{
        @try {
            return handler(args) ?: NSNull.null;
        } @catch (NSException *exception) {
            return AutoMakeError(AutoSDKErrorAutomationFailed, exception.reason ?: @"Native method failed.", nil);
        }
    });
    return [value isKindOfClass:NSError.class] ? [self failure:value] : value;
}

@end

@implementation AutoJSConsole

- (instancetype)init {
    self = [super init];
    if (self) {
        _entries = [NSMutableArray array];
        _maximumEntries = 1000;
        _maximumMessageLength = 16 * 1024;
        _maximumTotalBytes = 8 * 1024 * 1024;
    }
    return self;
}

- (void)appendLevel:(NSString *)level value:(JSValue *)value {
    id object = AutoJSObject(value);
    NSString *message = [object isKindOfClass:NSString.class] ? object : [object description];
    if (message.length > self.maximumMessageLength) {
        NSUInteger limit = self.maximumMessageLength;
        NSRange lastCharacter = [message rangeOfComposedCharacterSequenceAtIndex:limit - 1];
        NSUInteger cut = lastCharacter.location + lastCharacter.length;
        if (cut > limit) cut = lastCharacter.location;
        message = [[message substringToIndex:cut] stringByAppendingString:@"..."];
    }
    NSUInteger messageBytes = [message lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    @synchronized (self) {
        BOOL withinEntryLimit = self.maximumEntries > 0 && self.entries.count < self.maximumEntries;
        BOOL withinByteLimit = messageBytes <= self.maximumTotalBytes &&
            self.retainedMessageBytes <= self.maximumTotalBytes - messageBytes;
        if (withinEntryLimit && withinByteLimit) {
            [self.entries addObject:@{ @"level": level, @"message": message ?: @"" }];
            self.retainedMessageBytes += messageBytes;
        }
    }
    if (self.emitToSystemLog) {
        if ([level isEqualToString:@"error"]) NSLog(@"[AutoSDK][JS][error] %@", message);
        else if ([level isEqualToString:@"warn"]) NSLog(@"[AutoSDK][JS][warn] %@", message);
        else NSLog(@"[AutoSDK][JS] %@", message);
    }
}

- (void)log:(JSValue *)value { [self appendLevel:@"log" value:value]; }
- (void)warn:(JSValue *)value { [self appendLevel:@"warn" value:value]; }
- (void)error:(JSValue *)value { [self appendLevel:@"error" value:value]; }

@end

@implementation AutoEngine

- (BOOL)isRunning {
    @synchronized (self) { return _running; }
}

+ (instancetype)sharedEngine {
    static AutoEngine *engine;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ engine = [AutoEngine new]; });
    return engine;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _config = @{};
        _nativeMethods = [NSMutableDictionary dictionary];
        _adapter = [AutoUnavailableAdapter new];
        _scriptQueue = dispatch_queue_create("com.autosdk.javascript", DISPATCH_QUEUE_SERIAL);
        _debugAdapterQueue = dispatch_queue_create("com.autosdk.debug-adapter", DISPATCH_QUEUE_SERIAL);
        _debugServerQueue = dispatch_queue_create("com.autosdk.debug-server-state", DISPATCH_QUEUE_SERIAL);
        dispatch_queue_set_specific(_debugServerQueue, AutoDebugServerQueueKey, AutoDebugServerQueueKey, NULL);
    }
    return self;
}

- (void)initWithConfig:(NSDictionary<NSString *,id> *)config __attribute__((objc_method_family(none))) {
    [self configureWithConfig:config];
}

- (void)configureWithConfig:(NSDictionary<NSString *,id> *)config {
    NSDictionary *configSnapshot = nil;
    @synchronized (self) {
        configSnapshot = AutoImmutableConfigSnapshot(config);
        self.config = configSnapshot;
        if ([configSnapshot[@"adapter"] conformsToProtocol:@protocol(AutoAutomationAdapter)]) {
            self.adapter = configSnapshot[@"adapter"];
        }
        id protocolValue = configSnapshot[@"urlProtocolClasses"];
        NSArray *configuredProtocols = [protocolValue isKindOfClass:NSArray.class] ? protocolValue : nil;
        NSMutableArray *validProtocols = [NSMutableArray array];
        for (id protocol in configuredProtocols) {
            if (object_isClass(protocol)) [validProtocols addObject:protocol];
        }
        self.urlProtocolClasses = validProtocols.count > 0 ? [validProtocols copy] : nil;
    }
    if (AutoBoolean(configSnapshot[@"debugServerEnabled"], NO)) {
        uint16_t port = (uint16_t)AutoBoundedPositiveInteger(configSnapshot[@"debugPort"], 9001, UINT16_MAX);
        BOOL allowsWiFi = AutoBoolean(configSnapshot[@"debugAllowWiFi"], NO);
        [self startDebugServerWithPort:port allowsWiFi:allowsWiFi completion:^(NSError * _Nullable error) {
            if (error) NSLog(@"[AutoSDK] debug server failed: %@", error);
            else if (AutoBoolean(configSnapshot[@"debugLogging"], NO)) {
                NSLog(@"[AutoSDK] debug server listening on %@:%hu", allowsWiFi ? @"Wi-Fi" : @"127.0.0.1", port);
            }
        }];
    } else {
        [self stopDebugServer];
    }
}

- (void)setAutomationAdapter:(id<AutoAutomationAdapter>)adapter {
    @synchronized (self) { self.adapter = adapter ?: [AutoUnavailableAdapter new]; }
}

- (void)startDebugServerWithPort:(uint16_t)port completion:(void (^)(NSError * _Nullable error))completion {
    [self startDebugServerWithPort:port allowsWiFi:NO completion:completion];
}

- (void)startDebugServerWithPort:(uint16_t)port
                     allowsWiFi:(BOOL)allowsWiFi
                      completion:(void (^)(NSError * _Nullable error))completion {
    void (^operation)(void) = ^{
        if (!self.debugServer) self.debugServer = [AutoDebugServer new];
        AutoDebugServer *server = self.debugServer;
        NSDictionary *config = self.config ?: @{};
        NSString *token = [config[@"debugToken"] isKindOfClass:NSString.class] ? config[@"debugToken"] : @"";
        NSDictionary *desiredConfiguration = @{ @"port": @(port), @"allowsWiFi": @(allowsWiFi), @"token": token };
        if ([self.debugServerConfiguration isEqualToDictionary:desiredConfiguration]) {
            if (server.isRunning) {
                if (completion) AutoDispatchDebugServerCompletions(@[[completion copy]], nil);
                return;
            }
            if (self.debugServerStarting) {
                if (completion) [self.debugServerStartCompletions addObject:[completion copy]];
                return;
            }
        }

        [server stop];
        NSUInteger generation = ++self.debugServerGeneration;
        NSMutableArray *startCompletions = [NSMutableArray array];
        if (completion) [startCompletions addObject:[completion copy]];
        self.debugServerConfiguration = desiredConfiguration;
        self.debugServerStarting = YES;
        self.debugServerStartCompletions = startCompletions;

        __weak AutoEngine *weakSelf = self;
        [server startWithPort:port token:token allowsWiFi:allowsWiFi requestHandler:^(NSDictionary<NSString *,id> *request, AutoDebugResponseHandler response) {
            AutoEngine *strongSelf = weakSelf;
            if (strongSelf) [strongSelf handleDebugRequest:request response:response];
        } completion:^(NSError * _Nullable error) {
            AutoEngine *strongSelf = weakSelf;
            if (!strongSelf) return;
            dispatch_async(strongSelf.debugServerQueue, ^{
                if (strongSelf.debugServerGeneration == generation) {
                    strongSelf.debugServerStarting = NO;
                    strongSelf.debugServerStartCompletions = nil;
                    if (error && [strongSelf.debugServerConfiguration isEqualToDictionary:desiredConfiguration]) {
                        strongSelf.debugServerConfiguration = nil;
                    }
                }
                NSArray *callbacks = [startCompletions copy];
                [startCompletions removeAllObjects];
                AutoDispatchDebugServerCompletions(callbacks, error);
            });
        }];
    };
    if (dispatch_get_specific(AutoDebugServerQueueKey)) operation();
    else dispatch_async(self.debugServerQueue, operation);
}

- (void)stopDebugServer {
    void (^operation)(void) = ^{
        self.debugServerGeneration += 1;
        self.debugServerConfiguration = nil;
        self.debugServerStarting = NO;
        self.debugServerStartCompletions = nil;
        [self.debugServer stop];
    };
    if (dispatch_get_specific(AutoDebugServerQueueKey)) operation();
    else dispatch_sync(self.debugServerQueue, operation);
}

- (NSArray<NSDictionary<NSString *,id> *> *)deployedScriptsWithError:(NSError **)error {
    NSDictionary *config = self.config ?: @{};
    NSError *existsError = nil;
    id exists = AutoScriptFileOperation(@{ @"operation": @"exists", @"path": @"debug-scripts" }, config, &existsError);
    if (existsError) { if (error) *error = existsError; return nil; }
    if (![exists boolValue]) return @[];
    NSError *listError = nil;
    id listed = AutoScriptFileOperation(@{ @"operation": @"list", @"path": @"debug-scripts" }, config, &listError);
    if (![listed isKindOfClass:NSArray.class] || listError) { if (error) *error = listError; return nil; }
    NSMutableArray *scripts = [NSMutableArray array];
    for (NSDictionary *item in listed) {
        NSString *name = AutoDebugScriptName(item[@"name"]);
        if (!name || [item[@"isDirectory"] boolValue]) continue;
        [scripts addObject:@{ @"name": name,
                              @"sizeBytes": item[@"size"] ?: @0,
                              @"modifiedAtMs": item[@"modifiedAtMs"] ?: NSNull.null }];
    }
    [scripts sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        return [(NSString *)left[@"name"] localizedCaseInsensitiveCompare:(NSString *)right[@"name"]];
    }];
    return scripts;
}

- (void)runDeployedScriptNamed:(NSString *)name completion:(AutoScriptCompletion)completion {
    NSString *safeName = AutoDebugScriptName(name);
    if (!safeName) {
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil, AutoMakeError(AutoSDKErrorInvalidConfiguration, @"A valid deployed .js script name is required.", nil));
        });
        return;
    }
    NSError *pathError = nil;
    id path = AutoScriptFileOperation(@{ @"operation": @"resolvePath", @"path": AutoDebugScriptPath(safeName) },
                                      self.config ?: @{}, &pathError);
    if (![path isKindOfClass:NSString.class] || pathError || ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil, pathError ?: AutoMakeError(AutoSDKErrorScriptNotFound, @"The deployed script does not exist.", nil));
        });
        return;
    }
    [self runScript:path completion:completion];
}

- (BOOL)deleteDeployedScriptNamed:(NSString *)name error:(NSError **)error {
    NSString *safeName = AutoDebugScriptName(name);
    if (!safeName) {
        if (error) *error = AutoMakeError(AutoSDKErrorInvalidConfiguration, @"A valid deployed .js script name is required.", nil);
        return NO;
    }
    id result = AutoScriptFileOperation(@{ @"operation": @"remove", @"path": AutoDebugScriptPath(safeName) },
                                        self.config ?: @{}, error);
    return [result boolValue];
}

- (BOOL)saveDeployedScriptNamed:(NSString *)name script:(NSString *)script error:(NSError **)error {
    NSString *safeName = AutoDebugScriptName(name);
    if (!safeName) {
        if (error) *error = AutoMakeError(AutoSDKErrorInvalidConfiguration, @"A valid deployed .js script name is required.", nil);
        return NO;
    }
    if (![script isKindOfClass:NSString.class]) {
        if (error) *error = AutoMakeError(AutoSDKErrorInvalidConfiguration, @"Script source must be a string.", nil);
        return NO;
    }
    NSUInteger byteLength = [script lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    NSUInteger configuredLimit = AutoConfiguredByteLimit(self.config ?: @{}, @"maxScriptBytes", 5 * 1024 * 1024, 64 * 1024 * 1024);
    NSUInteger limit = MIN(configuredLimit, AutoDebugScriptByteLimit);
    if (byteLength == 0 || byteLength > limit) {
        if (error) *error = AutoMakeError(AutoSDKErrorInvalidConfiguration,
                                          [NSString stringWithFormat:@"Script must contain 1 to %lu UTF-8 bytes.", (unsigned long)limit], nil);
        return NO;
    }
    NSError *writeError = nil;
    id result = AutoScriptFileOperation(@{ @"operation": @"writeText",
                                            @"path": AutoDebugScriptPath(safeName),
                                            @"text": script }, self.config ?: @{}, &writeError);
    if (![result boolValue] && !writeError) {
        writeError = AutoMakeError(AutoSDKErrorFileOperationFailed, @"Unable to deploy the script.", nil);
    }
    if (writeError && error) *error = writeError;
    return [result boolValue];
}

- (NSString *)deployedScriptContentNamed:(NSString *)name error:(NSError **)error {
    NSString *safeName = AutoDebugScriptName(name);
    if (!safeName) {
        if (error) *error = AutoMakeError(AutoSDKErrorInvalidConfiguration, @"A valid deployed .js script name is required.", nil);
        return nil;
    }
    id result = AutoScriptFileOperation(@{ @"operation": @"readText", @"path": AutoDebugScriptPath(safeName) },
                                        self.config ?: @{}, error);
    return [result isKindOfClass:NSString.class] ? result : nil;
}

- (BOOL)renameDeployedScriptNamed:(NSString *)oldName toName:(NSString *)newName error:(NSError **)error {
    NSString *safeOld = AutoDebugScriptName(oldName);
    NSString *safeNew = AutoDebugScriptName(newName);
    if (!safeOld || !safeNew) {
        if (error) *error = AutoMakeError(AutoSDKErrorInvalidConfiguration, @"A valid deployed .js script name is required.", nil);
        return NO;
    }
    if ([safeOld isEqualToString:safeNew]) return YES;
    NSError *existsError = nil;
    id exists = AutoScriptFileOperation(@{ @"operation": @"exists", @"path": AutoDebugScriptPath(safeNew) },
                                        self.config ?: @{}, &existsError);
    if (existsError) { if (error) *error = existsError; return NO; }
    if ([exists boolValue]) {
        if (error) *error = AutoMakeError(AutoSDKErrorFileOperationFailed, @"A script with the new name already exists.", nil);
        return NO;
    }
    NSError *moveError = nil;
    id result = AutoScriptFileOperation(@{ @"operation": @"move",
                                            @"path": AutoDebugScriptPath(safeOld),
                                            @"destination": AutoDebugScriptPath(safeNew),
                                            @"overwrite": @NO }, self.config ?: @{}, &moveError);
    if (![result boolValue] && !moveError) {
        moveError = AutoMakeError(AutoSDKErrorFileOperationFailed, @"Unable to rename the script.", nil);
    }
    if (moveError && error) *error = moveError;
    return [result boolValue];
}

- (NSDictionary<NSString *, id> *)capabilityInfo {
    NSDictionary *config = nil;
    id<AutoAutomationAdapter> adapter = nil;
    @synchronized (self) {
        config = self.config ?: @{};
        adapter = self.adapter;
    }
    BOOL fileReadEnabled = AutoPermission(config, @"allowFileAccess", YES);
    BOOL fileWriteEnabled = fileReadEnabled &&
        AutoPermission(config, @"allowFileWrite", YES);
    NSMutableDictionary *result = [@{ @"runtime": @"JavaScriptCore",
                                      @"timers": @YES,
                                      @"parallelWorkers": @NO,
                                      @"interruptibleScripts": @(AutoPermission(config, @"interruptibleScripts", YES)),
                                      @"http": @(AutoBoolean(config[@"allowNetwork"], NO)),
                                      @"fileRead": @(fileReadEnabled),
                                      @"fileWrite": @(fileWriteEnabled),
                                      @"storage": @(AutoPermission(config, @"allowStorage", YES)),
                                      @"systemControl": @(AutoPermission(config, @"allowSystemControl", YES)),
                                      @"mediaLibraryWrite": @(AutoPermission(config, @"allowMediaLibrary", YES)) } mutableCopy];
    if ([adapter respondsToSelector:@selector(capabilities)]) result[@"automation"] = [adapter capabilities] ?: @{};
    return result;
}

- (void)performDebugAdapterBlock:(dispatch_block_t)block {
    if (!block) return;
    dispatch_async(self.debugAdapterQueue, block);
}

- (void)handleDebugRequest:(NSDictionary<NSString *,id> *)request response:(AutoDebugResponseHandler)response {
    NSDictionary *debugConfig = nil;
    id<AutoAutomationAdapter> rawAdapter = nil;
    @synchronized (self) {
        debugConfig = self.config ?: @{};
        rawAdapter = self.adapter;
    }
    NSDictionary *adapterCapabilities = [rawAdapter respondsToSelector:@selector(capabilities)] ? [rawAdapter capabilities] : nil;
    id<AutoAutomationAdapter> adapter = AutoBoolean(adapterCapabilities[@"requiresMainThread"], NO)
        ? (id<AutoAutomationAdapter>)[AutoMainThreadAdapterProxy proxyWithTarget:rawAdapter]
        : rawAdapter;
    NSString *type = [request[@"type"] isKindOfClass:NSString.class] ? request[@"type"] : @"";
    if ([type isEqualToString:@"ping"]) {
        response(@{@"ok": @YES, @"type": @"pong"});
        return;
    }
    if ([type isEqualToString:@"deviceInfo"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            response(@{@"ok": @YES, @"deviceInfo": [self getDeviceInfo] ?: @{}});
        });
        return;
    }
    if ([type isEqualToString:@"capabilities"]) {
        [self performDebugAdapterBlock:^{
            response(@{@"ok": @YES, @"capabilities": [self capabilityInfo] ?: @{}});
        }];
        return;
    }
    if ([type isEqualToString:@"inspectSnapshot"]) {
        NSDictionary *options = [request[@"options"] isKindOfClass:NSDictionary.class] ? request[@"options"] : @{};
        NSUInteger maxNodes = AutoDebugDefaultNodeLimit;
        if (AutoFiniteNumber(options[@"maxNodes"])) {
            double requested = [options[@"maxNodes"] doubleValue];
            if (requested > 0) maxNodes = MIN((NSUInteger)requested, AutoDebugMaximumNodeLimit);
        }
        [self performDebugAdapterBlock:^{
            NSDate *startedAt = [NSDate date];
            BOOL supportsSnapshot = [adapter respondsToSelector:@selector(nodeSnapshotWithMaxResults:error:)];
            if (!supportsSnapshot) {
                response(@{@"ok": @NO, @"error": @"The automation adapter does not support consistent node snapshots."});
                return;
            }
            NSError *screenshotError = nil;
            NSData *png = [adapter screenshotWithError:&screenshotError];
            if (!png || screenshotError) {
                response(@{@"ok": @NO, @"error": screenshotError.localizedDescription ?: @"Unable to capture screenshot."});
                return;
            }
            if (png.length > AutoScreenshotByteLimit(debugConfig)) {
                response(@{@"ok": @NO, @"error": @"Screenshot exceeds maxScreenshotBytes."});
                return;
            }
            NSError *nodeError = nil;
            NSArray *nodes = [adapter nodeSnapshotWithMaxResults:maxNodes error:&nodeError];
            if (!nodes || nodeError) {
                response(@{@"ok": @NO, @"error": nodeError.localizedDescription ?: @"Unable to inspect nodes."});
                return;
            }
            NSDictionary *deviceInfo = AutoValueOnMainThread(^id{ return [self getDeviceInfo]; }) ?: @{};
            response(@{ @"ok": @YES,
                        @"protocolVersion": @(AutoDebugProtocolVersion),
                        @"snapshotId": NSUUID.UUID.UUIDString,
                        @"capturedAtMs": @((long long)(NSDate.date.timeIntervalSince1970 * 1000.0)),
                        @"durationMs": @([NSDate.date timeIntervalSinceDate:startedAt] * 1000.0),
                        @"mimeType": @"image/png",
                        @"pngBase64": [png base64EncodedStringWithOptions:0],
                        @"deviceInfo": deviceInfo,
                        @"nodes": nodes,
                        @"nodeCount": @(nodes.count),
                        @"maxNodes": @(maxNodes),
                        @"truncated": @(nodes.count >= maxNodes) });
        }];
        return;
    }
    if ([type isEqualToString:@"screenshot"]) {
        [self performDebugAdapterBlock:^{
            NSError *error = nil;
            NSData *png = [adapter screenshotWithError:&error];
            if (!png || error) {
                response(@{@"ok": @NO, @"error": error.localizedDescription ?: @"Unable to capture screenshot."});
                return;
            }
            if (png.length > AutoScreenshotByteLimit(debugConfig)) {
                response(@{@"ok": @NO, @"error": @"Screenshot exceeds maxScreenshotBytes."});
                return;
            }
            response(@{@"ok": @YES, @"mimeType": @"image/png", @"pngBase64": [png base64EncodedStringWithOptions:0]});
        }];
        return;
    }
    if ([type isEqualToString:@"nodes"]) {
        [self performDebugAdapterBlock:^{
            BOOL supportsElements = [adapter respondsToSelector:@selector(elementsInfoForSelector:error:)];
            BOOL supportsSnapshot = [adapter respondsToSelector:@selector(nodeSnapshotWithMaxResults:error:)];
            if (!supportsElements && !supportsSnapshot) {
                response(@{@"ok": @NO, @"error": @"The automation adapter does not support node snapshots."});
                return;
            }
            id selector = [request[@"selector"] isKindOfClass:NSDictionary.class] ? request[@"selector"] : nil;
            NSError *error = nil;
            NSArray *nodes = nil;
            if (!selector && [adapter respondsToSelector:@selector(nodeSnapshotWithMaxResults:error:)]) {
                NSUInteger maxNodes = AutoDebugDefaultNodeLimit;
                if (AutoFiniteNumber(request[@"maxNodes"]) && [request[@"maxNodes"] doubleValue] > 0) {
                    maxNodes = MIN((NSUInteger)[request[@"maxNodes"] doubleValue], AutoDebugMaximumNodeLimit);
                }
                nodes = [adapter nodeSnapshotWithMaxResults:maxNodes error:&error];
            } else if (supportsElements) {
                nodes = [adapter elementsInfoForSelector:selector ?: @{@"visible": @YES, @"maxResults": @500} error:&error];
            } else {
                response(@{@"ok": @NO, @"error": @"The automation adapter does not support selector queries."});
                return;
            }
            if (!nodes || error) {
                response(@{@"ok": @NO, @"error": error.localizedDescription ?: @"Unable to inspect nodes."});
                return;
            }
            response(@{@"ok": @YES, @"nodes": nodes});
        }];
        return;
    }
    if ([type isEqualToString:@"pixelColor"]) {
        dispatch_async(self.debugAdapterQueue, ^{
            if (![adapter respondsToSelector:@selector(pixelColorAtX:y:error:)]) {
                response(@{@"ok": @NO, @"error": @"The automation adapter does not support pixel inspection."});
                return;
            }
            if (!AutoPayloadHasFiniteNumbers(request, @[@"x", @"y"])) {
                response(@{@"ok": @NO, @"error": @"Pixel coordinates must be finite numbers."});
                return;
            }
            NSError *error = nil;
            NSDictionary *color = [adapter pixelColorAtX:[request[@"x"] doubleValue]
                                                            y:[request[@"y"] doubleValue]
                                                        error:&error];
            response(color && !error
                ? @{@"ok": @YES, @"color": color}
                : @{@"ok": @NO, @"error": error.localizedDescription ?: @"Unable to inspect the pixel."});
        });
        return;
    }
    if ([type isEqualToString:@"findImage"]) {
        NSString *encoded = [request[@"templatePngBase64"] isKindOfClass:NSString.class] ? request[@"templatePngBase64"] : nil;
        NSString *assetName = AutoDebugAssetName(request[@"assetName"]);
        if (encoded.length == 0 && !assetName) {
            response(@{@"ok": @NO, @"error": @"Image template data or a deployed assetName is required."});
            return;
        }
        if (encoded.length > ((AutoDebugTemplateByteLimit + 2) / 3) * 4 + 8) {
            response(@{@"ok": @NO, @"error": @"Image template is missing or exceeds 512 KB."});
            return;
        }
        NSData *templateData = encoded.length > 0 ? [[NSData alloc] initWithBase64EncodedString:encoded options:0] : nil;
        if (encoded.length > 0 && (!templateData || templateData.length == 0 || templateData.length > AutoDebugTemplateByteLimit)) {
            response(@{@"ok": @NO, @"error": @"Image template is invalid or exceeds 512 KB."});
            return;
        }
        NSDictionary *options = [request[@"options"] isKindOfClass:NSDictionary.class] ? request[@"options"] : @{};
        dispatch_async(self.debugAdapterQueue, ^{
            NSString *path = nil;
            BOOL removesTemporaryFile = templateData != nil;
            if (templateData) {
                path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                    [[NSUUID.UUID UUIDString] stringByAppendingPathExtension:@"png"]];
                NSError *writeError = nil;
                if (![templateData writeToFile:path options:NSDataWritingAtomic error:&writeError]) {
                    response(@{@"ok": @NO, @"error": writeError.localizedDescription ?: @"Unable to stage the image template."});
                    return;
                }
            } else {
                NSError *pathError = nil;
                id resolved = AutoScriptFileOperation(@{ @"operation": @"resolvePath", @"path": AutoDebugAssetPath(assetName) },
                                                      debugConfig, &pathError);
                if (![resolved isKindOfClass:NSString.class] || pathError || ![[NSFileManager defaultManager] fileExistsAtPath:resolved]) {
                    response(@{@"ok": @NO, @"error": pathError.localizedDescription ?: @"The deployed image asset does not exist."});
                    return;
                }
                path = resolved;
            }
            NSError *matchError = nil;
            NSDictionary *match = [adapter findImageAtPath:path options:options error:&matchError];
            if (removesTemporaryFile) [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
            response(match && !matchError
                ? @{@"ok": @YES, @"match": match, @"assetPath": assetName ? AutoDebugAssetPath(assetName) : NSNull.null}
                : @{@"ok": @NO, @"error": matchError.localizedDescription ?: @"Image matching failed."});
        });
        return;
    }
    if ([type isEqualToString:@"testOCR"]) {
        if (![adapter respondsToSelector:@selector(ocrInRegion:error:)]) {
            response(@{@"ok": @NO, @"error": @"The automation adapter does not support OCR."});
            return;
        }
        NSDictionary *requestedRegion = [request[@"region"] isKindOfClass:NSDictionary.class] ? request[@"region"] : @{};
        NSMutableDictionary *region = [requestedRegion mutableCopy];
        for (NSString *key in @[@"x", @"y", @"width", @"height"]) {
            if (region[key] != nil && !AutoFiniteNumber(region[key])) {
                response(@{@"ok": @NO, @"error": @"OCR region values must be finite numbers."});
                return;
            }
        }
        NSUInteger requestedResults = AutoBoundedPositiveInteger(region[@"maxResults"], 100, 200);
        region[@"maxResults"] = @(requestedResults);
        [self performDebugAdapterBlock:^{
            NSError *ocrError = nil;
            NSArray *items = [adapter ocrInRegion:region error:&ocrError];
            response(items && !ocrError
                ? @{@"ok": @YES, @"items": items, @"count": @(items.count)}
                : @{@"ok": @NO, @"error": ocrError.localizedDescription ?: @"OCR failed."});
        }];
        return;
    }
    if ([type isEqualToString:@"nodeAction"]) {
        NSString *action = [request[@"action"] isKindOfClass:NSString.class]
            ? [request[@"action"] lowercaseString]
            : @"";
        id selector = [request[@"selector"] isKindOfClass:NSDictionary.class] ? request[@"selector"] : nil;
        BOOL hasPoint = AutoPayloadHasFiniteNumbers(request, @[@"x", @"y"]);
        if (![@[@"click", @"input", @"scroll"] containsObject:action] ||
            (!selector && !([action isEqualToString:@"click"] && hasPoint))) {
            response(@{@"ok": @NO, @"error": @"nodeAction requires click/input/scroll and a selector, or click coordinates."});
            return;
        }
        NSString *text = [request[@"text"] isKindOfClass:NSString.class] ? request[@"text"] : @"";
        if ([text lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 64 * 1024) {
            response(@{@"ok": @NO, @"error": @"Input text exceeds 64 KB."});
            return;
        }
        [self performDebugAdapterBlock:^{
            NSError *actionError = nil;
            BOOL ok = NO;
            if ([action isEqualToString:@"click"]) {
                if (selector) ok = [adapter click:selector error:&actionError];
                else if ([adapter respondsToSelector:@selector(clickAtX:y:error:)]) {
                    ok = [adapter clickAtX:[request[@"x"] doubleValue]
                                             y:[request[@"y"] doubleValue]
                                         error:&actionError];
                } else {
                    actionError = AutoMakeError(AutoSDKErrorAutomationUnavailable,
                                                @"The adapter does not support coordinate clicks.", nil);
                }
            } else if ([action isEqualToString:@"input"]) {
                ok = [adapter input:selector text:text error:&actionError];
            } else if ([adapter respondsToSelector:@selector(scrollIntoView:error:)]) {
                ok = [adapter scrollIntoView:selector error:&actionError];
            } else {
                actionError = AutoMakeError(AutoSDKErrorAutomationUnavailable,
                                            @"The adapter does not support scrollIntoView.", nil);
            }
            response(ok && !actionError
                ? @{@"ok": @YES, @"action": action}
                : @{@"ok": @NO, @"error": actionError.localizedDescription ?: @"Node action failed."});
        }];
        return;
    }
    if ([type isEqualToString:@"putScript"]) {
        NSString *name = AutoDebugScriptName(request[@"name"]);
        NSString *script = [request[@"script"] isKindOfClass:NSString.class] ? request[@"script"] : nil;
        NSUInteger byteLength = [script lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        NSUInteger configuredLimit = AutoConfiguredByteLimit(debugConfig, @"maxScriptBytes",
                                                               5 * 1024 * 1024, 64 * 1024 * 1024);
        NSUInteger limit = MIN(configuredLimit, AutoDebugScriptByteLimit);
        if (!name) {
            response(@{@"ok": @NO, @"error": @"Script name must be a safe .js filename using letters, numbers, dot, underscore, or hyphen."});
            return;
        }
        if (!script || byteLength == 0 || byteLength > limit) {
            response(@{@"ok": @NO, @"error": [NSString stringWithFormat:@"Script must contain 1 to %lu UTF-8 bytes.", (unsigned long)limit]});
            return;
        }
        NSError *writeError = nil;
        id result = AutoScriptFileOperation(@{ @"operation": @"writeText",
                                                @"path": AutoDebugScriptPath(name),
                                                @"text": script }, debugConfig, &writeError);
        response(result && !writeError
            ? @{@"ok": @YES, @"name": name, @"sizeBytes": @(byteLength)}
            : @{@"ok": @NO, @"error": writeError.localizedDescription ?: @"Unable to deploy the script."});
        return;
    }
    if ([type isEqualToString:@"putAsset"]) {
        NSString *name = AutoDebugAssetName(request[@"name"]);
        NSString *encoded = [request[@"dataBase64"] isKindOfClass:NSString.class] ? request[@"dataBase64"] : nil;
        if (!name) {
            response(@{@"ok": @NO, @"error": @"Asset name must be a safe PNG or JPEG filename."});
            return;
        }
        if (encoded.length == 0 || encoded.length > ((AutoDebugTemplateByteLimit + 2) / 3) * 4 + 8) {
            response(@{@"ok": @NO, @"error": @"Image asset is missing or exceeds 512 KB."});
            return;
        }
        NSData *data = [[NSData alloc] initWithBase64EncodedString:encoded options:0];
        if (!data || data.length == 0 || data.length > AutoDebugTemplateByteLimit) {
            response(@{@"ok": @NO, @"error": @"Image asset is invalid or exceeds 512 KB."});
            return;
        }
        NSError *writeError = nil;
        id result = AutoScriptFileOperation(@{ @"operation": @"writeBase64",
                                                @"path": AutoDebugAssetPath(name),
                                                @"text": encoded }, debugConfig, &writeError);
        response(result && !writeError
            ? @{@"ok": @YES, @"name": name, @"path": AutoDebugAssetPath(name), @"sizeBytes": @(data.length)}
            : @{@"ok": @NO, @"error": writeError.localizedDescription ?: @"Unable to deploy the image asset."});
        return;
    }
    if ([type isEqualToString:@"listAssets"]) {
        NSError *existsError = nil;
        id exists = AutoScriptFileOperation(@{ @"operation": @"exists", @"path": @"debug-assets" }, debugConfig, &existsError);
        if (existsError || ![exists boolValue]) {
            response(existsError ? @{@"ok": @NO, @"error": existsError.localizedDescription ?: @"Unable to inspect assets."}
                                 : @{@"ok": @YES, @"assets": @[]});
            return;
        }
        NSError *listError = nil;
        id listed = AutoScriptFileOperation(@{ @"operation": @"list", @"path": @"debug-assets" }, debugConfig, &listError);
        if (![listed isKindOfClass:NSArray.class] || listError) {
            response(@{@"ok": @NO, @"error": listError.localizedDescription ?: @"Unable to list assets."});
            return;
        }
        NSMutableArray *assets = [NSMutableArray array];
        for (NSDictionary *item in listed) {
            NSString *name = AutoDebugAssetName(item[@"name"]);
            if (name && ![item[@"isDirectory"] boolValue]) [assets addObject:@{ @"name": name, @"path": AutoDebugAssetPath(name), @"sizeBytes": item[@"size"] ?: @0 }];
        }
        response(@{@"ok": @YES, @"assets": assets});
        return;
    }
    if ([type isEqualToString:@"deleteAsset"]) {
        NSString *name = AutoDebugAssetName(request[@"name"]);
        if (!name) {
            response(@{@"ok": @NO, @"error": @"A valid deployed image asset name is required."});
            return;
        }
        NSError *removeError = nil;
        id result = AutoScriptFileOperation(@{ @"operation": @"remove", @"path": AutoDebugAssetPath(name) }, debugConfig, &removeError);
        response(result && !removeError ? @{@"ok": @YES, @"name": name}
                                       : @{@"ok": @NO, @"error": removeError.localizedDescription ?: @"Unable to delete the image asset."});
        return;
    }
    if ([type isEqualToString:@"listScripts"]) {
        NSError *listError = nil;
        NSArray *scripts = [self deployedScriptsWithError:&listError];
        if (!scripts || listError) {
            response(@{@"ok": @NO, @"error": listError.localizedDescription ?: @"Unable to list deployed scripts."});
            return;
        }
        response(@{@"ok": @YES, @"scripts": scripts});
        return;
    }
    if ([type isEqualToString:@"deleteScript"]) {
        NSString *name = AutoDebugScriptName(request[@"name"]);
        if (!name) {
            response(@{@"ok": @NO, @"error": @"A valid deployed .js script name is required."});
            return;
        }
        NSError *removeError = nil;
        BOOL result = [self deleteDeployedScriptNamed:name error:&removeError];
        response(result && !removeError
            ? @{@"ok": @YES, @"name": name}
            : @{@"ok": @NO, @"error": removeError.localizedDescription ?: @"Unable to delete the deployed script."});
        return;
    }
    if ([type isEqualToString:@"runStored"]) {
        NSString *name = AutoDebugScriptName(request[@"name"]);
        if (!name) {
            response(@{@"ok": @NO, @"error": @"A valid deployed .js script name is required."});
            return;
        }
        [self runDeployedScriptNamed:name completion:^(NSDictionary * _Nullable result, NSError * _Nullable error) {
            response(error
                ? @{@"ok": @NO, @"error": @{ @"domain": error.domain ?: @"",
                                                @"code": @(error.code),
                                                @"message": error.localizedDescription ?: @"Script failed." }}
                : @{@"ok": @YES, @"name": name, @"result": result ?: @{}});
        }];
        return;
    }
    if ([type isEqualToString:@"stop"]) {
        [self stopScript];
        response(@{@"ok": @YES});
        return;
    }
    if ([type isEqualToString:@"run"] || [type isEqualToString:@"runScript"]) {
        NSString *source = [request[@"script"] isKindOfClass:NSString.class] ? request[@"script"] : nil;
        if (source.length == 0) {
            response(@{@"ok": @NO, @"error": @"script is required."});
            return;
        }
        [self runScript:source completion:^(NSDictionary * _Nullable result, NSError * _Nullable error) {
            if (!error) {
                response(@{@"ok": @YES, @"result": result ?: @{}});
                return;
            }
            NSMutableDictionary *details = [@{ @"domain": error.domain ?: @"",
                                               @"code": @(error.code),
                                               @"message": error.localizedDescription ?: @"Script failed." } mutableCopy];
            if (error.userInfo[@"logs"]) details[@"logs"] = error.userInfo[@"logs"];
            response(@{@"ok": @NO, @"error": details});
        }];
        return;
    }
    response(@{@"ok": @NO, @"error": @"Unknown command."});
}

- (void)registerNativeMethod:(NSString *)methodName handler:(AutoNativeMethodHandler)handler {
    if (![methodName isKindOfClass:NSString.class] || methodName.length == 0 || methodName.length > 128 ||
        [methodName rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound || !handler) return;
    @synchronized (self) { self.nativeMethods[methodName] = [handler copy]; }
}

- (void)stopScript {
    id<AutoAutomationAdapter> adapter = nil;
    NSURLSessionTask *task = nil;
    @synchronized (self) {
        if (!self.running && !self.scriptTask) return;
        self.stopRequested = YES;
        adapter = self.activeAdapter ?: self.adapter;
        task = self.scriptTask;
        self.scriptTask = nil;
    }
    if ([adapter respondsToSelector:@selector(cancelCurrentOperations)]) [adapter cancelCurrentOperations];
    [task cancel];
}

- (void)requestStop {
    @synchronized (self) { self.stopRequested = YES; }
}

- (BOOL)shouldStop {
    @synchronized (self) { return self.stopRequested; }
}

- (void)runScript:(NSString *)scriptPathOrSource completion:(AutoScriptCompletion)completion {
    if (scriptPathOrSource.length == 0) {
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, AutoMakeError(AutoSDKErrorScriptNotFound, @"Script source is empty.", nil)); });
        return;
    }
    __block NSDictionary *runConfig = nil;
    __block id<AutoAutomationAdapter> runAdapter = nil;
    @synchronized (self) {
        if (self.running) {
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, AutoMakeError(AutoSDKErrorAlreadyRunning, @"Another script is already running.", nil)); });
            return;
        }
        self.running = YES;
        self.stopRequested = NO;
        runConfig = self.config ?: @{};
        runAdapter = self.adapter ?: [AutoUnavailableAdapter new];
        self.activeAdapter = runAdapter;
    }
    [self loadScript:scriptPathOrSource config:runConfig completion:^(NSString * _Nullable source, NSError * _Nullable error) {
        if (error) { [self finishWithResult:nil error:error completion:completion]; return; }
        if ([self shouldStop]) {
            [self finishWithResult:nil error:AutoMakeError(AutoSDKErrorScriptCancelled, @"Script cancelled.", nil) completion:completion];
            return;
        }
        dispatch_async(self.scriptQueue, ^{ [self evaluateScript:source config:runConfig adapter:runAdapter completion:completion]; });
    }];
}

- (void)loadScript:(NSString *)value config:(NSDictionary *)config completion:(void (^)(NSString * _Nullable source, NSError * _Nullable error))completion {
    NSUInteger maxBytes = AutoConfiguredByteLimit(config, @"maxScriptBytes",
                                                   5 * 1024 * 1024, 64 * 1024 * 1024);
    BOOL looksLikeURL = AutoScriptValueLooksLikeURL(value);
    NSURL *url = looksLikeURL ? [NSURL URLWithString:value] : nil;
    if (looksLikeURL && !url) {
        completion(nil, AutoMakeError(AutoSDKErrorScriptReadFailed, @"Script URL is invalid.", nil));
        return;
    }
    NSString *scheme = url.scheme.lowercaseString;
    if (looksLikeURL && scheme.length > 0 && ![scheme isEqualToString:@"file"] &&
        ![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) {
        completion(nil, AutoMakeError(AutoSDKErrorScriptReadFailed, @"Only file://, http:// and https:// script URLs are supported.", nil));
        return;
    }
    if ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) {
        if (!AutoBoolean(config[@"allowRemoteScripts"], NO)) {
            completion(nil, AutoMakeError(AutoSDKErrorScriptReadFailed, @"Remote scripts are disabled by configuration.", nil));
            return;
        }
        id configuredHostValue = config[@"allowedRemoteScriptHosts"] ?: config[@"allowedNetworkHosts"];
        BOOL hasHostAllowlist = NO;
        NSError *hostConfigurationError = nil;
        NSArray *allowedHosts = AutoValidatedHostAllowlist(configuredHostValue,
                                                           &hasHostAllowlist,
                                                           &hostConfigurationError);
        if (!allowedHosts) {
            completion(nil, hostConfigurationError);
            return;
        }
        if (url.host.length == 0) {
            completion(nil, AutoMakeError(AutoSDKErrorScriptReadFailed, @"Remote script URL has no host.", nil));
            return;
        }
        if (hasHostAllowlist) {
            BOOL allowed = NO;
            for (id host in allowedHosts) {
                if ([host isKindOfClass:NSString.class] && [url.host caseInsensitiveCompare:host] == NSOrderedSame) { allowed = YES; break; }
            }
            if (!allowed) {
                completion(nil, AutoMakeError(AutoSDKErrorScriptReadFailed, @"Remote script host is not allowed.", nil));
                return;
            }
        }
        AutoHTTPRedirectPolicy *policy = [AutoHTTPRedirectPolicy new];
        policy.followsRedirects = YES;
        policy.allowedHosts = hasHostAllowlist ? allowedHosts : nil;
        NSTimeInterval remoteTimeout = AutoFiniteDouble(config[@"remoteScriptTimeout"], 0);
        NSMutableURLRequest *remoteRequest = [NSMutableURLRequest requestWithURL:url];
        remoteRequest.timeoutInterval = (isfinite(remoteTimeout) && remoteTimeout > 0) ? MIN(120, remoteTimeout) : 30;
        NSURLSession *session = AutoHTTPSharedSession(self.urlProtocolClasses);
        AutoHTTPRedirectRouter *router = AutoHTTPSharedRouter();
        __weak NSURLSessionDownloadTask *weakTask = nil;
        NSObject *sizeLimitLock = [NSObject new];
        __block BOOL sizeLimitExceeded = NO;
        __block dispatch_source_t sizeMonitor = nil;
        NSURLSessionDownloadTask *task = [session downloadTaskWithRequest:remoteRequest completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
            if (sizeMonitor) dispatch_source_cancel(sizeMonitor);
            @synchronized (self) { self.scriptTask = nil; }
            [router removePolicyForTask:weakTask];
            BOOL exceeded = NO;
            @synchronized (sizeLimitLock) { exceeded = sizeLimitExceeded; }
            if (exceeded) {
                completion(nil, AutoMakeError(AutoSDKErrorScriptTooLarge, @"Remote script exceeds the configured size limit.", nil));
                return;
            }
            if (error) {
                AutoSDKErrorCode code = ([self shouldStop] && error.code == NSURLErrorCancelled) ? AutoSDKErrorScriptCancelled : AutoSDKErrorScriptReadFailed;
                NSString *message = code == AutoSDKErrorScriptCancelled ? @"Script cancelled." : @"Unable to download script.";
                completion(nil, AutoMakeError(code, message, error));
                return;
            }
            if (![response isKindOfClass:NSHTTPURLResponse.class] || ((NSHTTPURLResponse *)response).statusCode < 200 || ((NSHTTPURLResponse *)response).statusCode >= 300) {
                completion(nil, AutoMakeError(AutoSDKErrorScriptReadFailed, @"Remote script returned a non-success HTTP status.", nil));
                return;
            }
            if (!location) {
                completion(nil, AutoMakeError(AutoSDKErrorScriptReadFailed, @"Remote script download did not produce a file.", nil));
                return;
            }
            NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:location.path error:nil];
            if ([attributes[NSFileSize] unsignedLongLongValue] > maxBytes) {
                completion(nil, AutoMakeError(AutoSDKErrorScriptTooLarge, @"Remote script exceeds the configured size limit.", nil));
                return;
            }
            NSError *readError = nil;
            NSData *data = [NSData dataWithContentsOfURL:location options:NSDataReadingMappedIfSafe error:&readError];
            if (!data) {
                completion(nil, AutoMakeError(AutoSDKErrorScriptReadFailed, @"Unable to read the downloaded script.", readError));
                return;
            }
            if (data.length > maxBytes) {
                completion(nil, AutoMakeError(AutoSDKErrorScriptTooLarge, @"Remote script exceeds the configured size limit.", nil));
                return;
            }
            NSString *source = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            completion(source, source ? nil : AutoMakeError(AutoSDKErrorScriptReadFailed, @"Script is not valid UTF-8.", nil));
        }];
        weakTask = task;
        sizeMonitor = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                             dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
        dispatch_source_set_timer(sizeMonitor, DISPATCH_TIME_NOW,
                                  (uint64_t)(0.1 * NSEC_PER_SEC),
                                  (uint64_t)(0.02 * NSEC_PER_SEC));
        dispatch_source_set_event_handler(sizeMonitor, ^{
            NSURLSessionDownloadTask *activeTask = weakTask;
            if (!activeTask) return;
            int64_t expectedBytes = activeTask.countOfBytesExpectedToReceive;
            int64_t receivedBytes = activeTask.countOfBytesReceived;
            if ((expectedBytes > 0 && (uint64_t)expectedBytes > maxBytes) ||
                (receivedBytes > 0 && (uint64_t)receivedBytes > maxBytes)) {
                @synchronized (sizeLimitLock) { sizeLimitExceeded = YES; }
                [activeTask cancel];
            }
        });
        [router setPolicy:policy forTask:task];
        BOOL cancelBeforeStart = NO;
        @synchronized (self) {
            self.scriptTask = task;
            cancelBeforeStart = self.stopRequested;
        }
        dispatch_resume(sizeMonitor);
        if (cancelBeforeStart) [task cancel];
        else [task resume];
        return;
    }
    NSString *path = url.isFileURL ? url.path : value;
    BOOL isPath = [[NSFileManager defaultManager] fileExistsAtPath:path];
    if (!isPath) {
        NSString *bundlePath = [[NSBundle mainBundle] pathForResource:value.stringByDeletingPathExtension ofType:value.pathExtension.length ? value.pathExtension : @"js"];
        if (bundlePath) path = bundlePath, isPath = YES;
    }
    if (!isPath) {
        NSString *trimmedValue = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        BOOL containsPathSeparator = [trimmedValue containsString:@"/"] || [trimmedValue containsString:@"\\"];
        BOOL containsWhitespace = [trimmedValue rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location != NSNotFound;
        BOOL hasAlphabeticCharacter = [trimmedValue rangeOfCharacterFromSet:NSCharacterSet.letterCharacterSet].location != NSNotFound;
        NSCharacterSet *codeCharacters = [NSCharacterSet characterSetWithCharactersInString:@"(){};=+*%<>!?&|^'\"`,"];
        BOOL containsCodeCharacters = [trimmedValue rangeOfCharacterFromSet:codeCharacters].location != NSNotFound;
        BOOL looksLikePath = [trimmedValue hasPrefix:@"/"] || [trimmedValue hasPrefix:@"./"] ||
                             [trimmedValue hasPrefix:@"../"] || [trimmedValue hasPrefix:@"~/"] ||
                             [trimmedValue hasPrefix:@"file:"] ||
                             ([trimmedValue.lowercaseString hasSuffix:@".js"] &&
                              !containsWhitespace && !containsCodeCharacters) ||
                             (containsPathSeparator && !containsWhitespace && hasAlphabeticCharacter && !containsCodeCharacters);
        if (looksLikePath) {
            completion(nil, AutoMakeError(AutoSDKErrorScriptNotFound, @"Script path does not exist.", nil));
            return;
        }
        if ([value lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > maxBytes) {
            completion(nil, AutoMakeError(AutoSDKErrorScriptTooLarge, @"Script exceeds the configured size limit.", nil));
            return;
        }
        completion(value, nil);
        return;
    }
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    if ([attributes[NSFileSize] unsignedIntegerValue] > maxBytes) {
        completion(nil, AutoMakeError(AutoSDKErrorScriptTooLarge, @"Script exceeds the configured size limit.", nil));
        return;
    }
    NSError *error = nil;
    NSData *scriptData = [NSData dataWithContentsOfURL:[NSURL fileURLWithPath:path]
                                               options:NSDataReadingMappedIfSafe
                                                 error:&error];
    if (!scriptData) {
        completion(nil, AutoMakeError(AutoSDKErrorScriptReadFailed, @"Unable to read script.", error));
        return;
    }
    if (scriptData.length > maxBytes) {
        completion(nil, AutoMakeError(AutoSDKErrorScriptTooLarge, @"Script exceeds the configured size limit.", nil));
        return;
    }
    NSString *source = [[NSString alloc] initWithData:scriptData encoding:NSUTF8StringEncoding];
    completion(source, source ? nil : AutoMakeError(AutoSDKErrorScriptReadFailed, @"Script is not valid UTF-8.", nil));
}

- (void)evaluateScript:(NSString *)source config:(NSDictionary *)config adapter:(id<AutoAutomationAdapter>)scriptAdapter completion:(AutoScriptCompletion)completion {
    @autoreleasepool {
    NSDate *startDate = [NSDate date];
    JSContext *context = [JSContext new];
    AutoJSBridge *bridge = [AutoJSBridge new];
    AutoJSConsole *console = [AutoJSConsole new];
    console.emitToSystemLog = AutoBoolean(config[@"debugLogging"], NO);
    NSUInteger maximumLogEntries = AutoBoundedPositiveInteger(config[@"maxLogEntries"], 0, 10000);
    if (maximumLogEntries > 0) console.maximumEntries = MIN(maximumLogEntries, (NSUInteger)10000);
    NSUInteger maximumLogMessageLength = AutoBoundedPositiveInteger(config[@"maxLogMessageLength"], 0, 256 * 1024);
    if (maximumLogMessageLength > 0) console.maximumMessageLength = MIN(maximumLogMessageLength, (NSUInteger)(256 * 1024));
    console.maximumTotalBytes = AutoConfiguredByteLimit(config, @"maxLogBytes",
                                                         8 * 1024 * 1024, 32 * 1024 * 1024);
    bridge.engine = self;
    bridge.config = config ?: @{};
    NSDictionary *adapterCapabilities = [scriptAdapter respondsToSelector:@selector(capabilities)]
        ? [scriptAdapter capabilities]
        : nil;
    bridge.adapter = AutoBoolean(adapterCapabilities[@"requiresMainThread"], NO)
        ? (id<AutoAutomationAdapter>)[AutoMainThreadAdapterProxy proxyWithTarget:scriptAdapter]
        : scriptAdapter;
    context.exceptionHandler = ^(JSContext *ctx, JSValue *exception) {
        ctx.exception = exception;
    };
    context[@"__bridge"] = bridge;
    context[@"__console"] = console;
    JSValue *drainTimers = [context evaluateScript:AutoBootstrapScript()];
    if (context.exception) {
        NSString *message = [context.exception toString] ?: @"Unable to initialize the AutoSDK JavaScript API.";
        NSError *bootstrapError = AutoMakeError(AutoSDKErrorJavaScriptException, message, nil);
        [self finishWithResult:nil error:bootstrapError completion:completion];
        return;
    }
    NSTimeInterval timeout = AutoFiniteDouble(config[@"scriptTimeout"], 0);
    timeout = (isfinite(timeout) && timeout > 0) ? MIN(timeout, 3600.0) : 300.0;
    NSObject *executionState = [NSObject new];
    NSTimeInterval executionDeadline = NSProcessInfo.processInfo.systemUptime + timeout;
    __block BOOL executionFinished = NO;
    __block BOOL timedOut = NO;
    // One-shot dispatch timer instead of a blocking wait, so a long-running
    // script does not occupy a global utility thread for the whole budget.
    dispatch_source_t watchdog = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                                        dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    if (watchdog) {
        dispatch_source_set_timer(watchdog,
                                  dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)),
                                  DISPATCH_TIME_FOREVER,
                                  (uint64_t)(0.05 * NSEC_PER_SEC));
        dispatch_source_set_event_handler(watchdog, ^{
            @synchronized (executionState) {
                if (!executionFinished) timedOut = YES;
            }
            [self requestStop];
            if ([scriptAdapter respondsToSelector:@selector(cancelCurrentOperations)]) {
                [scriptAdapter cancelCurrentOperations];
            }
            dispatch_source_cancel(watchdog);
        });
        dispatch_resume(watchdog);
    }
    JSValue *value = [context evaluateScript:source ?: @""];
    if (!context.exception && ![self shouldStop]) [drainTimers callWithArguments:@[]];
    BOOL didTimeOut = NO;
    @synchronized (executionState) {
        executionFinished = YES;
        if (timedOut || NSProcessInfo.processInfo.systemUptime >= executionDeadline) didTimeOut = YES;
    }
    if (watchdog) dispatch_source_cancel(watchdog);
    NSError *error = nil;
    if (didTimeOut) error = AutoMakeError(AutoSDKErrorScriptTimeout, @"Script execution timed out.", nil);
    else if ([self shouldStop]) error = AutoMakeError(AutoSDKErrorScriptCancelled, @"Script cancelled.", nil);
    else if (context.exception) {
        NSString *exceptionMessage = [context.exception toString];
        NSString *message = [exceptionMessage isKindOfClass:NSString.class] ? exceptionMessage : @"JavaScript exception";
        error = AutoMakeError(AutoSDKErrorJavaScriptException, message, nil);
    }
    else if (bridge.lastError) error = bridge.lastError;
    if (error && console.entries.count > 0) {
        NSMutableDictionary *userInfo = [error.userInfo mutableCopy] ?: [NSMutableDictionary dictionary];
        userInfo[@"logs"] = [console.entries copy];
        error = [NSError errorWithDomain:error.domain code:error.code userInfo:userInfo];
    }
    NSDictionary *result = error ? nil : @{@"success": @YES,
                                           @"value": AutoBoundedJSResult(value),
                                           @"logs": [console.entries copy],
                                           @"durationMs": @([[NSDate date] timeIntervalSinceDate:startDate] * 1000.0)};
    [self finishWithResult:result error:error completion:completion];
    }
}

- (void)finishWithResult:(NSDictionary *)result error:(NSError *)error completion:(AutoScriptCompletion)completion {
    @synchronized (self) {
        self.running = NO;
        self.stopRequested = NO;
        self.activeAdapter = nil;
    }
    dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(result, error); });
}

- (NSDictionary<NSString *,id> *)getDeviceInfo {
    if (!NSThread.isMainThread) {
        return AutoValueOnMainThread(^id{ return [self getDeviceInfo]; }) ?: @{};
    }
    id<AutoAutomationAdapter> adapter = nil;
    @synchronized (self) { adapter = self.adapter; }
    UIDevice *device = UIDevice.currentDevice;
    BOOL batteryMonitoringWasEnabled = device.batteryMonitoringEnabled;
    if (!batteryMonitoringWasEnabled) device.batteryMonitoringEnabled = YES;
    UIInterfaceOrientation orientation = UIInterfaceOrientationUnknown;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:UIWindowScene.class] && scene.activationState == UISceneActivationStateForegroundActive) {
            orientation = ((UIWindowScene *)scene).interfaceOrientation;
            break;
        }
    }
    NSString *orientationName = @"unknown";
    if (UIInterfaceOrientationIsPortrait(orientation)) orientationName = orientation == UIInterfaceOrientationPortraitUpsideDown ? @"portraitUpsideDown" : @"portrait";
    else if (UIInterfaceOrientationIsLandscape(orientation)) orientationName = orientation == UIInterfaceOrientationLandscapeLeft ? @"landscapeLeft" : @"landscapeRight";
    NSBundle *bundle = NSBundle.mainBundle;
    float batteryLevel = device.batteryLevel;
    BOOL charging = device.batteryState == UIDeviceBatteryStateCharging || device.batteryState == UIDeviceBatteryStateFull;
    if (!batteryMonitoringWasEnabled) device.batteryMonitoringEnabled = NO;
    NSMutableDictionary *info = [@{ @"systemName": device.systemName ?: @"",
                                    @"systemVersion": device.systemVersion ?: @"",
                                    @"model": device.model ?: @"",
                                    @"name": device.name ?: @"",
                                    @"deviceId": device.identifierForVendor.UUIDString ?: @"",
                                    @"batteryLevel": batteryLevel < 0 ? [NSNull null] : @(batteryLevel * 100.0),
                                    @"isCharging": @(charging),
                                    @"orientation": orientationName,
                                    @"bundleId": bundle.bundleIdentifier ?: @"",
                                    @"appVersion": [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"",
                                    @"appBuild": [bundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"" } mutableCopy];
    NSDictionary *adapterInfo = [adapter deviceInfo];
    if (adapterInfo) [info addEntriesFromDictionary:adapterInfo];
    return info;
}

- (NSDictionary<NSString *,id> *)deviceMemoryInfo {
    uint64_t totalBytes = (uint64_t)NSProcessInfo.processInfo.physicalMemory;
    uint64_t freeBytes = 0;
    uint64_t appUsedBytes = 0;
    mach_port_t host = mach_host_self();
    vm_size_t pageSize = 0;
    if (host_page_size(host, &pageSize) == KERN_SUCCESS) {
        vm_statistics64_data_t stats;
        mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
        if (host_statistics64(host, HOST_VM_INFO64, (host_info64_t)&stats, &count) == KERN_SUCCESS) {
            freeBytes = (uint64_t)stats.free_count * pageSize;
        }
    }
    struct task_vm_info info;
    mach_msg_type_number_t taskCount = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &taskCount) == KERN_SUCCESS) {
        appUsedBytes = (uint64_t)info.phys_footprint;
    }
    mach_port_deallocate(mach_task_self(), host);
    return @{ @"totalBytes": @(totalBytes),
              @"freeBytes": @(freeBytes),
              @"appUsedBytes": @(appUsedBytes) };
}

@end
