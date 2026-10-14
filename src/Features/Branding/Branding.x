// Twitter's terminology in localized and server-composed strings, the new Tweets pill
// (labeled or hidden), the compose button (classic style or hidden), the confirm glyph
// kept white on the color screen, and each vector image tagged with its name.

#import "Support/HookHelpers.h"
#import "Debug/PFBDebugger.h"
#import "Debug/PFBProbe.h"

// Defined in Theme.x.
extern UIImage* PFBWhiteBakedGlyph(UIImage* image);
extern char PFBConfirmGlyphTag;
extern NSInteger PFBThemeScreenCount;
extern BOOL PFBAccentIsActive(void);

// MARK: - Restore Twitter terminology

// Word replacements come from the bundle's RenameWords.strings, per language, with no
// fallback to English rules.

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
        // The first half of a compound ("post-season") is not the word itself.
        NSUInteger after = NSMaxRange(match.range);
        if (after < input.length && [input characterAtIndex:after] == '-') {
            continue;
        }
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
        PFBCOMPAT_ACTION(PFBCompat_restore_twitter_names, @"string renamed");
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

// Text filled in after the lookup the NSBundle hook sees, such as a plural format,
// in Twitter's terminology when the option is on.
NSString* PFBTwitterTerminology(NSString* text) {
    return text.length && [PFBSettings boolForKey:@"restore_twitter_names"] ? RestoreTwitterTerminology(text) : text;
}

// MARK: - Rename localized strings

// Every UI string routes through this Foundation method, so the rename applies
// broadly. PrimeFreeBird's own bundles are skipped so their strings are not reprocessed.
%hook NSBundle
- (NSString*)localizedStringForKey:(NSString*)key
                             value:(NSString*)value
                             table:(NSString*)tableName {
    NSString* result = %orig;
    if (![PFBSettings boolForKey:@"restore_twitter_names"]) {
        if (PFBCompatNeedsObservation(PFBCompat_restore_twitter_names) &&
            self != [PFBBundle sharedBundle].mainBundle && self != [PFBBundle sharedBundle].englishBundle) {
            PFBCOMPAT_OBSERVE(PFBCompat_restore_twitter_names, @"read by Twitter");
        }
        return result;
    }
    PFBBundle* tweak = [PFBBundle sharedBundle];
    if (self == tweak.mainBundle || self == tweak.englishBundle) {
        return result;
    }

    // A plural format carries its forms with it, which a renamed copy loses, and two keys
    // can share one format, which the memo below would mix up: it is left as it is.
    if ([result containsString:@"%#@"]) {
        return result;
    }
    return result.length > 0 ? RestoreTwitterTerminology(result) : result;
}
%end

// MARK: - Rename server-composed text

// The view holds people's own words: a Tweet body, a bio, a draft or a link card.
static BOOL PFBTextViewHoldsOwnWords(UIView* view) {
    static NSArray<Class>* containers;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray<Class>* found = [NSMutableArray array];
        for (NSString* name in @[
                 @"T1ProfileUserInfoView", @"T1UserView", @"T1UserRecommendationView",
                 @"T1TweetDraftsDraftCompositionView", @"T1WebCardView"
             ]) {
            Class container = NSClassFromString(name);
            if (container) {
                [found addObject:container];
            }
        }
        containers = found.copy;
    });
    if ([view isKindOfClass:%c(TTAStatusBodyAttributedTextView)]) {
        return YES;
    }
    UIView* node = view.superview;
    for (NSInteger up = 0; node && up < 6; up++, node = node.superview) {
        for (Class container in containers) {
            if ([node isKindOfClass:container]) {
                return YES;
            }
        }
    }
    return NO;
}

// Probe: the end-of-tour summaries of this file, registered once while debug tools record.
static void PFBBrandingProbeTourEnded(void);

