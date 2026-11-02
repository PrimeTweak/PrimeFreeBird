// A small home screen of Twitter in the accent color, laid out by hand on the Theme color card.

#import "Features/Appearance/ThemeColor/PFBAccentPreviewView.h"
#import "Common/PFBBundle.h"
#import "Common/PFBSettings.h"
#import "Settings/Native/PFBShowcase.h"
#import "Settings/PFBSettingsCellStyle.h"
#import "Support/HookHelpers.h"
#import "Support/PFBManager.h"

// The screen's margin on the card, its top bar and timeline tabs, the Tweet's avatar, padding and
// action row, and the tab bar that the compose button's size matches.
static const CGFloat kPFBPreviewInset = 10.0;
static const CGFloat kPFBPreviewTopBar = 44.0;
static const CGFloat kPFBPreviewTabs = 40.0;
static const CGFloat kPFBPreviewAvatar = 40.0;
static const CGFloat kPFBPreviewPadding = 12.0;
static const CGFloat kPFBPreviewActions = 20.0;
static const CGFloat kPFBPreviewActionGlyph = 18.0;
static const CGFloat kPFBPreviewBarHeight = 56.0;
static const CGFloat kPFBPreviewGlyph = 24.0;
static const CGFloat kPFBPreviewDot = 9.0;

// A Twitter glyph in one color, or none where the app cannot draw it.
static UIImage* PFBPreviewGlyph(NSString* name, CGFloat size, UIColor* color) {
    if (![UIImage respondsToSelector:@selector(tfn_vectorImageNamed:fitsSize:fillColor:)]) {
        return nil;
    }
    return [UIImage tfn_vectorImageNamed:name fitsSize:CGSizeMake(size, size) fillColor:color];
}

