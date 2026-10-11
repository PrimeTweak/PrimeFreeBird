#import "Features/Appearance/ThemeColor/PFBPalette.h"
#import "Support/TwitterChirpFont.h"
#import "Settings/PFBModernSettingsHeaderCell.h"

@implementation PFBModernSettingsHeaderCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString*)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.userInteractionEnabled = NO;
        self.backgroundColor = [PFBPalette currentBackgroundColor];

        // Same margin neutralisation as PFBModernSettingsTableViewCell, so the
        // header's contentView starts at the rows' origin and its inset lines up.
        self.contentView.preservesSuperviewLayoutMargins = NO;
        self.contentView.layoutMargins = UIEdgeInsetsZero;
        self.preservesSuperviewLayoutMargins = NO;
        self.layoutMargins = UIEdgeInsetsZero;
        self.separatorInset = UIEdgeInsetsZero;

        self.headerLabel = [UILabel new];
        self.headerLabel.translatesAutoresizingMaskIntoConstraints = NO;
        // TwitterFontStyleBold is Chirp Heavy (800), the weight Twitter uses for its
        // own section headers.
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
