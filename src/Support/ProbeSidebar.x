// Probe for the Sidebar page: Twitter's panel table, and at each opening of the sidebar what it
// was read showing, the lists it was answered and the drawer's own snapshot. Removed once read.

#import <QuartzCore/QuartzCore.h>
#import <malloc/malloc.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "Common/PFBCompatibility.h"
#import "Features/Appearance/Sidebar/PFBSidebarItems.h"
#import "Features/Appearance/Sidebar/PFBSidebarViewController.h"

static CFTimeInterval gProbeStart;
static NSUInteger gProbeOpenings;
static NSUInteger gProbeAnswers;
static BOOL gProbeMenuOpen;

static NSString* pfbProbeNow(void) {
    return [NSString stringWithFormat:@"+%.1f s", CACurrentMediaTime() - gProbeStart];
}

static void pfbProbe(NSString* line) {
    PFBCompatMeasure(@"probe sidebar", line, 150);
}

// Panels by number and Twitter's name, as a list reads them.
static NSString* pfbProbePanels(NSArray* panels) {
    NSMutableArray<NSString*>* items = [NSMutableArray array];
    for (id panel in [panels isKindOfClass:[NSArray class]] ? panels : @[]) {
        NSInteger panelID = [panel respondsToSelector:@selector(integerValue)] ? [panel integerValue] : 0;
        [items addObject:[NSString stringWithFormat:@"%ld %@", (long)panelID,
                                                    panelID > 0 && panelID <= 25 ? [PFBSidebarItems nameForPanel:panelID] ?: @"-"
                                                                                 : @"-"]];
    }
    return items.count ? [items componentsJoinedByString:@", "] : @"none";
}

// A Swift [Int] held in an instance variable: its count and elements, read from its heap storage.
static NSString* pfbProbeSwiftInts(id owner, const char* name) {
    Ivar ivar = owner ? class_getInstanceVariable(object_getClass(owner), name) : NULL;
    if (!ivar) {
        return @"no such variable";
    }
    void* storage = NULL;
    memcpy(&storage, (const uint8_t*)(__bridge void*)owner + ivar_getOffset(ivar), sizeof(storage));
    if (!storage || !malloc_zone_from_ptr(storage)) {
        return [NSString stringWithFormat:@"storage %p outside the heap (an empty array)", storage];
    }
    size_t size = malloc_size(storage);
    int64_t count = 0;
    memcpy(&count, (const uint8_t*)storage + 16, sizeof(count));
    if (count < 0 || count > 64 || (size_t)(32 + count * 8) > size) {
        return [NSString stringWithFormat:@"count %lld unreadable in %zu bytes", count, size];
    }
    NSMutableArray<NSNumber*>* values = [NSMutableArray array];
    for (int64_t index = 0; index < count; index++) {
        int64_t value = 0;
        memcpy(&value, (const uint8_t*)storage + 32 + index * 8, sizeof(value));
        [values addObject:@(value)];
    }
    return pfbProbePanels(values);
}

// The drawer's content controller, through the controller that slides the sidebar in.
static id pfbProbeDashContent(void) {
    Class splitClass = NSClassFromString(@"T1AppSplitViewController");
    SEL content = NSSelectorFromString(@"dashContentController");
    for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }
        for (UIWindow* window in ((UIWindowScene*)scene).windows) {
            NSMutableArray<UIViewController*>* queue = [NSMutableArray array];
            if (window.rootViewController) {
                [queue addObject:window.rootViewController];
            }
            for (NSUInteger index = 0; index < queue.count && index < 200; index++) {
                UIViewController* controller = queue[index];
                if (splitClass && [controller isKindOfClass:splitClass] && [controller respondsToSelector:content]) {
                    return ((id (*)(id, SEL))objc_msgSend)(controller, content);
                }
                [queue addObjectsFromArray:controller.childViewControllers];
            }
        }
    }
    return nil;
}

// The classes under the drawer's host down three levels, counted, for a sidebar whose rows
// gave no labels.
static NSString* pfbProbeHostShape(void) {
    Class hostClass = NSClassFromString(@"_TtC11TwitterDash21DashHostingController");
    UIViewController* host = nil;
    for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }
        for (UIWindow* window in ((UIWindowScene*)scene).windows) {
            NSMutableArray<UIViewController*>* queue = [NSMutableArray array];
            if (window.rootViewController) {
                [queue addObject:window.rootViewController];
            }
            for (NSUInteger index = 0; index < queue.count && index < 400 && !host; index++) {
                if (hostClass && [queue[index] isKindOfClass:hostClass]) {
                    host = queue[index];
                }
                [queue addObjectsFromArray:queue[index].childViewControllers];
            }
        }
    }
    if (!host.isViewLoaded) {
        return @"no host view";
    }
    NSCountedSet<NSString*>* classes = [NSCountedSet set];
    NSArray<UIView*>* level = @[ host.view ];
    for (NSUInteger depth = 0; depth < 4 && level.count; depth++) {
        NSMutableArray<UIView*>* next = [NSMutableArray array];
        for (UIView* view in level) {
            [classes addObject:[NSString stringWithFormat:@"%lu:%@", (unsigned long)depth, NSStringFromClass([view class])]];
            [next addObjectsFromArray:view.subviews];
        }
        level = next;
    }
    NSMutableArray<NSString*>* items = [NSMutableArray array];
    for (NSString* name in [classes.allObjects sortedArrayUsingSelector:@selector(compare:)]) {
        [items addObject:[NSString stringWithFormat:@"%@ x%lu", name, (unsigned long)[classes countForObject:name]]];
    }
    return [items componentsJoinedByString:@", "];
}

