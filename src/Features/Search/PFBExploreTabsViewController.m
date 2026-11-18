// The Tabs page: its line, the sample of Explore on its card, the kept tabs and the hidden ones as
// two groups of chips, two hints, and Twitter's Restore to default on a glass bar in the tab bar's
// place. A tap moves a tab to the other group; the last tab kept stays.

#import "Features/Search/PFBExploreTabsViewController.h"
#import "Common/PFBBundle.h"
#import "Common/PFBSettings.h"
#import "Features/Search/PFBExplorePreviewView.h"
#import "Settings/Native/PFBShowcase.h"
#import "Settings/PFBModernSettingsPageViewController.h"
#import "Settings/PFBModernSettingsSessionCardCell.h"
#import "Settings/PFBSettingsCellStyle.h"
#import "Support/HookHelpers.h"

// The chips of Filters › Languages: 36 pt capsules, 17 pt of room around the name, 8 pt apart.
static const CGFloat kChipHeight = 36.0;
static const CGFloat kChipPadding = 17.0;
static const CGFloat kChipGap = 8.0;
static const CGFloat kChipPlus = 18.0;
static const CGFloat kCardPadding = 12.0;

// MARK: - Chip

// One tab: its name on glass while Explore keeps it; a fine dashed outline over a veil of the page's
// ground, and a plus, once hidden, as the Menu page's tiles.
@interface PFBExploreTabChip : UIControl
@property (nonatomic, copy, readonly) NSString* key;
@property (nonatomic) BOOL shown;
- (instancetype)initWithKey:(NSString*)key name:(NSString*)name;
- (CGFloat)fittingWidth;
- (void)applyTheme;
@end

@implementation PFBExploreTabChip {
    PFBShowcaseSurface* _surface;
    CAShapeLayer* _outline;
    UIImageView* _plus;
    UILabel* _name;
}

- (instancetype)initWithKey:(NSString*)key name:(NSString*)name {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _key = [key copy];
        _surface = [[PFBShowcaseSurface alloc] initWithCornerRadius:-1];
        _surface.userInteractionEnabled = NO;
        [self addSubview:_surface];
        _outline = [CAShapeLayer layer];
        _outline.lineWidth = 0.75;
        _outline.lineDashPattern = @[ @4, @4 ];
        [self.layer addSublayer:_outline];
        _plus = [[UIImageView alloc] init];
        _plus.contentMode = UIViewContentModeCenter;
        _name = [[UILabel alloc] init];
        _name.text = name;
        for (UIView* part in @[ _plus, _name ]) {
            part.userInteractionEnabled = NO;
            [self addSubview:part];
        }
        self.isAccessibilityElement = YES;
        self.accessibilityLabel = name;
        self.accessibilityTraits = UIAccessibilityTraitButton;
        _shown = YES;
        [self applyTheme];
    }
    return self;
}

- (void)setShown:(BOOL)shown {
    _shown = shown;
    [self applyTheme];
    [self setNeedsLayout];
}

- (void)applyTheme {
    UIColor* ink = _shown ? PFBSettingsTextColor() : [PFBSettingsSubtitleColor() colorWithAlphaComponent:0.65];
    _name.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:15]);
    _name.textColor = ink;
    _surface.alpha = _shown ? 1.0 : 0.0;
    _outline.opacity = _shown ? 0.0 : 1.0;
    _outline.strokeColor = [PFBSettingsSubtitleColor() colorWithAlphaComponent:0.3].CGColor;
    _outline.fillColor =
        [[[PFBPalette currentBackgroundColor] colorWithAlphaComponent:0.6] resolvedColorWithTraitCollection:self.traitCollection]
            .CGColor;
    _plus.hidden = _shown;
    _plus.image = [UIImage systemImageNamed:@"plus"
                          withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:12
                                                                                            weight:UIImageSymbolWeightMedium]];
    _plus.tintColor = ink;
    self.accessibilityValue = [[PFBBundle sharedBundle] localizedStringForKey:_shown ? @"SIDEBAR_ITEM_SHOWN" : @"SIDEBAR_ITEM_HIDDEN"];
}

- (void)traitCollectionDidChange:(UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self applyTheme];
}

