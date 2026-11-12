// The Sidebar page: its line, the sidebar's items as glass tiles on a card, the tab bar's apart,
// and Twitter's Restore to default at the bottom. A tap hides an item or shows it again.

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

// MARK: - Tile

// One item: Twitter's glyph and name on glass, with a filled check while it shows and an empty
// ring once hidden; an item of the tab bar shows dimmed, without a check.
@interface PFBSidebarTile : UIControl
@property (nonatomic, readonly) NSInteger panelID;
@property (nonatomic, readonly) BOOL fixed;
@property (nonatomic) BOOL shown;
- (instancetype)initWithPanel:(NSInteger)panelID fixed:(BOOL)fixed;
- (void)setShown:(BOOL)shown animated:(BOOL)animated;
- (void)applyTheme;
@end

@implementation PFBSidebarTile {
    PFBShowcaseSurface* _surface;
    UIImageView* _glyph;
    UIView* _mark;
    UIImageView* _check;
    UILabel* _name;
    NSString* _glyphName;
}

- (instancetype)initWithPanel:(NSInteger)panelID fixed:(BOOL)fixed {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _panelID = panelID;
        _fixed = fixed;
        _surface = [[PFBShowcaseSurface alloc] initWithCornerRadius:22.0];
        _surface.userInteractionEnabled = NO;
        [self addSubview:_surface];
        _glyph = [[UIImageView alloc] init];
        _glyph.contentMode = UIViewContentModeScaleAspectFit;
        _mark = [[UIView alloc] init];
        _mark.layer.cornerRadius = kMarkSize / 2.0;
        _mark.hidden = fixed;
        _check = [[UIImageView alloc] init];
        _check.contentMode = UIViewContentModeCenter;
        _check.image = [UIImage systemImageNamed:@"checkmark"
                               withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:11
                                                                                                 weight:UIImageSymbolWeightBold]];
        [_mark addSubview:_check];
        _name = [[UILabel alloc] init];
        _name.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleBold) fontWithSize:16]);
        _name.adjustsFontSizeToFitWidth = YES;
        _name.minimumScaleFactor = 0.75;
        _name.text = [PFBSidebarItems nameForPanel:panelID];
        _glyphName = [PFBSidebarItems glyphForPanel:panelID];
        for (UIView* part in @[ _glyph, _mark, _name ]) {
            part.userInteractionEnabled = NO;
            [_surface.contentView addSubview:part];
        }
        self.isAccessibilityElement = YES;
        self.accessibilityLabel = _name.text;
        self.accessibilityTraits = fixed ? UIAccessibilityTraitNotEnabled : UIAccessibilityTraitButton;
        self.userInteractionEnabled = !fixed;
        _shown = YES;
        [self applyTheme];
    }
    return self;
}

- (void)applyTheme {
    UIColor* ink = PFBSettingsTextColor();
    _name.textColor = ink;
    UIImage* glyph = nil;
    if (_glyphName.length && [UIImage respondsToSelector:@selector(tfn_vectorImageNamed:fitsSize:fillColor:)]) {
        glyph = [UIImage tfn_vectorImageNamed:_glyphName fitsSize:CGSizeMake(24, 24) fillColor:[UIColor blackColor]];
    }
    _glyph.image = [glyph imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
                       ?: [UIImage systemImageNamed:@"circle.grid.2x2"];
    _glyph.tintColor = ink;
    [self applyState];
}

- (void)setShown:(BOOL)shown {
    [self setShown:shown animated:NO];
}

- (void)setShown:(BOOL)shown animated:(BOOL)animated {
    _shown = shown;
    if (!animated) {
        [self applyState];
        return;
    }
    [UIView animateWithDuration:0.35
                          delay:0
         usingSpringWithDamping:0.7
          initialSpringVelocity:0.4
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
                       [self applyState];
                     }
                     completion:nil];
}

