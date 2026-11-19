// Twitter's own Liquid Glass tab bar: Selected tab tints the lens rows, Tab labels names the tabs on a taller
// bar, Always visible keeps it up, and Bottom fade gives it 12.42.1's untinted glass over a fade.

#import "Support/HookHelpers.h"
#import "Features/Appearance/ThemeColor/PFBPalette.h"

@interface _TtCC11XNavigation14CollapseEngine14ScrollObserver : NSObject
- (void)handlePan:(UIPanGestureRecognizer*)recognizer;
@end

@interface _TtCC11XNavigation17DisplayLinkDriverP33_DC9744A9B855F36B00902ED7FE8B664F5Proxy : NSObject
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

// The bytes an ivar spans: up to the next ivar of its own class, or to the end of the instance.
static ptrdiff_t PFBGlassIvarSpan(Class cls, Ivar ivar) {
    unsigned int count = 0;
    Ivar* list = class_copyIvarList(cls, &count);
    ptrdiff_t offset = ivar_getOffset(ivar);
    ptrdiff_t next = (ptrdiff_t)class_getInstanceSize(cls);
    for (unsigned int i = 0; i < count; i++) {
        ptrdiff_t other = ivar_getOffset(list[i]);
        if (other > offset && other < next) {
            next = other;
        }
    }
    free(list);
    return next - offset;
}

// A stack's collapse engine keeps the bar's band (extent first, then a byte at 24 that is 0 once
// set) and copies the extent into the hide travel: an engine made before the reserve changed is
// brought in line. Only Twitter's own values, with or without the extra height, are replaced.
static void PFBGlassSyncEngineReserve(UINavigationController* stack, PFBGlassReserve found) {
    static Class engineClass;
    static ptrdiff_t engineOffset = -1;
    static ptrdiff_t bandOffset = -1;
    static ptrdiff_t travelOffset = -1;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      engineClass = NSClassFromString(@"_TtC11XNavigation14CollapseEngine");
      Ivar engine = class_getInstanceVariable(NSClassFromString(@"XNAVNavigationController"), "collapseEngine");
      Ivar band = engineClass ? class_getInstanceVariable(engineClass, "bottomChromeBand") : NULL;
      Ivar travel = engineClass ? class_getInstanceVariable(engineClass, "hiddenBarTravel") : NULL;
      // Extent, slide and opacity, then the byte, in the 32 bytes measured before the next field.
      if (engine && band && travel && PFBGlassIvarSpan(engineClass, band) == 32) {
          engineOffset = ivar_getOffset(engine);
          bandOffset = ivar_getOffset(band);
          travelOffset = ivar_getOffset(travel);
      } else if (engineClass) {
          PFBCompatMeasure(@"bottom reserve", @"collapse engine band not found", 2);
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
    uint8_t* bytes = (uint8_t*)engine;
    double* values[2] = {bytes[bandOffset + 24] == 0 ? (double*)(bytes + bandOffset) : NULL,
                         (double*)(bytes + travelOffset)};
    double wanted = *found.reserve;
    for (NSUInteger i = 0; i < 2; i++) {
        double* value = values[i];
        if (value && *value != wanted &&
            (*value == found.original || *value == found.original + kPFBGlassExtraHeight)) {
            *value = wanted;
        }
    }
}

// Every glass tab styled again now: a setting changed while the bar is on screen
// otherwise waits for Twitter's next layout of the tabs. The bar is laid out again for its height.
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

// Twitter keeps its glass tab bar over the settings; its whole chrome, compose button included, is hidden there.
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
}

static void PFBGlassApplyBarTint(void);

// Before the first bar is built: the pill's height for Tab labels and the glass tint for Bottom fade.
void PFBGlassTabBarStart(void) {
    if (PFBNativeGlassAsked()) {
        PFBGlassSizePillForLabels();
        PFBGlassApplyBarTint();
    }
}

// MARK: - Bottom fade

// Twitter's Liquid Glass tuning, reached by its exported addressor: since 12.44 the tab bar's glass
// takes a 25 % tint in both themes, at 0x48 and 0x50 of it; 12.42.1 had none.
static const ptrdiff_t kPFBGlassTabBarTintOffset = 0x48;
static const double kPFBGlassTwitterBarTint = 0.25;

