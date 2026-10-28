// Twitter's own Liquid Glass tab bar. Each tab is drawn in three rows: the resting row,
// the row seen through the glass lens over the selected tab, and the row the lens
// carries while it is dragged. Selected tab colors the last two; Tab labels names tabs.

#import "Support/HookHelpers.h"

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

// Points the glyph rises when the name is shown, and the name's box under it.
static const CGFloat kPFBGlassGlyphLift = 8.0;
static const CGFloat kPFBGlassLabelTopFromBottom = 21.0;
static const CGFloat kPFBGlassLabelHeight = 12.0;

static const void* kPFBGlassLabelKey = &kPFBGlassLabelKey;
static const void* kPFBGlassLiftKey = &kPFBGlassLiftKey;
static const void* kPFBGlassTintKey = &kPFBGlassTintKey;

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
// and transforms included, the content moves with it.
static void PFBGlassLift(UIView* view, BOOL lifted) {
    if (!view) {
        return;
    }
    BOOL wasLifted = objc_getAssociatedObject(view, kPFBGlassLiftKey) != nil;
    if (!lifted && !wasLifted) {
        return;
    }
    CGRect bounds = view.bounds;
    CGFloat wanted = lifted ? kPFBGlassGlyphLift : 0.0;
    if (bounds.origin.y != wanted) {
        bounds.origin.y = wanted;
        view.bounds = bounds;
    }
    objc_setAssociatedObject(view, kPFBGlassLiftKey, lifted ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// The lens rows take the accent with Selected tab on; the resting row keeps Twitter's gray.
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
        if (![applied isEqual:accent] || ![glyph.tintColor isEqual:accent]) {
            glyph.tintColor = accent;
            objc_setAssociatedObject(glyph, kPFBGlassTintKey, accent, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    } else if (applied) {
        glyph.tintColor = nil;
        objc_setAssociatedObject(glyph, kPFBGlassTintKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static UIFont* PFBGlassLabelFont(void) {
    SEL twitterFont = NSSelectorFromString(@"xdsDeprecated_customFontOfSize:weight:scalesWithDynamicType:");
    UIFont* font = nil;
    if ([UIFont respondsToSelector:twitterFont]) {
        font = ((UIFont * (*)(id, SEL, CGFloat, NSInteger, BOOL))objc_msgSend)([UIFont class], twitterFont, 10.0, 1, NO);
    }
    return [font isKindOfClass:[UIFont class]] ? font : [UIFont systemFontOfSize:10.0 weight:UIFontWeightMedium];
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
        PFBGlassLift(holder, NO);
        if (name.length) {
            PFBCOMPAT_OBSERVE(PFBCompat_restore_tab_labels, @"glass tab laid out");
        }
        return;
    }
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
    label.font = PFBGlassLabelFont();
    if (![label.text isEqualToString:name]) {
        label.text = name;
    }
    UIColor* color = glyph.tintColor ?: [UIColor labelColor];
    if (![label.textColor isEqual:color]) {
        label.textColor = color;
    }
    CGRect bounds = item.bounds;
    CGRect frame = CGRectMake(0.0, CGRectGetMaxY(bounds) - kPFBGlassLabelTopFromBottom, CGRectGetWidth(bounds),
                              kPFBGlassLabelHeight);
    if (!CGRectEqualToRect(label.frame, frame)) {
        label.frame = frame;
    }
    PFBGlassLift(holder, YES);
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
    BOOL labels = [PFBSettings boolForKey:@"restore_tab_labels"];
    PFBWalkAllSubviews(bar, 4, ^(UIView* view) {
      if (gPFBGlassBadgesClass && [view isKindOfClass:gPFBGlassBadgesClass]) {
          PFBGlassLift(view, labels);
      }
    });
}

%hook _TtC11XNavigation10TabBarView

- (void)layoutSubviews {
    %orig;
    @try {
        PFBGlassLiftBadges((UIView*)self);
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
