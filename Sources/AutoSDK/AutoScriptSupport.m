#import "AutoScriptSupport.h"
#import "include/AutoSDKError.h"
#import <CommonCrypto/CommonDigest.h>
#import <ImageIO/ImageIO.h>
#include <math.h>

static NSError *AutoSupportError(AutoSDKErrorCode code, NSString *message, NSError *underlying) {
    NSMutableDictionary *info = [@{NSLocalizedDescriptionKey: message ?: @"Operation failed."} mutableCopy];
    if (underlying) info[NSUnderlyingErrorKey] = underlying;
    return [NSError errorWithDomain:AutoSDKErrorDomain code:code userInfo:info];
}

static NSString *AutoHexFromBytes(const unsigned char *bytes, NSUInteger length) {
    NSMutableString *hex = [NSMutableString stringWithCapacity:length * 2];
    for (NSUInteger index = 0; index < length; index++) {
        [hex appendFormat:@"%02x", bytes[index]];
    }
    return hex;
}

NSString *AutoScriptMD5Hex(NSData *data) {
    if (data.length == 0) return @"";
    unsigned char digest[CC_MD5_DIGEST_LENGTH] = {0};
    CC_MD5(data.bytes, (CC_LONG)data.length, digest);
    return AutoHexFromBytes(digest, CC_MD5_DIGEST_LENGTH);
}

NSString *AutoScriptSHA1Hex(NSData *data) {
    if (data.length == 0) return @"";
    unsigned char digest[CC_SHA1_DIGEST_LENGTH] = {0};
    CC_SHA1(data.bytes, (CC_LONG)data.length, digest);
    return AutoHexFromBytes(digest, CC_SHA1_DIGEST_LENGTH);
}
static BOOL AutoConfigAllows(NSDictionary *config, NSString *key, BOOL defaultValue) {
    id value = config[key];
    if (value == nil) return defaultValue;
    return [value isKindOfClass:NSNumber.class] ? [value boolValue] : NO;
}

static NSUInteger AutoSupportByteLimit(NSDictionary *config,
                                        NSString *key,
                                        NSUInteger defaultValue,
                                        NSUInteger hardMaximum) {
    id rawValue = [config isKindOfClass:NSDictionary.class] ? config[key] : nil;
    double number = [rawValue isKindOfClass:NSNumber.class] ? [rawValue doubleValue] : 0;
    if (!isfinite(number) || number <= 0 || number > (double)NSUIntegerMax) return defaultValue;
    return MIN((NSUInteger)number, hardMaximum);
}

static NSObject *AutoFileOperationLock(void) {
    static NSObject *lock;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ lock = [NSObject new]; });
    return lock;
}

static BOOL AutoPathIsWithinRoot(NSString *path, NSString *root) {
    if ([path isEqualToString:root]) return YES;
    NSString *prefix = [root stringByAppendingString:@"/"];
    return [path hasPrefix:prefix];
}

static NSURL *AutoFileRoot(NSDictionary *config, NSError **error) {
    NSString *configured = [config[@"fileRoot"] isKindOfClass:NSString.class] ? config[@"fileRoot"] : nil;
    NSURL *documents = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory
                                                               inDomains:NSUserDomainMask] firstObject];
    NSURL *root = configured.length > 0
        ? ([configured isAbsolutePath] ? [NSURL fileURLWithPath:configured] : [documents URLByAppendingPathComponent:configured])
        : [documents URLByAppendingPathComponent:@"AutoSDK"];
    root = root.URLByStandardizingPath.URLByResolvingSymlinksInPath;
    NSString *home = [NSURL fileURLWithPath:NSHomeDirectory()].URLByStandardizingPath.URLByResolvingSymlinksInPath.path;
    if (!AutoPathIsWithinRoot(root.path, home) || [root.path isEqualToString:home]) {
        if (error) *error = AutoSupportError(AutoSDKErrorInvalidConfiguration, @"fileRoot must be a child directory inside the host application's sandbox.", nil);
        return nil;
    }
    NSError *createError = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:&createError]) {
        if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Unable to create the AutoSDK file root.", createError);
        return nil;
    }
    return root;
}

static NSURL *AutoResolveFilePath(NSString *path, NSDictionary *config, BOOL allowRoot, NSError **error) {
    NSURL *root = AutoFileRoot(config, error);
    if (!root) return nil;
    if (![path isKindOfClass:NSString.class] || [path rangeOfString:@"\0"].location != NSNotFound) {
        if (error) *error = AutoSupportError(AutoSDKErrorFileAccessDenied, @"File path is invalid.", nil);
        return nil;
    }
    NSURL *candidate = path.length == 0 ? root : ([path isAbsolutePath] ? [NSURL fileURLWithPath:path] : [root URLByAppendingPathComponent:path]);
    candidate = candidate.URLByStandardizingPath.URLByResolvingSymlinksInPath;
    if (!AutoPathIsWithinRoot(candidate.path, root.path) || (!allowRoot && [candidate.path isEqualToString:root.path])) {
        if (error) *error = AutoSupportError(AutoSDKErrorFileAccessDenied, @"File path escapes the configured AutoSDK file root.", nil);
        return nil;
    }
    return candidate;
}

static BOOL AutoRequireFileAccess(NSDictionary *config, BOOL write, NSError **error) {
    if (!AutoConfigAllows(config, @"allowFileAccess", YES)) {
        if (error) *error = AutoSupportError(AutoSDKErrorFileAccessDenied, @"Script file access is disabled by configuration.", nil);
        return NO;
    }
    if (write && !AutoConfigAllows(config, @"allowFileWrite", YES)) {
        if (error) *error = AutoSupportError(AutoSDKErrorFileAccessDenied, @"Script file writes are disabled by configuration.", nil);
        return NO;
    }
    return YES;
}

static NSString *AutoRequiredString(id value, NSString *field, NSError **error) {
    if ([value isKindOfClass:NSString.class]) return value;
    if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed,
                                        [NSString stringWithFormat:@"%@ must be a string.", field], nil);
    return nil;
}

