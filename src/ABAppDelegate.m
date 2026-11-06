#import "ABAppDelegate.h"
#import "ABAppListViewController.h"
#import "ABBackupListViewController.h"
#import "ABDeviceViewController.h"
#import "ABIcon.h"

@implementation ABAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.tintColor = ABAccentColor();
    UINavigationBar.appearance.tintColor = ABAccentColor();
    UITabBar.appearance.tintColor = ABAccentColor();
    UISwitch.appearance.onTintColor = ABAccentColor();

    ABAppListViewController *apps = [ABAppListViewController new];
    UINavigationController *appsNavigation = [[UINavigationController alloc] initWithRootViewController:apps];
    appsNavigation.navigationBar.prefersLargeTitles = YES;
    appsNavigation.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"应用" image:[UIImage systemImageNamed:@"square.grid.2x2"] tag:0];

    ABBackupListViewController *backups = [ABBackupListViewController new];
    UINavigationController *backupsNavigation = [[UINavigationController alloc] initWithRootViewController:backups];
    backupsNavigation.navigationBar.prefersLargeTitles = YES;
    backupsNavigation.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"备份" image:[UIImage systemImageNamed:@"archivebox"] tag:1];

    ABDeviceViewController *device = [ABDeviceViewController new];
    UINavigationController *deviceNavigation = [[UINavigationController alloc] initWithRootViewController:device];
    deviceNavigation.navigationBar.prefersLargeTitles = YES;
    deviceNavigation.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"机型" image:[UIImage systemImageNamed:@"iphone.gen3"] tag:2];

    UITabBarAppearance *bar = [UITabBarAppearance new];
    [bar configureWithOpaqueBackground];
    UITabBar.appearance.standardAppearance = bar;
    UITabBar.appearance.scrollEdgeAppearance = bar;

    UITabBarController *tabs = [UITabBarController new];
    tabs.viewControllers = @[appsNavigation, backupsNavigation, deviceNavigation];
    self.window.rootViewController = tabs;
    [self.window makeKeyAndVisible];
    return YES;
}

@end
