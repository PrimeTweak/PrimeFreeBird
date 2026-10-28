// Measures what is still unknown under Twitter's own Liquid Glass: what shrinks the tab
// bar while Home scrolls (Always visible) and what builds its tabs (Customize tabs).
//
// Each scroll and a summary at 25 s and 60 s go to MEASUREMENTS, which the stethoscope
// copies with the Compatibility report. The hooks are installed after every other file's,
// so each call is charged to the code that sent it.

#import <mach-o/loader.h>
#import <pthread.h>
#import "Support/HookHelpers.h"
#import "Common/PFBCompatibility.h"

// The methods called below that no header declares.
@interface T1HostViewController (PFBGlassChromeProbe)
- (id)appNavigation;
@end

@interface _TtC14T1TwitterSwift20XTabbedAppNavigation : NSObject
- (NSArray*)visiblePanelIDs;
- (long long)currentPanelID;
- (void)recalculateVisiblePanels;
- (void)recalculateVisiblePanelsWithUpdatedPanelIDs:(NSArray*)panelIDs;
@end

@interface XNAVConfiguration : NSObject
+ (instancetype)standardConfiguration;
+ (instancetype)pinnedConfiguration;
+ (instancetype)hiddenConfiguration;
+ (instancetype)pinnedTransparentConfiguration;
@end

@interface UIViewController (PFBGlassChromeProbe)
- (BOOL)tfn_prefersTabBarPinned;
- (BOOL)tfn_preferManualNavBarCollapse;
@end

@interface _TtCC11XNavigation14CollapseEngine14ScrollObserver : NSObject
- (void)handlePan:(UIGestureRecognizer*)recognizer;
@end

static NSString* const kPFBProbeTopic = @"glass probe";
static CFTimeInterval gProbeStart;

// MARK: - Who sent it

// PrimeFreeBird's code is the __TEXT segment of the image this file is in.
static uintptr_t gProbeOursStart;
static uintptr_t gProbeOursEnd;

static void PFBProbeFindOurCode(void) {
    Dl_info info;
    if (!dladdr((const void*)&PFBProbeFindOurCode, &info) || !info.dli_fbase) {
        return;
    }
    const struct mach_header_64* header = (const struct mach_header_64*)info.dli_fbase;
    const uint8_t* cursor = (const uint8_t*)(header + 1);
    for (uint32_t i = 0; i < header->ncmds; i++) {
        const struct load_command* command = (const struct load_command*)cursor;
        if (command->cmd == LC_SEGMENT_64) {
            const struct segment_command_64* segment = (const struct segment_command_64*)cursor;
            if (strncmp(segment->segname, SEG_TEXT, sizeof(segment->segname)) == 0) {
                gProbeOursStart = (uintptr_t)header;
                gProbeOursEnd = gProbeOursStart + (uintptr_t)segment->vmsize;
                return;
            }
        }
        cursor += command->cmdsize;
    }
}

static BOOL PFBProbeFromUs(const void* returnAddress) {
    uintptr_t address = (uintptr_t)returnAddress;
    return address >= gProbeOursStart && address < gProbeOursEnd;
}

// "XServiceLibraries+0x22b6030": the image a call came from and the place in it.
static NSString* PFBProbeCaller(const void* address) {
    if (!address) {
        return @"?";
    }
    if (PFBProbeFromUs(address)) {
        return @"PrimeFreeBird";
    }
    Dl_info info;
    if (!dladdr(address, &info) || !info.dli_fname || !info.dli_fbase) {
        return @"?";
    }
    const char* slash = strrchr(info.dli_fname, '/');
    return [NSString stringWithFormat:@"%s+0x%lx", slash ? slash + 1 : info.dli_fname,
                                      (unsigned long)((uintptr_t)address - (uintptr_t)info.dli_fbase)];
}

// "_TtC11XNavigation10TabBarView" reads "XNavigation.TabBarView".
static NSString* PFBProbeName(Class cls) {
    if (!cls) {
        return @"none";
    }
    NSString* name = NSStringFromClass(cls);
    if (![name hasPrefix:@"_TtC"] || [name hasPrefix:@"_TtCC"]) {
        return name;
    }
    const char* cursor = name.UTF8String + 4;
    NSMutableArray<NSString*>* parts = [NSMutableArray array];
    while (*cursor >= '0' && *cursor <= '9') {
        char* end = NULL;
        long length = strtol(cursor, &end, 10);
        if (length <= 0 || (long)strlen(end) < length) {
            return name;
        }
        NSString* part = [[NSString alloc] initWithBytes:end length:(NSUInteger)length encoding:NSUTF8StringEncoding];
        [parts addObject:part ?: @"?"];
        cursor = end + length;
    }
    return parts.count == 2 && *cursor == '\0' ? [parts componentsJoinedByString:@"."] : name;
}

// MARK: - Tallies

