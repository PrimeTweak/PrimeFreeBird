#import "Common/PFBCompatibility.h"
#import "Settings/PFBModernSettingsCells.h"
#import <QuartzCore/QuartzCore.h>
#import "Support/PFBManager.h"
#import "Common/PFBSettings.h"
#import "Support/TWHeaders.h"
#import "Features/Appearance/ThemeColor/PFBPalette.h"
#import "Features/Appearance/ThemeColor/PFBDarkModeStyle.h"
#import "Support/TwitterChirpFont.h"
#import "Debug/PFBDebugger.h"
#import "Settings/PFBModernSettingsButtonPairCell.h"

@interface PFBModernSettingsButtonPairCell ()
@property (nonatomic, strong) UIButton* firstButton;
@property (nonatomic, strong) UIButton* secondButton;
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

- (void)applyTheme {
    id fontGroup = [PFBManager sharedFontGroup];
    Class TAEColorSettingsCls = objc_getClass("TAEColorSettings");
    id colorPalette =
        [[[TAEColorSettingsCls sharedSettings] currentColorPalette] colorPalette];
    self.backgroundColor = [PFBPalette currentBackgroundColor];
    UIFont* font = [fontGroup performSelector:@selector(bodyBoldFont)];
    UIColor* ink = [colorPalette performSelector:@selector(textColor)];
    UIColor* faint = [colorPalette performSelector:@selector(faintBackgroundColor)];
    for (UIButton* button in @[ self.firstButton, self.secondButton ]) {
        button.titleLabel.font = font;
        button.backgroundColor = faint;
        [button setTitleColor:ink forState:UIControlStateNormal];
    }
}

@end
