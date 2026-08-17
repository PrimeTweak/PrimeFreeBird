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

// Call counters for the blind-spot report (UIKit calls only; our own
// self-test calls are excluded by the flag).
static NSInteger gNFBNotifCanEditCalls;
static NSInteger gNFBNotifSwipeCalls;
static BOOL gNFBNotifSelfTesting;   // tells our own calls apart from UIKit's


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
    // Measured, 18:20:17 — this model exposes exactly six selectors:
    // description, scribeComponent, scribeElement, scribeItem,
    // scribeItemImpressionID, init. So the identifier is a scribe one; the
    // usual entryId/id names simply do not exist here. scribeItem is tried
    // first (an object that may carry a stabler id), then the impression id.
    NSArray<NSString*>* candidates = @[
        @"scribeItemImpressionID", @"scribeItemImpressionId",
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
    // One level into scribeItem: the wrapper may hold the durable id.
    id scribeItem = NFBNotifAsk(model, NSSelectorFromString(@"scribeItem"));
    if (scribeItem && ![scribeItem isKindOfClass:[NSString class]]) {
        NSArray<NSString*>* inner = @[@"entryId", @"entryID", @"id", @"itemId",
                                      @"itemID", @"restId", @"identifier",
                                      @"impressionId", @"impressionID"];
        for (NSString* name in inner) {
            NSString* value = NFBNotifString(NFBNotifAsk(scribeItem,
                                                         NSSelectorFromString(name)));
            if (value.length) {
                NFBDebugLog(@"notifhide: identité via scribeItem.%@", name);
                return [@"si:" stringByAppendingString:value];
            }
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
    // An impression id is not guaranteed to survive a refresh. Rather than
    // assume either way, the identity seen while FILTERING is journaled twice:
    // if a hidden notification ever comes back, comparing these lines with
    // « masquée <…> » says at once whether the id changed between two
    // displays — no probe build needed.
    static NSInteger noted;
    if (identity.length && noted < 2) {
        noted++;
        NFBDebugLog(@"notifhide: identité vue au filtre <%@>", identity);
    }
    return identity.length && hidden[identity] != nil;
}


// This view model carries no text either (same measurement), so the wording
// shown in the hidden list is read from the CELL at the moment of hiding —
// its labels are the only place the notification's words exist.
static NSString* NFBNotifTextFromCell(UITableView* table, NSIndexPath* indexPath) {
    if (![table isKindOfClass:[UITableView class]] || !indexPath) {
        return nil;
    }
    UITableViewCell* cell = [table cellForRowAtIndexPath:indexPath];
    if (!cell) {
        return nil;
    }
    NSMutableArray<NSString*>* pieces = [NSMutableArray array];
    __block void (^walk)(UIView*, NSInteger);
    walk = ^(UIView* view, NSInteger depth) {
        if (!view || depth > 6 || pieces.count >= 3) {
            return;
        }
        if (view.hidden || view.alpha < 0.05) {
            return;
        }
        NSString* found = nil;
        if ([view isKindOfClass:[UILabel class]]) {
            found = ((UILabel*)view).text;
        } else {
            for (NSString* name in @[@"text", @"attributedText"]) {
                SEL selector = NSSelectorFromString(name);
                if (![view respondsToSelector:selector]) {
                    continue;
                }
                NSMethodSignature* signature = [view methodSignatureForSelector:selector];
                if (!signature.methodReturnType ||
                    strcmp(signature.methodReturnType, "@") != 0) {
                    continue;
                }
                id value = ((id (*)(id, SEL))objc_msgSend)(view, selector);
                if ([value isKindOfClass:[NSString class]]) {
                    found = value;
                } else if ([value isKindOfClass:[NSAttributedString class]]) {
                    found = ((NSAttributedString*)value).string;
                }
                if (found.length) {
                    break;
                }
            }
        }
        if (found.length > 1 && ![pieces containsObject:found]) {
            [pieces addObject:found];
        }
        for (UIView* sub in view.subviews) {
            walk(sub, depth + 1);
        }
    };
    walk(cell.contentView, 0);
    return pieces.count ? [pieces componentsJoinedByString:@" · "] : nil;
}

static void NFBHideNotifWithText(id model, NSString* cellText) {
    NSString* identity = NFBNotifIdentity(model);
    if (!identity.length) {
        NFBDebugLog(@"notifhide: aucune identité lisible — masquage refusé");
        return;
    }
    NSMutableDictionary* current = [NFBHiddenNotifs() mutableCopy];
    NSString* text = NFBNotifText(model) ?: (cellText ?: @"");
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

static void NFBHideNotif(id model) {
    NFBHideNotifWithText(model, nil);
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

// Ask the CELL. His 18:04 capture proved the delegate is a shared proxy and
// the data source is the controller — but neither « édition autorisée » nor
// « swipe posé » ever appeared, so the row itself is what we fail to read.
// The cell is the one object that certainly holds its own model.
static id NFBModelFromCell(UITableView* table, NSIndexPath* indexPath) {
    if (![table isKindOfClass:[UITableView class]]) {
        return nil;
    }
    UITableViewCell* cell = [table cellForRowAtIndexPath:indexPath];
    if (!cell) {
        return nil;
    }
    NSArray<NSString*>* holders = @[@"viewModel", @"item", @"model", @"dataViewItem",
                                    @"notification", @"timelineItem"];
    for (NSString* name in holders) {
        SEL selector = NSSelectorFromString(name);
        if (![cell respondsToSelector:selector]) {
            continue;
        }
        NSMethodSignature* signature = [cell methodSignatureForSelector:selector];
        if (!signature.methodReturnType || strcmp(signature.methodReturnType, "@") != 0) {
            continue;
        }
        id value = ((id (*)(id, SEL))objc_msgSend)(cell, selector);
        id model = unwrapDataViewItem(value) ?: value;
        if (model) {
            return model;
        }
    }
    return nil;
}

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
    // we cannot identify could never be unhidden, so it is left alone. Each
    // refusal says WHY, once: he reported "no Hide appears", and a silent
    // guard is exactly what makes that impossible to diagnose without another
    // probe build.
    NSString* modelClass = model ? NSStringFromClass([model class]) : @"(rien)";
    if (!model) {
        static BOOL saidNoModel;
        if (!saidNoModel) {
            saidNoModel = YES;
            NFBDebugLog(@"[notifs] swipe: aucun modèle à la ligne %ld/%ld — "
                        @"lecture des sections à revoir",
                        (long)indexPath.section, (long)indexPath.row);
        }
        return original;
    }
    if (![modelClass containsString:@"Notification"]) {
        static NSMutableSet<NSString*>* seenClasses;
        if (!seenClasses) { seenClasses = [NSMutableSet set]; }
        if (![seenClasses containsObject:modelClass] && seenClasses.count < 6) {
            [seenClasses addObject:modelClass];
            NFBDebugLog(@"[notifs] swipe: classe non reconnue « %@ » — pas d'action posée",
                        modelClass);
        }
        return original;
    }
    if (!NFBNotifIdentity(model)) {
        static BOOL saidNoIdentity;
        if (!saidNoIdentity) {
            saidNoIdentity = YES;
            NFBDebugLog(@"[notifs] swipe: %@ sans identité lisible — action refusée",
                        modelClass);
        }
        return original;
    }
    static BOOL saidArmed;
    if (!saidArmed) {
        saidArmed = YES;
        NFBDebugLog(@"[notifs] swipe: action « Masquer » posée sur %@", modelClass);
    }

    NSString* title = [[BHTBundle sharedBundle] localizedStringForKey:@"NOTIFS_HIDE_ACTION"];
    UIContextualAction* hide = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleDestructive
                            title:title
                          handler:^(__unused UIContextualAction* action,
                                    __unused UIView* sourceView,
                                    void (^completion)(BOOL)) {
            NSString* identity = NFBNotifIdentity(model);
            NFBHideNotifWithText(model, NFBNotifTextFromCell(tableView, indexPath));
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

%hook TFNItemsDataViewController

// Safety net, and a measurement in one: if the notifications list is NOT a
// plain T1URTViewController on his build, the hook above never fires and the
// swipe silently does nothing — which is exactly what he reported. This one
// sits on the base class the whole app's lists inherit from, so it fires
// wherever the rows live; it declines immediately unless the row really is a
// notification we can name.
- (UISwipeActionsConfiguration*)tableView:(UITableView*)tableView
    trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath*)indexPath {
    UISwipeActionsConfiguration* original = %orig;
    if (!NFBNotifsEnabled()) {
        return original;
    }
    id dataVC = self;
    if ([NSStringFromClass([dataVC class]) isEqualToString:@"T1URTViewController"]) {
        return original;  // already handled above — never twice
    }
    id model = NFBModelAtIndexPath(dataVC, indexPath);
    if (!model) {
        return original;
    }
    NSString* modelClass = NSStringFromClass([model class]);
    if (![modelClass containsString:@"Notification"] || !NFBNotifIdentity(model)) {
        return original;
    }
    static BOOL saidNet;
    if (!saidNet) {
        saidNet = YES;
        NFBDebugLog(@"[notifs] swipe: posé par le filet sur %@ (classe de liste %@)",
                    modelClass, NSStringFromClass([dataVC class]));
    }

    NSString* title = [[BHTBundle sharedBundle] localizedStringForKey:@"NOTIFS_HIDE_ACTION"];
    UIContextualAction* hide = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleDestructive
                            title:title
                          handler:^(__unused UIContextualAction* action,
                                    __unused UIView* sourceView,
                                    void (^completion)(BOOL)) {
            NSString* identity = NFBNotifIdentity(model);
            NFBHideNotifWithText(model, NFBNotifTextFromCell(tableView, indexPath));
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
    configuration.performsFirstActionWithFullSwipe = NO;
    return configuration;
}

%end

// MARK: - the missing link
//
// He built the previous fix and reported the swipe still doing nothing — AND no
// « swipe: … » line came out of it, although every refusal path was journaled.
// A hook that never speaks is a hook that is never called, so the question is
// not why our action is refused but why UIKit never asks for it.
//
// UIKit's own rule answers it: a table row offers NO swipe actions unless its
// data source allows editing for that row. If Twitter's list answers NO to
// tableView:canEditRowAtIndexPath: — or simply never gets asked because editing
// is off — trailingSwipeActionsConfigurationForRowAtIndexPath: is never called
// at all. That is mechanism, not a guess about their code: it is the documented
// order in which UITableView asks its questions.
//
// So editing is allowed for the rows we can act on, and only those. Everything
// else keeps Twitter's own answer.

static BOOL NFBNotifRowIsOursInTable(id dataViewController, UITableView* table,
                                     NSIndexPath* indexPath);

// The row's model, from the data source or — failing that — from the cell.
static id NFBNotifModelForRow(id dataViewController, UITableView* table,
                              NSIndexPath* indexPath) {
    id model = NFBModelAtIndexPath(dataViewController, indexPath);
    if (!model) {
        model = NFBModelFromCell(table, indexPath);
        if (model) {
            static BOOL said;
            if (!said) {
                said = YES;
                NFBDebugLog(@"[notifs] modèle lu depuis la cellule (%@)",
                            NSStringFromClass([model class]));
            }
        }
    }
    return model;
}

// Every refusal names itself ONCE. Silence was what cost the last three builds.
static BOOL NFBNotifRowIsOursInTable(id dataViewController, UITableView* table,
                                     NSIndexPath* indexPath) {
    if (!NFBNotifsEnabled()) {
        return NO;
    }
    id model = NFBNotifModelForRow(dataViewController, table, indexPath);
    if (!model) {
        static BOOL saidNoModel;
        if (!saidNoModel) {
            saidNoModel = YES;
            NFBDebugLog(@"[notifs] ligne %ld/%ld: AUCUN modèle (source=%@) — "
                        @"ni sections ni cellule",
                        (long)indexPath.section, (long)indexPath.row,
                        NSStringFromClass([dataViewController class]));
        }
        return NO;
    }
    NSString* modelClass = NSStringFromClass([model class]);
    if (![modelClass containsString:@"Notification"]) {
        static NSMutableSet<NSString*>* seen;
        if (!seen) { seen = [NSMutableSet set]; }
        if (![seen containsObject:modelClass] && seen.count < 6) {
            [seen addObject:modelClass];
            NFBDebugLog(@"[notifs] ligne portée par « %@ » — pas reconnue comme notification",
                        modelClass);
        }
        return NO;
    }
    if (!NFBNotifIdentity(model)) {
        static NSMutableSet<NSString*>* dumped;
        if (!dumped) { dumped = [NSMutableSet set]; }
        if (![dumped containsObject:modelClass] && dumped.count < 3) {
            [dumped addObject:modelClass];
            // The runtime knows the real field names; print them rather than
            // guess a fourth list.
            unsigned int count = 0;
            Method* methods = class_copyMethodList([model class], &count);
            NSMutableArray<NSString*>* names = [NSMutableArray array];
            for (unsigned int i = 0; methods && i < count && names.count < 40; i++) {
                NSString* name = NSStringFromSelector(method_getName(methods[i]));
                if ([name containsString:@":"] || [name hasPrefix:@"_"] ||
                    [name hasPrefix:@"."]) {
                    continue;
                }
                [names addObject:name];
            }
            if (methods) { free(methods); }
            NFBDebugLog(@"[notifs] %@ SANS identité — sélecteurs: %@", modelClass,
                        [names componentsJoinedByString:@" "]);
        }
        return NO;
    }
    return YES;
}

%hook T1URTViewController

- (BOOL)tableView:(UITableView*)tableView canEditRowAtIndexPath:(NSIndexPath*)indexPath {
    if (NFBNotifRowIsOursInTable(self, tableView, indexPath)) {
        static BOOL said;
        if (!said) {
            said = YES;
            NFBDebugLog(@"[notifs] édition autorisée sur la liste (le swipe peut apparaître)");
        }
        return YES;
    }
    return %orig;
}

%end

%hook TFNItemsDataViewController

- (BOOL)tableView:(UITableView*)tableView canEditRowAtIndexPath:(NSIndexPath*)indexPath {
    id dataVC = self;
    if ([NSStringFromClass([dataVC class]) isEqualToString:@"T1URTViewController"]) {
        return %orig;  // handled above — never twice
    }
    if (NFBNotifRowIsOursInTable(dataVC, tableView, indexPath)) {
        static BOOL saidNet;
        if (!saidNet) {
            saidNet = YES;
            NFBDebugLog(@"[notifs] édition autorisée par le filet sur %@",
                        NSStringFromClass([dataVC class]));
        }
        return YES;
    }
    return %orig;
}

%end

// MARK: - stop assuming who answers the table
//
// Everything so far hooked the VIEW CONTROLLER, assuming it is the table's own
// data source and delegate. His FLEX capture shows a DataViewHostView sitting
// between T1URTViewController and the TFNTableView, so that assumption was
// never verified — and it explains the total silence: if another object answers
// the table, our methods are simply never consulted.
//
// So nothing is assumed any more. The table is asked who its delegate and data
// source ARE, both names are journaled (the fact that was missing all along),
// and the two methods are installed on THOSE classes:
//   · canEditRowAtIndexPath: on the data source — without it UIKit never even
//     asks for swipe actions;
//   · trailingSwipeActionsConfigurationForRowAtIndexPath: on the delegate.
// Installation uses class_addMethod first and only falls back to replacing an
// implementation the class owns — the exact shape that stopped the recursion
// crash: never swizzle a method a class merely inherits.

static NSMutableDictionary<NSString*, NSValue*>* gNFBNotifOrigCanEdit;
static NSMutableDictionary<NSString*, NSValue*>* gNFBNotifOrigSwipe;

// The object that can actually hand out rows: whichever of these knows about
// sections. Tried in order, no guess.
static id NFBNotifRowSourceFor(id candidate, UITableView* table) {
    SEL sectionsSel = NSSelectorFromString(@"sections");
    SEL itemSel = NSSelectorFromString(@"itemAtIndexPath:");
    id options[3] = { candidate, table.dataSource, table.delegate };
    for (int i = 0; i < 3; i++) {
        id option = options[i];
        if (option && ([option respondsToSelector:sectionsSel] ||
                       [option respondsToSelector:itemSel])) {
            return option;
        }
    }
    UIResponder* responder = table;
    NSInteger hops = 0;
    while ((responder = responder.nextResponder) && hops < 12) {
        if ([responder respondsToSelector:sectionsSel] ||
            [responder respondsToSelector:itemSel]) {
            return responder;
        }
        hops++;
    }
    return candidate;
}

static BOOL nfbNotifCanEdit(id self, SEL _cmd, UITableView* table, NSIndexPath* indexPath) {
    // Binary question, answered once: does the table ask us at all?
    if (!gNFBNotifSelfTesting) {
        gNFBNotifCanEditCalls++;
    }
    if (NFBNotifRowIsOursInTable(NFBNotifRowSourceFor(self, table), table, indexPath)) {
        static BOOL said;
        if (!said) {
            said = YES;
            NFBDebugLog(@"[notifs] édition autorisée par %@ — le swipe peut apparaître",
                        NSStringFromClass([self class]));
        }
        return YES;
    }
    NSValue* boxed = gNFBNotifOrigCanEdit[NSStringFromClass([self class])];
    if (boxed) {
        BOOL (*original)(id, SEL, UITableView*, NSIndexPath*) = [boxed pointerValue];
        return original(self, _cmd, table, indexPath);
    }
    return YES;  // UIKit's own default when nobody implements it
}

static UISwipeActionsConfiguration* nfbNotifTrailingSwipe(id self, SEL _cmd,
                                                          UITableView* table,
                                                          NSIndexPath* indexPath) {
    if (!gNFBNotifSelfTesting) {
        gNFBNotifSwipeCalls++;
    }
    UISwipeActionsConfiguration* original = nil;
    NSValue* boxed = gNFBNotifOrigSwipe[NSStringFromClass([self class])];
    if (boxed) {
        UISwipeActionsConfiguration* (*orig)(id, SEL, UITableView*, NSIndexPath*) =
            [boxed pointerValue];
        original = orig(self, _cmd, table, indexPath);
    }
    id source = NFBNotifRowSourceFor(self, table);
    if (!NFBNotifRowIsOursInTable(source, table, indexPath)) {
        return original;
    }
    id model = NFBNotifModelForRow(source, table, indexPath);
    static BOOL said;
    if (!said) {
        said = YES;
        NFBDebugLog(@"[notifs] swipe: action « Masquer » posée par %@",
                    NSStringFromClass([self class]));
    }

    NSString* title = [[BHTBundle sharedBundle] localizedStringForKey:@"NOTIFS_HIDE_ACTION"];
    UIContextualAction* hide = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleDestructive
                            title:title
                          handler:^(__unused UIContextualAction* action,
                                    __unused UIView* sourceView,
                                    void (^completion)(BOOL)) {
            NSString* identity = NFBNotifIdentity(model);
            NFBHideNotifWithText(model, NFBNotifTextFromCell(table, indexPath));
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
    configuration.performsFirstActionWithFullSwipe = NO;
    return configuration;
}

// Add on the subclass, never replace an inherited implementation (the crash
// lesson). If the class owns the method, its implementation is kept and called.
static void NFBNotifInstall(id target, SEL selector, IMP replacement,
                            const char* types,
                            NSMutableDictionary<NSString*, NSValue*>* store) {
    if (!target) {
        return;
    }
    Class cls = [target class];
    NSString* name = NSStringFromClass(cls);
    if (store[name]) {
        return;  // already done for this class
    }
    Method owned = class_getInstanceMethod(cls, selector);
    BOOL ownsIt = owned && class_getMethodImplementation(class_getSuperclass(cls), selector)
                            != method_getImplementation(owned);
    if (!ownsIt && class_addMethod(cls, selector, replacement, types)) {
        IMP inherited = owned ? method_getImplementation(owned) : NULL;
        store[name] = [NSValue valueWithPointer:inherited];
        NFBDebugLog(@"[notifs] méthode ajoutée à %@ (%@)", name, NSStringFromSelector(selector));
        return;
    }
    if (owned) {
        IMP previous = method_setImplementation(owned, replacement);
        store[name] = [NSValue valueWithPointer:previous];
        NFBDebugLog(@"[notifs] méthode remplacée sur %@ (%@)", name,
                    NSStringFromSelector(selector));
    }
}

static void NFBNotifRefreshDelegateCache(UITableView* table) {
    if (![table isKindOfClass:[UITableView class]]) {
        return;
    }
    static const char* kNFBNotifRefreshedKey = "nfbNotifRefreshed";
    if (objc_getAssociatedObject(table, kNFBNotifRefreshedKey)) {
        return;   // once per table: re-assigning marks the table for reload
    }
    objc_setAssociatedObject(table, kNFBNotifRefreshedKey, @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    id delegate = table.delegate;
    id dataSource = table.dataSource;
    if (delegate) {
        table.delegate = nil;
        table.delegate = delegate;
    }
    if (dataSource) {
        table.dataSource = nil;
        table.dataSource = dataSource;
    }
    NFBDebugLog(@"[notifs] cache du delegate reconstruit (%@)",
                NSStringFromClass([table class]));
}


// MARK: - THE BLIND-SPOT REPORT
//
// His fair criticism, and it lands: I was testing ONE hypothesis per build.
// This prints every link in the chain at once, so a single capture says which
// one is broken instead of costing another round trip. The two angles I had
// never even looked at are numbers 8 and 9 — the notifications list lives
// inside a HORIZONTAL pager (All / Mentions), and a left swipe is a horizontal
// gesture: if the pager's pan wins, the table never sees the swipe at all, no
// matter how perfect the delegate wiring is.

static NSString* NFBNotifGestureList(UIView* view) {
    NSMutableArray<NSString*>* names = [NSMutableArray array];
    for (UIGestureRecognizer* gesture in view.gestureRecognizers) {
        [names addObject:[NSString stringWithFormat:@"%@%@",
                          NSStringFromClass([gesture class]),
                          gesture.isEnabled ? @"" : @"(off)"]];
        if (names.count >= 4) { break; }
    }
    return names.count ? [names componentsJoinedByString:@","] : @"-";
}

static void NFBNotifDiagnose(UITableView* table) {
    if (![table isKindOfClass:[UITableView class]] || !table.window) {
        return;
    }
    id delegate = table.delegate;
    id dataSource = table.dataSource;
    SEL swipeSel = @selector(tableView:trailingSwipeActionsConfigurationForRowAtIndexPath:);
    SEL editSel = @selector(tableView:canEditRowAtIndexPath:);
    NSIndexPath* probe = [NSIndexPath indexPathForRow:0 inSection:0];

    NFBDebugLog(@"===== [notifs] RAPPORT ANGLES MORTS =====");

    // 1 — the toggle, raw value included: a silent NO disables everything.
    id rawToggle = [[NSUserDefaults standardUserDefaults] objectForKey:kNFBHideNotifsEnabledKey];
    NFBDebugLog(@"1. toggle hide_notifications = %@ | actif: %@",
                rawToggle ?: @"(absent)", NFBNotifsEnabled() ? @"OUI" : @"NON");

    // 2 — the table itself.
    NFBDebugLog(@"2. table %@ | editing=%d | lignes s0=%ld | gestes: %@",
                NSStringFromClass([table class]), table.isEditing,
                (long)[table numberOfRowsInSection:0], NFBNotifGestureList(table));

    // 3/4 — do the two objects admit our methods, and is OUR implementation
    // the one actually installed on their class?
    IMP swipeIMP = class_getMethodImplementation([delegate class], swipeSel);
    IMP editIMP = class_getMethodImplementation([dataSource class], editSel);
    NFBDebugLog(@"3. delegate %@ | répond=%@ | notre IMP=%@",
                NSStringFromClass([delegate class]),
                [delegate respondsToSelector:swipeSel] ? @"OUI" : @"NON",
                swipeIMP == (IMP)nfbNotifTrailingSwipe ? @"OUI" : @"NON");
    NFBDebugLog(@"4. dataSource %@ | répond=%@ | notre IMP=%@",
                NSStringFromClass([dataSource class]),
                [dataSource respondsToSelector:editSel] ? @"OUI" : @"NON",
                editIMP == (IMP)nfbNotifCanEdit ? @"OUI" : @"NON");

    // 5/6 — SELF TEST: call the two methods ourselves. If they work when WE
    // call them but UIKit never does, the wiring is sound and the problem is
    // upstream (cache, proxy, or a gesture stealing the swipe).
    gNFBNotifSelfTesting = YES;
    NSInteger canEditBefore = gNFBNotifCanEditCalls;
    BOOL editable = NO;
    if ([dataSource respondsToSelector:editSel]) {
        editable = ((BOOL (*)(id, SEL, id, id))objc_msgSend)(dataSource, editSel, table, probe);
    }
    NFBDebugLog(@"5. auto-test canEdit(0,0) = %@ | notre code atteint: %@",
                editable ? @"YES" : @"NO",
                gNFBNotifCanEditCalls > canEditBefore ? @"OUI" : @"NON");

    NSInteger swipeBefore = gNFBNotifSwipeCalls;
    id configuration = nil;
    if ([delegate respondsToSelector:swipeSel]) {
        configuration = ((id (*)(id, SEL, id, id))objc_msgSend)(delegate, swipeSel, table, probe);
    }
    NFBDebugLog(@"6. auto-test swipe(0,0) = %ld action(s) | notre code atteint: %@",
                (long)[[configuration valueForKey:@"actions"] count],
                gNFBNotifSwipeCalls > swipeBefore ? @"OUI" : @"NON");
    gNFBNotifSelfTesting = NO;

    // 7 — the row itself: model and computed identity, values included.
    id model = NFBNotifModelForRow(NFBNotifRowSourceFor(dataSource, table), table, probe);
    NFBDebugLog(@"7. ligne 0: modèle=%@ | identité=%@",
                model ? NSStringFromClass([model class]) : @"(aucun)",
                NFBNotifIdentity(model) ?: @"(aucune)");

    // 8 — the cell: anything here can swallow a horizontal drag.
    UITableViewCell* cell = [table cellForRowAtIndexPath:probe];
    NFBDebugLog(@"8. cellule %@ | interaction=%d | gestes: %@",
                cell ? NSStringFromClass([cell class]) : @"(aucune)",
                cell.isUserInteractionEnabled, NFBNotifGestureList(cell));

    // 9 — THE ANGLE I NEVER LOOKED AT: the ancestors. This screen sits in a
    // horizontal pager; if its pan recogniser claims the gesture, no delegate
    // work of ours can ever matter.
    UIView* node = table.superview;
    NSInteger depth = 0;
    while (node && depth < 6) {
        if (node.gestureRecognizers.count) {
            NFBDebugLog(@"9.%ld ancêtre %@ | gestes: %@", (long)depth,
                        NSStringFromClass([node class]), NFBNotifGestureList(node));
        }
        node = node.superview;
        depth++;
    }

    // 10 — who has actually called us so far (UIKit only; self-tests excluded).
    NFBDebugLog(@"10. appels reçus d'UIKit — canEdit=%ld swipe=%ld",
                (long)gNFBNotifCanEditCalls, (long)gNFBNotifSwipeCalls);
    NFBDebugLog(@"===== fin du rapport =====");
}

static void NFBNotifWireTable(UITableView* table) {
    if (!NFBNotifsEnabled() || !table) {
        return;
    }
    static NSMutableSet<NSString*>* announced;
    if (!announced) { announced = [NSMutableSet set]; }
    if (!gNFBNotifOrigCanEdit) { gNFBNotifOrigCanEdit = [NSMutableDictionary dictionary]; }
    if (!gNFBNotifOrigSwipe) { gNFBNotifOrigSwipe = [NSMutableDictionary dictionary]; }

    id delegate = table.delegate;
    id dataSource = table.dataSource;
    NSString* pair = [NSString stringWithFormat:@"%@|%@",
                      NSStringFromClass([delegate class]),
                      NSStringFromClass([dataSource class])];
    if (![announced containsObject:pair] && announced.count < 8) {
        [announced addObject:pair];
        // The fact that was missing since the first attempt.
        NFBDebugLog(@"[notifs] table %@ — delegate=%@ dataSource=%@",
                    NSStringFromClass([table class]),
                    NSStringFromClass([delegate class]),
                    NSStringFromClass([dataSource class]));
    }

    NFBNotifInstall(dataSource, @selector(tableView:canEditRowAtIndexPath:),
                    (IMP)nfbNotifCanEdit, "B@:@@", gNFBNotifOrigCanEdit);
    NFBNotifInstall(delegate,
                    @selector(tableView:trailingSwipeActionsConfigurationForRowAtIndexPath:),
                    (IMP)nfbNotifTrailingSwipe, "@@:@@", gNFBNotifOrigSwipe);

    // MEASUREMENT, not theory. Two competing explanations for ten silent
    // builds — the table caches what its delegate answers, OR the delegate is
    // a proxy that forwards respondsToSelector: elsewhere and therefore denies
    // knowing our method. This line settles it on the spot: after installing,
    // ASK the delegate whether it now recognises the selector.
    //   répond=OUI  → the object admits the method; if the swipe still never
    //                 fires, the cache is the culprit.
    //   répond=NON  → the proxy denies it; the cache is innocent and the fix
    //                 belongs on respondsToSelector:.
    SEL swipeSel = @selector(tableView:trailingSwipeActionsConfigurationForRowAtIndexPath:);
    SEL editSel = @selector(tableView:canEditRowAtIndexPath:);
    NFBDebugLog(@"[notifs] MESURE — delegate %@ répond au swipe: %@ | dataSource %@ "
                @"répond à canEdit: %@",
                NSStringFromClass([delegate class]),
                [delegate respondsToSelector:swipeSel] ? @"OUI" : @"NON",
                NSStringFromClass([dataSource class]),
                [dataSource respondsToSelector:editSel] ? @"OUI" : @"NON");

    NFBNotifRefreshDelegateCache(table);

    // The report runs once the layout has settled — and again on every later
    // visit, so the call counters show what happened during his gestures.
    __weak UITableView* weakTable = table;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        NFBNotifDiagnose(weakTable);
    });
}

%hook TFNTableView

// The notifications table, named by his FLEX capture. Wiring happens once per
// class pair, and only where a row of ours can exist.
- (void)didMoveToWindow {
    %orig;
    UIView* table = (UIView*)self;
    if (table.window) {
        NFBNotifWireTable((UITableView*)self);
    }
}

%end

// MARK: - the cache nobody mentions
//
// Ten builds in, everything was installed and nothing was ever asked. The
// missing fact is UIKit's own: a UITableView interrogates its delegate and its
// data source ONCE — when they are assigned — and caches which optional methods
// they answer. Adding a method afterwards changes nothing: the table never asks
// again. Our methods existed; the table did not know they did.
//
// Two consequences, both handled here:
//   · install BEFORE the assignment (the setter hooks below), so the cache is
//     built with our methods already in place;
//   · for a table already wired, re-assign delegate and data source once, which
//     is the documented way to make the table rebuild that cache.


%hook UITableView

// Installing here means the cache below is built WITH our methods present —
// the ordering that the whole feature was missing.
- (void)setDelegate:(id)delegate {
    if (delegate && NFBNotifsEnabled()) {
        if (!gNFBNotifOrigSwipe) { gNFBNotifOrigSwipe = [NSMutableDictionary dictionary]; }
        NFBNotifInstall(delegate,
                        @selector(tableView:trailingSwipeActionsConfigurationForRowAtIndexPath:),
                        (IMP)nfbNotifTrailingSwipe, "@@:@@", gNFBNotifOrigSwipe);
    }
    %orig;
}

- (void)setDataSource:(id)dataSource {
    if (dataSource && NFBNotifsEnabled()) {
        if (!gNFBNotifOrigCanEdit) { gNFBNotifOrigCanEdit = [NSMutableDictionary dictionary]; }
        NFBNotifInstall(dataSource, @selector(tableView:canEditRowAtIndexPath:),
                        (IMP)nfbNotifCanEdit, "B@:@@", gNFBNotifOrigCanEdit);
    }
    %orig;
}

%end
