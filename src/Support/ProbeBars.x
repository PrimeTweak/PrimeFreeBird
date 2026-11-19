// Probe for Twitter 12.45, removed once read. Notifications: the room under the bar held at Chat's
// 60 pt, or else the list moved 16 pt down. Always visible: the collapse engine read as it changes,
// and the tab bar's policy taken from a stack whose bar stays full.

#import "Support/HookHelpers.h"
#import <malloc/malloc.h>
#import <objc/message.h>
#import <objc/runtime.h>

@interface PFBNotifSearchBar : UIView
@end

@interface _TtCC11XNavigation14CollapseEngine14ScrollObserver : NSObject
- (void)handlePan:(UIPanGestureRecognizer*)recognizer;
@end

static NSString* const kPFBProbeRoomTopic = @"probe search room";
static NSString* const kPFBProbeBarTopic = @"probe always visible";
static NSUInteger gPFBProbeSeq;

static void PFBProbeLine(NSString* topic, NSString* line, NSUInteger cap) {
    PFBCompatMeasure(topic, [NSString stringWithFormat:@"%02lu %@", (unsigned long)++gPFBProbeSeq, line], cap);
}

static NSString* PFBProbeName(id object) {
    if (!object) {
        return @"nil";
    }
    NSString* name = NSStringFromClass([object class]);
    NSRange dot = [name rangeOfString:@"." options:NSBackwardsSearch];
    return dot.location == NSNotFound ? name : [name substringFromIndex:dot.location + 1];
}

