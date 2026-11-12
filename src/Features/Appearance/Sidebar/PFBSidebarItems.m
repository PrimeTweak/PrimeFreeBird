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

static NSString* const kHiddenKey = @"pfb_sidebar_hidden";
static NSString* const kShownKey = @"pfb_sidebar_shown";
static NSString* const kBuiltKey = @"pfb_sidebar_built";

static NSArray<NSNumber*>* gPFBSidebarTabs;
static NSMutableArray<NSNumber*>* gPFBSidebarBuilding;
static NSArray<NSNumber*>* gPFBSidebarBefore;
static NSArray<NSNumber*>* gPFBSidebarBuilt;

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

static NSArray<NSNumber*>* PFBPanelsForKeys(NSArray* keys) {
    NSMutableArray<NSNumber*>* panels = [NSMutableArray array];
    for (NSString* key in keys) {
        NSInteger panelID = PFBPanelForKey(key);
        if (panelID > 0) {
            [panels addObject:@(panelID)];
        }
    }
    return panels;
}

// The items whose builders ask Twitter's panel table for their name once they are kept.
static BOOL PFBSidebarIsNamedWhenBuilt(NSInteger panelID) {
    return panelID == 2 || panelID == 5 || panelID == 9 || panelID == 11 || panelID == 14 || panelID == 18 ||
           panelID == 22 || panelID == 23 || panelID == 24 || panelID == 25;
}

// The signed-in account's feature switches, the ones the sidebar's conditions read.
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
    return @[ @8, @15, @14, @17, @24, @23, @25, @9, @20, @18, @16, @7, @13, @4, @5, @2, @22, @11, @21 ];
}

// The sidebar titles Premium with Twitter's subscription title, not the panel table's name.
+ (NSString*)nameForPanel:(NSInteger)panelID {
    if (panelID == 15) {
        NSString* title = [[PFBBundle sharedBundle] localizedTwitterStringForKey:@"SUBSCRIPTION_TITLE"];
        if (title.length && ![title isEqualToString:@"SUBSCRIPTION_TITLE"]) {
            return title;
        }
    }
    return PFBPanelIdentityAnswer(@"localizedNameForPanelID:", panelID);
}

+ (NSString*)glyphForPanel:(NSInteger)panelID {
    return PFBPanelIdentityAnswer(@"iconImageNameForPanelID:", panelID);
}

+ (NSArray<NSString*>*)keysFor:(NSString*)defaultsKey {
    return [[NSUserDefaults standardUserDefaults] arrayForKey:defaultsKey] ?: @[];
}

+ (BOOL)isHidden:(NSInteger)panelID {
    if (panelID == PFBSidebarGrokPanel) {
        return [PFBSettings boolForKey:@"hide_grok_sidebar"];
    }
    NSString* key = PFBPanelIdentityAnswer(@"stringForPanelID:", panelID);
    if (key && [[self keysFor:kHiddenKey] containsObject:key]) {
        return YES;
    }
    if (key && [[self keysFor:kShownKey] containsObject:key]) {
        return NO;
    }
    return PFBDashKeepsOut(panelID);
}

