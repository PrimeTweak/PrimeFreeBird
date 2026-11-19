// Probe for Twitter 12.45, removed once read: how the glass bar collapses into its round button,
// frame by frame, with each part that could carry the collapse to the names under the glyphs.

#import "Support/HookHelpers.h"

@interface _TtCC11XNavigation14CollapseEngine14ScrollObserver : NSObject
@end

static NSString* const kPFBCollapseProbeTopic = @"probe tab collapse";
static const NSUInteger kPFBCollapseProbeCap = 320;
static NSUInteger gPFBCollapseProbeSeq;
static CFAbsoluteTime gPFBCollapseProbeStart;
static __weak UIView* gPFBCollapseProbeBar;
static __weak UINavigationController* gPFBCollapseProbeStack;
static NSString* gPFBCollapseProbeLast;
static NSUInteger gPFBCollapseProbeStill;
static BOOL gPFBCollapseProbeRestWritten = YES;
static CADisplayLink* gPFBCollapseProbeLink;
static NSUInteger gPFBCollapseProbeLensWrites;
static NSUInteger gPFBCollapseProbeItemLayouts;
static NSUInteger gPFBCollapseProbePlatterWrites;
static NSUInteger gPFBCollapseProbeBarLayouts;
static NSMutableArray<NSString*>* gPFBCollapseProbePending;

// Lines are kept while the bar moves and written once it is still, so writing never slows a frame.
static void PFBCollapseProbeFlush(void) {
    for (NSString* line in gPFBCollapseProbePending) {
        PFBCompatMeasure(kPFBCollapseProbeTopic, line, kPFBCollapseProbeCap);
    }
    [gPFBCollapseProbePending removeAllObjects];
}

static void PFBCollapseProbeLine(NSString* line) {
    if (gPFBCollapseProbeSeq >= kPFBCollapseProbeCap) {
        return;
    }
    gPFBCollapseProbePending = gPFBCollapseProbePending ?: [NSMutableArray array];
    [gPFBCollapseProbePending addObject:[NSString stringWithFormat:@"%03lu %.3f s %@", (unsigned long)++gPFBCollapseProbeSeq,
                                                                   CFAbsoluteTimeGetCurrent() - gPFBCollapseProbeStart, line]];
}

static NSString* PFBCollapseProbeRect(CGRect rect) {
    return [NSString stringWithFormat:@"%.1f,%.1f %.1fx%.1f", rect.origin.x, rect.origin.y, rect.size.width, rect.size.height];
}

// The bar's parts: its lens, pill, portal and every tab item, wherever Twitter nests them.
typedef struct {
    __unsafe_unretained UIView* lens;
    __unsafe_unretained UIView* pill;
    __unsafe_unretained UIView* portal;
} PFBCollapseProbeParts;

static PFBCollapseProbeParts PFBCollapseProbeFind(UIView* bar, NSMutableArray<UIView*>* items) {
    static Class lensClass, pillClass, portalClass, itemClass;
    lensClass = lensClass ?: NSClassFromString(@"_TtC13XDesignSystem10LiquidLens");
    pillClass = pillClass ?: NSClassFromString(@"_TtC11XNavigation10TabBarPill");
    portalClass = portalClass ?: NSClassFromString(@"_TtC11XNavigation16TabBarPortalView");
    itemClass = itemClass ?: NSClassFromString(@"_TtC11XNavigation14TabBarItemView");
    __block PFBCollapseProbeParts parts = {nil, nil, nil};
    PFBWalkAllSubviews(bar, 7, ^(UIView* view) {
      if (!parts.lens && lensClass && [view isKindOfClass:lensClass]) {
          parts.lens = view;
      } else if (!parts.pill && pillClass && [view isKindOfClass:pillClass]) {
          parts.pill = view;
      } else if (!parts.portal && portalClass && [view isKindOfClass:portalClass]) {
          parts.portal = view;
      } else if (itemClass && [view isKindOfClass:itemClass]) {
          [items addObject:view];
      }
    });
    return parts;
}

// The item's glyph: its largest image view with an image.
static UIImageView* PFBCollapseProbeGlyph(UIView* item) {
    __block UIImageView* glyph = nil;
    PFBWalkAllSubviews(item, 4, ^(UIView* view) {
      if ([view isKindOfClass:[UIImageView class]] && ((UIImageView*)view).image &&
          (!glyph || CGRectGetWidth(view.bounds) > CGRectGetWidth(glyph.bounds))) {
          glyph = (UIImageView*)view;
      }
    });
    return glyph;
}

