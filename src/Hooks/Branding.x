//
//  Branding.x
//  PrimeFreeBird
//

#import <objc/runtime.h>
#import "HookHelpers.h"

// Declared after the framework imports: objc/runtime.h alone only forward-
// declares NSString, which is not enough under modules.
extern UIImage* NFBWhiteBakedGlyph(UIImage* image);
extern char NFBConfirmGlyphTag;
extern NSInteger NFBColorThemeScreenVisible;

// MARK: - Restore Twitter terminology
// Two layers, both driven by locale files in the tweak bundle:
//   1. RenameOverrides.strings — Twitter localization key -> exact replacement,
//      a missing key falls through to the generic replacement
//   2. RenameWords.strings — generic word replacements ("X" -> "Twitter",
//      "Post" -> "Tweet", etc.) applied to localized and server-side strings
// Both are strictly per-language: a language without its own copy of a file
// gets no renaming from that layer, rather than English rules applied to
// non-English text.

static NSDictionary<NSString*, NSString*>* RenameTable(NSString* name) {
    NSBundle* bundle = [BHTBundle sharedBundle].mainBundle;
    NSString* appLanguage =
        [[NSBundle mainBundle] preferredLocalizations].firstObject ?: @"en";
    NSString* localization =
        [NSBundle preferredLocalizationsFromArray:bundle.localizations
                                   forPreferences:@[appLanguage]]
            .firstObject;

    // preferredLocalizationsFromArray: falls back to en when nothing matches, so
    // reject a mismatch: unsupported languages skip renaming, not get English
    // rules.
    NSString* appCode =
        [appLanguage componentsSeparatedByString:@"-"].firstObject;
    NSString* lprojCode =
        [[localization stringByReplacingOccurrencesOfString:@"_" withString:@"-"]
            componentsSeparatedByString:@"-"]
            .firstObject;
    if (![appCode isEqualToString:lprojCode]) {
        return @{};
    }

    NSString* path = [bundle pathForResource:name
                                      ofType:@"strings"
                                 inDirectory:nil
                             forLocalization:localization];
    NSString* contents =
        path ? [NSString stringWithContentsOfFile:path
                                         encoding:NSUTF8StringEncoding
                                            error:nil]
             : nil;
    NSDictionary* table = [contents propertyListFromStringsFileFormat];
    return [table isKindOfClass:[NSDictionary class]] ? table : @{};
}

static NSDictionary<NSString*, NSString*>* RenameKeyOverrides(void) {
    static NSDictionary* overrides = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        overrides = RenameTable(@"RenameOverrides");
    });
    return overrides;
}

static NSDictionary<NSString*, NSString*>* TwitterWordMap(void) {
    static NSDictionary* map = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        map = RenameTable(@"RenameWords");
    });
    return map;
}

// Builds a case-insensitive \b(word|word…)\b from the map keys, longest first
// so inflections win over their stems. Exact case for uppercase-bearing keys is
// enforced per match in RenameEdits, so lowercase "x" never becomes "Twitter".
static NSRegularExpression* RenameRegex(void) {
    NSMutableArray<NSString*>* words = [NSMutableArray array];
    for (NSString* word in TwitterWordMap()) {
        [words addObject:[NSRegularExpression escapedPatternForString:word]];
    }
    if (words.count == 0) {
        return nil;
    }

    [words sortUsingComparator:^NSComparisonResult(NSString* a, NSString* b) {
        if (a.length > b.length)
            return NSOrderedAscending;
        if (a.length < b.length)
            return NSOrderedDescending;
        return [a compare:b];
    }];
    NSString* pattern = [NSString
        stringWithFormat:@"\\b(%@)\\b", [words componentsJoinedByString:@"|"]];
    return [NSRegularExpression
        regularExpressionWithPattern:pattern
                             options:NSRegularExpressionCaseInsensitive
                               error:nil];
}

