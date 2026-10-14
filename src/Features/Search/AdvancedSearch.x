// A Filters button in the Explore bar that opens the native Advanced Search form,
// with the app's own filter button collapsed inside the search bar. The glyph is
// drawn here at the settings gear's stroke, since no library glyph matches it.

#import "Support/HookHelpers.h"
#import "Debug/PFBDebugger.h"
#import "Debug/PFBProbe.h"
#import "Features/Search/PFBAdvancedSearchViewController.h"
#import <objc/runtime.h>
#import <objc/message.h>

static const void* kPFBAdvSearchBtnKey = &kPFBAdvSearchBtnKey;
static const void* kPFBAdvSearchGreyKey = &kPFBAdvSearchGreyKey;
static const void* kPFBAdvHiddenByTweakKey = &kPFBAdvHiddenByTweakKey;
static const void* kPFBAdvFlagBackupKey = &kPFBAdvFlagBackupKey;

// Rows of Twitter's filter glyph on a 24-point grid: {center y, handle center x}.
// The upper handle sits right of center and the lower one left, so the two rows
// read as two settings. A block cannot capture a local C array.
static const CGFloat kPFBSliderGeometry[2][2] = {{8.0, 14.0}, {16.0, 10.0}};

// The glyph is drawn in its final color and returned as an original image, so
// no tint can reach it: a template would inherit the bar's accent between its
// creation and the first pass of the gray sweep next door.
static UIImage* PFBSlidersGlyph(CGFloat side, UIColor* colour) {
    const CGFloat kUnit = 24.0;
    // Stroke on the 24-unit grid, lighter than the gear's nominal weight: the gear's glyph
    // stands taller, so an equal stroke would read heavier here.
    const CGFloat kThickness = 1.75;
    // Large enough for the ring's opening to read at actual size, with the rail meeting
    // the ring; a smaller radius closes the ring into a dot.
    const CGFloat kHandleRadius = 2.8;
    const CGFloat kInset = 3.0;
    CGFloat scale = side / kUnit;
    CGFloat half = kThickness / 2.0;
    UIGraphicsImageRendererFormat* format =
        [UIGraphicsImageRendererFormat preferredFormat];
    format.opaque = NO;
    UIGraphicsImageRenderer* renderer =
        [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)
                                               format:format];
    UIImage* drawn = [renderer
        imageWithActions:^(UIGraphicsImageRendererContext* context) {
            CGContextRef ctx = context.CGContext;
            [(colour ?: [UIColor blackColor]) setStroke];
            CGContextSetLineWidth(ctx, kThickness * scale);
            // Round caps and joins, as the app's own glyphs are drawn.
            CGContextSetLineCap(ctx, kCGLineCapRound);
            CGContextSetLineJoin(ctx, kCGLineJoinRound);
            // The handle's outer edge, half a stroke beyond its radius.
            CGFloat reach = kHandleRadius + half;
            for (NSInteger i = 0; i < 2; i++) {
                CGFloat cy = kPFBSliderGeometry[i][0];
                CGFloat cx = kPFBSliderGeometry[i][1];
                // Rail up to the handle, then on from its far side.
                CGContextMoveToPoint(ctx, kInset * scale, cy * scale);
                CGContextAddLineToPoint(ctx, (cx - reach) * scale, cy * scale);
                CGContextStrokePath(ctx);
                CGContextMoveToPoint(ctx, (cx + reach) * scale, cy * scale);
                CGContextAddLineToPoint(ctx, (kUnit - kInset) * scale, cy * scale);
                CGContextStrokePath(ctx);
                // The handle: a ring, like the gear's center.
                CGContextAddArc(ctx, cx * scale, cy * scale,
                                kHandleRadius * scale, 0.0, M_PI * 2.0, 0);
                CGContextStrokePath(ctx);
            }
        }];
    return [drawn imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

static UIColor* PFBBarIconGrey(UITraitCollection* traits) {
    UIColor* grey = [[UIColor labelColor] colorWithAlphaComponent:0.6];
    if (traits && [grey respondsToSelector:@selector(resolvedColorWithTraitCollection:)]) {
        return [grey resolvedColorWithTraitCollection:traits] ?: grey;
    }
    return grey;
}

// MARK: - the app's own Filters button

// Every search results screen carries a sliders button opening the native Filters
// tray, drawn with the same glyph as this form's on Explore, so the native item is
// replaced. It is told apart by the vector it shows, or by its accessibility label.

// Presents the Advanced Search form as a page sheet over the given controller.
static void pfbAdvPresentForm(UIViewController* owner) {
    PFBAdvancedSearchViewController* form = [[PFBAdvancedSearchViewController alloc] init];
    UINavigationController* nav =
        [[UINavigationController alloc] initWithRootViewController:form];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    [owner presentViewController:nav animated:YES completion:nil];
}

// Probe: the first tap on a replacement, with the state of the controller it opens over
// (11#F032).
static void pfbAdvProbeLaunch(UIViewController* owner) {
    if (!PFBProbeWants(@"11#F032 launch")) {
        return;
    }
    NSString* state = !owner ? @"gone" : (owner.presentedViewController ? @"presenting" : @"present");
    PFBProbeNote(@"11#F032 launch",
                 @"11#F032 advanced search: replacement tapped, owner %@ (%@, in a window %@), %@ in front", state,
                 PFBProbeClassName(owner), owner.viewIfLoaded.window ? @"yes" : @"no", PFBProbeFrontScreen());
}

@interface PFBAdvSearchLauncher : NSObject
@property (nonatomic, weak) UIViewController* owner;
- (void)launch:(id)sender;
@end

@implementation PFBAdvSearchLauncher
- (void)launch:(id)sender {
    UIViewController* owner = self.owner;
    pfbAdvProbeLaunch(owner);
    if (!owner || owner.presentedViewController) {
        return;
    }
    pfbAdvPresentForm(owner);
}
@end

static const void* kPFBAdvLauncherKey = &kPFBAdvLauncherKey;
static const void* kPFBAdvReplacedKey = &kPFBAdvReplacedKey;

static NSString* pfbAdvVectorName(UIImage* image) {
    return image ? objc_getAssociatedObject(
                       image, @selector(tfn_vectorImageNamed:fitsSize:fillColor:))
                 : nil;
}

#define kPFBAdvMaskSide ((size_t)24)

static BOOL pfbAdvRenderMask(UIImage* image, uint8_t* pixels) {
    if (!image.CGImage) {
        return NO;
    }
    CGColorSpaceRef gray = CGColorSpaceCreateDeviceGray();
    CGContextRef context = CGBitmapContextCreate(pixels, kPFBAdvMaskSide, kPFBAdvMaskSide, 8,
                                                 kPFBAdvMaskSide, gray, kCGImageAlphaOnly);
    CGColorSpaceRelease(gray);
    if (!context) {
        return NO;
    }
    memset(pixels, 0, kPFBAdvMaskSide * kPFBAdvMaskSide);
    CGContextDrawImage(context, CGRectMake(0, 0, kPFBAdvMaskSide, kPFBAdvMaskSide),
                       image.CGImage);
    CGContextRelease(context);
    return YES;
}

// The sliders glyph as a 24-point alpha mask, drawn from the app's own vector
// so it matches what the app draws elsewhere. Rendered once.
static const uint8_t* pfbAdvSlidersMask(void) {
    static uint8_t mask[kPFBAdvMaskSide * kPFBAdvMaskSide];
    static BOOL ready = NO;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      if ([UIImage respondsToSelector:@selector(tfn_vectorImageNamed:fitsSize:fillColor:)]) {
          UIImage* glyph = [UIImage tfn_vectorImageNamed:@"settings_slider"
                                                fitsSize:CGSizeMake(kPFBAdvMaskSide, kPFBAdvMaskSide)
                                               fillColor:[UIColor blackColor]];
          ready = pfbAdvRenderMask(glyph, mask);
      }
    });
    return ready ? mask : NULL;
}

