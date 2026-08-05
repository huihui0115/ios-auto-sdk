#import "AutoScriptSupport.h"
#import <CoreFoundation/CoreFoundation.h>
#import "include/AutoSDKError.h"
#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonCryptor.h>
#import <ImageIO/ImageIO.h>
#include <math.h>
#include <string.h>
#include <zlib.h>

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

NSString *AutoScriptSHA256Hex(NSData *data) {
    if (data.length == 0) return @"";
    unsigned char digest[CC_SHA256_DIGEST_LENGTH] = {0};
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    return AutoHexFromBytes(digest, CC_SHA256_DIGEST_LENGTH);
}

NSString *AutoScriptSHA512Hex(NSData *data) {
    if (data.length == 0) return @"";
    unsigned char digest[CC_SHA512_DIGEST_LENGTH] = {0};
    CC_SHA512(data.bytes, (CC_LONG)data.length, digest);
    return AutoHexFromBytes(digest, CC_SHA512_DIGEST_LENGTH);
}

NSString *AutoScriptAES128EncryptBase64(NSString *plaintext, NSString *key) {
    if (plaintext.length == 0) return @"";
    NSData *keyData = [key dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char fixedKey[kCCKeySizeAES128] = {0};
    NSUInteger copyLength = MIN(keyData.length, kCCKeySizeAES128);
    if (copyLength > 0) memcpy(fixedKey, keyData.bytes, copyLength);
    NSData *input = [plaintext dataUsingEncoding:NSUTF8StringEncoding];
    size_t bufferSize = input.length + kCCBlockSizeAES128;
    NSMutableData *buffer = [NSMutableData dataWithLength:bufferSize];
    size_t written = 0;
    CCCryptorStatus status = CCCrypt(kCCEncrypt,
                                     kCCAlgorithmAES128,
                                     kCCOptionPKCS7Padding | kCCOptionECBMode,
                                     fixedKey, kCCKeySizeAES128,
                                     NULL,
                                     input.bytes, input.length,
                                     buffer.mutableBytes, bufferSize,
                                     &written);
    if (status != kCCSuccess) return @"";
    return [[buffer subdataWithRange:NSMakeRange(0, written)] base64EncodedStringWithOptions:0];
}

NSString *AutoScriptAES128DecryptBase64(NSString *base64, NSString *key) {
    if (base64.length == 0) return @"";
    NSData *keyData = [key dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char fixedKey[kCCKeySizeAES128] = {0};
    NSUInteger copyLength = MIN(keyData.length, kCCKeySizeAES128);
    if (copyLength > 0) memcpy(fixedKey, keyData.bytes, copyLength);
    NSData *input = [[NSData alloc] initWithBase64EncodedString:base64 options:0];
    if (!input) return @"";
    size_t bufferSize = input.length + kCCBlockSizeAES128;
    NSMutableData *buffer = [NSMutableData dataWithLength:bufferSize];
    size_t written = 0;
    CCCryptorStatus status = CCCrypt(kCCDecrypt,
                                     kCCAlgorithmAES128,
                                     kCCOptionPKCS7Padding | kCCOptionECBMode,
                                     fixedKey, kCCKeySizeAES128,
                                     NULL,
                                     input.bytes, input.length,
                                     buffer.mutableBytes, bufferSize,
                                     &written);
    if (status != kCCSuccess) return @"";
    NSData *decrypted = [buffer subdataWithRange:NSMakeRange(0, written)];
    return [[NSString alloc] initWithData:decrypted encoding:NSUTF8StringEncoding] ?: @"";
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

// ===== ZIP archive support (raw DEFLATE via zlib, RFC 1951 containers) =====
@interface AutoZipEntry : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) uint32_t method;
@property (nonatomic, assign) uint32_t crc;
@property (nonatomic, assign) uint32_t compressedSize;
@property (nonatomic, assign) uint32_t uncompressedSize;
@property (nonatomic, assign) uint32_t localOffset;
@property (nonatomic, assign) BOOL isDirectory;
@end
@implementation AutoZipEntry
@end

static uint32_t AutoZipCRC32(const uint8_t *bytes, size_t length) {
    static uint32_t table[256];
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        for (uint32_t i = 0; i < 256; i++) {
            uint32_t crc = i;
            for (int bit = 0; bit < 8; bit++) {
                crc = (crc & 1) ? (crc >> 1) ^ 0xEDB88320u : crc >> 1;
            }
            table[i] = crc;
        }
    });
    uint32_t crc = 0xFFFFFFFFu;
    for (size_t i = 0; i < length; i++) {
        crc = table[(crc ^ bytes[i]) & 0xFFu] ^ (crc >> 8);
    }
    return crc ^ 0xFFFFFFFFu;
}

static void AutoZipAppendUInt16(NSMutableData *data, uint16_t value) {
    uint8_t bytes[2] = { (uint8_t)(value & 0xFF), (uint8_t)(value >> 8) };
    [data appendBytes:bytes length:2];
}

static void AutoZipAppendUInt32(NSMutableData *data, uint32_t value) {
    uint8_t bytes[4] = { (uint8_t)(value & 0xFF), (uint8_t)((value >> 8) & 0xFF),
                         (uint8_t)((value >> 16) & 0xFF), (uint8_t)((value >> 24) & 0xFF) };
    [data appendBytes:bytes length:4];
}

static uint16_t AutoZipReadUInt16(const uint8_t *bytes) {
    return (uint16_t)(bytes[0] | (bytes[1] << 8));
}

static uint32_t AutoZipReadUInt32(const uint8_t *bytes) {
    return (uint32_t)bytes[0] | ((uint32_t)bytes[1] << 8) |
           ((uint32_t)bytes[2] << 16) | ((uint32_t)bytes[3] << 24);
}

static NSString *AutoZipDecodeName(NSData *nameData) {
    NSString *utf8 = [[NSString alloc] initWithData:nameData encoding:NSUTF8StringEncoding];
    if (utf8) return utf8;
    NSStringEncoding gbk = CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000);
    return [[NSString alloc] initWithData:nameData encoding:gbk];
}

static void AutoZipDOSDateTime(NSDate *date, uint16_t *dosTime, uint16_t *dosDate) {
    NSDateComponents *components = [[NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian]
        components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay |
                    NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond
           fromDate:date ?: [NSDate date]];
    NSInteger year = components.year;
    if (year < 1980) year = 1980;
    if (year > 2107) year = 2107;
    if (dosDate) *dosDate = (uint16_t)(((year - 1980) << 9) | (components.month << 5) | components.day);
    if (dosTime) *dosTime = (uint16_t)((components.hour << 11) | (components.minute << 5) | (components.second / 2));
}