// Applies the capitalisation style of `token` (all-caps or leading-capital) to
// `base`.
static NSString* MatchCapitalisation(NSString* token, NSString* base) {
    if (token.length == 0 || base.length == 0) {
        return base;
    }

    NSString* lower = token.lowercaseString;
    if (token.length > 1 && [token isEqualToString:token.uppercaseString] &&
        ![token isEqualToString:lower]) {
        return base.uppercaseString;
    }

    unichar first = [token characterAtIndex:0];
    if ([[NSCharacterSet uppercaseLetterCharacterSet] characterIsMember:first]) {
        return [base stringByReplacingCharactersInRange:NSMakeRange(0, 1)
                                             withString:[base substringToIndex:1]
                                                            .uppercaseString];
    }
    return base;
}

// Returns the edits (@"range" -> NSValue, @"repl" -> NSString) in ascending,
// non-overlapping order — apply them back-to-front. Nil when nothing changes.
static NSArray<NSDictionary*>* RenameEdits(NSString* input) {
    if (input.length == 0) {
        return nil;
    }

    static NSRegularExpression* regex = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        regex = RenameRegex();
    });
    if (!regex) {
        return nil;
    }

    NSDictionary* wordMap = TwitterWordMap();
    NSRange full = NSMakeRange(0, input.length);
    NSMutableArray<NSDictionary*>* edits = [NSMutableArray array];

    for (NSTextCheckingResult* match in [regex matchesInString:input
                                                       options:0
                                                         range:full]) {
        NSString* token = [input substringWithRange:match.range];
        // Exact key wins; otherwise fall back to the lowercase key and copy the
        // token's capitalisation. A lowercase hit on an uppercase-only key is left
        // alone.
        NSString* repl = wordMap[token];
        if (!repl) {
            NSString* base = wordMap[token.lowercaseString];
            repl = base ? MatchCapitalisation(token, base) : nil;
        }
        if (repl) {
            [edits addObject:@{
                @"range": [NSValue valueWithRange:match.range],
                @"repl": repl
            }];
        }
    }

    return edits.count > 0 ? edits : nil;
}

static NSString* RestoreTwitterTerminology(NSString* input) {
    // Memoise: labels re-set the same handful of strings over and over.
    static NSCache<NSString*, NSString*>* cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [NSCache new];
    });

    NSString* cached = [cache objectForKey:input];
    if (cached) {
        return cached;
    }

    NSArray<NSDictionary*>* edits = RenameEdits(input);
    NSString* output = input;
    if (edits) {
        NSMutableString* result = [input mutableCopy];
        for (NSDictionary* edit in edits.reverseObjectEnumerator) {
            [result replaceCharactersInRange:[edit[@"range"] rangeValue]
                                  withString:edit[@"repl"]];
        }
        output = [result copy];
    }

    [cache setObject:output forKey:input];
    return output;
}

static NSAttributedString* RestoreTwitterAttributed(NSAttributedString* input) {
    NSArray<NSDictionary*>* edits = RenameEdits(input.string);
    if (!edits) {
        return input;
    }

    NSMutableAttributedString* result = [input mutableCopy];
    for (NSDictionary* edit in edits.reverseObjectEnumerator) {
        NSRange range = [edit[@"range"] rangeValue];
        NSDictionary* attrs = [result attributesAtIndex:range.location
                                         effectiveRange:NULL];
        NSAttributedString* piece =
            [[NSAttributedString alloc] initWithString:edit[@"repl"]
                                            attributes:attrs];
        [result replaceCharactersInRange:range withAttributedString:piece];
    }
    return result;
}

// MARK: - Rename localized strings
// Every UI string routes through this Foundation method in 12.3, so the rename
// applies broadly. Skip the tweak's own bundle so the tweak's strings aren't
// reprocessed.
%hook NSBundle
- (NSString*)localizedStringForKey:(NSString*)key
                             value:(NSString*)value
                             table:(NSString*)tableName {
    NSString* result = %orig;
    if (![BHTSettings boolForKey:@"restore_twitter_names"] ||
        self == [BHTBundle sharedBundle].mainBundle) {
        return result;
    }

    NSString* override = key ? RenameKeyOverrides()[key] : nil;
    if (override) {
        return override;
    }
    return result.length > 0 ? RestoreTwitterTerminology(result) : result;
}
%end

