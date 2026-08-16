//
//  NFBDebugger.m
//
//  See NFBDebugger.h for the shape of the thing. Everything here is inert
//  unless flex_twitter is on, checked once and cached.
//

#import "Debug/NFBDebugger.h"
#import "Generated/NFBHookManifest.h"
#import "Core/BHTSettings.h"
#import "Debug/NFBDiagnosticsViewController.h"
#import <objc/runtime.h>
#import <os/log.h>
#import <sys/utsname.h>

// MARK: - gate

static BOOL NFBDebugEnabled(void) {
    static BOOL enabled;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        enabled = [BHTSettings boolForKey:@"flex_twitter"];
    });
    return enabled;
}

static os_log_t NFBDebugLogHandle(void) {
    static os_log_t log;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ log = os_log_create("com.primefreebird.debug", "debugger"); });
    return log;
}

// MARK: - marks

static char kNFBMarkKey;

void NFBMark(UIView* view, NSString* origin) {
    if (!NFBDebugEnabled() || !view || !origin.length) {
        return;
    }
    objc_setAssociatedObject(view, &kNFBMarkKey, origin, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

static NSString* NFBMarkOf(UIView* view) {
    return objc_getAssociatedObject(view, &kNFBMarkKey);
}

// MARK: - decision log (ring buffer)

#define NFB_LOG_CAPACITY 80

static NSMutableArray<NSString*>* NFBDecisionRing(void) {
    static NSMutableArray* ring;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ ring = [NSMutableArray arrayWithCapacity:NFB_LOG_CAPACITY]; });
    return ring;
}

void NFBDebugLog(NSString* format, ...) {
    if (!NFBDebugEnabled() || !format) {
        return;
    }
    va_list args;
    va_start(args, format);
    NSString* line = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    // Timestamped to the second — enough to order decisions without noise.
    NSString* stamp;
    @synchronized(NFBDecisionRing()) {
        static NSDateFormatter* formatter;
        if (!formatter) {
            formatter = [NSDateFormatter new];
            formatter.dateFormat = @"HH:mm:ss";
        }
        stamp = [formatter stringFromDate:[NSDate date]];
        NSMutableArray* ring = NFBDecisionRing();
        [ring addObject:[NSString stringWithFormat:@"%@  %@", stamp, line]];
        if (ring.count > NFB_LOG_CAPACITY) {
            [ring removeObjectAtIndex:0];
        }
    }
    os_log(NFBDebugLogHandle(), "%{public}@", line);
}

// MARK: - environment

static NSString* NFBEnvironmentBlock(void) {
    NSDictionary* info = [NSBundle mainBundle].infoDictionary;
    NSString* app = info[@"CFBundleShortVersionString"] ?: @"?";
    NSString* build = info[@"CFBundleVersion"] ?: @"?";
    UIDevice* device = [UIDevice currentDevice];

    // Model identifier (iPhone17,2 and the like), which the marketing name hides.
    struct utsname systemInfo;
    NSString* model = @"?";
    if (uname(&systemInfo) == 0) {
        model = [NSString stringWithCString:systemInfo.machine
                                   encoding:NSUTF8StringEncoding] ?: @"?";
    }

    UITraitCollection* traits = UITraitCollection.currentTraitCollection;
    NSString* style = traits.userInterfaceStyle == UIUserInterfaceStyleDark
        ? @"Sombre" : @"Clair";
    BOOL liquidGlass = [BHTSettings boolForKey:@"enable_liquid_glass"];

    return [NSString stringWithFormat:
        @"PFB DIAG\n"
        @"Twitter %@ (%@) · iOS %@ · %@\n"
        @"Interface: %@ · Liquid Glass %@\n",
        app, build, device.systemVersion, model,
        style, liquidGlass ? @"ON" : @"OFF"];
}

// MARK: - hook health

// The dead list is collected once per call and shared by the text block and
// the banner count, so the two can never disagree.
typedef struct {
    NSUInteger okClasses;
    NSUInteger okMethods;
    NSUInteger okRuntime;
} NFBHealthCounts;

