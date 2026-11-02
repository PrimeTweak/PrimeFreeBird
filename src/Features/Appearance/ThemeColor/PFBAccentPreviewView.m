// A sample of Twitter in the accent color, laid out by hand on the Theme color card.

#import "Features/Appearance/ThemeColor/PFBAccentPreviewView.h"
#import "Common/PFBBundle.h"
#import "Common/PFBSettings.h"
#import "Settings/Native/PFBShowcase.h"
#import "Settings/PFBSettingsCellStyle.h"
#import "Support/PFBManager.h"

// The sample's margin on the card, the bar's height that the compose button's size matches, and
// the Tweet's avatar, padding and glyph sizes.
static const CGFloat kPFBPreviewInset = 14.0;
static const CGFloat kPFBPreviewBarHeight = 60.0;
static const CGFloat kPFBPreviewAvatar = 40.0;
static const CGFloat kPFBPreviewPadding = 12.0;
static const CGFloat kPFBPreviewGlyph = 26.0;
static const CGFloat kPFBPreviewDot = 9.0;

// A Twitter glyph in one color, or none where the app cannot draw it.
static UIImage* PFBPreviewGlyph(NSString* name, CGFloat size, UIColor* color) {
    if (![UIImage respondsToSelector:@selector(tfn_vectorImageNamed:fitsSize:fillColor:)]) {
        return nil;
    }
    return [UIImage tfn_vectorImageNamed:name fitsSize:CGSizeMake(size, size) fillColor:color];
}

// Turns a left-to-right frame into the view's direction.
static CGRect PFBPreviewMirrored(CGRect frame, CGFloat width, BOOL rtl) {
    if (rtl) {
        frame.origin.x = width - CGRectGetMaxX(frame);
    }
    return frame;
}

@implementation PFBAccentPreviewView {
    PFBShowcaseSurface* _post;
    UIView* _avatar;
    UIImageView* _bird;
    UILabel* _byline;
    UILabel* _text;
    PFBShowcaseSurface* _bar;
    UIView* _pill;
    NSArray<UIImageView*>* _tabs;
    UIView* _dot;
    UIView* _compose;
    UIImageView* _composeGlyph;
    UIColor* _accent;
    BOOL _tintsSelectedTab;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = NO;
        self.accessibilityElementsHidden = YES;
        _accent = [UIColor systemBlueColor];
        _post = [[PFBShowcaseSurface alloc] initWithCornerRadius:20.0];
        _avatar = [[UIView alloc] init];
        _avatar.layer.cornerRadius = kPFBPreviewAvatar / 2.0;
        _bird = [[UIImageView alloc] init];
        _bird.contentMode = UIViewContentModeCenter;
        [_avatar addSubview:_bird];
        _byline = [[UILabel alloc] init];
        _text = [[UILabel alloc] init];
        _text.numberOfLines = 0;
        for (UIView* part in @[ _avatar, _byline, _text ]) {
            [_post.contentView addSubview:part];
        }
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
        for (UIView* part in @[ _post, _bar, _compose ]) {
            [self addSubview:part];
        }
        [self applyTheme];
    }
    return self;
}

