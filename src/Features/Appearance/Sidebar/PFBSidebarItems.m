// The sidebar's items as Twitter's panels: names and glyphs from Twitter's panel table, the
// hidden ones stored by Twitter's panel name, and readings of the open sidebar.

#import "Features/Appearance/Sidebar/PFBSidebarItems.h"
#import <objc/message.h>
#import "Common/PFBCompatibility.h"
#import "Common/PFBSettings.h"
#import "Support/HookHelpers.h"

NSNotificationName const PFBSidebarItemsDidChangeNotification = @"PFBSidebarItemsDidChangeNotification";

static NSString* const kHiddenKey = @"pfb_sidebar_hidden";
static NSString* const kSeenKey = @"pfb_sidebar_seen";

// Panels Twitter offers only to some accounts; PrimeFreeBird keeps them out unless they are.
static BOOL PFBSidebarIsGated(NSInteger panelID) {
    return panelID == 13 || panelID == 15 || panelID == 16 || panelID == 17;
}

// The main tabs and the Connect tab reach the sidebar only once taken out of the tab bar.
static BOOL PFBSidebarIsTabFirst(NSInteger panelID) {
    return panelID == 1 || panelID == 2 || panelID == 4 || panelID == 5 || panelID == 22;
}

static NSArray<NSNumber*>* gPFBSidebarTabs;
static NSDictionary* gPFBSidebarReading;

// Twitter's panel table answers by class method; each read is checked so a renamed one gives nil.
static id PFBPanelIdentityAnswer(NSString* selectorName, NSInteger panelID) {
    Class identity = NSClassFromString(@"T1PanelIdentity");
    SEL selector = NSSelectorFromString(selectorName);
    if (![identity respondsToSelector:selector]) {
        return nil;
    }
    id answer = ((id (*)(id, SEL, long long))objc_msgSend)(identity, selector, (long long)panelID);
    return [answer isKindOfClass:[NSString class]] && [answer length] ? answer : nil;
}

static NSInteger PFBPanelForKey(NSString* key) {
    Class identity = NSClassFromString(@"T1PanelIdentity");
    SEL selector = NSSelectorFromString(@"panelIDForString:");
    if (![key isKindOfClass:[NSString class]] || ![identity respondsToSelector:selector]) {
        return 0;
    }
    return (NSInteger)((long long (*)(id, SEL, id))objc_msgSend)(identity, selector, key);
}

@implementation PFBSidebarItems

+ (NSArray<NSNumber*>*)catalog {
    return @[
        @8, @15, @24, @6, @23, @25, @9, @20, @7, @16, @12, @19, @17, @13, @21, @18, @14, @11, @22, @1, @5, @2, @4
    ];
}

+ (NSString*)nameForPanel:(NSInteger)panelID {
    return PFBPanelIdentityAnswer(@"localizedNameForPanelID:", panelID);
}

+ (NSString*)glyphForPanel:(NSInteger)panelID {
    return PFBPanelIdentityAnswer(@"iconImageNameForPanelID:", panelID);
}

+ (NSArray<NSString*>*)hiddenKeys {
    NSArray* keys = [[NSUserDefaults standardUserDefaults] arrayForKey:kHiddenKey];
    return keys ?: @[];
}

+ (BOOL)isHidden:(NSInteger)panelID {
    if (panelID == PFBSidebarGrokPanel) {
        return [PFBSettings boolForKey:@"hide_grok_sidebar"];
    }
    NSString* key = PFBPanelIdentityAnswer(@"stringForPanelID:", panelID);
    return key && [[self hiddenKeys] containsObject:key];
}

+ (void)setPanel:(NSInteger)panelID hidden:(BOOL)hidden {
    if (panelID == PFBSidebarGrokPanel) {
        [[NSUserDefaults standardUserDefaults] setBool:hidden forKey:@"hide_grok_sidebar"];
    } else {
        NSString* key = PFBPanelIdentityAnswer(@"stringForPanelID:", panelID);
        if (!key) {
            return;
        }
        NSMutableArray<NSString*>* keys = [[self hiddenKeys] mutableCopy];
        [keys removeObject:key];
        if (hidden) {
            [keys addObject:key];
        }
        [[NSUserDefaults standardUserDefaults] setObject:keys forKey:kHiddenKey];
    }
    [self changed];
}