// The bytes an ivar spans: up to the next ivar of its own class, or to the end of the instance.
static ptrdiff_t PFBProbeSpan(Class cls, Ivar ivar) {
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

// An ivar is read only when it is pointer-sized and points into the heap, so a Swift value stored
// inline is never taken for an object.
static id PFBProbeIvar(id object, const char* name) {
    if (!object) {
        return nil;
    }
    for (Class cls = object_getClass(object); cls; cls = class_getSuperclass(cls)) {
        Ivar found = NULL;
        unsigned int count = 0;
        Ivar* list = class_copyIvarList(cls, &count);
        for (unsigned int i = 0; i < count; i++) {
            if (strcmp(ivar_getName(list[i]) ?: "", name) == 0) {
                found = list[i];
            }
        }
        free(list);
        if (!found) {
            continue;
        }
        if (PFBProbeSpan(cls, found) != (ptrdiff_t)sizeof(void*)) {
            return nil;
        }
        void* raw = *(void**)((uint8_t*)(__bridge void*)object + ivar_getOffset(found));
        if (!raw || ((uintptr_t)raw >> 63) || !malloc_zone_from_ptr(raw)) {
            return nil;
        }
        return (__bridge id)raw;
    }
    return nil;
}

static NSString* PFBProbeHex(const uint8_t* bytes, ptrdiff_t count) {
    NSMutableString* text = [NSMutableString string];
    for (ptrdiff_t i = 0; i < count; i++) {
        [text appendFormat:@"%@%02x", i && i % 8 == 0 ? @" " : @"", bytes[i]];
    }
    return text;
}

static NSString* PFBProbeView(UIView* view) {
    if (!view) {
        return @"none";
    }
    CGRect frame = [view convertRect:view.bounds toView:nil];
    return [NSString stringWithFormat:@"%@ %.1f,%.1f %.1fx%.1f%@", PFBProbeName(view), frame.origin.x, frame.origin.y,
                                      frame.size.width, frame.size.height, view.window ? @"" : @" off screen"];
}

static UIView* PFBProbeFind(UIView* root, NSString* word, NSUInteger depth) {
    if (!root) {
        return nil;
    }
    if ([NSStringFromClass([root class]) containsString:word]) {
        return root;
    }
    if (depth == 0) {
        return nil;
    }
    for (UIView* sub in root.subviews) {
        UIView* found = PFBProbeFind(sub, word, depth - 1);
        if (found) {
            return found;
        }
    }
    return nil;
}

// MARK: - the room under Notifications' bar

static const CGFloat kPFBProbeRoom = 60.0;
static const CGFloat kPFBProbeDrop = 16.0;
static NSLayoutConstraint* gPFBProbeHeight;
static BOOL gPFBProbeHolding;
static CGFloat gPFBProbeTwitterHeight = 44.0;
static BOOL gPFBProbeAsked;
static BOOL gPFBProbeRead;
static BOOL gPFBProbeInsetTry;
static UITableView* gPFBProbeTable;
static CGFloat gPFBProbeInsetBase;
static NSUInteger gPFBProbeHeightSets;
static NSUInteger gPFBProbeInsetSets;

static BOOL PFBProbeOwns(id segmented) {
    SEL dataSource = NSSelectorFromString(@"dataSource");
    Class notifications = NSClassFromString(@"T1NotificationsViewController");
    return [PFBSettings boolForKey:@"unified_notifications"] && notifications && [segmented respondsToSelector:dataSource] &&
           [((id (*)(id, SEL))objc_msgSend)(segmented, dataSource) isKindOfClass:notifications];
}

// Try A: the row's height constraint held at 60 pt, whatever Twitter sets.
static void PFBProbeHold(id segmented, NSString* when) {
    if (gPFBProbeInsetTry || !PFBProbeOwns(segmented)) {
        return;
    }
    NSLayoutConstraint* height = PFBProbeIvar(segmented, "barContainerHeightConstraint");
    if (![height isKindOfClass:[NSLayoutConstraint class]]) {
        PFBProbeLine(kPFBProbeRoomTopic, [NSString stringWithFormat:@"A at %@: no row height constraint", when], 40);
        return;
    }
    if (height != gPFBProbeHeight) {
        PFBProbeLine(kPFBProbeRoomTopic, [NSString stringWithFormat:@"A at %@: row height %+.1f p%.0f held at 60", when,
                                                                    height.constant, height.priority],
                     40);
        gPFBProbeHeight = height;
    }
    gPFBProbeHolding = YES;
    if (fabs(height.constant - kPFBProbeRoom) > 0.1) {
        height.constant = kPFBProbeRoom;
    }
}

static UITableView* PFBProbeList(UIView* root) {
    if ([root isKindOfClass:[UITableView class]] && root.window && !root.hidden) {
        return (UITableView*)root;
    }
    for (UIView* sub in root.subviews) {
        UITableView* found = PFBProbeList(sub);
        if (found) {
            return found;
        }
    }
    return nil;
}

static void PFBProbeAskNavigation(UIViewController* screen) {
    SEL update = NSSelectorFromString(@"xnav_setNeedsNavigationConfigurationUpdateAnimated:");
    if ([screen respondsToSelector:update]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(screen, update, NO);
    }
}

// The room, the row, the field and the list as they stand, then where a tap near the field's
// bottom lands and which of its holders clip. YES when the room ends and the list starts at 176 pt.
static BOOL PFBProbeReadRoom(UIViewController* screen, NSString* label) {
    id segmented = PFBProbeIvar(screen, "$__lazy_storage_$_segmentedController");
    NSLayoutConstraint* height = PFBProbeIvar(segmented, "barContainerHeightConstraint");
    UIView* zone = PFBProbeFind(screen.view, @"AccessoryStackView", 2);
    UIView* row = PFBProbeFind(zone, @"LegacySegmentedTabBarView", 3);
    UIView* bar = PFBProbeFind(row, @"PFBNotifSearchBar", 1);
    UITextField* field = (UITextField*)PFBProbeFind(bar, @"UITextField", 1);
    UITableView* list = PFBProbeList(screen.view);
    NSString* top = @"none";
    for (NSLayoutConstraint* c in zone.superview.constraints) {
        if (c.firstItem == zone && c.firstAttribute == NSLayoutAttributeTop) {
            top = [NSString stringWithFormat:@"%+.1f", c.constant];
        }
    }
    NSDictionary* hint = field.attributedPlaceholder.length ? [field.attributedPlaceholder attributesAtIndex:0 effectiveRange:NULL] : nil;
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [[hint[NSForegroundColorAttributeName] resolvedColorWithTraitCollection:field.traitCollection] getRed:&r green:&g blue:&b alpha:&a];
    PFBProbeLine(kPFBProbeRoomTopic,
                 [NSString stringWithFormat:@"%@: row height %@; room %@ top %@; container %@; row %@; field %@ \"%@\" font %@ %.2f "
                                            @"hint %.0f,%.0f,%.0f a%.2f; list %@ inset %.1f adjusted %.1f offset %.1f; safe top %.1f",
                                            label,
                                            height ? [NSString stringWithFormat:@"%+.1f p%.0f", height.constant, height.priority] : @"none",
                                            PFBProbeView(zone), top, PFBProbeView(row.superview), PFBProbeView(row),
                                            PFBProbeView(field), field.placeholder, field.font.fontName, field.font.pointSize,
                                            r * 255, g * 255, b * 255, a, PFBProbeView(list), list.contentInset.top,
                                            list.adjustedContentInset.top, list.contentOffset.y, screen.view.safeAreaInsets.top],
                 40);
    if (field.window) {
        CGRect frame = [field convertRect:field.bounds toView:nil];
        UIView* hit = [field.window hitTest:CGPointMake(CGRectGetMidX(frame), CGRectGetMaxY(frame) - 4.0) withEvent:nil];
        NSMutableArray<NSString*>* clips = [NSMutableArray array];
        for (UIView* holder = bar; holder && holder != zone.superview; holder = holder.superview) {
            [clips addObject:[NSString stringWithFormat:@"%@ %d", PFBProbeName(holder), holder.clipsToBounds || holder.layer.masksToBounds]];
        }
        PFBProbeLine(kPFBProbeRoomTopic, [NSString stringWithFormat:@"%@: a tap 4 pt above the field's bottom reaches %@ (field %d); clips %@",
                                                                    label, PFBProbeName(hit), [hit isDescendantOfView:field],
                                                                    [clips componentsJoinedByString:@", "]],
                     40);
    }
    CGRect room = [zone convertRect:zone.bounds toView:nil];
    return zone.window && CGRectGetMaxY(room) >= 175.0 && list.adjustedContentInset.top >= 175.0;
}

// Try B: the row back to Twitter's height, the list 16 pt lower and the field 8 pt lower.
static void PFBProbeStartInsetTry(UIViewController* screen) {
    gPFBProbeHolding = NO;
    gPFBProbeInsetTry = YES;
    gPFBProbeHeight.constant = gPFBProbeTwitterHeight;
    UITableView* list = PFBProbeList(screen.view);
    gPFBProbeTable = list;
    gPFBProbeInsetBase = list.contentInset.top;
    BOOL atTop = list.contentOffset.y <= -list.adjustedContentInset.top + 0.5;
    UIEdgeInsets insets = list.contentInset;
    insets.top += kPFBProbeDrop;
    list.contentInset = insets;
    if (atTop) {
        [list setContentOffset:CGPointMake(list.contentOffset.x, -list.adjustedContentInset.top) animated:NO];
    }
    [PFBProbeFind(PFBProbeFind(screen.view, @"AccessoryStackView", 2), @"PFBNotifSearchBar", 4) setNeedsLayout];
    PFBProbeAskNavigation(screen);
    PFBProbeLine(kPFBProbeRoomTopic, [NSString stringWithFormat:@"B started: row back to %.1f, list inset %.1f to %.1f",
                                                                gPFBProbeTwitterHeight, gPFBProbeInsetBase, insets.top],
                 40);
}

%hook _TtC10TFNUISwift29LegacySegmentedViewController

- (void)viewDidLoad {
    %orig;
    PFBProbeHold(self, @"load");
}

- (void)viewWillLayoutSubviews {
    %orig;
    if (gPFBProbeHolding) {
        PFBProbeHold(self, @"layout");
    }
}

%end

%hook NSLayoutConstraint

- (void)setConstant:(CGFloat)constant {
    if (gPFBProbeHolding && self == gPFBProbeHeight && fabs(constant - kPFBProbeRoom) > 0.1) {
        if (gPFBProbeHeightSets++ < 4) {
            PFBProbeLine(kPFBProbeRoomTopic, [NSString stringWithFormat:@"A: Twitter set the row height to %.1f, kept at 60", constant], 40);
        }
        gPFBProbeTwitterHeight = constant;
        constant = kPFBProbeRoom;
    }
    %orig(constant);
}

%end

%hook TFNTableView

- (void)setContentInset:(UIEdgeInsets)insets {
    if (gPFBProbeInsetTry && self == gPFBProbeTable) {
        BOOL moved = fabs(insets.top - gPFBProbeInsetBase) < 0.5;
        if (gPFBProbeInsetSets++ < 8) {
            PFBProbeLine(kPFBProbeRoomTopic, [NSString stringWithFormat:@"B: Twitter set the list inset to %.1f%@", insets.top,
                                                                        moved ? @", moved 16 pt" : @""],
                         40);
        }
        insets.top += moved ? kPFBProbeDrop : 0.0;
    }
    %orig(insets);
}

%end

%hook PFBNotifSearchBar

- (void)layoutSubviews {
    %orig;
    UIView* field = PFBProbeFind(self, @"UITextField", 1);
    if (gPFBProbeInsetTry && field) {
        CGRect frame = field.frame;
        frame.origin.y = (CGRectGetHeight(self.bounds) - CGRectGetHeight(frame)) / 2.0 + kPFBProbeDrop / 2.0;
        field.frame = frame;
    }
}

%end

%hook T1NotificationsViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    UIViewController* screen = (UIViewController*)self;
    if (![PFBSettings boolForKey:@"unified_notifications"]) {
        return;
    }
    if (!gPFBProbeAsked && gPFBProbeHolding) {
        gPFBProbeAsked = YES;
        PFBProbeAskNavigation(screen);
        PFBProbeLine(kPFBProbeRoomTopic, @"A: navigation asked to measure the room again", 40);
    }
    if (gPFBProbeRead) {
        PFBProbeReadRoom(screen, gPFBProbeInsetTry ? @"B on a later visit" : @"A on a later visit");
        return;
    }
    gPFBProbeRead = YES;
    __weak UIViewController* weakScreen = screen;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      UIViewController* shown = weakScreen;
      if (!shown.viewIfLoaded.window) {
          return;
      }
      if (!PFBProbeReadRoom(shown, @"A after 1 s")) {
          PFBProbeStartInsetTry(shown);
      }
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (weakScreen.viewIfLoaded.window) {
            PFBProbeReadRoom(weakScreen, gPFBProbeInsetTry ? @"B after 1.5 s" : @"A after 2.5 s");
        }
      });
    });
}

