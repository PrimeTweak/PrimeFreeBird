// Probe for the Sidebar page: Twitter's panel table, after each update of the sidebar what its
// rebuild kept, the drawer's own list and the page's tiles, and who asks for each item's name.
// Removed once read.

#import <QuartzCore/QuartzCore.h>
#import <dlfcn.h>
#import <objc/message.h>
#import "Common/PFBCompatibility.h"
#import "Features/Appearance/Sidebar/PFBSidebarItems.h"
#import "Features/Appearance/Sidebar/PFBSidebarViewController.h"

static CFTimeInterval gProbeStart;
static NSUInteger gProbeUpdates;
static NSUInteger gProbeAnswers;
static NSUInteger gProbeNamings;
static NSInteger gProbeUpdateDepth;
static BOOL gProbeMenuOpen;

static NSString* pfbProbeNow(void) {
    return [NSString stringWithFormat:@"+%.1f s", CACurrentMediaTime() - gProbeStart];
}

static void pfbProbe(NSString* line) {
    PFBCompatMeasure(@"probe sidebar", line, 150);
}

// Panels by number and Twitter's name, as a list reads them.
static NSString* pfbProbePanels(NSArray* panels) {
    if (!panels) {
        return @"unknown";
    }
    NSMutableArray<NSString*>* items = [NSMutableArray array];
    for (id panel in [panels isKindOfClass:[NSArray class]] ? panels : @[]) {
        NSInteger panelID = [panel respondsToSelector:@selector(integerValue)] ? [panel integerValue] : 0;
        [items addObject:[NSString stringWithFormat:@"%ld %@", (long)panelID,
                                                    panelID > 0 && panelID <= 25 ? [PFBSidebarItems nameForPanel:panelID] ?: @"-"
                                                                                 : @"-"]];
    }
    return items.count ? [items componentsJoinedByString:@", "] : @"none";
}

// One line per update, once the update and its check are done.
%hook T1DashContentController

- (void)updateVisiblePanelIDs {
    NSArray<NSNumber*>* before = PFBDashSnapshot(self);
    gProbeUpdateDepth++;
    %orig;
    gProbeUpdateDepth--;
    if (gProbeUpdates >= 16) {
        return;
    }
    gProbeUpdates++;
    NSUInteger update = gProbeUpdates;
    __weak id content = self;
    dispatch_async(dispatch_get_main_queue(), ^{
      NSArray<NSNumber*>* after = PFBDashSnapshot(content);
      pfbProbe([NSString stringWithFormat:@"%@ update %lu: list %@; rebuild kept %@; drawer list %@; tab bar %@",
                                          pfbProbeNow(), (unsigned long)update,
                                          before && after ? ([before isEqualToArray:after] ? @"same" : @"changed") : @"unreadable",
                                          pfbProbePanels([PFBSidebarItems lastBuiltPanels]), pfbProbePanels(after),
                                          pfbProbePanels([PFBSidebarItems tabPanelIDs])]);
      pfbProbe([NSString stringWithFormat:@"%@ update %lu: hidden %@; tab items added %@; page %@; News %@, Business %@",
                                          pfbProbeNow(), (unsigned long)update,
                                          pfbProbePanels([PFBSidebarItems hiddenPanelIDs]),
                                          pfbProbePanels([PFBSidebarItems tabPanelsInSidebar]),
                                          pfbProbePanels([PFBSidebarItems panelsForPage]),
                                          [PFBSidebarItems newsOffered] ? @"offered" : @"not offered",
                                          [PFBSidebarItems businessOffered] ? @"offered" : @"not offered"]);
    });
}

%end

// The first caller outside this tweak: its image and its address there, which names the
// sidebar's item builder in Twitter's binary.
static NSString* pfbProbeCaller(void) {
    Dl_info own;
    dladdr((const void*)&pfbProbeCaller, &own);
    NSArray<NSNumber*>* stack = [NSThread callStackReturnAddresses];
    for (NSNumber* address in [stack subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)8, stack.count))]) {
        Dl_info info;
        if (dladdr((const void*)address.unsignedLongValue, &info) && info.dli_fbase != own.dli_fbase) {
            return [NSString stringWithFormat:@"%@+0x%lx", [@(info.dli_fname) lastPathComponent],
                                              address.unsignedLongValue - (unsigned long)info.dli_fbase];
        }
    }
    return @"?";
}

// Each name Twitter asks for an item the sidebar names as it builds, inside an update or not.
%hook T1PanelIdentity

+ (NSString*)localizedNameForPanelID:(long long)panelID {
    NSString* name = %orig;
    BOOL named = panelID == 2 || panelID == 5 || panelID == 9 || panelID == 11 || panelID == 14 || panelID == 18 ||
                 panelID == 22 || panelID == 23 || panelID == 24 || panelID == 25;
    NSString* caller = named && gProbeNamings < 40 ? pfbProbeCaller() : nil;
    if ([caller hasPrefix:@"T1Twitter+"]) {
        gProbeNamings++;
        pfbProbe([NSString stringWithFormat:@"%@ %lld %@ named by %@, %@ an update, menu %@", pfbProbeNow(), panelID,
                                            name ?: @"-", caller, gProbeUpdateDepth ? @"inside" : @"outside",
                                            gProbeMenuOpen ? @"open" : @"closed"]);
    }
    return name;
}

%end

%hook T1DashContentPresenter

- (void)dashDidSettleOpen:(BOOL)open {
    gProbeMenuOpen = open;
    %orig;
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
    pfbProbe([NSString stringWithFormat:@"%@ Sidebar page shows %@; hidden %@; tab bar %@", pfbProbeNow(),
                                        pfbProbePanels([PFBSidebarItems panelsForPage]),
                                        pfbProbePanels([PFBSidebarItems hiddenPanelIDs]),
                                        pfbProbePanels([PFBSidebarItems tabPanelIDs])]);
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
      NSMutableArray<NSString*>* kept = [NSMutableArray array];
      for (NSNumber* panel in @[ @13, @15, @16, @17 ]) {
          [kept addObject:[NSString stringWithFormat:@"%@ %@", panel, PFBDashKeepsOut(panel.longLongValue) ? @"out" : @"in"]];
      }
      pfbProbe([NSString stringWithFormat:@"%@ unlock-only panels by default: %@", pfbProbeNow(),
                                          [kept componentsJoinedByString:@", "]]);
    });
}
