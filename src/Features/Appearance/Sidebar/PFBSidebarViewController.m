// The Sidebar page: its line, the items in the sidebar and the hidden ones as two groups of glass
// tiles, and Twitter's Restore to default on a glass bar in the tab bar's place. A tap moves an item
// to the other group.

#import "Features/Appearance/Sidebar/PFBSidebarViewController.h"
#import "Common/PFBBundle.h"
#import "Features/Appearance/Sidebar/PFBSidebarItems.h"
#import "Settings/Native/PFBShowcase.h"
#import "Settings/PFBSettingsCellStyle.h"
#import "Support/Helpers.h"
#import "Support/HookHelpers.h"
#import "Support/TWHeaders.h"

static const CGFloat kTileHeight = 92.0;
static const CGFloat kTileGap = 10.0;
static const CGFloat kTileInset = 14.0;
static const CGFloat kCardPadding = 12.0;
static const CGFloat kMarkSize = 24.0;
static const CGFloat kTileRadius = 22.0;

// MARK: - Tile

// One item: Twitter's glyph and name on glass with a filled check while it is in the sidebar; a
// fine dashed outline over a veil of the page's ground, and a plus, once hidden.
@interface PFBSidebarTile : UIControl
@property (nonatomic, readonly) NSInteger panelID;
@property (nonatomic) BOOL shown;
- (instancetype)initWithPanel:(NSInteger)panelID;
- (void)applyTheme;
@end

@implementation PFBSidebarTile {
    PFBShowcaseSurface* _surface;
    CAShapeLayer* _outline;
    UIImageView* _glyph;
    UIView* _mark;
    UIImageView* _sign;
    UILabel* _name;
    NSString* _glyphName;
}

- (instancetype)initWithPanel:(NSInteger)panelID {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _panelID = panelID;
        _surface = [[PFBShowcaseSurface alloc] initWithCornerRadius:kTileRadius];
        _surface.userInteractionEnabled = NO;
        [self addSubview:_surface];
        _outline = [CAShapeLayer layer];
        _outline.lineWidth = 0.75;
        _outline.lineDashPattern = @[ @4, @4 ];
        [self.layer addSublayer:_outline];
        _glyph = [[UIImageView alloc] init];
        _glyph.contentMode = UIViewContentModeScaleAspectFit;
        _mark = [[UIView alloc] init];
        _mark.layer.cornerRadius = kMarkSize / 2.0;
        _sign = [[UIImageView alloc] init];
        _sign.contentMode = UIViewContentModeCenter;
        [_mark addSubview:_sign];
        _name = [[UILabel alloc] init];
        _name.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleBold) fontWithSize:16]);
        _name.adjustsFontSizeToFitWidth = YES;
        _name.minimumScaleFactor = 0.75;
        _name.text = [PFBSidebarItems nameForPanel:panelID];
        _glyphName = [PFBSidebarItems glyphForPanel:panelID];
        for (UIView* part in @[ _glyph, _mark, _name ]) {
            part.userInteractionEnabled = NO;
            [self addSubview:part];
        }
        self.isAccessibilityElement = YES;
        self.accessibilityLabel = _name.text;
        self.accessibilityTraits = UIAccessibilityTraitButton;
        _shown = YES;
        [self applyTheme];
    }
    return self;
}

- (void)applyTheme {
    UIImage* glyph = nil;
    if (_glyphName.length && [UIImage respondsToSelector:@selector(tfn_vectorImageNamed:fitsSize:fillColor:)]) {
        glyph = [UIImage tfn_vectorImageNamed:_glyphName fitsSize:CGSizeMake(24, 24) fillColor:[UIColor blackColor]];
    }
    _glyph.image = [glyph imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
                       ?: [UIImage systemImageNamed:@"circle.grid.2x2"];
    [self applyState];
}

- (void)setShown:(BOOL)shown {
    _shown = shown;
    [self applyState];
}

// In the sidebar: glass, ink and the check on the accent. Hidden: the dashed outline and the veil,
// ink at 65 % and a plus in a fine ring.
- (void)applyState {
    UIColor* ink = _shown ? PFBSettingsTextColor() : [PFBSettingsSubtitleColor() colorWithAlphaComponent:0.65];
    _glyph.tintColor = ink;
    _name.textColor = ink;
    _surface.alpha = _shown ? 1.0 : 0.0;
    _outline.opacity = _shown ? 0.0 : 1.0;
    _outline.strokeColor = [PFBSettingsSubtitleColor() colorWithAlphaComponent:0.3].CGColor;
    _outline.fillColor =
        [[[PFBPalette currentBackgroundColor] colorWithAlphaComponent:0.6] resolvedColorWithTraitCollection:self.traitCollection]
            .CGColor;
    _mark.backgroundColor = _shown ? PFBBrandAccentColor() : [UIColor clearColor];
    _mark.layer.borderWidth = _shown ? 0.0 : 1.0;
    _mark.layer.borderColor = [[UIColor separatorColor] resolvedColorWithTraitCollection:self.traitCollection].CGColor;
    _sign.image = [UIImage systemImageNamed:_shown ? @"checkmark" : @"plus"
                          withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:11
                                                                                            weight:UIImageSymbolWeightBold]];
    _sign.tintColor = _shown ? [UIColor whiteColor] : ink;
    self.accessibilityValue = [[PFBBundle sharedBundle] localizedStringForKey:_shown ? @"SIDEBAR_ITEM_SHOWN" : @"SIDEBAR_ITEM_HIDDEN"];
}

