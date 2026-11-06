#import "ABChrome.h"
#import "ABIcon.h"

void ABInstallAppearance(void) {
    UIColor *accent = ABAccentColor();
    UINavigationBarAppearance *navigation = [UINavigationBarAppearance new];
    [navigation configureWithDefaultBackground];
    navigation.titleTextAttributes = @{NSForegroundColorAttributeName : UIColor.labelColor};
    navigation.largeTitleTextAttributes = @{NSForegroundColorAttributeName : UIColor.labelColor};
    UINavigationBar.appearance.standardAppearance = navigation;
    UINavigationBar.appearance.scrollEdgeAppearance = navigation;
    UINavigationBar.appearance.compactAppearance = navigation;
    UINavigationBar.appearance.tintColor = accent;

    UITabBarAppearance *tab = [UITabBarAppearance new];
    [tab configureWithDefaultBackground];
    tab.stackedLayoutAppearance.selected.iconColor = accent;
    tab.stackedLayoutAppearance.selected.titleTextAttributes = @{NSForegroundColorAttributeName : accent};
    UITabBar.appearance.standardAppearance = tab;
    UITabBar.appearance.scrollEdgeAppearance = tab;
    UITabBar.appearance.tintColor = accent;
    UISwitch.appearance.onTintColor = accent;
}

UIImage *ABSymbolImage(NSString *name) {
    UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightSemibold];
    return [[UIImage systemImageNamed:name] imageByApplyingSymbolConfiguration:configuration];
}

UIBackgroundConfiguration *ABHighlightedCellBackground(void) {
    UIBackgroundConfiguration *background = [UIBackgroundConfiguration listGroupedCellConfiguration];
    background.backgroundColor = [ABAccentColor() colorWithAlphaComponent:0.14];
    return background;
}
