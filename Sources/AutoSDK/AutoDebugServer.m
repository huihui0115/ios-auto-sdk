#import "include/AutoDebugServer.h"
#import "include/AutoSDKError.h"
#import <Network/Network.h>
#import <CommonCrypto/CommonDigest.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>

static NSError *AutoDebugError(AutoSDKErrorCode code, NSString *message, NSError *underlying) {
    NSMutableDictionary *info = [@{NSLocalizedDescriptionKey: message} mutableCopy];
    if (underlying) info[NSUnderlyingErrorKey] = underlying;
    return [NSError errorWithDomain:AutoSDKErrorDomain code:code userInfo:info];
}

@class AutoDebugPeer;

@interface AutoDebugPeer : NSObject
@property (nonatomic, strong) nw_connection_t connection;
@property (nonatomic, strong) NSMutableData *buffer;
@property (nonatomic, copy) NSString *token;
@property (nonatomic, copy) AutoDebugRequestHandler requestHandler;
@property (nonatomic, copy) void (^didStop)(AutoDebugPeer *peer);
@property (nonatomic, assign) BOOL handshakeComplete;
@property (nonatomic, assign) BOOL authenticated;
@property (nonatomic, assign) BOOL authenticationRejected;
@property (nonatomic, assign) BOOL stopped;
@property (nonatomic, assign) NSUInteger inFlightRequests;
@property (nonatomic, assign) BOOL heavyRequestInFlight;
@property (nonatomic, strong) NSMutableDictionary<NSUUID *, NSDictionary *> *pendingRequests;
@property (nonatomic, assign) NSUInteger queuedSendBytes;
@property (nonatomic, assign) NSTimeInterval lastActivityTime;
@property (nonatomic, strong) dispatch_queue_t queue;
- (instancetype)initWithConnection:(nw_connection_t)connection
                              token:(NSString *)token
                    requestHandler:(AutoDebugRequestHandler)requestHandler;
- (void)start;
- (void)stop;
- (void)scheduleIdleCheck;
- (void)sendDispatchData:(dispatch_data_t)content;
- (void)sendWebSocketPayload:(NSData *)payload opcode:(uint8_t)opcode;
- (void)completeRequestWithKey:(NSUUID *)requestKey response:(NSDictionary *)response;
@end

@interface AutoDebugServer ()
@property (nonatomic, strong) nw_listener_t listener;
@property (nonatomic, strong) NSMutableSet<AutoDebugPeer *> *peers;
@property (nonatomic, assign, getter=isRunning) BOOL running;
@property (nonatomic, copy, nullable) void (^pendingStartCompletion)(NSError * _Nullable error);
@property (nonatomic, assign) NSUInteger listenerGeneration;
@property (nonatomic, strong) dispatch_queue_t queue;
@end

static uint16_t AutoReadBE16(const uint8_t *bytes) {
    return ((uint16_t)bytes[0] << 8) | bytes[1];
}

static uint64_t AutoReadBE64(const uint8_t *bytes) {
    uint64_t value = 0;
    for (NSUInteger index = 0; index < 8; index++) value = (value << 8) | bytes[index];
    return value;
}

static BOOL AutoConstantTimeStringEqual(NSString *left, NSString *right) {
    NSData *a = [left dataUsingEncoding:NSUTF8StringEncoding] ?: NSData.data;
    NSData *b = [right dataUsingEncoding:NSUTF8StringEncoding] ?: NSData.data;
    NSUInteger maximum = MAX(a.length, b.length);
    const uint8_t *aBytes = a.bytes;
    const uint8_t *bBytes = b.bytes;
    NSUInteger difference = a.length ^ b.length;
    for (NSUInteger index = 0; index < maximum; index++) {
        uint8_t aByte = index < a.length ? aBytes[index] : 0;
        uint8_t bByte = index < b.length ? bBytes[index] : 0;
        difference |= aByte ^ bByte;
    }
    return difference == 0;
}

