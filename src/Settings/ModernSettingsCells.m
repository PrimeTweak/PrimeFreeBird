//
//  ModernSettingsCells.m
//  PrimeFreeBird
//
//  Created by nyaathea
//

#import "Settings/ModernSettingsCells.h"
#import "Core/BHTManager.h"
#import "Core/BHTSettings.h"
#import "Headers/TWHeaders.h"
#import "ThemeColor/Palette.h"
#import "Core/TwitterChirpFont.h"
 
@interface ModernSettingsTableViewCell ()
@property (nonatomic, strong) NSLayoutConstraint* titleLeadingWithIcon;
@property (nonatomic, strong) NSLayoutConstraint* titleLeadingNoIcon;
@end

@implementation ModernSettingsTableViewCell

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
    self.contentView.preservesSuperviewLayoutMargins = NO;
    self.contentView.layoutMargins = UIEdgeInsetsZero;
    self.preservesSuperviewLayoutMargins = NO;
    self.layoutMargins = UIEdgeInsetsZero;
    self.separatorInset = UIEdgeInsetsZero;
    self.iconImageView = [[UIImageView alloc] init];
    self.iconImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.iconImageView.contentMode = UIViewContentModeScaleAspectFit;
    self.iconImageView.tintColor = [UIColor secondaryLabelColor];
    [self.contentView addSubview:self.iconImageView];
 
    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    id fontGroup = [BHTManager sharedFontGroup];
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
 
    self.backgroundColor = [Palette currentBackgroundColor];
    self.selectionStyle = UITableViewCellSelectionStyleDefault;
}
 
- (void)setupConstraints {
        // Title leading is conditional: after the icon when there is one, flush
    // with the toggle cells (16pt) when there isn't — fixes the indent drift.
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
    Class TAEColorSettingsCls = objc_getClass("TAEColorSettings");
    id settings = [TAEColorSettingsCls sharedSettings];
    id currentPalette = [settings currentColorPalette];
    id colorPalette = [currentPalette colorPalette];
    UIColor* subtitleColor = [colorPalette performSelector:@selector(tabBarItemColor)];
    self.subtitleLabel.textColor = subtitleColor;
}
 
- (void)traitCollectionDidChange:(UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    self.backgroundColor = [Palette currentBackgroundColor];
    [self updateIconColors];
    [self updateSubtitleColor];
    if (previousTraitCollection.preferredContentSizeCategory !=
        self.traitCollection.preferredContentSizeCategory) {
        id fontGroup = [BHTManager sharedFontGroup];
        self.titleLabel.font = [fontGroup performSelector:@selector(bodyBoldFont)];
        self.subtitleLabel.font = [fontGroup performSelector:@selector(subtext2Font)];
    }
}
 
@end

@implementation ModernSettingsCompactButtonCell
 
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
    id fontGroup = [BHTManager sharedFontGroup];
    self.titleLabel.font = [fontGroup performSelector:@selector(bodyBoldFont)];
    self.titleLabel.textColor = [UIColor labelColor];
    [self.contentView addSubview:self.titleLabel];
 
    self.subtitleLabel = [[UILabel alloc] init];
    self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.subtitleLabel.font = [fontGroup performSelector:@selector(subtext2Font)];
    self.subtitleLabel.textAlignment = NSTextAlignmentRight;
    [self updateSubtitleColor];
    [self.contentView addSubview:self.subtitleLabel];
 
    self.chevronImageView = [[UIImageView alloc] init];
    self.chevronImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.chevronImageView.contentMode = UIViewContentModeScaleAspectFit;
    [self.contentView addSubview:self.chevronImageView];
 
    self.backgroundColor = [Palette currentBackgroundColor];
    self.selectionStyle = UITableViewCellSelectionStyleDefault;
    [self updateChevronColor];
}
 
