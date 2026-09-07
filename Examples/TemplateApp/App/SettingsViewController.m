#import "SettingsViewController.h"
#import "AutoTemplateSettings.h"
@import AutoSDK;

typedef NS_ENUM(NSInteger, AutoSettingsRow) {
    AutoSettingsRowDebugURL,
    AutoSettingsRowBonjourName,
    AutoSettingsRowDebugToken,
    AutoSettingsRowDebugPort,
    AutoSettingsRowWiFi,
    AutoSettingsRowBuiltinSwitch,
    AutoSettingsRowVersion,
    AutoSettingsRowCount
};

@interface SettingsViewController ()
@property (nonatomic, strong) UISwitch *wifiSwitch;
@property (nonatomic, strong) UISwitch *builtinSwitch;
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
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 5;   // Debug
    if (section == 1) return 1;   // Adapter
    return 1;                     // Info
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"Debug Server (VS Code)";
    if (section == 1) return @"Automation adapter";
    return @"About";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 1) {
        return @"内置适配器的跨 App 能力取决于系统、实际签名权限与真机验证；普通签名不保证可用。关闭后只操作宿主 App。后台执行时间由 iOS 限制，不保证永久保活。";
    }
    if (section == 2) {
        BOOL lowMemory = NSProcessInfo.processInfo.physicalMemory <= 2ULL * 1024 * 1024 * 1024;
        return lowMemory ? @"低内存保护已自动启用（适合 iPhone 7）：限制节点、图片和日志开销。内存告警或严重发热时会请求停止，需手动重新运行。"
            : @"资源保护已启用。内存告警或严重发热时会请求停止，需手动重新运行。";
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
        if (indexPath.row == AutoSettingsRowDebugURL || indexPath.row == AutoSettingsRowBonjourName || indexPath.row == AutoSettingsRowDebugToken) {
            cell = [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            if (indexPath.row == AutoSettingsRowDebugURL) {
                cell.textLabel.text = @"Debug URL";
                cell.detailTextLabel.text = [NSString stringWithFormat:@"ws://%@:%lu", address, (unsigned long)port];
            } else if (indexPath.row == AutoSettingsRowBonjourName) {
                cell.textLabel.text = @"Wi-Fi Broadcast";
                cell.detailTextLabel.text = [AutoTemplateSettings debugServiceName];
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
        cell = [tableView dequeueReusableCellWithIdentifier:@"switch-cell" forIndexPath:indexPath];
        cell.textLabel.text = @"Built-in no-WDA adapter";
        NSString *adapter = [defaults stringForKey:@"AutoSDKAdapter"];
        if (adapter.length == 0) adapter = [bundle objectForInfoDictionaryKey:@"AutoSDKAdapter"];
        self.builtinSwitch = [UISwitch new];
        self.builtinSwitch.on = adapter.length == 0 || [adapter caseInsensitiveCompare:@"UIKIT"] != NSOrderedSame;
        [self.builtinSwitch addTarget:self action:@selector(builtinToggled:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = self.builtinSwitch;
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
}

- (void)wifiToggled:(UISwitch *)sender {
    [NSUserDefaults.standardUserDefaults setBool:sender.on forKey:@"AutoSDKDebugAllowWiFi"];
    [AutoTemplateSettings applyEngineConfiguration];
}

- (void)builtinToggled:(UISwitch *)sender {
    [NSUserDefaults.standardUserDefaults setObject:sender.on ? @"BUILTIN" : @"UIKIT" forKey:@"AutoSDKAdapter"];
    [AutoTemplateSettings applyEngineConfiguration];
}

@end
