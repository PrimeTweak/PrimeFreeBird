// Probe for the tab bar that folds on 12.42.1: every switch whose value differs from the IPA's
// defaults (and when one changes), and each fold and unfold of Twitter's tab bar with the state of
// its controller, collapse driver and accessory coordinator. Removed once read.

#import <QuartzCore/QuartzCore.h>
#import <malloc/malloc.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <os/lock.h>
#import "Support/HookHelpers.h"

static CFTimeInterval gProbeStart;
static os_unfair_lock gProbeLock = OS_UNFAIR_LOCK_INIT;
static id gProbeSwitches;
static void* gProbeStorePointer;
static void* gProbeStoresSeen[8];
static NSUInteger gProbeStores;
static NSDictionary<NSString*, id>* gProbeDefaults;
static NSMutableDictionary<NSString*, NSString*>* gProbeSeen;
static SEL gProbeReader;
static __weak UIView* gProbeBar;
static NSInteger gProbeFolded = -1;
static NSUInteger gProbeDumps;
static CFTimeInterval gProbeLastSearch;
static NSUInteger gProbeTicks;
static NSUInteger gProbeTransitions;
static NSUInteger gProbeBarsFound;
static NSString* gProbeLastGlass = @"none";

// Time since launch and the clock, so lines from two launches of the same build stay apart.
static NSString* pfbProbeNow(void) {
    static NSDateFormatter* clock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      clock = [NSDateFormatter new];
      clock.dateFormat = @"HH:mm:ss";
    });
    return [NSString stringWithFormat:@"+%.1f s (%@)", CACurrentMediaTime() - gProbeStart, [clock stringFromDate:[NSDate date]]];
}

// Each topic keeps its own lines, so a long switch list cannot crowd out the tab bar.
static void pfbProbe(NSString* topic, NSString* line) {
    PFBCompatMeasure(topic, line, 150);
}

// Splits a long list over several report lines.
static void pfbProbeList(NSString* topic, NSString* title, NSArray<NSString*>* items) {
    NSMutableString* line = [NSMutableString stringWithString:title];
    for (NSString* item in items) {
        if (line.length + item.length > 900) {
            pfbProbe(topic, line);
            line = [NSMutableString stringWithString:@"  …"];
        }
        [line appendFormat:@" %@;", item];
    }
    pfbProbe(topic, line);
}

static id pfbProbeStore(void) {
    os_unfair_lock_lock(&gProbeLock);
    id store = gProbeSwitches;
    os_unfair_lock_unlock(&gProbeLock);
    return store;
}

static BOOL pfbProbeWatched(NSString* key) {
    return [key containsString:@"tab_bar"] || [key containsString:@"liquid_glass"] || [key containsString:@"navigation"] ||
           [key containsString:@"collapse"] || [key containsString:@"xnc"] || [key containsString:@"fab"] ||
           [key containsString:@"accessory"] || [key containsString:@"chrome"];
}

// The switches the tweak answers itself in these families, for reading the list.
static BOOL pfbProbeTweakAnswers(NSString* key) {
    static NSSet<NSString*>* keys;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      keys = [NSSet setWithArray:@[@"ios_liquid_glass_redesign_enabled", @"ios_tab_bar_default_show_communities",
                                   @"ios_tab_bar_default_show_profile", @"xchat_liquid_glass_convo_header_enabled",
                                   @"ios_tweet_detail_overflow_in_navigation_enabled"]];
    });
    return [keys containsObject:key];
}

static NSString* pfbProbeText(id value) {
    if (!value || value == (id)kCFNull) {
        return @"none";
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        if (CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) {
            return [value boolValue] ? @"true" : @"false";
        }
        return [NSString stringWithFormat:@"%g", [value doubleValue]];
    }
    if ([value isKindOfClass:[NSString class]]) {
        return [NSString stringWithFormat:@"\"%@\"", [value substringToIndex:MIN([value length], (NSUInteger)60)]];
    }
    if ([NSJSONSerialization isValidJSONObject:value]) {
        NSData* data = [NSJSONSerialization dataWithJSONObject:value options:0 error:nil];
        NSString* text = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"?";
        return [text substringToIndex:MIN(text.length, (NSUInteger)60)];
    }
    return [NSString stringWithFormat:@"<%@>", NSStringFromClass([value class])];
}