- (void)setupConstraints {
    [NSLayoutConstraint activateConstraints:@[
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor
                                                      constant:10],
        [self.titleLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [self.titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor
                                                  constant:18],
        [self.titleLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor
                                                     constant:-18],
 
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
 
- (void)configureWithTitle:(NSString*)title subtitle:(NSString*)subtitle {
    self.titleLabel.text = title;
    self.subtitleLabel.text = subtitle;
}
 
- (void)updateChevronColor {
    UIColor* chevronColor = [UIColor tertiaryLabelColor];
    self.chevronImageView.image = [UIImage tfn_vectorImageNamed:@"chevron_right"
                                                       fitsSize:CGSizeMake(18, 18)
                                                      fillColor:chevronColor];
}
 
- (void)updateSubtitleColor {
    Class TAEColorSettingsCls = objc_getClass("TAEColorSettings");
    id settings = [TAEColorSettingsCls sharedSettings];
    id currentPalette = [settings currentColorPalette];
    id colorPalette = [currentPalette colorPalette];
    UIColor* subtitleColor = [colorPalette performSelector:@selector(tabBarItemColor)];
    self.subtitleLabel.textColor = subtitleColor;
}
 
- (void)traitCollectionDidChange:(UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    self.backgroundColor = [Palette currentBackgroundColor];
    [self updateChevronColor];
    [self updateSubtitleColor];
    if (previousTraitCollection.preferredContentSizeCategory !=
        self.traitCollection.preferredContentSizeCategory) {
        id fontGroup = [BHTManager sharedFontGroup];
        self.titleLabel.font = [fontGroup performSelector:@selector(bodyBoldFont)];
        self.subtitleLabel.font = [fontGroup performSelector:@selector(subtext2Font)];
    }
}
 
@end
 
@implementation ModernSettingsHeaderCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString*)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.userInteractionEnabled = NO;
        self.backgroundColor = [Palette currentBackgroundColor];

        // Same margin neutralisation as ModernSettingsTableViewCell. Without it
        // the header's contentView starts from a different origin, so its 16pt
        // does not line up with the rows' 16pt.
        self.contentView.preservesSuperviewLayoutMargins = NO;
        self.contentView.layoutMargins = UIEdgeInsetsZero;
        self.preservesSuperviewLayoutMargins = NO;
        self.layoutMargins = UIEdgeInsetsZero;
        self.separatorInset = UIEdgeInsetsZero;

        self.headerLabel = [UILabel new];
        self.headerLabel.translatesAutoresizingMaskIntoConstraints = NO;
        // Chirp Heavy (800), not Bold (700) — the weight Twitter uses for its own
        // section headers, and the only reason ours read lighter.
        self.headerLabel.font = [TwitterChirpFont(TwitterFontStyleBold) fontWithSize:20];
        self.headerLabel.textColor = [UIColor labelColor];
        [self.contentView addSubview:self.headerLabel];

        [NSLayoutConstraint activateConstraints:@[
            [self.headerLabel.leadingAnchor
                constraintEqualToAnchor:self.contentView.leadingAnchor constant:10],
            [self.headerLabel.trailingAnchor
                constraintEqualToAnchor:self.contentView.trailingAnchor constant:-10],
            [self.headerLabel.topAnchor
                constraintEqualToAnchor:self.contentView.topAnchor constant:20],
            [self.headerLabel.bottomAnchor
                constraintEqualToAnchor:self.contentView.bottomAnchor constant:-8]
        ]];
    }
    return self;
}

- (void)configureWithTitle:(NSString*)title {
    self.headerLabel.text = title;
}

@end
@interface NFBTintedSwitch : UISwitch
- (void)nfb_refreshTint;
@end
 
@implementation NFBTintedSwitch
 
- (void)nfb_refreshTint {
    extern UIColor* CurrentAccentColor(void);
    UIColor* target = nil;
    if ([BHTSettings boolForKey:@"color_nfb_switches"]) {
        UIColor* accent = CurrentAccentColor();
        // Freeze to a static colour so it can't re-resolve through the hooks.
        target = [accent resolvedColorWithTraitCollection:self.traitCollection] ?: accent;
    }
    if (self.onTintColor != target && ![self.onTintColor isEqual:target]) {
        [UIView performWithoutAnimation:^{
            self.onTintColor = target;
        }];
    }
}
 
- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) {
        [self nfb_refreshTint];
    }
}
 
- (void)tintColorDidChange {
    [super tintColorDidChange];
    [self nfb_refreshTint];
}
 
@end
 
@implementation ModernSettingsToggleCell
 
- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString*)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.contentView.preservesSuperviewLayoutMargins = NO;
        self.contentView.layoutMargins = UIEdgeInsetsZero;
        self.preservesSuperviewLayoutMargins = NO;
        self.layoutMargins = UIEdgeInsetsZero;
        self.separatorInset = UIEdgeInsetsZero;
        self.backgroundColor = [Palette currentBackgroundColor];
        self.titleLabel = [UILabel new];
        self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.titleLabel];
        self.subtitleLabel = [UILabel new];
        self.subtitleLabel.numberOfLines = 0;
        self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.subtitleLabel];
        self.toggleSwitch = [NFBTintedSwitch new];
        self.toggleSwitch.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.toggleSwitch];
        [self applyTheme];
        self.titleLeading =
            [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor
                                                          constant:10];
        [NSLayoutConstraint activateConstraints:@[
            [self.toggleSwitch.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor
                                                             constant:-10],
            self.titleLeading,
            [self.titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor
                                                      constant:18],
            [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.toggleSwitch.leadingAnchor
                                                           constant:-16],
            [self.toggleSwitch.centerYAnchor constraintEqualToAnchor:self.titleLabel.centerYAnchor],
            [self.subtitleLabel.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
            [self.subtitleLabel.trailingAnchor constraintEqualToAnchor:self.titleLabel.trailingAnchor],
            [self.subtitleLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor
                                                         constant:2],
            [self.subtitleLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor
                                                            constant:-18]
        ]];
    }
    return self;
}
 
- (void)configureWithTitle:(NSString*)title subtitle:(NSString*)subtitle {
    self.titleLabel.text = title;
    self.subtitleLabel.text = subtitle;
}
 
- (void)configureWithTitle:(NSString*)title subtitle:(NSString*)subtitle iconName:(NSString*)iconName {
    [self configureWithTitle:title subtitle:subtitle];
    objc_setAssociatedObject(self, @selector(iconImageView), iconName, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
 
// Child rows (e.g. the per-tab switches under "Hide trending content") sit a
// step to the right so they read as a sub-category. 34 = 10 base + 24 indent;
// the subtitle follows because it is pinned to titleLabel.leadingAnchor.
// cellForRowAtIndexPath calls this on EVERY toggle cell with the row's flag, so
// a recycled cell always gets the right value (no stale indentation).
- (void)setIndented:(BOOL)indented {
    self.titleLeading.constant = indented ? 34.0 : 10.0;
}

- (void)addTarget:(id)target action:(SEL)action forControlEvents:(UIControlEvents)events {
    [self.toggleSwitch addTarget:target action:action forControlEvents:events];
}
 
- (void)applyTheme {
    id fontGroup = [BHTManager sharedFontGroup];
    self.titleLabel.font = [fontGroup performSelector:@selector(bodyBoldFont)];
    self.subtitleLabel.font = [fontGroup performSelector:@selector(subtext2Font)];
    Class TAEColorSettingsCls = objc_getClass("TAEColorSettings");
    id settings = [TAEColorSettingsCls sharedSettings];
    id colorPalette = [[settings currentColorPalette] colorPalette];
    self.titleLabel.textColor = [colorPalette performSelector:@selector(textColor)];
    self.subtitleLabel.textColor = [colorPalette performSelector:@selector(tabBarItemColor)];
    [(NFBTintedSwitch*)self.toggleSwitch nfb_refreshTint];
}
 
- (void)traitCollectionDidChange:(UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self applyTheme];
}
 
@end