// How much of two 24-point masks agree, both thresholded at half alpha.
static double pfbAdvMaskAgreement(UIImage* image) {
    const uint8_t* reference = pfbAdvSlidersMask();
    if (!reference || !image) {
        return 0;
    }
    uint8_t candidate[kPFBAdvMaskSide * kPFBAdvMaskSide];
    if (!pfbAdvRenderMask(image, candidate)) {
        return 0;
    }
    size_t agree = 0;
    size_t inked = 0;
    for (size_t i = 0; i < kPFBAdvMaskSide * kPFBAdvMaskSide; i++) {
        BOOL a = reference[i] > 127;
        BOOL b = candidate[i] > 127;
        if (a || b) {
            inked++;
            if (a == b) {
                agree++;
            }
        }
    }
    return inked ? (double)agree / (double)inked : 0;
}

// The first image an item shows: on the item itself, or inside a custom view (the
// search screen's items are TFNBarButtonItemButton views with a plain UIImageView
// inside, carrying no name or label).
static UIImage* pfbAdvItemImage(UIBarButtonItem* item) {
    if (item.image) {
        return item.image;
    }
    __block UIImage* image = nil;
    if (item.customView) {
        PFBEnumerateSubviewsRecursively(item.customView, ^(UIView* view) {
            if (!image && [view isKindOfClass:[UIImageView class]]) {
                image = [(UIImageView*)view image];
            }
        });
    }
    return image;
}

// Probe: what recognized the last Filters item, read by the replacement notes below.
static NSString* gPFBAdvProbeMatch = nil;

