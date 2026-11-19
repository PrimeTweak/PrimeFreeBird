// Probe for Twitter 12.45, removed once read: what makes the tab bar twitch while Always visible holds
// it. During each drag, every frame, the collapse driver's flags and springs are read, and every view
// of the bar as drawn is compared with how it stood when the drag began.

#import "Support/HookHelpers.h"
#import <objc/runtime.h>

@interface _TtCC11XNavigation17DisplayLinkDriverP33_DC9744A9B855F36B00902ED7FE8B664F5Proxy : NSObject
@end

@interface _TtCC11XNavigation14CollapseEngine14ScrollObserver : NSObject
- (void)handlePan:(UIPanGestureRecognizer*)recognizer;
@end

static NSString* const kPFBTwitchTopic = @"probe tab bar twitch";
static const NSUInteger kPFBTwitchCap = 90;
static const NSUInteger kPFBTwitchDrags = 4;
static const NSUInteger kPFBTwitchViewLines = 6;
static const NSUInteger kPFBTwitchDriverLines = 6;
static const NSUInteger kPFBTwitchPerLine = 8;
static NSUInteger gPFBTwitchSeq;
static CFAbsoluteTime gPFBTwitchStart;

static void PFBTwitchLine(NSString* line) {
    PFBCompatMeasure(kPFBTwitchTopic,
                     [NSString stringWithFormat:@"%02lu %.2f s %@", (unsigned long)++gPFBTwitchSeq, CFAbsoluteTimeGetCurrent() - gPFBTwitchStart, line],
                     kPFBTwitchCap);
}

static NSString* PFBTwitchName(id object) {
    NSString* name = NSStringFromClass([object class]);
    NSRange dot = [name rangeOfString:@"." options:NSBackwardsSearch];
    return dot.location == NSNotFound ? name : [name substringFromIndex:dot.location + 1];
}

static ptrdiff_t PFBTwitchOffset(Class cls, const char* name) {
    Ivar ivar = cls ? class_getInstanceVariable(cls, name) : NULL;
    return ivar ? ivar_getOffset(ivar) : -1;
}

// MARK: - the controller and its driver

static Class gPFBTwitchControllerClass;
static Class gPFBTwitchDriverClass;
static Class gPFBTwitchBarClass;
static ptrdiff_t gPFBTwitchContent = -1;
static ptrdiff_t gPFBTwitchDriver = -1;
static ptrdiff_t gPFBTwitchLatched = -1;
static ptrdiff_t gPFBTwitchResizing = -1;
static ptrdiff_t gPFBTwitchMorph = -1;
static ptrdiff_t gPFBTwitchScale = -1;
static ptrdiff_t gPFBTwitchResize = -1;
static ptrdiff_t gPFBTwitchTarget = -1;
static ptrdiff_t gPFBTwitchCatchingUp = -1;
static __weak UIViewController* gPFBTwitchController;

static void PFBTwitchFindOffsets(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      gPFBTwitchControllerClass = NSClassFromString(@"_TtC11XNavigation16TabBarController");
      gPFBTwitchDriverClass = NSClassFromString(@"_TtC11XNavigation20TabBarCollapseDriver");
      gPFBTwitchBarClass = NSClassFromString(@"_TtC11XNavigation10TabBarView");
      gPFBTwitchContent = PFBTwitchOffset(gPFBTwitchControllerClass, "contentContainerView");
      gPFBTwitchDriver = PFBTwitchOffset(gPFBTwitchControllerClass, "$__lazy_storage_$_collapseDriver");
      gPFBTwitchLatched = PFBTwitchOffset(gPFBTwitchDriverClass, "isLatched");
      gPFBTwitchResizing = PFBTwitchOffset(gPFBTwitchDriverClass, "isResizing");
      gPFBTwitchMorph = PFBTwitchOffset(gPFBTwitchDriverClass, "morphSpring");
      gPFBTwitchScale = PFBTwitchOffset(gPFBTwitchDriverClass, "scaleSpring");
      gPFBTwitchResize = PFBTwitchOffset(gPFBTwitchDriverClass, "resizeSpring");
      gPFBTwitchTarget = PFBTwitchOffset(gPFBTwitchDriverClass, "progressTarget");
      gPFBTwitchCatchingUp = PFBTwitchOffset(gPFBTwitchDriverClass, "isCatchingUpScale");
    });
}

