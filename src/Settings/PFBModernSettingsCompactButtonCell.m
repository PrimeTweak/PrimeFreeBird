#import "Support/PFBManager.h"
#import "Features/Appearance/ThemeColor/PFBPalette.h"
#import "Support/TwitterChirpFont.h"
#import "Settings/PFBSettingsCellStyle.h"
#import "Settings/PFBModernSettingsCompactButtonCell.h"

UIColor* PFBSettingsSubtitleColor(void) {
    Class TAEColorSettingsCls = objc_getClass("TAEColorSettings");
    id settings = [TAEColorSettingsCls sharedSettings];
    id currentPalette = [settings currentColorPalette];
    id colorPalette = [currentPalette colorPalette];
    return [colorPalette performSelector:@selector(tabBarItemColor)];
}

@interface PFBModernSettingsCompactButtonCell ()
@property (nonatomic, strong) NSArray<NSLayoutConstraint*>* singleLine;
@property (nonatomic, strong) NSArray<NSLayoutConstraint*>* withDetail;
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
    id fontGroup = [PFBManager sharedFontGroup];
    self.titleLabel.font = [fontGroup performSelector:@selector(bodyBoldFont)];
    self.titleLabel.textColor = [UIColor labelColor];
    [self.contentView addSubview:self.titleLabel];
 
    self.subtitleLabel = [[UILabel alloc] init];
    self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.subtitleLabel.font = [fontGroup performSelector:@selector(subtext2Font)];
    self.subtitleLabel.textAlignment = NSTextAlignmentRight;
    [self updateSubtitleColor];
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
    [NSLayoutConstraint activateConstraints:@[
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor
                                                      constant:10],
        [self.titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor
                                                  constant:18],
 
        [self.subtitleLabel.leadingAnchor
            constraintGreaterThanOrEqualToAnchor:self.titleLabel.trailingAnchor
                                        constant:16],
        [self.subtitleLabel.trailingAnchor constraintEqualToAnchor:self.chevronImageView.leadingAnchor
                                                          constant:-16],
        [self.subtitleLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
 
        [self.chevronImageView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor
                                                             constant:-10],
        [self.chevronImageView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
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
    self.selectionStyle = UITableViewCellSelectionStyleDefault;
}

// The chevron's place is kept, so a value without one lines up with the others.
- (void)setShowsChevron:(BOOL)showsChevron {
    self.chevronImageView.hidden = !showsChevron;
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
 
- (void)updateChevronColor {
    UIColor* chevronColor = [UIColor tertiaryLabelColor];
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
    [self updateChevronColor];
    [self updateSubtitleColor];
    if (previousTraitCollection.preferredContentSizeCategory !=
        self.traitCollection.preferredContentSizeCategory) {
        id fontGroup = [PFBManager sharedFontGroup];
        self.titleLabel.font = [fontGroup performSelector:@selector(bodyBoldFont)];
        self.subtitleLabel.font = [fontGroup performSelector:@selector(subtext2Font)];
        self.detailLabel.font = self.subtitleLabel.font;
    }
}
 
@end
