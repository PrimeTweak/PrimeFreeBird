// Probe for Notifications search: where each notification keeps its words and where the strip
// under the title sits. Removed once read; its lines go to the stethoscope report under the topic
// "probe notifications search".

#import "Support/HookHelpers.h"
#import <malloc/malloc.h>
#import <objc/message.h>
#import <objc/runtime.h>

static NSString* const kPFBSearchProbeTopic = @"probe notifications search";
static const NSUInteger kPFBSearchProbeMaxLists = 2;
static const NSUInteger kPFBSearchProbeMaxCells = 3;
static const NSUInteger kPFBSearchProbeMaxScreens = 2;

static NSUInteger gPFBSearchProbeLists;
static NSUInteger gPFBSearchProbeScreens;
static NSHashTable* gPFBSearchProbeCells;

static void PFBSearchProbeLine(NSString* line) {
    PFBCompatMeasure(kPFBSearchProbeTopic, line, 60);
}

// A Swift class name without its module prefix.
static NSString* PFBSearchProbeName(id object) {
    if (!object) {
        return @"nil";
    }
    NSString* name = NSStringFromClass([object class]);
    NSScanner* scanner = [NSScanner scannerWithString:name];
    if (![scanner scanString:@"_TtC" intoString:NULL]) {
        return name;
    }
    NSInteger length = 0;
    NSString* last = name;
    while ([scanner scanInteger:&length] && length > 0 && scanner.scanLocation + (NSUInteger)length <= name.length) {
        last = [name substringWithRange:NSMakeRange(scanner.scanLocation, (NSUInteger)length)];
        scanner.scanLocation += (NSUInteger)length;
    }
    return last;
}

static NSString* PFBSearchProbeClip(id value, NSUInteger length) {
    NSString* text = [value isKindOfClass:[NSAttributedString class]] ? [(NSAttributedString*)value string]
                     : [value isKindOfClass:[NSString class]]         ? value
                                                                      : nil;
    if (!text) {
        return value ? [NSString stringWithFormat:@"<%@>", PFBSearchProbeName(value)] : @"nil";
    }
    text = [[text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] componentsJoinedByString:@" / "];
    return [NSString stringWithFormat:@"\"%@\"", text.length > length ? [[text substringToIndex:length] stringByAppendingString:@"…"] : text];
}

// An ivar is read only when it is pointer-sized and points into the heap, so a Swift value stored
// inline is never taken for an object.
static id PFBSearchProbeIvar(id object, const char* name) {
    if (!object) {
        return nil;
    }
    for (Class cls = object_getClass(object); cls; cls = class_getSuperclass(cls)) {
        unsigned int count = 0;
        Ivar* list = class_copyIvarList(cls, &count);
        Ivar found = NULL;
        for (unsigned int i = 0; i < count; i++) {
            if (strcmp(ivar_getName(list[i]) ?: "", name) == 0) {
                found = list[i];
            }
        }
        if (!found) {
            free(list);
            continue;
        }
        ptrdiff_t offset = ivar_getOffset(found);
        ptrdiff_t next = (ptrdiff_t)class_getInstanceSize(cls);
        for (unsigned int i = 0; i < count; i++) {
            ptrdiff_t other = ivar_getOffset(list[i]);
            if (other > offset && other < next) {
                next = other;
            }
        }
        free(list);
        if (next - offset != (ptrdiff_t)sizeof(void*)) {
            return nil;
        }
        void* raw = *(void**)((uint8_t*)(__bridge void*)object + offset);
        if (!raw || ((uintptr_t)raw >> 63) || !malloc_zone_from_ptr(raw)) {
            return nil;
        }
        return (__bridge id)raw;
    }
    return nil;
}

static id PFBSearchProbeSend(id receiver, NSString* selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    return [receiver respondsToSelector:selector] ? ((id (*)(id, SEL))objc_msgSend)(receiver, selector) : nil;
}