static UIViewController* PFBTwitchController(void) {
    PFBTwitchFindOffsets();
    UIViewController* controller = gPFBTwitchController;
    if (controller.viewIfLoaded.window) {
        return controller;
    }
    for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }
        for (UIWindow* window in ((UIWindowScene*)scene).windows) {
            __block UIView* bar = nil;
            PFBWalkAllSubviews(window, 16, ^(UIView* view) {
              if (!bar && gPFBTwitchBarClass && [view isKindOfClass:gPFBTwitchBarClass]) {
                  bar = view;
              }
            });
            for (UIResponder* next = bar; next; next = next.nextResponder) {
                if ([next isKindOfClass:gPFBTwitchControllerClass]) {
                    gPFBTwitchController = (UIViewController*)next;
                    return (UIViewController*)next;
                }
            }
        }
    }
    return nil;
}

// A spring as its first three numbers, which hold where it is, how fast it goes and where it heads.
static NSString* PFBTwitchSpring(const uint8_t* driver, ptrdiff_t offset) {
    if (offset < 0) {
        return @"-";
    }
    double values[3] = {0, 0, 0};
    memcpy(values, driver + offset, sizeof(values));
    return [NSString stringWithFormat:@"%.3f %.3f %.3f", values[0], values[1], values[2]];
}

static NSString* PFBTwitchDriverState(UIViewController* controller) {
    if (!controller || gPFBTwitchDriver < 0) {
        return @"no driver";
    }
    void* driver = NULL;
    memcpy(&driver, (const uint8_t*)(__bridge void*)controller + gPFBTwitchDriver, sizeof(driver));
    if (!driver || object_getClass((__bridge id)driver) != gPFBTwitchDriverClass) {
        return @"no driver";
    }
    const uint8_t* d = (const uint8_t*)driver;
    double target = 0;
    if (gPFBTwitchTarget >= 0) {
        memcpy(&target, d + gPFBTwitchTarget, sizeof(target));
    }
    return [NSString stringWithFormat:@"latched %d resizing %d catching up %d target %.2f | morph %@ | scale %@ | resize %@",
                                      gPFBTwitchLatched >= 0 ? d[gPFBTwitchLatched] : 9, gPFBTwitchResizing >= 0 ? d[gPFBTwitchResizing] : 9,
                                      gPFBTwitchCatchingUp >= 0 ? d[gPFBTwitchCatchingUp] : 9, target, PFBTwitchSpring(d, gPFBTwitchMorph),
                                      PFBTwitchSpring(d, gPFBTwitchScale), PFBTwitchSpring(d, gPFBTwitchResize)];
}

// MARK: - the views as drawn

static NSString* PFBTwitchLayer(UIView* view) {
    CALayer* shown = view.layer.presentationLayer ?: view.layer;
    CATransform3D t = shown.transform;
    CALayer* mask = shown.mask ?: view.layer.mask;
    NSString* maskText = @"";
    if (mask) {
        CALayer* maskShown = mask.presentationLayer ?: mask;
        CGRect box = [maskShown isKindOfClass:[CAShapeLayer class]] && ((CAShapeLayer*)maskShown).path
                         ? CGPathGetBoundingBox(((CAShapeLayer*)maskShown).path)
                         : maskShown.frame;
        maskText = [NSString stringWithFormat:@" mask %.1f,%.1f %.1fx%.1f", box.origin.x, box.origin.y, box.size.width, box.size.height];
    }
    NSArray<NSString*>* keys = view.layer.animationKeys;
    return [NSString stringWithFormat:@"%.1f,%.1f %.1fx%.1f a%.2f%@ r%.1f%@%@", shown.position.x, shown.position.y, shown.bounds.size.width,
                                      shown.bounds.size.height, shown.opacity,
                                      CATransform3DIsIdentity(t) ? @""
                                                                 : [NSString stringWithFormat:@" t %.3f %.3f %.1f %.1f", t.m11, t.m22, t.m41, t.m42],
                                      shown.cornerRadius, maskText,
                                      keys.count ? [@" anim " stringByAppendingString:[keys componentsJoinedByString:@","]] : @""];
}

