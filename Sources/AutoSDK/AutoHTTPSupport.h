#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Per-task redirect policy for the shared HTTP session. allowedHosts == nil
// means same-scheme redirects to any http(s) host are allowed; an empty or
// populated array restricts redirects to those exact hosts.
@interface AutoHTTPRedirectPolicy : NSObject
@property (nonatomic, assign) BOOL followsRedirects;
@property (nonatomic, strong, nullable) NSArray<NSString *> *allowedHosts;
@end

// Routes NSURLSessionTaskDelegate redirect callbacks from the shared session
// to the policy registered for each task, so the engine can reuse one
// keep-alive session without giving up per-request redirect enforcement.
@interface AutoHTTPRedirectRouter : NSObject <NSURLSessionTaskDelegate>
- (void)setPolicy:(AutoHTTPRedirectPolicy *)policy forTask:(NSURLSessionTask *)task;
- (void)removePolicyForTask:(NSURLSessionTask *)task;
@end

NS_ASSUME_NONNULL_END
