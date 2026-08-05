#import "include/AutoWDAHTTPAdapter.h"
#import "include/AutoSDKError.h"
#import <UIKit/UIKit.h>
#import <Vision/Vision.h>
#include <math.h>
#include <stdlib.h>
#include <stdint.h>

static NSString * const AutoWDAProtocolErrorKey = @"AutoWDAProtocolError";
static NSString * const AutoWDAHTTPStatusKey = @"AutoWDAHTTPStatus";
static NSString * const AutoWDAOperationCancellationThreadKey = @"com.autosdk.wda.operation-cancellation-generation";
static const size_t AutoWDAMaxPixelBufferBytes = 64 * 1024 * 1024;
static const NSUInteger AutoWDAMaxHTTPRequestBytes = 4 * 1024 * 1024;
static const NSUInteger AutoWDADefaultHTTPResponseBytes = 16 * 1024 * 1024;
static const NSUInteger AutoWDAMaxHTTPResponseBytes = 40 * 1024 * 1024;
static const NSUInteger AutoWDAMaxScreenshotBytes = 24 * 1024 * 1024;
static const NSUInteger AutoWDADefaultSourceMaxBytes = 16 * 1024 * 1024;
static const NSUInteger AutoWDAMaxSourceBytes = 32 * 1024 * 1024;
static const NSUInteger AutoWDADefaultSourceMaxNodes = 50000;
static const NSUInteger AutoWDAMaxSourceNodes = 200000;
static const NSUInteger AutoWDAMaxSourceDepth = 1024;
static const NSUInteger AutoWDAMaxColorPoints = 4096;
static const NSUInteger AutoWDAMaxColorOffsets = 256;
static const NSUInteger AutoWDADefaultColorCandidates = 200000;
static const NSUInteger AutoWDAMaxColorCandidates = 5000000;
static const NSUInteger AutoWDADefaultColorComparisons = 50000000;
static const NSUInteger AutoWDAMaxColorComparisons = 500000000;
enum { AutoWDAMaxSelectorNestingDepth = 32 };
static const NSUInteger AutoWDAMaxSelectorTextLength = 8192;
static const NSUInteger AutoWDAMaxSelectorExpressionLength = 64 * 1024;
static const NSUInteger AutoWDAMaxSelectorRegexLength = 1024;
static const NSUInteger AutoWDAMaxElementHandleLength = 4096;
static const NSUInteger AutoWDAMaxInputTextBytes = 1024 * 1024;

static NSError *AutoWDAError(AutoSDKErrorCode code, NSString *message) {
    return [NSError errorWithDomain:AutoSDKErrorDomain
                                code:code
                            userInfo:@{ NSLocalizedDescriptionKey: message ?: @"WDA request failed." }];
}

static NSError *AutoWDAResponseError(NSInteger statusCode, NSString *protocolError, NSString *message) {
    NSMutableDictionary *userInfo = [@{ NSLocalizedDescriptionKey: message ?: @"WDA request failed." } mutableCopy];
    if (protocolError.length > 0) userInfo[AutoWDAProtocolErrorKey] = protocolError;
    if (statusCode > 0) userInfo[AutoWDAHTTPStatusKey] = @(statusCode);
    return [NSError errorWithDomain:AutoSDKErrorDomain code:AutoSDKErrorAutomationFailed userInfo:userInfo];
}

static BOOL AutoWDAErrorIsInvalidSession(NSError *error) {
    if (![error isKindOfClass:NSError.class]) return NO;
    NSString *protocolError = [error.userInfo[AutoWDAProtocolErrorKey] description].lowercaseString;
    NSString *message = error.localizedDescription.lowercaseString;
    return [protocolError isEqualToString:@"invalid session id"] ||
           [protocolError isEqualToString:@"invalid session"] ||
           [protocolError containsString:@"invalid session"] ||
           [message containsString:@"invalid session id"] ||
           [message containsString:@"invalid session"];
}

static BOOL AutoWDAErrorIsElementNotFound(NSError *error) {
    if (![error isKindOfClass:NSError.class]) return NO;
    NSString *protocolError = [error.userInfo[AutoWDAProtocolErrorKey] description].lowercaseString;
    NSString *message = error.localizedDescription.lowercaseString;
    return [protocolError isEqualToString:@"no such element"] ||
           [protocolError isEqualToString:@"stale element reference"] ||
           [protocolError containsString:@"element not found"] ||
           [message containsString:@"no such element"] ||
           [message containsString:@"unable to find an element"] ||
           [message containsString:@"stale element reference"];
}

static BOOL AutoWDAErrorIsStaleElement(NSError *error) {
    if (![error isKindOfClass:NSError.class]) return NO;
    NSString *protocolError = [error.userInfo[AutoWDAProtocolErrorKey] description].lowercaseString;
    NSString *message = error.localizedDescription.lowercaseString;
    return [protocolError isEqualToString:@"stale element reference"] ||
           [protocolError containsString:@"stale element"] ||
           [message containsString:@"stale element reference"];
}

static BOOL AutoWDAErrorIsUnsupportedCommand(NSError *error) {
    if (![error isKindOfClass:NSError.class]) return NO;
    NSString *protocolError = [error.userInfo[AutoWDAProtocolErrorKey] description].lowercaseString;
    NSString *message = error.localizedDescription.lowercaseString;
    NSInteger statusCode = [error.userInfo[AutoWDAHTTPStatusKey] integerValue];
    BOOL unsupportedStatus = statusCode == 405 || statusCode == 501 ||
                             (statusCode == 404 && !AutoWDAErrorIsInvalidSession(error));
    return unsupportedStatus ||
           [protocolError isEqualToString:@"unknown command"] ||
           [protocolError isEqualToString:@"unsupported operation"] ||
           [protocolError isEqualToString:@"not implemented"] ||
           [protocolError containsString:@"unsupported"] ||
           [message containsString:@"unknown command"] ||
           [message containsString:@"unknown setting"] ||
           [message containsString:@"unrecognized setting"] ||
           [message containsString:@"unsupported setting"] ||
           [message containsString:@"not implemented"];
}

