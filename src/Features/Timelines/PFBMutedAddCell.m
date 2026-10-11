#import "Support/TwitterChirpFont.h"
#import "Support/HookHelpers.h"
#import "Features/Timelines/PFBMutedWordsStyle.h"
#import "Features/Timelines/PFBMutedAddCell.h"

@implementation PFBMutedAddCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString*)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [UIColor clearColor];

        // Bordered box, 1px systemGray3, radius 6 — the exact box the advanced
        // search screen uses, so the two screens read as one design.
        UIView* box = [[UIView alloc] init];
        box.layer.borderWidth = 1.0;
        box.layer.borderColor = [UIColor systemGray3Color].CGColor;
        box.layer.cornerRadius = 6.0;

        _field = [[UITextField alloc] init];
        _field.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:16]);
        _field.autocorrectionType = UITextAutocorrectionTypeNo;
        _field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        _field.returnKeyType = UIReturnKeyDone;
        _field.clearButtonMode = UITextFieldViewModeWhileEditing;

        // The explanation lives inside this cell, under the box: that keeps
        // the order fixed (box, then hint, then the list) in both the full
        // screen and the popover, without a separate footer.
        _hintLabel = [[UILabel alloc] init];
        _hintLabel.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:13.5]);
        _hintLabel.textColor = [UIColor secondaryLabelColor];
        _hintLabel.numberOfLines = 0;

        _addButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _addButton.titleLabel.font =
            PFBScaledFont([TwitterChirpFont(TwitterFontStyleBold) fontWithSize:15]);
        [_addButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        // The accent is read from the theme rather than inherited from the
        // window: outside Liquid Glass no window tint is pushed, and this
        // button would fall back to the system color.
        _addButton.backgroundColor =
            PFBCurrentAccentColor() ?: (self.tintColor ?: [UIColor systemBlueColor]);
        _addButton.layer.cornerRadius = 6.0;
        [_addButton setContentHuggingPriority:UILayoutPriorityRequired
                                      forAxis:UILayoutConstraintAxisHorizontal];

        for (UIView* v in @[ box, _addButton, _hintLabel ]) {
            v.translatesAutoresizingMaskIntoConstraints = NO;
            [self.contentView addSubview:v];
        }
        _field.translatesAutoresizingMaskIntoConstraints = NO;
        [box addSubview:_field];

        [NSLayoutConstraint activateConstraints:@[
            [box.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor
                                              constant:kPFBMutedSideMargin],
            // 16 pt matches the visible top of a language name in the other list.
            [box.topAnchor constraintEqualToAnchor:self.contentView.topAnchor
                                          constant:16.0],
            [box.heightAnchor constraintEqualToConstant:42.0],
            [_hintLabel.topAnchor constraintEqualToAnchor:box.bottomAnchor
                                                 constant:8.0],
            [_hintLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor
                                                     constant:kPFBMutedSideMargin + 2.0],
            [_hintLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor
                                                      constant:-kPFBMutedSideMargin],
            [_hintLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor
                                                    constant:-10.0],
            [_field.leadingAnchor constraintEqualToAnchor:box.leadingAnchor
                                                 constant:12.0],
            [_field.trailingAnchor constraintEqualToAnchor:box.trailingAnchor
                                                  constant:-10.0],
            [_field.centerYAnchor constraintEqualToAnchor:box.centerYAnchor],
            [_addButton.leadingAnchor constraintEqualToAnchor:box.trailingAnchor
                                                     constant:10.0],
            [_addButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor
                                                      constant:-kPFBMutedSideMargin],
            [_addButton.centerYAnchor constraintEqualToAnchor:box.centerYAnchor],
            [_addButton.heightAnchor constraintEqualToConstant:42.0],
            [_addButton.widthAnchor constraintGreaterThanOrEqualToConstant:64.0],
        ]];
    }
    return self;
}

- (void)tintColorDidChange {
    [super tintColorDidChange];
    self.addButton.backgroundColor =
        PFBCurrentAccentColor() ?: (self.tintColor ?: [UIColor systemBlueColor]);
}

@end
