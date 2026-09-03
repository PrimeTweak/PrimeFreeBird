//
//  Theme.x
//  PrimeFreeBird
//

#import <objc/runtime.h>
#import <objc/message.h>
#import "HookHelpers.h"
#import "Core/BHTBundle.h"
#import "Debug/NFBDebugger.h"

#import "ThemeColor/DarkModeStyle.h"

// MARK: - Custom accent color

static NSNumber* selectedThemeColor(void) {
    return [NSUserDefaults.standardUserDefaults objectForKey:@"bh_color_theme_selectedColor"];
}

static UIColor* customAccentColor(void) {
    NSString* hex = [NSUserDefaults.standardUserDefaults objectForKey:@"bh_custom_accent_hex"];
    if (![hex isKindOfClass:[NSString class]] || hex.length < 6) {
        return nil;
    }
    unsigned int rgb = 0;
    NSScanner* scanner = [NSScanner scannerWithString:hex];
    [scanner setScanLocation:[hex hasPrefix:@"#"] ? 1 : 0];
    if (![scanner scanHexInt:&rgb]) {
        return nil;
    }
    return [UIColor colorWithRed:((rgb & 0xFF0000) >> 16) / 255.0
                           green:((rgb & 0x00FF00) >> 8) / 255.0
                            blue:(rgb & 0x0000FF) / 255.0
                           alpha:1.0];
}

// Depth counter, not a flag: raw reads nest. NFBIsAccentColor opens its own raw
// read during ordinary text rendering, so with a plain boolean its End closed a
// raw read the colour picker had opened around building its swatches — the
// remaining swatches then resolved to the custom accent. That was the flicker.
static NSInteger NFBRawPaletteDepth = 0;
static inline BOOL NFBRawPaletteReading(void) { return NFBRawPaletteDepth > 0; }
void NFBBeginRawPaletteRead(void) { NFBRawPaletteDepth++; }
void NFBEndRawPaletteRead(void)   { if (NFBRawPaletteDepth > 0) { NFBRawPaletteDepth--; } }

static BOOL customAccentActive(void) {
    return [NSUserDefaults.standardUserDefaults boolForKey:@"bh_custom_is_active"]
           && customAccentColor() != nil;
}

// Central accent resolver. Every accent-producing palette accessor routes
// through this: returns the custom colour when active (except during a raw
// swatch read), otherwise whatever Twitter would natively return.
// The avatar shown while a portrait loads takes its fill from the palette, and
// that fill is derived from the primary colour — so a custom accent turns every
// loading avatar into a flat disc of it. It is answered with a neutral instead,
// which is what a placeholder is for.
static UIColor* NFBPlaceholderGrey(void) {
    static UIColor* grey;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      grey = [UIColor colorWithDynamicProvider:^UIColor*(UITraitCollection* traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark
                   ? [UIColor colorWithWhite:0.22 alpha:1.0]
                   : [UIColor colorWithWhite:0.85 alpha:1.0];
      }];
    });
    return grey;
}

static UIColor* NFBAccent(UIColor* orig) {
    if (customAccentActive() && !NFBRawPaletteReading()) {
        UIColor* c = customAccentColor();
        if (c) { return c; }
    }
    return orig;
}

// Logo colours follow the accent ONLY when the user opted in via the
// "Color Twitter icon" toggle; otherwise the native logo colour passes through.
static UIColor* NFBLogoAccent(UIColor* orig) {
    if (![BHTSettings boolForKey:@"color_twitter_icon_in_top_bar"]) {
        return orig;
    }
    return NFBAccent(orig);
}

// iOS 26 Liquid Glass controls (compose FAB, follow buttons, switches, the
// new-posts pill, selection highlights) take their accent from the window tint,
// not the palette, so the custom accent is pushed onto every window's
// tintColor. Under the standard interface the palette carries the accent on its
// own, and a window tint would only leak onto everything that has no colour of
// its own — alert buttons, back chevrons, bar glyphs before their own colour is
// set. It is therefore pushed for Liquid Glass only, and cleared otherwise.
// Depth counter for the settings stack (Twitter's root, the tweak's menu, every page,
// the theme screen). The Done platter is ONE button shared by the whole stack,
// so the whitening must live as long as ANY settings screen is up. A counter,
// not a BOOL: on pop, the target's viewWillAppear fires BEFORE the source's
// viewDidDisappear — a flag would be clobbered to NO mid-stack. >0 = visible.
NSInteger NFBColorThemeScreenVisible;

static void NFBApplyGlobalTint(void) {
    extern UIColor* CurrentAccentColor(void);
    NSUserDefaults* defs = NSUserDefaults.standardUserDefaults;
    // The window tint is inherited by UIKit's own controls - the buttons in a
    // system alert take their colour from it - so it is spent only on a colour
    // the reader actually picked. The theming toggles are not a colour: turning
    // them on paints the tab bar and the logo, and leaves the system alone.
    BOOL hasAccent = customAccentActive() ||
                     [defs objectForKey:@"bh_color_theme_selectedColor"] != nil ||
                     [defs integerForKey:@"T1ColorSettingsPrimaryColorOptionKey"] >= 1;
    // Standard interface: no window tint at all, so nothing inherits the accent
    // that has no colour of its own.
    if (![BHTSettings boolForKey:@"enable_liquid_glass"]) {
        hasAccent = NO;
    }
    UIColor* tint = hasAccent ? CurrentAccentColor() : nil;
    void (^apply)(void) = ^{
        for (id scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:objc_getClass("UIWindowScene")]) {
                for (UIWindow* w in [scene windows]) { w.tintColor = tint; }
            }
        }
    };
    if ([NSThread isMainThread]) { apply(); }
    else { dispatch_async(dispatch_get_main_queue(), apply); }
}

// Weak handle to the live top-bar logo so a colour pick can re-tint it
// immediately, without waiting for the title view to be rebuilt (= restart).
static __weak UIImageView* NFBTopBarLogoView;

// Read by the layer-animation hook in NavBarIcons.x, which has to know which
// image view is the logo to keep the glass vibrancy filter off it.
UIImageView* NFBTopBarLogoViewCurrent(void) {
    return NFBTopBarLogoView;
}

// In Liquid Glass the title plugin returns a CONTAINER, not the image view
// itself. Find the image view wherever it sits in the returned hierarchy.
static UIImageView* NFBFindLogoImageView(UIView* root) {
    if ([root isKindOfClass:[UIImageView class]] && ((UIImageView*)root).image) {
        return (UIImageView*)root;
    }
    for (UIView* sub in root.subviews) {
        UIImageView* found = NFBFindLogoImageView(sub);
        if (found) {
            return found;
        }
    }
    return nil;
}

// Every logo the tweak have ever vetted, weakly held. Re-tinting the registry is
// precise and needs no container matching — the name-based sweep misses
// Twitter's Swift home header, which is why the bird only refreshed when the
// plugins rebuilt the title view on a tab change.
static NSHashTable<UIImageView*>* NFBLogoRegistry;

static void NFBRegisterLogoView(UIImageView* logo) {
    if (!logo) {
        return;
    }
    if (!NFBLogoRegistry) {
        NFBLogoRegistry = [NSHashTable weakObjectsHashTable];
    }
    [NFBLogoRegistry addObject:logo];
}

// CurrentAccentColor() never returns nil — it falls back to systemBlue — so it
// cannot answer "is an accent actually set?". After a Reset every key is gone
// and that fallback made the chrome repaint itself blue instead of reverting.
// This is the real test, matching what NFBApplyGlobalTint uses.
static BOOL NFBAccentIsActive(void) {
    if (customAccentActive()) {
        return YES;
    }
    NSUserDefaults* defs = NSUserDefaults.standardUserDefaults;
    if ([defs objectForKey:@"bh_color_theme_selectedColor"] ||
        [defs integerForKey:@"T1ColorSettingsPrimaryColorOptionKey"] >= 1) {
        return YES;
    }
    // Fresh install (option 0, nothing picked yet) defaults to Twitter blue as the
    // active accent — UNLESS the user reset (which reverts to native/black).
    return ![defs boolForKey:@"nfb_color_reset_done"];
}

// Read by NavBarIcons.x, whose layer-animation hook keeps the glass vibrancy
// filter off the tab bar only while a themed bar was asked for.
BOOL NFBThemedTabBarWanted(void) {
    return [BHTSettings boolForKey:@"tab_bar_theming"] && NFBAccentIsActive();
}