static BOOL pfbProbeSame(id now, id fallback) {
    if ([now isKindOfClass:[NSNumber class]] && [fallback isKindOfClass:[NSNumber class]]) {
        return [now doubleValue] == [fallback doubleValue];
    }
    return [pfbProbeText(now) isEqualToString:pfbProbeText(fallback)];
}

static BOOL pfbProbePlain(id value) {
    return [value isKindOfClass:[NSNumber class]] || [value isKindOfClass:[NSString class]] ||
           [value isKindOfClass:[NSArray class]] || [value isKindOfClass:[NSDictionary class]];
}

// Twitter's store wraps each value in a TFSFeatureSwitchesValue: its value comes from -rawValue,
// or failing that from its first instance variable holding a plain value.
static id pfbProbeUnwrap(id wrapper) {
    if (!wrapper || pfbProbePlain(wrapper) || wrapper == (id)kCFNull) {
        return wrapper;
    }
    SEL raw = NSSelectorFromString(@"rawValue");
    if ([wrapper respondsToSelector:raw]) {
        id inner = nil;
        @try {
            inner = ((id (*)(id, SEL))objc_msgSend)(wrapper, raw);
        } @catch (__unused NSException* exception) {
        }
        if (pfbProbePlain(inner) || inner == (id)kCFNull) {
            return inner;
        }
    }
    for (Class cls = object_getClass(wrapper); cls && cls != [NSObject class]; cls = class_getSuperclass(cls)) {
        unsigned count = 0;
        Ivar* ivars = class_copyIvarList(cls, &count);
        for (unsigned index = 0; index < count; index++) {
            const char* type = ivar_getTypeEncoding(ivars[index]);
            if (type && type[0] == '@') {
                id inner = object_getIvar(wrapper, ivars[index]);
                if (pfbProbePlain(inner)) {
                    free(ivars);
                    return inner;
                }
            }
        }
        free(ivars);
    }
    return wrapper;
}

// The value in Twitter's store, read past the tweak's answers so no option is marked as seen.
static id pfbProbeValue(id store, NSString* key) {
    id value = nil;
    @try {
        value = ((id (*)(id, SEL, id))objc_msgSend)(store, gProbeReader, key);
    } @catch (__unused NSException* exception) {
        return nil;
    }
    return pfbProbeUnwrap(value);
}

// The members of a class, for reading what the store hands back.
static NSString* pfbProbeMembers(Class cls) {
    NSMutableArray<NSString*>* items = [NSMutableArray array];
    unsigned count = 0;
    Ivar* ivars = class_copyIvarList(cls, &count);
    for (unsigned index = 0; index < count; index++) {
        [items addObject:[NSString stringWithFormat:@"ivar %s %s", ivar_getName(ivars[index]) ?: "?", ivar_getTypeEncoding(ivars[index]) ?: ""]];
    }
    free(ivars);
    objc_property_t* properties = class_copyPropertyList(cls, &count);
    for (unsigned index = 0; index < count; index++) {
        [items addObject:[NSString stringWithFormat:@"property %s", property_getName(properties[index])]];
    }
    free(properties);
    Method* methods = class_copyMethodList(cls, &count);
    for (unsigned index = 0; index < count; index++) {
        [items addObject:[@"-" stringByAppendingString:NSStringFromSelector(method_getName(methods[index]))]];
    }
    free(methods);
    return [items componentsJoinedByString:@", "];
}

