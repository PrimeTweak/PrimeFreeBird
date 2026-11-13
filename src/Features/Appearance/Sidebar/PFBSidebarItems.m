// The sidebar's items as Twitter's panels: names and glyphs from Twitter's panel table, the
// choices stored by Twitter's panel name, and what each rebuild of the sidebar kept.

#import "Features/Appearance/Sidebar/PFBSidebarItems.h"
#import <dlfcn.h>
#import <mach-o/loader.h>
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
static BOOL gPFBSidebarAnalyticsAsked;

// Analytics is shown only to an account that is not Premium. In T1Twitter 12.42.1, the build with
// this UUID, its builder asks once, from the call returning to this offset.
static const NSInteger kAnalyticsPanel = 19;
static const uintptr_t kAnalyticsPremiumReturn = 0xa01ecc;
static const uint8_t kT1Twitter1242UUID[16] = {0xBB, 0x9C, 0xD0, 0x55, 0xAE, 0xFC, 0x31, 0xEC,
                                               0xB9, 0x34, 0x1C, 0x11, 0x79, 0x31, 0x93, 0x3F};

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

// T1Twitter's load address when it is 12.42.1's build, where Analytics' check is known; 0 otherwise.
static uintptr_t PFBSidebarT1TwitterBase(void) {
    static uintptr_t base;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      Class dash = NSClassFromString(@"T1DashContentController");
      Dl_info info;
      if (!dash || !dladdr((__bridge const void*)dash, &info) || !info.dli_fbase) {
          return;
      }
      const struct mach_header_64* header = (const struct mach_header_64*)info.dli_fbase;
      const uint8_t* cursor = (const uint8_t*)(header + 1);
      for (uint32_t i = 0; header->magic == MH_MAGIC_64 && i < header->ncmds; i++) {
          const struct load_command* command = (const struct load_command*)cursor;
          if (command->cmd == LC_UUID) {
              if (!memcmp(((const struct uuid_command*)command)->uuid, kT1Twitter1242UUID, 16)) {
                  base = (uintptr_t)header;
              }
              return;
          }
          cursor += command->cmdsize;
      }
    });
    return base;
}

// Downloads and Boost stay as Twitter shows them: they depend on downloads and badges the account
// has. Analytics is offered where its check is known.
static BOOL PFBSidebarIsOffered(NSInteger panelID) {
    if (panelID == kAnalyticsPanel) {
        return PFBSidebarT1TwitterBase() != 0;
    }
    return panelID != 18 && panelID != 23;
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

// The signed-in account, as Twitter's sidebar reads it.
static id PFBSidebarAccount(void) {
    Class hostClass = NSClassFromString(@"T1HostViewController");
    SEL shared = NSSelectorFromString(@"sharedHostViewController");
    SEL current = NSSelectorFromString(@"currentAccount");
    if (![hostClass respondsToSelector:shared]) {
        return nil;
    }
    id host = ((id (*)(id, SEL))objc_msgSend)(hostClass, shared);
    return [host respondsToSelector:current] ? ((id (*)(id, SEL))objc_msgSend)(host, current) : nil;
}

static id PFBSidebarAccountSwitches(void) {
    id account = PFBSidebarAccount();
    SEL switches = NSSelectorFromString(@"featureSwitches");
    return [account respondsToSelector:switches] ? ((id (*)(id, SEL))objc_msgSend)(account, switches) : nil;
}

// Twitter keeps Analytics from organizations and business accounts before it asks for Premium.
static BOOL PFBSidebarAccountIsBusiness(void) {
    id account = PFBSidebarAccount();
    for (NSString* name in @[ @"isVerifiedOrganizationAccount", @"isBusinessOrAffiliateAccount" ]) {
        SEL selector = NSSelectorFromString(name);
        if ([account respondsToSelector:selector] && ((BOOL (*)(id, SEL))objc_msgSend)(account, selector)) {
            return YES;
        }
    }
    return NO;
}

// The choice made on the page for a panel, nil when none was made.
static NSNumber* PFBSidebarChoice(NSInteger panelID) {
    NSString* key = PFBPanelIdentityAnswer(@"stringForPanelID:", panelID);
    id choice = key ? [[NSUserDefaults standardUserDefaults] dictionaryForKey:kChoicesKey][key] : nil;
    return [choice isKindOfClass:[NSNumber class]] ? choice : nil;
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

// Premium, Analytics and Creator Studio carry the titles their rows show, not the panel table's;
// the Creator Studio row turns into Monetization when that switch is on.
+ (NSString*)nameForPanel:(NSInteger)panelID {
    NSString* title = nil;
    if (panelID == 15) {
        title = PFBSidebarTwitterString(@"SUBSCRIPTION_TITLE");
    } else if (panelID == kAnalyticsPanel) {
        title = PFBSidebarTwitterString(@"DASH_ANALYTICS_TITLE");
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
    NSNumber* choice = PFBSidebarChoice(panelID);
    return !(choice ? choice.boolValue : PFBSidebarShownByDefault(panelID));
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

+ (BOOL)showsAnalytics {
    return PFBSidebarIsOffered(kAnalyticsPanel) && ![self isHidden:kAnalyticsPanel];
}

+ (BOOL)isAnalyticsPremiumCheck:(const void*)returnAddress {
    uintptr_t base = PFBSidebarT1TwitterBase();
    if (!base || (uintptr_t)returnAddress - base != kAnalyticsPremiumReturn || ![self showsAnalytics]) {
        return NO;
    }
    gPFBSidebarAnalyticsAsked = YES;
    PFBCOMPAT_ACTION(PFBCompat_customize_sidebar, @"Analytics shown");
    return YES;
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
    gPFBSidebarAnalyticsAsked = NO;
}

+ (void)noteBuiltPanel:(NSInteger)panelID {
    if (PFBSidebarIsNamedWhenBuilt(panelID) && ![gPFBSidebarBuilding containsObject:@(panelID)]) {
        [gPFBSidebarBuilding addObject:@(panelID)];
    }
}

// A hidden item Twitter named, or one missing from the list the drawer kept, is still in the
// sidebar; a rebuild that named items and not a shown one Twitter always builds left it out, as
// one where Analytics, shown, never asked its check of a personal account.
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
    if (built.count && [self showsAnalytics] && ![tabs containsObject:@(kAnalyticsPanel)] && !gPFBSidebarAnalyticsAsked &&
        !PFBSidebarAccountIsBusiness()) {
        [self noteFailureOf:@(kAnalyticsPanel) state:@"missing from the sidebar"];
    }
    if (!PFBSidebarIsOffered(kAnalyticsPanel) && PFBSidebarChoice(kAnalyticsPanel).boolValue) {
        PFBCompatNoteFailure(PFBCompat_customize_sidebar, @"Analytics not offered: T1Twitter is not 12.42.1's build");
    }
}

+ (void)noteFailureOf:(NSNumber*)panel state:(NSString*)state {
    NSString* name = [self nameForPanel:panel.integerValue] ?: panel.stringValue;
    PFBCompatNoteFailure(PFBCompat_customize_sidebar, [NSString stringWithFormat:@"%@ %@", name, state]);
}

@end