- (void)traitCollectionDidChange:(UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self applyTheme];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat height = CGRectGetHeight(self.bounds);
    _surface.frame = self.bounds;
    _outline.frame = self.bounds;
    _outline.path = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(self.bounds, 0.375, 0.375) cornerRadius:kTileRadius].CGPath;
    BOOL rtl = self.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    CGFloat textWidth = MAX(0, width - 2 * kTileInset);
    CGRect glyph = CGRectMake(kTileInset, kTileInset, 24, 24);
    CGRect mark = CGRectMake(width - kTileInset - kMarkSize, kTileInset, kMarkSize, kMarkSize);
    CGFloat line = ceil(_name.font.lineHeight);
    CGRect name = CGRectMake(kTileInset, height - kTileInset - line, textWidth, line);
    if (rtl) {
        glyph.origin.x = width - CGRectGetMaxX(glyph);
        mark.origin.x = width - CGRectGetMaxX(mark);
    }
    _name.textAlignment = rtl ? NSTextAlignmentRight : NSTextAlignmentLeft;
    _glyph.frame = glyph;
    _mark.frame = mark;
    _sign.frame = _mark.bounds;
    _name.frame = name;
}

// A press shrinks the tile a little, as the page's capsules do.
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
@interface PFBSidebarGroup : NSObject
@property (nonatomic, strong) UILabel* title;
@property (nonatomic, strong) UILabel* count;
@property (nonatomic, strong) UIView* card;
@end

@implementation PFBSidebarGroup
@end

@interface PFBSidebarViewController ()
@property (nonatomic, strong) UIScrollView* scroll;
@property (nonatomic, strong) UILabel* introLabel;
@property (nonatomic, strong) PFBSidebarGroup* shownGroup;
@property (nonatomic, strong) PFBSidebarGroup* hiddenGroup;
@property (nonatomic, strong) NSArray<PFBSidebarTile*>* tiles;
@property (nonatomic, strong) PFBShowcaseButton* resetCapsule;
@property (nonatomic, strong) UISelectionFeedbackGenerator* feedback;
@end

@implementation PFBSidebarViewController

- (PFBSidebarGroup*)groupTitled:(NSString*)key {
    PFBSidebarGroup* group = [[PFBSidebarGroup alloc] init];
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
    [self.view addSubview:self.scroll];

    self.introLabel = PFBShowcaseIntroLabel();
    self.introLabel.text = [bundle localizedStringForKey:@"SIDEBAR_EDITOR_DETAIL"];
    [self.scroll addSubview:self.introLabel];
    self.shownGroup = [self groupTitled:@"SIDEBAR_SECTION_SHOWN"];
    self.hiddenGroup = [self groupTitled:@"SIDEBAR_SECTION_HIDDEN"];

    self.resetCapsule = [PFBShowcaseButton buttonWithStyle:PFBShowcaseButtonStyleGlass];
    self.resetCapsule.label = [bundle localizedTwitterStringForKey:@"SUBSCRIPTION_TAB_CUSTOMIZATION_RESTORE_BUTTON_TITLE"];
    self.resetCapsule.labelFont = PFBScaledFont([TwitterChirpFont(TwitterFontStyleSemibold) fontWithSize:17]);
    [self.resetCapsule addTarget:self action:@selector(resetToDefault) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.resetCapsule];
    self.feedback = [[UISelectionFeedbackGenerator alloc] init];

    [self buildTiles];
    [self applyColors];
}

// The tiles are built as the page opens, in the sidebar's order; a tap moves one to the other
// group, where it keeps that order.
- (void)buildTiles {
    for (PFBSidebarTile* tile in self.tiles) {
        [tile removeFromSuperview];
    }
    // The tab bar's panels are known once the sidebar has asked for them.
    if (![PFBSidebarItems tabPanelIDs].count) {
        PFBDashRefresh();
    }
    NSMutableArray<PFBSidebarTile*>* tiles = [NSMutableArray array];
    for (NSNumber* panel in [PFBSidebarItems panelsForPage]) {
        PFBSidebarTile* tile = [[PFBSidebarTile alloc] initWithPanel:panel.integerValue];
        [tile addTarget:self action:@selector(tileTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.scroll addSubview:tile];
        [tiles addObject:tile];
    }
    self.tiles = tiles;
    [self refreshStates];
    [self.view setNeedsLayout];
}

- (void)refreshStates {
    for (PFBSidebarTile* tile in self.tiles) {
        tile.shown = ![PFBSidebarItems isHidden:tile.panelID];
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshStates];
    [self.view setNeedsLayout];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.view setNeedsLayout];
}

