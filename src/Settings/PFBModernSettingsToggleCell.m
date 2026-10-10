#import <QuartzCore/QuartzCore.h>
#import "Support/PFBManager.h"
#import "Support/TWHeaders.h"
#import "Features/Appearance/ThemeColor/PFBPalette.h"
#import "Settings/PFBModernSettingsToggleCell.h"
#import "Settings/PFBTintedSwitch.h"

@implementation PFBModernSettingsToggleCell
 
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
        self.backgroundColor = [PFBPalette currentBackgroundColor];
        self.titleLabel = [UILabel new];
        self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.titleLabel];
        self.subtitleLabel = [UILabel new];
        self.subtitleLabel.numberOfLines = 0;
        self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.subtitleLabel];
        self.toggleSwitch = [PFBTintedSwitch new];
        self.toggleSwitch.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.toggleSwitch];
        self.pillButton = [UIButton buttonWithType:UIButtonTypeSystem];
        self.pillButton.translatesAutoresizingMaskIntoConstraints = NO;
        // Vertically tight on purpose: centered on the title, a taller pill would
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
            // The subtitle stops where the title does, so both share one right edge
            // and the text wraps at the pill. On a row without a pill the title
            // already stops at the switch.
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

// A recycled cell can still be inside the pill's fade: its completion would then
// land on whatever row the cell serves next. Reset to the no-pill layout and let
// the next configuration decide.
- (void)prepareForReuse {
    [super prepareForReuse];
    self.pillButton.hidden = YES;
    self.pillButton.alpha = 0.0;
    self.titleTrailingToPill.active = NO;
    self.titleTrailingToSwitch.active = YES;
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
    id fontGroup = [PFBManager sharedFontGroup];
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
    [(PFBTintedSwitch*)self.toggleSwitch pfb_refreshTint];
}
 
- (void)traitCollectionDidChange:(UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self applyTheme];
}
 
@end
