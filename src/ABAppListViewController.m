#import "ABAppListViewController.h"
#import "ABAppDetailViewController.h"
#import "ABAppLibrary.h"
#import "ABChrome.h"
#import "ABIcon.h"

@interface ABAppListViewController () <UISearchResultsUpdating>
@property (nonatomic, copy) NSArray<ABAppInfo *> *apps;
@property (nonatomic, copy) NSString *searchText;
@property (nonatomic) BOOL accessDenied;
@property (nonatomic) BOOL loaded;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) dispatch_queue_t loadQueue;
@property (nonatomic, strong) UILabel *overviewLabel;
@end

@implementation ABAppListViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"应用";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.searchText = @"";
    self.loadQueue = dispatch_queue_create("com.local.appbackup.list", DISPATCH_QUEUE_SERIAL);
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"搜索名称或 Bundle ID";
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"info.circle"] style:UIBarButtonItemStylePlain target:self action:@selector(showHelp)];
    self.definesPresentationContext = YES;
    self.refreshControl = [UIRefreshControl new];
    [self.refreshControl addTarget:self action:@selector(reloadApps) forControlEvents:UIControlEventValueChanged];
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self buildOverview];
    [self reloadApps];
}

- (void)buildOverview {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 92)];
    UIView *card = [UIView new];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    card.layer.cornerRadius = 16;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    UIImageView *icon = [[UIImageView alloc] initWithImage:ABSymbolImage(@"square.grid.2x2.fill")];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.tintColor = ABAccentColor();
    UILabel *title = [UILabel new];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    title.text = @"应用库";
    UILabel *detail = [UILabel new];
    detail.translatesAutoresizingMaskIntoConstraints = NO;
    detail.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    detail.textColor = UIColor.secondaryLabelColor;
    detail.text = @"正在读取";
    self.overviewLabel = detail;
    [card addSubview:icon];
    [card addSubview:title];
    [card addSubview:detail];
    [header addSubview:card];
    [NSLayoutConstraint activateConstraints:@[
        [card.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20],
        [card.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20],
        [card.topAnchor constraintEqualToAnchor:header.topAnchor constant:4],
        [card.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-8],
        [icon.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [icon.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [title.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:12],
        [title.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [title.topAnchor constraintEqualToAnchor:card.topAnchor constant:16],
        [detail.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [detail.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
        [detail.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:2],
        [detail.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-16],
    ]];
    self.tableView.tableHeaderView = header;
}

- (NSArray<ABAppInfo *> *)visibleApps {
    if (self.searchText.length == 0) {
        return self.apps ?: @[];
    }
    NSString *query = self.searchText.lowercaseString;
    NSMutableArray<ABAppInfo *> *matches = [NSMutableArray array];
    for (ABAppInfo *app in self.apps) {
        if ([app.displayName.lowercaseString containsString:query] || [app.bundleIdentifier.lowercaseString containsString:query]) {
            [matches addObject:app];
        }
    }
    return matches;
}

- (void)reloadApps {
    dispatch_async(self.loadQueue, ^{
        ABAppLibrary *library = [ABAppLibrary sharedLibrary];
        [library reload];
        NSArray<ABAppInfo *> *apps = [library installedApps];
        BOOL denied = library.accessDenied;
        dispatch_async(dispatch_get_main_queue(), ^{
            self.apps = apps;
            self.accessDenied = denied;
            self.loaded = YES;
            [self.refreshControl endRefreshing];
            self.overviewLabel.text = denied ? @"无法读取其他应用" : [NSString stringWithFormat:@"%lu 个已安装的应用", (unsigned long)apps.count];
            [self.tableView reloadData];
            [self updateEmptyState];
        });
    });
}

- (void)updateEmptyState {
    NSArray *visible = [self visibleApps];
    if (!self.loaded || visible.count > 0) {
        self.tableView.backgroundView = nil;
        return;
    }
    UILabel *label = [[UILabel alloc] initWithFrame:self.tableView.bounds];
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    label.textColor = UIColor.secondaryLabelColor;
    if (self.accessDenied) {
        label.text = @"无法读取其他应用的数据。\n请用 TrollStore 安装本应用。";
    } else if (self.searchText.length > 0) {
        label.text = @"没有匹配的应用";
    } else {
        label.text = @"没有找到用户应用";
    }
    self.tableView.backgroundView = label;
}

- (void)showHelp {
    NSString *message = @"备份每个应用的 Documents、Library 和 App Group，默认跳过缓存。文件保存在「文件」App 的「应用备份 / Backups」。\n\n不包含钥匙串，所以有些应用恢复后仍要登录。恢复时按 Bundle ID 写回当前容器，应用重装后也能用。\n\n必须用 TrollStore 安装。普通签名会被沙盒挡住。";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"应用备份" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    self.searchText = searchController.searchBar.text ?: @"";
    [self.tableView reloadData];
    [self updateEmptyState];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (!self.loaded) {
        return 1;
    }
    return [self visibleApps].count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"app"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"app"];
    }
    UIListContentConfiguration *config = [UIListContentConfiguration subtitleCellConfiguration];
    config.imageProperties.maximumSize = CGSizeMake(44, 44);
    config.imageProperties.reservedLayoutSize = CGSizeMake(44, 44);
    config.imageProperties.cornerRadius = 10;
    cell.accessoryView = nil;
    if (!self.loaded) {
        config.text = @"正在读取已安装的应用";
        config.secondaryText = nil;
        config.image = nil;
        cell.contentConfiguration = config;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    ABAppInfo *app = [self visibleApps][indexPath.row];
    config.text = app.displayName;
    NSString *version = app.shortVersion.length ? app.shortVersion : app.bundleVersion;
    config.secondaryText = version.length ? [NSString stringWithFormat:@"%@ · %@", app.bundleIdentifier, version] : app.bundleIdentifier;
    UIImage *icon = ABAppIcon(app.bundleIdentifier);
    if (icon) {
        config.image = icon;
        config.imageProperties.tintColor = nil;
    } else {
        config.image = [UIImage systemImageNamed:@"app.fill"];
        config.imageProperties.tintColor = UIColor.secondaryLabelColor;
    }
    cell.contentConfiguration = config;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (!self.loaded) {
        return nil;
    }
    return @"点进应用后可以备份或恢复。备份文件在「文件」App 的「应用备份 / Backups」。";
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (!self.loaded || indexPath.row >= (NSInteger)[self visibleApps].count) {
        return;
    }
    ABAppInfo *app = [self visibleApps][indexPath.row];
    ABAppDetailViewController *detail = [[ABAppDetailViewController alloc] initWithApp:app];
    [self.navigationController pushViewController:detail animated:YES];
}

@end
