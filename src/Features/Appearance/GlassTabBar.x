// Twitter's own Liquid Glass tab bar, drawn in three rows: resting, the row seen through the
// lens over the selected tab, and the row the lens carries while dragged. Selected tab colors
// the lens rows; Tab labels names the tabs on a taller bar; Always visible keeps it from collapsing.

#import "Support/HookHelpers.h"

@interface _TtCC11XNavigation14CollapseEngine14ScrollObserver : NSObject
- (void)handlePan:(UIPanGestureRecognizer*)recognizer;
@end

static Class gPFBGlassBarClass;
static Class gPFBGlassItemClass;
static Class gPFBGlassPortalClass;
static Class gPFBGlassCarriedClass;
static Class gPFBGlassBadgesClass;

static void PFBGlassFindClasses(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      gPFBGlassBarClass = NSClassFromString(@"_TtC11XNavigation10TabBarView");
      gPFBGlassItemClass = NSClassFromString(@"_TtC11XNavigation14TabBarItemView");
      gPFBGlassPortalClass = NSClassFromString(@"_TtC11XNavigation16TabBarPortalView");
      gPFBGlassCarriedClass = NSClassFromString(@"_TtC11XNavigation16TabBarCarriedRow");
      gPFBGlassBadgesClass = NSClassFromString(@"_TtC11XNavigation18TabBarBadgeOverlay");
    });
}

// Twitter's bar is 62 pt; Tab labels makes it 72 pt, where the glyph grows from 24 to 28 pt
// and rises 9 pt over an 11 pt name. A bar under 70 pt fits a 10 pt name under a glyph risen 8 pt.
static const CGFloat kPFBGlassExtraHeight = 10.0;

typedef struct {
    CGFloat lift;
    CGFloat labelTopFromBottom;
    CGFloat labelHeight;
    CGFloat fontSize;
    CGFloat glyphScale;
} PFBGlassMetrics;

static PFBGlassMetrics PFBGlassMetricsForHeight(CGFloat height) {
    if (height >= 70.0) {
        return (PFBGlassMetrics){9.0, 28.0, 14.0, 11.0, 28.0 / 24.0};
    }
    return (PFBGlassMetrics){8.0, 21.0, 12.0, 10.0, 1.0};
}

static const void* kPFBGlassLabelKey = &kPFBGlassLabelKey;
static const void* kPFBGlassLiftKey = &kPFBGlassLiftKey;
static const void* kPFBGlassTintKey = &kPFBGlassTintKey;
static const void* kPFBGlassOwnTintKey = &kPFBGlassOwnTintKey;
static const void* kPFBGlassGlyphSizeKey = &kPFBGlassGlyphSizeKey;
static const void* kPFBGlassOwnGlyphSizeKey = &kPFBGlassOwnGlyphSizeKey;

static BOOL PFBGlassIsLensRow(UIView* view) {
    return (gPFBGlassPortalClass && [view isKindOfClass:gPFBGlassPortalClass]) ||
           (gPFBGlassCarriedClass && [view isKindOfClass:gPFBGlassCarriedClass]);
}

// The bar a view sits in, and whether a lens row lies on the way up.
static UIView* PFBGlassBarOf(UIView* view, BOOL* lens) {
    BOOL inLens = NO;
    UIView* node = view.superview;
    for (NSInteger depth = 0; node && depth < 5; depth++, node = node.superview) {
        inLens = inLens || PFBGlassIsLensRow(node);
        if (gPFBGlassBarClass && [node isKindOfClass:gPFBGlassBarClass]) {
            if (lens) {
                *lens = inLens;
            }
            return node;
        }
    }
    return nil;
}

