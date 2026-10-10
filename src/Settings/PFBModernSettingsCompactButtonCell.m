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
#import "Settings/PFBSettingsCellStyle.h"
#import "Settings/PFBModernSettingsCompactButtonCell.h"

UIColor* PFBSettingsSubtitleColor(void) {
    Class TAEColorSettingsCls = objc_getClass("TAEColorSettings");
    id settings = [TAEColorSettingsCls sharedSettings];
    id currentPalette = [settings currentColorPalette];
    id colorPalette = [currentPalette colorPalette];
    return [colorPalette performSelector:@selector(tabBarItemColor)];
}

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
    UIColor* subtitleColor = PFBSettingsSubtitleColor();
    self.subtitleLabel.textColor = subtitleColor;
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
    }
}
 
@end