// Each tab under the lens center, in each row Twitter draws: the glyph's width and center and the
// names' centers from the lens center, the glyph's lift, and each name's alpha.
static NSString* PFBCollapseProbeTabs(NSArray<UIView*>* items, CGPoint lensCenter, BOOL detail) {
    NSMutableArray<NSString*>* tabs = [NSMutableArray array];
    for (UIView* item in items) {
        CGRect frame = [item convertRect:item.bounds toView:nil];
        if (!CGRectContainsPoint(frame, lensCenter) || tabs.count >= 4) {
            continue;
        }
        UIImageView* glyph = PFBCollapseProbeGlyph(item);
        CGRect glyphFrame = glyph ? [glyph convertRect:glyph.bounds toView:nil] : CGRectZero;
        NSMutableArray<NSString*>* names = [NSMutableArray array];
        PFBWalkAllSubviews(item, 3, ^(UIView* view) {
          if ([view isKindOfClass:[UILabel class]] && ((UILabel*)view).text.length) {
              CGRect labelFrame = [view convertRect:view.bounds toView:nil];
              [names addObject:[NSString stringWithFormat:@"'%@' a%.2f dy%.1f%@", ((UILabel*)view).text, view.alpha,
                                                          CGRectGetMidY(labelFrame) - lensCenter.y,
                                                          detail ? [@" " stringByAppendingString:PFBCollapseProbeRect(labelFrame)] : @""]];
          }
        });
        NSString* row = [NSString stringWithFormat:@"%@/%@", NSStringFromClass(item.superview.superview.class),
                                                   NSStringFromClass(item.superview.class)];
        [tabs addObject:[NSString stringWithFormat:@"%@ a%.2f: glyph w%.1f dy%.1f lift%.1f%@ names [%@]",
                                                   [row stringByReplacingOccurrencesOfString:@"_TtC11XNavigation" withString:@""], item.alpha,
                                                   CGRectGetWidth(glyphFrame), CGRectGetMidY(glyphFrame) - lensCenter.y, glyph.superview.bounds.origin.y,
                                                   detail ? [NSString stringWithFormat:@" %@ item %@", PFBCollapseProbeRect(glyphFrame), PFBCollapseProbeRect(frame)] : @"",
                                                   [names componentsJoinedByString:@", "]]];
    }
    return [tabs componentsJoinedByString:@" | "];
}

// The stack engine's collapse progress for the bar (its second value), as the tweak reads it.
static NSString* PFBCollapseProbeEngine(void) {
    static Class engineClass;
    static ptrdiff_t engineOffset = -1, progressOffset = -1;
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
    UINavigationController* stack = gPFBCollapseProbeStack;
    if (!stack || engineOffset < 0) {
        return @"-";
    }
    void* engine = NULL;
    memcpy(&engine, (const uint8_t*)(__bridge void*)stack + engineOffset, sizeof(engine));
    if (!engine || object_getClass((__bridge id)engine) != engineClass) {
        return @"none";
    }
    double progress[2];
    memcpy(progress, (const uint8_t*)engine + progressOffset, sizeof(progress));
    return [NSString stringWithFormat:@"%.3f", progress[1]];
}