static NSData *AutoZipDeflateData(NSData *input, NSError **error) {
    if (input.length > UINT32_MAX) {
        if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Zip entry is too large to compress.", nil);
        return nil;
    }
    z_stream stream;
    memset(&stream, 0, sizeof(stream));
    if (deflateInit2(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -15, 8, Z_DEFAULT_STRATEGY) != Z_OK) {
        if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Unable to initialize the deflate compressor.", nil);
        return nil;
    }
    NSMutableData *output = [NSMutableData dataWithCapacity:input.length / 2 + 64];
    uint8_t buffer[64 * 1024];
    stream.next_in = (Bytef *)input.bytes;
    stream.avail_in = (uInt)input.length;
    int result = Z_OK;
    while (result != Z_STREAM_END) {
        stream.next_out = buffer;
        stream.avail_out = sizeof(buffer);
        result = deflate(&stream, Z_FINISH);
        if (result != Z_OK && result != Z_STREAM_END) break;
        [output appendBytes:buffer length:sizeof(buffer) - stream.avail_out];
    }
    deflateEnd(&stream);
    if (result != Z_STREAM_END) {
        if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Unable to deflate the zip entry.", nil);
        return nil;
    }
    return output;
}

static NSData *AutoZipInflateData(NSData *input, NSUInteger expectedSize, NSError **error) {
    if (input.length > UINT32_MAX) {
        if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Zip entry is too large to decompress.", nil);
        return nil;
    }
    z_stream stream;
    memset(&stream, 0, sizeof(stream));
    if (inflateInit2(&stream, -15) != Z_OK) {
        if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Unable to initialize the inflate decompressor.", nil);
        return nil;
    }
    NSUInteger capacity = expectedSize > 0 && expectedSize <= 256 * 1024 * 1024 ? expectedSize : 64 * 1024;
    NSMutableData *output = [NSMutableData dataWithCapacity:capacity];
    uint8_t buffer[64 * 1024];
    stream.next_in = (Bytef *)input.bytes;
    stream.avail_in = (uInt)input.length;
    int result = Z_OK;
    while (result != Z_STREAM_END) {
        stream.next_out = buffer;
        stream.avail_out = sizeof(buffer);
        result = inflate(&stream, Z_NO_FLUSH);
        if (result != Z_OK && result != Z_STREAM_END) break;
        [output appendBytes:buffer length:sizeof(buffer) - stream.avail_out];
        if (output.length > 512 * 1024 * 1024) {
            result = Z_MEM_ERROR;
            break;
        }
    }
    inflateEnd(&stream);
    if (result != Z_STREAM_END) {
        if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Unable to inflate the zip entry.", nil);
        return nil;
    }
    return output;
}

