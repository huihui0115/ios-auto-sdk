#import <Foundation/Foundation.h>
#include <stdint.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^AutoDebugResponseHandler)(NSDictionary<NSString *, id> *response);
typedef void (^AutoDebugRequestHandler)(NSDictionary<NSString *, id> *request,
                                        AutoDebugResponseHandler response);

/** Development-only authenticated WebSocket transport for script commands. */
@interface AutoDebugServer : NSObject

@property (nonatomic, readonly, getter=isRunning) BOOL running;

- (void)startWithPort:(uint16_t)port
                token:(NSString *)token
       requestHandler:(AutoDebugRequestHandler)requestHandler
           completion:(void (^)(NSError * _Nullable error))completion;

/**
 * Starts on the loopback interface by default. Set allowsWiFi to YES to retain
 * loopback access and accept direct local-network connections while explicitly
 * prohibiting cellular interfaces. Wi-Fi mode requires a token containing at
 * least 16 characters. Tokens must not exceed 1024 UTF-8 bytes.
 */
- (void)startWithPort:(uint16_t)port
                token:(NSString *)token
           allowsWiFi:(BOOL)allowsWiFi
       requestHandler:(AutoDebugRequestHandler)requestHandler
           completion:(void (^)(NSError * _Nullable error))completion;

/** Wi-Fi variant that publishes `_autosdk._tcp` with a stable Bonjour name. */
- (void)startWithPort:(uint16_t)port
                token:(NSString *)token
           allowsWiFi:(BOOL)allowsWiFi
          serviceName:(nullable NSString *)serviceName
       requestHandler:(AutoDebugRequestHandler)requestHandler
           completion:(void (^)(NSError * _Nullable error))completion;

- (void)stop;

@end

NS_ASSUME_NONNULL_END