static BOOL AutoHTTPHeaderContainsToken(NSString *value, NSString *expectedToken) {
    if (![value isKindOfClass:NSString.class] || expectedToken.length == 0) return NO;
    for (NSString *component in [value componentsSeparatedByString:@","]) {
        NSString *token = [component stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if ([token caseInsensitiveCompare:expectedToken] == NSOrderedSame) return YES;
    }
    return NO;
}

static NSError *AutoNSErrorFromNWError(nw_error_t error) {
    if (!error) return nil;
    CFErrorRef copiedError = nw_error_copy_cf_error(error);
    return CFBridgingRelease(copiedError);
}

static NSTimeInterval AutoDebugRequestTimeout(NSDictionary *request) {
    NSString *type = [request[@"type"] isKindOfClass:NSString.class] ? request[@"type"] : @"";
    // Script execution is allowed to run for the engine's one-hour maximum.
    // Short-lived inspector commands use a smaller default so abandoned work
    // does not occupy a peer for longer than necessary.
    NSTimeInterval defaultTimeout = [@[ @"run", @"runScript", @"runStored" ] containsObject:type]
        ? 3600.0 : 360.0;
    id rawTimeout = request[@"timeoutMs"];
    if ([rawTimeout isKindOfClass:NSNumber.class]) {
        double milliseconds = [rawTimeout doubleValue];
        if (isfinite(milliseconds) && milliseconds > 0) {
            return MIN(3600.0, MAX(1.0, milliseconds / 1000.0));
        }
    }
    return defaultTimeout;
}

static dispatch_data_t AutoDispatchDataFromNSData(NSData *data) {
    if (data.length == 0) return dispatch_data_empty;
    NSData *retainedData = data;
    return dispatch_data_create(retainedData.bytes,
                                retainedData.length,
                                dispatch_get_global_queue(QOS_CLASS_UTILITY, 0),
                                ^{ (void)retainedData; });
}

static NSData *AutoWebSocketHeader(NSUInteger length, uint8_t opcode) {
    NSMutableData *header = [NSMutableData dataWithCapacity:10];
    uint8_t first = (uint8_t)(0x80 | (opcode & 0x0f));
    [header appendBytes:&first length:1];
    if (length < 126) {
        uint8_t second = (uint8_t)length;
        [header appendBytes:&second length:1];
    } else if (length <= UINT16_MAX) {
        uint8_t second = 126;
        uint16_t networkLength = CFSwapInt16HostToBig((uint16_t)length);
        [header appendBytes:&second length:1];
        [header appendBytes:&networkLength length:2];
    } else {
        uint8_t second = 127;
        uint64_t networkLength = CFSwapInt64HostToBig((uint64_t)length);
        [header appendBytes:&second length:1];
        [header appendBytes:&networkLength length:8];
    }
    return header;
}

@implementation AutoDebugPeer

- (instancetype)initWithConnection:(nw_connection_t)connection
                              token:(NSString *)token
                    requestHandler:(AutoDebugRequestHandler)requestHandler {
    self = [super init];
    if (self) {
        _connection = connection;
        _token = [token copy];
        _requestHandler = [requestHandler copy];
        _buffer = [NSMutableData data];
        _pendingRequests = [NSMutableDictionary dictionary];
        _lastActivityTime = CFAbsoluteTimeGetCurrent();
        _queue = dispatch_queue_create("com.autosdk.runtime.debug.peer", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)start {
    __weak AutoDebugPeer *weakSelf = self;
    nw_connection_set_queue(self.connection, self.queue);
    nw_connection_set_state_changed_handler(self.connection, ^(nw_connection_state_t state, nw_error_t error) {
        AutoDebugPeer *strongSelf = weakSelf;
        if (!strongSelf) return;
        if (state == nw_connection_state_ready) [strongSelf receive];
        else if (state == nw_connection_state_failed || state == nw_connection_state_cancelled) [strongSelf stop];
        (void)error;
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), self.queue, ^{
        AutoDebugPeer *strongSelf = weakSelf;
        if (strongSelf && !strongSelf.authenticated) [strongSelf stop];
    });
    [self scheduleIdleCheck];
    nw_connection_start(self.connection);
}

- (void)scheduleIdleCheck {
    __weak AutoDebugPeer *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30 * NSEC_PER_SEC)), self.queue, ^{
        AutoDebugPeer *strongSelf = weakSelf;
        if (!strongSelf || strongSelf.stopped) return;
        NSTimeInterval now = CFAbsoluteTimeGetCurrent();
        for (NSUUID *requestKey in strongSelf.pendingRequests.allKeys) {
            NSDictionary *pending = strongSelf.pendingRequests[requestKey];
            if ([pending[@"deadline"] doubleValue] <= now) {
                [strongSelf completeRequestWithKey:requestKey
                                          response:@{ @"ok": @NO,
                                                      @"error": @"Debug request timed out.",
                                                      @"code": @(AutoSDKErrorDebugServerFailed) }];
            }
        }
        NSTimeInterval idleTime = now - strongSelf.lastActivityTime;
        if (idleTime >= 90 && strongSelf.inFlightRequests == 0) {
            [strongSelf stop];
            return;
        }
        [strongSelf scheduleIdleCheck];
    });
}

