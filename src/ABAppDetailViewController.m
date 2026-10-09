#import "ABAppDetailViewController.h"
#import "ABAppLibrary.h"
#import "ABBackupActions.h"
#import "ABBackupEngine.h"
#import "ABIcon.h"
#import <QuartzCore/QuartzCore.h>

@interface ABAppDetailViewController ()
@property (nonatomic, strong) ABAppInfo *app;
@property (nonatomic, copy) NSArray<ABBackupInfo *> *backups;
@property (nonatomic) BOOL backupsLoaded;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *versionLabel;
@property (nonatomic, strong) UILabel *bundleLabel;
@property (nonatomic, strong) UILabel *pathLabel;
@property (nonatomic, strong) UIButton *copyButton;
@end

@implementation ABAppDetailViewController

- (instancetype)initWithApp:(ABAppInfo *)app {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _app = app;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.app.displayName;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    [self buildHeader];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshLocationAndBackups];
}

- (void)buildHeader {
    UIView *header = [UIView new];
    UIImageView *icon = [UIImageView new];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.layer.cornerRadius = 14;
    icon.layer.cornerCurve = kCACornerCurveContinuous;
    icon.clipsToBounds = YES;
    icon.contentMode = UIViewContentModeScaleAspectFill;
    icon.backgroundColor = UIColor.secondarySystemFillColor;
    [header addSubview:icon];
    self.iconView = icon;

    UILabel *name = [UILabel new];
    name.translatesAutoresizingMaskIntoConstraints = NO;
    name.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    name.numberOfLines = 2;
    name.textColor = UIColor.labelColor;
    [header addSubview:name];
    self.nameLabel = name;

    UILabel *version = [UILabel new];
    version.translatesAutoresizingMaskIntoConstraints = NO;
    version.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    version.textColor = UIColor.secondaryLabelColor;
    [header addSubview:version];
    self.versionLabel = version;

    UILabel *bundle = [UILabel new];
    bundle.translatesAutoresizingMaskIntoConstraints = NO;
    bundle.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    bundle.textColor = UIColor.tertiaryLabelColor;
    bundle.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [header addSubview:bundle];
    self.bundleLabel = bundle;

    UILabel *path = [UILabel new];
    path.translatesAutoresizingMaskIntoConstraints = NO;
    path.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    path.textColor = UIColor.secondaryLabelColor;
    path.numberOfLines = 0;
    [header addSubview:path];
    self.pathLabel = path;

    UIButton *copy = [UIButton buttonWithType:UIButtonTypeSystem];
    copy.translatesAutoresizingMaskIntoConstraints = NO;
    [copy setTitle:@"复制数据路径" forState:UIControlStateNormal];
    copy.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    [copy addTarget:self action:@selector(copyPath) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:copy];
    self.copyButton = copy;

    [NSLayoutConstraint activateConstraints:@[
        [icon.topAnchor constraintEqualToAnchor:header.topAnchor constant:8],
        [icon.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20],
        [icon.widthAnchor constraintEqualToConstant:64],
        [icon.heightAnchor constraintEqualToConstant:64],
        [name.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:14],
        [name.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20],
        [name.topAnchor constraintEqualToAnchor:icon.topAnchor constant:2],
        [version.leadingAnchor constraintEqualToAnchor:name.leadingAnchor],
        [version.trailingAnchor constraintEqualToAnchor:name.trailingAnchor],
        [version.topAnchor constraintEqualToAnchor:name.bottomAnchor constant:4],
        [bundle.leadingAnchor constraintEqualToAnchor:name.leadingAnchor],
        [bundle.trailingAnchor constraintEqualToAnchor:name.trailingAnchor],
        [bundle.topAnchor constraintEqualToAnchor:version.bottomAnchor constant:2],
        [path.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20],
        [path.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20],
        [path.topAnchor constraintGreaterThanOrEqualToAnchor:icon.bottomAnchor constant:16],
        [path.topAnchor constraintGreaterThanOrEqualToAnchor:bundle.bottomAnchor constant:16],
        [copy.leadingAnchor constraintEqualToAnchor:path.leadingAnchor],
        [copy.topAnchor constraintEqualToAnchor:path.bottomAnchor constant:4],
        [copy.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-8]
    ]];
    self.tableView.tableHeaderView = header;
    [self fillHeader];
}

