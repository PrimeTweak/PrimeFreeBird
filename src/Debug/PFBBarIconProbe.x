// Watches the icons PrimeFreeBird adds or repaints in the top bars. One that is on screen but
// cannot be seen goes to MEASUREMENTS with why: hidden, faded, layer opacity, animations, ink, cover.

#import "Support/HookHelpers.h"
#import "Common/PFBBundle.h"
#import "Common/PFBCompatibility.h"
#import "Debug/PFBDebugger.h"

static NSString* const kPFBIconProbeTopic = @"icon visibility";
static const NSUInteger kPFBIconProbeLines = 20;
// Each icon as it shows when it can be seen, once per screen, apart from the failures above.
static NSString* const kPFBIconReferenceTopic = @"icon reference";
static const NSUInteger kPFBIconReferenceLines = 10;
// The top bars sit above this line; the lists below it are not walked.
static const CGFloat kPFBIconProbeTop = 200.0;

static NSString* gPFBIconScreen;
static NSString* gPFBIconPreviousScreen;
static CFTimeInterval gPFBIconShownAt;
static NSUInteger gPFBIconGeneration;
static NSMutableSet<NSString*>* gPFBIconSeenVisible;

// The labels PrimeFreeBird gives its own bar icons.
static NSSet<NSString*>* PFBIconLabels(void) {
    static NSSet<NSString*>* labels;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      PFBBundle* bundle = [PFBBundle sharedBundle];
      labels = [NSSet setWithObjects:[bundle localizedStringForKey:@"FILTERS_TITLE"],
                                     [bundle localizedStringForKey:@"ADVANCED_SEARCH_TITLE"],
                                     [bundle localizedStringForKey:@"HIDDEN_NOTIFS_TITLE"], nil];
    });
    return labels;
}

// PrimeFreeBird's icons in the top part of a window: its glyph buttons, the items it labels, and
// the buttons whose glyph it repainted, the gears among them.
static void PFBIconCollect(UIView* view, NSUInteger depth, NSMutableArray<UIView*>* icons) {
    if (depth > 30 || view.hidden || [view convertRect:view.bounds toView:nil].origin.y > kPFBIconProbeTop) {
        return;
    }
    if ([view isKindOfClass:[PFBBarGlyphButton class]] ||
        (view.accessibilityLabel.length && [PFBIconLabels() containsObject:view.accessibilityLabel])) {
        [icons addObject:view];
        return;
    }
    if ([view isKindOfClass:[UIImageView class]] && PFBIsPaintedBarGlyph(((UIImageView*)view).image)) {
        UIView* button = view;
        for (UIView* node = view.superview; node && node != button.window; node = node.superview) {
            if ([node isKindOfClass:[UIControl class]]) {
                button = node;
                break;
            }
        }
        if (![icons containsObject:button]) {
            [icons addObject:button];
        }
        return;
    }
    for (UIView* sub in view.subviews) {
        PFBIconCollect(sub, depth + 1, icons);
    }
}

static UIImageView* PFBIconGlyphView(UIView* icon) {
    __block UIImageView* found = nil;
    PFBWalkAllSubviews(icon, 3, ^(UIView* view) {
      if (!found && [view isKindOfClass:[UIImageView class]] && ((UIImageView*)view).image) {
          found = (UIImageView*)view;
      }
    });
    return found;
}

// Views drawn after the icon, up its chain, that cover at least half of it.
static NSString* PFBIconCover(UIView* icon) {
    CGRect mine = [icon convertRect:icon.bounds toView:nil];
    CGFloat area = CGRectGetWidth(mine) * CGRectGetHeight(mine);
    NSMutableArray<NSString*>* found = [NSMutableArray array];
    for (UIView* node = icon; node.superview && found.count < 3 && ![node isKindOfClass:[UIWindow class]];
         node = node.superview) {
        NSArray<UIView*>* siblings = node.superview.subviews;
        NSUInteger index = [siblings indexOfObject:node];
        for (NSUInteger i = index + 1; i < siblings.count && found.count < 3; i++) {
            UIView* above = siblings[i];
            if (above.hidden || above.alpha < 0.05 || above.layer.opacity < 0.05) {
                continue;
            }
            CGRect overlap = CGRectIntersection(mine, [above convertRect:above.bounds toView:nil]);
            if (CGRectIsNull(overlap) || CGRectGetWidth(overlap) * CGRectGetHeight(overlap) < area * 0.5) {
                continue;
            }
            BOOL paints = [above isKindOfClass:[UIVisualEffectView class]] ||
                          (above.backgroundColor && CGColorGetAlpha(above.backgroundColor.CGColor) > 0.5);
            [found addObject:[NSString stringWithFormat:@"%@%@", PFBReadableClassName(above), paints ? @" (paints)" : @""]];
        }
    }
    return found.count ? [found componentsJoinedByString:@", "] : @"nothing";
}

