// Probe for the Notifications tab row: what the row, its tabs, its underline and its pager are made
// of, and each tab change with the code that started it. Removed once read; its lines go to the
// stethoscope report under the topic "probe notifications tabs".

#import "Support/HookHelpers.h"
#import <QuartzCore/QuartzCore.h>
#import <dlfcn.h>
#import <objc/message.h>

static NSString* const kPFBNotifTabsTopic = @"probe notifications tabs";
static const NSUInteger kPFBNotifTabsMaxEvents = 16;
static const NSUInteger kPFBNotifTabsMaxDumps = 4;

static __weak UICollectionView* gPFBNotifTabsPager;
static NSUInteger gPFBNotifTabsEvents;
static NSUInteger gPFBNotifTabsDumps;

static void PFBNotifTabsLine(NSString* line) {
    PFBCompatMeasure(kPFBNotifTabsTopic, line, 40);
}

// A Swift class name without its module prefix.
static NSString* PFBNotifTabsName(id object) {
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

// The first callers outside this tweak and the hooking library, as image+offset.
static NSString* PFBNotifTabsCallers(NSUInteger wanted) {
    Dl_info own;
    dladdr((const void*)&PFBNotifTabsCallers, &own);
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

static BOOL PFBNotifTabsOwned(UIViewController* controller) {
    Class container = NSClassFromString(@"_TtC14T1TwitterSwift36NotificationsContainerViewController");
    for (UIViewController* step = controller; step && container; step = step.parentViewController) {
        if ([step isKindOfClass:container]) {
            return YES;
        }
    }
    return NO;
}

static UIViewController* PFBNotifTabsContainer(UIViewController* controller) {
    Class container = NSClassFromString(@"_TtC14T1TwitterSwift36NotificationsContainerViewController");
    for (UIViewController* step = controller; step; step = step.parentViewController) {
        if ([step isKindOfClass:container]) {
            return step;
        }
    }
    return nil;
}

static NSString* PFBNotifTabsColor(UIColor* color) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) {
        return @"?";
    }
    return [NSString stringWithFormat:@"#%02X%02X%02X/%.2f", (int)lround(r * 255), (int)lround(g * 255), (int)lround(b * 255), a];
}

// One view: class, frame on screen, and what matters for its kind.
static NSString* PFBNotifTabsDescribe(UIView* view) {
    CGRect frame = [view convertRect:view.bounds toView:nil];
    NSMutableString* text = [NSMutableString stringWithFormat:@"%@ %.1f,%.1f %.1fx%.1f", PFBNotifTabsName(view),
                                                              frame.origin.x, frame.origin.y, frame.size.width, frame.size.height];
    if (view.hidden || view.alpha < 0.01) {
        [text appendString:@" hidden"];
    }
    if ([view isKindOfClass:[UILabel class]]) {
        UILabel* label = (UILabel*)view;
        [text appendFormat:@" \"%@\" %@ %.1f %@", label.text ?: @"", label.font.fontName, label.font.pointSize,
                           PFBNotifTabsColor(label.textColor)];
    } else if ([view isKindOfClass:[UIImageView class]]) {
        UIImage* image = ((UIImageView*)view).image;
        [text appendFormat:@" image %.0fx%.0f tint %@", image.size.width, image.size.height, PFBNotifTabsColor(view.tintColor)];
    } else if ([view isKindOfClass:[UICollectionView class]]) {
        UICollectionView* collection = (UICollectionView*)view;
        NSInteger items = collection.numberOfSections ? [collection numberOfItemsInSection:0] : 0;
        [text appendFormat:@" items %ld paging %d offset %.1f content %.1f layout %@ source %@ delegate %@", (long)items,
                           collection.pagingEnabled, collection.contentOffset.x, collection.contentSize.width,
                           PFBNotifTabsName(collection.collectionViewLayout), PFBNotifTabsName(collection.dataSource),
                           PFBNotifTabsName(collection.delegate)];
    } else if (view.backgroundColor && CGRectGetHeight(frame) <= 6) {
        [text appendFormat:@" fill %@", PFBNotifTabsColor(view.backgroundColor)];
    }
    return text;
}

