// A small Explore screen laid out by hand on the Tabs page's card, as the Accent page's sample is.

#import "Features/Search/PFBExplorePreviewView.h"
#import "Common/PFBBundle.h"
#import "Common/PFBSettings.h"
#import "Settings/Native/PFBShowcase.h"
#import "Settings/PFBSettingsCellStyle.h"
#import "Support/Helpers.h"
#import "Support/HookHelpers.h"
#import "Support/PFBManager.h"

// The margin around the screen, its top bar and tab row, a trend's padding, and the tab bar that the
// compose button's size matches.
static const CGFloat kPFBExploreInset = 10.0;
static const CGFloat kPFBExploreTopBar = 44.0;
static const CGFloat kPFBExploreTabs = 40.0;
static const CGFloat kPFBExplorePadding = 12.0;
static const CGFloat kPFBExploreField = 30.0;
static const CGFloat kPFBExploreTabGap = 32.0;
static const CGFloat kPFBExploreTrendGap = 8.0;
static const CGFloat kPFBExploreBarHeight = 56.0;
static const CGFloat kPFBExploreGlyph = 24.0;

// A Twitter glyph in one color, or none where the app cannot draw it.
static UIImage* PFBExploreGlyph(NSString* name, CGFloat size, UIColor* color) {
    if (![UIImage respondsToSelector:@selector(tfn_vectorImageNamed:fitsSize:fillColor:)]) {
        return nil;
    }
    return [UIImage tfn_vectorImageNamed:name fitsSize:CGSizeMake(size, size) fillColor:color];
}

static CGRect PFBExploreMirrored(CGRect frame, CGFloat width, BOOL rtl) {
    if (rtl) {
        frame.origin.x = width - CGRectGetMaxX(frame);
    }
    return frame;
}

