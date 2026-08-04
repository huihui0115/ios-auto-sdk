#import "ScriptListViewController.h"
#import "AutoTemplateSettings.h"
#import "ScriptEditorViewController.h"
#import "SettingsViewController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
@import AutoSDK;

@interface ScriptListViewController () <UITableViewDataSource, UITableViewDelegate, UIDocumentPickerDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UITextView *logView;
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, NSString *> *> *scriptItems;
@property (nonatomic, assign) NSInteger selectedIndex;
@end

@implementation ScriptListViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"AutoSDK Scripts";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.selectedIndex = NSNotFound;

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.accessibilityIdentifier = @"script-list";
    [self.view addSubview:self.tableView];

    self.logView = [UITextView new];
    self.logView.translatesAutoresizingMaskIntoConstraints = NO;
    self.logView.editable = NO;
    self.logView.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.logView.backgroundColor = UIColor.secondarySystemBackgroundColor;
    self.logView.accessibilityIdentifier = @"script-log";
    [self.view addSubview:self.logView];

    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:guide.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor],
        [self.tableView.heightAnchor constraintEqualToAnchor:guide.heightAnchor multiplier:0.48],
        [self.logView.topAnchor constraintEqualToAnchor:self.tableView.bottomAnchor constant:8],
        [self.logView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:12],
        [self.logView.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-12],
        [self.logView.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor]
    ]];

    UIBarButtonItem *run = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemPlay target:self action:@selector(runSelectedScript)];
    run.accessibilityIdentifier = @"run-script";
    UIBarButtonItem *stop = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemStop target:self action:@selector(stopScript)];
    stop.accessibilityIdentifier = @"stop-script";
    self.navigationItem.rightBarButtonItems = @[run, stop];
    UIBarButtonItem *settings = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"gearshape"] style:UIBarButtonItemStylePlain target:self action:@selector(openSettings)];
    settings.accessibilityIdentifier = @"open-settings";
    UIBarButtonItem *refresh = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(reloadScripts)];
    refresh.accessibilityIdentifier = @"refresh-scripts";
    self.navigationItem.leftBarButtonItems = @[settings, refresh];

    UIBarButtonItem *newScript = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(createScript)];
    newScript.accessibilityIdentifier = @"new-script";
    UIBarButtonItem *import = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"folder"] style:UIBarButtonItemStylePlain target:self action:@selector(importScript)];
    import.accessibilityIdentifier = @"import-script";
    UIBarButtonItem *edit = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"pencil"] style:UIBarButtonItemStylePlain target:self action:@selector(editSelected)];
    edit.accessibilityIdentifier = @"edit-script";
    UIBarButtonItem *rename = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"textformat"] style:UIBarButtonItemStylePlain target:self action:@selector(renameSelected)];
    rename.accessibilityIdentifier = @"rename-script";
    UIBarButtonItem *export = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(exportSelected)];
    export.accessibilityIdentifier = @"export-script";
    UIBarButtonItem *space = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    self.toolbarItems = @[newScript, import, space, edit, rename, export];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(scriptsChanged:) name:@"AutoSDKScriptsChanged" object:nil];

    [self reloadScripts];
    [self updateDebugHint];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setToolbarHidden:NO animated:animated];
    [self reloadScripts];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.navigationController setToolbarHidden:YES animated:animated];
}

- (void)scriptsChanged:(NSNotification *)notification {
    [self reloadScripts];
}

- (void)openSettings {
    [self.navigationController pushViewController:[SettingsViewController new] animated:YES];
}