- (CGFloat)fittingWidth {
    CGFloat name = ceil([_name sizeThatFits:CGSizeMake(CGFLOAT_MAX, kChipHeight)].width);
    return name + 2 * kChipPadding + (_shown ? 0 : kChipPlus);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    CGFloat width = CGRectGetWidth(bounds);
    CGFloat height = CGRectGetHeight(bounds);
    _surface.frame = bounds;
    _outline.frame = bounds;
    _outline.path = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(bounds, 0.375, 0.375) cornerRadius:height / 2.0].CGPath;
    BOOL rtl = self.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    CGFloat start = kChipPadding;
    CGRect plus = CGRectMake(start - 4.0, 0, kChipPlus, height);
    if (!_shown) {
        start += kChipPlus;
    }
    CGRect name = CGRectMake(start, 0, MAX(0, width - start - kChipPadding), height);
    if (rtl) {
        plus.origin.x = width - CGRectGetMaxX(plus);
        name.origin.x = width - CGRectGetMaxX(name);
    }
    _plus.frame = plus;
    _name.frame = name;
}

// A press shrinks the chip a little, as the page's capsules do.
- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    [UIView animateWithDuration:0.15
                     animations:^{
                       self.transform = highlighted ? CGAffineTransformMakeScale(0.96, 0.96) : CGAffineTransformIdentity;
                     }];
}

@end

// MARK: - Page

// A group's title and its count, over its card.
@interface PFBExploreTabsGroup : NSObject
@property (nonatomic, strong) UILabel* title;
@property (nonatomic, strong) UILabel* count;
@property (nonatomic, strong) UIView* card;
@end

@implementation PFBExploreTabsGroup
@end

@interface PFBExploreTabsViewController ()
@property (nonatomic, strong) UIScrollView* scroll;
@property (nonatomic, strong) UILabel* introLabel;
@property (nonatomic, strong) UIView* previewCard;
@property (nonatomic, strong) PFBExplorePreviewView* preview;
@property (nonatomic, strong) PFBExploreTabsGroup* shownGroup;
@property (nonatomic, strong) PFBExploreTabsGroup* hiddenGroup;
@property (nonatomic, strong) NSArray<PFBExploreTabChip*>* chips;
@property (nonatomic, copy) NSArray<PFBShowcaseHintRow*>* hints;
@property (nonatomic, strong) PFBShowcaseButton* resetCapsule;
@property (nonatomic, strong) UISelectionFeedbackGenerator* feedback;
@property (nonatomic, strong) UINotificationFeedbackGenerator* refusal;
@end

@implementation PFBExploreTabsViewController

- (PFBExploreTabsGroup*)groupTitled:(NSString*)key {
    PFBExploreTabsGroup* group = [[PFBExploreTabsGroup alloc] init];
    group.title = [[UILabel alloc] init];
    group.title.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleSemibold) fontWithSize:15]);
    group.title.text = [[PFBBundle sharedBundle] localizedStringForKey:key];
    group.count = [[UILabel alloc] init];
    group.count.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:15]);
    group.card = PFBShowcaseCard();
    for (UIView* part in @[ group.card, group.title, group.count ]) {
        [self.scroll addSubview:part];
    }
    return group;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    PFBBundle* bundle = [PFBBundle sharedBundle];
    self.navigationController.navigationBar.prefersLargeTitles = NO;
    self.scroll = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.scroll.alwaysBounceVertical = YES;
    self.scroll.showsVerticalScrollIndicator = NO;
    [self.view addSubview:self.scroll];

    self.introLabel = PFBShowcaseIntroLabel();
    [self.scroll addSubview:self.introLabel];
    self.previewCard = PFBShowcaseCard();
    self.preview = [[PFBExplorePreviewView alloc] init];
    [self.previewCard addSubview:self.preview];
    [self.scroll addSubview:self.previewCard];
    __weak PFBExplorePreviewView* preview = self.preview;
    [PFBModernSettingsSessionCardCell fetchAvatarFromURL:self.account ? PFBAccountAvatarURL(self.account) : nil
                                              completion:^(UIImage* photo) {
                                                [preview showReaderPhoto:photo];
                                              }];
    self.shownGroup = [self groupTitled:@"EXPLORE_TABS_SECTION_SHOWN"];
    self.hiddenGroup = [self groupTitled:@"SIDEBAR_SECTION_HIDDEN"];

    NSMutableArray<PFBExploreTabChip*>* chips = [NSMutableArray array];
    for (NSString* key in PFBExploreTabKeys()) {
        NSString* name = [bundle localizedStringForKey:[NSString stringWithFormat:@"%@_TAB_NAME", key.uppercaseString]];
        PFBExploreTabChip* chip = [[PFBExploreTabChip alloc] initWithKey:key name:name];
        [chip addTarget:self action:@selector(chipTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.scroll addSubview:chip];
        [chips addObject:chip];
    }
    self.chips = chips;

    self.hints = @[
        [[PFBShowcaseHintRow alloc] initWithSymbol:@"hand.tap" text:[bundle localizedStringForKey:@"EXPLORE_TABS_HINT_TAP"]],
        [[PFBShowcaseHintRow alloc] initWithSymbol:@"eye.slash" text:[bundle localizedStringForKey:@"EXPLORE_TABS_KEEP_ONE"]],
    ];
    for (PFBShowcaseHintRow* hint in self.hints) {
        [self.scroll addSubview:hint];
    }

    self.resetCapsule = [PFBShowcaseButton buttonWithStyle:PFBShowcaseButtonStyleGlass];
    self.resetCapsule.label = [bundle localizedTwitterStringForKey:@"SUBSCRIPTION_TAB_CUSTOMIZATION_RESTORE_BUTTON_TITLE"];
    self.resetCapsule.labelFont = PFBScaledFont([TwitterChirpFont(TwitterFontStyleSemibold) fontWithSize:17]);
    [self.resetCapsule addTarget:self action:@selector(resetToDefault) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.resetCapsule];
    self.feedback = [[UISelectionFeedbackGenerator alloc] init];
    self.refusal = [[UINotificationFeedbackGenerator alloc] init];

    [self refreshStates];
    [self applyColors];
}