// The tweak's bird, ready to take a tint; Twitter's own glyph by that name now draws the X.
static UIImage* PFBPreviewBird(CGFloat size) {
    return [PFBBundlePDFImage(@"LaunchTwitterBird.pdf", CGSizeMake(size, size), 0.86)
        imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

// Turns a left-to-right frame into the view's direction.
static CGRect PFBPreviewMirrored(CGRect frame, CGFloat width, BOOL rtl) {
    if (rtl) {
        frame.origin.x = width - CGRectGetMaxX(frame);
    }
    return frame;
}

@implementation PFBAccentPreviewView {
    UIView* _screen;
    UIView* _reader;
    UIImageView* _logo;
    UILabel* _forYou;
    UILabel* _following;
    UIView* _underline;
    UIView* _divider;
    UIView* _avatar;
    UIImageView* _bird;
    UILabel* _byline;
    UILabel* _text;
    NSArray<UIImageView*>* _actions;
    NSArray<UILabel*>* _counts;
    PFBShowcaseSurface* _bar;
    UIView* _pill;
    NSArray<UIImageView*>* _tabs;
    UIView* _dot;
    UIView* _compose;
    UIImageView* _composeGlyph;
    UIColor* _accent;
    BOOL _tintsSelectedTab;
    BOOL _tintsLogo;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = NO;
        self.accessibilityElementsHidden = YES;
        _accent = [UIColor systemBlueColor];
        _screen = [[UIView alloc] init];
        _screen.layer.cornerRadius = 20.0;
        _screen.layer.cornerCurve = kCACornerCurveContinuous;
        _screen.layer.borderWidth = 0.5;
        [self addSubview:_screen];

        _reader = [[UIView alloc] init];
        _reader.layer.cornerRadius = 13.0;
        _logo = [[UIImageView alloc] init];
        _logo.contentMode = UIViewContentModeCenter;
        PFBBundle* bundle = [PFBBundle sharedBundle];
        _forYou = [[UILabel alloc] init];
        _forYou.text = [bundle localizedTwitterStringForKey:@"HOME_TIMELINE_TITLE"];
        _forYou.textAlignment = NSTextAlignmentCenter;
        _following = [[UILabel alloc] init];
        _following.text = [bundle localizedTwitterStringForKey:@"HOME_TIMELINE_LATEST_TITLE"];
        _following.textAlignment = NSTextAlignmentCenter;
        _underline = [[UIView alloc] init];
        _underline.layer.cornerRadius = 2.0;
        _divider = [[UIView alloc] init];
        _avatar = [[UIView alloc] init];
        _avatar.layer.cornerRadius = kPFBPreviewAvatar / 2.0;
        _bird = [[UIImageView alloc] init];
        _bird.contentMode = UIViewContentModeCenter;
        [_avatar addSubview:_bird];
        _byline = [[UILabel alloc] init];
        _text = [[UILabel alloc] init];
        _text.numberOfLines = 0;
        for (UIView* part in @[ _reader, _logo, _forYou, _following, _underline, _divider, _avatar, _byline, _text ]) {
            [_screen addSubview:part];
        }

        // Reply, Retweet, Like and Views with their counts, then Share.
        NSMutableArray<UIImageView*>* actions = [NSMutableArray array];
        NSMutableArray<UILabel*>* counts = [NSMutableArray array];
        NSArray<NSNumber*>* numbers = @[ @24, @112, @865, @4210 ];
        for (NSUInteger i = 0; i < 5; i++) {
            UIImageView* action = [[UIImageView alloc] init];
            action.contentMode = UIViewContentModeCenter;
            UILabel* count = [[UILabel alloc] init];
            count.adjustsFontSizeToFitWidth = YES;
            count.minimumScaleFactor = 0.7;
            count.text = i < numbers.count ? [NSNumberFormatter localizedStringFromNumber:numbers[i]
                                                                              numberStyle:NSNumberFormatterDecimalStyle]
                                           : nil;
            [_screen addSubview:action];
            [_screen addSubview:count];
            [actions addObject:action];
            [counts addObject:count];
        }
        _actions = actions;
        _counts = counts;

        _bar = [[PFBShowcaseSurface alloc] initWithCornerRadius:-1];
        _pill = [[UIView alloc] init];
        [_bar.contentView addSubview:_pill];
        NSMutableArray<UIImageView*>* tabs = [NSMutableArray array];
        for (NSUInteger i = 0; i < 4; i++) {
            UIImageView* tab = [[UIImageView alloc] init];
            tab.contentMode = UIViewContentModeCenter;
            [_bar.contentView addSubview:tab];
            [tabs addObject:tab];
        }
        _tabs = tabs;
        _dot = [[UIView alloc] init];
        _dot.layer.borderWidth = 1.5;
        _dot.layer.cornerRadius = kPFBPreviewDot / 2.0;
        [_bar.contentView addSubview:_dot];
        _compose = [[UIView alloc] init];
        _compose.layer.cornerRadius = kPFBPreviewBarHeight / 2.0;
        _compose.layer.shadowOpacity = 0.3f;
        _compose.layer.shadowRadius = 8.0;
        _compose.layer.shadowOffset = CGSizeMake(0, 3);
        _composeGlyph = [[UIImageView alloc] init];
        _composeGlyph.contentMode = UIViewContentModeCenter;
        [_compose addSubview:_composeGlyph];
        [_screen addSubview:_bar];
        [_screen addSubview:_compose];
        [self applyTheme];
    }
    return self;
}

- (void)applyAccent:(UIColor*)accent tintsSelectedTab:(BOOL)tintsSelectedTab tintsLogo:(BOOL)tintsLogo {
    _accent = accent;
    _tintsSelectedTab = tintsSelectedTab;
    _tintsLogo = tintsLogo;
    [self applyTheme];
}

// The sample's link, mention and hashtag take the accent; its words keep the text color.
- (NSAttributedString*)sampleText {
    NSString* text = [[PFBBundle sharedBundle] localizedStringForKey:@"THEME_PREVIEW_TWEET"];
    NSMutableAttributedString* sample = [[NSMutableAttributedString alloc]
        initWithString:text
            attributes:@{
                NSFontAttributeName: PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:15]),
                NSForegroundColorAttributeName: PFBSettingsTextColor(),
            }];
    NSRegularExpression* entities = [NSRegularExpression regularExpressionWithPattern:@"[@#]\\w+|[\\w.-]+\\.com\\b"
                                                                              options:0
                                                                                error:nil];
    for (NSTextCheckingResult* match in [entities matchesInString:text options:0 range:NSMakeRange(0, text.length)]) {
        [sample addAttribute:NSForegroundColorAttributeName value:_accent range:match.range];
    }
    return sample;
}

