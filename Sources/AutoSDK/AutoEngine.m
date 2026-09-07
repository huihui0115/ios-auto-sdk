#import "include/AutoEngine.h"
#import "include/AutoDebugServer.h"
#import "include/AutoSDKError.h"
#import "AutoScriptSupport.h"
#import "AutoBootstrapScript.h"
#import "AutoHTTPSupport.h"
#import "AutoSystemOperations.h"
#import "AutoBackgroundLease.h"
#import "AutoResourcePolicy.h"
#import <JavaScriptCore/JavaScriptCore.h>
#import <UIKit/UIKit.h>
#import <Photos/Photos.h>
#import <ImageIO/ImageIO.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <WebKit/WebKit.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <UserNotifications/UserNotifications.h>
#import <Vision/Vision.h>
#import <sqlite3.h>
#import <CoreLocation/CoreLocation.h>
#import <NetworkExtension/NetworkExtension.h>
#import <mach/mach.h>
#include <math.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <arpa/inet.h>

@interface AutoWebMessageHandler : NSObject <WKScriptMessageHandler>
@property (nonatomic, copy) void (^onMessage)(WKScriptMessage * _Nonnull);
@end

@interface AutoWebSocketDelegate : NSObject <NSURLSessionWebSocketDelegate>
@property (nonatomic, strong) NSNumber *handle;
@end

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
- (id)invokeScreenshotRegion:(JSValue *)payload;
- (id)invokeFindImage:(JSValue *)payload;
- (id)invokeFindColor:(JSValue *)payload;
- (id)invokePixelColor:(JSValue *)payload;
- (id)invokeCompareColors:(JSValue *)payload;
- (id)invokeFindMultiColor:(JSValue *)payload;
- (id)invokeFindColorEx:(JSValue *)payload;
- (id)invokeFindNotColor:(JSValue *)payload;
- (id)invokeHTTP:(JSValue *)payload;
- (id)invokeOCR:(JSValue *)region;
- (id)invokeExists:(JSValue *)selector;
- (id)invokeFindElement:(JSValue *)selector;
- (id)invokeFindElements:(JSValue *)selector;
- (id)invokeNodeSnapshot:(JSValue *)payload;
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
- (id)invokeLastError;
- (id)invokeNative:(JSValue *)payload;
- (id)invokeExecAsync:(JSValue *)payload;
- (id)invokeExecOp:(JSValue *)payload;
@end

@protocol AutoConsoleExport <JSExport>
- (void)log:(JSValue *)value;
- (void)warn:(JSValue *)value;
- (void)error:(JSValue *)value;
@end

@class AutoEngine;

@protocol AutoSystemStatusProviding <NSObject>
- (BOOL)autoLowPowerModeEnabled;
- (BOOL)autoLocationServicesEnabled;
- (CLAuthorizationStatus)autoLocationAuthorizationStatus;
@end

@interface AutoJSBridge : NSObject <AutoJSExport>
@property (nonatomic, weak) AutoEngine *engine;
@property (nonatomic, strong) id<AutoAutomationAdapter> adapter;
@property (nonatomic, copy) NSDictionary *config;
@property (nonatomic, strong) NSError *lastError;
@property (atomic, assign) BOOL threadCancelled;
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

@interface AutoAsyncThread : NSObject
@property (nonatomic, strong) JSContext *context;
@property (nonatomic, strong) AutoJSBridge *bridge;
@property (nonatomic, strong) dispatch_queue_t queue;
@property (atomic, assign) BOOL finished;
@property (atomic, assign) BOOL cancelled;
@property (atomic, strong) id result;
@property (atomic, strong) NSError *error;
@end
@implementation AutoAsyncThread
@end

@interface AutoEngine () <AVAudioPlayerDelegate>
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
@property (nonatomic, strong) AutoBackgroundLease *backgroundLease;
@property (nonatomic, strong) NSUUID *activeRunIdentifier;
@property (atomic, copy) NSString *stopReason;
@property (nonatomic, strong) NSMutableArray<AVAudioPlayer *> *audioPlayers;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, AVAudioPlayer *> *audioPlayersById;
@property (nonatomic, assign) NSUInteger audioPlayerIdCounter;
@property (nonatomic, strong) NSMutableArray<AutoAsyncThread *> *asyncThreads;
@property (nonatomic, assign) BOOL audioStopWhenScriptEnd;
@property (nonatomic, strong) AVSpeechSynthesizer *speechSynthesizer;
@property (nonatomic, assign) BOOL speechStopWhenScriptEnd;
@property (nonatomic, strong) NSMutableDictionary<NSString *, id> *webViews;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<id> *> *webViewMessages;
@property (nonatomic, strong) NSMutableDictionary<NSString *, id> *webViewMessageHandlers;
@property (nonatomic, assign) NSUInteger webViewSequence;
@property (atomic, copy) NSString *currentScriptSource;
@property (nonatomic, strong) NSMutableDictionary<NSString *, id> *screenDraws;
@property (nonatomic, assign) NSUInteger screenDrawSequence;
@property (nonatomic, strong) UIWindow *overlayWindow;
@property (nonatomic, strong) UIView *floatBallView;
@property (nonatomic, strong) UILabel *floatBallTitleLabel;
@property (nonatomic, strong) UIView *floatLogView;
@property (nonatomic, strong) UITextView *floatLogTextView;
@property (nonatomic, strong) NSMutableArray<NSString *> *floatLogLines;
@property (atomic, strong, nullable) id<AutoSystemStatusProviding> systemStatusProviderForTesting;
- (void)loadScript:(NSString *)value config:(NSDictionary *)config completion:(void (^)(NSString * _Nullable source, NSError * _Nullable error))completion;
- (void)evaluateScript:(NSString *)source config:(NSDictionary *)config adapter:(id<AutoAutomationAdapter>)adapter completion:(AutoScriptCompletion)completion;
- (void)finishWithResult:(NSDictionary * _Nullable)result error:(NSError * _Nullable)error completion:(AutoScriptCompletion)completion;
- (void)cleanupOverlayUI;
- (void)stopAllAudioPlayback;
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
static NSString *AutoAppSchemeForName(NSString *name) {
    if (name.length == 0) return nil;
    static NSDictionary<NSString *, NSString *> *autoAppSchemes = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        autoAppSchemes = @{
            // WeChat
            @"weixin": @"weixin://", @"wechat": @"weixin://", @"微信": @"weixin://", @"com.tencent.xin": @"weixin://",
            // Alipay
            @"alipay": @"alipays://platformapi/startapp?saId=10000007", @"支付宝": @"alipays://platformapi/startapp?saId=10000007", @"com.alipay.iphoneclient": @"alipays://platformapi/startapp?saId=10000007",
            // Taobao / Tmall
            @"taobao": @"taobao://", @"淘宝": @"taobao://", @"com.taobao.taobao": @"taobao://",
            @"tmall": @"tmall://", @"天猫": @"tmall://",
            // JD
            @"jd": @"openapp.jdmobile://", @"jingdong": @"openapp.jdmobile://", @"京东": @"openapp.jdmobile://", @"com.360buy.jdmobile": @"openapp.jdmobile://",
            // Pinduoduo
            @"pinduoduo": @"pinduoduo://", @"pdd": @"pinduoduo://", @"拼多多": @"pinduoduo://",
            // Douyin
            @"douyin": @"snssdk1128://", @"抖音": @"snssdk1128://", @"com.ss.iphone.ugc.aweme": @"snssdk1128://",
            // Kuaishou
            @"kuaishou": @"kwai://", @"快手": @"kwai://",
            // Meituan / Dianping / Eleme
            @"meituan": @"imeituan://", @"美团": @"imeituan://", @"com.meituan.imeituan": @"imeituan://",
            @"dianping": @"dianping://", @"大众点评": @"dianping://", @"com.dianping.v1": @"dianping://",
            @"eleme": @"eleme://", @"饿了么": @"eleme://",
            // QQ / Weibo
            @"qq": @"mqq://", @"mqq": @"mqq://", @"com.tencent.mqq": @"mqq://",
            @"weibo": @"sinaweibo://", @"sinaweibo": @"sinaweibo://", @"微博": @"sinaweibo://", @"com.sina.weibo": @"sinaweibo://",
            // Zhihu / Bilibili / Xiaohongshu
            @"zhihu": @"zhihu://", @"知乎": @"zhihu://", @"com.zhihu.ios": @"zhihu://",
            @"bilibili": @"bilibili://", @"bili": @"bilibili://", @"哔哩哔哩": @"bilibili://",
            @"xiaohongshu": @"xhsdiscover://", @"xhs": @"xhsdiscover://", @"小红书": @"xhsdiscover://", @"com.xingin.xhs": @"xhsdiscover://",
            // Video: Youku / iQiyi / Tencent Video
            @"youku": @"youku://", @"优酷": @"youku://", @"com.youku.YouKu": @"youku://",
            @"iqiyi": @"iqiyi://", @"爱奇艺": @"iqiyi://", @"com.qiyi.video": @"iqiyi://",
            @"tencentvideo": @"tenvideo://", @"tenvideo": @"tenvideo://", @"腾讯视频": @"tenvideo://", @"com.tencent.live4iphone": @"tenvideo://",
            // Music: NetEase / QQ Music / Kugou
            @"wangyiyun": @"orpheus://", @"nemusic": @"orpheus://", @"netease": @"orpheus://", @"网易云音乐": @"orpheus://", @"com.netease.cloudmusic": @"orpheus://",
            @"qqmusic": @"qqmusic://", @"QQ音乐": @"qqmusic://", @"com.tencent.QQMusic": @"qqmusic://",
            @"kugou": @"kugou://", @"酷狗": @"kugou://",
            // Douban / Ctrip
            @"douban": @"douban://", @"豆瓣": @"douban://", @"com.douban.frodo": @"douban://",
            @"ctrip": @"ctrip://", @"携程": @"ctrip://", @"com.ctrip.trip": @"ctrip://",
            // Maps: Gaode / Baidu
            @"gaode": @"iosamap://", @"amap": @"iosamap://", @"高德地图": @"iosamap://", @"com.autonavi.minimap": @"iosamap://",
            @"baidumap": @"baidumap://", @"百度地图": @"baidumap://", @"com.baidu.BaiduMap": @"baidumap://",
            // Didi / DingTalk / WeCom / Feishu
            @"didi": @"didihybird://", @"滴滴": @"didihybird://", @"com.sdu.didi.psnger": @"didihybird://",
            @"dingtalk": @"dingtalk://", @"钉钉": @"dingtalk://", @"com.laiwang.DingTalk": @"dingtalk://",
            @"wecom": @"wxwork://", @"wxwork": @"wxwork://", @"企业微信": @"wxwork://", @"com.tencent.wework": @"wxwork://",
            @"feishu": @"feishu://", @"lark": @"feishu://", @"飞书": @"feishu://", @"com.ss.android.lark": @"feishu://",
            // News / Search / Mail
            @"toutiao": @"snssdk36://", @"今日头条": @"snssdk36://",
            @"baidu": @"baiduboxapp://", @"百度": @"baiduboxapp://",
            @"qqmail": @"qqmail://", @"QQ邮箱": @"qqmail://", @"com.tencent.qqmail": @"qqmail://",
            // International
            @"telegram": @"tg://", @"tg": @"tg://", @"ph.telegra.Telegraph": @"tg://",
            @"whatsapp": @"whatsapp://", @"net.whatsapp.WhatsApp": @"whatsapp://",
            @"facebook": @"fb://", @"fb": @"fb://", @"com.facebook.Facebook": @"fb://",
            @"instagram": @"instagram://", @"com.burbn.instagram": @"instagram://",
            @"twitter": @"twitter://", @"x": @"twitter://", @"com.twitter.twitter": @"twitter://",
            @"youtube": @"youtube://", @"com.google.ios.youtube": @"youtube://",
            @"chrome": @"googlechrome://", @"googlechrome": @"googlechrome://", @"com.google.chrome.ios": @"googlechrome://",
            @"gmail": @"googlegmail://", @"com.google.Gmail": @"googlegmail://",
            @"spotify": @"spotify:", @"com.spotify.client": @"spotify:",
            @"netflix": @"nflx://", @"com.netflix.Netflix": @"nflx://",
            // Apple system apps
            @"applemusic": @"music://", @"music": @"music://", @"苹果音乐": @"music://", @"com.apple.Music": @"music://",
            @"appletv": @"tv://", @"tv": @"tv://", @"com.apple.tv": @"tv://",
            @"podcasts": @"podcasts://", @"播客": @"podcasts://", @"com.apple.podcasts": @"podcasts://",
            @"books": @"ibooks://", @"ibooks": @"ibooks://", @"图书": @"ibooks://", @"com.apple.iBooks": @"ibooks://",
            @"applemaps": @"maps://", @"applemap": @"maps://", @"苹果地图": @"maps://", @"com.apple.Maps": @"maps://",
            @"weather": @"weather://", @"天气": @"weather://", @"com.apple.weather": @"weather://",
            @"clock": @"clock-app://", @"时钟": @"clock-app://", @"com.apple.mobiletimer": @"clock-app://",
            @"photosapp": @"photos-redirect://", @"照片": @"photos-redirect://", @"com.apple.mobileslideshow": @"photos-redirect://",
            @"camera": @"camera://", @"相机": @"camera://", @"com.apple.camera": @"camera://",
            @"settingsapp": @"app-settings:", @"设置": @"app-settings:", @"com.apple.Preferences": @"app-settings:",
            @"contacts": @"contacts://", @"通讯录": @"contacts://", @"com.apple.MobileAddressBook": @"contacts://",
            @"calendarapp": @"calshow://", @"日历": @"calshow://", @"com.apple.mobilecal": @"calshow://",
            @"notes": @"mobilenotes://", @"备忘录": @"mobilenotes://", @"com.apple.mobilenotes": @"mobilenotes://",
            @"reminders": @"x-apple-reminderkit://", @"提醒事项": @"x-apple-reminderkit://", @"com.apple.reminders": @"x-apple-reminderkit://",
            @"mail": @"message://", @"邮件": @"message://", @"com.apple.mobilemail": @"message://",
            @"messages": @"sms://", @"短信": @"sms://", @"com.apple.MobileSMS": @"sms://",
            @"phone": @"tel://", @"电话": @"tel://", @"com.apple.mobilephone": @"tel://",
            @"facetime": @"facetime://", @"com.apple.facetime": @"facetime://",
            @"appstore": @"itms-apps://", @"app store": @"itms-apps://", @"应用商店": @"itms-apps://", @"com.apple.AppStore": @"itms-apps://",
            @"wallet": @"wallet://", @"钱包": @"wallet://", @"com.apple.Passbook": @"wallet://",
            @"health": @"x-apple-health://", @"健康": @"x-apple-health://", @"com.apple.Health": @"x-apple-health://",
            @"homeapp": @"home://", @"家庭": @"home://", @"com.apple.Home": @"home://",
            @"shortcuts": @"shortcuts://", @"快捷指令": @"shortcuts://", @"com.apple.shortcuts": @"shortcuts://",
            @"testflight": @"itms-beta://", @"com.apple.TestFlight": @"itms-beta://",
            // Productivity: Microsoft / Google / misc
            @"outlook": @"ms-outlook://", @"com.microsoft.Office.Outlook": @"ms-outlook://",
            @"onedrive": @"onedrive://", @"com.microsoft.skydrive": @"onedrive://",
            @"word": @"ms-word://", @"com.microsoft.Word": @"ms-word://",
            @"excel": @"ms-excel://", @"com.microsoft.Excel": @"ms-excel://",
            @"powerpoint": @"ms-powerpoint://", @"com.microsoft.PowerPoint": @"ms-powerpoint://",
            @"teams": @"msteams://", @"microsoft teams": @"msteams://", @"com.microsoft.skype.teams.ni": @"msteams://",
            @"wemeet": @"wemeet://", @"腾讯会议": @"wemeet://", @"com.tencent.wemeet": @"wemeet://",
            @"zoom": @"zoommtg://", @"com.us.zoom.videomeetings": @"zoommtg://",
            @"skype": @"skype://", @"com.skype.skype": @"skype://",
            @"slack": @"slack://", @"com.tinyspeck.chatlyio": @"slack://",
            @"notion": @"notion://", @"notion.id": @"notion://",
            @"evernote": @"evernote://", @"印象笔记": @"evernote://", @"com.evernote.Evernote": @"evernote://",
            @"dropbox": @"dbapi-1://", @"com.getdropbox.Dropbox": @"dbapi-1://",
            @"googlemaps": @"comgooglemaps://", @"谷歌地图": @"comgooglemaps://", @"com.google.Maps": @"comgooglemaps://",
            @"googledrive": @"googledrive://", @"谷歌网盘": @"googledrive://", @"com.google.Drive": @"googledrive://",
            @"googlephotos": @"googlephotos://", @"谷歌相册": @"googlephotos://", @"com.google.GooglePhotos": @"googlephotos://",
            @"googletranslate": @"googletranslate://", @"谷歌翻译": @"googletranslate://", @"com.google.Translate": @"googletranslate://",
            @"googlecalendar": @"googlecalendar://", @"谷歌日历": @"googlecalendar://", @"com.google.calendar": @"googlecalendar://",
            @"googlemeet": @"comgooglemeet://", @"com.google.ios.meet": @"comgooglemeet://",
            @"github": @"github://", @"com.github.GitHubClient": @"github://",
            @"wps": @"wps://", @"cn.wps.moffice": @"wps://",
            @"youdao": @"yddict://", @"有道词典": @"yddict://", @"com.youdao.dict": @"yddict://",
            @"duolingo": @"duo://", @"多邻国": @"duo://", @"com.duolingo.DuolingoMobile": @"duo://",
            // Social / streaming / shopping (international + China)
            @"discord": @"discord://", @"com.hammerandchisel.discord": @"discord://",
            @"line": @"line://", @"jp.naver.line": @"line://",
            @"kakaotalk": @"kakotalk://", @"kakao": @"kakotalk://", @"com.iwilab.KakaoTalk": @"kakotalk://",
            @"linkedin": @"linkedin://", @"com.linkedin.LinkedIn": @"linkedin://",
            @"reddit": @"reddit://", @"com.reddit.Reddit": @"reddit://",
            @"snapchat": @"snapchat://", @"com.toyopagroup.picaboo": @"snapchat://",
            @"pinterest": @"pinit://", @"com.pinterest.Pinterest": @"pinit://",
            @"steam": @"steam://", @"com.valvesoftware.steam.mobile": @"steam://",
            @"twitch": @"twitch://", @"com.twitch.twitchapp": @"twitch://",
            @"amazon": @"amzn://", @"com.amazon.Amazon": @"amzn://",
            @"ebay": @"ebay://", @"com.ebay.iphone": @"ebay://",
            @"primevideo": @"primevideo://", @"com.amazon.avod.iphone": @"primevideo://",
            @"disneyplus": @"disneyplus://", @"disney+": @"disneyplus://", @"com.disney.disneyplus": @"disneyplus://",
            @"hbomax": @"hbomax://", @"com.hbo.hbomax": @"hbomax://",
            @"tieba": @"tieba://", @"贴吧": @"tieba://", @"com.baidu.tieba": @"tieba://",
            @"idlefish": @"idlefish://", @"闲鱼": @"idlefish://", @"com.taobao.idlefish": @"idlefish://",
            @"vipshop": @"vipshop://", @"唯品会": @"vipshop://", @"com.vipshop": @"vipshop://",
            @"suning": @"suning://", @"苏宁易购": @"suning://", @"com.suning.mobile.ebuy": @"suning://",
            @"maoyan": @"maoyan://", @"猫眼": @"maoyan://", @"com.sankuai.movie": @"maoyan://",
            @"damai": @"damai://", @"大麦": @"damai://", @"cn.damai": @"damai://",
            @"mangotv": @"imgtv://", @"芒果tv": @"imgtv://", @"芒果TV": @"imgtv://", @"com.hunantv.imgo": @"imgtv://",
            @"kwmusic": @"kwmusic://", @"酷我音乐": @"kwmusic://", @"com.kuwo.kwmusic": @"kwmusic://",
            @"ximalaya": @"ximalaya://", @"喜马拉雅": @"ximalaya://", @"com.gemd.iting": @"ximalaya://",
            @"douyutv": @"douyutv://", @"斗鱼": @"douyutv://", @"com.air.douyutv": @"douyutv://",
            @"huya": @"huya://", @"虎牙": @"huya://", @"com.duowan.huya": @"huya://",
            @"momo": @"momo://", @"陌陌": @"momo://", @"com.immomo.momo": @"momo://",
            @"tantan": @"tantan://", @"探探": @"tantan://", @"com.p1er.tantan": @"tantan://",
            @"baidunetdisk": @"baiduyun://", @"百度网盘": @"baiduyun://", @"com.baidu.netdisk": @"baiduyun://",
            @"qqmap": @"qqmap://", @"腾讯地图": @"qqmap://", @"com.tencent.map": @"qqmap://",
            @"unionpay": @"unionpay://", @"云闪付": @"unionpay://", @"com.unionpay.cloudpay": @"unionpay://",
            @"qunar": @"qunariphone://", @"去哪儿": @"qunariphone://", @"com.Qunar.QunarApp": @"qunariphone://",
            @"keep": @"keep://", @"com.gotokeep.keep": @"keep://",
        };
    });
    NSString *trimmed = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *scheme = autoAppSchemes[trimmed];
    if (!scheme) scheme = autoAppSchemes[trimmed.lowercaseString];
    return scheme;
}