static void PFBBrandingProbeArm(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      if (!PFBDebugIsRecording()) {
          return;
      }
      [[NSNotificationCenter defaultCenter] addObserverForName:PFBProbeTourEndedNotification
                                                        object:nil
                                                         queue:nil
                                                    usingBlock:^(__unused NSNotification* note) {
                                                      PFBBrandingProbeTourEnded();
                                                    }];
    });
}

// Probe (SC-8): renames applied outside the kept list, tallied by cell and slot with their
// count, replaced words and longest text length, never the text itself.
static char kPFBProbeRenameSlotKey;
static NSMutableDictionary<NSString*, NSMutableDictionary*>* gPFBProbeRenames;
static NSMutableDictionary<NSString*, NSArray*>* gPFBProbeIvarLists;
static NSUInteger gPFBProbeRenamesElsewhere;
static NSUInteger gPFBProbeRenameWalks;
static int gPFBProbeRenameState;

// Probe: a class's ivars as name and offset, up to its first UIKit or Foundation superclass.
static NSArray<NSArray*>* PFBProbeIvarList(Class cls) {
    NSString* className = NSStringFromClass(cls);
    NSArray<NSArray*>* known = gPFBProbeIvarLists[className];
    if (known) {
        return known;
    }
    NSMutableArray<NSArray*>* found = [NSMutableArray array];
    for (Class level = cls; level; level = class_getSuperclass(level)) {
        NSString* levelName = NSStringFromClass(level);
        if ([levelName hasPrefix:@"UI"] || [levelName hasPrefix:@"_UI"] || [levelName hasPrefix:@"NS"]) {
            break;
        }
        unsigned int count = 0;
        Ivar* ivars = class_copyIvarList(level, &count);
        for (unsigned int i = 0; i < count; i++) {
            const char* name = ivar_getName(ivars[i]);
            if (name) {
                [found addObject:@[ @(name), @(ivar_getOffset(ivars[i])) ]];
            }
        }
        free(ivars);
    }
    if (!gPFBProbeIvarLists) {
        gPFBProbeIvarLists = [NSMutableDictionary dictionary];
    }
    gPFBProbeIvarLists[className] = found;
    return found;
}

// Probe: the ivar of holder whose raw value is one of the views, compared as a pointer and
// never retained or messaged; the earliest view in the list wins and its position is returned.
static NSString* PFBProbeSlotHolding(id holder, NSArray<UIView*>* views, NSUInteger* position) {
    Class cls = object_getClass(holder);
    size_t size = class_getInstanceSize(cls);
    NSArray<NSArray*>* ivars = PFBProbeIvarList(cls);
    const uint8_t* base = (const uint8_t*)(__bridge const void*)holder;
    for (NSUInteger i = 0; i < views.count; i++) {
        const void* wanted = (__bridge const void*)views[i];
        for (NSArray* ivar in ivars) {
            long offset = [ivar[1] longValue];
            if (offset < 0 || offset % (long)sizeof(void*) != 0 || (size_t)offset + sizeof(void*) > size) {
                continue;
            }
            if (*(const void* const*)(base + offset) == wanted) {
                if (position) {
                    *position = i;
                }
                return ivar[0];
            }
        }
    }
    return nil;
}

// Probe: "Host.slot TextViewClass", the host being the cell holding the text view, or its
// controller when no cell does; inCell says whether a cell was found.
static NSString* PFBProbeRenameSlot(UIView* textView, BOOL* inCell) {
    NSMutableArray<UIView*>* below = [NSMutableArray arrayWithObject:textView];
    id host = nil;
    for (UIView* node = textView.superview; node && below.count < 14; node = node.superview) {
        if ([node isKindOfClass:[UITableViewCell class]] || [node isKindOfClass:[UICollectionViewCell class]]) {
            host = node;
            break;
        }
        [below addObject:node];
    }
    *inCell = host != nil;
    NSString* hostName = host ? NSStringFromClass([host class]) : nil;
    if (!host) {
        host = PFBProbeControllerOfView(textView);
        hostName = [NSString stringWithFormat:@"%@ (no cell)", PFBProbeClassName(host)];
    }
    NSUInteger hit = 0;
    NSString* slot = host ? PFBProbeSlotHolding(host, below, &hit) : nil;
    if (slot && hit > 0) {
        NSString* inner = PFBProbeSlotHolding(below[hit], [below subarrayWithRange:NSMakeRange(0, hit)], NULL);
        if (inner) {
            slot = [NSString stringWithFormat:@"%@.%@", slot, inner];
        }
    }
    return [NSString stringWithFormat:@"%@.%@ %@", hostName, slot ?: @"?", NSStringFromClass([textView class])];
}

