// Twitter's own Liquid Glass tab bar, drawn in three rows (resting, seen through the lens, carried
// by the lens). Selected tab colors the lens rows; Tab labels names the tabs on a taller bar with a
// matching bottom reserve and pill; Always visible keeps it up; Hide bottom fade clears the fade
// under it.

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

// Twitter's bar is 62 pt; Tab labels makes it 72 pt, where the glyph keeps Twitter's 24 pt and
// rises 9 pt over an 11 pt name. A bar under 70 pt fits a 10 pt name under a glyph risen 8 pt.
static const CGFloat kPFBGlassExtraHeight = 10.0;

typedef struct {
    CGFloat lift;
    CGFloat labelTopFromBottom;
    CGFloat labelHeight;
    CGFloat fontSize;
} PFBGlassMetrics;

static PFBGlassMetrics PFBGlassMetricsForHeight(CGFloat height) {
    if (height >= 70.0) {
        return (PFBGlassMetrics){9.0, 28.0, 14.0, 11.0};
    }
    return (PFBGlassMetrics){8.0, 21.0, 12.0, 10.0};
}

static const void* kPFBGlassLabelKey = &kPFBGlassLabelKey;
static const void* kPFBGlassLiftKey = &kPFBGlassLiftKey;
static const void* kPFBGlassTintKey = &kPFBGlassTintKey;
static const void* kPFBGlassOwnTintKey = &kPFBGlassOwnTintKey;
static const void* kPFBGlassCollapseKey = &kPFBGlassCollapseKey;

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

