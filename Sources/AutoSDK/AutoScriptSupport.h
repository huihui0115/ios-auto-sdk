#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

id _Nullable AutoScriptFileOperation(NSDictionary<NSString *, id> *payload,
                                     NSDictionary<NSString *, id> *config,
                                     NSError **error);
id _Nullable AutoScriptStorageOperation(NSDictionary<NSString *, id> *payload,
                                        NSDictionary<NSString *, id> *config,
                                        NSError **error);
BOOL AutoScriptValidateDownloadDestination(NSString *path,
                                           NSDictionary<NSString *, id> *config,
                                           NSError **error);
NSUInteger AutoScriptMaximumDownloadBytes(NSDictionary<NSString *, id> *config);
NSString * _Nullable AutoScriptMD5Hex(NSData *data);
NSString * _Nullable AutoScriptSHA1Hex(NSData *data);
NSString * _Nullable AutoScriptSHA256Hex(NSData *data);
NSString * _Nullable AutoScriptSHA512Hex(NSData *data);
NSString * _Nullable AutoScriptAES128EncryptBase64(NSString *plaintext, NSString *key);
NSString * _Nullable AutoScriptAES128DecryptBase64(NSString *base64, NSString *key);
NSString * _Nullable AutoScriptToPinYin(NSString *text);
BOOL AutoScriptInstallDownloadedFile(NSURL *temporaryURL,
                                     NSString *path,
                                     NSDictionary<NSString *, id> *config,
                                     NSError **error);

NS_ASSUME_NONNULL_END
