// Probe for the sidebar's last three items: whether Downloads, Boost and Analytics show once the
// conditions Twitter reads for them are forced, in one rebuild of the sidebar. Removed once read.

#import "Features/Appearance/Sidebar/PFBSidebarItems.h"
#import "Support/HookHelpers.h"

static CFTimeInterval gProbeStart;
static BOOL gProbeForcing;
static NSInteger gProbeUpdateDepth;
static BOOL gProbeMenuOpen;
static BOOL gProbePending;
static BOOL gProbeDone;
static __weak id gProbeContent;
static NSArray* gProbeAnswered;
static NSMutableArray<NSNumber*>* gProbeNamed;
static NSMutableArray<NSString*>* gProbeDefaultsCallers;

static NSString* pfbProbeNow(void) {
    return [NSString stringWithFormat:@"+%.1f s", CACurrentMediaTime() - gProbeStart];
}

static void pfbProbe(NSString* line) {
    PFBCompatMeasure(@"probe sidebar", line, 40);
}

// True while the forced rebuild runs: the hooks below answer only then.
static BOOL pfbProbeForces(void) {
    return gProbeForcing && gProbeUpdateDepth > 0;
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

static id pfbProbeSend(id receiver, NSString* selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    return [receiver respondsToSelector:selector] ? ((id (*)(id, SEL))objc_msgSend)(receiver, selector) : nil;
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

// The conditions as Twitter gets them now, with the tweak.
static NSString* pfbProbeConditions(void) {
    id account = pfbProbeSend(pfbProbeSend(NSClassFromString(@"T1HostViewController"), @"sharedHostViewController"),
                              @"currentAccount");
    id switches = pfbProbeSend(account, @"featureSwitches");
    id user = pfbProbeSend(account, @"user");
    SEL identity = NSSelectorFromString(@"identityType");
    NSString* identityType = [user respondsToSelector:identity]
                                 ? [NSString stringWithFormat:@"%ld", (long)((NSInteger (*)(id, SEL))objc_msgSend)(user, identity)]
                                 : @"?";
    return [NSString stringWithFormat:@"isVideoCacheActivityHistoryEnabled %@; user %@ verified %@, isBlueVerified %@, "
                                      @"identityType %@; boost_tab_enabled %@; isPremiumTierUser %@, "
                                      @"dash_items_account_analytics_enabled %@",
                                      pfbProbeFlag(pfbProbeSend(account, @"accountFeatureSwitches"), @"isVideoCacheActivityHistoryEnabled"),
                                      user ? NSStringFromClass([user class]) : @"none", pfbProbeFlag(user, @"verified"),
                                      pfbProbeSend(user, @"isBlueVerified") ?: @"nil", identityType,
                                      pfbProbeSwitch(switches, @"boost_tab_enabled"), pfbProbeFlag(account, @"isPremiumTierUser"),
                                      pfbProbeSwitch(switches, @"dash_items_account_analytics_enabled")];
}

// The tab bar's list with its first panel repeated, for the forced rebuild only: the drawer then
// sees a new list and rebuilds, with no panel more or less.
static NSArray* pfbProbeAnswer(NSArray* panelIDs) {
    if (!pfbProbeForces() || ![panelIDs isKindOfClass:[NSArray class]] || !panelIDs.count ||
        [panelIDs isEqualToArray:gProbeAnswered ?: @[]]) {
        return panelIDs;
    }
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
    NSString* before = pfbProbeConditions();
    gProbeContent = nil;
    gProbeAnswered = nil;
    [gProbeNamed removeAllObjects];
    [gProbeDefaultsCallers removeAllObjects];
    gProbeForcing = YES;
    CFTimeInterval started = CACurrentMediaTime();
    PFBDashRefresh();
    CFTimeInterval took = CACurrentMediaTime() - started;
    gProbeForcing = NO;
    id content = gProbeContent;
    if (!content) {
        gProbePending = YES;
        pfbProbe([NSString stringWithFormat:@"%@ no sidebar to rebuild yet: again when the menu closes", pfbProbeNow()]);
        return;
    }
    gProbeDone = YES;
    NSArray<NSNumber*>* kept = PFBDashSnapshot(content);
    PFBDashRefresh();

    // Analytics reads the account's defaults from its builder (T1Twitter 12.42.1 +0xa01e04..+0xa0214c).
    BOOL analytics = NO;
    for (NSString* caller in gProbeDefaultsCallers) {
        unsigned long long offset = 0;
        if ([caller hasPrefix:@"T1Twitter+"] &&
            [[NSScanner scannerWithString:[caller substringFromIndex:10]] scanHexLongLong:&offset]) {
            analytics = analytics || (offset >= 0xa01e04 && offset < 0xa0214c);
        }
    }
    NSString* now = pfbProbeNow();
    NSString* rebuilt = kept && [kept isEqualToArray:gProbeAnswered ?: @[]] ? @"rebuilt" : @"not rebuilt";
    pfbProbe([NSString stringWithFormat:@"%@ forced rebuild: %@ in %.0f ms; named %@; account defaults read from %@", now,
                                        rebuilt, took * 1000, gProbeNamed.count ? [gProbeNamed componentsJoinedByString:@", "] : @"none",
                                        gProbeDefaultsCallers.count ? [gProbeDefaultsCallers componentsJoinedByString:@", "] : @"nowhere"]);
    pfbProbe([NSString stringWithFormat:@"%@ forced: Downloads %@, Boost %@, Analytics %@", now,
                                        [gProbeNamed containsObject:@18] ? @"shown" : @"not shown",
                                        [gProbeNamed containsObject:@23] ? @"shown" : @"not shown",
                                        analytics ? @"shown" : @"not shown"]);
    pfbProbe([NSString stringWithFormat:@"%@ conditions before forcing: %@", now, before]);
}

// MARK: - Hooks

%hook T1DashContentController

- (void)updateVisiblePanelIDs {
    if (gProbeForcing) {
        gProbeContent = self;
    }
    gProbeUpdateDepth++;
    %orig;
    gProbeUpdateDepth--;
}

%end

%hook T1PanelIdentity

+ (NSString*)localizedNameForPanelID:(long long)panelID {
    if (pfbProbeForces() && ![gProbeNamed containsObject:@(panelID)]) {
        [gProbeNamed addObject:@(panelID)];
    }
    return %orig;
}

%end

%hook TFSAccountUserDefaults

+ (id)sharedAccountUserDefaultsForAccountID:(id)accountID {
    if (pfbProbeForces()) {
        [gProbeDefaultsCallers addObject:pfbProbeCaller()];
    }
    return %orig;
}

%end

// Downloads: shown when the video cache history lives outside Activity, and there are downloads.
%hook TFSAccountFeatureSwitches

- (BOOL)isVideoCacheActivityHistoryEnabled {
    return pfbProbeForces() ? NO : %orig;
}

%end

// Analytics: shown to an account that is not Premium, with its switch on.
%hook TFNTwitterAccount

- (BOOL)isPremiumTierUser {
    return pfbProbeForces() ? NO : %orig;
}

%end

%hook TFSFeatureSwitches

- (BOOL)boolForKey:(NSString*)key {
    if (pfbProbeForces() && ([key isEqual:@"dash_items_account_analytics_enabled"] || [key isEqual:@"boost_tab_enabled"])) {
        return YES;
    }
    return %orig;
}

%end

%hook TFSInstrumentedFeatureSwitches

- (BOOL)boolForKey:(NSString*)key {
    if (pfbProbeForces() && ([key isEqual:@"dash_items_account_analytics_enabled"] || [key isEqual:@"boost_tab_enabled"])) {
        return YES;
    }
    return %orig;
}

%end

// Boost: shown to an account with a verified badge.
%hook TFSTwitterUser

- (BOOL)verified {
    return pfbProbeForces() ? YES : %orig;
}

- (id)isBlueVerified {
    return pfbProbeForces() ? @YES : %orig;
}

%end

%hook TFSTwitterUserSource

- (BOOL)verified {
    return pfbProbeForces() ? YES : %orig;
}

- (id)isBlueVerified {
    return pfbProbeForces() ? @YES : %orig;
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
    gProbeNamed = [NSMutableArray array];
    gProbeDefaultsCallers = [NSMutableArray array];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      pfbProbeRun();
    });
}