// The tab bar's tint, light then dark; NULL unless the values after it are 12.44's: frost radius 0
// and saturation 1 in both themes, edge blur 6, edge tint 1, pill blur 2.
static double* PFBGlassTabBarTint(void) {
    static double* tint;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      void* (*shared)(void) = (void* (*)(void))dlsym(RTLD_DEFAULT, "$s11XNavigation17LiquidGlassTuningV6sharedACvau");
      double* base = shared ? (double*)((uint8_t*)shared() + kPFBGlassTabBarTintOffset) : NULL;
      if (!base) {
          PFBCompatMeasure(@"bottom fade", @"Twitter's glass tuning not found", 2);
          return;
      }
      BOOL matches = base[2] == 0.0 && base[3] == 0.0 && base[4] == 1.0 && base[5] == 1.0 && base[6] == 6.0 &&
                     base[7] == 1.0 && base[8] == 2.0;
      tint = matches ? base : NULL;
      if (!matches) {
          PFBCompatMeasure(@"bottom fade",
                           [NSString stringWithFormat:@"tab bar tuning moved: tint %.2f/%.2f, frost %.1f/%.1f, saturation "
                                                      @"%.2f/%.2f, edge blur %.1f, edge tint %.2f, pill blur %.1f",
                                                      base[0], base[1], base[2], base[3], base[4], base[5], base[6], base[7],
                                                      base[8]],
                           2);
      }
    });
    return tint;
}

// Twitter's tab bar glass, nil when no bar is on screen.
static UIView* PFBGlassBarGlass(void) {
    __block UIView* found = nil;
    Class glassClass = NSClassFromString(@"XDSGlass");
    PFBGlassFindClasses();
    PFBGlassForEachWindow(^(UIWindow* window) {
      PFBWalkAllSubviews(window, 40, ^(UIView* view) {
        if (found || !gPFBGlassBarClass || !glassClass || ![view isKindOfClass:gPFBGlassBarClass]) {
            return;
        }
        PFBWalkAllSubviews(view, 3, ^(UIView* inner) {
          if (!found && [inner isKindOfClass:glassClass]) {
              found = inner;
          }
        });
      });
    });
    return found;
}

// With Bottom fade on, the tab bar's glass gets 12.42.1's untinted glass at its next layout, so a
// change of the option shows without a relaunch; turned back off, Twitter's 25 % of the background.
static const void* kPFBGlassBarClearedKey = &kPFBGlassBarClearedKey;

