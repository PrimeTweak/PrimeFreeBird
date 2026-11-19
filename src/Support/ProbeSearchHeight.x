// Probe for the search field's height: Chat's own field in detail, and which constraint sizes the
// room under Notifications' bar, each tried 16 pt taller then put back. Removed once read; its
// lines go to the stethoscope report under the topic "probe search height".

#import "Support/HookHelpers.h"
#import <malloc/malloc.h>
#import <objc/message.h>
#import <objc/runtime.h>

static NSString* const kPFBHeightProbeTopic = @"probe search height";
static NSUInteger gPFBHeightProbeChat;
static BOOL gPFBHeightProbeNotifications;

static void PFBHeightProbeLine(NSString* line) {
    PFBCompatMeasure(kPFBHeightProbeTopic, line, 90);
}

static NSString* PFBHeightProbeName(id object) {
    if (!object) {
        return @"nil";
    }
    NSString* name = NSStringFromClass([object class]);
    NSRange dot = [name rangeOfString:@"." options:NSBackwardsSearch];
    return dot.location == NSNotFound ? name : [name substringFromIndex:dot.location + 1];
}

// An ivar is read only when it is pointer-sized and points into the heap, so a Swift value stored
// inline is never taken for an object.
static id PFBHeightProbeIvar(id object, const char* name) {
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

static NSString* PFBHeightProbeView(UIView* view) {
    if (!view) {
        return @"none";
    }
    CGRect frame = [view convertRect:view.bounds toView:nil];
    return [NSString stringWithFormat:@"%@ %.1f,%.1f %.1fx%.1f%@%@", PFBHeightProbeName(view), frame.origin.x, frame.origin.y,
                                      frame.size.width, frame.size.height, view.hidden || view.alpha < 0.01 ? @" hidden" : @"",
                                      view.window ? @"" : @" off screen"];
}

static NSString* PFBHeightProbeChain(UIView* view, NSUInteger steps) {
    NSMutableArray<NSString*>* parts = [NSMutableArray array];
    for (UIView* step = view.superview; step && parts.count < steps; step = step.superview) {
        [parts addObject:PFBHeightProbeView(step)];
    }
    return parts.count ? [parts componentsJoinedByString:@" < "] : @"none";
}

static NSString* PFBHeightProbeColor(UIColor* color, UITraitCollection* traits) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (!color || ![[color resolvedColorWithTraitCollection:traits] getRed:&r green:&g blue:&b alpha:&a]) {
        return color ? @"unreadable" : @"nil";
    }
    return [NSString stringWithFormat:@"%.0f,%.0f,%.0f a%.2f", r * 255, g * 255, b * 255, a];
}

static NSString* PFBHeightProbeFont(UIFont* font) {
    return font ? [NSString stringWithFormat:@"%@ %.2f", font.fontName, font.pointSize] : @"nil";
}

static NSString* PFBHeightProbeConstraint(NSLayoutConstraint* c) {
    if (![c isKindOfClass:[NSLayoutConstraint class]]) {
        return @"none";
    }
    return [NSString stringWithFormat:@"%@.%ld %@ %@.%ld x%.2f %+.1f p%.0f%@%@", PFBHeightProbeName(c.firstItem), (long)c.firstAttribute,
                                      c.relation == NSLayoutRelationEqual ? @"=" : (c.relation < 0 ? @"<=" : @">="),
                                      PFBHeightProbeName(c.secondItem), (long)c.secondAttribute, c.multiplier, c.constant,
                                      c.priority, c.active ? @"" : @" inactive",
                                      c.identifier.length ? [NSString stringWithFormat:@" \"%@\"", c.identifier] : @""];
}

// The constraints that set a view's height or its top and bottom, wherever they are kept.
static NSArray<NSLayoutConstraint*>* PFBHeightProbeTouching(UIView* view) {
    NSMutableArray<NSLayoutConstraint*>* found = [NSMutableArray array];
    NSUInteger hops = 0;
    for (UIView* owner = view; owner && hops < 4; owner = owner.superview, hops++) {
        for (NSLayoutConstraint* c in owner.constraints) {
            BOOL mine = c.firstItem == view || c.secondItem == view;
            NSLayoutAttribute a = c.firstItem == view ? c.firstAttribute : c.secondAttribute;
            if (mine && (a == NSLayoutAttributeHeight || a == NSLayoutAttributeTop || a == NSLayoutAttributeBottom) &&
                ![found containsObject:c]) {
                [found addObject:c];
            }
        }
    }
    return found;
}

