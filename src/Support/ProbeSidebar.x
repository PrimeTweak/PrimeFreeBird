// Probe for the sidebar: Twitter's rebuild on its own, with nothing from the tweak, each item's
// conditions as Twitter gets them and as they are, then the tweak's rebuild. Removed once read.

#import "Features/Appearance/Sidebar/PFBSidebarItems.h"
#import "Support/HookHelpers.h"

typedef NS_ENUM(NSInteger, PFBProbePass) {
    PFBProbePassNone,
    PFBProbePassTwitter,
    PFBProbePassTweak,
};

static CFTimeInterval gProbeStart;
static PFBProbePass gProbePass;
static NSInteger gProbeUpdateDepth;
static BOOL gProbeMenuOpen;
static BOOL gProbePending;
static BOOL gProbeDone;
static __weak id gProbeContent;
static NSArray* gProbeTabs;
static NSArray* gProbeAnswered;
static NSMutableArray<NSNumber*>* gProbeTwitterBuilt;
static NSMutableArray<NSString*>* gProbeTwitterCallers;
static NSMutableArray<NSNumber*>* gProbeTweakBuilt;

static NSString* pfbProbeNow(void) {
    return [NSString stringWithFormat:@"+%.1f s", CACurrentMediaTime() - gProbeStart];
}

static void pfbProbe(NSString* line) {
    PFBCompatMeasure(@"probe sidebar", line, 60);
}

static NSString* pfbProbeName(NSInteger panelID) {
    return panelID > 0 && panelID <= 25 ? [PFBSidebarItems nameForPanel:panelID] ?: @"-" : @"-";
}

// Panels by number and Twitter's name, as a list reads them.
static NSString* pfbProbePanels(NSArray* panels) {
    if (!panels) {
        return @"unknown";
    }
    NSMutableArray<NSString*>* items = [NSMutableArray array];
    for (id panel in [panels isKindOfClass:[NSArray class]] ? panels : @[]) {
        NSInteger panelID = [panel respondsToSelector:@selector(integerValue)] ? [panel integerValue] : 0;
        [items addObject:[NSString stringWithFormat:@"%ld %@", (long)panelID, pfbProbeName(panelID)]];
    }
    return items.count ? [items componentsJoinedByString:@", "] : @"none";
}

// The first caller outside this tweak, as its image and its address there.
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

// MARK: - Reading the conditions

static id pfbProbeSend(id receiver, NSString* selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    return [receiver respondsToSelector:selector] ? ((id (*)(id, SEL))objc_msgSend)(receiver, selector) : nil;
}

static id pfbProbeAccount(void) {
    return pfbProbeSend(pfbProbeSend(NSClassFromString(@"T1HostViewController"), @"sharedHostViewController"),
                        @"currentAccount");
}

static NSString* pfbProbeFlag(id receiver, NSString* selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    if (![receiver respondsToSelector:selector]) {
        return @"?";
    }
    return ((BOOL (*)(id, SEL))objc_msgSend)(receiver, selector) ? @"1" : @"0";
}

static NSString* pfbProbeSwitch(id switches, NSString* key) {
    SEL reader = NSSelectorFromString(@"boolForKey:");
    if (![switches respondsToSelector:reader]) {
        return @"?";
    }
    return ((BOOL (*)(id, SEL, id))objc_msgSend)(switches, reader, key) ? @"1" : @"0";
}

static NSString* pfbProbeCount(id switches, NSString* key) {
    SEL reader = NSSelectorFromString(@"integerForKey:");
    if (![switches respondsToSelector:reader]) {
        return @"?";
    }
    return [NSString stringWithFormat:@"%ld", (long)((NSInteger (*)(id, SEL, id))objc_msgSend)(switches, reader, key)];
}

static NSString* pfbProbeNewsTab(id switches) {
    Class features = NSClassFromString(@"T1ExploreFeatures");
    SEL initializer = NSSelectorFromString(@"initWithFeatureSwitches:");
    if (!switches || ![features instancesRespondToSelector:initializer]) {
        return @"?";
    }
    id explore = ((id (*)(id, SEL, id))objc_msgSend)([features alloc], initializer, switches);
    return pfbProbeFlag(explore, @"enableNewsTab");
}