%end

// MARK: - Always visible

static Class gPFBProbeStackClass;
static Class gPFBProbeEngineClass;
static Class gPFBProbeTabBarClass;
static ptrdiff_t gPFBProbeEngineOffset = -1;
static ptrdiff_t gPFBProbeAppliedOffset = -1;
static ptrdiff_t gPFBProbeApplicationsOffset = -1;
static ptrdiff_t gPFBProbePoliciesOffset = -1;
static ptrdiff_t gPFBProbePoliciesSpan;
static ptrdiff_t gPFBProbeProgressOffset = -1;
static ptrdiff_t gPFBProbeTravelOffset = -1;
static ptrdiff_t gPFBProbePendingOffset = -1;
static ptrdiff_t gPFBProbeCollapseOffset = -1;

// The tab bar's policy: the second of two 49-byte policies, at their 56-byte stride.
static const ptrdiff_t kPFBProbeTabPolicy = 56;
static const ptrdiff_t kPFBProbePolicySize = 49;
static const NSUInteger kPFBProbeNotes = 24;
static const NSUInteger kPFBProbeTries = 6;

static ptrdiff_t PFBProbeOffset(Class cls, const char* name, ptrdiff_t* span) {
    Ivar ivar = cls ? class_getInstanceVariable(cls, name) : NULL;
    if (span) {
        *span = ivar ? PFBProbeSpan(cls, ivar) : 0;
    }
    return ivar ? ivar_getOffset(ivar) : -1;
}