static void pfbProbeOpening(void) {
    gProbeOpenings++;
    if (gProbeOpenings > 12) {
        return;
    }
    NSDictionary* reading = [PFBSidebarItems lastReading];
    NSArray<NSString*>* labels = reading[@"labels"];
    NSArray* shown = reading[@"panels"];
    pfbProbe([NSString stringWithFormat:@"%@ opening %lu: host %@, %lu nodes, VoiceOver %@, %lu labels: %@",
                                        pfbProbeNow(), (unsigned long)gProbeOpenings, reading[@"host"] ?: @"?",
                                        (unsigned long)[reading[@"visits"] unsignedIntegerValue],
                                        UIAccessibilityIsVoiceOverRunning() ? @"on" : @"off", (unsigned long)labels.count,
                                        labels.count ? [[labels subarrayWithRange:NSMakeRange(0, MIN(labels.count, 60))]
                                                           componentsJoinedByString:@" | "]
                                                     : pfbProbeHostShape()]);
    pfbProbe([NSString stringWithFormat:@"%@ opening %lu: rows named %@; tab bar %@; hidden %@; page %@",
                                        pfbProbeNow(), (unsigned long)gProbeOpenings, pfbProbePanels(shown),
                                        pfbProbePanels([PFBSidebarItems tabPanelIDs]),
                                        pfbProbePanels([PFBSidebarItems hiddenPanelIDs]),
                                        pfbProbePanels([PFBSidebarItems panelsForPage])]);
    pfbProbe([NSString stringWithFormat:@"%@ opening %lu: drawer snapshot visiblePanelIDs %@", pfbProbeNow(),
                                        (unsigned long)gProbeOpenings, pfbProbeSwiftInts(pfbProbeDashContent(), "visiblePanelIDs")]);
}

%hook T1DashContentPresenter

- (void)dashDidSettleOpen:(BOOL)open {
    gProbeMenuOpen = open;
    %orig;
    if (open) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
          pfbProbeOpening();
        });
    }
}

%end

// The lists the sidebar is answered while it is open, claims included.
%hook _TtC14T1TwitterSwift20XTabbedAppNavigation

- (NSArray*)visiblePanelIDs {
    NSArray* panelIDs = %orig;
    if (gProbeMenuOpen && gProbeAnswers < 8) {
        gProbeAnswers++;
        pfbProbe([NSString stringWithFormat:@"%@ glass navigation answered while open: %@", pfbProbeNow(), pfbProbePanels(panelIDs)]);
    }
    return panelIDs;
}

%end

%hook T1TabbedAppNavigationViewController

- (NSArray*)visiblePanelIDsForAppNavigation:(id)appNavigation {
    NSArray* panelIDs = %orig;
    if (gProbeMenuOpen && gProbeAnswers < 8) {
        gProbeAnswers++;
        pfbProbe([NSString stringWithFormat:@"%@ classic navigation answered while open: %@", pfbProbeNow(), pfbProbePanels(panelIDs)]);
    }
    return panelIDs;
}

%end

%hook PFBSidebarViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    pfbProbe([NSString stringWithFormat:@"%@ Sidebar page shows %@; tab bar %@", pfbProbeNow(),
                                        pfbProbePanels([PFBSidebarItems panelsForPage]), pfbProbePanels([PFBSidebarItems tabPanelIDs])]);
}

%end

%ctor {
    gProbeStart = CACurrentMediaTime();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      Class identity = NSClassFromString(@"T1PanelIdentity");
      SEL keyReader = NSSelectorFromString(@"stringForPanelID:");
      NSMutableArray<NSString*>* table = [NSMutableArray array];
      for (NSInteger panelID = 1; panelID <= 25; panelID++) {
          id key = [identity respondsToSelector:keyReader]
                       ? ((id (*)(id, SEL, long long))objc_msgSend)(identity, keyReader, (long long)panelID)
                       : nil;
          [table addObject:[NSString stringWithFormat:@"%ld %@ \"%@\" %@", (long)panelID, key ?: @"-",
                                                      [PFBSidebarItems nameForPanel:panelID] ?: @"-",
                                                      [PFBSidebarItems glyphForPanel:panelID] ?: @"-"]];
      }
      pfbProbe([NSString stringWithFormat:@"%@ panel table: %@", pfbProbeNow(), [table componentsJoinedByString:@"; "]]);
    });
}