static void PFBTwitchCollect(UIView* view, UIView* screens, NSUInteger depth, NSMutableDictionary<NSValue*, NSString*>* into) {
    if (!view || view == screens || into.count >= 220) {
        return;
    }
    into[[NSValue valueWithNonretainedObject:view]] = [NSString stringWithFormat:@"%@ %@", PFBTwitchName(view), PFBTwitchLayer(view)];
    for (UIView* sub in depth ? view.subviews : @[]) {
        PFBTwitchCollect(sub, screens, depth - 1, into);
    }
}

static NSDictionary<NSValue*, NSString*>* PFBTwitchSnapshot(UIViewController* controller) {
    NSMutableDictionary<NSValue*, NSString*>* now = [NSMutableDictionary dictionary];
    void* screens = NULL;
    if (gPFBTwitchContent >= 0) {
        memcpy(&screens, (const uint8_t*)(__bridge void*)controller + gPFBTwitchContent, sizeof(screens));
    }
    PFBTwitchCollect(controller.view, (__bridge UIView*)screens, 12, now);
    return now;
}

// MARK: - each drag

static BOOL gPFBTwitchWatching;
static CFAbsoluteTime gPFBTwitchWatchUntil;
static NSUInteger gPFBTwitchDragCount;
static NSUInteger gPFBTwitchViewWritten;
static NSUInteger gPFBTwitchDriverWritten;
static NSDictionary<NSValue*, NSString*>* gPFBTwitchBaseline;
static NSString* gPFBTwitchLastDiff;
static NSString* gPFBTwitchLastDriver;
static NSString* gPFBTwitchRestDriver;
static CADisplayLink* gPFBTwitchLink;

@interface PFBTwitchTicker : NSObject
@end

@implementation PFBTwitchTicker

// Each frame of a watched drag: the views that stand apart from the start of the drag, written when
// that set changes.
- (void)tick:(CADisplayLink*)link {
    UIViewController* controller = PFBTwitchController();
    if (!gPFBTwitchWatching || !controller || CFAbsoluteTimeGetCurrent() > gPFBTwitchWatchUntil) {
        gPFBTwitchWatching = NO;
        link.paused = YES;
        return;
    }
    NSDictionary<NSValue*, NSString*>* now = PFBTwitchSnapshot(controller);
    NSMutableArray<NSString*>* changes = [NSMutableArray array];
    for (NSValue* key in now) {
        NSString* before = gPFBTwitchBaseline[key];
        if (before && ![before isEqualToString:now[key]]) {
            [changes addObject:[NSString stringWithFormat:@"%@ -> %@", before, [now[key] substringFromIndex:[now[key] rangeOfString:@" "].location + 1]]];
        } else if (!before) {
            [changes addObject:[@"+ " stringByAppendingString:now[key]]];
        }
    }
    [changes sortUsingSelector:@selector(compare:)];
    NSString* diff = [changes componentsJoinedByString:@" ; "];
    if (!changes.count || [diff isEqualToString:gPFBTwitchLastDiff] || gPFBTwitchViewWritten >= kPFBTwitchViewLines * kPFBTwitchDrags) {
        return;
    }
    gPFBTwitchLastDiff = diff;
    gPFBTwitchViewWritten++;
    for (NSUInteger i = 0; i < changes.count && i < 2 * kPFBTwitchPerLine; i += kPFBTwitchPerLine) {
        NSArray<NSString*>* part = [changes subarrayWithRange:NSMakeRange(i, MIN(kPFBTwitchPerLine, changes.count - i))];
        PFBTwitchLine([NSString stringWithFormat:@"drag %lu, %lu views apart, %lu-%lu: %@", (unsigned long)gPFBTwitchDragCount,
                                                 (unsigned long)changes.count, (unsigned long)i + 1, (unsigned long)(i + part.count),
                                                 [part componentsJoinedByString:@" ; "]]);
    }
}

