#import "ABAppListViewController.h"
#import "ABAppDetailViewController.h"
#import "ABAppLibrary.h"
#import "ABBackupEngine.h"
#import "ABIcon.h"

@interface ABAppListViewController () <UISearchResultsUpdating>
@property (nonatomic, copy) NSArray<ABAppInfo *> *apps;
@property (nonatomic, copy) NSString *searchText;
@property (nonatomic) BOOL accessDenied;
@property (nonatomic) BOOL loaded;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) dispatch_queue_t loadQueue;
@property (nonatomic, strong) dispatch_queue_t sizeQueue;
@property (nonatomic, strong) NSMutableSet<NSString *> *sizing;
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
    self.sizing = [NSMutableSet set];
    self.loadQueue = dispatch_queue_create("com.local.appbackup.list", DISPATCH_QUEUE_SERIAL);
    self.sizeQueue = dispatch_queue_create("com.local.appbackup.size", DISPATCH_QUEUE_SERIAL);
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
    [self reloadApps];
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

- (NSString *)sizeTextForApp:(ABAppInfo *)app {
    ABBackupOptions *options = [ABBackupOptions currentOptions];
    BOOL sameOptions = app.measuredExcludesCaches == options.excludesCaches && app.measuredIncludesGroups == options.includesAppGroups;
    if ((app.sizeKnown || app.sizeFailed) && sameOptions) {
        return app.sizeKnown ? ABFormatBytes(app.dataBytes) : @"—";
    }
    [self measureApp:app];
    return @"…";
}

- (void)measureApp:(ABAppInfo *)app {
    if ([self.sizing containsObject:app.bundleIdentifier]) {
        return;
    }
    [self.sizing addObject:app.bundleIdentifier];
    ABBackupOptions *options = [ABBackupOptions currentOptions];
    dispatch_async(self.sizeQueue, ^{
        uint64_t bytes = 0;
        NSError *error = nil;
        BOOL ok = [[ABBackupEngine sharedEngine] calculateSizeForApp:app options:options bytes:&bytes error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.sizing removeObject:app.bundleIdentifier];
            app.sizeKnown = ok;
            app.sizeFailed = !ok;
            app.dataBytes = bytes;
            app.measuredExcludesCaches = options.excludesCaches;
            app.measuredIncludesGroups = options.includesAppGroups;
            [self reloadRowForBundleID:app.bundleIdentifier];
        });
    });
}

- (void)reloadRowForBundleID:(NSString *)bundleID {
    NSArray<ABAppInfo *> *visible = [self visibleApps];
    for (NSInteger index = 0; index < (NSInteger)visible.count; index++) {
        if ([visible[index].bundleIdentifier isEqualToString:bundleID]) {
            NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
            if ([self.tableView.indexPathsForVisibleRows containsObject:indexPath]) {
                [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
            }
            return;
        }
    }
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
    config.imageProperties.maximumSize = CGSizeMake(40, 40);
    config.imageProperties.reservedLayoutSize = CGSizeMake(40, 40);
    config.imageProperties.cornerRadius = 8;
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
    NSString *detail = version.length ? [NSString stringWithFormat:@"%@ · %@", app.bundleIdentifier, version] : app.bundleIdentifier;
    config.secondaryText = [NSString stringWithFormat:@"%@ · %@", detail, [self sizeTextForApp:app]];
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
