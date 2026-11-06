#import "ABBackupListViewController.h"
#import "ABAppLibrary.h"
#import "ABBackupActions.h"
#import "ABBackupEngine.h"
#import "ABChrome.h"
#import "ABIcon.h"
#import <QuartzCore/QuartzCore.h>

@interface ABBackupListViewController () <UISearchResultsUpdating>
@property (nonatomic, copy) NSArray<ABBackupInfo *> *backups;
@property (nonatomic, copy) NSString *searchText;
@property (nonatomic) BOOL loaded;
@property (nonatomic) NSUInteger unreadableCount;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, copy) NSString *pinnedPath;
@end

@implementation ABBackupListViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"备份";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.searchText = @"";
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"搜索备份";
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
    self.refreshControl = [UIRefreshControl new];
    [self.refreshControl addTarget:self action:@selector(reloadBackups) forControlEvents:UIControlEventValueChanged];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadBackups];
}

- (void)reloadBackups {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSUInteger unreadable = 0;
        NSError *error = nil;
        NSArray<ABBackupInfo *> *backups = [ABBackupEngine allBackupsWithUnreadableCount:&unreadable error:&error] ?: @[];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.backups = backups;
            self.unreadableCount = unreadable;
            self.loaded = YES;
            [self.refreshControl endRefreshing];
            [self.tableView reloadData];
            [self updateEmptyState];
            [self pinCurrentBackup];
        });
    });
}

- (NSSet<NSString *> *)currentPathsIn:(NSArray<ABBackupInfo *> *)backups {
    NSMutableDictionary<NSString *, ABBackupInfo *> *latest = [NSMutableDictionary dictionary];
    for (ABBackupInfo *backup in backups) {
        if (!backup.lastUsedAt || backup.bundleIdentifier.length == 0 || backup.fileURL.path.length == 0) {
            continue;
        }
        ABBackupInfo *existing = latest[backup.bundleIdentifier];
        if (!existing || [backup.lastUsedAt compare:existing.lastUsedAt] == NSOrderedDescending) {
            latest[backup.bundleIdentifier] = backup;
        }
    }
    NSMutableSet<NSString *> *paths = [NSMutableSet set];
    for (ABBackupInfo *backup in latest.allValues) {
        [paths addObject:backup.fileURL.path];
    }
    return paths;
}

- (NSString *)detailForBackup:(ABBackupInfo *)backup current:(BOOL)current {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    [parts addObject:current ? @"当前使用" : (backup.lastUsedAt ? [NSString stringWithFormat:@"上次使用 %@", ABFormatDate(backup.lastUsedAt)] : @"尚未使用")];
    NSString *created = ABFormatDate(backup.createdAt);
    if (created.length > 0) {
        [parts addObject:[NSString stringWithFormat:@"备份于 %@", created]];
    }
    if (backup.shortVersion.length > 0) {
        [parts addObject:backup.shortVersion];
    }
    if (backup.fileSize > 0) {
        [parts addObject:ABFormatBytes(backup.fileSize)];
    }
    return [parts componentsJoinedByString:@" · "];
}

- (void)pinCurrentBackup {
    if (self.pinnedPath.length == 0) {
        return;
    }
    NSArray<ABBackupInfo *> *visible = [self visibleBackups];
    for (NSUInteger index = 0; index < visible.count; index++) {
        if ([visible[index].fileURL.path isEqualToString:self.pinnedPath]) {
            NSIndexPath *path = [NSIndexPath indexPathForRow:(NSInteger)index inSection:0];
            [self.tableView scrollToRowAtIndexPath:path atScrollPosition:UITableViewScrollPositionMiddle animated:YES];
            [self.tableView selectRowAtIndexPath:path animated:NO scrollPosition:UITableViewScrollPositionNone];
            return;
        }
    }
}

- (NSArray<ABBackupInfo *> *)visibleBackups {
    if (self.searchText.length == 0) {
        return self.backups ?: @[];
    }
    NSString *query = self.searchText.lowercaseString;
    NSMutableArray<ABBackupInfo *> *matches = [NSMutableArray array];
    for (ABBackupInfo *backup in self.backups) {
        if ([backup.preferredTitle.lowercaseString containsString:query] || [backup.displayName.lowercaseString containsString:query] || [backup.bundleIdentifier.lowercaseString containsString:query]) {
            [matches addObject:backup];
        }
    }
    return matches;
}