// A count, the part sent by PrimeFreeBird, who sent it and the values seen. Main thread only.
@interface PFBProbeTally : NSObject
@property(nonatomic) NSUInteger total;
@property(nonatomic) NSUInteger ours;
@property(nonatomic, strong) NSMutableDictionary<NSString*, NSNumber*>* callers;
@property(nonatomic, strong) NSMutableOrderedSet<NSString*>* values;
@property(nonatomic, copy) NSString* lastCaller;
- (void)noteFrom:(const void*)address value:(NSString*)value;
- (NSString*)text;
@end

@implementation PFBProbeTally

- (instancetype)init {
    self = [super init];
    if (self) {
        _callers = [NSMutableDictionary dictionary];
        _values = [NSMutableOrderedSet orderedSet];
    }
    return self;
}

// The first 300 calls are charged to their sender: each costs a lookup of the image.
- (void)noteFrom:(const void*)address value:(NSString*)value {
    self.total++;
    BOOL ours = PFBProbeFromUs(address);
    self.ours += ours ? 1 : 0;
    if (self.total <= 300 && address) {
        NSString* caller = ours ? @"PrimeFreeBird" : PFBProbeCaller(address);
        self.lastCaller = caller;
        if (self.callers[caller] || self.callers.count < 8) {
            self.callers[caller] = @(self.callers[caller].unsignedIntegerValue + 1);
        }
    }
    if (value.length && self.values.count < 12) {
        [self.values addObject:value];
    }
}

- (NSString*)text {
    if (!self.total) {
        return @"0";
    }
    NSArray<NSString*>* names = [self.callers keysSortedByValueUsingComparator:^NSComparisonResult(NSNumber* a, NSNumber* b) {
      return [b compare:a];
    }];
    NSMutableArray<NSString*>* senders = [NSMutableArray array];
    for (NSString* name in names) {
        [senders addObject:[NSString stringWithFormat:@"%@ %@", name, self.callers[name]]];
    }
    NSMutableString* text = [NSMutableString stringWithFormat:@"%lu (by PrimeFreeBird %lu)", (unsigned long)self.total,
                                                               (unsigned long)self.ours];
    if (senders.count) {
        [text appendFormat:@", from [%@]", [senders componentsJoinedByString:@", "]];
    }
    if (self.values.count) {
        [text appendFormat:@", values [%@]", [self.values.array componentsJoinedByString:@" | "]];
    }
    return text;
}

@end

static NSMutableDictionary<NSString*, PFBProbeTally*>* gProbeTallies;

static PFBProbeTally* PFBProbeTallyNamed(NSString* name) {
    if (!gProbeTallies) {
        gProbeTallies = [NSMutableDictionary dictionary];
    }
    PFBProbeTally* tally = gProbeTallies[name];
    if (!tally) {
        tally = [PFBProbeTally new];
        gProbeTallies[name] = tally;
    }
    return tally;
}

static void PFBProbeCount(NSString* name, const void* address, NSString* value) {
    if (gProbeStart <= 0 || !pthread_main_np()) {
        return;
    }
    [PFBProbeTallyNamed(name) noteFrom:address value:value];
}

static NSString* PFBProbeTallyText(NSString* name) {
    PFBProbeTally* tally = gProbeTallies[name];
    return tally ? [tally text] : @"0";
}

static NSString* PFBProbeIDsText(NSArray* panelIDs) {
    if (![panelIDs isKindOfClass:[NSArray class]]) {
        return @"none";
    }
    NSMutableArray<NSString*>* parts = [NSMutableArray array];
    for (id panel in panelIDs) {
        [parts addObject:[panel description] ?: @"?"];
    }
    return [NSString stringWithFormat:@"[%@]", [parts componentsJoinedByString:@" "]];
}

// MARK: - Raw readings

// The first bytes of an instance variable, as hex.
static NSString* PFBProbeHex(id object, const char* name, NSUInteger length) {
    Ivar ivar = object ? class_getInstanceVariable(object_getClass(object), name) : NULL;
    if (!ivar) {
        return @"none";
    }
    ptrdiff_t offset = ivar_getOffset(ivar);
    size_t size = class_getInstanceSize(object_getClass(object));
    if (offset <= 0 || (size_t)offset >= size) {
        return @"none";
    }
    NSUInteger count = MIN(length, (NSUInteger)(size - (size_t)offset));
    const uint8_t* raw = (const uint8_t*)(__bridge void*)object + offset;
    NSMutableString* hex = [NSMutableString string];
    for (NSUInteger i = 0; i < count; i++) {
        [hex appendFormat:@"%02x", raw[i]];
    }
    return hex;
}

// An instance variable read as a double: NAN when it has no room for one or reads absurd.
static double PFBProbeDouble(id object, const char* name) {
    Ivar ivar = object ? class_getInstanceVariable(object_getClass(object), name) : NULL;
    if (!ivar) {
        return NAN;
    }
    ptrdiff_t offset = ivar_getOffset(ivar);
    if (offset <= 0 || (size_t)offset + sizeof(double) > class_getInstanceSize(object_getClass(object))) {
        return NAN;
    }
    double value = 0;
    memcpy(&value, (const uint8_t*)(__bridge void*)object + offset, sizeof(double));
    return isfinite(value) && fabs(value) < 100000.0 ? value : NAN;
}