// Each chip as stored, the sample with the tabs kept, and the page held while all tabs are hidden.
- (void)refreshStates {
    NSMutableArray<NSString*>* kept = [NSMutableArray array];
    for (PFBExploreTabChip* chip in self.chips) {
        chip.shown = ![PFBSettings boolForKey:chip.key];
        if (chip.shown) {
            [kept addObject:chip.accessibilityLabel];
        }
    }
    [self.preview showTabs:kept];
    BOOL held = [PFBSettings boolForKey:@"hide_explore_all"];
    PFBBundle* bundle = [PFBBundle sharedBundle];
    self.introLabel.text = [bundle localizedStringForKey:held ? @"EXPLORE_TABS_DETAIL_HELD" : @"EXPLORE_TABS_DETAIL"];
    NSArray<UIView*>* fixedParts = @[ self.previewCard, self.resetCapsule ];
    for (UIView* part in [fixedParts arrayByAddingObjectsFromArray:self.chips]) {
        part.alpha = held ? 0.4 : 1.0;
        part.userInteractionEnabled = !held;
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshStates];
    [self.view setNeedsLayout];
}

// Twitter's tab bar settles once the page is in: the capsule is placed again then.
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.view setNeedsLayout];
}

- (void)moveChipsAnimated:(void (^)(void))change {
    [UIView animateWithDuration:0.5
                          delay:0
         usingSpringWithDamping:0.82
          initialSpringVelocity:0.2
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
                       change();
                       [self layoutPage];
                     }
                     completion:nil];
}

// The last tab kept stays: Explore would have nothing to show, and hiding it all is an option of its
// own. The chip shakes instead, as the hint under it says.
- (void)chipTapped:(PFBExploreTabChip*)chip {
    if (chip.shown) {
        NSUInteger kept = 0;
        for (PFBExploreTabChip* other in self.chips) {
            kept += other.shown ? 1 : 0;
        }
        if (kept <= 1) {
            [self.refusal notificationOccurred:UINotificationFeedbackTypeWarning];
            CAKeyframeAnimation* nudge = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
            nudge.values = @[ @0, @(-4), @4, @(-2), @0 ];
            nudge.duration = 0.32;
            [chip.layer addAnimation:nudge forKey:@"pfbRefuse"];
            return;
        }
    }
    [self.feedback selectionChanged];
    [[NSUserDefaults standardUserDefaults] setBool:chip.shown forKey:chip.key];
    [self.scroll bringSubviewToFront:chip];
    [self moveChipsAnimated:^{
      [self refreshStates];
    }];
}

// The tweak's defaults again, as on a fresh install.
- (void)resetToDefault {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    for (NSString* key in PFBExploreTabKeys()) {
        [defaults removeObjectForKey:key];
    }
    [self.feedback selectionChanged];
    [self moveChipsAnimated:^{
      [self refreshStates];
    }];
}

- (void)applyColors {
    self.view.backgroundColor = [PFBPalette currentBackgroundColor];
    self.introLabel.textColor = PFBSettingsSubtitleColor();
    for (PFBExploreTabsGroup* group in @[ self.shownGroup, self.hiddenGroup ]) {
        group.title.textColor = PFBSettingsTextColor();
        group.count.textColor = PFBSettingsSubtitleColor();
    }
}

- (void)traitCollectionDidChange:(UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        [self applyColors];
    }
}

