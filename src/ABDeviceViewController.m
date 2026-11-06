#import "ABDeviceViewController.h"
#import "ABDeviceCatalog.h"
#import "ABDeviceStore.h"
#import "ABIcon.h"

@interface ABDeviceViewController ()
@property (nonatomic, copy) NSArray<NSString *> *generations;
@property (nonatomic, strong) ABDeviceModel *selected;
@property (nonatomic) BOOL enabled;
@property (nonatomic, strong) UIView *header;
@property (nonatomic, strong) UILabel *headerTitle;
@property (nonatomic, strong) UILabel *headerDetail;
@property (nonatomic, strong) UILabel *headerMeta;
@end

@implementation ABDeviceViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"机型";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.generations = [ABDeviceCatalog generations];
    [self reloadSelection];
    [self buildHeader];
}

- (void)reloadSelection {
    self.enabled = [ABDeviceStore isEnabled];
    self.selected = [ABDeviceStore selectedModel];
    [self refreshHeader];
    [self.tableView reloadData];
}

- (void)buildHeader {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 360, 148)];
    UIView *card = [UIView new];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = [ABAccentColor() colorWithAlphaComponent:0.12];
    card.layer.cornerRadius = 18;
    card.layer.cornerCurve = kCACornerCurveContinuous;

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"iphone.gen3"]];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.tintColor = ABAccentColor();
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:28 weight:UIImageSymbolWeightSemibold];

    UILabel *title = [UILabel new];
    UILabel *detail = [UILabel new];
    UILabel *meta = [UILabel new];
    for (UILabel *label in @[title, detail, meta]) {
        label.translatesAutoresizingMaskIntoConstraints = NO;
    }
    title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle2];
    title.adjustsFontForContentSizeCategory = YES;
    detail.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    detail.textColor = UIColor.secondaryLabelColor;
    meta.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    meta.textColor = ABAccentColor();
    self.headerTitle = title;
    self.headerDetail = detail;
    self.headerMeta = meta;

    [card addSubview:icon];
    [card addSubview:title];
    [card addSubview:detail];
    [card addSubview:meta];
    [header addSubview:card];
    [NSLayoutConstraint activateConstraints:@[
        [card.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20],
        [card.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20],
        [card.topAnchor constraintEqualToAnchor:header.topAnchor constant:8],
        [card.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-12],
        [icon.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [icon.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:36],
        [icon.heightAnchor constraintEqualToConstant:36],
        [title.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:14],
        [title.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [title.topAnchor constraintEqualToAnchor:card.topAnchor constant:18],
        [detail.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [detail.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
        [detail.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:2],
        [meta.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [meta.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
        [meta.topAnchor constraintEqualToAnchor:detail.bottomAnchor constant:6],
        [meta.bottomAnchor constraintLessThanOrEqualToAnchor:card.bottomAnchor constant:-16],
    ]];
    self.header = header;
    self.tableView.tableHeaderView = header;
    [self refreshHeader];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIView *header = self.tableView.tableHeaderView;
    if (!header) {
        return;
    }
    CGSize size = [header systemLayoutSizeFittingSize:CGSizeMake(self.tableView.bounds.size.width, 0) withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    if (fabs(header.frame.size.height - MAX(size.height, 148)) > 1) {
        CGRect frame = header.frame;
        frame.size.width = self.tableView.bounds.size.width;
        frame.size.height = MAX(size.height, 148);
        header.frame = frame;
        self.tableView.tableHeaderView = header;
    }
}

- (void)refreshHeader {
    ABDeviceModel *model = self.selected;
    self.headerTitle.text = self.enabled ? (model.name ?: @"未选择") : @"伪装已关闭";
    self.headerDetail.text = model ? [NSString stringWithFormat:@"%@ · %@", model.identifier, model.board] : @"";
    self.headerMeta.text = self.enabled ? @"重新打开目标 App 后生效" : @"目标 App 会看到这台手机的真实机型";
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2 + (NSInteger)self.generations.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section < 2) {
        return 1;
    }
    return [ABDeviceCatalog modelsInGeneration:self.generations[section - 2]].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) {
        return @"开关";
    }
    if (section == 1) {
        return @"安装身份";
    }
    return self.generations[section - 2];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return @"机型设置写入 DeviceSpoof。系统版本仍使用这台手机的真实版本，避免目标 App 打开后退出。";
    }
    if (section == 1) {
        return @"下一次打开目标 App 时更换 IDFV、安装 UUID 和 32 位设备指纹。已经登录的账号不会因此变成新账号。";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"switch"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"switch"];
            UISwitch *toggle = [UISwitch new];
            [toggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = toggle;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        }
        cell.textLabel.text = @"启用机型伪装";
        [(UISwitch *)cell.accessoryView setOn:self.enabled animated:NO];
        return cell;
    }
    if (indexPath.section == 1) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"fresh"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"fresh"];
        }
        UIListContentConfiguration *config = [UIListContentConfiguration subtitleCellConfiguration];
        config.text = @"换一套安装身份";
        config.secondaryText = @"只换标识，不改当前选择的机型";
        config.image = [UIImage systemImageNamed:@"arrow.triangle.2.circlepath"];
        config.imageProperties.tintColor = ABAccentColor();
        cell.contentConfiguration = config;
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }
    ABDeviceModel *model = [ABDeviceCatalog modelsInGeneration:self.generations[indexPath.section - 2]][indexPath.row];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"model"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"model"];
    }
    UIListContentConfiguration *config = [UIListContentConfiguration subtitleCellConfiguration];
    config.text = model.name;
    config.secondaryText = [NSString stringWithFormat:@"%@ · %.0f × %.0f", model.identifier, model.width, model.height];
    config.secondaryTextProperties.color = UIColor.secondaryLabelColor;
    cell.contentConfiguration = config;
    BOOL chosen = self.enabled && [model.identifier isEqualToString:self.selected.identifier];
    cell.accessoryType = chosen ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.tintColor = ABAccentColor();
    return cell;
}

- (void)toggleChanged:(UISwitch *)toggle {
    NSError *error = nil;
    if (![ABDeviceStore setEnabled:toggle.isOn error:&error]) {
        [self reloadSelection];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"没有保存" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    [self reloadSelection];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1) {
        NSError *error = nil;
        BOOL saved = [ABDeviceStore requestFreshIdentity:&error];
        NSString *message = saved ? @"下次打开目标 App 时会使用新的安装身份。" : (error.localizedDescription ?: @"没有写入配置。请确认已安装 Dopamine，并且 /var/jb 可用。");
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:saved ? @"已安排更换" : @"没有保存" message:message preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    if (indexPath.section < 2) {
        return;
    }
    ABDeviceModel *model = [ABDeviceCatalog modelsInGeneration:self.generations[indexPath.section - 2]][indexPath.row];
    NSError *error = nil;
    if (![ABDeviceStore selectModel:model error:&error]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"没有保存" message:error.localizedDescription ?: @"无法写入 /var/jb/Library/Preferences。" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    [ABDeviceStore setEnabled:YES];
    [self reloadSelection];
}

@end
