// Twitter's tab editor laid out over the whole page: its message at the top, the bar on a card,
// the hint as three illustrated tips, and Restore to default at the bottom. Twitter keeps the
// editing itself; only the places of its views change.

#import "Support/HookHelpers.h"
#import "Common/PFBBundle.h"

static const void* kPFBEditorCardKey = &kPFBEditorCardKey;
static const void* kPFBEditorTipsKey = &kPFBEditorTipsKey;
static const void* kPFBEditorPickerFrameKey = &kPFBEditorPickerFrameKey;

// The three tips, each a symbol in a circle beside its line.
@interface PFBTabEditorTipsView : UIView
@property (nonatomic, strong) UIFont* font;
@end

@implementation PFBTabEditorTipsView {
    NSArray<UIView*>* _circles;
    NSArray<UILabel*>* _labels;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = NO;
        PFBBundle* bundle = [PFBBundle sharedBundle];
        NSArray<NSArray<NSString*>*>* tips = @[
            @[ @"hand.tap", @"TAB_EDITOR_TIP_CHANGE" ], @[ @"arrow.left.arrow.right", @"TAB_EDITOR_TIP_ARRANGE" ],
            @[ @"plus", @"TAB_EDITOR_TIP_ADD" ]
        ];
        NSMutableArray<UIView*>* circles = [NSMutableArray array];
        NSMutableArray<UILabel*>* labels = [NSMutableArray array];
        UIImageSymbolConfiguration* symbol = [UIImageSymbolConfiguration configurationWithPointSize:15.0
                                                                                            weight:UIImageSymbolWeightMedium];
        for (NSArray<NSString*>* tip in tips) {
            UIView* circle = [[UIView alloc] init];
            circle.backgroundColor = UIColor.tertiarySystemFillColor;
            circle.layer.cornerRadius = 16.0;
            UIImageView* glyph = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:tip[0]
                                                                            withConfiguration:symbol]];
            glyph.tintColor = UIColor.labelColor;
            glyph.contentMode = UIViewContentModeCenter;
            glyph.frame = CGRectMake(0.0, 0.0, 32.0, 32.0);
            [circle addSubview:glyph];
            [self addSubview:circle];
            [circles addObject:circle];
            UILabel* label = [[UILabel alloc] init];
            label.text = [bundle localizedStringForKey:tip[1]];
            label.textColor = UIColor.secondaryLabelColor;
            label.numberOfLines = 2;
            [self addSubview:label];
            [labels addObject:label];
        }
        _circles = circles;
        _labels = labels;
    }
    return self;
}

- (void)setFont:(UIFont*)font {
    if ([font isEqual:_font]) {
        return;
    }
    _font = font;
    for (UILabel* label in _labels) {
        label.font = font;
    }
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = CGRectGetWidth(self.bounds);
    for (NSUInteger i = 0; i < _labels.count; i++) {
        CGFloat y = 44.0 * (CGFloat)i;
        _circles[i].frame = CGRectMake(0.0, y + 6.0, 32.0, 32.0);
        _labels[i].frame = CGRectMake(44.0, y, MAX(0.0, width - 44.0), 44.0);
    }
}

@end

static Ivar PFBEditorIvarNamed(const char* name) {
    Class editor = NSClassFromString(@"_TtC11XNavigation26TabBarEditorViewController");
    return editor ? class_getInstanceVariable(editor, name) : NULL;
}

static id PFBEditorPart(UIViewController* editor, const char* name, Class kind) {
    Ivar ivar = PFBEditorIvarNamed(name);
    id part = ivar ? object_getIvar(editor, ivar) : nil;
    return [part isKindOfClass:kind] ? part : nil;
}