static BOOL AutoZipBuildArchive(NSArray *sources, NSDictionary *config, NSData **output, NSError **error) {
    NSMutableArray<AutoZipEntry *> *entries = [NSMutableArray array];
    NSMutableData *archive = [NSMutableData data];
    NSFileManager *manager = NSFileManager.defaultManager;
    NSUInteger maximumRead = AutoSupportByteLimit(config, @"maxFileReadBytes", 10 * 1024 * 1024, 64 * 1024 * 1024);
    NSUInteger maximumWrite = AutoSupportByteLimit(config, @"maxFileWriteBytes", 10 * 1024 * 1024, 64 * 1024 * 1024);
    __block NSError *buildError = nil;
    __block NSUInteger entryCount = 0;
    __block NSUInteger totalInputBytes = 0;
    const NSUInteger maximumEntries = 2000;
    const NSUInteger maximumDepth = 32;
    __block void (^addPath)(NSURL *, NSString *, NSUInteger) = nil;
    addPath = ^(NSURL *sourceURL, NSString *entryName, NSUInteger depth) {
        if (buildError || entryCount >= maximumEntries) return;
        NSDictionary *attributes = [manager attributesOfItemAtPath:sourceURL.path error:nil];
        NSString *fileType = [attributes[NSFileType] isKindOfClass:NSString.class] ? attributes[NSFileType] : @"";
        if ([fileType isEqualToString:NSFileTypeDirectory]) {
            if (depth >= maximumDepth) {
                buildError = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Zip folder nesting exceeds the depth limit.", nil);
                return;
            }
            NSError *listError = nil;
            NSArray<NSURL *> *contents = [manager contentsOfDirectoryAtURL:sourceURL
                                                includingPropertiesForKeys:nil
                                                                   options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                     error:&listError];
            if (listError || !contents) {
                buildError = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Unable to enumerate the zip folder.", listError);
                return;
            }
            AutoZipEntry *directoryEntry = [AutoZipEntry new];
            directoryEntry.name = [entryName stringByAppendingString:@"/"];
            directoryEntry.isDirectory = YES;
            [entries addObject:directoryEntry];
            entryCount += 1;
            for (NSURL *child in contents) {
                addPath(child, [entryName stringByAppendingPathComponent:child.lastPathComponent], depth + 1);
                if (buildError) return;
            }
            return;
        }
        if (![fileType isEqualToString:NSFileTypeRegular]) {
            buildError = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Zip sources must be regular files or directories.", nil);
            return;
        }
        unsigned long long size = [attributes[NSFileSize] unsignedLongLongValue];
        if (size > maximumRead) {
            buildError = AutoSupportError(AutoSDKErrorFileOperationFailed, @"A zip source file exceeds maxFileReadBytes.", nil);
            return;
        }
        totalInputBytes += (NSUInteger)size;
        if (totalInputBytes > 512 * 1024 * 1024) {
            buildError = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Zip input exceeds the 512 MB total limit.", nil);
            return;
        }
        NSError *readError = nil;
        NSData *fileData = [NSData dataWithContentsOfURL:sourceURL options:NSDataReadingMappedIfSafe error:&readError];
        if (!fileData || fileData.length > maximumRead) {
            buildError = AutoSupportError(AutoSDKErrorFileOperationFailed,
                                          fileData ? @"A zip source file exceeds maxFileReadBytes." : @"Unable to read a zip source file.", readError);
            return;
        }
        NSError *deflateError = nil;
        NSData *compressed = AutoZipDeflateData(fileData, &deflateError);
        if (deflateError) {
            buildError = deflateError;
            return;
        }
        BOOL storeRaw = compressed.length >= fileData.length;
        NSData *payload = storeRaw ? fileData : compressed;
        if (archive.length + 30 + entryName.length > UINT32_MAX) {
            buildError = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Zip archive is too large.", nil);
            return;
        }
        AutoZipEntry *entry = [AutoZipEntry new];
        entry.name = entryName;
        entry.method = storeRaw ? 0 : 8;
        entry.crc = AutoZipCRC32(fileData.bytes, fileData.length);
        entry.compressedSize = (uint32_t)payload.length;
        entry.uncompressedSize = (uint32_t)fileData.length;
        entry.localOffset = (uint32_t)archive.length;
        [entries addObject:entry];
        entryCount += 1;
        AutoZipAppendUInt32(archive, 0x04034b50);
        AutoZipAppendUInt16(archive, 20);
        AutoZipAppendUInt16(archive, 0x0800);
        AutoZipAppendUInt16(archive, entry.method);
        uint16_t dosTime = 0, dosDate = 0;
        AutoZipDOSDateTime(attributes[NSFileModificationDate], &dosTime, &dosDate);
        AutoZipAppendUInt16(archive, dosTime);
        AutoZipAppendUInt16(archive, dosDate);
        AutoZipAppendUInt32(archive, entry.crc);
        AutoZipAppendUInt32(archive, entry.compressedSize);
        AutoZipAppendUInt32(archive, entry.uncompressedSize);
        NSData *nameData = [entryName dataUsingEncoding:NSUTF8StringEncoding];
        AutoZipAppendUInt16(archive, (uint16_t)nameData.length);
        AutoZipAppendUInt16(archive, 0);
        [archive appendData:nameData];
        [archive appendData:payload];
        if (archive.length > maximumWrite) {
            buildError = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Zip output exceeds maxFileWriteBytes.", nil);
            return;
        }
    };
    for (id source in sources) {
        if (buildError) break;
        if (![source isKindOfClass:NSString.class] || [source length] == 0) {
            buildError = AutoSupportError(AutoSDKErrorInvalidConfiguration, @"Zip sources must be non-empty paths.", nil);
            break;
        }
        NSError *resolveError = nil;
        NSURL *sourceURL = AutoResolveFilePath(source, config, NO, &resolveError);
        if (!sourceURL) {
            buildError = resolveError ?: AutoSupportError(AutoSDKErrorFileOperationFailed, @"Unable to resolve a zip source path.", nil);
            break;
        }
        addPath(sourceURL, sourceURL.lastPathComponent, 0);
    }
    if (buildError) {
        if (error) *error = buildError;
        return NO;
    }
    uint32_t centralOffset = (uint32_t)archive.length;
    NSMutableData *central = [NSMutableData data];
    uint16_t dosTime = 0, dosDate = 0;
    AutoZipDOSDateTime(nil, &dosTime, &dosDate);
    for (AutoZipEntry *entry in entries) {
        NSData *nameData = [entry.name dataUsingEncoding:NSUTF8StringEncoding];
        AutoZipAppendUInt32(central, 0x02014b50);
        AutoZipAppendUInt16(central, 20);
        AutoZipAppendUInt16(central, 20);
        AutoZipAppendUInt16(central, 0x0800);
        AutoZipAppendUInt16(central, entry.method);
        AutoZipAppendUInt16(central, dosTime);
        AutoZipAppendUInt16(central, dosDate);
        AutoZipAppendUInt32(central, entry.crc);
        AutoZipAppendUInt32(central, entry.compressedSize);
        AutoZipAppendUInt32(central, entry.uncompressedSize);
        AutoZipAppendUInt16(central, (uint16_t)nameData.length);
        AutoZipAppendUInt16(central, 0);
        AutoZipAppendUInt16(central, 0);
        AutoZipAppendUInt16(central, 0);
        AutoZipAppendUInt16(central, 0);
        AutoZipAppendUInt32(central, entry.isDirectory ? 0x10 : 0);
        AutoZipAppendUInt32(central, entry.localOffset);
        [central appendData:nameData];
    }
    [archive appendData:central];
    AutoZipAppendUInt32(archive, 0x06054b50);
    AutoZipAppendUInt16(archive, 0);
    AutoZipAppendUInt16(archive, 0);
    AutoZipAppendUInt16(archive, (uint16_t)entries.count);
    AutoZipAppendUInt16(archive, (uint16_t)entries.count);
    AutoZipAppendUInt32(archive, (uint32_t)central.length);
    AutoZipAppendUInt32(archive, centralOffset);
    AutoZipAppendUInt16(archive, 0);
    if (archive.length > maximumWrite) {
        if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Zip output exceeds maxFileWriteBytes.", nil);
        return NO;
    }
    if (output) *output = archive;
    return YES;
}

static BOOL AutoZipFindEndOfCentralDirectory(NSData *data, uint32_t *centralOffset, uint32_t *centralSize, uint16_t *entryCount, NSError **error) {
    NSUInteger length = data.length;
    if (length < 22) {
        if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Zip archive is too small.", nil);
        return NO;
    }
    NSUInteger start = length > 65557 ? length - 65557 : 0;
    const uint8_t *bytes = data.bytes;
    for (NSInteger j = (NSInteger)length - 22; j >= (NSInteger)start; j--) {
        if (bytes[j] == 0x50 && bytes[j + 1] == 0x4b && bytes[j + 2] == 0x05 && bytes[j + 3] == 0x06) {
            if (centralOffset) *centralOffset = AutoZipReadUInt32(bytes + j + 16);
            if (centralSize) *centralSize = AutoZipReadUInt32(bytes + j + 12);
            if (entryCount) *entryCount = AutoZipReadUInt16(bytes + j + 10);
            return YES;
        }
    }
    if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Zip archive has no end-of-central-directory record.", nil);
    return NO;
}

static BOOL AutoZipParseCentralDirectory(NSData *data, uint32_t centralOffset, uint32_t centralSize,
                                         uint16_t entryCount, NSArray<AutoZipEntry *> **entries, NSError **error) {
    const uint8_t *bytes = data.bytes;
    NSUInteger length = data.length;
    if (centralOffset > length || centralSize > length - centralOffset) {
        if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Zip central directory is out of bounds.", nil);
        return NO;
    }
    NSUInteger cursor = centralOffset;
    NSUInteger end = (NSUInteger)centralOffset + centralSize;
    NSMutableArray<AutoZipEntry *> *result = [NSMutableArray array];
    uint16_t parsed = 0;
    while (cursor + 46 <= end && parsed < entryCount) {
        if (AutoZipReadUInt32(bytes + cursor) != 0x02014b50) {
            if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Zip central directory is corrupt.", nil);
            return NO;
        }
        uint16_t nameLength = AutoZipReadUInt16(bytes + cursor + 28);
        uint16_t extraLength = AutoZipReadUInt16(bytes + cursor + 30);
        uint16_t commentLength = AutoZipReadUInt16(bytes + cursor + 32);
        if (cursor + 46 + nameLength + extraLength + commentLength > end) {
            if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Zip central directory is truncated.", nil);
            return NO;
        }
        NSData *nameData = [NSData dataWithBytes:bytes + cursor + 46 length:nameLength];
        NSString *name = AutoZipDecodeName(nameData);
        if (!name) {
            if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Zip entry has an invalid name.", nil);
            return NO;
        }
        AutoZipEntry *entry = [AutoZipEntry new];
        entry.name = name;
        entry.method = AutoZipReadUInt16(bytes + cursor + 10);
        entry.crc = AutoZipReadUInt32(bytes + cursor + 16);
        entry.compressedSize = AutoZipReadUInt32(bytes + cursor + 20);
        entry.uncompressedSize = AutoZipReadUInt32(bytes + cursor + 24);
        entry.localOffset = AutoZipReadUInt32(bytes + cursor + 42);
        entry.isDirectory = (AutoZipReadUInt32(bytes + cursor + 38) & 0x10) != 0 || [name hasSuffix:@"/"];
        [result addObject:entry];
        parsed += 1;
        cursor += 46 + nameLength + extraLength + commentLength;
    }
    if (parsed != entryCount) {
        if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Zip central directory has fewer entries than declared.", nil);
        return NO;
    }
    if (entries) *entries = result;
    return YES;
}

