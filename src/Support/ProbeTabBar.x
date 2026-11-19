// Probe for Twitter 12.45, removed once read: how the glass tab bar collapses while Always visible
// pins it. Every half second the bar, its controller, its collapse driver and the shown stack's engine
// are read, and a line is written when they change; a pan's view and owners are noted too.

#import "Support/HookHelpers.h"
#import <objc/message.h>
#import <objc/runtime.h>

@interface _TtCC11XNavigation14CollapseEngine14ScrollObserver : NSObject
- (void)handlePan:(UIPanGestureRecognizer*)recognizer;
@end

static NSString* const kPFBTabProbeTopic = @"probe always visible";
static const NSUInteger kPFBTabProbeCap = 60;
static const NSUInteger kPFBTabProbeChanges = 45;
static NSUInteger gPFBTabProbeSeq;

static void PFBTabProbeLine(NSString* line) {
    PFBCompatMeasure(kPFBTabProbeTopic, [NSString stringWithFormat:@"%02lu %@", (unsigned long)++gPFBTabProbeSeq, line], kPFBTabProbeCap);
}

static NSString* PFBTabProbeName(id object) {
    if (!object) {
        return @"nil";
    }
    NSString* name = NSStringFromClass([object class]);
    NSRange dot = [name rangeOfString:@"." options:NSBackwardsSearch];
    return dot.location == NSNotFound ? name : [name substringFromIndex:dot.location + 1];
}

static NSString* PFBTabProbeHex(const uint8_t* bytes, ptrdiff_t count) {
    NSMutableString* text = [NSMutableString string];
    for (ptrdiff_t i = 0; i < count; i++) {
        [text appendFormat:@"%@%02x", i && i % 8 == 0 ? @" " : @"", bytes[i]];
    }
    return text;
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

static NSString* PFBTabProbeView(UIView* view) {
    if (!view) {
        return @"none";
    }
    CGRect frame = [view convertRect:view.bounds toView:nil];
    CGAffineTransform t = view.transform;
    CALayer* shown = view.layer.presentationLayer ?: view.layer;
    return [NSString stringWithFormat:@"%.0f,%.0f %.0fx%.0f t %.2f %.2f %.1f a %.2f shown %.0fx%.0f", frame.origin.x, frame.origin.y,
                                      frame.size.width, frame.size.height, t.a, t.d, t.ty, view.alpha, shown.bounds.size.width,
                                      shown.bounds.size.height];
}

// MARK: - offsets

static Class gPFBTabProbeBarClass;
static Class gPFBTabProbeControllerClass;
static Class gPFBTabProbeDriverClass;
static Class gPFBTabProbeStackClass;
static Class gPFBTabProbeEngineClass;
static Class gPFBTabProbeGlassClass;
static ptrdiff_t gPFBTabProbePlatter = -1;
static ptrdiff_t gPFBTabProbeCollapse = -1;
static ptrdiff_t gPFBTabProbeHidden = -1;
static ptrdiff_t gPFBTabProbeHiddenProgress = -1;
static ptrdiff_t gPFBTabProbeDriver = -1;
static ptrdiff_t gPFBTabProbeLatched = -1;
static ptrdiff_t gPFBTabProbeResizing = -1;
static ptrdiff_t gPFBTabProbeTarget = -1;
static ptrdiff_t gPFBTabProbeClock = -1;
static ptrdiff_t gPFBTabProbeEngine = -1;
static ptrdiff_t gPFBTabProbeApplied = -1;
static ptrdiff_t gPFBTabProbeProgress = -1;
static ptrdiff_t gPFBTabProbePolicies = -1;

static void PFBTabProbeFindOffsets(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      gPFBTabProbeBarClass = NSClassFromString(@"_TtC11XNavigation10TabBarView");
      gPFBTabProbeControllerClass = NSClassFromString(@"_TtC11XNavigation16TabBarController");
      gPFBTabProbeDriverClass = NSClassFromString(@"_TtC11XNavigation20TabBarCollapseDriver");
      gPFBTabProbeStackClass = NSClassFromString(@"XNAVNavigationController");
      gPFBTabProbeEngineClass = NSClassFromString(@"_TtC11XNavigation14CollapseEngine");
      gPFBTabProbeGlassClass = NSClassFromString(@"XDSGlass");
      gPFBTabProbePlatter = PFBTabProbeOffset(gPFBTabProbeBarClass, "platter");
      gPFBTabProbeCollapse = PFBTabProbeOffset(gPFBTabProbeBarClass, "appliedCollapse");
      gPFBTabProbeHidden = PFBTabProbeOffset(gPFBTabProbeControllerClass, "isBarHidden");
      gPFBTabProbeHiddenProgress = PFBTabProbeOffset(gPFBTabProbeControllerClass, "barHiddenProgress");
      gPFBTabProbeDriver = PFBTabProbeOffset(gPFBTabProbeControllerClass, "$__lazy_storage_$_collapseDriver");
      gPFBTabProbeLatched = PFBTabProbeOffset(gPFBTabProbeDriverClass, "isLatched");
      gPFBTabProbeResizing = PFBTabProbeOffset(gPFBTabProbeDriverClass, "isResizing");
      gPFBTabProbeTarget = PFBTabProbeOffset(gPFBTabProbeDriverClass, "progressTarget");
      gPFBTabProbeClock = PFBTabProbeOffset(gPFBTabProbeDriverClass, "clock");
      gPFBTabProbeEngine = PFBTabProbeOffset(gPFBTabProbeStackClass, "collapseEngine");
      gPFBTabProbeApplied = PFBTabProbeOffset(gPFBTabProbeStackClass, "appliedConfiguration");
      gPFBTabProbeProgress = PFBTabProbeOffset(gPFBTabProbeEngineClass, "collapseProgress");
      gPFBTabProbePolicies = PFBTabProbeOffset(gPFBTabProbeEngineClass, "policies");
      PFBTabProbeLine([NSString stringWithFormat:@"offsets: platter %td, collapse %td, hidden %td/%td, driver %td (latched %td, resizing %td, "
                                                 @"target %td, clock %td), engine %td, applied %td, progress %td, policies %td",
                                                 gPFBTabProbePlatter, gPFBTabProbeCollapse, gPFBTabProbeHidden, gPFBTabProbeHiddenProgress,
                                                 gPFBTabProbeDriver, gPFBTabProbeLatched, gPFBTabProbeResizing, gPFBTabProbeTarget,
                                                 gPFBTabProbeClock, gPFBTabProbeEngine, gPFBTabProbeApplied, gPFBTabProbeProgress,
                                                 gPFBTabProbePolicies]);
    });
}