// Probe: the first Filters item recognized in this build, with its vector name, label and
// pixel agreement side by side; the tweak's own Explore button is noted apart (11#F023).
static void pfbAdvProbeFiltersMatch(UIBarButtonItem* item, NSString* reason) {
    if (!PFBDebugIsRecording()) {
        return;
    }
    UIImage* image = pfbAdvItemImage(item);
    NSString* name = pfbAdvVectorName(image);
    NSString* label = item.accessibilityLabel ?: item.customView.accessibilityLabel;
    if (label.length > 32) {
        label = [label substringToIndex:32];
    }
    double agreement = pfbAdvMaskAgreement(image);
    BOOL own = objc_getAssociatedObject(item, kPFBAdvSearchGreyKey) != nil;
    NSString* detail = [reason isEqualToString:@"name"]    ? [@"vector " stringByAppendingString:name ?: @"?"]
                       : [reason isEqualToString:@"label"] ? [@"label " stringByAppendingString:label ?: @"?"]
                                                           : [NSString stringWithFormat:@"pixels %.2f", agreement];
    gPFBAdvProbeMatch = own ? [detail stringByAppendingString:@" (the tweak's Explore button)"] : detail;
    NSString* key = own ? @"11#F023 own button" : @"11#F023 filters item";
    if (!PFBProbeWants(key)) {
        return;
    }
    PFBProbeNote(key, @"11#F023 advsearch filters item%@: matched by %@ name=%@ label=%@ agreement=%.2f",
                 own ? @" (the tweak's Explore button)" : @"", reason, name ?: @"nil", label ?: @"nil", agreement);
}

static BOOL pfbAdvIsFiltersItem(UIBarButtonItem* item) {
    if (objc_getAssociatedObject(item, kPFBAdvReplacedKey)) {
        return NO;
    }
    NSSet* glyphs = [NSSet setWithObjects:@"settings_slider", @"filter_bars", nil];
    UIImage* image = pfbAdvItemImage(item);
    NSString* name = pfbAdvVectorName(image);
    if (name && [glyphs containsObject:name]) {
        pfbAdvProbeFiltersMatch(item, @"name");
        return YES;
    }
    NSString* label = item.accessibilityLabel ?: item.customView.accessibilityLabel;
    NSSet* labels = [NSSet setWithObjects:@"Filters", @"Filter", @"Filtres", @"Filtre", nil];
    if (label && [labels containsObject:label]) {
        pfbAdvProbeFiltersMatch(item, @"label");
        return YES;
    }
    // Neither a name nor a label: the pixels decide. The same vector drawn by
    // the app's Swift icon code and by its ObjC loader agrees almost entirely;
    // any other glyph in this bar agrees far less.
    BOOL drawn = pfbAdvMaskAgreement(image) >= 0.85;
    if (drawn) {
        pfbAdvProbeFiltersMatch(item, @"pixels");
    }
    return drawn;
}

// The color the bar's other items are drawn in: the label color on the results screen,
// gray on Explore. The neighbor decides, and the Explore gray is the fallback.
static UIColor* pfbAdvNeighbourTint(UINavigationItem* item, UIViewController* owner) {
    NSMutableArray<UIBarButtonItem*>* candidates = [NSMutableArray array];
    [candidates addObjectsFromArray:item.rightBarButtonItems ?: @[]];
    if (@available(iOS 16.0, *)) {
        for (UIBarButtonItemGroup* group in item.trailingItemGroups) {
            [candidates addObjectsFromArray:group.barButtonItems];
        }
    }
    for (UIBarButtonItem* entry in candidates) {
        if (objc_getAssociatedObject(entry, kPFBAdvReplacedKey)) {
            continue;
        }
        __block UIColor* tint = nil;
        if (entry.customView) {
            PFBEnumerateSubviewsRecursively(entry.customView, ^(UIView* view) {
                if (!tint && [view isKindOfClass:[UIImageView class]] && view.tintColor) {
                    tint = view.tintColor;
                }
            });
        } else if (entry.tintColor) {
            tint = entry.tintColor;
        }
        if (tint) {
            return tint;
        }
    }
    return PFBBarIconGrey(owner.traitCollection);
}