@implementation PFBExplorePreviewView {
    UIView* _screen;
    UIView* _reader;
    UIImageView* _readerPhoto;
    UIView* _field;
    UIImageView* _fieldGlyph;
    UILabel* _fieldText;
    UIImageView* _gear;
    UIView* _tabRow;
    NSArray<UILabel*>* _tabs;
    UIView* _underline;
    UIView* _divider;
    NSArray<NSArray<UILabel*>*>* _trends;
    NSArray<UIImageView*>* _trendMore;
    PFBShowcaseSurface* _bar;
    UIView* _pill;
    NSArray<UIImageView*>* _barTabs;
    UIView* _compose;
    UIImageView* _composeGlyph;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = NO;
        self.accessibilityElementsHidden = YES;
        _screen = [[UIView alloc] init];
        _screen.layer.cornerRadius = 20.0;
        _screen.layer.cornerCurve = kCACornerCurveContinuous;
        _screen.layer.borderWidth = 0.5;
        _screen.clipsToBounds = YES;
        [self addSubview:_screen];

        _reader = [[UIView alloc] init];
        _reader.layer.cornerRadius = 13.0;
        _reader.clipsToBounds = YES;
        _readerPhoto = [[UIImageView alloc] init];
        _readerPhoto.contentMode = UIViewContentModeScaleAspectFill;
        _readerPhoto.alpha = 0;
        _readerPhoto.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [_reader addSubview:_readerPhoto];
        _field = [[UIView alloc] init];
        _field.layer.cornerRadius = kPFBExploreField / 2.0;
        _fieldGlyph = [[UIImageView alloc] init];
        _fieldGlyph.contentMode = UIViewContentModeCenter;
        _fieldText = [[UILabel alloc] init];
        _fieldText.text = [[PFBBundle sharedBundle] localizedTwitterStringForKey:@"TAB_BAR_SEARCH_ACCESSIBILITY_ACTION"];
        [_field addSubview:_fieldGlyph];
        [_field addSubview:_fieldText];
        _gear = [[UIImageView alloc] init];
        _gear.contentMode = UIViewContentModeCenter;
        _tabRow = [[UIView alloc] init];
        _tabRow.clipsToBounds = YES;
        _underline = [[UIView alloc] init];
        _underline.layer.cornerRadius = 2.0;
        [_tabRow addSubview:_underline];
        _divider = [[UIView alloc] init];
        for (UIView* part in @[ _reader, _field, _gear, _tabRow, _divider ]) {
            [_screen addSubview:part];
        }

        // Two trends as Explore lists them: Twitter's Trending over the topic, then its post count.
        PFBBundle* bundle = [PFBBundle sharedBundle];
        NSString* kicker = [bundle localizedTwitterStringForKey:@"TRENDS_TITLE"];
        NSString* format = [bundle localizedTwitterStringForKey:@"TWEETS_COUNT_TITLE_FORMAT"];
        NSMutableArray<NSArray<UILabel*>*>* trends = [NSMutableArray array];
        NSMutableArray<UIImageView*>* more = [NSMutableArray array];
        NSArray<NSArray*>* samples = @[ @[ @"#PrimeFreeBird", @1204 ], @[ @"Liquid Glass", @8312 ] ];
        for (NSArray* sample in samples) {
            NSString* count = [NSNumberFormatter localizedStringFromNumber:sample[1]
                                                               numberStyle:NSNumberFormatterDecimalStyle];
            NSMutableArray<UILabel*>* lines = [NSMutableArray array];
            for (NSString* text in @[ kicker, sample[0], [format stringByReplacingOccurrencesOfString:@"%@" withString:count] ]) {
                UILabel* line = [[UILabel alloc] init];
                line.text = text;
                [_screen addSubview:line];
                [lines addObject:line];
            }
            [trends addObject:lines];
            UIImageView* dots = [[UIImageView alloc] init];
            dots.contentMode = UIViewContentModeCenter;
            [_screen addSubview:dots];
            [more addObject:dots];
        }
        _trends = trends;
        _trendMore = more;

        _bar = [[PFBShowcaseSurface alloc] initWithCornerRadius:-1];
        _pill = [[UIView alloc] init];
        [_bar.contentView addSubview:_pill];
        NSMutableArray<UIImageView*>* barTabs = [NSMutableArray array];
        for (NSUInteger i = 0; i < 4; i++) {
            UIImageView* tab = [[UIImageView alloc] init];
            tab.contentMode = UIViewContentModeCenter;
            [_bar.contentView addSubview:tab];
            [barTabs addObject:tab];
        }
        _barTabs = barTabs;
        _compose = [[UIView alloc] init];
        _compose.layer.cornerRadius = kPFBExploreBarHeight / 2.0;
        _compose.layer.shadowOpacity = 0.3f;
        _compose.layer.shadowRadius = 8.0;
        _compose.layer.shadowOffset = CGSizeMake(0, 3);
        _composeGlyph = [[UIImageView alloc] init];
        _composeGlyph.contentMode = UIViewContentModeCenter;
        [_compose addSubview:_composeGlyph];
        [_screen addSubview:_bar];
        [_screen addSubview:_compose];
        _tabs = @[];
        [self applyTheme];
    }
    return self;
}

- (void)showTabs:(NSArray<NSString*>*)names {
    for (UILabel* tab in _tabs) {
        [tab removeFromSuperview];
    }
    NSMutableArray<UILabel*>* tabs = [NSMutableArray array];
    for (NSString* name in names) {
        UILabel* tab = [[UILabel alloc] init];
        tab.text = name;
        [_tabRow addSubview:tab];
        [tabs addObject:tab];
    }
    _tabs = tabs;
    _underline.hidden = tabs.count == 0;
    [self applyTheme];
}

