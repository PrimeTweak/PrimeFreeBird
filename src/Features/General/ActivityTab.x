// Activity tab: Notifications keeps its first tab alone, named Activity. That tab already lists
// every notification, mentions included. Read once per launch, so the count holds all session.

#import "Support/HookHelpers.h"
#import <objc/message.h>
#import <objc/runtime.h>

static BOOL PFBActivityTabOn(void) {
    static BOOL on;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      on = [PFBSettings boolForKey:@"activity_tab"];
    });
    return on;
}

static BOOL PFBActivityTabOwns(id segmentedController) {
    static Class notifications;
    notifications = notifications ?: NSClassFromString(@"T1NotificationsViewController");
    SEL dataSource = NSSelectorFromString(@"dataSource");
    if (!PFBActivityTabOn() || !notifications || ![segmentedController respondsToSelector:dataSource]) {
        return NO;
    }
    return [((id (*)(id, SEL))objc_msgSend)(segmentedController, dataSource) isKindOfClass:notifications];
}

static NSString* PFBActivityTabLabel(id descriptor) {
    SEL first = NSSelectorFromString(@"firstLabelText");
    if (![descriptor respondsToSelector:first]) {
        return nil;
    }
    id text = ((id (*)(id, SEL))objc_msgSend)(descriptor, first);
    return [text isKindOfClass:[NSString class]] ? text : nil;
}

// The slot holding the tab's words is the one whose removal changes them; it gets a label slot
// with the new name, the icon and the other slots staying as Twitter made them.
static void PFBActivityTabRename(id descriptor) {
    NSString* name = [[PFBBundle sharedBundle] localizedStringForKey:@"ACTIVITY_TAB_NAME"];
    NSString* current = PFBActivityTabLabel(descriptor);
    if (!current || [current isEqualToString:name]) {
        return;
    }
    Class slotClass = NSClassFromString(@"_TtC10TFNUISwift13LegacyTabSlot");
    SEL makeLabel = NSSelectorFromString(@"label:persistsWhenDeselected:");
    if (![slotClass respondsToSelector:makeLabel]) {
        PFBCompatMeasure(@"activity tab", @"name kept: Twitter's label slot is gone", 2);
        return;
    }
    for (NSString* slot in @[ @"leadingMain", @"trailingMain", @"leadingAccessory", @"trailingAccessory" ]) {
        SEL getter = NSSelectorFromString(slot);
        SEL setter = NSSelectorFromString([NSString stringWithFormat:@"set%@%@:", [slot substringToIndex:1].uppercaseString,
                                                                     [slot substringFromIndex:1]]);
        if (![descriptor respondsToSelector:getter] || ![descriptor respondsToSelector:setter]) {
            continue;
        }
        id original = ((id (*)(id, SEL))objc_msgSend)(descriptor, getter);
        if (!original) {
            continue;
        }
        ((void (*)(id, SEL, id))objc_msgSend)(descriptor, setter, nil);
        if ([PFBActivityTabLabel(descriptor) isEqualToString:current]) {
            ((void (*)(id, SEL, id))objc_msgSend)(descriptor, setter, original);
            continue;
        }
        SEL persistsSelector = NSSelectorFromString(@"persistsWhenDeselected");
        BOOL persists = ![original respondsToSelector:persistsSelector] ||
                        ((BOOL (*)(id, SEL))objc_msgSend)(original, persistsSelector);
        id label = ((id (*)(id, SEL, id, BOOL))objc_msgSend)(slotClass, makeLabel, name, persists);
        ((void (*)(id, SEL, id))objc_msgSend)(descriptor, setter, label ?: original);
        SEL accessibilitySetter = NSSelectorFromString(@"setTabAccessibilityLabel:");
        if (label && [descriptor respondsToSelector:accessibilitySetter]) {
            ((void (*)(id, SEL, id))objc_msgSend)(descriptor, accessibilitySetter, name);
        }
        PFBCOMPAT_ACTION(PFBCompat_activity_tab, @"tab named Activity");
        return;
    }
    PFBCompatMeasure(@"activity tab", [NSString stringWithFormat:@"name kept: no slot holds \"%@\"", current], 2);
}

%hook T1NotificationsViewController

- (NSInteger)numberOfTabsIn:(id)segmentedController {
    NSInteger tabs = %orig;
    if (!PFBActivityTabOn() || tabs <= 1) {
        PFBCOMPAT_OBSERVE(PFBCompat_activity_tab, @"tab count read");
        return tabs;
    }
    PFBCOMPAT_ACTION(PFBCompat_activity_tab, @"All and Mentions merged");
    return 1;
}

- (id)segmentedViewController:(id)segmentedController descriptorAtIndex:(NSInteger)index {
    id descriptor = %orig;
    if (PFBActivityTabOn() && index == 0) {
        PFBActivityTabRename(descriptor);
    }
    return descriptor;
}

%end

// The screen opens on the one tab left, whatever tab it was set to open on.
%hook _TtC10TFNUISwift29LegacySegmentedViewController

- (void)viewDidLoad {
    Ivar initial = PFBActivityTabOwns(self) ? class_getInstanceVariable(object_getClass(self), "initialSelectedIndex") : NULL;
    if (initial) {
        NSInteger* stored = (NSInteger*)((uint8_t*)(__bridge void*)self + ivar_getOffset(initial));
        if (*stored > 0) {
            *stored = 0;
            PFBCOMPAT_ACTION(PFBCompat_activity_tab, @"opening tab kept on Activity");
        }
    }
    %orig;
}

%end