static void PFBGlassTintBarGlass(UIView* glass) {
    if (!gPFBGlassBarClass || !PFBGlassTabBarTint() || ![glass respondsToSelector:@selector(setClearTint:scrimColor:)]) {
        return;
    }
    UIView* node = glass.superview;
    for (NSUInteger up = 0; node && up < 4 && ![node isKindOfClass:gPFBGlassBarClass]; up++) {
        node = node.superview;
    }
    BOOL show = [PFBSettings boolForKey:@"show_bottom_fade"];
    BOOL cleared = objc_getAssociatedObject(glass, kPFBGlassBarClearedKey) != nil;
    if (![node isKindOfClass:gPFBGlassBarClass] || show == cleared) {
        return;
    }
    UIColor* tint = [[PFBPalette currentBackgroundColor] colorWithAlphaComponent:show ? 0.0 : kPFBGlassTwitterBarTint];
    ((void (*)(id, SEL, UIColor*, UIColor*))objc_msgSend)(glass, @selector(setClearTint:scrimColor:), tint, [UIColor clearColor]);
    objc_setAssociatedObject(glass, kPFBGlassBarClearedKey, show ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (show) {
        PFBCOMPAT_ACTION(PFBCompat_show_bottom_fade, @"bottom bar glass untinted");
    }
}

// Bottom fade gives the bar 12.42.1's look, no tint; off, Twitter's 25 % comes back. Only those
// two values are ever written.
static void PFBGlassApplyBarTint(void) {
    double* tint = PFBGlassTabBarTint();
    if (!tint) {
        return;
    }
    PFBCompatReach(PFBCompatPath_bottom_fade);
    BOOL show = [PFBSettings boolForKey:@"show_bottom_fade"];
    double wanted = show ? 0.0 : kPFBGlassTwitterBarTint;
    for (NSUInteger i = 0; i < 2; i++) {
        if (tint[i] != wanted && (tint[i] == 0.0 || tint[i] == kPFBGlassTwitterBarTint)) {
            tint[i] = wanted;
        }
    }
    if (show) {
        PFBCOMPAT_ACTION(PFBCompat_show_bottom_fade, @"bottom bar tint removed");
    } else {
        PFBCOMPAT_OBSERVE(PFBCompat_show_bottom_fade, @"bottom bar tint found");
    }
}

// MARK: - Bottom band

// 12.42.1's band under its untinted bar: from the bar's top to the screen's bottom, the page blurred
// from about halfway down, under the background color. 12.44 builds none; this one sits right under
// the bar and follows it.
static const void* kPFBGlassBandKey = &kPFBGlassBandKey;
// The background color added under the glass at the bar's top, as chosen on renders against 12.42.1's
// captures; beside the glass, the page fades in from nothing, as on 12.42.1.
static const double kPFBGlassBandTopColor = 0.5;

static UIView* PFBGlassMakeBand(void) {
    UIView* band = [[UIView alloc] initWithFrame:CGRectZero];
    band.userInteractionEnabled = NO;
    UIVisualEffectView* blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleRegular]];
    UIView* blurMask = [[UIView alloc] initWithFrame:CGRectZero];
    CAGradientLayer* blurRamp = [CAGradientLayer layer];
    blurRamp.colors = @[ (id)UIColor.clearColor.CGColor, (id)UIColor.clearColor.CGColor,
                         (id)[UIColor colorWithWhite:0 alpha:0.5].CGColor, (id)UIColor.blackColor.CGColor ];
    blurRamp.locations = @[ @0.0, @0.1, @0.35, @0.6 ];
    [blurMask.layer addSublayer:blurRamp];
    blur.maskView = blurMask;
    [band addSubview:blur];
    UIView* color = [[UIView alloc] initWithFrame:CGRectZero];
    [color.layer addSublayer:[CAGradientLayer layer]];
    [band addSubview:color];
    UIView* lift = [[UIView alloc] initWithFrame:CGRectZero];
    [lift.layer addSublayer:[CAGradientLayer layer]];
    lift.layer.mask = [CAShapeLayer layer];
    [band addSubview:lift];
    return band;
}

// The band's parts sized to it, in the background color of its appearance: a ramp rising as the square
// of the height, and under the glass's capsule the top color fading out down the band. The blur's own
// 30 % white veil stays off.
static void PFBGlassLayOutBand(UIView* band, CGRect glass) {
    UIVisualEffectView* blur = band.subviews[0];
    UIView* color = band.subviews[1];
    UIView* lift = band.subviews[2];
    CAGradientLayer* blurRamp = (CAGradientLayer*)blur.maskView.layer.sublayers.firstObject;
    CAGradientLayer* colorRamp = (CAGradientLayer*)color.layer.sublayers.firstObject;
    CAGradientLayer* liftRamp = (CAGradientLayer*)lift.layer.sublayers.firstObject;
    CAShapeLayer* capsule = (CAShapeLayer*)lift.layer.mask;
    UIColor* background = [[PFBPalette currentBackgroundColor] resolvedColorWithTraitCollection:band.traitCollection];
    NSMutableArray* colors = [NSMutableArray array];
    NSMutableArray* lifts = [NSMutableArray array];
    NSMutableArray* locations = [NSMutableArray array];
    for (NSUInteger i = 0; i <= 8; i++) {
        double t = i / 8.0;
        [colors addObject:(id)[background colorWithAlphaComponent:t * t].CGColor];
        [lifts addObject:(id)[background colorWithAlphaComponent:kPFBGlassBandTopColor * (1.0 - t)].CGColor];
        [locations addObject:@(t)];
    }
    CGFloat radius = MIN(CGRectGetWidth(glass), CGRectGetHeight(glass)) / 2.0;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    blur.frame = band.bounds;
    blur.maskView.frame = blur.bounds;
    blurRamp.frame = blur.bounds;
    color.frame = band.bounds;
    colorRamp.frame = color.bounds;
    colorRamp.colors = colors;
    colorRamp.locations = locations;
    lift.frame = band.bounds;
    liftRamp.frame = lift.bounds;
    liftRamp.colors = lifts;
    liftRamp.locations = locations;
    capsule.frame = lift.bounds;
    capsule.path = [UIBezierPath bezierPathWithRoundedRect:glass cornerRadius:radius].CGPath;
    [CATransaction commit];
    for (UIView* veil in blur.subviews) {
        if ([NSStringFromClass([veil class]) isEqualToString:@"_UIVisualEffectSubview"] && veil.alpha > 0.0) {
            veil.alpha = 0.0;
        }
    }
}

