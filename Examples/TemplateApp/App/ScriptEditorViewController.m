#import "ScriptEditorViewController.h"
@import AutoSDK;

@interface ScriptEditorViewController () <UITextViewDelegate>
@property (nonatomic, copy, nullable) NSString *scriptName;
@property (nonatomic, copy, nullable) NSString *initialSource;
@property (nonatomic, strong) UITextView *sourceView;
@property (nonatomic, strong) UITextView *logView;
@property (nonatomic, strong) UIToolbar *toolbar;
@property (nonatomic, assign) BOOL running;
@end

@implementation ScriptEditorViewController

- (instancetype)initWithScriptName:(NSString *)name source:(NSString *)source {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _scriptName = [name copy];
        NSString *initial = source;
        if (initial.length == 0) {
            initial = @"// AutoSDK script
const info = device.getDeviceInfo();
console.log("device:", info.model);
";
        }
        _initialSource = [initial copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.title = self.scriptName ?: @"New Script";

    self.sourceView = [UITextView new];
    self.sourceView.translatesAutoresizingMaskIntoConstraints = NO;
    self.sourceView.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    self.sourceView.autocorrectionType = UITextAutocorrectionTypeNo;
    self.sourceView.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.sourceView.smartQuotesType = UITextSmartQuotesTypeNo;
    self.sourceView.smartDashesType = UITextSmartDashesTypeNo;
    self.sourceView.text = self.initialSource ?: @"";
    self.sourceView.accessibilityIdentifier = @"script-editor-source";
    [self.view addSubview:self.sourceView];

    self.logView = [UITextView new];
    self.logView.translatesAutoresizingMaskIntoConstraints = NO;
    self.logView.editable = NO;
    self.logView.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    self.logView.backgroundColor = UIColor.secondarySystemBackgroundColor;
    self.logView.accessibilityIdentifier = @"script-editor-log";
    [self.view addSubview:self.logView];

    self.toolbar = [UIToolbar new];
    self.toolbar.translatesAutoresizingMaskIntoConstraints = NO;
    UIBarButtonItem *run = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemPlay target:self action:@selector(runScript)];
    run.accessibilityIdentifier = @"editor-run";
    UIBarButtonItem *stop = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemStop target:self action:@selector(stopScript)];
    stop.accessibilityIdentifier = @"editor-stop";
    UIBarButtonItem *space = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    self.toolbar.items = @[run, stop, space];
    [self.view addSubview:self.toolbar];

    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.sourceView.topAnchor constraintEqualToAnchor:guide.topAnchor],
        [self.sourceView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
        [self.sourceView.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor],
        [self.sourceView.heightAnchor constraintEqualToAnchor:guide.heightAnchor multiplier:0.55],
        [self.logView.topAnchor constraintEqualToAnchor:self.sourceView.bottomAnchor constant:4],
        [self.logView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:8],
        [self.logView.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-8],
        [self.logView.bottomAnchor constraintEqualToAnchor:self.toolbar.topAnchor constant:-4],
        [self.toolbar.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
        [self.toolbar.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor],
        [self.toolbar.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor]
    ]];

    UIBarButtonItem *save = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave target:self action:@selector(saveScript)];
    save.accessibilityIdentifier = @"editor-save";
    self.navigationItem.rightBarButtonItem = save;
    UIBarButtonItem *close = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(close)];
    close.accessibilityIdentifier = @"editor-close";
    self.navigationItem.leftBarButtonItem = close;

    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboardWillChange:)
                                               name:UIKeyboardWillChangeFrameNotification object:nil];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [AutoEngine.sharedEngine stopScript];
}

- (void)close {
    [AutoEngine.sharedEngine stopScript];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)appendLog:(NSString *)text {
    NSString *existing = self.logView.text ?: @"";
    self.logView.text = existing.length == 0 ? text : [existing stringByAppendingFormat:@"\n%@", text];
    [self.logView scrollRangeToVisible:NSMakeRange(self.logView.text.length, 0)];
}

- (void)runScript {
    if (self.running) return;
    NSString *source = self.sourceView.text ?: @"";
    if (source.length == 0) { [self appendLog:@"Script is empty."]; return; }
    self.running = YES;
    self.logView.text = @"";
    [self appendLog:@"Running script..."];
    __weak ScriptEditorViewController *weakSelf = self;
    [AutoEngine.sharedEngine runScript:source completion:^(NSDictionary *result, NSError *error) {
        ScriptEditorViewController *strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.running = NO;
        NSArray *logs = error ? error.userInfo[@"logs"] : result[@"logs"];
        if ([logs isKindOfClass:NSArray.class]) {
            for (NSDictionary *entry in logs) {
                if ([entry isKindOfClass:NSDictionary.class]) {
                    [strongSelf appendLog:[NSString stringWithFormat:@"[%@] %@", entry[@"level"] ?: @"log", entry[@"message"] ?: @""]];
                }
            }
        }
        if (error) {
            [strongSelf appendLog:[NSString stringWithFormat:@"Error (%ld): %@", (long)error.code, error.localizedDescription ?: @""]];
        } else {
            id value = result[@"value"];
            NSString *valueText = value ? [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:value options:0 error:nil] encoding:NSUTF8StringEncoding] : @"undefined";
            [strongSelf appendLog:[NSString stringWithFormat:@"Value: %@", valueText ?: value]];
        }
    }];
}

- (void)stopScript {
    [AutoEngine.sharedEngine stopScript];
    self.running = NO;
    [self appendLog:@"Stop requested."];
}

- (void)saveScript {
    NSString *name = self.scriptName;
    if (name.length == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Script Name"
                                                                       message:@"Choose a name ending in .js"
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
            field.text = @"new-script.js";
            field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        }];
        [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            NSString *value = [[alert.textFields.firstObject text] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            if (value.length == 0) return;
            [self saveWithName:value];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    [self saveWithName:name];
}

- (void)saveWithName:(NSString *)name {
    NSError *error = nil;
    if (![AutoEngine.sharedEngine saveDeployedScriptNamed:name script:self.sourceView.text error:&error]) {
        [self appendLog:[NSString stringWithFormat:@"Save failed: %@", error.localizedDescription ?: @"unknown error"]];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Save Failed"
                                                                       message:error.localizedDescription
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    self.scriptName = name;
    self.title = name;
    [self appendLog:[NSString stringWithFormat:@"Saved %@", name]];
    if (self.onSaved) self.onSaved(name);
}

- (void)keyboardWillChange:(NSNotification *)notification {
    NSDictionary *info = notification.userInfo;
    CGRect end = [info[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGFloat duration = [info[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationOptions options = [info[UIKeyboardAnimationCurveUserInfoKey] unsignedIntegerValue] << 16;
    CGRect converted = [self.view convertRect:end fromView:nil];
    CGFloat overlap = CGRectGetMaxY(converted) - CGRectGetMinY(self.toolbar.frame);
    UIEdgeInsets insets = self.sourceView.contentInset;
    insets.bottom = MAX(0, overlap);
    self.sourceView.scrollIndicatorInsets = insets;
    [UIView animateWithDuration:duration delay:0 options:options animations:^{
        self.sourceView.contentInset = insets;
    } completion:nil];
}

@end