// Each item's conditions as Twitter 12.42.1 reads them, in the sidebar's order: item, condition.
static NSArray<NSArray<NSString*>*>* pfbProbeConditionList(void) {
    return @[
        @[ @"Grok", @"subscriptions_inapp_grok" ], @[ @"Grok", @"subscriptions_inapp_grok_upsell_enabled" ],
        @[ @"Money", @"canAccessXPayments" ], @[ @"Money", @"isPaymentsEnabled" ],
        @[ @"Boost", @"boost_tab_enabled" ], @[ @"News", @"enableNewsTab" ],
        @[ @"Downloads", @"isVideoCacheActivityHistoryEnabled" ],
        @[ @"Jobs", @"recruiting_global_jobs_hub_enabled" ],
        @[ @"Community Notes", @"birdwatchHomePageIsEnabled" ], @[ @"Community Notes", @"birdwatchHistoryIsEnabled" ],
        @[ @"Follow", @"ios_tab_bar_connect_tab_max_followings_count" ],
        @[ @"Follow", @"ios_dash_connect_max_followings_count" ],
        @[ @"Spaces", @"voice_rooms_consumption_enabled" ],
        @[ @"Analytics", @"isPremiumTierUser" ], @[ @"Analytics", @"isVerifiedOrganizationAccount" ],
        @[ @"Analytics", @"isBusinessOrAffiliateAccount" ], @[ @"Analytics", @"dash_items_account_analytics_enabled" ],
        @[ @"Creator Studio", @"creator_monetization_dashboard_enabled" ],
        @[ @"Creator Studio", @"creator_studio_nav_enabled" ],
        @[ @"Business", @"premium_business_ios_nav_promo_enabled" ],
    ];
}

// The conditions' values now: "1", "0", a count, or "?" when unreadable.
static NSDictionary<NSString*, NSString*>* pfbProbeConditions(void) {
    id account = pfbProbeAccount();
    id switches = pfbProbeSend(account, @"featureSwitches");
    id accountSwitches = pfbProbeSend(account, @"accountFeatureSwitches");
    NSSet<NSString*>* accountFlags = [NSSet setWithArray:@[
        @"canAccessXPayments", @"isPremiumTierUser", @"isVerifiedOrganizationAccount", @"isBusinessOrAffiliateAccount"
    ]];
    NSSet<NSString*>* switchFlags = [NSSet setWithArray:@[
        @"isPaymentsEnabled", @"isVideoCacheActivityHistoryEnabled", @"birdwatchHomePageIsEnabled",
        @"birdwatchHistoryIsEnabled"
    ]];
    NSMutableDictionary<NSString*, NSString*>* values = [NSMutableDictionary dictionary];
    for (NSArray<NSString*>* condition in pfbProbeConditionList()) {
        NSString* name = condition[1];
        if ([accountFlags containsObject:name]) {
            values[name] = pfbProbeFlag(account, name);
        } else if ([switchFlags containsObject:name]) {
            values[name] = pfbProbeFlag(accountSwitches, name);
        } else if ([name isEqualToString:@"enableNewsTab"]) {
            values[name] = pfbProbeNewsTab(switches);
        } else if ([name hasSuffix:@"_count"]) {
            values[name] = pfbProbeCount(switches, name);
        } else {
            values[name] = pfbProbeSwitch(switches, name);
        }
    }
    return values;
}

// MARK: - Twitter's sidebar without the tweak

// The panels in Twitter's order (T1Twitter 12.42.1 +0x9fc790); Twitter skips each one that is in
// the tab bar, Follow aside.
static NSArray<NSNumber*>* pfbProbeOrder(void) {
    return @[ @8, @15, @14, @17, @24, @23, @25, @9, @20, @18, @16, @7, @13, @4, @5, @2, @22, @11, @19, @12, @21 ];
}

// The items whose builders ask Twitter's panel table for their name once they keep them.
static BOOL pfbProbeNamedWhenBuilt(NSInteger panelID) {
    return panelID == 2 || panelID == 5 || panelID == 9 || panelID == 11 || panelID == 14 || panelID == 18 ||
           panelID == 22 || panelID == 23 || panelID == 24 || panelID == 25;
}