// The first reading lists every switch Twitter holds differently from the IPA's defaults; the
// later ones only what changed since.
static void pfbProbeSwitches(NSString* moment) {
    id store = pfbProbeStore();
    if (!store || !gProbeDefaults.count) {
        pfbProbe(@"probe switches", [NSString stringWithFormat:@"%@ %@: switches not read yet (store %@, defaults %lu)", pfbProbeNow(), moment,
                                                             store ? @"found" : @"missing", (unsigned long)gProbeDefaults.count]);
        return;
    }
    BOOL first = gProbeSeen.count == 0;
    NSMutableArray<NSString*>* watched = [NSMutableArray array];
    NSMutableArray<NSString*>* others = [NSMutableArray array];
    NSMutableArray<NSString*>* changed = [NSMutableArray array];
    NSUInteger none = 0;
    for (NSString* key in [gProbeDefaults.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        id now = pfbProbeValue(store, key);
        NSString* text = pfbProbeText(now);
        none += now ? 0 : 1;
        NSString* before = gProbeSeen[key];
        gProbeSeen[key] = text;
        if (before) {
            if (![before isEqualToString:text]) {
                [changed addObject:[NSString stringWithFormat:@"%@ %@ -> %@", key, before, text]];
            }
            continue;
        }
        if (!now || pfbProbeSame(now, gProbeDefaults[key])) {
            continue;
        }
        NSString* item = [NSString stringWithFormat:@"%@ = %@ (IPA %@)%@", key, text, pfbProbeText(gProbeDefaults[key]),
                                                    pfbProbeTweakAnswers(key) ? @" [tweak answers]" : @""];
        [pfbProbeWatched(key) ? watched : others addObject:item];
    }
    if (first) {
        pfbProbe(@"probe switches", [NSString stringWithFormat:@"%@ %@: read through %@, %lu switches in the IPA, %lu without a value, %lu differ",
                                                             pfbProbeNow(), moment, NSStringFromSelector(gProbeReader),
                                                             (unsigned long)gProbeDefaults.count, (unsigned long)none,
                                                             (unsigned long)(watched.count + others.count)]);
        pfbProbeList(@"probe switches", @"differ, tab bar, glass and navigation:", watched.count ? watched : @[@"none"]);
        pfbProbeList(@"probe switches, others", @"differ, all others:", others.count ? others : @[@"none"]);
    } else if (changed.count) {
        pfbProbeList(@"probe switches, changes", [NSString stringWithFormat:@"%@ %@ (store %lu seen):", pfbProbeNow(), moment,
                                                                                       (unsigned long)gProbeStores],
                     changed);
    } else {
        pfbProbe(@"probe switches, changes", [NSString stringWithFormat:@"%@ %@: no change (store %lu seen)", pfbProbeNow(), moment,
                                                                      (unsigned long)gProbeStores]);
    }
}

static UIView* pfbProbeFirst(UIView* root, Class cls, NSUInteger depth) {
    NSMutableArray<UIView*>* queue = [NSMutableArray arrayWithObject:root];
    NSMutableArray<NSNumber*>* depths = [NSMutableArray arrayWithObject:@0];
    for (NSUInteger index = 0; index < queue.count; index++) {
        UIView* view = queue[index];
        if (view != root && [view isKindOfClass:cls]) {
            return view;
        }
        if ([depths[index] unsignedIntegerValue] < depth) {
            for (UIView* child in view.subviews) {
                [queue addObject:child];
                [depths addObject:@([depths[index] unsignedIntegerValue] + 1)];
            }
        }
    }
    return nil;
}

// A stack's applied configuration (top bar byte, tab bar byte, style word) and its collapse.
static NSString* pfbProbeStack(UIViewController* stack) {
    Ivar applied = class_getInstanceVariable([stack class], "appliedConfiguration");
    Ivar lazy = class_getInstanceVariable([stack class], "$__lazy_storage_$_collapseEngine");
    NSMutableString* text = [NSMutableString stringWithFormat:@"%@ on %@", NSStringFromClass([stack class]),
                                                              NSStringFromClass([((UINavigationController*)stack).topViewController class])];
    if (applied) {
        const uint8_t* bytes = (const uint8_t*)(__bridge void*)stack + ivar_getOffset(applied);
        uintptr_t style = 0;
        memcpy(&style, bytes + 8, sizeof(style));
        [text appendFormat:@": top byte %u, tab byte %u, style %lu", bytes[0], bytes[1], (unsigned long)style];
    }
    if (lazy) {
        void* engine = NULL;
        memcpy(&engine, (const uint8_t*)(__bridge void*)stack + ivar_getOffset(lazy), sizeof(engine));
        Ivar progress = engine ? class_getInstanceVariable(object_getClass((__bridge id)engine), "collapseProgress") : NULL;
        if (progress) {
            double values[2] = {0, 0};
            memcpy(values, (const uint8_t*)engine + ivar_getOffset(progress), sizeof(values));
            [text appendFormat:@", collapse top %.2f tab %.2f", values[0], values[1]];
        } else {
            [text appendString:engine ? @", collapse engine unread" : @", no collapse engine yet"];
        }
    }
    return text;
}

static NSArray<UIWindow*>* pfbProbeWindows(void) {
    NSMutableArray<UIWindow*>* windows = [NSMutableArray array];
    for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            [windows addObjectsFromArray:((UIWindowScene*)scene).windows];
        }
    }
    return windows;
}

