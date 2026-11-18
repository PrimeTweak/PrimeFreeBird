// Probe for the Menu's Premium items (PFBMenuProbe.h). Its lines go to the stethoscope report,
// under the topic "probe menu premium".

#import "Support/PFBMenuProbe.h"
#import <QuartzCore/QuartzCore.h>
#import <dlfcn.h>
#import <objc/message.h>
#import "Common/PFBCompatibility.h"
#import "Common/PFBSettings.h"
#import "Features/Appearance/Sidebar/PFBSidebarItems.h"

BOOL PFBMenuProbeRecording;

static NSString* const kPFBMenuProbeTopic = @"probe menu premium";

static CFTimeInterval gPFBMenuProbeStart;
static NSInteger gPFBMenuProbeAttempts;
static BOOL gPFBMenuProbeDone;
static NSInteger gPFBMenuProbePass;
static __weak id gPFBMenuProbeContent;
static NSArray* gPFBMenuProbeAnswered;
static NSMutableOrderedSet<NSNumber*>* gPFBMenuProbeNamed;
static NSMutableArray<NSString*>* gPFBMenuProbeNamedCallers;
static NSMutableOrderedSet<NSString*>* gPFBMenuProbeSwitches;
static NSMutableOrderedSet<NSString*>* gPFBMenuProbeChecks;
static NSCountedSet<NSString*>* gPFBMenuProbeCheckCounts;

static void PFBMenuProbeLine(NSString* line) {
    PFBCompatMeasure(kPFBMenuProbeTopic, [NSString stringWithFormat:@"+%.0f s %@", CACurrentMediaTime() - gPFBMenuProbeStart, line], 30);
}

static NSString* PFBMenuProbePassName(NSInteger pass) {
    return pass == 1 ? @"Premium unlocked" : pass == 2 ? @"real Premium" : @"real Premium and real gates";
}

static NSString* PFBMenuProbePanels(NSArray* panels) {
    if (!panels) {
        return @"unknown";
    }
    NSMutableArray<NSString*>* items = [NSMutableArray array];
    for (id panel in panels) {
        NSInteger panelID = [panel respondsToSelector:@selector(integerValue)] ? [panel integerValue] : 0;
        [items addObject:[NSString stringWithFormat:@"%ld %@", (long)panelID, [PFBSidebarItems nameForPanel:panelID] ?: @"-"]];
    }
    return items.count ? [items componentsJoinedByString:@", "] : @"none";
}

// The first callers outside this tweak and the hooking library, as image+offset.
static NSString* PFBMenuProbeCallers(NSUInteger wanted) {
    Dl_info own;
    dladdr((const void*)&PFBMenuProbeCallers, &own);
    NSMutableArray<NSString*>* frames = [NSMutableArray array];
    for (NSNumber* address in [NSThread callStackReturnAddresses]) {
        Dl_info info;
        if (!dladdr((const void*)address.unsignedLongValue, &info) || info.dli_fbase == own.dli_fbase || !info.dli_fname) {
            continue;
        }
        NSString* image = [@(info.dli_fname) lastPathComponent];
        NSString* lower = image.lowercaseString;
        if ([lower hasPrefix:@"libobjc"] || [lower containsString:@"ellekit"] || [lower containsString:@"substrate"] ||
            [lower containsString:@"hooker"]) {
            continue;
        }
        [frames addObject:[NSString stringWithFormat:@"%@+0x%lx", image,
                                                     address.unsignedLongValue - (unsigned long)info.dli_fbase]];
        if (frames.count == wanted) {
            break;
        }
    }
    return frames.count ? [frames componentsJoinedByString:@" < "] : @"?";
}

// MARK: - Recording, from the hooks

NSArray* PFBMenuProbeAnswer(NSArray* panelIDs) {
    if (!panelIDs.count) {
        return panelIDs;
    }
    // The first tab repeated once per pass: each rebuild sees a new list, with no panel more or less.
    NSMutableArray* answer = [panelIDs mutableCopy];
    for (NSInteger repeat = 0; repeat < gPFBMenuProbePass; repeat++) {
        [answer addObject:panelIDs.firstObject];
    }
    gPFBMenuProbeAnswered = [answer copy];
    return gPFBMenuProbeAnswered;
}

void PFBMenuProbeNoteContent(id content) {
    gPFBMenuProbeContent = content;
}

void PFBMenuProbeNoteNamed(long long panelID) {
    if (![NSThread isMainThread] || [gPFBMenuProbeNamed containsObject:@(panelID)]) {
        return;
    }
    [gPFBMenuProbeNamed addObject:@(panelID)];
    [gPFBMenuProbeNamedCallers addObject:PFBMenuProbeCallers(1)];
}

void PFBMenuProbeNoteSwitch(NSString* key) {
    if ([NSThread isMainThread]) {
        [gPFBMenuProbeSwitches addObject:key];
    }
}

