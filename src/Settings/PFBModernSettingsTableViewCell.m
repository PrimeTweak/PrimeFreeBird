#import "Support/PFBManager.h"
#import "Features/Appearance/ThemeColor/PFBPalette.h"
#import "Settings/PFBSettingsCellStyle.h"
#import "Settings/PFBModernSettingsTableViewCell.h"
#import "Settings/PFBModernSettingsCompactButtonCell.h"

@interface PFBModernSettingsTableViewCell ()
@property (nonatomic, strong) NSLayoutConstraint* titleLeadingWithIcon;
@property (nonatomic, strong) NSLayoutConstraint* titleLeadingNoIcon;
@end
@implementation PFBModernSettingsTableViewCell

- (void)setShowsChevron:(BOOL)showsChevron {
    self.chevronImageView.hidden = !showsChevron;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    // Rows are recycled: one that hid its chevron must not pass that on.
    self.chevronImageView.hidden = NO;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString*)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.contentView.preservesSuperviewLayoutMargins = NO;
        self.contentView.layoutMargins = UIEdgeInsetsZero;
        self.preservesSuperviewLayoutMargins = NO;
        self.layoutMargins = UIEdgeInsetsZero;
        self.separatorInset = UIEdgeInsetsZero;
        [self setupViews];
        [self setupConstraints];
    }
    return self;
}
 
- (void)setupViews {
    self.iconImageView = [[UIImageView alloc] init];
    self.iconImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.iconImageView.contentMode = UIViewContentModeScaleAspectFit;
    self.iconImageView.tintColor = [UIColor secondaryLabelColor];
    [self.contentView addSubview:self.iconImageView];
 
    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    id fontGroup = [PFBManager sharedFontGroup];
    self.titleLabel.font = [fontGroup performSelector:@selector(bodyBoldFont)];
    self.titleLabel.textColor = [UIColor labelColor];
    [self.contentView addSubview:self.titleLabel];
 
    self.subtitleLabel = [[UILabel alloc] init];
    self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.subtitleLabel.font = [fontGroup performSelector:@selector(subtext2Font)];
    [self updateSubtitleColor];
    self.subtitleLabel.numberOfLines = 0;
    [self.contentView addSubview:self.subtitleLabel];
 
    self.chevronImageView = [[UIImageView alloc] init];
    self.chevronImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.chevronImageView.contentMode = UIViewContentModeScaleAspectFit;
    [self.contentView addSubview:self.chevronImageView];
 
    self.backgroundColor = [PFBPalette currentBackgroundColor];
    self.selectionStyle = UITableViewCellSelectionStyleDefault;
    pfbApplySelectedBackground(self);
}
 
- (void)setupConstraints {
    // Title leading is conditional: after the icon when there is one, flush
    // with the toggle cells when there isn't.
    self.titleLeadingWithIcon =
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.iconImageView.trailingAnchor
                                                      constant:10];
    self.titleLeadingNoIcon =
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor
                                                      constant:10];
    self.titleLeadingWithIcon.active = YES;
    [NSLayoutConstraint activateConstraints:@[
        [self.iconImageView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor
                                                         constant:10],
        [self.iconImageView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [self.iconImageView.widthAnchor constraintEqualToConstant:20],
        [self.iconImageView.heightAnchor constraintEqualToConstant:20],
 
        [self.titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor
                                                  constant:18],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.chevronImageView.leadingAnchor
                                                       constant:-16],
 
        [self.subtitleLabel.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
        [self.subtitleLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor
                                                     constant:2],
        [self.subtitleLabel.trailingAnchor constraintEqualToAnchor:self.titleLabel.trailingAnchor],
        [self.subtitleLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor
                                                        constant:-18],
 
        [self.chevronImageView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor
                                                             constant:-10],
        [self.chevronImageView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [self.chevronImageView.widthAnchor constraintEqualToConstant:18],
        [self.chevronImageView.heightAnchor constraintEqualToConstant:18]
    ]];
}
 
- (void)configureWithTitle:(NSString*)title
                  subtitle:(NSString*)subtitle
                  iconName:(NSString*)iconName {
    self.titleLabel.text = title;
    self.subtitleLabel.text = subtitle;
    objc_setAssociatedObject(self, @selector(iconName), iconName, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    BOOL hasIcon = (iconName != nil);
    self.iconImageView.hidden = !hasIcon;
    if (hasIcon) {
        self.titleLeadingNoIcon.active = NO;
        self.titleLeadingWithIcon.active = YES;
    } else {
        self.titleLeadingWithIcon.active = NO;
        self.titleLeadingNoIcon.active = YES;
    }
    [self updateIconColors];
}
 
// Vector images bake in their fill color, so they are re-rendered on every theme change.
- (void)updateIconColors {
    NSString* iconName = objc_getAssociatedObject(self, @selector(iconName));
    if (iconName) {
        Class TAEColorSettingsCls = objc_getClass("TAEColorSettings");
        id settings = [TAEColorSettingsCls sharedSettings];
        id currentPalette = [settings currentColorPalette];
        id colorPalette = [currentPalette colorPalette];
        UIColor* iconColor = [colorPalette performSelector:@selector(tabBarItemColor)];
        self.iconImageView.image = [UIImage tfn_vectorImageNamed:iconName
                                                        fitsSize:CGSizeMake(20, 20)
                                                       fillColor:iconColor];
    }
    UIColor* chevronColor = [UIColor tertiaryLabelColor];
    self.chevronImageView.image = [UIImage tfn_vectorImageNamed:@"chevron_right"
                                                       fitsSize:CGSizeMake(18, 18)
                                                      fillColor:chevronColor];
}
 
- (void)updateSubtitleColor {
    UIColor* subtitleColor = PFBSettingsSubtitleColor();
    self.subtitleLabel.textColor = subtitleColor;
}
 
- (void)traitCollectionDidChange:(UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    self.backgroundColor = [PFBPalette currentBackgroundColor];
    [self updateIconColors];
    [self updateSubtitleColor];
    if (previousTraitCollection.preferredContentSizeCategory !=
        self.traitCollection.preferredContentSizeCategory) {
        id fontGroup = [PFBManager sharedFontGroup];
        self.titleLabel.font = [fontGroup performSelector:@selector(bodyBoldFont)];
        self.subtitleLabel.font = [fontGroup performSelector:@selector(subtext2Font)];
    }
}
 
@end