// How far the bar has collapsed into its round button, from 0 shown in full to 1 collapsed,
// as last read from its platter.
static CGFloat PFBGlassCollapseOf(UIView* bar) {
    NSNumber* collapse = bar ? objc_getAssociatedObject(bar, kPFBGlassCollapseKey) : nil;
    return collapse ? collapse.doubleValue : 0.0;
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
// selected black and the accent alike. As the bar collapses, the name fades and the glyph
// comes back to its own place, so the round button shows Twitter's own tab.
static void PFBGlassNameTab(UIView* item, UIView* holder, UIImageView* glyph, NSString* name, CGFloat collapse) {
    UILabel* label = objc_getAssociatedObject(item, kPFBGlassLabelKey);
    BOOL wanted = name.length > 0 && [PFBSettings boolForKey:@"restore_tab_labels"];
    if (!wanted) {
        if (label) {
            [label removeFromSuperview];
            objc_setAssociatedObject(item, kPFBGlassLabelKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        PFBGlassLift(holder, 0.0);
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
    CGFloat alpha = 1.0 - collapse;
    if (fabs(label.alpha - alpha) > 0.001) {
        label.alpha = alpha;
    }
    PFBGlassLift(holder, metrics.lift * alpha);
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
    PFBGlassNameTab(item, holder, glyph, name, PFBGlassCollapseOf(bar));
}

// The badges sit over the glyphs, so they rise with them and come down as the bar collapses.
static void PFBGlassLiftBadges(UIView* bar) {
    PFBGlassFindClasses();
    CGFloat lift = [PFBSettings boolForKey:@"restore_tab_labels"]
                       ? PFBGlassMetricsForHeight(CGRectGetHeight(bar.bounds)).lift * (1.0 - PFBGlassCollapseOf(bar))
                       : 0.0;
    PFBWalkAllSubviews(bar, 4, ^(UIView* view) {
      if (gPFBGlassBadgesClass && [view isKindOfClass:gPFBGlassBadgesClass]) {
          PFBGlassLift(view, lift);
      }
    });
}

// The tabs of the bar Twitter draws, which Twitter's own editor sets, logged once per new set.
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
    PFBCompatMeasure(@"customize tabs",
                     [NSString stringWithFormat:@"glass bar [%@]", [shown componentsJoinedByString:@", "]], 6);
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

// MARK: - Bottom chrome reserve

// XNavigation keeps the bar's bottom reserve as a static: the margin under the bar plus its
// height, 20 + 62 = 82 pt, read for the lists' bottom inset and the accessory above the bar.
// Tab labels makes the bar taller, so the reserve grows by the same amount.
typedef struct {
    double* reserve;
    double original;
} PFBGlassReserve;

// The reserve and Twitter's own value for it, found by their exported names. reserve is NULL
// until Twitter has set the statics, or when they no longer add up to margin plus bar height.
static PFBGlassReserve PFBGlassChromeReserve(void) {
    static double* reserve;
    static const double* margin;
    static const double* height;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      reserve = (double*)dlsym(RTLD_DEFAULT,
                               "$s11XNavigation13TabBarMetricsO13restingExtent12CoreGraphics7CGFloatVvpZ");
      margin = (const double*)dlsym(RTLD_DEFAULT,
                                    "$s11XNavigation13TabBarMetricsO14barBottomInset12CoreGraphics7CGFloatVvpZ");
      height = (const double*)dlsym(RTLD_DEFAULT,
                                    "$s11XNavigation13TabBarMetricsO14expandedHeight12CoreGraphics7CGFloatVvpZ");
      if (!reserve || !margin || !height) {
          PFBCompatMeasure(@"bottom reserve", @"Twitter's tab bar metrics not found", 2);
      }
    });
    PFBGlassReserve found = {NULL, 0.0};
    if (!reserve || !margin || !height || *margin <= 0.0 || *height <= 0.0) {
        return found;
    }
    double original = *margin + *height;
    if (*reserve == original || *reserve == original + kPFBGlassExtraHeight) {
        found.reserve = reserve;
        found.original = original;
    }
    return found;
}

// Sets the reserve for the bar's height: Twitter's own with Tab labels off, the bar's extra
// height more with it on. Readers take it on their next layout.
static PFBGlassReserve PFBGlassApplyChromeReserve(void) {
    PFBGlassReserve found = PFBGlassChromeReserve();
    if (!found.reserve) {
        return found;
    }
    PFBCompatReach(PFBCompatPath_glass_bottom_reserve);
    double wanted = found.original + ([PFBSettings boolForKey:@"restore_tab_labels"] ? kPFBGlassExtraHeight : 0.0);
    if (*found.reserve != wanted) {
        *found.reserve = wanted;
        if (wanted != found.original) {
            PFBCOMPAT_ACTION(PFBCompat_restore_tab_labels, @"bottom reserve widened for the taller bar");
        }
    }
    return found;
}

// A stack's collapse engine copies the reserve when it is made, and Twitter copies it into the
// hide travel: an engine made before the reserve changed is brought in line. Only Twitter's own
// values, with or without the extra height, are replaced.
static void PFBGlassSyncEngineReserve(UINavigationController* stack, PFBGlassReserve found) {
    static Class engineClass;
    static ptrdiff_t engineOffset = -1;
    static ptrdiff_t fields[2] = {-1, -1};
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      engineClass = NSClassFromString(@"_TtC11XNavigation14CollapseEngine");
      Ivar engine = class_getInstanceVariable(NSClassFromString(@"XNAVNavigationController"),
                                              "$__lazy_storage_$_collapseEngine");
      Ivar extent = engineClass ? class_getInstanceVariable(engineClass, "bottomChromeExtent") : NULL;
      Ivar travel = engineClass ? class_getInstanceVariable(engineClass, "hiddenBarTravel") : NULL;
      if (engine && extent && travel) {
          engineOffset = ivar_getOffset(engine);
          fields[0] = ivar_getOffset(extent);
          fields[1] = ivar_getOffset(travel);
      }
    });
    if (!found.reserve || engineOffset < 0 || !stack) {
        return;
    }
    void* engine = NULL;
    memcpy(&engine, (const uint8_t*)(__bridge void*)stack + engineOffset, sizeof(engine));
    if (!engine || object_getClass((__bridge id)engine) != engineClass) {
        return;
    }
    double wanted = *found.reserve;
    for (NSUInteger i = 0; i < 2; i++) {
        double* value = (double*)((uint8_t*)engine + fields[i]);
        if (*value != wanted && (*value == found.original || *value == found.original + kPFBGlassExtraHeight)) {
            *value = wanted;
        }
    }
}

