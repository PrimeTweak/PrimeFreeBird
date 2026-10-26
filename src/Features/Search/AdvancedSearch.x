// Advanced search: a Filters button on Explore and search results that opens the search form.

#import "Support/HookHelpers.h"
#import "Features/Search/PFBAdvancedSearchViewController.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import "Debug/PFBProbe.h"

static const void* kPFBAdvSearchBtnKey = &kPFBAdvSearchBtnKey;
static const void* kPFBAdvSearchGrayKey = &kPFBAdvSearchGrayKey;
static const void* kPFBAdvStyleWatchKey = &kPFBAdvStyleWatchKey;
static const void* kPFBAdvTakenOverKey = &kPFBAdvTakenOverKey;
static const void* kPFBAdvFlagBackupKey = &kPFBAdvFlagBackupKey;

// Rows of Twitter's filter glyph on a 24-point grid: {center y, handle center x}.
// The upper handle sits right of center and the lower one left, so the two rows
// read as two settings. A block cannot capture a local C array.
static const CGFloat kPFBSliderGeometry[2][2] = {{8.0, 14.0}, {16.0, 10.0}};

// The sliders' 24-unit grid spans 27.33 points, not the gear's 24: they cover 18 of their
// units against the gear's 20.5, so they need the larger scale to reach its width on screen.
static const CGFloat kPFBFiltersSide = 27.33;
// The Explore button's canvas: the 24 points of the gear and the eye, so its glyph lines
// up in its slot as theirs do. Only transparent margin is cut.
static const CGFloat kPFBExploreGlyphSide = 24.0;