// An instance variable holding an object, read without retaining it twice.
static id PFBProbeObject(id object, const char* name) {
    Ivar ivar = object ? class_getInstanceVariable(object_getClass(object), name) : NULL;
    if (!ivar) {
        return nil;
    }
    ptrdiff_t offset = ivar_getOffset(ivar);
    if (offset <= 0 || (size_t)offset + sizeof(void*) > class_getInstanceSize(object_getClass(object))) {
        return nil;
    }
    void* raw = NULL;
    memcpy(&raw, (const uint8_t*)(__bridge void*)object + offset, sizeof(void*));
    // Only a plain, aligned heap address is taken for an object.
    uintptr_t address = (uintptr_t)raw;
    if (!address || (address & 0x7) || address < 0x100000000ULL || (address >> 47)) {
        return nil;
    }
    return (__bridge id)raw;
}

// MARK: - The bar

static __weak UIView* gProbeBar;
static __weak UIView* gProbeAccessory;
static __weak UIViewController* gProbeScreen;
static Class gProbeItemClass;
static Class gProbePortalClass;
static Class gProbeCarriedClass;
static Class gProbePillClass;

static BOOL PFBProbeOnScreen(UIView* view) {
    UIWindow* window = view.window;
    return window && CGRectIntersectsRect([view convertRect:view.bounds toView:nil], window.bounds);
}

static BOOL PFBProbeInLens(UIView* view, UIView* bar) {
    for (UIView* node = view; node && node != bar; node = node.superview) {
        if ((gProbePortalClass && [node isKindOfClass:gProbePortalClass]) ||
            (gProbeCarriedClass && [node isKindOfClass:gProbeCarriedClass])) {
            return YES;
        }
    }
    return NO;
}

// The resting row's tabs, left to right.
static NSArray<UIView*>* PFBProbeRestingItems(UIView* bar) {
    NSMutableArray<UIView*>* items = [NSMutableArray array];
    PFBWalkAllSubviews(bar, 4, ^(UIView* view) {
      if (gProbeItemClass && [view isKindOfClass:gProbeItemClass] && !PFBProbeInLens(view, bar)) {
          [items addObject:view];
      }
    });
    [items sortUsingComparator:^NSComparisonResult(UIView* a, UIView* b) {
      CGFloat ax = CGRectGetMinX(a.frame);
      CGFloat bx = CGRectGetMinX(b.frame);
      return ax < bx ? NSOrderedAscending : (ax > bx ? NSOrderedDescending : NSOrderedSame);
    }];
    return items;
}

static NSString* PFBProbeTabsText(UIView* bar) {
    NSMutableArray<NSString*>* names = [NSMutableArray array];
    for (UIView* item in PFBProbeRestingItems(bar)) {
        [names addObject:item.accessibilityLabel.length ? item.accessibilityLabel : @"?"];
    }
    return [NSString stringWithFormat:@"[%@]", [names componentsJoinedByString:@", "]];
}

static id PFBProbeAppNavigation(void) {
    Class hostClass = NSClassFromString(@"T1HostViewController");
    T1HostViewController* host =
        [hostClass respondsToSelector:@selector(sharedHostViewController)] ? [hostClass sharedHostViewController] : nil;
    return [host respondsToSelector:@selector(appNavigation)] ? [host appNavigation] : nil;
}

// MARK: - Customize tabs

// Each change of the bar's tabs, with what Twitter's navigation was asked before it.
static NSMutableArray<NSString*>* gProbeTabEvents;
static NSString* gProbeLastTabs;

static void PFBProbeNoteTabs(UIView* bar) {
    NSString* tabs = PFBProbeTabsText(bar);
    if ([tabs isEqualToString:gProbeLastTabs]) {
        return;
    }
    gProbeLastTabs = tabs;
    if (!gProbeTabEvents) {
        gProbeTabEvents = [NSMutableArray array];
    }
    if (gProbeTabEvents.count >= 6) {
        return;
    }
    PFBProbeTally* asked = gProbeTallies[@"visible panels"];
    PFBProbeTally* recalculated = gProbeTallies[@"recalculate"];
    PFBProbeTally* updated = gProbeTallies[@"recalculate with"];
    [gProbeTabEvents addObject:[NSString stringWithFormat:@"%.1f s %@ after visiblePanelIDs %lu (last from %@), "
                                                           @"recalculate %lu, recalculate with %lu",
                                                           CACurrentMediaTime() - gProbeStart, tabs,
                                                           (unsigned long)asked.total, asked.lastCaller ?: @"none",
                                                           (unsigned long)recalculated.total, (unsigned long)updated.total]];
}

