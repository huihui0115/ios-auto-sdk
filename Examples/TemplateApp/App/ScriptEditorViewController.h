#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/** On-device script editor: create/edit JavaScript, run it, and save to the sandbox. */
@interface ScriptEditorViewController : UIViewController

- (instancetype)initWithScriptName:(nullable NSString *)name source:(nullable NSString *)source;
/** Called after a successful save with the deployed script name. */
@property (nonatomic, copy, nullable) void (^onSaved)(NSString *name);

@end

NS_ASSUME_NONNULL_END
