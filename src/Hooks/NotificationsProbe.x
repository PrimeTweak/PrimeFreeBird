//
//  NotificationsProbe.x
//
//  TEMPORARY. Measures everything the hide-a-notification feature needs, in one
//  pass, so the design is settled before a line of it is written. Delete once
//  its output has been read.
//
//  It only reads: no view is painted, no image is replaced, no method with an
//  unverified signature is hooked. The single hook is
//  TFNItemsDataViewController's setSections:restoreScrollPosition:, whose
//  signature Timeline.x has been calling for months.
//
//  Read it in Console.app with the phone attached, filtering on:
//      subsystem:com.primefreebird.probe
//

#import "HookHelpers.h"
#import <os/log.h>
#import <string.h>

static os_log_t NFBProbeLog(void) {
    static os_log_t log;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        log = os_log_create("com.primefreebird.probe", "notifications");
    });
    return log;
}

// Values are asked for only when the selector exists AND returns an object.
// Messaging a scalar-returning selector as an object is what crashed the thread
// probe; the signature is checked first, every time.
static id NFBProbeAsk(id target, SEL selector) {
    if (!target || ![target respondsToSelector:selector]) {
        return nil;
    }
    NSMethodSignature* signature = [target methodSignatureForSelector:selector];
    const char* returnType = signature.methodReturnType;
    if (!returnType || strcmp(returnType, "@") != 0) {
        return nil;
    }
    return ((id (*)(id, SEL))objc_msgSend)(target, selector);
}

// A one-line answer to "does it respond, and what came back".
static NSString* NFBProbeField(id target, NSString* name) {
    SEL selector = NSSelectorFromString(name);
    if (!target || ![target respondsToSelector:selector]) {
        return [NSString stringWithFormat:@"%@=<absent>", name];
    }
    NSMethodSignature* signature = [target methodSignatureForSelector:selector];
    const char* type = signature.methodReturnType;
    if (!type) {
        return [NSString stringWithFormat:@"%@=<sans signature>", name];
    }
    if (strcmp(type, "@") != 0) {
        // Present but not an object: the encoding alone tells the shape.
        return [NSString stringWithFormat:@"%@=<non-objet '%s'>", name, type];
    }
    id value = ((id (*)(id, SEL))objc_msgSend)(target, selector);
    if (!value) {
        return [NSString stringWithFormat:@"%@=nil", name];
    }
    NSString* cls = NSStringFromClass([value classForCoder]);
    if ([value isKindOfClass:[NSString class]]) {
        return [NSString stringWithFormat:@"%@=\"%@\"", name, value];
    }
    return [NSString stringWithFormat:@"%@=<%@>", name, cls];
}

// The gesture surfaces. Nothing is called — only asked whether it is
// implemented, which is what decides where the action can be hung.
static void NFBProbeGestureSurfaces(UIViewController* controller) {
    UITableView* table = nil;
    NSMutableArray<UIView*>* queue =
        [NSMutableArray arrayWithObjects:controller.viewIfLoaded ?: (UIView*)nil, nil];
    [queue removeObjectIdenticalTo:(id)[NSNull null]];
    NSUInteger head = 0;
    while (head < queue.count && !table) {
        UIView* view = queue[head++];
        if (!view) {
            continue;
        }
        if ([view isKindOfClass:[UITableView class]]) {
            table = (UITableView*)view;
            break;
        }
        [queue addObjectsFromArray:view.subviews];
    }
    if (!table) {
        os_log(NFBProbeLog(), "   TABLE  <introuvable dans la hiérarchie>");
        return;
    }

    id delegate = table.delegate;
    id source = table.dataSource;
    os_log(NFBProbeLog(), "   TABLE  classe=%{public}@  delegate=%{public}@  dataSource=%{public}@",
           NSStringFromClass([table classForCoder]),
           delegate ? NSStringFromClass([delegate classForCoder]) : @"nil",
           source ? NSStringFromClass([source classForCoder]) : @"nil");

    NSArray<NSString*>* wanted = @[
        @"tableView:trailingSwipeActionsConfigurationForRowAtIndexPath:",
        @"tableView:leadingSwipeActionsConfigurationForRowAtIndexPath:",
        @"tableView:editActionsForRowAtIndexPath:",
        @"tableView:canEditRowAtIndexPath:",
        @"tableView:contextMenuConfigurationForRowAtIndexPath:point:",
    ];
    for (NSString* name in wanted) {
        SEL selector = NSSelectorFromString(name);
        BOOL onDelegate = delegate && [delegate respondsToSelector:selector];
        BOOL onSource = source && [source respondsToSelector:selector];
        os_log(NFBProbeLog(), "   GESTE  %{public}@ → delegate:%{public}s dataSource:%{public}s",
               name, onDelegate ? "OUI" : "non", onSource ? "OUI" : "non");
    }
}