// Shown: the check on the accent; hidden: an empty ring and the content faded.
- (void)applyState {
    CGFloat content = _fixed ? 0.5 : (_shown ? 1.0 : 0.38);
    _glyph.alpha = content;
    _name.alpha = content;
    _mark.backgroundColor = _shown ? PFBBrandAccentColor() : [UIColor clearColor];
    _mark.layer.borderWidth = _shown ? 0.0 : 1.5;
    _mark.layer.borderColor = [[UIColor separatorColor] resolvedColorWithTraitCollection:self.traitCollection].CGColor;
    _check.tintColor = [UIColor whiteColor];
    _check.alpha = _shown ? 1.0 : 0.0;
    PFBBundle* bundle = [PFBBundle sharedBundle];
    self.accessibilityValue = _fixed ? nil
                                     : [bundle localizedStringForKey:_shown ? @"SIDEBAR_ITEM_SHOWN" : @"SIDEBAR_ITEM_HIDDEN"];
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
    BOOL rtl = self.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    CGRect glyph = CGRectMake(kTileInset, kTileInset, 24, 24);
    CGRect mark = CGRectMake(width - kTileInset - kMarkSize, kTileInset, kMarkSize, kMarkSize);
    CGFloat line = ceil(_name.font.lineHeight);
    CGRect name = CGRectMake(kTileInset, height - kTileInset - line, MAX(0, width - 2 * kTileInset), line);
    if (rtl) {
        glyph.origin.x = width - CGRectGetMaxX(glyph);
        mark.origin.x = width - CGRectGetMaxX(mark);
        _name.textAlignment = NSTextAlignmentRight;
    } else {
        _name.textAlignment = NSTextAlignmentLeft;
    }
    _glyph.frame = glyph;
    _mark.frame = mark;
    _check.frame = _mark.bounds;
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

@interface PFBSidebarViewController ()
@property (nonatomic, strong) UIScrollView* scroll;
@property (nonatomic, strong) UILabel* introLabel;
@property (nonatomic, strong) UIView* itemsCard;
@property (nonatomic, strong) UILabel* tabHeader;
@property (nonatomic, strong) UIView* tabCard;
@property (nonatomic, strong) NSArray<PFBSidebarTile*>* tiles;
@property (nonatomic, strong) NSArray<PFBSidebarTile*>* tabTiles;
@property (nonatomic, strong) PFBShowcaseButton* resetCapsule;
@property (nonatomic, strong) UISelectionFeedbackGenerator* feedback;
@end

@implementation PFBSidebarViewController

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
    self.itemsCard = PFBShowcaseCard();
    self.tabHeader = [[UILabel alloc] init];
    self.tabHeader.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleSemibold) fontWithSize:15]);
    self.tabHeader.text = [bundle localizedStringForKey:@"SIDEBAR_EDITOR_TAB_BAR_HEADER"];
    self.tabCard = PFBShowcaseCard();
    for (UIView* part in @[ self.introLabel, self.itemsCard, self.tabHeader, self.tabCard ]) {
        [self.scroll addSubview:part];
    }

    self.resetCapsule = [PFBShowcaseButton buttonWithStyle:PFBShowcaseButtonStyleOutline];
    self.resetCapsule.label = [bundle localizedTwitterStringForKey:@"SUBSCRIPTION_TAB_CUSTOMIZATION_RESTORE_BUTTON_TITLE"];
    [self.resetCapsule addTarget:self action:@selector(resetToDefault) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.resetCapsule];
    self.feedback = [[UISelectionFeedbackGenerator alloc] init];

    [self buildTiles];
    [self applyColors];
}

// The tiles are built as the page opens and stay put while it shows, so an item shown again
// keeps its place; only their state follows the changes.
- (void)buildTiles {
    for (PFBSidebarTile* tile in [self.tiles arrayByAddingObjectsFromArray:self.tabTiles ?: @[]]) {
        [tile removeFromSuperview];
    }
    // The tab bar's panels are known once the sidebar has asked for them.
    if (![PFBSidebarItems tabPanelIDs].count) {
        PFBDashRefresh();
    }
    NSMutableArray<PFBSidebarTile*>* tiles = [NSMutableArray array];
    for (NSNumber* panel in [PFBSidebarItems panelsForPage]) {
        PFBSidebarTile* tile = [[PFBSidebarTile alloc] initWithPanel:panel.integerValue fixed:NO];
        [tile addTarget:self action:@selector(tileTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.itemsCard addSubview:tile];
        [tiles addObject:tile];
    }
    NSMutableArray<PFBSidebarTile*>* tabTiles = [NSMutableArray array];
    for (NSNumber* panel in [PFBSidebarItems tabPanelIDs]) {
        if ([PFBSidebarItems nameForPanel:panel.integerValue]) {
            PFBSidebarTile* tile = [[PFBSidebarTile alloc] initWithPanel:panel.integerValue fixed:YES];
            [self.tabCard addSubview:tile];
            [tabTiles addObject:tile];
        }
    }
    self.tiles = tiles;
    self.tabTiles = tabTiles;
    self.tabHeader.hidden = tabTiles.count == 0;
    self.tabCard.hidden = tabTiles.count == 0;
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
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.view setNeedsLayout];
}