// MARK: - one reading

static __weak UIView* gPFBTabProbeBar;

static UIView* PFBTabProbeTabBar(void) {
    UIView* bar = gPFBTabProbeBar.window ? gPFBTabProbeBar : nil;
    for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
        if (bar || ![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }
        for (UIWindow* window in ((UIWindowScene*)scene).windows) {
            bar = bar ?: PFBTabProbeFind(window, gPFBTabProbeBarClass, 16);
        }
    }
    gPFBTabProbeBar = bar;
    return bar;
}

static UIViewController* PFBTabProbeController(UIView* bar) {
    for (UIResponder* next = bar; next; next = next.nextResponder) {
        if ([next isKindOfClass:gPFBTabProbeControllerClass]) {
            return (UIViewController*)next;
        }
    }
    return nil;
}

// Whether nothing above the view hides it.
static BOOL PFBTabProbeShowing(UIView* view) {
    for (UIView* level = view; level; level = level.superview) {
        if (level.hidden || level.alpha <= 0.01) {
            return NO;
        }
    }
    return view.window != nil;
}

// The stacks on screen under the tab bar's controller, with their engine; *tabOnly gets the tab
// bar's part alone, which decides whether the reading changed.
static NSString* PFBTabProbeStacks(UIViewController* controller, NSString** tabOnly) {
    NSMutableArray<NSString*>* parts = [NSMutableArray array];
    NSMutableArray<NSString*>* tabParts = [NSMutableArray array];
    NSMutableArray<UIViewController*>* queue = [NSMutableArray arrayWithObject:controller];
    for (NSUInteger i = 0; i < queue.count && i < 120; i++) {
        UIViewController* screen = queue[i];
        if ([screen isKindOfClass:gPFBTabProbeStackClass] && PFBTabProbeShowing(screen.viewIfLoaded)) {
            UINavigationController* stack = (UINavigationController*)screen;
            id engine = PFBTabProbeObjectAt(stack, gPFBTabProbeEngine);
            const uint8_t* applied = gPFBTabProbeApplied >= 0 ? (const uint8_t*)(__bridge void*)stack + gPFBTabProbeApplied : NULL;
            double progress[2] = {-1, -1};
            uint8_t tabWord = 0xff;
            if (engine && object_getClass(engine) == gPFBTabProbeEngineClass && gPFBTabProbeProgress >= 0) {
                memcpy(progress, (const uint8_t*)(__bridge void*)engine + gPFBTabProbeProgress, sizeof(progress));
                if (gPFBTabProbePolicies >= 0) {
                    tabWord = *((const uint8_t*)(__bridge void*)engine + gPFBTabProbePolicies + 56);
                }
            }
            [parts addObject:[NSString stringWithFormat:@"%@ applied %02x %02x progress %.2f %.2f tab policy %02x",
                                                        PFBTabProbeName(stack.topViewController), applied ? applied[0] : 0xff,
                                                        applied ? applied[1] : 0xff, progress[0], progress[1], tabWord]];
            [tabParts addObject:[NSString stringWithFormat:@"%02x %.2f %02x", applied ? applied[1] : 0xff, progress[1], tabWord]];
            continue;
        }
        [queue addObjectsFromArray:screen.childViewControllers];
    }
    *tabOnly = [tabParts componentsJoinedByString:@";"];
    return parts.count ? [parts componentsJoinedByString:@"; "] : @"no stack shown";
}

