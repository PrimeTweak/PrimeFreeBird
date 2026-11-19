// Probe for Twitter 12.45, removed once read: why the first pull on Home after a launch is not faded.
// Each pull and each way Home's list is handed sections around it are written, with the list's state
// and whether a fade picture lay over the list just after.

#import "Support/HookHelpers.h"
#import <objc/message.h>
#import <objc/runtime.h>

static NSString* const kPFBRefreshProbeTopic = @"probe smooth refresh";
static const NSUInteger kPFBRefreshProbeCap = 70;
static const NSUInteger kPFBRefreshProbePulls = 5;
static const NSUInteger kPFBRefreshProbePerPull = 9;
static const NSUInteger kPFBRefreshProbeLaunchCalls = 6;
static NSUInteger gPFBRefreshProbeSeq;
static CFAbsoluteTime gPFBRefreshProbeStart;
static CFAbsoluteTime gPFBRefreshProbePulledAt = -1000;
static CFAbsoluteTime gPFBRefreshProbeEndedAt = -1000;
static NSUInteger gPFBRefreshProbePulls;
static NSUInteger gPFBRefreshProbeThisPull;
static NSUInteger gPFBRefreshProbeLaunchSeen;
static NSUInteger gPFBRefreshProbeDepth;
static BOOL gPFBRefreshProbeFull;
static NSUInteger gPFBRefreshProbeFullSeen;

static void PFBRefreshProbeLine(NSString* line) {
    PFBCompatMeasure(kPFBRefreshProbeTopic,
                     [NSString stringWithFormat:@"%02lu %.2f s %@", (unsigned long)++gPFBRefreshProbeSeq,
                                                CFAbsoluteTimeGetCurrent() - gPFBRefreshProbeStart, line],
                     kPFBRefreshProbeCap);
}

static NSString* PFBRefreshProbeName(id object) {
    NSString* name = NSStringFromClass([object class]);
    NSRange dot = [name rangeOfString:@"." options:NSBackwardsSearch];
    return dot.location == NSNotFound ? name : [name substringFromIndex:dot.location + 1];
}

static BOOL PFBRefreshProbeOnHome(UIViewController* controller) {
    static Class home;
    home = home ?: NSClassFromString(@"_TtC32TwitterHomeFeatureImplementation35HomeTimelineContainerViewController");
    for (UIViewController* level = controller; level && home; level = level.parentViewController) {
        if ([level isKindOfClass:home]) {
            return YES;
        }
    }
    return NO;
}

static UIScrollView* PFBRefreshProbeList(UIViewController* controller) {
    if (!controller.isViewLoaded) {
        return nil;
    }
    if ([controller.view isKindOfClass:[UIScrollView class]]) {
        return (UIScrollView*)controller.view;
    }
    for (UIView* sub in controller.view.subviews) {
        if ([sub isKindOfClass:[UIScrollView class]]) {
            return (UIScrollView*)sub;
        }
    }
    return nil;
}

static NSUInteger PFBRefreshProbeItems(id sections) {
    NSUInteger count = 0;
    if ([sections isKindOfClass:[NSArray class]]) {
        for (id section in (NSArray*)sections) {
            count += [section isKindOfClass:[NSArray class]] ? ((NSArray*)section).count : 1;
        }
    }
    return count;
}

// A picture of the old list laid just above the list: the fade at work.
static BOOL PFBRefreshProbeFadeShown(UIScrollView* list) {
    NSArray<UIView*>* siblings = list.superview.subviews;
    NSUInteger index = [siblings indexOfObject:list];
    return index != NSNotFound && index + 1 < siblings.count && !siblings[index + 1].userInteractionEnabled &&
           CGRectEqualToRect(siblings[index + 1].frame, list.frame);
}

static NSString* PFBRefreshProbeListState(UIScrollView* list) {
    if (!list) {
        return @"no list";
    }
    return [NSString stringWithFormat:@"list window %d superview %d tracking %d dragging %d decelerating %d offset %.0f", list.window != nil,
                                      list.superview != nil, list.tracking, list.dragging, list.decelerating, list.contentOffset.y];
}

// One hand-over of sections to a list: written on Home, around a pull or in the first ones of the launch.
static void PFBRefreshProbeCall(UIViewController* controller, NSString* method, id sections, dispatch_block_t original) {
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    BOOL home = PFBRefreshProbeOnHome(controller);
    BOOL aroundPull = now - gPFBRefreshProbePulledAt < 15.0 && (gPFBRefreshProbeEndedAt < gPFBRefreshProbePulledAt || now - gPFBRefreshProbeEndedAt < 3.0);
    BOOL atLaunch = home && gPFBRefreshProbeLaunchSeen < kPFBRefreshProbeLaunchCalls;
    BOOL write = home && ((aroundPull && gPFBRefreshProbePulls <= kPFBRefreshProbePulls && gPFBRefreshProbeThisPull < kPFBRefreshProbePerPull) || atLaunch);
    if (!write) {
        original();
        return;
    }
    if (atLaunch && !aroundPull) {
        gPFBRefreshProbeLaunchSeen++;
    } else {
        gPFBRefreshProbeThisPull++;
    }
    UIScrollView* list = PFBRefreshProbeList(controller);
    NSString* before = PFBRefreshProbeListState(list);
    SEL current = @selector(sections);
    NSUInteger had = PFBRefreshProbeItems([controller respondsToSelector:current] ? ((id (*)(id, SEL))objc_msgSend)(controller, current) : nil);
    gPFBRefreshProbeDepth++;
    original();
    gPFBRefreshProbeDepth--;
    PFBRefreshProbeLine([NSString stringWithFormat:@"%@%@ depth %lu: items %lu -> %lu; %@ since pull %.2f s, since end %.2f s; %@; fade shown after %d",
                                                   aroundPull ? @"pull " : @"launch ", method, (unsigned long)gPFBRefreshProbeDepth, (unsigned long)had,
                                                   (unsigned long)PFBRefreshProbeItems(sections), PFBRefreshProbeName(controller),
                                                   now - gPFBRefreshProbePulledAt, now - gPFBRefreshProbeEndedAt, before,
                                                   PFBRefreshProbeFadeShown(list)]);
}

