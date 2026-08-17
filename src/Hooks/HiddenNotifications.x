// HiddenNotifications.x — hide a notification, let it expire on its own.
//
// His ask, verbatim: swipe a notification away (the way the conversations list
// already works), see the hidden ones with a countdown to their expiry, unhide
// one, or clear them all — "even if I can't delete them, I can hide them and
// they disappear naturally".
//
// EVERY structural choice below is a measurement, not a guess (his probe,
// 17/08 15:03):
//   · the notifications list is a T1URTViewController and it answers
//     tableView:trailingSwipeActionsConfigurationForRowAtIndexPath: —
//     trailing=1, while the home timeline answers 0. His lead was right: the
//     native swipe mechanism is available here.
//   · a row's model is TwitterURT.URTTimelineNotificationViewModel, a Swift
//     class whose field names none of my candidate lists matched.
//
// So the field names are discovered AT RUNTIME instead of costing another
// probe build: a cascade of likely selectors first, then the class's own
// zero-argument getters, filtered by return type and name. What it settles on
// is journaled once, so the choice is auditable rather than magic.
//
// Nothing here touches a cell (his hard rule about recycled cells): the swipe
// comes from the table's own delegate, and hiding is done by filtering the
// sections — the mechanism already proven by Hidden Threads.

#import "HookHelpers.h"
#import "Debug/NFBDebugger.h"

static NSString* const kNFBHiddenNotifsKey = @"nfb_hidden_notifs";
static NSString* const kNFBNotifHorizonKey = @"nfb_notif_horizon_days";
static NSString* const kNFBHideNotifsEnabledKey = @"hide_notifications";

// Absent key ⇒ ON. The feature must work on the very first build, before the
// settings row lands; once the row exists (default YES) the two agree.
static BOOL NFBNotifsEnabled(void) {
    id value = [[NSUserDefaults standardUserDefaults]
                   objectForKey:kNFBHideNotifsEnabledKey];
    return value ? [value boolValue] : YES;
}

// The notifications screen names itself: the filter below runs on it, so it
// records the controller it saw. The quick-access button uses that instead of
// guessing a class name — the trap that cost three probe builds.
static __weak UIViewController* gNFBNotifScreen;

// The registry: id → { "t": text, "d": notification date, "h": hidden at }.
// A dictionary keyed by id makes lookup O(1) on the hot filtering path.
static NSDictionary* NFBHiddenNotifs(void) {
    NSDictionary* stored =
        [[NSUserDefaults standardUserDefaults] dictionaryForKey:kNFBHiddenNotifsKey];
    return stored ?: @{};
}

double NFBNotifHorizonDays(void) {
    double stored = [[NSUserDefaults standardUserDefaults] doubleForKey:kNFBNotifHorizonKey];
    return stored > 0 ? stored : 30.0;
}

// Days left before the entry drops out on its own. Counted from the
// notification's own date when we could read one, otherwise from the moment it
// was hidden — stated plainly in the UI rather than pretending to be exact.
double NFBNotifDaysLeft(NSDictionary* entry) {
    double base = [entry[@"d"] doubleValue];
    if (base <= 0) {
        base = [entry[@"h"] doubleValue];
    }
    if (base <= 0) {
        return NFBNotifHorizonDays();
    }
    double elapsed = ([[NSDate date] timeIntervalSince1970] - base) / 86400.0;
    double left = NFBNotifHorizonDays() - elapsed;
    return left > 0 ? left : 0;
}

// Purge on read: an entry past its horizon leaves by itself — his whole point.
void NFBPurgeExpiredNotifs(void) {
    NSDictionary* current = NFBHiddenNotifs();
    if (!current.count) {
        return;
    }
    NSMutableDictionary* kept = [current mutableCopy];
    for (NSString* key in current) {
        if (NFBNotifDaysLeft(current[key]) <= 0) {
            [kept removeObjectForKey:key];
        }
    }
    if (kept.count != current.count) {
        [[NSUserDefaults standardUserDefaults] setObject:kept forKey:kNFBHiddenNotifsKey];
    }
}