// The first tab and its line take the accent where Selected tab does, as Search does in the bar;
// vector glyphs bake in their color, so they are drawn again on every change.
- (void)applyTheme {
    UITraitCollection* traits = self.traitCollection;
    UIColor* ink = [PFBSettingsTextColor() resolvedColorWithTraitCollection:traits];
    UIColor* gray = [PFBSettingsSubtitleColor() resolvedColorWithTraitCollection:traits];
    UIColor* ground = [[PFBPalette currentBackgroundColor] resolvedColorWithTraitCollection:traits];
    UIColor* line = [PFBSettingsDividerColor() resolvedColorWithTraitCollection:traits];
    UIColor* accent = [PFBBrandAccentColor() resolvedColorWithTraitCollection:traits];
    UIColor* chosen = PFBThemedTabBarWanted() ? accent : ink;
    _screen.backgroundColor = ground;
    _screen.layer.borderColor = line.CGColor;
    _reader.backgroundColor = [UIColor tertiarySystemFillColor];
    _field.backgroundColor = [PFBSettingsFaintColor() resolvedColorWithTraitCollection:traits];
    _fieldGlyph.image = PFBExploreGlyph(@"search_stroke", 14.0, gray);
    _fieldText.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:14]);
    _fieldText.textColor = gray;
    _gear.image = PFBExploreGlyph(@"settings_stroke", 20.0, ink);
    UIFont* tabFont = PFBScaledFont([TwitterChirpFont(TwitterFontStyleSemibold) fontWithSize:15]);
    for (NSUInteger i = 0; i < _tabs.count; i++) {
        _tabs[i].font = tabFont;
        _tabs[i].textColor = i == 0 ? ink : gray;
    }
    _underline.backgroundColor = chosen;
    _divider.backgroundColor = line;
    UIFont* small = PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:13]);
    UIFont* topic = PFBScaledFont([TwitterChirpFont(TwitterFontStyleSemibold) fontWithSize:15]);
    for (NSArray<UILabel*>* lines in _trends) {
        for (NSUInteger i = 0; i < lines.count; i++) {
            lines[i].font = i == 1 ? topic : small;
            lines[i].textColor = i == 1 ? ink : gray;
        }
    }
    for (UIImageView* dots in _trendMore) {
        dots.image = PFBExploreGlyph(@"more_vertical", 16.0, gray);
    }
    _pill.backgroundColor = [UIColor tertiarySystemFillColor];
    NSArray<NSString*>* glyphs = @[ @"home_stroke", @"search", @"notifications_stroke", @"chat_bubble_stroke" ];
    for (NSUInteger i = 0; i < _barTabs.count; i++) {
        _barTabs[i].image = PFBExploreGlyph(glyphs[i], kPFBExploreGlyph, i == 1 ? chosen : ink);
    }
    _compose.backgroundColor = accent;
    _compose.layer.shadowColor = accent.CGColor;
    NSString* compose = [PFBSettings boolForKey:@"restore_tweet_button"] ? @"feather" : @"compose";
    _composeGlyph.image = PFBExploreGlyph(compose, kPFBExploreGlyph, [UIColor whiteColor]);
    [self setNeedsLayout];
}

- (void)traitCollectionDidChange:(UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self applyTheme];
}

// A trend's three lines grow with the text size.
- (CGFloat)trendHeight {
    CGFloat height = 0;
    for (UILabel* line in _trends.firstObject) {
        height += ceil(line.font.lineHeight);
    }
    return height;
}

- (CGFloat)tabsHeight {
    return MAX(kPFBExploreTabs, ceil(_tabs.firstObject.font.lineHeight ?: 18.0) + 18.0);
}

- (CGFloat)screenHeight {
    return kPFBExploreTopBar + [self tabsHeight] + kPFBExplorePadding + 2 * [self trendHeight] + kPFBExploreTrendGap +
           2 * kPFBExplorePadding + kPFBExploreBarHeight + kPFBExploreInset;
}