- (void)updateEmptyState {
    if (!self.loaded || [self visibleBackups].count > 0) {
        self.tableView.backgroundView = nil;
        return;
    }
    UILabel *label = [[UILabel alloc] initWithFrame:self.tableView.bounds];
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    label.textColor = UIColor.secondaryLabelColor;
    label.text = self.searchText.length > 0 ? @"没有匹配的备份" : @"还没有备份。\n到「应用」里选择一个应用。";
    self.tableView.backgroundView = label;
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
    return [self visibleBackups].count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"backup"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"backup"];
    }
    if (!self.loaded) {
        UIListContentConfiguration *config = [UIListContentConfiguration cellConfiguration];
        config.text = @"正在读取备份";
        config.textProperties.color = UIColor.secondaryLabelColor;
        cell.contentConfiguration = config;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    ABBackupInfo *backup = [self visibleBackups][indexPath.row];
    BOOL current = [[self currentPathsIn:self.backups] containsObject:backup.fileURL.path];
    UIListContentConfiguration *config = [UIListContentConfiguration subtitleCellConfiguration];
    config.text = backup.preferredTitle;
    config.secondaryText = [self detailForBackup:backup current:current];
    config.secondaryTextProperties.color = current ? ABAccentColor() : UIColor.secondaryLabelColor;
    config.secondaryTextProperties.numberOfLines = 2;
    UIImage *icon = ABAppIcon(backup.bundleIdentifier);
    config.image = icon ?: [UIImage systemImageNamed:current ? @"checkmark.circle.fill" : @"archivebox"];
    config.imageProperties.tintColor = icon ? nil : (current ? ABAccentColor() : UIColor.secondaryLabelColor);
    config.imageProperties.maximumSize = CGSizeMake(28, 28);
    config.imageProperties.cornerRadius = 6;
    cell.contentConfiguration = config;
    cell.backgroundConfiguration = current ? ABHighlightedCellBackground() : [UIBackgroundConfiguration listGroupedCellConfiguration];
    cell.accessoryType = current ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.tintColor = ABAccentColor();
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (!self.loaded) {
        return nil;
    }
    if (self.unreadableCount > 0) {
        return [NSString stringWithFormat:@"有 %lu 个文件无法读取。可用的备份在「文件」App 的「应用备份 / Backups」。", (unsigned long)self.unreadableCount];
    }
    return @"带对勾的是该应用当前使用的备份。点一份备份可以恢复、改名或分享。";
}

- (void)presentActionsForBackup:(ABBackupInfo *)backup sourceView:(UIView *)sourceView {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:backup.preferredTitle message:backup.summaryText preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"恢复" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        self.pinnedPath = backup.fileURL.path;
        [ABBackupActions confirmRestore:backup fromViewController:self sourceView:sourceView completion:^{
            [self reloadBackups];
        }];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"修改名称" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [ABBackupActions renameBackup:backup fromViewController:self completion:^{
            [self reloadBackups];
        }];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"分享" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [ABBackupActions shareBackup:backup fromViewController:self sourceView:sourceView];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        [ABBackupActions confirmDelete:backup fromViewController:self completion:^{
            [self reloadBackups];
        }];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    UIPopoverPresentationController *popover = sheet.popoverPresentationController;
    if (popover) {
        popover.sourceView = sourceView ?: self.view;
        popover.sourceRect = sourceView ? sourceView.bounds : CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (!self.loaded || indexPath.row >= (NSInteger)[self visibleBackups].count) {
        return;
    }
    [self presentActionsForBackup:[self visibleBackups][indexPath.row] sourceView:[tableView cellForRowAtIndexPath:indexPath]];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (!self.loaded || indexPath.row >= (NSInteger)[self visibleBackups].count) {
        return nil;
    }
    ABBackupInfo *backup = [self visibleBackups][indexPath.row];
    UIContextualAction *restore = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"恢复" handler:^(__unused UIContextualAction *action, UIView *sourceView, void (^done)(BOOL)) {
        self.pinnedPath = backup.fileURL.path;
        [ABBackupActions confirmRestore:backup fromViewController:self sourceView:sourceView completion:^{
            [self reloadBackups];
        }];
        done(YES);
    }];
    restore.backgroundColor = ABAccentColor();
    UIContextualAction *remove = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"删除" handler:^(__unused UIContextualAction *action, __unused UIView *sourceView, void (^done)(BOOL)) {
        [ABBackupActions confirmDelete:backup fromViewController:self completion:^{
            [self reloadBackups];
        }];
        done(YES);
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[remove, restore]];
}

@end