static NSString* PFBHeightProbeConstraints(UIView* view) {
    NSMutableArray<NSString*>* parts = [NSMutableArray array];
    for (NSLayoutConstraint* c in PFBHeightProbeTouching(view)) {
        [parts addObject:PFBHeightProbeConstraint(c)];
    }
    return parts.count ? [parts componentsJoinedByString:@"; "] : @"none";
}

static UIView* PFBHeightProbeFind(UIView* root, NSString* word, NSUInteger depth) {
    if ([NSStringFromClass([root class]) containsString:word]) {
        return root;
    }
    if (depth == 0) {
        return nil;
    }
    for (UIView* sub in root.subviews) {
        UIView* found = PFBHeightProbeFind(sub, word, depth - 1);
        if (found) {
            return found;
        }
    }
    return nil;
}

static UIView* PFBHeightProbeAncestor(UIView* view, NSString* word) {
    for (UIView* step = view.superview; step; step = step.superview) {
        if ([NSStringFromClass([step class]) containsString:word]) {
            return step;
        }
    }
    return nil;
}

static UIScrollView* PFBHeightProbeList(UIView* root) {
    if (([root isKindOfClass:[UITableView class]] || [root isKindOfClass:[UICollectionView class]]) && root.window && !root.hidden &&
        CGRectGetHeight(root.bounds) > 300) {
        return (UIScrollView*)root;
    }
    for (UIView* sub in root.subviews) {
        UIScrollView* found = PFBHeightProbeList(sub);
        if (found) {
            return found;
        }
    }
    return nil;
}

static void PFBHeightProbeImages(UIView* root, NSUInteger depth, NSMutableArray<NSString*>* parts) {
    if ([root isKindOfClass:[UIImageView class]] && ((UIImageView*)root).image) {
        CGSize size = ((UIImageView*)root).image.size;
        [parts addObject:[NSString stringWithFormat:@"%@ image %.1fx%.1f mode %ld", PFBHeightProbeView(root), size.width, size.height,
                                                    (long)root.contentMode]];
    }
    if (depth > 0) {
        for (UIView* sub in root.subviews) {
            PFBHeightProbeImages(sub, depth - 1, parts);
        }
    }
}

static NSString* PFBHeightProbeField(UIView* input, UITraitCollection* traits) {
    if (![input isKindOfClass:[UITextField class]]) {
        NSMutableArray<NSString*>* parts = [NSMutableArray array];
        for (UIView* sub in input.subviews) {
            [parts addObject:PFBHeightProbeView(sub)];
        }
        return [NSString stringWithFormat:@"not a text field; subviews %@", parts];
    }
    UITextField* field = (UITextField*)input;
    NSDictionary* placeholderStyle = field.attributedPlaceholder.length ? [field.attributedPlaceholder attributesAtIndex:0 effectiveRange:NULL] : nil;
    return [NSString stringWithFormat:@"placeholder \"%@\" font %@ grows with text size %d; text %@; placeholder %@ %@; "
                                      @"tint %@; left %@ mode %ld; clear %ld; align %ld",
                                      field.placeholder, PFBHeightProbeFont(field.font), field.adjustsFontForContentSizeCategory,
                                      PFBHeightProbeColor(field.textColor, traits), PFBHeightProbeFont(placeholderStyle[NSFontAttributeName]),
                                      PFBHeightProbeColor(placeholderStyle[NSForegroundColorAttributeName], traits),
                                      PFBHeightProbeColor(field.tintColor, traits), PFBHeightProbeView(field.leftView),
                                      (long)field.leftViewMode, (long)field.clearButtonMode, (long)field.textAlignment];
}

