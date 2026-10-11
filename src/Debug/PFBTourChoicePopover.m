#import "Common/PFBCompatibility.h"
#import "Support/TwitterChirpFont.h"
#import "Support/HookHelpers.h"
#import "Debug/PFBTourChoicePopover.h"

@implementation PFBTourChoicePopover

static const CGFloat kPFBTourChoiceRowHeight = 52.0;
static const CGFloat kPFBTourChoiceTop = 18.0;
static const CGFloat kPFBTourChoiceGap = 6.0;
static const CGFloat kPFBTourChoiceBottom = 6.0;
static const CGFloat kPFBTourChoiceInset = 20.0;
static const CGFloat kPFBTourChoiceGlyph = 24.0;
static const CGFloat kPFBTourChoiceSpacing = 14.0;

static NSString* PFBTourChoiceTitle(BOOL full) {
    return full ? @"Full tour" : @"Remaining";
}

static UIFont* PFBTourChoiceFont(void) {
    return PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:17]);
}

// A plain glyph in the text color, like Twitter's own menu rows.
- (UIButton*)rowForFullTour:(BOOL)full enabled:(BOOL)enabled {
    UIButton* row = [UIButton buttonWithType:UIButtonTypeCustom];
    row.tag = full;
    row.enabled = enabled;
    row.accessibilityLabel = PFBTourChoiceTitle(full);
    row.translatesAutoresizingMaskIntoConstraints = NO;

    UIImageSymbolConfiguration* glyphSize =
        [UIImageSymbolConfiguration configurationWithPointSize:18.0 weight:UIImageSymbolWeightRegular];
    UIImageView* glyph =
        [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:(full ? @"map" : @"scope")
                                                    withConfiguration:glyphSize]];
    glyph.contentMode = UIViewContentModeCenter;
    glyph.tintColor = enabled ? [UIColor labelColor] : [UIColor tertiaryLabelColor];
    glyph.userInteractionEnabled = NO;
    glyph.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel* label = [[UILabel alloc] init];
    label.text = row.accessibilityLabel;
    label.font = PFBTourChoiceFont();
    label.textColor = enabled ? [UIColor labelColor] : [UIColor secondaryLabelColor];
    label.userInteractionEnabled = NO;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:glyph];
    [row addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [row.heightAnchor constraintEqualToConstant:kPFBTourChoiceRowHeight],
        [glyph.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:kPFBTourChoiceInset],
        [glyph.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [glyph.widthAnchor constraintEqualToConstant:kPFBTourChoiceGlyph],
        [label.leadingAnchor constraintEqualToAnchor:glyph.trailingAnchor constant:kPFBTourChoiceSpacing],
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:row.trailingAnchor constant:-kPFBTourChoiceInset],
        [label.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
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
    title.text = @"Check paths";
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
    CGFloat textStart = kPFBTourChoiceInset + kPFBTourChoiceGlyph + kPFBTourChoiceSpacing;
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
        [divider.leadingAnchor constraintEqualToAnchor:area.leadingAnchor constant:textStart],
        [divider.trailingAnchor constraintEqualToAnchor:area.trailingAnchor],
        [divider.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
    ]];
    // Sized to its content: the widest of the title and the two rows, with even margins.
    CGFloat rows = MAX([PFBTourChoiceTitle(YES) sizeWithAttributes:@{NSFontAttributeName : PFBTourChoiceFont()}].width,
                       [PFBTourChoiceTitle(NO) sizeWithAttributes:@{NSFontAttributeName : PFBTourChoiceFont()}].width);
    CGFloat width = MAX([title.text sizeWithAttributes:@{NSFontAttributeName : title.font}].width + 2.0 * kPFBTourChoiceInset,
                        textStart + rows + kPFBTourChoiceInset);
    CGFloat height = kPFBTourChoiceTop + ceil(title.font.lineHeight) + kPFBTourChoiceGap +
                     2.0 * kPFBTourChoiceRowHeight + kPFBTourChoiceBottom;
    self.preferredContentSize = CGSizeMake(ceil(MAX(width, 220.0)), height);
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