// deadClasses  — the class is gone: a real break, counted and shown loud.
// unresolved   — class present, method not found statically: usually a Swift or
//                category method the hook still reaches; shown quietly.
// deadRuntime  — a by-name class is gone: a real break.
static void NFBCollectHealth(NSMutableArray<NSString*>* deadClasses,
                             NSMutableArray<NSString*>* unresolvedMethods,
                             NSMutableArray<NSString*>* deadRuntime,
                             NFBHealthCounts* counts) {
    NSUInteger okClasses = 0;
    NSUInteger okMethods = 0;

    // Class + method dependencies. A NULL method means "class hooked, no
    // specific method" — the class alone is checked.
    //
    // Two failure kinds, kept apart because they mean different things:
    //   · the CLASS is gone      → the whole hook is dead, a real break
    //   · the class is here but   → often a false alarm: Swift methods and
    //     the method isn't found     category methods don't always answer
    //     statically                 class_getInstanceMethod, yet the hook
    //                                still lands. Reported quietly, not counted
    //                                as a break.
    NSMutableArray<NSString*>* deadClasses = [NSMutableArray array];
    NSMutableArray<NSString*>* unresolvedMethods = [NSMutableArray array];
    for (size_t i = 0; i < NFBHookRecordCount; i++) {
        NFBHookRecord record = NFBHookRecords[i];
        Class cls = objc_getClass(record.className);
        if (!cls) {
            // Deduplicate: several methods of one class each produced a row.
            NSString* entry = [NSString stringWithFormat:@"  ✗ classe %s  (%s)",
                               record.className, record.file];
            if (![deadClasses containsObject:entry]) {
                [deadClasses addObject:entry];
            }
            continue;
        }
        okClasses++;
        if (!record.methodName) {
            continue;
        }
        SEL selector = sel_registerName(record.methodName);
        // class_getInstanceMethod and getClassMethod both walk the superclass
        // chain already; respondsToSelector catches dynamically provided ones.
        BOOL exists = class_getInstanceMethod(cls, selector) != NULL ||
                      class_getClassMethod(cls, selector) != NULL ||
                      [cls instancesRespondToSelector:selector] ||
                      [cls respondsToSelector:selector];
        if (exists) {
            okMethods++;
        } else {
            [unresolvedMethods addObject:
                [NSString stringWithFormat:@"  · %s -%s  (%s)",
                 record.className, record.methodName, record.file]];
        }
    }

    // Classes resolved by name at runtime (%c / objc_getClass / …).
    NSUInteger okRuntime = 0;
    for (size_t i = 0; i < NFBRuntimeClassCount; i++) {
        if (objc_getClass(NFBRuntimeClasses[i])) {
            okRuntime++;
        } else {
            NSString* entry = [NSString stringWithFormat:@"  ✗ classe (par nom) %s",
                               NFBRuntimeClasses[i]];
            if (![deadRuntime containsObject:entry]) {
                [deadRuntime addObject:entry];
            }
        }
    }

    if (counts) {
        counts->okClasses = okClasses;
        counts->okMethods = okMethods;
        counts->okRuntime = okRuntime;
    }
}

static NSString* NFBHealthBlock(void) {
    NSMutableArray<NSString*>* deadClasses = [NSMutableArray array];
    NSMutableArray<NSString*>* unresolved = [NSMutableArray array];
    NSMutableArray<NSString*>* deadRuntime = [NSMutableArray array];
    NFBHealthCounts counts = {0, 0, 0};
    NFBCollectHealth(deadClasses, unresolved, deadRuntime, &counts);

    // Only vanished classes count as breaks — the loud number. Unresolved
    // methods are listed below under their own quiet heading.
    NSUInteger breaks = deadClasses.count + deadRuntime.count;
    NSMutableString* out = [NSMutableString string];
    [out appendFormat:@"ACCROCHES  %lu classes, %lu méthodes, %lu par nom — %@\n",
        (unsigned long)counts.okClasses, (unsigned long)counts.okMethods,
        (unsigned long)counts.okRuntime,
        breaks ? [NSString stringWithFormat:@"%lu CLASSE%@ MANQUANTE%@",
                    (unsigned long)breaks, breaks > 1 ? @"S" : @"", breaks > 1 ? @"S" : @""]
               : @"toutes présentes"];
    if (deadClasses.count) {
        [out appendString:[deadClasses componentsJoinedByString:@"\n"]];
        [out appendString:@"\n"];
    }
    if (deadRuntime.count) {
        [out appendString:[deadRuntime componentsJoinedByString:@"\n"]];
        [out appendString:@"\n"];
    }
    if (unresolved.count) {
        [out appendFormat:
            @"\nMÉTHODES NON RÉSOLUES STATIQUEMENT (%lu) — souvent Swift/catégorie, "
            @"le hook fonctionne quand même :\n", (unsigned long)unresolved.count];
        [out appendString:[unresolved componentsJoinedByString:@"\n"]];
        [out appendString:@"\n"];
    }
    return out;
}

