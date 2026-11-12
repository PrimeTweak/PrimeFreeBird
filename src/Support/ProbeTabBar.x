// Probe for the tab bar that folds on 12.42.1: every switch whose value differs from the IPA's
// defaults (and when one changes), each fold and unfold of Twitter's tab bar with its navigation
// state, and the names in Twitter's navigation that speak of folding. Removed once read.

#import <QuartzCore/QuartzCore.h>
#import <mach-o/dyld.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "Support/HookHelpers.h"

static CFTimeInterval gProbeStart;
static id gProbeSwitches;
static NSDictionary<NSString*, id>* gProbeDefaults;
static NSMutableDictionary<NSString*, NSString*>* gProbeSeen;
static SEL gProbeReader;
static __weak UIView* gProbeBar;
static NSInteger gProbeFolded = -1;
static NSUInteger gProbeDumps;

static NSString* pfbProbeNow(void) {
    return [NSString stringWithFormat:@"+%.1f s", CACurrentMediaTime() - gProbeStart];
}

static void pfbProbe(NSString* topic, NSString* line) {
    PFBCompatMeasure(topic, line, 80);
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

// The value in Twitter's store, read past the tweak's answers so no option is marked as seen.
static id pfbProbeValue(NSString* key) {
    id value = nil;
    @try {
        value = ((id (*)(id, SEL, id))objc_msgSend)(gProbeSwitches, gProbeReader, key);
    } @catch (__unused NSException* exception) {
        return nil;
    }
    if (value && ![value isKindOfClass:[NSNumber class]] && ![value isKindOfClass:[NSString class]] &&
        ![value isKindOfClass:[NSArray class]] && ![value isKindOfClass:[NSDictionary class]] &&
        [value respondsToSelector:@selector(value)]) {
        value = [value valueForKey:@"value"];
    }
    return value;
}

// The first reading lists every switch Twitter holds differently from the IPA's defaults; the
// later ones only what changed since.
static void pfbProbeSwitches(NSString* moment) {
    if (!gProbeSwitches || !gProbeDefaults.count) {
        pfbProbe(@"probe switches", [NSString stringWithFormat:@"%@ %@: switches not read yet (store %@, defaults %lu)", pfbProbeNow(), moment,
                                                             gProbeSwitches ? @"found" : @"missing", (unsigned long)gProbeDefaults.count]);
        return;
    }
    BOOL first = gProbeSeen.count == 0;
    NSMutableArray<NSString*>* watched = [NSMutableArray array];
    NSMutableArray<NSString*>* others = [NSMutableArray array];
    NSMutableArray<NSString*>* changed = [NSMutableArray array];
    NSUInteger none = 0;
    for (NSString* key in [gProbeDefaults.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        id now = pfbProbeValue(key);
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
        pfbProbeList(@"probe switches", @"differ, all others:", others.count ? others : @[@"none"]);
    } else if (changed.count) {
        pfbProbeList(@"probe switches", [NSString stringWithFormat:@"%@ %@: changed since the last reading:", pfbProbeNow(), moment], changed);
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

// Every instance variable of a view and its superclasses up to UIView, by name and first bytes.
static NSString* pfbProbeIvars(UIView* view) {
    NSMutableArray<NSString*>* items = [NSMutableArray array];
    size_t size = class_getInstanceSize(object_getClass(view));
    for (Class cls = object_getClass(view); cls && cls != [UIView class]; cls = class_getSuperclass(cls)) {
        unsigned count = 0;
        Ivar* ivars = class_copyIvarList(cls, &count);
        for (unsigned index = 0; index < count; index++) {
            const char* name = ivar_getName(ivars[index]);
            ptrdiff_t offset = ivar_getOffset(ivars[index]);
            const uint8_t* bytes = (const uint8_t*)(__bridge void*)view + offset;
            NSMutableString* hex = [NSMutableString string];
            for (ptrdiff_t byte = 0; byte < 8 && offset + byte < (ptrdiff_t)size; byte++) {
                [hex appendFormat:@"%02x", bytes[byte]];
            }
            [items addObject:[NSString stringWithFormat:@"%s=%@", name ?: "?", hex]];
        }
        free(ivars);
    }
    return [items componentsJoinedByString:@" "];
}

static void pfbProbeCheckBar(NSString* why) {
    UIView* bar = gProbeBar;
    Class glassClass = NSClassFromString(@"XDSGlass");
    if (!bar.window || !glassClass) {
        return;
    }
    UIView* glass = pfbProbeFirst(bar, glassClass, 4);
    if (!glass) {
        return;
    }
    CGRect frame = [glass convertRect:glass.bounds toView:nil];
    NSInteger folded = frame.size.width < 100 ? 1 : 0;
    if (folded == gProbeFolded) {
        return;
    }
    gProbeFolded = folded;
    Class accessoryClass = NSClassFromString(@"_TtC11XNavigation23TabBarAccessoryHostView");
    UIView* accessory = accessoryClass ? pfbProbeFirst(bar.window, accessoryClass, 40) : nil;
    UIViewController* front = pfbProbeFront();
    pfbProbe(@"probe tab bar", [NSString stringWithFormat:@"%@ %@ (%@): glass %.0fx%.0f at %.0f,%.0f, bar %.0f wide; accessory %@; front %@; stacks: %@",
                                                        pfbProbeNow(), folded ? @"FOLDED" : @"full", why, frame.size.width, frame.size.height,
                                                        frame.origin.x, frame.origin.y, bar.bounds.size.width,
                                                        accessory && !accessory.hidden && accessory.alpha > 0.01 ? @"shown" : @"absent",
                                                        NSStringFromClass([front class]), [pfbProbeStacks() componentsJoinedByString:@" | "]]);
    if (gProbeDumps < 4) {
        gProbeDumps++;
        UIView* placement = bar.superview;
        pfbProbe(@"probe tab bar", [NSString stringWithFormat:@"%@ ivars of %@ while %@: %@", pfbProbeNow(), NSStringFromClass([bar class]),
                                                            folded ? @"folded" : @"full", pfbProbeIvars(bar)]);
        if (placement) {
            pfbProbe(@"probe tab bar", [NSString stringWithFormat:@"%@ ivars of %@ while %@: %@", pfbProbeNow(), NSStringFromClass([placement class]),
                                                                folded ? @"folded" : @"full", pfbProbeIvars(placement)]);
        }
    }
    pfbProbeSwitches(folded ? @"at a fold" : @"at an unfold");
}

// Selectors and instance variables of Twitter's navigation whose names speak of folding.
static void pfbProbeNavigationNames(void) {
    NSString* bundle = NSBundle.mainBundle.bundlePath;
    NSRegularExpression* words = [NSRegularExpression regularExpressionWithPattern:@"collaps|minimi|compact|accessor|fold|expand|shrink|morph|pinned|hidemode|hide_mode"
                                                                           options:NSRegularExpressionCaseInsensitive
                                                                             error:nil];
    BOOL (^speaks)(NSString*) = ^BOOL(NSString* name) {
      return [words firstMatchInString:name options:0 range:NSMakeRange(0, name.length)] != nil;
    };
    NSUInteger classes = 0;
    for (uint32_t image = 0; image < _dyld_image_count(); image++) {
        const char* path = _dyld_get_image_name(image);
        if (!path || ![@(path) hasPrefix:bundle]) {
            continue;
        }
        unsigned count = 0;
        const char** names = objc_copyClassNamesForImage(path, &count);
        for (unsigned index = 0; index < count; index++) {
            NSString* className = @(names[index]);
            if (![className containsString:@"XNavigation"] && ![className hasPrefix:@"XNAV"]) {
                continue;
            }
            classes++;
            Class cls = objc_getClass(names[index]);
            NSMutableArray<NSString*>* found = [NSMutableArray array];
            for (Class side = cls; side; side = (side == cls ? object_getClass(cls) : Nil)) {
                unsigned methodCount = 0;
                Method* methods = class_copyMethodList(side, &methodCount);
                for (unsigned item = 0; item < methodCount; item++) {
                    NSString* selector = NSStringFromSelector(method_getName(methods[item]));
                    if (speaks(selector)) {
                        [found addObject:[(side == cls ? @"-" : @"+") stringByAppendingString:selector]];
                    }
                }
                free(methods);
            }
            unsigned ivarCount = 0;
            Ivar* ivars = cls ? class_copyIvarList(cls, &ivarCount) : NULL;
            for (unsigned item = 0; item < ivarCount; item++) {
                NSString* name = @(ivar_getName(ivars[item]) ?: "");
                if (speaks(name)) {
                    [found addObject:[@"ivar " stringByAppendingString:name]];
                }
            }
            free(ivars);
            if (found.count) {
                pfbProbeList(@"probe navigation", [className stringByAppendingString:@":"], found);
            }
        }
        free(names);
    }
    pfbProbe(@"probe navigation", [NSString stringWithFormat:@"%lu classes of Twitter's navigation read", (unsigned long)classes]);
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

%hook TFSFeatureSwitches

- (BOOL)boolForKey:(NSString*)key {
    if (!gProbeSwitches) {
        gProbeSwitches = self;
    }
    return %orig;
}

%end

%hook _TtC11XNavigation10TabBarView

- (void)layoutSubviews {
    %orig;
    gProbeBar = (UIView*)self;
    pfbProbeCheckBar(@"layout");
}

%end

%ctor {
    gProbeStart = CACurrentMediaTime();
    gProbeSeen = [NSMutableDictionary dictionary];
    %init;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      pfbProbeLoadDefaults();
      SEL reader = NSSelectorFromString(@"_valueForKey:");
      gProbeReader = [gProbeSwitches respondsToSelector:reader] ? reader : NSSelectorFromString(@"featureSwitchValueForKey:");
      if (gProbeSwitches && gProbeDefaults.count) {
          id sample = nil;
          @try {
              sample = ((id (*)(id, SEL, id))objc_msgSend)(gProbeSwitches, gProbeReader, @"ios_liquid_glass_xnc2_disabled");
          } @catch (__unused NSException* exception) {
          }
          pfbProbe(@"probe switches", [NSString stringWithFormat:@"store %@, sample reading of ios_liquid_glass_xnc2_disabled: %@ (%@)",
                                                               NSStringFromClass([gProbeSwitches class]), pfbProbeText(pfbProbeValue(@"ios_liquid_glass_xnc2_disabled")),
                                                               sample ? NSStringFromClass([sample class]) : @"nil"]);
      }
      pfbProbeSwitches(@"after launch");
      pfbProbeNavigationNames();
      // The bar is checked twice a second too, for a fold that animates without a layout.
      [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(__unused NSTimer* timer) {
        pfbProbeCheckBar(@"timer");
      }];
    });
    for (NSNumber* delay in @[@90, @300]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
          pfbProbeSwitches([NSString stringWithFormat:@"at %@ s", delay]);
        });
    }
}
