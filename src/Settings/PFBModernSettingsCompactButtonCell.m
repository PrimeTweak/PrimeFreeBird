#import "Support/PFBManager.h"
#import "Features/Appearance/ThemeColor/PFBPalette.h"
#import "Settings/PFBSettingsCellStyle.h"
#import "Settings/PFBModernSettingsCompactButtonCell.h"

@interface PFBModernSettingsCompactButtonCell ()
@property (nonatomic, strong) NSArray<NSLayoutConstraint*>* singleLine;
@property (nonatomic, strong) NSArray<NSLayoutConstraint*>* withDetail;
@property (nonatomic, strong) NSLayoutConstraint* valueToChevron;
@property (nonatomic, strong) NSLayoutConstraint* valueToEdge;
@property (nonatomic, assign) BOOL opensMenu;
@end

@implementation PFBModernSettingsCompactButtonCell
 
- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString*)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        [self setupViews];
        [self setupConstraints];
    }
    return self;
}
 
- (void)setupViews {
    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.numberOfLines = 0;
    self.titleLabel.font = PFBSettingsTitleFont();
    self.titleLabel.textColor = [UIColor labelColor];
    [self.contentView addSubview:self.titleLabel];
 
    self.subtitleLabel = [[UILabel alloc] init];
    self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.subtitleLabel.font = PFBSettingsDetailFont();
    self.subtitleLabel.textAlignment = NSTextAlignmentRight;
    [self.contentView addSubview:self.subtitleLabel];

    self.detailLabel = [[UILabel alloc] init];
    self.detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.detailLabel.font = self.subtitleLabel.font;
    self.detailLabel.numberOfLines = 0;
    self.detailLabel.hidden = YES;
    [self.contentView addSubview:self.detailLabel];
    [self updateSubtitleColor];
 
    self.chevronImageView = [[UIImageView alloc] init];
    self.chevronImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.chevronImageView.contentMode = UIViewContentModeScaleAspectFit;
    [self.contentView addSubview:self.chevronImageView];
 
    self.backgroundColor = [PFBPalette currentBackgroundColor];
    self.selectionStyle = UITableViewCellSelectionStyleDefault;
    pfbApplySelectedBackground(self);
    [self updateChevronColor];
}
 