static BOOL PFBProbeBarReady(void) {
    static BOOL ready;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      gPFBProbeStackClass = NSClassFromString(@"XNAVNavigationController");
      gPFBProbeEngineClass = NSClassFromString(@"_TtC11XNavigation14CollapseEngine");
      gPFBProbeTabBarClass = NSClassFromString(@"_TtC11XNavigation10TabBarView");
      ptrdiff_t appliedSpan = 0;
      gPFBProbeEngineOffset = PFBProbeOffset(gPFBProbeStackClass, "collapseEngine", NULL);
      gPFBProbeAppliedOffset = PFBProbeOffset(gPFBProbeStackClass, "appliedConfiguration", &appliedSpan);
      gPFBProbeApplicationsOffset = PFBProbeOffset(gPFBProbeStackClass, "configurationApplications", NULL);
      gPFBProbePoliciesOffset = PFBProbeOffset(gPFBProbeEngineClass, "policies", &gPFBProbePoliciesSpan);
      gPFBProbeProgressOffset = PFBProbeOffset(gPFBProbeEngineClass, "collapseProgress", NULL);
      gPFBProbeTravelOffset = PFBProbeOffset(gPFBProbeEngineClass, "hiddenBarTravel", NULL);
      gPFBProbePendingOffset = PFBProbeOffset(gPFBProbeEngineClass, "pendingTarget", NULL);
      gPFBProbeCollapseOffset = PFBProbeOffset(gPFBProbeTabBarClass, "appliedCollapse", NULL);
      ready = gPFBProbeEngineOffset >= 0 && gPFBProbeAppliedOffset >= 0 && gPFBProbePoliciesOffset >= 0 &&
              gPFBProbeProgressOffset >= 0 && gPFBProbePoliciesSpan >= kPFBProbeTabPolicy + kPFBProbePolicySize;
      PFBProbeLine(kPFBProbeBarTopic,
                   [NSString stringWithFormat:@"layout %d: engine @%td, applied @%td span %td, applications @%td, policies @%td span %td, "
                                              @"progress @%td, travel @%td, pending @%td, tab bar collapse @%td",
                                              ready, gPFBProbeEngineOffset, gPFBProbeAppliedOffset, appliedSpan,
                                              gPFBProbeApplicationsOffset, gPFBProbePoliciesOffset, gPFBProbePoliciesSpan,
                                              gPFBProbeProgressOffset, gPFBProbeTravelOffset, gPFBProbePendingOffset,
                                              gPFBProbeCollapseOffset],
                   60);
    });
    return ready;
}