static NSData *AutoZipExtractEntryData(NSData *archive, AutoZipEntry *entry, NSUInteger maximumBytes, NSError **error) {
    const uint8_t *bytes = archive.bytes;
    NSUInteger length = archive.length;
    if ((NSUInteger)entry.localOffset + 30 > length) {
        if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Zip entry local header is out of bounds.", nil);
        return nil;
    }
    if (AutoZipReadUInt32(bytes + entry.localOffset) != 0x04034b50) {
        if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Zip entry local header is corrupt.", nil);
        return nil;
    }
    uint16_t nameLength = AutoZipReadUInt16(bytes + entry.localOffset + 26);
    uint16_t extraLength = AutoZipReadUInt16(bytes + entry.localOffset + 28);
    NSUInteger dataOffset = (NSUInteger)entry.localOffset + 30 + nameLength + extraLength;
    if (dataOffset + entry.compressedSize > length) {
        if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Zip entry data is truncated.", nil);
        return nil;
    }
    if (entry.uncompressedSize > maximumBytes) {
        if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Zip entry exceeds the extraction byte limit.", nil);
        return nil;
    }
    NSData *compressed = [NSData dataWithBytes:bytes + dataOffset length:entry.compressedSize];
    if (entry.method == 0) {
        if (entry.compressedSize != entry.uncompressedSize) {
            if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Zip stored entry size mismatch.", nil);
            return nil;
        }
        return compressed;
    }
    if (entry.method != 8) {
        if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Zip compression method is not supported.", nil);
        return nil;
    }
    NSData *inflated = AutoZipInflateData(compressed, entry.uncompressedSize, error);
    if (!inflated) return nil;
    if (inflated.length != entry.uncompressedSize) {
        if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Zip inflated entry size mismatch.", nil);
        return nil;
    }
    if (AutoZipCRC32(inflated.bytes, inflated.length) != entry.crc) {
        if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Zip entry CRC32 mismatch.", nil);
        return nil;
    }
    return inflated;
}

static NSArray *AutoZipListEntries(NSArray<AutoZipEntry *> *entries) {
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:entries.count];
    for (AutoZipEntry *entry in entries) {
        [result addObject:@{ @"name": entry.name ?: @"",
                             @"size": @(entry.uncompressedSize),
                             @"compressedSize": @(entry.compressedSize),
                             @"method": @(entry.method),
                             @"isDirectory": @(entry.isDirectory) }];
    }
    return result;
}

static id AutoZipReadEntry(NSData *archive, NSArray<AutoZipEntry *> *entries, NSString *entryName,
                           NSUInteger maximumBytes, NSError **error) {
    NSString *slashName = [entryName hasSuffix:@"/"] ? entryName : [entryName stringByAppendingString:@"/"];
    for (AutoZipEntry *entry in entries) {
        if ([entry.name isEqualToString:entryName] || [entry.name isEqualToString:slashName]) {
            if (entry.isDirectory) return [NSNull null];
            NSData *data = AutoZipExtractEntryData(archive, entry, maximumBytes, error);
            if (!data) return nil;
            NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if (text) return text;
            return [data base64EncodedStringWithOptions:0];
        }
    }
    if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Zip entry was not found.", nil);
    return nil;
}

static BOOL AutoZipExtract(NSData *archive, NSArray<AutoZipEntry *> *entries, NSString *destinationPath,
                           NSDictionary *config, NSError **error) {
    NSFileManager *manager = NSFileManager.defaultManager;
    NSUInteger maximumEntry = AutoSupportByteLimit(config, @"maxZipExtractEntryBytes", 64 * 1024 * 1024, 512 * 1024 * 1024);
    NSUInteger maximumTotal = AutoSupportByteLimit(config, @"maxZipExtractBytes", 128 * 1024 * 1024, 1024 * 1024 * 1024);
    NSUInteger totalBytes = 0;
    for (AutoZipEntry *entry in entries) {
        NSArray<NSString *> *components = entry.name.pathComponents;
        for (NSString *component in components) {
            if ([component isEqualToString:@".."]) {
                if (error) *error = AutoSupportError(AutoSDKErrorFileAccessDenied, @"Zip entry attempts to escape the destination directory.", nil);
                return NO;
            }
        }
        if ([entry.name hasPrefix:@"/"]) {
            if (error) *error = AutoSupportError(AutoSDKErrorFileAccessDenied, @"Zip entry uses an absolute path.", nil);
            return NO;
        }
        NSError *resolveError = nil;
        NSURL *targetURL = AutoResolveFilePath([destinationPath stringByAppendingPathComponent:entry.name], config, NO, &resolveError);
        if (!targetURL) {
            if (error) *error = resolveError ?: AutoSupportError(AutoSDKErrorFileAccessDenied, @"Zip entry escapes the sandbox.", nil);
            return NO;
        }
        if (entry.isDirectory) {
            NSError *directoryError = nil;
            if (![manager createDirectoryAtURL:targetURL withIntermediateDirectories:YES attributes:nil error:&directoryError]) {
                if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Unable to create the zip entry directory.", directoryError);
                return NO;
            }
            continue;
        }
        NSData *entryData = AutoZipExtractEntryData(archive, entry, maximumEntry, error);
        if (!entryData) return NO;
        totalBytes += entryData.length;
        if (totalBytes > maximumTotal) {
            if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Zip extraction exceeds maxZipExtractBytes.", nil);
            return NO;
        }
        NSError *directoryError = nil;
        if (![manager createDirectoryAtURL:targetURL.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&directoryError]) {
            if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Unable to create the extraction directory.", directoryError);
            return NO;
        }
        NSError *writeError = nil;
        if (![entryData writeToURL:targetURL options:NSDataWritingAtomic error:&writeError]) {
            if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Unable to write the extracted zip entry.", writeError);
            return NO;
        }
    }
    return YES;
}
static NSData *AutoZipEntryDataByName(NSData *archive, NSArray<AutoZipEntry *> *entries, NSString *name, NSUInteger maximumBytes, NSError **error) {
    for (AutoZipEntry *entry in entries) {
        if (entry.isDirectory) continue;
        if ([entry.name isEqualToString:name] || [entry.name hasSuffix:[@"/" stringByAppendingString:name]]) {
            return AutoZipExtractEntryData(archive, entry, maximumBytes, error);
        }
    }
    if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed,
                                         [NSString stringWithFormat:@"Excel workbook part %@ is missing.", name], nil);
    return nil;
}