// One group at the given height: its title and count, then its chips flowed from the leading edge
// on its card, mirrored right to left. An empty group folds away. Returns the height below it.
- (CGFloat)layoutGroup:(PFBExploreTabsGroup*)group chips:(NSArray<PFBExploreTabChip*>*)chips top:(CGFloat)top {
    CGFloat width = CGRectGetWidth(self.scroll.bounds);
    CGFloat side = 20.0;
    CGFloat inner = MAX(0, width - 2 * side);
    BOOL rtl = self.view.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    group.count.text = [NSNumberFormatter localizedStringFromNumber:@(chips.count) numberStyle:NSNumberFormatterNoStyle];
    CGFloat headerHeight = ceil(group.title.font.lineHeight);
    CGFloat countWidth = ceil([group.count sizeThatFits:CGSizeMake(inner, headerHeight)].width);
    CGRect title = CGRectMake(side + 4.0, top, MAX(0, inner - 16.0 - countWidth), headerHeight);
    CGRect count = CGRectMake(side + inner - 4.0 - countWidth, top, countWidth, headerHeight);
    if (rtl) {
        title.origin.x = width - CGRectGetMaxX(title);
        count.origin.x = width - CGRectGetMaxX(count);
    }
    group.title.textAlignment = rtl ? NSTextAlignmentRight : NSTextAlignmentLeft;
    group.title.frame = title;
    group.count.frame = count;

    CGFloat cardTop = top + headerHeight + 10.0;
    CGFloat room = MAX(0, inner - 2 * kCardPadding);
    CGFloat x = 0;
    CGFloat y = 0;
    for (PFBExploreTabChip* chip in chips) {
        CGFloat chipWidth = MIN(room, [chip fittingWidth]);
        if (x > 0 && x + chipWidth > room) {
            x = 0;
            y += kChipHeight + kChipGap;
        }
        CGRect frame = CGRectMake(side + kCardPadding + x, cardTop + kCardPadding + y, chipWidth, kChipHeight);
        if (rtl) {
            frame.origin.x = width - CGRectGetMaxX(frame);
        }
        chip.bounds = CGRectMake(0, 0, chipWidth, kChipHeight);
        chip.center = CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame));
        x += chipWidth + kChipGap;
    }
    CGFloat cardHeight = chips.count ? 2 * kCardPadding + y + kChipHeight : 0;
    group.card.frame = CGRectMake(side, cardTop, inner, cardHeight);
    CGFloat alpha = chips.count ? 1.0 : 0.0;
    group.title.alpha = alpha;
    group.count.alpha = alpha;
    group.card.alpha = alpha;
    return chips.count ? CGRectGetMaxY(group.card.frame) + 24.0 : top;
}

- (void)layoutPage {
    CGFloat width = CGRectGetWidth(self.scroll.bounds);
    CGFloat side = 20.0;
    CGFloat inner = MAX(0, width - 2 * side);
    CGFloat introHeight = ceil([self.introLabel sizeThatFits:CGSizeMake(inner, CGFLOAT_MAX)].height);
    self.introLabel.frame = CGRectMake(side, 12.0, inner, introHeight);
    CGFloat previewHeight = [self.preview sizeThatFits:CGSizeMake(inner, CGFLOAT_MAX)].height;
    self.preview.frame = CGRectMake(0, 0, inner, previewHeight);
    self.previewCard.frame = CGRectMake(side, CGRectGetMaxY(self.introLabel.frame) + 20.0, inner, previewHeight);
    NSMutableArray<PFBExploreTabChip*>* shown = [NSMutableArray array];
    NSMutableArray<PFBExploreTabChip*>* hidden = [NSMutableArray array];
    for (PFBExploreTabChip* chip in self.chips) {
        [(chip.shown ? shown : hidden) addObject:chip];
    }
    CGFloat bottom = [self layoutGroup:self.shownGroup chips:shown top:CGRectGetMaxY(self.previewCard.frame) + 24.0];
    bottom = [self layoutGroup:self.hiddenGroup chips:hidden top:bottom];
    bottom = PFBShowcaseLayoutHints(self.hints, bottom, width);
    self.scroll.contentSize = CGSizeMake(width, bottom + 24.0);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutPage];

    // The page scrolls under the glass bar and stops clear of it.
    self.resetCapsule.frame = PFBShowcaseDockFrame(self.view);
    UIEdgeInsets insets = self.scroll.contentInset;
    insets.bottom = MAX(0, CGRectGetMaxY(self.view.bounds) - self.view.safeAreaInsets.bottom -
                               CGRectGetMinY(self.resetCapsule.frame) + 16.0);
    if (fabs(insets.bottom - self.scroll.contentInset.bottom) > 0.5) {
        self.scroll.contentInset = insets;
    }
}

@end