// MARK: - Rename server-composed text
// TFNAttributedTextView renders chrome and server-composed URT text that
// carries no localization key, out of the NSBundle hook's reach. The
// TTAStatusBodyAttributedTextView subclass (tweet bodies) is skipped so a
// user's own words aren't mangled.
%hook TFNAttributedTextView
- (void)setTextModel:(TFNAttributedTextModel*)model {
    if (!model || !model.attributedString) {
        %orig(model);
        return;
    }

    NSMutableAttributedString* newString = nil;
    BOOL textChanged = NO;

    if ([BHTSettings boolForKey:@"restore_twitter_names"] &&
        ![self isKindOfClass:%c(TTAStatusBodyAttributedTextView)]) {
        NSAttributedString* source = newString ?: model.attributedString;
        NSAttributedString* renamed = RestoreTwitterAttributed(source);
        if (renamed != source) {
            newString = [renamed mutableCopy];
            textChanged = YES;
        }
    }

    if (!newString) {
        %orig(model);
        return;
    }

    if (textChanged) {
        // Text length changed, so rebuild the model to refresh length-derived
        // state.
        TFNAttributedTextModel* newModel = [[%c(TFNAttributedTextModel) alloc]
            initWithAttributedString:newString];
        %orig(newModel);
    } else if ([model respondsToSelector:@selector(setAttributedString:)]) {
        // Attributes only: keep the model to preserve its layout metadata.
        [model setAttributedString:newString];
        %orig(model);
    } else {
        TFNAttributedTextModel* newModel = [[%c(TFNAttributedTextModel) alloc]
            initWithAttributedString:newString];
        %orig(newModel);
    }
}
%end

// MARK: - Label the "new posts" refresh pill
// The facepile pill variant hardcodes blank text (no feature flag gates it).
// The tweak ships the label in the app's terminology and routes it through the
// rename pipeline, so "restore_twitter_names" converts it per-language.
static NSString* PillLabelText(void) {
    NSString* label =
        [[BHTBundle sharedBundle] localizedStringForKey:@"REFRESH_PILL_TEXT"];
    if ([BHTSettings boolForKey:@"restore_twitter_names"]) {
        label = RestoreTwitterTerminology(label);
    }
    return label;
}

%hook TUIUpdateIndicator

- (void)_recreatePillControlForContentNotification:(id)notification
                                      hideOnScroll:(BOOL)hideOnScroll {
    %orig;

    if (![BHTSettings boolForKey:@"refresh_pill_label"]) {
        return;
    }

    TFNPillControl* pill = self.pillControl;
    NSString* current = [pill.text
        stringByTrimmingCharactersInSet:[NSCharacterSet
                                            whitespaceAndNewlineCharacterSet]];
    if (current.length > 0) {
        return;
    }

    NSString* label = PillLabelText();
    if (label) {
        pill.text = label;
    }
}

%end

// MARK: - Classic compose button

// Two pieces restore the bird-era Tweet button: the "plus" vector glyph is
// remapped to the classic feather ("quill") rendered in white, and the FAB
// itself is painted Twitter blue. The FAB is located heuristically: a round
// square control at least 50pt wide inside the tab bar controller's view.

static UIColor* NFBTwitterBlue(void) {
    return [UIColor colorWithRed:0x1D / 255.0
                           green:0xA1 / 255.0
                            blue:0xF2 / 255.0
                           alpha:1.0];
}

static BOOL isComposePlusGlyph(NSString* name) {
    if (![BHTSettings boolForKey:@"restore_tweet_button"]) {
        return NO;
    }
    return [name isKindOfClass:[NSString class]] && [name isEqualToString:@"plus"];
}

%hook UIImage

+ (id)tfn_vectorImageNamed:(id)name fitsSize:(CGSize)size fillColor:(id)color {
    if (isComposePlusGlyph(name)) {
        return %orig(@"quill", size, [UIColor whiteColor]);
    }
    return %orig(name, size, color);
}

+ (id)tfn_vectorImageNamed:(id)name
    highContrastVariantNamed:(id)variant
                    fitsSize:(CGSize)size
                   fillColor:(id)color {
    if (isComposePlusGlyph(name)) {
        return %orig(@"quill", variant, size, [UIColor whiteColor]);
    }
    return %orig(name, variant, size, color);
}

+ (id)tfn_vectorImageNamed:(id)name height:(double)height fillColor:(id)color {
    if (isComposePlusGlyph(name)) {
        return %orig(@"quill", height, [UIColor whiteColor]);
    }
    return %orig(name, height, color);
}

