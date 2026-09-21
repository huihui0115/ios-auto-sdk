#import "AutoAccessibilityControl.h"
#import "include/AutoSDKError.h"
#import <UIKit/UIKit.h>
#import <TargetConditionals.h>
#include <dlfcn.h>
#include <string.h>

Class AutoAssistiveTouchControlClass(void) {
    static Class control;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
#if !TARGET_OS_SIMULATOR
        // Optional private SPI; no private framework is linked into the SDK.
        // Symbol availability does not prove the host has permission to change it.
        dlopen("/System/Library/PrivateFrameworks/Preferences.framework/Preferences", RTLD_LAZY | RTLD_LOCAL);
        control = NSClassFromString(@"PSAssistiveTouchSettingsDetail");
#endif
    });
    return control;
}

static BOOL AutoBoolEncoding(const char *encoding) {
    return encoding && (!strcmp(encoding, @encode(BOOL)) || !strcmp(encoding, "B") || !strcmp(encoding, "c"));
}

NSNumber *AutoAssistiveTouchState(Class control) {
    @try {
        SEL selector = NSSelectorFromString(@"isEnabled");
        NSMethodSignature *signature = [control methodSignatureForSelector:selector];
        if (![control respondsToSelector:selector] || signature.numberOfArguments != 2 ||
            !AutoBoolEncoding(signature.methodReturnType) || signature.methodReturnLength != sizeof(BOOL)) return nil;
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
        invocation.target = control;
        invocation.selector = selector;
        [invocation invoke];
        BOOL enabled = NO;
        [invocation getReturnValue:&enabled];
        return @(enabled);
    } @catch (__unused NSException *exception) { return nil; }
}

BOOL AutoSetAssistiveTouchEnabled(Class control, BOOL enabled, NSError **error) {
    NSString *reason = @"AssistiveTouch control is unavailable for this iOS version/signature. Open system.openSettings('assistiveTouch') and change it on the phone.";
    AutoSDKErrorCode code = AutoSDKErrorAutomationUnavailable;
    @try {
        NSNumber *before = AutoAssistiveTouchState(control);
        if (before && before.boolValue == enabled) return YES; // Idempotent, never toggle blindly.
        SEL selector = NSSelectorFromString(@"setEnabled:");
        NSMethodSignature *signature = [control methodSignatureForSelector:selector];
        if (before && [control respondsToSelector:selector] && signature.numberOfArguments == 3 &&
            !strcmp(signature.methodReturnType, @encode(void)) && AutoBoolEncoding([signature getArgumentTypeAtIndex:2])) {
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
            invocation.target = control;
            invocation.selector = selector;
            [invocation setArgument:&enabled atIndex:2];
            [invocation invoke];
            NSNumber *after = AutoAssistiveTouchState(control);
            if (after && after.boolValue == enabled) return YES;
            code = AutoSDKErrorAutomationFailed;
            reason = @"AssistiveTouch change was not confirmed. The signature may lack permission or iOS may apply it later. Check the phone; no automatic retry was made.";
        }
    } @catch (__unused NSException *exception) {
        reason = @"iOS rejected AssistiveTouch control. Check the phone's Settings and signing permissions.";
    }
    if (error) *error = [NSError errorWithDomain:AutoSDKErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: reason}];
    return NO;
}