// Detects QR codes / barcodes in an image file. Returns [{text, symbology, bounds:{x,y,width,height}}]
// with normalized coordinates (origin top-left, matching screenshot bounds).
static NSArray<NSDictionary<NSString *, id> *> *AutoScanBarcodes(NSData *imageData, NSError **error) {
    if (!imageData || imageData.length == 0) {
        if (error) *error = AutoMakeError(AutoSDKErrorAutomationFailed, @"scanCode received an empty image.", nil);
        return nil;
    }
    if (imageData.length > 64 * 1024 * 1024) {
        if (error) *error = AutoMakeError(AutoSDKErrorAutomationFailed, @"scanCode image exceeds the 64 MB limit.", nil);
        return nil;
    }
    UIImage *image = [UIImage imageWithData:imageData];
    CGImageRef sourceImage = image.CGImage;
    if (!sourceImage) {
        if (error) *error = AutoMakeError(AutoSDKErrorAutomationFailed, @"scanCode cannot decode the image file.", nil);
        return nil;
    }
    NSError *visionError = nil;
    VNDetectBarcodesRequest *request = [VNDetectBarcodesRequest new];
    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:sourceImage options:@{}];
    if (![handler performRequests:@[request] error:&visionError]) {
        if (error) *error = visionError ?: AutoMakeError(AutoSDKErrorAutomationFailed, @"Barcode detection failed.", nil);
        return nil;
    }
    NSMutableArray<NSDictionary<NSString *, id> *> *results = [NSMutableArray array];
    for (VNBarcodeObservation *observation in request.results) {
        NSMutableDictionary<NSString *, id> *item = [NSMutableDictionary dictionary];
        if (observation.payloadStringValue.length > 0) item[@"text"] = observation.payloadStringValue;
        if (observation.symbology.length > 0) item[@"symbology"] = observation.symbology;
        CGRect box = observation.boundingBox; // normalized, origin bottom-left
        item[@"bounds"] = @{
            @"x": @(box.origin.x),
            @"y": @(1.0 - box.origin.y - box.size.height),
            @"width": @(box.size.width),
            @"height": @(box.size.height),
        };
        [results addObject:item];
    }
    return results;
}

// --- WebSocket client (AScript WebSocket / kuaijs cloud parity) ---
static NSMutableDictionary<NSNumber *, NSURLSessionWebSocketTask *> *AutoWSTasks;
static NSMutableDictionary<NSNumber *, NSMutableArray<NSDictionary *> *> *AutoWSQueues;
static NSMutableDictionary<NSNumber *, AutoWebSocketDelegate *> *AutoWSDelegates;
static NSMutableDictionary<NSNumber *, NSURLSession *> *AutoWSSessions;
static NSLock *AutoWSLock;
static NSUInteger AutoWSNextHandle = 1;

static void AutoWSInit(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        AutoWSTasks = [NSMutableDictionary dictionary];
        AutoWSQueues = [NSMutableDictionary dictionary];
        AutoWSDelegates = [NSMutableDictionary dictionary];
        AutoWSSessions = [NSMutableDictionary dictionary];
        AutoWSLock = [NSLock new];
    });
}

static void AutoWSEnqueue(NSNumber *handle, NSDictionary *event) {
    AutoWSInit();
    [AutoWSLock lock];
    NSMutableArray *queue = AutoWSQueues[handle];
    if (queue && queue.count < 512) [queue addObject:event];
    [AutoWSLock unlock];
}

static void AutoWSStartReceive(NSNumber *handle, NSURLSessionWebSocketTask *task) {
    [task receiveMessageWithCompletionHandler:^(NSURLSessionWebSocketMessage *message, NSError *error) {
        if (error) {
            NSInteger code = error.code;
            if (code != 57 && code != 54 && code != -999) { // ignore local close/cancel
                AutoWSEnqueue(handle, @{@"type": @"error", @"error": error.localizedDescription ?: @"connection error"});
            }
            return;
        }
        if (message.type == NSURLSessionWebSocketMessageTypeString) {
            AutoWSEnqueue(handle, @{@"type": @"message", @"text": message.string ?: @""});
        } else if (message.type == NSURLSessionWebSocketMessageTypeData) {
            AutoWSEnqueue(handle, @{@"type": @"message", @"text": [message.data base64EncodedStringWithOptions:0], @"data": @YES});
        }
        BOOL stillOpen = NO;
        [AutoWSLock lock];
        if ([AutoWSTasks[handle] isEqual:task]) stillOpen = (task.state == NSURLSessionTaskStateRunning);
        [AutoWSLock unlock];
        if (stillOpen) AutoWSStartReceive(handle, task);
    }];
}

@implementation AutoWebSocketDelegate
- (void)URLSession:(NSURLSession *)session webSocketTask:(NSURLSessionWebSocketTask *)webSocketTask didOpenWithProtocol:(NSString *)protocol {
    AutoWSEnqueue(self.handle, @{@"type": @"open"});
}
- (void)URLSession:(NSURLSession *)session webSocketTask:(NSURLSessionWebSocketTask *)webSocketTask didCloseWithCode:(NSURLSessionWebSocketCloseCode)closeCode reason:(NSData *)reason {
    AutoWSEnqueue(self.handle, @{@"type": @"close", @"code": @(closeCode)});
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (error && error.code != -999 && error.code != 57 && error.code != 54) {
        AutoWSEnqueue(self.handle, @{@"type": @"error", @"error": error.localizedDescription ?: @"connection failed"});
    }
}
@end

static id AutoHandleWebSocket(NSString *name, NSArray *args) {
    AutoWSInit();
    if ([name isEqualToString:@"wsConnect"]) {
        NSString *urlString = args.count > 0 && [args[0] isKindOfClass:NSString.class] ? args[0] : @"";
        NSURL *url = [NSURL URLWithString:urlString];
        NSString *scheme = url.scheme.lowercaseString;
        if (!url || (![scheme isEqualToString:@"ws"] && ![scheme isEqualToString:@"wss"])) {
            return AutoMakeError(AutoSDKErrorInvalidConfiguration, @"ws.connect requires a ws:// or wss:// URL.", nil);
        }
        NSNumber *handle = @(AutoWSNextHandle++);
        AutoWebSocketDelegate *delegate = [AutoWebSocketDelegate new];
        delegate.handle = handle;
        NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.defaultSessionConfiguration;
        configuration.timeoutIntervalForRequest = 30;
        NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration delegate:delegate delegateQueue:nil];
        NSURLSessionWebSocketTask *task = [session webSocketTaskWithURL:url];
        [AutoWSLock lock];
        AutoWSTasks[handle] = task;
        AutoWSQueues[handle] = [NSMutableArray array];
        AutoWSDelegates[handle] = delegate;
        AutoWSSessions[handle] = session;
        [AutoWSLock unlock];
        [task resume];
        AutoWSStartReceive(handle, task);
        return handle;
    }
    if (args.count == 0) return AutoMakeError(AutoSDKErrorInvalidConfiguration, @"WebSocket operation requires a handle.", nil);
    NSNumber *handle = [args[0] isKindOfClass:NSNumber.class] ? args[0] : @([args[0] doubleValue]);
    if ([name isEqualToString:@"wsPoll"]) {
        [AutoWSLock lock];
        NSMutableArray *queue = AutoWSQueues[handle];
        id event = nil;
        if (queue.count > 0) {
            event = queue[0];
            [queue removeObjectAtIndex:0];
        }
        [AutoWSLock unlock];
        return event ?: [NSNull null];
    }
    if ([name isEqualToString:@"wsSend"]) {
        NSURLSessionWebSocketTask *task = nil;
        [AutoWSLock lock];
        task = AutoWSTasks[handle];
        [AutoWSLock unlock];
        if (!task) return AutoMakeError(AutoSDKErrorInvalidConfiguration, @"Unknown WebSocket handle.", nil);
        if (task.state != NSURLSessionTaskStateRunning) return @NO;
        NSString *text = args.count > 1 && [args[1] isKindOfClass:NSString.class] ? args[1] : @"";
        NSURLSessionWebSocketMessage *message = [[NSURLSessionWebSocketMessage alloc] initWithString:text];
        [task sendMessage:message completionHandler:^(NSError *sendError) {
            if (sendError) AutoWSEnqueue(handle, @{@"type": @"error", @"error": sendError.localizedDescription ?: @"send failed"});
        }];
        return @YES;
    }
    if ([name isEqualToString:@"wsClose"]) {
        [AutoWSLock lock];
        NSURLSessionWebSocketTask *task = AutoWSTasks[handle];
        [AutoWSTasks removeObjectForKey:handle];
        [AutoWSQueues removeObjectForKey:handle];
        [AutoWSDelegates removeObjectForKey:handle];
        [AutoWSSessions removeObjectForKey:handle];
        [AutoWSLock unlock];
        if (task) [task cancelWithCloseCode:NSURLSessionWebSocketCloseCodeNormalClosure reason:nil];
        return @YES;
    }
    return AutoMakeError(AutoSDKErrorInvalidConfiguration, @"Unknown WebSocket operation.", nil);
}

static void AutoWebSocketCloseAll(void) {
    AutoWSInit();
    [AutoWSLock lock];
    NSDictionary *tasks = [AutoWSTasks copy];
    [AutoWSTasks removeAllObjects];
    [AutoWSQueues removeAllObjects];
    [AutoWSDelegates removeAllObjects];
    [AutoWSSessions removeAllObjects];
    [AutoWSLock unlock];
    for (NSURLSessionWebSocketTask *task in tasks.allValues) {
        [task cancelWithCloseCode:NSURLSessionWebSocketCloseCodeNormalClosure reason:nil];
    }
}

static NSMutableDictionary<NSNumber *, NSValue *> *AutoSQLiteHandles;
static NSLock *AutoSQLiteLock;
static NSUInteger AutoSQLiteNextHandle = 1;

static void AutoSQLiteInit(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        AutoSQLiteHandles = [NSMutableDictionary dictionary];
        AutoSQLiteLock = [NSLock new];
    });
}

static const NSUInteger AutoSQLiteMaxRows = 100000;

static NSArray<NSDictionary<NSString *, id> *> *AutoSQLiteRowsForStatement(sqlite3_stmt *statement) {
    int columns = sqlite3_column_count(statement);
    NSMutableArray<NSDictionary<NSString *, id> *> *rows = [NSMutableArray array];
    while (rows.count < AutoSQLiteMaxRows && sqlite3_step(statement) == SQLITE_ROW) {
        NSMutableDictionary<NSString *, id> *row = [NSMutableDictionary dictionary];
        for (int i = 0; i < columns; i++) {
            const char *name = sqlite3_column_name(statement, i);
            NSString *key = name ? [NSString stringWithUTF8String:name] : [NSString stringWithFormat:@"col%d", i];
            id value = nil;
            switch (sqlite3_column_type(statement, i)) {
                case SQLITE_INTEGER: value = @(sqlite3_column_int64(statement, i)); break;
                case SQLITE_FLOAT: value = @(sqlite3_column_double(statement, i)); break;
                case SQLITE_TEXT: {
                    const unsigned char *text = sqlite3_column_text(statement, i);
                    value = text ? [NSString stringWithUTF8String:(const char *)text] : @"";
                    break;
                }
                case SQLITE_BLOB: {
                    const void *bytes = sqlite3_column_blob(statement, i);
                    int length = sqlite3_column_bytes(statement, i);
                    value = bytes && length > 0 ? [[NSData dataWithBytes:bytes length:(NSUInteger)length] base64EncodedStringWithOptions:0] : @"";
                    break;
                }
                default: value = NSNull.null; break;
            }
            row[key] = value ?: NSNull.null;
        }
        [rows addObject:row];
    }
    return rows;
}

static int AutoSQLiteBindParams(sqlite3_stmt *statement, NSArray *params) {
    for (NSUInteger i = 0; i < params.count; i++) {
        id param = params[i];
        int index = (int)(i + 1);
        int rc;
        if (param == nil || [param isKindOfClass:NSNull.class]) {
            rc = sqlite3_bind_null(statement, index);
        } else if ([param isKindOfClass:NSNumber.class]) {
            CFNumberType numberType = CFNumberGetType((__bridge CFNumberRef)param);
            if (numberType == kCFNumberFloatType || numberType == kCFNumberFloat32Type ||
                numberType == kCFNumberFloat64Type || numberType == kCFNumberDoubleType ||
                numberType == kCFNumberCGFloatType) {
                rc = sqlite3_bind_double(statement, index, [param doubleValue]);
            } else {
                rc = sqlite3_bind_int64(statement, index, (sqlite3_int64)[param longLongValue]);
            }
        } else if ([param isKindOfClass:NSData.class]) {
            rc = sqlite3_bind_blob(statement, index, [param bytes], (int)[param length], SQLITE_TRANSIENT);
        } else {
            NSString *text = [param isKindOfClass:NSString.class] ? param : [param description];
            rc = sqlite3_bind_text(statement, index, text.UTF8String, (int)[text lengthOfBytesUsingEncoding:NSUTF8StringEncoding], SQLITE_TRANSIENT);
        }
        if (rc != SQLITE_OK) return rc;
    }
    return SQLITE_OK;
}

static id AutoSQLiteOperation(NSString *name, NSArray *args, NSDictionary *config) {
    AutoSQLiteInit();
    if ([name isEqualToString:@"sqO"]) {
        NSString *pathValue = args.count > 0 && [args[0] isKindOfClass:NSString.class] ? args[0] : @"";
        if (pathValue.length == 0) {
            return AutoMakeError(AutoSDKErrorInvalidConfiguration, @"sqlite.open requires a database path.", nil);
        }
        NSError *resolveError = nil;
        id resolved = AutoScriptFileOperation(@{ @"operation": @"resolvePath", @"path": pathValue }, config ?: @{}, &resolveError);
        if (resolveError) return resolveError;
        NSString *resolvedPath = [resolved isKindOfClass:NSString.class] ? resolved : pathValue;
        sqlite3 *db = NULL;
        int rc = sqlite3_open_v2(resolvedPath.UTF8String, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, NULL);
        if (rc != SQLITE_OK) {
            NSString *message = db ? [NSString stringWithUTF8String:sqlite3_errmsg(db)] : @"cannot open database";
            if (db) sqlite3_close(db);
            return AutoMakeError(AutoSDKErrorFileOperationFailed, message ?: @"sqlite open failed.", nil);
        }
        [AutoSQLiteLock lock];
        NSNumber *handle = @(AutoSQLiteNextHandle++);
        AutoSQLiteHandles[handle] = [NSValue valueWithPointer:db];
        [AutoSQLiteLock unlock];
        return handle;
    }
    if (args.count == 0) {
        return AutoMakeError(AutoSDKErrorInvalidConfiguration, @"sqlite operation requires a handle.", nil);
    }
    NSNumber *handle = [args[0] isKindOfClass:NSNumber.class] ? args[0] : @([args[0] doubleValue]);
    NSString *sql = args.count > 1 && [args[1] isKindOfClass:NSString.class] ? args[1] : @"";
    if ([name isEqualToString:@"sqC"]) {
        [AutoSQLiteLock lock];
        sqlite3 *db = (sqlite3 *)AutoSQLiteHandles[handle].pointerValue;
        [AutoSQLiteHandles removeObjectForKey:handle];
        [AutoSQLiteLock unlock];
        if (db) { sqlite3_close(db); return @YES; }
        return @NO;
    }
    [AutoSQLiteLock lock];
    sqlite3 *db = (sqlite3 *)AutoSQLiteHandles[handle].pointerValue;
    [AutoSQLiteLock unlock];
    if (!db) return AutoMakeError(AutoSDKErrorAutomationFailed, @"sqlite handle is not open.", nil);
    if (sql.length == 0) return AutoMakeError(AutoSDKErrorInvalidConfiguration, @"sqlite requires SQL text.", nil);
    sqlite3_stmt *statement = NULL;
    const char *sqlText = sql.UTF8String;
    const char *tail = NULL;
    int rc = sqlite3_prepare_v2(db, sqlText, -1, &statement, &tail);
    if (rc != SQLITE_OK) {
        NSString *message = [NSString stringWithUTF8String:sqlite3_errmsg(db)];
        return AutoMakeError(AutoSDKErrorAutomationFailed, message ?: @"sqlite prepare failed.", nil);
    }
    while (tail && *tail && isspace((unsigned char)*tail)) tail++;
    if (tail && *tail) {
        sqlite3_finalize(statement);
        return AutoMakeError(AutoSDKErrorInvalidConfiguration, @"sqlite accepts one statement per call; split multiple statements into separate exec() calls.", nil);
    }
    NSArray *params = args.count > 2 && [args[2] isKindOfClass:NSArray.class] ? args[2] : @[];
    rc = AutoSQLiteBindParams(statement, params);
    if (rc != SQLITE_OK) {
        NSString *message = [NSString stringWithUTF8String:sqlite3_errmsg(db)];
        sqlite3_finalize(statement);
        return AutoMakeError(AutoSDKErrorAutomationFailed, message ?: @"sqlite bind failed.", nil);
    }
    if (sqlite3_column_count(statement) > 0) {
        NSArray *rows = AutoSQLiteRowsForStatement(statement);
        sqlite3_finalize(statement);
        return rows;
    }
    rc = sqlite3_step(statement);
    sqlite3_finalize(statement);
    if (rc != SQLITE_DONE) {
        NSString *message = [NSString stringWithUTF8String:sqlite3_errmsg(db)];
        return AutoMakeError(AutoSDKErrorAutomationFailed, message ?: @"sqlite step failed.", nil);
    }
    return @{ @"changes": @(sqlite3_changes(db)), @"lastInsertRowId": @(sqlite3_last_insert_rowid(db)) };
}

static void AutoSQLiteCloseAll(void) {
    AutoSQLiteInit();
    [AutoSQLiteLock lock];
    NSDictionary *handles = [AutoSQLiteHandles copy];
    [AutoSQLiteHandles removeAllObjects];
    [AutoSQLiteLock unlock];
    for (NSValue *boxedHandle in handles.allValues) {
        sqlite3 *db = (sqlite3 *)boxedHandle.pointerValue;
        if (db) sqlite3_close(db);
    }
}

// Classifies the image with Vision's on-device model. Without a bundled Core ML
// detector Vision reports whole-image labels, so each result uses the full image rect.
static NSArray<NSDictionary<NSString *, id> *> *AutoDetectObjects(UIImage *image, NSError **error) {
    CGImageRef sourceImage = image.CGImage;
    if (!sourceImage) {
        if (error) *error = AutoMakeError(AutoSDKErrorAutomationFailed, @"yolo cannot decode the image file.", nil);
        return nil;
    }
    if (@available(iOS 15.0, *)) {
        NSError *visionError = nil;
        VNClassifyImageRequest *request = [VNClassifyImageRequest new];
        VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:sourceImage options:@{}];
        if (![handler performRequests:@[request] error:&visionError]) {
            if (error) *error = visionError ?: AutoMakeError(AutoSDKErrorAutomationFailed, @"Image classification failed.", nil);
            return nil;
        }
        NSUInteger width = CGImageGetWidth(sourceImage);
        NSUInteger height = CGImageGetHeight(sourceImage);
        NSMutableArray<NSDictionary<NSString *, id> *> *results = [NSMutableArray array];
        for (VNClassificationObservation *observation in request.results) {
            if (observation.identifier.length == 0 || observation.confidence <= 0 || results.count >= 20) continue;
            [results addObject:@{
                @"label": observation.identifier,
                @"confidence": @(observation.confidence),
                @"rect": @{ @"x": @0, @"y": @0, @"width": @(width), @"height": @(height) },
            }];
        }
        return results;
    }
    if (error) *error = AutoMakeError(AutoSDKErrorAutomationUnavailable,
                                      @"Image classification requires iOS 15 or later.", nil);
    return nil;
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

