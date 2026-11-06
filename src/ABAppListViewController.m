#import "ABAppListViewController.h"
#import "ABAppDetailViewController.h"
#import "ABAppLibrary.h"
#import "ABIcon.h"

@interface ABAppListViewController () <UISearchResultsUpdating>
@property (nonatomic, copy) NSArray<ABAppInfo *> *apps;
@property (nonatomic, copy) NSString *searchText;
@property (nonatomic) BOOL accessDenied;
@property (nonatomic) BOOL loaded;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) dispatch_queue_t loadQueue;
@end

@implementation ABAppListViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStylePlain];
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
    self.searchController.searchBar.placeholder = @"搜索";
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
    self.refreshControl = [UIRefreshControl new];
    [self.refreshControl addTarget:self action:@selector(reloadApps) forControlEvents:UIControlEventValueChanged];
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.tableView.rowHeight = 64;
    self.tableView.separatorInset = UIEdgeInsetsMake(0, 76, 0, 0);
    self.tableView.backgroundColor = UIColor.systemBackgroundColor;
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
            [self measureSizes:apps];
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

static uint64_t ABDirectorySize(NSString *path) {
    if (path.length == 0) {
        return 0;
    }
    NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtURL:[NSURL fileURLWithPath:path]
                                                             includingPropertiesForKeys:@[NSURLFileSizeKey]
                                                                                options:0
                                                                           errorHandler:nil];
    uint64_t total = 0;
    for (NSURL *url in enumerator) {
        NSNumber *size = nil;
        [url getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
        total += size.unsignedLongLongValue;
    }
    return total;
}

- (void)measureSizes:(NSArray<ABAppInfo *> *)apps {
    dispatch_async(self.loadQueue, ^{
        NSUInteger index = 0;
        for (ABAppInfo *app in apps) {
            if (!app.sizeKnown) {
                app.dataBytes = ABDirectorySize(app.dataContainerURL.path);
                app.sizeKnown = YES;
            }
            index++;
            if (index % 6 == 0 || index == apps.count) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (self.apps == apps) {
                        [self.tableView reloadData];
                    }
                });
            }
        }
    });
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"app"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"app"];
    }
    UIListContentConfiguration *config = [UIListContentConfiguration valueCellConfiguration];
    config.imageProperties.maximumSize = CGSizeMake(40, 40);
    config.imageProperties.reservedLayoutSize = CGSizeMake(40, 40);
    config.imageProperties.cornerRadius = 9;
    config.textProperties.font = [UIFont systemFontOfSize:17];
    config.secondaryTextProperties.font = [UIFont systemFontOfSize:15];
    config.secondaryTextProperties.color = UIColor.secondaryLabelColor;
    if (!self.loaded) {
        config.text = @"正在读取";
        config.secondaryText = nil;
        config.image = nil;
        cell.contentConfiguration = config;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    ABAppInfo *app = [self visibleApps][indexPath.row];
    config.text = app.displayName;
    config.secondaryText = app.sizeKnown ? ABFormatBytes(app.dataBytes) : @"";
    UIImage *icon = ABAppIconForBundle(app.bundleIdentifier, app.bundleURL);
    config.image = icon ?: [UIImage systemImageNamed:@"app.fill"];
    config.imageProperties.tintColor = icon ? nil : UIColor.tertiaryLabelColor;
    cell.contentConfiguration = config;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.backgroundColor = UIColor.systemBackgroundColor;
    return cell;
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