static void PFBProbeRenamedOutside(UIView* textView, NSAttributedString* source) {
    if (gPFBProbeRenameState == 2 || !NSThread.isMainThread) {
        return;
    }
    if (gPFBProbeRenameState == 0) {
        gPFBProbeRenameState = PFBProbeWants(@"SC-8 tour") ? 1 : 2;
        if (gPFBProbeRenameState == 2) {
            return;
        }
        PFBBrandingProbeArm();
    }
    NSString* pair = objc_getAssociatedObject(textView, &kPFBProbeRenameSlotKey);
    if (!pair) {
        if (gPFBProbeRenameWalks >= 2000) {
            return;
        }
        gPFBProbeRenameWalks++;
        BOOL inCell = NO;
        pair = PFBProbeRenameSlot(textView, &inCell);
        if (inCell) {
            objc_setAssociatedObject(textView, &kPFBProbeRenameSlotKey, pair, OBJC_ASSOCIATION_COPY_NONATOMIC);
        }
    }
    if (!gPFBProbeRenames) {
        gPFBProbeRenames = [NSMutableDictionary dictionary];
    }
    NSMutableDictionary* tally = gPFBProbeRenames[pair];
    if (!tally) {
        if (gPFBProbeRenames.count >= 10) {
            gPFBProbeRenamesElsewhere++;
            return;
        }
        tally = [@{@"n": @0, @"len": @0, @"words": [NSMutableOrderedSet orderedSet]} mutableCopy];
        gPFBProbeRenames[pair] = tally;
    }
    NSUInteger seen = [tally[@"n"] unsignedIntegerValue] + 1;
    tally[@"n"] = @(seen);
    if (source.length > [tally[@"len"] unsignedIntegerValue]) {
        tally[@"len"] = @(source.length);
    }
    NSMutableOrderedSet<NSString*>* words = tally[@"words"];
    if (seen <= 8 && words.count < 4) {
        for (NSDictionary* edit in RenameEdits(source.string)) {
            if (words.count < 4) {
                [words addObject:[source.string substringWithRange:[edit[@"range"] rangeValue]].lowercaseString];
            }
        }
    }
}

