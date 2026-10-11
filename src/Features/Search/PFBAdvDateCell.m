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

        _clearButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_clearButton setImage:PFBTwitterGlyphFor(@"close_circle_fill", [UIImage systemImageNamed:@"xmark.circle.fill"])
                      forState:UIControlStateNormal];
        _clearButton.tintColor = [UIColor systemGray3Color];
        [_clearButton addTarget:self
                          action:@selector(pfbClearDate)
                forControlEvents:UIControlEventTouchUpInside];

        // Compact row: the native calendar capsule anchored to the RIGHT
        // (the iOS Settings pattern), the clear × just left of it, nothing
        // stretched — the box stays as tight as every other field.
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
            [row.heightAnchor constraintEqualToConstant:36.0],
            [_clearButton.centerYAnchor
                constraintEqualToAnchor:_picker.centerYAnchor],
            [_clearButton.trailingAnchor
                constraintEqualToAnchor:_picker.leadingAnchor
                               constant:-8.0],
            [_clearButton.widthAnchor constraintEqualToConstant:26.0],
        ]];

        UILabel* example = nil;
        _floatLabel = PFBAdvInstallBox(self, row, &example);
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
    self.floatLabel.text = [bundle localizedStringForKey:model.labelKey];
    self.exampleLabel.text =
        model.exampleKey ? [bundle localizedStringForKey:model.exampleKey] : @"";
    NSString* stored =
        [[NSUserDefaults standardUserDefaults] stringForKey:model.storeKey];
    NSDate* date = stored ? [[PFBAdvDateCell pfbFormatter] dateFromString:stored]
                          : nil;
    if (date) { self.picker.date = date; }
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
    self.picker.alpha = 0.45;
    self.clearButton.hidden = YES;
}

@end