NSArray<NSDictionary*>* NFBHiddenNotifList(void) {
    NFBPurgeExpiredNotifs();
    NSDictionary* current = NFBHiddenNotifs();
    NSMutableArray<NSDictionary*>* rows = [NSMutableArray array];
    for (NSString* key in current) {
        NSMutableDictionary* row = [current[key] mutableCopy];
        row[@"id"] = key;
        [rows addObject:row];
    }
    // Newest hidden first.
    [rows sortUsingComparator:^NSComparisonResult(NSDictionary* a, NSDictionary* b) {
        return [b[@"h"] compare:a[@"h"]];
    }];
    return rows;
}

void NFBUnhideNotif(NSString* notifID) {
    NSMutableDictionary* current = [NFBHiddenNotifs() mutableCopy];
    [current removeObjectForKey:notifID];
    [[NSUserDefaults standardUserDefaults] setObject:current forKey:kNFBHiddenNotifsKey];
}

void NFBUnhideAllNotifs(void) {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kNFBHiddenNotifsKey];
}

NSInteger NFBHiddenNotifCount(void) {
    NFBPurgeExpiredNotifs();
    return (NSInteger)NFBHiddenNotifs().count;
}

// MARK: - Reading a notification without knowing its class
//
// Type-safe throughout: a selector whose return type is not what we expect is
// never called (the statusDidUpdate crash lesson — a guessed signature made
// ARC retain the integer 0x6005).

static id NFBNotifAsk(id target, SEL selector) {
    if (!target || ![target respondsToSelector:selector]) {
        return nil;
    }
    NSMethodSignature* signature = [target methodSignatureForSelector:selector];
    const char* type = signature.methodReturnType;
    if (!type || strcmp(type, "@") != 0) {
        return nil;
    }
    return ((id (*)(id, SEL))objc_msgSend)(target, selector);
}

static double NFBNotifAskNumber(id target, SEL selector) {
    if (!target || ![target respondsToSelector:selector]) {
        return 0;
    }
    NSMethodSignature* signature = [target methodSignatureForSelector:selector];
    const char* type = signature.methodReturnType;
    if (!type) {
        return 0;
    }
    if (strcmp(type, "d") == 0) {
        return ((double (*)(id, SEL))objc_msgSend)(target, selector);
    }
    if (strcmp(type, "q") == 0 || strcmp(type, "l") == 0) {
        return (double)((long long (*)(id, SEL))objc_msgSend)(target, selector);
    }
    if (strcmp(type, "@") == 0) {
        id value = ((id (*)(id, SEL))objc_msgSend)(target, selector);
        if ([value isKindOfClass:[NSNumber class]]) {
            return [(NSNumber*)value doubleValue];
        }
        if ([value isKindOfClass:[NSDate class]]) {
            return [(NSDate*)value timeIntervalSince1970];
        }
    }
    return 0;
}

static NSString* NFBNotifString(id value) {
    if ([value isKindOfClass:[NSString class]]) {
        return value;
    }
    if (value && [value respondsToSelector:@selector(string)]) {
        id text = ((id (*)(id, SEL))objc_msgSend)(value, @selector(string));
        if ([text isKindOfClass:[NSString class]]) {
            return text;
        }
    }
    return nil;
}

// The runtime sweep: the class's own zero-argument getters, scored by name.
// Used only when the candidate lists come up empty, and the winner is cached
// per class so the sweep happens once.
static SEL NFBNotifDiscover(id model, NSArray<NSString*>* wanted, char kind) {
    unsigned int count = 0;
    Method* methods = class_copyMethodList([model class], &count);
    if (!methods) {
        return NULL;
    }
    SEL winner = NULL;
    for (unsigned int i = 0; i < count && !winner; i++) {
        SEL selector = method_getName(methods[i]);
        NSString* name = NSStringFromSelector(selector);
        if ([name containsString:@":"] || [name hasPrefix:@"_"] ||
            [name hasPrefix:@"."]) {
            continue;
        }
        BOOL matches = NO;
        for (NSString* needle in wanted) {
            if ([name.lowercaseString containsString:needle]) {
                matches = YES;
                break;
            }
        }
        if (!matches) {
            continue;
        }
        char* returnType = method_copyReturnType(methods[i]);
        if (returnType) {
            BOOL usable = (kind == '@') ? (returnType[0] == '@')
                                        : (returnType[0] == 'd' || returnType[0] == 'q' ||
                                           returnType[0] == 'l' || returnType[0] == '@');
            free(returnType);
            if (usable) {
                // Confirm it actually yields something before adopting it.
                if (kind == '@') {
                    if (NFBNotifString(NFBNotifAsk(model, selector)).length) {
                        winner = selector;
                    }
                } else {
                    double value = NFBNotifAskNumber(model, selector);
                    if (value > 1420000000 && value < 2050000000) {
                        winner = selector;
                    } else if (value > 1420000000000.0 && value < 2050000000000.0) {
                        winner = selector;
                    }
                }
            }
        }
    }
    free(methods);
    return winner;
}

