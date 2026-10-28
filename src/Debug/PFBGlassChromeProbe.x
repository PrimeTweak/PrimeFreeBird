// Measures what Twitter's own Liquid Glass offers the options that lack a hook point
// there: the tab bar's icons, titles and room (Selected tab, Tab labels), its shrinking
// on scroll (Always visible), what builds its tabs (Customize tabs), the compose button
// (Classic Tweet button, Hide Tweet button) and the Spaces bar.
//
// A summary goes to MEASUREMENTS. When Twitter leaves the screen, this report and the
// whole Compatibility report go to the pasteboard, unless something was copied while
// Twitter was in front. The hooks are installed after every other file's, so each call
// is charged to the code that sent it.

#import <mach-o/loader.h>
#import <os/lock.h>
#import <pthread.h>
#import "Support/HookHelpers.h"
#import "Common/PFBCompatibility.h"

// The methods called below that no header declares.
@interface T1PanelIdentity (PFBGlassChromeProbe)
+ (NSString*)localizedNameForPanelID:(long long)panelID;
@end

@interface T1HostViewController (PFBGlassChromeProbe)
- (id)appNavigation;
@end

@interface TFNTwitterAccount (PFBGlassChromeProbe)
- (BOOL)isPremiumTierUser;
- (NSArray*)subscriptionClaims;
- (id)featureSwitches;
@end

@interface _TtC14T1TwitterSwift20XTabbedAppNavigation : NSObject
- (NSArray*)visiblePanelIDs;
- (void)setCurrentPanel:(long long)panel animated:(BOOL)animated completion:(id)completion;
@end

@interface XNAVConfiguration : NSObject
+ (instancetype)standardConfiguration;
+ (instancetype)pinnedConfiguration;
+ (instancetype)hiddenConfiguration;
+ (instancetype)pinnedTransparentConfiguration;
+ (instancetype)configurationWithCollapseMode:(long long)collapse popGestureMode:(long long)pop;
+ (instancetype)configurationWithCollapseMode:(long long)collapse
                               popGestureMode:(long long)pop
                         solidBackgroundColor:(UIColor*)color;
@end

@interface XNAVNavigationController : UINavigationController
- (instancetype)initWithRootViewController:(UIViewController*)root
                      popGestureCapability:(long long)capability
                      defaultConfiguration:(XNAVConfiguration*)configuration;
- (instancetype)initWithPopGestureCapability:(long long)capability
                        defaultConfiguration:(XNAVConfiguration*)configuration;
@end

@interface T1TabCustomizationConfig : NSObject
- (instancetype)initWithAccount:(id)account;
- (BOOL)isTabCustomizationEnabled;
@end

@interface TFSTwitterSubscriptionClaim : NSObject
- (NSString*)restId;
@end

@interface T1FleetLineHeaderController : NSObject
- (BOOL)_t1_shouldShowFleetLine;
@end

@interface T1FleetLineView : UIView
- (instancetype)initWithAccount:(id)account delegate:(id)delegate;
@end

@interface _TtCC11XNavigation14CollapseEngine14ScrollObserver : NSObject
- (void)handlePan:(UIGestureRecognizer*)recognizer;
@end

static NSString* const kPFBProbeTopic = @"glass probe";
static CFTimeInterval gProbeStart;
static NSString* gProbeLaunchClock;

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
    if (self.total <= 300) {
        NSString* caller = ours ? @"PrimeFreeBird" : PFBProbeCaller(address);
        if (self.callers[caller] || self.callers.count < 8) {
            self.callers[caller] = @(self.callers[caller].unsignedIntegerValue + 1);
        }
    }
    if (value.length && self.values.count < 16) {
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
    NSMutableString* text = [NSMutableString stringWithFormat:@"%lu (by PrimeFreeBird %lu), from [%@]",
                                                               (unsigned long)self.total, (unsigned long)self.ours,
                                                               [senders componentsJoinedByString:@", "]];
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

// MARK: - Icons by name

// The name an icon of Twitter's icon set was loaded with, carried to the copies made of it.
static const void* kPFBProbeIconKey = &kPFBProbeIconKey;
static os_unfair_lock gProbeIconLock = OS_UNFAIR_LOCK_INIT;
static NSMutableDictionary<NSString*, NSString*>* gProbeIconNames;  // name -> first sender

static BOOL PFBProbeIsIconBundle(NSBundle* bundle) {
    static __weak NSBundle* known;
    if (!bundle) {
        return NO;
    }
    if (bundle == known) {
        return YES;
    }
    if ([bundle.bundlePath hasSuffix:@"XIconsAssets.bundle"]) {
        known = bundle;
        return YES;
    }
    return NO;
}

static void PFBProbeTagIcon(UIImage* image, NSString* name, NSBundle* bundle, const void* address) {
    if (!image || !name.length || gProbeStart <= 0 || !PFBProbeIsIconBundle(bundle)) {
        return;
    }
    objc_setAssociatedObject(image, kPFBProbeIconKey, name, OBJC_ASSOCIATION_COPY_NONATOMIC);
    os_unfair_lock_lock(&gProbeIconLock);
    BOOL known = gProbeIconNames[name] != nil || gProbeIconNames.count >= 120;
    os_unfair_lock_unlock(&gProbeIconLock);
    if (known) {
        return;
    }
    NSString* caller = PFBProbeCaller(address);
    os_unfair_lock_lock(&gProbeIconLock);
    if (!gProbeIconNames) {
        gProbeIconNames = [NSMutableDictionary dictionary];
    }
    if (!gProbeIconNames[name]) {
        gProbeIconNames[name] = caller;
    }
    os_unfair_lock_unlock(&gProbeIconLock);
}

static void PFBProbeCarryIcon(UIImage* source, UIImage* copy) {
    if (!source || !copy || copy == source || gProbeStart <= 0) {
        return;
    }
    NSString* name = objc_getAssociatedObject(source, kPFBProbeIconKey);
    if (name) {
        objc_setAssociatedObject(copy, kPFBProbeIconKey, name, OBJC_ASSOCIATION_COPY_NONATOMIC);
    }
}

// An image by the icon name it was loaded with, its vector or symbol name, or its size.
static NSString* PFBProbeImageText(UIImage* image) {
    if (!image) {
        return @"no image";
    }
    NSString* icon = objc_getAssociatedObject(image, kPFBProbeIconKey);
    NSString* mode = image.renderingMode == UIImageRenderingModeAlwaysTemplate
                         ? @" template"
                         : (image.renderingMode == UIImageRenderingModeAlwaysOriginal ? @" original" : @"");
    if (icon) {
        return [NSString stringWithFormat:@"icon %@%@", icon, mode];
    }
    id vector = objc_getAssociatedObject(image, (const void*)NSSelectorFromString(@"tfn_vectorImageNamed:fitsSize:fillColor:"));
    if ([vector isKindOfClass:[NSString class]]) {
        return [NSString stringWithFormat:@"vector %@%@", vector, mode];
    }
    if (image.isSymbolImage) {
        return [@"symbol" stringByAppendingString:mode];
    }
    return [NSString stringWithFormat:@"image %.0fx%.0f%@", image.size.width, image.size.height, mode];
}

static NSString* PFBProbeColorText(UIColor* color) {
    if (!color) {
        return @"none";
    }
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) {
        return PFBProbeName([color class]);
    }
    return [NSString stringWithFormat:@"rgba(%.0f,%.0f,%.0f,%.2f)", r * 255.0, g * 255.0, b * 255.0, a];
}

