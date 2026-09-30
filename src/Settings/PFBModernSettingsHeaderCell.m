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
#import "Settings/PFBModernSettingsHeaderCell.h"
#import "Settings/PFBModernSettingsTableViewCell.h"

@implementation PFBModernSettingsHeaderCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString*)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.userInteractionEnabled = NO;
        self.backgroundColor = [PFBPalette currentBackgroundColor];

        // Same margin neutralisation as PFBModernSettingsTableViewCell. Without it
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