// Identity, date and text of a row's model. The three lookups share one shape:
// try the known names, then sweep, then remember — and say once what was found.
static NSString* NFBNotifIdentity(id model) {
    static NSMutableDictionary<NSString*, NSString*>* cache;
    if (!cache) { cache = [NSMutableDictionary dictionary]; }
    NSString* className = NSStringFromClass([model class]);

    NSString* known = cache[className];
    if (known) {
        return NFBNotifString(NFBNotifAsk(model, NSSelectorFromString(known)));
    }
    NSArray<NSString*>* candidates = @[
        @"entryId", @"entryID", @"identifier", @"notificationId",
        @"notificationID", @"id", @"sortIndex", @"key", @"itemIdentifier"
    ];
    for (NSString* name in candidates) {
        NSString* value = NFBNotifString(NFBNotifAsk(model, NSSelectorFromString(name)));
        if (value.length) {
            cache[className] = name;
            NFBDebugLog(@"notifhide: identité de %@ = %@", className, name);
            return value;
        }
    }
    SEL found = NFBNotifDiscover(model, @[@"entryid", @"identifier", @"sortindex",
                                          @"itemid", @"restid"], '@');
    if (found) {
        cache[className] = NSStringFromSelector(found);
        NFBDebugLog(@"notifhide: identité de %@ = %@ (découverte)",
                    className, NSStringFromSelector(found));
        return NFBNotifString(NFBNotifAsk(model, found));
    }
    return nil;
}

static double NFBNotifDate(id model) {
    NSArray<NSString*>* candidates = @[
        @"timestamp", @"sortTimestamp", @"createdAt", @"date", @"sortDate",
        @"timeInMs", @"createdAtMs", @"time"
    ];
    for (NSString* name in candidates) {
        double value = NFBNotifAskNumber(model, NSSelectorFromString(name));
        if (value > 1420000000 && value < 2050000000) {
            return value;
        }
        if (value > 1420000000000.0 && value < 2050000000000.0) {
            return value / 1000.0;
        }
    }
    SEL found = NFBNotifDiscover(model, @[@"date", @"time", @"created", @"sort"], 'd');
    if (found) {
        double discovered = NFBNotifAskNumber(model, found);
        return discovered > 1420000000000.0 ? discovered / 1000.0 : discovered;
    }
    return 0;
}

static NSString* NFBNotifText(id model) {
    NSArray<NSString*>* candidates = @[
        @"text", @"message", @"displayText", @"bodyText", @"title",
        @"formattedText", @"attributedText", @"summary", @"notificationText"
    ];
    for (NSString* name in candidates) {
        NSString* value = NFBNotifString(NFBNotifAsk(model, NSSelectorFromString(name)));
        if (value.length > 2) {
            return value;
        }
    }
    SEL found = NFBNotifDiscover(model, @[@"text", @"title", @"message", @"body",
                                          @"summary"], '@');
    if (found) {
        return NFBNotifString(NFBNotifAsk(model, found));
    }
    return nil;
}

BOOL NFBNotifIsHidden(id model) {
    if (!model) {
        return NO;
    }
    NSDictionary* hidden = NFBHiddenNotifs();
    if (!hidden.count) {
        return NO;   // the hot path costs one dictionary read
    }
    NSString* identity = NFBNotifIdentity(model);
    return identity.length && hidden[identity] != nil;
}