- (void)stop {
    __block void (^didStop)(AutoDebugPeer *) = nil;
    @synchronized (self) {
        if (self.stopped) return;
        self.stopped = YES;
        didStop = self.didStop;
        self.didStop = nil;
    }
    nw_connection_cancel(self.connection);
    dispatch_async(self.queue, ^{
        [self.buffer setLength:0];
        [self.pendingRequests removeAllObjects];
        self.inFlightRequests = 0;
        self.heavyRequestInFlight = NO;
        self.requestHandler = nil;
        self.token = @"";
    });
    if (didStop) didStop(self);
}

- (void)receive {
    __weak AutoDebugPeer *weakSelf = self;
    nw_connection_receive(self.connection, 1, 128 * 1024, ^(dispatch_data_t _Nullable content,
                                                            nw_content_context_t _Nullable context,
                                                            bool isComplete,
                                                            nw_error_t _Nullable receiveError) {
        AutoDebugPeer *strongSelf = weakSelf;
        if (!strongSelf) return;
        NSData *data = nil;
        if (content) {
            const void *mappedBytes = NULL;
            size_t mappedSize = 0;
            dispatch_data_t mapped = dispatch_data_create_map(content, &mappedBytes, &mappedSize);
            if (mapped && mappedSize > 0) data = [NSData dataWithBytes:mappedBytes length:mappedSize];
        }
        if (data.length > 0) {
            strongSelf.lastActivityTime = CFAbsoluteTimeGetCurrent();
            [strongSelf.buffer appendData:data];
            NSUInteger maximumBuffer = strongSelf.handshakeComplete ? 2 * 1024 * 1024 : 64 * 1024;
            if (strongSelf.buffer.length > maximumBuffer) {
                [strongSelf stop];
                return;
            }
            [strongSelf processBuffer];
        }
        if (strongSelf.stopped) return;
        if (!isComplete && !receiveError) [strongSelf receive];
        else [strongSelf stop];
        (void)context;
    });
}

- (void)sendDispatchData:(dispatch_data_t)content {
    if (!content) { [self stop]; return; }
    NSUInteger byteCount = dispatch_data_get_size(content);
    static const NSUInteger maximumQueuedSendBytes = 40 * 1024 * 1024;
    BOOL exceedsQueueLimit = NO;
    @synchronized (self) {
        if (self.stopped) return;
        if (byteCount > maximumQueuedSendBytes || self.queuedSendBytes > maximumQueuedSendBytes - byteCount) {
            exceedsQueueLimit = YES;
        } else {
            self.queuedSendBytes += byteCount;
        }
    }
    if (exceedsQueueLimit) { [self stop]; return; }
    __weak AutoDebugPeer *weakSelf = self;
    nw_connection_send(self.connection, content, NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT, true, ^(nw_error_t _Nullable error) {
        AutoDebugPeer *strongSelf = weakSelf;
        if (!strongSelf) return;
        @synchronized (strongSelf) {
            strongSelf.queuedSendBytes = strongSelf.queuedSendBytes >= byteCount
                ? strongSelf.queuedSendBytes - byteCount
                : 0;
        }
        if (error) [strongSelf stop];
    });
}

- (void)sendData:(NSData *)data {
    [self sendDispatchData:AutoDispatchDataFromNSData(data)];
}

- (void)sendWebSocketPayload:(NSData *)payload opcode:(uint8_t)opcode {
    NSData *header = AutoWebSocketHeader(payload.length, opcode);
    dispatch_data_t headerData = AutoDispatchDataFromNSData(header);
    dispatch_data_t payloadData = AutoDispatchDataFromNSData(payload);
    [self sendDispatchData:dispatch_data_create_concat(headerData, payloadData)];
}