static UIBarButtonItem* pfbAdvReplacementFor(UIViewController* owner) {
    UIColor* grey = pfbAdvNeighbourTint(owner.navigationItem, owner);
    PFBAdvSearchLauncher* launcher = [PFBAdvSearchLauncher new];
    launcher.owner = owner;
    UIBarButtonItem* btn = [[UIBarButtonItem alloc] initWithImage:PFBSlidersGlyph(27.33, grey)
                                                            style:UIBarButtonItemStylePlain
                                                           target:launcher
                                                           action:@selector(launch:)];
    btn.tintColor = grey;
    btn.accessibilityLabel = [[PFBBundle sharedBundle] localizedStringForKey:@"ADVANCED_SEARCH_TITLE"];
    if ([btn respondsToSelector:@selector(setHidesSharedBackground:)]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(btn, @selector(setHidesSharedBackground:), YES);
    }
    // The item holds its launcher; the launcher only holds the owner weakly.
    objc_setAssociatedObject(btn, kPFBAdvLauncherKey, launcher, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(btn, kPFBAdvReplacedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return btn;
}

// An active search bar puts Cancel in the same trailing group. The app shows
// nothing else beside it, so the entry is taken out while it is there.
static BOOL pfbAdvGroupHasCancel(NSArray<UIBarButtonItem*>* items) {
    NSString* cancel = [[PFBBundle sharedBundle]
        localizedTwitterStringForKey:@"CANCEL_ACTION_LABEL"];
    if (cancel.length == 0) {
        return NO;
    }
    for (UIBarButtonItem* entry in items) {
        if ([entry.title isEqualToString:cancel]) {
            return YES;
        }
    }
    return NO;
}

static BOOL pfbAdvIsOurs(UIBarButtonItem* entry) {
    return objc_getAssociatedObject(entry, kPFBAdvReplacedKey) != nil ||
           objc_getAssociatedObject(entry, kPFBAdvSearchGreyKey) != nil;
}

// Probe: declared here for the probes below; defined with the scans further down.
static BOOL pfbAdvIsSearchScreen(UIViewController* vc);

// Probe: the controller whose navigation item this is, found in the loaded navigation stacks
// of the app's windows (whose items exist already); nil when no stack holds it.
static UIViewController* pfbAdvProbeHolderOf(UINavigationItem* item) {
    NSMutableArray<UIViewController*>* queue = [NSMutableArray array];
    for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }
        for (UIWindow* window in ((UIWindowScene*)scene).windows) {
            if (window.rootViewController) {
                [queue addObject:window.rootViewController];
            }
        }
    }
    NSMutableSet<UIViewController*>* seen = [NSMutableSet set];
    for (NSUInteger i = 0; i < queue.count && i < 200; i++) {
        UIViewController* controller = queue[i];
        if ([seen containsObject:controller]) {
            continue;
        }
        [seen addObject:controller];
        if ([controller isKindOfClass:[UINavigationController class]] && controller.isViewLoaded) {
            for (UIViewController* stacked in [(UINavigationController*)controller viewControllers]) {
                if (stacked.navigationItem == item) {
                    return stacked;
                }
            }
        }
        [queue addObjectsFromArray:controller.childViewControllers];
        if (controller.presentedViewController) {
            [queue addObject:controller.presentedViewController];
        }
    }
    return nil;
}

static NSUInteger gPFBAdvProbeReplacedNotes = 0;

// Probe: each Filters item replaced, once per screen in front and holder of the bar: whose
// bar, whether a search screen was in front, and what recognized it (11#F032, 14b#F008).
static void pfbAdvProbeReplaced(UINavigationItem* item, UIViewController* owner, NSString* place) {
    if (!PFBDebugIsRecording() || gPFBAdvProbeReplacedNotes >= 8) {
        return;
    }
    UIViewController* holder = pfbAdvProbeHolderOf(item);
    NSString* key = [NSString stringWithFormat:@"11#F032 %@ %@", PFBProbeClassName(owner), PFBProbeClassName(holder)];
    if (!PFBProbeWants(key)) {
        return;
    }
    gPFBAdvProbeReplacedNotes++;
    NSString* bar = holder == owner ? @"its own bar"
                    : holder        ? [@"the bar of " stringByAppendingString:PFBProbeClassName(holder)]
                                    : @"a bar outside the navigation stacks";
    PFBProbeNote(key, @"11#F032/14b#F008 advanced search: a Filters item replaced in the %@ on %@ while %@ was in front (%@), matched by %@",
                 place, bar, PFBProbeClassName(owner), pfbAdvIsSearchScreen(owner) ? @"search screen" : @"not a search screen",
                 gPFBAdvProbeMatch ?: @"?");
}

// Probe: Twitter's Cancel found among the bar items, once per place (11#F033).
static void pfbAdvProbeCancel(BOOL found, NSString* place, UIViewController* owner, NSUInteger count) {
    if (!found || !PFBDebugIsRecording()) {
        return;
    }
    NSString* key = [@"11#F033 " stringByAppendingString:place];
    if (!PFBProbeWants(key)) {
        return;
    }
    PFBProbeNote(key, @"11#F033 advanced search: Cancel arrives as a bar item in %@ of %@ (%lu items)", place,
                 PFBProbeClassName(owner), (unsigned long)count);
}

static NSUInteger gPFBAdvProbeScreensNoted = 0;