%end

// The compose FAB is a plain UIView subclass, so style it directly: blue
// disc, white glyphs, and any internal chrome (grey disc, blur) neutralised.
@interface TFNFloatingActionButton : UIView
@end

// Tag set on the FAB's glyph image views so the UIImageView hook below can
// recognise them in O(1) and keep swapped-in images template+white.
static char kNFBFABGlyphKey;
// Shared (non-static) so ColorThemeViewController can tag the confirm glyph:
// once tagged, the setImage: hook below whitens Twitter's re-bakes before
// their first render — no more timed races.
// Set while the tweak's code installs an effect, so the setEffect: hook lets it pass —
// Without it the setEffect: hook swallows and re-tints in a loop, eating the
// own reinstalls: the material never got tinted all session.
static BOOL NFBEffectInstallAllowed;
// What the tweak last installed. UIVisualEffectView.effect vends copies whose
// tintColor does not round-trip, so the getter can never be trusted for
// mismatch detection — compare against this shadow instead.
static char kNFBFABGlassShadowTintKey;
// The opaque colour cap inside the material's contentView. Snapshots render
// glass materials blank-white — the transition copies iOS draws during tab
// changes — while plain layers snapshot correctly, so the cap is what keeps
// the snapshot coloured.
static char kNFBFABGlassCapKey;
// Tag for the FAB's glass material so the layout guard below can re-assert its
// colour the instant anything clears it.
static char kNFBFABGlassKey;