// With Bottom fade on, the band is placed under the tab bar's platter, the glass at least 60 % as wide
// as the bar, from its top to the window's bottom, in the bar's closest ancestor that reaches that
// bottom, right under the branch holding the bar. It takes that branch's visibility; off, it hides.
static void PFBGlassPlaceBand(UIView* glass) {
    if (!gPFBGlassBarClass || !glass) {
        return;
    }
    UIView* bar = glass.superview;
    for (NSUInteger up = 0; bar && up < 4 && ![bar isKindOfClass:gPFBGlassBarClass]; up++) {
        bar = bar.superview;
    }
    if (![bar isKindOfClass:gPFBGlassBarClass] || !bar.superview || CGRectGetWidth(glass.bounds) < 0.6 * CGRectGetWidth(bar.bounds)) {
        return;
    }
    PFBCompatReach(PFBCompatPath_bottom_band);
    UIView* band = objc_getAssociatedObject(bar, kPFBGlassBandKey);
    UIWindow* window = bar.window;
    if (![PFBSettings boolForKey:@"show_bottom_fade"] || !window) {
        band.hidden = YES;
        return;
    }
    CGFloat windowBottom = CGRectGetMaxY(window.bounds);
    UIView* branch = bar;
    UIView* host = bar.superview;
    while (host.superview && CGRectGetMaxY([host convertRect:host.bounds toView:nil]) < windowBottom - 0.5) {
        branch = host;
        host = host.superview;
    }
    if (!band) {
        band = PFBGlassMakeBand();
        objc_setAssociatedObject(bar, kPFBGlassBandKey, band, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (band.superview != host || [host.subviews indexOfObject:band] > [host.subviews indexOfObject:branch]) {
        [host insertSubview:band belowSubview:branch];
    }
    CGRect onScreen = [glass convertRect:glass.bounds toView:nil];
    CGRect frame = [host convertRect:CGRectMake(CGRectGetMinX(window.bounds), CGRectGetMinY(onScreen), CGRectGetWidth(window.bounds),
                                                MAX(0.0, windowBottom - CGRectGetMinY(onScreen)))
                            fromView:nil];
    if (!CGRectEqualToRect(band.frame, frame)) {
        band.frame = frame;
    }
    PFBGlassLayOutBand(band, [band convertRect:glass.bounds fromView:glass]);
    BOOL hidden = NO;
    CGFloat alpha = 1.0;
    for (UIView* node = bar; node && node != host; node = node.superview) {
        hidden = hidden || node.hidden;
        alpha *= node.alpha;
    }
    band.hidden = hidden;
    band.alpha = alpha;
    PFBCOMPAT_ACTION(PFBCompat_show_bottom_fade, @"fade drawn under the bottom bar");
}

// A change to Bottom fade reaches the bar on screen, which takes its new look at its next layout.
void PFBGlassRefreshBottomFade(void) {
    if (!PFBNativeGlassAsked()) {
        return;
    }
    PFBGlassApplyBarTint();
    UIView* glass = PFBGlassBarGlass();
    PFBGlassTintBarGlass(glass);
    PFBGlassPlaceBand(glass);
    PFBRestyleGlassTabBars();
}

// Twitter's classic settings pages, or the list of its new settings, anywhere in the stack.
static BOOL PFBGlassStackHoldsSettings(UINavigationController* stack) {
    Class classic = objc_getClass("T1GenericSettingsViewController");
    Class list = objc_getClass("_TtC9XSettings26SettingsListViewController");
    for (UIViewController* screen in stack.viewControllers) {
        if ((classic && [screen isKindOfClass:classic]) || (list && [screen isKindOfClass:list])) {
            return YES;
        }
    }
    return NO;
}

// MARK: - Always visible

// The first 16 bytes of one of Twitter's static configurations, for the report.
static NSString* PFBGlassConfigBytes(const uint8_t* bytes) {
    NSMutableString* text = [NSMutableString string];
    for (NSUInteger i = 0; i < 16; i++) {
        [text appendFormat:@"%02x%@", bytes[i], i == 7 ? @" " : @""];
    }
    return text;
}

// Whether Twitter's configuration is the larger layout, where the word at 8 is not the bar style.
static BOOL gPFBGlassConfigLarge;

// Confirms the collapse-mode bytes sit where the patch writes, by their fingerprint in Twitter's
// four static configurations: top bar mode at byte 0, tab bar mode at 1, and in the smaller
// layout the style word at 8. A mismatch keeps the patch off.
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
      gPFBGlassConfigLarge = class_getInstanceSize(cls) - (size_t)offset > 24;
      const char* names[] = {"standardConfiguration", "pinnedConfiguration", "hiddenConfiguration",
                             "pinnedTransparentConfiguration"};
      const uint8_t navBar[] = {1, 3, 2, 3};
      const uintptr_t style[] = {0, 0, 0, 1};
      BOOL matches = YES;
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
          BOOL match = bytes[0] == navBar[i] && bytes[1] == 0 && (gPFBGlassConfigLarge || word == style[i]);
          if (!match) {
              PFBCompatMeasure(@"always visible",
                               [NSString stringWithFormat:@"%s does not match: %@", names[i], PFBGlassConfigBytes(bytes)],
                               8);
          }
          matches = matches && match;
      }
      verified = matches;
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
      ptrdiff_t size = applied ? PFBGlassIvarSpan(stack, applied) : 0;
      // 40 or 48 bytes as measured; a larger configuration is used only while the fingerprint of
      // Twitter's own configurations still puts the patched bytes in place.
      if (size == 40 || size == 48 || (size > 48 && PFBGlassConfigLayoutVerified())) {
          offset = ivar_getOffset(applied);
      }
      if (offset < 0 || !PFBGlassConfigLayoutVerified()) {
          PFBCompatMeasure(@"always visible",
                           offset < 0 ? [NSString stringWithFormat:@"patch off: applied configuration is %td bytes", size]
                                      : @"patch off: the configuration bytes moved",
                           2);
      }
    });
    return offset;
}