- (void)setupConstraints {
    self.singleLine = @[
        [self.titleLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [self.titleLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor
                                                     constant:-18],
    ];
    self.withDetail = @[
        [self.detailLabel.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
        [self.detailLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor
                                                   constant:2],
        [self.detailLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor
                                                      constant:-18],
        [self.detailLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.subtitleLabel.leadingAnchor
                                                                   constant:-16],
    ];
    [NSLayoutConstraint activateConstraints:self.singleLine];
    // The value and its chevron sit on the title's line, as a switch does; without a
    // chevron the value ends where the switches do.
    self.valueToChevron = [self.subtitleLabel.trailingAnchor constraintEqualToAnchor:self.chevronImageView.leadingAnchor
                                                                            constant:-16];
    self.valueToEdge = [self.subtitleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor
                                                                         constant:-10];
    [NSLayoutConstraint activateConstraints:@[
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor
                                                      constant:10],
        [self.titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor
                                                  constant:18],
 
        [self.subtitleLabel.leadingAnchor
            constraintGreaterThanOrEqualToAnchor:self.titleLabel.trailingAnchor
                                        constant:16],
        self.valueToChevron,
        [self.subtitleLabel.centerYAnchor constraintEqualToAnchor:self.titleLabel.centerYAnchor],
 
        [self.chevronImageView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor
                                                             constant:-10],
        [self.chevronImageView.centerYAnchor constraintEqualToAnchor:self.titleLabel.centerYAnchor],
        [self.chevronImageView.widthAnchor constraintEqualToConstant:18],
        [self.chevronImageView.heightAnchor constraintEqualToConstant:18]
    ]];
    [self.titleLabel setContentHuggingPriority:UILayoutPriorityDefaultHigh
                                       forAxis:UILayoutConstraintAxisHorizontal];
    [self.subtitleLabel setContentHuggingPriority:UILayoutPriorityDefaultLow
                                          forAxis:UILayoutConstraintAxisHorizontal];
    [self.subtitleLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow
                                                        forAxis:UILayoutConstraintAxisHorizontal];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    // Rows are recycled: a described or chevron-less row must not pass that on.
    [self configureWithTitle:nil subtitle:nil detail:nil];
    [self setShowsChevron:YES];
    [self setOpensMenu:NO];
    self.selectionStyle = UITableViewCellSelectionStyleDefault;
}

- (void)setShowsChevron:(BOOL)showsChevron {
    self.chevronImageView.hidden = !showsChevron;
    self.valueToEdge.active = NO;
    self.valueToChevron.active = showsChevron;
    self.valueToEdge.active = !showsChevron;
}

- (void)setOpensMenu:(BOOL)opensMenu {
    _opensMenu = opensMenu;
    [self updateChevronColor];
}

- (void)configureWithTitle:(NSString*)title subtitle:(NSString*)subtitle detail:(NSString*)detail {
    self.titleLabel.text = title;
    self.subtitleLabel.text = subtitle;
    BOOL described = detail.length > 0;
    self.detailLabel.text = detail;
    self.detailLabel.hidden = !described;
    [NSLayoutConstraint deactivateConstraints:described ? self.singleLine : self.withDetail];
    [NSLayoutConstraint activateConstraints:described ? self.withDetail : self.singleLine];
    // Described, the value keeps its width and the description wraps instead.
    [self.subtitleLabel setContentCompressionResistancePriority:described ? UILayoutPriorityDefaultHigh + 1
                                                                          : UILayoutPriorityDefaultLow
                                                        forAxis:UILayoutConstraintAxisHorizontal];
}
 
// A row that opens a menu in place shows the up-down chevron of UIKit's pop-up buttons; a
// row that leads to a screen shows Twitter's right chevron.
- (void)updateChevronColor {
    UIColor* chevronColor = [UIColor tertiaryLabelColor];
    if (self.opensMenu) {
        UIImageSymbolConfiguration* config =
            [UIImageSymbolConfiguration configurationWithPointSize:12 weight:UIImageSymbolWeightSemibold];
        self.chevronImageView.contentMode = UIViewContentModeCenter;
        self.chevronImageView.tintColor = chevronColor;
        self.chevronImageView.image = [UIImage systemImageNamed:@"chevron.up.chevron.down" withConfiguration:config];
        return;
    }
    self.chevronImageView.contentMode = UIViewContentModeScaleAspectFit;
    if (![UIImage respondsToSelector:@selector(tfn_vectorImageNamed:fitsSize:fillColor:)]) {
        return;
    }
    self.chevronImageView.image = [UIImage tfn_vectorImageNamed:@"chevron_right"
                                                       fitsSize:CGSizeMake(18, 18)
                                                      fillColor:chevronColor];
}
 
- (void)updateSubtitleColor {
    UIColor* subtitleColor = PFBSettingsSubtitleColor();
    self.subtitleLabel.textColor = subtitleColor;
    self.detailLabel.textColor = subtitleColor;
}
 
- (void)traitCollectionDidChange:(UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    self.backgroundColor = [PFBPalette currentBackgroundColor];
    pfbApplySelectedBackground(self);
    [self updateChevronColor];
    [self updateSubtitleColor];
    if (previousTraitCollection.preferredContentSizeCategory !=
        self.traitCollection.preferredContentSizeCategory) {
        self.titleLabel.font = PFBSettingsTitleFont();
        self.subtitleLabel.font = PFBSettingsDetailFont();
        self.detailLabel.font = self.subtitleLabel.font;
    }
}
 
@end
