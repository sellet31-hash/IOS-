#import "ABBackupListViewController.h"
#import "ABAppLibrary.h"
#import "ABBackupActions.h"
#import "ABBackupEngine.h"
#import "ABIcon.h"
#import <QuartzCore/QuartzCore.h>

@interface ABBackupListViewController () <UISearchResultsUpdating>
@property (nonatomic, copy) NSArray<ABBackupInfo *> *backups;
@property (nonatomic, copy) NSString *searchText;
@property (nonatomic) BOOL loaded;
@property (nonatomic) NSUInteger unreadableCount;
@property (nonatomic, strong) UISearchController *searchController;
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
        });
    });
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
        cell.textLabel.text = @"正在读取备份";
        cell.detailTextLabel.text = nil;
        cell.imageView.image = nil;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    ABBackupInfo *backup = [self visibleBackups][indexPath.row];
    cell.textLabel.text = backup.preferredTitle;
    cell.detailTextLabel.numberOfLines = 2;
    cell.detailTextLabel.text = backup.summaryText;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    UIImage *icon = ABAppIcon(backup.bundleIdentifier);
    cell.imageView.image = icon ?: [UIImage systemImageNamed:@"archivebox"];
    cell.imageView.layer.cornerRadius = 8;
    cell.imageView.layer.cornerCurve = kCACornerCurveContinuous;
    cell.imageView.clipsToBounds = YES;
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
    return @"点一份备份可以修改名称，用来标记用途。恢复成功后会自动记下上次使用时间。";
}

- (void)presentActionsForBackup:(ABBackupInfo *)backup sourceView:(UIView *)sourceView {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:backup.preferredTitle message:backup.summaryText preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"恢复" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
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
