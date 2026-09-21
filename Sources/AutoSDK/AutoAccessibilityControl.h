#import <Foundation/Foundation.h>

// Internal helpers. A supplied class is a test seam, never a script-controlled value.
NSNumber *AutoAssistiveTouchState(Class control);
BOOL AutoSetAssistiveTouchEnabled(Class control, BOOL enabled, NSError **error);
Class AutoAssistiveTouchControlClass(void);