// The banner counts only real breaks — vanished classes — not the quiet
// unresolved-method list, which is mostly false alarms.
NSUInteger NFBDebuggerMissingCount(void) {
    NSMutableArray<NSString*>* deadClasses = [NSMutableArray array];
    NSMutableArray<NSString*>* unresolved = [NSMutableArray array];
    NSMutableArray<NSString*>* deadRuntime = [NSMutableArray array];
    NFBCollectHealth(deadClasses, unresolved, deadRuntime, NULL);
    return deadClasses.count + deadRuntime.count;
}

// MARK: - view capture

static NSString* NFBColourText(UIColor* colour) {
    if (!colour) {
        return @"nil";
    }
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if ([colour getRed:&r green:&g blue:&b alpha:&a]) {
        return [NSString stringWithFormat:@"rgba(%.0f,%.0f,%.0f,%.2f)", r*255, g*255, b*255, a];
    }
    CGFloat w = 0;
    if ([colour getWhite:&w alpha:&a]) {
        return [NSString stringWithFormat:@"white(%.2f,%.2f)", w, a];
    }
    return @"?";
}

static void NFBCaptureView(UIView* view, NSInteger depth, NSMutableString* out) {
    if (!view || depth > 24) {
        return;
    }
    NSMutableString* indent = [NSMutableString string];
    for (NSInteger i = 0; i < depth; i++) {
        [indent appendString:@"  "];
    }

    CGRect inWindow = [view convertRect:view.bounds toView:nil];
    NSMutableString* line = [NSMutableString stringWithFormat:@"%@%@ %@",
        indent,
        NSStringFromClass([view classForCoder]),
        NSStringFromCGRect(view.frame)];

    // Only note colours and effects that are actually set, to keep it readable.
    if (view.backgroundColor) {
        [line appendFormat:@" bg=%@", NFBColourText(view.backgroundColor)];
    }
    if (view.layer.backgroundColor) {
        [line appendFormat:@" layer=%@",
            NFBColourText([UIColor colorWithCGColor:view.layer.backgroundColor])];
    }
    if (view.alpha < 0.999) {
        [line appendFormat:@" alpha=%.2f", view.alpha];
    }
    if (view.hidden) {
        [line appendString:@" HIDDEN"];
    }
    if ([view isKindOfClass:[UIImageView class]]) {
        UIImage* image = ((UIImageView*)view).image;
        [line appendFormat:@" img=%@ mode=%ld",
            image ? NSStringFromCGSize(image.size) : @"nil",
            image ? (long)image.renderingMode : -1L];
        [line appendFormat:@" tint=%@", NFBColourText(view.tintColor)];
    }
    if ([view isKindOfClass:[UIVisualEffectView class]]) {
        UIVisualEffect* fx = ((UIVisualEffectView*)view).effect;
        [line appendFormat:@" effect=%@",
            fx ? NSStringFromClass([fx classForCoder]) : @"nil"];
    }
    [line appendFormat:@" win=%@",
        NSStringFromCGRect(CGRectIntegral(inWindow))];
    [out appendString:line];
    [out appendString:@"\n"];

    // The tweak's own mark, if this view carries one — the line that turns
    // "what is this view" into "what did we do to it".
    NSString* mark = NFBMarkOf(view);
    if (mark) {
        [out appendFormat:@"%s  ⟨PFB: %@⟩\n", indent.UTF8String, mark];
    }

    for (UIView* sub in view.subviews) {
        NFBCaptureView(sub, depth + 1, out);
    }
}

static NSString* gNFBLastCapture;

static NSString* NFBCaptureBlock(void) {
    if (!gNFBLastCapture.length) {
        return @"CAPTURE  aucune — secoue l'appareil sur l'écran à diagnostiquer\n";
    }
    return [NSString stringWithFormat:@"CAPTURE\n%@", gNFBLastCapture];
}

