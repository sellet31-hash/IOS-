#import "ABProgressOverlay.h"
#import "ABIcon.h"
#import "ABModels.h"
#import <QuartzCore/QuartzCore.h>

@interface ABProgressOverlay ()
@property (nonatomic, strong) UIView *card;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *messageLabel;
@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, strong) UILabel *bytesLabel;
@property (nonatomic, strong) UIButton *cancelButton;
@property (nonatomic, strong) NSLayoutConstraint *cardWidth;
@property (nonatomic, copy) void (^cancelHandler)(void);
@end

@implementation ABProgressOverlay

+ (ABProgressOverlay *)showInView:(UIView *)view title:(NSString *)title cancelHandler:(void (^)(void))cancelHandler {
    ABProgressOverlay *overlay = [[ABProgressOverlay alloc] initWithFrame:view.bounds];
    overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    overlay.titleLabel.text = title;
    overlay.cancelHandler = cancelHandler;
    [view addSubview:overlay];
    return overlay;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.42];
        UIView *card = [UIView new];
        card.translatesAutoresizingMaskIntoConstraints = NO;
        card.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
        card.layer.cornerRadius = 18;
        card.layer.cornerCurve = kCACornerCurveContinuous;
        card.layer.shadowColor = UIColor.blackColor.CGColor;
        card.layer.shadowOpacity = 0.18;
        card.layer.shadowRadius = 24;
        card.layer.shadowOffset = CGSizeMake(0, 10);
        [self addSubview:card];
        self.card = card;

        UILabel *title = [UILabel new];
        title.translatesAutoresizingMaskIntoConstraints = NO;
        title.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
        title.textColor = UIColor.labelColor;
        [card addSubview:title];
        self.titleLabel = title;

        UILabel *message = [UILabel new];
        message.translatesAutoresizingMaskIntoConstraints = NO;
        message.font = [UIFont systemFontOfSize:13];
        message.textColor = UIColor.secondaryLabelColor;
        message.numberOfLines = 2;
        message.lineBreakMode = NSLineBreakByTruncatingMiddle;
        message.text = @"准备中";
        [card addSubview:message];
        self.messageLabel = message;

        UIProgressView *progress = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
        progress.translatesAutoresizingMaskIntoConstraints = NO;
        progress.progressTintColor = ABAccentColor();
        [card addSubview:progress];
        self.progressView = progress;

        UILabel *bytes = [UILabel new];
        bytes.translatesAutoresizingMaskIntoConstraints = NO;
        bytes.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightRegular];
        bytes.textColor = UIColor.tertiaryLabelColor;
        bytes.text = @"正在计算大小";
        [card addSubview:bytes];
        self.bytesLabel = bytes;

        UIButton *cancel = [UIButton buttonWithType:UIButtonTypeSystem];
        cancel.translatesAutoresizingMaskIntoConstraints = NO;
        [cancel setTitle:@"取消" forState:UIControlStateNormal];
        cancel.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
        [cancel addTarget:self action:@selector(cancelTapped) forControlEvents:UIControlEventTouchUpInside];
        [card addSubview:cancel];
        self.cancelButton = cancel;

        self.cardWidth = [card.widthAnchor constraintEqualToConstant:320];
        [NSLayoutConstraint activateConstraints:@[
            [card.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [card.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            self.cardWidth,
            [card.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:24],
            [card.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-24],
            [title.topAnchor constraintEqualToAnchor:card.topAnchor constant:22],
            [title.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20],
            [title.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-20],
            [message.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:8],
            [message.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
            [message.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
            [progress.topAnchor constraintEqualToAnchor:message.bottomAnchor constant:16],
            [progress.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
            [progress.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
            [bytes.topAnchor constraintEqualToAnchor:progress.bottomAnchor constant:8],
            [bytes.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
            [bytes.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
            [cancel.topAnchor constraintEqualToAnchor:bytes.bottomAnchor constant:8],
            [cancel.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
            [cancel.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-12],
            [cancel.heightAnchor constraintEqualToConstant:44]
        ]];
        CGFloat available = CGRectGetWidth(frame) - 48;
        if (available > 0) {
            self.cardWidth.constant = MIN(360, MAX(260, available));
        }
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat available = self.bounds.size.width - 48;
    self.cardWidth.constant = MIN(360, MAX(260, available));
}

- (void)updateMessage:(NSString *)message fraction:(double)fraction bytesDone:(uint64_t)done bytesTotal:(uint64_t)total {
    self.messageLabel.text = message.length ? message : @"正在处理";
    if (total == 0) {
        self.progressView.progress = 0;
        self.bytesLabel.text = @"正在计算大小";
        return;
    }
    float progress = (float)MIN(MAX(fraction, 0), 1);
    [self.progressView setProgress:progress animated:YES];
    self.bytesLabel.text = [NSString stringWithFormat:@"%@ / %@", ABFormatBytes(done), ABFormatBytes(total)];
}

- (void)cancelTapped {
    self.cancelButton.enabled = NO;
    [self.cancelButton setTitle:@"正在取消…" forState:UIControlStateNormal];
    if (self.cancelHandler) {
        self.cancelHandler();
    }
}

- (void)dismiss {
    [self removeFromSuperview];
}

@end