// Saved values whose key names the tabs or the navigation.
static NSString* PFBProbeSavedKeysText(void) {
    NSDictionary* all = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
    NSMutableArray<NSString*>* found = [NSMutableArray array];
    NSArray<NSString*>* parts = @[ @"tabidentifier", @"tab_identifier", @"tabs", @"navigation", @"customiz", @"panel" ];
    for (NSString* key in [all.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        if (found.count >= 20 || ![key isKindOfClass:[NSString class]] || [key hasPrefix:@"pfb_"]) {
            continue;
        }
        NSString* lower = key.lowercaseString;
        for (NSString* part in parts) {
            if ([lower containsString:part]) {
                NSString* value = [[[all[key] description] componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]
                    componentsJoinedByString:@""];
                [found addObject:[NSString stringWithFormat:@"%@ = %@ %@", key, PFBProbeName([all[key] class]),
                                                            value.length > 70 ? [value substringToIndex:70] : value]];
                break;
            }
        }
    }
    return found.count ? [found componentsJoinedByString:@" | "] : @"none";
}

// MARK: - How each screen declares its bars

// The bytes of a configuration Twitter's navigation stores, matched with its four named ones.
static NSData* gProbeReferenceBytes[4];
static NSString* const kPFBProbeReferenceNames[4] = {@"standard", @"pinned", @"hidden", @"pinned transparent"};

static NSData* PFBProbeWrapperBytes(id configuration) {
    Class cls = NSClassFromString(@"XNAVConfiguration");
    if (!configuration || !cls || ![configuration isKindOfClass:cls]) {
        return nil;
    }
    Ivar ivar = class_getInstanceVariable(cls, "configuration");
    ptrdiff_t offset = ivar ? ivar_getOffset(ivar) : 0;
    size_t size = class_getInstanceSize(cls);
    if (offset <= 0 || (size_t)offset >= size) {
        return nil;
    }
    return [NSData dataWithBytes:(const uint8_t*)(__bridge void*)configuration + offset length:size - (size_t)offset];
}

static void PFBProbeBuildReferences(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      Class cls = NSClassFromString(@"XNAVConfiguration");
      @try {
          gProbeReferenceBytes[0] = PFBProbeWrapperBytes([cls standardConfiguration]);
          gProbeReferenceBytes[1] = PFBProbeWrapperBytes([cls pinnedConfiguration]);
          gProbeReferenceBytes[2] = PFBProbeWrapperBytes([cls hiddenConfiguration]);
          gProbeReferenceBytes[3] = PFBProbeWrapperBytes([cls pinnedTransparentConfiguration]);
      } @catch (__unused id exception) {
      }
    });
}

// A stack's stored configuration by name, or its bytes when it matches none.
static NSString* PFBProbeStackConfigText(UINavigationController* stack, const char* name) {
    PFBProbeBuildReferences();
    NSUInteger length = gProbeReferenceBytes[0].length;
    Ivar ivar = stack ? class_getInstanceVariable(object_getClass(stack), name) : NULL;
    if (!ivar || !length) {
        return @"none";
    }
    ptrdiff_t offset = ivar_getOffset(ivar);
    if (offset <= 0 || (size_t)offset + length > class_getInstanceSize(object_getClass(stack))) {
        return @"none";
    }
    NSData* bytes = [NSData dataWithBytes:(const uint8_t*)(__bridge void*)stack + offset length:length];
    for (NSUInteger i = 0; i < 4; i++) {
        if ([gProbeReferenceBytes[i] isEqualToData:bytes]) {
            return kPFBProbeReferenceNames[i];
        }
    }
    return [@"other " stringByAppendingString:PFBProbeHex(stack, name, MIN(length, (NSUInteger)24))];
}

typedef const void* (*PFBProbeConformsFn)(const void* type, const void* protocol);
typedef const void* (*PFBProbeMetadataFn)(const void* cls);

static NSString* PFBProbeDeclarationText(UIViewController* controller) {
    static PFBProbeConformsFn conforms;
    static PFBProbeMetadataFn metadata;
    static const void* provides;
    static const void* delegates;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      conforms = (PFBProbeConformsFn)dlsym(RTLD_DEFAULT, "swift_conformsToProtocol");
      metadata = (PFBProbeMetadataFn)dlsym(RTLD_DEFAULT, "swift_getObjCClassMetadata");
      provides = dlsym(RTLD_DEFAULT, "$s11XNavigation32NavigationConfigurationProvidingMp");
      delegates = dlsym(RTLD_DEFAULT, "$s11XNavigation33NavigationConfigurationDelegatingMp");
    });
    NSMutableArray<NSString*>* parts = [NSMutableArray array];
    const void* type = metadata ? metadata((__bridge const void*)[controller class]) : NULL;
    if (type && conforms && provides) {
        [parts addObject:conforms(type, provides) ? @"Swift provides" : @"Swift no"];
    }
    if (type && conforms && delegates && conforms(type, delegates)) {
        [parts addObject:@"Swift delegates"];
    }
    if ([controller respondsToSelector:NSSelectorFromString(@"xnav_navigationConfiguration")]) {
        [parts addObject:@"ObjC declares"];
    }
    if ([controller respondsToSelector:@selector(tfn_prefersTabBarPinned)]) {
        [parts addObject:[NSString stringWithFormat:@"prefers tab bar pinned %@",
                                                    [controller tfn_prefersTabBarPinned] ? @"yes" : @"no"]];
    }
    if ([controller respondsToSelector:@selector(tfn_preferManualNavBarCollapse)]) {
        [parts addObject:[NSString stringWithFormat:@"manual top bar collapse %@",
                                                    [controller tfn_preferManualNavBarCollapse] ? @"yes" : @"no"]];
    }
    UINavigationController* stack = controller.navigationController;
    [parts addObject:[NSString stringWithFormat:@"stack default %@, applied %@",
                                                PFBProbeStackConfigText(stack, "defaultConfiguration"),
                                                PFBProbeStackConfigText(stack, "appliedConfiguration")]];
    return [parts componentsJoinedByString:@", "];
}