// The bar's collapse driver: latch, target, then each 8-byte word of its morph and scale springs.
static NSString* PFBCollapseProbeDriver(UIView* bar) {
    static Class controllerClass, driverClass;
    static ptrdiff_t driverOffset = -1, latchedOffset = -1, targetOffset = -1;
    static ptrdiff_t springOffsets[2] = {-1, -1};
    static ptrdiff_t springSpans[2];
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      controllerClass = NSClassFromString(@"_TtC11XNavigation16TabBarController");
      driverClass = NSClassFromString(@"_TtC11XNavigation20TabBarCollapseDriver");
      Ivar driver = controllerClass ? class_getInstanceVariable(controllerClass, "$__lazy_storage_$_collapseDriver") : NULL;
      Ivar latched = driverClass ? class_getInstanceVariable(driverClass, "isLatched") : NULL;
      Ivar target = driverClass ? class_getInstanceVariable(driverClass, "progressTarget") : NULL;
      const char* names[3] = {"morphSpring", "scaleSpring", "resizeSpring"};
      Ivar springs[3];
      for (int i = 0; i < 3; i++) {
          springs[i] = driverClass ? class_getInstanceVariable(driverClass, names[i]) : NULL;
      }
      if (driver && latched && target && springs[0] && springs[1] && springs[2]) {
          driverOffset = ivar_getOffset(driver);
          latchedOffset = ivar_getOffset(latched);
          targetOffset = ivar_getOffset(target);
          springOffsets[0] = ivar_getOffset(springs[0]);
          springOffsets[1] = ivar_getOffset(springs[1]);
          springSpans[0] = MIN((ptrdiff_t)80, springOffsets[1] - springOffsets[0]);
          springSpans[1] = MIN((ptrdiff_t)80, ivar_getOffset(springs[2]) - springOffsets[1]);
      }
      PFBCollapseProbeLine([NSString stringWithFormat:@"driver layout: driver %td latched %td target %td morph %td (%td) scale %td (%td)", driverOffset,
                                                      latchedOffset, targetOffset, springOffsets[0], springSpans[0], springOffsets[1], springSpans[1]]);
    });
    UIResponder* controller = bar;
    while (controller && controllerClass && ![controller isKindOfClass:controllerClass]) {
        controller = controller.nextResponder;
    }
    if (!controller || driverOffset < 0 || springSpans[0] <= 0 || springSpans[1] <= 0) {
        return @"-";
    }
    void* driver = NULL;
    memcpy(&driver, (const uint8_t*)(__bridge void*)controller + driverOffset, sizeof(driver));
    if (!driver || object_getClass((__bridge id)driver) != driverClass) {
        return @"none";
    }
    double target = 0.0;
    memcpy(&target, (const uint8_t*)driver + targetOffset, sizeof(target));
    NSMutableString* text = [NSMutableString stringWithFormat:@"L%d T%.3g", *((const uint8_t*)driver + latchedOffset), target];
    for (int s = 0; s < 2; s++) {
        [text appendString:s == 0 ? @" morph" : @" scale"];
        for (ptrdiff_t at = 0; at + 8 <= springSpans[s]; at += 8) {
            double word = 0.0;
            memcpy(&word, (const uint8_t*)driver + springOffsets[s] + at, sizeof(word));
            [text appendFormat:@" %.4g", word];
        }
    }
    return text;
}

// Each frame, the parts that follow the collapse, kept when they change; after half a second still,
// the tabs under the lens with their frames in window points, and every line kept is written.
@interface PFBCollapseProbeTicker : NSObject
@end

@implementation PFBCollapseProbeTicker

- (void)tick:(CADisplayLink*)link {
    if (gPFBCollapseProbeSeq >= kPFBCollapseProbeCap && !gPFBCollapseProbePending.count) {
        link.paused = YES;
        return;
    }
    UIView* bar = gPFBCollapseProbeBar;
    if (!bar.window) {
        return;
    }
    NSMutableArray<UIView*>* items = [NSMutableArray array];
    PFBCollapseProbeParts parts = PFBCollapseProbeFind(bar, items);
    UIView* lens = parts.lens;
    if (!lens) {
        return;
    }
    CGRect lensFrame = [lens convertRect:lens.bounds toView:nil];
    CGPoint center = CGPointMake(CGRectGetMidX(lensFrame), CGRectGetMidY(lensFrame));
    CALayer* mask = parts.portal.layer.mask;
    CGAffineTransform transform = bar.transform;
    NSString* state = [NSString
        stringWithFormat:@"lens %.1fx%.1f | pill a%.2f | portal a%.2f mask %@ | bar h%.0f t %.3f %.1f,%.1f | engine %@ | driver %@ | %@",
                         lens.bounds.size.width, lens.bounds.size.height, parts.pill.alpha, parts.portal.alpha,
                         mask ? PFBCollapseProbeRect(mask.frame) : @"none", CGRectGetHeight(bar.bounds), transform.a, transform.tx,
                         transform.ty, PFBCollapseProbeEngine(), PFBCollapseProbeDriver(bar), PFBCollapseProbeTabs(items, center, NO)];
    if ([state isEqualToString:gPFBCollapseProbeLast]) {
        if (++gPFBCollapseProbeStill == 60 && !gPFBCollapseProbeRestWritten) {
            gPFBCollapseProbeRestWritten = YES;
            PFBCollapseProbeLine([NSString stringWithFormat:@"still: lens %@, portal mask %@, bar %@ | %@", PFBCollapseProbeRect(lensFrame),
                                                            mask ? PFBCollapseProbeRect([parts.portal.layer convertRect:mask.frame toLayer:nil]) : @"none",
                                                            PFBCollapseProbeRect([bar convertRect:bar.bounds toView:nil]),
                                                            PFBCollapseProbeTabs(items, center, YES)]);
            PFBCollapseProbeFlush();
        }
        return;
    }
    gPFBCollapseProbeLast = state;
    gPFBCollapseProbeStill = 0;
    gPFBCollapseProbeRestWritten = NO;
    PFBCollapseProbeLine([NSString stringWithFormat:@"%@ | writes lens %lu items %lu platter %lu bar %lu", state, (unsigned long)gPFBCollapseProbeLensWrites,
                                                    (unsigned long)gPFBCollapseProbeItemLayouts, (unsigned long)gPFBCollapseProbePlatterWrites,
                                                    (unsigned long)gPFBCollapseProbeBarLayouts]);
    gPFBCollapseProbeLensWrites = gPFBCollapseProbeItemLayouts = gPFBCollapseProbePlatterWrites = gPFBCollapseProbeBarLayouts = 0;
}