// The words a notification row carries, from every place they could be read.
static NSString* PFBSearchProbeRow(id model) {
    NSMutableArray<NSString*>* parts = [NSMutableArray array];
    [parts addObject:[NSString stringWithFormat:@"description %@", PFBSearchProbeClip([model description], 400)]];
    id notification = PFBSearchProbeIvar(model, "notification");
    if (notification) {
        id richText = PFBSearchProbeIvar(notification, "richText");
        [parts addObject:[NSString stringWithFormat:@"notification %@ richText %@ text %@ entities %lu",
                                                    PFBSearchProbeName(notification), PFBSearchProbeName(richText),
                                                    PFBSearchProbeClip(PFBSearchProbeSend(richText, @"text"), 120),
                                                    (unsigned long)[PFBSearchProbeSend(richText, @"entities") count]]];
    }
    id status = PFBSearchProbeIvar(model, "status");
    if (status) {
        NSMutableArray<NSString*>* fields = [NSMutableArray array];
        for (NSString* name in @[ @"text", @"fullText", @"displayText", @"fromUserName", @"fromUserScreenName",
                                  @"fromUserFullName", @"representedFromUserName", @"representedFromUserScreenName" ]) {
            if ([status respondsToSelector:NSSelectorFromString(name)]) {
                [fields addObject:[NSString stringWithFormat:@"%@=%@", name, PFBSearchProbeClip(PFBSearchProbeSend(status, name), 80)]];
            }
        }
        [parts addObject:[NSString stringWithFormat:@"status %@ %@", PFBSearchProbeName(status),
                                                    fields.count ? [fields componentsJoinedByString:@" "] : @"no text getter"]];
    }
    static const char* const lists[] = {"fromUsers", "richTextUsers", "targetStatuses", "targetUsers"};
    for (size_t i = 0; i < sizeof(lists) / sizeof(lists[0]); i++) {
        id value = PFBSearchProbeIvar(model, lists[i]);
        if (value) {
            [parts addObject:[NSString stringWithFormat:@"%s %@", lists[i], PFBSearchProbeName(value)]];
        }
    }
    return [parts componentsJoinedByString:@"; "];
}

// The list as Twitter hands it over, before hidden rows are taken out.
static void PFBSearchProbeList(NSArray* sections, NSString* entry) {
    if (gPFBSearchProbeLists >= kPFBSearchProbeMaxLists || ![sections isKindOfClass:[NSArray class]]) {
        return;
    }
    NSMutableDictionary<NSString*, NSNumber*>* counts = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString*, NSMutableArray*>* samples = [NSMutableDictionary dictionary];
    BOOL notifications = NO;
    for (id section in sections) {
        id items = PFBSearchProbeSend(section, @"items");
        if (![items isKindOfClass:[NSArray class]]) {
            continue;
        }
        for (id item in (NSArray*)items) {
            id model = PFBUnwrapDataViewItem(item) ?: item;
            NSString* name = PFBSearchProbeName(model);
            notifications = notifications || [name containsString:@"Notification"];
            counts[name] = @(counts[name].integerValue + 1);
            NSMutableArray* kept = samples[name] ?: (samples[name] = [NSMutableArray array]);
            if (kept.count < 2) {
                [kept addObject:model];
            }
        }
    }
    if (!notifications) {
        return;
    }
    gPFBSearchProbeLists++;
    PFBSearchProbeLine([NSString stringWithFormat:@"list %lu (%@): %lu sections, rows %@", (unsigned long)gPFBSearchProbeLists,
                                                  entry, (unsigned long)sections.count, counts]);
    for (NSString* name in samples) {
        for (id model in samples[name]) {
            PFBSearchProbeLine([NSString stringWithFormat:@"row %@: %@", name, PFBSearchProbeRow(model)]);
        }
    }
}