// TFNAttributedTextView renders text carrying no localization key, out of the NSBundle
// hook's reach. The new string is set on the model received, which keeps its line limit
// and its trailing "more" text.
%hook TFNAttributedTextView
- (void)setTextModel:(TFNAttributedTextModel*)model {
    NSAttributedString* source = model.attributedString;
    if (source.length == 0) {
        %orig(model);
        return;
    }
    if (![PFBSettings boolForKey:@"restore_twitter_names"]) {
        PFBCOMPAT_OBSERVE(PFBCompat_restore_twitter_names, @"server text shown");
        %orig(model);
        return;
    }
    if ([model respondsToSelector:@selector(setAttributedString:)] && !PFBTextViewHoldsOwnWords(self)) {
        NSAttributedString* renamed = RestoreTwitterAttributed(source);
        if (renamed != source) {
            [model setAttributedString:renamed];
            PFBCOMPAT_ACTION(PFBCompat_restore_twitter_names, @"text renamed");
            // Probe: the cell and slot of this rename outside the kept list.
            PFBProbeRenamedOutside(self, source);
        }
    }
    %orig(model);
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
// the feather in white, and the FAB is painted Twitter blue, or the picked accent.

static UIColor* PFBTwitterBlue(void) {
    return [UIColor colorWithRed:0x1D / 255.0
                           green:0xA1 / 255.0
                            blue:0xF2 / 255.0
                           alpha:1.0];
}

static BOOL isComposePlusGlyph(NSString* name) {
    if (![name isKindOfClass:[NSString class]]) {
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
    return [composeGlyphs containsObject:name] && [PFBSettings boolForKey:@"restore_tweet_button"];
}

// Probe (11#F029, 14b#F007, 14a#F022): each white feather handed out for a compose glyph
// carries that glyph's name, so the image views it lands in can be told apart.
static char kPFBProbeFeatherNameKey;
static BOOL gPFBProbeFeatherOpen;
static BOOL gPFBProbeFeatherDone;

static id PFBProbeFeatherFor(id image, id name) {
    if (!gPFBProbeFeatherDone && PFBDebugIsRecording() && image && [name isKindOfClass:[NSString class]]) {
        objc_setAssociatedObject(image, &kPFBProbeFeatherNameKey, name, OBJC_ASSOCIATION_COPY_NONATOMIC);
        gPFBProbeFeatherOpen = YES;
        PFBBrandingProbeArm();
    }
    return image;
}

// Every vector the app loads by name keeps that name on the image, under the
// loader's own selector as the key so any file can read it back without a
// shared declaration. It is how a bar button is told apart by what it shows.
static id PFBNamedVector(id image, id name) {
    if (image && [name isKindOfClass:[NSString class]]) {
        objc_setAssociatedObject(image, @selector(tfn_vectorImageNamed:fitsSize:fillColor:),
                                 name, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    // Probe: a feather Twitter asks for itself is not one handed out for a compose glyph.
    if (gPFBProbeFeatherOpen && image && [name isEqual:@"feather"]) {
        objc_setAssociatedObject(image, &kPFBProbeFeatherNameKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
    }
    return image;
}

%hook UIImage

+ (id)tfn_vectorImageNamed:(id)name fitsSize:(CGSize)size fillColor:(id)color {
    if (isComposePlusGlyph(name)) {
        return PFBProbeFeatherFor(%orig(@"feather", size, [UIColor whiteColor]), name);
    }
    return PFBNamedVector(%orig(name, size, color), name);
}

+ (id)tfn_vectorImageNamed:(id)name
    highContrastVariantNamed:(id)variant
                    fitsSize:(CGSize)size
                   fillColor:(id)color {
    if (isComposePlusGlyph(name)) {
        return PFBProbeFeatherFor(%orig(@"feather", variant, size, [UIColor whiteColor]), name);
    }
    return PFBNamedVector(%orig(name, variant, size, color), name);
}

+ (id)tfn_vectorImageNamed:(id)name height:(double)height fillColor:(id)color {
    if (isComposePlusGlyph(name)) {
        return PFBProbeFeatherFor(%orig(@"feather", height, [UIColor whiteColor]), name);
    }
    return PFBNamedVector(%orig(name, height, color), name);
}

%end

// The compose FAB is a plain UIView subclass, so style it directly: blue
// disc, white glyphs, and any internal chrome (gray disc, blur) neutralised.
@interface TFNFloatingActionButton : UIView
@end

// Tag set on the FAB's glyph image views so the UIImageView hook below can
// recognize them in O(1) and bake swapped-in images white.
static char kPFBFABGlyphKey;
// Set while an effect is being installed here, so the setEffect: hook lets it
// through. Without it that hook swallows and re-tints in a loop, and the material
// is never tinted.
static BOOL PFBEffectInstallAllowed;
// The tint last installed here. UIVisualEffectView.effect vends copies whose tintColor
// does not round-trip, so mismatches are detected against this shadow instead.
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
    UIColor* blue = PFBFABBlueColor();
    if (![fab.backgroundColor isEqual:blue]) {
        fab.backgroundColor = blue;
    }
    CGFloat radius = MIN(fab.bounds.size.width, fab.bounds.size.height) / 2.0;
    if (fab.layer.cornerRadius != radius) {
        fab.layer.cornerRadius = radius;
    }
    fab.clipsToBounds = YES;
    // The button itself takes a white tint so any template glyph is white from its very
    // first render; tinting only the image view leaves one black frame on a tab change.
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

// Probe (14a#F009): whether the Tweet button is hidden in the launch Hide Tweet button is
// switched on, and how long after the switch; one line, hidden or not, for the person's own
// switch and one for the tour's (each marks its own moment), so neither hides the other.
static int gPFBProbeHideState[2];

static void PFBProbeTweetButtonVisibility(UIView* fab, BOOL wantHidden) {
    if (gPFBProbeHideState[0] == 2 && gPFBProbeHideState[1] == 2) {
        return;
    }
    if (gPFBProbeHideState[0] == 0) {
        gPFBProbeHideState[0] = PFBProbeWants(@"14a#F009 hide") ? 1 : 2;
        gPFBProbeHideState[1] = PFBProbeWants(@"14a#F009 hide tour") ? 1 : 2;
    }
    for (NSUInteger slot = 0; slot < 2; slot++) {
        if (gPFBProbeHideState[slot] != 1) {
            continue;
        }
        CFTimeInterval age = PFBProbeMarkAge(slot ? @"hide_tweet_button on (tour)" : @"hide_tweet_button on");
        if (age < 0) {
            continue;
        }
        gPFBProbeHideState[slot] = 2;
        NSString* key = slot ? @"14a#F009 hide tour" : @"14a#F009 hide";
        NSString* who = slot ? @"the tour's switch" : @"the switch";
        if (wantHidden) {
            PFBProbeNote(key,
                         @"14a#F009 Tweet button hidden %.1f s after %@, no relaunch (in a window: %@, screen in front: %@)",
                         age, who, fab.window ? @"yes" : @"no", PFBProbeFrontScreen());
        } else {
            PFBProbeNote(key,
                         @"14a#F009 Tweet button not hidden: not laid out while the option was on, laid out again %.1f s after %@ with the option off",
                         age, who);
        }
    }
}

// Probe (14a#F009): the screens the Tweet button shows on, by owning controller and screen in
// front, up to six, sampled at most twice a second.
static BOOL gPFBProbeShownDone;
static NSUInteger gPFBProbeShownNotes;
static NSUInteger gPFBProbeShownLooks;
static CFTimeInterval gPFBProbeShownLast;

static void PFBProbeTweetButtonShown(UIView* fab) {
    if (gPFBProbeShownDone || !PFBDebugIsRecording()) {
        return;
    }
    CFTimeInterval now = CACurrentMediaTime();
    if (!fab.window || fab.hidden || fab.alpha < 0.01 || now - gPFBProbeShownLast < 0.5) {
        return;
    }
    gPFBProbeShownLast = now;
    gPFBProbeShownLooks++;
    NSString* owner = PFBProbeClassName(PFBProbeControllerOfView(fab));
    NSString* front = PFBProbeFrontScreen();
    NSString* key = [NSString stringWithFormat:@"14a#F009 shown %@ %@", owner, front];
    if (PFBProbeWants(key)) {
        gPFBProbeShownNotes++;
        PFBProbeNote(key, @"14a#F009 Tweet button shown on %@ (screen in front: %@)", owner, front);
    }
    gPFBProbeShownDone = gPFBProbeShownNotes >= 6 || gPFBProbeShownLooks >= 600;
}

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
    // Probe: the first pass after Hide Tweet button is switched on in this launch.
    PFBProbeTweetButtonVisibility(fab, wantHidden);
}

%hook TFNFloatingActionButton

// willMoveToWindow: fires before the button is ever drawn, so the white glyph tint and
// the disc color are in place for its very first frame.
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
    // Probe: the screen the button shows on.
    PFBProbeTweetButtonShown((UIView*)self);
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
    // Probe: the screen the button shows on.
    PFBProbeTweetButtonShown((UIView*)self);
}

%end

// Probe (11#F029, 14b#F007, 14a#F022): where a feather handed out for a compose glyph is
// shown, inside the Tweet button or not; each image view is examined once per glyph name.
static char kPFBProbeFeatherSeenKey;
static NSUInteger gPFBProbeFeatherInside;
static NSUInteger gPFBProbeFeatherInsideNotes;
static NSUInteger gPFBProbeFeatherOutsideNotes;
static NSMutableOrderedSet<NSString*>* gPFBProbeFeatherOutside;

static void PFBProbeFeatherLanded(UIImageView* view, UIImage* image, BOOL arriving) {
    NSString* name = image ? objc_getAssociatedObject(image, &kPFBProbeFeatherNameKey) : nil;
    if (!name || !NSThread.isMainThread || [objc_getAssociatedObject(view, &kPFBProbeFeatherSeenKey) isEqual:name]) {
        return;
    }
    BOOL inside = objc_getAssociatedObject(view, &kPFBFABGlyphKey) != nil;
    NSMutableArray<NSString*>* chain = [NSMutableArray array];
    UIView* node = view.superview;
    for (NSInteger depth = 0; node && depth < 8; depth++, node = node.superview) {
        NSString* className = NSStringFromClass([node class]);
        if (chain.count < 4) {
            [chain addObject:className];
        }
        inside = inside || [className containsString:@"FloatingActionButton"];
    }
    // A view off screen and outside the button is examined again as it arrives.
    if (!arriving && !view.window && !inside) {
        return;
    }
    objc_setAssociatedObject(view, &kPFBProbeFeatherSeenKey, name, OBJC_ASSOCIATION_COPY_NONATOMIC);
    NSString* controller = PFBProbeClassName(PFBProbeControllerOfView(view));
    NSString* place = chain.count ? [chain componentsJoinedByString:@"/"] : @"no superview";
    if (inside) {
        gPFBProbeFeatherInside++;
        NSString* key = [NSString stringWithFormat:@"14b#F007 yes %@ %@ %@", name, controller, place];
        if (gPFBProbeFeatherInsideNotes < 6 && PFBProbeWants(key)) {
            gPFBProbeFeatherInsideNotes++;
            PFBProbeNote(key, @"14b#F007 compose glyph '%@' shown as the white feather on %@ in %@, inside the Tweet button: yes",
                         name, controller, place);
        }
    } else {
        if (!gPFBProbeFeatherOutside) {
            gPFBProbeFeatherOutside = [NSMutableOrderedSet orderedSet];
        }
        if (gPFBProbeFeatherOutside.count < 10) {
            [gPFBProbeFeatherOutside addObject:[NSString stringWithFormat:@"'%@' on %@", name, controller]];
        }
        NSString* key = [NSString stringWithFormat:@"11#F029 %@ %@ %@", name, controller, place];
        if (gPFBProbeFeatherOutsideNotes < 10 && PFBProbeWants(key)) {
            gPFBProbeFeatherOutsideNotes++;
            PFBProbeNote(key,
                         @"11#F029/14b#F007/14a#F022 compose glyph '%@' shown as the white feather on %@ in %@, inside the Tweet button: no",
                         name, controller, place);
        }
    }
    if (gPFBProbeFeatherInsideNotes >= 6 && gPFBProbeFeatherOutsideNotes >= 10) {
        gPFBProbeFeatherOpen = NO;
        gPFBProbeFeatherDone = YES;
    }
}

// Twitter swaps the glyph image on an existing image view during tab transitions,
// which the subview hook above does not cover. Only the FAB's glyphs and the
// navigation bar's confirm glyph are touched.
%hook UIImageView

// The glyph often sits inside the glass material's contentView, where the FAB's
// own didAddSubview: never fires. Tagged and baked white at attach, in the same
// transaction; the ancestor walk is six levels at most.
- (void)willMoveToWindow:(UIWindow*)newWindow {
    %orig;
    // Probe: a feather handed out for a compose glyph, examined as its view arrives.
    if (gPFBProbeFeatherOpen && newWindow) {
        PFBProbeFeatherLanded(self, self.image, YES);
    }
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
    // Probe: a feather handed out for a compose glyph, examined where it is set.
    if (gPFBProbeFeatherOpen && image) {
        PFBProbeFeatherLanded(self, image, NO);
    }
    // Baked at the setter, so the pixels that land are white whoever writes last.
    // A template glyph is only white while its tint survives; a baked one has
    // nothing left to lose.
    if (image && objc_getAssociatedObject(self, &kPFBFABGlyphKey)) {
        image = PFBWhiteBakedGlyph(image);
    } else if (image && objc_getAssociatedObject(self, &PFBConfirmGlyphTag) && PFBThemeScreenCount &&
               PFBAccentIsActive()) {
        image = PFBWhiteBakedGlyph(image);
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
        UIColor* blue = PFBFABBlueColor();
        // Installs made here pass through, tinted.
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
    UIColor* blue = PFBFABBlueColor();
    PFBColorFABGlass(self, blue);
}

%end

// Probe: the end-of-tour lines of 14a#F022 and SC-8, written once a full tour has run to its end.
static void PFBBrandingProbeTourEnded(void) {
    if (![PFBCompatTourLastRun() hasPrefix:@"Full tour"]) {
        return;
    }
    if (PFBProbeWants(@"14a#F022 tour")) {
        NSString* outside = gPFBProbeFeatherOutside.count
                                ? [gPFBProbeFeatherOutside.array componentsJoinedByString:@", "]
                                : @"none";
        PFBProbeNote(@"14a#F022 tour",
                     @"14a#F022 feather outside the Tweet button by the end of the tour: %@ (image views showing it inside the button in this launch: %lu, Classic Tweet button %@)",
                     outside, (unsigned long)gPFBProbeFeatherInside,
                     [PFBSettings boolForKey:@"restore_tweet_button"] ? @"on" : @"off");
    }
    if (gPFBProbeRenameState != 2 && PFBProbeWants(@"SC-8 tour")) {
        NSMutableArray<NSString*>* parts = [NSMutableArray array];
        NSArray<NSString*>* pairs = [gPFBProbeRenames
            keysSortedByValueUsingComparator:^NSComparisonResult(NSDictionary* a, NSDictionary* b) {
              return [(NSNumber*)b[@"n"] compare:(NSNumber*)a[@"n"]];
            }];
        for (NSString* pair in pairs) {
            NSDictionary* tally = gPFBProbeRenames[pair];
            NSOrderedSet<NSString*>* words = tally[@"words"];
            [parts addObject:[NSString stringWithFormat:@"%@ \u00d7%@ (%@, len\u2264%@)", pair, tally[@"n"],
                                                        words.count ? [words.array componentsJoinedByString:@"/"] : @"?",
                                                        tally[@"len"]]];
        }
        if (gPFBProbeRenamesElsewhere) {
            [parts addObject:[NSString stringWithFormat:@"+%lu renames on other slots",
                                                        (unsigned long)gPFBProbeRenamesElsewhere]];
        }
        PFBProbeNote(@"SC-8 tour", @"SC-8 renamed outside the kept list: %@%@",
                     parts.count ? [parts componentsJoinedByString:@"; "] : @"none",
                     [PFBSettings boolForKey:@"restore_twitter_names"] ? @"" : @" (Restore Twitter terminology off)");
        gPFBProbeRenameState = 2;
    }
}