// Every glass tab styled again now: a setting changed while the bar is on screen
// otherwise waits for Twitter's next layout of the tabs. The bar takes its new height too.
void PFBRestyleGlassTabBars(void) {
    PFBGlassFindClasses();
    PFBGlassApplyChromeReserve();
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

// MARK: - Collapse

// Twitter's own height for the collapsed bar, its round button; 0 when the metric is missing.
static CGFloat PFBGlassCollapsedHeight(void) {
    static CGFloat height;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      double (*getter)(void) = (double (*)(void))dlsym(
          RTLD_DEFAULT, "$s11XNavigation13TabBarMetricsO15collapsedHeight12CoreGraphics7CGFloatVvgZ");
      height = getter ? getter() : 0.0;
      if (height <= 0.0) {
          PFBCompatMeasure(@"tab labels", @"Twitter's collapsed bar height not found", 4);
      }
    });
    return height;
}

// Twitter collapses the bar by shrinking its platter frame by frame, from the bar's height to
// the round button's. Each step sets how far the names have faded and the glyphs come down.
static void PFBGlassFollowCollapse(UIView* platter, CGFloat height) {
    UIView* bar = platter.superview.superview;
    if (!gPFBGlassBarClass || ![bar isKindOfClass:gPFBGlassBarClass] ||
        ![PFBSettings boolForKey:@"restore_tab_labels"]) {
        return;
    }
    CGFloat full = CGRectGetHeight(bar.bounds);
    CGFloat collapsed = PFBGlassCollapsedHeight();
    if (collapsed <= 0.0 || full <= collapsed) {
        return;
    }
    CGFloat collapse = MIN(1.0, MAX(0.0, (full - height) / (full - collapsed)));
    CGFloat previous = PFBGlassCollapseOf(bar);
    if (collapse == previous || (fabs(collapse - previous) < 0.02 && collapse > 0.0 && collapse < 1.0)) {
        return;
    }
    objc_setAssociatedObject(bar, kPFBGlassCollapseKey, collapse > 0.0 ? @(collapse) : nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    PFBGlassLiftBadges(bar);
    PFBWalkAllSubviews(bar, 5, ^(UIView* inner) {
      if ([inner isKindOfClass:gPFBGlassItemClass]) {
          PFBGlassStyleTab(inner);
      }
    });
    if (collapse == 1.0) {
        PFBCOMPAT_ACTION(PFBCompat_restore_tab_labels, @"names faded in the collapsed bar");
    }
}

// MARK: - Pill

// Twitter builds the bar's pill once, from its metrics: 54 pt high, the 62 pt bar less 4 pt above
// and below. With Tab labels on at launch, the pill keeps those margins in the 72 pt bar.
static void PFBGlassSizePillForLabels(void) {
    double* (*heightAt)(void) = (double* (*)(void))dlsym(
        RTLD_DEFAULT, "$s11XNavigation13TabBarMetricsO10pillHeight12CoreGraphics7CGFloatVvau");
    CGSize* (*sizeAt)(void) =
        (CGSize* (*)(void))dlsym(RTLD_DEFAULT, "$s11XNavigation13TabBarMetricsO8pillSizeSo6CGSizeVvau");
    double (*inset)(void) = (double (*)(void))dlsym(
        RTLD_DEFAULT, "$s11XNavigation13TabBarMetricsO13pillRestInset12CoreGraphics7CGFloatVvgZ");
    double (*barHeight)(void) = (double (*)(void))dlsym(
        RTLD_DEFAULT, "$s11XNavigation13TabBarMetricsO14expandedHeight12CoreGraphics7CGFloatVvgZ");
    double* height = heightAt ? heightAt() : NULL;
    CGSize* size = sizeAt ? sizeAt() : NULL;
    if (!height || !size || !inset || !barHeight) {
        PFBCompatMeasure(@"tab labels", @"Twitter's pill metrics not found", 4);
        return;
    }
    double own = barHeight() - 2.0 * inset();
    if (*height != own || size->height != own) {
        PFBCompatMeasure(@"tab labels",
                         [NSString stringWithFormat:@"pill left as Twitter set it: %.0f pt, %.0fx%.0f, bar %.0f pt",
                                                    *height, size->width, size->height, barHeight()],
                         4);
        return;
    }
    PFBCompatReach(PFBCompatPath_glass_pill);
    if (![PFBSettings boolForKey:@"restore_tab_labels"]) {
        return;
    }
    *height = own + kPFBGlassExtraHeight;
    size->height = own + kPFBGlassExtraHeight;
    PFBCompatMeasure(@"tab labels", [NSString stringWithFormat:@"pill %.0f pt high, Twitter's %.0f", *height, own], 4);
}

void PFBGlassTabBarStart(void) {
    if (PFBNativeGlassAsked()) {
        PFBGlassSizePillForLabels();
    }
}

// MARK: - Bottom fade

// Twitter's edge treatment fades a list into white under the tab bar with a blur band, a color
// band (scrim) or a mask that fades the list itself. Hide bottom fade hides the bands in the lower
// half of the screen and makes the mask opaque there; the top stays Twitter's.
static const void* kPFBGlassFadeHiddenKey = &kPFBGlassFadeHiddenKey;
static const void* kPFBGlassFadeMaskKey = &kPFBGlassFadeMaskKey;
static const void* kPFBGlassFadeColorsKey = &kPFBGlassFadeColorsKey;

static Class gPFBGlassBlurClass;
static Class gPFBGlassScrimClass;
static Class gPFBGlassFadeMaskClass;
static Ivar gPFBGlassFadeMaskIvar;
static Ivar gPFBGlassMaskLayerIvar;
// Set while the mask is written here, so the hooks below tell it from Twitter's own writes.
static BOOL gPFBGlassWritingMask;

static void PFBGlassFindFadeParts(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      gPFBGlassBlurClass = NSClassFromString(@"XDSBlur");
      gPFBGlassScrimClass = NSClassFromString(@"_TtC13XDesignSystem18ScrollEdgeFadeView");
      gPFBGlassFadeMaskClass = NSClassFromString(@"_TtC13XDesignSystem18ScrollEdgeFadeMask");
      Class treatment = NSClassFromString(@"_TtC13XDesignSystem19ScrollEdgeTreatment");
      gPFBGlassFadeMaskIvar = treatment ? class_getInstanceVariable(treatment, "fadeMask") : NULL;
      gPFBGlassMaskLayerIvar =
          gPFBGlassFadeMaskClass ? class_getInstanceVariable(gPFBGlassFadeMaskClass, "gradientLayer") : NULL;
    });
}