// Vector glyphs bake in their fill color, so they are drawn again on every change.
- (void)applyTheme {
    UITraitCollection* traits = self.traitCollection;
    UIColor* ink = [PFBSettingsTextColor() resolvedColorWithTraitCollection:traits];
    UIColor* gray = [PFBSettingsSubtitleColor() resolvedColorWithTraitCollection:traits];
    UIColor* ground = [[PFBPalette currentBackgroundColor] resolvedColorWithTraitCollection:traits];
    UIColor* line = [PFBSettingsDividerColor() resolvedColorWithTraitCollection:traits];
    UIColor* accent = [_accent resolvedColorWithTraitCollection:traits];
    UIColor* chosen = _tintsSelectedTab ? accent : ink;
    _screen.backgroundColor = ground;
    _screen.layer.borderColor = line.CGColor;
    _reader.backgroundColor = [UIColor tertiarySystemFillColor];
    _logo.image = PFBPreviewBird(28.0);
    _logo.tintColor = _tintsLogo ? accent : ink;
    UIFont* tabFont = PFBScaledFont([TwitterChirpFont(TwitterFontStyleSemibold) fontWithSize:15]);
    _forYou.font = tabFont;
    _forYou.textColor = ink;
    _following.font = tabFont;
    _following.textColor = gray;
    _underline.backgroundColor = chosen;
    _divider.backgroundColor = line;
    _avatar.backgroundColor = ink;
    _bird.image = PFBPreviewBird(24.0);
    _bird.tintColor = ground;
    NSMutableAttributedString* byline = [[NSMutableAttributedString alloc]
        initWithString:@"Twitter"
            attributes:@{
                NSFontAttributeName: PFBScaledFont([TwitterChirpFont(TwitterFontStyleSemibold) fontWithSize:15]),
                NSForegroundColorAttributeName: ink,
            }];
    [byline appendAttributedString:[[NSAttributedString alloc]
                                       initWithString:@" @Twitter"
                                           attributes:@{
                                               NSFontAttributeName: PFBScaledFont(
                                                   [TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:15]),
                                               NSForegroundColorAttributeName: gray,
                                           }]];
    _byline.attributedText = byline;
    _text.attributedText = [self sampleText];
    NSArray<NSString*>* actions = @[ @"reply_stroke", @"retweet_stroke", @"heart_stroke", @"bar_chart", @"share_stroke" ];
    UIFont* countFont = PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:13]);
    for (NSUInteger i = 0; i < _actions.count; i++) {
        _actions[i].image = PFBPreviewGlyph(actions[i], kPFBPreviewActionGlyph, gray);
        _counts[i].font = countFont;
        _counts[i].textColor = gray;
    }
    _pill.backgroundColor = [UIColor tertiarySystemFillColor];
    NSArray<NSString*>* glyphs = @[ @"home", @"search_stroke", @"notifications_stroke", @"chat_bubble_stroke" ];
    for (NSUInteger i = 0; i < _tabs.count; i++) {
        _tabs[i].image = PFBPreviewGlyph(glyphs[i], kPFBPreviewGlyph, i == 0 ? chosen : ink);
    }
    _dot.backgroundColor = accent;
    _dot.layer.borderColor = ground.CGColor;
    _compose.backgroundColor = accent;
    _compose.layer.shadowColor = accent.CGColor;
    NSString* compose = [PFBSettings boolForKey:@"restore_tweet_button"] ? @"feather" : @"compose";
    _composeGlyph.image = PFBPreviewGlyph(compose, kPFBPreviewGlyph, [UIColor whiteColor]);
    [self setNeedsLayout];
}

