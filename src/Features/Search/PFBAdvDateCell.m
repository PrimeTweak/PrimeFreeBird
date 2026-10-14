#import "Common/PFBBundle.h"
#import "Debug/PFBProbe.h"
#import "Features/Search/PFBAdvancedSearchStyle.h"
#import "Support/HookHelpers.h"
#import "Features/Search/PFBAdvDateCell.h"
#import "Features/Search/PFBAdvField.h"

// Probe: one opening of a date picker, from EditingDidBegin to EditingDidEnd: whether a value
// arrived and whether the row is active afterwards (11#F038).
static BOOL gPFBAdvProbeDateWatching = NO;
static BOOL gPFBAdvProbeDateOpen = NO;
static BOOL gPFBAdvProbeDateChanged = NO;
static BOOL gPFBAdvProbeDateWasActive = NO;
static NSDate* gPFBAdvProbeDateShown = nil;

static BOOL pfbAdvProbeDateStored(PFBAdvDateCell* cell) {
    NSString* key = cell.model.storeKey;
    return key && [[NSUserDefaults standardUserDefaults] stringForKey:key] != nil;
}

static void pfbAdvProbeDateBegan(PFBAdvDateCell* cell) {
    if (!cell) {
        return;
    }
    gPFBAdvProbeDateOpen = YES;
    gPFBAdvProbeDateChanged = NO;
    gPFBAdvProbeDateWasActive = pfbAdvProbeDateStored(cell);
    gPFBAdvProbeDateShown = cell.picker.date;
}

// Probe: notes the opening once the picker closes, a moment later, since a value can arrive
// just after the close.
static void pfbAdvProbeDateEnded(PFBAdvDateCell* cell) {
    if (!cell || !gPFBAdvProbeDateOpen) {
        return;
    }
    BOOL wasActive = gPFBAdvProbeDateWasActive;
    NSDate* shown = gPFBAdvProbeDateShown;
    __weak PFBAdvDateCell* weakCell = cell;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        PFBAdvDateCell* strongCell = weakCell;
        gPFBAdvProbeDateOpen = NO;
        NSString* key = wasActive ? @"11#F038 date picker on a stored date" : @"11#F038 date picker";
        if (!strongCell || !PFBProbeWants(key)) {
            return;
        }
        BOOL sameDay = shown && [[NSCalendar currentCalendar] isDate:strongCell.picker.date inSameDayAsDate:shown];
        PFBProbeNote(key, @"11#F038 date picker %@: opened and closed, value changed %@, row active %@ (row %@ when opened, %@ day at close, stored %@, alpha %.2f)",
                     strongCell.model.labelKey ?: @"?", gPFBAdvProbeDateChanged ? @"yes" : @"no",
                     strongCell.picker.alpha >= 1.0 ? @"yes" : @"no", wasActive ? @"active" : @"dimmed",
                     sameDay ? @"same" : @"another", pfbAdvProbeDateStored(strongCell) ? @"yes" : @"no",
                     strongCell.picker.alpha);
    });
}

// Probe: watches the picker's opening and closing while the measurement is open (11#F038).
static void pfbAdvProbeWatchDatePicker(PFBAdvDateCell* cell, UIDatePicker* picker) {
    if (!PFBProbeWants(@"11#F038 date picker")) {
        return;
    }
    gPFBAdvProbeDateWatching = YES;
    __weak PFBAdvDateCell* weakCell = cell;
    UIAction* began = [UIAction actionWithHandler:^(__kindof UIAction* action) {
        pfbAdvProbeDateBegan(weakCell);
    }];
    UIAction* ended = [UIAction actionWithHandler:^(__kindof UIAction* action) {
        pfbAdvProbeDateEnded(weakCell);
    }];
    [picker addAction:began forControlEvents:UIControlEventEditingDidBegin];
    [picker addAction:ended forControlEvents:UIControlEventEditingDidEnd];
}

// Probe: a value from the picker; noted alone when no opening came before it (11#F038).
static void pfbAdvProbeDateValue(void) {
    if (!gPFBAdvProbeDateWatching) {
        return;
    }
    if (gPFBAdvProbeDateOpen) {
        gPFBAdvProbeDateChanged = YES;
        return;
    }
    if (PFBProbeWants(@"11#F038 date picker events")) {
        PFBProbeNote(@"11#F038 date picker events", @"11#F038 date picker: a value arrived with no EditingDidBegin before it");
    }
}

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
        pfbAdvProbeWatchDatePicker(self, _picker);

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
    pfbAdvProbeDateValue();
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
