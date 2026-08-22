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
#import "ThemeColor/DarkModeStyle.h"
#import "Core/TwitterChirpFont.h"
 
// UIKit paints its own selection in a system gray bright enough to sit above
// the dark-style filter's ceiling, so the row stays gray while the rest of the
// screen is recolored. The shade is handed to the cell directly instead.
static void nfbApplySelectedBackground(UITableViewCell* cell) {
    UIColor* shade = [DarkModeStyle elevatedBackgroundColor];
    if (!shade) {
        cell.selectedBackgroundView = nil;
        return;
    }
    UIView* selected = [[UIView alloc] init];
    selected.backgroundColor = shade;
    cell.selectedBackgroundView = selected;
}

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
    nfbApplySelectedBackground(self);
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
    nfbApplySelectedBackground(self);
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
        // section headers, and the only reason the tweak's read lighter.
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
        self.pillButton = [UIButton buttonWithType:UIButtonTypeSystem];
        self.pillButton.translatesAutoresizingMaskIntoConstraints = NO;
        // Vertically tight on purpose: centred on the title, a taller pill would
        // reach past the title's baseline and clip the first subtitle line.
        self.pillButton.contentEdgeInsets = UIEdgeInsetsMake(5, 13, 5, 13);
        self.pillButton.layer.cornerRadius = 13.0;
        self.pillButton.layer.masksToBounds = YES;
        self.pillButton.hidden = YES;
        self.pillButton.alpha = 0.0;
        [self.pillButton setContentHuggingPriority:UILayoutPriorityRequired
                                           forAxis:UILayoutConstraintAxisHorizontal];
        [self.pillButton
            setContentCompressionResistancePriority:UILayoutPriorityRequired
                                            forAxis:UILayoutConstraintAxisHorizontal];
        [self.contentView addSubview:self.pillButton];
        [self applyTheme];
        self.titleLeading =
            [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor
                                                          constant:10];
        self.titleTrailingToSwitch =
            [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.toggleSwitch.leadingAnchor
                                                           constant:-16];
        self.titleTrailingToPill =
            [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.pillButton.leadingAnchor
                                                           constant:-12];
        [NSLayoutConstraint activateConstraints:@[
            [self.toggleSwitch.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor
                                                             constant:-10],
            [self.pillButton.trailingAnchor constraintEqualToAnchor:self.toggleSwitch.leadingAnchor
                                                           constant:-12],
            [self.pillButton.centerYAnchor constraintEqualToAnchor:self.toggleSwitch.centerYAnchor],
            self.titleLeading,
            [self.titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor
                                                      constant:18],
            self.titleTrailingToSwitch,
            [self.toggleSwitch.centerYAnchor constraintEqualToAnchor:self.titleLabel.centerYAnchor],
            [self.subtitleLabel.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
            // The subtitle stops where the title does, so both share one right
            // edge and the text wraps at the pill rather than running beneath
            // it. On a row without a pill the title already stops at the
            // switch, so nothing there moves.
            [self.subtitleLabel.trailingAnchor
                constraintEqualToAnchor:self.titleLabel.trailingAnchor],
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
 
- (void)setRowEnabled:(BOOL)enabled {
    self.toggleSwitch.enabled = enabled;
    CGFloat alpha = enabled ? 1.0 : 0.4;
    self.titleLabel.alpha = alpha;
    self.subtitleLabel.alpha = alpha;
    self.toggleSwitch.alpha = alpha;
    self.userInteractionEnabled = enabled;
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

- (void)setPillTitle:(NSString*)title {
    [self.pillButton setTitle:title forState:UIControlStateNormal];
}

- (void)addPillTarget:(id)target action:(SEL)action {
    [self.pillButton removeTarget:nil
                           action:NULL
                 forControlEvents:UIControlEventTouchUpInside];
    [self.pillButton addTarget:target
                        action:action
              forControlEvents:UIControlEventTouchUpInside];
}

// The title gives up its width to the pill in the same breath the pill fades
// in, so the row reads as one movement rather than two.
- (void)setPillVisible:(BOOL)visible animated:(BOOL)animated {
    void (^apply)(void) = ^{
      self.titleTrailingToSwitch.active = !visible;
      self.titleTrailingToPill.active = visible;
      self.pillButton.alpha = visible ? 1.0 : 0.0;
      [self.contentView layoutIfNeeded];
    };
    if (visible) {
        self.pillButton.hidden = NO;
    }
    if (!animated) {
        apply();
        self.pillButton.hidden = !visible;
        return;
    }
    [UIView animateWithDuration:0.24
        animations:apply
        completion:^(BOOL finished) {
          self.pillButton.hidden = !visible;
        }];
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
    self.pillButton.titleLabel.font =
        [fontGroup performSelector:@selector(subtext1BoldFont)];
    [self.pillButton setTitleColor:[colorPalette performSelector:@selector(textColor)]
                          forState:UIControlStateNormal];
    self.pillButton.backgroundColor =
        [colorPalette performSelector:@selector(faintBackgroundColor)];
    [(NFBTintedSwitch*)self.toggleSwitch nfb_refreshTint];
}
 
- (void)traitCollectionDidChange:(UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self applyTheme];
}
 
@end

#pragma mark - Explore bar

@interface ModernSettingsTabBarCell ()
@property (nonatomic, strong) UIView* box;
@property (nonatomic, strong) UILabel* captionLabel;
@property (nonatomic, strong) UIView* barContainer;
@property (nonatomic, strong) UIView* rule;
@property (nonatomic, strong) UILabel* hintLabel;
@property (nonatomic, strong) UILabel* countLabel;
@property (nonatomic, strong) NSMutableArray<UIButton*>* tabButtons;
@property (nonatomic, strong) NSLayoutConstraint* barHeight;
@property (nonatomic, assign) CGFloat laidOutWidth;
@end

@implementation ModernSettingsTabBarCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString*)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.contentView.preservesSuperviewLayoutMargins = NO;
        self.contentView.layoutMargins = UIEdgeInsetsZero;
        self.separatorInset = UIEdgeInsetsZero;
        self.backgroundColor = [Palette currentBackgroundColor];
        self.tabButtons = [NSMutableArray array];

        self.box = [UIView new];
        self.box.translatesAutoresizingMaskIntoConstraints = NO;
        self.box.layer.cornerRadius = 16.0;
        self.box.layer.borderWidth = 1.0;
        self.box.layer.masksToBounds = YES;
        [self.contentView addSubview:self.box];

        self.captionLabel = [UILabel new];
        self.captionLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.box addSubview:self.captionLabel];

        self.barContainer = [UIView new];
        self.barContainer.translatesAutoresizingMaskIntoConstraints = NO;
        [self.box addSubview:self.barContainer];

        self.rule = [UIView new];
        self.rule.translatesAutoresizingMaskIntoConstraints = NO;
        [self.box addSubview:self.rule];

        self.hintLabel = [UILabel new];
        self.hintLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.box addSubview:self.hintLabel];

        self.countLabel = [UILabel new];
        self.countLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.countLabel.textAlignment = NSTextAlignmentCenter;
        self.countLabel.layer.cornerRadius = 11.0;
        self.countLabel.layer.masksToBounds = YES;
        [self.countLabel setContentHuggingPriority:UILayoutPriorityRequired
                                           forAxis:UILayoutConstraintAxisHorizontal];
        [self.countLabel
            setContentCompressionResistancePriority:UILayoutPriorityRequired
                                            forAxis:UILayoutConstraintAxisHorizontal];
        [self.box addSubview:self.countLabel];

        self.barHeight = [self.barContainer.heightAnchor constraintEqualToConstant:44.0];
        [NSLayoutConstraint activateConstraints:@[
            [self.box.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor
                                                   constant:18],
            [self.box.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor
                                                    constant:-18],
            [self.box.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6],
            [self.box.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor
                                                  constant:-18],

            [self.captionLabel.leadingAnchor constraintEqualToAnchor:self.box.leadingAnchor
                                                            constant:14],
            [self.captionLabel.topAnchor constraintEqualToAnchor:self.box.topAnchor constant:12],

            [self.barContainer.leadingAnchor constraintEqualToAnchor:self.box.leadingAnchor
                                                            constant:8],
            [self.barContainer.trailingAnchor constraintEqualToAnchor:self.box.trailingAnchor
                                                             constant:-8],
            [self.barContainer.topAnchor constraintEqualToAnchor:self.captionLabel.bottomAnchor
                                                        constant:6],
            self.barHeight,

            [self.rule.leadingAnchor constraintEqualToAnchor:self.box.leadingAnchor],
            [self.rule.trailingAnchor constraintEqualToAnchor:self.box.trailingAnchor],
            [self.rule.topAnchor constraintEqualToAnchor:self.barContainer.bottomAnchor
                                                constant:8],
            [self.rule.heightAnchor constraintEqualToConstant:1],

            [self.hintLabel.leadingAnchor constraintEqualToAnchor:self.box.leadingAnchor
                                                         constant:14],
            [self.hintLabel.topAnchor constraintEqualToAnchor:self.rule.bottomAnchor constant:10],
            [self.hintLabel.bottomAnchor constraintEqualToAnchor:self.box.bottomAnchor
                                                        constant:-12],

            [self.countLabel.trailingAnchor constraintEqualToAnchor:self.box.trailingAnchor
                                                           constant:-14],
            [self.countLabel.leadingAnchor
                constraintGreaterThanOrEqualToAnchor:self.hintLabel.trailingAnchor
                                            constant:8],
            [self.countLabel.centerYAnchor constraintEqualToAnchor:self.hintLabel.centerYAnchor],
            [self.countLabel.heightAnchor constraintEqualToConstant:22],
        ]];
        [self applyTheme];
    }
    return self;
}

