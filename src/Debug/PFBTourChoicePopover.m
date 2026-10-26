#import "Common/PFBCompatibility.h"
#import "Support/TwitterChirpFont.h"
#import "Settings/PFBSettingsCellStyle.h"
#import "Debug/PFBTourChoicePopover.h"

@implementation PFBTourChoicePopover

static const CGFloat kPFBTourChoiceTop = 18.0;
static const CGFloat kPFBTourChoiceGap = 4.0;
static const CGFloat kPFBTourChoiceBottom = 6.0;
static const CGFloat kPFBTourChoiceInset = 20.0;
// Above a choice's title and below its line.
static const CGFloat kPFBTourChoicePad = 11.0;
static const CGFloat kPFBTourChoiceLineGap = 2.0;

static NSString* PFBTourChoiceTitle(BOOL full) {
    return full ? @"All screens" : @"Remaining screens";
}

// What a tour covers: every screen, or those still to check.
static NSString* PFBTourChoiceLine(BOOL full) {
    NSUInteger screens = PFBCompatTourScreens(full);
    if (full) {
        return [NSString stringWithFormat:@"%lu screen%@", (unsigned long)screens, screens == 1 ? @"" : @"s"];
    }
    return screens ? [NSString stringWithFormat:@"%lu left", (unsigned long)screens] : @"Nothing left";
}

static UILabel* PFBTourChoiceLabel(NSString* text, UIFont* font, UIColor* color) {
    UILabel* label = [[UILabel alloc] init];
    label.text = text;
    label.font = font;
    label.textColor = color;
    label.userInteractionEnabled = NO;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

// A choice drawn as the report's rows draw theirs: the title in bold, what it covers in gray.
- (UIButton*)rowForFullTour:(BOOL)full enabled:(BOOL)enabled {
    UIButton* row = [UIButton buttonWithType:UIButtonTypeCustom];
    row.tag = full;
    row.enabled = enabled;
    row.accessibilityLabel = PFBTourChoiceTitle(full);
    row.accessibilityValue = PFBTourChoiceLine(full);
    row.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel* title = PFBTourChoiceLabel(PFBTourChoiceTitle(full), PFBSettingsTitleFont(),
                                        enabled ? [UIColor labelColor] : PFBSettingsSubtitleColor());
    UILabel* line = PFBTourChoiceLabel(PFBTourChoiceLine(full), PFBSettingsDetailFont(), PFBSettingsSubtitleColor());
    [row addSubview:title];
    [row addSubview:line];
    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:row.topAnchor constant:kPFBTourChoicePad],
        [title.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:kPFBTourChoiceInset],
        [title.trailingAnchor constraintLessThanOrEqualToAnchor:row.trailingAnchor constant:-kPFBTourChoiceInset],
        [line.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:kPFBTourChoiceLineGap],
        [line.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [line.trailingAnchor constraintLessThanOrEqualToAnchor:row.trailingAnchor constant:-kPFBTourChoiceInset],
        [line.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-kPFBTourChoicePad],
    ]];
    [row addTarget:self action:@selector(rowTouched:) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
    [row addTarget:self
                  action:@selector(rowReleased:)
        forControlEvents:UIControlEventTouchDragExit | UIControlEventTouchCancel | UIControlEventTouchUpOutside];
    [row addTarget:self action:@selector(rowChosen:) forControlEvents:UIControlEventTouchUpInside];
    return row;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // The popover draws its own material: an opaque view would flatten it.
    self.view.backgroundColor = [UIColor clearColor];

    UILabel* title = [[UILabel alloc] init];
    title.text = @"Check options";
    title.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleBold) fontWithSize:20]);
    title.textColor = [UIColor labelColor];
    title.accessibilityTraits = UIAccessibilityTraitHeader;
    title.translatesAutoresizingMaskIntoConstraints = NO;
    UIButton* full = [self rowForFullTour:YES enabled:YES];
    UIButton* left = [self rowForFullTour:NO enabled:PFBCompatTourScreens(NO) > 0];
    UIView* divider = [[UIView alloc] init];
    divider.backgroundColor = [UIColor separatorColor];
    divider.translatesAutoresizingMaskIntoConstraints = NO;
    for (UIView* view in @[ title, full, left, divider ]) {
        [self.view addSubview:view];
    }
    UILayoutGuide* area = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:area.topAnchor constant:kPFBTourChoiceTop],
        [title.leadingAnchor constraintEqualToAnchor:area.leadingAnchor constant:kPFBTourChoiceInset],
        [title.trailingAnchor constraintLessThanOrEqualToAnchor:area.trailingAnchor constant:-kPFBTourChoiceInset],
        [full.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:kPFBTourChoiceGap],
        [full.leadingAnchor constraintEqualToAnchor:area.leadingAnchor],
        [full.trailingAnchor constraintEqualToAnchor:area.trailingAnchor],
        [left.topAnchor constraintEqualToAnchor:full.bottomAnchor],
        [left.leadingAnchor constraintEqualToAnchor:area.leadingAnchor],
        [left.trailingAnchor constraintEqualToAnchor:area.trailingAnchor],
        [divider.topAnchor constraintEqualToAnchor:full.bottomAnchor],
        [divider.leadingAnchor constraintEqualToAnchor:area.leadingAnchor constant:kPFBTourChoiceInset],
        [divider.trailingAnchor constraintEqualToAnchor:area.trailingAnchor],
        [divider.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
    ]];
    // Sized to its content: the widest of the title and the choices, with even margins.
    UIFont* rowFont = PFBSettingsTitleFont();
    UIFont* lineFont = PFBSettingsDetailFont();
    CGFloat widest = [title.text sizeWithAttributes:@{NSFontAttributeName : title.font}].width;
    for (NSNumber* tour in @[ @YES, @NO ]) {
        widest = MAX(widest, [PFBTourChoiceTitle(tour.boolValue) sizeWithAttributes:@{NSFontAttributeName : rowFont}].width);
        widest = MAX(widest, [PFBTourChoiceLine(tour.boolValue) sizeWithAttributes:@{NSFontAttributeName : lineFont}].width);
    }
    CGFloat rowHeight = 2.0 * kPFBTourChoicePad + ceil(rowFont.lineHeight) + kPFBTourChoiceLineGap + ceil(lineFont.lineHeight);
    CGFloat height = kPFBTourChoiceTop + ceil(title.font.lineHeight) + kPFBTourChoiceGap + 2.0 * rowHeight +
                     kPFBTourChoiceBottom;
    self.preferredContentSize = CGSizeMake(ceil(MAX(widest + 2.0 * kPFBTourChoiceInset, 220.0)), ceil(height));
}

- (void)rowTouched:(UIButton*)row {
    row.backgroundColor = [[UIColor labelColor] colorWithAlphaComponent:0.06];
}

- (void)rowReleased:(UIButton*)row {
    row.backgroundColor = [UIColor clearColor];
}

- (void)rowChosen:(UIButton*)row {
    BOOL full = row.tag == 1;
    void (^chosen)(BOOL) = self.chosen;
    [self dismissViewControllerAnimated:YES
                             completion:^{
                               if (chosen) {
                                   chosen(full);
                               }
                             }];
}

// Without this a popover becomes a full-screen sheet on iPhone.
- (UIModalPresentationStyle)adaptivePresentationStyleForPresentationController:(UIPresentationController*)controller
                                                               traitCollection:(UITraitCollection*)traitCollection {
    return UIModalPresentationNone;
}

@end
