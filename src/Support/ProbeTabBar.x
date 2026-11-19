// Probe for Twitter 12.45, removed once read: what changes on screen when the glass tab bar collapses.
// Five times a second, finger down or not, the views of the tab bar's controller outside its screens
// and of the other windows are read; those that appear, vanish or change are written.

#import "Support/HookHelpers.h"
#import <objc/message.h>
#import <objc/runtime.h>

@interface _TtCC11XNavigation14CollapseEngine14ScrollObserver : NSObject
- (void)handlePan:(UIPanGestureRecognizer*)recognizer;
@end

static NSString* const kPFBTabProbeTopic = @"probe always visible";
static const NSUInteger kPFBTabProbeCap = 110;
static const NSUInteger kPFBTabProbeChanges = 80;
static const NSUInteger kPFBTabProbeLineLength = 1400;
static const NSUInteger kPFBTabProbePerLine = 8;
static NSUInteger gPFBTabProbeSeq;
static CFAbsoluteTime gPFBTabProbeStart;

static void PFBTabProbeLine(NSString* line) {
    if (line.length > kPFBTabProbeLineLength) {
        line = [[line substringToIndex:kPFBTabProbeLineLength] stringByAppendingString:@"…"];
    }
    PFBCompatMeasure(kPFBTabProbeTopic,
                     [NSString stringWithFormat:@"%02lu %.1f s %@", (unsigned long)++gPFBTabProbeSeq,
                                                CFAbsoluteTimeGetCurrent() - gPFBTabProbeStart, line],
                     kPFBTabProbeCap);
}

static NSString* PFBTabProbeName(id object) {
    if (!object) {
        return @"nil";
    }
    NSString* name = NSStringFromClass([object class]);
    NSRange dot = [name rangeOfString:@"." options:NSBackwardsSearch];
    return dot.location == NSNotFound ? name : [name substringFromIndex:dot.location + 1];
}

static ptrdiff_t PFBTabProbeOffset(Class cls, const char* name) {
    Ivar ivar = cls ? class_getInstanceVariable(cls, name) : NULL;
    return ivar ? ivar_getOffset(ivar) : -1;
}

// A pointer-sized object ivar at a known offset, or nil.
static id PFBTabProbeObjectAt(id object, ptrdiff_t offset) {
    if (!object || offset < 0) {
        return nil;
    }
    void* raw = NULL;
    memcpy(&raw, (const uint8_t*)(__bridge void*)object + offset, sizeof(raw));
    return raw && !((uintptr_t)raw >> 63) ? (__bridge id)raw : nil;
}

static UIView* PFBTabProbeFind(UIView* root, Class cls, NSUInteger depth) {
    if (!root || !cls) {
        return nil;
    }
    if ([root isKindOfClass:cls]) {
        return root;
    }
    if (depth == 0) {
        return nil;
    }
    for (UIView* sub in root.subviews) {
        UIView* found = PFBTabProbeFind(sub, cls, depth - 1);
        if (found) {
            return found;
        }
    }
    return nil;
}

// MARK: - the controller

static Class gPFBTabProbeBarClass;
static Class gPFBTabProbeControllerClass;
static Class gPFBTabProbeDriverClass;
static ptrdiff_t gPFBTabProbeContent = -1;
static ptrdiff_t gPFBTabProbeHidden = -1;
static ptrdiff_t gPFBTabProbeHiddenProgress = -1;
static ptrdiff_t gPFBTabProbeDriver = -1;
static ptrdiff_t gPFBTabProbeLatched = -1;
static ptrdiff_t gPFBTabProbeTarget = -1;
static __weak UIViewController* gPFBTabProbeController;