// Drawn in its final color, centered on a `canvas`-point square, and returned as an
// original image, so the bar's accent tint never reaches it.
static UIImage* PFBSlidersGlyph(CGFloat canvas, UIColor* color) {
    const CGFloat kUnit = 24.0;
    // Stroke on the 24-unit grid, lighter than the gear's nominal weight: the gear's glyph
    // stands taller, so an equal stroke would read heavier here.
    const CGFloat kThickness = 1.75;
    // Large enough for the ring's opening to read at actual size, with the rail meeting
    // the ring; a smaller radius closes the ring into a dot.
    const CGFloat kHandleRadius = 2.8;
    const CGFloat kInset = 3.0;
    CGFloat scale = kPFBFiltersSide / kUnit;
    CGFloat half = kThickness / 2.0;
    CGFloat offset = (canvas - kPFBFiltersSide) / 2.0;
    UIGraphicsImageRendererFormat* format =
        [UIGraphicsImageRendererFormat preferredFormat];
    format.opaque = NO;
    UIGraphicsImageRenderer* renderer =
        [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(canvas, canvas)
                                               format:format];
    UIImage* drawn = [renderer
        imageWithActions:^(UIGraphicsImageRendererContext* context) {
            CGContextRef ctx = context.CGContext;
            CGContextTranslateCTM(ctx, offset, offset);
            [(color ?: [UIColor blackColor]) setStroke];
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

// The Filters button in the bar's gray, flat like the settings gear: iOS 26 gives bar
// buttons a shared glass capsule, and the property opting out is reached through the
// runtime, since the build SDK predates it.
static UIBarButtonItem* PFBFiltersButton(id target, SEL action, UIColor* gray) {
    UIBarButtonItem* btn = [[UIBarButtonItem alloc] initWithImage:PFBSlidersGlyph(kPFBFiltersSide, gray)
                                                            style:UIBarButtonItemStylePlain
                                                           target:target
                                                           action:action];
    // The color lives in the image; the tint matches it so a highlighted state derived
    // from the tint stays the same gray.
    btn.tintColor = gray;
    btn.accessibilityLabel = [[PFBBundle sharedBundle] localizedStringForKey:@"ADVANCED_SEARCH_TITLE"];
    if ([btn respondsToSelector:@selector(setHidesSharedBackground:)]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(btn, @selector(setHidesSharedBackground:), YES);
    }
    return btn;
}

// MARK: - the app's own Filters button

// Every search results screen carries a sliders button opening the native Filters
// tray, drawn with the same glyph as the Explore button, so it is replaced. It is told
// apart by its vector name, its accessibility label or its pixels.

// Presents the Advanced Search form as a page sheet over the given controller.
static void pfbAdvPresentForm(UIViewController* owner) {
    PFBAdvancedSearchViewController* form = [[PFBAdvancedSearchViewController alloc] init];
    UINavigationController* nav =
        [[UINavigationController alloc] initWithRootViewController:form];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    [owner presentViewController:nav animated:YES completion:nil];
}

@interface PFBAdvSearchLauncher : NSObject
@property (nonatomic, weak) UIViewController* owner;
- (void)launch:(id)sender;
@end

@implementation PFBAdvSearchLauncher
- (void)launch:(id)sender {
    UIViewController* owner = self.owner;
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

static BOOL pfbAdvIsFiltersItem(UIBarButtonItem* item) {
    if (objc_getAssociatedObject(item, kPFBAdvReplacedKey) ||
        objc_getAssociatedObject(item, kPFBAdvSearchGrayKey)) {
        return NO;
    }
    NSSet* glyphs = [NSSet setWithObjects:@"settings_slider", @"filter_bars", nil];
    UIImage* image = pfbAdvItemImage(item);
    NSString* name = pfbAdvVectorName(image);
    if (name && [glyphs containsObject:name]) {
        return YES;
    }
    NSString* label = item.accessibilityLabel ?: item.customView.accessibilityLabel;
    NSSet* labels = [NSSet setWithObjects:@"Filters", @"Filter", nil];
    if (label && [labels containsObject:label]) {
        return YES;
    }
    // Neither a name nor a label: the pixels decide. The sliders glyph matches the
    // reference drawn from the app's own vector almost entirely; other glyphs far less.
    return pfbAdvMaskAgreement(image) >= 0.85;
}

// The color the bar's other items are drawn in: the label color on the results screen,
// gray on Explore. The neighbor decides, and the Explore gray is the fallback.
static UIColor* pfbAdvNeighborTint(UINavigationItem* item, UIViewController* owner) {
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
    return PFBBarIconGray(owner.traitCollection);
}

static UIBarButtonItem* pfbAdvReplacementFor(UIViewController* owner) {
    UIColor* gray = pfbAdvNeighborTint(owner.navigationItem, owner);
    PFBAdvSearchLauncher* launcher = [PFBAdvSearchLauncher new];
    launcher.owner = owner;
    UIBarButtonItem* btn = PFBFiltersButton(launcher, @selector(launch:), gray);
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
           objc_getAssociatedObject(entry, kPFBAdvSearchGrayKey) != nil;
}

static BOOL pfbAdvIsSearchScreen(UIViewController* vc);

// Measurement: the screens other than search where the Filters button is replaced,
// one line per screen class.
static void pfbProbeReplacedOutsideSearch(UIViewController* owner) {
    if (pfbAdvIsSearchScreen(owner)) {
        return;
    }
    PFB_PROBE(@"Filters replaced outside search", 6, @"%@", NSStringFromClass([owner class]));
}

// Measurement: who calls the three group setters, by the image that sent the message.
static void pfbProbeGroupSetter(NSString* setter, void* caller) {
    if (!PFBProbeNewCaller(caller)) {
        return;
    }
    Dl_info info;
    NSString* from = dladdr(caller, &info) && info.dli_fname ? [@(info.dli_fname) lastPathComponent] : @"?";
    PFB_PROBE(@"bar group setters", 9, @"%@ sent from %@", setter, from);
}

// Works on the item that received the buttons rather than the top controller's:
// an active search bar sets them on a different navigation item.
static void pfbAdvReplaceFiltersInItem(UINavigationItem* item,
                                       UIViewController* owner) {
    if (![PFBSettings boolForKey:@"advanced_search"] || !item || !owner) {
        return;
    }
    NSInteger replaced = 0;
    BOOL swapped = NO;
    NSArray* right = item.rightBarButtonItems ?: @[];
    BOOL searching = pfbAdvGroupHasCancel(right);
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
            swapped = YES;
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
                    swapped = YES;
                }
            }
            if (changed) {
                group.barButtonItems = members;
            }
        }
    }
    if (swapped) {
        PFBCompatReach(PFBCompatPath_results_filters_button);
        PFBCOMPAT_ACTION(PFBCompat_advanced_search, @"Filters button replaced in search results");
        pfbProbeReplacedOutsideSearch(owner);
    }
}

static BOOL pfbAdvIsSearchScreen(UIViewController* vc) {
    NSString* name = NSStringFromClass([vc class]);
    return [name rangeOfString:@"search" options:NSCaseInsensitiveSearch].location != NSNotFound &&
           ![vc isKindOfClass:[PFBAdvancedSearchViewController class]];
}