static NSMutableDictionary<NSString*, NSString*>* gProbeScreens;

// MARK: - Shrinking on scroll

// A range of values over one scroll.
typedef struct {
    double low;
    double high;
    BOOL seen;
} PFBProbeRange;

static void PFBProbeWiden(PFBProbeRange* range, double value) {
    if (isnan(value)) {
        return;
    }
    if (!range->seen) {
        range->low = value;
        range->high = value;
        range->seen = YES;
        return;
    }
    range->low = MIN(range->low, value);
    range->high = MAX(range->high, value);
}

static NSString* PFBProbeRangeText(PFBProbeRange range) {
    if (!range.seen) {
        return @"none";
    }
    if (fabs(range.high - range.low) < 0.005) {
        return [NSString stringWithFormat:@"%.2f", range.low];
    }
    return [NSString stringWithFormat:@"%.2f to %.2f", range.low, range.high];
}

// One window per scroll: the bar's parts while the finger moves, and for 1.5 s after.
@interface PFBProbeScrollWindow : NSObject {
  @public
    PFBProbeRange barWidth, barY, containerWidth, containerScale, platterWidth, platterX, maskWidth;
    PFBProbeRange rowSpan, lowestTabAlpha, lowestTabScale, pillWidth, pillX;
    PFBProbeRange accessoryX, accessoryY, accessoryAlpha, topY;
    PFBProbeRange applied, progress, extent, opacity, slide, travel;
}
@property(nonatomic, copy) NSString* screen;
@property(nonatomic) CFTimeInterval began;
@property(nonatomic) CFTimeInterval lastPan;
@property(nonatomic) NSUInteger pans;
@property(nonatomic) NSUInteger samples;
@property(nonatomic) NSUInteger fadedTabs;
@property(nonatomic) NSUInteger barLayoutsBefore;
@property(nonatomic) NSUInteger tabLayoutsBefore;
@property(nonatomic) double narrowest;
@property(nonatomic, copy) NSString* peakApplied;
@property(nonatomic, copy) NSString* peakProgress;
@end

@implementation PFBProbeScrollWindow
@end

@interface PFBProbeSampler : NSObject
@property(nonatomic, strong) CADisplayLink* link;
@property(nonatomic, strong) PFBProbeScrollWindow* window;
- (void)tick:(CADisplayLink*)link;
@end

static PFBProbeSampler* gProbeSampler;
static NSUInteger gProbeScrollWindows;
static NSUInteger gProbeShrunkWindows;

static NSString* PFBProbeScrollText(PFBProbeScrollWindow* w) {
    NSUInteger barLayouts = gProbeTallies[@"bar layout"].total - w.barLayoutsBefore;
    NSUInteger tabLayouts = gProbeTallies[@"tab layout"].total - w.tabLayoutsBefore;
    return [NSString
        stringWithFormat:@"scroll on %@: %lu pans, %lu samples · bar width %@, y %@ · container width %@, scale %@ · "
                         @"platter width %@, x %@, mask width %@ · row span %@, lowest tab alpha %@ (%lu faded), "
                         @"lowest tab scale %@ · pill width %@, x %@ · accessory x %@, y %@, alpha %@ · top bar y %@ · "
                         @"appliedCollapse %@ (narrowest %@) · engine progress %@ (narrowest %@), bottom extent %@, "
                         @"opacity %@, slide %@, hidden travel %@ · layouts bar %lu, tabs %lu",
                         w.screen, (unsigned long)w.pans, (unsigned long)w.samples, PFBProbeRangeText(w->barWidth),
                         PFBProbeRangeText(w->barY), PFBProbeRangeText(w->containerWidth),
                         PFBProbeRangeText(w->containerScale), PFBProbeRangeText(w->platterWidth),
                         PFBProbeRangeText(w->platterX), PFBProbeRangeText(w->maskWidth), PFBProbeRangeText(w->rowSpan),
                         PFBProbeRangeText(w->lowestTabAlpha), (unsigned long)w.fadedTabs,
                         PFBProbeRangeText(w->lowestTabScale), PFBProbeRangeText(w->pillWidth),
                         PFBProbeRangeText(w->pillX), PFBProbeRangeText(w->accessoryX), PFBProbeRangeText(w->accessoryY),
                         PFBProbeRangeText(w->accessoryAlpha), PFBProbeRangeText(w->topY), PFBProbeRangeText(w->applied),
                         w.peakApplied ?: @"none", PFBProbeRangeText(w->progress), w.peakProgress ?: @"none",
                         PFBProbeRangeText(w->extent), PFBProbeRangeText(w->opacity), PFBProbeRangeText(w->slide),
                         PFBProbeRangeText(w->travel), (unsigned long)barLayouts, (unsigned long)tabLayouts];
}