static uint8_t* PFBProbeEngine(UINavigationController* stack) {
    if (!PFBProbeBarReady() || ![stack isKindOfClass:gPFBProbeStackClass]) {
        return NULL;
    }
    void* engine = NULL;
    memcpy(&engine, (const uint8_t*)(__bridge void*)stack + gPFBProbeEngineOffset, sizeof(engine));
    return engine && object_getClass((__bridge id)engine) == gPFBProbeEngineClass ? (uint8_t*)engine : NULL;
}

// A policy holds only plain numbers: each of its first six words is zero or a finite value of
// sane size, never a pointer.
static BOOL PFBProbePlainPolicy(const uint8_t* policy) {
    for (int i = 0; i < 6; i++) {
        double value = 0;
        memcpy(&value, policy + i * 8, sizeof(value));
        if (value != 0.0 && (!isfinite(value) || fabs(value) < 1e-6 || fabs(value) > 1e6)) {
            return NO;
        }
    }
    return YES;
}

// The glass tab bar on screen: its size, its glass and the collapse it applied.
static NSString* PFBProbeTabBar(void) {
    static __weak UIView* known;
    UIView* bar = known.window ? known : nil;
    for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
        if (bar || ![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }
        for (UIWindow* window in ((UIWindowScene*)scene).windows) {
            bar = bar ?: PFBProbeFind(window, @"XNavigation.TabBarView", 14);
        }
    }
    if (![bar isKindOfClass:gPFBProbeTabBarClass]) {
        return @"no tab bar";
    }
    known = bar;
    UIView* glass = PFBProbeFind(bar, @"XDSGlass", 4);
    NSString* collapse = gPFBProbeCollapseOffset >= 0 ? PFBProbeHex((const uint8_t*)(__bridge void*)bar + gPFBProbeCollapseOffset, 32) : @"-";
    return [NSString stringWithFormat:@"bar %.0fx%.0f glass %.0fx%.0f collapse %@", CGRectGetWidth(bar.bounds), CGRectGetHeight(bar.bounds),
                                      CGRectGetWidth(glass.bounds), CGRectGetHeight(glass.bounds), collapse];
}

