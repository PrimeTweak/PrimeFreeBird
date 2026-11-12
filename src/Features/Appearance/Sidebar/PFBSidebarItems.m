// The sidebar's items as Twitter's panels: names and glyphs from Twitter's panel table, the ones
// Twitter shows as measured from its own rebuild, and the choices stored by Twitter's panel name.

#import "Features/Appearance/Sidebar/PFBSidebarItems.h"
#import <malloc/malloc.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "Common/PFBBundle.h"
#import "Common/PFBCompatibility.h"
#import "Common/PFBSettings.h"

NSNotificationName const PFBSidebarItemsDidChangeNotification = @"PFBSidebarItemsDidChangeNotification";

static NSString* const kHiddenKey = @"pfb_sidebar_hidden";
static NSString* const kNativeKey = @"pfb_sidebar_native";

static NSMutableArray<NSNumber*>* gPFBSidebarBuilding;
static NSArray<NSNumber*>* gPFBSidebarNative;
static BOOL gPFBSidebarCreatorStudio;

// The panels whose gates the unlock forces on (FeatureSwitches.x): Spaces, Community Notes, Grok,
// Jobs, Money and News.
static NSArray<NSNumber*>* PFBSidebarUnlockGated(void) {
    return @[ @11, @13, @14, @16, @17, @20 ];
}

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

static NSArray<NSString*>* PFBKeysForPanels(NSArray<NSNumber*>* panels) {
    NSMutableArray<NSString*>* keys = [NSMutableArray array];
    for (NSNumber* panel in panels) {
        NSString* key = PFBPanelIdentityAnswer(@"stringForPanelID:", panel.integerValue);
        if (key) {
            [keys addObject:key];
        }
    }
    return keys;
}

// A title from Twitter's own string tables; nil when Twitter has none.
static NSString* PFBSidebarTwitterString(NSString* key) {
    NSString* text = [[PFBBundle sharedBundle] localizedTwitterStringForKey:key];
    return text.length && ![text isEqualToString:key] ? text : nil;
}

// MARK: - Twitter's conditions

// The items whose builders ask Twitter's panel table for their name once they keep them.
static BOOL PFBSidebarIsNamedWhenBuilt(NSInteger panelID) {
    return panelID == 2 || panelID == 5 || panelID == 9 || panelID == 11 || panelID == 14 || panelID == 18 ||
           panelID == 22 || panelID == 23 || panelID == 24 || panelID == 25;
}

static id PFBSidebarSend(id receiver, NSString* selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    return [receiver respondsToSelector:selector] ? ((id (*)(id, SEL))objc_msgSend)(receiver, selector) : nil;
}

static BOOL PFBSidebarFlag(id receiver, NSString* selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    return [receiver respondsToSelector:selector] && ((BOOL (*)(id, SEL))objc_msgSend)(receiver, selector);
}

static BOOL PFBSidebarSwitch(id switches, NSString* key) {
    SEL reader = NSSelectorFromString(@"boolForKey:");
    return [switches respondsToSelector:reader] && ((BOOL (*)(id, SEL, id))objc_msgSend)(switches, reader, key);
}

static id PFBSidebarAccount(void) {
    return PFBSidebarSend(PFBSidebarSend(NSClassFromString(@"T1HostViewController"), @"sharedHostViewController"),
                          @"currentAccount");
}

static BOOL PFBSidebarNewsTab(id switches) {
    Class features = NSClassFromString(@"T1ExploreFeatures");
    SEL initializer = NSSelectorFromString(@"initWithFeatureSwitches:");
    if (!switches || ![features instancesRespondToSelector:initializer]) {
        return NO;
    }
    return PFBSidebarFlag(((id (*)(id, SEL, id))objc_msgSend)([features alloc], initializer, switches), @"enableNewsTab");
}

