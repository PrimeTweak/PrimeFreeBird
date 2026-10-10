#import "Features/Search/PFBAdvancedSearchViewController.h"
#import "Common/PFBBundle.h"
#import "Support/TwitterChirpFont.h"
#import <math.h>
#import <objc/message.h>
#import <objc/runtime.h>
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
        _titleLabel2.font =
            PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:16.5]);
        _titleLabel2.textColor = [UIColor labelColor];

        _subtitleLabel = [[UILabel alloc] init];
        _subtitleLabel.font =
            PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:13.5]);
        _subtitleLabel.textColor = [UIColor secondaryLabelColor];
        _subtitleLabel.numberOfLines = 0;

        _toggle = [[UISwitch alloc] init];
        _toggle.onTintColor = PFBAdvBlue();
        [_toggle addTarget:self
                      action:@selector(pfbToggled:)
            forControlEvents:UIControlEventValueChanged];

        for (UIView* v in @[ _titleLabel2, _subtitleLabel, _toggle ]) {
            v.translatesAutoresizingMaskIntoConstraints = NO;
            [self.contentView addSubview:v];
        }
        UILayoutGuide* m = self.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [_titleLabel2.topAnchor
                constraintEqualToAnchor:self.contentView.topAnchor
                               constant:10.0],
            [_titleLabel2.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
            [_subtitleLabel.topAnchor
                constraintEqualToAnchor:_titleLabel2.bottomAnchor
                               constant:2.0],
            [_subtitleLabel.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
            [_subtitleLabel.trailingAnchor
                constraintEqualToAnchor:_toggle.leadingAnchor
                               constant:-12.0],
            [_subtitleLabel.bottomAnchor
                constraintEqualToAnchor:self.contentView.bottomAnchor
                               constant:-10.0],
            [_titleLabel2.trailingAnchor
                constraintLessThanOrEqualToAnchor:_toggle.leadingAnchor
                                         constant:-12.0],
            [_toggle.centerYAnchor
                constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_toggle.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
        ]];
    }
    return self;
}

- (void)configureWith:(PFBAdvField*)model on:(BOOL)on {
    self.model = model;
    PFBBundle* bundle = [PFBBundle sharedBundle];
    self.titleLabel2.text = [bundle localizedStringForKey:model.labelKey];
    self.subtitleLabel.text =
        model.exampleKey ? [bundle localizedStringForKey:model.exampleKey] : @"";
    self.toggle.on = on;
}

- (void)pfbToggled:(UISwitch*)sender {
    if (!self.model) { return; }
    [[NSUserDefaults standardUserDefaults] setBool:sender.isOn
                                            forKey:self.model.storeKey];
}

@end