// One place to colour the FAB's glass — three layers, because the system can
// re-render the material itself during transitions:
// 1. the effect's own tint when the runtime exposes one (the native Liquid
//    Glass path — lives INSIDE the material, survives its animations),
// 2. the effect view's backgroundColor (a plain layer that renders even when
//    the material is snapshotted or drawn blank),
// 3. the contentView colour (the original approach, kept).
static void NFBColorFABGlass(UIVisualEffectView* effect, UIColor* blue) {
    // Keep the material tinted at all times (an untinted material renders
    // opaque light, covering even the coloured background beneath), but
    // re-assign only on an actual mismatch and with all implicit animation
    // disabled — each effect re-assignment triggers an animated rebuild that
    // flashes the glyph black.
    // The setEffect: hook below handles the system's own re-installs, so this
    // path should stay quiet outside launch.
    UIVisualEffect* fx = effect.effect;
    UIColor* lastInstalled = objc_getAssociatedObject(effect, &kNFBFABGlassShadowTintKey);
    if (fx && [fx respondsToSelector:@selector(setTintColor:)] &&
        ![lastInstalled isEqual:blue]) {
        [(id)fx setTintColor:blue];
        NFBEffectInstallAllowed = YES;
        [UIView performWithoutAnimation:^{
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            effect.effect = fx;
            [CATransaction commit];
        }];
        NFBEffectInstallAllowed = NO;
        objc_setAssociatedObject(effect, &kNFBFABGlassShadowTintKey, blue,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (![effect.backgroundColor isEqual:blue]) {
        effect.backgroundColor = blue;
    }
    if (![effect.contentView.backgroundColor isEqual:blue]) {
        effect.contentView.backgroundColor = blue;
    }
    UIView* cap = objc_getAssociatedObject(effect, &kNFBFABGlassCapKey);
    if (!cap) {
        cap = [[UIView alloc] initWithFrame:effect.contentView.bounds];
        cap.autoresizingMask =
            UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        cap.userInteractionEnabled = NO;
        [effect.contentView insertSubview:cap atIndex:0];
        objc_setAssociatedObject(effect, &kNFBFABGlassCapKey, cap,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    cap.layer.cornerRadius = effect.layer.cornerRadius;
    cap.layer.cornerCurve = effect.layer.cornerCurve;
    cap.clipsToBounds = YES;
    if (![cap.backgroundColor isEqual:blue]) {
        cap.backgroundColor = blue;
    }
}

// The compose FAB is Twitter's brand button — its base colour is Twitter blue,
// never iOS systemBlue. Use the accent only when the user ACTUALLY picked one
// (custom hex, a swatch, or Twitter's own non-default option). On a fresh
// install or right after a reset the palette can briefly resolve option 0 to
// systemBlue via CurrentAccentColor's fallback — that iOS-blue leak was the FAB
// bug. Forcing Twitter blue here keeps the FAB on-brand in every no-accent state.
static UIColor* NFBFABBlueColor(void) {
    extern UIColor* CurrentAccentColor(void);
    NSUserDefaults* d = NSUserDefaults.standardUserDefaults;
    BOOL picked = [d objectForKey:@"bh_custom_accent_hex"] ||
                  [d objectForKey:@"bh_color_theme_selectedColor"] ||
                  [d integerForKey:@"T1ColorSettingsPrimaryColorOptionKey"] >= 1;
    if (picked) {
        return CurrentAccentColor() ?: NFBTwitterBlue();
    }
    return NFBTwitterBlue();
}

static void styleComposeFAB(UIView* fab) {
    if (![BHTSettings boolForKey:@"restore_tweet_button"]) {
        return;
    }
    extern UIColor* CurrentAccentColor(void);
    UIColor* blue = NFBFABBlueColor();
    if (![fab.backgroundColor isEqual:blue]) {
        fab.backgroundColor = blue;
    }
    CGFloat radius = MIN(fab.bounds.size.width, fab.bounds.size.height) / 2.0;
    if (fab.layer.cornerRadius != radius) {
        fab.layer.cornerRadius = radius;
    }
    fab.clipsToBounds = YES;
    // Give the button itself a white tint so any template glyph is white from
    // its very first render. Waiting to tint the image view is what made the
    // logo flash black for a frame on every tab change.
    if (![fab.tintColor isEqual:[UIColor whiteColor]]) {
        fab.tintColor = [UIColor whiteColor];
    }
    EnumerateSubviewsRecursively(fab, ^(UIView* sub) {
        if (sub == fab) {
            return;
        }
        if ([sub isKindOfClass:[UIImageView class]]) {
            UIImageView* imageView = (UIImageView*)sub;
            BOOL alreadyTagged =
                objc_getAssociatedObject(imageView, &kNFBFABGlyphKey) != nil;
            objc_setAssociatedObject(imageView, &kNFBFABGlyphKey, @YES,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            if (!alreadyTagged && imageView.image) {
                // First encounter: bake what is already there; every later
                // assignment goes through the setter hook and arrives baked.
                imageView.image = NFBWhiteBakedGlyph(imageView.image);
            }
            if (![imageView.tintColor isEqual:[UIColor whiteColor]]) {
                imageView.tintColor = [UIColor whiteColor];
            }
        } else if ([sub isKindOfClass:[UIVisualEffectView class]]) {
            UIVisualEffectView* effect = (UIVisualEffectView*)sub;
            if ([BHTSettings boolForKey:@"enable_liquid_glass"]) {
                objc_setAssociatedObject(effect, &kNFBFABGlassKey, @YES,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                NFBColorFABGlass(effect, blue);
            } else if (!effect.hidden) {
                effect.hidden = YES;
            }
        } else if (![sub isKindOfClass:[UILabel class]] &&
                   sub.subviews.count == 0 &&
                   sub.backgroundColor) {
            CGFloat r = sub.layer.cornerRadius;
            BOOL isDisc = r > 1.0 &&
                          fabs(sub.bounds.size.width - sub.bounds.size.height) < 2.0 &&
                          fabs(r - sub.bounds.size.width / 2.0) < 2.0;
            if (isDisc && ![sub.backgroundColor isEqual:blue]) {
                sub.backgroundColor = blue;
            }
        }
    });
}

// Weak handle to the live compose FAB so a colour pick can restyle it
// immediately, without waiting for the next layout pass.
static __weak UIView* NFBComposeFABView;

// Called from NFBSyncAccentTheme (Theme.x) right after the accent changes.
void NFBRestyleComposeFAB(void) {
    void (^run)(void) = ^{
        // The cached handle is only a fast path: while the settings screen is
        // pushed, the timeline's views are detached (window == nil) and the FAB
        // is often rebuilt on the way back — so a stale or detached reference is
        // normal. Restyle it unconditionally, then sweep the live hierarchy so
        // whichever FAB is actually on screen also gets the new accent.
        UIView* known = NFBComposeFABView;
        if (known) {
            styleComposeFAB(known);
            [known setNeedsLayout];
        }
        Class FABClass = NSClassFromString(@"TFNFloatingActionButton");
        if (!FABClass) {
            return;
        }
        for (id scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:NSClassFromString(@"UIWindowScene")]) {
                continue;
            }
            for (UIWindow* window in [scene windows]) {
                EnumerateSubviewsRecursively(window, ^(UIView* sub) {
                    if ([sub isKindOfClass:FABClass]) {
                        NFBComposeFABView = sub;
                        styleComposeFAB(sub);
                        [sub setNeedsLayout];
                    }
                });
            }
        }
    };
    if ([NSThread isMainThread]) {
        run();
    } else {
        dispatch_async(dispatch_get_main_queue(), run);
    }
}

// Hiding the compose button is independent of restyling it: styleComposeFAB
// only paints, and returns early when the classic button is off. The tweak tracks
// whether the tweak hid the button so turning the option back off restores it —
// without ever forcing it visible on an untouched button (Twitter fades
// the FAB itself in places, and fighting that would flicker).
static const void* kNFBFABHiddenByUsKey = &kNFBFABHiddenByUsKey;

static void nfbApplyComposeFABVisibility(UIView* fab) {
    if (!fab) {
        return;
    }
    BOOL wantHidden = [BHTSettings boolForKey:@"hide_tweet_button"];
    BOOL hiddenByUs = objc_getAssociatedObject(fab, kNFBFABHiddenByUsKey) != nil;
    if (wantHidden) {
        fab.hidden = YES;
        fab.alpha = 0.0;
        fab.userInteractionEnabled = NO;
        if (!hiddenByUs) {
            objc_setAssociatedObject(fab, kNFBFABHiddenByUsKey, @YES,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    } else if (hiddenByUs) {
        fab.hidden = NO;
        fab.alpha = 1.0;
        fab.userInteractionEnabled = YES;
        objc_setAssociatedObject(fab, kNFBFABHiddenByUsKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

%hook TFNFloatingActionButton

// willMoveToWindow: fires before the button is ever drawn, so the white glyph
// tint and the disc colour are in place for its very first frame — that first
// unstyled frame was the flash still visible on every tab change.
- (void)willMoveToWindow:(UIWindow*)newWindow {
    %orig;
    if (newWindow) {
        NFBComposeFABView = (UIView*)self;
        styleComposeFAB((UIView*)self);
        nfbApplyComposeFABVisibility((UIView*)self);
    }
}

- (void)didMoveToWindow {
    %orig;
    NFBComposeFABView = (UIView*)self;
    styleComposeFAB((UIView*)self);
    nfbApplyComposeFABVisibility((UIView*)self);
}

// The glass material and the glyph arrive as SUBVIEWS after the button is
// attached; willMoveToWindow: ran too early to see them. Styling the instant
// they land colours them within the same transaction — before their first
// frame, which was the last visible blink.
- (void)didAddSubview:(UIView*)subview {
    %orig;
    styleComposeFAB((UIView*)self);
}

- (void)layoutSubviews {
    %orig;
    NFBComposeFABView = (UIView*)self;
    styleComposeFAB((UIView*)self);
    nfbApplyComposeFABVisibility((UIView*)self);
}

%end

// Twitter swaps the glyph IMAGE on an existing image view during tab
// transitions; new subviews were covered, image replacements were not — that
// was the frame still blinking. Only views styleComposeFAB has tagged are
// touched, so elsewhere this costs a single associated-object lookup.
%hook UIImageView

// The glyph often sits inside the glass material's contentView, where the
// FAB's own didAddSubview: never fires — a brand-new button could therefore
// show one untagged, untemplated (black) frame. Tag and template at attach,
// within the same transaction, before the first frame. The ancestor walk is
// six levels at most and only runs for image views entering a window.
- (void)willMoveToWindow:(UIWindow*)newWindow {
    %orig;
    if (!newWindow || objc_getAssociatedObject(self, &kNFBFABGlyphKey) ||
        ![BHTSettings boolForKey:@"restore_tweet_button"]) {
        return;
    }
    UIView* ancestor = self.superview;
    NSInteger depth = 0;
    while (ancestor && depth < 6) {
        if ([NSStringFromClass([ancestor class])
                containsString:@"FloatingActionButton"]) {
            objc_setAssociatedObject(self, &kNFBFABGlyphKey, @YES,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            if (self.image) {
                self.image = NFBWhiteBakedGlyph(self.image);
            }
            self.tintColor = [UIColor whiteColor];
            return;
        }
        ancestor = ancestor.superview;
        depth++;
    }
}

- (void)setImage:(UIImage*)image {
    // Bake at the SETTER: whoever writes last, the pixels that land are white.
    // This ends the pass-ordering race that kept resurrecting the dark check
    // (yellow) and the black FAB frames — a template glyph is only white while
    // its tint survives; a baked one has nothing left to lose.
    if (image && objc_getAssociatedObject(self, &kNFBFABGlyphKey)) {
        image = NFBWhiteBakedGlyph(image);
    } else if (image && objc_getAssociatedObject(self, &NFBConfirmGlyphTag) &&
               NFBColorThemeScreenVisible) {
        NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
        BOOL accentActive =
            [defaults boolForKey:@"bh_custom_is_active"] ||
            [defaults objectForKey:@"bh_color_theme_selectedColor"] != nil;
        if (accentActive) {
            image = NFBWhiteBakedGlyph(image);
        }
    }
    %orig(image);
}

%end

// Same principle as the glyph, applied to the DISC: during a tab transition the
// glass material can arrive as a fresh UIVisualEffectView whose contentView the tweak
// only coloured at the next styling pass — one glassy-white frame, the flick
// that remains. Colour it the instant it enters a window, same transaction.
%hook UIVisualEffectView

// The system re-installs the material's effect on each tab transition.
// Tinting the INCOMING
// effect right here means the reset itself installs a coloured material — no
// extra assignment from the tweak, no rebuild of the tweak's own, no untinted frame.
- (void)setEffect:(UIVisualEffect*)effect {
    if (effect && objc_getAssociatedObject(self, &kNFBFABGlassKey) &&
        [BHTSettings boolForKey:@"restore_tweet_button"] &&
        [BHTSettings boolForKey:@"enable_liquid_glass"] &&
        [effect respondsToSelector:@selector(setTintColor:)]) {
        extern UIColor* CurrentAccentColor(void);
        UIColor* blue = NFBFABBlueColor();
        // The tweak's own installs pass through, tinted.
        if (NFBEffectInstallAllowed) {
            [(id)effect setTintColor:blue];
            %orig;
            return;
        }
        // The per-transition re-install triggers the animated rebuild —
        // swallow it when nothing changes. No in-place mutation here:
        // self.effect returns a copy, so mutating it is a no-op.
        UIVisualEffect* current = self.effect;
        if (current && [current class] == [effect class]) {
            return;
        }
        [(id)effect setTintColor:blue];
        %orig;
        return;
    }
    %orig;
}

- (void)willMoveToWindow:(UIWindow*)newWindow {
    %orig;
    if (!newWindow || ![BHTSettings boolForKey:@"restore_tweet_button"] ||
        ![BHTSettings boolForKey:@"enable_liquid_glass"]) {
        return;
    }
    UIView* ancestor = self.superview;
    NSInteger depth = 0;
    while (ancestor && depth < 6) {
        if ([NSStringFromClass([ancestor class])
                containsString:@"FloatingActionButton"]) {
            objc_setAssociatedObject(self, &kNFBFABGlassKey, @YES,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            extern UIColor* CurrentAccentColor(void);
            UIColor* blue = NFBFABBlueColor();
            NFBColorFABGlass(self, blue);
            return;
        }
        ancestor = ancestor.superview;
        depth++;
    }
}

// If anything clears the tagged material's colour mid-transition, this
// re-asserts it within the same layout pass.
- (void)layoutSubviews {
    %orig;
    if (!objc_getAssociatedObject(self, &kNFBFABGlassKey)) {
        return;
    }
    extern UIColor* CurrentAccentColor(void);
    UIColor* blue = NFBFABBlueColor();
    BOOL wasCleared = ![self.contentView.backgroundColor isEqual:blue] ||
                      ![self.backgroundColor isEqual:blue];
    NFBColorFABGlass(self, blue);
    if (wasCleared) {
    }
}

%end
