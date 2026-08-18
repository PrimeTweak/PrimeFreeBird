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
    // Printed while the registry is not empty: comparing this value with the
    // « menu: masquée <…> » line says at once whether the impression id is the
    // same between two displays — the one risk flagged when it was chosen.
    static NSInteger noted;
    if (identity.length && hidden.count && noted < 4) {
        noted++;
        NFBDebugLog(@"notifhide: identité vue au filtre <%@> | %@",
                    identity, hidden[identity] ? @"TROUVÉE → masquée" : @"absente du registre");
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
    __block __weak void (^weakWalk)(UIView*, NSInteger);
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
            void (^w)(UIView*, NSInteger) = weakWalk; if (w) { w(sub, depth + 1); }
        }
    };    weakWalk = walk;

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
    // His call: the toast stays where it is, but the navigation title was
    // reading through the text. The material alone is too thin, so a veil at
    // 80 % sits behind the content — enough to stop the title, thin enough to
    // still let the background breathe, which is what he asked for.
    toast.layer.shadowColor = [UIColor blackColor].CGColor;
    toast.layer.shadowOpacity = 0.16;
    toast.layer.shadowRadius = 10.0;
    toast.layer.shadowOffset = CGSizeMake(0, 4);
    [window addSubview:toast];

    UIView* content = toast.contentView;

    UIView* veil = [[UIView alloc] init];
    veil.backgroundColor = [[UIColor systemBackgroundColor] colorWithAlphaComponent:0.80];
    veil.userInteractionEnabled = NO;
    veil.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:veil];
    [NSLayoutConstraint activateConstraints:@[
        [veil.topAnchor constraintEqualToAnchor:content.topAnchor],
        [veil.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
        [veil.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [veil.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
    ]];

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


// Measured in the binary: TFNItemsDataViewController implements
// -deleteItemAtIndexPath:withRowAnimation:. So a hidden row leaves the list on
// the spot, instead of hoping a sections replay reaches this screen — which is
// what never happened. The registry + filter still handle later reloads.
static void NFBNotifDropRow(id dataViewController, NSIndexPath* indexPath) {
    if (!dataViewController || !indexPath) {
        return;
    }
    @try {
        SEL deleteSel = NSSelectorFromString(@"deleteItemAtIndexPath:withRowAnimation:");
        if ([dataViewController respondsToSelector:deleteSel]) {
            ((void (*)(id, SEL, id, NSInteger))objc_msgSend)(
                dataViewController, deleteSel, indexPath, UITableViewRowAnimationLeft);
            NFBDebugLog(@"[notifs] ligne retirée de la liste (%ld/%ld)",
                        (long)indexPath.section, (long)indexPath.row);
            return;
        }
        NFBDebugLog(@"[notifs] suppression directe indisponible sur %@",
                    NSStringFromClass([dataViewController class]));
    } @catch (id exception) {
        NFBDebugLog(@"[notifs] suppression directe refusée — la ligne partira au rechargement");
    }
}

%hook T1URTViewController

- (UISwipeActionsConfiguration*)tableView:(UITableView*)tableView
    trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath*)indexPath {
    UISwipeActionsConfiguration* original = %orig;
    if (!NFBNotifsEnabled()) {
        return original;
    }
    id model = NFBModelAtIndexPath(self, indexPath) ?: NFBModelFromCell(tableView, indexPath);
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
            NFBNotifDropRow(self, indexPath);
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

// Measured: T1URTViewController implements NEITHER -sections NOR -setSections:.
// Both are inherited from TFNItemsDataViewController, so the filter belongs
// there — hooking the subclass meant it could never speak.
%hook TFNItemsDataViewController

- (void)setSections:(NSArray*)sections restoreScrollPosition:(BOOL)restore {
    if (NFBSectionsAreNotifications(sections)) {
        gNFBNotifScreen = (UIViewController*)self;
    }
    %orig(NFBFilterNotifSections(sections), restore);
}

- (void)setSections:(NSArray*)sections {
    if (NFBSectionsAreNotifications(sections)) {
        gNFBNotifScreen = (UIViewController*)self;
    }
    %orig(NFBFilterNotifSections(sections));
}

- (void)updateSections:(NSArray*)sections {
    if (NFBSectionsAreNotifications(sections)) {
        gNFBNotifScreen = (UIViewController*)self;
    }
    %orig(NFBFilterNotifSections(sections));
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



static const NSInteger kNFBNotifBarItemTag = 90314;
static const CGFloat kNFBNotifEyeSide = 24.0;   // cote validée: comme l'engrenage

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

// The sender is now a UIBarButtonItem — the bar's own kind of button, since we
// go through Twitter's real door. A bar item is NOT a view: it answers neither
// -bounds nor -nextResponder, and asking it either is an unrecognised selector,
// i.e. the crash on tap. Both kinds are handled here, and the host controller no
// longer comes from the sender at all.
- (void)present:(id)sender {
    Class screenClass = NSClassFromString(@"HiddenNotificationsViewController");
    if (!screenClass) {
        return;
    }
    @try {
        id allocated = [screenClass alloc];
        id screen = ((id (*)(id, SEL))objc_msgSend)(allocated,
                                                    NSSelectorFromString(@"initCompact"));
        UIViewController* controller = screen;
        if (!controller) {
            return;
        }
        controller.modalPresentationStyle = UIModalPresentationPopover;
        UIPopoverPresentationController* popover =
            controller.popoverPresentationController;
        if ([sender isKindOfClass:[UIBarButtonItem class]]) {
            popover.barButtonItem = sender;          // anchors itself, no bounds needed
        } else if ([sender isKindOfClass:[UIView class]]) {
            popover.sourceView = sender;
            popover.sourceRect = ((UIView*)sender).bounds;
        }
        popover.permittedArrowDirections = UIPopoverArrowDirectionUp;
        popover.delegate = (id)self;

        // Host: the visible controller of the key window — never derived from
        // the sender, which is exactly what blew up.
        UIWindow* window = nil;
        for (UIScene* scene in [UIApplication sharedApplication].connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) {
                continue;
            }
            for (UIWindow* candidate in ((UIWindowScene*)scene).windows) {
                if (candidate.isKeyWindow) {
                    window = candidate;
                    break;
                }
                if (!window) {
                    window = candidate;
                }
            }
            if (window.isKeyWindow) {
                break;
            }
        }
        UIViewController* host = window.rootViewController;
        while (host.presentedViewController) {
            host = host.presentedViewController;
        }
        if (!host) {
            NFBDebugLog(@"[notifs] aucun écran hôte pour la liste — présentation annulée");
            return;
        }
        [host presentViewController:controller animated:YES completion:nil];
        NFBDebugLog(@"[notifs] liste des masquées présentée depuis %@",
                    NSStringFromClass([host class]));
    } @catch (id exception) {
        NFBDebugLog(@"[notifs] présentation de la liste abandonnée — sans conséquence");
    }
}

// Without this a popover becomes full screen on iPhone.
- (UIModalPresentationStyle)adaptivePresentationStyleForPresentationController:
    (__unused UIPresentationController*)controller {
    return UIModalPresentationNone;
}

@end


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

// MARK: - recognising one of our rows
//
// Measured in the binary, and it corrects everything I assumed earlier:
// tableView:canEditRowAtIndexPath: is implemented ONLY by T1AccountsViewController
// and T1TweetDraftsViewController — never by the notifications list. Nobody was
// refusing the swipe; I was forcing an answer to a question no one asked, on a
// method that did not exist. That whole apparatus is gone.

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

// MARK: - the eye, through the door Twitter actually uses
//
// Measured in the binary: the right-hand bar buttons are provided by
//   T1TabNavigationController
//     -_t1_main_updateNavigationItemForViewController:isRoot:
//        providingLeftBarButtonItems:rightBarButtonItems:
// My previous attempt bolted a subview onto TFNNavigationBar and depended on a
// three-link chain that silently failed. This one adds a proper bar button
// item where Twitter adds its own, and only for the notifications screen —
// recognised by the class name read from the binary, not guessed.

%hook T1TabNavigationController

- (void)_t1_main_updateNavigationItemForViewController:(UIViewController*)viewController
                                                isRoot:(BOOL)isRoot
                           providingLeftBarButtonItems:(BOOL)left
                                 rightBarButtonItems:(BOOL)right {
    %orig;
    if (!NFBNotifsEnabled() || !viewController) {
        return;
    }
    @try {
        if (![NSStringFromClass([viewController class])
                containsString:@"NotificationsViewController"]) {
            return;
        }
        UINavigationItem* item = viewController.navigationItem;
        for (UIBarButtonItem* existing in item.rightBarButtonItems) {
            if (existing.tag == kNFBNotifBarItemTag) {
                return;   // already there
            }
        }
        UIImage* glyph = nil;
        if ([UIImage respondsToSelector:@selector(tfn_vectorImageNamed:fitsSize:fillColor:)]) {
            glyph = [UIImage tfn_vectorImageNamed:@"eye_off"
                                         fitsSize:CGSizeMake(24, 24)
                                        fillColor:[UIColor labelColor]];
        }
        glyph = glyph ? [glyph imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
                      : [UIImage systemImageNamed:@"eye.slash"];
        UIBarButtonItem* ours =
            [[UIBarButtonItem alloc] initWithImage:glyph
                                             style:UIBarButtonItemStylePlain
                                            target:[NFBNotifQuickPresenter shared]
                                            action:@selector(present:)];
        ours.tag = kNFBNotifBarItemTag;

        // He asked for the glass pastille behind the eye to go, position and
        // size unchanged. Two routes, tried in order in the same build so he
        // never has to compile twice:
        //
        //   1. the bar's own opt-out, when the system offers it;
        //   2. a custom view, which is what Twitter itself uses for the gear
        //      next to us (measured: TFNBarButtonItemButton, not a bare image)
        //      — a custom view gets no shared background at all.
        BOOL glassRefused = NO;
        SEL hideShared = NSSelectorFromString(@"setHidesSharedBackground:");
        if ([ours respondsToSelector:hideShared]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(ours, hideShared, YES);
            glassRefused = YES;
        }
        if (!glassRefused) {
            UIButton* plain = [UIButton buttonWithType:UIButtonTypeSystem];
            [plain setImage:glyph forState:UIControlStateNormal];
            plain.tintColor = [UIColor labelColor];
            plain.frame = CGRectMake(0, 0, kNFBNotifEyeSide, kNFBNotifEyeSide);
            [plain addTarget:[NFBNotifQuickPresenter shared]
                      action:@selector(present:)
            forControlEvents:UIControlEventTouchUpInside];
            ours = [[UIBarButtonItem alloc] initWithCustomView:plain];
            ours.tag = kNFBNotifBarItemTag;
        }
        NFBDebugLog(@"[notifs] œil sans verre — voie %@",
                    glassRefused ? @"1 (refus du fond partagé)" : @"2 (vue personnalisée)");
        NSMutableArray<UIBarButtonItem*>* items =
            [NSMutableArray arrayWithArray:item.rightBarButtonItems ?: @[]];
        [items addObject:ours];          // after Twitter's own (the gear)
        item.rightBarButtonItems = items;
        static BOOL said;
        if (!said) {
            said = YES;
            NFBDebugLog(@"[notifs] œil posé dans la barre de %@ (%lu bouton(s))",
                        NSStringFromClass([viewController class]),
                        (unsigned long)items.count);
        }
    } @catch (id exception) {
        NFBDebugLog(@"[notifs] pose de l'œil abandonnée — sans conséquence");
    }
}

%end

// MARK: - the button that was already there
//
// Measured in the binary, and visible in his own FLEX capture all along:
//   T1URTTimelineNotificationCell  ->  dismissButton, setDismissButton:,
//                                      dismissButtonWasTapped, layoutSubviews
//   the cell already holds a TFNDismissButton at {413, 12}, 18x18 — HIDDEN.
//
// So Twitter ships a dismiss button on every notification row and simply keeps
// it hidden. Revealing it costs nothing, depends on no gesture, no menu, no
// delegate and no proxy — the three things that ate this whole evening. The tap
// is already wired to a method of the cell, which is where we act.

static const char* kNFBNotifRevealedKey = "nfbNotifRevealedDismiss";
static const char* kNFBNotifGlyphKey    = "nfbNotifDismissGlyph";
// Cotes validées sur la planche UI v2.
static const CGFloat kNFBNotifDismissTarget = 44.0;   // zone tactile
static const CGFloat kNFBNotifDismissGlyph  = 15.0;   // corps du symbole ×
static const CGFloat kNFBNotifDismissInset  = 16.0;   // marge au bord droit
static const CGFloat kNFBNotifDismissTop    = 4.0;    // haut de la cellule

// The table a cell lives in, walked from the cell itself.
static UITableView* NFBNotifTableForCell(UIView* cell) {
    UIView* node = cell.superview;
    NSInteger hops = 0;
    while (node && hops < 6) {
        if ([node isKindOfClass:[UITableView class]]) {
            return (UITableView*)node;
        }
        node = node.superview;
        hops++;
    }
    return nil;
}

%hook T1URTTimelineNotificationCell

- (void)layoutSubviews {
    %orig;
    if (!NFBNotifsEnabled()) {
        return;
    }
    @try {
        id button = NFBNotifAsk(self, NSSelectorFromString(@"dismissButton"));
        if (![button isKindOfClass:[UIView class]]) {
            return;
        }
        UIView* dismiss = button;
        // Measured: dismissButtonWasTapped just invokes the cell's
        // dismissButtonTapped block (ivar +0xb8), and layoutSubviews does not
        // re-hide the button. What I could NOT prove statically is HOW it is
        // hidden, so every route is covered — hidden flag, alpha, and a zero
        // frame — and it is marked ours so the tap handler knows.
        BOOL changed = NO;
        if (dismiss.hidden) { dismiss.hidden = NO; changed = YES; }
        if (dismiss.alpha < 0.5) { dismiss.alpha = 1.0; changed = YES; }
        dismiss.userInteractionEnabled = YES;

        // Agreed geometry: a 44 pt target (Apple's minimum, and what he asked
        // for — « dur d'accès »), the glyph itself staying small at 22, and a
        // 16 pt margin so it lines up with the bell on the left instead of
        // hugging the screen edge at 9 pt.
        CGFloat side = kNFBNotifDismissTarget;
        CGRect wanted = CGRectMake(((UIView*)self).bounds.size.width - side - kNFBNotifDismissInset,
                                   kNFBNotifDismissTop, side, side);
        if (!CGRectEqualToRect(dismiss.frame, wanted)) {
            dismiss.frame = wanted;
            changed = YES;
        }

        // The × replaces the ⋯: « plus d'options » is not what this does.
        if ([dismiss isKindOfClass:[UIButton class]]) {
            UIButton* button = (UIButton*)dismiss;
            if (!objc_getAssociatedObject(dismiss, kNFBNotifGlyphKey)) {
                UIImage* cross = nil;
                if (@available(iOS 13.0, *)) {
                    UIImageSymbolConfiguration* cfg =
                        [UIImageSymbolConfiguration configurationWithPointSize:kNFBNotifDismissGlyph
                                                                       weight:UIImageSymbolWeightSemibold];
                    cross = [UIImage systemImageNamed:@"xmark" withConfiguration:cfg];
                }
                if (cross) {
                    [button setImage:[cross imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
                            forState:UIControlStateNormal];
                    button.tintColor = [UIColor secondaryLabelColor];
                    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
                    button.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
                    objc_setAssociatedObject(dismiss, kNFBNotifGlyphKey, @YES,
                                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
            }
            // Touch feedback before the finger lifts.
            extern UIColor* CurrentAccentColor(void);
            UIColor* accent = CurrentAccentColor();
            if (accent) {
                [button addAction:[UIAction actionWithHandler:^(__unused UIAction* a) {
                    button.tintColor = accent;
                }] forControlEvents:UIControlEventTouchDown];
                [button addAction:[UIAction actionWithHandler:^(__unused UIAction* a) {
                    button.tintColor = [UIColor secondaryLabelColor];
                }] forControlEvents:UIControlEventTouchUpOutside | UIControlEventTouchCancel];
            }
        }
        objc_setAssociatedObject(self, kNFBNotifRevealedKey, @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (changed) {
            static BOOL said;
            if (!said) {
                said = YES;
                NFBDebugLog(@"[notifs] bouton × révélé sur la notification");
            }
        }
    } @catch (id exception) {
    }
}

- (void)dismissButtonWasTapped {
    // One decision, taken outside the fence, so %orig is never called from
    // inside a protected block: either we handled it, or Twitter does.
    BOOL handled = NO;
    BOOL ours = objc_getAssociatedObject(self, kNFBNotifRevealedKey) != nil;
    if (NFBNotifsEnabled() && ours) {
        @try {
            UITableView* table = NFBNotifTableForCell((UIView*)self);
            NSIndexPath* indexPath =
                table ? [table indexPathForCell:(UITableViewCell*)self] : nil;
            id source = table.dataSource;
            id model = indexPath ? (NFBModelAtIndexPath(source, indexPath)
                                    ?: NFBModelFromCell(table, indexPath))
                                 : nil;
            NSString* identity = model ? NFBNotifIdentity(model) : nil;
            if (identity.length) {
                NFBHideNotifWithText(model, NFBNotifTextFromCell(table, indexPath));
                NFBDebugLog(@"[notifs] × : masquée <%@>", identity);
                NFBNotifDropRow(source, indexPath);
                NFBShowNotifToast(identity);
                handled = YES;
            } else {
                NFBDebugLog(@"[notifs] × : ligne ou identité introuvable — "
                            @"action laissée à Twitter");
            }
        } @catch (id exception) {
            NFBDebugLog(@"[notifs] × : masquage interrompu — action laissée à Twitter");
        }
    }
    if (!handled) {
        %orig;
    }
}

%end
