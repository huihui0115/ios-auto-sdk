#import "AppDelegate.h"
#import "AutoTemplateSettings.h"
#import "ScriptListViewController.h"
@import AutoSDK;

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    [AutoTemplateSettings applyEngineConfiguration];

    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    ScriptListViewController *scripts = [ScriptListViewController new];
    self.window.rootViewController = [[UINavigationController alloc] initWithRootViewController:scripts];
    [self.window makeKeyAndVisible];
    return YES;
}

- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options {
    if (![url isFileURL] || url.pathExtension.length == 0) return NO;
    NSString *extension = url.pathExtension.lowercaseString;
    if (![extension isEqualToString:@"js"] && ![extension isEqualToString:@"mjs"] && ![extension isEqualToString:@"txt"]) return NO;
    NSString *source = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil];
    if (source.length == 0) return NO;
    NSString *name = [url.lastPathComponent stringByDeletingPathExtension];
    NSString *safe = [[name stringByReplacingOccurrencesOfString:@" " withString:@"-"]
                          stringByAppendingPathExtension:@"js"];
    NSError *error = nil;
    if (![AutoEngine.sharedEngine saveDeployedScriptNamed:safe script:source error:&error]) {
        NSLog(@"[TemplateApp] Import failed: %@", error.localizedDescription ?: @"unknown error");
        return NO;
    }
    NSLog(@"[TemplateApp] Imported script %@", safe);
    [NSNotificationCenter.defaultCenter postNotificationName:@"AutoSDKScriptsChanged" object:nil];
    return YES;
}

@end