// The gradient the treatment masks its list with, installed or not.
static CAGradientLayer* PFBGlassFadeMaskLayer(UIView* treatment) {
    if (!gPFBGlassFadeMaskIvar || !gPFBGlassMaskLayerIvar) {
        return nil;
    }
    id mask = object_getIvar(treatment, gPFBGlassFadeMaskIvar);
    if (![mask isKindOfClass:gPFBGlassFadeMaskClass]) {
        return nil;
    }
    id layer = object_getIvar(mask, gPFBGlassMaskLayerIvar);
    return [layer isKindOfClass:[CAGradientLayer class]] ? layer : nil;
}

// True when the mask is set on the list under the treatment or on one beside it.
static BOOL PFBGlassMaskInstalled(UIView* treatment, CALayer* mask) {
    UIView* parent = treatment.superview;
    if (parent.layer.mask == mask) {
        return YES;
    }
    for (UIView* sibling in parent.subviews) {
        if (sibling.layer.mask == mask) {
            return YES;
        }
    }
    return NO;
}

// A stop's place down the layer, from 0 at its top to 1 at its bottom.
static CGFloat PFBGlassStopDepth(CAGradientLayer* layer, NSUInteger index, NSUInteger count) {
    NSArray<NSNumber*>* locations = layer.locations;
    CGFloat location = locations.count == count ? locations[index].doubleValue
                                                : (count > 1 ? (CGFloat)index / (CGFloat)(count - 1) : 0.0);
    return layer.startPoint.y + location * (layer.endPoint.y - layer.startPoint.y);
}