// The stack engine's collapse progress: the top bar's value, then the tab bar's, from 0 shown to
// 1 collapsed. NULL with no engine yet, and *readable NO when the layout is not the one measured.
static double* PFBGlassCollapseProgress(UINavigationController* stack, BOOL* readable) {
    static Class engineClass;
    static ptrdiff_t engineOffset = -1;
    static ptrdiff_t progressOffset = -1;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      engineClass = NSClassFromString(@"_TtC11XNavigation14CollapseEngine");
      Ivar engine = class_getInstanceVariable(NSClassFromString(@"XNAVNavigationController"), "collapseEngine");
      Ivar progress = engineClass ? class_getInstanceVariable(engineClass, "collapseProgress") : NULL;
      if (engine && progress) {
          engineOffset = ivar_getOffset(engine);
          progressOffset = ivar_getOffset(progress);
      }
    });
    *readable = engineOffset >= 0;
    if (engineOffset < 0) {
        return NULL;
    }
    void* engine = NULL;
    memcpy(&engine, (const uint8_t*)(__bridge void*)stack + engineOffset, sizeof(engine));
    if (engine && object_getClass((__bridge id)engine) != engineClass) {
        *readable = NO;
        return NULL;
    }
    return engine ? (double*)((uint8_t*)engine + progressOffset) : NULL;
}