static UIWindow *AutoEngineMainWindow(void) {
    if (!NSThread.isMainThread) return nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            if (windowScene.activationState != UISceneActivationStateForegroundActive) continue;
            UIWindow *window = windowScene.windows.firstObject;
            if (window) return window;
        }
    }
    return UIApplication.sharedApplication.keyWindow;
}

static UIColor *AutoOverlayColorFromHex(NSString *hex) {
    if (![hex isKindOfClass:NSString.class]) return nil;
    NSString *value = [hex stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if ([value hasPrefix:@"#"]) value = [value substringFromIndex:1];
    if ([value hasPrefix:@"0x"] || [value hasPrefix:@"0X"]) value = [value substringFromIndex:2];
    if (value.length != 6 && value.length != 8) return nil;
    NSScanner *scanner = [NSScanner scannerWithString:value];
    unsigned long long rgb = 0;
    if (![scanner scanHexLongLong:&rgb] || !scanner.isAtEnd) return nil;
    if (value.length == 6) {
        return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                               green:((rgb >> 8) & 0xFF) / 255.0
                                blue:(rgb & 0xFF) / 255.0
                               alpha:1.0];
    }
    return [UIColor colorWithRed:((rgb >> 24) & 0xFF) / 255.0
                           green:((rgb >> 16) & 0xFF) / 255.0
                            blue:((rgb >> 8) & 0xFF) / 255.0
                           alpha:(rgb & 0xFF) / 255.0];
}

@interface AutoPassThroughView : UIView
@end

@implementation AutoPassThroughView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return (hit == self) ? nil : hit;
}
@end

@interface AutoOverlayRootViewController : UIViewController
@end

@implementation AutoOverlayRootViewController
- (void)loadView {
    AutoPassThroughView *view = [[AutoPassThroughView alloc] initWithFrame:UIScreen.mainScreen.bounds];
    view.backgroundColor = UIColor.clearColor;
    self.view = view;
}
@end

@interface AutoScreenDrawView : UIView
@property (nonatomic, strong) UILabel *titleLabel;
- (void)setDrawTitle:(NSString *)title;
@end

@implementation AutoScreenDrawView
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.userInteractionEnabled = NO;
        self.layer.borderWidth = 2.0;
        self.layer.borderColor = UIColor.redColor.CGColor;
        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.font = [UIFont boldSystemFontOfSize:12];
        _titleLabel.textColor = UIColor.whiteColor;
        _titleLabel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6];
        _titleLabel.numberOfLines = 1;
        _titleLabel.hidden = YES;
        [self addSubview:_titleLabel];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    if (!_titleLabel.hidden) {
        CGSize size = [_titleLabel sizeThatFits:CGSizeMake(CGRectGetWidth(self.bounds), CGFLOAT_MAX)];
        _titleLabel.frame = CGRectMake(0, 0, MIN(CGRectGetWidth(self.bounds), size.width + 8), size.height + 4);
    }
}
- (void)setDrawTitle:(NSString *)title {
    self.titleLabel.text = title;
    self.titleLabel.hidden = (title.length == 0);
    [self setNeedsLayout];
}
@end

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

static NSString *AutoCurrentNetworkType(void) {
    SCNetworkReachabilityRef reachability = SCNetworkReachabilityCreateWithName(kCFAllocatorDefault, "apple.com");
    if (!reachability) return @"none";
    SCNetworkReachabilityFlags flags = 0;
    BOOL reachable = SCNetworkReachabilityGetFlags(reachability, &flags);
    CFRelease(reachability);
    if (!reachable || (flags & kSCNetworkReachabilityFlagsReachable) == 0) return @"none";
    if ((flags & kSCNetworkReachabilityFlagsIsWWAN) != 0) return @"cellular";
    return @"wifi";
}

static NSString *AutoVPNStatusName(NEVPNStatus status) {
    switch (status) {
        case NEVPNStatusDisconnected: return @"disconnected";
        case NEVPNStatusConnecting: return @"connecting";
        case NEVPNStatusConnected: return @"connected";
        case NEVPNStatusReasserting: return @"reasserting";
        case NEVPNStatusDisconnecting: return @"disconnecting";
        case NEVPNStatusInvalid:
        default: return @"invalid";
    }
}

static NSString *AutoLocationAuthorizationStatusName(CLAuthorizationStatus status) {
    switch (status) {
        case kCLAuthorizationStatusRestricted: return @"restricted";
        case kCLAuthorizationStatusDenied: return @"denied";
        case kCLAuthorizationStatusAuthorizedAlways: return @"authorizedAlways";
        case kCLAuthorizationStatusAuthorizedWhenInUse: return @"authorizedWhenInUse";
        case kCLAuthorizationStatusNotDetermined:
        default: return @"notDetermined";
    }
}

static NEVPNManager *AutoLoadPersonalVPNManager(AutoSystemCancellation cancellation, NSError **error) {
    if (NSThread.isMainThread) {
        if (error) *error = AutoMakeError(AutoSDKErrorAutomationUnavailable,
                                          @"Personal VPN preferences cannot be loaded synchronously on the main thread.", nil);
        return nil;
    }
    AutoPendingSystemOperation *pending = [[AutoPendingSystemOperation alloc] initWithTimeout:5 cancellation:cancellation];
    NEVPNManager *manager = NEVPNManager.sharedManager;
    if ([pending isActive]) {
        [manager loadFromPreferencesWithCompletionHandler:^(NSError * _Nullable callbackError) {
            [pending completeWithResult:nil error:callbackError];
        }];
    }
    NSError *loadError = nil;
    if (![pending waitWithError:&loadError]) {
        if (error) *error = loadError ?: AutoMakeError(AutoSDKErrorAutomationUnavailable,
                                          @"Loading the Personal VPN configuration timed out after 5 seconds.", nil);
        return nil;
    }
    if (loadError) {
        NSString *message = @"Unable to load the host app's Personal VPN configuration.";
        if ([loadError.domain isEqualToString:NEVPNErrorDomain]) {
            switch (loadError.code) {
                case NEVPNErrorConfigurationInvalid:
                    message = @"The host app's Personal VPN configuration is invalid.";
                    break;
                case NEVPNErrorConfigurationDisabled:
                    message = @"The host app's Personal VPN configuration is disabled.";
                    break;
                case NEVPNErrorConfigurationStale:
                    message = @"The host app's Personal VPN configuration changed; retry after reloading it.";
                    break;
                case NEVPNErrorConfigurationReadWriteFailed:
                    message = @"Unable to read the Personal VPN configuration; verify the host entitlement and saved profile.";
                    break;
                case NEVPNErrorConnectionFailed:
                    message = @"The Personal VPN connection failed while loading its configuration.";
                    break;
                case NEVPNErrorConfigurationUnknown:
                default:
                    message = @"Unable to load the Personal VPN configuration; verify the host entitlement and saved profile.";
                    break;
            }
        }
        if (error) *error = AutoMakeError(AutoSDKErrorAutomationUnavailable, message, loadError);
        return nil;
    }
    return manager;
}

static NSURL *AutoSystemSettingsURL(NSString *page) {
    NSString *normalized = page.lowercaseString;
    if ([normalized isEqualToString:@"app"]) return [NSURL URLWithString:UIApplicationOpenSettingsURLString];
    NSDictionary<NSString *, NSString *> *pages = @{
        @"vpn": @"App-prefs:root=General&path=VPN",
        @"wifi": @"App-prefs:root=WIFI",
        @"bluetooth": @"App-prefs:root=Bluetooth",
        @"cellular": @"App-prefs:root=MOBILE_DATA_SETTINGS_ID",
        @"hotspot": @"App-prefs:root=INTERNET_TETHERING",
        @"location": @"App-prefs:root=Privacy&path=LOCATION",
        @"battery": @"App-prefs:root=BATTERY_USAGE",
        @"focus": @"App-prefs:root=DO_NOT_DISTURB",
        @"notifications": @"App-prefs:root=NOTIFICATIONS_ID",
        @"display": @"App-prefs:root=DISPLAY",
        @"accessibility": @"App-prefs:root=ACCESSIBILITY",
        @"general": @"App-prefs:root=General",
        @"airplane": @"App-prefs:"
    };
    NSString *urlString = pages[normalized];
    return urlString ? [NSURL URLWithString:urlString] : nil;
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

static NSURL *AutoMediaDownloadToTempURL(NSURL *remoteURL, NSDictionary *config, NSError **error);

static NSURL *AutoMediaSourceURL(id pathValue, NSDictionary *config, NSError **error) {
    if (![pathValue isKindOfClass:NSString.class] || [pathValue length] == 0) {
        if (error) *error = AutoMakeError(AutoSDKErrorInvalidConfiguration,
                                          @"Media source path must not be empty.", nil);
        return nil;
    }
    NSString *mediaPath = (NSString *)pathValue;
    if ([mediaPath hasPrefix:@"http://"] || [mediaPath hasPrefix:@"https://"]) {
        NSURL *remoteURL = [NSURL URLWithString:mediaPath];
        if (!remoteURL) {
            if (error) *error = AutoMakeError(AutoSDKErrorInvalidConfiguration, @"Media source URL is invalid.", nil);
            return nil;
        }
        NSError *downloadError = nil;
        NSURL *downloaded = AutoMediaDownloadToTempURL(remoteURL, config ?: @{}, &downloadError);
        if (!downloaded) {
            if (error) *error = downloadError ?: AutoMakeError(AutoSDKErrorNetworkFailed, @"Unable to download the media source.", nil);
            return nil;
        }
        return downloaded;
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

static NSURL *AutoMediaDownloadToTempURL(NSURL *remoteURL, NSDictionary *config, NSError **error) {
    NSUInteger maximum = AutoMediaFileByteLimit(config ?: @{});
    __block NSURL *destination = nil;
    __block NSError *blockError = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    NSURLSessionConfiguration *sessionConfiguration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    sessionConfiguration.timeoutIntervalForRequest = 60.0;
    sessionConfiguration.timeoutIntervalForResource = 90.0;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfiguration];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:remoteURL
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:60.0];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *taskError) {
        if (taskError) {
            blockError = taskError;
            dispatch_semaphore_signal(semaphore);
            return;
        }
        long long expectedLength = response.expectedContentLength;
        if (expectedLength > 0 && (unsigned long long)expectedLength > maximum) {
            blockError = AutoMakeError(AutoSDKErrorFileOperationFailed, @"Remote media exceeds maxMediaBytes.", nil);
            dispatch_semaphore_signal(semaphore);
            return;
        }
        if (data.length == 0 || data.length > maximum) {
            blockError = AutoMakeError(AutoSDKErrorFileOperationFailed,
                                       data.length == 0 ? @"Remote media is empty." : @"Remote media exceeds maxMediaBytes.", nil);
            dispatch_semaphore_signal(semaphore);
            return;
        }
        NSString *baseName = [NSString stringWithFormat:@"autosdk-media-%@", NSUUID.UUID.UUIDString];
        NSString *extension = remoteURL.pathExtension.length > 0 ? remoteURL.pathExtension.lowercaseString : @"";
        NSString *fileName = extension.length > 0 ? [baseName stringByAppendingPathExtension:extension] : baseName;
        NSURL *target = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:fileName]];
        if (![data writeToURL:target atomically:YES]) {
            blockError = AutoMakeError(AutoSDKErrorFileOperationFailed, @"Unable to write downloaded media to temporary storage.", nil);
            dispatch_semaphore_signal(semaphore);
            return;
        }
        destination = target;
        dispatch_semaphore_signal(semaphore);
    }];
    [task resume];
    NSTimeInterval deadline = NSProcessInfo.processInfo.systemUptime + 90.0;
    BOOL timedOut = NO;
    while (dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC))) != 0) {
        if (NSProcessInfo.processInfo.systemUptime >= deadline) {
            timedOut = YES;
            [task cancel];
            break;
        }
    }
    [session finishTasksAndInvalidate];
    if (timedOut && !blockError) {
        blockError = AutoMakeError(AutoSDKErrorWaitTimeout, @"Timed out downloading remote media.", nil);
    }
    if (blockError) {
        if (error) *error = blockError;
        return nil;
    }
    return destination;
}

static BOOL AutoMediaImageURLIsValid(NSURL *url) {
    if (!url) return NO;
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    BOOL valid = source && CGImageSourceGetCount(source) > 0;
    if (source) CFRelease(source);
    return valid;
}

typedef struct {
    uint8_t red;
    uint8_t green;
    uint8_t blue;
    CGFloat tolerance;
} AutoEngineColorTarget;

typedef struct {
    uint8_t *bytes;
    size_t width;
    size_t height;
    size_t bytesPerRow;
    CGContextRef context;
} AutoEnginePixelBuffer;

static NSString *AutoPhotoAuthorizationStatusString(PHAuthorizationStatus status) {
    switch (status) {
        case PHAuthorizationStatusNotDetermined: return @"notDetermined";
        case PHAuthorizationStatusRestricted: return @"restricted";
        case PHAuthorizationStatusDenied: return @"denied";
        case PHAuthorizationStatusAuthorized: return @"authorized";
        case PHAuthorizationStatusLimited: return @"limited";
        default: return @"unknown";
    }
}