// A choice that matches the default is not kept, so the default still follows the account.
+ (void)setPanel:(NSInteger)panelID hidden:(BOOL)hidden {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    if (panelID == PFBSidebarGrokPanel) {
        [defaults setBool:hidden forKey:@"hide_grok_sidebar"];
    } else {
        NSString* key = PFBPanelIdentityAnswer(@"stringForPanelID:", panelID);
        if (!key) {
            return;
        }
        NSMutableArray<NSString*>* hiddenKeys = [[self keysFor:kHiddenKey] mutableCopy];
        NSMutableArray<NSString*>* shownKeys = [[self keysFor:kShownKey] mutableCopy];
        [hiddenKeys removeObject:key];
        [shownKeys removeObject:key];
        BOOL hiddenByDefault = PFBDashKeepsOut(panelID);
        if (hidden && !hiddenByDefault) {
            [hiddenKeys addObject:key];
        } else if (!hidden && hiddenByDefault) {
            [shownKeys addObject:key];
        }
        [defaults setObject:hiddenKeys forKey:kHiddenKey];
        [defaults setObject:shownKeys forKey:kShownKey];
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
    [defaults removeObjectForKey:kHiddenKey];
    [defaults removeObjectForKey:kShownKey];
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

// MARK: - Rebuilds

+ (void)beginBuildOfContent:(id)content {
    gPFBSidebarBefore = PFBDashSnapshot(content);
    gPFBSidebarBuilding = [NSMutableArray array];
}

+ (void)noteBuiltPanel:(NSInteger)panelID {
    if (PFBSidebarIsNamedWhenBuilt(panelID) && ![gPFBSidebarBuilding containsObject:@(panelID)]) {
        [gPFBSidebarBuilding addObject:@(panelID)];
    }
}

// Twitter rebuilds only when the list it keeps changes, so a rebuild either named an item or
// left a new list behind.
+ (void)endBuildOfContent:(id)content {
    NSArray<NSNumber*>* built = gPFBSidebarBuilding;
    NSArray<NSNumber*>* before = gPFBSidebarBefore;
    gPFBSidebarBuilding = nil;
    gPFBSidebarBefore = nil;
    NSArray<NSNumber*>* snapshot = PFBDashSnapshot(content);
    NSArray<NSNumber*>* hidden = [self hiddenPanelIDs];
    if (built.count || (before && snapshot && ![before isEqualToArray:snapshot])) {
        gPFBSidebarBuilt = [built copy];
        NSMutableArray<NSString*>* keys = [NSMutableArray array];
        for (NSNumber* panel in built) {
            NSString* key = PFBPanelIdentityAnswer(@"stringForPanelID:", panel.integerValue);
            if (key) {
                [keys addObject:key];
            }
        }
        [[NSUserDefaults standardUserDefaults] setObject:keys forKey:kBuiltKey];
        for (NSNumber* panel in hidden) {
            if ([built containsObject:panel]) {
                [self noteStillShown:panel];
            }
        }
    }
    for (NSNumber* panel in snapshot ? hidden : @[]) {
        if (![snapshot containsObject:panel]) {
            [self noteStillShown:panel];
        }
    }
}

+ (void)noteStillShown:(NSNumber*)panel {
    PFBCompatNoteFailure(PFBCompat_customize_sidebar,
                         [NSString stringWithFormat:@"%@ still in the sidebar",
                                                    [self nameForPanel:panel.integerValue] ?: panel.stringValue]);
}

+ (NSArray<NSNumber*>*)lastBuiltPanels {
    if (gPFBSidebarBuilt) {
        return gPFBSidebarBuilt;
    }
    NSArray* keys = [[NSUserDefaults standardUserDefaults] arrayForKey:kBuiltKey];
    return keys ? PFBPanelsForKeys(keys) : nil;
}

+ (BOOL)newsOffered {
    Class features = NSClassFromString(@"T1ExploreFeatures");
    SEL initializer = NSSelectorFromString(@"initWithFeatureSwitches:");
    SEL news = NSSelectorFromString(@"enableNewsTab");
    id switches = PFBSidebarAccountSwitches();
    if (!switches || ![features instancesRespondToSelector:initializer] || ![features instancesRespondToSelector:news]) {
        return YES;
    }
    id explore = ((id (*)(id, SEL, id))objc_msgSend)([features alloc], initializer, switches);
    return explore ? ((BOOL (*)(id, SEL))objc_msgSend)(explore, news) : YES;
}

+ (BOOL)businessOffered {
    id switches = PFBSidebarAccountSwitches();
    SEL reader = NSSelectorFromString(@"boolForKey:");
    if (![switches respondsToSelector:reader]) {
        return YES;
    }
    return ((BOOL (*)(id, SEL, id))objc_msgSend)(switches, reader, @"premium_business_ios_nav_promo_enabled");
}

+ (NSArray<NSNumber*>*)panelsForPage {
    NSArray<NSNumber*>* tabs = [self tabPanelIDs];
    NSArray<NSNumber*>* built = [self lastBuiltPanels];
    NSMutableArray<NSNumber*>* panels = [NSMutableArray array];
    for (NSNumber* panel in [self catalog]) {
        NSInteger panelID = panel.integerValue;
        if ([tabs containsObject:panel] || ![self nameForPanel:panelID]) {
            continue;
        }
        BOOL kept = YES;
        if (PFBSidebarIsNamedWhenBuilt(panelID)) {
            kept = !built || [built containsObject:panel];
        } else if (panelID == 20) {
            kept = [self newsOffered];
        } else if (panelID == 21) {
            kept = [self businessOffered];
        }
        if (kept || [self isHidden:panelID]) {
            [panels addObject:panel];
        }
    }
    return panels;
}

@end