// One icon: how it shows, and why it cannot be seen when it cannot.
static NSString* PFBIconReport(UIView* icon, BOOL* invisible) {
    NSMutableArray<NSString*>* reasons = [NSMutableArray array];
    NSMutableArray<NSString*>* animations = [NSMutableArray array];
    UIImageView* glyph = PFBIconGlyphView(icon);
    CGFloat alpha = 1.0, model = 1.0, shown = 1.0;
    NSString* hiddenBy = nil;
    for (UIView* node = glyph ?: icon; node; node = node.superview) {
        if (node.hidden && !hiddenBy) {
            hiddenBy = PFBReadableClassName(node);
        }
        alpha *= node.alpha;
        model *= node.layer.opacity;
        CALayer* presented = node.layer.presentationLayer;
        shown *= presented ? presented.opacity : node.layer.opacity;
        for (NSString* key in node.layer.animationKeys) {
            if (animations.count < 4) {
                [animations addObject:[NSString stringWithFormat:@"%@ %@", PFBReadableClassName(node), key]];
            }
        }
        if ([node isKindOfClass:[UIWindow class]]) {
            break;
        }
    }
    NSString* ink = PFBImageInk(glyph.image);
    UIUserInterfaceStyle style = icon.traitCollection.userInterfaceStyle;
    double r = -1, g = -1, b = -1;
    if (ink) {
        sscanf(ink.UTF8String, "rgb(%lf,%lf,%lf)", &r, &g, &b);
    }
    CGRect frame = [icon convertRect:icon.bounds toView:nil];
    NSString* cover = PFBIconCover(icon);
    if (hiddenBy) {
        [reasons addObject:[@"hidden by " stringByAppendingString:hiddenBy]];
    }
    if (alpha < 0.05) {
        [reasons addObject:@"alpha"];
    }
    if (model < 0.05) {
        [reasons addObject:@"layer opacity"];
    }
    if (shown < 0.05) {
        [reasons addObject:@"opacity on screen"];
    }
    if (!glyph) {
        [reasons addObject:@"no image"];
    } else if (!ink || [ink isEqualToString:@"transparent"]) {
        [reasons addObject:@"transparent image"];
    } else if (style != UIUserInterfaceStyleDark && r > 230 && g > 230 && b > 230) {
        [reasons addObject:@"white ink on a light screen"];
    } else if (style == UIUserInterfaceStyleDark && r >= 0 && r < 25 && g < 25 && b < 25) {
        [reasons addObject:@"black ink on a dark screen"];
    }
    if ([cover containsString:@"(paints)"]) {
        [reasons addObject:@"covered"];
    }
    if (!CGRectIntersectsRect(frame, icon.window.bounds)) {
        [reasons addObject:@"off screen"];
    }
    *invisible = reasons.count > 0;
    return [NSString stringWithFormat:@"%@ · frame %.0f,%.0f %.0fx%.0f · alpha %.2f · opacity %.2f, on screen %.2f · "
                                      @"animations [%@] · ink %@ in %@ · tint %@ · over it %@",
                                      reasons.count ? [@"INVISIBLE: " stringByAppendingString:[reasons componentsJoinedByString:@", "]]
                                                    : @"visible",
                                      frame.origin.x, frame.origin.y, frame.size.width, frame.size.height, alpha, model,
                                      shown, [animations componentsJoinedByString:@", "], ink ?: @"none",
                                      style == UIUserInterfaceStyleDark ? @"dark" : @"light",
                                      PFBColorText(glyph.tintColor), cover];
}

static void PFBIconCheck(NSString* moment) {
    NSMutableArray<UIView*>* icons = [NSMutableArray array];
    for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }
        for (UIWindow* window in ((UIWindowScene*)scene).windows) {
            if (!window.hidden) {
                PFBIconCollect(window, 0, icons);
            }
        }
    }
    if (!gPFBIconSeenVisible) {
        gPFBIconSeenVisible = [NSMutableSet set];
    }
    for (UIView* icon in icons) {
        BOOL invisible = NO;
        NSString* report = PFBIconReport(icon, &invisible);
        NSString* name = icon.accessibilityLabel.length ? icon.accessibilityLabel : PFBReadableClassName(icon);
        NSString* key = [NSString stringWithFormat:@"%@ on %@", name, gPFBIconScreen ?: @"?"];
        // A visible icon is noted once per screen; every way of not showing is noted.
        if (!invisible && [gPFBIconSeenVisible containsObject:key]) {
            continue;
        }
        if (!invisible) {
            [gPFBIconSeenVisible addObject:key];
        }
        PFBCompatMeasure(invisible ? kPFBIconProbeTopic : kPFBIconReferenceTopic,
                         [NSString stringWithFormat:@"%@ (%@, %.1f s after it showed, after %@): %@", key, moment,
                                                    CACurrentMediaTime() - gPFBIconShownAt,
                                                    gPFBIconPreviousScreen ?: @"none", report],
                         invisible ? kPFBIconProbeLines : kPFBIconReferenceLines);
    }
}

// Looked at once the screen has settled, and again a few seconds later.
static void PFBIconScheduleChecks(void) {
    NSUInteger generation = ++gPFBIconGeneration;
    for (NSNumber* delay in @[ @1.0, @4.0 ]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
                         if (generation == gPFBIconGeneration) {
                             @try {
                                 PFBIconCheck([NSString stringWithFormat:@"%.0f s", delay.doubleValue]);
                             } @catch (__unused id exception) {
                             }
                         }
                       });
    }
}

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    UIViewController* controller = (UIViewController*)self;
    if (controller.navigationController.topViewController != controller) {
        return;
    }
    NSString* name = PFBReadableClassName(controller);
    if (![name isEqualToString:gPFBIconScreen]) {
        gPFBIconPreviousScreen = gPFBIconScreen;
        gPFBIconScreen = name;
    }
    gPFBIconShownAt = CACurrentMediaTime();
    PFBIconScheduleChecks();
}

%end

%ctor {
    %init;
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                      object:nil
                                                       queue:NSOperationQueue.mainQueue
                                                  usingBlock:^(__unused NSNotification* note) {
                                                    PFBIconScheduleChecks();
                                                  }];
    // At each stethoscope capture, the icons as they are at that moment.
    [[NSNotificationCenter defaultCenter] addObserverForName:PFBDebuggerWillCaptureNotification
                                                      object:nil
                                                       queue:nil
                                                  usingBlock:^(__unused NSNotification* note) {
                                                    @try {
                                                        PFBIconCheck(@"at capture");
                                                    } @catch (__unused id exception) {
                                                    }
                                                  }];
}