- (void)traitCollectionDidChange:(UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self applyTheme];
}

// The timeline tabs and the action row grow with the text size.
- (CGFloat)tabsHeight {
    return MAX(kPFBPreviewTabs, ceil(_forYou.font.lineHeight) + 18.0);
}

- (CGFloat)actionsHeight {
    return MAX(kPFBPreviewActions, ceil(_counts.firstObject.font.lineHeight));
}

- (CGFloat)textWidthForScreenWidth:(CGFloat)width {
    return MAX(0, width - 2 * kPFBPreviewPadding - kPFBPreviewAvatar - 10.0);
}

// The Tweet: its padding around the avatar beside the byline, the text and the action row.
- (CGFloat)tweetHeightForScreenWidth:(CGFloat)width {
    CGFloat textWidth = [self textWidthForScreenWidth:width];
    CGFloat byline = ceil([_byline sizeThatFits:CGSizeMake(textWidth, CGFLOAT_MAX)].height);
    CGFloat text = ceil([_text sizeThatFits:CGSizeMake(textWidth, CGFLOAT_MAX)].height);
    return 2 * kPFBPreviewPadding + MAX(kPFBPreviewAvatar, byline + 2.0 + text + 8.0 + [self actionsHeight]);
}

- (CGFloat)screenHeightForWidth:(CGFloat)width {
    return kPFBPreviewTopBar + [self tabsHeight] + [self tweetHeightForScreenWidth:width] + kPFBPreviewBarHeight +
           kPFBPreviewInset;
}