%hook TFNItemsDataViewController

- (void)setSections:(NSArray*)sections restoreScrollPosition:(BOOL)restoreScrollPosition {
    %orig;

    NSString* controllerClass = NSStringFromClass(object_getClass(self));
    // Every screen passes through here. Only the notifications one is reported,
    // so the log stays readable while he scrolls.
    if ([controllerClass rangeOfString:@"Notification"].location == NSNotFound) {
        return;
    }

    os_log(NFBProbeLog(), "──────── SONDE NOTIFICATIONS ────────");
    os_log(NFBProbeLog(), "CONTRÔLEUR  %{public}@  (sections=%{public}lu)",
           controllerClass, (unsigned long)sections.count);
    // Confirms the filter door: if this is a TFNItemsDataViewController, the
    // pass that already drops hidden threads reaches this screen unchanged.
    os_log(NFBProbeLog(), "   PORTE  TFNItemsDataViewController=%{public}s",
           [self isKindOfClass:objc_getClass("TFNItemsDataViewController")] ? "OUI" : "non");

    NFBProbeGestureSurfaces((UIViewController*)self);

    NSUInteger reported = 0;
    for (id section in sections) {
        if (![section isKindOfClass:[NSArray class]]) {
            continue;
        }
        for (id item in (NSArray*)section) {
            if (reported >= 12) {
                break;
            }
            id model = unwrapDataViewItem(item);
            if (!model) {
                continue;
            }
            reported++;
            NSString* modelClass = NSStringFromClass([model classForCoder]);
            os_log(NFBProbeLog(), "[%{public}lu] MODÈLE %{public}@",
                   (unsigned long)reported, modelClass);
            os_log(NFBProbeLog(), "      %{public}@ | %{public}@",
                   NFBProbeField(model, @"entryID"),
                   NFBProbeField(model, @"notificationID"));

            // The notification object carries the icon that classifies the row —
            // the text is localised and cannot be the discriminator.
            id notification = NFBProbeAsk(model, @selector(notification));
            if (notification) {
                os_log(NFBProbeLog(), "      NOTIF %{public}@ | %{public}@ | %{public}@",
                       NSStringFromClass([notification classForCoder]),
                       NFBProbeField(notification, @"notificationID"),
                       NFBProbeField(notification, @"icon"));
                id icon = NFBProbeAsk(notification, @selector(icon));
                if (icon) {
                    os_log(NFBProbeLog(), "      ICÔNE %{public}@ | %{public}@ | %{public}@",
                           NSStringFromClass([icon classForCoder]),
                           NFBProbeField(icon, @"name"),
                           NFBProbeField(icon, @"identifier"));
                }
                id rich = NFBProbeAsk(notification, @selector(richText));
                if (rich) {
                    os_log(NFBProbeLog(), "      TEXTE %{public}@ | %{public}@",
                           NSStringFromClass([rich classForCoder]),
                           NFBProbeField(rich, @"text"));
                }
            }
        }
    }
    os_log(NFBProbeLog(), "──────── FIN (%{public}lu rangées) ────────",
           (unsigned long)reported);
}

%end

%ctor {
    os_log(NFBProbeLog(), "SONDE NOTIFICATIONS CHARGÉE — ouvre l'onglet Notifications");
}
