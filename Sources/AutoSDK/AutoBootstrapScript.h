#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Private helper: builds the JavaScript bootstrap that installs the global
// auto API, timer heap, storage, HTTP, file, device and console facades.
// Kept in its own file so AutoEngine.m stays navigable.
NSString *AutoBootstrapScript(void);

NS_ASSUME_NONNULL_END