// The tab bar's collapse in the stack's engine, from 0 shown to 1 collapsed; -1 when unread.
// The engine is made when first needed: until then nothing has collapsed.
static double PFBGlassTabBarCollapse(UINavigationController* stack) {
    BOOL readable = NO;
    double* progress = PFBGlassCollapseProgress(stack, &readable);
    if (!readable) {
        return -1.0;
    }
    return !progress ? 0.0 : (isfinite(progress[1]) ? progress[1] : -1.0);
}

// A finger is on a list Twitter's collapse engine follows.
static BOOL gPFBGlassDragging;
static const void* kPFBGlassBroughtBackKey = &kPFBGlassBroughtBackKey;

// A bar left collapsed with no finger on the screen, as Twitter hands Home back after its own
// Search, is set back to shown and the stack applies its configuration again. At most twice a
// second per stack.
static BOOL PFBGlassBringBackTabBar(UINavigationController* stack) {
    BOOL readable = NO;
    double* progress = PFBGlassCollapseProgress(stack, &readable);
    NSNumber* last = objc_getAssociatedObject(stack, kPFBGlassBroughtBackKey);
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (!progress || gPFBGlassDragging || (last && now - last.doubleValue < 0.5)) {
        return NO;
    }
    objc_setAssociatedObject(stack, kPFBGlassBroughtBackKey, @(now), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    progress[1] = 0.0;
    PFBCOMPAT_ACTION(PFBCompat_no_tab_bar_hiding, @"collapsed tab bar brought back");
    __weak UINavigationController* weakStack = stack;
    dispatch_async(dispatch_get_main_queue(), ^{
      SEL update = NSSelectorFromString(@"xnav_setNeedsNavigationConfigurationUpdateAnimated:");
      if ([weakStack respondsToSelector:update]) {
          ((void (*)(id, SEL, BOOL))objc_msgSend)(weakStack, update, NO);
      }
    });
    return YES;
}

// Pins the tab bar where Twitter's configuration lets it collapse (Home), the top bar's mode
// untouched. A bar caught collapsing under a finger is pinned once back, as the engine stops
// moving it; one left collapsed is brought back first.
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
    if ((!gPFBGlassConfigLarge && style == 2) || configuration[0] > 3 || configuration[1] != 1) {
        return;
    }
    if (![PFBSettings boolForKey:@"no_tab_bar_hiding"]) {
        PFBCOMPAT_OBSERVE(PFBCompat_no_tab_bar_hiding, @"glass tab bar set to collapse");
        return;
    }
    double collapse = PFBGlassTabBarCollapse(stack);
    if (collapse < 0.0 || (collapse > 0.001 && !PFBGlassBringBackTabBar(stack))) {
        return;
    }
    configuration[1] = 0;
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

// Whether nothing above the view hides it.
static BOOL PFBGlassShowing(UIView* view) {
    for (UIView* level = view; level; level = level.superview) {
        if (level.hidden || level.alpha <= 0.01) {
            return NO;
        }
    }
    return view != nil;
}

// Twitter 12.45 collapses the bar through its controller's collapse driver: latched with a target of
// 1 to collapse, unlatched at 0 to show the bar full (measured). The controller seen with the bar.
static __weak UIViewController* gPFBGlassTabController;
static __weak UIView* gPFBGlassTabBarView;
static Class gPFBGlassDriverClass;
static ptrdiff_t gPFBGlassDriverOffset = -1;
static ptrdiff_t gPFBGlassLatchedOffset = -1;
static ptrdiff_t gPFBGlassTargetOffset = -1;

static void PFBGlassNoteTabController(UIView* bar) {
    gPFBGlassTabBarView = bar;
    if (gPFBGlassTabController.viewIfLoaded.window) {
        return;
    }
    Class controller = NSClassFromString(@"_TtC11XNavigation16TabBarController");
    for (UIResponder* next = bar; next && controller; next = next.nextResponder) {
        if ([next isKindOfClass:controller]) {
            gPFBGlassTabController = (UIViewController*)next;
            return;
        }
    }
}

// The driver's latch and target sit where the patch writes: a pointer to the driver, a 1-byte latch
// and an 8-byte target, as measured. Any other layout keeps the hold off.
static BOOL PFBGlassDriverLayoutFound(void) {
    static BOOL found;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      Class controller = NSClassFromString(@"_TtC11XNavigation16TabBarController");
      gPFBGlassDriverClass = NSClassFromString(@"_TtC11XNavigation20TabBarCollapseDriver");
      Ivar driver = controller ? class_getInstanceVariable(controller, "$__lazy_storage_$_collapseDriver") : NULL;
      Ivar latched = gPFBGlassDriverClass ? class_getInstanceVariable(gPFBGlassDriverClass, "isLatched") : NULL;
      Ivar target = gPFBGlassDriverClass ? class_getInstanceVariable(gPFBGlassDriverClass, "progressTarget") : NULL;
      found = driver && latched && target && PFBGlassIvarSpan(controller, driver) == 8 &&
              PFBGlassIvarSpan(gPFBGlassDriverClass, latched) == 1 && PFBGlassIvarSpan(gPFBGlassDriverClass, target) == 8;
      if (found) {
          gPFBGlassDriverOffset = ivar_getOffset(driver);
          gPFBGlassLatchedOffset = ivar_getOffset(latched);
          gPFBGlassTargetOffset = ivar_getOffset(target);
      } else {
          PFBCompatMeasure(@"always visible", @"hold off: Twitter's collapse driver not laid out as measured", 2);
      }
    });
    return found;
}