// One view: class, frame on screen, and whether it shows.
static NSString* PFBSearchProbeView(UIView* view) {
    if (!view) {
        return @"none";
    }
    CGRect frame = [view convertRect:view.bounds toView:nil];
    return [NSString stringWithFormat:@"%@ %.1f,%.1f %.1fx%.1f%@%@", PFBSearchProbeName(view), frame.origin.x, frame.origin.y,
                                      frame.size.width, frame.size.height, view.hidden || view.alpha < 0.01 ? @" hidden" : @"",
                                      view.window ? @"" : @" off screen"];
}

static void PFBSearchProbeWalk(UIView* view, NSUInteger depth, NSUInteger maxDepth, NSMutableArray<NSString*>* parts) {
    if (!view || parts.count >= 24) {
        return;
    }
    [parts addObject:[NSString stringWithFormat:@"%lu:%@", (unsigned long)depth, PFBSearchProbeView(view)]];
    if (depth < maxDepth) {
        for (UIView* sub in view.subviews) {
            PFBSearchProbeWalk(sub, depth + 1, maxDepth, parts);
        }
    }
}

static NSString* PFBSearchProbeTree(UIView* root, NSUInteger maxDepth) {
    NSMutableArray<NSString*>* parts = [NSMutableArray array];
    PFBSearchProbeWalk(root, 0, maxDepth, parts);
    return parts.count ? [parts componentsJoinedByString:@"; "] : @"none";
}

static UITableView* PFBSearchProbeTable(UIView* root) {
    if ([root isKindOfClass:[UITableView class]] && root.window && !root.hidden) {
        return (UITableView*)root;
    }
    for (UIView* sub in root.subviews) {
        UITableView* found = PFBSearchProbeTable(sub);
        if (found) {
            return found;
        }
    }
    return nil;
}

static CGFloat PFBSearchProbeFloat(id receiver, NSString* selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    return [receiver respondsToSelector:selector] ? ((CGFloat (*)(id, SEL))objc_msgSend)(receiver, selector) : -1;
}

// The strip under the title, the segmented screen that owns it, and the list below them.
static void PFBSearchProbeScreen(UIViewController* screen) {
    if (gPFBSearchProbeScreens >= kPFBSearchProbeMaxScreens || !screen.viewIfLoaded.window) {
        return;
    }
    gPFBSearchProbeScreens++;
    UINavigationBar* bar = screen.navigationController.navigationBar;
    PFBSearchProbeLine([NSString stringWithFormat:@"screen %lu (%@, unified %d): view %@ safe top %.1f; bar %@",
                                                  (unsigned long)gPFBSearchProbeScreens,
                                                  [PFBSettings boolForKey:@"enable_liquid_glass"] ? @"Liquid Glass" : @"Standard",
                                                  [PFBSettings boolForKey:@"activity_tab"], PFBSearchProbeView(screen.view),
                                                  screen.view.safeAreaInsets.top, PFBSearchProbeView(bar)]);
    UIView* accessory = PFBSearchProbeSend(screen, @"tfn_navigationBarAccessoryView");
    PFBSearchProbeLine([NSString stringWithFormat:@"accessory: %@", PFBSearchProbeTree(accessory, 3)]);
    UIView* stack = PFBSearchProbeIvar(screen, "$__lazy_storage_$_navigationAccessoryStackView");
    NSMutableArray<NSString*>* arranged = [NSMutableArray array];
    if ([stack isKindOfClass:[UIStackView class]]) {
        for (UIView* view in ((UIStackView*)stack).arrangedSubviews) {
            [arranged addObject:PFBSearchProbeView(view)];
        }
    }
    PFBSearchProbeLine([NSString stringWithFormat:@"accessory stack: %@; superview %@; arranged %@", PFBSearchProbeView(stack),
                                                  PFBSearchProbeName(stack.superview),
                                                  arranged.count ? [arranged componentsJoinedByString:@", "] : @"none"]);
    id segmented = PFBSearchProbeIvar(screen, "$__lazy_storage_$_segmentedController");
    UIView* tabBar = PFBSearchProbeSend(segmented, @"tabBarView");
    NSMutableArray<NSString*>* chain = [NSMutableArray array];
    for (UIView* step = tabBar.superview; step && chain.count < 4; step = step.superview) {
        [chain addObject:PFBSearchProbeView(step)];
    }
    SEL hideMode = NSSelectorFromString(@"tabBarHideMode");
    PFBSearchProbeLine([NSString stringWithFormat:@"segmented %@ view %@; tab bar %@ in %@; hide mode %ld; bar height %.1f max %.1f",
                                                  PFBSearchProbeName(segmented),
                                                  PFBSearchProbeView([segmented isKindOfClass:[UIViewController class]]
                                                                         ? [(UIViewController*)segmented viewIfLoaded]
                                                                         : nil),
                                                  PFBSearchProbeView(tabBar),
                                                  chain.count ? [chain componentsJoinedByString:@" < "] : @"none",
                                                  [segmented respondsToSelector:hideMode]
                                                      ? (long)((NSInteger (*)(id, SEL))objc_msgSend)(segmented, hideMode)
                                                      : -1L,
                                                  PFBSearchProbeFloat(segmented, @"barHeight"),
                                                  PFBSearchProbeFloat(segmented, @"maximumBarHeight")]);
    UITableView* table = PFBSearchProbeTable(screen.view);
    PFBSearchProbeLine([NSString stringWithFormat:@"list %@: inset top %.1f adjusted %.1f offset %.1f header %@; source %@",
                                                  PFBSearchProbeView(table), table.contentInset.top,
                                                  table.adjustedContentInset.top, table.contentOffset.y,
                                                  PFBSearchProbeView(table.tableHeaderView), PFBSearchProbeName(table.dataSource)]);
    PFBSearchProbeLine([NSString stringWithFormat:@"screen tree: %@", PFBSearchProbeTree(screen.view, 3)]);
}