// The screen in front: the deepest shown child, past navigation stacks and presentations.
static UIViewController* pfbProbeFront(void) {
    UIViewController* front = nil;
    for (UIWindow* window in pfbProbeWindows()) {
        if (window.isKeyWindow) {
            front = window.rootViewController;
        }
    }
    for (NSUInteger hops = 0; front && hops < 30; hops++) {
        UIViewController* next = front.presentedViewController;
        if (!next && [front isKindOfClass:[UINavigationController class]]) {
            next = ((UINavigationController*)front).topViewController;
        }
        if (!next) {
            for (UIViewController* child in front.childViewControllers.reverseObjectEnumerator) {
                if (child.isViewLoaded && child.view.window && !child.view.hidden) {
                    next = child;
                    break;
                }
            }
        }
        if (!next) {
            break;
        }
        front = next;
    }
    return front;
}

static NSArray<NSString*>* pfbProbeStacks(void) {
    Class stackClass = NSClassFromString(@"XNAVNavigationController");
    NSMutableArray<NSString*>* found = [NSMutableArray array];
    for (UIWindow* window in pfbProbeWindows()) {
        NSMutableArray<UIViewController*>* queue = [NSMutableArray array];
        if (window.rootViewController) {
            [queue addObject:window.rootViewController];
        }
        for (NSUInteger index = 0; index < queue.count && index < 300; index++) {
            UIViewController* controller = queue[index];
            if (stackClass && [controller isKindOfClass:stackClass] && controller.isViewLoaded && controller.view.window &&
                !controller.view.hidden && found.count < 4) {
                [found addObject:pfbProbeStack(controller)];
            }
            [queue addObjectsFromArray:controller.childViewControllers];
            if (controller.presentedViewController) {
                [queue addObject:controller.presentedViewController];
            }
        }
    }
    return found;
}

