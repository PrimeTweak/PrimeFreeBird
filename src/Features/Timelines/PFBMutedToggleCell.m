#import "Settings/PFBSettingsCellStyle.h"
#import "Features/Timelines/PFBMutedWordsStyle.h"
#import "Features/Timelines/PFBMutedToggleCell.h"

@implementation PFBMutedToggleCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString*)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [UIColor clearColor];

        _titleLabel2 = [[UILabel alloc] init];

        _subtitleLabel = [[UILabel alloc] init];
        _subtitleLabel.numberOfLines = 0;

        _toggle = [[UISwitch alloc] init];

        for (UIView* v in @[ _titleLabel2, _subtitleLabel, _toggle ]) {
            v.translatesAutoresizingMaskIntoConstraints = NO;
            [self.contentView addSubview:v];
        }
        [self applyTheme];
        [NSLayoutConstraint activateConstraints:@[
            [_titleLabel2.topAnchor constraintEqualToAnchor:self.contentView.topAnchor
                                                   constant:18.0],
            [_titleLabel2.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor
                                                       constant:kPFBMutedSideMargin],
            [_titleLabel2.trailingAnchor
                constraintLessThanOrEqualToAnchor:_toggle.leadingAnchor
                                         constant:-16.0],
            [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel2.bottomAnchor
                                                     constant:2.0],
            [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleLabel2.leadingAnchor],
            [_subtitleLabel.trailingAnchor constraintEqualToAnchor:_toggle.leadingAnchor
                                                          constant:-16.0],
            [_subtitleLabel.bottomAnchor
                constraintEqualToAnchor:self.contentView.bottomAnchor
                               constant:-18.0],
            [_toggle.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_toggle.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor
                                                   constant:-kPFBMutedSideMargin],
        ]];
    }
    return self;
}

// The same fonts and palette colors as the rest of the settings, rather than hard
// sizes and system grays. Re-applied on trait changes, since a palette color does
// not follow light and dark on its own.
- (void)applyTheme {
    self.titleLabel2.font = PFBSettingsTitleFont();
    self.subtitleLabel.font = PFBSettingsDetailFont();
    self.titleLabel2.textColor = PFBSettingsTextColor();
    self.subtitleLabel.textColor = PFBSettingsSubtitleColor();
}

- (void)traitCollectionDidChange:(UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self applyTheme];
}

@end
