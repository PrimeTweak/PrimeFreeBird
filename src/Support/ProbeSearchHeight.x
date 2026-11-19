// Probe for the search field on Twitter 12.45: Notifications' tab row held at 60 pt before Twitter
// sizes the room under its bar, and Chat's text field read, then given "Search chat". Removed once
// read; its lines go to the stethoscope report under the topic "probe search height".

#import "Support/HookHelpers.h"
#import <malloc/malloc.h>
#import <objc/message.h>
#import <objc/runtime.h>

static NSString* const kPFBHeightProbeTopic = @"probe search height";
static const CGFloat kPFBHeightProbeRow = 60.0;
static BOOL gPFBHeightProbeHeld;
static BOOL gPFBHeightProbeRead;
static BOOL gPFBHeightProbeChat;

static void PFBHeightProbeLine(NSString* line) {
    PFBCompatMeasure(kPFBHeightProbeTopic, line, 60);
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
    return [NSString stringWithFormat:@"%+.1f p%.0f%@", c.constant, c.priority, c.active ? @"" : @" inactive"];
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

static UITableView* PFBHeightProbeTable(UIView* root) {
    if ([root isKindOfClass:[UITableView class]] && root.window && !root.hidden) {
        return (UITableView*)root;
    }
    for (UIView* sub in root.subviews) {
        UITableView* found = PFBHeightProbeTable(sub);
        if (found) {
            return found;
        }
    }
    return nil;
}

static BOOL PFBHeightProbeOwns(id segmented) {
    SEL dataSource = NSSelectorFromString(@"dataSource");
    Class notifications = NSClassFromString(@"T1NotificationsViewController");
    return notifications && [segmented respondsToSelector:dataSource] &&
           [((id (*)(id, SEL))objc_msgSend)(segmented, dataSource) isKindOfClass:notifications];
}

// Notifications' tab row held at 60 pt as its screen loads, before Twitter sizes the room.
static void PFBHeightProbeHold(id segmented, NSString* when) {
    if (gPFBHeightProbeHeld || !PFBHeightProbeOwns(segmented)) {
        return;
    }
    NSLayoutConstraint* height = PFBHeightProbeIvar(segmented, "barContainerHeightConstraint");
    if (![height isKindOfClass:[NSLayoutConstraint class]]) {
        PFBHeightProbeLine([NSString stringWithFormat:@"hold at %@: no row height constraint yet", when]);
        return;
    }
    gPFBHeightProbeHeld = YES;
    PFBHeightProbeLine([NSString stringWithFormat:@"hold at %@: row height %@ set to %.0f required", when,
                                                  PFBHeightProbeConstraint(height), kPFBHeightProbeRow]);
    height.priority = UILayoutPriorityRequired;
    height.constant = kPFBHeightProbeRow;
}

// The room, the row and the list once Notifications shows, and whether the row kept its 60 pt.
static void PFBHeightProbeReadNotifications(UIViewController* screen) {
    if (gPFBHeightProbeRead || !screen.viewIfLoaded.window) {
        return;
    }
    gPFBHeightProbeRead = YES;
    id segmented = PFBHeightProbeIvar(screen, "$__lazy_storage_$_segmentedController");
    NSLayoutConstraint* height = PFBHeightProbeIvar(segmented, "barContainerHeightConstraint");
    UIView* zone = PFBHeightProbeFind(screen.view, @"AccessoryStackView", 2);
    UIView* row = PFBHeightProbeFind(zone, @"LegacySegmentedTabBarView", 3);
    UITableView* table = PFBHeightProbeTable(screen.view);
    NSMutableArray<NSString*>* zoneHeights = [NSMutableArray array];
    for (NSLayoutConstraint* c in zone.superview.constraints) {
        if (c.firstItem == zone && c.firstAttribute == NSLayoutAttributeTop) {
            [zoneHeights addObject:PFBHeightProbeConstraint(c)];
        }
    }
    PFBHeightProbeLine([NSString stringWithFormat:@"notifications held %d: row height now %@; zone %@ top %@; row %@; safe top %.1f; "
                                                  @"list %@ inset %.1f adjusted %.1f",
                                                  gPFBHeightProbeHeld, PFBHeightProbeConstraint(height), PFBHeightProbeView(zone),
                                                  zoneHeights.count ? [zoneHeights componentsJoinedByString:@", "] : @"none",
                                                  PFBHeightProbeView(row), screen.view.safeAreaInsets.top, PFBHeightProbeView(table),
                                                  table.contentInset.top, table.adjustedContentInset.top]);
}

static NSString* PFBHeightProbeField(UITextField* field) {
    if (![field isKindOfClass:[UITextField class]]) {
        return [NSString stringWithFormat:@"not a text field: %@", PFBHeightProbeName(field)];
    }
    UITraitCollection* traits = field.traitCollection;
    NSDictionary* style = field.attributedPlaceholder.length ? [field.attributedPlaceholder attributesAtIndex:0 effectiveRange:NULL] : nil;
    return [NSString stringWithFormat:@"%@ (%@) placeholder \"%@\" in %@ %@; font %@ grows %d; text %@; tint %@",
                                      PFBHeightProbeView(field), NSStringFromClass([field superclass]), field.placeholder,
                                      PFBHeightProbeFont(style[NSFontAttributeName]),
                                      PFBHeightProbeColor(style[NSForegroundColorAttributeName], traits), PFBHeightProbeFont(field.font),
                                      field.adjustsFontForContentSizeCategory, PFBHeightProbeColor(field.textColor, traits),
                                      PFBHeightProbeColor(field.tintColor, traits)];
}

// Chat's search field: its text field and glyph, then "Search chat" given and read back twice.
static void PFBHeightProbeChat(UIView* button) {
    if (gPFBHeightProbeChat || !button.window) {
        return;
    }
    gPFBHeightProbeChat = YES;
    id input = PFBHeightProbeIvar(button, "input");
    UITextField* field = PFBHeightProbeIvar(input, "textField");
    UIImageView* icon = PFBHeightProbeIvar(input, "leadingIconView");
    PFBHeightProbeLine([NSString stringWithFormat:@"chat input %@; field %@", PFBHeightProbeName(input), PFBHeightProbeField(field)]);
    PFBHeightProbeLine([NSString stringWithFormat:@"chat glyph %@ image %.1fx%.1f; padding %@", PFBHeightProbeView(icon),
                                                  [icon isKindOfClass:[UIImageView class]] ? icon.image.size.width : -1,
                                                  [icon isKindOfClass:[UIImageView class]] ? icon.image.size.height : -1,
                                                  PFBHeightProbeView(PFBHeightProbeIvar(input, "leadingPaddingView"))]);
    if (![field isKindOfClass:[UITextField class]]) {
        return;
    }
    NSDictionary* style = field.attributedPlaceholder.length ? [field.attributedPlaceholder attributesAtIndex:0 effectiveRange:NULL] : @{};
    field.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"Search chat" attributes:style];
    __weak UITextField* weakField = field;
    for (NSNumber* delay in @[ @1, @4 ]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
          PFBHeightProbeLine([NSString stringWithFormat:@"chat after %@ s: placeholder \"%@\"", delay, weakField.placeholder]);
        });
    }
}

%hook _TtC10TFNUISwift29LegacySegmentedViewController

- (void)viewDidLoad {
    %orig;
    PFBHeightProbeHold(self, @"load");
}

%end

%hook T1NotificationsViewController

- (void)viewWillAppear:(BOOL)animated {
    PFBHeightProbeHold(PFBHeightProbeIvar(self, "$__lazy_storage_$_segmentedController"), @"will appear");
    %orig;
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    __weak UIViewController* screen = (UIViewController*)self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      PFBHeightProbeReadNotifications(screen);
    });
}

%end

%hook _TtC7DMInbox20InboxSearchBarButton

- (void)layoutSubviews {
    %orig;
    __weak UIView* button = (UIView*)self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      PFBHeightProbeChat(button);
    });
}

%end