// A layer's filters by name, and its compositing filter.
static NSString* PFBProbeFiltersText(CALayer* layer) {
    NSMutableArray<NSString*>* names = [NSMutableArray array];
    @try {
        for (id filter in layer.filters) {
            id name = [filter respondsToSelector:@selector(name)] ? [filter valueForKey:@"name"] : nil;
            id type = [filter respondsToSelector:@selector(type)] ? [filter valueForKey:@"type"] : nil;
            [names addObject:[NSString stringWithFormat:@"%@%@", name ?: @"?",
                                                        type && ![type isEqual:name] ? [NSString stringWithFormat:@"(%@)", type] : @""]];
        }
        id compositing = layer.compositingFilter;
        if (compositing) {
            id name = [compositing isKindOfClass:[NSString class]] ? compositing : [compositing valueForKey:@"name"];
            [names addObject:[NSString stringWithFormat:@"compositing %@", name ?: @"?"]];
        }
    } @catch (__unused id exception) {
        [names addObject:@"unreadable"];
    }
    return names.count ? [names componentsJoinedByString:@" "] : @"";
}

// MARK: - The bar and the compose button

static __weak UIView* gProbeBar;
static __weak UIView* gProbeAccessory;
static Class gProbeItemClass;

static BOOL PFBProbeOnScreen(UIView* view) {
    UIWindow* window = view.window;
    return window && CGRectIntersectsRect([view convertRect:view.bounds toView:nil], window.bounds);
}

static BOOL PFBProbeViewIn(UIView* view, UIView* root) {
    if (!root) {
        return NO;
    }
    __unsafe_unretained UIView* node = view;
    for (NSInteger depth = 0; node && depth < 40; depth++) {
        if (node == root) {
            return YES;
        }
        node = node.superview;
    }
    return NO;
}

static BOOL PFBProbeLayerIn(CALayer* layer, UIView* root) {
    CALayer* target = root.layer;
    if (!target) {
        return NO;
    }
    __unsafe_unretained CALayer* node = layer;
    for (NSInteger depth = 0; node && depth < 60; depth++) {
        if (node == target) {
            return YES;
        }
        node = node.superlayer;
    }
    return NO;
}

// What a layer belongs to: its view's class, or the layer's own.
static NSString* PFBProbeLayerOwner(CALayer* layer) {
    id delegate = layer.delegate;
    return PFBProbeName([delegate isKindOfClass:[UIView class]] ? [delegate class] : [layer class]);
}

static UIImageView* PFBProbeGlyphView(UIView* view) {
    __block UIImageView* found = nil;
    PFBWalkAllSubviews(view, 6, ^(UIView* sub) {
      if (!found && [sub isKindOfClass:[UIImageView class]]) {
          found = (UIImageView*)sub;
      }
    });
    return found;
}

// The bar's selected tab, read from its stored index.
static NSInteger PFBProbeSelectedIndex(UIView* bar) {
    Ivar ivar = class_getInstanceVariable([bar class], "selectedIndex");
    if (!ivar) {
        return NSNotFound;
    }
    NSInteger value = *(NSInteger*)((uint8_t*)(__bridge void*)bar + ivar_getOffset(ivar));
    return value >= -1 && value < 64 ? value : NSNotFound;
}

static id PFBProbeAppNavigation(void) {
    T1HostViewController* host = [T1HostViewController sharedHostViewController];
    return [host respondsToSelector:@selector(appNavigation)] ? [host appNavigation] : nil;
}

// The panels Twitter's new navigation shows, with their names.
static NSString* PFBProbePanelsText(void) {
    id navigation = PFBProbeAppNavigation();
    NSArray* panels = [navigation respondsToSelector:@selector(visiblePanelIDs)] ? [navigation visiblePanelIDs] : nil;
    if (![panels isKindOfClass:[NSArray class]]) {
        return [NSString stringWithFormat:@"none (%@)", PFBProbeName([navigation class])];
    }
    NSMutableArray<NSString*>* names = [NSMutableArray array];
    BOOL named = [T1PanelIdentity respondsToSelector:@selector(localizedNameForPanelID:)];
    for (id panel in panels) {
        long long panelID = [panel respondsToSelector:@selector(longLongValue)] ? [panel longLongValue] : -1;
        NSString* name = named ? [T1PanelIdentity localizedNameForPanelID:panelID] : nil;
        [names addObject:[NSString stringWithFormat:@"%lld %@", panelID, name.length ? name : @"?"]];
    }
    return [NSString stringWithFormat:@"[%@]", [names componentsJoinedByString:@", "]];
}

static NSString* PFBProbeItemText(UIView* item, UIView* bar, BOOL full) {
    UIImageView* glyph = PFBProbeGlyphView(item);
    CGRect frame = [item convertRect:item.bounds toView:bar];
    NSMutableString* text = [NSMutableString stringWithFormat:@"x %.0f w %.0f", frame.origin.x, frame.size.width];
    if (full) {
        NSString* label = item.accessibilityLabel;
        [text appendFormat:@" \"%@\"", label.length ? label : @""];
        if (glyph) {
            CGRect inItem = [glyph convertRect:glyph.bounds toView:item];
            CGRect holder = glyph.superview ? [glyph.superview convertRect:glyph.superview.bounds toView:item] : CGRectZero;
            [text appendFormat:@", glyph %.0fx%.0f at %.1f,%.1f in a %.0fx%.0f holder", inItem.size.width,
                               inItem.size.height, inItem.origin.x, inItem.origin.y, holder.size.width,
                               holder.size.height];
        }
    }
    if (glyph) {
        NSString* filters = PFBProbeFiltersText(glyph.layer);
        [text appendFormat:@", %@, tint %@%@%@", PFBProbeImageText(glyph.image), PFBProbeColorText(glyph.tintColor),
                           glyph.alpha < 0.99 ? [NSString stringWithFormat:@", alpha %.2f", glyph.alpha] : @"",
                           filters.length ? [NSString stringWithFormat:@", filters %@", filters] : @""];
    } else {
        [text appendString:@", no glyph"];
    }
    if (item.alpha < 0.99 || item.hidden) {
        [text appendFormat:@", item %@", item.hidden ? @"hidden" : [NSString stringWithFormat:@"alpha %.2f", item.alpha]];
    }
    return text;
}

// From a glyph up to the bar: each view and the filters on its layer.
static NSString* PFBProbeChainText(UIView* glyph, UIView* bar) {
    NSMutableArray<NSString*>* steps = [NSMutableArray array];
    for (UIView* node = glyph; node && steps.count < 12; node = node.superview) {
        NSString* filters = PFBProbeFiltersText(node.layer);
        [steps addObject:[NSString stringWithFormat:@"%@%@%@", PFBProbeName([node class]),
                                                    filters.length ? [NSString stringWithFormat:@" [%@]", filters] : @"",
                                                    node.alpha < 0.99 ? [NSString stringWithFormat:@" alpha %.2f", node.alpha] : @""]];
        if (node == bar) {
            break;
        }
    }
    return [steps componentsJoinedByString:@" < "];
}