static UIViewController* PFBTabProbeFindController(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      gPFBTabProbeBarClass = NSClassFromString(@"_TtC11XNavigation10TabBarView");
      gPFBTabProbeControllerClass = NSClassFromString(@"_TtC11XNavigation16TabBarController");
      gPFBTabProbeDriverClass = NSClassFromString(@"_TtC11XNavigation20TabBarCollapseDriver");
      gPFBTabProbeContent = PFBTabProbeOffset(gPFBTabProbeControllerClass, "contentContainerView");
      gPFBTabProbeHidden = PFBTabProbeOffset(gPFBTabProbeControllerClass, "isBarHidden");
      gPFBTabProbeHiddenProgress = PFBTabProbeOffset(gPFBTabProbeControllerClass, "barHiddenProgress");
      gPFBTabProbeDriver = PFBTabProbeOffset(gPFBTabProbeControllerClass, "$__lazy_storage_$_collapseDriver");
      gPFBTabProbeLatched = PFBTabProbeOffset(gPFBTabProbeDriverClass, "isLatched");
      gPFBTabProbeTarget = PFBTabProbeOffset(gPFBTabProbeDriverClass, "progressTarget");
    });
    UIViewController* controller = gPFBTabProbeController;
    if (controller.viewIfLoaded.window) {
        return controller;
    }
    for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }
        for (UIWindow* window in ((UIWindowScene*)scene).windows) {
            UIView* bar = PFBTabProbeFind(window, gPFBTabProbeBarClass, 16);
            for (UIResponder* next = bar; next; next = next.nextResponder) {
                if ([next isKindOfClass:gPFBTabProbeControllerClass]) {
                    gPFBTabProbeController = (UIViewController*)next;
                    return (UIViewController*)next;
                }
            }
        }
    }
    return nil;
}

// The controller's own state: bar hidden and its progress, and the collapse driver's latch and target.
static NSString* PFBTabProbeControllerState(UIViewController* controller) {
    if (gPFBTabProbeHidden < 0 || gPFBTabProbeHiddenProgress < 0) {
        return @"controller -";
    }
    const uint8_t* c = (const uint8_t*)(__bridge void*)controller;
    double progress = 0;
    memcpy(&progress, c + gPFBTabProbeHiddenProgress, sizeof(progress));
    NSString* driver = @"no driver";
    id object = PFBTabProbeObjectAt(controller, gPFBTabProbeDriver);
    if (object && object_getClass(object) == gPFBTabProbeDriverClass && gPFBTabProbeLatched >= 0 && gPFBTabProbeTarget >= 0) {
        const uint8_t* d = (const uint8_t*)(__bridge void*)object;
        double target = 0;
        memcpy(&target, d + gPFBTabProbeTarget, sizeof(target));
        driver = [NSString stringWithFormat:@"latched %d target %.2f", d[gPFBTabProbeLatched], target];
    }
    return [NSString stringWithFormat:@"controller hidden %d %.2f, driver %@", c[gPFBTabProbeHidden], progress, driver];
}

// MARK: - the views

// One view as drawn: frame in the window, size shown, alpha, hidden, transform, corner and mask.
static NSString* PFBTabProbeViewState(UIView* view) {
    CGRect frame = [view convertRect:view.bounds toView:nil];
    CALayer* shown = view.layer.presentationLayer ?: view.layer;
    CGAffineTransform t = view.transform;
    CALayer* mask = view.layer.mask ?: view.maskView.layer;
    NSString* maskText = @"";
    if (mask) {
        CGRect box = [mask isKindOfClass:[CAShapeLayer class]] && ((CAShapeLayer*)mask).path
                         ? CGPathGetBoundingBox(((CAShapeLayer*)mask).path)
                         : mask.bounds;
        maskText = [NSString stringWithFormat:@" mask %.0f,%.0f %.0fx%.0f", box.origin.x, box.origin.y, box.size.width, box.size.height];
    }
    return [NSString stringWithFormat:@"%.0f,%.0f %.0fx%.0f shown %.0fx%.0f a%.2f%@%@ r%.0f%@", frame.origin.x, frame.origin.y, frame.size.width,
                                      frame.size.height, shown.bounds.size.width, shown.bounds.size.height, shown.opacity,
                                      view.hidden ? @" hidden" : @"",
                                      CGAffineTransformIsIdentity(t) ? @"" : [NSString stringWithFormat:@" t %.2f %.2f %.0f %.0f", t.a, t.d, t.tx, t.ty],
                                      view.layer.cornerRadius, maskText];
}

// Every view under the controller but its screens, by address, with its class and state.
static void PFBTabProbeCollect(UIView* view, UIView* screens, NSUInteger depth, NSMutableDictionary<NSValue*, NSString*>* into) {
    if (!view || view == screens || into.count >= 260) {
        return;
    }
    into[[NSValue valueWithNonretainedObject:view]] = [NSString stringWithFormat:@"%@ %@", PFBTabProbeName(view), PFBTabProbeViewState(view)];
    if (depth == 0) {
        return;
    }
    for (UIView* sub in view.subviews) {
        PFBTabProbeCollect(sub, screens, depth - 1, into);
    }
}

static NSDictionary<NSValue*, NSString*>* gPFBTabProbeLast;
static NSUInteger gPFBTabProbeWritten;