// The words a shown notification cell holds: its spoken label and its view model's texts.
static void PFBSearchProbeCell(UITableViewCell* cell) {
    gPFBSearchProbeCells = gPFBSearchProbeCells ?: [NSHashTable weakObjectsHashTable];
    if (gPFBSearchProbeCells.count >= kPFBSearchProbeMaxCells || [gPFBSearchProbeCells containsObject:cell]) {
        return;
    }
    [gPFBSearchProbeCells addObject:cell];
    id viewModel = PFBSearchProbeIvar(cell, "viewModel");
    NSMutableArray<NSString*>* texts = [NSMutableArray array];
    static const char* const names[] = {"titleTextModel", "socialTextModel", "attributedSubTextModel"};
    for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); i++) {
        id model = PFBSearchProbeIvar(viewModel, names[i]);
        [texts addObject:[NSString stringWithFormat:@"%s %@", names[i],
                                                    PFBSearchProbeClip(PFBSearchProbeSend(model, @"attributedString"), 120)]];
    }
    PFBSearchProbeLine([NSString stringWithFormat:@"cell %lu: label %@; view model %@; %@", (unsigned long)gPFBSearchProbeCells.count,
                                                  PFBSearchProbeClip(cell.accessibilityLabel, 160), PFBSearchProbeName(viewModel),
                                                  [texts componentsJoinedByString:@"; "]]);
}

%hook T1NotificationsViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    __weak UIViewController* screen = (UIViewController*)self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      PFBSearchProbeScreen(screen);
    });
}

%end

%hook TFNItemsDataViewController

- (void)setSections:(NSArray*)sections {
    PFBSearchProbeList(sections, @"set");
    %orig;
}

- (void)setSections:(NSArray*)sections restoreScrollPosition:(BOOL)restore {
    PFBSearchProbeList(sections, @"set, scroll kept");
    %orig;
}

- (void)updateSections:(NSArray*)sections {
    PFBSearchProbeList(sections, @"update");
    %orig;
}

%end

%hook T1URTTimelineNotificationCell

- (void)layoutSubviews {
    %orig;
    PFBSearchProbeCell((UITableViewCell*)self);
}

%end