- (CGSize)sizeThatFits:(CGSize)size {
    return CGSizeMake(size.width, 2 * kPFBExploreInset + [self screenHeight]);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    BOOL rtl = self.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    CGFloat width = MAX(0, CGRectGetWidth(self.bounds) - 2 * kPFBExploreInset);
    _screen.frame = CGRectMake(kPFBExploreInset, kPFBExploreInset, width, [self screenHeight]);

    // The top bar: the account's photo, the search field, the settings gear.
    _reader.frame = PFBExploreMirrored(CGRectMake(kPFBExplorePadding, (kPFBExploreTopBar - 26.0) / 2.0, 26.0, 26.0),
                                       width, rtl);
    _readerPhoto.frame = _reader.bounds;
    CGFloat fieldX = kPFBExplorePadding + 26.0 + 10.0;
    CGFloat gearX = width - kPFBExplorePadding - 24.0;
    CGRect field = CGRectMake(fieldX, (kPFBExploreTopBar - kPFBExploreField) / 2.0, MAX(0, gearX - 10.0 - fieldX),
                              kPFBExploreField);
    _field.frame = PFBExploreMirrored(field, width, rtl);
    CGFloat fieldWidth = CGRectGetWidth(field);
    _fieldGlyph.frame = PFBExploreMirrored(CGRectMake(10.0, 0, 16.0, kPFBExploreField), fieldWidth, rtl);
    _fieldText.frame = PFBExploreMirrored(CGRectMake(32.0, 0, MAX(0, fieldWidth - 42.0), kPFBExploreField), fieldWidth, rtl);
    _fieldText.textAlignment = rtl ? NSTextAlignmentRight : NSTextAlignmentLeft;
    _gear.frame = PFBExploreMirrored(CGRectMake(gearX, (kPFBExploreTopBar - 24.0) / 2.0, 24.0, 24.0), width, rtl);

    // The tab row stops at the screen's edge, as Twitter's scrolls; the line sits under the first tab.
    CGFloat tabsHeight = [self tabsHeight];
    _tabRow.frame = CGRectMake(0, kPFBExploreTopBar, width, tabsHeight);
    CGFloat x = kPFBExplorePadding;
    for (NSUInteger i = 0; i < _tabs.count; i++) {
        CGFloat tabWidth = ceil([_tabs[i] sizeThatFits:CGSizeMake(CGFLOAT_MAX, tabsHeight)].width);
        _tabs[i].frame = PFBExploreMirrored(CGRectMake(x, 0, tabWidth, tabsHeight - 4.0), width, rtl);
        if (i == 0) {
            _underline.frame = PFBExploreMirrored(CGRectMake(x, tabsHeight - 4.0, tabWidth, 4.0), width, rtl);
        }
        x += tabWidth + kPFBExploreTabGap;
    }
    _divider.frame = CGRectMake(0, kPFBExploreTopBar + tabsHeight, width, 0.5);

    // The trends, their dots at the trailing edge.
    CGFloat y = kPFBExploreTopBar + tabsHeight + kPFBExplorePadding;
    for (NSUInteger row = 0; row < _trends.count; row++) {
        CGFloat top = y;
        for (UILabel* line in _trends[row]) {
            CGFloat height = ceil(line.font.lineHeight);
            line.frame = PFBExploreMirrored(CGRectMake(kPFBExplorePadding, y, MAX(0, width - 2 * kPFBExplorePadding - 24.0),
                                                       height),
                                            width, rtl);
            line.textAlignment = rtl ? NSTextAlignmentRight : NSTextAlignmentLeft;
            y += height;
        }
        _trendMore[row].frame = PFBExploreMirrored(CGRectMake(width - kPFBExplorePadding - 20.0, top, 20.0, 20.0), width, rtl);
        y += kPFBExploreTrendGap;
    }

    // The bar beside the compose button, Search chosen.
    CGFloat barY = CGRectGetHeight(_screen.bounds) - kPFBExploreInset - kPFBExploreBarHeight;
    CGFloat barWidth = MAX(0, width - 2 * kPFBExploreInset - kPFBExploreBarHeight - 10.0);
    _bar.frame = PFBExploreMirrored(CGRectMake(kPFBExploreInset, barY, barWidth, kPFBExploreBarHeight), width, rtl);
    _compose.frame = PFBExploreMirrored(
        CGRectMake(width - kPFBExploreInset - kPFBExploreBarHeight, barY, kPFBExploreBarHeight, kPFBExploreBarHeight),
        width, rtl);
    _composeGlyph.frame = _compose.bounds;
    CGFloat slot = MAX(0, (barWidth - 8.0) / (CGFloat)_barTabs.count);
    for (NSUInteger i = 0; i < _barTabs.count; i++) {
        _barTabs[i].frame = PFBExploreMirrored(CGRectMake(4.0 + slot * (CGFloat)i, 4.0, slot, kPFBExploreBarHeight - 8.0),
                                               barWidth, rtl);
    }
    _pill.frame = _barTabs[1].frame;
    _pill.layer.cornerRadius = CGRectGetHeight(_pill.frame) / 2.0;
}

- (void)showReaderPhoto:(UIImage*)photo {
    if (!photo) {
        return;
    }
    _readerPhoto.image = photo;
    [UIView animateWithDuration:0.2
                     animations:^{
                       self->_readerPhoto.alpha = 1.0;
                     }];
}

@end