// The bar's tabs row by row: where each sits, its label, glyph, tint and filters.
static NSString* PFBProbeBarText(void) {
    UIView* bar = gProbeBar;
    if (!bar) {
        return NSClassFromString(@"_TtC11XNavigation10TabBarView") ? @"never laid out" : @"not in this Twitter";
    }
    CGRect frame = [bar convertRect:bar.bounds toView:nil];
    NSMutableString* text = [NSMutableString
        stringWithFormat:@"%@ at %.0f,%.0f %.0fx%.0f, selected index %@ · panels %@", PFBProbeName([bar class]),
                         frame.origin.x, frame.origin.y, frame.size.width, frame.size.height,
                         PFBProbeSelectedIndex(bar) == NSNotFound ? @"?" : @(PFBProbeSelectedIndex(bar)),
                         PFBProbePanelsText()];
    NSMutableArray<UIView*>* rows = [NSMutableArray array];
    NSMapTable<UIView*, NSMutableArray<UIView*>*>* items = [NSMapTable strongToStrongObjectsMapTable];
    PFBWalkAllSubviews(bar, 30, ^(UIView* view) {
      if (!gProbeItemClass || ![view isKindOfClass:gProbeItemClass] || !view.superview) {
          return;
      }
      NSMutableArray<UIView*>* row = [items objectForKey:view.superview];
      if (!row) {
          row = [NSMutableArray array];
          [items setObject:row forKey:view.superview];
          [rows addObject:view.superview];
      }
      [row addObject:view];
    });
    for (NSUInteger index = 0; index < rows.count; index++) {
        UIView* rowView = rows[index];
        NSMutableArray<UIView*>* row = [items objectForKey:rowView];
        [row sortUsingComparator:^NSComparisonResult(UIView* a, UIView* b) {
          return a.frame.origin.x < b.frame.origin.x ? NSOrderedAscending
                                                     : (a.frame.origin.x > b.frame.origin.x ? NSOrderedDescending : NSOrderedSame);
        }];
        NSString* rowFilters = PFBProbeFiltersText(rowView.layer);
        [text appendFormat:@"\n  row %lu, %@%@%@ (%lu tabs):", (unsigned long)index + 1, PFBProbeName([rowView class]),
                           rowFilters.length ? [NSString stringWithFormat:@" [%@]", rowFilters] : @"",
                           rowView.alpha < 0.99 || rowView.hidden
                               ? [NSString stringWithFormat:@" %@", rowView.hidden ? @"hidden" : [NSString stringWithFormat:@"alpha %.2f", rowView.alpha]]
                               : @"",
                           (unsigned long)row.count];
        for (UIView* item in row) {
            [text appendFormat:@"\n    %@", PFBProbeItemText(item, bar, index == 0)];
        }
        NSInteger selected = PFBProbeSelectedIndex(bar);
        UIView* sample = selected != NSNotFound && selected >= 0 && (NSUInteger)selected < row.count ? row[(NSUInteger)selected] : row.firstObject;
        UIImageView* glyph = PFBProbeGlyphView(sample);
        if (glyph) {
            [text appendFormat:@"\n    from the %@ glyph to the bar: %@", sample == row.firstObject && selected != 0 ? @"first" : @"selected",
                               PFBProbeChainText(glyph, bar)];
        }
    }
    Class pillClass = NSClassFromString(@"_TtC11XNavigation10TabBarPill");
    PFBWalkAllSubviews(bar, 20, ^(UIView* view) {
      if (pillClass && [view isKindOfClass:pillClass]) {
          CGRect pill = [view convertRect:view.bounds toView:bar];
          NSMutableArray<NSString*>* parts = [NSMutableArray array];
          for (UIView* sub in view.subviews) {
              NSString* filters = PFBProbeFiltersText(sub.layer);
              [parts addObject:[NSString stringWithFormat:@"%@%@", PFBProbeName([sub class]),
                                                          filters.length ? [NSString stringWithFormat:@" [%@]", filters] : @""]];
          }
          [text appendFormat:@"\n  pill at %.0f,%.0f %.0fx%.0f: %@", pill.origin.x, pill.origin.y, pill.size.width,
                             pill.size.height, parts.count ? [parts componentsJoinedByString:@", "] : @"no parts"];
      }
    });
    return text;
}

// The compose button: where it is, its glyph and the glass behind it.
static NSString* PFBProbeComposeText(void) {
    UIView* host = gProbeAccessory;
    if (!host) {
        return @"not laid out yet";
    }
    CGRect frame = [host convertRect:host.bounds toView:nil];
    NSMutableString* text = [NSMutableString stringWithFormat:@"%@ at %.0f,%.0f %.0fx%.0f%@%@", PFBProbeName([host class]),
                                                              frame.origin.x, frame.origin.y, frame.size.width,
                                                              frame.size.height, host.hidden ? @", hidden" : @"",
                                                              host.alpha < 0.99 ? [NSString stringWithFormat:@", alpha %.2f", host.alpha] : @""];
    NSMutableArray<NSString*>* parts = [NSMutableArray array];
    PFBWalkAllSubviews(host, 14, ^(UIView* view) {
      if (parts.count >= 10) {
          return;
      }
      if ([view isKindOfClass:[UIImageView class]] && ((UIImageView*)view).image) {
          UIImageView* glyph = (UIImageView*)view;
          [parts addObject:[NSString stringWithFormat:@"glyph %.0fx%.0f %@ tint %@", glyph.bounds.size.width,
                                                      glyph.bounds.size.height, PFBProbeImageText(glyph.image),
                                                      PFBProbeColorText(glyph.tintColor)]];
      } else if ([view isKindOfClass:[UIVisualEffectView class]]) {
          UIVisualEffect* effect = ((UIVisualEffectView*)view).effect;
          UIColor* tint = nil;
          @try {
              tint = [effect respondsToSelector:@selector(tintColor)] ? [effect valueForKey:@"tintColor"] : nil;
          } @catch (__unused id exception) {
          }
          [parts addObject:[NSString stringWithFormat:@"effect %@ tint %@", PFBProbeName([effect class]),
                                                      PFBProbeColorText(tint)]];
      } else if ([view isKindOfClass:[UIControl class]]) {
          [parts addObject:[NSString stringWithFormat:@"control %@", PFBProbeName([view class])]];
      }
    });
    [text appendFormat:@": %@", parts.count ? [parts componentsJoinedByString:@" · "] : @"no parts"];
    return text;
}

// MARK: - Snapshots

static NSMutableArray<NSString*>* gProbeSnapshots;
static NSUInteger gProbeSnapshotsTaken;

static void PFBProbeTakeSnapshot(NSString* moment) {
    if (!gProbeSnapshots) {
        gProbeSnapshots = [NSMutableArray array];
    }
    @try {
        NSString* text = [NSString stringWithFormat:@"%@ (%.0f s): %@", moment, CACurrentMediaTime() - gProbeStart,
                                                    PFBProbeBarText()];
        [gProbeSnapshots addObject:text];
        if (gProbeSnapshots.count > 7) {
            [gProbeSnapshots removeObjectAtIndex:1];
        }
    } @catch (id exception) {
        [gProbeSnapshots addObject:[NSString stringWithFormat:@"%@: stopped (%@)", moment, exception]];
    }
}

static void PFBProbeSnapshotSoon(NSString* moment, double delay) {
    if (gProbeSnapshotsTaken >= 12) {
        return;
    }
    gProbeSnapshotsTaken++;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      PFBProbeTakeSnapshot(moment);
    });
}

// MARK: - Shrinking on scroll