static NSString *AutoWDAPredicateEscape(NSString *value) {
    return [[value stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"]
            stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
}

static NSString *AutoWDAPathSegment(NSString *value) {
    NSMutableCharacterSet *allowed = [NSCharacterSet.URLPathAllowedCharacterSet mutableCopy];
    [allowed removeCharactersInString:@"/?#"];
    return [value stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";
}

static NSString *AutoWDAElementType(NSString *value) {
    if (![value isKindOfClass:NSString.class] || value.length == 0) return value;
    return [value hasPrefix:@"XCUIElementType"] ? value : [@"XCUIElementType" stringByAppendingString:value];
}

static NSString *AutoWDAElementIdFromValue(id value) {
    if (![value isKindOfClass:NSDictionary.class]) return nil;
    NSDictionary *dictionary = value;
    if ([dictionary[@"sourceDerived"] isKindOfClass:NSNumber.class] && [dictionary[@"sourceDerived"] boolValue]) return nil;
    for (NSString *key in @[@"element-6066-11e4-a52e-4f735466cecf", @"ELEMENT", @"elementId", @"wdElementId", @"handle"]) {
        id candidate = dictionary[key];
        NSString *candidateString = [candidate isKindOfClass:NSString.class] ? (NSString *)candidate : nil;
        if (candidateString.length > 0 && candidateString.length <= AutoWDAMaxElementHandleLength) return candidateString;
    }
    return nil;
}

static BOOL AutoWDAIsNumber(id value);

static BOOL AutoWDAValidateUnwrappedSelector(id selector, NSError **error) {
    if ([selector isKindOfClass:NSString.class]) {
        if ([(NSString *)selector length] <= AutoWDAMaxSelectorTextLength) return YES;
        if (error) *error = AutoWDAError(AutoSDKErrorInvalidConfiguration,
                                         @"WDA string selectors are limited to 8192 characters.");
        return NO;
    }
    if (![selector isKindOfClass:NSDictionary.class]) return YES;
    NSDictionary *dictionary = selector;
    for (NSString *key in @[@"xpath", @"predicate", @"classChain"]) {
        id value = dictionary[key];
        if ([value isKindOfClass:NSString.class] && [(NSString *)value length] > AutoWDAMaxSelectorExpressionLength) {
            if (error) *error = AutoWDAError(AutoSDKErrorInvalidConfiguration,
                                             @"WDA selector expressions are limited to 65536 characters.");
            return NO;
        }
    }
    for (NSString *key in @[@"id", @"name", @"label", @"value", @"text", @"type"]) {
        id value = dictionary[key];
        if ([value isKindOfClass:NSString.class] && [(NSString *)value length] > AutoWDAMaxSelectorTextLength) {
            if (error) *error = AutoWDAError(AutoSDKErrorInvalidConfiguration,
                                             @"WDA selector text fields are limited to 8192 characters.");
            return NO;
        }
    }
    for (NSString *key in @[@"idMatch", @"idRegex", @"nameMatch", @"nameRegex", @"labelMatch", @"labelRegex",
                              @"valueMatch", @"valueRegex", @"textMatch", @"textRegex", @"typeMatch", @"typeRegex"]) {
        id value = dictionary[key];
        if ([value isKindOfClass:NSString.class] && [(NSString *)value length] > AutoWDAMaxSelectorRegexLength) {
            if (error) *error = AutoWDAError(AutoSDKErrorInvalidConfiguration,
                                             @"WDA selector regular expressions are limited to 1024 characters.");
            return NO;
        }
    }
    for (NSString *key in @[@"element-6066-11e4-a52e-4f735466cecf", @"ELEMENT", @"elementId", @"wdElementId", @"handle", @"sessionId"]) {
        id value = dictionary[key];
        if ([value isKindOfClass:NSString.class] && [(NSString *)value length] > AutoWDAMaxElementHandleLength) {
            if (error) *error = AutoWDAError(AutoSDKErrorInvalidConfiguration,
                                             @"WDA element and session handles are limited to 4096 characters.");
            return NO;
        }
    }
    for (NSString *key in @[@"index", @"depth", @"maxResults"]) {
        id value = dictionary[key];
        double number = AutoWDAIsNumber(value) ? [value doubleValue] : -1;
        if (value && (!AutoWDAIsNumber(value) || number < 0 ||
                      number > (double)NSUIntegerMax || floor(number) != number)) {
            if (error) *error = AutoWDAError(AutoSDKErrorInvalidConfiguration,
                [NSString stringWithFormat:@"WDA selector field '%@' must be a non-negative integer.", key]);
            return NO;
        }
    }
    id boundsValue = dictionary[@"bounds"];
    if (boundsValue) {
        if (![boundsValue isKindOfClass:NSDictionary.class]) {
            if (error) *error = AutoWDAError(AutoSDKErrorInvalidConfiguration,
                                             @"WDA selector bounds must be an object.");
            return NO;
        }
        NSDictionary *bounds = boundsValue;
        for (NSString *key in @[@"x", @"y", @"width", @"height"]) {
            if (!AutoWDAIsNumber(bounds[key])) {
                if (error) *error = AutoWDAError(AutoSDKErrorInvalidConfiguration,
                    @"WDA selector bounds require finite x, y, width, and height values.");
                return NO;
            }
        }
        if ([bounds[@"width"] doubleValue] < 0 || [bounds[@"height"] doubleValue] < 0) {
            if (error) *error = AutoWDAError(AutoSDKErrorInvalidConfiguration,
                                             @"WDA selector bounds dimensions cannot be negative.");
            return NO;
        }
    }
    return YES;
}

static id AutoWDAUnwrapSelector(id selector, NSError **error) {
    const void *visited[AutoWDAMaxSelectorNestingDepth] = {0};
    id current = selector;
    NSUInteger depth = 0;
    while ([current isKindOfClass:NSDictionary.class] && ((NSDictionary *)current)[@"selector"] != nil) {
        if (depth >= AutoWDAMaxSelectorNestingDepth) {
            if (error) *error = AutoWDAError(AutoSDKErrorInvalidConfiguration,
                                             @"WDA selector nesting exceeds 32 levels.");
            return nil;
        }
        const void *identity = (__bridge const void *)current;
        for (NSUInteger index = 0; index < depth; index++) {
            if (visited[index] == identity) {
                if (error) *error = AutoWDAError(AutoSDKErrorInvalidConfiguration,
                                                 @"WDA selector nesting contains a cycle.");
                return nil;
            }
        }
        visited[depth++] = identity;
        current = ((NSDictionary *)current)[@"selector"];
    }
    return AutoWDAValidateUnwrappedSelector(current, error) ? current : nil;
}

static id AutoWDAResponseValue(id response) {
    if ([response isKindOfClass:NSDictionary.class] && response[@"value"] != nil) return response[@"value"];
    return response;
}

static BOOL AutoWDAIsNumber(id value) {
    return [value isKindOfClass:NSNumber.class] && isfinite([value doubleValue]);
}

static CGFloat AutoWDADouble(id value, CGFloat fallback) {
    if (AutoWDAIsNumber(value)) return [value doubleValue];
    if ([value isKindOfClass:NSString.class] && ((NSString *)value).length > 0) {
        NSScanner *scanner = [NSScanner scannerWithString:value];
        double parsed = 0;
        if ([scanner scanDouble:&parsed] && scanner.isAtEnd && isfinite(parsed)) return (CGFloat)parsed;
    }
    return fallback;
}

static NSUInteger AutoWDAUnsigned(id value, NSUInteger fallback) {
    if (!AutoWDAIsNumber(value)) return fallback;
    double number = [value doubleValue];
    return number > 0 && number <= (double)NSUIntegerMax ? (NSUInteger)number : fallback;
}

typedef struct {
    CGContextRef context;
    uint8_t *bytes;
    size_t width;
    size_t height;
    size_t bytesPerRow;
} AutoWDAPixelImage;

static BOOL AutoWDAPixelByteCount(size_t width, size_t height, size_t *byteCount) {
    if (byteCount) *byteCount = 0;
    if (width == 0 || height == 0 || width > SIZE_MAX / 4) return NO;
    size_t bytesPerRow = width * 4;
    if (height > SIZE_MAX / bytesPerRow) return NO;
    if (byteCount) *byteCount = height * bytesPerRow;
    return YES;
}

static AutoWDAPixelImage AutoWDAPixelImageMake(CGImageRef image) {
    AutoWDAPixelImage result = {0};
    if (!image) return result;
    result.width = CGImageGetWidth(image);
    result.height = CGImageGetHeight(image);
    size_t byteCount = 0;
    if (!AutoWDAPixelByteCount(result.width, result.height, &byteCount)) return result;
    result.bytesPerRow = result.width * 4;
    if (byteCount > AutoWDAMaxPixelBufferBytes) return (AutoWDAPixelImage){0};
    result.bytes = calloc(result.height, result.bytesPerRow);
    if (!result.bytes) return (AutoWDAPixelImage){0};
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    if (!colorSpace) {
        free(result.bytes);
        return (AutoWDAPixelImage){0};
    }
    result.context = CGBitmapContextCreate(result.bytes, result.width, result.height, 8,
                                           result.bytesPerRow, colorSpace,
                                           kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);
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

static AutoWDAPixelImage AutoWDAPixelImageMakeRegion(CGImageRef image,
                                                      CGRect region,
                                                      NSUInteger *originX,
                                                      NSUInteger *originY) {
    if (originX) *originX = 0;
    if (originY) *originY = 0;
    if (!image || CGRectIsNull(region) || CGRectIsEmpty(region)) return (AutoWDAPixelImage){0};
    size_t imageWidth = CGImageGetWidth(image), imageHeight = CGImageGetHeight(image);
    CGRect clipped = CGRectIntersection(region, CGRectMake(0, 0, imageWidth, imageHeight));
    if (CGRectIsNull(clipped) || CGRectIsEmpty(clipped)) return (AutoWDAPixelImage){0};
    NSUInteger minX = MIN(imageWidth, (NSUInteger)MAX(0, floor(CGRectGetMinX(clipped))));
    NSUInteger minY = MIN(imageHeight, (NSUInteger)MAX(0, floor(CGRectGetMinY(clipped))));
    NSUInteger maxX = MIN(imageWidth, (NSUInteger)MAX(0, ceil(CGRectGetMaxX(clipped))));
    NSUInteger maxY = MIN(imageHeight, (NSUInteger)MAX(0, ceil(CGRectGetMaxY(clipped))));
    if (maxX <= minX || maxY <= minY) return (AutoWDAPixelImage){0};
    if (originX) *originX = minX;
    if (originY) *originY = minY;
    if (minX == 0 && minY == 0 && maxX == imageWidth && maxY == imageHeight) {
        return AutoWDAPixelImageMake(image);
    }
    CGImageRef cropped = CGImageCreateWithImageInRect(image, CGRectMake(minX, minY, maxX - minX, maxY - minY));
    if (!cropped) return (AutoWDAPixelImage){0};
    AutoWDAPixelImage result = AutoWDAPixelImageMake(cropped);
    CGImageRelease(cropped);
    return result;
}

static void AutoWDAPixelImageDestroy(AutoWDAPixelImage *image) {
    if (image->context) CGContextRelease(image->context);
    free(image->bytes);
    *image = (AutoWDAPixelImage){0};
}

static NSUInteger AutoWDAAdaptedScanStep(NSUInteger width,
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
} AutoWDAColorOffset;

static BOOL AutoWDAParseColor(id color, uint8_t *red, uint8_t *green, uint8_t *blue) {
    NSArray *colorValues = [color isKindOfClass:NSArray.class] ? (NSArray *)color : nil;
    if (colorValues.count >= 3) {
        if (!AutoWDAIsNumber(colorValues[0]) || !AutoWDAIsNumber(colorValues[1]) || !AutoWDAIsNumber(colorValues[2])) return NO;
        *red = (uint8_t)MIN(255, MAX(0, AutoWDADouble(colorValues[0], 0)));
        *green = (uint8_t)MIN(255, MAX(0, AutoWDADouble(colorValues[1], 0)));
        *blue = (uint8_t)MIN(255, MAX(0, AutoWDADouble(colorValues[2], 0)));
        return YES;
    }
    if ([color isKindOfClass:NSDictionary.class]) {
        id redValue = color[@"r"] ?: color[@"red"];
        id greenValue = color[@"g"] ?: color[@"green"];
        id blueValue = color[@"b"] ?: color[@"blue"];
        if (AutoWDAIsNumber(redValue) && AutoWDAIsNumber(greenValue) && AutoWDAIsNumber(blueValue)) {
            *red = (uint8_t)MIN(255, MAX(0, AutoWDADouble(redValue, 0)));
            *green = (uint8_t)MIN(255, MAX(0, AutoWDADouble(greenValue, 0)));
            *blue = (uint8_t)MIN(255, MAX(0, AutoWDADouble(blueValue, 0)));
            return YES;
        }
    }
    if (![color isKindOfClass:NSString.class]) return NO;
    NSString *value = [(NSString *)color stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([value hasPrefix:@"#"]) value = [value substringFromIndex:1];
    if ([value hasPrefix:@"0x"] || [value hasPrefix:@"0X"]) value = [value substringFromIndex:2];
    unsigned long long number = 0;
    NSScanner *scanner = [NSScanner scannerWithString:value];
    if (![scanner scanHexLongLong:&number] || !scanner.isAtEnd || (value.length != 6 && value.length != 8)) return NO;
    *red = (uint8_t)((number >> 16) & 0xff);
    *green = (uint8_t)((number >> 8) & 0xff);
    *blue = (uint8_t)(number & 0xff);
    return YES;
}

typedef struct {
    CGFloat x;
    CGFloat y;
} AutoWDACoordinateScale;

static AutoWDACoordinateScale AutoWDACoordinateScaleMake(CGFloat x, CGFloat y) {
    return (AutoWDACoordinateScale){ MAX(0.01, x), MAX(0.01, y) };
}

static CGRect AutoWDAPixelRegion(NSDictionary *region, AutoWDACoordinateScale scale, size_t width, size_t height) {
    BOOL hasWidth = region[@"width"] != nil;
    BOOL hasHeight = region[@"height"] != nil;
    CGFloat x = AutoWDADouble(region[@"x"], 0) * scale.x;
    CGFloat y = AutoWDADouble(region[@"y"], 0) * scale.y;
    CGFloat w = AutoWDADouble(region[@"width"], 0) * scale.x;
    CGFloat h = AutoWDADouble(region[@"height"], 0) * scale.y;
    if (!isfinite(x) || !isfinite(y) || !isfinite(w) || !isfinite(h)) return CGRectNull;
    CGRect bounds = CGRectMake(0, 0, width, height);
    if (!hasWidth && !hasHeight) return bounds;
    if (!hasWidth || !hasHeight || w <= 0 || h <= 0) return CGRectNull;
    return CGRectIntersection(CGRectMake(x, y, w, h), bounds);
}

static NSDictionary *AutoWDAMatchResult(CGFloat x, CGFloat y, CGFloat width, CGFloat height, AutoWDACoordinateScale scale) {
    return @{ @"found": @YES, @"x": @(x / scale.x), @"y": @(y / scale.y),
              @"width": @(width / scale.x), @"height": @(height / scale.y),
              @"centerX": @((x + width / 2) / scale.x), @"centerY": @((y + height / 2) / scale.y) };
}

static UIImage *AutoWDATemplateImage(NSString *path) {
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
        size_t width = CGImageGetWidth(image.CGImage), height = CGImageGetHeight(image.CGImage);
        NSUInteger cost = width > 0 && height <= NSUIntegerMax / width / 4 ? width * height * 4 : 1;
        [cache setObject:image forKey:cacheKey cost:cost];
    }
    return image;
}

static BOOL AutoWDAPixelMatches(const uint8_t *pixel, uint8_t red, uint8_t green, uint8_t blue, CGFloat tolerance) {
    return fabs((double)pixel[0] - red) <= tolerance &&
           fabs((double)pixel[1] - green) <= tolerance &&
           fabs((double)pixel[2] - blue) <= tolerance;
}

static NSDictionary *AutoWDAPixelColorResult(const uint8_t *pixel, CGFloat x, CGFloat y) {
    return @{ @"x": @(x), @"y": @(y), @"r": @(pixel[0]), @"g": @(pixel[1]), @"b": @(pixel[2]),
              @"a": @(pixel[3]), @"hex": [NSString stringWithFormat:@"#%02X%02X%02X", pixel[0], pixel[1], pixel[2]] };
}

static CGFloat AutoWDAImageSimilarity(AutoWDAPixelImage needle, AutoWDAPixelImage haystack,
                                       NSUInteger originX, NSUInteger originY,
                                       NSUInteger stepX, NSUInteger stepY,
                                       CGFloat minimumSimilarity,
                                       BOOL (^shouldCancel)(void),
                                       BOOL *cancelled) {
    if (cancelled) *cancelled = NO;
    double sampleWeight = 0;
    double difference = 0;
    NSUInteger checkedSamples = 0;
    NSUInteger xStep = MAX(1, stepX), yStep = MAX(1, stepY);
    NSUInteger totalSamples = ((needle.width - 1) / xStep + 1) * ((needle.height - 1) / yStep + 1);
    double maximumDifference = MAX(0, 1.0 - minimumSimilarity) * totalSamples;
    for (NSUInteger y = 0; y < needle.height; y += yStep) {
        for (NSUInteger x = 0; x < needle.width; x += xStep) {
            if ((checkedSamples++ & 0xFFF) == 0 && shouldCancel && shouldCancel()) {
                if (cancelled) *cancelled = YES;
                return 0;
            }
            const uint8_t *a = needle.bytes + y * needle.bytesPerRow + x * 4;
            const uint8_t *b = haystack.bytes + (originY + y) * haystack.bytesPerRow + (originX + x) * 4;
            if (a[3] == 0) continue;
            double alphaWeight = (double)a[3] / 255.0;
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

@interface AutoWDASourceNode : NSObject
@property (nonatomic, copy) NSString *elementName;
@property (nonatomic, copy) NSString *pathComponent;
@property (nonatomic, copy, nullable) NSString *cachedXPath;
@property (nonatomic, readonly, copy) NSString *xpath;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *attributes;
@property (nonatomic, weak) AutoWDASourceNode *parent;
@property (nonatomic, strong) NSMutableArray<AutoWDASourceNode *> *children;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *childTypeCounts;
@property (nonatomic, assign) NSUInteger depth;
@property (nonatomic, assign) NSUInteger siblingIndex;
@end

@implementation AutoWDASourceNode

- (NSString *)xpath {
    @synchronized (self) {
        if (self.cachedXPath.length > 0) return self.cachedXPath;
        NSMutableArray<NSString *> *components = [NSMutableArray array];
        AutoWDASourceNode *current = self;
        while (current) {
            if (current.pathComponent.length > 0) [components addObject:current.pathComponent];
            current = current.parent;
        }
        NSMutableString *result = [NSMutableString string];
        for (NSString *component in components.reverseObjectEnumerator) [result appendString:component];
        self.cachedXPath = result.copy;
        return self.cachedXPath ?: @"";
    }
}

@end

@interface AutoWDASourceParser : NSObject <NSXMLParserDelegate>
@property (nonatomic, strong) AutoWDASourceNode *root;
@property (nonatomic, strong) NSMutableArray<AutoWDASourceNode *> *stack;
@property (nonatomic, assign) NSUInteger maxNodes;
@property (nonatomic, assign) NSUInteger nodeCount;
@property (nonatomic, assign) BOOL limitExceeded;
@property (nonatomic, assign) BOOL depthExceeded;
@property (nonatomic, assign) BOOL cancelled;
@property (nonatomic, copy, nullable) BOOL (^shouldCancel)(void);
- (instancetype)initWithMaxNodes:(NSUInteger)maxNodes;
@end

@implementation AutoWDASourceParser

- (instancetype)init {
    return [self initWithMaxNodes:AutoWDADefaultSourceMaxNodes];
}

- (instancetype)initWithMaxNodes:(NSUInteger)maxNodes {
    self = [super init];
    if (self) {
        _stack = [NSMutableArray array];
        _maxNodes = maxNodes > 0 ? maxNodes : AutoWDADefaultSourceMaxNodes;
    }
    return self;
}

- (void)parser:(NSXMLParser *)parser
 didStartElement:(NSString *)elementName
    namespaceURI:(NSString *)namespaceURI
      qualifiedName:(NSString *)qName
      attributes:(NSDictionary<NSString *,NSString *> *)attributeDict {
    if ((self.nodeCount & 0x3F) == 0 && self.shouldCancel && self.shouldCancel()) {
        self.cancelled = YES;
        [parser abortParsing];
        return;
    }
    if (self.maxNodes > 0 && self.nodeCount >= self.maxNodes) {
        self.limitExceeded = YES;
        [parser abortParsing];
        return;
    }
    AutoWDASourceNode *parent = self.stack.lastObject;
    if (parent && parent.depth >= AutoWDAMaxSourceDepth - 1) {
        self.depthExceeded = YES;
        [parser abortParsing];
        return;
    }
    AutoWDASourceNode *node = [AutoWDASourceNode new];
    self.nodeCount += 1;
    node.elementName = elementName ?: @"Node";
    node.attributes = attributeDict ?: @{};
    node.parent = parent;
    node.depth = parent ? parent.depth + 1 : 0;
    if (parent && !parent.childTypeCounts) parent.childTypeCounts = [NSMutableDictionary dictionary];
    NSUInteger sameTypeIndex = parent ? [parent.childTypeCounts[node.elementName] unsignedIntegerValue] + 1 : 1;
    if (parent) parent.childTypeCounts[node.elementName] = @(sameTypeIndex);
    node.siblingIndex = sameTypeIndex - 1;
    node.pathComponent = [NSString stringWithFormat:@"/%@[%lu]", node.elementName, (unsigned long)sameTypeIndex];
    if (parent) {
        if (!parent.children) parent.children = [NSMutableArray array];
        [parent.children addObject:node];
    }
    else self.root = node;
    [self.stack addObject:node];
    (void)parser; (void)namespaceURI; (void)qName;
}

- (void)parser:(NSXMLParser *)parser
   didEndElement:(NSString *)elementName
    namespaceURI:(NSString *)namespaceURI
   qualifiedName:(NSString *)qName {
    if (self.stack.count > 0) {
        AutoWDASourceNode *node = self.stack.lastObject;
        // Sibling counters are only needed while this node is receiving children.
        node.childTypeCounts = nil;
        [self.stack removeLastObject];
    }
    (void)parser; (void)elementName; (void)namespaceURI; (void)qName;
}

@end

static BOOL AutoWDASourceBool(NSString *value) {
    NSString *normalized = value.lowercaseString;
    return [normalized isEqualToString:@"true"] || [normalized isEqualToString:@"yes"] || [normalized isEqualToString:@"1"];
}

static BOOL AutoWDASourceRegexMatches(NSString *actual, id pattern) {
    if (![actual isKindOfClass:NSString.class] || ![pattern isKindOfClass:NSString.class]) return NO;
    if (actual.length > AutoWDAMaxSelectorTextLength) return NO;
    if ([(NSString *)pattern length] == 0 || [(NSString *)pattern length] > 1024) return NO;
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
    return expression && [expression firstMatchInString:actual options:0 range:NSMakeRange(0, actual.length)] != nil;
}

static BOOL AutoWDASourceStringMatches(NSString *actual, id expected) {
    return [actual isKindOfClass:NSString.class] && [expected isKindOfClass:NSString.class] && [actual isEqualToString:expected];
}

static BOOL AutoWDASourceNodeMatches(AutoWDASourceNode *node, id selector) {
    NSDictionary *attributes = node.attributes;
    NSString *name = attributes[@"name"] ?: attributes[@"identifier"];
    NSString *label = attributes[@"label"];
    NSString *value = attributes[@"value"];
    NSString *type = attributes[@"type"] ?: node.elementName;
    if ([selector isKindOfClass:NSString.class]) {
        return AutoWDASourceStringMatches(name, selector) || AutoWDASourceStringMatches(label, selector) || AutoWDASourceStringMatches(value, selector);
    }
    if (![selector isKindOfClass:NSDictionary.class]) return NO;
    NSDictionary *query = selector;
    NSString *xpath = [query[@"xpath"] isKindOfClass:NSString.class] ? query[@"xpath"] : nil;
    if (xpath.length > 0) return [node.xpath isEqualToString:xpath];
    if ([query[@"predicate"] isKindOfClass:NSString.class] || [query[@"classChain"] isKindOfClass:NSString.class]) return NO;
    BOOL hasCondition = NO;
#define AUTO_WDA_SOURCE_EXACT(KEY, ACTUAL) do { id expected = query[KEY]; if (expected) { hasCondition = YES; if (!AutoWDASourceStringMatches((ACTUAL), expected)) return NO; } } while (0)
#define AUTO_WDA_SOURCE_REGEX(KEY, ACTUAL) do { id expected = query[KEY]; if (expected) { hasCondition = YES; if (!AutoWDASourceRegexMatches((ACTUAL), expected)) return NO; } } while (0)
    id identifier = query[@"id"];
    if (identifier) {
        hasCondition = YES;
        NSString *sourceId = attributes[@"identifier"] ?: name;
        if (!AutoWDASourceStringMatches(sourceId, identifier)) return NO;
    }
    AUTO_WDA_SOURCE_REGEX(@"idMatch", attributes[@"identifier"] ?: name);
    if (!query[@"idMatch"]) AUTO_WDA_SOURCE_REGEX(@"idRegex", attributes[@"identifier"] ?: name);
    AUTO_WDA_SOURCE_EXACT(@"name", name);
    AUTO_WDA_SOURCE_EXACT(@"label", label);
    AUTO_WDA_SOURCE_EXACT(@"value", value);
    id text = query[@"text"];
    if (text) { hasCondition = YES; if (!AutoWDASourceStringMatches(label, text) && !AutoWDASourceStringMatches(value, text)) return NO; }
    AUTO_WDA_SOURCE_REGEX(@"nameMatch", name);
    if (!query[@"nameMatch"]) AUTO_WDA_SOURCE_REGEX(@"nameRegex", name);
    AUTO_WDA_SOURCE_REGEX(@"labelMatch", label);
    if (!query[@"labelMatch"]) AUTO_WDA_SOURCE_REGEX(@"labelRegex", label);
    AUTO_WDA_SOURCE_REGEX(@"valueMatch", value);
    if (!query[@"valueMatch"]) AUTO_WDA_SOURCE_REGEX(@"valueRegex", value);
    id textPattern = query[@"textMatch"] ?: query[@"textRegex"];
    if (textPattern) { hasCondition = YES; if (!AutoWDASourceRegexMatches(label, textPattern) && !AutoWDASourceRegexMatches(value, textPattern)) return NO; }
    id expectedType = query[@"type"];
    if (expectedType) {
        hasCondition = YES;
        if (![expectedType isKindOfClass:NSString.class] || !AutoWDASourceStringMatches(type, AutoWDAElementType(expectedType))) return NO;
    }
    id typePattern = query[@"typeMatch"] ?: query[@"typeRegex"];
    if (typePattern) { hasCondition = YES; if (!AutoWDASourceRegexMatches(type, typePattern)) return NO; }
#undef AUTO_WDA_SOURCE_EXACT
#undef AUTO_WDA_SOURCE_REGEX
    for (NSString *key in @[@"visible", @"enabled", @"selected", @"accessible"]) {
        id expected = query[key];
        if (![expected isKindOfClass:NSNumber.class]) continue;
        hasCondition = YES;
        if (AutoWDASourceBool(attributes[key]) != [expected boolValue]) return NO;
    }
    if ([query[@"index"] isKindOfClass:NSNumber.class]) {
        hasCondition = YES;
        NSNumber *indexValue = [attributes[@"index"] isKindOfClass:NSNumber.class] ? attributes[@"index"] : nil;
        NSUInteger index = indexValue ? indexValue.unsignedIntegerValue : node.siblingIndex;
        if (index != [query[@"index"] unsignedIntegerValue]) return NO;
    }
    if ([query[@"depth"] isKindOfClass:NSNumber.class]) {
        hasCondition = YES;
        if (node.depth != [query[@"depth"] unsignedIntegerValue]) return NO;
    }
        NSDictionary *bounds = [query[@"bounds"] isKindOfClass:NSDictionary.class] ? query[@"bounds"] : nil;
    if (bounds) {
        hasCondition = YES;
        for (NSString *key in @[@"x", @"y", @"width", @"height"]) {
            CGFloat actual = AutoWDADouble(attributes[key], NAN);
            if (!AutoWDAIsNumber(bounds[key]) || !isfinite(actual) || fabs(actual - [bounds[key] doubleValue]) > 1.0) return NO;
        }
    }
    return hasCondition;
}

static AutoWDASourceNode *AutoWDAFindSourceNodeByAbsolutePath(AutoWDASourceNode *root,
                                                               NSString *xpath,
                                                               BOOL *recognized,
                                                               BOOL (^shouldCancel)(void),
                                                               BOOL *cancelled) {
    if (recognized) *recognized = NO;
    if (!root || ![xpath isKindOfClass:NSString.class] || ![xpath hasPrefix:@"/"] ||
        [xpath rangeOfString:@"//"].location != NSNotFound) return nil;
    NSArray<NSString *> *rawComponents = [xpath componentsSeparatedByString:@"/"];
    if (rawComponents.count < 2 || rawComponents.count > AutoWDAMaxSourceDepth + 1) return nil;
    AutoWDASourceNode *current = root;
    NSUInteger pathIndex = 0;
    for (NSString *component in rawComponents) {
        if (component.length == 0) continue;
        if ((pathIndex & 0x3F) == 0 && shouldCancel && shouldCancel()) {
            if (cancelled) *cancelled = YES;
            return nil;
        }
        NSRange bracket = [component rangeOfString:@"[" options:NSBackwardsSearch];
        if (bracket.location == NSNotFound || ![component hasSuffix:@"]"] || bracket.location == 0) return nil;
        NSString *name = [component substringToIndex:bracket.location];
        NSString *indexText = [component substringWithRange:NSMakeRange(bracket.location + 1,
                                                                        component.length - bracket.location - 2)];
        NSScanner *scanner = [NSScanner scannerWithString:indexText];
        NSInteger oneBasedIndex = 0;
        if (![scanner scanInteger:&oneBasedIndex] || !scanner.isAtEnd || oneBasedIndex <= 0) return nil;
        if (pathIndex == 0) {
            if (![current.elementName isEqualToString:name] || current.siblingIndex + 1 != (NSUInteger)oneBasedIndex) {
                if (recognized) *recognized = YES;
                return nil;
            }
        } else {
            AutoWDASourceNode *next = nil;
            for (AutoWDASourceNode *child in current.children) {
                if ([child.elementName isEqualToString:name] && child.siblingIndex + 1 == (NSUInteger)oneBasedIndex) {
                    next = child;
                    break;
                }
            }
            if (!next) {
                if (recognized) *recognized = YES;
                return nil;
            }
            current = next;
        }
        pathIndex += 1;
    }
    if (pathIndex == 0) return nil;
    if (recognized) *recognized = YES;
    return current;
}

static AutoWDASourceNode *AutoWDAFindSourceNode(AutoWDASourceNode *root,
                                                 id selector,
                                                 BOOL (^shouldCancel)(void),
                                                 BOOL *cancelled,
                                                 NSError **error) {
    if (cancelled) *cancelled = NO;
    if (!root) return nil;
    NSError *unwrapError = nil;
    id unwrapped = AutoWDAUnwrapSelector(selector, &unwrapError);
    if (unwrapError) {
        if (error) *error = unwrapError;
        return nil;
    }
    NSString *xpath = [unwrapped isKindOfClass:NSDictionary.class] && [unwrapped[@"xpath"] isKindOfClass:NSString.class]
        ? unwrapped[@"xpath"]
        : nil;
    BOOL recognizedAbsolutePath = NO;
    if (xpath.length > 0) {
        AutoWDASourceNode *pathNode = AutoWDAFindSourceNodeByAbsolutePath(root, xpath,
                                                                         &recognizedAbsolutePath,
                                                                         shouldCancel, cancelled);
        if (recognizedAbsolutePath || (cancelled && *cancelled)) return pathNode;
        // WDA can resolve descendant/complex XPath expressions. The local tree
        // only supports exact generated absolute paths, so avoid an O(n) scan.
        return nil;
    }
    NSMutableArray<AutoWDASourceNode *> *nodes = [NSMutableArray arrayWithObject:root];
    NSUInteger visitedCount = 0;
    while (nodes.count > 0) {
        if ((visitedCount++ & 0x3F) == 0 && shouldCancel && shouldCancel()) {
            if (cancelled) *cancelled = YES;
            return nil;
        }
        AutoWDASourceNode *node = nodes.lastObject;
        [nodes removeLastObject];
        if (AutoWDASourceNodeMatches(node, unwrapped)) return node;
        for (AutoWDASourceNode *child in node.children.reverseObjectEnumerator) {
            [nodes addObject:child];
        }
    }
    return nil;
}

static NSDictionary *AutoWDASourceNodeInfo(AutoWDASourceNode *node) {
    NSDictionary *attributes = node.attributes;
    NSString *name = attributes[@"name"] ?: attributes[@"identifier"];
    NSString *label = attributes[@"label"];
    NSString *value = attributes[@"value"];
    NSString *type = attributes[@"type"] ?: node.elementName ?: @"";
    CGFloat x = AutoWDADouble(attributes[@"x"], 0), y = AutoWDADouble(attributes[@"y"], 0);
    CGFloat width = AutoWDADouble(attributes[@"width"], 0), height = AutoWDADouble(attributes[@"height"], 0);
    NSString *handle = [@"source:" stringByAppendingString:node.xpath ?: @""];
    NSString *parentHandle = node.parent
        ? [@"source:" stringByAppendingString:node.parent.xpath ?: @""]
        : nil;
    return @{ @"selector": @{ @"xpath": node.xpath ?: @"" }, @"sourceDerived": @YES,
              @"handle": handle, @"uid": handle,
              @"nodeId": handle, @"parentId": parentHandle ?: NSNull.null,
              @"id": attributes[@"identifier"] ?: name ?: [NSNull null], @"name": name ?: [NSNull null],
              @"label": label ?: [NSNull null], @"value": value ?: [NSNull null],
              @"text": label ?: (value ?: [NSNull null]), @"type": type, @"className": node.elementName ?: type,
              @"enabled": @(AutoWDASourceBool(attributes[@"enabled"])), @"selected": @(AutoWDASourceBool(attributes[@"selected"])),
              @"visible": @(AutoWDASourceBool(attributes[@"visible"])), @"accessible": @(AutoWDASourceBool(attributes[@"accessible"])),
              @"index": attributes[@"index"] ? @([attributes[@"index"] integerValue]) : @(node.siblingIndex),
              @"order": @(node.siblingIndex), @"depth": @(node.depth), @"childCount": @(node.children.count),
              @"bounds": @{ @"x": @(x), @"y": @(y), @"width": @(width), @"height": @(height),
                             @"centerX": @(x + width / 2), @"centerY": @(y + height / 2) } };
}

@interface AutoWDAHTTPRedirectDelegate : NSObject <NSURLSessionTaskDelegate>
@property (nonatomic, strong) NSURL *originURL;
@end

@implementation AutoWDAHTTPRedirectDelegate

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
willPerformHTTPRedirection:(NSHTTPURLResponse *)response
        newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest * _Nullable))completionHandler {
    NSURL *origin = self.originURL;
    NSURL *target = request.URL;
    BOOL sameScheme = origin.scheme.length > 0 && [origin.scheme caseInsensitiveCompare:target.scheme] == NSOrderedSame;
    BOOL sameHost = origin.host.length > 0 && [origin.host caseInsensitiveCompare:target.host] == NSOrderedSame;
    NSInteger originPort = origin.port.integerValue ?: ([origin.scheme.lowercaseString isEqualToString:@"https"] ? 443 : 80);
    NSInteger targetPort = target.port.integerValue ?: ([target.scheme.lowercaseString isEqualToString:@"https"] ? 443 : 80);
    (void)session; (void)task; (void)response;
    completionHandler(sameScheme && sameHost && originPort == targetPort ? request : nil);
}

@end

static NSURLSession *AutoWDACreateURLSession(NSURL *baseURL, NSTimeInterval timeout) {
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    configuration.HTTPShouldSetCookies = NO;
    configuration.HTTPShouldUsePipelining = YES;
    configuration.URLCache = nil;
    configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    configuration.timeoutIntervalForRequest = timeout;
    configuration.timeoutIntervalForResource = timeout;
    AutoWDAHTTPRedirectDelegate *redirectDelegate = [AutoWDAHTTPRedirectDelegate new];
    redirectDelegate.originURL = baseURL;
    return [NSURLSession sessionWithConfiguration:configuration delegate:redirectDelegate delegateQueue:nil];
}

@interface AutoWDAHTTPAdapter ()
@property (nonatomic, readwrite) NSURL *baseURL;
@property (nonatomic, copy, readwrite, nullable) NSString *sessionId;
@property (nonatomic, strong) NSObject *sessionLock;
@property (nonatomic, strong) NSRecursiveLock *sessionCreationLock;
@property (nonatomic, strong) NSRecursiveLock *screenshotRequestLock;
@property (nonatomic, strong) NSRecursiveLock *sourceRequestLock;
@property (nonatomic, strong) NSRecursiveLock *visualOperationLock;
@property (nonatomic, strong) NSRecursiveLock *settingsApplicationLock;
@property (nonatomic, assign) NSUInteger sessionGeneration;
@property (nonatomic, assign) NSUInteger operationCancellationGeneration;
@property (nonatomic, copy) NSString *operationCancellationThreadKey;
@property (nonatomic, copy) NSString *operationCleanupTimeoutThreadKey;
@property (nonatomic, strong) NSURLSession *URLSession;
@property (nonatomic, strong) NSMutableSet<NSURLSessionTask *> *activeTasks;
@property (nonatomic, strong) NSMutableSet<VNRequest *> *activeVisionRequests;
@property (nonatomic, strong, nullable) AutoWDASourceNode *sourceCacheRoot;
@property (nonatomic, assign) NSTimeInterval sourceCacheTimestamp;
@property (nonatomic, assign) NSUInteger sourceCacheGeneration;
@property (nonatomic, strong, nullable) NSData *screenshotCacheData;
@property (nonatomic, assign) NSTimeInterval screenshotCacheTimestamp;
@property (nonatomic, assign) NSUInteger screenshotCacheGeneration;
@property (nonatomic, assign) CGSize windowSizeCache;
@property (nonatomic, assign) NSTimeInterval windowSizeCacheTimestamp;
@property (nonatomic, assign) NSUInteger windowSizeCacheGeneration;
@property (nonatomic, copy) NSString *settingsAppliedSessionId;
@property (nonatomic, copy) NSString *settingsAttemptedSessionId;
@property (nonatomic, assign) NSUInteger settingsGeneration;
@property (nonatomic, assign) NSUInteger settingsAppliedGeneration;
@property (nonatomic, assign) NSUInteger settingsAttemptedGeneration;
- (BOOL)ensureSession:(NSError **)error;
- (BOOL)applySessionSettingsForCurrentSession:(NSError **)error;
- (id)requestSessionSuffix:(NSString *)suffix method:(NSString *)method body:(NSDictionary *)body error:(NSError **)error;
- (id)requestSessionSuffix:(NSString *)suffix method:(NSString *)method body:(NSDictionary *)body usedSession:(NSString **)usedSession error:(NSError **)error;
- (id)requestElementSelector:(id)selector suffix:(NSString *)suffix method:(NSString *)method body:(NSDictionary *)body wdaNamespace:(BOOL)wdaNamespace error:(NSError **)error;
- (AutoWDACoordinateScale)coordinateScaleForImage:(CGImageRef)image;
- (AutoWDASourceNode *)sourceRootWithError:(NSError **)error;
- (AutoWDASourceNode *)sourceNodeForSelector:(id)selector
                               retainingRoot:(AutoWDASourceNode * _Nullable * _Nullable)retainedRoot
                                       error:(NSError **)error;
- (void)invalidateVisualCaches;
- (void)invalidateVisualCachesLocked;
- (NSUInteger)currentOperationCancellationGeneration;
- (BOOL)operationWasCancelledSinceGeneration:(NSUInteger)generation;
- (BOOL)installCancellationContextForGeneration:(NSUInteger)generation;
- (void)clearCancellationContext;
- (id)requestCleanupPath:(NSString *)path method:(NSString *)method body:(NSDictionary *)body error:(NSError **)error;
@end

@implementation AutoWDAHTTPAdapter

@synthesize applicationBundleId = _applicationBundleId;
@synthesize requestTimeout = _requestTimeout;
@synthesize sessionId = _sessionId;
@synthesize sourceCacheDuration = _sourceCacheDuration;
@synthesize sourceMaxBytes = _sourceMaxBytes;
@synthesize sourceMaxNodes = _sourceMaxNodes;
@synthesize screenshotCacheDuration = _screenshotCacheDuration;
@synthesize sessionSettings = _sessionSettings;
@synthesize ignoresUnsupportedSessionSettings = _ignoresUnsupportedSessionSettings;

- (instancetype)initWithBaseURL:(NSURL *)baseURL {
    return [self initWithBaseURL:baseURL applicationBundleId:nil timeout:15];
}

- (instancetype)initWithBaseURL:(NSURL *)baseURL
             applicationBundleId:(NSString *)applicationBundleId
                          timeout:(NSTimeInterval)timeout {
    self = [super init];
    if (!self) return nil;
    NSURLComponents *components = baseURL ? [NSURLComponents componentsWithURL:baseURL resolvingAgainstBaseURL:NO] : nil;
    if (components.path.length > 0 && ![components.path hasSuffix:@"/"]) components.path = [components.path stringByAppendingString:@"/"];
    _baseURL = components.URL ?: baseURL;
    _applicationBundleId = [applicationBundleId isKindOfClass:NSString.class] ? [applicationBundleId copy] : nil;
    _requestTimeout = timeout > 0 ? MIN(timeout, 120) : 15;
    _sessionLock = [NSObject new];
    _sessionCreationLock = [NSRecursiveLock new];
    _sessionCreationLock.name = @"com.autosdk.wda.session-creation";
    _screenshotRequestLock = [NSRecursiveLock new];
    _screenshotRequestLock.name = @"com.autosdk.wda.screenshot";
    _sourceRequestLock = [NSRecursiveLock new];
    _sourceRequestLock.name = @"com.autosdk.wda.source";
    _visualOperationLock = [NSRecursiveLock new];
    _visualOperationLock.name = @"com.autosdk.wda.visual-processing";
    _settingsApplicationLock = [NSRecursiveLock new];
    _settingsApplicationLock.name = @"com.autosdk.wda.settings-application";
    _sourceCacheDuration = 0.15;
    _sourceMaxBytes = AutoWDADefaultSourceMaxBytes;
    _sourceMaxNodes = AutoWDADefaultSourceMaxNodes;
    _screenshotCacheDuration = 0;
    _sessionSettings = @{};
    _settingsGeneration = 1;
    _ignoresUnsupportedSessionSettings = YES;
    _operationCancellationThreadKey = [NSString stringWithFormat:@"%@.%@",
                                       AutoWDAOperationCancellationThreadKey,
                                       NSUUID.UUID.UUIDString];
    _operationCleanupTimeoutThreadKey = [_operationCancellationThreadKey stringByAppendingString:@".cleanup-timeout"];
    _URLSession = AutoWDACreateURLSession(_baseURL, _requestTimeout);
    _activeTasks = [NSMutableSet set];
    _activeVisionRequests = [NSMutableSet set];
    return self;
}

- (void)dealloc {
    [self.URLSession invalidateAndCancel];
}

- (NSString *)applicationBundleId {
    @synchronized (self.sessionLock) { return [_applicationBundleId copy]; }
}

- (NSTimeInterval)requestTimeout {
    @synchronized (self.sessionLock) { return _requestTimeout; }
}

- (NSString *)sessionId {
    @synchronized (self.sessionLock) { return [_sessionId copy]; }
}

- (NSTimeInterval)sourceCacheDuration {
    @synchronized (self.sessionLock) { return _sourceCacheDuration; }
}

- (NSUInteger)sourceMaxBytes {
    @synchronized (self.sessionLock) { return _sourceMaxBytes; }
}

- (NSUInteger)sourceMaxNodes {
    @synchronized (self.sessionLock) { return _sourceMaxNodes; }
}

- (NSTimeInterval)screenshotCacheDuration {
    @synchronized (self.sessionLock) { return _screenshotCacheDuration; }
}

- (NSDictionary<NSString *,id> *)sessionSettings {
    @synchronized (self.sessionLock) { return [_sessionSettings copy] ?: @{}; }
}

- (BOOL)ignoresUnsupportedSessionSettings {
    @synchronized (self.sessionLock) { return _ignoresUnsupportedSessionSettings; }
}

- (NSUInteger)currentOperationCancellationGeneration {
    NSNumber *contextGeneration = NSThread.currentThread.threadDictionary[self.operationCancellationThreadKey];
    if ([contextGeneration isKindOfClass:NSNumber.class]) return contextGeneration.unsignedIntegerValue;
    @synchronized (self.sessionLock) { return self.operationCancellationGeneration; }
}

- (BOOL)operationWasCancelledSinceGeneration:(NSUInteger)generation {
    @synchronized (self.sessionLock) { return generation != self.operationCancellationGeneration; }
}

- (BOOL)installCancellationContextForGeneration:(NSUInteger)generation {
    NSMutableDictionary *threadDictionary = NSThread.currentThread.threadDictionary;
    NSString *key = self.operationCancellationThreadKey;
    if (threadDictionary[key] != nil) return NO;
    threadDictionary[key] = @(generation);
    return YES;
}

- (void)clearCancellationContext {
    [NSThread.currentThread.threadDictionary removeObjectForKey:self.operationCancellationThreadKey];
}

- (id)requestCleanupPath:(NSString *)path
                  method:(NSString *)method
                    body:(NSDictionary *)body
                   error:(NSError **)error {
    NSMutableDictionary *threadDictionary = NSThread.currentThread.threadDictionary;
    NSString *key = self.operationCancellationThreadKey;
    NSString *timeoutKey = self.operationCleanupTimeoutThreadKey;
    id previousContext = threadDictionary[key];
    id previousTimeout = threadDictionary[timeoutKey];
    NSUInteger currentGeneration = 0;
    @synchronized (self.sessionLock) { currentGeneration = self.operationCancellationGeneration; }
    threadDictionary[key] = @(currentGeneration);
    threadDictionary[timeoutKey] = @1.0;
    @try {
        return [self requestPath:path method:method body:body error:error];
    } @finally {
        if (previousContext) threadDictionary[key] = previousContext;
        else [threadDictionary removeObjectForKey:key];
        if (previousTimeout) threadDictionary[timeoutKey] = previousTimeout;
        else [threadDictionary removeObjectForKey:timeoutKey];
    }
}

- (void)setIgnoresUnsupportedSessionSettings:(BOOL)ignoresUnsupportedSessionSettings {
    @synchronized (self.sessionLock) { _ignoresUnsupportedSessionSettings = ignoresUnsupportedSessionSettings; }
}

- (void)setRequestTimeout:(NSTimeInterval)requestTimeout {
    NSTimeInterval value = isfinite(requestTimeout) && requestTimeout > 0 ? MIN(requestTimeout, 120.0) : 15.0;
    NSURLSession *oldSession = nil;
    @synchronized (self.sessionLock) {
        if (_requestTimeout == value) return;
        _requestTimeout = value;
        oldSession = self.URLSession;
        self.URLSession = AutoWDACreateURLSession(self.baseURL, value);
    }
    [oldSession finishTasksAndInvalidate];
}

- (void)setSourceCacheDuration:(NSTimeInterval)sourceCacheDuration {
    NSTimeInterval value = isfinite(sourceCacheDuration) && sourceCacheDuration > 0 ? MIN(sourceCacheDuration, 5.0) : 0;
    @synchronized (self.sessionLock) {
        if (_sourceCacheDuration == value) return;
        _sourceCacheDuration = value;
        self.sourceCacheGeneration += 1;
        self.sourceCacheRoot = nil;
        self.sourceCacheTimestamp = 0;
    }
}

- (void)setSourceMaxBytes:(NSUInteger)sourceMaxBytes {
    NSUInteger value = sourceMaxBytes > 0 ? MIN(sourceMaxBytes, AutoWDAMaxSourceBytes) : AutoWDADefaultSourceMaxBytes;
    @synchronized (self.sessionLock) {
        _sourceMaxBytes = value;
        self.sourceCacheRoot = nil;
        self.sourceCacheTimestamp = 0;
        self.sourceCacheGeneration += 1;
    }
}

- (void)setSourceMaxNodes:(NSUInteger)sourceMaxNodes {
    NSUInteger value = sourceMaxNodes > 0 ? MIN(sourceMaxNodes, AutoWDAMaxSourceNodes) : AutoWDADefaultSourceMaxNodes;
    @synchronized (self.sessionLock) {
        _sourceMaxNodes = value;
        self.sourceCacheRoot = nil;
        self.sourceCacheTimestamp = 0;
        self.sourceCacheGeneration += 1;
    }
}

- (void)setScreenshotCacheDuration:(NSTimeInterval)screenshotCacheDuration {
    NSTimeInterval value = isfinite(screenshotCacheDuration) && screenshotCacheDuration > 0 ? MIN(screenshotCacheDuration, 2.0) : 0;
    @synchronized (self.sessionLock) {
        if (_screenshotCacheDuration == value) return;
        _screenshotCacheDuration = value;
        self.screenshotCacheGeneration += 1;
        self.screenshotCacheData = nil;
        self.screenshotCacheTimestamp = 0;
    }
}

- (void)setSessionSettings:(NSDictionary<NSString *,id> *)sessionSettings {
    NSDictionary *value = [sessionSettings isKindOfClass:NSDictionary.class] ? [sessionSettings copy] : @{};
    @synchronized (self.sessionLock) {
        if ([_sessionSettings isEqualToDictionary:value]) return;
        _sessionSettings = value;
        self.settingsGeneration += 1;
        if (self.settingsGeneration == 0) self.settingsGeneration = 1;
        self.settingsAppliedSessionId = nil;
        self.settingsAttemptedSessionId = nil;
        self.settingsAppliedGeneration = 0;
        self.settingsAttemptedGeneration = 0;
    }
}

- (void)invalidateVisualCaches {
    @synchronized (self.sessionLock) {
        [self invalidateVisualCachesLocked];
    }
}

- (void)invalidateVisualCachesLocked {
    self.sourceCacheRoot = nil;
    self.sourceCacheTimestamp = 0;
    self.sourceCacheGeneration += 1;
    self.screenshotCacheData = nil;
    self.screenshotCacheTimestamp = 0;
    self.screenshotCacheGeneration += 1;
    self.windowSizeCache = CGSizeZero;
    self.windowSizeCacheTimestamp = 0;
    self.windowSizeCacheGeneration += 1;
}

- (void)setApplicationBundleId:(NSString *)applicationBundleId {
    NSString *newValue = [applicationBundleId isKindOfClass:NSString.class] && applicationBundleId.length > 0
        ? [applicationBundleId copy]
        : nil;
    NSString *oldSession = nil;
    NSArray<NSURLSessionTask *> *tasks = nil;
    NSArray<VNRequest *> *visionRequests = nil;
    @synchronized (self.sessionLock) {
        if ((_applicationBundleId == newValue) || [_applicationBundleId isEqualToString:newValue]) return;
        _applicationBundleId = newValue;
        self.operationCancellationGeneration += 1;
        tasks = self.activeTasks.allObjects;
        visionRequests = self.activeVisionRequests.allObjects;
        oldSession = self.sessionId;
        self.sessionId = nil;
        self.sessionGeneration += 1;
        self.settingsAppliedSessionId = nil;
        self.settingsAttemptedSessionId = nil;
        self.settingsAppliedGeneration = 0;
        self.settingsAttemptedGeneration = 0;
        [self invalidateVisualCachesLocked];
    }
    for (NSURLSessionTask *task in tasks) [task cancel];
    for (VNRequest *request in visionRequests) [request cancel];
    if (oldSession.length > 0) {
        [self requestCleanupPath:[NSString stringWithFormat:@"/session/%@", AutoWDAPathSegment(oldSession)]
                          method:@"DELETE" body:nil error:nil];
    }
}

- (NSURL *)requestURLForPath:(NSString *)path {
    NSString *relative = [path hasPrefix:@"/"] ? [path substringFromIndex:1] : path;
    if (relative.length == 0) return self.baseURL;
    return [NSURL URLWithString:relative relativeToURL:self.baseURL].absoluteURL;
}

- (id)requestPath:(NSString *)path
           method:(NSString *)method
             body:(NSDictionary *)body
             error:(NSError **)error {
    // NSError out parameters are autoreleasing. A method-local pool would
    // invalidate returned errors before the caller can retain them.
    {
    NSString *scheme = self.baseURL.scheme.lowercaseString;
    if (!self.baseURL || (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"])) {
        if (error) *error = AutoWDAError(AutoSDKErrorInvalidConfiguration, @"WDA baseURL must use http or https.");
        return nil;
    }
    NSURL *url = [self requestURLForPath:path];
    if (!url) {
        if (error) *error = AutoWDAError(AutoSDKErrorInvalidConfiguration, @"WDA request URL is invalid.");
        return nil;
    }
    NSURLSession *session = nil;
    NSTimeInterval requestTimeout = 0;
    NSUInteger cancellationGeneration = 0;
    cancellationGeneration = [self currentOperationCancellationGeneration];
    @synchronized (self.sessionLock) {
        requestTimeout = self.requestTimeout;
    }
    NSNumber *timeoutOverride = NSThread.currentThread.threadDictionary[self.operationCleanupTimeoutThreadKey];
    if ([timeoutOverride isKindOfClass:NSNumber.class] && timeoutOverride.doubleValue > 0) {
        requestTimeout = MIN(requestTimeout, timeoutOverride.doubleValue);
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url
                                                              cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                          timeoutInterval:requestTimeout];
    request.HTTPMethod = method.uppercaseString ?: @"GET";
    request.HTTPShouldHandleCookies = NO;
    if (body) {
        NSData *bodyData = nil;
        @try {
            bodyData = [NSJSONSerialization dataWithJSONObject:body options:0 error:error];
        } @catch (NSException *exception) {
            (void)exception;
            if (error) *error = AutoWDAError(AutoSDKErrorInvalidConfiguration,
                                             @"WDA request body is not valid JSON.");
            return nil;
        }
        if (!bodyData) return nil;
        if (bodyData.length > AutoWDAMaxHTTPRequestBytes) {
            if (error) *error = AutoWDAError(AutoSDKErrorInvalidConfiguration,
                                             @"WDA request body exceeds the 4 MB limit.");
            return nil;
        }
        request.HTTPBody = bodyData;
        [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    }

    NSUInteger maximumResponseBytes = AutoWDADefaultHTTPResponseBytes;
    if ([path hasSuffix:@"/screenshot"]) {
        maximumResponseBytes = AutoWDAMaxHTTPResponseBytes;
    } else if ([path hasSuffix:@"/source"]) {
        NSUInteger sourceBytes = 0;
        @synchronized (self.sessionLock) { sourceBytes = self.sourceMaxBytes; }
        maximumResponseBytes = MIN(AutoWDAMaxHTTPResponseBytes,
                                   sourceBytes * 2 + 1024 * 1024);
    }
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSData *responseData = nil;
    __block NSURLResponse *urlResponse = nil;
    __block NSError *requestError = nil;
    NSURLSessionDataTask *task = nil;
    __weak AutoWDAHTTPAdapter *weakSelf = self;
    __block __weak NSURLSessionDataTask *weakTask = nil;
    BOOL cancelledBeforeStart = NO;
    @synchronized (self.sessionLock) {
        cancelledBeforeStart = cancellationGeneration != self.operationCancellationGeneration;
        if (!cancelledBeforeStart) {
            session = self.URLSession;
            task = [session dataTaskWithRequest:request
                             completionHandler:^(NSData *data, NSURLResponse *response, NSError *requestErrorValue) {
                AutoWDAHTTPAdapter *strongSelf = weakSelf;
                NSURLSessionDataTask *completedTask = weakTask;
                if (strongSelf && completedTask) {
                    @synchronized (strongSelf.sessionLock) { [strongSelf.activeTasks removeObject:completedTask]; }
                }
                responseData = data;
                urlResponse = response;
                requestError = requestErrorValue;
                dispatch_semaphore_signal(semaphore);
            }];
            weakTask = task;
            [self.activeTasks addObject:task];
            [task resume];
        }
    }
    if (cancelledBeforeStart) {
        [task cancel];
        if (error) *error = AutoWDAError(AutoSDKErrorScriptCancelled, @"WDA request was cancelled before it started.");
        return nil;
    }
    NSTimeInterval waitSeconds = requestTimeout + MIN(1.0, MAX(0.1, requestTimeout * 0.1));
    NSTimeInterval deadline = NSProcessInfo.processInfo.systemUptime + waitSeconds;
    BOOL completed = NO, responseTooLarge = NO, operationCancelled = NO;
    while (!completed && NSProcessInfo.processInfo.systemUptime < deadline) {
        completed = dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC))) == 0;
        if (!completed && [self operationWasCancelledSinceGeneration:cancellationGeneration]) {
            operationCancelled = YES;
            [task cancel];
            break;
        }
        int64_t expectedBytes = task.countOfBytesExpectedToReceive;
        int64_t receivedBytes = task.countOfBytesReceived;
        if (!completed && ((expectedBytes > 0 && (uint64_t)expectedBytes > maximumResponseBytes) ||
                           (receivedBytes > 0 && (uint64_t)receivedBytes > maximumResponseBytes))) {
            responseTooLarge = YES;
            [task cancel];
            break;
        }
    }
    if (responseTooLarge) {
        if (error) *error = AutoWDAError(AutoSDKErrorAutomationFailed,
                                         @"WDA response exceeds the endpoint size limit.");
        return nil;
    }
    if (operationCancelled) {
        if (error) *error = AutoWDAError(AutoSDKErrorScriptCancelled, @"WDA request was cancelled.");
        return nil;
    }
    if (!completed) {
        [task cancel];
        if (error) *error = AutoWDAError(AutoSDKErrorAutomationFailed, [NSString stringWithFormat:@"WDA request timed out: %@", path]);
        return nil;
    }
    if (requestError) {
        if (requestError.code == NSURLErrorCancelled &&
            [self operationWasCancelledSinceGeneration:cancellationGeneration]) {
            if (error) *error = AutoWDAError(AutoSDKErrorScriptCancelled, @"WDA request was cancelled.");
            return nil;
        }
        if (error) *error = [NSError errorWithDomain:AutoSDKErrorDomain
                                                 code:AutoSDKErrorAutomationFailed
                                             userInfo:@{ NSLocalizedDescriptionKey: requestError.localizedDescription ?: @"Unable to reach WDA.",
                                                         NSUnderlyingErrorKey: requestError }];
        return nil;
    }
    if (responseData.length > maximumResponseBytes) {
        if (error) *error = AutoWDAError(AutoSDKErrorAutomationFailed,
                                         @"WDA response exceeds the endpoint size limit.");
        return nil;
    }
    NSInteger statusCode = [urlResponse isKindOfClass:NSHTTPURLResponse.class] ? [(NSHTTPURLResponse *)urlResponse statusCode] : 0;
    id parsed = nil;
    NSData *completedResponseData = responseData;
    responseData = nil;
    if (completedResponseData.length > 0) {
        parsed = [NSJSONSerialization JSONObjectWithData:completedResponseData options:NSJSONReadingFragmentsAllowed error:nil];
        if (!parsed) parsed = [[NSString alloc] initWithData:completedResponseData encoding:NSUTF8StringEncoding];
    }
    completedResponseData = nil;
    if (statusCode < 200 || statusCode >= 300) {
        NSString *message = nil;
        NSString *protocolError = nil;
        id value = AutoWDAResponseValue(parsed);
        if ([value isKindOfClass:NSDictionary.class]) {
            message = [value[@"message"] description];
            protocolError = [value[@"error"] description];
        }
        if (message.length == 0) message = [NSString stringWithFormat:@"WDA returned HTTP %ld for %@.", (long)statusCode, path];
        if (error) *error = AutoWDAResponseError(statusCode, protocolError, message);
        return nil;
    }
    id value = AutoWDAResponseValue(parsed);
    id protocolErrorValue = [value isKindOfClass:NSDictionary.class] ? value[@"error"] : nil;
    if (protocolErrorValue != nil && protocolErrorValue != NSNull.null) {
        NSString *message = [value[@"message"] description];
        if (message.length == 0) message = [protocolErrorValue description];
        if (error) *error = AutoWDAResponseError(statusCode, [protocolErrorValue description], message.length > 0 ? message : @"WDA rejected the request.");
        return nil;
    }
    return parsed;
    }
}

- (id)requestSessionSuffix:(NSString *)suffix
                    method:(NSString *)method
                      body:(NSDictionary *)body
                     error:(NSError **)error {
    return [self requestSessionSuffix:suffix method:method body:body usedSession:nil error:error];
}

- (id)requestSessionSuffix:(NSString *)suffix
                    method:(NSString *)method
                      body:(NSDictionary *)body
               usedSession:(NSString **)usedSession
                     error:(NSError **)error {
    NSUInteger operationGeneration = [self currentOperationCancellationGeneration];
    BOOL ownsCancellationContext = [self installCancellationContextForGeneration:operationGeneration];
    @try {
    if (usedSession) *usedSession = nil;
    if (![self ensureSession:error]) return nil;
    NSString *session = nil;
    @synchronized (self.sessionLock) { session = [self.sessionId copy]; }
    if (session.length == 0) {
        if (error) *error = AutoWDAError(AutoSDKErrorAutomationFailed, @"WDA session disappeared before the request started.");
        return nil;
    }
    NSString *encodedSession = AutoWDAPathSegment(session);
    NSString *normalizedSuffix = [suffix hasPrefix:@"/"] ? suffix : [@"/" stringByAppendingString:suffix ?: @""];
    NSError *firstError = nil;
    id result = [self requestPath:[NSString stringWithFormat:@"/session/%@%@", encodedSession, normalizedSuffix]
                           method:method body:body error:&firstError];
    if (!AutoWDAErrorIsInvalidSession(firstError)) {
        if (usedSession) *usedSession = session;
        if (firstError && error) *error = firstError;
        return result;
    }

    @synchronized (self.sessionLock) {
        if ([self.sessionId isEqualToString:session]) {
            self.sessionId = nil;
            self.sessionGeneration += 1;
            self.settingsAppliedSessionId = nil;
            self.settingsAttemptedSessionId = nil;
            self.settingsAppliedGeneration = 0;
            self.settingsAttemptedGeneration = 0;
            [self invalidateVisualCachesLocked];
        }
    }
    NSError *restartError = nil;
    if (![self ensureSession:&restartError]) {
        if (error) *error = restartError ?: firstError;
        return nil;
    }
    NSString *newSessionId = nil;
    @synchronized (self.sessionLock) { newSessionId = [self.sessionId copy]; }
    NSString *newSession = AutoWDAPathSegment(newSessionId);
    NSError *retryError = nil;
    result = [self requestPath:[NSString stringWithFormat:@"/session/%@%@", newSession, normalizedSuffix]
                        method:method body:body error:&retryError];
    if (usedSession) *usedSession = newSessionId;
    if (retryError && error) *error = retryError;
    return result;
    } @finally {
        if (ownsCancellationContext) [self clearCancellationContext];
    }
}

- (AutoWDACoordinateScale)coordinateScaleForImage:(CGImageRef)image {
    CGFloat fallback = UIScreen.mainScreen.scale > 0 ? UIScreen.mainScreen.scale : 1;
    if (!image) return AutoWDACoordinateScaleMake(fallback, fallback);
    CGSize cachedWindow = CGSizeZero;
    NSUInteger requestGeneration = 0;
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    @synchronized (self.sessionLock) {
        if (self.windowSizeCache.width > 0 && self.windowSizeCache.height > 0 &&
            now - self.windowSizeCacheTimestamp <= 2.0) cachedWindow = self.windowSizeCache;
        requestGeneration = self.windowSizeCacheGeneration;
    }
    CGFloat windowWidth = cachedWindow.width, windowHeight = cachedWindow.height;
    if (windowWidth <= 0 || windowHeight <= 0) {
        NSError *windowError = nil;
        id response = [self requestSessionSuffix:@"/window/size" method:@"GET" body:nil error:&windowError];
        id value = AutoWDAResponseValue(response);
        windowWidth = AutoWDADouble([value isKindOfClass:NSDictionary.class] ? value[@"width"] : nil, 0);
        windowHeight = AutoWDADouble([value isKindOfClass:NSDictionary.class] ? value[@"height"] : nil, 0);
        if (windowWidth > 0 && windowHeight > 0) {
            NSTimeInterval cacheTimestamp = NSProcessInfo.processInfo.systemUptime;
            @synchronized (self.sessionLock) {
                if (self.windowSizeCacheGeneration == requestGeneration) {
                    self.windowSizeCache = CGSizeMake(windowWidth, windowHeight);
                    self.windowSizeCacheTimestamp = cacheTimestamp;
                    self.windowSizeCacheGeneration += 1;
                }
            }
        }
    }
    CGFloat pixelWidth = CGImageGetWidth(image), pixelHeight = CGImageGetHeight(image);
    if (windowWidth > 0 && windowHeight > 0) {
        CGFloat scaleX = pixelWidth / windowWidth, scaleY = pixelHeight / windowHeight;
        if (isfinite(scaleX) && isfinite(scaleY) && scaleX > 0 && scaleY > 0) {
            return AutoWDACoordinateScaleMake(scaleX, scaleY);
        }
    }
    return AutoWDACoordinateScaleMake(fallback, fallback);
}

- (BOOL)startSession:(NSError **)error {
    NSUInteger operationGeneration = [self currentOperationCancellationGeneration];
    BOOL ownsCancellationContext = [self installCancellationContextForGeneration:operationGeneration];
    [self.sessionCreationLock lock];
    @try {
        if ([self operationWasCancelledSinceGeneration:operationGeneration]) {
            if (error) *error = AutoWDAError(AutoSDKErrorScriptCancelled, @"WDA session creation was cancelled.");
            return NO;
        }
        __block NSUInteger generation = 0;
        __block NSString *bundleId = nil;
        @synchronized (self.sessionLock) {
            if (self.sessionId.length > 0) return YES;
            generation = self.sessionGeneration;
            bundleId = [self.applicationBundleId copy];
        }
        if (bundleId.length > 255) {
            if (error) *error = AutoWDAError(AutoSDKErrorInvalidConfiguration,
                                             @"Application bundleId must contain at most 255 characters.");
            return NO;
        }
        NSMutableDictionary *alwaysMatch = [@{ @"platformName": @"iOS",
                                               @"appium:automationName": @"XCUITest" } mutableCopy];
        if (bundleId.length > 0) {
            alwaysMatch[@"appium:bundleId"] = bundleId;
            alwaysMatch[@"bundleId"] = bundleId;
        }
        NSDictionary *body = @{ @"capabilities": @{ @"alwaysMatch": alwaysMatch },
                                @"desiredCapabilities": alwaysMatch };
        id response = [self requestPath:@"/session" method:@"POST" body:body error:error];
        id value = AutoWDAResponseValue(response);
        id responseSession = [response isKindOfClass:NSDictionary.class] ? response[@"sessionId"] : nil;
        id valueSession = [value isKindOfClass:NSDictionary.class] ? value[@"sessionId"] : nil;
        id valueId = [value isKindOfClass:NSDictionary.class] ? value[@"id"] : nil;
        NSString *session = [responseSession isKindOfClass:NSString.class] ? responseSession : nil;
        if (session.length == 0 && [valueSession isKindOfClass:NSString.class]) session = valueSession;
        if (session.length == 0 && [valueId isKindOfClass:NSString.class]) session = valueId;
        if (session.length == 0 || session.length > AutoWDAMaxElementHandleLength) {
            if (error && !*error) *error = AutoWDAError(AutoSDKErrorAutomationFailed,
                                                        @"WDA did not return a valid bounded session id.");
            return NO;
        }
        BOOL accepted = NO;
        @synchronized (self.sessionLock) {
            accepted = generation == self.sessionGeneration && self.sessionId.length == 0;
            if (accepted) {
                self.sessionId = session;
                self.settingsAppliedSessionId = nil;
                self.settingsAttemptedSessionId = nil;
                self.settingsAppliedGeneration = 0;
                self.settingsAttemptedGeneration = 0;
                [self invalidateVisualCachesLocked];
            }
        }
        if (!accepted) {
            [self requestCleanupPath:[NSString stringWithFormat:@"/session/%@", AutoWDAPathSegment(session)]
                              method:@"DELETE" body:nil error:nil];
            if (error && !*error) *error = AutoWDAError(AutoSDKErrorAutomationFailed, @"WDA session creation was invalidated.");
            return NO;
        }
        NSError *settingsError = nil;
        if (![self applySessionSettingsForCurrentSession:&settingsError]) {
            BOOL ignoresUnsupported = NO;
            @synchronized (self.sessionLock) { ignoresUnsupported = _ignoresUnsupportedSessionSettings; }
            if (!ignoresUnsupported || settingsError.code == AutoSDKErrorScriptCancelled ||
                settingsError.code == AutoSDKErrorInvalidConfiguration) {
                if (error) *error = settingsError;
                [self invalidateSession];
                return NO;
            }
        }
        return YES;
    } @finally {
        [self.sessionCreationLock unlock];
        if (ownsCancellationContext) [self clearCancellationContext];
    }
}

- (void)invalidateSession {
    NSString *session = nil;
    @synchronized (self.sessionLock) {
        self.sessionGeneration += 1;
        session = self.sessionId;
        self.sessionId = nil;
        self.settingsAppliedSessionId = nil;
        self.settingsAttemptedSessionId = nil;
        self.settingsAppliedGeneration = 0;
        self.settingsAttemptedGeneration = 0;
        [self invalidateVisualCachesLocked];
    }
    if (session.length == 0) return;
    [self requestCleanupPath:[NSString stringWithFormat:@"/session/%@", AutoWDAPathSegment(session)]
                      method:@"DELETE" body:nil error:nil];
}

- (void)cancelCurrentOperations {
    NSArray<NSURLSessionTask *> *tasks = nil;
    NSArray<VNRequest *> *visionRequests = nil;
    @synchronized (self.sessionLock) {
        self.operationCancellationGeneration += 1;
        tasks = self.activeTasks.allObjects;
        visionRequests = self.activeVisionRequests.allObjects;
    }
    for (NSURLSessionTask *task in tasks) [task cancel];
    for (VNRequest *request in visionRequests) [request cancel];
}

- (BOOL)ensureSession:(NSError **)error {
    NSUInteger operationGeneration = [self currentOperationCancellationGeneration];
    BOOL ownsCancellationContext = [self installCancellationContextForGeneration:operationGeneration];
    @try {
    for (NSUInteger attempt = 0; attempt < 3; attempt++) {
        NSString *session = nil;
        NSDictionary *settings = nil;
        NSString *appliedSession = nil;
        NSString *attemptedSession = nil;
        NSUInteger settingsGeneration = 0;
        NSUInteger appliedGeneration = 0;
        NSUInteger attemptedGeneration = 0;
        BOOL ignoresUnsupported = NO;
        @synchronized (self.sessionLock) {
            session = [_sessionId copy];
            settings = [_sessionSettings copy];
            appliedSession = [self.settingsAppliedSessionId copy];
            attemptedSession = [self.settingsAttemptedSessionId copy];
            settingsGeneration = self.settingsGeneration;
            appliedGeneration = self.settingsAppliedGeneration;
            attemptedGeneration = self.settingsAttemptedGeneration;
            ignoresUnsupported = _ignoresUnsupportedSessionSettings;
        }
        if (session.length == 0) {
            if (![self startSession:error]) return NO;
            continue;
        }
        if (settings.count == 0 ||
            ([appliedSession isEqualToString:session] && appliedGeneration == settingsGeneration) ||
            (ignoresUnsupported && [attemptedSession isEqualToString:session] && attemptedGeneration == settingsGeneration)) return YES;
        NSError *settingsError = nil;
        if (![self applySessionSettingsForCurrentSession:&settingsError]) {
            BOOL ignoresFailureNow = NO;
            @synchronized (self.sessionLock) { ignoresFailureNow = _ignoresUnsupportedSessionSettings; }
            if (!ignoresFailureNow || settingsError.code == AutoSDKErrorScriptCancelled ||
                settingsError.code == AutoSDKErrorInvalidConfiguration) {
                if (error) *error = settingsError;
                return NO;
            }
        }
        return YES;
    }
    if (error) *error = AutoWDAError(AutoSDKErrorAutomationFailed, @"WDA session state changed repeatedly while it was being prepared.");
    return NO;
    } @finally {
        if (ownsCancellationContext) [self clearCancellationContext];
    }
}

- (BOOL)applySessionSettingsForCurrentSession:(NSError **)error {
    [self.settingsApplicationLock lock];
    @try {
        NSUInteger operationGeneration = [self currentOperationCancellationGeneration];
        if ([self operationWasCancelledSinceGeneration:operationGeneration]) {
            if (error) *error = AutoWDAError(AutoSDKErrorScriptCancelled, @"WDA session settings were cancelled.");
            return NO;
        }
        for (NSUInteger attempt = 0; attempt < 3; attempt++) {
            NSString *session = nil;
            NSDictionary *settings = nil;
            NSString *appliedSession = nil;
            NSUInteger generation = 0, appliedGeneration = 0;
            @synchronized (self.sessionLock) {
                session = [_sessionId copy];
                settings = [_sessionSettings copy];
                generation = self.settingsGeneration;
                appliedSession = [self.settingsAppliedSessionId copy];
                appliedGeneration = self.settingsAppliedGeneration;
            }
            if (session.length == 0) {
                if (error) *error = AutoWDAError(AutoSDKErrorAutomationFailed, @"WDA session changed while settings were being applied.");
                return NO;
            }
            if (settings.count == 0 ||
                ([appliedSession isEqualToString:session] && appliedGeneration == generation)) return YES;

            NSString *path = [NSString stringWithFormat:@"/session/%@/appium/settings", AutoWDAPathSegment(session)];
            NSError *requestError = nil;
            [self requestPath:path method:@"POST" body:@{ @"settings": settings } error:&requestError];
            if (!requestError && [self operationWasCancelledSinceGeneration:operationGeneration]) {
                requestError = AutoWDAError(AutoSDKErrorScriptCancelled, @"WDA session settings were cancelled.");
            }
            BOOL remembersAttempt = requestError == nil || AutoWDAErrorIsUnsupportedCommand(requestError);
            BOOL stateStillCurrent = NO;
            @synchronized (self.sessionLock) {
                stateStillCurrent = [_sessionId isEqualToString:session] && self.settingsGeneration == generation;
                if (stateStillCurrent) {
                    if (remembersAttempt) {
                        self.settingsAttemptedSessionId = session;
                        self.settingsAttemptedGeneration = generation;
                    } else if ([self.settingsAttemptedSessionId isEqualToString:session] &&
                               self.settingsAttemptedGeneration == generation) {
                        self.settingsAttemptedSessionId = nil;
                        self.settingsAttemptedGeneration = 0;
                    }
                    if (!requestError) {
                        self.settingsAppliedSessionId = session;
                        self.settingsAppliedGeneration = generation;
                    }
                }
            }
            if (!stateStillCurrent) continue;
            if (requestError) {
                if (error) *error = requestError;
                return NO;
            }
            return YES;
        }
        if (error) *error = AutoWDAError(AutoSDKErrorAutomationFailed, @"WDA session settings changed repeatedly while they were being applied.");
        return NO;
    } @finally {
        [self.settingsApplicationLock unlock];
    }
}

- (BOOL)applySessionSettings:(NSError **)error {
    NSUInteger operationGeneration = [self currentOperationCancellationGeneration];
    BOOL ownsCancellationContext = [self installCancellationContextForGeneration:operationGeneration];
    @try {
        if (![self ensureSession:error]) return NO;
        return [self applySessionSettingsForCurrentSession:error];
    } @finally {
        if (ownsCancellationContext) [self clearCancellationContext];
    }
}

- (NSDictionary *)locatorForSelector:(id)selector error:(NSError **)error {
    NSError *unwrapError = nil;
    selector = AutoWDAUnwrapSelector(selector, &unwrapError);
    if (unwrapError) {
        if (error) *error = unwrapError;
        return nil;
    }
    if ([selector isKindOfClass:NSString.class] && [(NSString *)selector length] > 0) return @{ @"using": @"accessibility id", @"value": selector };
    if (![selector isKindOfClass:NSDictionary.class]) {
        if (error) *error = AutoWDAError(AutoSDKErrorElementNotFound, @"WDA selector must be a string or object.");
        return nil;
    }
    NSDictionary *dictionary = selector;
    NSString *xpath = [dictionary[@"xpath"] isKindOfClass:NSString.class] ? dictionary[@"xpath"] : nil;
    NSString *predicate = [dictionary[@"predicate"] isKindOfClass:NSString.class] ? dictionary[@"predicate"] : nil;
    NSString *classChain = [dictionary[@"classChain"] isKindOfClass:NSString.class] ? dictionary[@"classChain"] : nil;
    if (xpath.length > 0) return @{ @"using": @"xpath", @"value": xpath };
    if (classChain.length > 0) return @{ @"using": @"-ios class chain", @"value": classChain };

    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (predicate.length > 0) [parts addObject:predicate];
    NSString *label = [dictionary[@"label"] isKindOfClass:NSString.class] ? dictionary[@"label"] : nil;
    NSString *value = [dictionary[@"value"] isKindOfClass:NSString.class] ? dictionary[@"value"] : nil;
    NSString *text = [dictionary[@"text"] isKindOfClass:NSString.class] ? dictionary[@"text"] : nil;
    NSString *type = [dictionary[@"type"] isKindOfClass:NSString.class] ? dictionary[@"type"] : nil;
    NSString *labelMatch = [dictionary[@"labelMatch"] isKindOfClass:NSString.class] ? dictionary[@"labelMatch"] : nil;
    NSString *identifier = [dictionary[@"id"] isKindOfClass:NSString.class] ? dictionary[@"id"] : nil;
    NSString *name = [dictionary[@"name"] isKindOfClass:NSString.class] ? dictionary[@"name"] : nil;
    NSString *nameMatch = [dictionary[@"nameMatch"] isKindOfClass:NSString.class] ? dictionary[@"nameMatch"] : nil;
    NSString *valueMatch = [dictionary[@"valueMatch"] isKindOfClass:NSString.class] ? dictionary[@"valueMatch"] : nil;
    NSString *textMatch = [dictionary[@"textMatch"] isKindOfClass:NSString.class] ? dictionary[@"textMatch"] : nil;
    NSString *typeMatch = [dictionary[@"typeMatch"] isKindOfClass:NSString.class] ? dictionary[@"typeMatch"] : nil;
    if (!labelMatch.length && [dictionary[@"labelRegex"] isKindOfClass:NSString.class]) labelMatch = dictionary[@"labelRegex"];
    if (!nameMatch.length && [dictionary[@"nameRegex"] isKindOfClass:NSString.class]) nameMatch = dictionary[@"nameRegex"];
    if (!valueMatch.length && [dictionary[@"valueRegex"] isKindOfClass:NSString.class]) valueMatch = dictionary[@"valueRegex"];
    if (!textMatch.length && [dictionary[@"textRegex"] isKindOfClass:NSString.class]) textMatch = dictionary[@"textRegex"];
    if (!typeMatch.length && [dictionary[@"typeRegex"] isKindOfClass:NSString.class]) typeMatch = dictionary[@"typeRegex"];
    if (identifier.length > 0) [parts addObject:[NSString stringWithFormat:@"name == \"%@\"", AutoWDAPredicateEscape(identifier)]];
    if (name.length > 0) [parts addObject:[NSString stringWithFormat:@"name == \"%@\"", AutoWDAPredicateEscape(name)]];
    if (label.length > 0) [parts addObject:[NSString stringWithFormat:@"label == \"%@\"", AutoWDAPredicateEscape(label)]];
    if (value.length > 0) [parts addObject:[NSString stringWithFormat:@"value == \"%@\"", AutoWDAPredicateEscape(value)]];
    if (text.length > 0) [parts addObject:[NSString stringWithFormat:@"(label == \"%@\" OR value == \"%@\")", AutoWDAPredicateEscape(text), AutoWDAPredicateEscape(text)]];
    if (type.length > 0) [parts addObject:[NSString stringWithFormat:@"type == \"%@\"", AutoWDAPredicateEscape(AutoWDAElementType(type))]];
    if (labelMatch.length > 0) [parts addObject:[NSString stringWithFormat:@"label MATCHES \"%@\"", AutoWDAPredicateEscape(labelMatch)]];
    if (nameMatch.length > 0) [parts addObject:[NSString stringWithFormat:@"name MATCHES \"%@\"", AutoWDAPredicateEscape(nameMatch)]];
    if (valueMatch.length > 0) [parts addObject:[NSString stringWithFormat:@"value MATCHES \"%@\"", AutoWDAPredicateEscape(valueMatch)]];
    if (textMatch.length > 0) [parts addObject:[NSString stringWithFormat:@"(label MATCHES \"%@\" OR value MATCHES \"%@\")", AutoWDAPredicateEscape(textMatch), AutoWDAPredicateEscape(textMatch)]];
    if (typeMatch.length > 0) [parts addObject:[NSString stringWithFormat:@"type MATCHES \"%@\"", AutoWDAPredicateEscape(typeMatch)]];
    if ([dictionary[@"visible"] isKindOfClass:NSNumber.class]) [parts addObject:[dictionary[@"visible"] boolValue] ? @"visible == 1" : @"visible == 0"];
    if ([dictionary[@"enabled"] isKindOfClass:NSNumber.class]) [parts addObject:[dictionary[@"enabled"] boolValue] ? @"enabled == 1" : @"enabled == 0"];
    if ([dictionary[@"selected"] isKindOfClass:NSNumber.class]) [parts addObject:[dictionary[@"selected"] boolValue] ? @"selected == 1" : @"selected == 0"];
    if ([dictionary[@"accessible"] isKindOfClass:NSNumber.class]) [parts addObject:[dictionary[@"accessible"] boolValue] ? @"accessible == 1" : @"accessible == 0"];
    if (parts.count == 0) {
        if (error) *error = AutoWDAError(AutoSDKErrorElementNotFound, @"WDA selector does not contain a supported field.");
        return nil;
    }
    return @{ @"using": @"-ios predicate string", @"value": [parts componentsJoinedByString:@" AND "] };
}

- (NSDictionary *)elementPayloadForSelector:(id)selector error:(NSError **)error {
    if ([selector isKindOfClass:NSDictionary.class]) {
        NSString *elementId = AutoWDAElementIdFromValue(selector);
        if (elementId.length > 0) {
            if (![self ensureSession:error]) return nil;
            NSString *currentSession = nil;
            @synchronized (self.sessionLock) { currentSession = [self.sessionId copy]; }
            NSString *handleSession = [selector[@"sessionId"] isKindOfClass:NSString.class] ? selector[@"sessionId"] : nil;
            NSError *unwrapError = nil;
            id recoverySelector = selector[@"selector"] != nil
                ? AutoWDAUnwrapSelector(selector, &unwrapError)
                : selector;
            if (unwrapError) {
                if (error) *error = unwrapError;
                return nil;
            }
            if (handleSession.length == 0 || [handleSession isEqualToString:currentSession]) {
                return @{ @"elementId": elementId, @"selector": recoverySelector,
                          @"sessionId": handleSession ?: currentSession ?: @"" };
            }
            if (selector[@"selector"] == nil) {
                if (error) *error = AutoWDAError(AutoSDKErrorElementNotFound, @"The WDA element handle belongs to an expired session and has no recovery selector.");
                return nil;
            }
            selector = recoverySelector;
        }
    }
    NSError *unwrapError = nil;
    selector = AutoWDAUnwrapSelector(selector, &unwrapError);
    if (unwrapError) {
        if (error) *error = unwrapError;
        return nil;
    }
    NSDictionary *locator = [self locatorForSelector:selector error:error];
    if (!locator) return nil;
    NSString *elementSession = nil;
    id response = [self requestSessionSuffix:@"/element" method:@"POST" body:locator usedSession:&elementSession error:error];
    id value = AutoWDAResponseValue(response);
    NSString *elementId = AutoWDAElementIdFromValue(value);
    if (elementId.length == 0) {
        if (error && !*error) *error = AutoWDAError(AutoSDKErrorElementNotFound, @"WDA could not find the element.");
        return nil;
    }
    return @{ @"elementId": elementId, @"selector": selector ?: [NSNull null],
              @"sessionId": elementSession ?: @"" };
}

- (NSString *)elementPath:(NSString *)elementId session:(NSString *)sessionId suffix:(NSString *)suffix {
    NSString *encoded = AutoWDAPathSegment(elementId);
    NSString *session = AutoWDAPathSegment(sessionId);
    return [NSString stringWithFormat:@"/session/%@/element/%@%@", session, encoded, suffix ?: @""];
}

- (id)requestElementSelector:(id)selector
                      suffix:(NSString *)suffix
                      method:(NSString *)method
                        body:(NSDictionary *)body
                wdaNamespace:(BOOL)wdaNamespace
                       error:(NSError **)error {
    NSUInteger operationGeneration = [self currentOperationCancellationGeneration];
    BOOL ownsCancellationContext = [self installCancellationContextForGeneration:operationGeneration];
    @try {
    NSDictionary *payload = [self elementPayloadForSelector:selector error:error];
    if (!payload) return nil;
    NSString *(^pathForPayload)(NSDictionary *) = ^NSString *(NSDictionary *item) {
        NSString *path = [self elementPath:item[@"elementId"] session:item[@"sessionId"] suffix:suffix];
        return wdaNamespace ? [path stringByReplacingOccurrencesOfString:@"/element/" withString:@"/wda/element/"] : path;
    };
    NSString *session = payload[@"sessionId"];
    NSError *firstError = nil;
    id result = [self requestPath:pathForPayload(payload) method:method body:body error:&firstError];
    id recoverySelector = payload[@"selector"];
    if (AutoWDAErrorIsStaleElement(firstError) && recoverySelector != nil && recoverySelector != NSNull.null &&
        AutoWDAElementIdFromValue(recoverySelector).length == 0) {
        NSError *lookupError = nil;
        NSDictionary *freshPayload = [self elementPayloadForSelector:recoverySelector error:&lookupError];
        if (!freshPayload) {
            if (error) *error = lookupError ?: firstError;
            return nil;
        }
        NSError *retryError = nil;
        result = [self requestPath:pathForPayload(freshPayload) method:method body:body error:&retryError];
        if (retryError && error) *error = retryError;
        return result;
    }
    if (!AutoWDAErrorIsInvalidSession(firstError)) {
        if (firstError && error) *error = firstError;
        return result;
    }

    @synchronized (self.sessionLock) {
        if ([self.sessionId isEqualToString:session]) {
            self.sessionId = nil;
            self.sessionGeneration += 1;
            self.settingsAppliedSessionId = nil;
            self.settingsAttemptedSessionId = nil;
            self.settingsAppliedGeneration = 0;
            self.settingsAttemptedGeneration = 0;
            [self invalidateVisualCachesLocked];
        }
    }
    NSError *restartError = nil;
    if (![self startSession:&restartError]) {
        if (error) *error = restartError ?: firstError;
        return nil;
    }
    NSError *lookupError = nil;
    NSDictionary *newPayload = [self elementPayloadForSelector:payload[@"selector"] error:&lookupError];
    if (!newPayload) {
        if (error) *error = lookupError ?: firstError;
        return nil;
    }
    NSError *retryError = nil;
    result = [self requestPath:pathForPayload(newPayload) method:method body:body error:&retryError];
    if (retryError && error) *error = retryError;
    return result;
    } @finally {
        if (ownsCancellationContext) [self clearCancellationContext];
    }
}

- (BOOL)performTouchActions:(NSArray<NSDictionary *> *)actions error:(NSError **)error {
    NSDictionary *body = @{ @"actions": @[@{ @"type": @"pointer", @"id": @"autosdk-finger", @"parameters": @{ @"pointerType": @"touch" }, @"actions": actions ?: @[] }] };
    NSError *requestError = nil;
    [self requestSessionSuffix:@"/actions" method:@"POST" body:body error:&requestError];
    if (requestError && error) *error = requestError;
    if (!requestError) [self invalidateVisualCaches];
    return requestError == nil;
}

- (BOOL)performMultiTouch:(NSArray<NSArray<NSDictionary *> *> *)fingers error:(NSError **)error {
    if (![fingers isKindOfClass:NSArray.class] || fingers.count == 0) {
        if (error) *error = AutoWDAError(AutoSDKErrorInvalidConfiguration, @"performMultiTouch requires at least one finger track.");
        return NO;
    }
    if (fingers.count > 10) {
        if (error) *error = AutoWDAError(AutoSDKErrorInvalidConfiguration, @"performMultiTouch accepts at most 10 fingers.");
        return NO;
    }
    NSMutableArray *sources = [NSMutableArray arrayWithCapacity:fingers.count];
    [fingers enumerateObjectsUsingBlock:^(NSArray *track, NSUInteger index, BOOL *stop) {
        [sources addObject:@{
            @"type": @"pointer",
            @"id": [NSString stringWithFormat:@"autosdk-finger-%lu", (unsigned long)index],
            @"parameters": @{ @"pointerType": @"touch" },
            @"actions": [track isKindOfClass:NSArray.class] ? track : @[]
        }];
    }];
    NSDictionary *body = @{ @"actions": sources };
    NSError *requestError = nil;
    [self requestSessionSuffix:@"/actions" method:@"POST" body:body error:&requestError];
    if (requestError && error) *error = requestError;
    if (!requestError) [self invalidateVisualCaches];
    return requestError == nil;
}
- (NSDictionary *)elementInfoFromPayload:(NSDictionary *)payload {
    NSString *elementId = payload[@"elementId"];
    id selector = payload[@"selector"] ?: [NSNull null];
    NSMutableDictionary *info = [@{ @"handle": elementId ?: @"", @"elementId": elementId ?: @"", @"wdElementId": elementId ?: @"",
                                     @"sessionId": payload[@"sessionId"] ?: @"", @"selector": selector } mutableCopy];
    if ([selector isKindOfClass:NSDictionary.class]) {
        for (NSString *key in @[@"id", @"label", @"type", @"value", @"xpath", @"predicate"]) if (selector[key] != nil) info[key] = selector[key];
    }
    return info;
}

- (BOOL)click:(id)selector error:(NSError **)error {
    NSError *requestError = nil;
    [self requestElementSelector:selector suffix:@"/click" method:@"POST" body:@{} wdaNamespace:NO error:&requestError];
    if (requestError && error) *error = requestError;
    if (!requestError) [self invalidateVisualCaches];
    return requestError == nil;
}

- (BOOL)longClick:(id)selector duration:(NSTimeInterval)duration error:(NSError **)error {
    if (!isfinite(duration)) {
        if (error) *error = AutoWDAError(AutoSDKErrorInvalidConfiguration, @"Long-click duration must be finite.");
        return NO;
    }
    NSUInteger operationGeneration = [self currentOperationCancellationGeneration];
    BOOL ownsCancellationContext = [self installCancellationContextForGeneration:operationGeneration];
    @try {
    NSDictionary *bounds = [self boundsForSelector:selector error:error];
    if (!bounds) return NO;
    CGFloat x = [bounds[@"centerX"] doubleValue], y = [bounds[@"centerY"] doubleValue];
    return [self performTouchActions:@[@{ @"type": @"pointerMove", @"duration": @0, @"x": @(x), @"y": @(y) },
                                      @{ @"type": @"pointerDown", @"button": @0 },
                                      @{ @"type": @"pause", @"duration": @(MIN(60.0, MAX(0.1, duration)) * 1000) },
                                      @{ @"type": @"pointerUp", @"button": @0 }] error:error];
    } @finally {
        if (ownsCancellationContext) [self clearCancellationContext];
    }
}

- (BOOL)swipeFromX:(CGFloat)x1 y:(CGFloat)y1 toX:(CGFloat)x2 y:(CGFloat)y2 duration:(NSTimeInterval)duration error:(NSError **)error {
    if (!isfinite(x1) || !isfinite(y1) || !isfinite(x2) || !isfinite(y2) || !isfinite(duration)) {
        if (error) *error = AutoWDAError(AutoSDKErrorInvalidConfiguration, @"Swipe coordinates and duration must be finite.");
        return NO;
    }
    return [self performTouchActions:@[@{ @"type": @"pointerMove", @"duration": @0, @"x": @(x1), @"y": @(y1) },
                                      @{ @"type": @"pointerDown", @"button": @0 },
                                      @{ @"type": @"pointerMove", @"duration": @(MIN(60.0, MAX(0, duration)) * 1000), @"x": @(x2), @"y": @(y2) },
                                      @{ @"type": @"pointerUp", @"button": @0 }] error:error];
}

- (BOOL)input:(id)selector text:(NSString *)text error:(NSError **)error {
    NSString *inputText = [text isKindOfClass:NSString.class] ? text : @"";
    if ([inputText lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > AutoWDAMaxInputTextBytes) {
        if (error) *error = AutoWDAError(AutoSDKErrorInvalidConfiguration,
                                         @"WDA text input exceeds the 1 MB UTF-8 limit.");
        return NO;
    }
    NSUInteger operationGeneration = [self currentOperationCancellationGeneration];
    BOOL ownsCancellationContext = [self installCancellationContextForGeneration:operationGeneration];
    @try {
    NSError *requestError = nil;
    [self requestElementSelector:selector suffix:@"/click" method:@"POST" body:@{} wdaNamespace:NO error:&requestError];
    if (requestError) { if (error) *error = requestError; return NO; }
    [self invalidateVisualCaches];
    [self requestElementSelector:selector suffix:@"/value" method:@"POST"
                            body:@{ @"value": @[inputText], @"text": inputText }
                    wdaNamespace:NO error:&requestError];
    if (requestError && error) *error = requestError;
    if (!requestError) [self invalidateVisualCaches];
    return requestError == nil;
    } @finally {
        if (ownsCancellationContext) [self clearCancellationContext];
    }
}

- (NSString *)textForSelector:(id)selector error:(NSError **)error {
    id response = [self requestElementSelector:selector suffix:@"/text" method:@"GET" body:nil wdaNamespace:NO error:error];
    id value = AutoWDAResponseValue(response);
    return [value isKindOfClass:NSString.class] ? value : [value description];
}

- (NSData *)screenshotWithError:(NSError **)error {
    NSUInteger operationGeneration = [self currentOperationCancellationGeneration];
    BOOL ownsCancellationContext = [self installCancellationContextForGeneration:operationGeneration];
    [self.visualOperationLock lock];
    @try {
    if ([self operationWasCancelledSinceGeneration:operationGeneration]) {
        if (error) *error = AutoWDAError(AutoSDKErrorScriptCancelled, @"Screenshot was cancelled.");
        return nil;
    }
    [self.screenshotRequestLock lock];
    @try {
    {
        NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
        __block NSUInteger requestGeneration = 0;
        __block NSTimeInterval duration = 0;
        @synchronized (self.sessionLock) {
            if (operationGeneration != self.operationCancellationGeneration) {
                if (error) *error = AutoWDAError(AutoSDKErrorScriptCancelled, @"Screenshot was cancelled.");
                return nil;
            }
            duration = self.screenshotCacheDuration;
            if (self.screenshotCacheDuration > 0 && self.screenshotCacheData &&
                now - self.screenshotCacheTimestamp <= self.screenshotCacheDuration) {
                return self.screenshotCacheData;
            }
            requestGeneration = self.screenshotCacheGeneration;
        }
        id response = [self requestSessionSuffix:@"/screenshot" method:@"GET" body:nil error:error];
        id value = AutoWDAResponseValue(response);
        if (![value isKindOfClass:NSString.class]) {
            if (error && !*error) *error = AutoWDAError(AutoSDKErrorAutomationFailed, @"WDA screenshot response is not base64.");
            return nil;
        }
        NSUInteger encodedLength = [(NSString *)value lengthOfBytesUsingEncoding:NSASCIIStringEncoding];
        NSUInteger maximumEncodedLength = (AutoWDAMaxScreenshotBytes / 3) * 4 + 4;
        if (encodedLength > maximumEncodedLength) {
            if (error) *error = AutoWDAError(AutoSDKErrorAutomationFailed, @"WDA screenshot exceeds the 24 MB decoded limit.");
            return nil;
        }
        NSData *data = [[NSData alloc] initWithBase64EncodedString:value options:0];
        if (!data || data.length > AutoWDAMaxScreenshotBytes) {
            if (error) *error = AutoWDAError(AutoSDKErrorAutomationFailed, @"WDA returned invalid screenshot data.");
            return nil;
        }
        response = nil;
        value = nil;
        NSUInteger generation = 0;
        BOOL cancelledAfterDecode = NO;
        NSTimeInterval cacheTimestamp = NSProcessInfo.processInfo.systemUptime;
        @synchronized (self.sessionLock) {
            cancelledAfterDecode = operationGeneration != self.operationCancellationGeneration;
            if (!cancelledAfterDecode && duration > 0) {
                if (self.screenshotCacheGeneration == requestGeneration) {
                    self.screenshotCacheData = data;
                    self.screenshotCacheTimestamp = cacheTimestamp;
                    generation = ++self.screenshotCacheGeneration;
                }
            }
        }
        if (cancelledAfterDecode) {
            if (error) *error = AutoWDAError(AutoSDKErrorScriptCancelled, @"Screenshot decoding was cancelled.");
            return nil;
        }
        if (generation > 0) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)),
                           dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                @synchronized (self.sessionLock) {
                    if (self.screenshotCacheGeneration == generation) {
                        self.screenshotCacheData = nil;
                        self.screenshotCacheTimestamp = 0;
                    }
                }
            });
        }
        return data;
    }
    } @finally {
        [self.screenshotRequestLock unlock];
    }
    } @finally {
        if (ownsCancellationContext) [self clearCancellationContext];
        [self.visualOperationLock unlock];
    }
}