%hook _TtC32TwitterHomeFeatureImplementation25HomeLogoRefreshController

// A pull drawn to its end while the finger is down, noted even when no refresh is said to begin.
- (void)pullToRefreshControl:(id)control didUpdatePullFraction:(double)fraction dragging:(BOOL)dragging {
    %orig;
    BOOL full = dragging && fraction >= 1.0;
    if (full && !gPFBRefreshProbeFull && gPFBRefreshProbeFullSeen++ < kPFBRefreshProbePulls) {
        PFBRefreshProbeLine([NSString stringWithFormat:@"pull drawn to its end, fraction %.2f", fraction]);
    }
    gPFBRefreshProbeFull = full;
}

- (void)pullToRefreshControl:(id)control didBeginRefreshingFromPull:(BOOL)fromPull {
    %orig;
    if (fromPull) {
        gPFBRefreshProbePulledAt = CFAbsoluteTimeGetCurrent();
        gPFBRefreshProbePulls++;
        gPFBRefreshProbeThisPull = 0;
    }
    if (gPFBRefreshProbePulls <= kPFBRefreshProbePulls) {
        PFBRefreshProbeLine([NSString stringWithFormat:@"pull %lu began, from pull %d, Smooth refresh %d", (unsigned long)gPFBRefreshProbePulls,
                                                       fromPull, [PFBSettings boolForKey:@"refresh_fade"]]);
    }
}

- (void)pullToRefreshControlDidEndRefreshing:(id)control {
    %orig;
    gPFBRefreshProbeEndedAt = CFAbsoluteTimeGetCurrent();
    if (gPFBRefreshProbePulls <= kPFBRefreshProbePulls) {
        PFBRefreshProbeLine([NSString stringWithFormat:@"pull %lu ended, %.2f s after it began", (unsigned long)gPFBRefreshProbePulls,
                                                       gPFBRefreshProbeEndedAt - gPFBRefreshProbePulledAt]);
    }
}

%end

%hook TFNItemsDataViewController

- (void)setSections:(NSArray*)sections {
    PFBRefreshProbeCall((UIViewController*)self, @"setSections:", sections, ^{
      %orig;
    });
}

- (void)setSections:(NSArray*)sections restoreScrollPosition:(BOOL)restore {
    PFBRefreshProbeCall((UIViewController*)self, restore ? @"setSections:restoreScrollPosition:YES" : @"setSections:restoreScrollPosition:NO", sections, ^{
      %orig;
    });
}

- (void)updateSections:(NSArray*)sections {
    PFBRefreshProbeCall((UIViewController*)self, @"updateSections:", sections, ^{
      %orig;
    });
}

- (void)updateSections:(NSArray*)sections withRowAnimation:(long long)animation {
    PFBRefreshProbeCall((UIViewController*)self, @"updateSections:withRowAnimation:", sections, ^{
      %orig;
    });
}

- (void)updateSections:(NSArray*)sections completion:(id)completion {
    PFBRefreshProbeCall((UIViewController*)self, @"updateSections:completion:", sections, ^{
      %orig;
    });
}

- (void)updateSections:(NSArray*)sections withRowAnimation:(long long)animation completion:(id)completion {
    PFBRefreshProbeCall((UIViewController*)self, @"updateSections:withRowAnimation:completion:", sections, ^{
      %orig;
    });
}

- (void)updateSections:(NSArray*)sections
    reconfigureItemIdentifiers:(NSArray*)identifiers
              withRowAnimation:(long long)animation
                    completion:(id)completion {
    PFBRefreshProbeCall((UIViewController*)self, @"updateSections:reconfigureItemIdentifiers:withRowAnimation:completion:", sections, ^{
      %orig;
    });
}

- (void)insertSection:(NSArray*)section atIndex:(NSInteger)index withRowAnimation:(long long)animation {
    PFBRefreshProbeCall((UIViewController*)self, [NSString stringWithFormat:@"insertSection:atIndex:%ld withRowAnimation:", (long)index], @[ section ?: @[] ], ^{
      %orig;
    });
}

- (void)insertItem:(id)item atIndexPath:(NSIndexPath*)indexPath withRowAnimation:(long long)animation {
    PFBRefreshProbeCall((UIViewController*)self, [NSString stringWithFormat:@"insertItem:atIndexPath:%ld.%ld withRowAnimation:", (long)indexPath.section,
                                                                            (long)indexPath.row],
                        @[ @[ item ?: [NSNull null] ] ], ^{
                          %orig;
                        });
}

- (void)updateSection:(NSArray*)section atIndex:(NSInteger)index withRowAnimation:(long long)animation {
    PFBRefreshProbeCall((UIViewController*)self, [NSString stringWithFormat:@"updateSection:atIndex:%ld withRowAnimation:", (long)index], @[ section ?: @[] ], ^{
      %orig;
    });
}

%end

%ctor {
    %init;
    gPFBRefreshProbeStart = CFAbsoluteTimeGetCurrent();
}