- (void)sendJSON:(NSDictionary *)json {
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:json options:0 error:&error];
    if (!data || error) {
        data = [NSJSONSerialization dataWithJSONObject:@{@"ok": @NO, @"error": @"Response is not JSON-serializable."} options:0 error:nil];
    }
    if (data.length > 32 * 1024 * 1024) {
        NSMutableDictionary *limitError = [@{@"ok": @NO, @"error": @"Response exceeds the 32 MB debug transport limit."} mutableCopy];
        if (json[@"id"]) limitError[@"id"] = json[@"id"];
        data = [NSJSONSerialization dataWithJSONObject:limitError options:0 error:nil];
    }
    [self sendWebSocketPayload:data opcode:0x1];
}

- (void)completeRequestWithKey:(NSUUID *)requestKey response:(NSDictionary *)response {
    NSDictionary *pending = self.pendingRequests[requestKey];
    if (!pending) return;
    [self.pendingRequests removeObjectForKey:requestKey];
    if (self.inFlightRequests > 0) self.inFlightRequests -= 1;
    if ([pending[@"heavy"] boolValue]) self.heavyRequestInFlight = NO;
    if (self.stopped) return;
    NSMutableDictionary *message = [response isKindOfClass:NSDictionary.class]
        ? [response mutableCopy]
        : [@{ @"ok": @NO, @"error": @"Debug request handler returned an invalid response." } mutableCopy];
    NSString *requestID = [pending[@"requestId"] isKindOfClass:NSString.class] ? pending[@"requestId"] : nil;
    if (requestID && !message[@"id"]) message[@"id"] = requestID;
    self.lastActivityTime = CFAbsoluteTimeGetCurrent();
    [self sendJSON:message];
}

- (void)sendHTTPHandshakeForKey:(NSString *)key {
    NSString *source = [key stringByAppendingString:@"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"];
    unsigned char digest[CC_SHA1_DIGEST_LENGTH] = {0};
    CC_SHA1(source.UTF8String, (CC_LONG)strlen(source.UTF8String), digest);
    NSString *accept = [[NSData dataWithBytes:digest length:sizeof(digest)] base64EncodedStringWithOptions:0];
    NSString *response = [NSString stringWithFormat:@"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: %@\r\n\r\n", accept];
    [self sendData:[response dataUsingEncoding:NSUTF8StringEncoding]];
    self.handshakeComplete = YES;
}