static void NFBHideNotif(id model) {
    NSString* identity = NFBNotifIdentity(model);
    if (!identity.length) {
        NFBDebugLog(@"notifhide: aucune identité lisible — masquage refusé");
        return;
    }
    NSMutableDictionary* current = [NFBHiddenNotifs() mutableCopy];
    NSString* text = NFBNotifText(model) ?: @"";
    if (text.length > 140) {
        text = [text substringToIndex:140];
    }
    current[identity] = @{
        @"t": text,
        @"d": @(NFBNotifDate(model)),
        @"h": @([[NSDate date] timeIntervalSince1970])
    };
    [[NSUserDefaults standardUserDefaults] setObject:current forKey:kNFBHiddenNotifsKey];
    NFBDebugLog(@"notifhide: masquée <%@> — %lu au total",
                identity, (unsigned long)current.count);
}

// MARK: - The toast (the capsule he validated for Hidden Threads)

static const NSInteger kNFBNotifToastTag = 90313;

static void NFBDismissNotifToast(UIView* toast) {
    [UIView animateWithDuration:0.22
        animations:^{
          toast.alpha = 0;
          toast.transform = CGAffineTransformMakeTranslation(0.0, -8.0);
        }
        completion:^(__unused BOOL finished) {
          [toast removeFromSuperview];
        }];
}

extern void nfbReapplyTimelineFilter(void);

static void NFBShowNotifToast(NSString* notifID) {
    UIWindow* window = nil;
    for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }
        for (UIWindow* candidate in ((UIWindowScene*)scene).windows) {
            if (candidate.isKeyWindow) {
                window = candidate;
            }
        }
    }
    if (!window) {
        return;
    }
    [[window viewWithTag:kNFBNotifToastTag] removeFromSuperview];

    BOOL liquidGlass = [BHTSettings boolForKey:@"enable_liquid_glass"];
    Class glassClass = NSClassFromString(@"UIGlassEffect");
    UIVisualEffect* effect = nil;
    if (liquidGlass && glassClass) {
        effect = [[glassClass alloc] init];
    }
    if (!effect) {
        effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThickMaterial];
        liquidGlass = NO;
    }
    UIVisualEffectView* toast = [[UIVisualEffectView alloc] initWithEffect:effect];
    toast.tag = kNFBNotifToastTag;
    toast.translatesAutoresizingMaskIntoConstraints = NO;
    toast.layer.cornerRadius = 22.0;
    toast.layer.cornerCurve = kCACornerCurveContinuous;
    if (!liquidGlass) {
        toast.clipsToBounds = YES;
        toast.layer.borderWidth = 0.5;
        toast.layer.borderColor = [UIColor separatorColor].CGColor;
    }
    [window addSubview:toast];

    UIView* content = toast.contentView;

    UILabel* label = [[UILabel alloc] init];
    label.text = [[BHTBundle sharedBundle] localizedStringForKey:@"NOTIFS_HIDDEN_TOAST"];
    label.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    label.textColor = [UIColor labelColor];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:label];

    UIButton* undo = [UIButton buttonWithType:UIButtonTypeSystem];
    [undo setTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"THREADS_UNDO"]
          forState:UIControlStateNormal];
    extern UIColor* CurrentAccentColor(void);
    [undo setTitleColor:CurrentAccentColor() ?: [UIColor labelColor]
               forState:UIControlStateNormal];
    undo.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    undo.translatesAutoresizingMaskIntoConstraints = NO;
    [undo addAction:[UIAction actionWithHandler:^(__unused UIAction* action) {
              NFBUnhideNotif(notifID);
              nfbReapplyTimelineFilter();
              NFBDismissNotifToast(toast);
            }]
        forControlEvents:UIControlEventTouchUpInside];
    [content addSubview:undo];

    [NSLayoutConstraint activateConstraints:@[
        [toast.centerXAnchor constraintEqualToAnchor:window.centerXAnchor],
        [toast.topAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.topAnchor
                                        constant:6],
        [toast.heightAnchor constraintEqualToConstant:44],
        [toast.leadingAnchor constraintGreaterThanOrEqualToAnchor:window.leadingAnchor
                                                        constant:20],
        [label.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:18],
        [label.centerYAnchor constraintEqualToAnchor:content.centerYAnchor],
        [undo.leadingAnchor constraintEqualToAnchor:label.trailingAnchor constant:14],
        [undo.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-18],
        [undo.centerYAnchor constraintEqualToAnchor:content.centerYAnchor],
    ]];

    toast.alpha = 0;
    toast.transform = CGAffineTransformMakeTranslation(0.0, -8.0);
    [UIView animateWithDuration:0.22
                     animations:^{
                       toast.alpha = 1;
                       toast.transform = CGAffineTransformIdentity;
                     }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                     if (toast.superview) {
                         NFBDismissNotifToast(toast);
                     }
                   });
}