// ===== Excel workbook support: XLSX (ZIP+XML) with a plain CSV fallback =====
@interface AutoXLSXWorkbookScanner : NSObject <NSXMLParserDelegate>
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *sheets;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *targets;
@property (nonatomic, assign) BOOL scanningRels;
@end
@implementation AutoXLSXWorkbookScanner
- (instancetype)init {
    self = [super init];
    if (self) {
        _sheets = [NSMutableArray array];
        _targets = [NSMutableDictionary dictionary];
    }
    return self;
}
- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qualifiedName attributes:(NSDictionary<NSString *,NSString *> *)attributeDict {
    if (self.scanningRels) {
        if ([elementName isEqualToString:@"Relationship"]) {
            NSString *relId = attributeDict[@"Id"] ?: attributeDict[@"id"];
            NSString *target = attributeDict[@"Target"] ?: attributeDict[@"target"];
            if (relId.length > 0 && target.length > 0) self.targets[relId] = target;
        }
        return;
    }
    if ([elementName isEqualToString:@"sheet"]) {
        NSString *relId = attributeDict[@"r:id"] ?: attributeDict[@"id"];
        NSString *name = attributeDict[@"name"] ?: @"";
        [self.sheets addObject:@{ @"rId": relId ?: @"", @"name": name }];
    }
}
@end

@interface AutoXLSXParser : NSObject <NSXMLParserDelegate>
@property (nonatomic, strong) NSMutableArray<NSMutableArray *> *rows;
@property (nonatomic, assign) BOOL parsingShared;
@property (nonatomic, strong) NSMutableArray<NSString *> *sharedStrings;
@property (nonatomic, strong) NSMutableString *currentText;
@property (nonatomic, assign) BOOL collectingText;
@property (nonatomic, strong) NSMutableArray *currentRow;
@property (nonatomic, assign) NSInteger currentColumn;
@property (nonatomic, copy) NSString *cellType;
@property (nonatomic, assign) BOOL insidePhonetic;
@end
@implementation AutoXLSXParser
- (instancetype)init {
    self = [super init];
    if (self) {
        _rows = [NSMutableArray array];
        _sharedStrings = [NSMutableArray array];
    }
    return self;
}
- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qualifiedName attributes:(NSDictionary<NSString *,NSString *> *)attributeDict {
    if (self.parsingShared) {
        if ([elementName isEqualToString:@"si"]) {
            self.currentText = [NSMutableString string];
            self.collectingText = NO;
            self.insidePhonetic = NO;
        } else if ([elementName isEqualToString:@"rPh"] || [elementName isEqualToString:@"phoneticPr"]) {
            self.insidePhonetic = YES;
            self.collectingText = NO;
        } else if ([elementName isEqualToString:@"t"] && !self.insidePhonetic) {
            if (self.currentText == nil) self.currentText = [NSMutableString string];
            self.collectingText = YES;
        }
        return;
    }
    if ([elementName isEqualToString:@"row"]) {
        self.currentRow = [NSMutableArray array];
        self.currentColumn = -1;
        self.currentText = nil;
        self.collectingText = NO;
    } else if ([elementName isEqualToString:@"c"]) {
        self.currentText = [NSMutableString string];
        self.collectingText = NO;
        self.cellType = attributeDict[@"t"] ?: @"";
        NSString *reference = attributeDict[@"r"] ?: @"";
        NSInteger column = -1;
        for (NSUInteger i = 0; i < reference.length; i++) {
            unichar c = [reference characterAtIndex:i];
            if (c >= 'A' && c <= 'Z') column = column < 0 ? 0 : column, column = column * 26 + (c - 'A' + 1);
            else if (c >= 'a' && c <= 'z') column = column < 0 ? 0 : column, column = column * 26 + (c - 'a' + 1);
            else break;
        }
        self.currentColumn = column >= 0 ? column - 1 : self.currentColumn + 1;
    } else if ([elementName isEqualToString:@"v"] || [elementName isEqualToString:@"t"]) {
        if (self.currentText == nil) self.currentText = [NSMutableString string];
        self.collectingText = YES;
    }
}
- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string {
    if (self.collectingText && self.currentText) [self.currentText appendString:string];
}
- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qualifiedName {
    if ([elementName isEqualToString:@"t"]) self.collectingText = NO;
    if (self.parsingShared) {
        if ([elementName isEqualToString:@"rPh"] || [elementName isEqualToString:@"phoneticPr"]) {
            self.insidePhonetic = NO;
            self.collectingText = NO;
        } else if ([elementName isEqualToString:@"si"]) {
            [self.sharedStrings addObject:[self.currentText copy] ?: @""];
            self.currentText = nil;
            self.insidePhonetic = NO;
        }
        return;
    }
    if ([elementName isEqualToString:@"c"]) {
        if (self.currentColumn < 0 || self.currentRow == nil) return;
        NSString *text = self.currentText ? [self.currentText copy] : @"";
        id value = text;
        if ([self.cellType isEqualToString:@"s"]) {
            NSInteger index = text.integerValue;
            value = (index >= 0 && index < (NSInteger)self.sharedStrings.count) ? self.sharedStrings[index] : @"";
        } else if ([self.cellType isEqualToString:@"b"]) {
            value = [text isEqualToString:@"1"] ? @"true" : @"false";
        } else if (self.cellType.length == 0 || [self.cellType isEqualToString:@"n"]) {
            NSScanner *scanner = [NSScanner scannerWithString:text];
            double number = 0;
            if (text.length > 0 && [scanner scanDouble:&number] && scanner.isAtEnd) value = @(number);
        }
        while ((NSInteger)self.currentRow.count <= self.currentColumn) [self.currentRow addObject:@""];
        self.currentRow[self.currentColumn] = value ?: @"";
    } else if ([elementName isEqualToString:@"row"]) {
        while (self.currentRow.count > 0 && [self.currentRow.lastObject isEqual:@""]) [self.currentRow removeLastObject];
        [self.rows addObject:self.currentRow ?: [NSMutableArray array]];
        self.currentRow = nil;
    }
}
@end

