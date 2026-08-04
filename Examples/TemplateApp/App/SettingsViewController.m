#import "SettingsViewController.h"
#import "AutoTemplateSettings.h"
@import AutoSDK;

typedef NS_ENUM(NSInteger, AutoSettingsRow) {
    AutoSettingsRowDebugURL,
    AutoSettingsRowDebugToken,
    AutoSettingsRowDebugPort,
    AutoSettingsRowWiFi,
    AutoSettingsRowWDASwitch,
    AutoSettingsRowWDAURL,
    AutoSettingsRowWDABundleId,
    AutoSettingsRowWDATimeout,
    AutoSettingsRowWDAApply,
    AutoSettingsRowVersion,
    AutoSettingsRowCount
};

@interface SettingsViewController ()
@property (nonatomic, strong) UISwitch *wifiSwitch;
@property (nonatomic, strong) UISwitch *wdaSwitch;
@property (nonatomic, strong) UITextField *wdaURLField;
@property (nonatomic, strong) UITextField *wdaBundleField;
@property (nonatomic, strong) UITextField *wdaTimeoutField;
@end

@implementation SettingsViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Settings";
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"cell"];
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"switch-cell"];
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"field-cell"];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 4;   // Debug
    if (section == 1) return 5;   // WDA
    return 1;                     // Info
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"Debug Server (VS Code)";
    if (section == 1) return @"WDA Runner (cross-app automation)";
    return @"About";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 1) {
        return @"Enabling WDA sends automation to a WDA-compatible runner "
               @"(for example WebDriverAgent) on this device. Changes apply immediately.";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSBundle *bundle = NSBundle.mainBundle;
    NSUInteger port = [defaults integerForKey:@"AutoSDKDebugPort"];
    if (port == 0) port = 9001;
    BOOL usesWiFi = [defaults boolForKey:@"AutoSDKDebugWiFiActive"];
    NSString *address = usesWiFi ? [AutoTemplateSettings wifiIPv4Address] ?: @"<no Wi-Fi>" : @"127.0.0.1";
    NSString *token = [defaults stringForKey:@"AutoSDKDebugToken"] ?: @"";

    UITableViewCell *cell = nil;
    if (indexPath.section == 0) {
        if (indexPath.row == AutoSettingsRowDebugURL || indexPath.row == AutoSettingsRowDebugToken) {
            cell = [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            if (indexPath.row == AutoSettingsRowDebugURL) {
                cell.textLabel.text = @"Debug URL";
                cell.detailTextLabel.text = [NSString stringWithFormat:@"ws://%@:%lu", address, (unsigned long)port];
            } else {
                cell.textLabel.text = @"Debug Token";
                cell.detailTextLabel.text = token;
                cell.detailTextLabel.numberOfLines = 0;
            }
            cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
            cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
        } else if (indexPath.row == AutoSettingsRowDebugPort) {
            cell = [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.textLabel.text = @"Port";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)port];
        } else {
            cell = [tableView dequeueReusableCellWithIdentifier:@"switch-cell" forIndexPath:indexPath];
            cell.textLabel.text = @"Allow Wi-Fi connections";
            self.wifiSwitch = [UISwitch new];
            self.wifiSwitch.on = [defaults boolForKey:@"AutoSDKDebugAllowWiFi"];
            [self.wifiSwitch addTarget:self action:@selector(wifiToggled:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = self.wifiSwitch;
        }
    } else if (indexPath.section == 1) {
        if (indexPath.row == AutoSettingsRowWDASwitch) {
            cell = [tableView dequeueReusableCellWithIdentifier:@"switch-cell" forIndexPath:indexPath];
            cell.textLabel.text = @"Use WDA adapter";
            NSString *adapter = [defaults stringForKey:@"AutoSDKAdapter"];
            if (adapter.length == 0) adapter = [bundle objectForInfoDictionaryKey:@"AutoSDKAdapter"];
            self.wdaSwitch = [UISwitch new];
            self.wdaSwitch.on = adapter.length > 0 && ([adapter caseInsensitiveCompare:@"WDA"] == NSOrderedSame || [adapter caseInsensitiveCompare:@"WDAHTTP"] == NSOrderedSame);
            [self.wdaSwitch addTarget:self action:@selector(wdaToggled:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = self.wdaSwitch;
        } else if (indexPath.row == AutoSettingsRowWDAApply) {
            cell = [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];
            cell.textLabel.text = @"Apply WDA Settings";
            cell.textLabel.textColor = self.view.tintColor;
        } else {
            cell = [tableView dequeueReusableCellWithIdentifier:@"field-cell" forIndexPath:indexPath];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            UITextField *field = nil;
            if (indexPath.row == AutoSettingsRowWDAURL) {
                cell.textLabel.text = @"Runner URL";
                field = self.wdaURLField ?: (self.wdaURLField = [UITextField new]);
                field.keyboardType = UIKeyboardTypeURL;
                field.text = [defaults stringForKey:@"AutoSDKWDAURL"] ?: [bundle objectForInfoDictionaryKey:@"AutoSDKWDAURL"];
            } else if (indexPath.row == AutoSettingsRowWDABundleId) {
                cell.textLabel.text = @"Target Bundle ID";
                field = self.wdaBundleField ?: (self.wdaBundleField = [UITextField new]);
                field.autocapitalizationType = UITextAutocapitalizationTypeNone;
                field.text = [defaults stringForKey:@"AutoSDKWDABundleId"];
            } else {
                cell.textLabel.text = @"Timeout (s)";
                field = self.wdaTimeoutField ?: (self.wdaTimeoutField = [UITextField new]);
                field.keyboardType = UIKeyboardTypeDecimalPad;
                double timeout = [defaults doubleForKey:@"AutoSDKWDATimeout"];
                if (timeout <= 0) timeout = [[bundle objectForInfoDictionaryKey:@"AutoSDKWDATimeout"] doubleValue];
                if (timeout <= 0) timeout = 15;
                field.text = [NSString stringWithFormat:@"%.0f", timeout];
            }
            field.font = [UIFont systemFontOfSize:15];
            field.textAlignment = NSTextAlignmentRight;
            field.frame = CGRectMake(0, 0, 180, 30);
            field.clearButtonMode = UITextFieldViewModeWhileEditing;
            cell.accessoryView = field;
        }
    } else {
        cell = [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.text = @"SDK Version";
        cell.detailTextLabel.text = [NSString stringWithUTF8String:(const char *)AutoSDKVersionString];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1 && indexPath.row == AutoSettingsRowWDAApply) {
        [self applyWDASettings];
    }
}

- (void)wifiToggled:(UISwitch *)sender {
    [NSUserDefaults.standardUserDefaults setBool:sender.on forKey:@"AutoSDKDebugAllowWiFi"];
    [AutoTemplateSettings applyEngineConfiguration];
}

- (void)wdaToggled:(UISwitch *)sender {
    [NSUserDefaults.standardUserDefaults setObject:sender.on ? @"WDA" : @"UIKit" forKey:@"AutoSDKAdapter"];
    [AutoTemplateSettings applyEngineConfiguration];
}

- (void)applyWDASettings {
    [self.view endEditing:YES];
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSString *url = [self.wdaURLField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (url.length == 0) url = @"http://127.0.0.1:8100";
    [defaults setObject:url forKey:@"AutoSDKWDAURL"];
    [defaults setObject:[self.wdaBundleField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet]
                 forKey:@"AutoSDKWDABundleId"];
    double timeout = [self.wdaTimeoutField.text doubleValue];
    if (timeout < 1) timeout = 15;
    [defaults setDouble:MIN(timeout, 120) forKey:@"AutoSDKWDATimeout"];
    [AutoTemplateSettings applyEngineConfiguration];
    [self.tableView reloadData];
}

@end
