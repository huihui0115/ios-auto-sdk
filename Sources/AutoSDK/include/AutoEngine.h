#import <Foundation/Foundation.h>
#import "AutoAutomationAdapter.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^AutoScriptCompletion)(NSDictionary<NSString *, id> * _Nullable result,
                                     NSError * _Nullable error);
typedef id _Nullable (^AutoNativeMethodHandler)(NSArray *args);

/** Main entry point for the embedded automation runtime. */
@interface AutoEngine : NSObject

+ (instancetype)sharedEngine;

/** Applies an immutable snapshot of the runtime configuration. */
- (void)configureWithConfig:(NSDictionary<NSString *, id> *)config;
/** Compatibility alias. This is deliberately excluded from Objective-C's init method family. */
- (void)initWithConfig:(NSDictionary<NSString *, id> *)config __attribute__((objc_method_family(none)));

/**
 * Runs a file path, a bundle resource path, a file:// URL, an http(s) URL, or
 * JavaScript source text. Remote URLs require allowRemoteScripts=@YES in the
 * configuration. Completion is always delivered on the main queue. A
 * successful result contains success, value, logs and durationMs keys.
 */
- (void)runScript:(NSString *)scriptPathOrSource completion:(AutoScriptCompletion)completion;
- (void)stopScript;

/** Lists JavaScript files deployed into the debug-scripts sandbox directory. */
- (nullable NSArray<NSDictionary<NSString *, id> *> *)deployedScriptsWithError:(NSError * _Nullable * _Nullable)error;
/** Runs one safe flat .js filename previously deployed by the debug protocol. */
- (void)runDeployedScriptNamed:(NSString *)name completion:(AutoScriptCompletion _Nullable)completion;
/** Removes one deployed script without affecting bundled scripts. */
- (BOOL)deleteDeployedScriptNamed:(NSString *)name error:(NSError * _Nullable * _Nullable)error;
/** Validates and stores one UTF-8 script into the deployed-scripts sandbox. */
- (BOOL)saveDeployedScriptNamed:(NSString *)name script:(NSString *)script error:(NSError * _Nullable * _Nullable)error;
/** Reads the source of one deployed script for editing. */
- (nullable NSString *)deployedScriptContentNamed:(NSString *)name error:(NSError * _Nullable * _Nullable)error;
/** Renames one deployed script; fails when the new name is already taken. */
- (BOOL)renameDeployedScriptNamed:(NSString *)oldName toName:(NSString *)newName error:(NSError * _Nullable * _Nullable)error;

- (void)registerNativeMethod:(NSString *)methodName handler:(AutoNativeMethodHandler)handler;

- (NSDictionary<NSString *, id> *)getDeviceInfo;

/** Total/free system memory and this process's memory footprint in bytes. */
- (NSDictionary<NSString *, id> *)deviceMemoryInfo;

/** Set the automation adapter (built-in no-WDA / UIKit). Must be called before runScript:. */
- (void)setAutomationAdapter:(id<AutoAutomationAdapter>)adapter;

/** Starts the authenticated loopback WebSocket debug transport. */
- (void)startDebugServerWithPort:(uint16_t)port completion:(void (^)(NSError * _Nullable error))completion;

/**
 * Starts the authenticated WebSocket debug transport and optionally accepts
 * direct connections from the local Wi-Fi network.
 */
- (void)startDebugServerWithPort:(uint16_t)port
                     allowsWiFi:(BOOL)allowsWiFi
                      completion:(void (^)(NSError * _Nullable error))completion;
- (void)stopDebugServer;

@property (nonatomic, readonly, getter=isRunning) BOOL running;

@end

NS_ASSUME_NONNULL_END