- (void)fillHeader {
    self.nameLabel.text = self.app.displayName;
    NSString *version = self.app.shortVersion.length ? self.app.shortVersion : @"未知版本";
    self.versionLabel.text = self.app.bundleVersion.length ? [NSString stringWithFormat:@"版本 %@ (%@)", version, self.app.bundleVersion] : [NSString stringWithFormat:@"版本 %@", version];
    self.bundleLabel.text = self.app.bundleIdentifier;
    self.pathLabel.text = self.app.dataContainerURL.path.length ? self.app.dataContainerURL.path : @"还没有数据目录";
    self.copyButton.hidden = self.app.dataContainerURL.path.length == 0;
    UIImage *icon = ABAppIcon(self.app.bundleIdentifier);
    self.iconView.image = icon ?: [UIImage systemImageNamed:@"app.fill"];
    self.iconView.tintColor = icon ? nil : UIColor.secondaryLabelColor;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIView *header = self.tableView.tableHeaderView;
    if (!header) {
        return;
    }
    CGFloat width = self.tableView.bounds.size.width;
    CGSize size = [header systemLayoutSizeFittingSize:CGSizeMake(width, 0) withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    if (fabs(header.frame.size.width - width) > 0.5 || fabs(header.frame.size.height - size.height) > 0.5) {
        header.frame = CGRectMake(0, 0, width, size.height);
        self.tableView.tableHeaderView = header;
    }
}

- (void)copyPath {
    if (self.app.dataContainerURL.path.length == 0) {
        return;
    }
    UIPasteboard.generalPasteboard.string = self.app.dataContainerURL.path;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"已复制" message:self.app.dataContainerURL.path preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)refreshLocationAndBackups {
    NSString *bundleID = self.app.bundleIdentifier;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        ABContainerLocation *location = [[ABAppLibrary sharedLibrary] locationForBundleIdentifier:bundleID];
        NSError *error = nil;
        NSArray<ABBackupInfo *> *all = [ABBackupEngine allBackupsWithUnreadableCount:NULL error:&error];
        NSMutableArray<ABBackupInfo *> *mine = [NSMutableArray array];
        for (ABBackupInfo *backup in all) {
            if ([backup.bundleIdentifier isEqualToString:bundleID]) {
                [mine addObject:backup];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (location.dataContainerURL) {
                self.app.dataContainerURL = location.dataContainerURL;
            }
            if (location.bundleURL) {
                self.app.bundleURL = location.bundleURL;
            }
            if (location.displayName.length > 0) {
                self.app.displayName = location.displayName;
                self.title = location.displayName;
            }
            self.backups = mine;
            self.backupsLoaded = YES;
            [self fillHeader];
            [self.tableView reloadData];
        });
    });
}

- (BOOL)hasContainer {
    return self.app.dataContainerURL.path.length > 0;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 2) {
        return MAX((NSInteger)self.backups.count, 1);
    }
    return section == 0 ? 1 : 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 1) {
        return @"选项";
    }
    if (section == 2) {
        return @"历史备份";
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0 && ![self hasContainer]) {
        return @"系统还没有给这个应用创建数据目录。先打开一次该应用。";
    }
    if (section == 1) {
        return @"默认跳过缓存和临时文件。钥匙串不会备份，部分应用恢复后需要重新登录。";
    }
    return nil;
}