// Every instance variable of an object and its superclasses up to UIKit's or NSObject, by name
// and first bytes, the eight bytes also read as a double.
static NSString* pfbProbeIvars(id object) {
    NSMutableArray<NSString*>* items = [NSMutableArray array];
    size_t size = class_getInstanceSize(object_getClass(object));
    for (Class cls = object_getClass(object); cls && cls != [UIView class] && cls != [UIViewController class] &&
                                              cls != [NSObject class];
         cls = class_getSuperclass(cls)) {
        unsigned count = 0;
        Ivar* ivars = class_copyIvarList(cls, &count);
        for (unsigned index = 0; index < count; index++) {
            const char* name = ivar_getName(ivars[index]);
            ptrdiff_t offset = ivar_getOffset(ivars[index]);
            const uint8_t* bytes = (const uint8_t*)(__bridge void*)object + offset;
            NSMutableString* hex = [NSMutableString string];
            for (ptrdiff_t byte = 0; byte < 8 && offset + byte < (ptrdiff_t)size; byte++) {
                [hex appendFormat:@"%02x", bytes[byte]];
            }
            double number = 0;
            if (offset + 8 <= (ptrdiff_t)size) {
                memcpy(&number, bytes, sizeof(number));
            }
            BOOL readable = isfinite(number) && fabs(number) < 100000 && (number == 0 || fabs(number) > 0.000001);
            [items addObject:[NSString stringWithFormat:@"%s=%@%@", name ?: "?", hex,
                                                        readable ? [NSString stringWithFormat:@"(%g)", number] : @""]];
        }
        free(ivars);
    }
    return [items componentsJoinedByString:@" "];
}

static int pfbProbeCompare(const void* left, const void* right) {
    uintptr_t a = *(const uintptr_t*)left, b = *(const uintptr_t*)right;
    return a < b ? -1 : a > b;
}

// A pointer is read as an object only when it starts a heap block whose class is registered.
static BOOL pfbProbeIsObject(const void* pointer) {
    static uintptr_t* classes;
    static unsigned count;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      Class* list = objc_copyClassList(&count);
      classes = malloc(sizeof(uintptr_t) * (count ?: 1));
      for (unsigned index = 0; index < count; index++) {
          classes[index] = (uintptr_t)(__bridge void*)list[index];
      }
      free(list);
      qsort(classes, count, sizeof(uintptr_t), pfbProbeCompare);
    });
    if (!pointer || ((uintptr_t)pointer & 7) || !malloc_zone_from_ptr(pointer)) {
        return NO;
    }
    uintptr_t cls = (uintptr_t)(__bridge void*)object_getClass((__bridge id)pointer);
    return bsearch(&cls, classes, count, sizeof(uintptr_t), pfbProbeCompare) != NULL;
}

// The object held in an instance variable, or the variable's first bytes when it holds none.
static id pfbProbeHeld(id owner, const char* name, NSString** bytes) {
    Ivar ivar = owner ? class_getInstanceVariable(object_getClass(owner), name) : NULL;
    if (!ivar) {
        *bytes = @"no such variable";
        return nil;
    }
    const uint8_t* start = (const uint8_t*)(__bridge void*)owner + ivar_getOffset(ivar);
    void* pointer = NULL;
    memcpy(&pointer, start, sizeof(pointer));
    if (pfbProbeIsObject(pointer)) {
        return (__bridge id)pointer;
    }
    size_t size = class_getInstanceSize(object_getClass(owner));
    NSMutableString* hex = [NSMutableString stringWithString:@"not an object, bytes "];
    for (ptrdiff_t byte = 0; byte < 48 && ivar_getOffset(ivar) + byte < (ptrdiff_t)size; byte++) {
        [hex appendFormat:@"%02x", start[byte]];
    }
    *bytes = hex;
    return nil;
}

static BOOL pfbProbeHasCoordinator(UIResponder* responder) {
    return [responder isKindOfClass:[UIViewController class]] &&
           class_getInstanceVariable(object_getClass(responder), "accessoryCoordinator") != NULL;
}