// Whether Twitter put a panel in its own rebuild: seen as it names it, always there off the tab bar,
// or from the conditions it reads.
static NSString* pfbProbeNative(NSInteger panelID, NSArray<NSNumber*>* tabs, NSArray<NSNumber*>* built,
                                NSDictionary<NSString*, NSString*>* real) {
    if (pfbProbeNamedWhenBuilt(panelID)) {
        return [built containsObject:@(panelID)] ? @"in (built)" : @"out (not built)";
    }
    if (!tabs) {
        return @"unknown (tab bar unread)";
    }
    if ([tabs containsObject:@(panelID)]) {
        return @"out (tab bar)";
    }
    BOOL (^on)(NSString*) = ^BOOL(NSString* name) {
      return [real[name] isEqualToString:@"1"];
    };
    BOOL (^off)(NSString*) = ^BOOL(NSString* name) {
      return [real[name] isEqualToString:@"0"];
    };
    BOOL (^known)(NSArray<NSString*>*) = ^BOOL(NSArray<NSString*>* names) {
      for (NSString* name in names) {
          if ([real[name] isEqualToString:@"?"]) {
              return NO;
          }
      }
      return YES;
    };
    NSArray<NSString*>* needs = nil;
    BOOL kept = YES;
    switch (panelID) {
        case 4:
        case 7:
        case 8:
        case 15:
            return @"in (always)";
        case 17:
            needs = @[ @"canAccessXPayments", @"isPaymentsEnabled" ];
            kept = on(@"canAccessXPayments") || on(@"isPaymentsEnabled");
            break;
        case 20:
            needs = @[ @"enableNewsTab" ];
            kept = on(@"enableNewsTab");
            break;
        case 16:
            needs = @[ @"recruiting_global_jobs_hub_enabled" ];
            kept = on(@"recruiting_global_jobs_hub_enabled");
            break;
        case 13:
            needs = @[ @"birdwatchHomePageIsEnabled", @"birdwatchHistoryIsEnabled" ];
            kept = on(@"birdwatchHomePageIsEnabled") && on(@"birdwatchHistoryIsEnabled");
            break;
        case 19:
            needs = @[ @"isPremiumTierUser", @"isVerifiedOrganizationAccount", @"isBusinessOrAffiliateAccount",
                       @"dash_items_account_analytics_enabled" ];
            kept = off(@"isPremiumTierUser") && off(@"isVerifiedOrganizationAccount") &&
                   off(@"isBusinessOrAffiliateAccount") && on(@"dash_items_account_analytics_enabled");
            break;
        case 12:
            needs = @[ @"creator_monetization_dashboard_enabled", @"creator_studio_nav_enabled" ];
            kept = on(@"creator_monetization_dashboard_enabled") || on(@"creator_studio_nav_enabled");
            break;
        case 21:
            needs = @[ @"premium_business_ios_nav_promo_enabled" ];
            kept = on(@"premium_business_ios_nav_promo_enabled");
            break;
        default:
            return @"unknown";
    }
    if (!known(needs)) {
        return @"unknown (condition unread)";
    }
    return kept ? @"in (conditions)" : @"out (conditions)";
}

// The tab bar's list with its first panel repeated, for Twitter's own rebuild only: the drawer then
// sees a new list and rebuilds, with no panel more or less.
static NSArray* pfbProbeAnswer(NSArray* panelIDs) {
    if (gProbePass != PFBProbePassTwitter || !gProbeUpdateDepth || ![panelIDs isKindOfClass:[NSArray class]] ||
        !panelIDs.count || [panelIDs isEqualToArray:gProbeAnswered ?: @[]]) {
        return panelIDs;
    }
    gProbeTabs = [panelIDs copy];
    gProbeAnswered = [panelIDs arrayByAddingObject:panelIDs.firstObject];
    return gProbeAnswered;
}