static NSString* NFBDecisionBlock(void) {
    @synchronized(NFBDecisionRing()) {
        NSArray* ring = NFBDecisionRing();
        if (!ring.count) {
            return @"DÉCISIONS  (aucune enregistrée)\n";
        }
        return [NSString stringWithFormat:@"DÉCISIONS (%lu dernières)\n%@\n",
                (unsigned long)ring.count, [ring componentsJoinedByString:@"\n"]];
    }
}

// MARK: - report

NSString* NFBDebuggerReport(void) {
    NSMutableString* report = [NSMutableString string];
    [report appendString:NFBEnvironmentBlock()];
    [report appendString:@"\n"];
    [report appendString:NFBHealthBlock()];
    [report appendString:@"\n"];
    [report appendString:NFBDecisionBlock()];
    [report appendString:@"\n"];
    [report appendString:NFBCaptureBlock()];
    return report;
}

// MARK: - share sheet

static UIWindow* NFBActiveWindow(void) {
    for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }
        for (UIWindow* window in ((UIWindowScene*)scene).windows) {
            if (window.isKeyWindow) {
                return window;
            }
        }
    }
    return UIApplication.sharedApplication.windows.firstObject;
}

NSURL* NFBDebuggerWriteReportFile(void) {
    // A file, so the share sheet hands the report off whole — a large
    // hierarchy is painful to paste out of anything else.
    NSString* path = [NSTemporaryDirectory()
        stringByAppendingPathComponent:@"PrimeFreeBird-diagnostic.txt"];
    NSError* error = nil;
    [NFBDebuggerReport() writeToFile:path
                          atomically:YES
                            encoding:NSUTF8StringEncoding
                               error:&error];
    return error ? nil : [NSURL fileURLWithPath:path];
}

void NFBDebuggerPresent(void) {
    UIWindow* window = NFBActiveWindow();
    UIViewController* host = window.rootViewController;
    while (host.presentedViewController) {
        host = host.presentedViewController;
    }
    if (!host) {
        return;
    }
    // A second shake while the sheet is up refreshes it instead of stacking a
    // twin on top.
    if ([host isKindOfClass:[UINavigationController class]] &&
        [((UINavigationController*)host).topViewController
            isKindOfClass:[NFBDiagnosticsViewController class]]) {
        return;
    }
    NFBDiagnosticsViewController* screen = [NFBDiagnosticsViewController new];
    UINavigationController* nav =
        [[UINavigationController alloc] initWithRootViewController:screen];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    [host presentViewController:nav animated:YES completion:nil];
}

// MARK: - shake

// The tweak's own window subclass would be heavy; instead the shake is caught
// on UIWindow via a hook (see NFBDebugShake.x) which calls this.
void NFBDebuggerHandleShake(void) {
    if (!NFBDebugEnabled()) {
        return;
    }
    UIWindow* window = NFBActiveWindow();
    if (!window) {
        return;
    }
    NSMutableString* capture = [NSMutableString string];
    // The frontmost view controller's view is the useful root — its own
    // hierarchy, not the whole window chrome.
    UIViewController* top = window.rootViewController;
    while (top.presentedViewController) {
        top = top.presentedViewController;
    }
    UIView* root = top.viewIfLoaded ?: window;
    NFBCaptureView(root, 0, capture);
    gNFBLastCapture = capture;
    NFBDebugLog(@"capture prise (%lu caractères)", (unsigned long)capture.length);

    NFBDebuggerPresent();
}

// MARK: - install

void NFBDebuggerInstall(void) {
    if (!NFBDebugEnabled()) {
        return;
    }
    // The health check runs twice. The first pass, soon after launch, catches
    // the obvious. The second, later, gives frameworks that only load with
    // their screen (DM, Immersive, Guide) time to arrive before their classes
    // are judged — otherwise every not-yet-loaded class reads as a false break.
    // The on-device screen recomputes on every open anyway, so it is always
    // current; these log passes are for a developer watching at launch.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        os_log(NFBDebugLogHandle(), "%{public}@", NFBHealthBlock());
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(12.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        NSUInteger breaks = NFBDebuggerMissingCount();
        os_log(NFBDebugLogHandle(),
               "santé (2e passe, 12 s) : %{public}lu classe(s) manquante(s)",
               (unsigned long)breaks);
    });
}