// The controller on screen: the last one presented, then the visible child of
// navigation and tab controllers.
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
        Class cls = objc_getClass("_TtC15TwitterSearchV29SearchBar");
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
        // The app may raise the flag after the first pass; the first value and any
        // later raise are kept, to be given back when the option is off.
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
    BOOL ours = objc_getAssociatedObject(button, kPFBAdvTakenOverKey) != nil;
    if (hide) {
        // Only a button the app shows is taken over; one it hides itself is
        // left alone so it is never un-hidden on release.
        if (!ours && !button.hidden) {
            objc_setAssociatedObject(button, kPFBAdvTakenOverKey, @YES,
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
        objc_setAssociatedObject(button, kPFBAdvTakenOverKey, nil,
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

%hook _TtC15TwitterSearchV29SearchBar

- (void)layoutSubviews {
    UIView* bar = (UIView*)self;
    @try {
        pfbAdvCollapseNativeInSearchBar(bar);
    } @catch (id exception) {
    }
    %orig;
}

%end

%hook UINavigationItem

- (void)setRightBarButtonItems:(NSArray<UIBarButtonItem*>*)items {
    %orig;
    pfbAdvRescanItemSoon(self);
}

- (void)setRightBarButtonItems:(NSArray<UIBarButtonItem*>*)items animated:(BOOL)animated {
    %orig;
    pfbAdvRescanItemSoon(self);
}

- (void)setTrailingItemGroups:(NSArray<UIBarButtonItemGroup*>*)groups {
    %orig;
    pfbProbeGroupSetter(@"setTrailingItemGroups:", __builtin_return_address(0));
    pfbAdvRescanItemSoon(self);
}

- (void)setPinnedTrailingGroup:(UIBarButtonItemGroup*)group {
    %orig;
    pfbProbeGroupSetter(@"setPinnedTrailingGroup:", __builtin_return_address(0));
    pfbAdvRescanItemSoon(self);
}

%end

// A group already on the bar can have its items swapped without any setter on the
// navigation item firing, so the swap is caught on the group itself.
%hook UIBarButtonItemGroup

- (void)setBarButtonItems:(NSArray<UIBarButtonItem*>*)items {
    %orig;
    pfbProbeGroupSetter(@"setBarButtonItems:", __builtin_return_address(0));
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

// Draws the Explore Filters glyph in the gray of the owner's appearance.
static void pfbAdvPaintExploreButton(UIViewController* owner, UIBarButtonItem* button) {
    UIColor* gray = PFBBarIconGray(owner.traitCollection);
    UIColor* painted = objc_getAssociatedObject(button, kPFBAdvSearchGrayKey);
    if (painted && [painted isEqual:gray]) {
        return;
    }
    PFBBarGlyphButton* view = (PFBBarGlyphButton*)button.customView;
    if ([view isKindOfClass:[PFBBarGlyphButton class]]) {
        view.glyph = PFBSlidersGlyph(kPFBExploreGlyphSide, gray);
    }
    objc_setAssociatedObject(button, kPFBAdvSearchGrayKey, gray, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// A light/dark switch while Explore is on screen repaints the glyph at once. The
// registration API is newer than the SDK, so it is called by name, once per controller.
static void pfbAdvWatchExploreStyle(UIViewController* owner) {
    SEL registerSelector = NSSelectorFromString(@"registerForTraitChanges:withHandler:");
    Class styleTrait = NSClassFromString(@"UITraitUserInterfaceStyle");
    if (objc_getAssociatedObject(owner, kPFBAdvStyleWatchKey) || !styleTrait ||
        ![owner respondsToSelector:registerSelector]) {
        return;
    }
    void (^handler)(id, UITraitCollection*) = ^(id environment, __unused UITraitCollection* previous) {
        UIBarButtonItem* button = objc_getAssociatedObject(environment, kPFBAdvSearchBtnKey);
        if (button && [environment isKindOfClass:[UIViewController class]]) {
            pfbAdvPaintExploreButton(environment, button);
        }
    };
    id registration = ((id (*)(id, SEL, NSArray*, id))objc_msgSend)(owner, registerSelector, @[ styleTrait ], handler);
    objc_setAssociatedObject(owner, kPFBAdvStyleWatchKey, registration ?: @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%hook _TtC14T1TwitterSwift28GuideContainerViewController

%new
- (void)pfbShowAdvancedSearch {
    pfbAdvPresentForm((UIViewController*)self);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    @try {
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
        UIViewController* owner = (UIViewController*)self;
        UIBarButtonItem* btn = existingBtn;
        if (btn) {
            // A theme change resolves to another gray; the glyph carries its color, so it
            // is redrawn rather than re-tinted.
            pfbAdvPaintExploreButton(owner, btn);
        } else {
            UIColor* gray = PFBBarIconGray(owner.traitCollection);
            // Paired with the gear beside it below, as the Notifications eye is.
            btn = PFBBarGlyphItem(
                PFBSlidersGlyph(kPFBExploreGlyphSide, gray),
                [[PFBBundle sharedBundle] localizedStringForKey:@"ADVANCED_SEARCH_TITLE"],
                self, @selector(pfbShowAdvancedSearch));
            objc_setAssociatedObject(btn, kPFBAdvSearchGrayKey, gray,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(self, kPFBAdvSearchBtnKey, btn,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            pfbAdvWatchExploreStyle(owner);
        }
        // Twitter may have replaced the right items since: the button is put back.
        if (![item.rightBarButtonItems containsObject:btn]) {
            NSArray* existing = item.rightBarButtonItems ?: @[];
            item.rightBarButtonItems = [existing arrayByAddingObject:btn];
        }
        if ([item.rightBarButtonItems containsObject:btn]) {
            PFBBarPairWithNeighbor(btn, item.rightBarButtonItems, @"Explore");
            PFBCOMPAT_ACTION(PFBCompat_advanced_search, @"Advanced search button in Explore");
        }
    } @catch (id e) {
    }
}

%end