void PFBMenuProbeNoteSubscription(NSUInteger tier, BOOL subscribed) {
    if (![NSThread isMainThread]) {
        return;
    }
    NSString* check = [NSString stringWithFormat:@"tier %lu=%d at %@", (unsigned long)tier, subscribed, PFBMenuProbeCallers(3)];
    [gPFBMenuProbeChecks addObject:check];
    [gPFBMenuProbeCheckCounts addObject:check];
}

// MARK: - Reading the account

static id PFBMenuProbeSend(id receiver, NSString* selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    return [receiver respondsToSelector:selector] ? ((id (*)(id, SEL))objc_msgSend)(receiver, selector) : nil;
}

static id PFBMenuProbeAccount(void) {
    return PFBMenuProbeSend(PFBMenuProbeSend(NSClassFromString(@"T1HostViewController"), @"sharedHostViewController"),
                            @"currentAccount");
}

static NSString* PFBMenuProbeFlag(id receiver, NSString* selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    if (![receiver respondsToSelector:selector]) {
        return @"?";
    }
    return ((BOOL (*)(id, SEL))objc_msgSend)(receiver, selector) ? @"1" : @"0";
}

// The account's gates for the sidebar's items, as the current reads give them.
static NSString* PFBMenuProbeGates(id account) {
    id accountSwitches = PFBMenuProbeSend(account, @"accountFeatureSwitches");
    NSMutableArray<NSString*>* gates = [NSMutableArray array];
    for (NSString* name in @[ @"isPremiumTierUser", @"isVerifiedPremiumTierUser", @"isVerifiedOrganizationAccount",
                              @"isBusinessOrAffiliateAccount", @"canAccessXPayments" ]) {
        [gates addObject:[NSString stringWithFormat:@"%@=%@", name, PFBMenuProbeFlag(account, name)]];
    }
    for (NSString* name in @[ @"isPaymentsEnabled", @"isVideoCacheActivityHistoryEnabled", @"birdwatchHomePageIsEnabled",
                              @"birdwatchHistoryIsEnabled" ]) {
        [gates addObject:[NSString stringWithFormat:@"%@=%@", name, PFBMenuProbeFlag(accountSwitches, name)]];
    }
    return [gates componentsJoinedByString:@", "];
}

// Each switch read during the rebuild, with the value the current reads give it.
static NSString* PFBMenuProbeSwitchValues(id account) {
    id switches = PFBMenuProbeSend(account, @"featureSwitches");
    SEL reader = NSSelectorFromString(@"numberForKey:");
    NSMutableArray<NSString*>* values = [NSMutableArray array];
    for (NSString* key in gPFBMenuProbeSwitches) {
        id value = [switches respondsToSelector:reader] ? ((id (*)(id, SEL, id))objc_msgSend)(switches, reader, key) : nil;
        [values addObject:[NSString stringWithFormat:@"%@=%@", key, value ?: @"nil"]];
    }
    return values.count ? [values componentsJoinedByString:@", "] : @"none";
}

static NSString* PFBMenuProbeRealTiers(id account) {
    SEL subscribedTo = NSSelectorFromString(@"isSubscribedTo:");
    if (![account respondsToSelector:subscribedTo]) {
        return @"?";
    }
    NSMutableArray<NSString*>* tiers = [NSMutableArray array];
    for (NSUInteger tier = 0; tier < 16; tier++) {
        if (((BOOL (*)(id, SEL, NSUInteger))objc_msgSend)(account, subscribedTo, tier)) {
            [tiers addObject:@(tier).stringValue];
        }
    }
    return tiers.count ? [tiers componentsJoinedByString:@" "] : @"none";
}

// MARK: - The three rebuilds