+ (NSArray<NSNumber*>*)hiddenPanelIDs {
    NSMutableArray<NSNumber*>* panels = [NSMutableArray array];
    for (NSString* key in [self hiddenKeys]) {
        NSInteger panelID = PFBPanelForKey(key);
        if (panelID > 0 && panelID != PFBSidebarGrokPanel) {
            [panels addObject:@(panelID)];
        }
    }
    return panels;
}

+ (void)resetToDefault {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:kHiddenKey];
    [defaults removeObjectForKey:@"hide_grok_sidebar"];
    [self changed];
}

+ (void)changed {
    PFBDashRefresh();
    [[NSNotificationCenter defaultCenter] postNotificationName:PFBSidebarItemsDidChangeNotification object:nil];
}

+ (void)recordTabPanelIDs:(NSArray*)panelIDs {
    NSMutableArray<NSNumber*>* tabs = [NSMutableArray array];
    for (id panel in [panelIDs isKindOfClass:[NSArray class]] ? panelIDs : @[]) {
        if ([panel isKindOfClass:[NSNumber class]]) {
            [tabs addObject:panel];
        }
    }
    @synchronized(self) {
        gPFBSidebarTabs = tabs;
    }
}

+ (NSArray<NSNumber*>*)tabPanelIDs {
    @synchronized(self) {
        return gPFBSidebarTabs ?: @[];
    }
}

+ (NSArray<NSNumber*>*)seenPanelIDs {
    NSArray* keys = [[NSUserDefaults standardUserDefaults] arrayForKey:kSeenKey];
    if (!keys.count) {
        return nil;
    }
    NSMutableArray<NSNumber*>* panels = [NSMutableArray array];
    for (NSString* key in keys) {
        NSInteger panelID = PFBPanelForKey(key);
        if (panelID > 0) {
            [panels addObject:@(panelID)];
        }
    }
    return panels;
}

+ (NSArray<NSNumber*>*)panelsForPage {
    NSArray<NSNumber*>* tabs = [self tabPanelIDs];
    NSArray<NSNumber*>* seen = [self seenPanelIDs];
    NSMutableArray<NSNumber*>* panels = [NSMutableArray array];
    for (NSNumber* panel in [self catalog]) {
        NSInteger panelID = panel.integerValue;
        if ([tabs containsObject:panel] || ![self nameForPanel:panelID]) {
            continue;
        }
        if (PFBSidebarIsGated(panelID) && !PFBPanelIsGenuinelyAvailable(panelID) && ![seen containsObject:panel]) {
            continue;
        }
        BOOL listed = seen ? [seen containsObject:panel] : !PFBSidebarIsTabFirst(panelID);
        if (listed || [self isHidden:panelID]) {
            [panels addObject:panel];
        }
    }
    return panels;
}

// MARK: - Reading the open sidebar

// The sidebar's SwiftUI host, under the controller that slides it in.
static UIViewController* PFBSidebarHost(void) {
    Class hostClass = NSClassFromString(@"_TtC11TwitterDash21DashHostingController");
    if (!hostClass) {
        return nil;
    }
    for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }
        for (UIWindow* window in ((UIWindowScene*)scene).windows) {
            NSMutableArray<UIViewController*>* queue = [NSMutableArray array];
            if (window.rootViewController) {
                [queue addObject:window.rootViewController];
            }
            for (NSUInteger index = 0; index < queue.count && index < 400; index++) {
                UIViewController* controller = queue[index];
                if ([controller isKindOfClass:hostClass]) {
                    return controller;
                }
                [queue addObjectsFromArray:controller.childViewControllers];
                if (controller.presentedViewController) {
                    [queue addObject:controller.presentedViewController];
                }
            }
        }
    }
    return nil;
}