- (UITableViewCell *)switchCellWithTitle:(NSString *)title on:(BOOL)on action:(SEL)action {
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:title];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:title];
        UISwitch *toggle = [UISwitch new];
        [toggle addTarget:self action:action forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    cell.textLabel.text = title;
    UISwitch *toggle = (UISwitch *)cell.accessoryView;
    toggle.on = on;
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"backup"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"backup"];
        }
        BOOL enabled = [self hasContainer];
        cell.textLabel.text = @"开始备份";
        cell.textLabel.textColor = enabled ? ABAccentColor() : UIColor.tertiaryLabelColor;
        cell.imageView.image = [UIImage systemImageNamed:@"arrow.down.doc"];
        cell.imageView.tintColor = enabled ? ABAccentColor() : UIColor.tertiaryLabelColor;
        cell.selectionStyle = enabled ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
        return cell;
    }
    if (indexPath.section == 1) {
        ABBackupOptions *options = [ABBackupOptions currentOptions];
        if (indexPath.row == 0) {
            return [self switchCellWithTitle:@"排除缓存" on:options.excludesCaches action:@selector(cachesChanged:)];
        }
        return [self switchCellWithTitle:@"包含 App Group" on:options.includesAppGroups action:@selector(groupsChanged:)];
    }
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"history"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"history"];
    }
    if (!self.backupsLoaded) {
        cell.textLabel.text = @"正在读取备份";
        cell.detailTextLabel.text = nil;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }
    if (self.backups.count == 0) {
        cell.textLabel.text = @"还没有这个应用的备份";
        cell.detailTextLabel.text = nil;
        cell.textLabel.textColor = UIColor.secondaryLabelColor;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }
    ABBackupInfo *backup = self.backups[indexPath.row];
    cell.textLabel.textColor = UIColor.labelColor;
    cell.textLabel.text = ABFormatDate(backup.createdAt);
    NSString *version = backup.shortVersion.length ? backup.shortVersion : @"";
    cell.detailTextLabel.text = version.length ? [NSString stringWithFormat:@"%@ · %@", version, ABFormatBytes(backup.fileSize)] : ABFormatBytes(backup.fileSize);
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)cachesChanged:(UISwitch *)sender {
    [[NSUserDefaults standardUserDefaults] setBool:sender.on forKey:ABExcludeCachesKey];
}

- (void)groupsChanged:(UISwitch *)sender {
    [[NSUserDefaults standardUserDefaults] setBool:sender.on forKey:ABIncludeGroupsKey];
}

- (BOOL)isHistoryRow:(NSIndexPath *)indexPath {
    return indexPath.section == 2 && self.backupsLoaded && indexPath.row < (NSInteger)self.backups.count;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) {
        if (![self hasContainer]) {
            return;
        }
        [ABBackupActions backupApp:self.app fromViewController:self completion:^{
            [self refreshLocationAndBackups];
        }];
        return;
    }
    if (![self isHistoryRow:indexPath]) {
        return;
    }
    ABBackupInfo *backup = self.backups[indexPath.row];
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:ABFormatDate(backup.createdAt) message:ABFormatBytes(backup.fileSize) preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"恢复" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        [ABBackupActions confirmRestore:backup fromViewController:self sourceView:cell completion:^{
            [self refreshLocationAndBackups];
        }];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"分享" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [ABBackupActions shareBackup:backup fromViewController:self sourceView:cell];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        [ABBackupActions confirmDelete:backup fromViewController:self completion:^{
            [self refreshLocationAndBackups];
        }];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    UIPopoverPresentationController *popover = sheet.popoverPresentationController;
    if (popover) {
        popover.sourceView = cell ?: self.view;
        popover.sourceRect = cell ? cell.bounds : CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (![self isHistoryRow:indexPath]) {
        return nil;
    }
    ABBackupInfo *backup = self.backups[indexPath.row];
    UIContextualAction *restore = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"恢复" handler:^(__unused UIContextualAction *action, __unused UIView *sourceView, void (^done)(BOOL)) {
        [ABBackupActions confirmRestore:backup fromViewController:self sourceView:sourceView completion:^{
            [self refreshLocationAndBackups];
        }];
        done(YES);
    }];
    restore.backgroundColor = ABAccentColor();
    UIContextualAction *remove = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"删除" handler:^(__unused UIContextualAction *action, __unused UIView *sourceView, void (^done)(BOOL)) {
        [ABBackupActions confirmDelete:backup fromViewController:self completion:^{
            [self refreshLocationAndBackups];
        }];
        done(YES);
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[remove, restore]];
}

@end