// Chat's field: its frames, its room under the bar, its capsule, its text field and glyph.
static void PFBHeightProbeChat(UIView* bar) {
    if (gPFBHeightProbeChat >= 2 || !bar.window) {
        return;
    }
    gPFBHeightProbeChat++;
    UITraitCollection* traits = bar.traitCollection;
    UIView* accessory = PFBHeightProbeAncestor(bar, @"InboxSearchBarAccessoryView");
    UIView* zone = PFBHeightProbeAncestor(bar, @"AccessoryStackView");
    UIResponder* responder = bar;
    while (responder && ![responder isKindOfClass:[UIViewController class]]) {
        responder = responder.nextResponder;
    }
    UIViewController* screen = (UIViewController*)responder;
    UIScrollView* list = PFBHeightProbeList(screen.view);
    PFBHeightProbeLine([NSString stringWithFormat:@"chat %lu: bar %@ fits %.1f; accessory %@ height %@; zone %@; chain %@",
                                                  (unsigned long)gPFBHeightProbeChat, PFBHeightProbeView(bar), bar.intrinsicContentSize.height,
                                                  PFBHeightProbeView(accessory),
                                                  PFBHeightProbeConstraint(PFBHeightProbeIvar(accessory, "heightConstraint")),
                                                  PFBHeightProbeView(zone), PFBHeightProbeChain(bar, 8)]);
    PFBHeightProbeLine([NSString stringWithFormat:@"chat %lu screen %@ safe top %.1f; list %@ inset %.1f adjusted %.1f; zone holds %@",
                                                  (unsigned long)gPFBHeightProbeChat, PFBHeightProbeName(screen), screen.view.safeAreaInsets.top,
                                                  PFBHeightProbeView(list), list.contentInset.top, list.adjustedContentInset.top,
                                                  PFBHeightProbeConstraints(accessory)]);
    UIView* capsule = PFBHeightProbeIvar(bar, "capsule");
    PFBHeightProbeLine([NSString stringWithFormat:@"chat %lu capsule %@ radius %.1f fill %@ curve %@", (unsigned long)gPFBHeightProbeChat,
                                                  PFBHeightProbeView(capsule), capsule.layer.cornerRadius,
                                                  PFBHeightProbeColor(capsule.backgroundColor, traits), capsule.layer.cornerCurve]);
    UIView* input = PFBHeightProbeIvar(bar, "input");
    PFBHeightProbeLine([NSString stringWithFormat:@"chat %lu input %@ (%@ < %@): %@", (unsigned long)gPFBHeightProbeChat,
                                                  PFBHeightProbeView(input), NSStringFromClass([input superclass]),
                                                  NSStringFromClass([[input superclass] superclass]), PFBHeightProbeField(input, traits)]);
    NSMutableArray<NSString*>* images = [NSMutableArray array];
    PFBHeightProbeImages(bar, 5, images);
    PFBHeightProbeLine([NSString stringWithFormat:@"chat %lu glyphs %@", (unsigned long)gPFBHeightProbeChat,
                                                  images.count ? [images componentsJoinedByString:@"; "] : @"none"]);
}

static UIView* PFBHeightProbeRow(UIView* root, CGRect zone) {
    static Class rowClass;
    rowClass = rowClass ?: NSClassFromString(@"_TtC10TFNUISwift25LegacySegmentedTabBarView");
    if (root.hidden) {
        return nil;
    }
    if (rowClass && [root isKindOfClass:rowClass] && CGRectIntersectsRect([root convertRect:root.bounds toView:nil], zone)) {
        return root;
    }
    for (UIView* sub in root.subviews) {
        UIView* found = PFBHeightProbeRow(sub, zone);
        if (found) {
            return found;
        }
    }
    return nil;
}

static NSString* PFBHeightProbeState(UIViewController* screen, UIView* zone, UIView* row) {
    UIScrollView* list = PFBHeightProbeList(screen.view);
    return [NSString stringWithFormat:@"zone %@; row %@; safe top %.1f; list inset %.1f adjusted %.1f", PFBHeightProbeView(zone),
                                      PFBHeightProbeView(row), screen.view.safeAreaInsets.top, list.contentInset.top,
                                      list.adjustedContentInset.top];
}

// Each height constraint found is made 16 pt taller, read back once laid out, then put back.
static void PFBHeightProbeTry(UIViewController* screen, UIView* zone, UIView* row, NSArray* levers, NSUInteger index) {
    if (index >= levers.count || !screen.viewIfLoaded.window) {
        PFBHeightProbeLine([NSString stringWithFormat:@"tries done; now %@", PFBHeightProbeState(screen, zone, row)]);
        return;
    }
    NSString* name = levers[index][0];
    NSLayoutConstraint* lever = levers[index][1];
    CGFloat original = lever.constant;
    lever.constant = original + 16.0;
    [screen.view setNeedsLayout];
    [screen.view.window layoutIfNeeded];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      PFBHeightProbeLine([NSString stringWithFormat:@"try %@ %.1f -> %.1f: %@", name, original, original + 16.0,
                                                    PFBHeightProbeState(screen, zone, row)]);
      lever.constant = original;
      [screen.view setNeedsLayout];
      [screen.view.window layoutIfNeeded];
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        PFBHeightProbeTry(screen, zone, row, levers, index + 1);
      });
    });
}