// Before each frame Twitter animates, a collapse the driver was given is taken back: unlatched at a
// target of 0, the bar has nothing to collapse toward.
static void PFBGlassHoldTabBarOpen(void) {
    UIViewController* controller = gPFBGlassTabController;
    if (!controller || !PFBGlassDriverLayoutFound() || ![PFBSettings boolForKey:@"no_tab_bar_hiding"]) {
        return;
    }
    void* driver = NULL;
    memcpy(&driver, (const uint8_t*)(__bridge void*)controller + gPFBGlassDriverOffset, sizeof(driver));
    if (!driver || object_getClass((__bridge id)driver) != gPFBGlassDriverClass) {
        return;
    }
    uint8_t* latched = (uint8_t*)driver + gPFBGlassLatchedOffset;
    double target = 0.0;
    memcpy(&target, (uint8_t*)driver + gPFBGlassTargetOffset, sizeof(target));
    if (*latched == 0 && target == 0.0) {
        return;
    }
    *latched = 0;
    target = 0.0;
    memcpy((uint8_t*)driver + gPFBGlassTargetOffset, &target, sizeof(target));
    PFBCOMPAT_ACTION(PFBCompat_no_tab_bar_hiding, @"tab bar collapse held off");
}

// Always visible keeps the bar full: a second after a scroll, a selection lens about as wide as tall,
// the round button of the collapsed bar (measured 47 x 48 pt against 98 x 54 full), fails the option.
static void PFBGlassCheckAlwaysVisible(void) {
    static BOOL noted;
    if (noted || ![PFBSettings boolForKey:@"no_tab_bar_hiding"]) {
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
      static Class lensClass;
      lensClass = lensClass ?: NSClassFromString(@"_TtC13XDesignSystem10LiquidLens");
      __block UIView* lens = nil;
      PFBWalkAllSubviews(gPFBGlassTabBarView, 6, ^(UIView* inner) {
        if (!lens && lensClass && [inner isKindOfClass:lensClass]) {
            lens = inner;
        }
      });
      CGSize size = lens.bounds.size;
      if (!noted && size.height > 0.0 && size.width <= size.height * 1.3 && PFBGlassShowing(lens) &&
          [PFBSettings boolForKey:@"no_tab_bar_hiding"]) {
          noted = YES;
          PFBCompatNoteFailure(PFBCompat_no_tab_bar_hiding, @"tab bar still collapsed a second later");
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
    UIGestureRecognizerState state = recognizer.state;
    if (state == UIGestureRecognizerStateBegan) {
        @try {
            PFBGlassPinTabBar(PFBOwningController(recognizer.view).navigationController);
        } @catch (__unused id exception) {
        }
    }
    gPFBGlassDragging = state == UIGestureRecognizerStateBegan || state == UIGestureRecognizerStateChanged;
    %orig;
    if (state == UIGestureRecognizerStateEnded || state == UIGestureRecognizerStateCancelled) {
        PFBGlassCheckAlwaysVisible();
    }
}

%end

// Every frame Twitter animates passes through its display link: the bar's collapse is taken back first.
%hook _TtCC11XNavigation17DisplayLinkDriverP33_DC9744A9B855F36B00902ED7FE8B664F5Proxy

- (void)handleTick:(CADisplayLink*)link {
    @try {
        PFBGlassHoldTabBarOpen();
    } @catch (__unused id exception) {
    }
    %orig;
}

%end

// As the finger drags, Twitter squeezes the bar's whole chrome toward its bottom edge, then springs it
// back once the collapse is held off: a scale just under 1 with a shift down (measured down to 0.971
// and 13 pt). Always visible keeps the chrome at its size; any other transform goes through.
%hook _TtC11XNavigation25TabBarChromeContainerView

- (void)setTransform:(CGAffineTransform)transform {
    BOOL squeeze = transform.a > 0.9 && transform.a < 1.0 && fabs(transform.d - transform.a) < 0.001 && transform.b == 0.0 &&
                   transform.c == 0.0 && fabs(transform.tx) < 0.5 && transform.ty >= 0.0;
    if (squeeze && [PFBSettings boolForKey:@"no_tab_bar_hiding"]) {
        transform = CGAffineTransformIdentity;
        PFBCOMPAT_ACTION(PFBCompat_no_tab_bar_hiding, @"bar squeeze held off");
    }
    %orig(transform);
}

%end

// Once per launch, a second after the first bar is on screen and at rest: whether it stands taller than
// Twitter's height for the names.
static void PFBGlassCheckBarHeight(UIView* bar) {
    static BOOL scheduled;
    if (scheduled || !bar.window || CGRectGetHeight(bar.bounds) <= 0.0) {
        return;
    }
    scheduled = YES;
    __weak UIView* weakBar = bar;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      UIView* shown = weakBar;
      if (!shown.window || ![PFBSettings boolForKey:@"restore_tab_labels"] || PFBGlassCollapseOf(shown) > 0.0) {
          return;
      }
      CGFloat height = CGRectGetHeight(shown.bounds);
      if (height >= 70.0) {
          PFBCOMPAT_ACTION(PFBCompat_restore_tab_labels, @"bar raised above Twitter's height for the names");
      } else {
          PFBCompatNoteFailure(PFBCompat_restore_tab_labels,
                               [NSString stringWithFormat:@"Twitter's bar held at %.0f pt", height]);
      }
    });
}

%hook _TtC11XNavigation10TabBarView

// Twitter holds the bar at its own height, a required height on the view that places it (measured).
// With Tab labels, the bar's frame reaches the extra height above the rect Twitter lays out.
- (UIEdgeInsets)alignmentRectInsets {
    UIEdgeInsets insets = %orig;
    PFBCompatReach(PFBCompatPath_glass_bar_height);
    if ([PFBSettings boolForKey:@"restore_tab_labels"]) {
        insets.top += kPFBGlassExtraHeight;
    }
    return insets;
}

- (void)layoutSubviews {
    %orig;
    @try {
        UIView* bar = (UIView*)self;
        PFBGlassNoteTabController(bar);
        PFBGlassLiftBadges(bar);
        PFBGlassCheckBarHeight(bar);
        PFBCompatReach(PFBCompatPath_glass_tabs);
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
        PFBGlassPlaceBand((UIView*)self);
    } @catch (__unused id exception) {
    }
}

- (void)layoutSubviews {
    %orig;
    @try {
        PFBGlassFindClasses();
        PFBGlassTintBarGlass((UIView*)self);
        PFBGlassPlaceBand((UIView*)self);
    } @catch (__unused id exception) {
    }
}

%end