- (CGSize)sizeThatFits:(CGSize)size {
    CGFloat screenWidth = MAX(0, size.width - 2 * kPFBPreviewInset);
    return CGSizeMake(size.width, 2 * kPFBPreviewInset + [self screenHeightForWidth:screenWidth]);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    BOOL rtl = self.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    CGFloat width = MAX(0, CGRectGetWidth(self.bounds) - 2 * kPFBPreviewInset);
    _screen.frame = CGRectMake(kPFBPreviewInset, kPFBPreviewInset, width, [self screenHeightForWidth:width]);

    // The top bar: the reader's avatar, and the bird in the middle.
    _reader.frame = PFBPreviewMirrored(
        CGRectMake(kPFBPreviewPadding, (kPFBPreviewTopBar - 26.0) / 2.0, 26.0, 26.0), width, rtl);
    _logo.frame = CGRectMake((width - 32.0) / 2.0, (kPFBPreviewTopBar - 32.0) / 2.0, 32.0, 32.0);

    // The timeline tabs, For you chosen, its underline on the divider.
    CGFloat half = width / 2.0;
    CGFloat tabsY = kPFBPreviewTopBar;
    CGFloat tabsHeight = [self tabsHeight];
    _forYou.frame = PFBPreviewMirrored(CGRectMake(0, tabsY, half, tabsHeight - 4.0), width, rtl);
    _following.frame = PFBPreviewMirrored(CGRectMake(half, tabsY, half, tabsHeight - 4.0), width, rtl);
    CGFloat lineWidth = MIN(half, MAX(40.0, ceil([_forYou sizeThatFits:CGSizeMake(half, CGFLOAT_MAX)].width)));
    _underline.frame = PFBPreviewMirrored(
        CGRectMake((half - lineWidth) / 2.0, tabsY + tabsHeight - 4.0, lineWidth, 4.0), width, rtl);
    _divider.frame = CGRectMake(0, tabsY + tabsHeight, width, 0.5);

    // The Tweet beside its avatar, then its actions spread under the text, Share at the end.
    CGFloat top = tabsY + tabsHeight + kPFBPreviewPadding;
    CGFloat textX = kPFBPreviewPadding + kPFBPreviewAvatar + 10.0;
    CGFloat textWidth = [self textWidthForScreenWidth:width];
    CGFloat bylineHeight = ceil([_byline sizeThatFits:CGSizeMake(textWidth, CGFLOAT_MAX)].height);
    CGFloat textHeight = ceil([_text sizeThatFits:CGSizeMake(textWidth, CGFLOAT_MAX)].height);
    _avatar.frame = PFBPreviewMirrored(CGRectMake(kPFBPreviewPadding, top, kPFBPreviewAvatar, kPFBPreviewAvatar),
                                       width, rtl);
    _bird.frame = _avatar.bounds;
    _byline.frame = PFBPreviewMirrored(CGRectMake(textX, top, textWidth, bylineHeight), width, rtl);
    _text.frame = PFBPreviewMirrored(CGRectMake(textX, top + bylineHeight + 2.0, textWidth, textHeight), width, rtl);
    CGFloat actionsY = top + bylineHeight + 2.0 + textHeight + 8.0;
    CGFloat actionsHeight = [self actionsHeight];
    CGFloat slot = MAX(0, textWidth - kPFBPreviewActionGlyph - 4.0) / 4.0;
    for (NSUInteger i = 0; i < _actions.count; i++) {
        BOOL share = i + 1 == _actions.count;
        CGFloat x = share ? textX + textWidth - kPFBPreviewActionGlyph : textX + slot * (CGFloat)i;
        _actions[i].frame = PFBPreviewMirrored(CGRectMake(x, actionsY, kPFBPreviewActionGlyph, actionsHeight),
                                               width, rtl);
        CGFloat countWidth = share ? 0 : MAX(0, slot - kPFBPreviewActionGlyph - 8.0);
        _counts[i].frame = PFBPreviewMirrored(
            CGRectMake(x + kPFBPreviewActionGlyph + 4.0, actionsY, countWidth, actionsHeight), width, rtl);
        _counts[i].textAlignment = rtl ? NSTextAlignmentRight : NSTextAlignmentLeft;
    }

    // The bar beside the compose button, as at the bottom of the app; Home is the selected tab.
    CGFloat barY = CGRectGetHeight(_screen.bounds) - kPFBPreviewInset - kPFBPreviewBarHeight;
    CGFloat barWidth = MAX(0, width - 2 * kPFBPreviewInset - kPFBPreviewBarHeight - 10.0);
    _bar.frame = PFBPreviewMirrored(CGRectMake(kPFBPreviewInset, barY, barWidth, kPFBPreviewBarHeight), width, rtl);
    _compose.frame = PFBPreviewMirrored(
        CGRectMake(width - kPFBPreviewInset - kPFBPreviewBarHeight, barY, kPFBPreviewBarHeight, kPFBPreviewBarHeight),
        width, rtl);
    _composeGlyph.frame = _compose.bounds;
    CGFloat tabSlot = MAX(0, (barWidth - 8.0) / (CGFloat)_tabs.count);
    for (NSUInteger i = 0; i < _tabs.count; i++) {
        _tabs[i].frame = PFBPreviewMirrored(
            CGRectMake(4.0 + tabSlot * (CGFloat)i, 4.0, tabSlot, kPFBPreviewBarHeight - 8.0), barWidth, rtl);
    }
    _pill.frame = _tabs[0].frame;
    _pill.layer.cornerRadius = CGRectGetHeight(_pill.frame) / 2.0;

    // Home's dot sits at its glyph's top trailing corner.
    CGRect home = _tabs[0].frame;
    CGFloat dotX = rtl ? CGRectGetMidX(home) - kPFBPreviewGlyph / 2.0 - kPFBPreviewDot / 2.0 + 1.0
                       : CGRectGetMidX(home) + kPFBPreviewGlyph / 2.0 - kPFBPreviewDot / 2.0 - 1.0;
    _dot.frame = CGRectMake(dotX, CGRectGetMidY(home) - kPFBPreviewGlyph / 2.0 - 2.0, kPFBPreviewDot, kPFBPreviewDot);
}

@end
