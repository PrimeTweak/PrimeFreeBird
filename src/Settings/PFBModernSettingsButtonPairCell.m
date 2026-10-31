#import "Features/Appearance/ThemeColor/PFBPalette.h"
#import "Settings/PFBSettingsCellStyle.h"
#import "Settings/PFBModernSettingsButtonPairCell.h"

@interface PFBModernSettingsButtonPairCell ()
@property (nonatomic, strong) UIButton* firstButton;
@property (nonatomic, strong) UIButton* secondButton;
@property (nonatomic, assign) BOOL secondDestructive;
@end
@implementation PFBModernSettingsButtonPairCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString*)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.contentView.preservesSuperviewLayoutMargins = NO;
        self.contentView.layoutMargins = UIEdgeInsetsZero;
        self.separatorInset = UIEdgeInsetsZero;

        self.firstButton = [UIButton buttonWithType:UIButtonTypeSystem];
        self.secondButton = [UIButton buttonWithType:UIButtonTypeSystem];
        for (UIButton* button in @[ self.firstButton, self.secondButton ]) {
            button.translatesAutoresizingMaskIntoConstraints = NO;
            button.layer.cornerRadius = 12.0;
            button.layer.masksToBounds = YES;
            [self.contentView addSubview:button];
        }
        [NSLayoutConstraint activateConstraints:@[
            [self.firstButton.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor
                                                           constant:18],
            [self.firstButton.topAnchor constraintEqualToAnchor:self.contentView.topAnchor
                                                       constant:2],
            [self.firstButton.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor
                                                          constant:-10],
            [self.firstButton.heightAnchor constraintEqualToConstant:46],
            [self.secondButton.leadingAnchor constraintEqualToAnchor:self.firstButton.trailingAnchor
                                                            constant:8],
            [self.secondButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor
                                                             constant:-18],
            [self.secondButton.topAnchor constraintEqualToAnchor:self.firstButton.topAnchor],
            [self.secondButton.heightAnchor constraintEqualToConstant:46],
            [self.secondButton.widthAnchor constraintEqualToAnchor:self.firstButton.widthAnchor],
        ]];
        [self applyTheme];
    }
    return self;
}

- (void)configureWithFirst:(NSString*)first second:(NSString*)second {
    [self.firstButton setTitle:first forState:UIControlStateNormal];
    [self.secondButton setTitle:second forState:UIControlStateNormal];
    // A recycled cell may come back with its second button disabled.
    self.secondButton.enabled = YES;
    [self applyTheme];
}

- (void)addFirstTarget:(id)target action:(SEL)action {
    [self.firstButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
    [self.firstButton addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
}

- (void)addSecondTarget:(id)target action:(SEL)action {
    [self.secondButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
    [self.secondButton addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
}

- (void)setSecondDestructive:(BOOL)destructive {
    _secondDestructive = destructive;
    [self applyTheme];
}

- (void)setSecondEnabled:(BOOL)enabled {
    self.secondButton.enabled = enabled;
}

- (void)applyTheme {
    self.backgroundColor = [PFBPalette currentBackgroundColor];
    UIFont* font = PFBSettingsTitleFont();
    UIColor* ink = PFBSettingsTextColor();
    UIColor* soft = PFBSettingsSubtitleColor();
    UIColor* faint = PFBSettingsFaintColor();
    UIColor* alert = PFBSettingsAlertColor();
    for (UIButton* button in @[ self.firstButton, self.secondButton ]) {
        button.titleLabel.font = font;
        button.backgroundColor = faint;
        [button setTitleColor:ink forState:UIControlStateNormal];
    }
    // A destructive second action reads in red; disabled, in gray.
    [self.secondButton setTitleColor:self.secondDestructive ? alert : ink forState:UIControlStateNormal];
    [self.secondButton setTitleColor:soft forState:UIControlStateDisabled];
}

// Palette colors are fixed values: they are read again when light and dark switch.
- (void)traitCollectionDidChange:(UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self applyTheme];
}

@end