// Probe: what a search screen's navigation item holds when scanned, once per screen class: at
// the first scan with a bar button, or its own item's fifth (3 s) scan if all were empty (11#F046, 14b#F033).
static void pfbAdvProbeBarItems(UINavigationItem* item, UIViewController* owner) {
    if (!PFBDebugIsRecording() || gPFBAdvProbeScreensNoted >= 3 || !pfbAdvIsSearchScreen(owner)) {
        return;
    }
    NSString* key = [@"11#F046 " stringByAppendingString:PFBProbeClassName(owner)];
    if (!PFBProbeWants(key)) {
        return;
    }
    NSMutableArray<UIBarButtonItem*>* entries = [NSMutableArray arrayWithArray:item.rightBarButtonItems ?: @[]];
    NSUInteger right = entries.count;
    if (@available(iOS 16.0, *)) {
        for (UIBarButtonItemGroup* group in item.trailingItemGroups) {
            [entries addObjectsFromArray:group.barButtonItems ?: @[]];
        }
    }
    BOOL own = item == owner.navigationItem;
    NSUInteger scan = own ? PFBProbeCount(key) : PFBProbeCountValue(key);
    if (entries.count == 0 && (!own || scan < 5)) {
        return;
    }
    gPFBAdvProbeScreensNoted++;
    NSString* matched = @"no";
    NSMutableArray<NSString*>* kinds = [NSMutableArray array];
    double best = 0;
    for (UIBarButtonItem* entry in entries) {
        if (kinds.count >= 8) {
            break;
        }
        if (objc_getAssociatedObject(entry, kPFBAdvReplacedKey)) {
            [kinds addObject:@"replacement"];
            matched = @"yes (replaced on an earlier scan)";
            continue;
        }
        gPFBAdvProbeMatch = nil;
        if (pfbAdvIsFiltersItem(entry)) {
            matched = [NSString stringWithFormat:@"yes (%@)", gPFBAdvProbeMatch ?: @"?"];
        }
        UIImage* image = pfbAdvItemImage(entry);
        [kinds addObject:pfbAdvVectorName(image) ?: (image ? @"image" : (entry.title.length ? @"title" : @"other"))];
        double agreement = pfbAdvMaskAgreement(image);
        if (agreement > best) {
            best = agreement;
        }
    }
    PFBProbeNote(key, @"11#F046/14b#F033 search bar items: %lu right, %lu in groups on %@ (%@ item, own scan %lu); Filters item matched %@; items [%@], best pixels %.2f",
                 (unsigned long)right, (unsigned long)(entries.count - right), PFBProbeClassName(owner),
                 own ? @"its own" : @"another", (unsigned long)scan, matched, [kinds componentsJoinedByString:@", "],
                 best);
}

// Works on the item that received the buttons rather than the top controller's:
// an active search bar sets them on a different navigation item.
static void pfbAdvReplaceFiltersInItem(UINavigationItem* item,
                                       UIViewController* owner) {
    if (![PFBSettings boolForKey:@"advanced_search"] || !item || !owner) {
        return;
    }
    pfbAdvProbeBarItems(item, owner);
    NSInteger replaced = 0;
    NSArray* right = item.rightBarButtonItems ?: @[];
    BOOL searching = pfbAdvGroupHasCancel(right);
    pfbAdvProbeCancel(searching, @"right items", owner, right.count);
    NSMutableArray* rebuilt = [NSMutableArray arrayWithCapacity:right.count];
    for (UIBarButtonItem* entry in right) {
        BOOL match = pfbAdvIsFiltersItem(entry);
        if (searching && (match || pfbAdvIsOurs(entry))) {
            replaced++;
            continue;
        }
        if (match) {
            [rebuilt addObject:pfbAdvReplacementFor(owner)];
            replaced++;
            pfbAdvProbeReplaced(item, owner, @"right items");
        } else {
            [rebuilt addObject:entry];
        }
    }
    if (replaced) {
        item.rightBarButtonItems = rebuilt;
    }
    if (@available(iOS 16.0, *)) {
        for (UIBarButtonItemGroup* group in item.trailingItemGroups) {
            NSMutableArray* members = [group.barButtonItems mutableCopy];
            BOOL groupSearching = pfbAdvGroupHasCancel(members);
            pfbAdvProbeCancel(groupSearching, @"trailing group", owner, members.count);
            BOOL changed = NO;
            for (NSInteger i = (NSInteger)members.count - 1; i >= 0; i--) {
                UIBarButtonItem* entry = members[i];
                BOOL match = pfbAdvIsFiltersItem(entry);
                if (groupSearching && (match || pfbAdvIsOurs(entry))) {
                    [members removeObjectAtIndex:i];
                    changed = YES;
                    continue;
                }
                if (match) {
                    members[i] = pfbAdvReplacementFor(owner);
                    changed = YES;
                    pfbAdvProbeReplaced(item, owner, @"trailing group");
                }
            }
            if (changed) {
                group.barButtonItems = members;
            }
        }
    }
}

static BOOL pfbAdvIsSearchScreen(UIViewController* vc) {
    NSString* name = NSStringFromClass([vc class]);
    return [name rangeOfString:@"search" options:NSCaseInsensitiveSearch].location != NSNotFound &&
           ![vc isKindOfClass:[PFBAdvancedSearchViewController class]];
}

// The item is set on the container after the results land, well after the container
// appeared, so the setters are the moment. The owner is the search screen at the top
// of the stack, and the scan runs once the setter has returned.
static UIViewController* pfbAdvTopViewController(void) {
    UIWindow* window = nil;
    for (id scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene respondsToSelector:@selector(windows)]) {
            continue;
        }
        for (UIWindow* candidate in [scene windows]) {
            if (candidate.isKeyWindow || (!window && candidate.rootViewController)) {
                window = candidate;
            }
        }
    }
    UIViewController* top = window.rootViewController;
    while (top.presentedViewController) {
        top = top.presentedViewController;
    }
    while (YES) {
        if ([top isKindOfClass:[UINavigationController class]]) {
            top = [(UINavigationController*)top topViewController];
        } else if ([top isKindOfClass:[UITabBarController class]]) {
            top = [(UITabBarController*)top selectedViewController];
        } else {
            break;
        }
    }
    return top;
}