// MARK: - The swipe, on the list's own delegate
//
// Measured: T1URTViewController answers the trailing-swipe delegate call
// (trailing=1) while the home timeline does not (0). So the action is appended
// to whatever Twitter already returns — nothing of theirs is dropped, and if
// they return nothing we hand back a configuration with ours alone.

static id NFBModelAtIndexPath(id dataViewController, NSIndexPath* indexPath) {
    SEL itemSel = NSSelectorFromString(@"itemAtIndexPath:");
    if ([dataViewController respondsToSelector:itemSel]) {
        id item = ((id (*)(id, SEL, id))objc_msgSend)(dataViewController, itemSel, indexPath);
        id model = unwrapDataViewItem(item);
        if (model) {
            return model;
        }
    }
    SEL sectionsSel = NSSelectorFromString(@"sections");
    if (![dataViewController respondsToSelector:sectionsSel]) {
        return nil;
    }
    NSArray* sections = ((id (*)(id, SEL))objc_msgSend)(dataViewController, sectionsSel);
    if (indexPath.section >= (NSInteger)sections.count) {
        return nil;
    }
    id section = sections[indexPath.section];
    NSArray* items = nil;
    if ([section respondsToSelector:@selector(items)]) {
        id maybe = ((id (*)(id, SEL))objc_msgSend)(section, @selector(items));
        if ([maybe isKindOfClass:[NSArray class]]) {
            items = maybe;
        }
    }
    if (indexPath.row >= (NSInteger)items.count) {
        return nil;
    }
    return unwrapDataViewItem(items[indexPath.row]);
}

%hook T1URTViewController

- (UISwipeActionsConfiguration*)tableView:(UITableView*)tableView
    trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath*)indexPath {
    UISwipeActionsConfiguration* original = %orig;
    if (!NFBNotifsEnabled()) {
        return original;
    }
    id model = NFBModelAtIndexPath(self, indexPath);
    // Only rows that carry a notification, and only ones we can name — a row
    // we cannot identify could never be unhidden, so it is left alone.
    NSString* modelClass = NSStringFromClass([model class]);
    if (![modelClass containsString:@"Notification"] || !NFBNotifIdentity(model)) {
        return original;
    }

    NSString* title = [[BHTBundle sharedBundle] localizedStringForKey:@"NOTIFS_HIDE_ACTION"];
    UIContextualAction* hide = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleDestructive
                            title:title
                          handler:^(__unused UIContextualAction* action,
                                    __unused UIView* sourceView,
                                    void (^completion)(BOOL)) {
            NSString* identity = NFBNotifIdentity(model);
            NFBHideNotif(model);
            completion(YES);
            nfbReapplyTimelineFilter();
            NFBShowNotifToast(identity);
        }];
    hide.backgroundColor = [UIColor systemGrayColor];
    UIImage* glyph = [UIImage systemImageNamed:@"eye.slash.fill"];
    if (glyph) {
        hide.image = glyph;
    }

    NSMutableArray<UIContextualAction*>* actions = [NSMutableArray arrayWithObject:hide];
    if (original.actions.count) {
        [actions addObjectsFromArray:original.actions];
    }
    UISwipeActionsConfiguration* configuration =
        [UISwipeActionsConfiguration configurationWithActions:actions];
    configuration.performsFirstActionWithFullSwipe = NO;  // a full swipe never hides by accident
    return configuration;
}

%end