// One rebuild of Twitter's own sidebar under the pass's reads; the panels it named, or nil when
// there was no sidebar to rebuild.
static NSOrderedSet<NSNumber*>* PFBMenuProbeRunPass(NSInteger pass, id account) {
    gPFBMenuProbePass = pass;
    gPFBMenuProbeContent = nil;
    gPFBMenuProbeAnswered = nil;
    [gPFBMenuProbeNamed removeAllObjects];
    [gPFBMenuProbeNamedCallers removeAllObjects];
    [gPFBMenuProbeSwitches removeAllObjects];
    [gPFBMenuProbeChecks removeAllObjects];
    gPFBMenuProbeCheckCounts = [NSCountedSet set];

    PFBMenuProbeSetRealReads(pass >= 2, pass >= 3);
    PFBMenuProbeRecording = YES;
    CFTimeInterval started = CACurrentMediaTime();
    PFBDashRefresh();
    CFTimeInterval took = CACurrentMediaTime() - started;
    PFBMenuProbeRecording = NO;
    id content = gPFBMenuProbeContent;
    NSString* gates = PFBMenuProbeGates(account);
    NSString* switchValues = PFBMenuProbeSwitchValues(account);
    PFBMenuProbeSetRealReads(NO, NO);
    if (!content) {
        return nil;
    }

    NSArray* drawer = PFBDashSnapshot(content);
    NSString* state = !drawer ? @"drawer list unreadable"
                      : [drawer isEqualToArray:gPFBMenuProbeAnswered ?: @[]] ? @"rebuilt" : @"not rebuilt";
    NSMutableArray<NSString*>* named = [NSMutableArray array];
    [gPFBMenuProbeNamed enumerateObjectsUsingBlock:^(NSNumber* panel, NSUInteger index, BOOL* stop) {
      NSString* caller = index < gPFBMenuProbeNamedCallers.count ? gPFBMenuProbeNamedCallers[index] : @"?";
      [named addObject:[NSString stringWithFormat:@"%@ (%@)", PFBMenuProbePanels(@[ panel ]), caller]];
    }];
    NSMutableArray<NSString*>* checks = [NSMutableArray array];
    for (NSString* check in gPFBMenuProbeChecks) {
        [checks addObject:[NSString stringWithFormat:@"%@ x%lu", check, (unsigned long)[gPFBMenuProbeCheckCounts countForObject:check]]];
    }
    NSString* name = PFBMenuProbePassName(pass);
    PFBMenuProbeLine([NSString stringWithFormat:@"pass %ld %@: %@ in %.0f ms; named: %@", (long)pass, name, state,
                                                took * 1000, named.count ? [named componentsJoinedByString:@", "] : @"none"]);
    PFBMenuProbeLine([NSString stringWithFormat:@"pass %ld %@ Premium checks: %@", (long)pass, name,
                                                checks.count ? [checks componentsJoinedByString:@"; "] : @"none"]);
    PFBMenuProbeLine([NSString stringWithFormat:@"pass %ld %@ gates: %@; switches read: %@", (long)pass, name, gates,
                                                switchValues]);
    return [gPFBMenuProbeNamed copy];
}

static void PFBMenuProbeRun(void) {
    if (gPFBMenuProbeDone) {
        return;
    }
    id account = PFBMenuProbeAccount();
    if (PFBMenuProbeMenuOpen() || !account) {
        if (++gPFBMenuProbeAttempts < 60) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
              PFBMenuProbeRun();
            });
        }
        return;
    }

    PFBMenuProbeSetRealReads(YES, YES);
    NSString* realTiers = PFBMenuProbeRealTiers(account);
    NSString* realGates = PFBMenuProbeGates(account);
    PFBMenuProbeSetRealReads(NO, NO);
    NSString* unlockedGates = PFBMenuProbeGates(account);

    NSMutableArray<NSOrderedSet<NSNumber*>*>* namedByPass = [NSMutableArray array];
    for (NSInteger pass = 1; pass <= 3; pass++) {
        NSOrderedSet<NSNumber*>* named = PFBMenuProbeRunPass(pass, account);
        if (!named) {
            break;
        }
        [namedByPass addObject:named];
    }
    gPFBMenuProbePass = 0;
    PFBDashRefresh();
    if (namedByPass.count < 3) {
        if (!gPFBMenuProbeAttempts) {
            PFBMenuProbeLine(@"no sidebar to rebuild yet: tried again every 5 s");
        }
        if (++gPFBMenuProbeAttempts < 60) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
              PFBMenuProbeRun();
            });
        }
        return;
    }
    gPFBMenuProbeDone = YES;

    PFBMenuProbeLine([NSString stringWithFormat:@"account: subscribed tiers %@; real %@; with the tweak %@", realTiers,
                                                realGates, unlockedGates]);
    NSArray<NSNumber*>* tabs = [PFBSidebarItems tabPanelIDs];
    NSMutableArray<NSString*>* items = [NSMutableArray array];
    for (NSNumber* panel in [PFBSidebarItems catalog]) {
        NSMutableString* marks = [NSMutableString string];
        for (NSOrderedSet<NSNumber*>* named in namedByPass) {
            [marks appendString:[named containsObject:panel] ? @"+" : @"-"];
        }
        NSString* where = [tabs containsObject:panel] ? @"tab bar" : [PFBSidebarItems isHidden:panel.integerValue] ? @"hidden" : @"shown";
        [items addObject:[NSString stringWithFormat:@"%@ named %@ %@", PFBMenuProbePanels(@[ panel ]), marks, where]];
    }
    PFBMenuProbeLine([NSString stringWithFormat:@"items (named in passes 1/2/3, Menu page): %@; tab bar %@",
                                                [items componentsJoinedByString:@"; "], PFBMenuProbePanels(tabs)]);
}

__attribute__((constructor)) static void PFBMenuProbeStart(void) {
    gPFBMenuProbeStart = CACurrentMediaTime();
    gPFBMenuProbeNamed = [NSMutableOrderedSet orderedSet];
    gPFBMenuProbeNamedCallers = [NSMutableArray array];
    gPFBMenuProbeSwitches = [NSMutableOrderedSet orderedSet];
    gPFBMenuProbeChecks = [NSMutableOrderedSet orderedSet];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      PFBMenuProbeRun();
    });
}