static void pfbAdvReplaceFilters(UIViewController* owner) {
    pfbAdvReplaceFiltersInItem(owner.navigationItem, owner);
}

// The navigation item that just received the buttons is passed straight in, so
// a search bar setting them on its own item is covered too.
static void pfbAdvRescanItemSoon(UINavigationItem* item) {
    dispatch_async(dispatch_get_main_queue(), ^{
      UIViewController* top = pfbAdvTopViewController();
      if (!top) {
          return;
      }
      if (pfbAdvIsSearchScreen(top)) {
          pfbAdvReplaceFiltersInItem(top.navigationItem, top);
      }
      if (item && item != top.navigationItem) {
          pfbAdvReplaceFiltersInItem(item, top);
      }
    });
}

static void pfbAdvRescanSoon(void) {
    pfbAdvRescanItemSoon(nil);
}


// Probe: Twitter's filter glyph in the search bar against the pixel test, once per build and
// compared after the layout pass, so it is known even with no Filters bar item (11#F023).
static BOOL gPFBAdvProbeGlyphDone = NO;
static NSUInteger gPFBAdvProbeGlyphPasses = 0;

static void pfbAdvProbeSearchBarGlyph(UIButton* button) {
    if (gPFBAdvProbeGlyphDone) {
        return;
    }
    if (!PFBProbeWants(@"11#F023 search bar glyph")) {
        gPFBAdvProbeGlyphDone = YES;
        return;
    }
    __block UIImage* image = button.configuration.image ?: button.currentImage;
    if (!image) {
        PFBEnumerateSubviewsRecursively(button, ^(UIView* view) {
            if (!image && [view isKindOfClass:[UIImageView class]]) {
                image = [(UIImageView*)view image];
            }
        });
    }
    if (!image && ++gPFBAdvProbeGlyphPasses < 50) {
        return;
    }
    gPFBAdvProbeGlyphDone = YES;
    UIImage* glyph = image;
    NSString* label = button.accessibilityLabel;
    if (label.length > 32) {
        label = [label substringToIndex:32];
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        PFBProbeNote(@"11#F023 search bar glyph", @"11#F023 search bar filter button: image %@, name=%@ label=%@ agreement=%.2f",
                     glyph ? @"found" : @"none after 50 passes", pfbAdvVectorName(glyph) ?: @"nil", label ?: @"nil",
                     pfbAdvMaskAgreement(glyph));
    });
}

// The app's own entry lives inside its search bar as a plain button, not as a
// bar button item, so the bar button passes above never reach it.