- (void)configureWithTabs:(NSArray<NSDictionary*>*)tabs
                  caption:(NSString*)caption
                     hint:(NSString*)hint {
    self.captionLabel.text = caption;
    self.hintLabel.text = hint;
    if (self.tabButtons.count != tabs.count) {
        for (UIButton* old in self.tabButtons) {
            [old removeFromSuperview];
        }
        [self.tabButtons removeAllObjects];
        for (NSUInteger i = 0; i < tabs.count; i++) {
            UIButton* tab = [UIButton buttonWithType:UIButtonTypeCustom];
            [self.barContainer addSubview:tab];
            [self.tabButtons addObject:tab];
        }
    }
    [tabs enumerateObjectsUsingBlock:^(NSDictionary* tab, NSUInteger i, BOOL* stop) {
      UIButton* button = self.tabButtons[i];
      objc_setAssociatedObject(button, @"tabKey", tab[@"key"],
                               OBJC_ASSOCIATION_RETAIN_NONATOMIC);
      objc_setAssociatedObject(button, @"tabName", tab[@"name"],
                               OBJC_ASSOCIATION_RETAIN_NONATOMIC);
      // The first tab is the one Explore opens on, and the app underlines it.
      objc_setAssociatedObject(button, @"tabIsFirst", @(i == 0),
                               OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }];
    self.laidOutWidth = 0;
    [self applyTheme];
    [self setNeedsLayout];
}

- (void)setCountText:(NSString*)text {
    self.countLabel.text = [NSString stringWithFormat:@"  %@  ", text];
}

- (void)addTabTarget:(id)target action:(SEL)action {
    for (UIButton* tab in self.tabButtons) {
        [tab removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
        [tab addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    }
}

// The tabs are flowed by hand rather than stacked: a line is filled until the
// next tab would not fit, then a new line is started. One line is the common
// case and costs nothing; a second appears only when it is needed.
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat available = self.barContainer.bounds.size.width;
    if (available <= 0 || self.tabButtons.count == 0) {
        return;
    }
    const CGFloat lineHeight = 40.0;
    const CGFloat gap = 2.0;
    CGFloat x = 0;
    CGFloat y = 0;
    for (UIButton* tab in self.tabButtons) {
        CGSize size = [tab sizeThatFits:CGSizeMake(available, lineHeight)];
        CGFloat width = MIN(ceil(size.width), available);
        if (x > 0 && x + width > available) {
            x = 0;
            y += lineHeight;
        }
        tab.frame = CGRectMake(x, y, width, lineHeight);
        x += width + gap;
    }
    CGFloat needed = y + lineHeight;
    if (fabs(self.barHeight.constant - needed) > 0.5) {
        self.barHeight.constant = needed;
        // A changed height has to reach the table, which sized this row before
        // the flow ran.
        UITableView* table = (UITableView*)self.superview;
        while (table && ![table isKindOfClass:[UITableView class]]) {
            table = (UITableView*)table.superview;
        }
        [table beginUpdates];
        [table endUpdates];
    }
}

- (void)applyTheme {
    id fontGroup = [BHTManager sharedFontGroup];
    Class TAEColorSettingsCls = objc_getClass("TAEColorSettings");
    id settings = [TAEColorSettingsCls sharedSettings];
    id colorPalette = [[settings currentColorPalette] colorPalette];
    UIColor* ink = [colorPalette performSelector:@selector(textColor)];
    UIColor* soft = [colorPalette performSelector:@selector(tabBarItemColor)];
    UIColor* faint = [colorPalette performSelector:@selector(faintBackgroundColor)];
    UIColor* divider = [colorPalette performSelector:@selector(dividerColor)];

    self.box.backgroundColor = faint;
    self.box.layer.borderColor = divider.CGColor;
    self.rule.backgroundColor = divider;
    self.captionLabel.font = [fontGroup performSelector:@selector(subtext3BoldFont)];
    self.captionLabel.textColor = soft;
    self.hintLabel.font = [fontGroup performSelector:@selector(subtext2Font)];
    self.hintLabel.textColor = soft;
    self.countLabel.font = [fontGroup performSelector:@selector(subtext2BoldFont)];
    self.countLabel.textColor = soft;
    self.countLabel.backgroundColor = [Palette currentBackgroundColor];

    for (UIButton* tab in self.tabButtons) {
        NSString* name = objc_getAssociatedObject(tab, @"tabName") ?: @"";
        NSString* key = objc_getAssociatedObject(tab, @"tabKey");
        BOOL hidden = key ? [BHTSettings boolForKey:key] : NO;
        NSMutableAttributedString* label = [[NSMutableAttributedString alloc]
            initWithString:name
                attributes:@{
                  NSFontAttributeName :
                      [fontGroup performSelector:@selector(subtext1BoldFont)],
                  NSForegroundColorAttributeName : hidden ? soft : ink
                }];
        if (hidden) {
            [label addAttribute:NSStrikethroughStyleAttributeName
                          value:@(NSUnderlineStyleSingle)
                          range:NSMakeRange(0, name.length)];
            [label addAttribute:NSStrikethroughColorAttributeName
                          value:soft
                          range:NSMakeRange(0, name.length)];
        }
        [tab setAttributedTitle:label forState:UIControlStateNormal];
        tab.alpha = hidden ? 0.45 : 1.0;
        tab.contentEdgeInsets = UIEdgeInsetsMake(0, 9, 0, 9);
    }
    [self setNeedsLayout];
}

@end