static void PFBTabProbeRead(void) {
    UIViewController* controller = PFBTabProbeFindController();
    if (!controller || gPFBTabProbeWritten >= kPFBTabProbeChanges) {
        return;
    }
    UIView* screens = PFBTabProbeObjectAt(controller, gPFBTabProbeContent);
    NSMutableDictionary<NSValue*, NSString*>* now = [NSMutableDictionary dictionary];
    PFBTabProbeCollect(controller.view, [screens isKindOfClass:[UIView class]] ? screens : nil, 12, now);
    for (UIWindow* window in controller.view.window.windowScene.windows) {
        if (window != controller.view.window) {
            PFBTabProbeCollect(window, nil, 6, now);
        }
    }
    if (!gPFBTabProbeLast) {
        gPFBTabProbeLast = now;
        NSArray<NSString*>* all = [now.allValues sortedArrayUsingSelector:@selector(compare:)];
        for (NSUInteger i = 0; i < all.count && i < 12 * kPFBTabProbePerLine; i += kPFBTabProbePerLine) {
            NSArray<NSString*>* part = [all subarrayWithRange:NSMakeRange(i, MIN(kPFBTabProbePerLine, all.count - i))];
            PFBTabProbeLine([NSString stringWithFormat:@"views %lu-%lu of %lu: %@", (unsigned long)i + 1, (unsigned long)(i + part.count),
                                                       (unsigned long)all.count, [part componentsJoinedByString:@" ; "]]);
        }
        PFBTabProbeLine(PFBTabProbeControllerState(controller));
        return;
    }
    NSMutableArray<NSString*>* changes = [NSMutableArray array];
    for (NSValue* key in now) {
        NSString* before = gPFBTabProbeLast[key];
        if (!before) {
            [changes addObject:[@"+ " stringByAppendingString:now[key]]];
        } else if (![before isEqualToString:now[key]]) {
            [changes addObject:[NSString stringWithFormat:@"~ %@ -> %@", before, [now[key] substringFromIndex:[now[key] rangeOfString:@" "].location + 1]]];
        }
    }
    for (NSValue* key in gPFBTabProbeLast) {
        if (!now[key]) {
            [changes addObject:[@"- " stringByAppendingString:gPFBTabProbeLast[key]]];
        }
    }
    gPFBTabProbeLast = now;
    if (!changes.count) {
        return;
    }
    [changes sortUsingSelector:@selector(compare:)];
    NSString* state = PFBTabProbeControllerState(controller);
    for (NSUInteger i = 0; i < changes.count && i < 3 * kPFBTabProbePerLine && gPFBTabProbeWritten < kPFBTabProbeChanges; i += kPFBTabProbePerLine) {
        NSArray<NSString*>* part = [changes subarrayWithRange:NSMakeRange(i, MIN(kPFBTabProbePerLine, changes.count - i))];
        gPFBTabProbeWritten++;
        PFBTabProbeLine([NSString stringWithFormat:@"%@ | %lu changes, %lu-%lu: %@", state, (unsigned long)changes.count, (unsigned long)i + 1,
                                                   (unsigned long)(i + part.count), [part componentsJoinedByString:@" ; "]]);
    }
}

static NSUInteger gPFBTabProbePans;

%hook _TtCC11XNavigation14CollapseEngine14ScrollObserver

- (void)handlePan:(UIPanGestureRecognizer*)recognizer {
    UIGestureRecognizerState state = recognizer.state;
    if ((state == UIGestureRecognizerStateBegan || state == UIGestureRecognizerStateEnded) && gPFBTabProbePans++ < 12) {
        PFBTabProbeLine([NSString stringWithFormat:@"pan %@ on %@", state == UIGestureRecognizerStateBegan ? @"began" : @"ended",
                                                   PFBTabProbeName(PFBOwningController(recognizer.view))]);
    }
    %orig;
}

%end

%ctor {
    %init;
    gPFBTabProbeStart = CFAbsoluteTimeGetCurrent();
    dispatch_async(dispatch_get_main_queue(), ^{
      NSTimer* timer = [NSTimer timerWithTimeInterval:0.2
                                              repeats:YES
                                                block:^(NSTimer* t) {
                                                  PFBTabProbeRead();
                                                  if (gPFBTabProbeWritten >= kPFBTabProbeChanges) {
                                                      [t invalidate];
                                                  }
                                                }];
      [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    });
}
