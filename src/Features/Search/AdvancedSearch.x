// A Filters button in the Explore bar that opens the native Advanced Search form,
// with the app's own filter button collapsed inside the search bar. The glyph is
// drawn here at the settings gear's stroke, since no library glyph matches it.

#import "Support/HookHelpers.h"
#import "Debug/PFBDebugger.h"
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
    // Matched to the settings gear by pixel count on screen, not by nominal weight:
    // the gear's glyph stands taller, so an equal stroke reads heavier here. Trimmed
    // to 1.75 on the 24-unit grid rather than 2.0.
    const CGFloat kThickness = 1.75;
    // Rendered and compared at actual size: at 2.2 the ring closes up into a
    // dot and the rail beyond it shrinks to a stub. At 2.8 the opening reads,
    // and the rail meets the ring rather than stopping short of it.
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
            // Round caps and joins: the app's own glyphs are drawn this way, and
            // a square-ended rectangle cannot imitate it — that difference, not
            // the stroke width, is what set this icon apart from the gear.
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
    PFBAdvancedSearchViewController* form = [[PFBAdvancedSearchViewController alloc] init];
    UINavigationController* nav =
        [[UINavigationController alloc] initWithRootViewController:form];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    [owner presentViewController:nav animated:YES completion:nil];
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

// The first image an item shows, wherever it keeps it: on the item itself, or
// inside a custom view - the search screen's items are TFNBarButtonItemButton
// views with a plain UIImageView inside, measured, and carry no name or label.
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
    if (objc_getAssociatedObject(item, kPFBAdvReplacedKey)) {
        return NO;
    }
    NSSet* glyphs = [NSSet setWithObjects:@"settings_slider", @"filter_bars", nil];
    UIImage* image = pfbAdvItemImage(item);
    NSString* name = pfbAdvVectorName(image);
    if (name && [glyphs containsObject:name]) {
        return YES;
    }
    NSString* label = item.accessibilityLabel ?: item.customView.accessibilityLabel;
    NSSet* labels = [NSSet setWithObjects:@"Filters", @"Filter", @"Filtres", @"Filtre", nil];
    if (label && [labels containsObject:label]) {
        return YES;
    }
    // Neither a name nor a label: the pixels decide. The same vector drawn by
    // the app's Swift icon code and by its ObjC loader agrees almost entirely;
    // any other glyph in this bar agrees far less.
    return pfbAdvMaskAgreement(image) >= 0.85;
}

// The color the bar's other items are drawn in: on the results screen the
// share glyph is the label color, measured at (15,20,25), while Explore's
// gear is gray. The neighbour decides, and the Explore gray is the fallback.
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

// Works on the item that received the buttons rather than the top controller's:
// an active search bar sets them on a different navigation item.
static void pfbAdvReplaceFiltersInItem(UINavigationItem* item,
                                       UIViewController* owner) {
    if (![PFBSettings boolForKey:@"advanced_search"] || !item || !owner) {
        return;
    }
    NSInteger replaced = 0;
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
                    replaced++;
                    continue;
                }
                if (match) {
                    members[i] = pfbAdvReplacementFor(owner);
                    changed = YES;
                    replaced++;
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
    BOOL ours = objc_getAssociatedObject(button, kPFBAdvHiddenByTweakKey) != nil;
    if (hide) {
        // Only a button the app shows is taken over; one it hides itself is
        // left alone so it is never un-hidden on release.
        if (!ours && !button.hidden) {
            objc_setAssociatedObject(button, kPFBAdvHiddenByTweakKey, @YES,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            ours = YES;
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
    pfbAdvRescanItemSoon(self);
}

- (void)setPinnedTrailingGroup:(UIBarButtonItemGroup*)group {
    %orig;
    pfbAdvRescanItemSoon(self);
}

%end

// A group already on the bar can have its items swapped without any setter
// on the navigation item firing - measured: after a restart the sliders sat
// in place with no scan triggered until the next appearance.
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
        // The results, and the item that comes with them, land after the
        // screen has appeared. A few later looks cost nothing when the item is
        // already the tweak's.
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
    PFBAdvancedSearchViewController* form = [[PFBAdvancedSearchViewController alloc] init];
    UINavigationController* nav =
        [[UINavigationController alloc] initWithRootViewController:form];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    [(UIViewController*)self presentViewController:nav
                                          animated:YES
                                        completion:nil];
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
            // Toggle is off: remove the tweak's button if a previous appearance
            // added it, so the setting applies live on the next visit.
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
    } @catch (id e) {
    }
}

%end
