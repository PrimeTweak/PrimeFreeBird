#import "Support/TwitterChirpFont.h"
#import "Support/HookHelpers.h"
#import "Features/Timelines/PFBMutedWordsStyle.h"
#import "Features/Timelines/PFBMutedAddCell.h"
#import "Settings/Native/PFBNativeSettingsRowCell.h"
#import "Settings/PFBSettingsCellStyle.h"

@interface PFBMutedAddCell ()
@property (nonatomic, strong) UIView* box;
@property (nonatomic, assign) BOOL native;
@property (nonatomic, strong) NSLayoutConstraint* boxLeading;
@property (nonatomic, strong) NSLayoutConstraint* boxHeight;
@property (nonatomic, strong) NSLayoutConstraint* addTrailing;
@property (nonatomic, strong) NSLayoutConstraint* addHeight;
@property (nonatomic, strong) NSLayoutConstraint* hintLeading;
@property (nonatomic, strong) NSLayoutConstraint* hintTrailing;
@end

@implementation PFBMutedAddCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString*)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [UIColor clearColor];

        // Bordered box, 1 pt systemGray3, radius 6 — the exact box the advanced
        // search screen uses, so the two screens read as one design.
        UIView* box = [[UIView alloc] init];
        _box = box;
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

        _boxLeading = [box.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor
                                                        constant:kPFBMutedSideMargin];
        _boxHeight = [box.heightAnchor constraintEqualToConstant:42.0];
        _hintLeading = [_hintLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor
                                                                constant:kPFBMutedSideMargin + 2.0];
        _hintTrailing = [_hintLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor
                                                                  constant:-kPFBMutedSideMargin];
        _addTrailing = [_addButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor
                                                                 constant:-kPFBMutedSideMargin];
        _addHeight = [_addButton.heightAnchor constraintEqualToConstant:42.0];
        [NSLayoutConstraint activateConstraints:@[
            _boxLeading,
            // 16 pt matches the visible top of a language name in the other list.
            [box.topAnchor constraintEqualToAnchor:self.contentView.topAnchor
                                          constant:16.0],
            _boxHeight,
            [_hintLabel.topAnchor constraintEqualToAnchor:box.bottomAnchor
                                                 constant:8.0],
            _hintLeading,
            _hintTrailing,
            [_hintLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor
                                                    constant:-10.0],
            [_field.leadingAnchor constraintEqualToAnchor:box.leadingAnchor
                                                 constant:12.0],
            [_field.trailingAnchor constraintEqualToAnchor:box.trailingAnchor
                                                  constant:-10.0],
            [_field.centerYAnchor constraintEqualToAnchor:box.centerYAnchor],
            [_addButton.leadingAnchor constraintEqualToAnchor:box.trailingAnchor
                                                     constant:10.0],
            _addTrailing,
            [_addButton.centerYAnchor constraintEqualToAnchor:box.centerYAnchor],
            _addHeight,
            [_addButton.widthAnchor constraintGreaterThanOrEqualToConstant:64.0],
        ]];
    }
    return self;
}

// The controls stand 16 points in, the text where the rows' icons stand.
- (void)applyNativeLook {
    self.native = YES;
    CGFloat text = [PFBNativeSettingsRowStyle shared].iconFrame.origin.x;
    self.boxLeading.constant = 16.0;
    self.addTrailing.constant = -16.0;
    self.hintLeading.constant = text;
    self.hintTrailing.constant = -text;
    self.boxHeight.constant = 40.0;
    self.addHeight.constant = 40.0;
    self.box.layer.borderWidth = 0.0;
    self.box.layer.cornerRadius = 20.0;
    self.addButton.layer.cornerRadius = 20.0;
    [self applyNativeColors];
}

- (void)applyNativeColors {
    self.box.backgroundColor = PFBSettingsFaintColor();
    self.addButton.backgroundColor = PFBSettingsTextColor();
    [self.addButton setTitleColor:[PFBPalette currentBackgroundColor] forState:UIControlStateNormal];
}

// In the new look Add keeps the text color; the classic one takes the accent.
- (void)tintColorDidChange {
    [super tintColorDidChange];
    if (self.native) {
        return;
    }
    self.addButton.backgroundColor =
        PFBCurrentAccentColor() ?: (self.tintColor ?: [UIColor systemBlueColor]);
}

// A layer border keeps the CGColor it was given: the gray is resolved again for the new
// appearance, as the new look's colors are.
- (void)traitCollectionDidChange:(UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (self.native) {
        [self applyNativeColors];
        return;
    }
    self.box.layer.borderColor = [[UIColor systemGray3Color] resolvedColorWithTraitCollection:self.traitCollection].CGColor;
}

@end