static BOOL AutoEngineParseColor(id color, uint8_t *red, uint8_t *green, uint8_t *blue) {
    if (!color) return NO;
    if ([color isKindOfClass:NSArray.class]) {
        NSArray *values = color;
        if (values.count < 3) return NO;
        double redValue = AutoFiniteDouble(values[0], NAN);
        double greenValue = AutoFiniteDouble(values[1], NAN);
        double blueValue = AutoFiniteDouble(values[2], NAN);
        if (!isfinite(redValue) || !isfinite(greenValue) || !isfinite(blueValue)) return NO;
        *red = (uint8_t)MIN(255, MAX(0, redValue));
        *green = (uint8_t)MIN(255, MAX(0, greenValue));
        *blue = (uint8_t)MIN(255, MAX(0, blueValue));
        return YES;
    }
    if ([color isKindOfClass:NSDictionary.class]) {
        id redValue = color[@"r"] ?: color[@"red"];
        id greenValue = color[@"g"] ?: color[@"green"];
        id blueValue = color[@"b"] ?: color[@"blue"];
        double redNumber = AutoFiniteDouble(redValue, NAN);
        double greenNumber = AutoFiniteDouble(greenValue, NAN);
        double blueNumber = AutoFiniteDouble(blueValue, NAN);
        if (!isfinite(redNumber) || !isfinite(greenNumber) || !isfinite(blueNumber)) return NO;
        *red = (uint8_t)MIN(255, MAX(0, redNumber));
        *green = (uint8_t)MIN(255, MAX(0, greenNumber));
        *blue = (uint8_t)MIN(255, MAX(0, blueNumber));
        return YES;
    }
    if (![color isKindOfClass:NSString.class]) return NO;
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

// Parses an EasyClick-style color list: "RRGGBB-TOL,RRGGBB-TOL" or an array of
// colors (each optionally "RRGGBB-TOL" or [r,g,b,tolerance]). A per-pair TOL is
// a per-channel hex tolerance; the global similarity (0-1) applies otherwise.
static NSArray *AutoEngineParseColorTargets(id colors, CGFloat similarity) {
    NSMutableArray *targets = [NSMutableArray array];
    NSArray *entries = nil;
    if ([colors isKindOfClass:NSString.class]) {
        entries = [(NSString *)colors componentsSeparatedByString:@","];
    } else if ([colors isKindOfClass:NSArray.class]) {
        entries = colors;
    }
    if (entries.count == 0 || entries.count > 32) return @[];
    CGFloat defaultTolerance = MIN(255.0, MAX(0.0, (1.0 - similarity) * 255.0));
    for (id entry in entries) {
        NSString *colorText = nil;
        NSNumber *toleranceNumber = nil;
        if ([entry isKindOfClass:NSString.class]) {
            NSArray<NSString *> *parts = [(NSString *)entry componentsSeparatedByString:@"-"];
            colorText = parts.firstObject;
            if (parts.count > 1 && parts[1].length > 0) {
                NSString *toleranceText = parts[1];
                if ([toleranceText hasPrefix:@"0x"] || [toleranceText hasPrefix:@"0X"]) {
                    toleranceText = [toleranceText substringFromIndex:2];
                }
                unsigned long long parsed = 0;
                NSScanner *toleranceScanner = [NSScanner scannerWithString:toleranceText];
                if ([toleranceScanner scanHexLongLong:&parsed] && toleranceScanner.isAtEnd) {
                    toleranceNumber = @(MIN(255.0, MAX(0.0, (double)((parsed >> 16) & 0xff))));
                }
            }
        } else if ([entry isKindOfClass:NSArray.class] && [(NSArray *)entry count] >= 4) {
            AutoEngineColorTarget target = {0};
            if (!AutoEngineParseColor(entry, &target.red, &target.green, &target.blue)) continue;
            target.tolerance = AutoFiniteNumber(((NSArray *)entry)[3])
                ? MIN(255.0, MAX(0.0, AutoFiniteDouble(((NSArray *)entry)[3], defaultTolerance)))
                : defaultTolerance;
            [targets addObject:[NSValue valueWithBytes:&target objCType:@encode(AutoEngineColorTarget)]];
            continue;
        }
        AutoEngineColorTarget target = {0};
        if (!AutoEngineParseColor(colorText, &target.red, &target.green, &target.blue)) continue;
        target.tolerance = toleranceNumber ? toleranceNumber.doubleValue : defaultTolerance;
        [targets addObject:[NSValue valueWithBytes:&target objCType:@encode(AutoEngineColorTarget)]];
    }
    return targets;
}

static BOOL AutoEnginePixelMatchesTargets(const uint8_t *pixel, NSArray *targets) {
    for (NSValue *targetValue in targets) {
        AutoEngineColorTarget target;
        [targetValue getValue:&target];
        if (fabs((double)pixel[0] - target.red) <= target.tolerance &&
            fabs((double)pixel[1] - target.green) <= target.tolerance &&
            fabs((double)pixel[2] - target.blue) <= target.tolerance) return YES;
    }
    return NO;
}

static AutoEnginePixelBuffer AutoEnginePixelBufferMake(CGImageRef image) {
    AutoEnginePixelBuffer result = {0};
    if (!image) return result;
    size_t width = CGImageGetWidth(image), height = CGImageGetHeight(image);
    if (width == 0 || height == 0 || width > SIZE_MAX / 4 || height > SIZE_MAX / (width * 4)) return result;
    size_t bytesPerRow = width * 4;
    size_t byteCount = height * bytesPerRow;
    if (byteCount > AutoDecodedImageBudget(NSProcessInfo.processInfo.physicalMemory)) return result;
    uint8_t *bytes = calloc(height, bytesPerRow);
    if (!bytes) return result;
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    if (!colorSpace) {
        free(bytes);
        return result;
    }
    CGContextRef context = CGBitmapContextCreate(bytes, width, height, 8, bytesPerRow, colorSpace,
                                                 kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);
    if (!context) {
        free(bytes);
        return result;
    }
    CGContextTranslateCTM(context, 0, height);
    CGContextScaleCTM(context, 1, -1);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
    result.bytes = bytes;
    result.width = width;
    result.height = height;
    result.bytesPerRow = bytesPerRow;
    result.context = context;
    return result;
}

static void AutoEnginePixelBufferDestroy(AutoEnginePixelBuffer *buffer) {
    if (buffer->context) CGContextRelease(buffer->context);
    free(buffer->bytes);
    *buffer = (AutoEnginePixelBuffer){0};
}
static NSData *AutoEngineScreenPNG(id<AutoAutomationAdapter> adapter, NSString *cachedPath, NSError **error) {
    if ([cachedPath isKindOfClass:NSString.class] && cachedPath.length > 0 &&
        [cachedPath isAbsolutePath] && [cachedPath hasPrefix:[NSHomeDirectory() stringByAppendingString:@"/"]]) {
        NSData *cached = [NSData dataWithContentsOfFile:cachedPath];
        if (cached.length > 0) return cached;
    }
    return [adapter screenshotWithError:error];
}

static NSArray *AutoEngineScanColorPoints(id<AutoAutomationAdapter> adapter,
                                          AutoEngine *engine,
                                          NSArray *targets,
                                          double x, double y, double ex, double ey,
                                          NSUInteger maximumMatches,
                                          NSUInteger order,
                                          BOOL notMode,
                                          NSString *cachedScreenPath,
                                          NSError **error) {
    NSData *png = AutoEngineScreenPNG(adapter, cachedScreenPath, error);
    if (!png) {
        if (error && !*error) *error = AutoMakeError(AutoSDKErrorAutomationFailed,
                                                     @"Unable to capture a screenshot for color search.", nil);
        return nil;
    }
    if (png.length == 0) return @[];
    UIImage *image = [UIImage imageWithData:png];
    CGImageRef screenCGImage = image.CGImage;
    if (!screenCGImage) {
        if (error) *error = AutoMakeError(AutoSDKErrorAutomationFailed,
                                          @"Unable to decode the screenshot for color search.", nil);
        return nil;
    }
    CGFloat scale = image.scale > 0 ? image.scale : 1.0;
    size_t imageWidth = CGImageGetWidth(screenCGImage);
    size_t imageHeight = CGImageGetHeight(screenCGImage);
    BOOL regionProvided = x != 0 || y != 0 || ex != 0 || ey != 0;
    double minX = 0, minY = 0, maxX = imageWidth / scale, maxY = imageHeight / scale;
    if (regionProvided) {
        minX = MIN(x, ex);
        maxX = MAX(x, ex);
        minY = MIN(y, ey);
        maxY = MAX(y, ey);
    }
    if (maxX - minX <= 0 || maxY - minY <= 0) {
        if (error) *error = AutoMakeError(AutoSDKErrorInvalidConfiguration,
                                          @"Color search region must have positive width and height.", nil);
        return nil;
    }
    size_t pixelMinX = (size_t)MIN(imageWidth, (size_t)MAX(0, floor(minX * scale)));
    size_t pixelMinY = (size_t)MIN(imageHeight, (size_t)MAX(0, floor(minY * scale)));
    size_t pixelMaxX = (size_t)MIN(imageWidth, (size_t)MAX(0, ceil(maxX * scale)));
    size_t pixelMaxY = (size_t)MIN(imageHeight, (size_t)MAX(0, ceil(maxY * scale)));
    if (pixelMaxX <= pixelMinX || pixelMaxY <= pixelMinY) return @[];
    AutoEnginePixelBuffer buffer = AutoEnginePixelBufferMake(screenCGImage);
    if (!buffer.bytes) {
        if (error) *error = AutoMakeError(AutoSDKErrorAutomationFailed,
                                          @"Unable to allocate a pixel buffer for color search.", nil);
        return nil;
    }
    size_t step = 1;
    double regionWidth = (double)(pixelMaxX - pixelMinX);
    double regionHeight = (double)(pixelMaxY - pixelMinY);
    const double scanBudget = 2 * 1024 * 1024;
    if (regionWidth * regionHeight > scanBudget) {
        step = (size_t)ceil(sqrt((regionWidth * regionHeight) / scanBudget));
        if (step < 1) step = 1;
    }
    NSInteger rowCount = (NSInteger)(pixelMaxY - pixelMinY);
    NSInteger columnCount = (NSInteger)(pixelMaxX - pixelMinX);
    BOOL columnsLeftToRight = (order == 1 || order == 3 || order == 5 || order == 7);
    BOOL rowsTopToBottom = (order == 1 || order == 2 || order == 5 || order == 6);
    BOOL columnMajor = order <= 4;
    NSInteger iStep = (NSInteger)step;
    NSMutableArray *matches = [NSMutableArray array];
    __block BOOL cancelled = NO;
    __block NSUInteger scanned = 0;
    void (^evaluatePixel)(NSInteger, NSInteger, NSInteger, NSInteger) = ^(NSInteger columnIndex, NSInteger rowIndex, NSInteger majorIndex, NSInteger minorIndex) {
        (void)majorIndex; (void)minorIndex;
        const uint8_t *pixel = buffer.bytes + (NSUInteger)(pixelMinY + rowIndex) * buffer.bytesPerRow
                             + (NSUInteger)(pixelMinX + columnIndex) * 4;
        BOOL matched = AutoEnginePixelMatchesTargets(pixel, targets);
        if (notMode ? !matched : matched) {
            [matches addObject:@{ @"x": @((pixelMinX + columnIndex) / scale),
                                  @"y": @((pixelMinY + rowIndex) / scale) }];
        }
        scanned += 1;
        if ((scanned & 0x3FFF) == 0 && [engine shouldStop]) cancelled = YES;
    };
    if (columnMajor) {
        for (NSInteger i = 0; i < columnCount && matches.count < maximumMatches && !cancelled; i += iStep) {
            NSInteger columnIndex = columnsLeftToRight ? i : (columnCount - 1 - i);
            for (NSInteger j = 0; j < rowCount && matches.count < maximumMatches; j += iStep) {
                NSInteger rowIndex = rowsTopToBottom ? j : (rowCount - 1 - j);
                evaluatePixel(columnIndex, rowIndex, i, j);
            }
        }
    } else {
        for (NSInteger i = 0; i < rowCount && matches.count < maximumMatches && !cancelled; i += iStep) {
            NSInteger rowIndex = rowsTopToBottom ? i : (rowCount - 1 - i);
            for (NSInteger j = 0; j < columnCount && matches.count < maximumMatches; j += iStep) {
                NSInteger columnIndex = columnsLeftToRight ? j : (columnCount - 1 - j);
                evaluatePixel(columnIndex, rowIndex, i, j);
            }
        }
    }
    AutoEnginePixelBufferDestroy(&buffer);
    if (cancelled) {
        if (error) *error = AutoMakeError(AutoSDKErrorScriptCancelled, @"Script cancelled.", nil);
        return nil;
    }
    return matches;
}

static NSString *AutoSystemWiFiIPv4Address(void) {
    NSString *result = nil;
    struct ifaddrs *interfaces = NULL;
    if (getifaddrs(&interfaces) == 0) {
        for (struct ifaddrs *interface = interfaces; interface; interface = interface->ifa_next) {
            if (!interface->ifa_addr || interface->ifa_addr->sa_family != AF_INET) continue;
            if ((interface->ifa_flags & IFF_UP) == 0) continue;
            NSString *name = [NSString stringWithUTF8String:interface->ifa_name ?: ""];
            if ([name isEqualToString:@"en0"] || [name isEqualToString:@"en1"]) {
                struct sockaddr_in *address = (struct sockaddr_in *)interface->ifa_addr;
                char buffer[INET_ADDRSTRLEN] = {0};
                if (inet_ntop(AF_INET, &address->sin_addr, buffer, sizeof(buffer))) {
                    result = [NSString stringWithUTF8String:buffer];
                    break;
                }
            }
        }
        freeifaddrs(interfaces);
    }
    return result;
}

static id AutoEngineHandleAudio(AutoEngine *engine, NSString *name, NSArray *arguments, NSDictionary *config) {
    if (!engine) return AutoMakeError(AutoSDKErrorAutomationFailed, @"Audio engine is unavailable.", nil);
    if ([name isEqualToString:@"stopMp3"]) {
        [engine stopAllAudioPlayback];
        return @YES;
    }
    if ([name isEqualToString:@"speak"] || [name isEqualToString:@"tts"] || [name isEqualToString:@"speech"]) {
        if (!AutoPermission(config, @"allowAudio", YES)) {
            return AutoMakeError(AutoSDKErrorInvalidConfiguration, @"Speech synthesis is disabled by configuration.", nil);
        }
        NSString *speechText = [arguments.firstObject isKindOfClass:NSString.class] ? arguments.firstObject : nil;
        if (speechText.length == 0) {
            return AutoMakeError(AutoSDKErrorInvalidConfiguration, @"speak requires a non-empty text string.", nil);
        }
        NSDictionary *speechOptions = [arguments count] > 1 && [arguments[1] isKindOfClass:NSDictionary.class] ? arguments[1] : nil;
        AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:speechText];
        if (AutoFiniteNumber(speechOptions[@"rate"])) {
            double rate = [speechOptions[@"rate"] doubleValue];
            utterance.rate = (float)MIN(AVSpeechUtteranceMaximumSpeechRate, MAX(AVSpeechUtteranceMinimumSpeechRate, rate));
        }
        if (AutoFiniteNumber(speechOptions[@"volume"])) {
            double volume = [speechOptions[@"volume"] doubleValue];
            utterance.volume = (float)MIN(1.0, MAX(0.0, volume));
        }
        if ([speechOptions[@"language"] isKindOfClass:NSString.class] && [speechOptions[@"language"] length] > 0) {
            AVSpeechSynthesisVoice *speechVoice = [AVSpeechSynthesisVoice voiceWithLanguage:speechOptions[@"language"]];
            if (speechVoice) utterance.voice = speechVoice;
        }
        BOOL speechStopWhenScriptEnd = AutoBoolean([arguments count] > 2 ? arguments[2] : nil, NO);
        [AVAudioSession.sharedInstance setCategory:AVAudioSessionCategoryPlayback error:nil];
        [AVAudioSession.sharedInstance setActive:YES error:nil];
        @synchronized (engine) {
            engine.speechStopWhenScriptEnd = speechStopWhenScriptEnd;
            [engine.speechSynthesizer stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
            if (!engine.speechSynthesizer) engine.speechSynthesizer = [AVSpeechSynthesizer new];
            [engine.speechSynthesizer speakUtterance:utterance];
            return @YES;
        }
    }
    if ([name isEqualToString:@"speechStop"] || [name isEqualToString:@"stopSpeak"]) {
        @synchronized (engine) {
            [engine.speechSynthesizer stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
        }
        return @YES;
    }
    if ([name isEqualToString:@"audioStop"] || [name isEqualToString:@"stopAudio"]) {
        double stopId = AutoFiniteDouble(arguments.count > 0 ? arguments[0] : nil, 0);
        if (stopId > 0) {
            NSNumber *key = @((long long)stopId);
            AVAudioPlayer *target = nil;
            @synchronized (engine) {
                target = engine.audioPlayersById[key];
                if (target) [engine.audioPlayersById removeObjectForKey:key];
            }
            if (target && target.isPlaying) [target stop];
        } else {
            [engine stopAllAudioPlayback];
        }
        return @YES;
    }
    if (!AutoPermission(config, @"allowAudio", YES)) {
        return AutoMakeError(AutoSDKErrorInvalidConfiguration, @"Audio playback is disabled by configuration.", nil);
    }
    NSString *path = [arguments.firstObject isKindOfClass:NSString.class] ? arguments.firstObject : nil;
    if (path.length == 0) {
        return AutoMakeError(AutoSDKErrorInvalidConfiguration, @"playMp3 requires a media file path.", nil);
    }
    NSError *error = nil;
    NSURL *sourceURL = AutoMediaSourceURL(path, config ?: @{}, &error);
    if (!sourceURL) return error ?: AutoMakeError(AutoSDKErrorFileOperationFailed, @"Unable to resolve the audio file.", nil);
    double volume = AutoFiniteDouble([arguments count] > 1 ? arguments[1] : nil, 100);
    volume = MIN(100.0, MAX(0.0, volume)) / 100.0;
    BOOL queue = AutoBoolean([arguments count] > 2 ? arguments[2] : nil, NO);
    BOOL stopWhenScriptEnd = AutoBoolean([arguments count] > 3 ? arguments[3] : nil, NO);
    [AVAudioSession.sharedInstance setCategory:AVAudioSessionCategoryPlayback error:nil];
    [AVAudioSession.sharedInstance setActive:YES error:nil];
    NSError *playerError = nil;
    AVAudioPlayer *player = [[AVAudioPlayer alloc] initWithContentsOfURL:sourceURL error:&playerError];
    if (!player) {
        return AutoMakeError(AutoSDKErrorAutomationFailed,
                             playerError ? [NSString stringWithFormat:@"Unable to open audio file: %@", playerError.localizedDescription]
                                         : @"Unable to open audio file.", nil);
    }
    player.volume = (float)volume;
    player.delegate = engine;
    if (![player prepareToPlay]) {
        return AutoMakeError(AutoSDKErrorAutomationFailed, @"Unable to prepare the audio player.", nil);
    }
    BOOL started = NO;
    @synchronized (engine) {
        if (!engine.audioPlayers) engine.audioPlayers = [NSMutableArray array];
        engine.audioStopWhenScriptEnd = stopWhenScriptEnd;
        if (queue && engine.audioPlayers.count > 0) {
            [engine.audioPlayers addObject:player];
            return @YES;
        }
        for (AVAudioPlayer *existing in engine.audioPlayers) {
            if (existing.isPlaying) [existing stop];
        }
        [engine.audioPlayers removeAllObjects];
        [engine.audioPlayers addObject:player];
        started = [player play];
    }
    return @(started);
}
static id AutoEngineHandleAudioPlay(AutoEngine *engine, NSString *name, NSArray *arguments, NSDictionary *config) {
    if (!engine) return AutoMakeError(AutoSDKErrorAutomationFailed, @"Audio engine is unavailable.", nil);
    if (!AutoPermission(config, @"allowAudio", YES)) {
        return AutoMakeError(AutoSDKErrorInvalidConfiguration, @"Audio playback is disabled by configuration.", nil);
    }
    NSString *path = [arguments.firstObject isKindOfClass:NSString.class] ? arguments.firstObject : nil;
    if (path.length == 0) {
        return AutoMakeError(AutoSDKErrorInvalidConfiguration, @"audioPlay requires a media file path.", nil);
    }
    NSError *error = nil;
    NSURL *sourceURL = AutoMediaSourceURL(path, config ?: @{}, &error);
    if (!sourceURL) return error ?: AutoMakeError(AutoSDKErrorFileOperationFailed, @"Unable to resolve the audio file.", nil);
    double volume = AutoFiniteDouble([arguments count] > 1 ? arguments[1] : nil, 100);
    volume = MIN(100.0, MAX(0.0, volume)) / 100.0;
    BOOL stopWhenScriptEnd = AutoBoolean([arguments count] > 2 ? arguments[2] : nil, NO);
    [AVAudioSession.sharedInstance setCategory:AVAudioSessionCategoryPlayback error:nil];
    [AVAudioSession.sharedInstance setActive:YES error:nil];
    NSError *playerError = nil;
    AVAudioPlayer *player = [[AVAudioPlayer alloc] initWithContentsOfURL:sourceURL error:&playerError];
    if (!player) {
        return AutoMakeError(AutoSDKErrorAutomationFailed,
                             playerError ? [NSString stringWithFormat:@"Unable to open audio file: %@", playerError.localizedDescription]
                                         : @"Unable to open audio file.", nil);
    }
    player.volume = (float)volume;
    player.delegate = engine;
    if (![player prepareToPlay]) {
        return AutoMakeError(AutoSDKErrorAutomationFailed, @"Unable to prepare the audio player.", nil);
    }
    NSNumber *playerId = nil;
    BOOL started = NO;
    @synchronized (engine) {
        if (!engine.audioPlayersById) engine.audioPlayersById = [NSMutableDictionary dictionary];
        engine.audioStopWhenScriptEnd = stopWhenScriptEnd;
        engine.audioPlayerIdCounter += 1;
        playerId = @((long long)engine.audioPlayerIdCounter);
        engine.audioPlayersById[playerId] = player;
        started = [player play];
    }
    if (!started) {
        @synchronized (engine) {
            [engine.audioPlayersById removeObjectForKey:playerId];
        }
        return @{ @"id": playerId, @"playing": @NO };
    }
    return @{ @"id": playerId, @"playing": @YES };
}
static BOOL AutoEnsurePhotoLibraryAccess(AutoEngine *engine,
                                         NSDictionary *config,
                                         PHAccessLevel accessLevel,
                                         NSString *usageDescriptionKey,
                                         NSError **error) {
    PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatusForAccessLevel:accessLevel];
    if (status == PHAuthorizationStatusAuthorized || status == PHAuthorizationStatusLimited) return YES;
    if (status == PHAuthorizationStatusDenied || status == PHAuthorizationStatusRestricted) {
        if (error) *error = AutoMakeError(AutoSDKErrorFileAccessDenied,
                                          @"Photo library access was denied. Enable Photos access in Settings.", nil);
        return NO;
    }

    id usageDescription = [NSBundle.mainBundle objectForInfoDictionaryKey:usageDescriptionKey];
    if (![usageDescription isKindOfClass:NSString.class] || [usageDescription length] == 0) {
        if (error) *error = AutoMakeError(AutoSDKErrorInvalidConfiguration,
                                          [NSString stringWithFormat:@"%@ is required for this media operation.", usageDescriptionKey], nil);
        return NO;
    }

    __block PHAuthorizationStatus requestedStatus = PHAuthorizationStatusNotDetermined;
    dispatch_semaphore_t finished = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_main_queue(), ^{
        [PHPhotoLibrary requestAuthorizationForAccessLevel:accessLevel handler:^(PHAuthorizationStatus newStatus) {
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
                                      @"Photo library access was denied. Enable Photos access in Settings.", nil);
    return NO;
}

static BOOL AutoEnsurePhotoLibraryWriteAccess(AutoEngine *engine,
                                              NSDictionary *config,
                                              NSError **error) {
    return AutoEnsurePhotoLibraryAccess(engine,
                                        config,
                                        PHAccessLevelAddOnly,
                                        @"NSPhotoLibraryAddUsageDescription",
                                        error);
}

static BOOL AutoEnsurePhotoLibraryReadWriteAccess(AutoEngine *engine,
                                                  NSDictionary *config,
                                                  NSError **error) {
    return AutoEnsurePhotoLibraryAccess(engine,
                                        config,
                                        PHAccessLevelReadWrite,
                                        @"NSPhotoLibraryUsageDescription",
                                        error);
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

// Multipart field/file names are interpolated into Content-Disposition headers,
// so they must not contain quotes, CR/LF or other control characters.
static BOOL AutoHTTPFieldNameIsValid(NSString *name) {
    if (![name isKindOfClass:NSString.class] || name.length == 0) return NO;
    if ([name rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) return NO;
    if ([name rangeOfString:@"\""].location != NSNotFound) return NO;
    return YES;
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
    if ([data[@"cookies"] isKindOfClass:NSDictionary.class]) {
        NSDictionary *cookies = data[@"cookies"];
        if (cookies.count > 64) {
            if (error) *error = AutoMakeError(AutoSDKErrorNetworkFailed, @"HTTP requests accept at most 64 cookies.", nil);
            return nil;
        }
        NSMutableArray *cookiePairs = [NSMutableArray array];
        for (id rawKey in cookies) {
            id value = cookies[rawKey];
            if (![rawKey isKindOfClass:NSString.class] || [(NSString *)rawKey length] == 0 ||
                [(NSString *)rawKey lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 1024 ||
                ![value isKindOfClass:NSString.class] || [(NSString *)value lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 4096) {
                if (error) *error = AutoMakeError(AutoSDKErrorNetworkFailed, @"Cookie names or values are invalid or too long.", nil);
                return nil;
            }
            [cookiePairs addObject:[NSString stringWithFormat:@"%@=%@", rawKey, value]];
        }
        if (cookiePairs.count > 0) {
            [request setValue:[cookiePairs componentsJoinedByString:@"; "] forHTTPHeaderField:@"Cookie"];
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
    if ([data[@"files"] isKindOfClass:NSDictionary.class] && ((NSDictionary *)data[@"files"]).count > 0) {
        NSDictionary *files = data[@"files"];
        if (files.count > 16) {
            if (error) *error = AutoMakeError(AutoSDKErrorNetworkFailed, @"HTTP requests accept at most 16 upload files.", nil);
            return nil;
        }
        NSDictionary *formData = [data[@"formData"] isKindOfClass:NSDictionary.class] ? data[@"formData"] : @{};
        if (formData.count + files.count > 64) {
            if (error) *error = AutoMakeError(AutoSDKErrorNetworkFailed, @"HTTP multipart requests accept at most 64 fields.", nil);
            return nil;
        }
        NSString *boundary = [NSString stringWithFormat:@"AutoSDKBoundary%@", [NSUUID UUID].UUIDString];
        NSMutableData *bodyData = [NSMutableData data];
        for (id rawKey in formData) {
            id value = formData[rawKey];
            if (![rawKey isKindOfClass:NSString.class] || [(NSString *)rawKey length] == 0 ||
                [rawKey lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 256 ||
                !AutoHTTPFieldNameIsValid(rawKey) ||
                ![value isKindOfClass:NSString.class] || [(NSString *)value lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 8192) {
                if (error) *error = AutoMakeError(AutoSDKErrorNetworkFailed, @"Multipart form field names or values are invalid or too long.", nil);
                return nil;
            }
            [bodyData appendData:[[NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"%@\"\r\n\r\n%@\r\n", boundary, rawKey, value] dataUsingEncoding:NSUTF8StringEncoding]];
        }
        for (id rawKey in files) {
            id pathValue = files[rawKey];
            if (![rawKey isKindOfClass:NSString.class] || [(NSString *)rawKey length] == 0 ||
                [rawKey lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 256 ||
                !AutoHTTPFieldNameIsValid(rawKey)) {
                if (error) *error = AutoMakeError(AutoSDKErrorNetworkFailed, @"Multipart file field names are invalid.", nil);
                return nil;
            }
            NSError *fileResolveError = nil;
            NSURL *fileURL = AutoMediaSourceURL(pathValue, config, &fileResolveError);
            if (!fileURL) {
                if (error) *error = fileResolveError ?: AutoMakeError(AutoSDKErrorFileOperationFailed, @"Unable to resolve the upload file.", nil);
                return nil;
            }
            NSData *fileData = [NSData dataWithContentsOfURL:fileURL options:NSDataReadingMappedIfSafe error:nil];
            if (!fileData) {
                if (error) *error = AutoMakeError(AutoSDKErrorFileOperationFailed, @"Unable to read the upload file.", nil);
                return nil;
            }
            if (bodyData.length + fileData.length > maximumRequestBytes) {
                if (error) *error = AutoMakeError(AutoSDKErrorNetworkFailed, @"Request body exceeds maxHTTPRequestBytes.", nil);
                return nil;
            }
            NSString *fileName = fileURL.lastPathComponent;
            if (!AutoHTTPFieldNameIsValid(fileName)) {
                if (error) *error = AutoMakeError(AutoSDKErrorNetworkFailed, @"Upload file names must not contain quotes or control characters.", nil);
                return nil;
            }
            NSString *extension = fileName.pathExtension.lowercaseString;
            NSString *mime = [extension isEqualToString:@"png"] ? @"image/png"
                            : ([extension isEqualToString:@"jpg"] || [extension isEqualToString:@"jpeg"]) ? @"image/jpeg"
                            : ([extension isEqualToString:@"gif"]) ? @"image/gif"
                            : ([extension isEqualToString:@"txt"]) ? @"text/plain"
                            : ([extension isEqualToString:@"json"]) ? @"application/json"
                            : ([extension isEqualToString:@"mp4"]) ? @"video/mp4"
                            : ([extension isEqualToString:@"mp3"]) ? @"audio/mpeg"
                            : @"application/octet-stream";
            [bodyData appendData:[[NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"%@\"; filename=\"%@\"\r\nContent-Type: %@\r\n\r\n", boundary, rawKey, fileName, mime] dataUsingEncoding:NSUTF8StringEncoding]];
            [bodyData appendData:fileData];
            [bodyData appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
        }
        [bodyData appendData:[[NSString stringWithFormat:@"--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
        if (bodyData.length > maximumRequestBytes) {
            if (error) *error = AutoMakeError(AutoSDKErrorNetworkFailed, @"Request body exceeds maxHTTPRequestBytes.", nil);
            return nil;
        }
        request.HTTPBody = bodyData;
        if (![request valueForHTTPHeaderField:@"Content-Type"]) {
            [request setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary] forHTTPHeaderField:@"Content-Type"];
        }
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
    if (![self.engine shouldStop] && !self.threadCancelled) {
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
        while (![self.engine shouldStop] && !self.threadCancelled) {
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

- (id)invokeScreenshotRegion:(JSValue *)payload {
    if (![self ensureScriptRunning]) return @NO;
    NSDictionary *data = AutoPayload(payload);
    if (!AutoPayloadHasFiniteNumbers(data, @[@"x", @"y", @"width", @"height"])) {
        return [self failure:AutoMakeError(AutoSDKErrorInvalidConfiguration, @"screenshotRegion requires finite x, y, width and height.", nil)];
    }
    double x = [data[@"x"] doubleValue];
    double y = [data[@"y"] doubleValue];
    double width = [data[@"width"] doubleValue];
    double height = [data[@"height"] doubleValue];
    if (width <= 0 || height <= 0) {
        return [self failure:AutoMakeError(AutoSDKErrorInvalidConfiguration, @"screenshotRegion width and height must be positive.", nil)];
    }
    NSError *error = nil;
    NSData *captured = [self.adapter screenshotWithError:&error];
    if (error) return [self failure:error];
    if (captured.length == 0) return [NSNull null];
    UIImage *image = [UIImage imageWithData:captured];
    if (!image) return [self failure:AutoMakeError(AutoSDKErrorAutomationFailed, @"Unable to decode the screenshot.", nil)];
    CGFloat scale = image.scale > 0 ? image.scale : 1.0;
    CGRect requested = CGRectMake(x * scale, y * scale, width * scale, height * scale);
    CGRect bounds = CGRectMake(0, 0, image.size.width * scale, image.size.height * scale);
    CGRect clipped = CGRectIntersection(requested, bounds);
    if (CGRectIsNull(clipped) || clipped.size.width <= 0 || clipped.size.height <= 0) {
        return [self failure:AutoMakeError(AutoSDKErrorInvalidConfiguration, @"screenshotRegion is outside the screenshot bounds.", nil)];
    }
    CGImageRef source = image.CGImage;
    CGImageRef cropped = CGImageCreateWithImageInRect(source, clipped);
    if (!cropped) return [self failure:AutoMakeError(AutoSDKErrorAutomationFailed, @"Unable to crop the screenshot.", nil)];
    UIImage *result = [UIImage imageWithCGImage:cropped scale:scale orientation:image.imageOrientation];
    CGImageRelease(cropped);
    NSData *output = UIImagePNGRepresentation(result);
    if (!output) return [self failure:AutoMakeError(AutoSDKErrorAutomationFailed, @"Unable to encode the cropped screenshot.", nil)];
    if (output.length > AutoScreenshotByteLimit(self.config ?: @{})) {
        return [self failure:AutoMakeError(AutoSDKErrorAutomationFailed, @"Screenshot exceeds maxScreenshotBytes.", nil)];
    }
    return [output base64EncodedStringWithOptions:0];
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
    if ([operation isEqualToString:@"photoauthorizationstatus"] || [operation isEqualToString:@"photoauthorizationrequest"]) {
        PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelAddOnly];
        if ([operation isEqualToString:@"photoauthorizationrequest"] && status == PHAuthorizationStatusNotDetermined) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly handler:^(PHAuthorizationStatus newStatus) {
                    (void)newStatus;
                }];
            });
        }
        return AutoPhotoAuthorizationStatusString(status);
    }
    if ([operation isEqualToString:@"deleteallphotos"] ||
        [operation isEqualToString:@"deleteallvideos"] ||
        [operation isEqualToString:@"deleteallmedia"]) {
        BOOL deletePhotos = YES;
        BOOL deleteVideos = YES;
        if ([operation isEqualToString:@"deleteallphotos"]) deleteVideos = NO;
        else if ([operation isEqualToString:@"deleteallvideos"]) deletePhotos = NO;
        NSError *error = nil;
        if (!AutoEnsurePhotoLibraryReadWriteAccess(self.engine, self.config ?: @{}, &error)) {
            return [self failure:error];
        }
        if (![self ensureScriptRunning]) return @NO;
        __block NSUInteger deletedCount = 0;
        __block NSError *deleteError = nil;
        BOOL changed = [PHPhotoLibrary.sharedPhotoLibrary performChangesAndWait:^{
            PHFetchResult<PHAsset *> *assets = [PHAsset fetchAssetsWithOptions:nil];
            NSMutableArray<PHAsset *> *targets = [NSMutableArray array];
            [assets enumerateObjectsUsingBlock:^(PHAsset *asset, NSUInteger idx, BOOL *stop) {
                if (deletePhotos && asset.mediaType == PHAssetMediaTypeImage) [targets addObject:asset];
                else if (deleteVideos && asset.mediaType == PHAssetMediaTypeVideo) [targets addObject:asset];
            }];
            deletedCount = targets.count;
            if (targets.count > 0) {
                [PHAssetChangeRequest deleteAssets:targets];
            }
        } error:&deleteError];
        if (!changed || deleteError) {
            return [self failure:AutoMakeError(AutoSDKErrorAutomationFailed,
                                               @"Unable to delete media from the photo library.", deleteError)];
        }
        return @{ @"deleted": @(deletedCount) };
    }
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

- (id)invokeFindColorEx:(JSValue *)payload {
    if (![self ensureScriptRunning]) return @NO;
    NSDictionary *data = AutoPayload(payload);
    double threshold = AutoFiniteDouble(data[@"threshold"], 0.9);
    threshold = MIN(1.0, MAX(0.0, threshold));
    double x = AutoFiniteDouble(data[@"x"], 0);
    double y = AutoFiniteDouble(data[@"y"], 0);
    double ex = AutoFiniteDouble(data[@"ex"], 0);
    double ey = AutoFiniteDouble(data[@"ey"], 0);
    double limit = AutoFiniteDouble(data[@"limit"], 10);
    double direction = AutoFiniteDouble(data[@"direction"], 1);
    if (!isfinite(x) || !isfinite(y) || !isfinite(ex) || !isfinite(ey) ||
        !isfinite(limit) || !isfinite(direction)) {
        return [self failure:AutoMakeError(AutoSDKErrorInvalidConfiguration,
                                           @"findColorEx requires finite coordinates, limit and direction.", nil)];
    }
    NSArray *targets = AutoEngineParseColorTargets(data[@"colors"], (CGFloat)threshold);
    if (targets.count == 0) {
        return [self failure:AutoMakeError(AutoSDKErrorInvalidConfiguration,
                                           @"findColorEx requires at least one valid color target.", nil)];
    }
    if (limit < 1) limit = 1;
    if (limit > 1000) limit = 1000;
    NSUInteger order = (NSUInteger)direction;
    if (order < 1 || order > 8) order = 1;
    NSError *error = nil;
    NSString *cachedScreenPath = [data[@"screenshotPath"] isKindOfClass:NSString.class] ? data[@"screenshotPath"] : nil;
    NSArray *matches = AutoEngineScanColorPoints(self.adapter, self.engine, targets,
                                                 x, y, ex, ey, (NSUInteger)limit, order, NO, cachedScreenPath, &error);
    if (error) return [self failure:error];
    return matches.count > 0 ? matches : [NSNull null];
}

- (id)invokeFindNotColor:(JSValue *)payload {
    if (![self ensureScriptRunning]) return @NO;
    NSDictionary *data = AutoPayload(payload);
    double threshold = AutoFiniteDouble(data[@"threshold"], 0.9);
    threshold = MIN(1.0, MAX(0.0, threshold));
    double x = AutoFiniteDouble(data[@"x"], 0);
    double y = AutoFiniteDouble(data[@"y"], 0);
    double ex = AutoFiniteDouble(data[@"ex"], 0);
    double ey = AutoFiniteDouble(data[@"ey"], 0);
    double limit = AutoFiniteDouble(data[@"limit"], 10);
    double direction = AutoFiniteDouble(data[@"direction"], 1);
    if (!isfinite(x) || !isfinite(y) || !isfinite(ex) || !isfinite(ey) ||
        !isfinite(limit) || !isfinite(direction)) {
        return [self failure:AutoMakeError(AutoSDKErrorInvalidConfiguration,
                                           @"findNotColor requires finite coordinates, limit and direction.", nil)];
    }
    NSArray *targets = AutoEngineParseColorTargets(data[@"colors"], (CGFloat)threshold);
    if (targets.count == 0) {
        return [self failure:AutoMakeError(AutoSDKErrorInvalidConfiguration,
                                           @"findNotColor requires at least one valid color target.", nil)];
    }
    if (limit < 1) limit = 1;
    if (limit > 1000) limit = 1000;
    NSUInteger order = (NSUInteger)direction;
    if (order < 1 || order > 8) order = 1;
    NSError *error = nil;
    NSString *cachedScreenPath = [data[@"screenshotPath"] isKindOfClass:NSString.class] ? data[@"screenshotPath"] : nil;
    NSArray *matches = AutoEngineScanColorPoints(self.adapter, self.engine, targets,
                                                 x, y, ex, ey, (NSUInteger)limit, order, YES, cachedScreenPath, &error);
    if (error) return [self failure:error];
    return matches.count > 0 ? matches : [NSNull null];
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
    NSMutableDictionary *responseCookies = [NSMutableDictionary dictionary];
    for (id key in httpResponse.allHeaderFields) {
        if ([[key description] caseInsensitiveCompare:@"Set-Cookie"] != NSOrderedSame) continue;
        NSString *headerValue = [httpResponse.allHeaderFields[key] description] ?: @"";
        NSRange separator = [headerValue rangeOfString:@";"];
        NSString *pair = separator.location == NSNotFound ? headerValue : [headerValue substringToIndex:separator.location];
        NSRange equals = [pair rangeOfString:@"="];
        if (equals.location != NSNotFound && equals.location > 0) {
            NSString *cookieName = [[pair substringToIndex:equals.location] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            NSString *cookieValue = [[pair substringFromIndex:equals.location + 1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            if (cookieName.length > 0 && cookieName.length <= 1024 && cookieValue.length <= 4096) {
                responseCookies[cookieName] = cookieValue;
            }
        }
    }
    if (responseCookies.count > 0) result[@"cookies"] = responseCookies;
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

- (id)invokeNodeSnapshot:(JSValue *)payload {
    if (![self ensureScriptRunning]) return @NO;
    if (![self.adapter respondsToSelector:@selector(nodeSnapshotWithMaxResults:error:)]) {
        return [self failure:AutoMakeError(AutoSDKErrorAutomationUnavailable, @"The automation adapter does not support node snapshots.", nil)];
    }
    NSDictionary *data = AutoPayload(payload);
    NSUInteger maxResults = AutoBoundedPositiveInteger(data[@"maxResults"], 500, 2000);
    NSError *error = nil;
    NSArray *nodes = [self.adapter nodeSnapshotWithMaxResults:maxResults error:&error];
    return error ? [self failure:error] : (nodes ?: @[]);
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
    NSError *error = nil;
    if ([operation isEqualToString:@"info"]) {
        NSDictionary *info = AutoValueOnMainThread(^id{ return [self.engine getDeviceInfo]; });
        return info ?: @{};
    }
    if ([operation isEqualToString:@"clipboardGet"] || [operation isEqualToString:@"clipboardSet"] ||
        [operation isEqualToString:@"brightnessGet"] || [operation isEqualToString:@"brightnessSet"] ||
        [operation isEqualToString:@"volumeGet"] || [operation isEqualToString:@"vibrate"] ||
        [operation isEqualToString:@"keepScreenOn"] || [operation isEqualToString:@"flashlight"] ||
        [operation isEqualToString:@"vpnSet"] || [operation isEqualToString:@"openSystemSettings"] ||
        [operation isEqualToString:@"torch"]) {
        if (!AutoPermission(self.config, @"allowSystemControl", YES)) {
            return [self failure:AutoMakeError(AutoSDKErrorInvalidConfiguration, @"System control is disabled by configuration.", nil)];
        }
    }
    if ([operation isEqualToString:@"memory"]) {
        return AutoValueOnMainThread(^id{ return [self.engine deviceMemoryInfo]; }) ?: @{};
    }
    if ([operation isEqualToString:@"lowPowerMode"]) {
        id<AutoSystemStatusProviding> provider = self.engine.systemStatusProviderForTesting;
        return @(provider ? [provider autoLowPowerModeEnabled] : NSProcessInfo.processInfo.lowPowerModeEnabled);
    }
    if ([operation isEqualToString:@"locationServices"]) {
        id<AutoSystemStatusProviding> provider = self.engine.systemStatusProviderForTesting;
        return @(provider ? [provider autoLocationServicesEnabled] : [CLLocationManager locationServicesEnabled]);
    }
    if ([operation isEqualToString:@"locationAuthorization"]) {
        id<AutoSystemStatusProviding> provider = self.engine.systemStatusProviderForTesting;
        CLAuthorizationStatus status = provider ? [provider autoLocationAuthorizationStatus]
                                                : CLLocationManager.authorizationStatus;
        return AutoLocationAuthorizationStatusName(status);
    }
    if ([operation isEqualToString:@"vpnStatus"] || [operation isEqualToString:@"vpnSet"]) {
        NEVPNManager *manager = AutoLoadPersonalVPNManager(^BOOL { return [self invokeIsStopped]; }, &error);
        if (!manager) return [self failure:error];
        if (![self ensureScriptRunning]) return @NO;
        if ([operation isEqualToString:@"vpnStatus"]) return AutoVPNStatusName(manager.connection.status);
        BOOL connect = AutoBoolean(data[@"value"], YES);
        if (!connect) {
            [manager.connection stopVPNTunnel];
            return @YES;
        }
        if (!manager.protocolConfiguration || !manager.enabled) {
            return [self failure:AutoMakeError(AutoSDKErrorInvalidConfiguration,
                                                @"No enabled Personal VPN configuration belongs to this host app.", nil)];
        }
        NSError *startError = nil;
        BOOL started = [manager.connection startVPNTunnelAndReturnError:&startError];
        return started ? @YES : [self failure:AutoMakeError(AutoSDKErrorAutomationFailed,
                                                            @"Unable to start the Personal VPN connection.", startError)];
    }
    if ([operation isEqualToString:@"openSystemSettings"]) {
        NSString *page = [data[@"page"] isKindOfClass:NSString.class] ? data[@"page"] : @"app";
        if (page.length == 0 || page.length > 32) {
            return [self failure:AutoMakeError(AutoSDKErrorInvalidConfiguration,
                                                @"System settings page must contain 1 to 32 characters.", nil)];
        }
        NSURL *settingsURL = AutoSystemSettingsURL(page);
        if (!settingsURL) {
            return [self failure:AutoMakeError(AutoSDKErrorInvalidConfiguration,
                                                @"Unknown system settings page.", nil)];
        }
        BOOL opened = [AutoValueOnMainThread(^id{ return @([UIApplication.sharedApplication openURL:settingsURL]); }) boolValue];
        if (!opened && ![page.lowercaseString isEqualToString:@"app"]) {
            NSURL *fallbackURL = [NSURL URLWithString:@"App-prefs:"];
            opened = [AutoValueOnMainThread(^id{ return @([UIApplication.sharedApplication openURL:fallbackURL]); }) boolValue];
        }
        if (!opened) {
            NSURL *appSettingsURL = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
            opened = [AutoValueOnMainThread(^id{ return @([UIApplication.sharedApplication openURL:appSettingsURL]); }) boolValue];
        }
        return @(opened);
    }
    if ([operation isEqualToString:@"language"] || [operation isEqualToString:@"country"] ||
        [operation isEqualToString:@"locale"] || [operation isEqualToString:@"timezone"] ||
        [operation isEqualToString:@"uptime"] || [operation isEqualToString:@"networkType"] ||
        [operation isEqualToString:@"isWifi"]) {
        NSDictionary *deviceInfo = AutoValueOnMainThread(^id{ return [self.engine getDeviceInfo]; }) ?: @{};
        if ([operation isEqualToString:@"language"]) return deviceInfo[@"language"] ?: @"";
        if ([operation isEqualToString:@"country"]) return deviceInfo[@"country"] ?: @"";
        if ([operation isEqualToString:@"locale"]) return deviceInfo[@"locale"] ?: @"";
        if ([operation isEqualToString:@"timezone"]) return deviceInfo[@"timezone"] ?: @"";
        if ([operation isEqualToString:@"uptime"]) return deviceInfo[@"uptimeSeconds"] ?: @0;
        if ([operation isEqualToString:@"networkType"]) return AutoCurrentNetworkType();
        return @([AutoCurrentNetworkType() isEqualToString:@"wifi"]);
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
    if ([operation isEqualToString:@"keepScreenOn"]) {
        BOOL keepOn = AutoBoolean(data[@"value"], YES);
        AutoValueOnMainThread(^id{
            UIApplication.sharedApplication.idleTimerDisabled = keepOn;
            return @YES;
        });
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
    if ([operation isEqualToString:@"flashlight"] || [operation isEqualToString:@"torch"]) {
        BOOL torchOn = AutoBoolean(data[@"value"], YES);
        AVCaptureDevice *captureDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        if (!captureDevice || ![captureDevice hasTorch]) return @NO;
        NSError *torchError = nil;
        if (![captureDevice lockForConfiguration:&torchError]) return @NO;
        captureDevice.torchMode = torchOn ? AVCaptureTorchModeOn : AVCaptureTorchModeOff;
        [captureDevice unlockForConfiguration];
        return @YES;
    }
    if ([operation isEqualToString:@"volumeUp"] || [operation isEqualToString:@"volumeDown"]) {
        if (!AutoPermission(self.config, @"allowSystemControl", YES)) {
            return [self failure:AutoMakeError(AutoSDKErrorInvalidConfiguration, @"System control is disabled by configuration.", nil)];
        }
        if (![self.adapter respondsToSelector:@selector(pressButtonWithName:error:)]) {
            return [self failure:AutoMakeError(AutoSDKErrorAutomationUnavailable, @"The automation adapter does not support hardware button presses.", nil)];
        }
        NSString *buttonName = [operation isEqualToString:@"volumeUp"] ? @"volumeUp" : @"volumeDown";
        BOOL ok = [self.adapter pressButtonWithName:buttonName error:&error];
        return error ? [self failure:error] : @(ok);
    }
    if ([operation isEqualToString:@"isScreenOn"]) {
        if (!AutoPermission(self.config, @"allowSystemControl", YES)) {
            return [self failure:AutoMakeError(AutoSDKErrorInvalidConfiguration, @"System control is disabled by configuration.", nil)];
        }
        if (![self.adapter respondsToSelector:@selector(deviceLockedStateWithError:)]) {
            return [self failure:AutoMakeError(AutoSDKErrorAutomationUnavailable, @"The automation adapter does not report screen lock state.", nil)];
        }
        NSNumber *locked = [self.adapter deviceLockedStateWithError:&error];
        if (error) return [self failure:error];
        return @(!locked.boolValue);
    }
    NSDictionary *mapping = @{ @"screenWidth": @"screenWidth", @"screenHeight": @"screenHeight",
                               @"scale": @"screenScale", @"model": @"model", @"osVersion": @"systemVersion",
                               @"name": @"name", @"battery": @"batteryLevel", @"isCharging": @"isCharging",
                               @"orientation": @"orientation", @"deviceId": @"deviceId",
                               @"appVersion": @"appVersion", @"packageName": @"bundleId",
                               @"bundleId": @"bundleId" };
    if ([operation isEqualToString:@"ipAddress"]) {
        NSString *address = AutoSystemWiFiIPv4Address();
        return address ?: [NSNull null];
    }
    if ([operation isEqualToString:@"serialNo"]) {
        // Third-party iOS apps cannot read the hardware serial number.
        return [NSNull null];
    }
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
    if ([operation isEqualToString:@"opensettings"] || [operation isEqualToString:@"openappstore"]) {
        if (!AutoPermission(self.config, @"allowSystemControl", YES)) {
            return [self failure:AutoMakeError(AutoSDKErrorInvalidConfiguration, @"System control is disabled by configuration.", nil)];
        }
        NSString *appSchemeURL = nil;
        if ([operation isEqualToString:@"opensettings"]) {
            appSchemeURL = UIApplicationOpenSettingsURLString;
        } else {
            NSString *storeAppId = [data[@"appId"] isKindOfClass:NSString.class] ? data[@"appId"] : @"";
            if (storeAppId.length == 0) {
                return [self failure:AutoMakeError(AutoSDKErrorInvalidConfiguration, @"openAppStore requires an App Store app id.", nil)];
            }
            appSchemeURL = [NSString stringWithFormat:@"itms-apps://itunes.apple.com/app/id%@", storeAppId];
        }
        NSURL *appSchemeURLObject = [NSURL URLWithString:appSchemeURL];
        return @([AutoValueOnMainThread(^id{ return @([UIApplication.sharedApplication openURL:appSchemeURLObject]); }) boolValue]);
    }
    if ([operation isEqualToString:@"getappscheme"]) {
        NSString *name = [data[@"name"] isKindOfClass:NSString.class] ? data[@"name"] : @"";
        NSString *scheme = AutoAppSchemeForName(name);
        return scheme ?: [NSNull null];
    }
    if ([operation isEqualToString:@"launchbyscheme"]) {
        if (!AutoPermission(self.config, @"allowSystemControl", YES)) {
            return [self failure:AutoMakeError(AutoSDKErrorInvalidConfiguration, @"System control is disabled by configuration.", nil)];
        }
        NSString *name = [data[@"name"] isKindOfClass:NSString.class] ? data[@"name"] : @"";
        NSString *scheme = AutoAppSchemeForName(name);
        if (scheme.length == 0) return @NO;
        NSURL *url = [NSURL URLWithString:scheme];
        if (!AutoSystemURLSchemeAllowed(url)) return @NO;
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
    if ([operation isEqualToString:@"current"]) {
        if (![self.adapter respondsToSelector:@selector(currentApplicationWithError:)]) {
            return [self failure:AutoMakeError(AutoSDKErrorAutomationUnavailable, @"The automation adapter does not report the foreground application.", nil)];
        }
        NSString *bundleId = [self.adapter currentApplicationWithError:&error];
        return error ? [self failure:error] : (bundleId ?: [NSNull null]);
    }
    if ([operation isEqualToString:@"applist"]) {
        if (![self.adapter respondsToSelector:@selector(installedApplicationsWithError:)]) {
            return [self failure:AutoMakeError(AutoSDKErrorAutomationUnavailable, @"The automation adapter does not list installed applications.", nil)];
        }
        NSArray *apps = [self.adapter installedApplicationsWithError:&error];
        return error ? [self failure:error] : (apps ?: @[]);
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
    return [self.engine shouldStop] || self.threadCancelled;
}

- (id)invokeLastError {
    NSError *error = self.lastError;
    if (!error) return [NSNull null];
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[@"code"] = @(error.code);
    info[@"message"] = error.localizedDescription ?: @"";
    if (error.domain.length > 0) info[@"domain"] = error.domain;
    NSError *underlying = error.userInfo[NSUnderlyingErrorKey];
    if ([underlying isKindOfClass:NSError.class] && underlying.localizedDescription.length > 0) {
        info[@"underlying"] = underlying.localizedDescription;
    }
    return info;
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
        if ([name isEqualToString:@"md5"] || [name isEqualToString:@"sha1"] ||
            [name isEqualToString:@"sha256"] || [name isEqualToString:@"sha512"]) {
            id argument = [nativePayload[@"arguments"] isKindOfClass:NSArray.class] ? [nativePayload[@"arguments"] firstObject] : nil;
            NSString *input = [argument isKindOfClass:NSString.class] ? argument : [argument description];
            NSData *inputData = [input dataUsingEncoding:NSUTF8StringEncoding];
            if (!inputData) return @"";
            if ([name isEqualToString:@"md5"]) return AutoScriptMD5Hex(inputData);
            if ([name isEqualToString:@"sha1"]) return AutoScriptSHA1Hex(inputData);
            if ([name isEqualToString:@"sha256"]) return AutoScriptSHA256Hex(inputData);
            return AutoScriptSHA512Hex(inputData);
        }
        if ([name isEqualToString:@"hmac1"] || [name isEqualToString:@"hmac256"]) {
            NSArray *hmacArgs = [nativePayload[@"arguments"] isKindOfClass:NSArray.class] ? nativePayload[@"arguments"] : @[];
            NSString *text = hmacArgs.count > 0 && [hmacArgs[0] isKindOfClass:NSString.class] ? hmacArgs[0] : @"";
            NSString *key = hmacArgs.count > 1 && [hmacArgs[1] isKindOfClass:NSString.class] ? hmacArgs[1] : @"";
            return [name isEqualToString:@"hmac1"] ? AutoScriptHMACSHA1Hex(text, key) : AutoScriptHMACSHA256Hex(text, key);
        }
        if ([name isEqualToString:@"aes128Encrypt"] || [name isEqualToString:@"aes128Decrypt"]) {
            NSArray *aesArgs = [nativePayload[@"arguments"] isKindOfClass:NSArray.class] ? nativePayload[@"arguments"] : @[];
            NSString *text = aesArgs.count > 0 && [aesArgs[0] isKindOfClass:NSString.class] ? aesArgs[0] : @"";
            NSString *key = aesArgs.count > 1 && [aesArgs[1] isKindOfClass:NSString.class] ? aesArgs[1] : @"";
            return [name isEqualToString:@"aes128Encrypt"]
                ? AutoScriptAES128EncryptBase64(text, key)
                : AutoScriptAES128DecryptBase64(text, key);
        }
        if ([name isEqualToString:@"playMp3"] || [name isEqualToString:@"stopMp3"] || [name isEqualToString:@"audioPlay"] || [name isEqualToString:@"audioStop"] || [name isEqualToString:@"stopAudio"]) {
            id audioResult = AutoEngineHandleAudio(self.engine, name,
                                                   [nativePayload[@"arguments"] isKindOfClass:NSArray.class] ? nativePayload[@"arguments"] : @[],
                                                   self.config ?: @{});
            return [audioResult isKindOfClass:NSError.class] ? [self failure:audioResult] : audioResult;
        }
        if ([name isEqualToString:@"toast"]) {
            id message = [nativePayload[@"arguments"] isKindOfClass:NSArray.class] ? [nativePayload[@"arguments"] firstObject] : nil;
            NSString *text = [message isKindOfClass:NSString.class] ? message : [message description];
            if (text.length == 0) text = @"";
            AutoShowToast(text);
            return @YES;
        }
        if ([name isEqualToString:@"alert"]) {
            NSArray *args = [nativePayload[@"arguments"] isKindOfClass:NSArray.class] ? nativePayload[@"arguments"] : @[];
            id message = args.count > 0 ? args[0] : nil;
            id titleValue = args.count > 1 ? args[1] : nil;
            NSString *text = [message isKindOfClass:NSString.class] ? message : [message description];
            NSString *title = [titleValue isKindOfClass:NSString.class] ? titleValue : @"AutoSDK";
            if (text.length == 0) text = @"";
            dispatch_async(dispatch_get_main_queue(), ^{
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
                UIViewController *presenter = window.rootViewController;
                if (!presenter) return;
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                               message:text
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [presenter presentViewController:alert animated:YES completion:nil];
            });
            return @YES;
        }
        if ([name isEqualToString:@"exit"]) {
            [self.engine stopScript];
            return @YES;
        }
        if ([name isEqualToString:@"restartScript"]) {
            NSString *restartSource = self.engine.currentScriptSource;
            if (restartSource.length == 0) {
                return [self failure:AutoMakeError(AutoSDKErrorAutomationFailed, @"restartScript requires a script that was started from source.", nil)];
            }
            [self.engine stopScript];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
                [self.engine runScript:restartSource completion:nil];
            });
            return @YES;
        }
        if ([name isEqualToString:@"webViewInit"] || [name isEqualToString:@"webViewShow"] ||
            [name isEqualToString:@"webViewHidden"] || [name isEqualToString:@"webViewEval"] ||
            [name isEqualToString:@"webViewTakeMessage"] || [name isEqualToString:@"webViewLoadHTML"] ||
            [name isEqualToString:@"webViewRelease"]) {
            NSArray *webArgs = [nativePayload[@"arguments"] isKindOfClass:NSArray.class] ? nativePayload[@"arguments"] : @[];
            return [self handleWebViewOperation:name arguments:webArgs];
        }
        if ([name isEqualToString:@"scanCode"]) {
            NSArray *scanArgs = [nativePayload[@"arguments"] isKindOfClass:NSArray.class] ? nativePayload[@"arguments"] : @[];
            NSString *pathValue = scanArgs.count > 0 && [scanArgs[0] isKindOfClass:NSString.class] ? scanArgs[0] : @"";
            if (pathValue.length == 0) {
                return [self failure:AutoMakeError(AutoSDKErrorInvalidConfiguration, @"scanCode requires an image file path.", nil)];
            }
            NSError *resolveError = nil;
            id resolved = AutoScriptFileOperation(@{ @"operation": @"resolvePath", @"path": pathValue }, self.config ?: @{}, &resolveError);
            if (resolveError) return [self failure:resolveError];
            NSString *resolvedPath = [resolved isKindOfClass:NSString.class] ? resolved : pathValue;
            NSData *scanData = [NSData dataWithContentsOfFile:resolvedPath];
            if (!scanData) {
                return [self failure:AutoMakeError(AutoSDKErrorAutomationFailed, @"scanCode cannot read the image file.", nil)];
            }
            NSError *scanError = nil;
            NSArray *scanResults = AutoScanBarcodes(scanData, &scanError);
            return scanError ? [self failure:scanError] : (scanResults ?: @[]);
        }
        if ([name isEqualToString:@"wsConnect"] || [name isEqualToString:@"wsPoll"] ||
            [name isEqualToString:@"wsSend"] || [name isEqualToString:@"wsClose"]) {
            NSArray *wsArgs = [nativePayload[@"arguments"] isKindOfClass:NSArray.class] ? nativePayload[@"arguments"] : @[];
            id wsResult = AutoHandleWebSocket(name, wsArgs);
            return [wsResult isKindOfClass:NSError.class] ? [self failure:wsResult] : wsResult;
        }
        if ([name isEqualToString:@"notify"]) {
            NSArray *notifyArgs = [nativePayload[@"arguments"] isKindOfClass:NSArray.class] ? nativePayload[@"arguments"] : @[];
            id bodyValue = notifyArgs.count > 0 ? notifyArgs[0] : nil;
            id titleValue = notifyArgs.count > 1 ? notifyArgs[1] : nil;
            NSString *body = [bodyValue isKindOfClass:NSString.class] ? bodyValue : [bodyValue description];
            NSString *title = [titleValue isKindOfClass:NSString.class] ? titleValue : @"AutoSDK";
            if (body.length == 0) body = @"";
            NSString *bundleExtension = NSBundle.mainBundle.bundlePath.pathExtension.lowercaseString;
            if (![bundleExtension isEqualToString:@"app"] && ![bundleExtension isEqualToString:@"appex"]) return @YES;
            dispatch_async(dispatch_get_main_queue(), ^{
                @try {
                    UNUserNotificationCenter *center = UNUserNotificationCenter.currentNotificationCenter;
                    [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
                        UNMutableNotificationContent *content = [UNMutableNotificationContent new];
                        content.title = title;
                        content.body = body;
                        content.sound = UNNotificationSound.defaultSound;
                        UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:[NSUUID UUID].UUIDString
                                                                                              content:content
                                                                                              trigger:nil];
                        if (settings.authorizationStatus == UNAuthorizationStatusAuthorized ||
                            settings.authorizationStatus == UNAuthorizationStatusProvisional) {
                            [center addNotificationRequest:request withCompletionHandler:nil];
                        } else if (settings.authorizationStatus == UNAuthorizationStatusNotDetermined) {
                            [center requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound)
                                                  completionHandler:^(BOOL granted, NSError *requestError) {
                                (void)requestError;
                                if (granted) [center addNotificationRequest:request withCompletionHandler:nil];
                            }];
                        }
                    }];
                } @catch (NSException *exception) {
                    (void)exception;
                }
            });
            return @YES;
        }
        if ([name isEqualToString:@"toPinYin"]) {
            NSArray *pinyinArgs = [nativePayload[@"arguments"] isKindOfClass:NSArray.class] ? nativePayload[@"arguments"] : @[];
            NSString *pinyinText = pinyinArgs.count > 0 && [pinyinArgs[0] isKindOfClass:NSString.class] ? pinyinArgs[0] : @"";
            return AutoScriptToPinYin(pinyinText);
        }

        if ([name isEqualToString:@"locGet"]) {
            if (!AutoPermission(self.config, @"allowSystemControl", YES)) {
                return [self failure:AutoMakeError(AutoSDKErrorInvalidConfiguration,
                                                    @"Location access is disabled by configuration.", nil)];
            }
            NSArray *locArgs = [nativePayload[@"arguments"] isKindOfClass:NSArray.class] ? nativePayload[@"arguments"] : @[];
            double timeoutMs = locArgs.count > 0 && [locArgs[0] isKindOfClass:NSNumber.class] ? [locArgs[0] doubleValue] : 5000.0;
            if (!isfinite(timeoutMs) || timeoutMs < 500 || timeoutMs > 30000) timeoutMs = 5000.0;
            NSError *locationError = nil;
            NSDictionary *location = AutoGetLocationSnapshot(timeoutMs, ^BOOL { return [self invokeIsStopped]; }, nil,
                [NSBundle.mainBundle objectForInfoDictionaryKey:@"NSLocationWhenInUseUsageDescription"] != nil, &locationError);
            if (locationError) return [self failure:locationError];
            return location ?: [NSNull null];
        }
        if ([name isEqualToString:@"sqO"] || [name isEqualToString:@"sqE"] ||
            [name isEqualToString:@"sqQ"] || [name isEqualToString:@"sqC"]) {
            NSArray *sqliteArgs = [nativePayload[@"arguments"] isKindOfClass:NSArray.class] ? nativePayload[@"arguments"] : @[];
            id sqliteResult = AutoSQLiteOperation(name, sqliteArgs, self.config ?: @{});
            return [sqliteResult isKindOfClass:NSError.class] ? [self failure:sqliteResult] : sqliteResult;
        }
        if ([name isEqualToString:@"yoloD"]) {
            NSArray *yoloArgs = [nativePayload[@"arguments"] isKindOfClass:NSArray.class] ? nativePayload[@"arguments"] : @[];
            NSString *pathValue = yoloArgs.count > 0 && [yoloArgs[0] isKindOfClass:NSString.class] ? yoloArgs[0] : @"";
            if (pathValue.length == 0) {
                return [self failure:AutoMakeError(AutoSDKErrorInvalidConfiguration, @"yolo.detect requires an image file path.", nil)];
            }
            NSError *resolveError = nil;
            id resolved = AutoScriptFileOperation(@{ @"operation": @"resolvePath", @"path": pathValue }, self.config ?: @{}, &resolveError);
            if (resolveError) return [self failure:resolveError];
            NSString *resolvedPath = [resolved isKindOfClass:NSString.class] ? resolved : pathValue;
            NSData *imageData = [NSData dataWithContentsOfFile:resolvedPath];
            if (!imageData) {
                return [self failure:AutoMakeError(AutoSDKErrorAutomationFailed, @"yolo.detect cannot read the image file.", nil)];
            }
            UIImage *image = [UIImage imageWithData:imageData];
            if (!image) {
                return [self failure:AutoMakeError(AutoSDKErrorAutomationFailed, @"yolo.detect cannot decode the image file.", nil)];
            }
            NSError *detectError = nil;
            NSArray *detected = AutoDetectObjects(image, &detectError);
            return detectError ? [self failure:detectError] : (detected ?: @[]);
        }
        if ([name hasPrefix:@"screenDraw"] || [name hasPrefix:@"floatBall"] || [name hasPrefix:@"floatLog"]) {
            NSArray *overlayArgs = [nativePayload[@"arguments"] isKindOfClass:NSArray.class] ? nativePayload[@"arguments"] : @[];
            return [self handleOverlayOperation:name arguments:overlayArgs];
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

- (id)handleWebViewOperation:(NSString *)name arguments:(NSArray *)args {
    __block id result = nil;
    __block NSError *blockError = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([name isEqualToString:@"webViewTakeMessage"]) {
            NSString *token = args.count > 0 && [args[0] isKindOfClass:NSString.class] ? args[0] : @"";
            id message = nil;
            @synchronized (self.engine) {
                NSMutableArray *queue = self.engine.webViewMessages[token];
                if (queue.count > 0) {
                    message = queue.firstObject;
                    [queue removeObjectAtIndex:0];
                }
            }
            result = message ?: [NSNull null];
            dispatch_semaphore_signal(semaphore);
            return;
        }
        if ([name isEqualToString:@"webViewEval"]) {
            NSString *token = args.count > 0 && [args[0] isKindOfClass:NSString.class] ? args[0] : @"";
            NSString *js = args.count > 1 && [args[1] isKindOfClass:NSString.class] ? args[1] : @"";
            WKWebView *webView = nil;
            @synchronized (self.engine) { webView = self.engine.webViews[token]; }
            if (!webView) {
                blockError = AutoMakeError(AutoSDKErrorAutomationFailed, @"webView.eval requires a valid webView token.", nil);
                dispatch_semaphore_signal(semaphore);
                return;
            }
            [webView evaluateJavaScript:js completionHandler:^(id value, NSError *evalError) {
                result = value ?: [NSNull null];
                blockError = evalError;
                dispatch_semaphore_signal(semaphore);
            }];
            return;
        }
        result = [self performWebViewOperationOnMain:name arguments:args];
        if ([result isKindOfClass:NSError.class]) {
            blockError = result;
            result = nil;
        }
        dispatch_semaphore_signal(semaphore);
    });
    NSTimeInterval deadline = NSProcessInfo.processInfo.systemUptime + 15.0;
    while (dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC))) != 0) {
        if ([self.engine shouldStop]) {
            return [self failure:AutoMakeError(AutoSDKErrorScriptCancelled, @"Script cancelled.", nil)];
        }
        if (NSProcessInfo.processInfo.systemUptime >= deadline) {
            return [self failure:AutoMakeError(AutoSDKErrorAutomationFailed, @"Timed out waiting for the web view operation.", nil)];
        }
    }
    if (blockError) return [self failure:blockError];
    return result;
}

- (id)performWebViewOperationOnMain:(NSString *)name arguments:(NSArray *)args {
    if ([name isEqualToString:@"webViewInit"]) {
        NSString *urlString = args.count > 0 && [args[0] isKindOfClass:NSString.class] ? args[0] : @"about:blank";
        WKWebViewConfiguration *configuration = [WKWebViewConfiguration new];
        WKUserContentController *controller = [WKUserContentController new];
        configuration.userContentController = controller;
        WKWebView *created = [[WKWebView alloc] initWithFrame:CGRectZero configuration:configuration];
        created.backgroundColor = UIColor.whiteColor;
        created.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        NSString *token = nil;
        @synchronized (self.engine) {
            if (!self.engine.webViews) self.engine.webViews = [NSMutableDictionary dictionary];
            self.engine.webViewSequence += 1;
            token = [NSString stringWithFormat:@"webview-%lu", (unsigned long)self.engine.webViewSequence];
            self.engine.webViews[token] = created;
        }
        AutoWebMessageHandler *messageHandler = [[AutoWebMessageHandler alloc] init];
        __weak typeof(self) weakSelf = self;
        NSString *capturedToken = [token copy];
        messageHandler.onMessage = ^(WKScriptMessage *message) {
            AutoEngine *engine = weakSelf.engine;
            if (!engine) return;
            id body = message.body ?: [NSNull null];
            @synchronized (engine) {
                if (!engine.webViewMessages) engine.webViewMessages = [NSMutableDictionary dictionary];
                NSMutableArray *queue = engine.webViewMessages[capturedToken];
                if (!queue) {
                    queue = [NSMutableArray array];
                    engine.webViewMessages[capturedToken] = queue;
                }
                [queue addObject:body];
            }
        };
        [controller addScriptMessageHandler:messageHandler name:@"autosdk"];
        @synchronized (self.engine) {
            if (!self.engine.webViewMessageHandlers) self.engine.webViewMessageHandlers = [NSMutableDictionary dictionary];
            self.engine.webViewMessageHandlers[token] = messageHandler;
        }
        NSURL *url = [NSURL URLWithString:urlString];
        if (url) {
            [created loadRequest:[NSURLRequest requestWithURL:url]];
        }
        return token;
    }
    NSString *token = args.count > 0 && [args[0] isKindOfClass:NSString.class] ? args[0] : @"";
    WKWebView *webView = nil;
    @synchronized (self.engine) { webView = self.engine.webViews[token]; }
    if (!webView) {
        return AutoMakeError(AutoSDKErrorAutomationFailed, @"webView operation requires a valid token from webView.init.", nil);
    }
    if ([name isEqualToString:@"webViewShow"]) {
        UIWindow *window = AutoEngineMainWindow();
        if (!window) {
            return AutoMakeError(AutoSDKErrorAutomationUnavailable, @"No active window is available to show the web view.", nil);
        }
        UIView *container = window.rootViewController.view ?: window;
        CGFloat x = args.count > 1 && [args[1] isKindOfClass:NSNumber.class] ? [args[1] doubleValue] : 0;
        CGFloat y = args.count > 2 && [args[2] isKindOfClass:NSNumber.class] ? [args[2] doubleValue] : 100;
        CGFloat width = args.count > 3 && [args[3] isKindOfClass:NSNumber.class] && [args[3] doubleValue] > 0
            ? [args[3] doubleValue] : CGRectGetWidth(window.bounds);
        CGFloat height = args.count > 4 && [args[4] isKindOfClass:NSNumber.class] && [args[4] doubleValue] > 0
            ? [args[4] doubleValue] : MAX(0, CGRectGetHeight(window.bounds) - y);
        webView.frame = CGRectMake(x, y, width, height);
        if (webView.superview != container) {
            [container addSubview:webView];
        }
        return @YES;
    }
    if ([name isEqualToString:@"webViewHidden"]) {
        [webView removeFromSuperview];
        return @YES;
    }
    if ([name isEqualToString:@"webViewLoadHTML"]) {
        NSString *html = args.count > 1 && [args[1] isKindOfClass:NSString.class] ? args[1] : @"";
        [webView loadHTMLString:html baseURL:nil];
        return @YES;
    }
    if ([name isEqualToString:@"webViewRelease"]) {
        [webView removeFromSuperview];
        [webView.configuration.userContentController removeScriptMessageHandlerForName:@"autosdk"];
        @synchronized (self.engine) {
            [self.engine.webViews removeObjectForKey:token];
            [self.engine.webViewMessageHandlers removeObjectForKey:token];
            [self.engine.webViewMessages removeObjectForKey:token];
        }
        return @YES;
    }
    return AutoMakeError(AutoSDKErrorAutomationFailed, @"Unknown web view operation.", nil);
}

- (UIWindow *)ensureOverlayWindow {
    UIWindow *window = self.engine.overlayWindow;
    if (!window) {
        window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
        if (@available(iOS 13.0, *)) {
            UIWindow *mainWindow = AutoEngineMainWindow();
            if (mainWindow.windowScene) window.windowScene = mainWindow.windowScene;
        }
        window.windowLevel = UIWindowLevelStatusBar + 50.0;
        window.backgroundColor = UIColor.clearColor;
        window.rootViewController = [[AutoOverlayRootViewController alloc] init];
        window.hidden = NO;
        self.engine.overlayWindow = window;
    } else if (@available(iOS 13.0, *)) {
        UIWindow *mainWindow = AutoEngineMainWindow();
        if (mainWindow.windowScene && window.windowScene != mainWindow.windowScene) {
            window.windowScene = mainWindow.windowScene;
        }
    }
    return window;
}

- (void)refreshOverlayVisibility {
    BOOL anyVisible = NO;
    for (UIView *draw in self.engine.screenDraws.allValues) {
        if (draw.superview != nil) { anyVisible = YES; break; }
    }
    if (!anyVisible && self.engine.floatBallView.superview != nil) anyVisible = YES;
    if (!anyVisible && self.engine.floatLogView != nil && self.engine.floatLogView.superview != nil) anyVisible = YES;
    self.engine.overlayWindow.hidden = !anyVisible;
}

- (id)handleOverlayOperation:(NSString *)name arguments:(NSArray *)args {
    __block id result = nil;
    __block NSError *blockError = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_main_queue(), ^{
        result = [self performOverlayOperationOnMain:name arguments:args];
        if ([result isKindOfClass:NSError.class]) {
            blockError = result;
            result = nil;
        }
        dispatch_semaphore_signal(semaphore);
    });
    NSTimeInterval deadline = NSProcessInfo.processInfo.systemUptime + 10.0;
    while (dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC))) != 0) {
        if ([self.engine shouldStop]) {
            return [self failure:AutoMakeError(AutoSDKErrorScriptCancelled, @"Script cancelled.", nil)];
        }
        if (NSProcessInfo.processInfo.systemUptime >= deadline) {
            return [self failure:AutoMakeError(AutoSDKErrorAutomationFailed, @"Timed out waiting for the overlay operation.", nil)];
        }
    }
    if (blockError) return [self failure:blockError];
    return result;
}

- (id)performOverlayOperationOnMain:(NSString *)name arguments:(NSArray *)args {
    if ([name isEqualToString:@"screenDrawInit"]) {
        AutoScreenDrawView *view = [[AutoScreenDrawView alloc] initWithFrame:CGRectZero];
        @synchronized (self.engine) {
            if (!self.engine.screenDraws) self.engine.screenDraws = [NSMutableDictionary dictionary];
            self.engine.screenDrawSequence += 1;
            NSString *token = [NSString stringWithFormat:@"draw-%lu", (unsigned long)self.engine.screenDrawSequence];
            self.engine.screenDraws[token] = view;
            return token;
        }
    }
    NSString *token = args.count > 0 && [args[0] isKindOfClass:NSString.class] ? args[0] : @"";
    AutoScreenDrawView *drawView = nil;
    @synchronized (self.engine) { drawView = self.engine.screenDraws[token]; }
    if ([name isEqualToString:@"screenDrawSetBorderWidth"]) {
        if (!drawView) return AutoMakeError(AutoSDKErrorAutomationFailed, @"screenDraw operation requires a valid token from screenDraw.init.", nil);
        double width = args.count > 1 && [args[1] isKindOfClass:NSNumber.class] ? [args[1] doubleValue] : 0;
        drawView.layer.borderWidth = MAX(0, width);
        return @YES;
    }
    if ([name isEqualToString:@"screenDrawSetBorderColor"]) {
        if (!drawView) return AutoMakeError(AutoSDKErrorAutomationFailed, @"screenDraw operation requires a valid token from screenDraw.init.", nil);
        NSString *hex = args.count > 1 && [args[1] isKindOfClass:NSString.class] ? args[1] : @"";
        UIColor *color = AutoOverlayColorFromHex(hex);
        if (!color) return AutoMakeError(AutoSDKErrorInvalidConfiguration, @"screenDraw.setBorderColor expects a hex color like '#FF0000'.", nil);
        drawView.layer.borderColor = color.CGColor;
        return @YES;
    }
    if ([name isEqualToString:@"screenDrawSetTitle"]) {
        if (!drawView) return AutoMakeError(AutoSDKErrorAutomationFailed, @"screenDraw operation requires a valid token from screenDraw.init.", nil);
        NSString *title = args.count > 1 && [args[1] isKindOfClass:NSString.class] ? args[1] : @"";
        [drawView setDrawTitle:title];
        return @YES;
    }
    if ([name isEqualToString:@"screenDrawShow"]) {
        if (!drawView) return AutoMakeError(AutoSDKErrorAutomationFailed, @"screenDraw operation requires a valid token from screenDraw.init.", nil);
        UIWindow *window = [self ensureOverlayWindow];
        UIView *container = window.rootViewController.view;
        CGFloat x = args.count > 1 && [args[1] isKindOfClass:NSNumber.class] ? [args[1] doubleValue] : 0;
        CGFloat y = args.count > 2 && [args[2] isKindOfClass:NSNumber.class] ? [args[2] doubleValue] : 0;
        CGFloat width = args.count > 3 && [args[3] isKindOfClass:NSNumber.class] && [args[3] doubleValue] > 0
            ? [args[3] doubleValue] : 100;
        CGFloat height = args.count > 4 && [args[4] isKindOfClass:NSNumber.class] && [args[4] doubleValue] > 0
            ? [args[4] doubleValue] : 100;
        drawView.frame = CGRectMake(x, y, width, height);
        if (drawView.superview != container) [container addSubview:drawView];
        [self refreshOverlayVisibility];
        return @YES;
    }
    if ([name isEqualToString:@"screenDrawMove"]) {
        if (!drawView) return AutoMakeError(AutoSDKErrorAutomationFailed, @"screenDraw operation requires a valid token from screenDraw.init.", nil);
        CGFloat x = args.count > 1 && [args[1] isKindOfClass:NSNumber.class] ? [args[1] doubleValue] : 0;
        CGFloat y = args.count > 2 && [args[2] isKindOfClass:NSNumber.class] ? [args[2] doubleValue] : 0;
        CGRect frame = drawView.frame;
        frame.origin.x = x;
        frame.origin.y = y;
        drawView.frame = frame;
        return @YES;
    }
    if ([name isEqualToString:@"screenDrawHide"]) {
        if (!drawView) return AutoMakeError(AutoSDKErrorAutomationFailed, @"screenDraw operation requires a valid token from screenDraw.init.", nil);
        [drawView removeFromSuperview];
        [self refreshOverlayVisibility];
        return @YES;
    }
    if ([name isEqualToString:@"screenDrawRelease"]) {
        if (!drawView) return AutoMakeError(AutoSDKErrorAutomationFailed, @"screenDraw operation requires a valid token from screenDraw.init.", nil);
        [drawView removeFromSuperview];
        @synchronized (self.engine) { [self.engine.screenDraws removeObjectForKey:token]; }
        [self refreshOverlayVisibility];
        return @YES;
    }
    if ([name isEqualToString:@"screenDrawClearAll"]) {
        for (AutoScreenDrawView *draw in self.engine.screenDraws.allValues) [draw removeFromSuperview];
        @synchronized (self.engine) { [self.engine.screenDraws removeAllObjects]; }
        [self refreshOverlayVisibility];
        return @YES;
    }
    if ([name isEqualToString:@"floatBallShow"]) {
        NSString *title = args.count > 0 && [args[0] isKindOfClass:NSString.class] ? args[0] : @"";
        CGFloat x = args.count > 1 && [args[1] isKindOfClass:NSNumber.class] ? [args[1] doubleValue] : 20;
        CGFloat y = args.count > 2 && [args[2] isKindOfClass:NSNumber.class] ? [args[2] doubleValue] : 120;
        UIView *ball = self.engine.floatBallView;
        if (!ball) {
            ball = [[UIView alloc] initWithFrame:CGRectMake(x, y, 56, 56)];
            ball.backgroundColor = [UIColor colorWithRed:0.16 green:0.50 blue:0.96 alpha:0.92];
            ball.layer.cornerRadius = 28;
            ball.layer.shadowColor = UIColor.blackColor.CGColor;
            ball.layer.shadowOpacity = 0.35;
            ball.layer.shadowOffset = CGSizeMake(0, 2);
            ball.layer.shadowRadius = 4;
            ball.userInteractionEnabled = YES;
            UILabel *label = [[UILabel alloc] initWithFrame:CGRectInset(ball.bounds, 4, 4)];
            label.font = [UIFont boldSystemFontOfSize:11];
            label.textColor = UIColor.whiteColor;
            label.textAlignment = NSTextAlignmentCenter;
            label.numberOfLines = 2;
            label.adjustsFontSizeToFitWidth = YES;
            label.minimumScaleFactor = 0.6;
            [ball addSubview:label];
            UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleFloatBallPan:)];
            [ball addGestureRecognizer:pan];
            UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleFloatBallTap:)];
            [ball addGestureRecognizer:tap];
            self.engine.floatBallView = ball;
            self.engine.floatBallTitleLabel = label;
        }
        ball.frame = CGRectMake(x, y, 56, 56);
        self.engine.floatBallTitleLabel.text = title;
        UIWindow *window = [self ensureOverlayWindow];
        UIView *container = window.rootViewController.view;
        if (ball.superview != container) [container addSubview:ball];
        [self refreshOverlayVisibility];
        return @YES;
    }
    if ([name isEqualToString:@"floatBallMove"]) {
        CGFloat x = args.count > 0 && [args[0] isKindOfClass:NSNumber.class] ? [args[0] doubleValue] : 0;
        CGFloat y = args.count > 1 && [args[1] isKindOfClass:NSNumber.class] ? [args[1] doubleValue] : 0;
        UIView *ball = self.engine.floatBallView;
        if (!ball) return @NO;
        CGRect frame = ball.frame;
        frame.origin.x = x;
        frame.origin.y = y;
        ball.frame = frame;
        return @YES;
    }
    if ([name isEqualToString:@"floatBallHide"]) {
        [self.engine.floatBallView removeFromSuperview];
        [self refreshOverlayVisibility];
        return @YES;
    }
    if ([name isEqualToString:@"floatBallIsShow"]) {
        UIView *ball = self.engine.floatBallView;
        return @(ball != nil && ball.superview != nil);
    }
    if ([name hasPrefix:@"floatLog"]) {
        UIView *panel = self.engine.floatLogView;
        UITextView *textView = self.engine.floatLogTextView;
        if (!panel) {
            panel = [[UIView alloc] initWithFrame:CGRectMake(80, 120, 260, 180)];
            panel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.78];
            panel.layer.cornerRadius = 10;
            panel.layer.borderWidth = 1;
            panel.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.35].CGColor;
            textView = [[UITextView alloc] initWithFrame:CGRectInset(panel.bounds, 4, 4)];
            textView.editable = NO;
            textView.selectable = YES;
            textView.backgroundColor = UIColor.clearColor;
            textView.textColor = UIColor.whiteColor;
            textView.font = [UIFont systemFontOfSize:12];
            textView.textContainerInset = UIEdgeInsetsMake(4, 4, 4, 4);
            [panel addSubview:textView];
            UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleFloatLogPan:)];
            [panel addGestureRecognizer:pan];
            self.engine.floatLogView = panel;
            self.engine.floatLogTextView = textView;
            self.engine.floatLogLines = [NSMutableArray array];
        }
        if ([name isEqualToString:@"floatLogShow"]) {
            CGFloat x = args.count > 0 && [args[0] isKindOfClass:NSNumber.class] ? [args[0] doubleValue] : 80;
            CGFloat y = args.count > 1 && [args[1] isKindOfClass:NSNumber.class] ? [args[1] doubleValue] : 120;
            CGFloat width = args.count > 2 && [args[2] isKindOfClass:NSNumber.class] && [args[2] doubleValue] > 0 ? [args[2] doubleValue] : 260;
            CGFloat height = args.count > 3 && [args[3] isKindOfClass:NSNumber.class] && [args[3] doubleValue] > 0 ? [args[3] doubleValue] : 180;
            panel.frame = CGRectMake(x, y, width, height);
            textView.frame = CGRectInset(panel.bounds, 4, 4);
            UIWindow *window = [self ensureOverlayWindow];
            UIView *container = window.rootViewController.view;
            if (panel.superview != container) [container addSubview:panel];
            [self refreshOverlayVisibility];
            return @YES;
        }
        if ([name isEqualToString:@"floatLogLog"]) {
            NSString *text = args.count > 0 && [args[0] isKindOfClass:NSString.class] ? args[0] : @"";
            if (text.length == 0) return @YES;
            NSArray<NSString *> *pieces = [text componentsSeparatedByString:@"\n"];
            for (NSString *piece in pieces) {
                if (piece.length > 0) [self.engine.floatLogLines addObject:piece];
            }
            while (self.engine.floatLogLines.count > 200) [self.engine.floatLogLines removeObjectAtIndex:0];
            textView.text = [self.engine.floatLogLines componentsJoinedByString:@"\n"];
            [textView scrollRangeToVisible:NSMakeRange(textView.text.length, 0)];
            return @YES;
        }
        if ([name isEqualToString:@"floatLogClear"]) {
            [self.engine.floatLogLines removeAllObjects];
            textView.text = @"";
            return @YES;
        }
        if ([name isEqualToString:@"floatLogHide"]) {
            [panel removeFromSuperview];
            [self refreshOverlayVisibility];
            return @YES;
        }
        if ([name isEqualToString:@"floatLogIsShow"]) {
            return @(panel != nil && panel.superview != nil);
        }
        if ([name isEqualToString:@"floatLogDestroy"]) {
            [panel removeFromSuperview];
            self.engine.floatLogView = nil;
            self.engine.floatLogTextView = nil;
            self.engine.floatLogLines = nil;
            [self refreshOverlayVisibility];
            return @YES;
        }
        return AutoMakeError(AutoSDKErrorAutomationFailed, @"Unknown floatLog operation.", nil);
    }
    return AutoMakeError(AutoSDKErrorAutomationFailed, @"Unknown overlay operation.", nil);
}

- (void)handleFloatBallPan:(UIPanGestureRecognizer *)gesture {
    UIView *ball = gesture.view;
    if (!ball.superview) return;
    CGPoint translation = [gesture translationInView:ball.superview];
    CGPoint center = CGPointMake(ball.center.x + translation.x, ball.center.y + translation.y);
    CGRect bounds = ball.superview.bounds;
    center.x = MAX(ball.bounds.size.width / 2.0, MIN(bounds.size.width - ball.bounds.size.width / 2.0, center.x));
    center.y = MAX(ball.bounds.size.height / 2.0, MIN(bounds.size.height - ball.bounds.size.height / 2.0, center.y));
    ball.center = center;
    [gesture setTranslation:CGPointZero inView:ball.superview];
}

- (void)handleFloatBallTap:(UITapGestureRecognizer *)gesture {
    NSString *title = self.engine.floatBallTitleLabel.text;
    if (title.length > 0) AutoShowToast(title);
}

- (void)handleFloatLogPan:(UIPanGestureRecognizer *)gesture {
    UIView *panel = gesture.view;
    if (!panel.superview) return;
    CGPoint translation = [gesture translationInView:panel.superview];
    CGRect frame = panel.frame;
    frame.origin.x = MAX(0, MIN(panel.superview.bounds.size.width - frame.size.width, frame.origin.x + translation.x));
    frame.origin.y = MAX(0, MIN(panel.superview.bounds.size.height - frame.size.height, frame.origin.y + translation.y));
    panel.frame = frame;
    [gesture setTranslation:CGPointZero inView:panel.superview];
}

- (id)invokeExecAsync:(JSValue *)payload {
    if (![self ensureScriptRunning]) return @NO;
    NSDictionary *data = AutoPayload(payload);
    NSString *source = [data[@"source"] isKindOfClass:NSString.class] ? data[@"source"] : @"";
    if (source.length == 0 || source.length > 1024 * 1024) {
        return [self failure:AutoMakeError(AutoSDKErrorInvalidConfiguration, @"execAsync requires a function body of 1 to 1 MiB.", nil)];
    }
    NSArray *rawArguments = [data[@"arguments"] isKindOfClass:NSArray.class] ? data[@"arguments"] : @[];
    if (rawArguments.count > 32) {
        return [self failure:AutoMakeError(AutoSDKErrorInvalidConfiguration, @"execAsync accepts at most 32 arguments.", nil)];
    }
    BOOL sync = AutoBoolean(data[@"sync"], NO);
    NSData *argumentsJSON = [NSJSONSerialization dataWithJSONObject:rawArguments options:0 error:nil];
    if (!argumentsJSON) {
        return [self failure:AutoMakeError(AutoSDKErrorInvalidConfiguration, @"execAsync arguments must be JSON-serializable.", nil)];
    }
    NSString *argumentsExpression = [[NSString alloc] initWithData:argumentsJSON encoding:NSUTF8StringEncoding];
    NSUInteger activeCount = 0;
    @synchronized (self.engine) {
        for (AutoAsyncThread *candidate in self.engine.asyncThreads) {
            if (!candidate.finished) activeCount += 1;
        }
    }
    if (activeCount >= 8) {
        return [self failure:AutoMakeError(AutoSDKErrorAutomationFailed, @"Too many concurrent execAsync threads (limit 8).", nil)];
    }
    AutoAsyncThread *thread = [AutoAsyncThread new];
    AutoJSBridge *threadBridge = [AutoJSBridge new];
    threadBridge.engine = self.engine;
    threadBridge.config = self.config ?: @{};
    NSDictionary *capabilities = [self.adapter respondsToSelector:@selector(capabilities)] ? [self.adapter capabilities] : nil;
    threadBridge.adapter = AutoBoolean(capabilities[@"requiresMainThread"], NO)
        ? (id<AutoAutomationAdapter>)[AutoMainThreadAdapterProxy proxyWithTarget:self.adapter]
        : self.adapter;
    thread.bridge = threadBridge;
    thread.queue = dispatch_queue_create("autosdk.exec", DISPATCH_QUEUE_SERIAL);
    @synchronized (self.engine) { [self.engine.asyncThreads addObject:thread]; }
    uint64_t threadId = (uint64_t)(uintptr_t)thread;
    AutoJSConsole *threadConsole = [AutoJSConsole new];
    threadConsole.emitToSystemLog = AutoBoolean(self.config[@"debugLogging"], NO);
    NSUInteger maximumLogEntries = AutoBoundedPositiveInteger(self.config[@"maxLogEntries"], 0, 10000);
    if (maximumLogEntries > 0) threadConsole.maximumEntries = MIN(maximumLogEntries, (NSUInteger)10000);
    NSUInteger maximumLogMessageLength = AutoBoundedPositiveInteger(self.config[@"maxLogMessageLength"], 0, 256 * 1024);
    if (maximumLogMessageLength > 0) threadConsole.maximumMessageLength = MIN(maximumLogMessageLength, (NSUInteger)(256 * 1024));
    threadConsole.maximumTotalBytes = AutoConfiguredByteLimit(self.config, @"maxLogBytes", 8 * 1024 * 1024, 32 * 1024 * 1024);
    AutoEngine *engine = self.engine;
    dispatch_async(thread.queue, ^{
        @autoreleasepool {
            JSContext *context = [JSContext new];
            thread.context = context;
            context.exceptionHandler = ^(JSContext *ctx, JSValue *exception) {
                ctx.exception = exception;
            };
            context[@"__bridge"] = threadBridge;
            context[@"__console"] = threadConsole;
            JSValue *drainTimers = [context evaluateScript:AutoBootstrapScript()];
            JSValue *value = nil;
            if (!context.exception && !thread.cancelled && ![engine shouldStop]) {
                NSString *call = [NSString stringWithFormat:
                    @"(function(){var fn=%@;if(typeof fn!=='function')throw new Error('execAsync argument must be a function');return fn.apply(null,%@);})()",
                    source, argumentsExpression];
                value = [context evaluateScript:call];
                if (!context.exception && !thread.cancelled && ![engine shouldStop]) {
                    [drainTimers callWithArguments:@[]];
                }
            }
            if (context.exception) {
                thread.error = AutoMakeError(AutoSDKErrorJavaScriptException,
                                             [[context.exception toString] ?: @"Async thread exception." description], nil);
            } else if (thread.cancelled || [engine shouldStop]) {
                thread.error = AutoMakeError(AutoSDKErrorScriptCancelled, @"Async thread cancelled.", nil);
            } else if (threadBridge.lastError) {
                thread.error = threadBridge.lastError;
            } else {
                thread.result = AutoBoundedJSResult(value);
            }
            thread.finished = YES;
            thread.context = nil;
        }
    });
    if (sync) {
        while (!thread.finished && ![self.engine shouldStop] && !self.threadCancelled) {
            AutoPumpRunLoopWithSleepFallback(0.02);
        }
        if (thread.error) return [self failure:thread.error];
        return thread.result ?: [NSNull null];
    }
    return @{ @"threadId": @(threadId) };
}

- (id)invokeExecOp:(JSValue *)payload {
    if (![self ensureScriptRunning]) return @NO;
    NSDictionary *data = AutoPayload(payload);
    NSString *operation = [data[@"operation"] isKindOfClass:NSString.class] ? data[@"operation"] : @"";
    if ([operation isEqualToString:@"stopAll"]) {
        @synchronized (self.engine) {
            for (AutoAsyncThread *candidate in self.engine.asyncThreads) {
                candidate.cancelled = YES;
                candidate.bridge.threadCancelled = YES;
            }
        }
        return @YES;
    }
    uint64_t rawId = (uint64_t)AutoFiniteDouble(data[@"threadId"], 0);
    if (rawId == 0) {
        return [self failure:AutoMakeError(AutoSDKErrorInvalidConfiguration, @"exec thread id is required.", nil)];
    }
    AutoAsyncThread *thread = nil;
    @synchronized (self.engine) {
        for (AutoAsyncThread *candidate in self.engine.asyncThreads) {
            if ((uint64_t)(uintptr_t)candidate == rawId) { thread = candidate; break; }
        }
    }
    if (!thread) {
        return [self failure:AutoMakeError(AutoSDKErrorAutomationFailed, @"exec thread is no longer active.", nil)];
    }
    if ([operation isEqualToString:@"isFinished"]) return @(thread.finished);
    if ([operation isEqualToString:@"cancel"]) {
        thread.cancelled = YES;
        thread.bridge.threadCancelled = YES;
        return @YES;
    }
    if ([operation isEqualToString:@"result"]) {
        if (!thread.finished) return [NSNull null];
        if (thread.error) return [self failure:thread.error];
        return thread.result ?: [NSNull null];
    }
    if ([operation isEqualToString:@"join"]) {
        while (!thread.finished && ![self.engine shouldStop] && !self.threadCancelled) {
            AutoPumpRunLoopWithSleepFallback(0.02);
        }
        if (thread.error) return [self failure:thread.error];
        return thread.result ?: [NSNull null];
    }
    return [self failure:AutoMakeError(AutoSDKErrorInvalidConfiguration, @"Unknown exec thread operation.", nil)];
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
        _config = AutoUsesLowMemoryProfile(NSProcessInfo.processInfo.physicalMemory)
            ? @{ @"maxLogEntries": @250, @"maxLogMessageLength": @4096,
                 @"maxLogBytes": @(1024 * 1024), @"maxScriptBytes": @(1024 * 1024) } : @{};
        _nativeMethods = [NSMutableDictionary dictionary];
        _asyncThreads = [NSMutableArray array];
        _adapter = [AutoUnavailableAdapter new];
        _scriptQueue = dispatch_queue_create("com.autosdk.javascript", DISPATCH_QUEUE_SERIAL);
        _debugAdapterQueue = dispatch_queue_create("com.autosdk.debug-adapter", DISPATCH_QUEUE_SERIAL);
        _debugServerQueue = dispatch_queue_create("com.autosdk.debug-server-state", DISPATCH_QUEUE_SERIAL);
        dispatch_queue_set_specific(_debugServerQueue, AutoDebugServerQueueKey, AutoDebugServerQueueKey, NULL);
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(handleResourcePressure:)
            name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(handleResourcePressure:)
            name:NSProcessInfoThermalStateDidChangeNotification object:nil];
    }
    return self;
}

- (void)initWithConfig:(NSDictionary<NSString *,id> *)config __attribute__((objc_method_family(none))) {
    [self configureWithConfig:config];
}

- (void)requestStopForRun:(NSUUID *)identifier reason:(NSString *)reason {
    @synchronized (self) {
        if (!self.running || ![self.activeRunIdentifier isEqual:identifier]) return;
        self.stopReason = reason;
        self.stopRequested = YES;
        // No waiting for JS/SQL/network completion on the expiration callback.
        if ([self.activeAdapter respondsToSelector:@selector(cancelCurrentOperations)]) [self.activeAdapter cancelCurrentOperations];
        [self.scriptTask cancel];
    }
}

- (void)handleResourcePressure:(NSNotification *)notification {
    BOOL memory = [notification.name isEqualToString:UIApplicationDidReceiveMemoryWarningNotification];
    if (!memory && NSProcessInfo.processInfo.thermalState < NSProcessInfoThermalStateSerious) return;
    id<AutoAutomationAdapter> adapter;
    @synchronized (self) {
        [self requestStopForRun:self.activeRunIdentifier reason:memory
            ? @"Stopped because iOS reported low memory. Return to AutoSDK and reduce the workload before running again."
            : @"Stopped because the device is overheating. Let it cool before running again."];
        adapter = self.adapter;
        if (self.activeAdapter != adapter && [self.activeAdapter respondsToSelector:@selector(releaseCachedResources)]) {
            [self.activeAdapter releaseCachedResources];
        }
    }
    if ([adapter respondsToSelector:@selector(releaseCachedResources)]) [adapter releaseCachedResources];
}

- (void)configureWithConfig:(NSDictionary<NSString *,id> *)config {
    NSDictionary *configSnapshot = nil;
    @synchronized (self) {
        configSnapshot = AutoImmutableConfigSnapshot(config);
        if (AutoUsesLowMemoryProfile(NSProcessInfo.processInfo.physicalMemory)) {
            NSMutableDictionary *bounded = [configSnapshot mutableCopy];
            bounded[@"maxLogEntries"] = @(AutoBoundedPositiveInteger(bounded[@"maxLogEntries"], 250, 250));
            bounded[@"maxLogMessageLength"] = @(AutoBoundedPositiveInteger(bounded[@"maxLogMessageLength"], 4096, 4096));
            bounded[@"maxLogBytes"] = @(AutoConfiguredByteLimit(bounded, @"maxLogBytes", 1024 * 1024, 1024 * 1024));
            bounded[@"maxScriptBytes"] = @(AutoConfiguredByteLimit(bounded, @"maxScriptBytes", 1024 * 1024, 1024 * 1024));
            configSnapshot = [bounded copy];
        }
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
        NSString *serviceName = [config[@"debugServiceName"] isKindOfClass:NSString.class] ? config[@"debugServiceName"] : @"AutoSDK iPhone";
        NSDictionary *desiredConfiguration = @{ @"port": @(port), @"allowsWiFi": @(allowsWiFi), @"token": token, @"serviceName": serviceName };
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
        [server startWithPort:port token:token allowsWiFi:allowsWiFi serviceName:serviceName requestHandler:^(NSDictionary<NSString *,id> *request, AutoDebugResponseHandler response) {
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
                                      @"mediaLibraryWrite": @(AutoPermission(config, @"allowMediaLibrary", YES)),
                                      @"findColorEx": @YES,
                                      @"audioPlayback": @(AutoPermission(config, @"allowAudio", YES)),
                                      @"photoAuthorization": @(AutoPermission(config, @"allowMediaLibrary", YES)) } mutableCopy];
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
    AutoWebSocketCloseAll();
    AutoSQLiteCloseAll();
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
    if (NSProcessInfo.processInfo.thermalState >= NSProcessInfoThermalStateSerious) {
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil,
            AutoMakeError(AutoSDKErrorAutomationUnavailable, @"Device is overheating; wait for it to cool before running scripts.", nil)); });
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
        self.stopReason = nil;
        NSUUID *identifier = NSUUID.UUID;
        self.activeRunIdentifier = identifier;
        runConfig = self.config ?: @{};
        runAdapter = self.adapter ?: [AutoUnavailableAdapter new];
        self.activeAdapter = runAdapter;
        __weak AutoEngine *weakSelf = self;
        self.backgroundLease = [AutoBackgroundLease leaseWithExpiration:^{
            [weakSelf requestStopForRun:identifier reason:@"iOS background execution time expired. Return to AutoSDK and run again; actions are not replayed automatically."];
        }];
    }
    [self loadScript:scriptPathOrSource config:runConfig completion:^(NSString * _Nullable source, NSError * _Nullable error) {
        if ([self shouldStop]) {
            [self finishWithResult:nil error:AutoMakeError(AutoSDKErrorScriptCancelled, self.stopReason ?: @"Script cancelled.", nil) completion:completion];
            return;
        }
        if (error) { [self finishWithResult:nil error:error completion:completion]; return; }
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
    self.currentScriptSource = source ?: @"";
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
    @synchronized (self) { self.audioStopWhenScriptEnd = NO; }
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
                // A cancelled source may already have queued its handler. Do
                // not let a finished run's watchdog stop a subsequent script.
                if (executionFinished) return;
                timedOut = YES;
                [self requestStop];
                if ([scriptAdapter respondsToSelector:@selector(cancelCurrentOperations)]) {
                    [scriptAdapter cancelCurrentOperations];
                }
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
    else if ([self shouldStop]) error = AutoMakeError(AutoSDKErrorScriptCancelled, self.stopReason ?: @"Script cancelled.", nil);
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
    AutoBackgroundLease *lease;
    NSArray *asyncThreadsToStop = nil;
    @synchronized (self) {
        asyncThreadsToStop = [self.asyncThreads copy];
        [self.asyncThreads removeAllObjects];
    }
    for (AutoAsyncThread *asyncThread in asyncThreadsToStop) {
        asyncThread.cancelled = YES;
        asyncThread.bridge.threadCancelled = YES;
    }
    @synchronized (self) {
        lease = self.backgroundLease;
        self.backgroundLease = nil;
        self.activeRunIdentifier = nil;
        self.running = NO;
        self.stopRequested = NO;
        self.activeAdapter = nil;
        self.currentScriptSource = nil;
        if (self.audioStopWhenScriptEnd) {
            self.audioStopWhenScriptEnd = NO;
            [self stopAllAudioPlayback];
        }
        if (self.speechStopWhenScriptEnd) {
            self.speechStopWhenScriptEnd = NO;
            [self.speechSynthesizer stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
        }
    }
    [lease finish];
    [self cleanupOverlayUI];
    dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(result, error); });
}

