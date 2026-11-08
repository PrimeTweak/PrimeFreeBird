#import "Common/PFBBundle.h"
#import "Features/Search/PFBAdvancedSearchStyle.h"
#import "Support/HookHelpers.h"
#import "Features/Search/PFBAdvDateCell.h"
#import "Features/Search/PFBAdvField.h"

@implementation PFBAdvDateCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString*)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        _picker = [[UIDatePicker alloc] init];
        _picker.datePickerMode = UIDatePickerModeDate;
        _picker.preferredDatePickerStyle = UIDatePickerStyleCompact;
        [_picker addTarget:self
                      action:@selector(pfbDateChanged:)
            forControlEvents:UIControlEventValueChanged];

        _clearButton = [PFBHitButton buttonWithType:UIButtonTypeSystem];
        [_clearButton setImage:PFBTwitterGlyphFor(@"close_circle_fill", [UIImage systemImageNamed:@"xmark.circle.fill"])
                      forState:UIControlStateNormal];
        _clearButton.tintColor = [UIColor systemGray3Color];
        [_clearButton addTarget:self
                          action:@selector(pfbClearDate)
                forControlEvents:UIControlEventTouchUpInside];

        // The native calendar control at the trailing end, the clear button just before it.
        UIView* row = [[UIView alloc] init];
        _picker.translatesAutoresizingMaskIntoConstraints = NO;
        _clearButton.translatesAutoresizingMaskIntoConstraints = NO;
        [_picker setContentHuggingPriority:UILayoutPriorityRequired
                                   forAxis:UILayoutConstraintAxisHorizontal];
        [_picker setContentHuggingPriority:UILayoutPriorityRequired
                                   forAxis:UILayoutConstraintAxisVertical];
        [row addSubview:_picker];
        [row addSubview:_clearButton];
        [NSLayoutConstraint activateConstraints:@[
            [_picker.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
            [_picker.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
            [_picker.topAnchor
                constraintGreaterThanOrEqualToAnchor:row.topAnchor],
            [_picker.bottomAnchor
                constraintLessThanOrEqualToAnchor:row.bottomAnchor],
            [_clearButton.centerYAnchor
                constraintEqualToAnchor:_picker.centerYAnchor],
            [_clearButton.trailingAnchor
                constraintEqualToAnchor:_picker.leadingAnchor
                               constant:-8.0],
            [_clearButton.widthAnchor constraintEqualToConstant:26.0],
        ]];

        UILabel* name = nil;
        UILabel* example = nil;
        PFBAdvInstallField(self, row, &name, &example);
        _nameLabel = name;
        _exampleLabel = example;
    }
    return self;
}

+ (NSDateFormatter*)pfbFormatter {
    static NSDateFormatter* f = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        f = [[NSDateFormatter alloc] init];
        f.dateFormat = @"yyyy-MM-dd";
        f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    });
    return f;
}

- (void)configureWith:(PFBAdvField*)model {
    self.model = model;
    PFBBundle* bundle = [PFBBundle sharedBundle];
    self.nameLabel.text = [bundle localizedStringForKey:model.labelKey];
    self.picker.accessibilityLabel = self.nameLabel.text;
    self.exampleLabel.text =
        model.exampleKey ? [bundle localizedStringForKey:model.exampleKey] : @"";
    NSString* stored =
        [[NSUserDefaults standardUserDefaults] stringForKey:model.storeKey];
    NSDate* date = stored ? [[PFBAdvDateCell pfbFormatter] dateFromString:stored]
                          : nil;
    // Unset, the dimmed picker shows today, never a date left by another row.
    self.picker.date = date ?: [NSDate date];
    BOOL active = (date != nil);
    self.picker.alpha = active ? 1.0 : 0.45;
    self.clearButton.hidden = !active;
}

- (void)pfbDateChanged:(UIDatePicker*)sender {
    if (!self.model) { return; }
    NSString* s = [[PFBAdvDateCell pfbFormatter] stringFromDate:sender.date];
    [[NSUserDefaults standardUserDefaults] setObject:s
                                              forKey:self.model.storeKey];
    self.picker.alpha = 1.0;
    self.clearButton.hidden = NO;
}

- (void)pfbClearDate {
    if (!self.model) { return; }
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:self.model.storeKey];
    self.picker.date = [NSDate date];
    self.picker.alpha = 0.45;
    self.clearButton.hidden = YES;
}

- (void)traitCollectionDidChange:(UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    PFBAdvThemeLabels(self.nameLabel, self.exampleLabel);
}

@end