static BOOL AutoValidateTreeBudget(NSURL *url,
                                   NSUInteger maximumBytes,
                                   NSUInteger maximumItems,
                                   NSString *operationName,
                                   NSError **error) {
    NSFileManager *manager = NSFileManager.defaultManager;
    NSNumber *isDirectory = nil;
    NSNumber *isRegularFile = nil;
    NSNumber *fileSize = nil;
    NSError *resourceError = nil;
    if (![url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:&resourceError] ||
        ![url getResourceValue:&isRegularFile forKey:NSURLIsRegularFileKey error:&resourceError] ||
        ![url getResourceValue:&fileSize forKey:NSURLFileSizeKey error:&resourceError]) {
        if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed,
                                             [NSString stringWithFormat:@"Unable to inspect the %@ source.", operationName], resourceError);
        return NO;
    }
    NSUInteger itemCount = 1;
    unsigned long long totalBytes = isRegularFile.boolValue ? fileSize.unsignedLongLongValue : 0;
    if (itemCount > maximumItems || totalBytes > maximumBytes) {
        if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed,
                                             [NSString stringWithFormat:@"%@ exceeds the configured file operation limits.", operationName], nil);
        return NO;
    }
    if (!isDirectory.boolValue) return YES;

    __block NSError *enumerationError = nil;
    NSError *budgetError = nil;
    NSDirectoryEnumerator<NSURL *> *enumerator = [manager enumeratorAtURL:url
        includingPropertiesForKeys:@[NSURLIsRegularFileKey, NSURLFileSizeKey]
                           options:0
                      errorHandler:^BOOL(NSURL *itemURL, NSError *encounteredError) {
                          enumerationError = encounteredError;
                          return NO;
                      }];
    for (NSURL *item in enumerator) {
        @autoreleasepool {
            itemCount += 1;
            NSNumber *regular = nil;
            NSNumber *size = nil;
            NSError *itemError = nil;
            if (![item getResourceValue:&regular forKey:NSURLIsRegularFileKey error:&itemError] ||
                ![item getResourceValue:&size forKey:NSURLFileSizeKey error:&itemError]) {
                enumerationError = itemError;
                break;
            }
            unsigned long long itemBytes = regular.boolValue ? size.unsignedLongLongValue : 0;
            if (itemCount > maximumItems || itemBytes > maximumBytes || totalBytes > maximumBytes - itemBytes) {
                budgetError = AutoSupportError(AutoSDKErrorFileOperationFailed,
                                               [NSString stringWithFormat:@"%@ exceeds the configured file operation limits.", operationName], nil);
                break;
            }
            totalBytes += itemBytes;
        }
    }
    if (budgetError) {
        if (error) *error = budgetError;
        return NO;
    }
    if (enumerationError) {
        if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed,
                                             [NSString stringWithFormat:@"Unable to inspect every item before %@.", operationName], enumerationError);
        return NO;
    }
    return YES;
}

BOOL AutoScriptValidateDownloadDestination(NSString *path,
                                           NSDictionary<NSString *,id> *config,
                                           NSError **error) {
    @synchronized (AutoFileOperationLock()) {
        if (!AutoRequireFileAccess(config, YES, error)) return NO;
        NSURL *destination = AutoResolveFilePath(path, config, NO, error);
        if (!destination) return NO;
        BOOL isDirectory = NO;
        if ([NSFileManager.defaultManager fileExistsAtPath:destination.path isDirectory:&isDirectory] && isDirectory) {
            if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Download destination is a directory.", nil);
            return NO;
        }
        return YES;
    }
}

NSUInteger AutoScriptMaximumDownloadBytes(NSDictionary<NSString *,id> *config) {
    return AutoSupportByteLimit(config, @"maxFileWriteBytes",
                                10 * 1024 * 1024, 64 * 1024 * 1024);
}

BOOL AutoScriptInstallDownloadedFile(NSURL *temporaryURL,
                                     NSString *path,
                                     NSDictionary<NSString *,id> *config,
                                     NSError **error) {
    @synchronized (AutoFileOperationLock()) {
        if (!AutoRequireFileAccess(config, YES, error)) return NO;
        NSURL *destination = AutoResolveFilePath(path, config, NO, error);
        if (!destination || !temporaryURL.isFileURL) {
            if (destination && error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Downloaded file location is invalid.", nil);
            return NO;
        }
        NSFileManager *manager = NSFileManager.defaultManager;
        NSDictionary *attributes = [manager attributesOfItemAtPath:temporaryURL.path error:nil];
        NSUInteger maximum = AutoScriptMaximumDownloadBytes(config);
        unsigned long long size = [attributes[NSFileSize] unsignedLongLongValue];
        if (![attributes[NSFileType] isEqualToString:NSFileTypeRegular] || size > maximum) {
            if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed,
                                                 size > maximum ? @"Downloaded file exceeds maxFileWriteBytes." : @"Downloaded item is not a regular file.", nil);
            return NO;
        }
        NSError *directoryError = nil;
        if (![manager createDirectoryAtURL:destination.URLByDeletingLastPathComponent
               withIntermediateDirectories:YES attributes:nil error:&directoryError]) {
            if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Unable to create the download destination directory.", directoryError);
            return NO;
        }
        BOOL destinationIsDirectory = NO;
        if ([manager fileExistsAtPath:destination.path isDirectory:&destinationIsDirectory] && destinationIsDirectory) {
            if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Download destination is a directory.", nil);
            return NO;
        }
        NSURL *staging = [destination.URLByDeletingLastPathComponent
            URLByAppendingPathComponent:[NSString stringWithFormat:@".autosdk-download-%@", NSUUID.UUID.UUIDString]];
        NSError *moveError = nil;
        BOOL staged = [manager moveItemAtURL:temporaryURL toURL:staging error:&moveError];
        if (!staged) {
            moveError = nil;
            staged = [manager copyItemAtURL:temporaryURL toURL:staging error:&moveError];
        }
        if (!staged) {
            [manager removeItemAtURL:staging error:nil];
            if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Unable to stage downloaded file.", moveError);
            return NO;
        }
        BOOL destinationExists = [manager fileExistsAtPath:destination.path];
        BOOL installed = NO;
        NSError *installError = nil;
        if (destinationExists) {
            NSURL *resultingURL = nil;
            installed = [manager replaceItemAtURL:destination withItemAtURL:staging backupItemName:nil
                                           options:0 resultingItemURL:&resultingURL error:&installError];
        } else {
            installed = [manager moveItemAtURL:staging toURL:destination error:&installError];
        }
        if (!installed) {
            [manager removeItemAtURL:staging error:nil];
            if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Unable to install downloaded file.", installError);
        }
        return installed;
    }
}

