// The sidebar's items as Twitter's panels: names and glyphs from Twitter's panel table, the
// choices stored by Twitter's panel name, and what each rebuild of the sidebar kept.

#import "Features/Appearance/Sidebar/PFBSidebarItems.h"
#import <malloc/malloc.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "Common/PFBBundle.h"
#import "Common/PFBCompatibility.h"
#import "Common/PFBSettings.h"

NSNotificationName const PFBSidebarItemsDidChangeNotification = @"PFBSidebarItemsDidChangeNotification";

// Each choice made on the page, shown or not, by Twitter's panel name.
static NSString* const kChoicesKey = @"pfb_sidebar_choices";

static NSArray<NSNumber*>* gPFBSidebarTabs;
static NSMutableArray<NSNumber*>* gPFBSidebarBuilding;

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

// A title from Twitter's own string tables; nil when Twitter has none.
static NSString* PFBSidebarTwitterString(NSString* key) {
    NSString* text = [[PFBBundle sharedBundle] localizedTwitterStringForKey:key];
    return text.length && ![text isEqualToString:key] ? text : nil;
}

// Downloads, Boost and Analytics stay as Twitter shows them: whether the tweak can show them
// is not measured yet.
static BOOL PFBSidebarIsOffered(NSInteger panelID) {
    return panelID != 18 && panelID != 19 && panelID != 23;
}

// In the sidebar on a fresh install: Profile, History, News, Lists and Spaces.
static BOOL PFBSidebarShownByDefault(NSInteger panelID) {
    return panelID == 8 || panelID == 24 || panelID == 20 || panelID == 7 || panelID == 11;
}

// The items whose builders ask Twitter's panel table for their name once they keep them.
static BOOL PFBSidebarIsNamedWhenBuilt(NSInteger panelID) {
    return panelID == 2 || panelID == 5 || panelID == 9 || panelID == 11 || panelID == 14 || panelID == 18 ||
           panelID == 22 || panelID == 23 || panelID == 24 || panelID == 25;
}

// Of those, the ones Twitter builds whenever they are shown: History and Communities always, Spaces
// and Follow through the switches the tweak answers.
static BOOL PFBSidebarIsBuiltWhenShown(NSInteger panelID) {
    return panelID == 24 || panelID == 9 || panelID == 11 || panelID == 22;
}

// The signed-in account's feature switches, as Twitter's sidebar reads them.
static id PFBSidebarAccountSwitches(void) {
    Class hostClass = NSClassFromString(@"T1HostViewController");
    SEL shared = NSSelectorFromString(@"sharedHostViewController");
    SEL current = NSSelectorFromString(@"currentAccount");
    SEL switches = NSSelectorFromString(@"featureSwitches");
    if (![hostClass respondsToSelector:shared]) {
        return nil;
    }
    id host = ((id (*)(id, SEL))objc_msgSend)(hostClass, shared);
    id account = [host respondsToSelector:current] ? ((id (*)(id, SEL))objc_msgSend)(host, current) : nil;
    return [account respondsToSelector:switches] ? ((id (*)(id, SEL))objc_msgSend)(account, switches) : nil;
}

NSArray<NSNumber*>* PFBDashSnapshot(id content) {
    Ivar ivar = content ? class_getInstanceVariable(object_getClass(content), "visiblePanelIDs") : NULL;
    if (!ivar) {
        return nil;
    }
    void* storage = NULL;
    memcpy(&storage, (const uint8_t*)(__bridge void*)content + ivar_getOffset(ivar), sizeof(storage));
    if (!storage || !malloc_zone_from_ptr(storage)) {
        return nil;
    }
    size_t size = malloc_size(storage);
    int64_t count = 0;
    memcpy(&count, (const uint8_t*)storage + 16, sizeof(count));
    if (count < 0 || count > 64 || (size_t)(32 + count * 8) > size) {
        return nil;
    }
    NSMutableArray<NSNumber*>* panels = [NSMutableArray array];
    for (int64_t index = 0; index < count; index++) {
        int64_t value = 0;
        memcpy(&value, (const uint8_t*)storage + 32 + index * 8, sizeof(value));
        [panels addObject:@(value)];
    }
    return panels;
}

@implementation PFBSidebarItems

+ (NSArray<NSNumber*>*)catalog {
    return @[ @8, @15, @14, @17, @24, @23, @25, @9, @20, @18, @16, @7, @13, @4, @5, @2, @22, @11, @19, @12, @21 ];
}

// Premium and Creator Studio carry the titles their rows show, not the panel table's; the Creator
// Studio row turns into Monetization when that switch is on.
+ (NSString*)nameForPanel:(NSInteger)panelID {
    NSString* title = nil;
    if (panelID == 15) {
        title = PFBSidebarTwitterString(@"SUBSCRIPTION_TITLE");
    } else if (panelID == 12) {
        SEL reader = NSSelectorFromString(@"boolForKey:");
        id switches = PFBSidebarAccountSwitches();
        BOOL monetization = [switches respondsToSelector:reader] &&
                            ((BOOL (*)(id, SEL, id))objc_msgSend)(switches, reader, @"creator_monetization_dashboard_enabled");
        title = monetization ? nil : PFBSidebarTwitterString(@"CREATOR_STUDIO_TITLE");
    }
    return title ?: PFBPanelIdentityAnswer(@"localizedNameForPanelID:", panelID);
}