static NSString* gPFBTabProbeLast;
static NSUInteger gPFBTabProbeWritten;
static CFAbsoluteTime gPFBTabProbeStart;

// The bar as it stands: written only when it differs from the last reading.
static void PFBTabProbeRead(NSString* when) {
    PFBTabProbeFindOffsets();
    UIView* bar = PFBTabProbeTabBar();
    if (!bar || gPFBTabProbeWritten >= kPFBTabProbeChanges) {
        return;
    }
    UIView* glass = PFBTabProbeFind(bar, gPFBTabProbeGlassClass, 5);
    UIView* platter = [PFBTabProbeObjectAt(bar, gPFBTabProbePlatter) isKindOfClass:[UIView class]] ? PFBTabProbeObjectAt(bar, gPFBTabProbePlatter) : nil;
    UIViewController* controller = PFBTabProbeController(bar);
    NSString* hidden = @"-";
    NSString* driverState = @"no driver";
    if (controller && gPFBTabProbeHidden >= 0 && gPFBTabProbeHiddenProgress >= 0) {
        double progress = 0;
        memcpy(&progress, (const uint8_t*)(__bridge void*)controller + gPFBTabProbeHiddenProgress, sizeof(progress));
        hidden = [NSString stringWithFormat:@"%d %.2f", *((const uint8_t*)(__bridge void*)controller + gPFBTabProbeHidden), progress];
        id driver = PFBTabProbeObjectAt(controller, gPFBTabProbeDriver);
        if (driver && object_getClass(driver) == gPFBTabProbeDriverClass) {
            const uint8_t* d = (const uint8_t*)(__bridge void*)driver;
            double target = 0;
            if (gPFBTabProbeTarget >= 0) {
                memcpy(&target, d + gPFBTabProbeTarget, sizeof(target));
            }
            driverState = [NSString stringWithFormat:@"latched %d resizing %d target %.2f clock %@", gPFBTabProbeLatched >= 0 ? d[gPFBTabProbeLatched] : 9,
                                                     gPFBTabProbeResizing >= 0 ? d[gPFBTabProbeResizing] : 9, target,
                                                     gPFBTabProbeClock >= 0 ? PFBTabProbeHex(d + gPFBTabProbeClock, 9) : @"-"];
        }
    }
    NSString* collapse = gPFBTabProbeCollapse >= 0 ? PFBTabProbeHex((const uint8_t*)(__bridge void*)bar + gPFBTabProbeCollapse, 32) : @"-";
    NSString* tabOnly = @"";
    NSString* stacks = controller ? PFBTabProbeStacks(controller, &tabOnly) : @"no controller";
    NSString* state = [NSString stringWithFormat:@"bar %@ | glass %@ | platter %@ | collapse %@ | controller hidden %@ | driver %@",
                                                 PFBTabProbeView(bar), PFBTabProbeView(glass), PFBTabProbeView(platter), collapse, hidden, driverState];
    NSString* signature = [state stringByAppendingString:tabOnly];
    if ([signature isEqualToString:gPFBTabProbeLast]) {
        return;
    }
    gPFBTabProbeLast = signature;
    state = [NSString stringWithFormat:@"%@ | %@", state, stacks];
    gPFBTabProbeWritten++;
    PFBTabProbeLine([NSString stringWithFormat:@"%.1f s %@: %@", CFAbsoluteTimeGetCurrent() - gPFBTabProbeStart, when, state]);
}

%hook _TtC11XNavigation10TabBarView

- (void)layoutSubviews {
    %orig;
    PFBTabProbeRead(@"layout");
}

%end

static NSUInteger gPFBTabProbePans;

%hook _TtCC11XNavigation14CollapseEngine14ScrollObserver

- (void)handlePan:(UIPanGestureRecognizer*)recognizer {
    UIGestureRecognizerState state = recognizer.state;
    if ((state == UIGestureRecognizerStateBegan || state == UIGestureRecognizerStateEnded) && gPFBTabProbePans++ < 8) {
        UIViewController* owner = PFBOwningController(recognizer.view);
        PFBTabProbeLine([NSString stringWithFormat:@"pan %@ on %@, owner %@, its stack %@", state == UIGestureRecognizerStateBegan ? @"began" : @"ended",
                                                   PFBTabProbeName(recognizer.view), PFBTabProbeName(owner),
                                                   PFBTabProbeName(owner.navigationController)]);
    }
    %orig;
}

%end

%ctor {
    %init;
    gPFBTabProbeStart = CFAbsoluteTimeGetCurrent();
    dispatch_async(dispatch_get_main_queue(), ^{
      [NSTimer scheduledTimerWithTimeInterval:0.5
                                      repeats:YES
                                        block:^(NSTimer* timer) {
                                          PFBTabProbeRead(@"tick");
                                          if (gPFBTabProbeWritten >= kPFBTabProbeChanges) {
                                              [timer invalidate];
                                          }
                                        }];
    });
}