- (void)updateDebugHint {
#if DEBUG
    NSString *debugToken = [NSUserDefaults.standardUserDefaults stringForKey:@"AutoSDKDebugToken"];
    if (debugToken.length > 0) {
        BOOL usesWiFi = [NSUserDefaults.standardUserDefaults boolForKey:@"AutoSDKDebugWiFiActive"];
        NSUInteger port = [NSUserDefaults.standardUserDefaults integerForKey:@"AutoSDKDebugPort"];
        if (port == 0) port = 9001;
        NSString *address = usesWiFi ? [AutoTemplateSettings wifiIPv4Address] ?: @"" : @"127.0.0.1";
        NSString *url = address.length > 0
            ? [NSString stringWithFormat:@"ws://%@:%lu", address, (unsigned long)port]
            : @"Connect this iPhone to Wi-Fi to obtain its debug URL.";
        NSString *mode = usesWiFi ? @"Wi-Fi" : @"USB tunnel";
        self.logView.text = [NSString stringWithFormat:@"Debug mode: %@\nDebug URL: %@\nDebug token: %@\n\n%@",
                             mode, url, debugToken, self.logView.text ?: @""];
    }
#endif
}

- (void)reloadScripts {
    NSMutableArray<NSDictionary<NSString *, NSString *> *> *items = [NSMutableArray array];
    NSArray<NSString *> *bundlePaths = [[[NSBundle mainBundle] pathsForResourcesOfType:@"js" inDirectory:nil]
        sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    for (NSString *path in bundlePaths) {
        [items addObject:@{ @"name": path.lastPathComponent, @"source": @"Bundled", @"path": path }];
    }
    NSError *error = nil;
    NSArray<NSDictionary<NSString *, id> *> *deployed = [AutoEngine.sharedEngine deployedScriptsWithError:&error];
    for (NSDictionary *script in deployed ?: @[]) {
        NSString *name = [script[@"name"] isKindOfClass:NSString.class] ? script[@"name"] : nil;
        if (name.length > 0) [items addObject:@{ @"name": name, @"source": @"Deployed" }];
    }
    self.scriptItems = items;
    self.selectedIndex = items.count > 0 ? 0 : NSNotFound;
    [self.tableView reloadData];
    if (items.count > 0) {
        [self.tableView selectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]
                                   animated:NO scrollPosition:UITableViewScrollPositionNone];
    } else {
        self.logView.text = error.localizedDescription ?: @"No bundled or deployed JavaScript files found.\nTap + to create one.";
    }
    if (error) self.logView.text = [NSString stringWithFormat:@"Unable to load deployed scripts: %@", error.localizedDescription];
    [self updateDebugHint];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.scriptItems.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"ScriptCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    NSDictionary *item = self.scriptItems[indexPath.row];
    cell.textLabel.text = item[@"name"];
    cell.detailTextLabel.text = item[@"source"];
    cell.accessibilityIdentifier = [@"script-" stringByAppendingString:item[@"name"] ?: @"unknown"];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    self.selectedIndex = indexPath.row;
}

- (NSDictionary *)selectedItem {
    if (self.selectedIndex == NSNotFound || self.selectedIndex >= self.scriptItems.count) return nil;
    return self.scriptItems[self.selectedIndex];
}

- (void)runSelectedScript {
    NSDictionary *item = [self selectedItem];
    if (!item) return;
    NSString *name = item[@"name"];
    self.logView.text = [NSString stringWithFormat:@"Running %@...\n", name];
    __weak ScriptListViewController *weakSelf = self;
    AutoScriptCompletion completion = ^(NSDictionary *result, NSError *error) {
        ScriptListViewController *strongSelf = weakSelf;
        if (!strongSelf) return;
        id output = error ? @{ @"error": error.localizedDescription ?: @"Unknown error",
                               @"code": @(error.code),
                               @"logs": error.userInfo[@"logs"] ?: @[] } : (result ?: @{});
        NSData *data = [NSJSONSerialization dataWithJSONObject:output options:NSJSONWritingPrettyPrinted error:nil];
        strongSelf.logView.text = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : [output description];
        [strongSelf updateDebugHint];
    };
    if ([item[@"source"] isEqualToString:@"Deployed"]) {
        [AutoEngine.sharedEngine runDeployedScriptNamed:name completion:completion];
    } else {
        [AutoEngine.sharedEngine runScript:item[@"path"] completion:completion];
    }
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return [self.scriptItems[indexPath.row][@"source"] isEqualToString:@"Deployed"];
}

