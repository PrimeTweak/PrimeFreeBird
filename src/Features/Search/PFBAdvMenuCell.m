#import "Common/PFBBundle.h"
#import "Features/Search/PFBAdvancedSearchStyle.h"
#import "Support/HookHelpers.h"
#import "Features/Search/PFBAdvMenuCell.h"
#import "Features/Search/PFBAdvField.h"

// The capsule's content as one button; a press dims it, as a row's does.
@interface PFBAdvValueField : UIControl
@end

@implementation PFBAdvValueField

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.alpha = highlighted ? 0.5 : 1.0;
}

@end

@implementation PFBAdvMenuCell {
    UIImageView* _chevron;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString*)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        _valueField = [[PFBAdvValueField alloc] init];
        _valueField.isAccessibilityElement = YES;
        _valueField.accessibilityTraits = UIAccessibilityTraitButton;
        [_valueField addTarget:self action:@selector(pfbOpen) forControlEvents:UIControlEventTouchUpInside];
        _valueLabel = [[UILabel alloc] init];
        _chevron = [[UIImageView alloc] init];
        _chevron.contentMode = UIViewContentModeCenter;
        for (UIView* part in @[ _valueLabel, _chevron ]) {
            part.translatesAutoresizingMaskIntoConstraints = NO;
            part.userInteractionEnabled = NO;
            [_valueField addSubview:part];
        }
        [_chevron setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [NSLayoutConstraint activateConstraints:@[
            [_valueLabel.leadingAnchor constraintEqualToAnchor:_valueField.leadingAnchor],
            [_valueLabel.centerYAnchor constraintEqualToAnchor:_valueField.centerYAnchor],
            [_valueLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_chevron.leadingAnchor constant:-8.0],
            [_chevron.trailingAnchor constraintEqualToAnchor:_valueField.trailingAnchor constant:-4.0],
            [_chevron.centerYAnchor constraintEqualToAnchor:_valueField.centerYAnchor],
        ]];
        UILabel* name = nil;
        UILabel* example = nil;
        PFBAdvInstallField(self, _valueField, &name, &example);
        _nameLabel = name;
        _exampleLabel = example;
        [self applyTheme];
    }
    return self;
}

// The chevron is Twitter's, as on the rows of its new settings.
- (void)applyTheme {
    PFBAdvThemeLabels(self.nameLabel, self.exampleLabel);
    self.valueLabel.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:16]);
    self.valueLabel.textColor = PFBSettingsTextColor();
    _chevron.image = [PFBTwitterGlyphFor(@"chevron_right", [UIImage systemImageNamed:@"chevron.right"])
        imageFlippedForRightToLeftLayoutDirection];
    _chevron.tintColor = [UIColor tertiaryLabelColor];
}

- (void)traitCollectionDidChange:(UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self applyTheme];
}

- (void)configureWith:(PFBAdvField*)model currentTitle:(NSString*)currentTitle open:(void (^)(void))open {
    PFBBundle* bundle = [PFBBundle sharedBundle];
    NSString* title = [bundle localizedStringForKey:model.labelKey];
    self.nameLabel.text = title;
    self.valueLabel.text = currentTitle;
    self.valueField.accessibilityLabel = title;
    self.valueField.accessibilityValue = currentTitle;
    self.exampleLabel.text =
        model.exampleKey ? [bundle localizedStringForKey:model.exampleKey] : @"";
    self.open = open;
}

- (void)pfbOpen {
    if (self.open) {
        self.open();
    }
}

@end
