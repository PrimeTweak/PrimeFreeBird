// Restores Twitter's terminology and glyphs: localized and server-composed
// strings, the "new posts" pill label, and the classic compose button.

#import <objc/runtime.h>
#import "Support/HookHelpers.h"

// Declared after the framework imports: objc/runtime.h alone only forward-
// declares NSString, which is not enough under modules.
extern UIImage* PFBWhiteBakedGlyph(UIImage* image);
extern char PFBConfirmGlyphTag;
extern NSInteger PFBColorThemeScreenVisible;

// MARK: - Restore Twitter terminology

// Two layers from the bundle's locale files: RenameOverrides.strings maps a
// localization key to an exact replacement, RenameWords.strings holds generic word
// replacements. Both are per-language, with no fallback to English rules.

static NSDictionary<NSString*, NSString*>* RenameTable(NSString* name) {
    NSBundle* bundle = [PFBBundle sharedBundle].mainBundle;
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

// Every UI string routes through this Foundation method, so the rename applies
// broadly. The tweak's own bundle is skipped so its strings are not reprocessed.
%hook NSBundle
- (NSString*)localizedStringForKey:(NSString*)key
                             value:(NSString*)value
                             table:(NSString*)tableName {
    NSString* result = %orig;
    if (![PFBSettings boolForKey:@"restore_twitter_names"] ||
        self == [PFBBundle sharedBundle].mainBundle) {
        return result;
    }

    NSString* override = key ? RenameKeyOverrides()[key] : nil;
    if (override) {
        PFBCOMPAT_ACTION(PFBCompat_restore_twitter_names, @"string renamed");
        return override;
    }
    PFBCOMPAT_OBSERVE(PFBCompat_restore_twitter_names, @"read by Twitter");
    return result.length > 0 ? RestoreTwitterTerminology(result) : result;
}
%end

// MARK: - Rename server-composed text

// TFNAttributedTextView renders text carrying no localization key, out of the
// NSBundle hook's reach. The tweet-body subclass is skipped so a user's own words
// are not mangled.
%hook TFNAttributedTextView
- (void)setTextModel:(TFNAttributedTextModel*)model {
    if (!model || !model.attributedString) {
        %orig(model);
        return;
    }

    NSMutableAttributedString* newString = nil;
    BOOL textChanged = NO;

    if ([PFBSettings boolForKey:@"restore_twitter_names"] &&
        ![self isKindOfClass:%c(TTAStatusBodyAttributedTextView)]) {
        NSAttributedString* source = newString ?: model.attributedString;
        NSAttributedString* renamed = RestoreTwitterAttributed(source);
        if (renamed != source) {
            PFBCOMPAT_ACTION(PFBCompat_restore_twitter_names, @"text renamed");
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

// The facepile pill variant hardcodes blank text. The label is shipped in the app's
// terminology and routed through the rename pipeline, so it converts per-language.
static NSString* PillLabelText(void) {
    NSString* label =
        [[PFBBundle sharedBundle] localizedStringForKey:@"REFRESH_PILL_TEXT"];
    if ([PFBSettings boolForKey:@"restore_twitter_names"]) {
        label = RestoreTwitterTerminology(label);
    }
    return label;
}

%hook TUIUpdateIndicator

// Hide new Tweets pill: the indicator is refused the pill before it builds one.
- (BOOL)_canShowPillForContentNotification:(id)notification {
    BOOL canShow = %orig;
    if (!canShow) {
        return NO;
    }
    if ([PFBSettings boolForKey:@"hide_new_tweets_pill"]) {
        PFBCOMPAT_ACTION(PFBCompat_hide_new_tweets_pill, @"new Tweets pill held back");
        return NO;
    }
    PFBCOMPAT_OBSERVE(PFBCompat_hide_new_tweets_pill, @"new Tweets pill offered");
    return YES;
}

- (void)_recreatePillControlForContentNotification:(id)notification
                                      hideOnScroll:(BOOL)hideOnScroll {
    %orig;

    // A pill built by another path is hidden before it can be seen.
    if ([PFBSettings boolForKey:@"hide_new_tweets_pill"]) {
        self.pillControl.hidden = YES;
        PFBCOMPAT_ACTION(PFBCompat_hide_new_tweets_pill, @"new Tweets pill hidden");
        return;
    }

    if (![PFBSettings boolForKey:@"refresh_pill_label"]) {
        PFBCOMPAT_OBSERVE(PFBCompat_refresh_pill_label, @"refresh pill shown");
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
        PFBCOMPAT_ACTION(PFBCompat_refresh_pill_label, @"pill labeled");
    }
}

%end

// MARK: - Classic compose button

// Two pieces restore the bird-era Tweet button: the compose glyph is remapped to
// the feather in white, and the FAB is painted Twitter blue. The FAB is found as a round
// square control at least 50 pt wide inside the tab bar controller's view.

static UIColor* PFBTwitterBlue(void) {
    return [UIColor colorWithRed:0x1D / 255.0
                           green:0xA1 / 255.0
                            blue:0xF2 / 255.0
                           alpha:1.0];
}

static BOOL isComposePlusGlyph(NSString* name) {
    if (![PFBSettings boolForKey:@"restore_tweet_button"] || ![name isKindOfClass:[NSString class]]) {
        return NO;
    }
    // "plus" is the pre-Liquid-Glass compose glyph; the redesign draws the FAB
    // with one of the compose vectors instead, so those are remapped as well.
    static NSSet<NSString*>* composeGlyphs = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        composeGlyphs = [NSSet setWithArray:@[
            @"plus", @"compose", @"alt_compose", @"alt_compose_plus", @"compose_square"
        ]];
    });
    return [composeGlyphs containsObject:name];
}

// Every vector the app loads by name keeps that name on the image, under the
// loader's own selector as the key so any file can read it back without a
// shared declaration. It is how a bar button is told apart by what it shows.
static id PFBNamedVector(id image, id name) {
    if (image && [name isKindOfClass:[NSString class]]) {
        objc_setAssociatedObject(image, @selector(tfn_vectorImageNamed:fitsSize:fillColor:),
                                 name, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return image;
}

%hook UIImage

+ (id)tfn_vectorImageNamed:(id)name fitsSize:(CGSize)size fillColor:(id)color {
    if (isComposePlusGlyph(name)) {
        return %orig(@"feather", size, [UIColor whiteColor]);
    }
    return PFBNamedVector(%orig(name, size, color), name);
}

+ (id)tfn_vectorImageNamed:(id)name
    highContrastVariantNamed:(id)variant
                    fitsSize:(CGSize)size
                   fillColor:(id)color {
    if (isComposePlusGlyph(name)) {
        return %orig(@"feather", variant, size, [UIColor whiteColor]);
    }
    return PFBNamedVector(%orig(name, variant, size, color), name);
}

+ (id)tfn_vectorImageNamed:(id)name height:(double)height fillColor:(id)color {
    if (isComposePlusGlyph(name)) {
        return %orig(@"feather", height, [UIColor whiteColor]);
    }
    return PFBNamedVector(%orig(name, height, color), name);
}

%end

// The compose FAB is a plain UIView subclass, so style it directly: blue
// disc, white glyphs, and any internal chrome (gray disc, blur) neutralised.
@interface TFNFloatingActionButton : UIView
@end

// Tag set on the FAB's glyph image views so the UIImageView hook below can
// recognize them in O(1) and keep swapped-in images template+white.
static char kPFBFABGlyphKey;
// Set while an effect is being installed here, so the setEffect: hook lets it
// through. Without it that hook swallows and re-tints in a loop, and the material
// is never tinted.
static BOOL PFBEffectInstallAllowed;
// What the tweak last installed. UIVisualEffectView.effect vends copies whose
// tintColor does not round-trip, so the getter can never be trusted for
// mismatch detection — compare against this shadow instead.
static char kPFBFABGlassShadowTintKey;
// The opaque color cap inside the material's contentView. Snapshots render glass
// materials blank-white while plain layers snapshot correctly, so the cap is what
// keeps the snapshot colored.
static char kPFBFABGlassCapKey;
// Tag for the FAB's glass material so the layout guard below can re-assert its
// color the instant anything clears it.
static char kPFBFABGlassKey;

// One place to color the FAB's glass, in three layers since the system can
// re-render the material during transitions: the effect's own tint, the effect
// view's backgroundColor, and the contentView color.
static void PFBColorFABGlass(UIVisualEffectView* effect, UIColor* blue) {
    // The material is kept tinted at all times, since an untinted one renders
    // opaque light over the colored background. Re-assigned only on a mismatch and
    // without implicit animation: a re-assignment rebuilds and flashes the glyph.
    UIVisualEffect* fx = effect.effect;
    UIColor* lastInstalled = objc_getAssociatedObject(effect, &kPFBFABGlassShadowTintKey);
    if (fx && [fx respondsToSelector:@selector(setTintColor:)] &&
        ![lastInstalled isEqual:blue]) {
        [(id)fx setTintColor:blue];
        PFBEffectInstallAllowed = YES;
        [UIView performWithoutAnimation:^{
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            effect.effect = fx;
            [CATransaction commit];
        }];
        PFBEffectInstallAllowed = NO;
        objc_setAssociatedObject(effect, &kPFBFABGlassShadowTintKey, blue,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (![effect.backgroundColor isEqual:blue]) {
        effect.backgroundColor = blue;
    }
    if (![effect.contentView.backgroundColor isEqual:blue]) {
        effect.contentView.backgroundColor = blue;
    }
    UIView* cap = objc_getAssociatedObject(effect, &kPFBFABGlassCapKey);
    if (!cap) {
        cap = [[UIView alloc] initWithFrame:effect.contentView.bounds];
        cap.autoresizingMask =
            UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        cap.userInteractionEnabled = NO;
        [effect.contentView insertSubview:cap atIndex:0];
        objc_setAssociatedObject(effect, &kPFBFABGlassCapKey, cap,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    cap.layer.cornerRadius = effect.layer.cornerRadius;
    cap.layer.cornerCurve = effect.layer.cornerCurve;
    cap.clipsToBounds = YES;
    if (![cap.backgroundColor isEqual:blue]) {
        cap.backgroundColor = blue;
    }
}

// The compose FAB is a brand button: its base color is Twitter blue, never iOS
// systemBlue. The accent is used only when one was actually picked, since without
// that the palette can resolve option 0 to systemBlue through the fallback.
static UIColor* PFBFABBlueColor(void) {
    extern UIColor* PFBCurrentAccentColor(void);
    NSUserDefaults* d = NSUserDefaults.standardUserDefaults;
    BOOL picked = [d objectForKey:@"pfb_custom_accent_hex"] ||
                  [d objectForKey:@"pfb_color_theme_selectedColor"] ||
                  [d integerForKey:@"T1ColorSettingsPrimaryColorOptionKey"] >= 1;
    if (picked) {
        return PFBCurrentAccentColor() ?: PFBTwitterBlue();
    }
    return PFBTwitterBlue();
}

static void styleComposeFAB(UIView* fab) {
    if (![PFBSettings boolForKey:@"restore_tweet_button"]) {
        PFBCOMPAT_OBSERVE(PFBCompat_restore_tweet_button, @"Tweet button found");
        return;
    }
    PFBCOMPAT_ACTION(PFBCompat_restore_tweet_button, @"Tweet button restyled");
    extern UIColor* PFBCurrentAccentColor(void);
    UIColor* blue = PFBFABBlueColor();
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
    PFBEnumerateSubviewsRecursively(fab, ^(UIView* sub) {
        if (sub == fab) {
            return;
        }
        if ([sub isKindOfClass:[UIImageView class]]) {
            UIImageView* imageView = (UIImageView*)sub;
            BOOL alreadyTagged =
                objc_getAssociatedObject(imageView, &kPFBFABGlyphKey) != nil;
            objc_setAssociatedObject(imageView, &kPFBFABGlyphKey, @YES,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            if (!alreadyTagged && imageView.image) {
                // First encounter: bake what is already there; every later
                // assignment goes through the setter hook and arrives baked.
                imageView.image = PFBWhiteBakedGlyph(imageView.image);
            }
            if (![imageView.tintColor isEqual:[UIColor whiteColor]]) {
                imageView.tintColor = [UIColor whiteColor];
            }
        } else if ([sub isKindOfClass:[UIVisualEffectView class]]) {
            UIVisualEffectView* effect = (UIVisualEffectView*)sub;
            if ([PFBSettings boolForKey:@"enable_liquid_glass"]) {
                objc_setAssociatedObject(effect, &kPFBFABGlassKey, @YES,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                PFBColorFABGlass(effect, blue);
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

// Weak handle to the live compose FAB so a color pick can restyle it
// immediately, without waiting for the next layout pass.
static __weak UIView* PFBComposeFABView;

// Called from PFBSyncAccentTheme (Theme.x) right after the accent changes.
void PFBRestyleComposeFAB(void) {
    void (^run)(void) = ^{
        // The cached handle is only a fast path: with the settings screen pushed,
        // the timeline's views are detached and the FAB is often rebuilt, so a stale
        // reference is normal. The live hierarchy is swept afterwards.
        UIView* known = PFBComposeFABView;
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
                PFBEnumerateSubviewsRecursively(window, ^(UIView* sub) {
                    if ([sub isKindOfClass:FABClass]) {
                        PFBComposeFABView = sub;
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

// Hiding the compose button is independent of restyling it: styleComposeFAB only
// paints. Whether the button was hidden here is recorded, so turning the option
// off restores it without forcing an untouched button visible.
static const void* kPFBFABHiddenByUsKey = &kPFBFABHiddenByUsKey;

static void pfbApplyComposeFABVisibility(UIView* fab) {
    if (!fab) {
        return;
    }
    BOOL wantHidden = [PFBSettings boolForKey:@"hide_tweet_button"];
    BOOL hiddenByUs = objc_getAssociatedObject(fab, kPFBFABHiddenByUsKey) != nil;
    if (!wantHidden) {
        PFBCOMPAT_OBSERVE(PFBCompat_hide_tweet_button, @"Tweet button found");
    }
    if (wantHidden) {
        PFBCOMPAT_ACTION(PFBCompat_hide_tweet_button, @"Tweet button hidden");
        fab.hidden = YES;
        fab.alpha = 0.0;
        fab.userInteractionEnabled = NO;
        if (!hiddenByUs) {
            objc_setAssociatedObject(fab, kPFBFABHiddenByUsKey, @YES,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    } else if (hiddenByUs) {
        fab.hidden = NO;
        fab.alpha = 1.0;
        fab.userInteractionEnabled = YES;
        objc_setAssociatedObject(fab, kPFBFABHiddenByUsKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

%hook TFNFloatingActionButton

// willMoveToWindow: fires before the button is ever drawn, so the white glyph
// tint and the disc color are in place for its very first frame — that first
// unstyled frame was the flash still visible on every tab change.
- (void)willMoveToWindow:(UIWindow*)newWindow {
    %orig;
    if (newWindow) {
        PFBComposeFABView = (UIView*)self;
        styleComposeFAB((UIView*)self);
        pfbApplyComposeFABVisibility((UIView*)self);
    }
}

- (void)didMoveToWindow {
    %orig;
    PFBComposeFABView = (UIView*)self;
    styleComposeFAB((UIView*)self);
    pfbApplyComposeFABVisibility((UIView*)self);
}

// The glass material and the glyph arrive as subviews after the button is
// attached, which willMoveToWindow: is too early to see. Styling them as they land
// colors them within the same transaction, before their first frame.
- (void)didAddSubview:(UIView*)subview {
    %orig;
    styleComposeFAB((UIView*)self);
}

- (void)layoutSubviews {
    %orig;
    PFBComposeFABView = (UIView*)self;
    styleComposeFAB((UIView*)self);
    pfbApplyComposeFABVisibility((UIView*)self);
}

%end

// Twitter swaps the glyph image on an existing image view during tab transitions,
// which the subview hook above does not cover. Only views styleComposeFAB has
// tagged are touched, so elsewhere this costs one associated-object lookup.
%hook UIImageView

// The glyph often sits inside the glass material's contentView, where the FAB's
// own didAddSubview: never fires. Tagged and templated at attach, in the same
// transaction; the ancestor walk is six levels at most.
- (void)willMoveToWindow:(UIWindow*)newWindow {
    %orig;
    if (!newWindow || objc_getAssociatedObject(self, &kPFBFABGlyphKey) ||
        ![PFBSettings boolForKey:@"restore_tweet_button"]) {
        return;
    }
    UIView* ancestor = self.superview;
    NSInteger depth = 0;
    while (ancestor && depth < 6) {
        if ([NSStringFromClass([ancestor class])
                containsString:@"FloatingActionButton"]) {
            objc_setAssociatedObject(self, &kPFBFABGlyphKey, @YES,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            if (self.image) {
                self.image = PFBWhiteBakedGlyph(self.image);
            }
            self.tintColor = [UIColor whiteColor];
            return;
        }
        ancestor = ancestor.superview;
        depth++;
    }
}

- (void)setImage:(UIImage*)image {
    // Baked at the setter, so the pixels that land are white whoever writes last.
    // A template glyph is only white while its tint survives; a baked one has
    // nothing left to lose.
    if (image && objc_getAssociatedObject(self, &kPFBFABGlyphKey)) {
        image = PFBWhiteBakedGlyph(image);
    } else if (image && objc_getAssociatedObject(self, &PFBConfirmGlyphTag) &&
               PFBColorThemeScreenVisible) {
        NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
        BOOL accentActive =
            [defaults boolForKey:@"pfb_custom_is_active"] ||
            [defaults objectForKey:@"pfb_color_theme_selectedColor"] != nil;
        if (accentActive) {
            image = PFBWhiteBakedGlyph(image);
        }
    }
    %orig(image);
}

%end

// The same principle applied to the disc: during a tab transition the glass
// material can arrive as a fresh UIVisualEffectView, colored only at the next
// styling pass. It is colored as it enters a window, in the same transaction.
%hook UIVisualEffectView

// The system re-installs the material's effect on each tab transition. Tinting the
// incoming effect here means the reset itself installs a colored material, with no
// extra assignment and no rebuild.
- (void)setEffect:(UIVisualEffect*)effect {
    if (effect && objc_getAssociatedObject(self, &kPFBFABGlassKey) &&
        [PFBSettings boolForKey:@"restore_tweet_button"] &&
        [PFBSettings boolForKey:@"enable_liquid_glass"] &&
        [effect respondsToSelector:@selector(setTintColor:)]) {
        extern UIColor* PFBCurrentAccentColor(void);
        UIColor* blue = PFBFABBlueColor();
        // The tweak's own installs pass through, tinted.
        if (PFBEffectInstallAllowed) {
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
    if (!newWindow || ![PFBSettings boolForKey:@"restore_tweet_button"] ||
        ![PFBSettings boolForKey:@"enable_liquid_glass"]) {
        return;
    }
    UIView* ancestor = self.superview;
    NSInteger depth = 0;
    while (ancestor && depth < 6) {
        if ([NSStringFromClass([ancestor class])
                containsString:@"FloatingActionButton"]) {
            objc_setAssociatedObject(self, &kPFBFABGlassKey, @YES,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            extern UIColor* PFBCurrentAccentColor(void);
            UIColor* blue = PFBFABBlueColor();
            PFBColorFABGlass(self, blue);
            return;
        }
        ancestor = ancestor.superview;
        depth++;
    }
}

// If anything clears the tagged material's color mid-transition, this
// re-asserts it within the same layout pass.
- (void)layoutSubviews {
    %orig;
    if (!objc_getAssociatedObject(self, &kPFBFABGlassKey)) {
        return;
    }
    extern UIColor* PFBCurrentAccentColor(void);
    UIColor* blue = PFBFABBlueColor();
    BOOL wasCleared = ![self.contentView.backgroundColor isEqual:blue] ||
                      ![self.backgroundColor isEqual:blue];
    PFBColorFABGlass(self, blue);
    if (wasCleared) {
    }
}

%end