@end

// Once, with the first bar on screen: the options that shape it and Twitter's collapsed height.
static void PFBCollapseProbeNoteBar(UIView* bar) {
    gPFBCollapseProbeBarLayouts++;
    if (!bar.window || gPFBCollapseProbeLink) {
        return;
    }
    gPFBCollapseProbeBar = bar;
    double (*getter)(void) =
        (double (*)(void))dlsym(RTLD_DEFAULT, "$s11XNavigation13TabBarMetricsO15collapsedHeight12CoreGraphics7CGFloatVvgZ");
    PFBCollapseProbeLine([NSString stringWithFormat:@"bar %.0fx%.0f, Tab labels %d, Always visible %d, Selected tab %d, collapsedHeight %@",
                                                    CGRectGetWidth(bar.bounds), CGRectGetHeight(bar.bounds),
                                                    [PFBSettings boolForKey:@"restore_tab_labels"], [PFBSettings boolForKey:@"no_tab_bar_hiding"],
                                                    [PFBSettings boolForKey:@"tab_bar_theming"],
                                                    getter ? [NSString stringWithFormat:@"%.1f", getter()] : @"not found"]);
    gPFBCollapseProbeLink = [CADisplayLink displayLinkWithTarget:[PFBCollapseProbeTicker new] selector:@selector(tick:)];
    [gPFBCollapseProbeLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

%hook _TtC11XNavigation10TabBarView

- (void)layoutSubviews {
    %orig;
    PFBCollapseProbeNoteBar((UIView*)self);
}

%end

%hook _TtC11XNavigation14TabBarItemView

- (void)layoutSubviews {
    %orig;
    gPFBCollapseProbeItemLayouts++;
}

%end

%hook _TtC13XDesignSystem10LiquidLens

- (void)setBounds:(CGRect)bounds {
    %orig;
    gPFBCollapseProbeLensWrites++;
}

%end

%hook XDSGlass

- (void)setBounds:(CGRect)bounds {
    %orig;
    gPFBCollapseProbePlatterWrites++;
}

%end

// The stack whose list the finger moves, for its engine's progress.
%hook _TtCC11XNavigation14CollapseEngine14ScrollObserver

- (void)handlePan:(UIPanGestureRecognizer*)recognizer {
    UIGestureRecognizerState state = recognizer.state;
    if (state == UIGestureRecognizerStateBegan) {
        gPFBCollapseProbeStack = PFBOwningController(recognizer.view).navigationController;
        PFBCollapseProbeLine([NSString stringWithFormat:@"pan began on %@", NSStringFromClass(PFBOwningController(recognizer.view).class)]);
    }
    %orig;
    if (state == UIGestureRecognizerStateEnded || state == UIGestureRecognizerStateCancelled) {
        PFBCollapseProbeLine(@"pan ended");
    }
}

%end

%ctor {
    %init;
    gPFBCollapseProbeStart = CFAbsoluteTimeGetCurrent();
}