// The controller is looked for above the bar, then through every window's controllers.
static UIViewController* pfbProbeTabController(UIView* bar) {
    UIResponder* responder = bar;
    for (NSUInteger hops = 0; responder && hops < 80; hops++, responder = responder.nextResponder) {
        if (pfbProbeHasCoordinator(responder)) {
            return (UIViewController*)responder;
        }
    }
    for (UIWindow* window in pfbProbeWindows()) {
        NSMutableArray<UIViewController*>* queue = [NSMutableArray array];
        if (window.rootViewController) {
            [queue addObject:window.rootViewController];
        }
        for (NSUInteger index = 0; index < queue.count && index < 400; index++) {
            UIViewController* controller = queue[index];
            if (pfbProbeHasCoordinator(controller)) {
                return controller;
            }
            [queue addObjectsFromArray:controller.childViewControllers];
            if (controller.presentedViewController) {
                [queue addObject:controller.presentedViewController];
            }
        }
    }
    return nil;
}

// Twitter's tab bar controller above the bar, with its collapse driver and accessory coordinator.
static void pfbProbeControllerState(UIView* bar, BOOL folded) {
    UIViewController* controller = pfbProbeTabController(bar);
    NSString* state = folded ? @"folded" : @"full";
    if (!controller) {
        pfbProbe(@"probe tab bar", [NSString stringWithFormat:@"%@ no controller with an accessory coordinator found", pfbProbeNow()]);
        return;
    }
    pfbProbe(@"probe tab bar", [NSString stringWithFormat:@"%@ %@ while %@: %@", pfbProbeNow(), NSStringFromClass([controller class]), state,
                                                        pfbProbeIvars(controller)]);
    for (NSString* name in @[@"$__lazy_storage_$_collapseDriver", @"accessoryCoordinator"]) {
        NSString* bytes = nil;
        id held = pfbProbeHeld(controller, name.UTF8String, &bytes);
        pfbProbe(@"probe tab bar", [NSString stringWithFormat:@"%@ %@ (%@) while %@: %@", pfbProbeNow(), name,
                                                            held ? NSStringFromClass(object_getClass(held)) : @"-", state,
                                                            held ? pfbProbeIvars(held) : bytes]);
    }
}

static UIView* pfbProbeGlass(UIView* bar) {
    Class glassClass = NSClassFromString(@"XDSGlass");
    return glassClass ? pfbProbeFirst(bar, glassClass, 4) : nil;
}

// Every shown tab bar in every window, the key window's first.
static NSArray<UIView*>* pfbProbeBars(void) {
    Class barClass = NSClassFromString(@"_TtC11XNavigation10TabBarView");
    NSMutableArray<UIView*>* bars = [NSMutableArray array];
    for (UIWindow* window in pfbProbeWindows()) {
        NSMutableArray<UIView*>* queue = [NSMutableArray arrayWithObject:window];
        for (NSUInteger index = 0; barClass && index < queue.count && index < 20000; index++) {
            UIView* view = queue[index];
            if ([view isKindOfClass:barClass]) {
                if (!view.hidden) {
                    [bars insertObject:view atIndex:window.isKeyWindow ? 0 : bars.count];
                }
                continue;
            }
            [queue addObjectsFromArray:view.subviews];
        }
    }
    return bars;
}

// The bar in the key window, looked up again every 10 s, or every 2 s while none is shown.
static UIView* pfbProbeFindBar(void) {
    UIView* bar = gProbeBar;
    BOOL live = bar.window.isKeyWindow && !bar.hidden;
    CFTimeInterval now = CACurrentMediaTime();
    if (now - gProbeLastSearch < (live ? 10 : 2)) {
        return live ? bar : nil;
    }
    gProbeLastSearch = now;
    NSArray<UIView*>* bars = pfbProbeBars();
    UIView* chosen = bars.firstObject;
    if (chosen && chosen != bar) {
        gProbeBar = chosen;
        gProbeBarsFound++;
        if (gProbeBarsFound <= 10) {
            NSMutableArray<NSString*>* items = [NSMutableArray array];
            for (UIView* each in bars) {
                UIView* glass = pfbProbeGlass(each);
                [items addObject:[NSString stringWithFormat:@"%p in %@%@, glass %.0fx%.0f", each, NSStringFromClass([each.window class]),
                                                            each.window.isKeyWindow ? @" (key)" : @"", glass.bounds.size.width,
                                                            glass.bounds.size.height]];
            }
            pfbProbe(@"probe tab bar", [NSString stringWithFormat:@"%@ watching bar %lu of %lu shown: %@", pfbProbeNow(),
                                                                (unsigned long)gProbeBarsFound, (unsigned long)bars.count,
                                                                [items componentsJoinedByString:@"; "]]);
        }
    }
    return chosen;
}