// The mask's colors with the stops of its lower half made opaque; nil when none fades there.
static NSArray* PFBGlassOpenedMaskColors(CAGradientLayer* layer, NSArray* colors) {
    NSMutableArray* opened = nil;
    for (NSUInteger i = 0; i < colors.count; i++) {
        id object = colors[i];
        if ([object isKindOfClass:[UIColor class]] || CFGetTypeID((__bridge CFTypeRef)object) != CGColorGetTypeID()) {
            continue;
        }
        CGColorRef color = (__bridge CGColorRef)object;
        if (CGColorGetAlpha(color) >= 1.0 || PFBGlassStopDepth(layer, i, colors.count) <= 0.5) {
            continue;
        }
        CGColorRef opaque = CGColorCreateCopyWithAlpha(color, 1.0);
        if (!opaque) {
            continue;
        }
        if (!opened) {
            opened = [colors mutableCopy];
        }
        opened[i] = (__bridge_transfer id)opaque;
    }
    return opened;
}

// Writes the mask the option asks for: Twitter's colors, with their lower half opaque while on.
// YES when the lower half fades in Twitter's colors.
static BOOL PFBGlassWriteMask(CAGradientLayer* mask) {
    NSArray* theirs = objc_getAssociatedObject(mask, kPFBGlassFadeColorsKey);
    NSArray* opened = PFBGlassOpenedMaskColors(mask, theirs);
    BOOL fades = opened != nil;
    if (![PFBSettings boolForKey:@"hide_bottom_fade"]) {
        opened = nil;
    }
    NSArray* wanted = opened ?: theirs;
    if (wanted && ![mask.colors isEqual:wanted]) {
        gPFBGlassWritingMask = YES;
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        mask.colors = wanted;
        [CATransaction commit];
        gPFBGlassWritingMask = NO;
    }
    if (opened) {
        PFBCOMPAT_ACTION(PFBCompat_hide_bottom_fade, @"fade mask under the tab bar opened");
    }
    return fades;
}