static NSMapTable* gPFBProbeLastPolicies;
static NSUInteger gPFBProbeLayoutNotes;
static NSUInteger gPFBProbeScrollNotes;
static NSUInteger gPFBProbeTriesWritten;
static NSMutableArray<NSData*>* gPFBProbeCollapsing;
static NSData* gPFBProbeFull;

static NSData* PFBProbeTabPolicy(uint8_t* engine) {
    return [NSData dataWithBytes:engine + gPFBProbePoliciesOffset + kPFBProbeTabPolicy length:kPFBProbePolicySize];
}

// A tab policy seen while the bar is collapsed, or one seen with the bar full after a scroll and
// unlike those, kept for the try.
static void PFBProbeSortPolicy(UINavigationController* stack, uint8_t* engine, double tabProgress, BOOL settled) {
    if (tabProgress > 0.05 && gPFBProbeCollapsing.count < 4) {
        NSData* tab = PFBProbeTabPolicy(engine);
        gPFBProbeCollapsing = gPFBProbeCollapsing ?: [NSMutableArray array];
        if (![gPFBProbeCollapsing containsObject:tab] && PFBProbePlainPolicy(tab.bytes)) {
            [gPFBProbeCollapsing addObject:tab];
            PFBProbeLine(kPFBProbeBarTopic, [NSString stringWithFormat:@"tab policy seen collapsing on %@", PFBProbeName(stack.topViewController)], 60);
        }
    } else if (settled && tabProgress == 0.0 && !gPFBProbeFull && gPFBProbeCollapsing.count) {
        NSData* tab = PFBProbeTabPolicy(engine);
        if (![gPFBProbeCollapsing containsObject:tab] && PFBProbePlainPolicy(tab.bytes)) {
            gPFBProbeFull = tab;
            PFBProbeLine(kPFBProbeBarTopic, [NSString stringWithFormat:@"tab policy seen full after a scroll on %@", PFBProbeName(stack.topViewController)], 60);
        }
    }
}