// MARK: - Keeping them out of the list
//
// Same shape as Hidden Threads: filter the sections on their way in. An id in
// the registry can only belong to a notification we hid, so no other screen can
// match — the filter needs no scoping of its own.

// True when the batch carries at least one notification model — checked on the
// first few items only, so the hot path stays cheap.
static BOOL NFBSectionsAreNotifications(NSArray* sections) {
    NSInteger looked = 0;
    for (id section in sections) {
        NSArray* items = nil;
        if ([section respondsToSelector:@selector(items)]) {
            id maybe = ((id (*)(id, SEL))objc_msgSend)(section, @selector(items));
            if ([maybe isKindOfClass:[NSArray class]]) {
                items = maybe;
            }
        }
        for (id item in items) {
            id model = unwrapDataViewItem(item);
            if ([NSStringFromClass([model class]) containsString:@"Notification"]) {
                return YES;
            }
            if (++looked > 8) {
                return NO;
            }
        }
    }
    return NO;
}

static NSArray* NFBFilterNotifSections(NSArray* sections) {
    if (!NFBNotifsEnabled()) {
        return sections;
    }
    if (!NFBHiddenNotifs().count) {
        return sections;
    }
    NSMutableArray* result = [NSMutableArray arrayWithCapacity:sections.count];
    BOOL changed = NO;
    for (id section in sections) {
        NSArray* items = nil;
        if ([section respondsToSelector:@selector(items)]) {
            id maybe = ((id (*)(id, SEL))objc_msgSend)(section, @selector(items));
            if ([maybe isKindOfClass:[NSArray class]]) {
                items = maybe;
            }
        }
        if (!items.count) {
            [result addObject:section];
            continue;
        }
        NSMutableArray* kept = [NSMutableArray arrayWithCapacity:items.count];
        for (id item in items) {
            if (NFBNotifIsHidden(unwrapDataViewItem(item))) {
                changed = YES;
                continue;
            }
            [kept addObject:item];
        }
        if (kept.count == items.count) {
            [result addObject:section];
            continue;
        }
        SEL setItems = NSSelectorFromString(@"setItems:");
        if ([section respondsToSelector:setItems]) {
            ((void (*)(id, SEL, id))objc_msgSend)(section, setItems, kept);
            [result addObject:section];
        } else {
            [result addObject:section];  // immutable section: leave it whole
        }
    }
    return changed ? result : sections;
}

%hook T1URTViewController

- (void)setSections:(NSArray*)sections restoreScrollPosition:(BOOL)restore {
    if (NFBSectionsAreNotifications(sections)) {
        // Cast and assign only — T1URTViewController is not declared in the
        // headers, so it must never be sent a message (the Logos rule that
        // broke a build once: "receiver type is a forward declaration").
        gNFBNotifScreen = (UIViewController*)self;
    }
    %orig(NFBFilterNotifSections(sections), restore);
}

%end

// MARK: - Quick access, the pattern he validated for muted words
//
// Scoping is the whole difficulty of a bar button (TFNNavigationBar is generic
// — every screen has one). Rather than guess the notifications screen's class
// name, the screen NAMES ITSELF: the filter above runs on it, so it records the
// controller it saw. A bar then belongs to notifications when its owner is that
// controller or one of its ancestors. If nothing matches, no button is added —
// best effort, never destructive, and the list stays reachable from Settings.

static UIViewController* NFBOwningVC(UIView* view) {
    UIResponder* responder = view;
    NSInteger hops = 0;
    while (responder && hops < 40) {
        if ([responder isKindOfClass:[UIViewController class]]) {
            return (UIViewController*)responder;
        }
        responder = responder.nextResponder;
        hops++;
    }
    return nil;
}

static BOOL NFBBarBelongsToNotifs(UIView* bar) {
    UIViewController* screen = gNFBNotifScreen;
    if (!screen || !screen.view.window) {
        return NO;
    }
    UIViewController* owner = NFBOwningVC(bar);
    if (!owner) {
        return NO;
    }
    UIViewController* node = screen;
    NSInteger hops = 0;
    while (node && hops < 12) {
        if (node == owner) {
            return YES;
        }
        node = node.parentViewController;
        hops++;
    }
    return NO;
}