static void pfbProbeRun(void) {
    if (gProbeDone) {
        return;
    }
    if (gProbeMenuOpen) {
        gProbePending = YES;
        return;
    }
    gProbePending = NO;
    NSDictionary<NSString*, NSString*>* seen = pfbProbeConditions();

    gProbeContent = nil;
    gProbeTabs = nil;
    gProbeAnswered = nil;
    [gProbeTwitterBuilt removeAllObjects];
    [gProbeTwitterCallers removeAllObjects];
    PFBBeginTwitterOnlyReads();
    PFBBeginRawVerifiedRead();
    gProbePass = PFBProbePassTwitter;
    CFTimeInterval started = CACurrentMediaTime();
    PFBDashRefresh();
    CFTimeInterval took = CACurrentMediaTime() - started;
    id content = gProbeContent;
    NSArray<NSNumber*>* twitterDrawer = PFBDashSnapshot(content);
    NSDictionary<NSString*, NSString*>* real = pfbProbeConditions();
    gProbePass = PFBProbePassNone;
    PFBEndRawVerifiedRead();
    PFBEndTwitterOnlyReads();

    if (!content) {
        gProbePending = YES;
        pfbProbe([NSString stringWithFormat:@"%@ no sidebar to rebuild yet: again when the menu closes", pfbProbeNow()]);
        return;
    }
    gProbeDone = YES;

    [gProbeTweakBuilt removeAllObjects];
    gProbePass = PFBProbePassTweak;
    PFBDashRefresh();
    gProbePass = PFBProbePassNone;
    NSArray<NSNumber*>* tweakDrawer = PFBDashSnapshot(content);

    NSString* now = pfbProbeNow();
    NSString* rebuilt = @"not rebuilt";
    if (!twitterDrawer) {
        rebuilt = @"drawer list unreadable";
    } else if (gProbeAnswered && [twitterDrawer isEqualToArray:gProbeAnswered]) {
        rebuilt = @"rebuilt";
    }
    pfbProbe([NSString stringWithFormat:@"%@ Twitter's own rebuild: %@ in %.0f ms; tab bar %@; drawer list %@", now,
                                        rebuilt, took * 1000, pfbProbePanels(gProbeTabs), pfbProbePanels(twitterDrawer)]);

    NSMutableArray<NSString*>* named = [NSMutableArray array];
    [gProbeTwitterBuilt enumerateObjectsUsingBlock:^(NSNumber* panel, NSUInteger index, BOOL* stop) {
      NSString* caller = index < gProbeTwitterCallers.count ? gProbeTwitterCallers[index] : @"?";
      [named addObject:[NSString stringWithFormat:@"%@ %@ (%@)", panel, pfbProbeName(panel.integerValue), caller]];
    }];
    pfbProbe([NSString stringWithFormat:@"%@ named by Twitter as it built: %@", now,
                                        named.count ? [named componentsJoinedByString:@", "] : @"none"]);

    NSMutableArray<NSString*>* native = [NSMutableArray array];
    for (NSNumber* panel in pfbProbeOrder()) {
        [native addObject:[NSString stringWithFormat:@"%@ %@ %@", panel, pfbProbeName(panel.integerValue),
                                                     pfbProbeNative(panel.integerValue, gProbeTabs, gProbeTwitterBuilt, real)]];
    }
    pfbProbe([NSString stringWithFormat:@"%@ Twitter's sidebar: %@", now, [native componentsJoinedByString:@"; "]]);

    NSMutableArray<NSString*>* conditions = [NSMutableArray array];
    for (NSArray<NSString*>* condition in pfbProbeConditionList()) {
        [conditions addObject:[NSString stringWithFormat:@"%@ %@ %@/%@", condition[0], condition[1],
                                                         seen[condition[1]], real[condition[1]]]];
    }
    pfbProbe([NSString stringWithFormat:@"%@ conditions, with the tweak/real: %@", now,
                                        [conditions componentsJoinedByString:@", "]]);

    pfbProbe([NSString stringWithFormat:@"%@ tweak's rebuild: drawer list %@; named %@; hidden %@; tab items added %@; "
                                        @"hide_grok_sidebar %@, hide_blue_verified %@",
                                        now, pfbProbePanels(tweakDrawer), pfbProbePanels(gProbeTweakBuilt),
                                        pfbProbePanels([PFBSidebarItems hiddenPanelIDs]),
                                        pfbProbePanels([PFBSidebarItems tabPanelsInSidebar]),
                                        [PFBSettings boolForKey:@"hide_grok_sidebar"] ? @"on" : @"off",
                                        [PFBSettings boolForKey:@"hide_blue_verified"] ? @"on" : @"off"]);
}

// MARK: - Hooks

%hook T1DashContentController

- (void)updateVisiblePanelIDs {
    if (gProbePass != PFBProbePassNone) {
        gProbeContent = self;
    }
    gProbeUpdateDepth++;
    %orig;
    gProbeUpdateDepth--;
}

%end

// The items Twitter names as it builds them, in each of the probe's two rebuilds.
%hook T1PanelIdentity

+ (NSString*)localizedNameForPanelID:(long long)panelID {
    if (gProbePass != PFBProbePassNone && gProbeUpdateDepth) {
        BOOL twitter = gProbePass == PFBProbePassTwitter;
        NSMutableArray<NSNumber*>* built = twitter ? gProbeTwitterBuilt : gProbeTweakBuilt;
        if (![built containsObject:@(panelID)]) {
            [built addObject:@(panelID)];
            if (twitter) {
                [gProbeTwitterCallers addObject:pfbProbeCaller()];
            }
        }
    }
    return %orig;
}

%end

// Run with the menu closed, so neither rebuild shows.
%hook T1DashContentPresenter

- (void)dashDidSettleOpen:(BOOL)open {
    gProbeMenuOpen = open;
    %orig;
    if (!open && gProbePending) {
        dispatch_async(dispatch_get_main_queue(), ^{
          pfbProbeRun();
        });
    }
}

%end

%hook T1TabbedAppNavigationViewController

- (NSArray*)visiblePanelIDsForAppNavigation:(id)appNavigation {
    return pfbProbeAnswer(%orig);
}

%end

%hook _TtC14T1TwitterSwift20XTabbedAppNavigation

- (NSArray*)visiblePanelIDs {
    return pfbProbeAnswer(%orig);
}

%end

%ctor {
    gProbeStart = CACurrentMediaTime();
    gProbeTwitterBuilt = [NSMutableArray array];
    gProbeTwitterCallers = [NSMutableArray array];
    gProbeTweakBuilt = [NSMutableArray array];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      pfbProbeRun();
    });
}