static NSArray *AutoExcelParseCSV(NSString *text, NSError **error) {
    NSMutableArray *rows = [NSMutableArray array];
    NSMutableArray *row = [NSMutableArray array];
    NSMutableString *field = [NSMutableString string];
    BOOL inQuotes = NO;
    NSUInteger length = text.length;
    for (NSUInteger i = 0; i < length; i++) {
        unichar c = [text characterAtIndex:i];
        if (inQuotes) {
            if (c == '"') {
                if (i + 1 < length && [text characterAtIndex:i + 1] == '"') {
                    [field appendString:@"\""];
                    i += 1;
                } else {
                    inQuotes = NO;
                }
            } else {
                [field appendFormat:@"%C", c];
            }
        } else if (c == '"' && field.length == 0) {
            inQuotes = YES;
        } else if (c == ',') {
            [row addObject:field];
            field = [NSMutableString string];
        } else if (c == '\n') {
            [row addObject:field];
            field = [NSMutableString string];
            if (row.count > 0) [rows addObject:row];
            row = [NSMutableArray array];
        } else if (c != '\r') {
            [field appendFormat:@"%C", c];
        }
    }
    if (field.length > 0 || row.count > 0) {
        [row addObject:field];
        if (row.count > 0) [rows addObject:row];
    }
    return rows;
}

static NSArray *AutoExcelParseXLSX(NSData *archive, NSArray<AutoZipEntry *> *entries,
                                   NSUInteger sheetIndex, NSDictionary *config, NSError **error) {
    NSUInteger partLimit = AutoSupportByteLimit(config, @"maxExcelBytes", 32 * 1024 * 1024, 256 * 1024 * 1024);
    NSError *partError = nil;
    NSData *workbookData = AutoZipEntryDataByName(archive, entries, @"xl/workbook.xml", partLimit, &partError);
    if (!workbookData) {
        if (error) *error = partError;
        return nil;
    }
    AutoXLSXWorkbookScanner *scanner = [AutoXLSXWorkbookScanner new];
    NSXMLParser *workbookParser = [[NSXMLParser alloc] initWithData:workbookData];
    workbookParser.delegate = scanner;
    if (![workbookParser parse] || scanner.sheets.count == 0) {
        if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Excel workbook.xml is missing or invalid.", workbookParser.parserError);
        return nil;
    }
    if (sheetIndex >= scanner.sheets.count) {
        if (error) *error = AutoSupportError(AutoSDKErrorInvalidConfiguration, @"Excel sheet index is out of range.", nil);
        return nil;
    }
    NSDictionary *sheet = scanner.sheets[sheetIndex];
    NSString *relId = sheet[@"rId"];
    NSString *target = nil;
    if (relId.length > 0) {
        NSData *relsData = AutoZipEntryDataByName(archive, entries, @"xl/_rels/workbook.xml.rels", partLimit, &partError);
        if (relsData) {
            AutoXLSXWorkbookScanner *relsScanner = [AutoXLSXWorkbookScanner new];
            relsScanner.scanningRels = YES;
            NSXMLParser *relsParser = [[NSXMLParser alloc] initWithData:relsData];
            relsParser.delegate = relsScanner;
            if ([relsParser parse]) target = relsScanner.targets[relId];
        }
    }
    if (target.length == 0) target = [NSString stringWithFormat:@"worksheets/sheet%lu.xml", (unsigned long)(sheetIndex + 1)];
    if ([target hasPrefix:@"/"]) target = [target substringFromIndex:1];
    else if (![target hasPrefix:@"xl/"]) target = [@"xl/" stringByAppendingString:target];
    NSRange queryRange = [target rangeOfString:@"?"];
    if (queryRange.location != NSNotFound) target = [target substringToIndex:queryRange.location];

    NSArray<NSString *> *sharedStrings = @[];
    NSData *sharedData = AutoZipEntryDataByName(archive, entries, @"xl/sharedStrings.xml", partLimit, &partError);
    if (sharedData) {
        AutoXLSXParser *sharedParser = [AutoXLSXParser new];
        sharedParser.parsingShared = YES;
        NSXMLParser *sharedXMLParser = [[NSXMLParser alloc] initWithData:sharedData];
        sharedXMLParser.delegate = sharedParser;
        if ([sharedXMLParser parse]) sharedStrings = sharedParser.sharedStrings ?: @[];
    }

    NSData *sheetData = AutoZipEntryDataByName(archive, entries, target, partLimit, &partError);
    if (!sheetData) {
        if (error) *error = partError;
        return nil;
    }
    AutoXLSXParser *sheetParser = [AutoXLSXParser new];
    sheetParser.sharedStrings = [sharedStrings mutableCopy];
    NSXMLParser *sheetXMLParser = [[NSXMLParser alloc] initWithData:sheetData];
    sheetXMLParser.delegate = sheetParser;
    if (![sheetXMLParser parse]) {
        if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Excel sheet XML is invalid.", sheetXMLParser.parserError);
        return nil;
    }
    return sheetParser.rows ?: @[];
}

static BOOL AutoZipParseArchiveData(NSData *data, NSArray<AutoZipEntry *> **entries, NSError **error) {
    uint32_t centralOffset = 0, centralSize = 0;
    uint16_t entryCount = 0;
    if (!AutoZipFindEndOfCentralDirectory(data, &centralOffset, &centralSize, &entryCount, error)) return NO;
    if (entryCount > 2000) {
        if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Zip archive has too many entries.", nil);
        return NO;
    }
    NSArray<AutoZipEntry *> *parsedEntries = nil;
    if (!AutoZipParseCentralDirectory(data, centralOffset, centralSize, entryCount, &parsedEntries, error)) return NO;
    if (entries) *entries = parsedEntries;
    return YES;
}

static BOOL AutoLoadZipArchive(NSURL *url, NSDictionary *config,
                               NSArray<AutoZipEntry *> **entries, NSData **archiveData, NSError **error) {
    NSUInteger maximum = AutoSupportByteLimit(config, @"maxZipArchiveBytes", 128 * 1024 * 1024, 1024 * 1024 * 1024);
    NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:url.path error:nil];
    if ([attributes[NSFileSize] unsignedLongLongValue] > maximum) {
        if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Zip archive exceeds maxZipArchiveBytes.", nil);
        return NO;
    }
    NSError *readError = nil;
    NSData *data = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:&readError];
    if (!data || data.length > maximum) {
        if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Unable to read the zip archive.", readError);
        return NO;
    }
    if (!AutoZipParseArchiveData(data, entries, error)) return NO;
    if (archiveData) *archiveData = data;
    return YES;
}