- (void)cleanupOverlayUI {
    NSArray *draws = nil;
    @synchronized (self) { draws = [self.screenDraws.allValues copy]; }
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.floatBallView removeFromSuperview];
        [self.floatLogView removeFromSuperview];
        for (UIView *draw in draws) [draw removeFromSuperview];
        self.overlayWindow.hidden = YES;
    });
}

- (void)stopAllAudioPlayback {
    NSArray *players = nil;
    NSArray *playersById = nil;
    @synchronized (self) {
        players = [self.audioPlayers copy];
        [self.audioPlayers removeAllObjects];
        playersById = [self.audioPlayersById.allValues copy];
        [self.audioPlayersById removeAllObjects];
    }
    for (AVAudioPlayer *player in players) {
        if (player.isPlaying) [player stop];
    }
    for (AVAudioPlayer *player in playersById) {
        if (player.isPlaying) [player stop];
    }
}

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
    (void)flag;
    @synchronized (self) {
        if (self.audioPlayersById.count > 0) {
            NSNumber *matchedKey = nil;
            for (NSNumber *key in self.audioPlayersById) {
                if (self.audioPlayersById[key] == player) { matchedKey = key; break; }
            }
            if (matchedKey) [self.audioPlayersById removeObjectForKey:matchedKey];
        }
        if (self.audioPlayers.count == 0) return;
        AVAudioPlayer *current = self.audioPlayers.firstObject;
        if (current == player) {
            [self.audioPlayers removeObjectAtIndex:0];
        } else {
            [self.audioPlayers removeObject:player];
        }
        AVAudioPlayer *next = self.audioPlayers.firstObject;
        if (next && !next.isPlaying) [next play];
    }
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [_backgroundLease finish];
    [self stopAllAudioPlayback];
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
    NSLocale *activeLocale = NSLocale.currentLocale;
    NSString *preferredLanguage = NSLocale.preferredLanguages.firstObject ?: @"";
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
                                    @"appBuild": [bundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"",
                                    @"language": preferredLanguage,
                                    @"country": [activeLocale objectForKey:NSLocaleCountryCode] ?: @"",
                                    @"locale": activeLocale.localeIdentifier ?: @"",
                                    @"timezone": NSTimeZone.localTimeZone.name ?: @"",
                                    @"uptimeSeconds": @(NSProcessInfo.processInfo.systemUptime),
                                    @"networkType": AutoCurrentNetworkType() } mutableCopy];
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

@implementation AutoWebMessageHandler
- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    (void)userContentController;
    if (self.onMessage) self.onMessage(message);
}
@end