// The labels the accessibility tree gives, in reading order.
static void PFBSidebarCollect(id element, NSUInteger depth, NSMutableArray<NSString*>* labels, NSUInteger* visits) {
    if (!element || depth > 18 || *visits > 800) {
        return;
    }
    (*visits)++;
    if ([element isKindOfClass:[UIView class]] && (((UIView*)element).hidden || ((UIView*)element).alpha < 0.01)) {
        return;
    }
    NSString* label = [element isAccessibilityElement] ? [element accessibilityLabel] : nil;
    if ([label isKindOfClass:[NSString class]] && label.length) {
        [labels addObject:label];
    }
    NSArray* children = [element accessibilityElements];
    if (![children isKindOfClass:[NSArray class]] || !children.count) {
        children = nil;
        NSInteger count = [element accessibilityElementCount];
        if (count != NSNotFound && count > 0 && count < 300) {
            NSMutableArray* found = [NSMutableArray array];
            for (NSInteger index = 0; index < count; index++) {
                id child = [element accessibilityElementAtIndex:index];
                if (child) {
                    [found addObject:child];
                }
            }
            children = found;
        }
    }
    if (!children.count && [element isKindOfClass:[UIView class]]) {
        children = ((UIView*)element).subviews;
    }
    for (id child in children) {
        PFBSidebarCollect(child, depth + 1, labels, visits);
    }
}

// The panel a label names: Twitter's name for it, alone or before a badge.
static NSInteger PFBSidebarPanelForLabel(NSString* label, NSDictionary<NSString*, NSNumber*>* names) {
    NSString* text = [[label stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
        lowercaseString];
    NSInteger best = 0;
    NSUInteger bestLength = 0;
    for (NSString* name in names) {
        BOOL whole = [text isEqualToString:name];
        BOOL leads = [text hasPrefix:name] && text.length > name.length &&
                     ![NSCharacterSet.letterCharacterSet characterIsMember:[text characterAtIndex:name.length]];
        if ((whole || leads) && name.length > bestLength) {
            best = names[name].integerValue;
            bestLength = name.length;
        }
    }
    return best;
}

+ (void)readOpenSidebar {
    UIViewController* host = PFBSidebarHost();
    NSMutableArray<NSString*>* labels = [NSMutableArray array];
    NSUInteger visits = 0;
    if (host.isViewLoaded) {
        PFBSidebarCollect(host.view, 0, labels, &visits);
    }
    NSMutableDictionary<NSString*, NSNumber*>* names = [NSMutableDictionary dictionary];
    for (NSNumber* panel in [self catalog]) {
        NSString* name = [self nameForPanel:panel.integerValue];
        if (name) {
            names[name.lowercaseString] = panel;
        }
    }
    NSMutableArray<NSNumber*>* shown = [NSMutableArray array];
    for (NSString* label in labels) {
        NSInteger panelID = PFBSidebarPanelForLabel(label, names);
        if (panelID && ![shown containsObject:@(panelID)]) {
            [shown addObject:@(panelID)];
        }
    }
    @synchronized(self) {
        gPFBSidebarReading = @{
            @"host": host ? NSStringFromClass([host class]) : @"none",
            @"labels": labels,
            @"visits": @(visits),
            @"panels": shown
        };
    }
    if (!shown.count) {
        return;
    }
    NSMutableArray<NSString*>* keys = [NSMutableArray array];
    for (NSNumber* panel in shown) {
        NSString* key = PFBPanelIdentityAnswer(@"stringForPanelID:", panel.integerValue);
        if (key) {
            [keys addObject:key];
        }
    }
    [[NSUserDefaults standardUserDefaults] setObject:keys forKey:kSeenKey];
    for (NSNumber* panel in [self hiddenPanelIDs]) {
        if ([shown containsObject:panel]) {
            PFBCompatNoteFailure(PFBCompat_customize_sidebar,
                                 [NSString stringWithFormat:@"%@ still in the sidebar",
                                                            [self nameForPanel:panel.integerValue] ?: panel.stringValue]);
        }
    }
}

+ (NSDictionary*)lastReading {
    @synchronized(self) {
        return gPFBSidebarReading ?: @{};
    }
}

@end