static id AutoPlistToJSONValue(id value, NSError **error) {
    if ([value isKindOfClass:NSDictionary.class]) {
        NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:[(NSDictionary *)value count]];
        for (id key in value) {
            if (![key isKindOfClass:NSString.class]) {
                if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"plist dictionary keys must be strings.", nil);
                return nil;
            }
            id converted = AutoPlistToJSONValue(value[key], error);
            if (!converted) return nil;
            result[key] = converted;
        }
        return result;
    }
    if ([value isKindOfClass:NSArray.class]) {
        NSMutableArray *result = [NSMutableArray arrayWithCapacity:[(NSArray *)value count]];
        for (id item in value) {
            id converted = AutoPlistToJSONValue(item, error);
            if (!converted) return nil;
            [result addObject:converted];
        }
        return result;
    }
    if ([value isKindOfClass:NSData.class]) return [value base64EncodedStringWithOptions:0];
    if ([value isKindOfClass:NSDate.class]) return @([value timeIntervalSince1970] * 1000.0);
    if ([value isKindOfClass:NSNumber.class] || [value isKindOfClass:NSString.class] || [value isKindOfClass:NSNull.class]) return value;
    if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"plist contains an unsupported value type.", nil);
    return nil;
}

static BOOL AutoJSONValueToPlist(id value, id *converted, NSError **error) {
    if ([value isKindOfClass:NSDictionary.class]) {
        NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:[(NSDictionary *)value count]];
        for (id key in value) {
            if (![key isKindOfClass:NSString.class]) {
                if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"plistWrite dictionary keys must be strings.", nil);
                return NO;
            }
            id child = nil;
            if (!AutoJSONValueToPlist(value[key], &child, error)) return NO;
            result[key] = child;
        }
        *converted = result;
        return YES;
    }
    if ([value isKindOfClass:NSArray.class]) {
        NSMutableArray *result = [NSMutableArray arrayWithCapacity:[(NSArray *)value count]];
        for (id item in value) {
            id child = nil;
            if (!AutoJSONValueToPlist(item, &child, error)) return NO;
            [result addObject:child];
        }
        *converted = result;
        return YES;
    }
    if ([value isKindOfClass:NSString.class] || [value isKindOfClass:NSNumber.class] || [value isKindOfClass:NSNull.class]) {
        *converted = value;
        return YES;
    }
    if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"plistWrite value must contain only JSON-serializable values.", nil);
    return NO;
}