// Twitter's own logo colour, read raw so the tweak's accent hooks don't repaint it.
static UIColor* NFBRawLogoColor(void) {
    NFBBeginRawPaletteRead();
    id palette = [[[objc_getClass("TAEColorSettings") sharedSettings]
        currentColorPalette] colorPalette];
    UIColor* raw = nil;
    if ([palette respondsToSelector:@selector(navigationBarLogoColor)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        raw = [palette performSelector:@selector(navigationBarLogoColor)];
#pragma clang diagnostic pop
    }
    NFBEndRawPaletteRead();
    return raw;
}

static const void* kNFBLogoOriginalKey = &kNFBLogoOriginalKey;
static const void* kNFBLogoBakedKey = &kNFBLogoBakedKey;

// The bird, rendered from the PDF the tweak already ships, at the size the bar
// asks for. Cached per size: the render costs a PDF parse and the bar asks on
// every layout pass. Same recipe as the settings header in Settings.x.
static UIImage* NFBBirdLogoImage(CGSize size) {
    static NSMutableDictionary<NSString*, UIImage*>* cache = nil;
    if (!cache) {
        cache = [NSMutableDictionary dictionary];
    }
    NSString* key = [NSString stringWithFormat:@"%.0fx%.0f", size.width, size.height];
    UIImage* cached = cache[key];
    if (cached) {
        return cached;
    }
    // The filled bird, not the outlined one: measured in the PDFs the tweak
    // ships - bird_stroke draws a stroke, LaunchTwitterBird fills.
    NSURL* birdURL = [[BHTBundle sharedBundle] pathForFile:@"LaunchTwitterBird.pdf"];
    if (!birdURL || size.width < 1 || size.height < 1) {
        return nil;
    }
    CGPDFDocumentRef pdf = CGPDFDocumentCreateWithURL((__bridge CFURLRef)birdURL);
    if (!pdf) {
        return nil;
    }
    UIImage* rendered = nil;
    CGPDFPageRef page = CGPDFDocumentGetPage(pdf, 1);
    if (page) {
        UIGraphicsImageRendererFormat* fmt = [UIGraphicsImageRendererFormat preferredFormat];
        fmt.opaque = NO;
        UIGraphicsImageRenderer* renderer =
            [[UIGraphicsImageRenderer alloc] initWithSize:size format:fmt];
        rendered = [renderer imageWithActions:^(UIGraphicsImageRendererContext* ctx) {
          CGContextRef c = ctx.CGContext;
          CGRect box = CGPDFPageGetBoxRect(page, kCGPDFCropBox);
          // Drawn a shade smaller than the box the bar hands over: the X it
        // replaces reads narrower than a bird at the same nominal size.
        CGFloat inset = 0.86;
        CGFloat scale = MIN(size.width / box.size.width, size.height / box.size.height) * inset;
          CGFloat drawnW = box.size.width * scale;
          CGFloat drawnH = box.size.height * scale;
          CGContextTranslateCTM(c, (size.width - drawnW) / 2.0,
                                size.height - (size.height - drawnH) / 2.0);
          CGContextScaleCTM(c, 1, -1);
          CGContextScaleCTM(c, scale, scale);
          CGContextDrawPDFPage(c, page);
        }];
        rendered = [rendered imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }
    CGPDFDocumentRelease(pdf);
    if (rendered) {
        cache[key] = rendered;
    }
    return rendered;
}

static void NFBApplyLogoTint(UIImageView* logoView) {
    UIImage* current = logoView.image;
    if (!current) {
        return;
    }
    NFBRegisterLogoView(logoView);
    UIImage* original = objc_getAssociatedObject(logoView, kNFBLogoOriginalKey);
    UIImage* baked = objc_getAssociatedObject(logoView, kNFBLogoBakedKey);
    if (!original || (current != original && current != baked)) {
        // A new image from the app: remember it as the one to paint from.
        original = current;
        objc_setAssociatedObject(logoView, kNFBLogoOriginalKey, original,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        baked = nil;
        objc_setAssociatedObject(logoView, kNFBLogoBakedKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    // The bird replaces the X when the reader asked for Twitter's branding back.
    // Substituting the image, not the tint: the glyph itself is what changed.
    if ([BHTSettings boolForKey:@"restore_twitter_names"]) {
        UIImage* bird = NFBBirdLogoImage(original.size);
        if (bird && original != bird) {
            original = bird;
            objc_setAssociatedObject(logoView, kNFBLogoOriginalKey, bird,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            baked = nil;
            objc_setAssociatedObject(logoView, kNFBLogoBakedKey, nil,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            NFBDebugLog(@"[logo] bird substituted for the X");
        }
    }
    UIColor* target = nil;
    if ([BHTSettings boolForKey:@"color_twitter_icon_in_top_bar"] && NFBAccentIsActive()) {
        target = NFBBrandAccentColor();
    }
    if (logoView.layer.filters.count) {
        logoView.layer.filters = nil;
    }
    if (!target) {
        // Option off: hand the untouched image back AND restore the native
        // colour, the way this function did before the baking was added.
        if (current != original) {
            logoView.image = original;
        }
        UIColor* raw = NFBRawLogoColor() ?: [UIColor labelColor];
        if (original.renderingMode == UIImageRenderingModeAlwaysTemplate &&
            ![logoView.tintColor isEqual:raw]) {
            logoView.tintColor = raw;
        }
        return;
    }
    if (!baked) {
        baked = NFBPaintedGlyph(original, target);
        objc_setAssociatedObject(logoView, kNFBLogoBakedKey, baked,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NFBDebugLog(@"[logo] colour baked into the image");
    }
    if (current != baked) {
        logoView.image = baked;
    }
}

static void NFBRetintRegisteredLogos(void) {
    // The baked copy is tied to one colour; a new accent starts over.
    for (UIImageView* logo in NFBLogoRegistry) {
        objc_setAssociatedObject(logo, kNFBLogoBakedKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    for (UIImageView* logo in NFBLogoRegistry) {
        NFBApplyLogoTint(logo);
    }
}

// Tab icons cache their tinted image, so they need an explicit nudge. Walk the
// live controller tree and ask every tab view to re-theme its icon. Mirrors the
// picker's own pass, but from here it also covers toggle changes.
static void NFBReapplyTabBarAccent(void) {
    Class tabBarVCClass = objc_getClass("T1TabBarViewController");
    if (!tabBarVCClass) {
        return;
    }
    void (^apply)(void) = ^{
        for (id scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:objc_getClass("UIWindowScene")]) {
                continue;
            }
            for (UIWindow* window in [scene windows]) {
                NSMutableArray* stack = [NSMutableArray array];
                if (window.rootViewController) {
                    [stack addObject:window.rootViewController];
                }
                while (stack.count) {
                    UIViewController* vc = stack.firstObject;
                    [stack removeObjectAtIndex:0];
                    if ([vc isKindOfClass:tabBarVCClass] &&
                        [vc respondsToSelector:@selector(tabViews)]) {
                        for (id tab in [vc valueForKey:@"tabViews"]) {
                            if ([tab respondsToSelector:@selector(applyCurrentThemeToIcon)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                                [tab performSelector:@selector(applyCurrentThemeToIcon)];
#pragma clang diagnostic pop
                            }
                        }
                    }
                    if (vc.presentedViewController) {
                        [stack addObject:vc.presentedViewController];
                    }
                    if ([vc isKindOfClass:[UINavigationController class]]) {
                        [stack addObjectsFromArray:((UINavigationController*)vc).viewControllers];
                    }
                    if ([vc isKindOfClass:[UITabBarController class]]) {
                        [stack addObjectsFromArray:((UITabBarController*)vc).viewControllers];
                    }
                    [stack addObjectsFromArray:vc.childViewControllers];
                }
            }
        }
    };
    if ([NSThread isMainThread]) {
        apply();
    } else {
        dispatch_async(dispatch_get_main_queue(), apply);
    }
}

// Don't rely on having captured the logo when it was installed: sweep the live
// navigation bars at refresh time. Works no matter which of Twitter's title
// plugins built it, or whether the bar is native or custom.
// Twitter's home header is not always a UINavigationBar, so match on the class
// name too. Inside such a container only image views ALREADY in
// template mode: converting an arbitrary one here would flatten avatars into
// silhouettes. The trusted title-view hooks do the first conversion.
static BOOL NFBIsTopBarContainer(UIView* view) {
    if ([view isKindOfClass:[UINavigationBar class]]) {
        return YES;
    }
    NSString* name = NSStringFromClass([view class]);
    return [name containsString:@"NavigationBar"] || [name containsString:@"TopBar"];
}

// Every image view under a title control, painted. The title control is the
// only place the bar puts a title image, so the reach is exactly the logo.
static void NFBBakeTitleControlLogos(UIView* root) {
    if ([NSStringFromClass([root class]) containsString:@"NavigationBarTitleControl"]) {
        EnumerateSubviewsRecursively(root, ^(UIView* view) {
          if ([view isKindOfClass:[UIImageView class]]) {
              NFBApplyLogoTint((UIImageView*)view);
          }
        });
        return;
    }
    for (UIView* sub in root.subviews) {
        NFBBakeTitleControlLogos(sub);
    }
}

static void NFBRetintTemplateLogos(UIView* root) {
    if ([root isKindOfClass:[UIImageView class]]) {
        UIImageView* imageView = (UIImageView*)root;
        if (imageView.image &&
            imageView.image.renderingMode == UIImageRenderingModeAlwaysTemplate &&
            imageView.bounds.size.width > 0 && imageView.bounds.size.width < 60) {
            NFBApplyLogoTint(imageView);
        }
        return;
    }
    for (UIView* sub in root.subviews) {
        NFBRetintTemplateLogos(sub);
    }
}

static void NFBSweepTopBarLogos(UIView* root) {
    if (NFBIsTopBarContainer(root)) {
        NFBRetintTemplateLogos(root);
        return;
    }
    for (UIView* sub in root.subviews) {
        NFBSweepTopBarLogos(sub);
    }
}

// What was last pushed into a given tab bar. bar.tintColor cannot be used for
// the comparison: the bar INHERITS the window tint, so it reports the new
// accent while the installed appearance — which actually paints the selected
// icon — may still carry the old one.
static char kNFBAppliedAccentKey;

// Raised on every accent change; the view-controller hook below keeps
// re-applying until the timeline chrome is actually back on screen.
static BOOL NFBAccentPending = NO;

static void NFBApplyTabBarAccent(UITabBar* bar) {
    BOOL active = [BHTSettings boolForKey:@"tab_bar_theming"] && NFBAccentIsActive();
    // Brand accent, not CurrentAccentColor: with nothing picked the latter falls
    // back to iOS systemBlue, which does not belong on a Twitter surface.
    UIColor* accent = active ? NFBBrandAccentColor() : nil;

    UIColor* applied = objc_getAssociatedObject(bar, &kNFBAppliedAccentKey);
    BOOL changed = !((applied == nil && accent == nil) ||
                     (applied && accent && [applied isEqual:accent]));

    // In Liquid Glass the native tab bar takes its selected colour straight from
    // tintColor, so this line is what actually paints the tab. Never leave it nil
    // when the toggle is off: nil makes the bar INHERIT the window tint (iOS blue
    // after a reset, or the picked colour even with tab_bar_theming off). labelColor
    // is the native black and, being explicit, it overrides the window tint so the
    // tab strictly respects the toggle.
    bar.tintColor = accent ?: [UIColor labelColor];

    if (!changed) {
        return;
    }

    // The transition only counts once the bar is in a window: marking an
    // off-screen bar "done" would skip the visible repaint on every later
    // pass. And the appearance is assigned exactly once per transition: each
    // assignment installs a fresh copy, orphaning Twitter's own later writes
    // (its badge colour) on the instance it still holds.
    if (!bar.window) {
        return;
    }
    objc_setAssociatedObject(bar, &kNFBAppliedAccentKey, accent,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UITabBarAppearance* standard = bar.standardAppearance;
    if (standard) {
        bar.standardAppearance = standard;
    }
    if (@available(iOS 15.0, *)) {
        UITabBarAppearance* scrollEdge = bar.scrollEdgeAppearance;
        if (scrollEdge) {
            bar.scrollEdgeAppearance = scrollEdge;
        }
    }
}


// Twitter 12.21 deleted T1LiquidGlassTabBarController and its whole native
// tab-bar path (measured: absent from all 56 binaries, present in 12.15). Until
// then, forcing UIDesignRequiresCompatibility to NO was enough - the app took
// its own native route and iOS glazed the bar itself.
//
// Rebuilt the way PrimeSenger does it on Messenger: a real UITabBar standing
// outside any UITabBarController still receives the full iOS 26 treatment.
// It has to be the real, interactive control - the long-press-and-slide that
// moves between tabs belongs to UITabBar's own gesture machinery, and a
// decorative copy with interaction switched off loses it.
//
// Messenger hands out UITabBarItem objects plus viewForItem:/didTapButton:, so
// that tweak routes taps in one line. Twitter exposes none of that, so the
// selection is routed through a cascade, tried in order and reported: the
// app's own selectTabAtIndex:, then setSelectedIndex:, then the tab's host
// view as a control, then its gesture recognisers. If every rung fails the
// host bar is handed straight back, so navigation is never lost.
static const void* kNFBTabBarKey = &kNFBTabBarKey;
static const void* kNFBTabHiddenKey = &kNFBTabHiddenKey;
static const void* kNFBTabBridgeKey = &kNFBTabBridgeKey;
// Shared with the debugger, which reports the rung the last tap used.
extern const void* NFBTabRouteProbeKey(void);

static UIView* NFBCustomTabBar(UIView* host) {
    __block UIView* found = nil;
    EnumerateSubviewsRecursively(host, ^(UIView* sub) {
      if (!found && [NSStringFromClass([sub class]) containsString:@"CustomTabBar"]) {
          found = sub;
      }
    });
    return found;
}

// Twitter's tab views, left to right.
static NSArray<UIView*>* NFBTabViews(UIView* bar) {
    NSMutableArray<UIView*>* tabs = [NSMutableArray array];
    EnumerateSubviewsRecursively(bar, ^(UIView* sub) {
      if ([NSStringFromClass([sub class]) isEqualToString:@"T1TabView"]) {
          [tabs addObject:sub];
      }
    });
    [tabs sortUsingComparator:^NSComparisonResult(UIView* a, UIView* b) {
      CGFloat ax = [a convertPoint:CGPointZero toView:bar].x;
      CGFloat bx = [b convertPoint:CGPointZero toView:bar].x;
      return ax < bx ? NSOrderedAscending : (ax > bx ? NSOrderedDescending : NSOrderedSame);
    }];
    return tabs;
}

static NSUInteger NFBSelectedTabIndex(NSArray<UIView*>* tabs) {
    for (NSUInteger i = 0; i < tabs.count; i++) {
        id tab = tabs[i];
        if ([tab respondsToSelector:@selector(isSelected)] && [tab isSelected]) {
            return i;
        }
    }
    return NSNotFound;
}

// First responder up the chain that answers `sel`, starting at the view.
static id NFBResponderAnswering(UIView* view, SEL sel) {
    UIResponder* candidate = view;
    while (candidate) {
        if ([candidate respondsToSelector:sel]) {
            return candidate;
        }
        candidate = candidate.nextResponder;
    }
    return nil;
}

// Selection routing, rung by rung. Returns the name of the rung that worked.
static NSString* NFBRouteTabSelection(UIView* hostBar, NSArray<UIView*>* tabs,
                                      NSUInteger index) {
    if (index >= tabs.count) {
        return nil;
    }
    UIView* tab = tabs[index];

    id target = NFBResponderAnswering(hostBar, @selector(selectTabAtIndex:));
    if (target) {
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(target, @selector(selectTabAtIndex:),
                                                     (NSInteger)index);
        return @"selectTabAtIndex:";
    }
    target = NFBResponderAnswering(hostBar, @selector(setSelectedIndex:));
    if (target) {
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(target, @selector(setSelectedIndex:),
                                                     (NSInteger)index);
        return @"setSelectedIndex:";
    }
    // The tab's own host view, if the app made it a control.
    for (UIView* up = tab; up && up != hostBar.superview; up = up.superview) {
        if ([up isKindOfClass:[UIControl class]]) {
            [(UIControl*)up sendActionsForControlEvents:UIControlEventTouchUpInside];
            return @"UIControl";
        }
    }
    // No further rung is attempted. Firing a gesture recogniser by hand is not
    // something UIKit supports, and a wrong guess here would leave the reader
    // with a bar that does not navigate. The caller hands the app's bar back
    // instead, and the probe reports what the tab chain does expose.
    return nil;
}

@interface NFBTabBarBridge : NSObject <UITabBarDelegate>
@property (nonatomic, weak) UIView* host;
@end

@implementation NFBTabBarBridge

- (void)tabBar:(UITabBar*)tabBar didSelectItem:(UITabBarItem*)item {
    UIView* host = self.host;
    UIView* bar = host ? NFBCustomTabBar(host) : nil;
    if (!bar) {
        return;
    }
    NSArray<UIView*>* tabs = NFBTabViews(bar);
    NSUInteger index = (NSUInteger)item.tag;
    NSString* rung = NFBRouteTabSelection(bar, tabs, index);
    objc_setAssociatedObject(host, NFBTabRouteProbeKey(), rung ?: @"NONE",
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NFBDebugLog(@"[tabbar] tab %lu routed via %@", (unsigned long)index, rung ?: @"NOTHING");
    if (rung) {
        return;
    }
    // Nothing worked: give the app its own bar back rather than leave the
    // reader with a tab bar that does not navigate.
    for (UIView* hidden in objc_getAssociatedObject(host, kNFBTabHiddenKey)) {
        hidden.hidden = NO;
    }
    objc_setAssociatedObject(host, kNFBTabHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [tabBar removeFromSuperview];
    objc_setAssociatedObject(host, kNFBTabBarKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NFBDebugLog(@"[tabbar] FAILSAFE: no route found, host bar restored");
}

@end

static void NFBApplyTabBarGlass(UIView* host) {
    UITabBar* native = objc_getAssociatedObject(host, kNFBTabBarKey);

    if (![BHTSettings boolForKey:@"enable_liquid_glass"]) {
        if (native) {
            [native removeFromSuperview];
            objc_setAssociatedObject(host, kNFBTabBarKey, nil,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(host, kNFBTabBridgeKey, nil,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        for (UIView* hidden in objc_getAssociatedObject(host, kNFBTabHiddenKey)) {
            hidden.hidden = NO;
        }
        objc_setAssociatedObject(host, kNFBTabHiddenKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }

    UIView* bar = NFBCustomTabBar(host);
    UIView* parent = bar.superview;
    NSArray<UIView*>* tabs = bar ? NFBTabViews(bar) : nil;
    if (!parent || tabs.count == 0) {
        return;  // Laid out later; the next pass will find it.
    }

    if (!native) {
        NFBTabBarBridge* bridge = [[NFBTabBarBridge alloc] init];
        bridge.host = host;
        native = [[UITabBar alloc] initWithFrame:parent.bounds];
        native.delegate = bridge;
        native.autoresizingMask =
            UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        objc_setAssociatedObject(host, kNFBTabBarKey, native,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(host, kNFBTabBridgeKey, bridge,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NFBDebugLog(@"[tabbar] native UITabBar built for %@ (%lu tabs)",
                    NSStringFromClass([parent class]), (unsigned long)tabs.count);
    }

    // Items carry the app's own icons and titles, so the bar reads as Twitter's
    // while UIKit draws the platter, the capsule and the slide gesture.
    if (native.items.count != tabs.count) {
        NSMutableArray<UITabBarItem*>* items = [NSMutableArray array];
        for (NSUInteger i = 0; i < tabs.count; i++) {
            id tab = tabs[i];
            UIImage* image = nil;
            NSString* title = nil;
            if ([tab respondsToSelector:@selector(imageView)]) {
                image = [(UIImageView*)[tab imageView] image];
            }
            if ([tab respondsToSelector:@selector(title)]) {
                title = [tab title];
            }
            UITabBarItem* item =
                [[UITabBarItem alloc] initWithTitle:title
                                              image:[image imageWithRenderingMode:
                                                                UIImageRenderingModeAlwaysTemplate]
                                                tag:(NSInteger)i];
            [items addObject:item];
        }
        native.items = items;
        NFBDebugLog(@"[tabbar] %lu item(s) installed from the app's own tabs",
                    (unsigned long)items.count);
    }

    // On top of the host bar, re-seated every pass: the bar has to receive the
    // touches for the long-press-and-slide to exist at all.
    NSUInteger nativeIndex = [parent.subviews indexOfObject:native];
    NSUInteger barIndex = [parent.subviews indexOfObject:bar];
    BOOL seated = native.superview == parent && nativeIndex != NSNotFound &&
                  barIndex != NSNotFound && nativeIndex > barIndex;
    if (!seated) {
        [native removeFromSuperview];
        [parent insertSubview:native aboveSubview:bar];
        NFBDebugLog(@"[tabbar] seated above %@ at %lu/%lu",
                    NSStringFromClass([bar class]),
                    (unsigned long)[parent.subviews indexOfObject:native],
                    (unsigned long)parent.subviews.count);
    }
    if (!CGRectEqualToRect(native.frame, parent.bounds)) {
        native.frame = parent.bounds;
    }

    NSUInteger selected = NFBSelectedTabIndex(tabs);
    if (selected != NSNotFound && selected < native.items.count &&
        native.selectedItem != native.items[selected]) {
        native.selectedItem = native.items[selected];
    }

    // The app's own icons and its opaque backdrop are hidden, not cleared: the
    // native bar draws the icons now, and glass samples what is behind it.
    NSMutableArray<UIView*>* hidden =
        objc_getAssociatedObject(host, kNFBTabHiddenKey) ?: [NSMutableArray array];
    NSUInteger before = hidden.count;
    void (^hide)(UIView*) = ^(UIView* view) {
      if (view && ![hidden containsObject:view]) {
          [hidden addObject:view];
      }
      view.hidden = YES;
    };
    hide(bar);
    // Every sibling that draws something, not only the opaque ones: the app's
    // own capsule and its faded icons showed through the glass because they
    // carry a translucent fill, and the alpha > 0.9 test walked past them.
    for (UIView* sub in parent.subviews) {
        if (sub == native || sub == bar) {
            continue;
        }
        hide(sub);
    }
    EnumerateSubviewsRecursively(host, ^(UIView* sub) {
      if (sub == native || [sub isDescendantOfView:native] || sub == bar ||
          [sub isDescendantOfView:bar] || sub == parent ||
          [native isDescendantOfView:sub]) {
          return;
      }
      UIColor* colour = sub.backgroundColor;
      CGFloat alpha = 0;
      if (colour && ([colour getWhite:NULL alpha:&alpha] ||
                     [colour getRed:NULL green:NULL blue:NULL alpha:&alpha]) &&
          alpha > 0.05) {
          hide(sub);
      }
    });
    if (hidden.count != before) {
        objc_setAssociatedObject(host, kNFBTabHiddenKey, hidden,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NFBDebugLog(@"[tabbar] %lu view(s) hidden behind the native bar",
                    (unsigned long)hidden.count);
    }
}

static void NFBSweepNativeTabBars(UIView* root, UIColor* accent) {
    if ([root isKindOfClass:[UITabBar class]]) {
        NFBApplyTabBarAccent((UITabBar*)root);
        [root setNeedsLayout];
        return;
    }
    for (UIView* sub in root.subviews) {
        NFBSweepNativeTabBars(sub, accent);
    }
}

// Twitter hides the tab bar on its settings screens, so finding one — native
// UITabBar, or the T1 custom bar whose class names all contain "TabBar" — is
// the signal that the timeline chrome is actually back on screen.
static BOOL NFBViewTreeHasTabBar(UIView* root) {
    if ([root isKindOfClass:[UITabBar class]] ||
        [NSStringFromClass([root class]) containsString:@"TabBar"]) {
        return YES;
    }
    for (UIView* sub in root.subviews) {
        if (NFBViewTreeHasTabBar(sub)) {
            return YES;
        }
    }
    return NO;
}

// Re-apply the tweak's accent to whatever chrome is on screen right now.
static void NFBReapplyChromeAccent(void) {
    UIColor* accent = CurrentAccentColor();
    void (^run)(void) = ^{
        NFBRetintRegisteredLogos();
        for (id scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:objc_getClass("UIWindowScene")]) {
                continue;
            }
            for (UIWindow* w in [scene windows]) {
                NFBSweepTopBarLogos(w);
                // Ungated: the applier is bidirectional and decides
                // accent-or-native itself; gating on the toggle blocked the
                // NATIVE revert when the switch was turned off.
                NFBSweepNativeTabBars(w, accent);
                [w setNeedsLayout];
                [w layoutIfNeeded];
            }
        }
    };
    if ([NSThread isMainThread]) { run(); }
    else { dispatch_async(dispatch_get_main_queue(), run); }
}

// Twitter's OWN repaint path: TFNDynamicColorManager's reloadDynamicColors
// walks every registered dynamic-colour setter and repaints, which is what
// the navigation bar and tab bar actually use.
static void NFBReloadTwitterDynamicColors(void) {
    Class managerClass = objc_getClass("TFNDynamicColorManager");
    id manager = nil;
    if (managerClass) {
        for (NSString* accessor in
             @[@"sharedColorManager", @"defaultManager", @"sharedManager", @"sharedInstance"]) {
            SEL sel = NSSelectorFromString(accessor);
            if ([managerClass respondsToSelector:sel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                manager = [managerClass performSelector:sel];
#pragma clang diagnostic pop
                if (manager) {
                    break;
                }
            }
        }
    }
    SEL reload = NSSelectorFromString(@"reloadDynamicColors");
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    if ([manager respondsToSelector:reload]) {
        [manager performSelector:reload];
    } else if (managerClass && [managerClass respondsToSelector:reload]) {
        [managerClass performSelector:reload];
    }
#pragma clang diagnostic pop

    // Broadcast the pair Twitter's views actually observe — the binary is full
    // of _tfn_dynamicColorsWillReload:/_tfn_dynamicColorsDidReload: observers
    // (T1, TFN, and the Swift hosting views), and the tab icons' vector images
    // register dynamic-colour info on this very bus. Posting the pair directly
    // makes those views re-resolve their colours through the tweak's palette hooks even
    // when the manager accessor above finds nothing.
    NSNotificationCenter* nc = NSNotificationCenter.defaultCenter;
    [nc postNotificationName:@"TFNDynamicColorsWillReloadNotification" object:nil];
    [nc postNotificationName:@"TFNDynamicColorsDidReloadNotification" object:nil];
    [nc postNotificationName:@"TAEColorSettingsDidChangeUserDefaultsNotification"
                      object:nil];
}

// MARK: - Accent settle timer

// The appliers are idempotent and correct; the open question is only the
// moment they run. Neither didMoveToWindow, layoutSubviews nor
// viewDidAppear is guaranteed to fire exactly when the timeline chrome returns
// (and which view even hosts it differs between Standard and Liquid Glass). So
// after every accent change, re-run the idempotent, per-view-guarded appliers
// on a short cadence until a tab bar has actually been seen on screen, then one
// grace pass, hard-capped at six seconds. It is the manual tab change, automated.
static dispatch_source_t NFBAccentSettleTimer;

static BOOL NFBAccentSettlePass(void) {
    extern void NFBRestyleComposeFAB(void);
    NFBRetintRegisteredLogos();
    UIColor* accent = CurrentAccentColor();
    BOOL chromeSeen = NO;
    for (id scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:objc_getClass("UIWindowScene")]) {
            continue;
        }
        for (UIWindow* w in [scene windows]) {
            NFBSweepTopBarLogos(w);
            NFBSweepNativeTabBars(w, accent);
            if (!chromeSeen && NFBViewTreeHasTabBar(w)) {
                chromeSeen = YES;
            }
        }
    }
    NFBReapplyTabBarAccent();
    NFBRestyleComposeFAB();
    return chromeSeen;
}

static void NFBStartAccentSettle(void) {
    if (NFBAccentSettleTimer) {
        dispatch_source_cancel(NFBAccentSettleTimer);
        NFBAccentSettleTimer = nil;
    }
    __block NSInteger ticks = 0;
    __block NSInteger graceLeft = -1;
    dispatch_source_t timer =
        dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 0),
                              (uint64_t)(0.3 * NSEC_PER_SEC),
                              (uint64_t)(0.05 * NSEC_PER_SEC));
    dispatch_source_set_event_handler(timer, ^{
        ticks++;
        BOOL seen = NFBAccentSettlePass();
        // (Two diagnostic sweeps once counted tab bars and floating action
        // buttons here; their results were never read — removed.)
        if (seen && graceLeft < 0) {
            graceLeft = 2;
        }
        if (graceLeft > 0) {
            graceLeft--;
        }
        if (graceLeft == 0 || ticks >= 20) {
            NFBAccentPending = NO;
            if (NFBAccentSettleTimer == timer) {
                dispatch_source_cancel(timer);
                NFBAccentSettleTimer = nil;
            }
        }
    });
    NFBAccentSettleTimer = timer;
    dispatch_resume(timer);
}

void NFBSyncAccentTheme(void) {
    NFBAccentPending = YES;
    id settings = [objc_getClass("TAEColorSettings") sharedSettings];
    if ([settings respondsToSelector:@selector(applyCurrentColorPalette)]) {
        [settings performSelector:@selector(applyCurrentColorPalette)];
    }

    // Rebuild Twitter's cached primary-colour-derived colours (FAB, follow
    // buttons, pill, badges, selection). It resolves through the palette
    // accessors the tweak now hooks on every subclass, so the results become custom.
    Class T1ColorSettingsCls = objc_getClass("T1ColorSettings");
    if ([T1ColorSettingsCls respondsToSelector:@selector(_t1_applyPrimaryColorOption)]) {
        [T1ColorSettingsCls performSelector:@selector(_t1_applyPrimaryColorOption)];
    }

    // Liquid Glass controls read the window tint, not the palette.
    NFBApplyGlobalTint();

    // No window check: while the settings screen is pushed the timeline's views
    // are detached (window == nil), which is precisely when a colour gets
    // picked. The weak ref stays valid, so re-tint it regardless.
    UIImageView* logo = NFBTopBarLogoView;
    if (logo) {
        NFBApplyLogoTint(logo);
    }
    extern void NFBRestyleComposeFAB(void);
    NFBRestyleComposeFAB();
    NFBReapplyTabBarAccent();
    UIColor* sweepAccent = CurrentAccentColor();
    for (id scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:objc_getClass("UIWindowScene")]) {
            continue;
        }
        for (UIWindow* w in [scene windows]) {
            NFBSweepTopBarLogos(w);
            NFBSweepNativeTabBars(w, sweepAccent);
            // Force a layout pass so the navigation-bar and tab-bar hooks run
            // now, instead of waiting for the next natural relayout.
            [w setNeedsLayout];
            [w layoutIfNeeded];
        }
    }

    NFBReloadTwitterDynamicColors();
    NFBStartAccentSettle();
}

static CFAbsoluteTime NFBThemeLoadTime;

// Shown when the user leaves a dark palette while Dim/Grey/Blackout was active:
// live views keep their old backgrounds, so suggest a quick restart to clear them.
static void NFBShowRestartReminder(void) {
    if (CFAbsoluteTimeGetCurrent() - NFBThemeLoadTime < 5.0) {
        return; // ignore palette churn during app launch
    }
    UIWindow* keyWindow = nil;
    for (UIWindow* window in UIApplication.sharedApplication.windows) {
        if (window.isKeyWindow) { keyWindow = window; break; }
    }
    UIViewController* top = keyWindow.rootViewController;
    if (!top) { return; }
    while (top.presentedViewController) {
        top = top.presentedViewController;
    }
    UIAlertController* alert = [UIAlertController
        alertControllerWithTitle:@"Back to light mode"
                         message:@"Your dark style was reset to System. Restart Twitter to clear any leftover dark colors."
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Later"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Close app"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction* action) {
                                                exit(0);
                                            }]];
    [top presentViewController:alert animated:YES completion:nil];
}

// Every apply path (launch re-apply, trait changes, both settings pickers)
// funnels through this setter, so coercing here keeps the custom color pinned.
%hook TAEColorSettings

- (void)setPrimaryColorOption:(NSInteger)colorOption {
    NSNumber* selectedColor = selectedThemeColor();
    %orig(selectedColor ? selectedColor.integerValue : colorOption);
}

- (void)setCurrentColorPalette:(TAETwitterColorPaletteSettingInfo*)palette {
    %orig(palette);
    // Twitter just swapped Day/Night. Once settled, if not dark, back to System
    // and remind the user to restart so leftover dark backgrounds clear out.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (![DarkModeStyle isDarkModeActive]) {
            // Twitter switched to a light palette. Read the pinned style FIRST,
            // then drop it back to System, then (if it wasn't already System)
            // remind the user to restart so any leftover dark backgrounds on
            // live views clear out. Order matters: the previous value has to be
            // captured before the overwrite, or the reminder's condition would
            // always see System and never fire.
            NSInteger previous = [[NSUserDefaults standardUserDefaults]
                integerForKey:@"dark_mode_style"];
            [[NSUserDefaults standardUserDefaults]
                setInteger:NFBDarkModeStyleSystem
                    forKey:@"dark_mode_style"];
            if (previous != NFBDarkModeStyleSystem) {
                NFBShowRestartReminder();
            }
        }
    });
}

- (NSInteger)primaryColorOption {
    NSNumber* selectedColor = selectedThemeColor();
    return selectedColor ? selectedColor.integerValue : %orig;
}

%end

%hook TAEDarkColorPalette

- (UIColor*)avatarPlaceholderBackgroundColor {
    UIColor* o = %orig;
    return customAccentActive() ? NFBPlaceholderGrey() : o;
}
- (UIColor*)avatarPlaceholderUIColor {
    UIColor* o = %orig;
    return customAccentActive() ? NFBPlaceholderGrey() : o;
}
- (UIColor*)primaryColor {
    UIColor* o = %orig;
    return NFBAccent(o);
}
- (UIColor*)primaryColorForOption:(NSUInteger)colorOption {
    UIColor* o = %orig;
    return NFBAccent(o);
}
- (UIColor*)primaryColorOptionBlueColor {
    UIColor* o = %orig;
    return NFBAccent(o);
}
- (UIColor*)primaryColorOptionGreenColor {
    UIColor* o = %orig;
    return NFBAccent(o);
}
- (UIColor*)primaryColorOptionYellowColor {
    UIColor* o = %orig;
    return NFBAccent(o);
}
- (UIColor*)primaryColorOptionOrangeColor {
    UIColor* o = %orig;
    return NFBAccent(o);
}
- (UIColor*)primaryColorOptionPurpleColor {
    UIColor* o = %orig;
    return NFBAccent(o);
}
- (UIColor*)primaryColorOptionRedColor {
    UIColor* o = %orig;
    return NFBAccent(o);
}
- (UIColor*)brandLogoColor {
    UIColor* o = %orig;
    return NFBLogoAccent(o);
}
- (UIColor*)navigationBarLogoColor {
    UIColor* o = %orig;
    return NFBLogoAccent(o);
}
%end

%hook TAELightColorPalette

- (UIColor*)avatarPlaceholderBackgroundColor {
    UIColor* o = %orig;
    return customAccentActive() ? NFBPlaceholderGrey() : o;
}
- (UIColor*)avatarPlaceholderUIColor {
    UIColor* o = %orig;
    return customAccentActive() ? NFBPlaceholderGrey() : o;
}
- (UIColor*)primaryColor {
    UIColor* o = %orig;
    return NFBAccent(o);
}
- (UIColor*)primaryColorForOption:(NSUInteger)colorOption {
    UIColor* o = %orig;
    return NFBAccent(o);
}
- (UIColor*)primaryColorOptionBlueColor {
    UIColor* o = %orig;
    return NFBAccent(o);
}
- (UIColor*)primaryColorOptionGreenColor {
    UIColor* o = %orig;
    return NFBAccent(o);
}
- (UIColor*)primaryColorOptionYellowColor {
    UIColor* o = %orig;
    return NFBAccent(o);
}
- (UIColor*)primaryColorOptionOrangeColor {
    UIColor* o = %orig;
    return NFBAccent(o);
}
- (UIColor*)primaryColorOptionPurpleColor {
    UIColor* o = %orig;
    return NFBAccent(o);
}
- (UIColor*)primaryColorOptionRedColor {
    UIColor* o = %orig;
    return NFBAccent(o);
}
- (UIColor*)brandLogoColor {
    UIColor* o = %orig;
    return NFBLogoAccent(o);
}
- (UIColor*)navigationBarLogoColor {
    UIColor* o = %orig;
    return NFBLogoAccent(o);
}
%end

%hook TFNUIDefaultColorPalette

- (UIColor*)avatarPlaceholderBackgroundColor {
    UIColor* o = %orig;
    return customAccentActive() ? NFBPlaceholderGrey() : o;
}
- (UIColor*)avatarPlaceholderUIColor {
    UIColor* o = %orig;
    return customAccentActive() ? NFBPlaceholderGrey() : o;
}
- (UIColor*)primaryColor {
    UIColor* o = %orig;
    return NFBAccent(o);
}
- (UIColor*)primaryColorForOption:(NSUInteger)colorOption {
    UIColor* o = %orig;
    return NFBAccent(o);
}
- (UIColor*)primaryColorOptionBlueColor {
    UIColor* o = %orig;
    return NFBAccent(o);
}
- (UIColor*)primaryColorOptionGreenColor {
    UIColor* o = %orig;
    return NFBAccent(o);
}
- (UIColor*)primaryColorOptionYellowColor {
    UIColor* o = %orig;
    return NFBAccent(o);
}
- (UIColor*)primaryColorOptionOrangeColor {
    UIColor* o = %orig;
    return NFBAccent(o);
}
- (UIColor*)primaryColorOptionPurpleColor {
    UIColor* o = %orig;
    return NFBAccent(o);
}
- (UIColor*)primaryColorOptionRedColor {
    UIColor* o = %orig;
    return NFBAccent(o);
}
- (UIColor*)navigationBarLogoColor {
    UIColor* o = %orig;
    return NFBLogoAccent(o);
}
%end

// Liquid Glass: keep the custom tint on any window created after launch. Under
// the standard interface the window keeps its own tint, so nothing inherits the
// accent that should not.
%hook UIWindow
- (void)makeKeyAndVisible {
    %orig;
    if ([BHTSettings boolForKey:@"enable_liquid_glass"] && customAccentActive()) {
        self.tintColor = customAccentColor();
    }
}
%end

%hook TAEColorPalette

- (UIColor*)avatarPlaceholderBackgroundColor {
    UIColor* o = %orig;
    return customAccentActive() ? NFBPlaceholderGrey() : o;
}
- (UIColor*)avatarPlaceholderUIColor {
    UIColor* o = %orig;
    return customAccentActive() ? NFBPlaceholderGrey() : o;
}
- (UIColor*)_t1_infoTextColorForOptions:(NSUInteger)options {
    if (customAccentActive()) {
        UIColor* c = customAccentColor();
        if (c) { return c; }
    }
    return %orig;
}
- (UIColor*)linkColor {
    if (customAccentActive()) {
        UIColor* c = customAccentColor();
        if (c) { return c; }
    }
    return %orig;
}
- (UIColor*)textLinkColor {
    if (customAccentActive()) {
        UIColor* c = customAccentColor();
        if (c) { return c; }
    }
    return %orig;
}

- (UIColor*)tabBarItemColor {
    if (customAccentActive()) {
        UIColor* c = customAccentColor();
        if (c) { return c; }
    }
    return %orig;
}

// The resolved accent every control reads (compose FAB, follow buttons, the
// "new tweets" pill, selection highlights). primaryColorForOption: is the
// palette-option lookup; -primaryColor is the already-resolved result, and
// buttons ask for THIS, which is why links went custom but buttons stayed blue.
- (UIColor*)primaryColor {
    if (customAccentActive() && !NFBRawPaletteReading()) {
        UIColor* c = customAccentColor();
        if (c) { return c; }
    }
    return %orig;
}

- (UIColor*)primaryButtonBackgroundColor {
    if (customAccentActive()) {
        UIColor* c = customAccentColor();
        if (c) { return c; }
    }
    return %orig;
}

- (UIColor*)primaryOutlinedButtonBorderColor {
    if (customAccentActive()) {
        UIColor* c = customAccentColor();
        if (c) { return c; }
    }
    return %orig;
}

%end

%hook TFNTwitterStatusDisplayAttributedTextModelFontOptions
- (UIColor*)linkTextColor {
    if (customAccentActive()) {
        UIColor* c = customAccentColor();
        if (c) { return c; }
    }
    return %orig;
}
%end

%hook TFNMutableTwitterStatusDisplayAttributedTextModelFontOptions
- (UIColor*)linkTextColor {
    if (customAccentActive()) {
        UIColor* c = customAccentColor();
        if (c) { return c; }
    }
    return %orig;
}
%end

void applySelectedThemeColor(void) {
    NSNumber* selectedColor = selectedThemeColor();
    if (selectedColor) {
        [[objc_getClass("TAEColorSettings") sharedSettings]
            setPrimaryColorOption:selectedColor.integerValue];
    }
}

static void NFBRefreshSubviewBackgrounds(UIView* view) {
    UIColor* current = view.backgroundColor;
    if (current) {
        view.backgroundColor = nil;
        view.backgroundColor = current;
    }
    for (UIView* sub in view.subviews) {
        NFBRefreshSubviewBackgrounds(sub);
    }
}

static void NFBForceBackgroundRefresh(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        for (UIWindow* window in UIApplication.sharedApplication.windows) {
            NFBRefreshSubviewBackgrounds(window);
        }
    });
}

%ctor {
    NFBThemeLoadTime = CFAbsoluteTimeGetCurrent();
    [[NSNotificationCenter defaultCenter]
        addObserverForName:@"TAEColorSettingsDidChangeUserDefaultsNotification"
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification* note) {
                    // Leaving a dark palette is handled in one place only —
                    // -setCurrentColorPalette: reads the pinned style, drops it
                    // back to System and shows the restart reminder. Doing the
                    // reset here too raced ahead of that path: this notification
                    // fires first, so dark_mode_style was already System by the
                    // time the reminder checked, and the popup never appeared.
                    // Here the tweak only refreshes backgrounds.
                    NFBForceBackgroundRefresh();
                }];

    // Whenever Twitter repaints its own dynamic colours — for any reason, from
    // any screen — repaint the tweak's in the same pass: no layout guessing, no
    // timers.
    [[NSNotificationCenter defaultCenter]
        addObserverForName:@"TFNDynamicColorsDidReloadNotification"
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification* note) {
                    NFBReapplyChromeAccent();
                }];

    // Surfaces that resolve their colour once at launch and then cache it —
    // the theme screen's confirm control — never see the tweak's palette without a
    // reload pass. If an accent is active, broadcast one shortly after boot:
    // the same pass a live colour change performs.
    if (NFBAccentIsActive()) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
                           // The window tint IS the Confirm button's colour;
                           // the reload alone re-resolves Twitter's palette but
                           // never sets the tweak's tint. Set it here, at the moment
                           // the window exists.
                           NFBApplyGlobalTint();
                           NFBReloadTwitterDynamicColors();
                       });
    }
}

// MARK: - Custom tab bar order and visibility

static NSString* scribePageForEntry(id<T1AppNavigationTabEntry> entry) {
    if (![entry respondsToSelector:@selector(tabView)]) {
        return nil;
    }
    return [entry tabView].scribePage;
}

// Operates on the tab ENTRIES, not the button views: the app derives both the
// buttons and their content view controllers from this one array.
static NSArray* orderedTabEntries(NSArray* entries) {
    // Record the underlying tab views so the editor can show real titles and icons.
    NSMutableArray* tabViews = [NSMutableArray new];
    for (id<T1AppNavigationTabEntry> entry in entries) {
        T1TabView* tabView = [entry respondsToSelector:@selector(tabView)] ? [entry tabView] : nil;
        if (tabView) {
            [tabViews addObject:tabView];
        }
    }
    [CustomTabBarUtility recordTabViews:tabViews];

    NSArray<NSString*>* visibleOrder = [CustomTabBarUtility visiblePageIDsInOrder];

    NSMutableDictionary<NSString*, id>* entriesByPage = [NSMutableDictionary new];
    for (id<T1AppNavigationTabEntry> entry in entries) {
        NSString* page = scribePageForEntry(entry);
        if (page && !entriesByPage[page]) {
            entriesByPage[page] = entry;
        }
    }

    // Not customised yet: show the default set (Home, Search, Notifications, Chats)
    // in that order, hiding everything else the app builds.
    if (!visibleOrder) {
        NSMutableArray* defaultEntries = [NSMutableArray new];
        for (NSString* pageID in [CustomTabBarUtility defaultVisiblePageIDs]) {
            id entry = entriesByPage[pageID];
            if (entry) {
                [defaultEntries addObject:entry];
            }
        }
        return defaultEntries;
    }

    // Only the chosen tabs show; anything the editor hasn't been told to show
    // (including tabs unlocked after the user last saved) stays hidden.
    NSMutableArray* orderedEntries = [NSMutableArray new];
    NSMutableSet* placed = [NSMutableSet new];
    for (NSString* pageID in visibleOrder) {
        id entry = entriesByPage[pageID];
        if (entry && ![placed containsObject:pageID]) {
            [orderedEntries addObject:entry];
            [placed addObject:pageID];
        }
    }

    return orderedEntries;
}

// The single ordered spine that feeds both the tab buttons and their content, so
// filtering/reordering here keeps taps mapped to the right panel.
%hook T1TabbedAppNavigationViewController

- (void)setVisibleTabEntries:(NSArray*)entries {
    %orig(orderedTabEntries(entries));
}

%end

// MARK: - Keep tab bar visible

%hook T1TabBarViewController

// The scroll-driven hide only reaches the tab bar as a collapse ratio, so
// clamping it spares the deliberate hides (fullscreen media, immersive player).
- (void)setTabBarCollapseRatio:(double)ratio {
    if ([BHTSettings boolForKey:@"no_tab_bar_hiding"]) {
        %orig(0.0);
    } else {
        %orig(ratio);
    }
}

%end

// MARK: - Tab bar icon and label theming

static BOOL updatingTabIconColor = NO;

static UIColor* tabItemColor(BOOL selected) {
    return selected ? CurrentAccentColor() : [UIColor secondaryLabelColor];
}

static const void* kNFBTabOriginalKey = &kNFBTabOriginalKey;
static const void* kNFBTabBakedKey = &kNFBTabBakedKey;
static const void* kNFBTabColourKey = &kNFBTabColourKey;

// Same trick as the logo: the colour lives in the pixels, so no tint and no
// vibrancy filter downstream can undo it. The untouched image is kept so the
// icon can be handed back when the option goes off.
static void NFBBakeTabIcon(UIImageView* icon, UIColor* colour) {
    UIImage* current = icon.image;
    if (!current || !colour) {
        return;
    }
    UIImage* original = objc_getAssociatedObject(icon, kNFBTabOriginalKey);
    UIImage* baked = objc_getAssociatedObject(icon, kNFBTabBakedKey);
    UIColor* bakedColour = objc_getAssociatedObject(icon, kNFBTabColourKey);
    if (!original || (current != original && current != baked)) {
        original = current;
        objc_setAssociatedObject(icon, kNFBTabOriginalKey, original,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        baked = nil;
    }
    if (!baked || ![bakedColour isEqual:colour]) {
        baked = NFBPaintedGlyph(original, colour);
        objc_setAssociatedObject(icon, kNFBTabBakedKey, baked,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(icon, kNFBTabColourKey, colour,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (icon.image != baked) {
        icon.image = baked;
    }
}

static void NFBRestoreTabIcon(UIImageView* icon) {
    UIImage* original = objc_getAssociatedObject(icon, kNFBTabOriginalKey);
    if (original && icon.image != original) {
        icon.image = original;
    }
}

%hook T1TabView

- (void)_t1_updateImageViewAnimated:(BOOL)animated {
    // setIconColor: re-enters this method, so swallow the inner call and let
    // %orig below render once with the new color
    if (updatingTabIconColor) {
        return;
    }

    updatingTabIconColor = YES;
    if ([BHTSettings boolForKey:@"tab_bar_theming"]) {
        self.iconColor = tabItemColor(self.selected);
    } else if (self.iconColor) {
        self.iconColor = nil;
    }
    updatingTabIconColor = NO;

    %orig(animated);

    // 12.21: the tab icon arrives rendered AlwaysOriginal (measured in a
    // capture: mode=1 with the tint set and ignored), so the colour set above
    // never reaches it. Rendering it as a template lets the tint through again.
    // 12.21: setting iconColor no longer reaches the icon, and a tintColor is
    // replaced by the app's own right after. Measured in a capture: template
    // image, tint back to the system grey and to Twitter blue on the selected
    // tab. So the colour is baked into the image, served AlwaysOriginal, which
    // nothing downstream can repaint.
    if ([BHTSettings boolForKey:@"tab_bar_theming"]) {
        NFBBakeTabIcon(self.imageView, tabItemColor(self.selected));
    } else {
        NFBRestoreTabIcon(self.imageView);
    }
}

- (void)_t1_updateTitleLabel {
    %orig;

    if ([BHTSettings boolForKey:@"tab_bar_theming"]) {
        self.titleLabel.textColor = tabItemColor(self.selected);
    }
}

- (BOOL)showsTitleInDisplayMode:(long long)displayMode {
    if ([BHTSettings boolForKey:@"restore_tab_labels"]) {
        return YES;
    }
    return %orig;
}

// Restored labels were off-centre until something forced a fresh layout: the
// settings page relays out the tabs when the switch is flipped, but on a cold
// launch nothing did, so the tab kept the geometry it computed while the label
// was still hidden. Re-run Twitter's own tab layout as each tab enters a
// window and the labels sit centred from the first frame.
- (void)didMoveToWindow {
    %orig;

    if (!self.window || ![BHTSettings boolForKey:@"restore_tab_labels"]) {
        return;
    }
    if ([self respondsToSelector:@selector(_t1_layoutForTabBar)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [self performSelector:@selector(_t1_layoutForTabBar)];
#pragma clang diagnostic pop
    }
}

%new
- (void)applyCurrentThemeToIcon {
    [self _t1_updateImageViewAnimated:NO];
    [self _t1_updateTitleLabel];
}

%end

// MARK: - Top bar logo theming

%hook _TtC11TwitterHome39HomeDefaultNavigationBarTitleViewPlugin

- (UIView*)titleView {
    UIView* titleView = %orig;
    UIImageView* logo = NFBFindLogoImageView(titleView);
    // iOS 27 does not put the handed-over view on screen: it builds its own
    // image view inside _UINavigationBarTitleControl. Measured in a capture -
    // two image views, ours hidden, the visible one tinted by the bar. The
    // sweep below runs after the bar has built that chain.
    dispatch_async(dispatch_get_main_queue(), ^{
      UIView* bar = titleView;
      while (bar && ![NSStringFromClass([bar class]) containsString:@"NavigationBar"]) {
          bar = bar.superview;
      }
      if (bar) {
          NFBBakeTitleControlLogos(bar);
      }
    });
    if (logo) {
        NFBTopBarLogoView = logo;
        NFBRegisterLogoView(logo);
        NFBApplyLogoTint(logo);
    }
    return titleView;
}

%end

// Same treatment for the segmented-label title variant, which the Liquid Glass
// home can use instead of the default plugin.
%hook _TtC11TwitterHome46HomeSegmentedLabelNavigationBarTitleViewPlugin

- (UIView*)titleView {
    UIView* titleView = %orig;
    UIImageView* logo = NFBFindLogoImageView(titleView);
    if (logo) {
        NFBTopBarLogoView = logo;
        NFBRegisterLogoView(logo);
        NFBApplyLogoTint(logo);
    }
    return titleView;
}

%end

// A native tab bar takes its selected colour from tintColor, unless an explicit
// UITabBarAppearance pins it — and Twitter installs one via setStandardAppearance.
// Cover both paths.
static UITabBarAppearance* NFBPatchedTabBarAppearance(UITabBarAppearance* appearance) {
    if (!appearance) {
        return appearance;
    }
    BOOL active = [BHTSettings boolForKey:@"tab_bar_theming"] && NFBAccentIsActive();
    UIColor* target = active ? CurrentAccentColor() : [UIColor labelColor];
    if (!target) {
        return appearance;
    }
    // Bidirectional on purpose. Restoring a captured "original" appearance was
    // a trap: the one Twitter installs at launch already carries whatever
    // accent was active THEN, so putting it back could never yield black —
    // only a full relaunch did. Neutral = labelColor, the native selected
    // colour in both light and dark mode.
    UITabBarAppearance* patched = [appearance copy];
    // Assigning an appearance costs Twitter its own badge configuration, and
    // UIKit's default badgeBackgroundColor is red. Restore a themed badge
    // deterministically: the accent when one is active, system blue otherwise.
    UIColor* badgeColor = CurrentAccentColor();
    NSArray<UITabBarItemAppearance*>* layouts = @[
        patched.stackedLayoutAppearance,
        patched.inlineLayoutAppearance,
        patched.compactInlineLayoutAppearance
    ];
    for (UITabBarItemAppearance* layout in layouts) {
        layout.normal.badgeBackgroundColor = badgeColor;
        layout.selected.badgeBackgroundColor = badgeColor;
        layout.selected.iconColor = target;
        NSMutableDictionary* attrs =
            [layout.selected.titleTextAttributes mutableCopy] ?: [NSMutableDictionary dictionary];
        attrs[NSForegroundColorAttributeName] = target;
        layout.selected.titleTextAttributes = attrs;
    }
    return patched;
}

%hook T1TabBarHostView

- (void)layoutSubviews {
    %orig;
    NFBApplyTabBarGlass((UIView*)self);
}

%end

// The app lays its own bar out without the host taking part, and puts back what
// was hidden while doing it. Reapplying from here closes that gap - the same
// hook point PrimeSenger uses on Messenger's own bar.
%hook TFNCustomTabBar

- (void)layoutSubviews {
    %orig;
    UIView* host = (UIView*)self;
    while (host && ![NSStringFromClass([host class]) isEqualToString:@"T1TabBarHostView"]) {
        host = host.superview;
    }
    if (host) {
        NFBApplyTabBarGlass(host);
    }
}

%end

%hook UITabBar

- (void)didMoveToWindow {
    %orig;
    NFBApplyTabBarAccent(self);
}

// didMoveToWindow alone was not enough: returning from the settings screen does
// not re-attach the bar, but it always re-lays it out.
- (void)layoutSubviews {
    %orig;
    NFBApplyTabBarAccent(self);
}

- (void)setStandardAppearance:(UITabBarAppearance*)appearance {
    UITabBarAppearance* patched = NFBPatchedTabBarAppearance(appearance);
    if (NFBAccentPending) {
    }
    %orig(patched);
}

- (void)setScrollEdgeAppearance:(UITabBarAppearance*)appearance {
    UITabBarAppearance* patched = NFBPatchedTabBarAppearance(appearance);
    if (NFBAccentPending) {
    }
    %orig(patched);
}

%end

// Belt and braces for the bird: a colour can be picked while the timeline is
// off-screen, so also re-apply on every navigation-bar layout. Cheap, and it
// means returning to the timeline is already enough — no tab switch needed.
// Whitens the confirm-side glyphs while the theme screen is frontmost. The
// VC's own viewDidLayoutSubviews misses BAR-INTERNAL relayouts (Twitter swaps
// or re-bakes the confirm without touching the VC's view) — which is exactly
// when the grey frame slipped through. The bar's layout is the right moment.
// The canonical white bake: draw the original, then sourceIn-fill white — every
// opaque pixel becomes white, alpha preserved, rendering mode plain. Immune to
// the imageWithTintColor quirks (its result can stay template and re-tint with
// the view's tint — the accent — which produced the grey AND, when tint reset,
// the black frames). Shared with Branding so the FAB glyph uses the same bake.
UIImage* NFBWhiteBakedGlyph(UIImage* image) {
    UIGraphicsImageRendererFormat* format =
        [UIGraphicsImageRendererFormat preferredFormat];
    format.opaque = NO;
    UIGraphicsImageRenderer* renderer =
        [[UIGraphicsImageRenderer alloc] initWithSize:image.size format:format];
    UIImage* baked =
        [renderer imageWithActions:^(UIGraphicsImageRendererContext* ctx) {
            CGRect rect = CGRectMake(0, 0, image.size.width, image.size.height);
            [image drawInRect:rect];
            CGContextSetBlendMode(ctx.CGContext, kCGBlendModeSourceIn);
            [[UIColor whiteColor] setFill];
            CGContextFillRect(ctx.CGContext, rect);
        }];
    // The confirm lives in a SwiftUI glass platter
    // (NavigationBarPlatterRepresentable → _UIModernBarButton), and a bar
    // button treats an AUTOMATIC-mode image as a TEMPLATE — the pixels are an
    // alpha mask, re-tinted by the button per its contrast rule.
    // AlwaysOriginal forbids the re-tint: what is baked is what renders; a
    // plain rendered bitmap accepts the mode change, an imageWithTintColor
    // result does not.
    return [baked imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

// Shared tag: once the whitener has identified the confirm glyph, Branding's
// setImage: hook white-bakes every image Twitter assigns to it BEFORE it can
// render — no pass ordering, no race, no dark frame possible.
char NFBConfirmGlyphTag;

static char kNFBWhiteBakedKey;

static char kNFBConfirmGlassCapKey;

// Force the confirm platter's glass to iOS system blue — its native colour —
// while the app's window tint stays Twitter blue for the tab. The glyph is
// already baked white. Same proven trick as the FAB: tint the glass material
// and lay an opaque disc over it so the Twitter-blue tint can't bleed through.
// Scoped to the confirm button's own subtree, so no other glass is touched.
static void NFBTintConfirmGlassBlue(UIView* container) {
    UIColor* blue = [UIColor systemBlueColor];
    for (UIView* sub in container.subviews) {
        if ([sub isKindOfClass:[UIVisualEffectView class]]) {
            UIVisualEffectView* fx = (UIVisualEffectView*)sub;
            UIVisualEffect* effect = fx.effect;
            if (effect && [effect respondsToSelector:@selector(setTintColor:)]) {
                [(id)effect setTintColor:blue];
            }
            if (![fx.backgroundColor isEqual:blue]) {
                fx.backgroundColor = blue;
            }
            if (![fx.contentView.backgroundColor isEqual:blue]) {
                fx.contentView.backgroundColor = blue;
            }
            UIView* cap = objc_getAssociatedObject(fx, &kNFBConfirmGlassCapKey);
            if (!cap) {
                cap = [[UIView alloc] initWithFrame:fx.contentView.bounds];
                cap.autoresizingMask =
                    UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                cap.userInteractionEnabled = NO;
                [fx.contentView insertSubview:cap atIndex:0];
                objc_setAssociatedObject(fx, &kNFBConfirmGlassCapKey, cap,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            cap.backgroundColor = blue;
        }
        NFBTintConfirmGlassBlue(sub);
    }
}

static void NFBWhitenConfirmGlyphsIn(UIView* view, UINavigationBar* bar) {
    for (UIView* sub in view.subviews) {
        if ([sub isKindOfClass:[UIImageView class]]) {
            UIImageView* glyph = (UIImageView*)sub;
            CGRect inBar = [glyph convertRect:glyph.bounds toView:bar];
            if (CGRectGetMidX(inBar) > bar.bounds.size.width * 0.6 &&
                glyph.bounds.size.width > 0 && glyph.bounds.size.width < 44 &&
                glyph.image &&
                objc_getAssociatedObject(glyph, &kNFBWhiteBakedKey) != (id)glyph.image) {
                objc_setAssociatedObject(glyph, &NFBConfirmGlyphTag, @YES,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                UIImage* white = NFBWhiteBakedGlyph(glyph.image);
                glyph.image = white;
                objc_setAssociatedObject(glyph, &kNFBWhiteBakedKey, white,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                // Belt for the one frame a freshly re-created button can show
                // before its first baked image lands: with the whole BarButton
                // chain tinted white, even a template-treated frame is white.
                glyph.tintColor = [UIColor whiteColor];
                UIView* ancestor = glyph.superview;
                for (NSInteger hop = 0; ancestor && hop < 2; hop++) {
                    if ([NSStringFromClass([ancestor class])
                            containsString:@"BarButton"]) {
                        ancestor.tintColor = [UIColor whiteColor];
                    }
                    ancestor = ancestor.superview;
                }
                // Recolour this confirm button's glass to iOS blue (native),
                // decoupled from the Twitter-blue window tint the tab needs.
                UIView* platter = glyph.superview;
                for (NSInteger phop = 0; platter && phop < 5; phop++) {
                    if ([NSStringFromClass([platter class])
                            containsString:@"BarButton"]) {
                        break;
                    }
                    platter = platter.superview;
                }
                NFBTintConfirmGlassBlue(platter ?: glyph.superview);
            }
        }
        NFBWhitenConfirmGlyphsIn(sub, bar);
    }
}

// Exposed so the theme screen can run a pass right after a pick (Twitter
// re-bakes its glyph on the following runloop turn).
void NFBWhitenNavigationBarConfirm(UINavigationBar* bar) {
    if (bar && NFBColorThemeScreenVisible && NFBAccentIsActive()) {
        NFBWhitenConfirmGlyphsIn(bar, bar);
    }
}

%hook UINavigationBar

- (void)didMoveToWindow {
    %orig;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    %orig;
    NFBWhitenNavigationBarConfirm(self);
    // Target topItem.titleView specifically: that IS the logo container, so
    // converting it to a template image here is safe — unlike sweeping any
    // image view, which would flatten avatars into silhouettes. And at layout
    // time the bounds are finally real, which setTitleView: cannot offer.
    UIView* titleView = self.topItem.titleView;
    if (titleView) {
        UIImageView* logo = NFBFindLogoImageView(titleView);
        // Logo-sized only, and tested HERE because bounds are real at layout
        // time. Without this guard the search screen's title view qualified:
        // its first image view is the search pill's stretchable BACKGROUND,
        // which then got template-converted and painted with the accent.
        if (logo && logo.bounds.size.width > 0 && logo.bounds.size.width < 60) {
            NFBTopBarLogoView = logo;
            NFBRegisterLogoView(logo);
            if (NFBAccentPending) {
            }
            NFBApplyLogoTint(logo);
        }
    }
    NFBRetintTemplateLogos(self);
}

%end

// Safety net for containers not known by name. For a few seconds after any
// accent change, every controller that appears re-applies the accent to the
// chrome that is now on screen — which is exactly the moment of return from
// the settings screen. Outside that window this costs a single float compare.
%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!NFBAccentPending) {
        return;
    }
    UIColor* accent = CurrentAccentColor();
    BOOL reachedChrome = NO;
    for (id scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:objc_getClass("UIWindowScene")]) {
            continue;
        }
        for (UIWindow* w in [scene windows]) {
            NFBSweepTopBarLogos(w);
            NFBSweepNativeTabBars(w, accent);
            if (!reachedChrome && NFBViewTreeHasTabBar(w)) {
                reachedChrome = YES;
            }
            [w setNeedsLayout];
        }
    }
    NFBReapplyTabBarAccent();
    // Only a tab bar's presence proves the timeline is back; until then the
    // flag stays up and every appearance retries.
    if (reachedChrome) {
        NFBAccentPending = NO;
    }
}

%end

// Twitter BAKES the tab icon's colour into the image itself
// (tfn_vectorImageNamed:...fillColor:, and addDynamicColorInfo registers it for
// the manager's re-bake — the binary even carries _tae_resetColor_tabBarItemColor).
// A baked image ignores tintColor and UITabBarAppearance, which is why every
// repaint the tweak pushed only showed up on the next re-bake: a tab change. Templating
// the images as they are installed flips them to tint-driven — the appearance
// patcher and the live tint updates then control them instantly, both directions.
%hook UITabBarItem

- (id)initWithTitle:(NSString*)title image:(UIImage*)image tag:(NSInteger)tag {
    if (image && [BHTSettings boolForKey:@"tab_bar_theming"] &&
        image.renderingMode != UIImageRenderingModeAlwaysTemplate) {
        image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }
    return %orig;
}

- (void)setImage:(UIImage*)image {
    if (image && [BHTSettings boolForKey:@"tab_bar_theming"] &&
        image.renderingMode != UIImageRenderingModeAlwaysTemplate) {
        image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }
    if (NFBAccentPending && image) {
    }
    %orig(image);
}

- (void)setSelectedImage:(UIImage*)image {
    if (image && [BHTSettings boolForKey:@"tab_bar_theming"] &&
        image.renderingMode != UIImageRenderingModeAlwaysTemplate) {
        image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }
    %orig(image);
}

// iOS 13+ lets an appearance be attached to the ITEM itself, and item-level
// overrides bar-level — if Twitter or UIKit's UITab bridging uses this path,
// the bar-level patcher never sees it. Patch here too.
- (void)setStandardAppearance:(UITabBarAppearance*)appearance {
    UITabBarAppearance* patched = NFBPatchedTabBarAppearance(appearance);
    if (NFBAccentPending) {
    }
    %orig(patched);
}

- (void)setScrollEdgeAppearance:(UITabBarAppearance*)appearance {
    UITabBarAppearance* patched = NFBPatchedTabBarAppearance(appearance);
    if (NFBAccentPending) {
    }
    %orig(patched);
}

%end