- (void)processHandshake {
    const uint8_t marker[] = {'\r', '\n', '\r', '\n'};
    NSData *markerData = [NSData dataWithBytes:marker length:4];
    NSRange range = [self.buffer rangeOfData:markerData options:0 range:NSMakeRange(0, self.buffer.length)];
    if (range.location == NSNotFound) return;
    NSData *headerData = [self.buffer subdataWithRange:NSMakeRange(0, range.location + 4)];
    [self.buffer replaceBytesInRange:NSMakeRange(0, range.location + 4) withBytes:NULL length:0];
    NSString *headers = [[NSString alloc] initWithData:headerData encoding:NSUTF8StringEncoding];
    NSArray<NSString *> *lines = [headers componentsSeparatedByString:@"\r\n"];
    NSString *requestLine = lines.firstObject;
    if (![requestLine hasPrefix:@"GET "] || [requestLine rangeOfString:@" HTTP/1.1"].location == NSNotFound) {
        [self stop];
        return;
    }
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    for (NSString *line in lines) {
        NSRange separator = [line rangeOfString:@":"];
        if (separator.location == NSNotFound) continue;
        NSString *name = [[line substringToIndex:separator.location] lowercaseString];
        NSString *value = [[line substringFromIndex:separator.location + 1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        values[name] = value;
    }
    NSString *key = values[@"sec-websocket-key"];
    NSData *decodedKey = [[NSData alloc] initWithBase64EncodedString:key ?: @"" options:0];
    BOOL hasUpgradeConnection = AutoHTTPHeaderContainsToken(values[@"connection"], @"upgrade");
    if (decodedKey.length != 16 ||
        ![[values[@"upgrade"] lowercaseString] isEqualToString:@"websocket"] ||
        !hasUpgradeConnection ||
        ![values[@"sec-websocket-version"] isEqualToString:@"13"]) {
        [self stop];
        return;
    }
    [self sendHTTPHandshakeForKey:key];
}

- (void)processFrames {
    if (self.authenticationRejected) return;
    while (!self.stopped && self.buffer.length >= 2) {
        const uint8_t *bytes = self.buffer.bytes;
        uint8_t first = bytes[0];
        uint8_t second = bytes[1];
        BOOL finalFrame = (first & 0x80) != 0;
        BOOL masked = (second & 0x80) != 0;
        if ((first & 0x70) != 0) {
            [self stop];
            return;
        }
        uint64_t payloadLength = second & 0x7f;
        NSUInteger headerLength = 2;
        if (payloadLength == 126) {
            if (self.buffer.length < 4) return;
            payloadLength = AutoReadBE16(bytes + 2);
            headerLength = 4;
        } else if (payloadLength == 127) {
            if (self.buffer.length < 10) return;
            payloadLength = AutoReadBE64(bytes + 2);
            headerLength = 10;
        }
        if (!finalFrame || !masked || payloadLength > 1024 * 1024) {
            [self stop];
            return;
        }
        uint8_t opcode = first & 0x0f;
        if ((opcode >= 0x8 && payloadLength > 125) ||
            (opcode != 0x1 && opcode != 0x8 && opcode != 0x9 && opcode != 0xA)) {
            [self stop];
            return;
        }
        NSUInteger maskLength = 4;
        NSUInteger totalLength = headerLength + maskLength + (NSUInteger)payloadLength;
        if (self.buffer.length < totalLength) return;
        const uint8_t *mask = bytes + headerLength;
        const uint8_t *payloadBytes = bytes + headerLength + maskLength;
        NSMutableData *payload = [NSMutableData dataWithLength:(NSUInteger)payloadLength];
        uint8_t *decoded = payload.mutableBytes;
        for (NSUInteger index = 0; index < payloadLength; index++) decoded[index] = payloadBytes[index] ^ mask[index % 4];
        [self.buffer replaceBytesInRange:NSMakeRange(0, totalLength) withBytes:NULL length:0];
        if (opcode == 0x8) { [self stop]; return; }
        if (opcode == 0x9) { [self sendWebSocketPayload:payload opcode:0xA]; continue; }
        if (opcode != 0x1) continue;
        NSError *error = nil;
        id object = [NSJSONSerialization JSONObjectWithData:payload options:0 error:&error];
        if (![object isKindOfClass:NSDictionary.class]) {
            [self sendJSON:@{@"ok": @NO, @"error": @"Request must be a JSON object."}];
            continue;
        }
        NSDictionary *request = object;
        if (![request[@"token"] isKindOfClass:NSString.class] || !AutoConstantTimeStringEqual(request[@"token"], self.token)) {
            self.authenticationRejected = YES;
            NSMutableDictionary *unauthorized = [@{@"ok": @NO, @"error": @"Unauthorized.", @"code": @(AutoSDKErrorDebugUnauthorized)} mutableCopy];
            if (request[@"id"]) unauthorized[@"id"] = request[@"id"];
            [self sendJSON:unauthorized];
            __weak AutoDebugPeer *weakSelf = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(100 * NSEC_PER_MSEC)), self.queue, ^{
                [weakSelf stop];
            });
            return;
        }
        self.authenticated = YES;
        NSString *requestID = [request[@"id"] isKindOfClass:NSString.class] ? request[@"id"] : nil;
        NSString *requestType = [request[@"type"] isKindOfClass:NSString.class] ? request[@"type"] : nil;
        if (requestID.length == 0 || requestID.length > 128 ||
            [requestID lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 512 ||
            requestType.length == 0 || requestType.length > 64) {
            NSMutableDictionary *invalid = [@{ @"ok": @NO,
                                                @"error": @"Request id and type must be non-empty bounded strings.",
                                                @"code": @(AutoSDKErrorInvalidConfiguration) } mutableCopy];
            if (requestID.length > 0 && requestID.length <= 128) invalid[@"id"] = requestID;
            [self sendJSON:invalid];
            continue;
        }
        AutoDebugRequestHandler handler = self.requestHandler;
        if (!handler) continue;
        BOOL heavyRequest = [@[@"screenshot", @"inspectSnapshot", @"nodes", @"pixelColor", @"findImage", @"testOCR"] containsObject:requestType];
        if (self.inFlightRequests >= 8 || (heavyRequest && self.heavyRequestInFlight)) {
            NSMutableDictionary *busy = [@{@"ok": @NO, @"error": @"The device is busy processing earlier debug requests.",
                                            @"code": @(AutoSDKErrorAlreadyRunning)} mutableCopy];
            if (request[@"id"]) busy[@"id"] = request[@"id"];
            [self sendJSON:busy];
            continue;
        }
        self.inFlightRequests += 1;
        if (heavyRequest) self.heavyRequestInFlight = YES;
        __weak AutoDebugPeer *weakSelf = self;
        NSUUID *requestKey = NSUUID.UUID;
        self.pendingRequests[requestKey] = @{ @"deadline": @(CFAbsoluteTimeGetCurrent() + AutoDebugRequestTimeout(request)),
                                              @"heavy": @(heavyRequest),
                                              @"requestId": requestID };
        @try {
            handler(request, ^(NSDictionary *response) {
                AutoDebugPeer *strongSelf = weakSelf;
                if (!strongSelf) return;
                dispatch_async(strongSelf.queue, ^{
                    [strongSelf completeRequestWithKey:requestKey response:response];
                });
            });
        } @catch (NSException *exception) {
            [self completeRequestWithKey:requestKey
                                response:@{ @"ok": @NO,
                                            @"error": exception.reason ?: @"Debug request handler failed." }];
        }
    }
}

- (void)processBuffer {
    if (!self.handshakeComplete) [self processHandshake];
    if (self.handshakeComplete) [self processFrames];
}

@end

@implementation AutoDebugServer

- (BOOL)isRunning {
    @synchronized (self) { return _running; }
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _peers = [NSMutableSet set];
        _queue = dispatch_queue_create("com.autosdk.runtime.debug", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)startWithPort:(uint16_t)port
                token:(NSString *)token
       requestHandler:(AutoDebugRequestHandler)requestHandler
           completion:(void (^)(NSError * _Nullable error))completion {
    [self startWithPort:port
                  token:token
             allowsWiFi:NO
         requestHandler:requestHandler
             completion:completion];
}

- (void)startWithPort:(uint16_t)port
                token:(NSString *)token
           allowsWiFi:(BOOL)allowsWiFi
       requestHandler:(AutoDebugRequestHandler)requestHandler
           completion:(void (^)(NSError * _Nullable error))completion {
    [self startWithPort:port
                  token:token
             allowsWiFi:allowsWiFi
            serviceName:nil
         requestHandler:requestHandler
             completion:completion];
}

- (void)startWithPort:(uint16_t)port
                token:(NSString *)token
           allowsWiFi:(BOOL)allowsWiFi
          serviceName:(NSString *)serviceName
       requestHandler:(AutoDebugRequestHandler)requestHandler
           completion:(void (^)(NSError * _Nullable error))completion {
    if (port == 0 || token.length == 0 || !requestHandler) {
        if (completion) completion(AutoDebugError(AutoSDKErrorInvalidConfiguration, @"Debug server requires a port, token and request handler.", nil));
        return;
    }
    if ([token lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 1024) {
        if (completion) completion(AutoDebugError(AutoSDKErrorInvalidConfiguration, @"Debug token must not exceed 1024 UTF-8 bytes.", nil));
        return;
    }
    if (allowsWiFi && token.length < 16) {
        if (completion) completion(AutoDebugError(AutoSDKErrorInvalidConfiguration, @"Wi-Fi debugging requires a token containing at least 16 characters.", nil));
        return;
    }
    nw_parameters_t parameters = nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL,
                                                                  NW_PARAMETERS_DEFAULT_CONFIGURATION);
    if (allowsWiFi) {
        nw_parameters_prohibit_interface_type(parameters, nw_interface_type_cellular);
    } else {
        nw_parameters_set_required_interface_type(parameters, nw_interface_type_loopback);
    }
    NSString *portString = [NSString stringWithFormat:@"%hu", port];
    nw_listener_t listener = nw_listener_create_with_port(portString.UTF8String, parameters);
    if (!listener) {
        if (completion) completion(AutoDebugError(AutoSDKErrorDebugServerFailed, @"Unable to create debug listener.", nil));
        return;
    }
    if (allowsWiFi) {
        NSString *bonjourName = serviceName.length > 0 ? serviceName : @"AutoSDK iPhone";
        NSData *nameBytes = [bonjourName dataUsingEncoding:NSUTF8StringEncoding];
        if (nameBytes.length > 63 || [bonjourName rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) {
            nw_listener_cancel(listener);
            if (completion) completion(AutoDebugError(AutoSDKErrorInvalidConfiguration, @"Bonjour service name must be at most 63 UTF-8 bytes and contain no control characters.", nil));
            return;
        }
        nw_listener_set_service(listener, bonjourName.UTF8String, "_autosdk._tcp", NULL);
    }
    NSUInteger generation = 0;
    BOOL accepted = NO;
    @synchronized (self) {
        accepted = !self.listener && !self.running;
        if (accepted) {
            self.listener = listener;
            self.pendingStartCompletion = completion;
            generation = ++self.listenerGeneration;
        }
    }
    if (!accepted) {
        nw_listener_cancel(listener);
        if (completion) completion(AutoDebugError(AutoSDKErrorDebugServerFailed, @"Debug server is already running.", nil));
        return;
    }
    __weak AutoDebugServer *weakSelf = self;
    nw_listener_set_queue(listener, self.queue);
    nw_listener_set_state_changed_handler(listener, ^(nw_listener_state_t state, nw_error_t error) {
        AutoDebugServer *strongSelf = weakSelf;
        if (!strongSelf) return;
        void (^startCompletion)(NSError *) = nil;
        if (state == nw_listener_state_ready) {
            @synchronized (strongSelf) {
                if (strongSelf.listener != listener || strongSelf.listenerGeneration != generation) return;
                strongSelf.running = YES;
                startCompletion = strongSelf.pendingStartCompletion;
                strongSelf.pendingStartCompletion = nil;
            }
            if (startCompletion) startCompletion(nil);
        } else if (state == nw_listener_state_failed || state == nw_listener_state_cancelled) {
            NSSet<AutoDebugPeer *> *failedPeers = nil;
            @synchronized (strongSelf) {
                if (strongSelf.listener != listener || strongSelf.listenerGeneration != generation) return;
                strongSelf.listener = nil;
                strongSelf.running = NO;
                strongSelf.listenerGeneration += 1;
                startCompletion = strongSelf.pendingStartCompletion;
                strongSelf.pendingStartCompletion = nil;
                failedPeers = [strongSelf.peers copy];
                [strongSelf.peers removeAllObjects];
            }
            if (state == nw_listener_state_failed) nw_listener_cancel(listener);
            for (AutoDebugPeer *peer in failedPeers) [peer stop];
            if (startCompletion) {
                NSString *message = state == nw_listener_state_cancelled
                    ? @"Debug listener was cancelled before it became ready."
                    : @"Debug listener failed.";
                startCompletion(AutoDebugError(AutoSDKErrorDebugServerFailed, message, AutoNSErrorFromNWError(error)));
            }
        }
    });
    nw_listener_set_new_connection_handler(listener, ^(nw_connection_t connection) {
        AutoDebugServer *strongSelf = weakSelf;
        if (!strongSelf) return;
        AutoDebugPeer *peer = [[AutoDebugPeer alloc] initWithConnection:connection token:token requestHandler:requestHandler];
        __weak AutoDebugServer *serverRef = strongSelf;
        peer.didStop = ^(AutoDebugPeer *stoppedPeer) {
            AutoDebugServer *server = serverRef;
            if (server) @synchronized (server) { [server.peers removeObject:stoppedPeer]; }
        };
        BOOL acceptedPeer = NO;
        @synchronized (strongSelf) {
            acceptedPeer = strongSelf.listener == listener &&
                           strongSelf.listenerGeneration == generation &&
                           strongSelf.running &&
                           strongSelf.peers.count < 8;
            if (acceptedPeer) {
                [strongSelf.peers addObject:peer];
            }
        }
        if (!acceptedPeer) {
            peer.didStop = nil;
            nw_connection_cancel(connection);
            return;
        }
        [peer start];
    });
    nw_listener_start(listener);
}

- (void)stop {
    __block nw_listener_t listener = nil;
    NSSet *peers = nil;
    void (^pendingStartCompletion)(NSError *) = nil;
    @synchronized (self) {
        listener = self.listener;
        self.listener = nil;
        self.running = NO;
        self.listenerGeneration += 1;
        pendingStartCompletion = self.pendingStartCompletion;
        self.pendingStartCompletion = nil;
        peers = [self.peers copy];
        [self.peers removeAllObjects];
    }
    if (listener) nw_listener_cancel(listener);
    for (AutoDebugPeer *peer in peers) [peer stop];
    if (pendingStartCompletion) {
        pendingStartCompletion(AutoDebugError(AutoSDKErrorDebugServerFailed,
                                              @"Debug server stopped before it became ready.", nil));
    }
}

@end