// One stack's engine: written on a layout pass only when its configuration or policies changed,
// and around each scroll with the tab bar on screen.
static void PFBProbeNoteStack(UINavigationController* stack, NSString* when, BOOL scroll, BOOL settled) {
    uint8_t* engine = PFBProbeEngine(stack);
    if (!engine) {
        return;
    }
    const uint8_t* applied = (const uint8_t*)(__bridge void*)stack + gPFBProbeAppliedOffset;
    const uint8_t* policies = engine + gPFBProbePoliciesOffset;
    double progress[2] = {0, 0};
    memcpy(progress, engine + gPFBProbeProgressOffset, sizeof(progress));
    PFBProbeSortPolicy(stack, engine, progress[1], settled);
    if (!scroll) {
        NSMutableData* signature = [NSMutableData dataWithBytes:applied length:2];
        [signature appendBytes:policies length:gPFBProbePoliciesSpan];
        gPFBProbeLastPolicies = gPFBProbeLastPolicies ?: [NSMapTable weakToStrongObjectsMapTable];
        if ([[gPFBProbeLastPolicies objectForKey:stack] isEqual:signature] || gPFBProbeLayoutNotes >= kPFBProbeNotes) {
            return;
        }
        [gPFBProbeLastPolicies setObject:signature forKey:stack];
        gPFBProbeLayoutNotes++;
    } else if (gPFBProbeScrollNotes++ >= kPFBProbeNotes) {
        return;
    }
    NSInteger applications = 0;
    if (gPFBProbeApplicationsOffset >= 0) {
        memcpy(&applications, (const uint8_t*)(__bridge void*)stack + gPFBProbeApplicationsOffset, sizeof(applications));
    }
    PFBProbeLine(kPFBProbeBarTopic,
                 [NSString stringWithFormat:@"%@ %@ #%ld: applied %02x %02x progress %.3f %.3f travel %@ pending %@ nav %@ | tab %@%@", when,
                                            PFBProbeName(stack.topViewController), (long)applications, applied[0], applied[1], progress[0],
                                            progress[1], gPFBProbeTravelOffset >= 0 ? PFBProbeHex(engine + gPFBProbeTravelOffset, 8) : @"-",
                                            gPFBProbePendingOffset >= 0 ? PFBProbeHex(engine + gPFBProbePendingOffset, 17) : @"-",
                                            PFBProbeHex(policies, kPFBProbeTabPolicy),
                                            PFBProbeHex(policies + kPFBProbeTabPolicy, gPFBProbePoliciesSpan - kPFBProbeTabPolicy),
                                            scroll ? [@"; " stringByAppendingString:PFBProbeTabBar()] : @""],
                 60);
}

// The try: on a stack whose tab policy was seen collapsing, the policy seen with a full bar is
// written in its place while Always visible is on.
static void PFBProbeTryPolicy(UINavigationController* stack, NSString* when) {
    uint8_t* engine = gPFBProbeFull ? PFBProbeEngine(stack) : NULL;
    if (!engine || ![PFBSettings boolForKey:@"no_tab_bar_hiding"] || ![gPFBProbeCollapsing containsObject:PFBProbeTabPolicy(engine)]) {
        return;
    }
    memcpy(engine + gPFBProbePoliciesOffset + kPFBProbeTabPolicy, gPFBProbeFull.bytes, kPFBProbePolicySize);
    if (gPFBProbeTriesWritten++ < kPFBProbeTries) {
        PFBProbeLine(kPFBProbeBarTopic, [NSString stringWithFormat:@"try at %@: full-bar tab policy written on %@", when,
                                                                   PFBProbeName(stack.topViewController)],
                     60);
    }
}

%hook XNAVNavigationController

- (void)viewWillLayoutSubviews {
    %orig;
    UINavigationController* stack = (UINavigationController*)self;
    if (stack.viewIfLoaded.window) {
        PFBProbeNoteStack(stack, @"layout", NO, NO);
        PFBProbeTryPolicy(stack, @"layout");
    }
}

%end

%hook _TtCC11XNavigation14CollapseEngine14ScrollObserver

- (void)handlePan:(UIPanGestureRecognizer*)recognizer {
    UINavigationController* stack = PFBOwningController(recognizer.view).navigationController;
    UIGestureRecognizerState state = recognizer.state;
    if (state == UIGestureRecognizerStateBegan) {
        PFBProbeNoteStack(stack, @"drag on", YES, NO);
        PFBProbeTryPolicy(stack, @"drag");
    }
    %orig;
    if (state == UIGestureRecognizerStateEnded || state == UIGestureRecognizerStateCancelled) {
        __weak UINavigationController* weakStack = stack;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
          UINavigationController* settled = weakStack;
          if (settled.viewIfLoaded.window) {
              PFBProbeNoteStack(settled, @"1 s after a scroll on", YES, YES);
          }
        });
    }
}

%end