@end

static void PFBTwitchStartWatching(void) {
    UIViewController* controller = PFBTwitchController();
    if (!controller || gPFBTwitchDragCount >= kPFBTwitchDrags || ![PFBSettings boolForKey:@"no_tab_bar_hiding"]) {
        return;
    }
    gPFBTwitchDragCount++;
    gPFBTwitchBaseline = PFBTwitchSnapshot(controller);
    gPFBTwitchLastDiff = nil;
    gPFBTwitchWatching = YES;
    gPFBTwitchWatchUntil = CFAbsoluteTimeGetCurrent() + 30.0;
    gPFBTwitchRestDriver = gPFBTwitchRestDriver ?: PFBTwitchDriverState(controller);
    PFBTwitchLine([NSString stringWithFormat:@"drag %lu began; driver %@", (unsigned long)gPFBTwitchDragCount, PFBTwitchDriverState(controller)]);
    if (!gPFBTwitchLink) {
        gPFBTwitchLink = [CADisplayLink displayLinkWithTarget:[PFBTwitchTicker new] selector:@selector(tick:)];
        [gPFBTwitchLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
    gPFBTwitchLink.paused = NO;
}

%hook _TtCC11XNavigation17DisplayLinkDriverP33_DC9744A9B855F36B00902ED7FE8B664F5Proxy

// Before the hold and after Twitter's frame, the driver as it stands, while a drag is watched.
- (void)handleTick:(CADisplayLink*)link {
    UIViewController* controller = gPFBTwitchWatching ? PFBTwitchController() : nil;
    NSString* before = controller ? PFBTwitchDriverState(controller) : nil;
    %orig;
    if (!controller || gPFBTwitchDriverWritten >= kPFBTwitchDriverLines * kPFBTwitchDrags) {
        return;
    }
    NSString* after = PFBTwitchDriverState(controller);
    NSString* pair = [NSString stringWithFormat:@"before %@ || after %@", before, after];
    if ([pair isEqualToString:gPFBTwitchLastDriver] || ([before isEqualToString:gPFBTwitchRestDriver] && [after isEqualToString:gPFBTwitchRestDriver])) {
        return;
    }
    gPFBTwitchLastDriver = pair;
    gPFBTwitchDriverWritten++;
    PFBTwitchLine([NSString stringWithFormat:@"drag %lu frame: driver %@", (unsigned long)gPFBTwitchDragCount, pair]);
}

%end

%hook _TtCC11XNavigation14CollapseEngine14ScrollObserver

- (void)handlePan:(UIPanGestureRecognizer*)recognizer {
    UIGestureRecognizerState state = recognizer.state;
    if (state == UIGestureRecognizerStateBegan) {
        PFBTwitchStartWatching();
    }
    %orig;
    if (state == UIGestureRecognizerStateEnded || state == UIGestureRecognizerStateCancelled) {
        gPFBTwitchWatchUntil = MIN(gPFBTwitchWatchUntil, CFAbsoluteTimeGetCurrent() + 0.8);
    }
}

%end

%ctor {
    %init;
    gPFBTwitchStart = CFAbsoluteTimeGetCurrent();
}