static void PFBNotifTabsWalk(UIView* view, NSUInteger depth, NSUInteger maxDepth, NSUInteger maxViews,
                             NSMutableArray<NSString*>* parts) {
    if (parts.count >= maxViews) {
        return;
    }
    [parts addObject:[NSString stringWithFormat:@"%lu:%@", (unsigned long)depth, PFBNotifTabsDescribe(view)]];
    if (depth < maxDepth) {
        for (UIView* sub in view.subviews) {
            PFBNotifTabsWalk(sub, depth + 1, maxDepth, maxViews, parts);
        }
    }
}

// Every view under a root, depth first, up to a depth and a count.
static NSString* PFBNotifTabsTree(UIView* root, NSUInteger maxDepth, NSUInteger maxViews) {
    NSMutableArray<NSString*>* parts = [NSMutableArray array];
    PFBNotifTabsWalk(root, 0, maxDepth, maxViews, parts);
    return [parts componentsJoinedByString:@"; "];
}

// The first view under a root whose class name holds one of the words.
static UIView* PFBNotifTabsFind(UIView* root, NSArray<NSString*>* words, BOOL (^extra)(UIView*)) {
    if (!root) {
        return nil;
    }
    NSString* name = NSStringFromClass([root class]);
    for (NSString* word in words) {
        if ([name containsString:word] && (!extra || extra(root))) {
            return root;
        }
    }
    for (UIView* sub in root.subviews) {
        UIView* found = PFBNotifTabsFind(sub, words, extra);
        if (found) {
            return found;
        }
    }
    return nil;
}

static UICollectionView* PFBNotifTabsFindPager(UIView* root) {
    if (!root) {
        return nil;
    }
    if ([root isKindOfClass:[UICollectionView class]] && ((UICollectionView*)root).pagingEnabled) {
        return (UICollectionView*)root;
    }
    for (UIView* sub in root.subviews) {
        UICollectionView* found = PFBNotifTabsFindPager(sub);
        if (found) {
            return found;
        }
    }
    return nil;
}

static id PFBNotifTabsSend(id receiver, NSString* selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    return [receiver respondsToSelector:selector] ? ((id (*)(id, SEL))objc_msgSend)(receiver, selector) : nil;
}

// The row, the pager and the screens around them, as they stand.
static void PFBNotifTabsDump(UIViewController* chrome, NSString* moment) {
    if (gPFBNotifTabsDumps >= kPFBNotifTabsMaxDumps || !chrome.viewIfLoaded.window) {
        return;
    }
    gPFBNotifTabsDumps++;
    UIViewController* container = PFBNotifTabsContainer(chrome);
    NSString* look = [PFBSettings boolForKey:@"enable_liquid_glass"] ? @"Liquid Glass" : @"Standard";

    NSMutableArray<NSString*>* owners = [NSMutableArray array];
    for (UIViewController* step = chrome; step; step = step.parentViewController) {
        [owners addObject:PFBNotifTabsName(step)];
    }
    NSMutableArray* owned = [NSMutableArray array];
    SEL ownedSelector = NSSelectorFromString(@"tfn_addDirectlyOwnedViewControllersToMutableArray:");
    if ([chrome respondsToSelector:ownedSelector]) {
        ((void (*)(id, SEL, id))objc_msgSend)(chrome, ownedSelector, owned);
    }
    NSMutableArray<NSString*>* ownedNames = [NSMutableArray array];
    for (id child in owned) {
        [ownedNames addObject:PFBNotifTabsName(child)];
    }
    PFBNotifTabsLine([NSString stringWithFormat:@"%@ (%@): screens %@; owned %@; children %lu", moment, look,
                                                [owners componentsJoinedByString:@" in "],
                                                ownedNames.count ? [ownedNames componentsJoinedByString:@", "] : @"none",
                                                (unsigned long)chrome.childViewControllers.count]);

    UIView* chromeAccessory = PFBNotifTabsSend(chrome, @"tfn_navigationBarAccessoryView");
    UIView* containerAccessory = PFBNotifTabsSend(container, @"tfn_navigationBarAccessoryView");
    NSArray<NSString*>* barWords = @[ @"SegmentedTabBar", @"SegmentedControl", @"TabBarView", @"PillBar", @"SegmentBar" ];
    BOOL (^notTabBar)(UIView*) = ^BOOL(UIView* view) {
      return ![view isKindOfClass:[UITabBar class]];
    };
    UIView* bar = nil;
    NSString* where = @"none";
    if (chromeAccessory) {
        bar = chromeAccessory;
        where = @"accessory of the tab screen";
    } else if (containerAccessory) {
        bar = containerAccessory;
        where = @"accessory of Notifications";
    } else if ((bar = PFBNotifTabsFind(container.viewIfLoaded ?: chrome.view, barWords, notTabBar))) {
        where = @"inside Notifications' view";
    } else if ((bar = PFBNotifTabsFind(chrome.navigationController.navigationBar, barWords, notTabBar))) {
        where = @"inside the navigation bar";
    }
    PFBNotifTabsLine([NSString stringWithFormat:@"%@ row (%@): %@", moment, where,
                                                bar ? PFBNotifTabsTree(bar, 8, 45) : @"not found"]);
    if (bar && !bar.window) {
        UIView* shown = PFBNotifTabsFind(container.viewIfLoaded ?: chrome.view, barWords, notTabBar)
                            ?: PFBNotifTabsFind(chrome.navigationController.navigationBar, barWords, notTabBar);
        PFBNotifTabsLine([NSString stringWithFormat:@"%@ row on screen: %@", moment,
                                                    shown ? PFBNotifTabsTree(shown, 8, 45) : @"not found"]);
    }

    UICollectionView* pager = PFBNotifTabsFindPager(container.viewIfLoaded ?: chrome.view);
    if (pager) {
        gPFBNotifTabsPager = pager;
    }
    PFBNotifTabsLine([NSString stringWithFormat:@"%@ pager: %@; its screens %@", moment,
                                                pager ? PFBNotifTabsDescribe(pager) : @"not found",
                                                pager ? PFBNotifTabsTree(pager, 2, 8) : @"-"]);
}