// The blur and color bands in the lower half of the screen, hidden with the option on and given
// back with it off. Each one found is described in parts.
static NSUInteger PFBGlassHideBottomBands(UIView* treatment, BOOL hide, NSMutableArray<NSString*>* parts) {
    __block NSUInteger found = 0;
    CGFloat middle = CGRectGetHeight(treatment.window.bounds) / 2.0;
    PFBWalkAllSubviews(treatment, 2, ^(UIView* band) {
      BOOL blur = gPFBGlassBlurClass && [band isKindOfClass:gPFBGlassBlurClass];
      BOOL scrim = gPFBGlassScrimClass && [band isKindOfClass:gPFBGlassScrimClass];
      CGRect frame = [band convertRect:band.bounds toView:nil];
      if (band == treatment || (!blur && !scrim) || CGRectGetMidY(frame) <= middle) {
          return;
      }
      found++;
      BOOL ours = objc_getAssociatedObject(band, kPFBGlassFadeHiddenKey) != nil;
      if (hide && !band.hidden) {
          band.hidden = YES;
          objc_setAssociatedObject(band, kPFBGlassFadeHiddenKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
      } else if (!hide && ours) {
          band.hidden = NO;
          objc_setAssociatedObject(band, kPFBGlassFadeHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
      }
      [parts addObject:[NSString stringWithFormat:@"%@ %.0f,%.0f %.0fx%.0f alpha %.2f", blur ? @"blur" : @"scrim",
                                                  frame.origin.x, frame.origin.y, frame.size.width,
                                                  frame.size.height, band.alpha]];
    });
    return found;
}

// The mask's stops as depth:alpha, from Twitter's own colors.
static NSString* PFBGlassMaskStopsText(CAGradientLayer* mask) {
    NSArray* theirs = objc_getAssociatedObject(mask, kPFBGlassFadeColorsKey);
    NSMutableArray<NSString*>* stops = [NSMutableArray array];
    for (NSUInteger i = 0; i < theirs.count && i < 12; i++) {
        id object = theirs[i];
        BOOL color = ![object isKindOfClass:[UIColor class]] &&
                     CFGetTypeID((__bridge CFTypeRef)object) == CGColorGetTypeID();
        [stops addObject:[NSString stringWithFormat:@"%.2f:%.2f", PFBGlassStopDepth(mask, i, theirs.count),
                                                    color ? CGColorGetAlpha((__bridge CGColorRef)object) : -1.0]];
    }
    return stops.count ? [stops componentsJoinedByString:@" "] : @"none";
}

static void PFBGlassApplyBottomFade(UIView* treatment) {
    PFBGlassFindFadeParts();
    if (!treatment.window) {
        return;
    }
    BOOL hide = [PFBSettings boolForKey:@"hide_bottom_fade"];
    NSMutableArray<NSString*>* parts = [NSMutableArray array];
    NSUInteger bands = PFBGlassHideBottomBands(treatment, hide, parts);
    CAGradientLayer* mask = PFBGlassFadeMaskLayer(treatment);
    BOOL masked = mask && PFBGlassMaskInstalled(treatment, mask);
    BOOL maskFades = NO;
    if (masked) {
        if (!objc_getAssociatedObject(mask, kPFBGlassFadeMaskKey)) {
            objc_setAssociatedObject(mask, kPFBGlassFadeMaskKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(mask, kPFBGlassFadeColorsKey, mask.colors, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        maskFades = PFBGlassWriteMask(mask);
    }
    if (bands || maskFades) {
        PFBCompatReach(PFBCompatPath_bottom_fade);
        if (hide && bands) {
            PFBCOMPAT_ACTION(PFBCompat_hide_bottom_fade, @"fade under the tab bar hidden");
        } else if (!hide) {
            PFBCOMPAT_OBSERVE(PFBCompat_hide_bottom_fade, @"fade under the tab bar found");
        }
    }
    // The edge's parts, until the topic is full.
    static BOOL measured;
    if (!measured) {
        NSString* maskText = !mask ? @"none" : (masked ? PFBGlassMaskStopsText(mask) : @"not set on a list");
        measured = !PFBCompatMeasure(@"bottom fade",
                                     [NSString stringWithFormat:@"over %@: bands in the lower half [%@] · mask %@",
                                                                NSStringFromClass([treatment.superview class]),
                                                                [parts componentsJoinedByString:@", "], maskText],
                                     8);
    }
}

// A change to Hide bottom fade reaches the lists on screen at once.
void PFBGlassRefreshBottomFades(void) {
    Class treatmentClass = NSClassFromString(@"_TtC13XDesignSystem19ScrollEdgeTreatment");
    if (!treatmentClass) {
        return;
    }
    PFBGlassForEachWindow(^(UIWindow* window) {
      PFBWalkAllSubviews(window, 60, ^(UIView* view) {
        if ([view isKindOfClass:treatmentClass]) {
            PFBGlassApplyBottomFade(view);
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
// for a manual mode). The bar style at 8 reads 2 while none is applied.
static ptrdiff_t PFBGlassAppliedConfigurationOffset(void) {
    static ptrdiff_t offset = -1;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      Class stack = NSClassFromString(@"XNAVNavigationController");
      Ivar applied = stack ? class_getInstanceVariable(stack, "appliedConfiguration") : NULL;
      Ivar next = stack ? class_getInstanceVariable(stack, "chromeFrozenScreen") : NULL;
      ptrdiff_t size = applied && next ? ivar_getOffset(next) - ivar_getOffset(applied) : 0;
      // 40 bytes through 12.38.1; 12.39 adds a bar style after the configuration, which
      // leaves the bytes the patch writes in place.
      if (size == 40 || size == 48) {
          offset = ivar_getOffset(applied);
      }
      PFBCompatMeasure(@"always visible",
                       offset < 0 ? [NSString stringWithFormat:@"patch off: applied configuration is %td bytes", size]
                       : PFBGlassConfigLayoutVerified()
                           ? [NSString stringWithFormat:@"patch ready: applied configuration is %td bytes", size]
                           : @"patch off: the configuration bytes moved",
                       2);
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
    @try {
        PFBGlassSyncEngineReserve((UINavigationController*)self, PFBGlassApplyChromeReserve());
    } @catch (__unused id exception) {
    }
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

// Twitter's tab editor previews the bar: with Tab labels, as tall as the real one and with its names.
%hook _TtC11XNavigation19TabBarEditorBarView

- (CGSize)intrinsicContentSize {
    CGSize size = %orig;
    if (size.height > 0.0 && [PFBSettings boolForKey:@"restore_tab_labels"]) {
        size.height += kPFBGlassExtraHeight;
    }
    return size;
}

%end

%hook _TtC11XNavigation20TabBarEditorItemView

- (void)layoutSubviews {
    %orig;
    @try {
        UIView* item = (UIView*)self;
        UIView* holder = nil;
        UIImageView* glyph = PFBGlassGlyph(item, &holder);
        if (glyph && holder) {
            PFBGlassNameTab(item, holder, glyph, PFBGlassTabName(item), 0.0);
        }
    } @catch (__unused id exception) {
    }
}

%end

// The bar's platter, shrunk by Twitter frame by frame as the bar collapses.
%hook XDSGlass

- (void)setBounds:(CGRect)bounds {
    %orig;
    @try {
        PFBGlassFindClasses();
        PFBGlassFollowCollapse((UIView*)self, CGRectGetHeight(bounds));
    } @catch (__unused id exception) {
    }
}

%end

%hook _TtC13XDesignSystem19ScrollEdgeTreatment

- (void)layoutSubviews {
    %orig;
    @try {
        PFBGlassApplyBottomFade((UIView*)self);
    } @catch (__unused id exception) {
    }
}

%end

// Twitter rewrites its fade mask as the list scrolls: its colors are kept as Twitter's own, and
// the lower half opened again with the option on.
%hook CAGradientLayer

- (void)setColors:(NSArray*)colors {
    if (gPFBGlassWritingMask || ![NSThread isMainThread] || !objc_getAssociatedObject(self, kPFBGlassFadeMaskKey)) {
        %orig;
        return;
    }
    objc_setAssociatedObject(self, kPFBGlassFadeColorsKey, colors, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSArray* opened = [PFBSettings boolForKey:@"hide_bottom_fade"]
                          ? PFBGlassOpenedMaskColors((CAGradientLayer*)self, colors)
                          : nil;
    %orig(opened ?: colors);
}

- (void)setLocations:(NSArray*)locations {
    %orig;
    if (!gPFBGlassWritingMask && [NSThread isMainThread] && objc_getAssociatedObject(self, kPFBGlassFadeMaskKey)) {
        PFBGlassWriteMask((CAGradientLayer*)self);
    }
}

%end
