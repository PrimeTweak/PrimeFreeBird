#import "Common/PFBBundle.h"
#import "Features/Search/PFBAdvancedSearchStyle.h"
#import "Features/Search/PFBAdvBoxCell.h"
#import "Features/Search/PFBAdvField.h"

@implementation PFBAdvBoxCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString*)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        _field = [[UITextField alloc] init];
        _field.autocorrectionType = UITextAutocorrectionTypeNo;
        _field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        _field.clearButtonMode = UITextFieldViewModeWhileEditing;
        _field.returnKeyType = UIReturnKeyDone;
        _field.delegate = self;
        [_field addTarget:self
                      action:@selector(pfbFieldEdited:)
            forControlEvents:UIControlEventEditingChanged];
        UILabel* name = nil;
        UILabel* example = nil;
        PFBAdvInstallField(self, _field, &name, &example);
        _nameLabel = name;
        _exampleLabel = example;
        [self applyTheme];
    }
    return self;
}

- (void)applyTheme {
    PFBAdvThemeLabels(self.nameLabel, self.exampleLabel);
    self.field.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:16]);
    self.field.textColor = PFBSettingsTextColor();
}

- (void)traitCollectionDidChange:(UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self applyTheme];
}

- (void)configureWith:(PFBAdvField*)model {
    self.model = model;
    PFBBundle* bundle = [PFBBundle sharedBundle];
    NSString* title = [bundle localizedStringForKey:model.labelKey];
    self.nameLabel.text = title;
    self.field.accessibilityLabel = title;
    self.field.keyboardType = (model.kind == PFBAdvFieldNumber)
                                  ? UIKeyboardTypeNumberPad
                                  : UIKeyboardTypeDefault;
    self.field.text =
        [[NSUserDefaults standardUserDefaults] stringForKey:model.storeKey] ?: @"";
    self.exampleLabel.text =
        model.exampleKey ? [bundle localizedStringForKey:model.exampleKey] : @"";
}

- (void)pfbFieldEdited:(UITextField*)sender {
    if (!self.model) { return; }
    [[NSUserDefaults standardUserDefaults] setObject:(sender.text ?: @"")
                                              forKey:self.model.storeKey];
}

- (BOOL)textFieldShouldReturn:(UITextField*)textField {
    [textField resignFirstResponder];
    return YES;
}

@end