// A row's tabs from left to right.
static NSArray<UIView*>* PFBGlassRowItems(UIView* row) {
    NSMutableArray<UIView*>* items = [NSMutableArray array];
    for (UIView* sub in row.subviews) {
        if ([sub isKindOfClass:gPFBGlassItemClass]) {
            [items addObject:sub];
        }
    }
    [items sortUsingComparator:^NSComparisonResult(UIView* a, UIView* b) {
      CGFloat ax = CGRectGetMinX(a.frame);
      CGFloat bx = CGRectGetMinX(b.frame);
      return ax < bx ? NSOrderedAscending : (ax > bx ? NSOrderedDescending : NSOrderedSame);
    }];
    return items;
}

// A tab's VoiceOver label, without what may follow its name after a comma.
static NSString* PFBGlassTabName(UIView* item) {
    NSString* label = [item.accessibilityLabel componentsSeparatedByString:@","].firstObject;
    return [label stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] ?: @"";
}

// The tabs' names in order, from the resting row: the one Twitter names for VoiceOver.
static NSArray<NSString*>* PFBGlassTabNames(UIView* bar) {
    __block NSArray<NSString*>* names = nil;
    PFBWalkAllSubviews(bar, 3, ^(UIView* view) {
      if (names || view == bar || [view isKindOfClass:gPFBGlassItemClass]) {
          return;
      }
      BOOL above = NO;
      PFBGlassBarOf(view, &above);
      NSArray<UIView*>* items = above || PFBGlassIsLensRow(view) ? nil : PFBGlassRowItems(view);
      if (!items.count) {
          return;
      }
      NSMutableArray<NSString*>* found = [NSMutableArray array];
      for (UIView* item in items) {
          [found addObject:PFBGlassTabName(item)];
      }
      names = found;
    });
    return names ?: @[];
}

// The tab's glyph and the holder it sits in, which fills the tab.
static UIImageView* PFBGlassGlyph(UIView* item, UIView** holder) {
    for (UIView* sub in item.subviews) {
        for (UIView* inner in sub.subviews) {
            if ([inner isKindOfClass:[UIImageView class]]) {
                if (holder) {
                    *holder = sub;
                }
                return (UIImageView*)inner;
            }
        }
    }
    return nil;
}