static const char* kNFBNotifButtonKey = "nfbNotifQuickButton";

@interface NFBNotifQuickButton : UIButton
@end
@implementation NFBNotifQuickButton
@end

@interface NFBNotifQuickPresenter : NSObject
+ (instancetype)shared;
- (void)present:(UIButton*)sender;
@end

@implementation NFBNotifQuickPresenter

+ (instancetype)shared {
    static NFBNotifQuickPresenter* instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[NFBNotifQuickPresenter alloc] init];
    });
    return instance;
}

- (void)present:(UIButton*)sender {
    Class screenClass = NSClassFromString(@"HiddenNotificationsViewController");
    if (!screenClass) {
        return;
    }
    id allocated = [screenClass alloc];
    id screen = ((id (*)(id, SEL))objc_msgSend)(allocated,
                                                NSSelectorFromString(@"initCompact"));
    UIViewController* controller = screen;
    if (!controller) {
        return;
    }
    controller.modalPresentationStyle = UIModalPresentationPopover;
    controller.popoverPresentationController.sourceView = sender;
    controller.popoverPresentationController.sourceRect = sender.bounds;
    controller.popoverPresentationController.permittedArrowDirections =
        UIPopoverArrowDirectionUp;
    controller.popoverPresentationController.delegate = (id)self;

    UIViewController* host = NFBOwningVC(sender);
    while (host.presentedViewController) {
        host = host.presentedViewController;
    }
    [host presentViewController:controller animated:YES completion:nil];
}

// Without this a popover becomes full screen on iPhone.
- (UIModalPresentationStyle)adaptivePresentationStyleForPresentationController:
    (__unused UIPresentationController*)controller {
    return UIModalPresentationNone;
}

@end

%hook TFNNavigationBar

- (void)layoutSubviews {
    %orig;
    UIView* bar = (UIView*)self;
    if (!NFBNotifsEnabled()) {
        return;
    }
    NFBNotifQuickButton* button = objc_getAssociatedObject(bar, kNFBNotifButtonKey);
    if (!button) {
        // The scoping test governs the DECISION TO INSTALL only — never the
        // upkeep. Re-testing it on every layout is what made the muted-words
        // button flicker away when the responder chain was briefly incomplete.
        if (!NFBBarBelongsToNotifs(bar)) {
            return;
        }
        button = [NFBNotifQuickButton buttonWithType:UIButtonTypeSystem];
        UIImage* glyph = nil;
        if ([UIImage respondsToSelector:@selector(tfn_vectorImageNamed:fitsSize:fillColor:)]) {
            glyph = [UIImage tfn_vectorImageNamed:@"eye_off"
                                         fitsSize:CGSizeMake(26, 26)
                                        fillColor:[UIColor secondaryLabelColor]];
        }
        glyph = glyph ? [glyph imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
                      : [UIImage systemImageNamed:@"eye.slash"];
        [button setImage:glyph forState:UIControlStateNormal];
        button.tintColor = [UIColor secondaryLabelColor];
        [button addTarget:[NFBNotifQuickPresenter shared]
                      action:@selector(present:)
            forControlEvents:UIControlEventTouchUpInside];
        [bar addSubview:button];
        objc_setAssociatedObject(bar, kNFBNotifButtonKey, button,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NFBDebugLog(@"notifhide: bouton quick access posé");
    }
    [bar bringSubviewToFront:button];
    // Aligned on the avatar the way the muted-words button is: centring in the
    // bar's own bounds does not work, the bar is taller than its content.
    CGFloat side = 34.0;
    CGFloat centreY = CGRectGetMidY(bar.bounds);
    for (UIView* sub in bar.subviews) {
        if (sub == button || sub.hidden || sub.bounds.size.width <= 0) {
            continue;
        }
        CGFloat width = sub.bounds.size.width;
        CGFloat height = sub.bounds.size.height;
        if (fabs(width - height) < 2 && width >= 24 && width <= 44) {
            centreY = CGRectGetMidY(sub.frame);
            break;
        }
    }
    button.frame = CGRectMake(bar.bounds.size.width - side - 52.0,
                              centreY - side / 2.0, side, side);
}

%end