// Whether Twitter shows a panel with nothing hidden: seen as Twitter names it while it builds, or
// from the conditions its builder reads (T1Twitter 12.42.1 +0x9fc790). A tab bar panel never is.
static BOOL PFBSidebarIsShown(NSInteger panelID, NSArray<NSNumber*>* tabs, NSArray<NSNumber*>* named, id account) {
    if (PFBSidebarIsNamedWhenBuilt(panelID)) {
        return [named containsObject:@(panelID)];
    }
    if ([tabs containsObject:@(panelID)]) {
        return NO;
    }
    id switches = PFBSidebarSend(account, @"featureSwitches");
    id accountSwitches = PFBSidebarSend(account, @"accountFeatureSwitches");
    switch (panelID) {
        case 17:
            return PFBSidebarFlag(account, @"canAccessXPayments") || PFBSidebarFlag(accountSwitches, @"isPaymentsEnabled");
        case 20:
            return PFBSidebarNewsTab(switches);
        case 16:
            return PFBSidebarSwitch(switches, @"recruiting_global_jobs_hub_enabled");
        case 13:
            return PFBSidebarFlag(accountSwitches, @"birdwatchHomePageIsEnabled") &&
                   PFBSidebarFlag(accountSwitches, @"birdwatchHistoryIsEnabled");
        case 19:
            return !PFBSidebarFlag(account, @"isPremiumTierUser") && !PFBSidebarFlag(account, @"isVerifiedOrganizationAccount") &&
                   !PFBSidebarFlag(account, @"isBusinessOrAffiliateAccount") &&
                   PFBSidebarSwitch(switches, @"dash_items_account_analytics_enabled");
        case 12:
            return PFBSidebarSwitch(switches, @"creator_monetization_dashboard_enabled") ||
                   PFBSidebarSwitch(switches, @"creator_studio_nav_enabled");
        case 21:
            return PFBSidebarSwitch(switches, @"premium_business_ios_nav_promo_enabled");
        default: // Profile, Premium, Lists and Chat: there whenever off the tab bar
            return YES;
    }
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

// Premium, Analytics and Creator Studio carry the titles their rows show, not the panel table's.
+ (NSString*)nameForPanel:(NSInteger)panelID {
    NSString* title = nil;
    if (panelID == 15) {
        title = PFBSidebarTwitterString(@"SUBSCRIPTION_TITLE");
    } else if (panelID == 19) {
        title = PFBSidebarTwitterString(@"DASH_ANALYTICS_TITLE");
    } else if (panelID == 12 && gPFBSidebarCreatorStudio) {
        title = PFBSidebarTwitterString(@"CREATOR_STUDIO_TITLE");
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
    NSString* key = PFBPanelIdentityAnswer(@"stringForPanelID:", panelID);
    NSArray* hidden = [[NSUserDefaults standardUserDefaults] arrayForKey:kHiddenKey];
    return key && [hidden containsObject:key];
}

+ (void)setPanel:(NSInteger)panelID hidden:(BOOL)hidden {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    if (panelID == PFBSidebarGrokPanel) {
        [defaults setBool:hidden forKey:@"hide_grok_sidebar"];
    } else {
        NSString* key = PFBPanelIdentityAnswer(@"stringForPanelID:", panelID);
        if (!key) {
            return;
        }
        NSMutableArray* keys = [[defaults arrayForKey:kHiddenKey] mutableCopy] ?: [NSMutableArray array];
        [keys removeObject:key];
        if (hidden) {
            [keys addObject:key];
        }
        [defaults setObject:keys forKey:kHiddenKey];
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
    [defaults removeObjectForKey:@"hide_grok_sidebar"];
    [self changed];
}

+ (void)changed {
    PFBDashRefresh();
    [[NSNotificationCenter defaultCenter] postNotificationName:PFBSidebarItemsDidChangeNotification object:nil];
}

// MARK: - Twitter's sidebar

// Kept before the tweak's own rebuild follows, so that rebuild already leaves out what only the
// unlock adds.
+ (BOOL)measureNative {
    __block BOOL namedAny = NO;
    PFBDashMeasurement result = PFBDashMeasure(^(NSArray<NSNumber*>* tabs, NSArray<NSNumber*>* named) {
      // History and Communities are named whenever off the tab bar: a rebuild naming nothing
      // measured nothing.
      namedAny = named.count > 0;
      if (!namedAny) {
          return;
      }
      id account = PFBSidebarAccount();
      NSMutableArray<NSNumber*>* panels = [NSMutableArray array];
      for (NSNumber* panel in [self catalog]) {
          if (PFBSidebarIsShown(panel.integerValue, tabs, named, account)) {
              [panels addObject:panel];
          }
      }
      gPFBSidebarCreatorStudio =
          !PFBSidebarSwitch(PFBSidebarSend(account, @"featureSwitches"), @"creator_monetization_dashboard_enabled");
      gPFBSidebarNative = panels;
      [[NSUserDefaults standardUserDefaults] setObject:PFBKeysForPanels(panels) forKey:kNativeKey];
    });
    if (result == PFBDashMeasurementNoSidebar) {
        return NO;
    }
    if (result == PFBDashMeasurementNotRebuilt) {
        PFBCompatNoteFailure(PFBCompat_customize_sidebar, @"sidebar not rebuilt to measure it");
    } else if (!namedAny) {
        PFBCompatNoteFailure(PFBCompat_customize_sidebar, @"no item named while Twitter rebuilt the sidebar");
    } else {
        PFBCOMPAT_OBSERVE(PFBCompat_customize_sidebar, @"Twitter's sidebar measured");
    }
    return YES;
}

// The last measure, kept across launches; nil before the first.
+ (NSArray<NSNumber*>*)nativePanels {
    if (gPFBSidebarNative) {
        return gPFBSidebarNative;
    }
    NSArray* stored = [[NSUserDefaults standardUserDefaults] arrayForKey:kNativeKey];
    return stored ? PFBPanelsForKeys(stored) : nil;
}

+ (NSArray<NSNumber*>*)panelsForPage {
    NSMutableArray<NSNumber*>* panels = [NSMutableArray array];
    for (NSNumber* panel in [self nativePanels]) {
        if ([self nameForPanel:panel.integerValue]) {
            [panels addObject:panel];
        }
    }
    return panels;
}

+ (NSArray<NSNumber*>*)unlockedPanelIDs {
    NSArray<NSNumber*>* native = [self nativePanels];
    NSMutableArray<NSNumber*>* panels = [NSMutableArray array];
    for (NSNumber* panel in native ? PFBSidebarUnlockGated() : @[]) {
        if (![native containsObject:panel]) {
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

// A hidden or unlocked item Twitter named as it built, or one missing from the list the drawer
// kept, is still in the sidebar.
+ (void)endBuildOfContent:(id)content {
    NSArray<NSNumber*>* built = gPFBSidebarBuilding;
    gPFBSidebarBuilding = nil;
    NSArray<NSNumber*>* kept = PFBDashSnapshot(content);
    for (NSNumber* panel in [[self hiddenPanelIDs] arrayByAddingObjectsFromArray:[self unlockedPanelIDs]]) {
        if ([built containsObject:panel] || (kept && ![kept containsObject:panel])) {
            [self noteFailureOf:panel state:@"still in the sidebar"];
        }
    }
}

+ (void)noteFailureOf:(NSNumber*)panel state:(NSString*)state {
    NSString* name = [self nameForPanel:panel.integerValue] ?: panel.stringValue;
    PFBCompatNoteFailure(PFBCompat_customize_sidebar, [NSString stringWithFormat:@"%@ %@", name, state]);
}

@end
