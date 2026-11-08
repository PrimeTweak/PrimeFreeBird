#import "Common/PFBBundle.h"
#import "Features/Search/PFBAdvancedSearchStyle.h"
#import "Features/Search/PFBAdvToggleCell.h"
#import "Features/Search/PFBAdvField.h"

@implementation PFBAdvToggleCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString*)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [UIColor clearColor];

        _titleLabel2 = [[UILabel alloc] init];
        _titleLabel2.numberOfLines = 0;
        _subtitleLabel = [[UILabel alloc] init];
        _subtitleLabel.numberOfLines = 0;

        _toggle = [[UISwitch alloc] init];
        [_toggle addTarget:self
                      action:@selector(pfbToggled:)
            forControlEvents:UIControlEventValueChanged];

        for (UIView* v in @[ _titleLabel2, _subtitleLabel, _toggle ]) {
            v.translatesAutoresizingMaskIntoConstraints = NO;
            [self.contentView addSubview:v];
        }
        UIView* box = self.contentView;
        [NSLayoutConstraint activateConstraints:@[
            [_titleLabel2.topAnchor constraintEqualToAnchor:box.topAnchor constant:12.0],
            [_titleLabel2.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:kPFBAdvTextSide],
            [_titleLabel2.trailingAnchor constraintLessThanOrEqualToAnchor:_toggle.leadingAnchor constant:-12.0],
            [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel2.bottomAnchor constant:2.0],
            [_subtitleLabel.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:kPFBAdvTextSide],
            [_subtitleLabel.trailingAnchor constraintEqualToAnchor:_toggle.leadingAnchor constant:-12.0],
            [_subtitleLabel.bottomAnchor constraintEqualToAnchor:box.bottomAnchor constant:-12.0],
            [_toggle.centerYAnchor constraintEqualToAnchor:box.centerYAnchor],
            [_toggle.trailingAnchor constraintEqualToAnchor:box.trailingAnchor constant:-kPFBAdvTextSide],
        ]];
        PFBAdvThemeLabels(_titleLabel2, _subtitleLabel);
    }
    return self;
}

- (void)traitCollectionDidChange:(UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    PFBAdvThemeLabels(self.titleLabel2, self.subtitleLabel);
}

- (void)configureWith:(PFBAdvField*)model on:(BOOL)on {
    self.model = model;
    PFBBundle* bundle = [PFBBundle sharedBundle];
    self.titleLabel2.text = [bundle localizedStringForKey:model.labelKey];
    self.subtitleLabel.text =
        model.exampleKey ? [bundle localizedStringForKey:model.exampleKey] : @"";
    self.toggle.accessibilityLabel = self.titleLabel2.text;
    self.toggle.accessibilityHint = self.subtitleLabel.text;
    self.toggle.on = on;
}

- (void)pfbToggled:(UISwitch*)sender {
    if (!self.model) { return; }
    [[NSUserDefaults standardUserDefaults] setBool:sender.isOn
                                            forKey:self.model.storeKey];
}

@end
