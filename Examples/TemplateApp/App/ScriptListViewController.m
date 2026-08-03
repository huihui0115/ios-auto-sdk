#import "ScriptListViewController.h"
@import AutoSDK;
#include <arpa/inet.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <string.h>

static NSString *AutoTemplateWiFiIPv4Address(void) {
    struct ifaddrs *interfaces = NULL;
    if (getifaddrs(&interfaces) != 0 || !interfaces) return nil;
    NSString *result = nil;
    for (struct ifaddrs *item = interfaces; item; item = item->ifa_next) {
        if (!item->ifa_addr || item->ifa_addr->sa_family != AF_INET) continue;
        if ((item->ifa_flags & IFF_UP) == 0 || (item->ifa_flags & IFF_LOOPBACK) != 0) continue;
        if (strcmp(item->ifa_name, "en0") != 0) continue;
        char address[INET_ADDRSTRLEN] = {0};
        struct sockaddr_in *ipv4 = (struct sockaddr_in *)item->ifa_addr;
        if (inet_ntop(AF_INET, &ipv4->sin_addr, address, sizeof(address))) {
            result = [NSString stringWithUTF8String:address];
            break;
        }
    }
    freeifaddrs(interfaces);
    return result;
}

@interface ScriptListViewController () <UITableViewDataSource, UITableViewDelegate>
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
    UIBarButtonItem *refresh = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(reloadScripts)];
    refresh.accessibilityIdentifier = @"refresh-scripts";
    self.navigationItem.leftBarButtonItem = refresh;
    [self reloadScripts];
#if DEBUG
    NSString *debugToken = [NSUserDefaults.standardUserDefaults stringForKey:@"AutoSDKDebugToken"];
    if (debugToken.length > 0) {
        BOOL usesWiFi = [NSUserDefaults.standardUserDefaults boolForKey:@"AutoSDKDebugWiFiActive"];
        NSUInteger port = [NSUserDefaults.standardUserDefaults integerForKey:@"AutoSDKDebugPort"];
        if (port == 0) port = 9001;
        NSString *address = usesWiFi ? AutoTemplateWiFiIPv4Address() : @"127.0.0.1";
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
        self.logView.text = error.localizedDescription ?: @"No bundled or deployed JavaScript files found.";
    }
    if (error) self.logView.text = [NSString stringWithFormat:@"Unable to load deployed scripts: %@", error.localizedDescription];
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

- (void)runSelectedScript {
    if (self.selectedIndex == NSNotFound || self.selectedIndex >= self.scriptItems.count) return;
    NSDictionary *item = self.scriptItems[self.selectedIndex];
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

@end