static double PFBProbeScaleOf(UIView* view) {
    CGAffineTransform t = view.transform;
    return sqrt(t.a * t.a + t.c * t.c);
}

// The navigation's collapse engine for the screen in front.
static id PFBProbeEngine(void) {
    UINavigationController* stack = gProbeScreen.navigationController;
    return stack ? PFBProbeObject(stack, "$__lazy_storage_$_collapseEngine") : nil;
}

@implementation PFBProbeSampler

- (void)finish {
    PFBProbeScrollWindow* w = self.window;
    [self.link invalidate];
    self.link = nil;
    self.window = nil;
    if (!w.samples) {
        return;
    }
    gProbeScrollWindows++;
    BOOL shrank = (w->platterWidth.seen && w->platterWidth.high - w->platterWidth.low > 20.0) ||
                  (w->containerWidth.seen && w->containerWidth.high - w->containerWidth.low > 20.0) ||
                  (w->rowSpan.seen && w->rowSpan.high - w->rowSpan.low > 20.0) || w.fadedTabs > 0;
    gProbeShrunkWindows += shrank ? 1 : 0;
    if (gProbeScrollWindows <= 10) {
        PFBCompatMeasure(kPFBProbeTopic, PFBProbeScrollText(w), 60);
    }
}

- (void)tick:(CADisplayLink*)link {
    PFBProbeScrollWindow* w = self.window;
    if (!w || CACurrentMediaTime() - w.lastPan > 1.5) {
        [self finish];
        return;
    }
    UIView* bar = gProbeBar;
    if (!bar.window) {
        return;
    }
    w.samples++;
    CGRect frame = [bar convertRect:bar.bounds toView:nil];
    PFBProbeWiden(&w->barWidth, frame.size.width);
    PFBProbeWiden(&w->barY, frame.origin.y);
    UIView* container = bar.subviews.firstObject;
    double width = NAN;
    if (container) {
        PFBProbeWiden(&w->containerWidth, CGRectGetWidth(container.frame));
        PFBProbeWiden(&w->containerScale, PFBProbeScaleOf(container));
        UIView* platter = container.subviews.firstObject;
        if (platter) {
            width = CGRectGetWidth(platter.frame);
            PFBProbeWiden(&w->platterWidth, width);
            PFBProbeWiden(&w->platterX, CGRectGetMinX(platter.frame));
            CALayer* mask = platter.layer.mask ?: container.layer.mask;
            if (mask) {
                PFBProbeWiden(&w->maskWidth, CGRectGetWidth(mask.frame));
            }
        }
        for (UIView* sub in container.subviews) {
            if (gProbePillClass && [sub isKindOfClass:gProbePillClass]) {
                PFBProbeWiden(&w->pillWidth, CGRectGetWidth(sub.frame));
                PFBProbeWiden(&w->pillX, CGRectGetMinX(sub.frame));
            }
        }
    }
    NSArray<UIView*>* items = PFBProbeRestingItems(bar);
    if (items.count) {
        CGRect first = [items.firstObject convertRect:items.firstObject.bounds toView:bar];
        CGRect last = [items.lastObject convertRect:items.lastObject.bounds toView:bar];
        PFBProbeWiden(&w->rowSpan, CGRectGetMaxX(last) - CGRectGetMinX(first));
        double lowestAlpha = 1.0;
        double lowestScale = 1.0;
        NSUInteger faded = 0;
        for (UIView* item in items) {
            lowestAlpha = MIN(lowestAlpha, item.alpha);
            lowestScale = MIN(lowestScale, PFBProbeScaleOf(item));
            faded += item.alpha < 0.5 || item.hidden ? 1 : 0;
        }
        PFBProbeWiden(&w->lowestTabAlpha, lowestAlpha);
        PFBProbeWiden(&w->lowestTabScale, lowestScale);
        w.fadedTabs = MAX(w.fadedTabs, faded);
    }
    UIView* accessory = gProbeAccessory;
    if (accessory.window) {
        CGRect place = [accessory convertRect:accessory.bounds toView:nil];
        PFBProbeWiden(&w->accessoryX, place.origin.x);
        PFBProbeWiden(&w->accessoryY, place.origin.y);
        PFBProbeWiden(&w->accessoryAlpha, accessory.alpha);
    }
    UINavigationBar* top = gProbeScreen.navigationController.navigationBar;
    if (top.window) {
        PFBProbeWiden(&w->topY, [top convertRect:top.bounds toView:nil].origin.y);
    }
    PFBProbeWiden(&w->applied, PFBProbeDouble(bar, "appliedCollapse"));
    id engine = PFBProbeEngine();
    PFBProbeWiden(&w->progress, PFBProbeDouble(engine, "collapseProgress"));
    PFBProbeWiden(&w->extent, PFBProbeDouble(engine, "bottomChromeExtent"));
    PFBProbeWiden(&w->opacity, PFBProbeDouble(engine, "bottomChromeOpacity"));
    PFBProbeWiden(&w->slide, PFBProbeDouble(engine, "bottomChromeSlide"));
    PFBProbeWiden(&w->travel, PFBProbeDouble(engine, "hiddenBarTravel"));
    // The raw readings where the platter is narrowest, to decode the values that are no double.
    if (!isnan(width) && (w.samples == 1 || width < w.narrowest)) {
        w.narrowest = width;
        w.peakApplied = PFBProbeHex(bar, "appliedCollapse", 24);
        w.peakProgress = engine ? PFBProbeHex(engine, "collapseProgress", 24) : @"no engine";
    }
}