// The bytes of an XNAVConfiguration's stored configuration, compared with Twitter's
// four named ones.
static NSData* PFBProbeConfigBytes(id configuration) {
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

static BOOL gProbeBuildingReferences;

static NSString* PFBProbeConfigText(id configuration) {
    static NSDictionary<NSString*, NSData*>* references;
    Class cls = NSClassFromString(@"XNAVConfiguration");
    if (!references && cls) {
        gProbeBuildingReferences = YES;
        NSMutableDictionary<NSString*, NSData*>* found = [NSMutableDictionary dictionary];
        @try {
            found[@"standard"] = PFBProbeConfigBytes([cls standardConfiguration]);
            found[@"pinned"] = PFBProbeConfigBytes([cls pinnedConfiguration]);
            found[@"hidden"] = PFBProbeConfigBytes([cls hiddenConfiguration]);
            found[@"pinned transparent"] = PFBProbeConfigBytes([cls pinnedTransparentConfiguration]);
        } @catch (__unused id exception) {
        }
        gProbeBuildingReferences = NO;
        references = [found copy];
    }
    if (!configuration) {
        return @"none";
    }
    NSData* bytes = PFBProbeConfigBytes(configuration);
    if (!bytes) {
        return PFBProbeName([configuration class]);
    }
    for (NSString* name in references) {
        if ([references[name] isEqualToData:bytes]) {
            return name;
        }
    }
    NSMutableString* hex = [NSMutableString stringWithString:@"other "];
    const uint8_t* raw = bytes.bytes;
    for (NSUInteger i = 0; i < MIN(bytes.length, (NSUInteger)24); i++) {
        [hex appendFormat:@"%02x", raw[i]];
    }
    return hex;
}

// Whether a screen declares its bars to Twitter's navigation, in Swift or in Objective-C.
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
    } else {
        [parts addObject:@"Swift unreadable"];
    }
    if (type && conforms && delegates && conforms(type, delegates)) {
        [parts addObject:@"Swift delegates"];
    }
    Protocol* objc = objc_getProtocol("XNAVConfigurationProviding");
    SEL getter = NSSelectorFromString(@"xnav_navigationConfiguration");
    if ((objc && [controller conformsToProtocol:objc]) || [controller respondsToSelector:getter]) {
        id configuration = [controller respondsToSelector:getter] ? ((id (*)(id, SEL))objc_msgSend)(controller, getter) : nil;
        [parts addObject:[NSString stringWithFormat:@"ObjC %@", PFBProbeConfigText(configuration)]];
    }
    return [parts componentsJoinedByString:@", "];
}

static NSMutableArray<NSString*>* gProbeStacks;
static NSMutableDictionary<NSString*, NSString*>* gProbeScreens;
static __weak UIViewController* gProbeScreen;

static void PFBProbeNoteStack(UIViewController* root, long long capability, id configuration) {
    if (!gProbeStacks) {
        gProbeStacks = [NSMutableArray array];
    }
    if (gProbeStacks.count >= 14) {
        return;
    }
    [gProbeStacks addObject:[NSString stringWithFormat:@"%@: %@, pop %lld", root ? PFBProbeName([root class]) : @"no root",
                                                       PFBProbeConfigText(configuration), capability]];
}

// One window per scroll: what the bar and the top bar did while the finger moved, and
// for 1.5 s after.
@interface PFBProbeScrollWindow : NSObject
@property(nonatomic, copy) NSString* screen;
@property(nonatomic) CFTimeInterval began;
@property(nonatomic) CFTimeInterval lastPan;
@property(nonatomic) NSUInteger pans;
@property(nonatomic) NSUInteger samples;
@property(nonatomic) CGFloat barMinWidth, barMaxWidth, barMinHeight, barMaxHeight, barMinY, barMaxY, barMinAlpha;
@property(nonatomic) CGFloat barMinScale;
@property(nonatomic) CGFloat topMinY, topMaxY, topMinHeight, topMaxHeight, topMinAlpha;
@end

@implementation PFBProbeScrollWindow
@end

@interface PFBProbeSampler : NSObject
@property(nonatomic, strong) CADisplayLink* link;
@property(nonatomic, strong) PFBProbeScrollWindow* window;
- (void)tick:(CADisplayLink*)link;
@end

static NSMutableArray<NSString*>* gProbeScrollTexts;
static PFBProbeSampler* gProbeSampler;
static NSUInteger gProbeScrollWindows;
static NSUInteger gProbeCollapsedWindows;

static NSString* PFBProbeScrollText(PFBProbeScrollWindow* window) {
    return [NSString stringWithFormat:@"%@, %lu pans, %lu samples · tab bar width %.0f to %.0f, height %.0f to %.0f, "
                                      @"top %.0f to %.0f, scale down to %.2f, alpha down to %.2f · top bar y %.0f to "
                                      @"%.0f, height %.0f to %.0f, alpha down to %.2f",
                                      window.screen, (unsigned long)window.pans, (unsigned long)window.samples,
                                      window.barMinWidth, window.barMaxWidth, window.barMinHeight, window.barMaxHeight,
                                      window.barMinY, window.barMaxY, window.barMinScale, window.barMinAlpha,
                                      window.topMinY, window.topMaxY, window.topMinHeight, window.topMaxHeight,
                                      window.topMinAlpha];
}

@implementation PFBProbeSampler

- (void)tick:(CADisplayLink*)link {
    PFBProbeScrollWindow* window = self.window;
    CFTimeInterval now = CACurrentMediaTime();
    if (!window || now - window.lastPan > 1.5) {
        [link invalidate];
        self.link = nil;
        if (window && window.samples) {
            gProbeScrollWindows++;
            gProbeCollapsedWindows += window.barMinWidth < window.barMaxWidth - 20.0 || window.barMinScale < 0.95 ? 1 : 0;
            if (!gProbeScrollTexts) {
                gProbeScrollTexts = [NSMutableArray array];
            }
            [gProbeScrollTexts addObject:PFBProbeScrollText(window)];
            if (gProbeScrollTexts.count > 6) {
                [gProbeScrollTexts removeObjectAtIndex:0];
            }
        }
        self.window = nil;
        return;
    }
    UIView* bar = gProbeBar;
    if (!bar.window) {
        return;
    }
    CGRect frame = [bar convertRect:bar.bounds toView:nil];
    CGFloat scale = (CGFloat)sqrt(bar.transform.a * bar.transform.a + bar.transform.c * bar.transform.c);
    BOOL first = window.samples == 0;
    window.samples++;
    window.barMinWidth = first ? frame.size.width : MIN(window.barMinWidth, frame.size.width);
    window.barMaxWidth = first ? frame.size.width : MAX(window.barMaxWidth, frame.size.width);
    window.barMinHeight = first ? frame.size.height : MIN(window.barMinHeight, frame.size.height);
    window.barMaxHeight = first ? frame.size.height : MAX(window.barMaxHeight, frame.size.height);
    window.barMinY = first ? frame.origin.y : MIN(window.barMinY, frame.origin.y);
    window.barMaxY = first ? frame.origin.y : MAX(window.barMaxY, frame.origin.y);
    window.barMinScale = first ? scale : MIN(window.barMinScale, scale);
    window.barMinAlpha = first ? bar.alpha : MIN(window.barMinAlpha, bar.alpha);
    UINavigationBar* top = gProbeScreen.navigationController.navigationBar;
    if (top.window) {
        CGRect topFrame = [top convertRect:top.bounds toView:nil];
        BOOL topFirst = window.topMaxHeight <= 0;
        window.topMinY = topFirst ? topFrame.origin.y : MIN(window.topMinY, topFrame.origin.y);
        window.topMaxY = topFirst ? topFrame.origin.y : MAX(window.topMaxY, topFrame.origin.y);
        window.topMinHeight = topFirst ? topFrame.size.height : MIN(window.topMinHeight, topFrame.size.height);
        window.topMaxHeight = MAX(window.topMaxHeight, topFrame.size.height);
        window.topMinAlpha = topFirst ? top.alpha : MIN(window.topMinAlpha, top.alpha);
    }
}

@end

