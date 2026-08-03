#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const AutoSDKErrorDomain;

typedef NS_ERROR_ENUM(AutoSDKErrorDomain, AutoSDKErrorCode) {
    AutoSDKErrorInvalidConfiguration = 1,
    AutoSDKErrorAlreadyRunning,
    AutoSDKErrorScriptNotFound,
    AutoSDKErrorScriptReadFailed,
    AutoSDKErrorScriptTooLarge,
    AutoSDKErrorScriptTimeout,
    AutoSDKErrorScriptCancelled,
    AutoSDKErrorAutomationUnavailable,
    AutoSDKErrorAutomationFailed,
    AutoSDKErrorJavaScriptException,
    AutoSDKErrorDebugServerFailed,
    AutoSDKErrorDebugUnauthorized,
    AutoSDKErrorElementNotFound,
    AutoSDKErrorWaitTimeout,
    AutoSDKErrorNetworkDisabled,
    AutoSDKErrorNetworkFailed,
    AutoSDKErrorFileAccessDenied,
    AutoSDKErrorFileOperationFailed,
    AutoSDKErrorStorageFailed
};

NS_ASSUME_NONNULL_END
