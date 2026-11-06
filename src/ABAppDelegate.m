#import "ABAppDelegate.h"
#import "ABAppListViewController.h"
#import "ABBackupListViewController.h"
#import "ABDeviceViewController.h"
#import "ABTweakInstaller.h"
#import "ABChrome.h"
#import "ABIcon.h"

@implementation ABAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    ABInstallAppearance();
    self.window.tintColor = ABAccentColor();

    ABAppListViewController *apps = [ABAppListViewController new];
    UINavigationController *appsNavigation = [[UINavigationController alloc] initWithRootViewController:apps];
    appsNavigation.navigationBar.prefersLargeTitles = YES;
    appsNavigation.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"应用" image:[UIImage systemImageNamed:@"list.bullet"] tag:0];

    ABBackupListViewController *backups = [ABBackupListViewController new];
    UINavigationController *backupsNavigation = [[UINavigationController alloc] initWithRootViewController:backups];
    backupsNavigation.navigationBar.prefersLargeTitles = YES;
    backupsNavigation.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"备份" image:[UIImage systemImageNamed:@"clock"] tag:1];

    ABDeviceViewController *device = [ABDeviceViewController new];
    UINavigationController *deviceNavigation = [[UINavigationController alloc] initWithRootViewController:device];
    deviceNavigation.navigationBar.prefersLargeTitles = YES;
    deviceNavigation.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"设置" image:[UIImage systemImageNamed:@"gearshape"] tag:2];

    UITabBarController *tabs = [UITabBarController new];
    tabs.viewControllers = @[appsNavigation, backupsNavigation, deviceNavigation];
    self.window.rootViewController = tabs;
    [self.window makeKeyAndVisible];
    dispatch_async(dispatch_get_main_queue(), ^{
        [ABTweakInstaller presentInstallerFromViewController:tabs userInitiated:NO];
    });
    return YES;
}

@end