- (NSDictionary *)findImageAtPath:(NSString *)templatePath options:(NSDictionary *)options error:(NSError **)error {
    NSUInteger operationGeneration = [self currentOperationCancellationGeneration];
    BOOL ownsCancellationContext = [self installCancellationContextForGeneration:operationGeneration];
    [self.visualOperationLock lock];
    @try {
    {
    if ([self operationWasCancelledSinceGeneration:operationGeneration]) {
        if (error) *error = AutoWDAError(AutoSDKErrorScriptCancelled, @"Image search was cancelled.");
        return nil;
    }
    if (![templatePath isKindOfClass:NSString.class] || templatePath.length == 0 || templatePath.length > 4096) {
        if (error) *error = AutoWDAError(AutoSDKErrorInvalidConfiguration,
                                         @"Image template paths must contain 1 to 4096 characters.");
        return nil;
    }
    NSString *path = templatePath;
    UIImage *template = AutoWDATemplateImage(path);
    NSData *screenshot = [self screenshotWithError:error];
    UIImage *screenImage = screenshot ? [UIImage imageWithData:screenshot] : nil;
    if (!template || !screenImage) {
        if (error && !*error) *error = AutoWDAError(AutoSDKErrorFileOperationFailed, [NSString stringWithFormat:@"Unable to load image template: %@", templatePath ?: @""]);
        return nil;
    }
    CGImageRef templateCGImage = template.CGImage;
    CGImageRef screenCGImage = screenImage.CGImage;
    if (!templateCGImage || !screenCGImage) {
        if (error && !*error) *error = AutoWDAError(AutoSDKErrorAutomationFailed, @"Unable to decode image matching inputs.");
        return nil;
    }
    AutoWDACoordinateScale scale = [self coordinateScaleForImage:screenCGImage];
    NSDictionary *searchRegion = [options[@"region"] isKindOfClass:NSDictionary.class] ? options[@"region"] : @{};
    CGRect search = AutoWDAPixelRegion(searchRegion, scale, CGImageGetWidth(screenCGImage), CGImageGetHeight(screenCGImage));
    if (CGRectIsNull(search) || CGRectIsEmpty(search)) return @{ @"found": @NO };
    NSUInteger searchMinX = (NSUInteger)floor(CGRectGetMinX(search));
    NSUInteger searchMinY = (NSUInteger)floor(CGRectGetMinY(search));
    NSUInteger searchMaxX = (NSUInteger)ceil(CGRectGetMaxX(search));
    NSUInteger searchMaxY = (NSUInteger)ceil(CGRectGetMaxY(search));
    size_t searchWidth = searchMaxX - searchMinX, searchHeight = searchMaxY - searchMinY;
    size_t templateWidth = CGImageGetWidth(templateCGImage), templateHeight = CGImageGetHeight(templateCGImage);
    if (templateWidth > searchWidth || templateHeight > searchHeight) return @{ @"found": @NO };
    size_t needleByteCount = 0, haystackByteCount = 0;
    if (!AutoWDAPixelByteCount(templateWidth, templateHeight, &needleByteCount) ||
        !AutoWDAPixelByteCount(searchWidth, searchHeight, &haystackByteCount) ||
        needleByteCount > AutoWDAMaxPixelBufferBytes ||
        haystackByteCount > AutoWDAMaxPixelBufferBytes - needleByteCount) {
        if (error) *error = AutoWDAError(AutoSDKErrorAutomationFailed, @"Image matching exceeds the 64 MB combined pixel-buffer limit.");
        return nil;
    }
    NSUInteger haystackOriginX = 0, haystackOriginY = 0;
    AutoWDAPixelImage needle = AutoWDAPixelImageMake(templateCGImage);
    AutoWDAPixelImage haystack = AutoWDAPixelImageMakeRegion(screenCGImage, search, &haystackOriginX, &haystackOriginY);
    if (!needle.bytes || !haystack.bytes || needle.width > haystack.width || needle.height > haystack.height) {
        BOOL allocationFailed = !needle.bytes || !haystack.bytes;
        AutoWDAPixelImageDestroy(&needle);
        AutoWDAPixelImageDestroy(&haystack);
        if (allocationFailed && error) *error = AutoWDAError(AutoSDKErrorAutomationFailed, @"Unable to allocate image matching buffers.");
        return allocationFailed ? nil : @{ @"found": @NO };
    }
    CGFloat threshold = AutoWDADouble(options[@"threshold"], 0);
    if (threshold <= 0 || threshold > 1) threshold = 0.92;
    NSUInteger step = MIN((NSUInteger)1024, MAX((NSUInteger)1, AutoWDAUnsigned(options[@"step"], 1)));
    NSUInteger requestedStep = step;
    NSUInteger sampleX = MAX(1, needle.width / 16);
    NSUInteger sampleY = MAX(1, needle.height / 16);
    NSUInteger minX = 0, minY = 0;
    NSUInteger maxX = haystack.width >= needle.width ? haystack.width - needle.width + 1 : 0;
    NSUInteger maxY = haystack.height >= needle.height ? haystack.height - needle.height + 1 : 0;
    NSUInteger candidateWidth = maxX, candidateHeight = maxY;
    NSUInteger maxCandidates = MIN(5000000, MAX(1000, AutoWDAUnsigned(options[@"maxCandidates"], 200000)));
    NSUInteger verificationLimit = MIN((NSUInteger)4096, MAX((NSUInteger)32, maxCandidates / 4));
    NSUInteger coarseLimit = MAX((NSUInteger)1, maxCandidates - verificationLimit);
    step = AutoWDAAdaptedScanStep(candidateWidth, candidateHeight, step, coarseLimit);
    NSDictionary *result = nil;
    NSUInteger verifyStep = MIN(AutoWDAUnsigned(options[@"verifyStep"], 1), MAX(1, MIN(needle.width, needle.height)));
    CGFloat coarseThreshold = MAX(0, threshold - 0.15);
    NSUInteger maxComparedPixels = AutoWDAUnsigned(options[@"maxComparedPixels"], 50000000);
    maxComparedPixels = MIN((NSUInteger)500000000, MAX((NSUInteger)100000, maxComparedPixels));
    NSUInteger coarsePixelCost = ((needle.width + sampleX - 1) / sampleX) * ((needle.height + sampleY - 1) / sampleY);
    NSUInteger verificationPixelCost = ((needle.width + verifyStep - 1) / verifyStep) * ((needle.height + verifyStep - 1) / verifyStep);
    NSUInteger comparedPixelBudget = 0;
    NSUInteger coarseCandidates = 0, verifiedCandidates = 0;
    BOOL truncated = NO, cancelled = NO;
    BOOL (^shouldCancelSimilarity)(void) = ^BOOL{
        return [self operationWasCancelledSinceGeneration:operationGeneration];
    };
    for (NSUInteger y = minY; y < maxY && !result && !truncated && !cancelled; y += MAX(1, step)) {
        if ([self operationWasCancelledSinceGeneration:operationGeneration]) { cancelled = YES; break; }
        for (NSUInteger x = minX; x < maxX && !result; x += MAX(1, step)) {
            if (coarseCandidates >= coarseLimit) { truncated = YES; break; }
            if (coarsePixelCost > maxComparedPixels - MIN(comparedPixelBudget, maxComparedPixels)) { truncated = YES; break; }
            coarseCandidates += 1;
            comparedPixelBudget += coarsePixelCost;
            BOOL similarityCancelled = NO;
            CGFloat coarseSimilarity = AutoWDAImageSimilarity(needle, haystack, x, y, sampleX, sampleY,
                                                               coarseThreshold, shouldCancelSimilarity,
                                                               &similarityCancelled);
            if (similarityCancelled) { cancelled = YES; break; }
            if (coarseSimilarity < coarseThreshold) continue;
            NSUInteger refineMinX = x >= step - 1 ? MAX(minX, x - (step - 1)) : minX;
            NSUInteger refineMinY = y >= step - 1 ? MAX(minY, y - (step - 1)) : minY;
            NSUInteger refineMaxX = MIN(maxX, x + MAX(1, step));
            NSUInteger refineMaxY = MIN(maxY, y + MAX(1, step));
            for (NSUInteger candidateY = refineMinY; candidateY < refineMaxY && !result; candidateY++) {
                if ([self operationWasCancelledSinceGeneration:operationGeneration]) { cancelled = YES; break; }
                for (NSUInteger candidateX = refineMinX; candidateX < refineMaxX && !result; candidateX++) {
                    if (verifiedCandidates >= verificationLimit) { truncated = YES; break; }
                    if (verificationPixelCost > maxComparedPixels - MIN(comparedPixelBudget, maxComparedPixels)) { truncated = YES; break; }
                    verifiedCandidates += 1;
                    comparedPixelBudget += verificationPixelCost;
                    BOOL similarityCancelled = NO;
                    CGFloat similarity = AutoWDAImageSimilarity(needle, haystack, candidateX, candidateY,
                                                                 verifyStep, verifyStep, threshold,
                                                                 shouldCancelSimilarity, &similarityCancelled);
                    if (similarityCancelled) { cancelled = YES; break; }
                    if (similarity >= threshold) {
                        NSMutableDictionary *match = [AutoWDAMatchResult(candidateX + haystackOriginX,
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
    AutoWDAPixelImageDestroy(&needle);
    AutoWDAPixelImageDestroy(&haystack);
    if (cancelled || [self operationWasCancelledSinceGeneration:operationGeneration]) {
        if (error) *error = AutoWDAError(AutoSDKErrorScriptCancelled, @"Image search was cancelled.");
        return nil;
    }
    return result ?: @{ @"found": @NO, @"truncated": @(truncated),
                        @"coarseCandidates": @(coarseCandidates),
                        @"verifiedCandidates": @(verifiedCandidates),
                        @"comparedPixelBudget": @(comparedPixelBudget) };
    }
    } @finally {
        if (ownsCancellationContext) [self clearCancellationContext];
        [self.visualOperationLock unlock];
    }
}

- (NSArray<NSDictionary *> *)ocrInRegion:(NSDictionary *)region error:(NSError **)error {
    NSUInteger operationGeneration = [self currentOperationCancellationGeneration];
    BOOL ownsCancellationContext = [self installCancellationContextForGeneration:operationGeneration];
    [self.visualOperationLock lock];
    @try {
    {
    if ([self operationWasCancelledSinceGeneration:operationGeneration]) {
        if (error) *error = AutoWDAError(AutoSDKErrorScriptCancelled, @"OCR was cancelled.");
        return nil;
    }
    NSData *png = [self screenshotWithError:error];
    UIImage *image = png ? [UIImage imageWithData:png] : nil;
    CGImageRef sourceImage = image.CGImage;
    if (!sourceImage) {
        if (error && !*error) *error = AutoWDAError(AutoSDKErrorAutomationFailed, @"Unable to create OCR image.");
        return nil;
    }
    region = [region isKindOfClass:NSDictionary.class] ? region : @{};
    AutoWDACoordinateScale scale = [self coordinateScaleForImage:sourceImage];
    CGRect cropPixels = CGRectMake(0, 0, CGImageGetWidth(sourceImage), CGImageGetHeight(sourceImage));
    CGImageRef requestImage = sourceImage;
    CGImageRef croppedImage = NULL;
    if (region[@"width"] != nil || region[@"height"] != nil) {
        CGRect crop = AutoWDAPixelRegion(region, scale, CGImageGetWidth(sourceImage), CGImageGetHeight(sourceImage));
        if (CGRectIsNull(crop) || CGRectIsEmpty(crop)) {
            if (error) *error = AutoWDAError(AutoSDKErrorAutomationFailed, @"OCR region does not intersect the screenshot.");
            return nil;
        }
        cropPixels = crop;
        croppedImage = CGImageCreateWithImageInRect(sourceImage, crop);
        if (!croppedImage) {
            if (error) *error = AutoWDAError(AutoSDKErrorAutomationFailed, @"Unable to crop the OCR image.");
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
         requestWidthPixels * requestHeightPixels * 4 > AutoWDAMaxPixelBufferBytes);
    if (requestWidthPixels == 0 || requestHeightPixels == 0 || imageTooLarge) {
        if (croppedImage) CGImageRelease(croppedImage);
        if (error) *error = AutoWDAError(AutoSDKErrorAutomationFailed, @"OCR image exceeds the 64 MB pixel limit.");
        return nil;
    }
    VNRecognizeTextRequest *request = [VNRecognizeTextRequest new];
    NSString *mode = [region[@"mode"] isKindOfClass:NSString.class] ? [region[@"mode"] lowercaseString] : @"";
    BOOL accurate = [mode isEqualToString:@"fast"] ? NO :
                    ([mode isEqualToString:@"accurate"] ? YES :
                     ([region[@"accurate"] respondsToSelector:@selector(boolValue)] ? [region[@"accurate"] boolValue] : YES));
    request.recognitionLevel = accurate ? VNRequestTextRecognitionLevelAccurate : VNRequestTextRecognitionLevelFast;
    BOOL hasLanguageCorrection = region[@"languageCorrection"] != nil;
    request.usesLanguageCorrection = hasLanguageCorrection
        ? ([region[@"languageCorrection"] respondsToSelector:@selector(boolValue)] ? [region[@"languageCorrection"] boolValue] : accurate)
        : accurate;
    if ([region[@"languages"] isKindOfClass:NSArray.class]) {
        NSMutableArray<NSString *> *languages = [NSMutableArray array];
        for (id language in region[@"languages"]) {
            if ([language isKindOfClass:NSString.class] && [(NSString *)language length] > 0 && [(NSString *)language length] <= 32) [languages addObject:language];
            if (languages.count >= 8) break;
        }
        if (languages.count > 0) request.recognitionLanguages = languages;
    }
    if ([region[@"customWords"] isKindOfClass:NSArray.class]) {
        NSMutableArray<NSString *> *customWords = [NSMutableArray array];
        for (id word in region[@"customWords"]) {
            if ([word isKindOfClass:NSString.class] && [(NSString *)word length] > 0 && [(NSString *)word length] <= 256) [customWords addObject:word];
            if (customWords.count >= 100) break;
        }
        if (customWords.count > 0) request.customWords = customWords;
    }
    CGFloat minimumTextHeight = AutoWDADouble(region[@"minimumTextHeight"], 0);
    if (minimumTextHeight > 0) request.minimumTextHeight = MIN(1, minimumTextHeight);
    NSUInteger maxResults = MIN((NSUInteger)1000, MAX((NSUInteger)1, AutoWDAUnsigned(region[@"maxResults"], 1000)));
    NSError *visionError = nil;
    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:requestImage options:@{}];
    BOOL cancelledBeforeVision = NO;
    @synchronized (self.sessionLock) {
        cancelledBeforeVision = operationGeneration != self.operationCancellationGeneration;
        if (!cancelledBeforeVision) [self.activeVisionRequests addObject:request];
    }
    if (cancelledBeforeVision) {
        if (croppedImage) CGImageRelease(croppedImage);
        if (error) *error = AutoWDAError(AutoSDKErrorScriptCancelled, @"OCR was cancelled.");
        return nil;
    }
    BOOL ok = NO;
    @try {
        ok = [handler performRequests:@[request] error:&visionError];
    } @catch (NSException *exception) {
        visionError = AutoWDAError(AutoSDKErrorAutomationFailed, [NSString stringWithFormat:@"Vision OCR failed: %@", exception.reason ?: @"unknown error"]);
    }
    @synchronized (self.sessionLock) { [self.activeVisionRequests removeObject:request]; }
    NSMutableArray *items = [NSMutableArray array];
    if (ok) {
        CGFloat requestWidth = CGImageGetWidth(requestImage), requestHeight = CGImageGetHeight(requestImage);
        for (VNRecognizedTextObservation *observation in request.results) {
            VNRecognizedText *candidate = [observation topCandidates:1].firstObject;
            if (!candidate) continue;
            CGRect box = observation.boundingBox;
            CGRect bounds = CGRectMake((cropPixels.origin.x + box.origin.x * requestWidth) / scale.x,
                                       (cropPixels.origin.y + (1.0 - CGRectGetMaxY(box)) * requestHeight) / scale.y,
                                       box.size.width * requestWidth / scale.x,
                                       box.size.height * requestHeight / scale.y);
            [items addObject:@{ @"text": candidate.string ?: @"", @"confidence": @(candidate.confidence),
                                @"bounds": @{ @"x": @(bounds.origin.x), @"y": @(bounds.origin.y),
                                               @"width": @(bounds.size.width), @"height": @(bounds.size.height),
                                               @"centerX": @(CGRectGetMidX(bounds)), @"centerY": @(CGRectGetMidY(bounds)) },
                                 @"normalizedBounds": @{ @"x": @(box.origin.x), @"y": @(box.origin.y),
                                                         @"width": @(box.size.width), @"height": @(box.size.height) } }];
            if (items.count >= maxResults) break;
        }
        if (items.count > 1) [items sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
            NSDictionary *a = left[@"bounds"], *b = right[@"bounds"];
            CGFloat yDifference = [a[@"y"] doubleValue] - [b[@"y"] doubleValue];
            if (fabs(yDifference) > 2) return yDifference < 0 ? NSOrderedAscending : NSOrderedDescending;
            CGFloat xDifference = [a[@"x"] doubleValue] - [b[@"x"] doubleValue];
            return xDifference < 0 ? NSOrderedAscending : (xDifference > 0 ? NSOrderedDescending : NSOrderedSame);
        }];
    }
    if (croppedImage) CGImageRelease(croppedImage);
    if ([self operationWasCancelledSinceGeneration:operationGeneration]) {
        if (error) *error = AutoWDAError(AutoSDKErrorScriptCancelled, @"OCR was cancelled.");
        return nil;
    }
    if (!ok) {
        if (error) *error = AutoWDAError(AutoSDKErrorAutomationFailed, visionError.localizedDescription ?: @"OCR failed.");
        return nil;
    }
    return items;
    }
    } @finally {
        if (ownsCancellationContext) [self clearCancellationContext];
        [self.visualOperationLock unlock];
    }
}

- (NSDictionary *)findColor:(id)color region:(NSDictionary *)region options:(NSDictionary *)options error:(NSError **)error {
    NSUInteger operationGeneration = [self currentOperationCancellationGeneration];
    BOOL ownsCancellationContext = [self installCancellationContextForGeneration:operationGeneration];
    [self.visualOperationLock lock];
    @try {
    {
    if ([self operationWasCancelledSinceGeneration:operationGeneration]) {
        if (error) *error = AutoWDAError(AutoSDKErrorScriptCancelled, @"Color search was cancelled.");
        return nil;
    }
    uint8_t red = 0, green = 0, blue = 0;
    if (!AutoWDAParseColor(color, &red, &green, &blue)) {
        if (error) *error = AutoWDAError(AutoSDKErrorAutomationFailed, @"Color must be #RRGGBB, [r,g,b], or {r,g,b}.");
        return nil;
    }
    NSData *png = [self screenshotWithError:error];
    UIImage *image = png ? [UIImage imageWithData:png] : nil;
    CGImageRef screenCGImage = image.CGImage;
    if (!screenCGImage) {
        if (error && !*error) *error = AutoWDAError(AutoSDKErrorAutomationFailed, @"Unable to decode the screenshot image.");
        return nil;
    }
    AutoWDACoordinateScale scale = [self coordinateScaleForImage:screenCGImage];
    CGRect search = AutoWDAPixelRegion([region isKindOfClass:NSDictionary.class] ? region : @{}, scale,
                                       CGImageGetWidth(screenCGImage), CGImageGetHeight(screenCGImage));
    if (CGRectIsNull(search) || CGRectIsEmpty(search)) return @{ @"found": @NO };
    NSUInteger pixelOriginX = 0, pixelOriginY = 0;
    AutoWDAPixelImage pixels = AutoWDAPixelImageMakeRegion(screenCGImage, search, &pixelOriginX, &pixelOriginY);
    if (!pixels.bytes) {
        if (error && !*error) *error = AutoWDAError(AutoSDKErrorAutomationFailed, @"Unable to allocate a screenshot pixel buffer.");
        return nil;
    }
    CGFloat tolerance = MIN(255, MAX(0, AutoWDADouble(options[@"tolerance"], 8)));
    NSUInteger requestedStep = MIN((NSUInteger)1024, MAX(1, AutoWDAUnsigned(options[@"step"], 1)));
    NSUInteger maxCandidates = MIN(AutoWDAMaxColorCandidates,
                                   MAX((NSUInteger)1000, AutoWDAUnsigned(options[@"maxCandidates"], AutoWDADefaultColorCandidates)));
    NSUInteger maxComparedPixels = MIN(AutoWDAMaxColorComparisons,
                                       MAX((NSUInteger)100000, AutoWDAUnsigned(options[@"maxComparedPixels"], AutoWDADefaultColorComparisons)));
    NSUInteger step = AutoWDAAdaptedScanStep(pixels.width, pixels.height, requestedStep, maxCandidates);
    NSUInteger minX = 0, minY = 0, maxX = pixels.width, maxY = pixels.height;
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
            const uint8_t *pixel = pixels.bytes + y * pixels.bytesPerRow + x * 4;
            if (AutoWDAPixelMatches(pixel, red, green, blue, tolerance)) {
                NSMutableDictionary *match = [AutoWDAMatchResult(x + pixelOriginX, y + pixelOriginY, 1, 1, scale) mutableCopy];
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
    AutoWDAPixelImageDestroy(&pixels);
    if (cancelled || [self operationWasCancelledSinceGeneration:operationGeneration]) {
        if (error) *error = AutoWDAError(AutoSDKErrorScriptCancelled, @"Color search was cancelled.");
        return nil;
    }
    return result ?: @{ @"found": @NO, @"truncated": @(truncated),
                        @"scannedCandidates": @(scannedCandidates),
                        @"comparedPixels": @(comparedPixels), @"effectiveStep": @(step) };
    }
    } @finally {
        if (ownsCancellationContext) [self clearCancellationContext];
        [self.visualOperationLock unlock];
    }
}

- (NSDictionary *)pixelColorAtX:(CGFloat)x y:(CGFloat)y error:(NSError **)error {
    NSUInteger operationGeneration = [self currentOperationCancellationGeneration];
    BOOL ownsCancellationContext = [self installCancellationContextForGeneration:operationGeneration];
    [self.visualOperationLock lock];
    @try {
    {
    if ([self operationWasCancelledSinceGeneration:operationGeneration]) {
        if (error) *error = AutoWDAError(AutoSDKErrorScriptCancelled, @"Pixel read was cancelled.");
        return nil;
    }
    if (!isfinite(x) || !isfinite(y)) {
        if (error) *error = AutoWDAError(AutoSDKErrorInvalidConfiguration, @"Pixel coordinates must be finite.");
        return nil;
    }
    NSData *png = [self screenshotWithError:error];
    UIImage *image = png ? [UIImage imageWithData:png] : nil;
    AutoWDAPixelImage pixels = AutoWDAPixelImageMake(image.CGImage);
    if (!pixels.bytes) {
        if (error && !*error) *error = AutoWDAError(AutoSDKErrorAutomationFailed, @"Unable to read screenshot pixels.");
        return nil;
    }
    AutoWDACoordinateScale scale = [self coordinateScaleForImage:image.CGImage];
    double scaledX = floor((double)x * scale.x), scaledY = floor((double)y * scale.y);
    if (!isfinite(scaledX) || !isfinite(scaledY) || scaledX < 0 || scaledY < 0 ||
        scaledX >= (double)pixels.width || scaledY >= (double)pixels.height) {
        AutoWDAPixelImageDestroy(&pixels);
        if (error) *error = AutoWDAError(AutoSDKErrorAutomationFailed, @"Pixel coordinates are outside the screenshot.");
        return nil;
    }
    NSInteger pixelX = (NSInteger)scaledX, pixelY = (NSInteger)scaledY;
    const uint8_t *pixel = pixels.bytes + (NSUInteger)pixelY * pixels.bytesPerRow + (NSUInteger)pixelX * 4;
    NSDictionary *result = AutoWDAPixelColorResult(pixel, x, y);
    AutoWDAPixelImageDestroy(&pixels);
    return result;
    }
    } @finally {
        if (ownsCancellationContext) [self clearCancellationContext];
        [self.visualOperationLock unlock];
    }
}

- (BOOL)compareColors:(NSArray<NSDictionary *> *)points options:(NSDictionary *)options error:(NSError **)error {
    NSUInteger operationGeneration = [self currentOperationCancellationGeneration];
    BOOL ownsCancellationContext = [self installCancellationContextForGeneration:operationGeneration];
    [self.visualOperationLock lock];
    @try {
    {
    if ([self operationWasCancelledSinceGeneration:operationGeneration]) {
        if (error) *error = AutoWDAError(AutoSDKErrorScriptCancelled, @"Color comparison was cancelled.");
        return NO;
    }
    if (![points isKindOfClass:NSArray.class] || points.count == 0) {
        if (error) *error = AutoWDAError(AutoSDKErrorAutomationFailed, @"compareColors requires at least one point.");
        return NO;
    }
    if (points.count > AutoWDAMaxColorPoints) {
        if (error) *error = AutoWDAError(AutoSDKErrorInvalidConfiguration, @"compareColors accepts at most 4096 points.");
        return NO;
    }
    NSData *png = [self screenshotWithError:error];
    UIImage *image = png ? [UIImage imageWithData:png] : nil;
    AutoWDAPixelImage pixels = AutoWDAPixelImageMake(image.CGImage);
    if (!pixels.bytes) {
        if (error && !*error) *error = AutoWDAError(AutoSDKErrorAutomationFailed, @"Unable to allocate a screenshot pixel buffer.");
        return NO;
    }
    AutoWDACoordinateScale scale = [self coordinateScaleForImage:image.CGImage];
    CGFloat defaultTolerance = MIN(255, MAX(0, AutoWDADouble(options[@"tolerance"], 8)));
    NSUInteger pointIndex = 0;
    for (id object in points) {
        if ((pointIndex++ & 0xFF) == 0 && [self operationWasCancelledSinceGeneration:operationGeneration]) {
            AutoWDAPixelImageDestroy(&pixels);
            if (error) *error = AutoWDAError(AutoSDKErrorScriptCancelled, @"Color comparison was cancelled.");
            return NO;
        }
        if (![object isKindOfClass:NSDictionary.class] || !AutoWDAIsNumber(object[@"x"]) || !AutoWDAIsNumber(object[@"y"])) {
            AutoWDAPixelImageDestroy(&pixels);
            if (error) *error = AutoWDAError(AutoSDKErrorAutomationFailed, @"Each compareColors point must contain numeric x and y.");
            return NO;
        }
        double scaledX = floor([object[@"x"] doubleValue] * scale.x);
        double scaledY = floor([object[@"y"] doubleValue] * scale.y);
        uint8_t red = 0, green = 0, blue = 0;
        if (!isfinite(scaledX) || !isfinite(scaledY) || scaledX < 0 || scaledY < 0 ||
            scaledX >= (double)pixels.width || scaledY >= (double)pixels.height ||
            !AutoWDAParseColor(object[@"color"], &red, &green, &blue)) {
            AutoWDAPixelImageDestroy(&pixels);
            if (error) *error = AutoWDAError(AutoSDKErrorAutomationFailed, @"A compareColors point has invalid coordinates or color.");
            return NO;
        }
        NSInteger x = (NSInteger)scaledX, y = (NSInteger)scaledY;
        CGFloat tolerance = MIN(255, MAX(0, AutoWDADouble(object[@"tolerance"], defaultTolerance)));
        const uint8_t *pixel = pixels.bytes + (NSUInteger)y * pixels.bytesPerRow + (NSUInteger)x * 4;
        if (!AutoWDAPixelMatches(pixel, red, green, blue, tolerance)) {
            AutoWDAPixelImageDestroy(&pixels); return NO;
        }
    }
    AutoWDAPixelImageDestroy(&pixels);
    return YES;
    }
    } @finally {
        if (ownsCancellationContext) [self clearCancellationContext];
        [self.visualOperationLock unlock];
    }
}

- (NSDictionary *)findMultiColor:(id)color offsets:(NSArray *)offsets region:(NSDictionary *)region options:(NSDictionary *)options error:(NSError **)error {
    NSUInteger operationGeneration = [self currentOperationCancellationGeneration];
    BOOL ownsCancellationContext = [self installCancellationContextForGeneration:operationGeneration];
    [self.visualOperationLock lock];
    @try {
    {
    if ([self operationWasCancelledSinceGeneration:operationGeneration]) {
        if (error) *error = AutoWDAError(AutoSDKErrorScriptCancelled, @"Multi-color search was cancelled.");
        return nil;
    }
    uint8_t baseRed = 0, baseGreen = 0, baseBlue = 0;
    if (!AutoWDAParseColor(color, &baseRed, &baseGreen, &baseBlue) || ![offsets isKindOfClass:NSArray.class]) {
        if (error) *error = AutoWDAError(AutoSDKErrorAutomationFailed, @"findMultiColor requires a base color and an offsets array.");
        return nil;
    }
    if (offsets.count > AutoWDAMaxColorOffsets) {
        if (error) *error = AutoWDAError(AutoSDKErrorInvalidConfiguration, @"findMultiColor accepts at most 256 offsets.");
        return nil;
    }
    NSData *png = [self screenshotWithError:error];
    UIImage *image = png ? [UIImage imageWithData:png] : nil;
    if (!image.CGImage) {
        if (error && !*error) *error = AutoWDAError(AutoSDKErrorAutomationFailed, @"Unable to decode the screenshot image.");
        return nil;
    }
    CGImageRef screenCGImage = image.CGImage;
    AutoWDACoordinateScale scale = [self coordinateScaleForImage:screenCGImage];
    size_t imageWidth = CGImageGetWidth(screenCGImage), imageHeight = CGImageGetHeight(screenCGImage);
    AutoWDAColorOffset *parsedOffsets = offsets.count > 0 ? calloc(offsets.count, sizeof(AutoWDAColorOffset)) : NULL;
    if (offsets.count > 0 && !parsedOffsets) {
        if (error) *error = AutoWDAError(AutoSDKErrorAutomationFailed, @"Unable to allocate multi-color offsets.");
        return nil;
    }
    BOOL invalidOffset = NO, impossibleOffset = NO;
    for (NSUInteger index = 0; index < offsets.count; index++) {
        id offsetObject = offsets[index];
        CGFloat dx = NAN, dy = NAN, offsetTolerance = MIN(255, MAX(0, AutoWDADouble(options[@"tolerance"], 8)));
        id offsetColor = nil;
        if ([offsetObject isKindOfClass:NSArray.class] && [offsetObject count] >= 3) {
            dx = AutoWDADouble(offsetObject[0], NAN);
            dy = AutoWDADouble(offsetObject[1], NAN);
            offsetColor = offsetObject[2];
        } else if ([offsetObject isKindOfClass:NSDictionary.class]) {
            dx = AutoWDADouble(offsetObject[@"dx"] ?: offsetObject[@"x"], NAN);
            dy = AutoWDADouble(offsetObject[@"dy"] ?: offsetObject[@"y"], NAN);
            offsetColor = offsetObject[@"color"];
            if (offsetObject[@"tolerance"]) offsetTolerance = MIN(255, MAX(0, AutoWDADouble(offsetObject[@"tolerance"], offsetTolerance)));
        } else {
            invalidOffset = YES;
            break;
        }
        double pixelDX = round((double)dx * scale.x), pixelDY = round((double)dy * scale.y);
        if (!isfinite(dx) || !isfinite(dy) || !isfinite(pixelDX) || !isfinite(pixelDY) ||
            !AutoWDAParseColor(offsetColor, &parsedOffsets[index].red, &parsedOffsets[index].green, &parsedOffsets[index].blue)) {
            invalidOffset = YES;
            break;
        }
        if (fabs(pixelDX) >= (double)imageWidth || fabs(pixelDY) >= (double)imageHeight) impossibleOffset = YES;
        parsedOffsets[index].dx = impossibleOffset ? 0 : (NSInteger)pixelDX;
        parsedOffsets[index].dy = impossibleOffset ? 0 : (NSInteger)pixelDY;
        parsedOffsets[index].tolerance = offsetTolerance;
    }
    if (invalidOffset || impossibleOffset) {
        free(parsedOffsets);
        if (invalidOffset && error) *error = AutoWDAError(AutoSDKErrorInvalidConfiguration, @"findMultiColor contains an invalid offset or color.");
        return invalidOffset ? nil : @{ @"found": @NO };
    }
    AutoWDAPixelImage pixels = AutoWDAPixelImageMake(image.CGImage);
    if (!pixels.bytes) {
        free(parsedOffsets);
        if (error && !*error) *error = AutoWDAError(AutoSDKErrorAutomationFailed, @"Unable to allocate a screenshot pixel buffer.");
        return nil;
    }
    CGFloat tolerance = MIN(255, MAX(0, AutoWDADouble(options[@"tolerance"], 8)));
    NSUInteger requestedStep = MIN((NSUInteger)1024, MAX(1, AutoWDAUnsigned(options[@"step"], 1)));
    CGRect search = AutoWDAPixelRegion([region isKindOfClass:NSDictionary.class] ? region : @{}, scale, pixels.width, pixels.height);
    if (CGRectIsNull(search) || CGRectIsEmpty(search)) {
        AutoWDAPixelImageDestroy(&pixels); free(parsedOffsets); return @{ @"found": @NO };
    }
    NSUInteger minX = MIN(pixels.width, MAX(0, (NSUInteger)floor(CGRectGetMinX(search))));
    NSUInteger minY = MIN(pixels.height, MAX(0, (NSUInteger)floor(CGRectGetMinY(search))));
    NSUInteger maxX = MIN(pixels.width, (NSUInteger)ceil(CGRectGetMaxX(search)));
    NSUInteger maxY = MIN(pixels.height, (NSUInteger)ceil(CGRectGetMaxY(search)));
    NSUInteger maxCandidates = MIN(AutoWDAMaxColorCandidates,
                                   MAX((NSUInteger)1000, AutoWDAUnsigned(options[@"maxCandidates"], AutoWDADefaultColorCandidates)));
    NSUInteger maxComparedPixels = MIN(AutoWDAMaxColorComparisons,
                                       MAX((NSUInteger)100000, AutoWDAUnsigned(options[@"maxComparedPixels"], AutoWDADefaultColorComparisons)));
    NSUInteger step = AutoWDAAdaptedScanStep(maxX - minX, maxY - minY, requestedStep, maxCandidates);
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
            const uint8_t *basePixel = pixels.bytes + y * pixels.bytesPerRow + x * 4;
            if (!AutoWDAPixelMatches(basePixel, baseRed, baseGreen, baseBlue, tolerance)) continue;
            BOOL matched = YES;
            for (NSUInteger index = 0; index < offsets.count; index++) {
                if (comparedPixels >= maxComparedPixels) { truncated = YES; matched = NO; break; }
                comparedPixels += 1;
                if ((comparedPixels & 0xFFF) == 0 && [self operationWasCancelledSinceGeneration:operationGeneration]) {
                    cancelled = YES; matched = NO; break;
                }
                AutoWDAColorOffset offset = parsedOffsets[index];
                NSInteger targetX = (NSInteger)x + offset.dx;
                NSInteger targetY = (NSInteger)y + offset.dy;
                if (targetX < 0 || targetY < 0 || targetX >= (NSInteger)pixels.width || targetY >= (NSInteger)pixels.height) {
                    matched = NO; break;
                }
                const uint8_t *pixel = pixels.bytes + (NSUInteger)targetY * pixels.bytesPerRow + (NSUInteger)targetX * 4;
                if (!AutoWDAPixelMatches(pixel, offset.red, offset.green, offset.blue, offset.tolerance)) { matched = NO; break; }
            }
            if (matched) {
                NSMutableDictionary *match = [AutoWDAMatchResult(x, y, 1, 1, scale) mutableCopy];
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
    AutoWDAPixelImageDestroy(&pixels);
    free(parsedOffsets);
    if (cancelled || [self operationWasCancelledSinceGeneration:operationGeneration]) {
        if (error) *error = AutoWDAError(AutoSDKErrorScriptCancelled, @"Multi-color search was cancelled.");
        return nil;
    }
    return result ?: @{ @"found": @NO, @"truncated": @(truncated),
                        @"scannedCandidates": @(scannedCandidates),
                        @"comparedPixels": @(comparedPixels), @"effectiveStep": @(step) };
    }
    } @finally {
        if (ownsCancellationContext) [self clearCancellationContext];
        [self.visualOperationLock unlock];
    }
}

- (NSDictionary *)deviceInfo {
    CGSize windowSize = CGSizeZero;
    NSString *session = nil;
    NSTimeInterval sourceDuration = 0;
    NSUInteger maxSourceBytes = 0;
    NSUInteger maxSourceNodes = 0;
    NSTimeInterval screenshotDuration = 0;
    @synchronized (self.sessionLock) {
        windowSize = self.windowSizeCache;
        session = [_sessionId copy];
        sourceDuration = _sourceCacheDuration;
        maxSourceBytes = _sourceMaxBytes;
        maxSourceNodes = _sourceMaxNodes;
        screenshotDuration = _screenshotCacheDuration;
    }
    NSMutableDictionary *info = [@{ @"adapter": @"WDAHTTP", @"scope": @"crossApp", @"baseURL": self.baseURL.absoluteString ?: @"",
                                     @"sessionId": session ?: [NSNull null], @"sourceCacheDuration": @(sourceDuration),
                                     @"sourceMaxBytes": @(maxSourceBytes), @"sourceMaxNodes": @(maxSourceNodes),
                                     @"screenshotCacheDuration": @(screenshotDuration) } mutableCopy];
    if (windowSize.width > 0 && windowSize.height > 0) {
        info[@"screenWidth"] = @(windowSize.width);
        info[@"screenHeight"] = @(windowSize.height);
    }
    return info;
}

- (BOOL)clickAtX:(CGFloat)x y:(CGFloat)y error:(NSError **)error {
    if (!isfinite(x) || !isfinite(y)) {
        if (error) *error = AutoWDAError(AutoSDKErrorInvalidConfiguration, @"Click coordinates must be finite.");
        return NO;
    }
    return [self performTouchActions:@[@{ @"type": @"pointerMove", @"duration": @0, @"x": @(x), @"y": @(y) },
                                      @{ @"type": @"pointerDown", @"button": @0 },
                                      @{ @"type": @"pointerUp", @"button": @0 }] error:error];
}

- (BOOL)doubleClickAtX:(CGFloat)x y:(CGFloat)y interval:(NSTimeInterval)interval error:(NSError **)error {
    if (!isfinite(x) || !isfinite(y) || !isfinite(interval)) {
        if (error) *error = AutoWDAError(AutoSDKErrorInvalidConfiguration, @"Double-click coordinates and interval must be finite.");
        return NO;
    }
    NSUInteger pause = (NSUInteger)(MIN(60.0, MAX(0, interval)) * 1000);
    return [self performTouchActions:@[@{ @"type": @"pointerMove", @"duration": @0, @"x": @(x), @"y": @(y) },
                                      @{ @"type": @"pointerDown", @"button": @0 }, @{ @"type": @"pointerUp", @"button": @0 },
                                      @{ @"type": @"pause", @"duration": @(pause) },
                                      @{ @"type": @"pointerMove", @"duration": @0, @"x": @(x), @"y": @(y) },
                                      @{ @"type": @"pointerDown", @"button": @0 }, @{ @"type": @"pointerUp", @"button": @0 }] error:error];
}

- (BOOL)exists:(id)selector error:(NSError **)error {
    if ([selector isKindOfClass:NSDictionary.class] && AutoWDAElementIdFromValue(selector).length > 0) {
        NSError *requestError = nil;
        [self requestElementSelector:selector suffix:@"/name" method:@"GET" body:nil wdaNamespace:NO error:&requestError];
        if (AutoWDAErrorIsElementNotFound(requestError)) return NO;
        if (requestError && error) *error = requestError;
        return requestError == nil;
    }
    NSDictionary *locator = [self locatorForSelector:selector error:error];
    if (!locator) return NO;
    NSError *requestError = nil;
    id response = [self requestSessionSuffix:@"/element" method:@"POST" body:locator error:&requestError];
    if (AutoWDAErrorIsElementNotFound(requestError)) return NO;
    if (requestError) {
        if (error) *error = requestError;
        return NO;
    }
    id value = AutoWDAResponseValue(response);
    return AutoWDAElementIdFromValue(value).length > 0;
}

- (NSDictionary *)elementInfoForSelector:(id)selector error:(NSError **)error {
    NSDictionary *payload = [self elementPayloadForSelector:selector error:error];
    return payload ? [self elementInfoFromPayload:payload] : nil;
}

- (NSArray<NSDictionary *> *)elementsInfoForSelector:(id)selector error:(NSError **)error {
    NSError *unwrapError = nil;
    id unwrapped = AutoWDAUnwrapSelector(selector, &unwrapError);
    if (unwrapError) {
        if (error) *error = unwrapError;
        return nil;
    }
    NSDictionary *locator = [self locatorForSelector:unwrapped error:error];
    if (!locator) return nil;
    NSUInteger maxResults = [unwrapped isKindOfClass:NSDictionary.class] ? AutoWDAUnsigned(unwrapped[@"maxResults"], 0) : 0;
    if (maxResults == 0) maxResults = 500;
    maxResults = MIN(maxResults, 2000);
    NSString *elementSession = nil;
    id response = [self requestSessionSuffix:@"/elements" method:@"POST" body:locator usedSession:&elementSession error:error];
    id value = AutoWDAResponseValue(response);
    if (![value isKindOfClass:NSArray.class]) return @[];
    NSMutableArray *result = [NSMutableArray array];
    for (id item in (NSArray *)value) {
        NSString *elementId = AutoWDAElementIdFromValue(item);
        if (elementId.length == 0) continue;
        [result addObject:[self elementInfoFromPayload:@{ @"elementId": elementId,
                                                          @"sessionId": elementSession ?: @"",
                                                          @"selector": selector ?: [NSNull null] }]];
        if (result.count >= maxResults) break;
    }
    return result;
}

- (id)attribute:(NSString *)attribute forSelector:(id)selector error:(NSError **)error {
    if (attribute.length == 0 || attribute.length > 256) {
        if (error) *error = AutoWDAError(AutoSDKErrorInvalidConfiguration,
                                         @"Element attribute names must contain 1 to 256 characters.");
        return nil;
    }
    NSString *name = AutoWDAPathSegment(attribute);
    id response = [self requestElementSelector:selector suffix:[NSString stringWithFormat:@"/attribute/%@", name]
                                         method:@"GET" body:nil wdaNamespace:NO error:error];
    id value = AutoWDAResponseValue(response);
    return value ?: [NSNull null];
}

- (NSDictionary *)boundsForSelector:(id)selector error:(NSError **)error {
    id response = [self requestElementSelector:selector suffix:@"/rect" method:@"GET" body:nil wdaNamespace:NO error:error];
    id value = AutoWDAResponseValue(response);
    if (![value isKindOfClass:NSDictionary.class]) return nil;
    CGFloat x = AutoWDADouble(value[@"x"], NAN), y = AutoWDADouble(value[@"y"], NAN);
    CGFloat width = AutoWDADouble(value[@"width"], NAN), height = AutoWDADouble(value[@"height"], NAN);
    if (!isfinite(x) || !isfinite(y) || !isfinite(width) || !isfinite(height) || width < 0 || height < 0) {
        if (error) *error = AutoWDAError(AutoSDKErrorAutomationFailed,
                                         @"WDA returned invalid element bounds.");
        return nil;
    }
    return @{ @"x": @(x), @"y": @(y), @"width": @(width), @"height": @(height), @"centerX": @(x + width / 2), @"centerY": @(y + height / 2) };
}

- (AutoWDASourceNode *)sourceRootWithError:(NSError **)error {
    NSUInteger operationGeneration = [self currentOperationCancellationGeneration];
    BOOL ownsCancellationContext = [self installCancellationContextForGeneration:operationGeneration];
    [self.sourceRequestLock lock];
    @try {
    {
        __block NSTimeInterval duration = 0;
        __block NSUInteger requestGeneration = 0;
        __block NSUInteger sourceMaxBytes = 0;
        __block NSUInteger sourceMaxNodes = 0;
        NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
        @synchronized (self.sessionLock) {
            if (operationGeneration != self.operationCancellationGeneration) {
                if (error) *error = AutoWDAError(AutoSDKErrorScriptCancelled, @"WDA source request was cancelled.");
                return nil;
            }
            duration = self.sourceCacheDuration;
            if (duration > 0 && self.sourceCacheRoot &&
                now - self.sourceCacheTimestamp <= duration) return self.sourceCacheRoot;
            if (self.sourceCacheRoot && now - self.sourceCacheTimestamp > duration) {
                self.sourceCacheRoot = nil;
                self.sourceCacheTimestamp = 0;
            }
            requestGeneration = self.sourceCacheGeneration;
            sourceMaxBytes = self.sourceMaxBytes;
            sourceMaxNodes = self.sourceMaxNodes;
        }
        id response = [self requestSessionSuffix:@"/source" method:@"GET" body:nil error:error];
        id value = AutoWDAResponseValue(response);
        NSString *xml = [value isKindOfClass:NSString.class] ? value : nil;
        if (!xml) {
            if (error && !*error) *error = AutoWDAError(AutoSDKErrorAutomationFailed, @"WDA source response is not XML text.");
            return nil;
        }
        NSUInteger xmlByteLength = [xml lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        if (sourceMaxBytes > 0 && xmlByteLength > sourceMaxBytes) {
            if (error) *error = AutoWDAError(AutoSDKErrorAutomationFailed, @"WDA source XML exceeds the configured byte limit.");
            return nil;
        }
        NSData *data = [xml dataUsingEncoding:NSUTF8StringEncoding];
        if (!data) {
            if (error) *error = AutoWDAError(AutoSDKErrorAutomationFailed, @"Unable to encode WDA source XML.");
            return nil;
        }
        response = nil;
        value = nil;
        xml = nil;
        AutoWDASourceParser *parser = [[AutoWDASourceParser alloc] initWithMaxNodes:sourceMaxNodes];
        parser.shouldCancel = ^BOOL{
            return [self operationWasCancelledSinceGeneration:operationGeneration];
        };
        NSXMLParser *xmlParser = [[NSXMLParser alloc] initWithData:data];
        xmlParser.delegate = parser;
        xmlParser.shouldResolveExternalEntities = NO;
        if (![xmlParser parse] || !parser.root) {
            NSString *message = parser.cancelled
                ? @"WDA source parsing was cancelled."
                : (parser.limitExceeded
                    ? @"WDA source XML exceeds the configured node limit."
                    : (parser.depthExceeded
                        ? @"WDA source XML exceeds the 1024-level depth limit."
                        : (xmlParser.parserError.localizedDescription ?: @"Unable to parse WDA source XML.")));
            if (error) *error = AutoWDAError(parser.cancelled ? AutoSDKErrorScriptCancelled : AutoSDKErrorAutomationFailed,
                                             message);
            return nil;
        }
        AutoWDASourceNode *root = parser.root;
        NSUInteger generation = 0;
        BOOL cancelledAfterParse = NO;
        NSTimeInterval cacheTimestamp = NSProcessInfo.processInfo.systemUptime;
        @synchronized (self.sessionLock) {
            cancelledAfterParse = operationGeneration != self.operationCancellationGeneration;
            if (!cancelledAfterParse && duration > 0) {
                if (self.sourceCacheGeneration == requestGeneration) {
                    self.sourceCacheRoot = root;
                    self.sourceCacheTimestamp = cacheTimestamp;
                    generation = ++self.sourceCacheGeneration;
                }
            }
        }
        if (cancelledAfterParse) {
            if (error) *error = AutoWDAError(AutoSDKErrorScriptCancelled, @"WDA source parsing was cancelled.");
            return nil;
        }
        if (generation > 0) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)),
                           dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                @synchronized (self.sessionLock) {
                    if (self.sourceCacheGeneration == generation) {
                        self.sourceCacheRoot = nil;
                        self.sourceCacheTimestamp = 0;
                    }
                }
            });
        }
        return root;
    }
    } @finally {
        [self.sourceRequestLock unlock];
        if (ownsCancellationContext) [self clearCancellationContext];
    }
}

- (NSArray<NSDictionary<NSString *,id> *> *)nodeSnapshotWithMaxResults:(NSUInteger)maxResults error:(NSError **)error {
    NSUInteger operationGeneration = [self currentOperationCancellationGeneration];
    BOOL ownsCancellationContext = [self installCancellationContextForGeneration:operationGeneration];
    @try {
    NSUInteger windowRequestGeneration = 0;
    @synchronized (self.sessionLock) { windowRequestGeneration = self.windowSizeCacheGeneration; }
    AutoWDASourceNode *root = [self sourceRootWithError:error];
    if (!root) return nil;
    CGFloat rootWidth = AutoWDADouble(root.attributes[@"width"], 0);
    CGFloat rootHeight = AutoWDADouble(root.attributes[@"height"], 0);
    if (rootWidth > 0 && rootHeight > 0) {
        @synchronized (self.sessionLock) {
            if (self.windowSizeCacheGeneration == windowRequestGeneration) {
                self.windowSizeCache = CGSizeMake(rootWidth, rootHeight);
                self.windowSizeCacheTimestamp = NSProcessInfo.processInfo.systemUptime;
                self.windowSizeCacheGeneration += 1;
            }
        }
    }
    NSUInteger maximum = MIN((NSUInteger)2000, MAX((NSUInteger)1, maxResults));
    NSMutableArray<NSDictionary<NSString *, id> *> *result = [NSMutableArray arrayWithCapacity:MIN(maximum, (NSUInteger)500)];
    NSMutableArray<AutoWDASourceNode *> *pending = [NSMutableArray arrayWithObject:root];
    while (pending.count > 0 && result.count < maximum) {
        if ((result.count & 0x3F) == 0 && [self operationWasCancelledSinceGeneration:operationGeneration]) {
            if (error) *error = AutoWDAError(AutoSDKErrorScriptCancelled, @"WDA node snapshot was cancelled.");
            return nil;
        }
        AutoWDASourceNode *node = pending.lastObject;
        [pending removeLastObject];
        [result addObject:AutoWDASourceNodeInfo(node)];
        for (AutoWDASourceNode *child in node.children.reverseObjectEnumerator) [pending addObject:child];
    }
    return result;
    } @finally {
        if (ownsCancellationContext) [self clearCancellationContext];
    }
}

- (AutoWDASourceNode *)sourceNodeForSelector:(id)selector
                               retainingRoot:(AutoWDASourceNode **)retainedRoot
                                       error:(NSError **)error {
    NSUInteger operationGeneration = [self currentOperationCancellationGeneration];
    BOOL ownsCancellationContext = [self installCancellationContextForGeneration:operationGeneration];
    @try {
    NSError *selectorError = nil;
    id unwrappedSelector = AutoWDAUnwrapSelector(selector, &selectorError);
    if (selectorError) {
        if (error) *error = selectorError;
        return nil;
    }
    AutoWDASourceNode *root = [self sourceRootWithError:error];
    if (!root) return nil;
    if (retainedRoot) *retainedRoot = root;
    BOOL (^shouldCancelLookup)(void) = ^BOOL{
        return [self operationWasCancelledSinceGeneration:operationGeneration];
    };
    BOOL lookupCancelled = NO;
    NSString *elementId = AutoWDAElementIdFromValue(selector);
    if (elementId.length > 0) {
        NSError *boundsError = nil;
        NSDictionary *bounds = [self boundsForSelector:selector error:&boundsError];
        NSMutableDictionary *identity = bounds ? [@{ @"bounds": bounds } mutableCopy] : [NSMutableDictionary dictionary];
        NSError *typeError = nil;
        id type = [self attribute:@"type" forSelector:selector error:&typeError];
        NSString *typeString = [type isKindOfClass:NSString.class] ? (NSString *)type : nil;
        if (typeString.length > 0) identity[@"type"] = typeString;
        id name = [self attribute:@"name" forSelector:selector error:nil];
        NSString *nameString = [name isKindOfClass:NSString.class] ? (NSString *)name : nil;
        if (nameString.length > 0) identity[@"name"] = nameString;
        AutoWDASourceNode *handleNode = identity.count > 0
            ? AutoWDAFindSourceNode(root, identity, shouldCancelLookup, &lookupCancelled, nil)
            : nil;
        if (lookupCancelled) {
            if (error) *error = AutoWDAError(AutoSDKErrorScriptCancelled, @"WDA node lookup was cancelled.");
            return nil;
        }
        if (handleNode) return handleNode;
        (void)boundsError;
        (void)typeError;
    }
    AutoWDASourceNode *node = AutoWDAFindSourceNode(root, unwrappedSelector,
                                                    shouldCancelLookup, &lookupCancelled, nil);
    if (lookupCancelled) {
        if (error) *error = AutoWDAError(AutoSDKErrorScriptCancelled, @"WDA node lookup was cancelled.");
        return nil;
    }
    if (!node) {
        NSError *identityError = nil;
        NSDictionary *bounds = [self boundsForSelector:selector error:&identityError];
        if (bounds) {
            NSMutableDictionary *identity = [@{ @"bounds": bounds } mutableCopy];
            NSError *typeError = nil;
            id type = [self attribute:@"type" forSelector:selector error:&typeError];
            if ([type isKindOfClass:NSString.class] && [(NSString *)type length] > 0) identity[@"type"] = type;
            node = AutoWDAFindSourceNode(root, identity, shouldCancelLookup, &lookupCancelled, nil);
            if (lookupCancelled) {
                if (error) *error = AutoWDAError(AutoSDKErrorScriptCancelled, @"WDA node lookup was cancelled.");
                return nil;
            }
            (void)typeError;
        }
        (void)identityError;
    }
    if ([self operationWasCancelledSinceGeneration:operationGeneration]) {
        if (error) *error = AutoWDAError(AutoSDKErrorScriptCancelled, @"WDA node lookup was cancelled.");
        return nil;
    }
    if (!node && error) *error = AutoWDAError(AutoSDKErrorElementNotFound, @"The selector was not found in the WDA source snapshot.");
    return node;
    } @finally {
        if (ownsCancellationContext) [self clearCancellationContext];
    }
}

- (NSArray<NSDictionary *> *)childrenForSelector:(id)selector error:(NSError **)error {
    __attribute__((objc_precise_lifetime)) AutoWDASourceNode *retainedRoot = nil;
    AutoWDASourceNode *node = [self sourceNodeForSelector:selector retainingRoot:&retainedRoot error:error];
    if (!node) return nil;
    NSUInteger maximum = 500;
    NSError *unwrapError = nil;
    id unwrapped = AutoWDAUnwrapSelector(selector, &unwrapError);
    if (unwrapError) {
        if (error) *error = unwrapError;
        return nil;
    }
    if ([unwrapped isKindOfClass:NSDictionary.class] && AutoWDAUnsigned(unwrapped[@"maxResults"], 0) > 0) {
        maximum = MIN(2000, AutoWDAUnsigned(unwrapped[@"maxResults"], 0));
    }
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:MIN(maximum, node.children.count)];
    for (AutoWDASourceNode *child in node.children) {
        [result addObject:AutoWDASourceNodeInfo(child)];
        if (result.count >= maximum) break;
    }
    return result;
}

- (NSDictionary *)parentForSelector:(id)selector error:(NSError **)error {
    __attribute__((objc_precise_lifetime)) AutoWDASourceNode *retainedRoot = nil;
    AutoWDASourceNode *node = [self sourceNodeForSelector:selector retainingRoot:&retainedRoot error:error];
    return node.parent ? AutoWDASourceNodeInfo(node.parent) : nil;
}

- (BOOL)scrollIntoView:(id)selector error:(NSError **)error {
    NSUInteger operationGeneration = [self currentOperationCancellationGeneration];
    BOOL ownsCancellationContext = [self installCancellationContextForGeneration:operationGeneration];
    @try {
    // WDA exposes element scrolling under its /wda namespace. Some older
    // compatible runners also accept the JSONWP /scroll route, so retry it
    // only when the preferred route is rejected.
    NSError *wdaError = nil;
    [self requestElementSelector:selector suffix:@"/scroll" method:@"POST" body:@{} wdaNamespace:YES error:&wdaError];
    BOOL success = wdaError == nil;
    if (!success && wdaError) {
        NSError *fallbackError = nil;
        [self requestElementSelector:selector suffix:@"/scroll" method:@"POST" body:@{} wdaNamespace:NO error:&fallbackError];
        success = fallbackError == nil;
        if (fallbackError && error) *error = fallbackError;
    }
    if (success) [self invalidateVisualCaches];
    return success;
    } @finally {
        if (ownsCancellationContext) [self clearCancellationContext];
    }
}

- (BOOL)validateBundleId:(NSString *)bundleId error:(NSError **)error {
    if (![bundleId isKindOfClass:NSString.class] || bundleId.length == 0 || bundleId.length > 255) {
        if (error) *error = AutoWDAError(AutoSDKErrorInvalidConfiguration,
                                         @"Application bundleId must contain 1 to 255 characters.");
        return NO;
    }
    return YES;
}

- (BOOL)launchApplicationWithBundleId:(NSString *)bundleId error:(NSError **)error {
    if (![self validateBundleId:bundleId error:error]) return NO;
    NSError *requestError = nil;
    [self requestSessionSuffix:@"/wda/apps/launch" method:@"POST" body:@{ @"bundleId": bundleId } error:&requestError];
    if (requestError && error) *error = requestError;
    if (!requestError) [self invalidateVisualCaches];
    return requestError == nil;
}

- (BOOL)activateApplicationWithBundleId:(NSString *)bundleId error:(NSError **)error {
    if (![self validateBundleId:bundleId error:error]) return NO;
    NSError *requestError = nil;
    [self requestSessionSuffix:@"/wda/apps/activate" method:@"POST" body:@{ @"bundleId": bundleId } error:&requestError];
    if (requestError && error) *error = requestError;
    if (!requestError) [self invalidateVisualCaches];
    return requestError == nil;
}

- (BOOL)terminateApplicationWithBundleId:(NSString *)bundleId error:(NSError **)error {
    if (![self validateBundleId:bundleId error:error]) return NO;
    NSError *requestError = nil;
    [self requestSessionSuffix:@"/wda/apps/terminate" method:@"POST" body:@{ @"bundleId": bundleId } error:&requestError];
    if (requestError && error) *error = requestError;
    if (!requestError) [self invalidateVisualCaches];
    return requestError == nil;
}

- (NSNumber *)applicationStateForBundleId:(NSString *)bundleId error:(NSError **)error {
    if (![self validateBundleId:bundleId error:error]) return nil;
    NSError *requestError = nil;
    id response = [self requestSessionSuffix:@"/wda/apps/state" method:@"POST" body:@{ @"bundleId": bundleId } error:&requestError];
    if (requestError) {
        if (error) *error = requestError;
        return nil;
    }
    id value = AutoWDAResponseValue(response);
    if ([value isKindOfClass:NSNumber.class]) return value;
    if ([value isKindOfClass:NSDictionary.class]) {
        id state = value[@"state"] ?: value[@"value"];
        if ([state isKindOfClass:NSNumber.class]) return state;
        if ([state isKindOfClass:NSString.class]) return @([(NSString *)state integerValue]);
    }
    if (error) *error = AutoWDAError(AutoSDKErrorAutomationFailed, @"WDA returned an invalid application state.");
    return nil;
}

- (BOOL)goToHomeScreenWithError:(NSError **)error {
    NSError *requestError = nil;
    [self requestSessionSuffix:@"/wda/homescreen" method:@"POST" body:@{} error:&requestError];
    if (requestError && error) *error = requestError;
    if (!requestError) [self invalidateVisualCaches];
    return requestError == nil;
}

- (BOOL)pressButtonWithName:(NSString *)name error:(NSError **)error {
    if (name.length == 0) {
        if (error) *error = AutoWDAError(AutoSDKErrorInvalidConfiguration, @"Button name must not be empty.");
        return NO;
    }
    NSError *requestError = nil;
    [self requestSessionSuffix:@"/wda/pressButton" method:@"POST" body:@{ @"name": name } error:&requestError];
    if (requestError && error) *error = requestError;
    if (!requestError) [self invalidateVisualCaches];
    return requestError == nil;
}

- (NSNumber *)deviceLockedStateWithError:(NSError **)error {
    NSError *requestError = nil;
    id response = [self requestSessionSuffix:@"/wda/locked" method:@"GET" body:nil error:&requestError];
    if (requestError) {
        if (error) *error = requestError;
        return nil;
    }
    id value = AutoWDAResponseValue(response);
    return @([value boolValue]);
}

- (NSString *)currentApplicationWithError:(NSError **)error {
    NSError *requestError = nil;
    id response = [self requestSessionSuffix:@"/wda/activeAppInfo" method:@"GET" body:nil error:&requestError];
    if (requestError) {
        if (error) *error = requestError;
        return nil;
    }
    id value = AutoWDAResponseValue(response);
    if ([value isKindOfClass:NSDictionary.class]) {
        id bundleId = value[@"bundleId"];
        if ([bundleId isKindOfClass:NSString.class] && ((NSString *)bundleId).length > 0) return bundleId;
    }
    return nil;
}

- (NSArray<NSDictionary<NSString *, id> *> *)installedApplicationsWithError:(NSError **)error {
    NSError *requestError = nil;
    id response = [self requestSessionSuffix:@"/wda/apps" method:@"GET" body:nil error:&requestError];
    if (requestError) {
        if (error) *error = requestError;
        return nil;
    }
    id value = AutoWDAResponseValue(response);
    if (![value isKindOfClass:NSArray.class]) return @[];
    NSUInteger maximum = MIN(value.count, (NSUInteger)1000);
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:MIN(maximum, (NSUInteger)128)];
    for (id item in value) {
        if (result.count >= maximum) break;
        if ([item isKindOfClass:NSString.class]) {
            [result addObject:@{ @"bundleId": item, @"name": @"" }];
        } else if ([item isKindOfClass:NSDictionary.class]) {
            id bundleId = item[@"bundleId"];
            id name = item[@"name"];
            [result addObject:@{ @"bundleId": [bundleId isKindOfClass:NSString.class] ? bundleId : @"",
                                 @"name": [name isKindOfClass:NSString.class] ? name : @"" }];
        }
    }
    return result;
}

- (BOOL)lockDeviceWithError:(NSError **)error {
    NSError *requestError = nil;
    [self requestSessionSuffix:@"/wda/lock" method:@"POST" body:@{} error:&requestError];
    if (requestError && error) *error = requestError;
    if (!requestError) [self invalidateVisualCaches];
    return requestError == nil;
}

- (BOOL)unlockDeviceWithError:(NSError **)error {
    NSError *requestError = nil;
    [self requestSessionSuffix:@"/wda/unlock" method:@"POST" body:@{} error:&requestError];
    if (requestError && error) *error = requestError;
    if (!requestError) [self invalidateVisualCaches];
    return requestError == nil;
}

- (NSDictionary *)capabilities {
    return @{ @"scope": @"crossApp", @"crossApp": @YES, @"requiresWDA": @YES,
              @"requiresMainThread": @NO,
              @"wdaHTTP": @YES, @"realTouchInjection": @YES, @"click": @YES,
              @"coordinateActivation": @YES, @"doubleActivation": @YES,
              @"longClick": @YES, @"swipe": @YES, @"nodes": @YES, @"sourceTreeRelations": @YES,
              @"stableNodeHandles": @NO, @"sessionScopedNodeHandles": @YES, @"xpath": @YES, @"screenshot": @YES,
              @"findColor": @YES, @"multiColor": @YES, @"findImage": @YES,
              @"ocr": @YES, @"opencv": @NO, @"multiTouch": @YES, @"appLifecycle": @YES, @"systemActions": @YES };
}

@end