static void PFBNotifTabsEvent(NSString* event) {
    if (gPFBNotifTabsEvents >= kPFBNotifTabsMaxEvents) {
        return;
    }
    gPFBNotifTabsEvents++;
    UICollectionView* pager = gPFBNotifTabsPager;
    PFBNotifTabsLine([NSString stringWithFormat:@"event %@; pager offset %.1f; from %@", event,
                                                pager ? pager.contentOffset.x : -1.0, PFBNotifTabsCallers(5)]);
}

%hook _TtC14T1TwitterSwift23URTChromeViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    UIViewController* chrome = (UIViewController*)self;
    if (!PFBNotifTabsOwned(chrome)) {
        return;
    }
    PFBNotifTabsEvent(@"Notifications appears");
    __weak UIViewController* weakChrome = chrome;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      PFBNotifTabsDump(weakChrome, @"on arrival");
    });
}

- (void)genericViewControllerCollectionWithDidSelectContentViewController:(UIViewController*)controller
                                                                       at:(NSInteger)index
                                                             indexChanged:(BOOL)indexChanged {
    %orig;
    UIViewController* chrome = (UIViewController*)self;
    if (!PFBNotifTabsOwned(chrome)) {
        return;
    }
    PFBNotifTabsEvent([NSString stringWithFormat:@"tab %ld chosen (changed %d), page %@", (long)index, indexChanged,
                                                 PFBNotifTabsName(controller)]);
    if (indexChanged) {
        __weak UIViewController* weakChrome = chrome;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
          PFBNotifTabsDump(weakChrome, [NSString stringWithFormat:@"after tab %ld", (long)index]);
        });
    }
}

%end

%hook UICollectionView

- (void)scrollToItemAtIndexPath:(NSIndexPath*)indexPath
               atScrollPosition:(UICollectionViewScrollPosition)scrollPosition
                       animated:(BOOL)animated {
    if (self == gPFBNotifTabsPager) {
        PFBNotifTabsEvent([NSString stringWithFormat:@"pager sent to page %ld (animated %d)", (long)indexPath.item, animated]);
    }
    %orig;
}

%end

%hook UIScrollView

- (void)setContentOffset:(CGPoint)contentOffset animated:(BOOL)animated {
    if (self == (UIScrollView*)gPFBNotifTabsPager && fabs(contentOffset.x - self.contentOffset.x) > 1.0) {
        PFBNotifTabsEvent([NSString stringWithFormat:@"pager offset set to %.1f (animated %d)", contentOffset.x, animated]);
    }
    %orig;
}

%end