// The bar sizes its filter slot from its stored showsFilterButton flag, not from
// the button's hidden state (hidden still measures 32 pt). Clearing the flag
// before the bar lays out frees the slot on the first pass; restored when off.
static void pfbAdvCollapseNativeInSearchBar(UIView* bar) {
    static Ivar flagIvar;
    static Ivar buttonIvar;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class cls = objc_getClass("_TtC15TwitterSearchV211SearchBarV2");
        flagIvar = class_getInstanceVariable(cls, "showsFilterButton");
        buttonIvar = class_getInstanceVariable(cls, "filterButton");
    });
    if (!flagIvar || !buttonIvar) {
        return;
    }
    BOOL hide = [PFBSettings boolForKey:@"advanced_search"];
    BOOL* flag = (BOOL*)((char*)(__bridge void*)bar + ivar_getOffset(flagIvar));
    NSNumber* backup = objc_getAssociatedObject(bar, kPFBAdvFlagBackupKey);
    if (hide) {
        // The app may raise the flag after the first pass; the latest value it
        // set is the one to give back.
        if (!backup || *flag) {
            objc_setAssociatedObject(bar, kPFBAdvFlagBackupKey, @(*flag),
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        *flag = NO;
    } else if (backup) {
        *flag = backup.boolValue;
        objc_setAssociatedObject(bar, kPFBAdvFlagBackupKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    UIButton* button = object_getIvar(bar, buttonIvar);
    if (![button isKindOfClass:[UIButton class]]) {
        return;
    }
    pfbAdvProbeSearchBarGlyph(button);
    BOOL ours = objc_getAssociatedObject(button, kPFBAdvHiddenByTweakKey) != nil;
    if (hide) {
        // Only a button the app shows is taken over; one it hides itself is
        // left alone so it is never un-hidden on release.
        if (!ours && !button.hidden) {
            objc_setAssociatedObject(button, kPFBAdvHiddenByTweakKey, @YES,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            ours = YES;
            PFBCOMPAT_ACTION(PFBCompat_advanced_search, @"Twitter's filter button hidden in search");
        }
        if (ours) {
            if (!button.hidden) {
                button.hidden = YES;
            }
            if (button.alpha != 0.0) {
                button.alpha = 0.0;
            }
            if (button.userInteractionEnabled) {
                button.userInteractionEnabled = NO;
            }
        }
    } else if (ours) {
        objc_setAssociatedObject(button, kPFBAdvHiddenByTweakKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        button.hidden = NO;
        button.alpha = 1.0;
        button.userInteractionEnabled = YES;
    }
    // With the option off, Twitter's own button showing is the proof it is left alone.
    if (!hide && *flag && !button.hidden && button.alpha > 0.0) {
        PFBCompatReach(PFBCompatPath_native_filter_button);
        PFBCOMPAT_OBSERVE(PFBCompat_advanced_search, @"Twitter's filter button shown");
    }
}

%hook _TtC15TwitterSearchV211SearchBarV2

- (void)layoutSubviews {
    UIView* bar = (UIView*)self;
    @try {
        pfbAdvCollapseNativeInSearchBar(bar);
    } @catch (id exception) {
    }
    %orig;
}

%end

// Probe: Explore's navigation item and its button, watched from the item setters until
// the button is seen missing after one of them (11#F034).
static BOOL gPFBAdvProbeExploreWatched = NO;
static __weak UINavigationItem* gPFBAdvProbeExploreItem = nil;
static __weak UIBarButtonItem* gPFBAdvProbeExploreButton = nil;

static BOOL pfbAdvProbeItemHolds(UINavigationItem* item, UIBarButtonItem* button) {
    if ([item.rightBarButtonItems indexOfObjectIdenticalTo:button] != NSNotFound) {
        return YES;
    }
    if (@available(iOS 16.0, *)) {
        for (UIBarButtonItemGroup* group in item.trailingItemGroups) {
            if ([group.barButtonItems indexOfObjectIdenticalTo:button] != NSNotFound) {
                return YES;
            }
        }
        return [item.pinnedTrailingGroup.barButtonItems indexOfObjectIdenticalTo:button] != NSNotFound;
    }
    return NO;
}

static void pfbAdvProbeWatchExplore(UINavigationItem* item, UIBarButtonItem* button) {
    if (!PFBProbeWants(@"11#F034 re-set")) {
        return;
    }
    gPFBAdvProbeExploreItem = item;
    gPFBAdvProbeExploreButton = button;
    gPFBAdvProbeExploreWatched = YES;
}

// Probe: after a setter on Explore's item with the option on, whether the button is gone,
// and how many of the new items are the tweak's Filters replacement (11#F034).
static void pfbAdvProbeExploreItemSet(UINavigationItem* item, NSString* setter) {
    if (!gPFBAdvProbeExploreWatched) {
        return;
    }
    UIBarButtonItem* button = gPFBAdvProbeExploreButton;
    if (item != gPFBAdvProbeExploreItem || !button || ![PFBSettings boolForKey:@"advanced_search"] ||
        pfbAdvProbeItemHolds(item, button)) {
        return;
    }
    gPFBAdvProbeExploreWatched = NO;
    if (!PFBProbeWants(@"11#F034 re-set")) {
        return;
    }
    NSArray<UIBarButtonItem*>* right = item.rightBarButtonItems ?: @[];
    NSUInteger replacements = 0;
    for (UIBarButtonItem* entry in right) {
        if (objc_getAssociatedObject(entry, kPFBAdvReplacedKey)) {
            replacements++;
        }
    }
    PFBProbeNote(@"11#F034 re-set",
                 @"11#F034 advanced search: Explore's bar items re-set without the button by %@ (%lu right items, %lu of them the tweak's Filters replacement)",
                 setter, (unsigned long)right.count, (unsigned long)replacements);
}

// Probe: at each later appearance of Explore, whether its button is still on the bar; noted
// at the first check, at the twentieth, and the first time it is missing (11#F034).
static void pfbAdvProbeExploreButton(UINavigationItem* item, UIBarButtonItem* button) {
    if (!PFBDebugIsRecording()) {
        return;
    }
    pfbAdvProbeWatchExplore(item, button);
    NSUInteger appearance = PFBProbeCount(@"11#F034 appearances");
    BOOL inBar = pfbAdvProbeItemHolds(item, button);
    NSString* key = !inBar ? @"11#F034 missing" : (appearance >= 20 ? @"11#F034 still in later" : @"11#F034 still in");
    if (!PFBProbeWants(key)) {
        return;
    }
    PFBProbeNote(key, @"11#F034 advanced search: Explore's button is %@ its bar at appearance %lu after the first (%lu right items)",
                 inBar ? @"still in" : @"missing from", (unsigned long)appearance,
                 (unsigned long)item.rightBarButtonItems.count);
}

// Probe: the advanced search form's text room, read a moment after Explore appears
// (PFBAdvancedSearchViewController.m, 11#F028).
extern void pfbAdvProbeTextRoom(void);

%hook UINavigationItem

- (void)setRightBarButtonItems:(NSArray<UIBarButtonItem*>*)items {
    %orig;
    pfbAdvRescanItemSoon(self);
    pfbAdvProbeExploreItemSet(self, @"setRightBarButtonItems:");
}

- (void)setRightBarButtonItems:(NSArray<UIBarButtonItem*>*)items animated:(BOOL)animated {
    %orig;
    pfbAdvRescanItemSoon(self);
    pfbAdvProbeExploreItemSet(self, @"setRightBarButtonItems:animated:");
}

- (void)setTrailingItemGroups:(NSArray<UIBarButtonItemGroup*>*)groups {
    %orig;
    pfbAdvRescanItemSoon(self);
    pfbAdvProbeExploreItemSet(self, @"setTrailingItemGroups:");
}

- (void)setPinnedTrailingGroup:(UIBarButtonItemGroup*)group {
    %orig;
    pfbAdvRescanItemSoon(self);
    pfbAdvProbeExploreItemSet(self, @"setPinnedTrailingGroup:");
}

%end

// A group already on the bar can have its items swapped without any setter on the
// navigation item firing, so the swap is caught on the group itself.
%hook UIBarButtonItemGroup

- (void)setBarButtonItems:(NSArray<UIBarButtonItem*>*)items {
    %orig;
    pfbAdvRescanSoon();
}

%end

%hook UIViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    if (pfbAdvIsSearchScreen(self)) {
        pfbAdvReplaceFilters(self);
    }
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (pfbAdvIsSearchScreen(self)) {
        pfbAdvReplaceFilters(self);
        // The results, and the item that comes with them, land after the screen has appeared;
        // a few later looks cost nothing once the item is already replaced.
        __weak UIViewController* weakSelf = self;
        for (NSNumber* delay in @[ @0.4, @1.2, @3.0 ]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                         (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
              UIViewController* strongSelf = weakSelf;
              if (strongSelf.viewIfLoaded.window) {
                  pfbAdvReplaceFilters(strongSelf);
              }
            });
        }
    }
}

%end

%hook _TtC14T1TwitterSwift28GuideContainerViewController

%new
- (void)pfbShowAdvancedSearch {
    pfbAdvPresentForm((UIViewController*)self);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    @try {
        pfbAdvProbeTextRoom();
        BOOL enabled = [PFBSettings boolForKey:@"advanced_search"];
        UIBarButtonItem* existingBtn =
            objc_getAssociatedObject(self, kPFBAdvSearchBtnKey);
        UINavigationItem* item = [(UIViewController*)self navigationItem];
        if (!item) {
            return;
        }
        if (!enabled) {
            PFBCOMPAT_OBSERVE(PFBCompat_advanced_search, @"Explore opened");
            // Toggle off: the Filters button a previous appearance added is removed, so the
            // setting applies live on the next visit.
            if (existingBtn) {
                NSMutableArray* items =
                    [item.rightBarButtonItems mutableCopy] ?: [NSMutableArray array];
                [items removeObject:existingBtn];
                item.rightBarButtonItems = items;
                objc_setAssociatedObject(self, kPFBAdvSearchBtnKey, nil,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            return;
        }
        PFBCOMPAT_ACTION(PFBCompat_advanced_search, @"Advanced search button in Explore");
        UIColor* grey = PFBBarIconGrey(((UIViewController*)self).traitCollection);
        if (existingBtn) {
            pfbAdvProbeExploreButton(item, existingBtn);
            // A light/dark switch or a theme change resolves to another gray;
            // the glyph carries its color, so it is redrawn rather than
            // re-tinted.
            UIColor* painted = objc_getAssociatedObject(existingBtn, kPFBAdvSearchGreyKey);
            if (!painted || ![painted isEqual:grey]) {
                existingBtn.image = PFBSlidersGlyph(27.33, grey);
                objc_setAssociatedObject(existingBtn, kPFBAdvSearchGreyKey, grey,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            return;
        }
        // 27.33 points, not the gear's 24: this shape covers 18 of its 24
        // units against the gear's 20.5, so it needs the wider canvas to
        // reach the same width on screen.
        UIImage* icon = PFBSlidersGlyph(27.33, grey);
        UIBarButtonItem* btn =
            [[UIBarButtonItem alloc] initWithImage:icon
                                             style:UIBarButtonItemStylePlain
                                            target:self
                                            action:@selector(pfbShowAdvancedSearch)];
        // The color lives in the image; the tint is set to match so that a
        // highlighted state derived from it stays the same gray.
        btn.tintColor = grey;
        objc_setAssociatedObject(btn, kPFBAdvSearchGreyKey, grey,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        // Matches Twitter's own settings gear, which sits flat in this bar: iOS 26
        // gives bar buttons a shared glass capsule and opting out is one property.
        // Reached through the runtime, since it exists on the iOS 26 SDK only.
        if ([btn respondsToSelector:@selector(setHidesSharedBackground:)]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(
                btn, @selector(setHidesSharedBackground:), YES);
        }
        NSArray* existing = item.rightBarButtonItems ?: @[];
        item.rightBarButtonItems = [existing arrayByAddingObject:btn];
        objc_setAssociatedObject(self, kPFBAdvSearchBtnKey, btn,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        pfbAdvProbeWatchExplore(item, btn);
    } @catch (id e) {
    }
}

%end