+ (NSString*)glyphForPanel:(NSInteger)panelID {
    return PFBPanelIdentityAnswer(@"iconImageNameForPanelID:", panelID);
}

+ (BOOL)isHidden:(NSInteger)panelID {
    if (panelID == PFBSidebarGrokPanel) {
        return [PFBSettings boolForKey:@"hide_grok_sidebar"];
    }
    if (!PFBSidebarIsOffered(panelID)) {
        return NO;
    }
    NSString* key = PFBPanelIdentityAnswer(@"stringForPanelID:", panelID);
    id choice = key ? [[NSUserDefaults standardUserDefaults] dictionaryForKey:kChoicesKey][key] : nil;
    BOOL shown = [choice isKindOfClass:[NSNumber class]] ? [choice boolValue] : PFBSidebarShownByDefault(panelID);
    return !shown;
}

// A choice that matches the default is not kept.
+ (void)setPanel:(NSInteger)panelID hidden:(BOOL)hidden {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    if (panelID == PFBSidebarGrokPanel) {
        [defaults setBool:hidden forKey:@"hide_grok_sidebar"];
    } else {
        NSString* key = PFBPanelIdentityAnswer(@"stringForPanelID:", panelID);
        if (!key) {
            return;
        }
        NSMutableDictionary* choices = [[defaults dictionaryForKey:kChoicesKey] mutableCopy] ?: [NSMutableDictionary dictionary];
        if (hidden == !PFBSidebarShownByDefault(panelID)) {
            [choices removeObjectForKey:key];
        } else {
            choices[key] = @(!hidden);
        }
        [defaults setObject:choices forKey:kChoicesKey];
    }
    [self changed];
}

+ (NSArray<NSNumber*>*)hiddenPanelIDs {
    NSMutableArray<NSNumber*>* panels = [NSMutableArray array];
    for (NSNumber* panel in [self catalog]) {
        if (panel.integerValue != PFBSidebarGrokPanel && [self isHidden:panel.integerValue]) {
            [panels addObject:panel];
        }
    }
    return panels;
}

+ (void)resetToDefault {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:kChoicesKey];
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
        if ([panel isKindOfClass:[NSNumber class]] && ![tabs containsObject:panel]) {
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

// Twitter leaves a tab bar item out of its sidebar, so the page does too.
+ (NSArray<NSNumber*>*)panelsForPage {
    NSArray<NSNumber*>* tabs = [self tabPanelIDs];
    NSMutableArray<NSNumber*>* panels = [NSMutableArray array];
    for (NSNumber* panel in [self catalog]) {
        if (PFBSidebarIsOffered(panel.integerValue) && ![tabs containsObject:panel] &&
            [self nameForPanel:panel.integerValue]) {
            [panels addObject:panel];
        }
    }
    return panels;
}

// MARK: - Rebuilds

+ (void)beginBuildOfContent:(id)content {
    gPFBSidebarBuilding = [NSMutableArray array];
}

+ (void)noteBuiltPanel:(NSInteger)panelID {
    if (PFBSidebarIsNamedWhenBuilt(panelID) && ![gPFBSidebarBuilding containsObject:@(panelID)]) {
        [gPFBSidebarBuilding addObject:@(panelID)];
    }
}

// A hidden item Twitter named, or one missing from the list the drawer kept, is still in the
// sidebar; a rebuild that named items and not a shown one Twitter always builds left it out.
+ (void)endBuildOfContent:(id)content {
    NSArray<NSNumber*>* built = gPFBSidebarBuilding;
    gPFBSidebarBuilding = nil;
    NSArray<NSNumber*>* kept = PFBDashSnapshot(content);
    for (NSNumber* panel in [self hiddenPanelIDs]) {
        if ([built containsObject:panel] || (kept && ![kept containsObject:panel])) {
            [self noteFailureOf:panel state:@"still in the sidebar"];
        }
    }
    NSArray<NSNumber*>* tabs = [self tabPanelIDs];
    for (NSNumber* panel in built.count ? [self catalog] : @[]) {
        if (PFBSidebarIsBuiltWhenShown(panel.integerValue) && ![self isHidden:panel.integerValue] &&
            ![tabs containsObject:panel] && ![built containsObject:panel]) {
            [self noteFailureOf:panel state:@"missing from the sidebar"];
        }
    }
}

+ (void)noteFailureOf:(NSNumber*)panel state:(NSString*)state {
    NSString* name = [self nameForPanel:panel.integerValue] ?: panel.stringValue;
    PFBCompatNoteFailure(PFBCompat_customize_sidebar, [NSString stringWithFormat:@"%@ %@", name, state]);
}

@end