// The picker Twitter anchors to the bar follows the bar, once per frame Twitter gives it. Its
// height, sized by Twitter for a bar at the bottom, is kept to the room left below: its list
// scrolls within.
static void PFBEditorMovePicker(UIViewController* editor, CGFloat delta) {
    UIView* picker = PFBEditorPart(editor, "picker", [UIView class]);
    UIView* page = editor.viewIfLoaded;
    if (!picker.superview || !page || delta == 0.0) {
        return;
    }
    NSValue* placed = objc_getAssociatedObject(picker, kPFBEditorPickerFrameKey);
    if (placed && CGRectEqualToRect(placed.CGRectValue, picker.frame)) {
        return;
    }
    CGRect frame = CGRectOffset(picker.frame, 0.0, delta);
    CGRect bottom = [page convertRect:CGRectMake(0.0, CGRectGetMaxY(page.bounds) - page.safeAreaInsets.bottom - 12.0, 1.0, 1.0)
                               toView:picker.superview];
    if (CGRectGetMaxY(frame) > CGRectGetMinY(bottom)) {
        frame.size.height = MAX(120.0, CGRectGetMinY(bottom) - CGRectGetMinY(frame));
    }
    picker.frame = frame;
    objc_setAssociatedObject(picker, kPFBEditorPickerFrameKey, [NSValue valueWithCGRect:frame],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void PFBEditorLayoutPage(UIViewController* editor) {
    UIView* page = editor.viewIfLoaded;
    UILabel* message = PFBEditorPart(editor, "messageLabel", [UILabel class]);
    UILabel* hint = PFBEditorPart(editor, "hintLabel", [UILabel class]);
    UIView* reset = PFBEditorPart(editor, "resetButton", [UIView class]);
    UIView* bar = PFBEditorPart(editor, "barView", [UIView class]);
    if (!page || !message || !hint || !reset || !bar) {
        PFBCOMPAT_OBSERVE(PFBCompat_custom_tab_bar, @"tab editor page left as Twitter laid it out");
        return;
    }
    PFBCompatReach(PFBCompatPath_tab_editor_page);
    CGRect bounds = page.bounds;
    UIEdgeInsets safe = page.safeAreaInsets;
    CGFloat width = CGRectGetWidth(bounds);

    message.textAlignment = NSTextAlignmentCenter;
    CGFloat messageHeight = ceil([message sizeThatFits:CGSizeMake(width - 40.0, CGFLOAT_MAX)].height);
    message.frame = CGRectMake(20.0, safe.top + 12.0, width - 40.0, messageHeight);

    CGFloat barHeight = bar.intrinsicContentSize.height > 0.0 ? bar.intrinsicContentSize.height : CGRectGetHeight(bar.frame);
    CGRect card = CGRectMake(20.0, CGRectGetMaxY(message.frame) + 20.0, width - 40.0, barHeight + 96.0);
    UIView* cardView = objc_getAssociatedObject(editor, kPFBEditorCardKey);
    if (!cardView) {
        cardView = [[UIView alloc] init];
        cardView.backgroundColor = UIColor.secondarySystemBackgroundColor;
        cardView.layer.cornerRadius = 28.0;
        cardView.layer.cornerCurve = kCACornerCurveContinuous;
        cardView.userInteractionEnabled = NO;
        objc_setAssociatedObject(editor, kPFBEditorCardKey, cardView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (cardView.superview != page) {
        [page insertSubview:cardView atIndex:0];
    }
    cardView.frame = card;

    CGFloat twitterBarY = CGRectGetMinY(bar.frame);
    CGRect barFrame = CGRectMake(32.0, CGRectGetMidY(card) - barHeight / 2.0, width - 64.0, barHeight);
    if (!CGRectEqualToRect(bar.frame, barFrame)) {
        bar.frame = barFrame;
    }
    // While the page slides in or out, the bar sits on its card at once rather than travelling
    // there inside the slide's animation.
    if (editor.transitionCoordinator) {
        for (NSString* key in bar.layer.animationKeys) {
            CAAnimation* animation = [bar.layer animationForKey:key];
            NSString* path = [animation isKindOfClass:[CAPropertyAnimation class]] ? ((CAPropertyAnimation*)animation).keyPath : nil;
            if ([path hasPrefix:@"position"] || [path hasPrefix:@"bounds"]) {
                [bar.layer removeAnimationForKey:key];
            }
        }
    }
    PFBEditorMovePicker(editor, CGRectGetMinY(barFrame) - twitterBarY);

    hint.hidden = YES;
    PFBTabEditorTipsView* tips = objc_getAssociatedObject(editor, kPFBEditorTipsKey);
    if (!tips) {
        tips = [[PFBTabEditorTipsView alloc] initWithFrame:CGRectZero];
        objc_setAssociatedObject(editor, kPFBEditorTipsKey, tips, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (tips.superview != page) {
        [page insertSubview:tips aboveSubview:cardView];
    }
    tips.font = [message.font fontWithSize:15.0];
    tips.frame = CGRectMake(24.0, CGRectGetMaxY(card) + 20.0, width - 48.0, 132.0);

    CGFloat resetHeight = CGRectGetHeight(reset.frame) > 0.0 ? CGRectGetHeight(reset.frame) : 36.0;
    reset.frame = CGRectMake(20.0, CGRectGetMaxY(bounds) - safe.bottom - 12.0 - resetHeight, width - 40.0, resetHeight);
    PFBCOMPAT_ACTION(PFBCompat_custom_tab_bar, @"tab editor page laid out");
}

// Twitter flies a copy of its bar between the tab bar at the bottom and the editor's bar as the
// page comes and goes. With the bar on a card at the top that flight crosses the screen: the copy
// is kept hidden and the editor's own bar shows on its card with the page.
static void PFBEditorGroundFlight(UIViewController* editor) {
    UIView* flight = PFBEditorPart(editor, "tabBarFlight", [UIView class]);
    UIView* bar = PFBEditorPart(editor, "barView", [UIView class]);
    if (!flight) {
        return;
    }
    flight.hidden = YES;
    bar.hidden = NO;
    bar.alpha = 1.0;
    PFBCOMPAT_ACTION(PFBCompat_custom_tab_bar, @"tab editor bar shown on its card");
}

%hook _TtC11XNavigation26TabBarEditorViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    @try {
        PFBEditorGroundFlight((UIViewController*)self);
    } @catch (__unused id exception) {
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    @try {
        PFBEditorGroundFlight((UIViewController*)self);
    } @catch (__unused id exception) {
    }
}

- (void)viewDidLayoutSubviews {
    %orig;
    @try {
        [UIView performWithoutAnimation:^{
          PFBEditorLayoutPage((UIViewController*)self);
        }];
        PFBEditorGroundFlight((UIViewController*)self);
    } @catch (__unused id exception) {
    }
}

%end