- (void)applyAccent:(UIColor*)accent tintsSelectedTab:(BOOL)tintsSelectedTab {
    _accent = accent;
    _tintsSelectedTab = tintsSelectedTab;
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
    UIColor* ink = [PFBSettingsTextColor() resolvedColorWithTraitCollection:self.traitCollection];
    UIColor* ground = [[PFBPalette currentBackgroundColor] resolvedColorWithTraitCollection:self.traitCollection];
    UIColor* accent = [_accent resolvedColorWithTraitCollection:self.traitCollection];
    _avatar.backgroundColor = ink;
    _bird.image = PFBPreviewGlyph(@"twitter", 22.0, ground);
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
                                               NSForegroundColorAttributeName: PFBSettingsSubtitleColor(),
                                           }]];
    _byline.attributedText = byline;
    _text.attributedText = [self sampleText];
    _pill.backgroundColor = [UIColor tertiarySystemFillColor];
    NSArray<NSString*>* glyphs = @[ @"home", @"search_stroke", @"notifications_stroke", @"chat_bubble_stroke" ];
    for (NSUInteger i = 0; i < _tabs.count; i++) {
        _tabs[i].image = PFBPreviewGlyph(glyphs[i], kPFBPreviewGlyph, i == 0 && _tintsSelectedTab ? accent : ink);
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

- (CGFloat)textWidthForPostWidth:(CGFloat)width {
    return MAX(0, width - 2 * kPFBPreviewPadding - kPFBPreviewAvatar - 10.0);
}

- (CGFloat)postHeightForWidth:(CGFloat)width {
    CGFloat textWidth = [self textWidthForPostWidth:width];
    CGFloat byline = ceil([_byline sizeThatFits:CGSizeMake(textWidth, CGFLOAT_MAX)].height);
    CGFloat text = ceil([_text sizeThatFits:CGSizeMake(textWidth, CGFLOAT_MAX)].height);
    return MAX(kPFBPreviewAvatar, byline + 2.0 + text) + 2 * kPFBPreviewPadding;
}

- (CGSize)sizeThatFits:(CGSize)size {
    CGFloat post = [self postHeightForWidth:size.width - 2 * kPFBPreviewInset];
    return CGSizeMake(size.width, kPFBPreviewInset + post + 12.0 + kPFBPreviewBarHeight + kPFBPreviewInset);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = CGRectGetWidth(self.bounds);
    BOOL rtl = self.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    CGFloat postWidth = MAX(0, width - 2 * kPFBPreviewInset);
    _post.frame = CGRectMake(kPFBPreviewInset, kPFBPreviewInset, postWidth, [self postHeightForWidth:postWidth]);
    CGFloat textX = kPFBPreviewPadding + kPFBPreviewAvatar + 10.0;
    CGFloat textWidth = [self textWidthForPostWidth:postWidth];
    CGFloat bylineHeight = ceil([_byline sizeThatFits:CGSizeMake(textWidth, CGFLOAT_MAX)].height);
    CGFloat textHeight = ceil([_text sizeThatFits:CGSizeMake(textWidth, CGFLOAT_MAX)].height);
    _avatar.frame = PFBPreviewMirrored(
        CGRectMake(kPFBPreviewPadding, kPFBPreviewPadding, kPFBPreviewAvatar, kPFBPreviewAvatar), postWidth, rtl);
    _bird.frame = _avatar.bounds;
    _byline.frame = PFBPreviewMirrored(CGRectMake(textX, kPFBPreviewPadding, textWidth, bylineHeight), postWidth, rtl);
    _text.frame = PFBPreviewMirrored(CGRectMake(textX, kPFBPreviewPadding + bylineHeight + 2.0, textWidth, textHeight),
                                     postWidth, rtl);

    // The bar beside the compose button, as at the bottom of the app; Home is the selected tab.
    CGFloat barY = CGRectGetMaxY(_post.frame) + 12.0;
    CGFloat barWidth = MAX(0, width - 2 * kPFBPreviewInset - kPFBPreviewBarHeight - 12.0);
    _bar.frame = PFBPreviewMirrored(CGRectMake(kPFBPreviewInset, barY, barWidth, kPFBPreviewBarHeight), width, rtl);
    _compose.frame = PFBPreviewMirrored(
        CGRectMake(width - kPFBPreviewInset - kPFBPreviewBarHeight, barY, kPFBPreviewBarHeight, kPFBPreviewBarHeight),
        width, rtl);
    _composeGlyph.frame = _compose.bounds;
    CGFloat slot = MAX(0, (barWidth - 8.0) / (CGFloat)_tabs.count);
    for (NSUInteger i = 0; i < _tabs.count; i++) {
        _tabs[i].frame = PFBPreviewMirrored(CGRectMake(4.0 + slot * (CGFloat)i, 4.0, slot, kPFBPreviewBarHeight - 8.0),
                                            barWidth, rtl);
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