@end

static void PFBProbeNotePan(void) {
    if (!gProbeSampler) {
        gProbeSampler = [PFBProbeSampler new];
    }
    CFTimeInterval now = CACurrentMediaTime();
    if (!gProbeSampler.window) {
        PFBProbeScrollWindow* w = [PFBProbeScrollWindow new];
        w.began = now;
        UIViewController* screen = gProbeScreen;
        w.screen = screen ? PFBProbeName([screen class]) : @"?";
        w.barLayoutsBefore = gProbeTallies[@"bar layout"].total;
        w.tabLayoutsBefore = gProbeTallies[@"tab layout"].total;
        gProbeSampler.window = w;
    }
    gProbeSampler.window.lastPan = now;
    gProbeSampler.window.pans++;
    if (!gProbeSampler.link) {
        gProbeSampler.link = [CADisplayLink displayLinkWithTarget:gProbeSampler selector:@selector(tick:)];
        [gProbeSampler.link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
}

// MARK: - The summary

static NSString* PFBProbeSettingsText(void) {
    NSString* (^on)(NSString*) = ^NSString*(NSString* key) {
      return [PFBSettings boolForKey:key] ? @"on" : @"off";
    };
    return [NSString stringWithFormat:@"Liquid Glass %@, Twitter's glass asked %@ · Always visible %@ · Customize tabs %@ · "
                                      @"Selected tab %@ · Tab labels %@ · Classic Tweet button %@ · Hide Tweet button %@",
                                      on(@"enable_liquid_glass"), PFBNativeGlassAsked() ? @"yes" : @"no",
                                      on(@"no_tab_bar_hiding"),
                                      [PFBCustomTabBarUtility visiblePageIDsInOrder] ? @"customized" : @"default",
                                      on(@"tab_bar_theming"), on(@"restore_tab_labels"), on(@"restore_tweet_button"),
                                      on(@"hide_tweet_button")];
}

static void PFBProbePersist(NSString* moment) {
    @try {
        id navigation = PFBProbeAppNavigation();
        NSArray* panels = [navigation respondsToSelector:@selector(visiblePanelIDs)] ? [navigation visiblePanelIDs] : nil;
        long long current = [navigation respondsToSelector:@selector(currentPanelID)] ? [navigation currentPanelID] : -1;
        UIView* bar = gProbeBar;
        NSMutableArray<NSString*>* screens = [NSMutableArray array];
        for (NSString* name in [gProbeScreens.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
            [screens addObject:[NSString stringWithFormat:@"%@: %@", name, gProbeScreens[name]]];
        }
        NSArray<NSString*>* lines = @[
            [NSString stringWithFormat:@"%@: %@", moment, PFBProbeSettingsText()],
            [NSString stringWithFormat:@"%@: tabs %@, panels %@, current %lld · changes %@ · visiblePanelIDs %@ · "
                                       @"recalculate %@ · recalculate with %@",
                                       moment, bar ? PFBProbeTabsText(bar) : @"no bar", PFBProbeIDsText(panels), current,
                                       gProbeTabEvents.count ? [gProbeTabEvents componentsJoinedByString:@" | "] : @"none",
                                       PFBProbeTallyText(@"visible panels"), PFBProbeTallyText(@"recalculate"),
                                       PFBProbeTallyText(@"recalculate with")],
            [NSString stringWithFormat:@"%@: screens %@ · scrolls %lu, the bar shrank in %lu", moment,
                                       screens.count ? [screens componentsJoinedByString:@" | "] : @"none",
                                       (unsigned long)gProbeScrollWindows, (unsigned long)gProbeShrunkWindows],
            [NSString stringWithFormat:@"%@: saved keys %@", moment, PFBProbeSavedKeysText()],
        ];
        for (NSString* line in lines) {
            PFBCompatMeasure(kPFBProbeTopic, line, 60);
        }
    } @catch (id exception) {
        PFBCompatMeasure(kPFBProbeTopic, [NSString stringWithFormat:@"%@: stopped (%@)", moment, exception], 60);
    }
}

static void PFBProbeStart(void) {
    gProbeItemClass = NSClassFromString(@"_TtC11XNavigation14TabBarItemView");
    gProbePortalClass = NSClassFromString(@"_TtC11XNavigation16TabBarPortalView");
    gProbeCarriedClass = NSClassFromString(@"_TtC11XNavigation16TabBarCarriedRow");
    gProbePillClass = NSClassFromString(@"_TtC11XNavigation10TabBarPill");
    for (NSNumber* moment in @[ @25, @60 ]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(moment.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
                         PFBProbePersist([NSString stringWithFormat:@"at %@ s", moment]);
                       });
    }
}

// MARK: - Hooks

// What Twitter builds while it launches: installed at once.
%group PFBGlassProbeEarly

%hook _TtC14T1TwitterSwift20XTabbedAppNavigation

// FeatureSwitches.x hooks this method too; when its hook is the sender, the call is
// charged to the code that called that hook, read from the frame records arm64 keeps.
- (NSArray*)visiblePanelIDs {
    NSArray* panels = %orig;
    const void* sender = __builtin_return_address(0);
    if (PFBProbeFromUs(sender)) {
        const void* const* frame = (const void* const*)__builtin_frame_address(0);
        const void* const* above = frame ? (const void* const*)frame[0] : NULL;
        sender = above ? above[1] : NULL;
    }
    PFBProbeCount(@"visible panels", sender, PFBProbeIDsText(panels));
    return panels;
}

- (void)recalculateVisiblePanels {
    PFBProbeCount(@"recalculate", __builtin_return_address(0), nil);
    %orig;
}

- (void)recalculateVisiblePanelsWithUpdatedPanelIDs:(NSArray*)panelIDs {
    PFBProbeCount(@"recalculate with", __builtin_return_address(0), PFBProbeIDsText(panelIDs));
    %orig;
}

%end

%hook _TtCC11XNavigation14CollapseEngine14ScrollObserver

- (void)handlePan:(UIGestureRecognizer*)recognizer {
    %orig;
    if (pthread_main_np() && gProbeStart > 0) {
        PFBProbeNotePan();
    }
}

%end

%end

// Methods other files hook as well: installed last, so each call is charged to its sender.
%group PFBGlassProbe

%hook _TtC11XNavigation10TabBarView

- (void)layoutSubviews {
    %orig;
    UIView* bar = (UIView*)self;
    if (gProbeBar != bar && PFBProbeOnScreen(bar)) {
        gProbeBar = bar;
    }
    PFBProbeCount(@"bar layout", NULL, nil);
    if (bar == gProbeBar) {
        @try {
            PFBProbeNoteTabs(bar);
        } @catch (__unused id exception) {
        }
    }
}

%end

%hook _TtC11XNavigation14TabBarItemView

- (void)layoutSubviews {
    %orig;
    PFBProbeCount(@"tab layout", NULL, nil);
}

%end

%hook _TtC11XNavigation23TabBarAccessoryHostView

- (void)layoutSubviews {
    %orig;
    UIView* host = (UIView*)self;
    if (host.frame.size.width > 0 && PFBProbeOnScreen(host)) {
        gProbeAccessory = host;
    }
}

%end

// The screens in front, and how each declares its bars to Twitter's navigation.
%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    UIViewController* controller = (UIViewController*)self;
    if (gProbeStart <= 0 || !PFBOnNativeGlassStack(controller)) {
        return;
    }
    UIView* view = controller.viewIfLoaded;
    if (!view.window || CGRectGetHeight(view.bounds) < CGRectGetHeight(view.window.bounds) * 0.5) {
        return;
    }
    gProbeScreen = controller;
    NSString* name = PFBProbeName([controller class]);
    if (!gProbeScreens) {
        gProbeScreens = [NSMutableDictionary dictionary];
    }
    if (!gProbeScreens[name] && gProbeScreens.count < 12) {
        @try {
            gProbeScreens[name] = PFBProbeDeclarationText(controller);
        } @catch (id exception) {
            gProbeScreens[name] = [NSString stringWithFormat:@"unreadable (%@)", exception];
        }
    }
}

%end

%end

// The early hooks go in at once, to see the launch. Every other file installs its hooks
// from its constructor and the main queue first runs once they all have, so the others
// are installed last.
%ctor {
    gProbeStart = CACurrentMediaTime();
    PFBProbeFindOurCode();
    %init(PFBGlassProbeEarly);
    dispatch_async(dispatch_get_main_queue(), ^{
      PFBProbeStart();
      %init(PFBGlassProbe);
    });
}