static double AutoSupportFiniteDouble(id value, double defaultValue) {
    if ([value isKindOfClass:NSNumber.class]) {
        double number = [value doubleValue];
        return isfinite(number) ? number : defaultValue;
    }
    return defaultValue;
}

typedef struct {
    uint8_t *bytes;
    size_t width;
    size_t height;
    size_t bytesPerRow;
    CGContextRef context;
} AutoSupportPixelImage;

static AutoSupportPixelImage AutoSupportPixelImageMake(CGImageRef image) {
    AutoSupportPixelImage result = {0};
    if (!image) return result;
    size_t width = CGImageGetWidth(image), height = CGImageGetHeight(image);
    if (width == 0 || height == 0 || width > SIZE_MAX / 4 || height > SIZE_MAX / (width * 4)) return result;
    size_t bytesPerRow = width * 4;
    size_t byteCount = height * bytesPerRow;
    if (byteCount > 64 * 1024 * 1024) return result;
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

static void AutoSupportPixelImageDestroy(AutoSupportPixelImage *image) {
    if (image->context) CGContextRelease(image->context);
    free(image->bytes);
    *image = (AutoSupportPixelImage){0};
}

static double AutoSupportImageScale(NSDictionary *properties) {
    NSNumber *dpi = properties[(__bridge NSString *)kCGImagePropertyDPIWidth];
    double scale = [dpi isKindOfClass:NSNumber.class] && [dpi doubleValue] > 0 ? [dpi doubleValue] / 72.0 : 1.0;
    return MAX(0.01, scale);
}

static BOOL AutoSupportWriteImage(CGImageRef image, NSURL *destinationURL, NSDictionary *config, NSError **error) {
    if (!image) {
        if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Unable to produce the processed image.", nil);
        return NO;
    }
    NSString *extension = destinationURL.pathExtension.lowercaseString;
    BOOL jpeg = [extension isEqualToString:@"jpg"] || [extension isEqualToString:@"jpeg"];
    CFStringRef type = jpeg ? CFSTR("public.jpeg") : CFSTR("public.png");
    NSMutableData *data = [NSMutableData data];
    CGImageDestinationRef destination = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data, type, 1, NULL);
    if (!destination) {
        if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Unable to create an image encoder.", nil);
        return NO;
    }
    if (jpeg) {
        NSDictionary *options = @{ (__bridge NSString *)kCGImageDestinationLossyCompressionQuality: @0.9 };
        CGImageDestinationAddImage(destination, image, (__bridge CFDictionaryRef)options);
    } else {
        CGImageDestinationAddImage(destination, image, NULL);
    }
    BOOL finalized = CGImageDestinationFinalize(destination);
    CFRelease(destination);
    if (!finalized) {
        if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Unable to encode the processed image.", nil);
        return NO;
    }
    NSUInteger maximum = AutoSupportByteLimit(config, @"maxFileWriteBytes", 10 * 1024 * 1024, 64 * 1024 * 1024);
    if (data.length > maximum) {
        if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Output image exceeds maxFileWriteBytes.", nil);
        return NO;
    }
    NSError *directoryError = nil;
    if (![NSFileManager.defaultManager createDirectoryAtURL:destinationURL.URLByDeletingLastPathComponent
                                withIntermediateDirectories:YES attributes:nil error:&directoryError]) {
        if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Unable to create the destination directory.", directoryError);
        return NO;
    }
    NSError *writeError = nil;
    if (![data writeToURL:destinationURL options:NSDataWritingAtomic error:&writeError]) {
        if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Unable to write the processed image.", writeError);
        return NO;
    }
    return YES;
}

static CGImageRef AutoSupportImageClip(CGImageRef source, double scale, double x, double y, double ex, double ey) {
    size_t width = CGImageGetWidth(source), height = CGImageGetHeight(source);
    size_t pixelMinX = (size_t)MIN(width, (size_t)MAX(0, floor(MIN(x, ex) * scale)));
    size_t pixelMinY = (size_t)MIN(height, (size_t)MAX(0, floor(MIN(y, ey) * scale)));
    size_t pixelMaxX = (size_t)MIN(width, (size_t)MAX(0, ceil(MAX(x, ex) * scale)));
    size_t pixelMaxY = (size_t)MIN(height, (size_t)MAX(0, ceil(MAX(y, ey) * scale)));
    if (pixelMaxX <= pixelMinX || pixelMaxY <= pixelMinY) return NULL;
    return CGImageCreateWithImageInRect(source, CGRectMake(pixelMinX, pixelMinY, pixelMaxX - pixelMinX, pixelMaxY - pixelMinY));
}

static CGImageRef AutoSupportImageScale(CGImageRef source, double scale, double width, double height) {
    if (width <= 0 || height <= 0) return NULL;
    size_t targetWidth = (size_t)MAX(1, lround(width * scale));
    size_t targetHeight = (size_t)MAX(1, lround(height * scale));
    if (targetWidth > 8192 || targetHeight > 8192 || targetWidth > SIZE_MAX / 4) return NULL;
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    if (!colorSpace) return NULL;
    CGContextRef context = CGBitmapContextCreate(NULL, targetWidth, targetHeight, 8, targetWidth * 4, colorSpace,
                                                 kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);
    if (!context) return NULL;
    CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
    CGContextDrawImage(context, CGRectMake(0, 0, targetWidth, targetHeight), source);
    CGImageRef result = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    return result;
}

static CGImageRef AutoSupportImageMono(CGImageRef source, BOOL binaryzation, NSUInteger threshold) {
    AutoSupportPixelImage buffer = AutoSupportPixelImageMake(source);
    if (!buffer.bytes) return NULL;
    for (size_t y = 0; y < buffer.height; y++) {
        uint8_t *row = buffer.bytes + y * buffer.bytesPerRow;
        for (size_t x = 0; x < buffer.width; x++) {
            uint8_t *pixel = row + x * 4;
            uint8_t luminance = (uint8_t)lround(0.299 * pixel[0] + 0.587 * pixel[1] + 0.114 * pixel[2]);
            uint8_t value = binaryzation ? (luminance >= threshold ? 255 : 0) : luminance;
            pixel[0] = value;
            pixel[1] = value;
            pixel[2] = value;
        }
    }
    CGImageRef result = CGBitmapContextCreateImage(buffer.context);
    AutoSupportPixelImageDestroy(&buffer);
    return result;
}