static void PFBProbeNotePan(void) {
    if (!gProbeSampler) {
        gProbeSampler = [PFBProbeSampler new];
    }
    CFTimeInterval now = CACurrentMediaTime();
    if (!gProbeSampler.window) {
        PFBProbeScrollWindow* window = [PFBProbeScrollWindow new];
        window.began = now;
        window.screen = gProbeScreen ? PFBProbeName([gProbeScreen class]) : @"?";
        gProbeSampler.window = window;
    }
    gProbeSampler.window.lastPan = now;
    gProbeSampler.window.pans++;
    if (!gProbeSampler.link) {
        gProbeSampler.link = [CADisplayLink displayLinkWithTarget:gProbeSampler selector:@selector(tick:)];
        [gProbeSampler.link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
}

// MARK: - Customize tabs

// Twitter's Custom navigation: whether its gate opens for this account, and what it reads.
// Read once an account is signed in, then kept: the reading builds one of Twitter's objects.
static NSString* gProbeCustomNavigation;

static NSString* PFBProbeCustomNavigationText(void) {
    if (gProbeCustomNavigation) {
        return gProbeCustomNavigation;
    }
    NSMutableArray<NSString*>* parts = [NSMutableArray array];
    @try {
        id account = [[T1HostViewController sharedHostViewController] currentAccount];
        Class configClass = NSClassFromString(@"T1TabCustomizationConfig");
        T1TabCustomizationConfig* config =
            account && configClass ? [(T1TabCustomizationConfig*)[configClass alloc] initWithAccount:account] : nil;
        [parts addObject:[NSString stringWithFormat:@"Custom navigation open %@",
                                                    [config respondsToSelector:@selector(isTabCustomizationEnabled)]
                                                        ? ([config isTabCustomizationEnabled] ? @"yes" : @"no")
                                                        : @"?"]];
        NSString* const* key = (NSString* const*)dlsym(RTLD_DEFAULT, "T1SubscriptionsTabCustomizationEnabledKey");
        id switches = [account respondsToSelector:@selector(featureSwitches)] ? [account featureSwitches] : nil;
        NSString* name = key ? *key : nil;
        NSString* value = name && [switches respondsToSelector:@selector(boolForKey:)]
                              ? ([switches boolForKey:name] ? @"yes" : @"no")
                              : @"?";
        [parts addObject:[NSString stringWithFormat:@"switch %@ %@", name ?: @"not found", value]];
        [parts addObject:[NSString stringWithFormat:@"Premium tier %@",
                                                    [account respondsToSelector:@selector(isPremiumTierUser)]
                                                        ? ([account isPremiumTierUser] ? @"yes" : @"no")
                                                        : @"?"]];
        NSArray* claims = [account respondsToSelector:@selector(subscriptionClaims)] ? [account subscriptionClaims] : nil;
        NSMutableArray<NSString*>* claimTexts = [NSMutableArray array];
        for (id claim in [claims isKindOfClass:[NSArray class]] ? claims : @[]) {
            if (claimTexts.count >= 4) {
                break;
            }
            NSString* rest = [claim respondsToSelector:@selector(restId)] ? [claim restId] : nil;
            id resources = nil;
            @try {
                resources = [claim valueForKey:@"resources"];
            } @catch (__unused id exception) {
            }
            NSString* resourcesText = [resources respondsToSelector:@selector(count)]
                                          ? [[[resources description] componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]
                                                componentsJoinedByString:@""]
                                          : @"?";
            [claimTexts addObject:[NSString stringWithFormat:@"%@ %@", rest ?: @"?",
                                                             resourcesText.length > 160 ? [resourcesText substringToIndex:160] : resourcesText]];
        }
        [parts addObject:[NSString stringWithFormat:@"claims %lu [%@]", (unsigned long)claims.count,
                                                    [claimTexts componentsJoinedByString:@" | "]]];
    } @catch (id exception) {
        [parts addObject:[NSString stringWithFormat:@"stopped: %@", exception]];
    }
    NSString* text = [parts componentsJoinedByString:@" · "];
    if ([[T1HostViewController sharedHostViewController] currentAccount]) {
        gProbeCustomNavigation = text;
    }
    return text;
}

// Saved values whose key names a tab set or the navigation.
static NSString* PFBProbeSavedKeysText(void) {
    NSDictionary* all = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
    NSMutableArray<NSString*>* found = [NSMutableArray array];
    NSArray<NSString*>* parts = @[ @"tabidentifier", @"tab_identifier", @"navigation", @"customiz", @"census", @"panel" ];
    for (NSString* key in [all.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        if (found.count >= 25 || ![key isKindOfClass:[NSString class]] || [key hasPrefix:@"pfb_"]) {
            continue;
        }
        NSString* lower = key.lowercaseString;
        for (NSString* part in parts) {
            if ([lower containsString:part]) {
                NSString* value = [[[all[key] description] componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]
                    componentsJoinedByString:@""];
                [found addObject:[NSString stringWithFormat:@"%@ = %@ %@", key, PFBProbeName([all[key] class]),
                                                            value.length > 80 ? [value substringToIndex:80] : value]];
                break;
            }
        }
    }
    return found.count ? [found componentsJoinedByString:@" | "] : @"none";
}

// The tab entries' two answers, counted through their own implementations.
static NSString* const kPFBProbeEntryClasses[] = {
    @"T1HomeTimelineAppNavigationTabEntry",
    @"_TtC14T1TwitterSwift25GrokAppNavigationTabEntry",
    @"_TtC14T1TwitterSwift25JobsAppNavigationTabEntry",
    @"_TtC14T1TwitterSwift25MoreAppNavigationTabEntry",
    @"_TtC14T1TwitterSwift25NewsAppNavigationTabEntry",
    @"_TtC14T1TwitterSwift26BoostAppNavigationTabEntry",
    @"_TtC14T1TwitterSwift26CallsAppNavigationTabEntry",
    @"_TtC14T1TwitterSwift26GuideAppNavigationTabEntry",
    @"_TtC14T1TwitterSwift26ListsAppNavigationTabEntry",
    @"_TtC14T1TwitterSwift26VoiceAppNavigationTabEntry",
    @"_TtC14T1TwitterSwift26XChatAppNavigationTabEntry",
    @"_TtC14T1TwitterSwift28ConnectAppNavigationTabEntry",
    @"_TtC14T1TwitterSwift28ProfileAppNavigationTabEntry",
    @"_TtC14T1TwitterSwift29PaymentsAppNavigationTabEntry",
    @"_TtC14T1TwitterSwift30BirdwatchAppNavigationTabEntry",
    @"_TtC14T1TwitterSwift30BookmarksAppNavigationTabEntry",
    @"_TtC14T1TwitterSwift31PremiumHubAppNavigationTabEntry",
    @"_TtC14T1TwitterSwift33OfflineCacheAppNavigationTabEntry",
    @"_TtC14T1TwitterSwift34NotificationsAppNavigationTabEntry",
    @"_TtC14T1TwitterSwift34T1CommunitiesAppNavigationTabEntry",
    @"_TtC14T1TwitterSwift36ActivityHistoryAppNavigationTabEntry",
};
#define PFB_PROBE_ENTRY_COUNT (sizeof(kPFBProbeEntryClasses) / sizeof(kPFBProbeEntryClasses[0]))

typedef BOOL (*PFBProbeBoolGetter)(id, SEL);
static Class gProbeEntryClasses[PFB_PROBE_ENTRY_COUNT];
static PFBProbeBoolGetter gProbeExcludedOriginals[PFB_PROBE_ENTRY_COUNT];
static PFBProbeBoolGetter gProbeSideBarOriginals[PFB_PROBE_ENTRY_COUNT];

static NSUInteger PFBProbeEntryIndex(id object) {
    for (Class cls = object_getClass(object); cls; cls = class_getSuperclass(cls)) {
        for (NSUInteger i = 0; i < PFB_PROBE_ENTRY_COUNT; i++) {
            if (gProbeEntryClasses[i] == cls) {
                return i;
            }
        }
    }
    return NSNotFound;
}

static void PFBProbeNoteEntry(id entry, NSString* question, BOOL answer, const void* address) {
    NSString* name = PFBProbeName(object_getClass(entry));
    if ([name hasSuffix:@"AppNavigationTabEntry"]) {
        name = [name substringToIndex:name.length - 21];
    }
    PFBProbeCount(question, address, [NSString stringWithFormat:@"%@ %@", name, answer ? @"yes" : @"no"]);
}

static BOOL PFBProbeEntryExcluded(id self, SEL _cmd) {
    NSUInteger index = PFBProbeEntryIndex(self);
    BOOL answer = index != NSNotFound && gProbeExcludedOriginals[index] ? gProbeExcludedOriginals[index](self, _cmd) : NO;
    PFBProbeNoteEntry(self, @"entry excluded from the tab bar", answer, __builtin_return_address(0));
    return answer;
}

static BOOL PFBProbeEntrySideBarOnly(id self, SEL _cmd) {
    NSUInteger index = PFBProbeEntryIndex(self);
    BOOL answer = index != NSNotFound && gProbeSideBarOriginals[index] ? gProbeSideBarOriginals[index](self, _cmd) : NO;
    PFBProbeNoteEntry(self, @"entry side menu only", answer, __builtin_return_address(0));
    return answer;
}

// Only methods each class implements itself are replaced, so a subclass never calls its
// parent's original twice.
static PFBProbeBoolGetter PFBProbeReplaceOwn(Class cls, SEL selector, IMP replacement) {
    unsigned int count = 0;
    Method* methods = class_copyMethodList(cls, &count);
    PFBProbeBoolGetter original = NULL;
    for (unsigned int i = 0; i < count; i++) {
        if (method_getName(methods[i]) == selector) {
            original = (PFBProbeBoolGetter)method_setImplementation(methods[i], replacement);
            break;
        }
    }
    free(methods);
    return original;
}

static void PFBProbeWatchEntries(void) {
    SEL excluded = NSSelectorFromString(@"isExcludedFromTabBar");
    SEL sideBar = NSSelectorFromString(@"isTabViewSideBarOnly");
    for (NSUInteger i = 0; i < PFB_PROBE_ENTRY_COUNT; i++) {
        Class cls = NSClassFromString(kPFBProbeEntryClasses[i]);
        if (!cls) {
            continue;
        }
        gProbeEntryClasses[i] = cls;
        gProbeExcludedOriginals[i] = PFBProbeReplaceOwn(cls, excluded, (IMP)PFBProbeEntryExcluded);
        gProbeSideBarOriginals[i] = PFBProbeReplaceOwn(cls, sideBar, (IMP)PFBProbeEntrySideBarOnly);
    }
}

// MARK: - The Spaces bar

static NSString* PFBProbeSpacesText(UIViewController* home) {
    NSMutableArray<NSString*>* found = [NSMutableArray array];
    PFBWalkAllSubviews(home.viewIfLoaded, 40, ^(UIView* view) {
      if (found.count >= 6) {
          return;
      }
      NSString* name = NSStringFromClass([view class]);
      BOOL fleet = [name containsString:@"FleetLine"] && ![name containsString:@"ItemView"] &&
                   ![name containsString:@"PresenceView"];
      BOOL space = [name containsString:@"SpaceBar"] || [name containsString:@"SpacesBar"] ||
                   [name containsString:@"AudioSpace"] || [name containsString:@"SpacesDock"];
      if (fleet || space) {
          CGRect frame = [view convertRect:view.bounds toView:nil];
          [found addObject:[NSString stringWithFormat:@"%@ at %.0f,%.0f %.0fx%.0f%@ in %@", PFBProbeName([view class]),
                                                      frame.origin.x, frame.origin.y, frame.size.width,
                                                      frame.size.height, view.hidden ? @" hidden" : @"",
                                                      PFBProbeName([view.superview class])]];
      }
    });
    return found.count ? [found componentsJoinedByString:@" | "] : @"none";
}

static NSString* gProbeHomeSpaces;

// MARK: - The report

static NSString* PFBProbeSettingsText(void) {
    NSString* (^on)(NSString*) = ^NSString*(NSString* key) {
      return [PFBSettings boolForKey:key] ? @"on" : @"off";
    };
    return [NSString stringWithFormat:@"Liquid Glass %@, Twitter's glass asked %@ · Selected tab %@ · Tab labels %@ · "
                                      @"Always visible %@ · Customize tabs %@ · Classic Tweet button %@ · Hide Tweet "
                                      @"button %@ · Hide Spaces bar %@",
                                      on(@"enable_liquid_glass"), PFBNativeGlassAsked() ? @"yes" : @"no",
                                      on(@"tab_bar_theming"), on(@"restore_tab_labels"), on(@"no_tab_bar_hiding"),
                                      [PFBCustomTabBarUtility visiblePageIDsInOrder] ? @"customized" : @"default",
                                      on(@"restore_tweet_button"), on(@"hide_tweet_button"), on(@"hide_spaces")];
}

static NSString* PFBProbeIconNamesText(void) {
    os_unfair_lock_lock(&gProbeIconLock);
    NSDictionary<NSString*, NSString*>* names = [gProbeIconNames copy];
    os_unfair_lock_unlock(&gProbeIconLock);
    if (!names.count) {
        return @"none";
    }
    NSMutableArray<NSString*>* parts = [NSMutableArray array];
    for (NSString* name in [names.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        [parts addObject:[NSString stringWithFormat:@"%@ (%@)", name, names[name]]];
    }
    return [NSString stringWithFormat:@"%lu: %@", (unsigned long)names.count, [parts componentsJoinedByString:@", "]];
}

static NSString* PFBProbeText(void) {
    NSDictionary* info = NSBundle.mainBundle.infoDictionary;
    NSMutableString* text = [NSMutableString
        stringWithFormat:@"GLASS PROBE 2 · PrimeFreeBird %@ · Twitter %@ · iOS %@ · launched %@, %.0f s ago\n%@\n",
                         PFBCompatBuildID(), info[@"CFBundleShortVersionString"], UIDevice.currentDevice.systemVersion,
                         gProbeLaunchClock, CACurrentMediaTime() - gProbeStart, PFBProbeSettingsText()];

    [text appendString:@"\nTAB BAR (Selected tab, Tab labels)\n"];
    PFBProbeTakeSnapshot(@"now");
    for (NSString* snapshot in gProbeSnapshots) {
        [text appendFormat:@"%@\n", snapshot];
    }
    [text appendFormat:@"Writes on the bar's glyphs: images %@\n  tints %@\n  filters set %@\n  compositing filters %@\n",
                       PFBProbeTallyText(@"bar image"), PFBProbeTallyText(@"bar tint"), PFBProbeTallyText(@"bar filters"),
                       PFBProbeTallyText(@"bar compositing")];
    [text appendFormat:@"Bar layouts %@ · tab layouts %@\n", PFBProbeTallyText(@"bar layout"),
                       PFBProbeTallyText(@"tab layout")];
    [text appendFormat:@"Icons loaded by name: %@\n", PFBProbeIconNamesText()];

    [text appendString:@"\nSHRINKING ON SCROLL (Always visible)\n"];
    [text appendFormat:@"Stacks built: %@\n", gProbeStacks.count ? [gProbeStacks componentsJoinedByString:@" | "] : @"none"];
    [text appendFormat:@"Configurations asked: standard %@\n  pinned %@\n  hidden %@\n  pinned transparent %@\n  by mode %@\n",
                       PFBProbeTallyText(@"config standard"), PFBProbeTallyText(@"config pinned"),
                       PFBProbeTallyText(@"config hidden"), PFBProbeTallyText(@"config pinned transparent"),
                       PFBProbeTallyText(@"config by mode")];
    NSMutableArray<NSString*>* screens = [NSMutableArray array];
    for (NSString* screen in [gProbeScreens.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        [screens addObject:[NSString stringWithFormat:@"%@: %@", screen, gProbeScreens[screen]]];
    }
    [text appendFormat:@"Screens: %@\n", screens.count ? [screens componentsJoinedByString:@" | "] : @"none"];
    [text appendFormat:@"Scroll observer pans %@ · scroll windows %lu, the bar shrank in %lu\n",
                       PFBProbeTallyText(@"scroll pan"), (unsigned long)gProbeScrollWindows,
                       (unsigned long)gProbeCollapsedWindows];
    for (NSString* window in gProbeScrollTexts) {
        [text appendFormat:@"  %@\n", window];
    }

    [text appendString:@"\nCUSTOMIZE TABS\n"];
    [text appendFormat:@"%@\nTwitter shows panels %@\n", PFBProbeCustomNavigationText(), PFBProbePanelsText()];
    [text appendFormat:@"Entries asked: excluded from the tab bar %@\n  side menu only %@\n",
                       PFBProbeTallyText(@"entry excluded from the tab bar"), PFBProbeTallyText(@"entry side menu only")];
    [text appendFormat:@"Saved keys: %@\n", PFBProbeSavedKeysText()];

    [text appendString:@"\nCOMPOSE BUTTON (Classic Tweet button, Hide Tweet button)\n"];
    [text appendFormat:@"%@\nWrites: images %@\n  alpha %@\n  hidden %@\n  host layouts %@\n", PFBProbeComposeText(),
                       PFBProbeTallyText(@"compose image"), PFBProbeTallyText(@"compose alpha"),
                       PFBProbeTallyText(@"compose hidden"), PFBProbeTallyText(@"compose layout")];

    [text appendString:@"\nSPACES BAR (Hide Spaces bar)\n"];
    [text appendFormat:@"Spaces line asked %@ · Spaces bars made %@ · on Home: %@\n",
                       PFBProbeTallyText(@"spaces asked"), PFBProbeTallyText(@"spaces made"), gProbeHomeSpaces ?: @"Home not shown"];
    return text;
}

static void PFBProbePersist(NSString* moment) {
    if (gProbeStart <= 0) {
        return;
    }
    NSString* stamp = [NSString stringWithFormat:@"launch %@, %@", gProbeLaunchClock, moment];
    NSArray<NSString*>* lines = @[
        [NSString stringWithFormat:@"%@: %@", stamp, PFBProbeSettingsText()],
        [NSString stringWithFormat:@"%@: bar %@", stamp,
                                   [[PFBProbeBarText() componentsSeparatedByString:@"\n"] componentsJoinedByString:@" ·"]],
        [NSString stringWithFormat:@"%@: glyph writes: images %@ · tints %@ · filters %@", stamp,
                                   PFBProbeTallyText(@"bar image"), PFBProbeTallyText(@"bar tint"),
                                   PFBProbeTallyText(@"bar filters")],
        [NSString stringWithFormat:@"%@: stacks %@ · pans %@ · scroll windows %lu, shrank in %lu · last %@", stamp,
                                   gProbeStacks.count ? [gProbeStacks componentsJoinedByString:@" | "] : @"none",
                                   PFBProbeTallyText(@"scroll pan"), (unsigned long)gProbeScrollWindows,
                                   (unsigned long)gProbeCollapsedWindows, gProbeScrollTexts.lastObject ?: @"none"],
        [NSString stringWithFormat:@"%@: %@ · entries excluded %@ · side menu only %@", stamp,
                                   PFBProbeCustomNavigationText(), PFBProbeTallyText(@"entry excluded from the tab bar"),
                                   PFBProbeTallyText(@"entry side menu only")],
        [NSString stringWithFormat:@"%@: compose %@ · images %@ · alpha %@ · hidden %@ · Spaces asked %@, made %@, on Home %@",
                                   stamp, PFBProbeComposeText(), PFBProbeTallyText(@"compose image"),
                                   PFBProbeTallyText(@"compose alpha"), PFBProbeTallyText(@"compose hidden"),
                                   PFBProbeTallyText(@"spaces asked"), PFBProbeTallyText(@"spaces made"),
                                   gProbeHomeSpaces ?: @"not shown"],
    ];
    for (NSString* line in lines) {
        PFBCompatMeasure(kPFBProbeTopic, line, 60);
    }
}

// MARK: - Leaving the screen

// The pasteboard's count when Twitter came to the front: any other count when it leaves
// means something was copied meanwhile, and that copy is left alone.
static NSInteger gProbeBoardCount;

static void PFBProbeLeave(void) {
    @try {
        PFBProbePersist([NSString stringWithFormat:@"leaving at %.0f s", CACurrentMediaTime() - gProbeStart]);
        UIPasteboard* board = UIPasteboard.generalPasteboard;
        if (!gProbeBar || board.changeCount != gProbeBoardCount) {
            return;
        }
        board.string = [NSString stringWithFormat:@"%@\n\n%@", PFBProbeText(), PFBCompatReportText()];
        gProbeBoardCount = board.changeCount;
    } @catch (id exception) {
        PFBCompatMeasure(kPFBProbeTopic, [NSString stringWithFormat:@"report stopped: %@", exception], 60);
    }
}

static void PFBProbeStart(void) {
    NSDateFormatter* clock = [[NSDateFormatter alloc] init];
    clock.dateFormat = @"HH:mm:ss";
    gProbeLaunchClock = [clock stringFromDate:[NSDate date]];
    gProbeItemClass = NSClassFromString(@"_TtC11XNavigation14TabBarItemView");
    gProbeBoardCount = UIPasteboard.generalPasteboard.changeCount;

    NSNotificationCenter* center = NSNotificationCenter.defaultCenter;
    [center addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil
                         queue:NSOperationQueue.mainQueue
                    usingBlock:^(__unused NSNotification* note) {
                      gProbeBoardCount = UIPasteboard.generalPasteboard.changeCount;
                    }];
    [center addObserverForName:UIApplicationWillResignActiveNotification
                        object:nil
                         queue:NSOperationQueue.mainQueue
                    usingBlock:^(__unused NSNotification* note) {
                      PFBProbeLeave();
                    }];
    for (NSNumber* moment in @[ @25, @60 ]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(moment.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
                         @try {
                             PFBProbePersist([NSString stringWithFormat:@"at %@ s", moment]);
                         } @catch (id exception) {
                             PFBCompatMeasure(kPFBProbeTopic, [NSString stringWithFormat:@"stopped: %@", exception], 60);
                         }
                       });
    }
}

// MARK: - Hooks

// What Twitter loads and builds while it launches: installed at once.
%group PFBGlassProbeEarly

%hook _TtC14T1TwitterSwift20XTabbedAppNavigation

- (void)setCurrentPanel:(long long)panel animated:(BOOL)animated completion:(id)completion {
    %orig;
    if (pthread_main_np()) {
        PFBProbeSnapshotSoon([NSString stringWithFormat:@"after panel %lld", panel], 0.8);
    }
}

%end

// MARK: Icons by name

%hook UIImage

+ (UIImage*)imageNamed:(NSString*)name inBundle:(NSBundle*)bundle compatibleWithTraitCollection:(UITraitCollection*)traits {
    UIImage* image = %orig;
    PFBProbeTagIcon(image, name, bundle, __builtin_return_address(0));
    return image;
}

+ (UIImage*)imageNamed:(NSString*)name inBundle:(NSBundle*)bundle withConfiguration:(UIImageConfiguration*)configuration {
    UIImage* image = %orig;
    PFBProbeTagIcon(image, name, bundle, __builtin_return_address(0));
    return image;
}

- (UIImage*)imageWithRenderingMode:(UIImageRenderingMode)mode {
    UIImage* image = %orig;
    PFBProbeCarryIcon(self, image);
    return image;
}

- (UIImage*)imageWithTintColor:(UIColor*)color {
    UIImage* image = %orig;
    PFBProbeCarryIcon(self, image);
    return image;
}

- (UIImage*)imageWithTintColor:(UIColor*)color renderingMode:(UIImageRenderingMode)mode {
    UIImage* image = %orig;
    PFBProbeCarryIcon(self, image);
    return image;
}

- (UIImage*)imageWithConfiguration:(UIImageConfiguration*)configuration {
    UIImage* image = %orig;
    PFBProbeCarryIcon(self, image);
    return image;
}

%end

// MARK: Shrinking on scroll

%hook XNAVNavigationController

- (id)initWithRootViewController:(UIViewController*)root
            popGestureCapability:(long long)capability
            defaultConfiguration:(id)configuration {
    id controller = %orig;
    if (pthread_main_np()) {
        PFBProbeNoteStack(root, capability, configuration);
    }
    return controller;
}

- (id)initWithPopGestureCapability:(long long)capability defaultConfiguration:(id)configuration {
    id controller = %orig;
    if (pthread_main_np()) {
        PFBProbeNoteStack(nil, capability, configuration);
    }
    return controller;
}

%end

%hook XNAVConfiguration

+ (id)standardConfiguration {
    if (!gProbeBuildingReferences) {
        PFBProbeCount(@"config standard", __builtin_return_address(0), nil);
    }
    return %orig;
}

+ (id)pinnedConfiguration {
    if (!gProbeBuildingReferences) {
        PFBProbeCount(@"config pinned", __builtin_return_address(0), nil);
    }
    return %orig;
}

+ (id)hiddenConfiguration {
    if (!gProbeBuildingReferences) {
        PFBProbeCount(@"config hidden", __builtin_return_address(0), nil);
    }
    return %orig;
}

+ (id)pinnedTransparentConfiguration {
    if (!gProbeBuildingReferences) {
        PFBProbeCount(@"config pinned transparent", __builtin_return_address(0), nil);
    }
    return %orig;
}

+ (id)configurationWithCollapseMode:(long long)collapse popGestureMode:(long long)pop {
    PFBProbeCount(@"config by mode", __builtin_return_address(0),
                  [NSString stringWithFormat:@"collapse %lld pop %lld", collapse, pop]);
    return %orig;
}

+ (id)configurationWithCollapseMode:(long long)collapse popGestureMode:(long long)pop solidBackgroundColor:(UIColor*)color {
    PFBProbeCount(@"config by mode", __builtin_return_address(0),
                  [NSString stringWithFormat:@"collapse %lld pop %lld with color", collapse, pop]);
    return %orig;
}

%end

%hook _TtCC11XNavigation14CollapseEngine14ScrollObserver

- (void)handlePan:(UIGestureRecognizer*)recognizer {
    %orig;
    if (pthread_main_np() && gProbeStart > 0) {
        PFBProbeCount(@"scroll pan", NULL, nil);
        PFBProbeNotePan();
    }
}

%end

// MARK: The Spaces bar

%hook T1FleetLineHeaderController

- (BOOL)_t1_shouldShowFleetLine {
    BOOL show = %orig;
    PFBProbeCount(@"spaces asked", __builtin_return_address(0), show ? @"show" : @"hide");
    return show;
}

%end

%hook T1FleetLineView

- (id)initWithAccount:(id)account delegate:(id)delegate {
    id view = %orig;
    PFBProbeCount(@"spaces made", __builtin_return_address(0), nil);
    return view;
}

%end

%end

// Methods other files hook as well: installed last, so each call is charged to its sender.
%group PFBGlassProbe

// MARK: Twitter's glass bar and its compose button

%hook _TtC11XNavigation10TabBarView

- (void)layoutSubviews {
    %orig;
    UIView* bar = (UIView*)self;
    if (gProbeBar != bar && PFBProbeOnScreen(bar)) {
        BOOL first = gProbeBar == nil;
        gProbeBar = bar;
        if (first) {
            PFBProbeSnapshotSoon(@"after launch", 2.0);
        }
    }
    PFBProbeCount(@"bar layout", NULL, nil);
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
    PFBProbeCount(@"compose layout", NULL, nil);
}

%end

// MARK: Writes on the glyphs

%hook CALayer

- (void)setFilters:(NSArray*)filters {
    %orig;
    UIView* bar = gProbeBar;
    if (bar && gProbeStart > 0 && pthread_main_np() && PFBProbeLayerIn(self, bar)) {
        PFBProbeCount(@"bar filters", __builtin_return_address(0),
                      [NSString stringWithFormat:@"%@ [%@]", PFBProbeLayerOwner(self), PFBProbeFiltersText(self)]);
    }
}

- (void)setCompositingFilter:(id)filter {
    %orig;
    UIView* bar = gProbeBar;
    if (bar && gProbeStart > 0 && pthread_main_np() && PFBProbeLayerIn(self, bar)) {
        PFBProbeCount(@"bar compositing", __builtin_return_address(0),
                      [NSString stringWithFormat:@"%@ %@", PFBProbeLayerOwner(self), filter ? [filter description] : @"none"]);
    }
}

%end

%hook UIView

- (void)setTintColor:(UIColor*)color {
    %orig;
    UIView* bar = gProbeBar;
    if (bar && pthread_main_np() && [self isKindOfClass:[UIImageView class]] && PFBProbeViewIn(self, bar)) {
        PFBProbeCount(@"bar tint", __builtin_return_address(0), PFBProbeColorText(color));
    }
}

- (void)setAlpha:(CGFloat)alpha {
    %orig;
    UIView* accessory = gProbeAccessory;
    if (accessory && pthread_main_np() && PFBProbeViewIn(self, accessory)) {
        PFBProbeCount(@"compose alpha", __builtin_return_address(0), [NSString stringWithFormat:@"%.2f", alpha]);
    }
}

- (void)setHidden:(BOOL)hidden {
    %orig;
    UIView* accessory = gProbeAccessory;
    if (accessory && pthread_main_np() && PFBProbeViewIn(self, accessory)) {
        PFBProbeCount(@"compose hidden", __builtin_return_address(0), hidden ? @"yes" : @"no");
    }
}

%end

%hook UIImageView

- (void)setImage:(UIImage*)image {
    %orig;
    if (!pthread_main_np() || gProbeStart <= 0) {
        return;
    }
    UIView* bar = gProbeBar;
    UIView* accessory = gProbeAccessory;
    if (bar && PFBProbeViewIn(self, bar)) {
        PFBProbeCount(@"bar image", __builtin_return_address(0), PFBProbeImageText(image));
    } else if (accessory && PFBProbeViewIn(self, accessory)) {
        PFBProbeCount(@"compose image", __builtin_return_address(0), PFBProbeImageText(image));
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
    if (!gProbeScreens[name] && gProbeScreens.count < 16) {
        @try {
            gProbeScreens[name] = PFBProbeDeclarationText(controller);
        } @catch (id exception) {
            gProbeScreens[name] = [NSString stringWithFormat:@"unreadable (%@)", exception];
        }
    }
    if (!gProbeHomeSpaces && [name containsString:@"HomeTimelineContainer"]) {
        __weak UIViewController* weakHome = controller;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
          UIViewController* home = weakHome;
          if (home.viewIfLoaded.window) {
              gProbeHomeSpaces = PFBProbeSpacesText(home);
          }
        });
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
    PFBProbeWatchEntries();
    %init(PFBGlassProbeEarly);
    dispatch_async(dispatch_get_main_queue(), ^{
      PFBProbeStart();
      %init(PFBGlassProbe);
    });
}
