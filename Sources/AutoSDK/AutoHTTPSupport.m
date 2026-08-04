#import "AutoHTTPSupport.h"

@implementation AutoHTTPRedirectPolicy
@end

@implementation AutoHTTPRedirectRouter {
    NSMapTable<NSURLSessionTask *, AutoHTTPRedirectPolicy *> *_policies;
    NSLock *_lock;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _policies = [NSMapTable weakToStrongObjectsMapTable];
        _lock = [NSLock new];
    }
    return self;
}

- (void)setPolicy:(AutoHTTPRedirectPolicy *)policy forTask:(NSURLSessionTask *)task {
    if (!task || !policy) return;
    [_lock lock];
    [_policies setObject:policy forKey:task];
    [_lock unlock];
}

- (void)removePolicyForTask:(NSURLSessionTask *)task {
    if (!task) return;
    [_lock lock];
    [_policies removeObjectForKey:task];
    [_lock unlock];
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
willPerformHTTPRedirection:(NSHTTPURLResponse *)response
        newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest * _Nullable))completionHandler {
    AutoHTTPRedirectPolicy *policy = nil;
    [_lock lock];
    policy = [_policies objectForKey:task];
    [_lock unlock];
    if (!policy || !policy.followsRedirects) {
        completionHandler(nil);
        return;
    }
    NSString *scheme = request.URL.scheme.lowercaseString;
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) {
        completionHandler(nil);
        return;
    }
    NSString *originalScheme = task.originalRequest.URL.scheme.lowercaseString;
    if ([originalScheme isEqualToString:@"https"] && [scheme isEqualToString:@"http"]) {
        completionHandler(nil);
        return;
    }
    if (policy.allowedHosts.count > 0) {
        BOOL allowed = NO;
        for (NSString *host in policy.allowedHosts) {
            if (request.URL.host.length > 0 && [request.URL.host caseInsensitiveCompare:host] == NSOrderedSame) {
                allowed = YES;
                break;
            }
        }
        completionHandler(allowed ? request : nil);
        return;
    }
    completionHandler(request);
    (void)session;
    (void)response;
}

@end