static void pfbProbeStatus(NSString* moment) {
    UIView* bar = gProbeBar;
    pfbProbe(@"probe tab bar", [NSString stringWithFormat:@"%@ %@: %lu checks, bar %@, glass %@, state %@, %lu folds and unfolds, %lu bars found",
                                                        pfbProbeNow(), moment, (unsigned long)gProbeTicks,
                                                        bar.window.isKeyWindow ? @"in the key window" : (bar.window ? @"in another window" : @"not shown"), gProbeLastGlass,
                                                        gProbeFolded < 0 ? @"unread" : (gProbeFolded ? @"folded" : @"full"),
                                                        (unsigned long)gProbeTransitions, (unsigned long)gProbeBarsFound]);
}

static void pfbProbeCheckBar(NSString* why) {
    gProbeTicks++;
    UIView* bar = pfbProbeFindBar();
    if (!bar.window) {
        return;
    }
    UIView* glass = pfbProbeGlass(bar);
    if (!glass) {
        gProbeLastGlass = @"none in the bar";
        return;
    }
    CGRect frame = [glass convertRect:glass.bounds toView:nil];
    gProbeLastGlass = [NSString stringWithFormat:@"%.0fx%.0f", frame.size.width, frame.size.height];
    NSInteger folded = frame.size.width < 100 ? 1 : 0;
    if (folded == gProbeFolded) {
        return;
    }
    gProbeFolded = folded;
    gProbeTransitions++;
    Class accessoryClass = NSClassFromString(@"_TtC11XNavigation23TabBarAccessoryHostView");
    UIView* accessory = accessoryClass ? pfbProbeFirst(bar.window, accessoryClass, 40) : nil;
    UIViewController* front = pfbProbeFront();
    pfbProbe(@"probe tab bar", [NSString stringWithFormat:@"%@ %@ (%@): glass %.0fx%.0f at %.0f,%.0f, bar %.0f wide; accessory %@; front %@; stacks: %@",
                                                        pfbProbeNow(), folded ? @"FOLDED" : @"full", why, frame.size.width, frame.size.height,
                                                        frame.origin.x, frame.origin.y, bar.bounds.size.width,
                                                        accessory && !accessory.hidden && accessory.alpha > 0.01 ? @"shown" : @"absent",
                                                        NSStringFromClass([front class]), [pfbProbeStacks() componentsJoinedByString:@" | "]]);
    if (gProbeDumps < 6) {
        gProbeDumps++;
        pfbProbe(@"probe tab bar", [NSString stringWithFormat:@"%@ ivars of %@ while %@: %@", pfbProbeNow(), NSStringFromClass([bar class]),
                                                            folded ? @"folded" : @"full", pfbProbeIvars(bar)]);
        if (accessory) {
            pfbProbe(@"probe tab bar", [NSString stringWithFormat:@"%@ ivars of %@ while %@: %@", pfbProbeNow(), NSStringFromClass([accessory class]),
                                                                folded ? @"folded" : @"full", pfbProbeIvars(accessory)]);
        }
        pfbProbeControllerState(bar, folded);
    }
    if (gProbeTransitions <= 20) {
        pfbProbeSwitches(folded ? @"at a fold" : @"at an unfold");
    }
}