id AutoScriptFileOperation(NSDictionary<NSString *,id> *payload,
                           NSDictionary<NSString *,id> *config,
                           NSError **error) {
    @synchronized (AutoFileOperationLock()) {
    NSString *operation = [payload[@"operation"] isKindOfClass:NSString.class] ? payload[@"operation"] : @"";
    NSSet *writeOperations = [NSSet setWithArray:@[@"writeText", @"writeBase64", @"appendText", @"mkdir", @"remove", @"copy", @"imageProcess", @"zip", @"unzip", @"plistWrite"]];
    BOOL writes = [writeOperations containsObject:operation];
    if (!AutoRequireFileAccess(config, writes, error)) return nil;
    if ([operation isEqualToString:@"sandboxDir"]) return AutoFileRoot(config, error).path;
    if ([operation isEqualToString:@"zip"]) {
        NSString *zipDestination = AutoRequiredString(payload[@"destination"], @"destination", error);
        if (!zipDestination) return nil;
        NSArray *zipSources = [payload[@"sources"] isKindOfClass:NSArray.class] ? payload[@"sources"] : nil;
        if (!zipSources || zipSources.count == 0) {
            if (error) *error = AutoSupportError(AutoSDKErrorInvalidConfiguration, @"zip.sources must be a non-empty array of file paths.", nil);
            return nil;
        }
        NSString *zipPasswd = [payload[@"passwd"] isKindOfClass:NSString.class] ? payload[@"passwd"] : @"";
        if (zipPasswd.length > 0) {
            if (error) *error = AutoSupportError(AutoSDKErrorInvalidConfiguration, @"Zip encryption is not supported; omit passwd.", nil);
            return nil;
        }
        NSURL *zipDestinationURL = AutoResolveFilePath(zipDestination, config, NO, error);
        if (!zipDestinationURL) return nil;
        NSData *zipArchive = nil;
        if (!AutoZipBuildArchive(zipSources, config, &zipArchive, error)) return nil;
        NSError *zipDirectoryError = nil;
        if (![NSFileManager.defaultManager createDirectoryAtURL:zipDestinationURL.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&zipDirectoryError]) {
            if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Unable to create the zip destination directory.", zipDirectoryError);
            return nil;
        }
        NSError *zipWriteError = nil;
        if (![zipArchive writeToURL:zipDestinationURL options:NSDataWritingAtomic error:&zipWriteError]) {
            if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Unable to write the zip archive.", zipWriteError);
            return nil;
        }
        return zipDestinationURL.path;
    }

    NSString *path = AutoRequiredString(payload[@"path"], @"path", error);
    if (!path) return nil;
    BOOL allowRoot = [operation isEqualToString:@"list"] || [operation isEqualToString:@"exists"] || [operation isEqualToString:@"resolvePath"];
    NSURL *url = AutoResolveFilePath(path, config, allowRoot, error);
    if (!url) return nil;
    NSFileManager *manager = NSFileManager.defaultManager;

    if ([operation isEqualToString:@"resolvePath"]) return url.path;
    if ([operation isEqualToString:@"exists"]) return @([manager fileExistsAtPath:url.path]);
    if ([operation isEqualToString:@"unzip"]) {
        NSString *zipPasswd = [payload[@"passwd"] isKindOfClass:NSString.class] ? payload[@"passwd"] : @"";
        if (zipPasswd.length > 0) {
            if (error) *error = AutoSupportError(AutoSDKErrorInvalidConfiguration, @"Zip encryption is not supported; omit passwd.", nil);
            return nil;
        }
        NSString *zipDestination = AutoRequiredString(payload[@"destination"], @"destination", error);
        if (!zipDestination) return nil;
        NSURL *zipDestinationURL = AutoResolveFilePath(zipDestination, config, NO, error);
        if (!zipDestinationURL) return nil;
        NSData *zipArchive = nil;
        NSArray<AutoZipEntry *> *zipEntries = nil;
        if (!AutoLoadZipArchive(url, config, &zipEntries, &zipArchive, error)) return nil;
        if (!AutoZipExtract(zipArchive, zipEntries, zipDestinationURL.path, config, error)) return nil;
        return @YES;
    }

    if ([operation isEqualToString:@"readFileInZip"]) {
        NSString *zipPasswd = [payload[@"passwd"] isKindOfClass:NSString.class] ? payload[@"passwd"] : @"";
        if (zipPasswd.length > 0) {
            if (error) *error = AutoSupportError(AutoSDKErrorInvalidConfiguration, @"Zip encryption is not supported; omit passwd.", nil);
            return nil;
        }
        NSString *entryName = AutoRequiredString(payload[@"entry"], @"entry", error);
        if (!entryName) return nil;
        NSData *zipArchive = nil;
        NSArray<AutoZipEntry *> *zipEntries = nil;
        if (!AutoLoadZipArchive(url, config, &zipEntries, &zipArchive, error)) return nil;
        NSUInteger zipEntryLimit = AutoSupportByteLimit(config, @"maxZipExtractEntryBytes", 64 * 1024 * 1024, 512 * 1024 * 1024);
        return AutoZipReadEntry(zipArchive, zipEntries, entryName, zipEntryLimit, error);
    }

    if ([operation isEqualToString:@"readExcelAllRow"] || [operation isEqualToString:@"readExcelRow"]) {
        NSUInteger maximum = AutoSupportByteLimit(config, @"maxExcelBytes", 32 * 1024 * 1024, 256 * 1024 * 1024);
        NSDictionary *excelAttributes = [manager attributesOfItemAtPath:url.path error:nil];
        if ([excelAttributes[NSFileSize] unsignedLongLongValue] > maximum) {
            if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Excel file exceeds maxExcelBytes.", nil);
            return nil;
        }
        NSError *excelReadError = nil;
        NSData *excelData = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:&excelReadError];
        if (!excelData || excelData.length > maximum) {
            if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Unable to read the Excel file.", excelReadError);
            return nil;
        }
        NSArray *excelRows = nil;
        if (excelData.length >= 4 && memcmp(excelData.bytes, "PK\x03\x04", 4) == 0) {
            NSArray<AutoZipEntry *> *excelEntries = nil;
            if (!AutoZipParseArchiveData(excelData, &excelEntries, error)) return nil;
            NSUInteger sheetIndex = AutoSupportFiniteDouble(payload[@"sheetIndex"], 0);
            if (sheetIndex > 100000) sheetIndex = 0;
            excelRows = AutoExcelParseXLSX(excelData, excelEntries, sheetIndex, config, error);
        } else {
            NSString *excelText = [[NSString alloc] initWithData:excelData encoding:NSUTF8StringEncoding];
            if (!excelText) {
                if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"CSV file is not valid UTF-8.", nil);
                return nil;
            }
            excelRows = AutoExcelParseCSV(excelText, error);
        }
        if (!excelRows) return nil;
        if ([operation isEqualToString:@"readExcelRow"]) {
            NSInteger rowIndex = (NSInteger)AutoSupportFiniteDouble(payload[@"row"], -1);
            if (rowIndex < 0 || rowIndex >= (NSInteger)excelRows.count) return [NSNull null];
            return excelRows[rowIndex];
        }
        if (excelRows.count == 0) return @[];
        NSArray *excelHeader = excelRows[0];
        NSMutableArray *excelResult = [NSMutableArray arrayWithCapacity:excelRows.count - 1];
        for (NSUInteger r = 1; r < excelRows.count; r++) {
            NSArray *excelRow = excelRows[r];
            NSMutableDictionary *record = [NSMutableDictionary dictionaryWithCapacity:excelHeader.count];
            for (NSUInteger c = 0; c < excelRow.count; c++) {
                NSString *key = (c < excelHeader.count && [(NSString *)excelHeader[c] length] > 0)
                    ? excelHeader[c] : [NSString stringWithFormat:@"%lu", (unsigned long)c];
                id value = excelRow[c];
                if (value == nil || ([value isKindOfClass:NSString.class] && [(NSString *)value length] == 0)) continue;
                record[key] = value;
            }
            [excelResult addObject:record];
        }
        return excelResult;
    }

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

    if ([operation isEqualToString:@"plistRead"] || [operation isEqualToString:@"plistWrite"]) {
        NSUInteger maximum = AutoSupportByteLimit(config, @"maxFileReadBytes", 10 * 1024 * 1024, 64 * 1024 * 1024);
        NSError *plistIOError = nil;
        NSData *data = nil;
        if ([operation isEqualToString:@"plistRead"]) {
            NSDictionary *attributes = [manager attributesOfItemAtPath:url.path error:nil];
            if ([attributes[NSFileSize] unsignedLongLongValue] > maximum) {
                if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"File exceeds maxFileReadBytes.", nil);
                return nil;
            }
            data = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:&plistIOError];
            if (!data || data.length > maximum) {
                NSString *message = data ? @"File exceeds maxFileReadBytes." : @"Unable to read file.";
                if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, message, plistIOError);
                return nil;
            }
        } else {
            id rawValue = payload[@"value"];
            id converted = nil;
            if (!AutoJSONValueToPlist(rawValue, &converted, error)) return nil;
            data = [NSPropertyListSerialization dataWithPropertyList:converted
                                                              format:NSPropertyListXMLFormat_v1_0
                                                             options:0
                                                               error:&plistIOError];
            if (!data || data.length > maximum) {
                NSString *message = data ? @"Value exceeds maxFileWriteBytes." : @"Unable to serialize the value as a plist.";
                if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, message, plistIOError);
                return nil;
            }
        }
        if ([operation isEqualToString:@"plistWrite"]) {
            NSError *directoryError = nil;
            if (![manager createDirectoryAtURL:url.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&directoryError]) {
                if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Unable to create the parent directory.", directoryError);
                return nil;
            }
            NSError *writeError = nil;
            if (![data writeToURL:url options:NSDataWritingAtomic error:&writeError]) {
                if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"Unable to write file.", writeError);
                return nil;
            }
            return @YES;
        }
        NSError *parseError = nil;
        id plist = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:&parseError];
        if (!plist) {
            if (error) *error = AutoSupportError(AutoSDKErrorFileOperationFailed, @"File is not a valid plist.", parseError);
            return nil;
        }
        return AutoPlistToJSONValue(plist, error);
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

NSString *AutoScriptToPinYin(NSString *text) {
    if (text.length == 0) return @"";
    NSMutableString *mutable = [text mutableCopy];
    CFStringTransform((__bridge CFMutableStringRef)mutable, NULL, kCFStringTransformToLatin, false);
    CFStringTransform((__bridge CFMutableStringRef)mutable, NULL, kCFStringTransformStripCombiningMarks, false);
    NSCharacterSet *separators = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSString *joined = [[mutable componentsSeparatedByCharactersInSet:separators] componentsJoinedByString:@""];
    return [joined lowercaseString];
}