static CGImageRef AutoSupportImageRotate(CGImageRef source, NSInteger degrees) {
    degrees = ((degrees % 360) + 360) % 360;
    if (degrees == 0) return CGImageRetain(source);
    if (degrees != 90 && degrees != 180 && degrees != 270) return NULL;
    size_t width = CGImageGetWidth(source), height = CGImageGetHeight(source);
    BOOL swaps = degrees == 90 || degrees == 270;
    size_t targetWidth = swaps ? height : width;
    size_t targetHeight = swaps ? width : height;
    if (targetWidth == 0 || targetHeight == 0 || targetWidth > SIZE_MAX / 4) return NULL;
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    if (!colorSpace) return NULL;
    CGContextRef context = CGBitmapContextCreate(NULL, targetWidth, targetHeight, 8, targetWidth * 4, colorSpace,
                                                 kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);
    if (!context) return NULL;
    CGContextTranslateCTM(context, targetWidth / 2.0, targetHeight / 2.0);
    CGContextRotateCTM(context, degrees * M_PI / 180.0);
    CGContextDrawImage(context, CGRectMake(-width / 2.0, -height / 2.0, width, height), source);
    CGImageRef result = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    return result;
}
id AutoScriptFileOperation(NSDictionary<NSString *,id> *payload,
                           NSDictionary<NSString *,id> *config,
                           NSError **error) {
    @synchronized (AutoFileOperationLock()) {
    NSString *operation = [payload[@"operation"] isKindOfClass:NSString.class] ? payload[@"operation"] : @"";
    NSSet *writeOperations = [NSSet setWithArray:@[@"writeText", @"writeBase64", @"appendText", @"mkdir", @"remove", @"copy", @"imageProcess"]];
    BOOL writes = [writeOperations containsObject:operation];
    if (!AutoRequireFileAccess(config, writes, error)) return nil;
    if ([operation isEqualToString:@"sandboxDir"]) return AutoFileRoot(config, error).path;

    NSString *path = AutoRequiredString(payload[@"path"], @"path", error);
    if (!path) return nil;
    BOOL allowRoot = [operation isEqualToString:@"list"] || [operation isEqualToString:@"exists"] || [operation isEqualToString:@"resolvePath"];
    NSURL *url = AutoResolveFilePath(path, config, allowRoot, error);
    if (!url) return nil;
    NSFileManager *manager = NSFileManager.defaultManager;

    if ([operation isEqualToString:@"resolvePath"]) return url.path;
    if ([operation isEqualToString:@"exists"]) return @([manager fileExistsAtPath:url.path]);

    if ([operation isEqualToString:@"stat"]) {
        NSError *statError = nil;
        NSDictionary *attributes = [manager attributesOfItemAtPath:url.path error:&statError];
        if (!attributes) {
            if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Unable to stat path.", statError);
            return nil;
        }
        NSString *fileType = [attributes[NSFileType] isKindOfClass:NSString.class] ? attributes[NSFileType] : @"";
        BOOL isDirectory = [fileType isEqualToString:NSFileTypeDirectory];
        NSNumber *size = [attributes[NSFileSize] isKindOfClass:NSNumber.class] ? attributes[NSFileSize] : @0;
        NSDate *modified = [attributes[NSFileModificationDate] isKindOfClass:NSDate.class] ? attributes[NSFileModificationDate] : nil;
        return @{ @"name": url.lastPathComponent ?: @"",
                  @"path": url.path ?: @"",
                  @"isDirectory": @(isDirectory),
                  @"isFile": @(!isDirectory),
                  @"size": size,
                  @"modifiedAtMs": modified ? @([modified timeIntervalSince1970] * 1000.0) : [NSNull null] };
    }

    if ([operation isEqualToString:@"imageSize"] || [operation isEqualToString:@"md5File"] ||
        [operation isEqualToString:@"sha1File"]) {
        NSUInteger maximum = AutoSupportByteLimit(config, @"maxFileReadBytes", 10 * 1024 * 1024, 64 * 1024 * 1024);
        NSDictionary *attributes = [manager attributesOfItemAtPath:url.path error:nil];
        if ([attributes[NSFileSize] unsignedLongLongValue] > maximum) {
            if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"File exceeds maxFileReadBytes.", nil);
            return nil;
        }
        NSError *readError = nil;
        NSData *data = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:&readError];
        if (!data || data.length > maximum) {
            NSString *message = data ? @"File exceeds maxFileReadBytes." : @"Unable to read file.";
            if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, message, readError);
            return nil;
        }
        if ([operation isEqualToString:@"md5File"]) return AutoScriptMD5Hex(data);
        if ([operation isEqualToString:@"sha1File"]) return AutoScriptSHA1Hex(data);
        CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
        if (!source) {
            if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Image file is not supported.", nil);
            return nil;
        }
        NSDictionary *properties = (__bridge_transfer NSDictionary *)CGImageSourceCopyPropertiesAtIndex(source, 0, NULL);
        CFRelease(source);
        NSNumber *pixelWidth = properties[(__bridge NSString *)kCGImagePropertyPixelWidth];
        NSNumber *pixelHeight = properties[(__bridge NSString *)kCGImagePropertyPixelHeight];
        if (![pixelWidth isKindOfClass:NSNumber.class] || ![pixelHeight isKindOfClass:NSNumber.class]) {
            if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Image file has no pixel dimensions.", nil);
            return nil;
        }
        double pixelW = [pixelWidth doubleValue];
        double pixelH = [pixelHeight doubleValue];
        NSNumber *dpi = properties[(__bridge NSString *)kCGImagePropertyDPIWidth];
        double scale = [dpi isKindOfClass:NSNumber.class] && [dpi doubleValue] > 0 ? [dpi doubleValue] / 72.0 : 1.0;
        return @{ @"width": @(pixelW / scale), @"height": @(pixelH / scale),
                  @"pixelWidth": @(pixelW), @"pixelHeight": @(pixelH), @"scale": @(scale) };
    }

    if ([operation isEqualToString:@"imageProcess"] || [operation isEqualToString:@"imagePixelAt"]) {
        NSUInteger maximum = AutoSupportByteLimit(config, @"maxFileReadBytes", 10 * 1024 * 1024, 64 * 1024 * 1024);
        NSDictionary *sourceAttributes = [manager attributesOfItemAtPath:url.path error:nil];
        if ([sourceAttributes[NSFileSize] unsignedLongLongValue] > maximum) {
            if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"File exceeds maxFileReadBytes.", nil);
            return nil;
        }
        NSError *readError = nil;
        NSData *data = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:&readError];
        if (!data || data.length > maximum) {
            NSString *message = data ? @"File exceeds maxFileReadBytes." : @"Unable to read file.";
            if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, message, readError);
            return nil;
        }
        CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
        if (!source) {
            if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Image file is not supported.", nil);
            return nil;
        }
        NSDictionary *properties = (__bridge_transfer NSDictionary *)CGImageSourceCopyPropertiesAtIndex(source, 0, NULL);
        CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
        CFRelease(source);
        if (!image) {
            if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Unable to decode the image file.", nil);
            return nil;
        }
        double scale = AutoSupportImageScale(properties);
        if ([operation isEqualToString:@"imagePixelAt"]) {
            double x = AutoSupportFiniteDouble(payload[@"x"], NAN);
            double y = AutoSupportFiniteDouble(payload[@"y"], NAN);
            if (!isfinite(x) || !isfinite(y)) {
                CGImageRelease(image);
                if (error) *error = AutoSupportError(AutoSDKErrorInvalidConfiguration, @"image.pixelAt requires numeric x and y.", nil);
                return nil;
            }
            size_t pixelX = (size_t)MIN((size_t)CGImageGetWidth(image), (size_t)MAX(0, floor(x * scale)));
            size_t pixelY = (size_t)MIN((size_t)CGImageGetHeight(image), (size_t)MAX(0, floor(y * scale)));
            CGImageRef sample = CGImageCreateWithImageInRect(image, CGRectMake(pixelX, pixelY, 1, 1));
            CGImageRelease(image);
            if (!sample) {
                if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Unable to sample the image pixel.", nil);
                return nil;
            }
            AutoSupportPixelImage buffer = AutoSupportPixelImageMake(sample);
            CGImageRelease(sample);
            if (!buffer.bytes) {
                if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Unable to allocate a pixel buffer.", nil);
                return nil;
            }
            const uint8_t *pixel = buffer.bytes;
            NSDictionary *result = @{ @"x": @(x), @"y": @(y),
                                      @"r": @(pixel[0]), @"g": @(pixel[1]), @"b": @(pixel[2]), @"a": @(pixel[3]),
                                      @"hex": [NSString stringWithFormat:@"#%02X%02X%02X", pixel[0], pixel[1], pixel[2]] };
            AutoSupportPixelImageDestroy(&buffer);
            return result;
        }
        NSString *sub = [payload[@"sub"] isKindOfClass:NSString.class] ? [payload[@"sub"] lowercaseString] : @"";
        NSString *destinationPath = AutoRequiredString(payload[@"destination"], @"destination", error);
        NSURL *destinationURL = nil;
        if (destinationPath) destinationURL = AutoResolveFilePath(destinationPath, config, NO, error);
        if (!destinationURL) {
            CGImageRelease(image);
            return nil;
        }
        NSDictionary *args = [payload[@"args"] isKindOfClass:NSDictionary.class] ? payload[@"args"] : @{};
        CGImageRef processed = NULL;
        if ([sub isEqualToString:@"clip"]) {
            processed = AutoSupportImageClip(image, scale,
                                             AutoSupportFiniteDouble(args[@"x"], 0),
                                             AutoSupportFiniteDouble(args[@"y"], 0),
                                             AutoSupportFiniteDouble(args[@"ex"], 0),
                                             AutoSupportFiniteDouble(args[@"ey"], 0));
        } else if ([sub isEqualToString:@"scale"]) {
            processed = AutoSupportImageScale(image, scale,
                                              AutoSupportFiniteDouble(args[@"width"], 0),
                                              AutoSupportFiniteDouble(args[@"height"], 0));
        } else if ([sub isEqualToString:@"gray"]) {
            processed = AutoSupportImageMono(image, NO, 0);
        } else if ([sub isEqualToString:@"binaryzation"]) {
            double threshold = AutoSupportFiniteDouble(args[@"threshold"], 128);
            processed = AutoSupportImageMono(image, YES, (NSUInteger)MIN(255, MAX(0, threshold)));
        } else if ([sub isEqualToString:@"rotate"]) {
            processed = AutoSupportImageRotate(image, (NSInteger)AutoSupportFiniteDouble(args[@"degrees"], 0));
        } else {
            CGImageRelease(image);
            if (error) *error = AutoSupportError(AutoSDKErrorInvalidConfiguration,
                                                 @"imageProcess sub must be clip, scale, gray, binaryzation or rotate.", nil);
            return nil;
        }
        CGImageRelease(image);
        if (!processed) {
            if (error) *error = AutoSupportError(AutoSDKErrorInvalidConfiguration, @"Unable to process the image with the given arguments.", nil);
            return nil;
        }
        BOOL written = AutoSupportWriteImage(processed, destinationURL, config, error);
        CGImageRelease(processed);
        return written ? destinationURL.path : nil;
    }

    if ([operation isEqualToString:@"readText"] || [operation isEqualToString:@"readBase64"] ||
        [operation isEqualToString:@"readLines"]) {
        NSUInteger maximum = AutoSupportByteLimit(config, @"maxFileReadBytes",
                                                   10 * 1024 * 1024, 64 * 1024 * 1024);
        NSDictionary *attributes = [manager attributesOfItemAtPath:url.path error:nil];
        if ([attributes[NSFileSize] unsignedLongLongValue] > maximum) {
            if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"File exceeds maxFileReadBytes.", nil);
            return nil;
        }
        NSError *readError = nil;
        NSData *data = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:&readError];
        if (!data || data.length > maximum) {
            NSString *message = data ? @"File exceeds maxFileReadBytes." : @"Unable to read file.";
            if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, message, readError);
            return nil;
        }
        if ([operation isEqualToString:@"readBase64"]) return [data base64EncodedStringWithOptions:0];
        if ([operation isEqualToString:@"readLines"]) {
            NSUInteger maximumLines = AutoSupportByteLimit(config, @"maxFileLineCount", 100000, 1000000);
            NSUInteger lineCount = 1;
            const uint8_t *bytes = data.bytes;
            for (NSUInteger index = 0; index < data.length; index++) {
                if (bytes[index] == '\n' && ++lineCount > maximumLines) {
                    if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"File exceeds maxFileLineCount.", nil);
                    return nil;
                }
            }
        }
        NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!text && error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"File is not valid UTF-8.", nil);
        if (!text || ![operation isEqualToString:@"readLines"]) return text;
        NSArray<NSString *> *rawLines = [text componentsSeparatedByString:@"\n"];
        NSMutableArray<NSString *> *lines = [NSMutableArray arrayWithCapacity:rawLines.count];
        for (NSString *line in rawLines) {
            [lines addObject:[line hasSuffix:@"\r"] ? [line substringToIndex:line.length - 1] : line];
        }
        return lines;
    }

    if ([operation isEqualToString:@"writeText"] || [operation isEqualToString:@"writeBase64"] || [operation isEqualToString:@"appendText"]) {
        NSString *text = AutoRequiredString(payload[@"text"], [operation isEqualToString:@"writeBase64"] ? @"base64" : @"text", error);
        if (!text) return nil;
        NSUInteger maximum = AutoSupportByteLimit(config, @"maxFileWriteBytes",
                                                   10 * 1024 * 1024, 64 * 1024 * 1024);
        if ([operation isEqualToString:@"writeBase64"]) {
            NSUInteger maximumEncodedLength = (maximum / 3) * 4 + 4;
            if (text.length > maximumEncodedLength) {
                if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Data exceeds maxFileWriteBytes.", nil);
                return nil;
            }
        } else if ([text lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > maximum) {
            if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Data exceeds maxFileWriteBytes.", nil);
            return nil;
        }
        NSError *directoryError = nil;
        if (![manager createDirectoryAtURL:url.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&directoryError]) {
            if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Unable to create the parent directory.", directoryError);
            return nil;
        }
        NSData *data = [operation isEqualToString:@"writeBase64"]
            ? [[NSData alloc] initWithBase64EncodedString:text options:0]
            : [text dataUsingEncoding:NSUTF8StringEncoding];
        if (!data) {
            if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Data is not valid base64.", nil);
            return nil;
        }
        unsigned long long existingSize = 0;
        if ([operation isEqualToString:@"appendText"] && [manager fileExistsAtPath:url.path]) {
            existingSize = [[[manager attributesOfItemAtPath:url.path error:nil] objectForKey:NSFileSize] unsignedLongLongValue];
        }
        if (data.length > maximum || existingSize > maximum - data.length) {
            if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Data exceeds maxFileWriteBytes.", nil);
            return nil;
        }
        NSError *writeError = nil;
        if ([operation isEqualToString:@"appendText"] && [manager fileExistsAtPath:url.path]) {
            NSFileHandle *handle = [NSFileHandle fileHandleForWritingToURL:url error:&writeError];
            @try {
                [handle seekToEndOfFile];
                [handle writeData:data];
            } @catch (NSException *exception) {
                writeError = AutoSupportError(AutoSDKErrorFileOperationFailed, exception.reason, nil);
            } @finally {
                @try {
                    [handle closeFile];
                } @catch (NSException *exception) {
                    if (!writeError) writeError = AutoSupportError(AutoSDKErrorFileOperationFailed, exception.reason, nil);
                }
            }
        } else {
            [data writeToURL:url options:NSDataWritingAtomic error:&writeError];
        }
        if (writeError) {
            if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Unable to write file.", writeError);
            return nil;
        }
        return @YES;
    }

    if ([operation isEqualToString:@"list"]) {
        __block NSError *listError = nil;
        NSNumber *isDirectory = nil;
        if (![url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:&listError] || !isDirectory.boolValue) {
            if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Unable to list a path that is not a directory.", listError);
            return nil;
        }
        NSUInteger maximumItems = AutoSupportByteLimit(config, @"maxFileListItems", 2000, 10000);
        NSDirectoryEnumerator<NSURL *> *items = [manager enumeratorAtURL:url
            includingPropertiesForKeys:@[NSURLIsDirectoryKey, NSURLFileSizeKey, NSURLContentModificationDateKey]
                               options:NSDirectoryEnumerationSkipsHiddenFiles | NSDirectoryEnumerationSkipsSubdirectoryDescendants
                          errorHandler:^BOOL(NSURL *itemURL, NSError *encounteredError) {
                              listError = encounteredError;
                              return NO;
                          }];
        NSMutableArray *result = [NSMutableArray arrayWithCapacity:MIN(maximumItems, (NSUInteger)128)];
        NSError *iterationError = nil;
        for (NSURL *item in items) {
            @autoreleasepool {
                if (result.count >= maximumItems) {
                    iterationError = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Directory exceeds maxFileListItems.", nil);
                    break;
                }
                NSError *itemError = nil;
                NSDictionary *values = [item resourceValuesForKeys:@[NSURLIsDirectoryKey, NSURLFileSizeKey, NSURLContentModificationDateKey]
                                                              error:&itemError];
                if (!values) {
                    iterationError = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Unable to inspect a listed item.", itemError);
                    break;
                }
                NSDate *date = values[NSURLContentModificationDateKey];
                [result addObject:@{ @"name": item.lastPathComponent ?: @"",
                                     @"path": item.path ?: @"",
                                     @"isDirectory": values[NSURLIsDirectoryKey] ?: @NO,
                                     @"size": values[NSURLFileSizeKey] ?: @0,
                                     @"modifiedAtMs": date ? @([date timeIntervalSince1970] * 1000.0) : [NSNull null] }];
            }
        }
        if (iterationError) {
            if (error) *error = iterationError;
            return nil;
        }
        if (listError) {
            if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Unable to list directory.", listError);
            return nil;
        }
        return result;
    }

    if ([operation isEqualToString:@"mkdir"]) {
        NSError *mkdirError = nil;
        BOOL ok = [manager createDirectoryAtURL:url withIntermediateDirectories:YES attributes:nil error:&mkdirError];
        if (!ok && error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Unable to create directory.", mkdirError);
        return ok ? @YES : nil;
    }

    if ([operation isEqualToString:@"remove"]) {
        if (![manager fileExistsAtPath:url.path]) return @YES;
        NSUInteger maximumItems = AutoSupportByteLimit(config, @"maxFileOperationItems", 4096, 100000);
        if (!AutoValidateTreeBudget(url, NSUIntegerMax, maximumItems, @"Remove operation", error)) return nil;
        NSError *removeError = nil;
        BOOL ok = [manager removeItemAtURL:url error:&removeError];
        if (!ok && error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Unable to remove path.", removeError);
        return ok ? @YES : nil;
    }

    if ([operation isEqualToString:@"copy"]) {
        NSString *destinationPath = AutoRequiredString(payload[@"destination"], @"destination", error);
        if (!destinationPath) return nil;
        NSURL *destination = AutoResolveFilePath(destinationPath, config, NO, error);
        if (!destination) return nil;
        if (![manager fileExistsAtPath:url.path]) {
            if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Source path does not exist.", nil);
            return nil;
        }
        NSString *sourcePath = url.path;
        NSString *destinationValue = destination.path;
        if ([sourcePath isEqualToString:destinationValue] ||
            [destinationValue hasPrefix:[sourcePath stringByAppendingString:@"/"]]) {
            if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Destination cannot be the source or one of its children.", nil);
            return nil;
        }
        NSUInteger defaultCopyBytes = AutoSupportByteLimit(config, @"maxFileWriteBytes",
                                                            10 * 1024 * 1024, 64 * 1024 * 1024);
        NSUInteger maximumCopyBytes = AutoSupportByteLimit(config, @"maxFileCopyBytes",
                                                            defaultCopyBytes, 64 * 1024 * 1024);
        NSUInteger maximumItems = AutoSupportByteLimit(config, @"maxFileOperationItems", 4096, 100000);
        if (!AutoValidateTreeBudget(url, maximumCopyBytes, maximumItems, @"Copy operation", error)) return nil;
        NSError *directoryError = nil;
        [manager createDirectoryAtURL:destination.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&directoryError];
        if (directoryError) {
            if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Unable to create the destination directory.", directoryError);
            return nil;
        }
        BOOL destinationExists = [manager fileExistsAtPath:destination.path];
        if (destinationExists && !([payload[@"overwrite"] isKindOfClass:NSNumber.class] && [payload[@"overwrite"] boolValue])) {
            if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Destination already exists.", nil);
            return nil;
        }
        NSString *stagingName = [NSString stringWithFormat:@".autosdk-copy-%@", NSUUID.UUID.UUIDString];
        NSURL *staging = [destination.URLByDeletingLastPathComponent URLByAppendingPathComponent:stagingName];
        NSError *copyError = nil;
        BOOL ok = [manager copyItemAtURL:url toURL:staging error:&copyError];
        if (!ok) {
            [manager removeItemAtURL:staging error:nil];
            if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Unable to copy path.", copyError);
            return nil;
        }
        if (destinationExists) {
            NSURL *resultingURL = nil;
            NSError *replaceError = nil;
            ok = [manager replaceItemAtURL:destination withItemAtURL:staging backupItemName:nil options:0 resultingItemURL:&resultingURL error:&replaceError];
            if (!ok) {
                [manager removeItemAtURL:staging error:nil];
                if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Unable to replace the destination path.", replaceError);
                return nil;
            }
        } else {
            ok = [manager moveItemAtURL:staging toURL:destination error:&copyError];
            if (!ok) [manager removeItemAtURL:staging error:nil];
        }
        if (!ok && error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Unable to finalize the copied path.", copyError);
        return ok ? @YES : nil;
    }

    if ([operation isEqualToString:@"move"]) {
        NSString *destinationPath = AutoRequiredString(payload[@"destination"], @"destination", error);
        if (!destinationPath) return nil;
        NSURL *destination = AutoResolveFilePath(destinationPath, config, NO, error);
        if (!destination) return nil;
        if (![manager fileExistsAtPath:url.path]) {
            if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Source path does not exist.", nil);
            return nil;
        }
        NSString *sourcePath = url.path;
        NSString *destinationValue = destination.path;
        if ([sourcePath isEqualToString:destinationValue] ||
            [destinationValue hasPrefix:[sourcePath stringByAppendingString:@"/"]]) {
            if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Destination cannot be the source or one of its children.", nil);
            return nil;
        }
        NSUInteger defaultBytes = AutoSupportByteLimit(config, @"maxFileWriteBytes", 10 * 1024 * 1024, 64 * 1024 * 1024);
        NSUInteger maximumBytes = AutoSupportByteLimit(config, @"maxFileCopyBytes", defaultBytes, 64 * 1024 * 1024);
        NSUInteger maximumItems = AutoSupportByteLimit(config, @"maxFileOperationItems", 4096, 100000);
        if (!AutoValidateTreeBudget(url, maximumBytes, maximumItems, @"Move operation", error)) return nil;
        NSError *directoryError = nil;
        [manager createDirectoryAtURL:destination.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&directoryError];
        if (directoryError) {
            if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Unable to create the destination directory.", directoryError);
            return nil;
        }
        BOOL destinationExists = [manager fileExistsAtPath:destination.path];
        if (destinationExists && !([payload[@"overwrite"] isKindOfClass:NSNumber.class] && [payload[@"overwrite"] boolValue])) {
            if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Destination already exists.", nil);
            return nil;
        }
        if (destinationExists) {
            NSError *removeError = nil;
            if (![manager removeItemAtURL:destination error:&removeError]) {
                if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Unable to replace the destination path.", removeError);
                return nil;
            }
        }
        NSError *moveError = nil;
        BOOL ok = [manager moveItemAtURL:url toURL:destination error:&moveError];
        if (!ok && error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Unable to move path.", moveError);
        return ok ? @YES : nil;
    }

    if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Unknown file operation.", nil);
    return nil;
    }
}

static NSString *AutoStorageDefaultsKey(NSString *name, NSError **error) {
    if (![name isKindOfClass:NSString.class] || name.length == 0 || name.length > 64) {
        if (error) *error = AutoSupportError(AutoSDKErrorStorageFailed, @"Storage name must contain 1 to 64 characters.", nil);
        return nil;
    }
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"];
    if ([name rangeOfCharacterFromSet:allowed.invertedSet].location != NSNotFound) {
        if (error) *error = AutoSupportError(AutoSDKErrorStorageFailed, @"Storage name contains unsupported characters.", nil);
        return nil;
    }
    return [@"AutoSDK.storage." stringByAppendingString:name];
}

static NSMutableDictionary *AutoLoadStorage(NSString *defaultsKey,
                                            NSUInteger maximumBytes,
                                            NSUInteger maximumEntries,
                                            NSError **error) {
    id storedValue = [NSUserDefaults.standardUserDefaults objectForKey:defaultsKey];
    if (!storedValue) return [NSMutableDictionary dictionary];
    if (![storedValue isKindOfClass:NSData.class]) {
        if (error) *error = AutoSupportError(AutoSDKErrorStorageFailed, @"Stored data is corrupt.", nil);
        return nil;
    }
    NSData *data = storedValue;
    if (data.length > maximumBytes) {
        if (error) *error = AutoSupportError(AutoSDKErrorStorageFailed, @"Stored data exceeds maxStorageBytes.", nil);
        return nil;
    }
    NSError *decodeError = nil;
    id object = nil;
    @try {
        object = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&decodeError];
    } @catch (NSException *exception) {
        decodeError = AutoSupportError(AutoSDKErrorStorageFailed,
                                       exception.reason ?: @"Stored data is corrupt.", nil);
    }
    if (![object isKindOfClass:NSDictionary.class]) {
        if (error) *error = AutoSupportError(AutoSDKErrorStorageFailed, @"Stored data is corrupt.", decodeError);
        return nil;
    }
    if ([(NSDictionary *)object count] > maximumEntries) {
        if (error) *error = AutoSupportError(AutoSDKErrorStorageFailed, @"Stored data exceeds maxStorageEntries.", nil);
        return nil;
    }
    return [object mutableCopy];
}

id AutoScriptStorageOperation(NSDictionary<NSString *,id> *payload,
                              NSDictionary<NSString *,id> *config,
                              NSError **error) {
    if (!AutoConfigAllows(config, @"allowStorage", YES)) {
        if (error) *error = AutoSupportError(AutoSDKErrorStorageFailed, @"Script storage is disabled by configuration.", nil);
        return nil;
    }
    NSString *defaultsKey = AutoStorageDefaultsKey(payload[@"name"], error);
    if (!defaultsKey) return nil;
    NSString *operation = [payload[@"operation"] isKindOfClass:NSString.class] ? payload[@"operation"] : @"";
    NSString *key = [payload[@"key"] isKindOfClass:NSString.class] ? payload[@"key"] : nil;
    NSSet *keyOperations = [NSSet setWithArray:@[@"put", @"get", @"remove", @"contains"]];
    if ([keyOperations containsObject:operation] && (key.length == 0 || key.length > 256)) {
        if (error) *error = AutoSupportError(AutoSDKErrorStorageFailed, @"Storage key must contain 1 to 256 characters.", nil);
        return nil;
    }
    NSUInteger maximum = AutoSupportByteLimit(config, @"maxStorageBytes",
                                               1024 * 1024, 16 * 1024 * 1024);
    NSUInteger maximumEntries = AutoSupportByteLimit(config, @"maxStorageEntries", 4096, 100000);

    @synchronized (NSUserDefaults.standardUserDefaults) {
        if ([operation isEqualToString:@"clear"]) {
            [NSUserDefaults.standardUserDefaults removeObjectForKey:defaultsKey];
            return @YES;
        }
        NSMutableDictionary *storage = AutoLoadStorage(defaultsKey, maximum, maximumEntries, error);
        if (!storage) return nil;
        if ([operation isEqualToString:@"keys"]) return [storage.allKeys sortedArrayUsingSelector:@selector(compare:)];
        if ([operation isEqualToString:@"all"]) return [storage copy];
        if ([operation isEqualToString:@"contains"]) return @(storage[key] != nil);
        if ([operation isEqualToString:@"get"]) return storage[key] ?: payload[@"defaultValue"] ?: [NSNull null];
        if ([operation isEqualToString:@"remove"]) [storage removeObjectForKey:key];
        else if ([operation isEqualToString:@"put"]) {
            id value = payload[@"value"] ?: [NSNull null];
            BOOL validValue = NO;
            @try {
                validValue = [NSJSONSerialization isValidJSONObject:@[value]];
            } @catch (__unused NSException *exception) {
                validValue = NO;
            }
            if (!validValue) {
                if (error) *error = AutoSupportError(AutoSDKErrorStorageFailed, @"Storage values must be JSON-serializable.", nil);
                return nil;
            }
            if (storage[key] == nil && storage.count >= maximumEntries) {
                if (error) *error = AutoSupportError(AutoSDKErrorStorageFailed, @"Storage exceeds maxStorageEntries.", nil);
                return nil;
            }
            storage[key] = value;
        } else {
            if (error) *error = AutoSupportError(AutoSDKErrorStorageFailed, @"Unknown storage operation.", nil);
            return nil;
        }
        NSError *encodeError = nil;
        NSData *data = nil;
        @try {
            data = [NSJSONSerialization dataWithJSONObject:storage options:0 error:&encodeError];
        } @catch (NSException *exception) {
            encodeError = AutoSupportError(AutoSDKErrorStorageFailed,
                                           exception.reason ?: @"Unable to encode storage data.", nil);
        }
        if (!data || data.length > maximum) {
            NSString *message = data ? @"Storage exceeds maxStorageBytes." : @"Unable to encode storage data.";
            if (error) *error = AutoSupportError(AutoSDKErrorStorageFailed, message, encodeError);
            return nil;
        }
        [NSUserDefaults.standardUserDefaults setObject:data forKey:defaultsKey];
        return @YES;
    }
}
