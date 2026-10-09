#import "ABAppDelegate.h"
#import "ABAppListViewController.h"
#import "ABBackupListViewController.h"
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

    UITabBarController *tabs = [UITabBarController new];
    tabs.viewControllers = @[appsNavigation, backupsNavigation];
    self.window.rootViewController = tabs;
    [self.window makeKeyAndVisible];
    return YES;
}

@end