// Notifications: the room under the bar, the tab row's own room, and what holds their heights.
static void PFBHeightProbeNotifications(UIViewController* screen) {
    if (gPFBHeightProbeNotifications || !screen.viewIfLoaded.window) {
        return;
    }
    gPFBHeightProbeNotifications = YES;
    UIView* zone = PFBHeightProbeFind(screen.view, @"AccessoryStackView", 2);
    CGRect room = zone ? [zone convertRect:zone.bounds toView:nil] : CGRectZero;
    UIView* row = PFBHeightProbeRow(screen.view.window, room);
    id segmented = PFBHeightProbeIvar(screen, "$__lazy_storage_$_segmentedController");
    UIView* container = PFBHeightProbeIvar(segmented, "barContainerView");
    NSLayoutConstraint* containerHeight = PFBHeightProbeIvar(segmented, "barContainerHeightConstraint");
    SEL barHeight = NSSelectorFromString(@"barHeight");
    SEL maxHeight = NSSelectorFromString(@"maximumBarHeight");
    PFBHeightProbeLine([NSString stringWithFormat:@"notifications: %@", PFBHeightProbeState(screen, zone, row)]);
    PFBHeightProbeLine([NSString stringWithFormat:@"zone constraints: %@; zone chain %@", PFBHeightProbeConstraints(zone),
                                                  PFBHeightProbeChain(zone, 4)]);
    PFBHeightProbeLine([NSString stringWithFormat:@"segmented bar %.1f max %.1f; container %@ height %@; container chain %@",
                                                  [segmented respondsToSelector:barHeight] ? ((CGFloat (*)(id, SEL))objc_msgSend)(segmented, barHeight) : -1,
                                                  [segmented respondsToSelector:maxHeight] ? ((CGFloat (*)(id, SEL))objc_msgSend)(segmented, maxHeight) : -1,
                                                  PFBHeightProbeView(container), PFBHeightProbeConstraint(containerHeight),
                                                  PFBHeightProbeChain(container, 5)]);
    PFBHeightProbeLine([NSString stringWithFormat:@"row fits %.1f autoresizing %d; constraints %@; chain %@", row.intrinsicContentSize.height,
                                                  row.translatesAutoresizingMaskIntoConstraints, PFBHeightProbeConstraints(row),
                                                  PFBHeightProbeChain(row, 8)]);
    UIView* field = PFBHeightProbeFind(row, @"PFBNotifSearchBar", 1);
    UITextField* text = (UITextField*)PFBHeightProbeFind(field, @"UITextField", 1);
    PFBHeightProbeLine([NSString stringWithFormat:@"our field %@; text %@ font %@", PFBHeightProbeView(field), PFBHeightProbeView(text),
                                                  PFBHeightProbeFont(text.font)]);
    NSMutableArray* levers = [NSMutableArray array];
    if ([containerHeight isKindOfClass:[NSLayoutConstraint class]]) {
        [levers addObject:@[ @"container height", containerHeight ]];
    }
    NSArray* owners = @[ @[ @"zone", zone ?: [NSNull null] ], @[ @"row", row ?: [NSNull null] ] ];
    for (NSArray* owner in owners) {
        if (![owner[1] isKindOfClass:[UIView class]]) {
            continue;
        }
        for (NSLayoutConstraint* c in PFBHeightProbeTouching(owner[1])) {
            if (c.firstItem == owner[1] && c.firstAttribute == NSLayoutAttributeHeight && !c.secondItem && c != containerHeight) {
                [levers addObject:@[ [NSString stringWithFormat:@"%@ height", owner[0]], c ]];
            }
        }
    }
    PFBHeightProbeLine([NSString stringWithFormat:@"levers to try: %lu", (unsigned long)levers.count]);
    PFBHeightProbeTry(screen, zone, row, levers, 0);
}

%hook _TtC4DMUI14InboxSearchBar

- (void)layoutSubviews {
    %orig;
    __weak UIView* bar = (UIView*)self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      PFBHeightProbeChat(bar);
    });
}

%end

%hook T1NotificationsViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    __weak UIViewController* screen = (UIViewController*)self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      PFBHeightProbeNotifications(screen);
    });
}

%end