- (void)tableView:(UITableView *)tableView
commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
 forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) return;
    NSString *name = self.scriptItems[indexPath.row][@"name"];
    NSError *error = nil;
    if (![AutoEngine.sharedEngine deleteDeployedScriptNamed:name error:&error]) {
        self.logView.text = error.localizedDescription ?: @"Unable to delete the deployed script.";
        return;
    }
    [self reloadScripts];
}

- (void)stopScript {
    [AutoEngine.sharedEngine stopScript];
    self.logView.text = [self.logView.text stringByAppendingString:@"\nStop requested."];
}

#pragma mark - Editor / import / rename / export

- (void)createScript {
    [self presentEditorWithName:nil source:nil];
}

- (void)editSelected {
    NSDictionary *item = [self selectedItem];
    if (!item) return;
    NSString *name = item[@"name"];
    if ([item[@"source"] isEqualToString:@"Deployed"]) {
        NSError *error = nil;
        NSString *content = [AutoEngine.sharedEngine deployedScriptContentNamed:name error:&error];
        if (!content) {
            self.logView.text = error.localizedDescription ?: @"Unable to read the script.";
            return;
        }
        [self presentEditorWithName:name source:content];
    } else {
        NSString *path = item[@"path"];
        NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
        [self presentEditorWithName:nil source:content];
    }
}

- (void)presentEditorWithName:(NSString *)name source:(NSString *)source {
    ScriptEditorViewController *editor = [[ScriptEditorViewController alloc] initWithScriptName:name source:source];
    __weak ScriptListViewController *weakSelf = self;
    editor.onSaved = ^(NSString *savedName) {
        [weakSelf reloadScripts];
    };
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:editor];
    navigation.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:navigation animated:YES completion:nil];
}

- (void)importScript {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:@[UTTypeJavaScript, UTTypePlainText]
                         asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;
    NSString *source = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil];
    if (source.length == 0) {
        self.logView.text = @"Unable to read the imported file.";
        return;
    }
    NSString *base = [url.lastPathComponent stringByDeletingPathExtension];
    NSString *safeBase = [[[base stringByReplacingOccurrencesOfString:@" " withString:@"-"]
                                componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\\/:*?\"<>|"]] componentsJoinedByString:@"-"];
    NSString *name = [safeBase stringByAppendingPathExtension:@"js"];
    NSError *error = nil;
    if (![AutoEngine.sharedEngine saveDeployedScriptNamed:name script:source error:&error]) {
        self.logView.text = error.localizedDescription ?: @"Import failed.";
        return;
    }
    [self reloadScripts];
    self.logView.text = [NSString stringWithFormat:@"Imported %@", name];
}

- (void)renameSelected {
    NSDictionary *item = [self selectedItem];
    if (!item || ![item[@"source"] isEqualToString:@"Deployed"]) {
        self.logView.text = @"Only deployed scripts can be renamed.";
        return;
    }
    NSString *oldName = item[@"name"];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Rename Script"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = oldName;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Rename" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *newName = [[alert.textFields.firstObject text] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (newName.length == 0) return;
        NSError *error = nil;
        if (![AutoEngine.sharedEngine renameDeployedScriptNamed:oldName toName:newName error:&error]) {
            self.logView.text = error.localizedDescription ?: @"Rename failed.";
            return;
        }
        [self reloadScripts];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)exportSelected {
    NSDictionary *item = [self selectedItem];
    if (!item) return;
    NSString *name = item[@"name"];
    NSString *content = nil;
    if ([item[@"source"] isEqualToString:@"Deployed"]) {
        NSError *error = nil;
        content = [AutoEngine.sharedEngine deployedScriptContentNamed:name error:&error];
    } else {
        content = [NSString stringWithContentsOfFile:item[@"path"] encoding:NSUTF8StringEncoding error:nil];
    }
    if (content.length == 0) {
        self.logView.text = @"Unable to read the script for export.";
        return;
    }
    NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
    [content writeToFile:tempPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:tempPath]] applicationActivities:nil];
    activity.popoverPresentationController.sourceView = self.view;
    [self presentViewController:activity animated:YES completion:nil];
}

@end