- (void)tileTapped:(PFBSidebarTile*)tile {
    BOOL show = !tile.shown;
    [self.feedback selectionChanged];
    [tile setShown:show animated:YES];
    [PFBSidebarItems setPanel:tile.panelID hidden:!show];
}

- (void)resetToDefault {
    [PFBSidebarItems resetToDefault];
    [self.feedback selectionChanged];
    for (PFBSidebarTile* tile in self.tiles) {
        [tile setShown:![PFBSidebarItems isHidden:tile.panelID] animated:YES];
    }
}

- (void)applyColors {
    self.view.backgroundColor = [PFBPalette currentBackgroundColor];
    self.resetCapsule.groundColor = self.view.backgroundColor;
    self.introLabel.textColor = PFBSettingsSubtitleColor();
    self.tabHeader.textColor = PFBSettingsSubtitleColor();
}

- (void)traitCollectionDidChange:(UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        [self applyColors];
    }
}

// Two tiles to a row, mirrored right to left; returns the grid's height.
- (CGFloat)layoutTiles:(NSArray<PFBSidebarTile*>*)tiles width:(CGFloat)width {
    CGFloat tileWidth = floor((width - 2 * kCardPadding - kTileGap) / 2.0);
    BOOL rtl = self.view.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    for (NSUInteger index = 0; index < tiles.count; index++) {
        NSUInteger column = rtl ? 1 - index % 2 : index % 2;
        CGFloat x = kCardPadding + column * (tileWidth + kTileGap);
        CGFloat y = kCardPadding + (index / 2) * (kTileHeight + kTileGap);
        tiles[index].bounds = CGRectMake(0, 0, tileWidth, kTileHeight);
        tiles[index].center = CGPointMake(x + tileWidth / 2.0, y + kTileHeight / 2.0);
    }
    NSUInteger rows = (tiles.count + 1) / 2;
    return rows ? 2 * kCardPadding + rows * kTileHeight + (rows - 1) * kTileGap : 0;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = CGRectGetWidth(self.scroll.bounds);
    CGFloat side = 20.0;
    CGFloat inner = MAX(0, width - 2 * side);
    CGFloat introHeight = ceil([self.introLabel sizeThatFits:CGSizeMake(inner, CGFLOAT_MAX)].height);
    self.introLabel.frame = CGRectMake(side, 12.0, inner, introHeight);
    CGFloat itemsHeight = [self layoutTiles:self.tiles width:inner];
    self.itemsCard.frame = CGRectMake(side, CGRectGetMaxY(self.introLabel.frame) + 20.0, inner, itemsHeight);
    CGFloat bottom = CGRectGetMaxY(self.itemsCard.frame);
    if (self.tabTiles.count) {
        CGFloat headerHeight = ceil(self.tabHeader.font.lineHeight);
        self.tabHeader.frame = CGRectMake(side + 4.0, bottom + 24.0, inner - 8.0, headerHeight);
        CGFloat tabHeight = [self layoutTiles:self.tabTiles width:inner];
        self.tabCard.frame = CGRectMake(side, CGRectGetMaxY(self.tabHeader.frame) + 10.0, inner, tabHeight);
        bottom = CGRectGetMaxY(self.tabCard.frame);
    }
    self.scroll.contentSize = CGSizeMake(width, bottom + 24.0);

    // Above Twitter's tab bar when it shows; the page scrolls clear of the capsule.
    CGFloat capsuleHeight = [self.resetCapsule sizeThatFits:CGSizeMake(inner, CGFLOAT_MAX)].height;
    CGFloat capsuleY = PFBShowcaseBottomLimit(self.view) - 16.0 - capsuleHeight;
    self.resetCapsule.frame = CGRectMake(side, capsuleY, inner, capsuleHeight);
    UIEdgeInsets insets = self.scroll.contentInset;
    insets.bottom = MAX(0, CGRectGetMaxY(self.view.bounds) - self.view.safeAreaInsets.bottom - capsuleY + 12.0);
    if (fabs(insets.bottom - self.scroll.contentInset.bottom) > 0.5) {
        self.scroll.contentInset = insets;
    }
}

@end