static void pfbProbeLoadDefaults(void) {
    NSString* path = [NSBundle.mainBundle pathForResource:@"fs_embedded_defaults_production" ofType:@"json"];
    NSData* data = path ? [NSData dataWithContentsOfFile:path] : nil;
    id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    id config = [json isKindOfClass:[NSDictionary class]] ? json[@"default"] : nil;
    config = [config isKindOfClass:[NSDictionary class]] ? config[@"config"] : nil;
    NSMutableDictionary<NSString*, id>* defaults = [NSMutableDictionary dictionary];
    if ([config isKindOfClass:[NSDictionary class]]) {
        [config enumerateKeysAndObjectsUsingBlock:^(id key, id entry, __unused BOOL* stop) {
          if ([key isKindOfClass:[NSString class]] && [entry isKindOfClass:[NSDictionary class]] && entry[@"value"]) {
              defaults[key] = entry[@"value"];
          }
        }];
    }
    gProbeDefaults = defaults;
}

// A store asked for the first time becomes the one read, so a store Twitter replaces is followed.
%hook TFSFeatureSwitches

- (BOOL)boolForKey:(NSString*)key {
    void* me = (__bridge void*)self;
    if (me != gProbeStorePointer) {
        os_unfair_lock_lock(&gProbeLock);
        BOOL known = NO;
        for (NSUInteger index = 0; index < MIN(gProbeStores, (NSUInteger)8); index++) {
            known = known || gProbeStoresSeen[index] == me;
        }
        if (!known) {
            if (gProbeStores < 8) {
                gProbeStoresSeen[gProbeStores] = me;
            }
            gProbeStores++;
            gProbeSwitches = self;
            gProbeStorePointer = me;
        }
        os_unfair_lock_unlock(&gProbeLock);
    }
    return %orig;
}

%end

%ctor {
    gProbeStart = CACurrentMediaTime();
    gProbeSeen = [NSMutableDictionary dictionary];
    %init;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      pfbProbeLoadDefaults();
      id store = pfbProbeStore();
      SEL reader = NSSelectorFromString(@"_valueForKey:");
      gProbeReader = [store respondsToSelector:reader] ? reader : NSSelectorFromString(@"featureSwitchValueForKey:");
      if (store && gProbeDefaults.count) {
          id sample = nil;
          @try {
              sample = ((id (*)(id, SEL, id))objc_msgSend)(store, gProbeReader, @"ios_liquid_glass_xnc2_disabled");
          } @catch (__unused NSException* exception) {
          }
          id unwrapped = pfbProbeUnwrap(sample);
          pfbProbe(@"probe switches", [NSString stringWithFormat:@"store %@, sample reading of ios_liquid_glass_xnc2_disabled: %@ (%@, read as %@)",
                                                               NSStringFromClass([store class]), pfbProbeText(unwrapped),
                                                               sample ? NSStringFromClass([sample class]) : @"nil",
                                                               unwrapped ? NSStringFromClass([unwrapped class]) : @"nil"]);
          if (sample && !pfbProbePlain(sample)) {
              pfbProbe(@"probe switches", [NSString stringWithFormat:@"members of %@: %@", NSStringFromClass(object_getClass(sample)),
                                                                   pfbProbeMembers(object_getClass(sample))]);
          }
      }
      pfbProbeSwitches(@"after launch");
    });
    // The bar is checked twice a second, scrolling included.
    NSTimer* timer = [NSTimer timerWithTimeInterval:0.5 repeats:YES block:^(__unused NSTimer* each) {
      pfbProbeCheckBar(@"timer");
    }];
    dispatch_async(dispatch_get_main_queue(), ^{
      [NSRunLoop.mainRunLoop addTimer:timer forMode:NSRunLoopCommonModes];
    });
    for (NSNumber* delay in @[@20, @90, @300, @600, @900, @1200, @1800]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
          NSString* moment = [NSString stringWithFormat:@"at %@ s", delay];
          pfbProbeStatus(moment);
          if (delay.integerValue > 20) {
              pfbProbeSwitches(moment);
          }
        });
    }
}