// Raises a view's content by shifting its bounds: whatever lays out its subviews, frames
// and transforms included, the content moves with it. A lift of 0 puts it back.
static void PFBGlassLift(UIView* view, CGFloat lift) {
    if (!view) {
        return;
    }
    BOOL wasLifted = objc_getAssociatedObject(view, kPFBGlassLiftKey) != nil;
    if (lift <= 0.0 && !wasLifted) {
        return;
    }
    CGRect bounds = view.bounds;
    if (bounds.origin.y != lift) {
        bounds.origin.y = lift;
        view.bounds = bounds;
    }
    objc_setAssociatedObject(view, kPFBGlassLiftKey, lift > 0.0 ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// Grows the glyph inside its own box, whose image Twitter scales to fit. Each layout of the
// tab writes Twitter's size again; that size is kept, so the glyph never grows twice.
static void PFBGlassSizeGlyph(UIImageView* glyph, CGFloat scale) {
    NSValue* applied = objc_getAssociatedObject(glyph, kPFBGlassGlyphSizeKey);
    if (scale == 1.0 && !applied) {
        return;
    }
    CGSize current = glyph.bounds.size;
    NSValue* own = objc_getAssociatedObject(glyph, kPFBGlassOwnGlyphSizeKey);
    // A size other than the one written here is Twitter's latest.
    CGSize base = applied && own && CGSizeEqualToSize(current, applied.CGSizeValue) ? own.CGSizeValue : current;
    CGSize wanted = CGSizeMake(base.width * scale, base.height * scale);
    if (CGSizeEqualToSize(current, wanted) && (scale != 1.0) == (applied != nil)) {
        return;
    }
    if (!CGSizeEqualToSize(current, wanted)) {
        CGRect bounds = glyph.bounds;
        bounds.size = wanted;
        glyph.bounds = bounds;
    }
    BOOL grown = scale != 1.0;
    objc_setAssociatedObject(glyph, kPFBGlassGlyphSizeKey, grown ? [NSValue valueWithCGSize:wanted] : nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(glyph, kPFBGlassOwnGlyphSizeKey, grown ? [NSValue valueWithCGSize:base] : nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// The lens rows take the accent with Selected tab on; the resting row keeps Twitter's gray.
// Twitter's own tint is kept and put back with the option off: the glyph would otherwise
// inherit the window's tint, which carries the accent.
static void PFBGlassTintGlyph(UIImageView* glyph, BOOL lens) {
    BOOL wanted = lens && [PFBSettings boolForKey:@"tab_bar_theming"];
    if (lens) {
        if (wanted) {
            PFBCOMPAT_ACTION(PFBCompat_tab_bar_theming, @"glass tab tinted");
        } else {
            PFBCOMPAT_OBSERVE(PFBCompat_tab_bar_theming, @"glass tab found");
        }
    }
    UIColor* applied = objc_getAssociatedObject(glyph, kPFBGlassTintKey);
    if (wanted) {
        UIColor* accent = PFBBrandAccentColor();
        UIColor* current = glyph.tintColor;
        if (![applied isEqual:accent] || ![current isEqual:accent]) {
            // A tint other than the one written here is Twitter's latest.
            if (!applied || ![current isEqual:applied]) {
                objc_setAssociatedObject(glyph, kPFBGlassOwnTintKey, current, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            glyph.tintColor = accent;
            objc_setAssociatedObject(glyph, kPFBGlassTintKey, accent, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    } else if (applied) {
        glyph.tintColor = objc_getAssociatedObject(glyph, kPFBGlassOwnTintKey);
        objc_setAssociatedObject(glyph, kPFBGlassTintKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(glyph, kPFBGlassOwnTintKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static UIFont* PFBGlassLabelFont(CGFloat size) {
    SEL twitterFont = NSSelectorFromString(@"xdsDeprecated_customFontOfSize:weight:scalesWithDynamicType:");
    UIFont* font = nil;
    if ([UIFont respondsToSelector:twitterFont]) {
        font = ((UIFont * (*)(id, SEL, CGFloat, NSInteger, BOOL))objc_msgSend)([UIFont class], twitterFont, size, 1, NO);
    }
    return [font isKindOfClass:[UIFont class]] ? font : [UIFont systemFontOfSize:size weight:UIFontWeightMedium];
}

// The name under the glyph, in the glyph's own color so it follows Twitter's gray, the
// selected black and the accent alike.
static void PFBGlassNameTab(UIView* item, UIView* holder, UIImageView* glyph, NSString* name) {
    UILabel* label = objc_getAssociatedObject(item, kPFBGlassLabelKey);
    BOOL wanted = name.length > 0 && [PFBSettings boolForKey:@"restore_tab_labels"];
    if (!wanted) {
        if (label) {
            [label removeFromSuperview];
            objc_setAssociatedObject(item, kPFBGlassLabelKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        PFBGlassLift(holder, 0.0);
        PFBGlassSizeGlyph(glyph, 1.0);
        if (name.length) {
            PFBCOMPAT_OBSERVE(PFBCompat_restore_tab_labels, @"glass tab laid out");
        }
        return;
    }
    CGRect bounds = item.bounds;
    PFBGlassMetrics metrics = PFBGlassMetricsForHeight(CGRectGetHeight(bounds));
    if (!label) {
        label = [[UILabel alloc] init];
        label.backgroundColor = [UIColor clearColor];
        label.isAccessibilityElement = NO;
        label.textAlignment = NSTextAlignmentCenter;
        label.adjustsFontSizeToFitWidth = YES;
        label.minimumScaleFactor = 0.8;
        label.userInteractionEnabled = NO;
        objc_setAssociatedObject(item, kPFBGlassLabelKey, label, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [item addSubview:label];
    }
    if (label.font.pointSize != metrics.fontSize) {
        label.font = PFBGlassLabelFont(metrics.fontSize);
    }
    if (![label.text isEqualToString:name]) {
        label.text = name;
    }
    UIColor* color = glyph.tintColor ?: [UIColor labelColor];
    if (![label.textColor isEqual:color]) {
        label.textColor = color;
    }
    CGRect frame = CGRectMake(0.0, CGRectGetMaxY(bounds) - metrics.labelTopFromBottom, CGRectGetWidth(bounds),
                              metrics.labelHeight);
    if (!CGRectEqualToRect(label.frame, frame)) {
        label.frame = frame;
    }
    PFBGlassSizeGlyph(glyph, metrics.glyphScale);
    PFBGlassLift(holder, metrics.lift);
    PFBCOMPAT_ACTION(PFBCompat_restore_tab_labels, @"name drawn under the glass icon");
}

static void PFBGlassStyleTab(UIView* item) {
    PFBGlassFindClasses();
    BOOL lens = NO;
    UIView* bar = PFBGlassBarOf(item, &lens);
    UIView* holder = nil;
    UIImageView* glyph = PFBGlassGlyph(item, &holder);
    if (!bar || !glyph || !holder) {
        return;
    }
    PFBCompatReach(PFBCompatPath_glass_tab_bar);
    PFBGlassTintGlyph(glyph, lens);
    NSArray<UIView*>* row = PFBGlassRowItems(item.superview);
    NSArray<NSString*>* names = PFBGlassTabNames(bar);
    NSUInteger index = [row indexOfObject:item];
    NSString* name = row.count == names.count && index < names.count ? names[index] : nil;
    PFBGlassNameTab(item, holder, glyph, name);
}

// The badges sit over the glyphs, so they rise with them.
static void PFBGlassLiftBadges(UIView* bar) {
    PFBGlassFindClasses();
    CGFloat lift = [PFBSettings boolForKey:@"restore_tab_labels"]
                       ? PFBGlassMetricsForHeight(CGRectGetHeight(bar.bounds)).lift
                       : 0.0;
    PFBWalkAllSubviews(bar, 4, ^(UIView* view) {
      if (gPFBGlassBadgesClass && [view isKindOfClass:gPFBGlassBadgesClass]) {
          PFBGlassLift(view, lift);
      }
    });
}

// Customize tabs will prove itself on the bar Twitter draws: its tabs must be the chosen ones,
// in their order. Nothing drives the glass bar yet, so this only measures the two lists; a match
// is not counted as working, since the tabs would match on their own. Each new set is logged once.
static void PFBGlassCheckChosenTabs(UIView* bar) {
    static NSArray<NSString*>* checked;
    static CFTimeInterval lastLook;
    CFTimeInterval now = CACurrentMediaTime();
    if (now - lastLook < 1.0) {
        return;
    }
    lastLook = now;
    NSArray<NSString*>* shown = PFBGlassTabNames(bar);
    if (!shown.count || [shown isEqualToArray:checked]) {
        return;
    }
    checked = shown;
    PFBCompatReach(PFBCompatPath_glass_tabs);
    NSArray<NSString*>* chosen = [PFBCustomTabBarUtility chosenTabNames];
    PFBCompatMeasure(@"customize tabs",
                     [NSString stringWithFormat:@"glass bar [%@] · chosen [%@] · %@", [shown componentsJoinedByString:@", "],
                                                [chosen componentsJoinedByString:@", "],
                                                [shown isEqualToArray:chosen] ? @"match" : @"differ"],
                     6);
}

static void PFBGlassForEachWindow(void (^block)(UIWindow* window)) {
    for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }
        for (UIWindow* window in ((UIWindowScene*)scene).windows) {
            block(window);
        }
    }
}

// Every glass tab styled again now: a setting changed while the bar is on screen
// otherwise waits for Twitter's next layout of the tabs. The bar takes its new height too.
void PFBRestyleGlassTabBars(void) {
    PFBGlassFindClasses();
    if (!gPFBGlassBarClass) {
        return;
    }
    PFBGlassForEachWindow(^(UIWindow* window) {
      PFBWalkAllSubviews(window, 12, ^(UIView* view) {
        if (![view isKindOfClass:gPFBGlassBarClass]) {
            return;
        }
        [view invalidateIntrinsicContentSize];
        [view.superview setNeedsLayout];
        PFBGlassLiftBadges(view);
        PFBWalkAllSubviews(view, 5, ^(UIView* inner) {
          if ([inner isKindOfClass:gPFBGlassItemClass]) {
              PFBGlassStyleTab(inner);
          }
        });
      });
    });
}

// Twitter keeps its glass tab bar over the settings, which never show the bar under
// the old design. Its whole chrome, compose button included, is hidden meanwhile.
static const void* kPFBGlassChromeHiddenKey = &kPFBGlassChromeHiddenKey;
static BOOL gPFBGlassChromeHidden;

void PFBGlassTabBarHideForSettings(BOOL hidden) {
    static Class chromeClass;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      chromeClass = NSClassFromString(@"_TtC11XNavigation25TabBarChromeContainerView");
    });
    if (!chromeClass || (!hidden && !gPFBGlassChromeHidden)) {
        return;
    }
    gPFBGlassChromeHidden = hidden;
    PFBGlassForEachWindow(^(UIWindow* window) {
      PFBWalkAllSubviews(window, 12, ^(UIView* view) {
        // The outermost chrome view holds the bar and the compose button; the
        // chrome views inside it are left alone.
        if (![view isKindOfClass:chromeClass] || [view.superview isKindOfClass:chromeClass]) {
            return;
        }
        BOOL ours = objc_getAssociatedObject(view, kPFBGlassChromeHiddenKey) != nil;
        if (hidden && !view.hidden) {
            view.hidden = YES;
            objc_setAssociatedObject(view, kPFBGlassChromeHiddenKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            PFBCompatReach(PFBCompatPath_settings_tab_bar);
            PFBCOMPAT_ACTION(PFBCompat_custom_tab_bar, @"glass tab bar hidden in the settings");
        } else if (!hidden && ours) {
            view.hidden = NO;
            objc_setAssociatedObject(view, kPFBGlassChromeHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
      });
    });
}

static BOOL PFBGlassStackHoldsSettings(UINavigationController* stack) {
    Class settings = objc_getClass("T1GenericSettingsViewController");
    for (UIViewController* screen in stack.viewControllers) {
        if (settings && [screen isKindOfClass:settings]) {
            return YES;
        }
    }
    return NO;
}

// MARK: - Always visible

// Confirms the collapse-mode bytes sit where the patch writes, by their fingerprint in Twitter's
// four static configurations. A later build that moves them fails this, so the patch stays off
// rather than writing into the wrong field.
static BOOL PFBGlassConfigLayoutVerified(void) {
    static BOOL verified;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      Class cls = NSClassFromString(@"XNAVConfiguration");
      Ivar ivar = cls ? class_getInstanceVariable(cls, "configuration") : NULL;
      if (!ivar) {
          return;
      }
      ptrdiff_t offset = ivar_getOffset(ivar);
      if (offset <= 0 || (size_t)offset + 16 > class_getInstanceSize(cls)) {
          return;
      }
      // Navigation bar mode at byte 0, tab bar mode at byte 1 (0 in every preset), style word at 8.
      const char* names[] = {"standardConfiguration", "pinnedConfiguration", "hiddenConfiguration",
                             "pinnedTransparentConfiguration"};
      const uint8_t navBar[] = {1, 3, 2, 3};
      const uintptr_t style[] = {0, 0, 0, 1};
      for (NSUInteger i = 0; i < 4; i++) {
          SEL selector = NSSelectorFromString([NSString stringWithUTF8String:names[i]]);
          if (![cls respondsToSelector:selector]) {
              return;
          }
          id configuration = ((id (*)(id, SEL))objc_msgSend)(cls, selector);
          if (![configuration isKindOfClass:cls]) {
              return;
          }
          const uint8_t* bytes = (const uint8_t*)(__bridge void*)configuration + offset;
          uintptr_t word = 0;
          memcpy(&word, bytes + 8, sizeof(word));
          if (bytes[0] != navBar[i] || bytes[1] != 0 || word != style[i]) {
              return;
          }
      }
      verified = YES;
    });
    return verified;
}

// The stack's applied configuration starts with the collapse mode Twitter's engine reads on
// each scroll: the top bar's byte (0 to 3), then the tab bar's (0 pinned, 1 collapses, high bit
// for a manual mode). The bar style at 8 reads 2 while none is applied; 40 bytes in all.
static ptrdiff_t PFBGlassAppliedConfigurationOffset(void) {
    static ptrdiff_t offset = -1;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      Class stack = NSClassFromString(@"XNAVNavigationController");
      Ivar applied = stack ? class_getInstanceVariable(stack, "appliedConfiguration") : NULL;
      Ivar next = stack ? class_getInstanceVariable(stack, "chromeFrozenScreen") : NULL;
      if (applied && next && ivar_getOffset(next) - ivar_getOffset(applied) == 40) {
          offset = ivar_getOffset(applied);
      }
    });
    return offset;
}

// The tab bar's collapse in the stack's engine, from 0 shown to 1 collapsed; -1 when unread.
static double PFBGlassTabBarCollapse(UINavigationController* stack) {
    static Class engineClass;
    static ptrdiff_t engineOffset = -1;
    static ptrdiff_t progressOffset = -1;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      engineClass = NSClassFromString(@"_TtC11XNavigation14CollapseEngine");
      Ivar engine = class_getInstanceVariable(NSClassFromString(@"XNAVNavigationController"),
                                              "$__lazy_storage_$_collapseEngine");
      Ivar progress = engineClass ? class_getInstanceVariable(engineClass, "collapseProgress") : NULL;
      if (engine && progress) {
          engineOffset = ivar_getOffset(engine);
          progressOffset = ivar_getOffset(progress);
      }
    });
    if (engineOffset < 0) {
        return -1.0;
    }
    void* engine = NULL;
    memcpy(&engine, (const uint8_t*)(__bridge void*)stack + engineOffset, sizeof(engine));
    // The engine is made when first needed: until then nothing has collapsed.
    if (!engine) {
        return 0.0;
    }
    if (object_getClass((__bridge id)engine) != engineClass) {
        return -1.0;
    }
    // The progress holds the top bar's value, then the tab bar's.
    double progress[2] = {0.0, 0.0};
    memcpy(progress, (const uint8_t*)engine + progressOffset, sizeof(progress));
    return isfinite(progress[1]) ? progress[1] : -1.0;
}

// How many times the patch has flipped the tab-bar byte, for the probe: a high count while
// Home sits still signals Twitter re-applying its configuration against the patch.
static NSUInteger gPFBGlassPinCount;

NSUInteger PFBGlassAlwaysVisiblePinCount(void) {
    return gPFBGlassPinCount;
}

// Pins the tab bar where Twitter's configuration lets it collapse (Home), the top bar's
// mode untouched. A bar caught collapsed is pinned once back, as the engine stops moving it.
static void PFBGlassPinTabBar(UINavigationController* stack) {
    static Class stackClass;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      stackClass = NSClassFromString(@"XNAVNavigationController");
    });
    ptrdiff_t offset = PFBGlassAppliedConfigurationOffset();
    if (offset < 0 || !stackClass || ![stack isKindOfClass:stackClass] || !PFBGlassConfigLayoutVerified()) {
        return;
    }
    uint8_t* configuration = (uint8_t*)(__bridge void*)stack + offset;
    uintptr_t style = 0;
    memcpy(&style, configuration + 8, sizeof(style));
    if (style == 2 || configuration[0] > 3 || configuration[1] != 1) {
        return;
    }
    if (![PFBSettings boolForKey:@"no_tab_bar_hiding"]) {
        PFBCOMPAT_OBSERVE(PFBCompat_no_tab_bar_hiding, @"glass tab bar set to collapse");
        return;
    }
    double collapse = PFBGlassTabBarCollapse(stack);
    if (collapse < 0.0 || collapse > 0.001) {
        return;
    }
    configuration[1] = 0;
    gPFBGlassPinCount++;
    PFBCOMPAT_ACTION(PFBCompat_no_tab_bar_hiding, @"glass tab bar pinned");
}

// A change to Always visible reaches the bars on screen at once: each glass stack applies its
// configuration again, so turning the option off lets Home's bar collapse without a navigation,
// and turning it on pins it at the next layout.
void PFBGlassRefreshAlwaysVisible(void) {
    Class stackClass = NSClassFromString(@"XNAVNavigationController");
    SEL update = NSSelectorFromString(@"xnav_setNeedsNavigationConfigurationUpdateAnimated:");
    if (!stackClass) {
        return;
    }
    PFBGlassForEachWindow(^(UIWindow* window) {
      NSMutableArray<UIViewController*>* queue = [NSMutableArray array];
      if (window.rootViewController) {
          [queue addObject:window.rootViewController];
      }
      for (NSUInteger i = 0; i < queue.count && i < 200; i++) {
          UIViewController* controller = queue[i];
          if ([controller isKindOfClass:stackClass] && [controller respondsToSelector:update]) {
              ((void (*)(id, SEL, BOOL))objc_msgSend)(controller, update, NO);
          }
          [queue addObjectsFromArray:controller.childViewControllers];
          if (controller.presentedViewController) {
              [queue addObject:controller.presentedViewController];
          }
      }
    });
}

// The settings can be left without their own exit running: a tab switch from a notification
// or a link, or a pop to the stack's root. A screen of Twitter's glass navigation appearing on
// a stack without settings shows the chrome again.
%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    UIViewController* screen = (UIViewController*)self;
    if (gPFBGlassChromeHidden && PFBOnNativeGlassStack(screen) &&
        !PFBGlassStackHoldsSettings(screen.navigationController)) {
        PFBGlassTabBarHideForSettings(NO);
    }
}

%end

// The stack applies a screen's configuration while it lays out, when the screen asked for
// it or its width changed; it is pinned right after.
%hook XNAVNavigationController

- (void)viewWillLayoutSubviews {
    %orig;
    @try {
        PFBGlassPinTabBar((UINavigationController*)self);
    } @catch (__unused id exception) {
    }
}

%end

// A configuration applied without a layout of its stack is pinned before the finger moves.
%hook _TtCC11XNavigation14CollapseEngine14ScrollObserver

- (void)handlePan:(UIPanGestureRecognizer*)recognizer {
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        @try {
            PFBGlassPinTabBar(PFBOwningController(recognizer.view).navigationController);
        } @catch (__unused id exception) {
        }
    }
    %orig;
}

%end

%hook _TtC11XNavigation10TabBarView

// Auto Layout gives the bar this height, and the bar lays its parts out in its bounds.
- (CGSize)intrinsicContentSize {
    CGSize size = %orig;
    if (size.height > 0.0 && [PFBSettings boolForKey:@"restore_tab_labels"]) {
        size.height += kPFBGlassExtraHeight;
    }
    return size;
}

- (void)layoutSubviews {
    %orig;
    @try {
        UIView* bar = (UIView*)self;
        PFBGlassLiftBadges(bar);
        PFBGlassCheckChosenTabs(bar);
    } @catch (__unused id exception) {
    }
}

%end

%hook _TtC11XNavigation14TabBarItemView

- (void)layoutSubviews {
    %orig;
    @try {
        PFBGlassStyleTab((UIView*)self);
    } @catch (__unused id exception) {
    }
}

%end