- (void)moveTilesAnimated:(void (^)(void))change {
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

- (void)tileTapped:(PFBSidebarTile*)tile {
    BOOL show = !tile.shown;
    [self.feedback selectionChanged];
    [PFBSidebarItems setPanel:tile.panelID hidden:!show];
    [self.scroll bringSubviewToFront:tile];
    [self moveTilesAnimated:^{
      tile.shown = show;
    }];
}

- (void)resetToDefault {
    [PFBSidebarItems resetToDefault];
    [self.feedback selectionChanged];
    [self moveTilesAnimated:^{
      [self refreshStates];
    }];
}

- (void)applyColors {
    self.view.backgroundColor = [PFBPalette currentBackgroundColor];
    self.introLabel.textColor = PFBSettingsSubtitleColor();
    for (PFBSidebarGroup* group in @[ self.shownGroup, self.hiddenGroup ]) {
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

// One group at the given height: its title and count, then its tiles two to a row on its card,
// mirrored right to left. An empty group folds away. Returns the height below it.
- (CGFloat)layoutGroup:(PFBSidebarGroup*)group tiles:(NSArray<PFBSidebarTile*>*)tiles top:(CGFloat)top {
    CGFloat width = CGRectGetWidth(self.scroll.bounds);
    CGFloat side = 20.0;
    CGFloat inner = MAX(0, width - 2 * side);
    BOOL rtl = self.view.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    group.count.text = [NSNumberFormatter localizedStringFromNumber:@(tiles.count) numberStyle:NSNumberFormatterNoStyle];
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

    CGFloat tileWidth = floor((inner - 2 * kCardPadding - kTileGap) / 2.0);
    NSUInteger rows = (tiles.count + 1) / 2;
    CGFloat cardTop = top + headerHeight + 10.0;
    CGFloat cardHeight = rows ? 2 * kCardPadding + rows * kTileHeight + (rows - 1) * kTileGap : 0;
    group.card.frame = CGRectMake(side, cardTop, inner, cardHeight);
    for (NSUInteger index = 0; index < tiles.count; index++) {
        NSUInteger column = rtl ? 1 - index % 2 : index % 2;
        CGFloat x = side + kCardPadding + column * (tileWidth + kTileGap);
        CGFloat y = cardTop + kCardPadding + (index / 2) * (kTileHeight + kTileGap);
        tiles[index].bounds = CGRectMake(0, 0, tileWidth, kTileHeight);
        tiles[index].center = CGPointMake(x + tileWidth / 2.0, y + kTileHeight / 2.0);
    }
    CGFloat alpha = tiles.count ? 1.0 : 0.0;
    group.title.alpha = alpha;
    group.count.alpha = alpha;
    group.card.alpha = alpha;
    return tiles.count ? CGRectGetMaxY(group.card.frame) + 24.0 : top;
}

- (void)layoutPage {
    CGFloat width = CGRectGetWidth(self.scroll.bounds);
    CGFloat side = 20.0;
    CGFloat inner = MAX(0, width - 2 * side);
    CGFloat introHeight = ceil([self.introLabel sizeThatFits:CGSizeMake(inner, CGFLOAT_MAX)].height);
    self.introLabel.frame = CGRectMake(side, 12.0, inner, introHeight);
    NSMutableArray<PFBSidebarTile*>* shown = [NSMutableArray array];
    NSMutableArray<PFBSidebarTile*>* hidden = [NSMutableArray array];
    for (PFBSidebarTile* tile in self.tiles) {
        if (tile.shown) {
            [shown addObject:tile];
        } else {
            [hidden addObject:tile];
        }
    }
    CGFloat bottom = [self layoutGroup:self.shownGroup tiles:shown top:CGRectGetMaxY(self.introLabel.frame) + 20.0];
    bottom = [self layoutGroup:self.hiddenGroup tiles:hidden top:bottom];
    self.scroll.contentSize = CGSizeMake(width, bottom);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutPage];

    // The tiles scroll under the glass bar and stop clear of it.
    self.resetCapsule.frame = PFBShowcaseDockFrame(self.view);
    UIEdgeInsets insets = self.scroll.contentInset;
    insets.bottom = MAX(0, CGRectGetMaxY(self.view.bounds) - self.view.safeAreaInsets.bottom -
                               CGRectGetMinY(self.resetCapsule.frame) + 16.0);
    if (fabs(insets.bottom - self.scroll.contentInset.bottom) > 0.5) {
        self.scroll.contentInset = insets;
    }
}

@end
