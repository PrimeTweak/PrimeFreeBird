#import "Features/Search/PFBAdvancedSearchViewController.h"
#import "Common/PFBBundle.h"
#import "Support/TwitterChirpFont.h"
#import <math.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "Features/Search/PFBAdvancedSearchStyle.h"
#import "Features/Search/PFBAdvBoxCell.h"
#import "Features/Search/PFBAdvField.h"

@implementation PFBAdvBoxCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString*)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [UIColor clearColor];

        _box = [[UIView alloc] init];
        _box.layer.borderWidth = 1.0;
        _box.layer.borderColor = [UIColor systemGray3Color].CGColor;
        _box.layer.cornerRadius = 6.0;

        _placeholderLabel = [[UILabel alloc] init];
        _placeholderLabel.font =
            PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:16.5]);
        _placeholderLabel.textColor = [UIColor secondaryLabelColor];
        _placeholderLabel.userInteractionEnabled = NO;

        _floatLabel = [[UILabel alloc] init];
        _floatLabel.font =
            PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:13]);
        _floatLabel.textColor = [UIColor secondaryLabelColor];
        _floatLabel.alpha = 0.0;

        _field = [[UITextField alloc] init];
        _field.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:16.5]);
        _field.autocorrectionType = UITextAutocorrectionTypeNo;
        _field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        _field.clearButtonMode = UITextFieldViewModeWhileEditing;
        _field.returnKeyType = UIReturnKeyDone;
        _field.delegate = self;
        [_field addTarget:self
                      action:@selector(pfbFieldEdited:)
            forControlEvents:UIControlEventEditingChanged];

        _exampleLabel = [[UILabel alloc] init];
        _exampleLabel.font =
            PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:13.5]);
        _exampleLabel.textColor = [UIColor secondaryLabelColor];
        _exampleLabel.numberOfLines = 0;

        for (UIView* v in @[ _box, _exampleLabel ]) {
            v.translatesAutoresizingMaskIntoConstraints = NO;
            [self.contentView addSubview:v];
        }
        for (UIView* v in @[ _floatLabel, _field, _placeholderLabel ]) {
            v.translatesAutoresizingMaskIntoConstraints = NO;
            [_box addSubview:v];
        }

        UILayoutGuide* m = self.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [_box.topAnchor constraintEqualToAnchor:self.contentView.topAnchor
                                           constant:7.0],
            [_box.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
            [_box.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
            [_box.heightAnchor constraintEqualToConstant:56.0],

            [_placeholderLabel.leadingAnchor
                constraintEqualToAnchor:_box.leadingAnchor
                               constant:12.0],
            [_placeholderLabel.trailingAnchor
                constraintEqualToAnchor:_box.trailingAnchor
                               constant:-12.0],
            [_placeholderLabel.centerYAnchor
                constraintEqualToAnchor:_box.centerYAnchor],

            [_floatLabel.topAnchor constraintEqualToAnchor:_box.topAnchor
                                                  constant:7.0],
            [_floatLabel.leadingAnchor
                constraintEqualToAnchor:_box.leadingAnchor
                               constant:12.0],
            [_floatLabel.trailingAnchor
                constraintEqualToAnchor:_box.trailingAnchor
                               constant:-12.0],

            [_field.leadingAnchor constraintEqualToAnchor:_box.leadingAnchor
                                                 constant:12.0],
            [_field.trailingAnchor constraintEqualToAnchor:_box.trailingAnchor
                                                  constant:-12.0],
            [_field.bottomAnchor constraintEqualToAnchor:_box.bottomAnchor
                                                constant:-7.0],
            [_field.heightAnchor constraintEqualToConstant:24.0],

            [_exampleLabel.topAnchor constraintEqualToAnchor:_box.bottomAnchor
                                                    constant:6.0],
            [_exampleLabel.leadingAnchor constraintEqualToAnchor:m.leadingAnchor
                                                        constant:2.0],
            [_exampleLabel.trailingAnchor
                constraintEqualToAnchor:m.trailingAnchor],
            [_exampleLabel.bottomAnchor
                constraintEqualToAnchor:self.contentView.bottomAnchor
                               constant:-7.0],
        ]];
    }
    return self;
}

- (void)configureWith:(PFBAdvField*)model {
    self.model = model;
    PFBBundle* bundle = [PFBBundle sharedBundle];
    NSString* title = [bundle localizedStringForKey:model.labelKey];
    self.placeholderLabel.text = title;
    self.floatLabel.text = title;
    self.field.keyboardType = (model.kind == PFBAdvFieldNumber)
                                  ? UIKeyboardTypeNumberPad
                                  : UIKeyboardTypeDefault;
    self.field.text =
        [[NSUserDefaults standardUserDefaults] stringForKey:model.storeKey] ?: @"";
    self.exampleLabel.text =
        model.exampleKey ? [bundle localizedStringForKey:model.exampleKey] : @"";
    [self pfbApplyFloatAnimated:NO];
}

// Label floats up on focus or once there's text — the web behavior.
- (void)pfbApplyFloatAnimated:(BOOL)animated {
    BOOL up = self.field.isFirstResponder || self.field.text.length > 0;
    void (^apply)(void) = ^{
        self.placeholderLabel.alpha = up ? 0.0 : 1.0;
        self.floatLabel.alpha = up ? 1.0 : 0.0;
    };
    if (animated) {
        [UIView animateWithDuration:0.15 animations:apply];
    } else {
        apply();
    }
}

- (void)pfbFieldEdited:(UITextField*)sender {
    if (!self.model) { return; }
    [[NSUserDefaults standardUserDefaults] setObject:(sender.text ?: @"")
                                              forKey:self.model.storeKey];
    [self pfbApplyFloatAnimated:YES];
}

- (void)textFieldDidBeginEditing:(UITextField*)textField {
    self.box.layer.borderColor = PFBAdvBlue().CGColor;
    self.box.layer.borderWidth = 2.0;
    [self pfbApplyFloatAnimated:YES];
}

- (void)textFieldDidEndEditing:(UITextField*)textField {
    self.box.layer.borderColor = [UIColor systemGray3Color].CGColor;
    self.box.layer.borderWidth = 1.0;
    [self pfbApplyFloatAnimated:YES];
}

- (BOOL)textFieldShouldReturn:(UITextField*)textField {
    [textField resignFirstResponder];
    return YES;
}

@end
