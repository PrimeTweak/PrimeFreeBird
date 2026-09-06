// HiddenNotifications.x — hide a notification, let it expire on its own.
//
// Purpose: swipe a notification away the way the conversations list already
// does, review the hidden ones with a countdown to their expiry, bring one
// back, or clear them all. Nothing is deleted server side; an entry leaves the
// registry on its own once its horizon passes.
//
// Every structural choice below rests on a measurement:
//   · the notifications list is a T1URTViewController and it answers
//     tableView:trailingSwipeActionsConfigurationForRowAtIndexPath: with
//     trailing=1, while the home timeline answers 0, so the native swipe
//     mechanism is available here;
//   · a row's model is TwitterURT.URTTimelineNotificationViewModel, a Swift
//     class whose field names match no fixed candidate list.
//
// The field names are therefore discovered AT RUNTIME: a cascade of likely
// selectors first, then the class's own zero-argument getters, filtered by
// return type and name. What it settles on is journaled once, so the choice is
// auditable rather than magic.
//
// Nothing here touches a cell, since cells are recycled: the swipe comes from
// the table's own delegate, and hiding is done by filtering the sections, the
// mechanism already proven by Hidden Threads.

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
// guessing a class name.
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
// notification's own date when one can be read, otherwise from the moment it
// was hidden, and stated plainly in the UI rather than pretending to be exact.
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


// Purge on read: an entry past its horizon leaves by itself.
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
        NFBWriteHiddenNotifs(kept);
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

// The registry is written through this, never straight to the defaults.
// NSUserDefaults flushes when the system chooses - usually at backgrounding -
// so a crash between hiding a notification and that flush loses it, which is
// what the reader saw. The store is asked to write now.
static void NFBWriteHiddenNotifs(NSDictionary* registry) {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    if (registry.count) {
        [defaults setObject:registry forKey:kNFBHiddenNotifsKey];
    } else {
        [defaults removeObjectForKey:kNFBHiddenNotifsKey];
    }
    [defaults synchronize];
}

void NFBUnhideNotif(NSString* notifID) {
    NSMutableDictionary* current = [NFBHiddenNotifs() mutableCopy];
    [current removeObjectForKey:notifID];
    NFBWriteHiddenNotifs(current);
}

void NFBUnhideAllNotifs(void) {
    NFBWriteHiddenNotifs(nil);
}

NSInteger NFBHiddenNotifCount(void) {
    NFBPurgeExpiredNotifs();
    return (NSInteger)NFBHiddenNotifs().count;
}

// MARK: - Reading a notification without knowing its class
//
// Type-safe throughout: a selector whose return type is not the expected one is
// never called, because a guessed signature can make ARC retain an integer as
// if it were an object.

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
    // Measured, 18:20:17 - this model exposes exactly six selectors:
    // description, scribeComponent, scribeElement, scribeItem,
    // scribeItemImpressionID, init. The impression id used to be tried first,
    // and that is why a hidden notification came back after a reinstall: an
    // impression id is minted per display, so the key written when hiding
    // never matched the key seen when filtering again. Durable names go first
    // now - the ones inside scribeItem, then the usual entry ids - and the
    // impression id is the last resort, journaled as such.
    id scribeItem = NFBNotifAsk(model, NSSelectorFromString(@"scribeItem"));
    if (scribeItem && ![scribeItem isKindOfClass:[NSString class]]) {
        NSArray<NSString*>* inner = @[@"entryId", @"entryID", @"id", @"itemId",
                                      @"itemID", @"restId", @"identifier",
                                      @"tweetId", @"userId", @"notificationId"];
        for (NSString* name in inner) {
            NSString* value = NFBNotifString(NFBNotifAsk(scribeItem,
                                                         NSSelectorFromString(name)));
            if (value.length) {
                NFBDebugLog(@"notifhide: identity via scribeItem.%@ (durable)", name);
                return [@"si:" stringByAppendingString:value];
            }
        }
        static BOOL described;
        if (!described) {
            described = YES;
            NSString* shape = nil;
            @try {
                shape = [scribeItem description];
                if (shape.length > 260) {
                    shape = [shape substringToIndex:260];
                }
            } @catch (id exception) {
                shape = @"(description unreadable)";
            }
            NFBDebugLog(@"notifhide: scribeItem is %@ and answers none of the durable "
                        @"names; description = %@",
                        NSStringFromClass([scribeItem class]), shape ?: @"(nil)");
        }
    }
    NSArray<NSString*>* candidates = @[
        @"entryId", @"entryID", @"identifier", @"notificationId", @"notificationID",
        @"id", @"sortIndex", @"key", @"itemIdentifier",
        @"scribeItemImpressionID", @"scribeItemImpressionId"
    ];
    for (NSString* name in candidates) {
        NSString* value = NFBNotifString(NFBNotifAsk(model, NSSelectorFromString(name)));
        if (value.length) {
            cache[className] = name;
            NFBDebugLog(@"notifhide: identity of %@ = %@%@", className, name,
                        [name hasPrefix:@"scribeItemImpression"]
                            ? @" (IMPRESSION ID - not stable across sessions)"
                            : @"");
            return value;
        }
    }
    SEL found = NFBNotifDiscover(model, @[@"entryid", @"identifier", @"sortindex",
                                          @"itemid", @"restid"], '@');
    if (found) {
        cache[className] = NSStringFromSelector(found);
        NFBDebugLog(@"notifhide: identity of %@ = %@ (discovered)",
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
    // ONE measurement, and it settles the pull-to-refresh question for good.
    //
    // Both facts are journaled the first four times the filter sees a row while
    // the registry is not empty: the identity the display carries, to compare
    // with the one written when hiding, and what the model exposes of itself,
    // in case it holds a stable id or the text. Two different identities mean
    // the impression id is per-response; two identical ones mean the filter is
    // not called on that path.
    static NSInteger noted;
    if (identity.length && hidden.count && noted < 4) {
        noted++;
        NSString* shape = nil;
        @try {
            shape = [model description];
            if (shape.length > 220) {
                shape = [shape substringToIndex:220];
            }
        } @catch (id exception) {
            shape = @"(description illisible)";
        }
        NFBDebugLog(@"notifhide: FILTER identity <%@> | %@",
                    identity, hidden[identity] ? @"FOUND -> hidden" : @"not in the registry");
        NFBDebugLog(@"notifhide: FILTER model = %@", shape ?: @"(nil)");
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


// The notification's own date, which is what the countdown hangs on, rather
// than the moment it was hidden.
//
// Measured: URTTimelineNotificationViewModel exposes no date at all (its six
// selectors are description / scribeComponent / scribeElement / scribeItem /
// scribeItemImpressionID / init), and the cell's timestampView is Swift, so the
// runtime cannot be asked. The age IS on screen though: the cell renders a
// relative form such as "1w", and that text is already read at hide time. The
// date is recovered from it, and the countdown runs from there.
//
// Handles the relative forms Twitter uses (30s / 45m / 5h / 3d / 1w) and the
// absolute ones it falls back to for older items ("Aug 11", "Aug 11, 2025").
// Returns 0 when nothing can be read, and the caller keeps its old behaviour.
static NSTimeInterval NFBNotifDateFromDisplayedAge(NSString* text) {
    if (!text.length) {
        return 0;
    }
    NSString* tail = [[text componentsSeparatedByString:@" · "] lastObject];
    tail = [tail stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!tail.length) {
        return 0;
    }

    static NSRegularExpression* relative;
    static NSDateFormatter* shortDate;
    static NSDateFormatter* longDate;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        relative = [NSRegularExpression regularExpressionWithPattern:@"^(\\d+)\\s*([smhdwy])$"
                                                             options:NSRegularExpressionCaseInsensitive
                                                               error:nil];
        shortDate = [[NSDateFormatter alloc] init];
        [shortDate setLocalizedDateFormatFromTemplate:@"MMMd"];
        longDate = [[NSDateFormatter alloc] init];
        [longDate setLocalizedDateFormatFromTemplate:@"MMMdyyyy"];
    });

    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSTextCheckingResult* match =
        [relative firstMatchInString:tail options:0 range:NSMakeRange(0, tail.length)];
    if (match && match.numberOfRanges == 3) {
        double amount = [[tail substringWithRange:[match rangeAtIndex:1]] doubleValue];
        NSString* unit = [[tail substringWithRange:[match rangeAtIndex:2]] lowercaseString];
        double seconds = 0;
        if ([unit isEqualToString:@"s"]) { seconds = amount; }
        else if ([unit isEqualToString:@"m"]) { seconds = amount * 60; }
        else if ([unit isEqualToString:@"h"]) { seconds = amount * 3600; }
        else if ([unit isEqualToString:@"d"]) { seconds = amount * 86400; }
        else if ([unit isEqualToString:@"w"]) { seconds = amount * 604800; }
        else if ([unit isEqualToString:@"y"]) { seconds = amount * 31557600; }
        if (seconds > 0) {
            return now - seconds;
        }
    }

    for (NSDateFormatter* formatter in @[longDate, shortDate]) {
        NSDate* parsed = [formatter dateFromString:tail];
        if (!parsed) {
            continue;
        }
        NSTimeInterval when = [parsed timeIntervalSince1970];
        // A short form carries no year: the parser assumes 1970, so the day and
        // month are grafted onto the current year, and pushed back a year if
        // that would place the notification in the future.
        if (formatter == shortDate) {
            NSCalendar* calendar = [NSCalendar currentCalendar];
            NSDateComponents* parts =
                [calendar components:NSCalendarUnitMonth | NSCalendarUnitDay fromDate:parsed];
            NSDateComponents* thisYear =
                [calendar components:NSCalendarUnitYear fromDate:[NSDate date]];
            parts.year = thisYear.year;
            NSDate* rebuilt = [calendar dateFromComponents:parts];
            when = [rebuilt timeIntervalSince1970];
            if (when > now) {
                parts.year = thisYear.year - 1;
                when = [[calendar dateFromComponents:parts] timeIntervalSince1970];
            }
        }
        if (when > 0 && when <= now) {
            return when;
        }
    }
    return 0;
}

static void NFBHideNotifWithText(id model, NSString* cellText) {
    NSString* identity = NFBNotifIdentity(model);
    if (!identity.length) {
        NFBDebugLog(@"notifhide: no readable identity - hide refused");
        return;
    }
    NSMutableDictionary* current = [NFBHiddenNotifs() mutableCopy];
    NSString* text = NFBNotifText(model) ?: (cellText ?: @"");
    if (text.length > 140) {
        text = [text substringToIndex:140];
    }
    // "d" is the notification's own date. The model has none, so it comes from
    // the age the cell displays; the countdown and the expiry date both read
    // "d" first and only fall back to "h", the moment it was hidden.
    NSTimeInterval notifDate = NFBNotifDate(model);
    NSString* source = @"model";
    if (notifDate <= 0) {
        notifDate = NFBNotifDateFromDisplayedAge(cellText ?: text);
        source = @"displayed age";
    }
    if (notifDate <= 0) {
        source = @"none - falling back to the hide date";
    }
    current[identity] = @{
        @"t": text,
        @"d": @(notifDate),
        @"h": @([[NSDate date] timeIntervalSince1970])
    };
    NFBDebugLog(@"notifhide: notification date = %@ (%@)",
                notifDate > 0
                    ? [NSDate dateWithTimeIntervalSince1970:notifDate]
                    : (id)@"unknown",
                source);
    NFBWriteHiddenNotifs(current);
    NFBDebugLog(@"notifhide: hidden <%@> - %lu total",
                identity, (unsigned long)current.count);
}

// MARK: - The toast (the capsule shared with Hidden Threads)

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
    // The toast stays where it is, but the navigation title reads through the
    // text. The material alone is too thin, so a veil at 80 % sits behind the
    // content: enough to stop the title, thin enough to let the background
    // still breathe.
    toast.layer.shadowColor = [UIColor blackColor].CGColor;
    toast.layer.shadowOpacity = 0.16;
    toast.layer.shadowRadius = 10.0;
    toast.layer.shadowOffset = CGSizeMake(0, 4);
    [window addSubview:toast];

    UIView* content = toast.contentView;

    UIView* veil = [[UIView alloc] init];
    veil.backgroundColor = [[UIColor systemBackgroundColor] colorWithAlphaComponent:0.80];
    veil.userInteractionEnabled = NO;
    veil.layer.cornerRadius = 22.0;              // matches the capsule radius
    veil.layer.cornerCurve = kCACornerCurveContinuous;
    veil.layer.masksToBounds = YES;
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
// to whatever Twitter already returns: nothing native is dropped, and when
// Twitter returns nothing the configuration carries the added action alone.

// Ask the CELL. The delegate is a shared proxy and the data source is the
// controller, and neither of them yields the row, so the cell is the one
// object that certainly holds its own model.
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
static void NFBNotifSyncEmptyState(id dataViewController);

static void NFBNotifDropRow(id dataViewController, NSIndexPath* indexPath) {
    if (!dataViewController || !indexPath) {
        return;
    }
    @try {
        SEL deleteSel = NSSelectorFromString(@"deleteItemAtIndexPath:withRowAnimation:");
        if ([dataViewController respondsToSelector:deleteSel]) {
            ((void (*)(id, SEL, id, NSInteger))objc_msgSend)(
                dataViewController, deleteSel, indexPath, UITableViewRowAnimationLeft);
            NFBDebugLog(@"[notifs] row removed from the list (%ld/%ld)",
                        (long)indexPath.section, (long)indexPath.row);
            // Deferred one turn: the table must finish its delete animation
            // before it reports a truthful row count.
            dispatch_async(dispatch_get_main_queue(), ^{
                NFBNotifSyncEmptyState(dataViewController);
            });
            return;
        }
        NFBDebugLog(@"[notifs] direct removal unavailable on %@",
                    NSStringFromClass([dataViewController class]));
    } @catch (id exception) {
        NFBDebugLog(@"[notifs] direct removal refused - the row goes on reload");
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
    // Only rows that carry a notification, and only ones that can be named: a
    // row that cannot be identified could never be unhidden, so it is left
    // alone. Each refusal says WHY, once, because a silent guard cannot be
    // diagnosed from the journal.
    NSString* modelClass = model ? NSStringFromClass([model class]) : @"(none)";
    if (!model) {
        static BOOL saidNoModel;
        if (!saidNoModel) {
            saidNoModel = YES;
            NFBDebugLog(@"[notifs] swipe: no model at row %ld/%ld - "
                        @"section reading to revisit",
                        (long)indexPath.section, (long)indexPath.row);
        }
        return original;
    }
    if (![modelClass containsString:@"Notification"]) {
        static NSMutableSet<NSString*>* seenClasses;
        if (!seenClasses) { seenClasses = [NSMutableSet set]; }
        if (![seenClasses containsObject:modelClass] && seenClasses.count < 6) {
            [seenClasses addObject:modelClass];
            NFBDebugLog(@"[notifs] swipe: unrecognised class \"%@\" - no action added",
                        modelClass);
        }
        return original;
    }
    if (!NFBNotifIdentity(model)) {
        static BOOL saidNoIdentity;
        if (!saidNoIdentity) {
            saidNoIdentity = YES;
            NFBDebugLog(@"[notifs] swipe: %@ has no readable identity - action refused",
                        modelClass);
        }
        return original;
    }
    static BOOL saidArmed;
    if (!saidArmed) {
        saidArmed = YES;
        NFBDebugLog(@"[notifs] swipe: \"Hide\" action added on %@", modelClass);
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
// the registry can only belong to a hidden notification, so no other screen can
// match and the filter needs no scoping of its own.

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


// MARK: - the sweep (what the filter could never do)
//
// Measured in the binary: no section class exposes -items in Objective-C, which
// is why NFBFilterNotifSections never reached a single row: with a non-empty
// registry the hide side is journaled but no filter line ever is. The hidden
// rows were therefore never filtered out; they only left because the row was
// deleted by hand, and a refresh brought them straight back.
//
// TFNItemsDataViewController does implement -itemAtIndexPath: and
// -deleteItemAtIndexPath:withRowAnimation:, and the second one works here. So
// after every content replacement the rows are walked, each item is requested,
// and the hidden ones are deleted from the end.



// Which screens the sweep is allowed to touch — decided by observation, not by
// a class name.
//
// Measured: without this guard the sweep walks the HOME TIMELINE on every
// reload, asking for every item and comparing every model. It deletes nothing
// there, but the work is real and has no business being on that screen.
//
// A name test would be fragile: the notifications list is a plain
// T1URTViewController, a class Twitter reuses elsewhere. So the verdict is
// EARNED instead: on its first pass over a controller the sweep watches what
// the models are. One notification model and the controller is kept forever;
// several items with none and it is dropped forever. That cannot break the
// notifications sweep — a screen showing notifications always earns YES — and
// after one pass the home timeline is never walked again.
static const char* kNFBNotifVerdictKey = "nfbNotifSweepVerdict";

static BOOL NFBNotifSweepAllowed(id dataViewController) {
    id verdict = objc_getAssociatedObject(dataViewController, kNFBNotifVerdictKey);
    return verdict ? [verdict boolValue] : YES;   // undecided: observe once
}

static void NFBNotifRecordVerdict(id dataViewController, BOOL sawNotification,
                                  NSInteger examined) {
    if (objc_getAssociatedObject(dataViewController, kNFBNotifVerdictKey)) {
        return;
    }
    if (sawNotification) {
        objc_setAssociatedObject(dataViewController, kNFBNotifVerdictKey, @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NFBDebugLog(@"[sweep] %@ kept - this is the notifications screen",
                    NSStringFromClass([dataViewController class]));
        return;
    }
    // A screen that BELONGS to the notifications tab is never condemned.
    //
    // Measured: an instance of T1URTViewController can be dropped for showing
    // rows that carry no notification, the Mentions tab being one. But the
    // same could hit the All tab if it ever showed placeholder rows before its
    // notifications arrived: dropped for good, and the hidden ones would come
    // back. Staying undecided costs one extra walk on Mentions; being wrong
    // costs the whole feature.
    UIViewController* node = [dataViewController isKindOfClass:[UIViewController class]]
                                 ? (UIViewController*)dataViewController
                                 : nil;
    for (NSInteger hop = 0; node && hop < 6; hop++) {
        if ([NSStringFromClass([node class])
                containsString:@"NotificationsViewController"]) {
            return;      // undecided on purpose — keep observing
        }
        node = node.parentViewController;
    }
    // Only decide against a screen once enough items have been seen: an empty
    // or still-loading list must not be condemned on a single empty pass.
    if (examined >= 5) {
        objc_setAssociatedObject(dataViewController, kNFBNotifVerdictKey, @NO,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NFBDebugLog(@"[sweep] %@ skipped - no notification in %ld row(s)",
                    NSStringFromClass([dataViewController class]), (long)examined);
    }
}

// MARK: - the empty panel (two labels, nothing borrowed)
//
// The first attempt instantiated Twitter's own TFNEmptyStateView. It crashed
// the app: an internal view carries invariants that cannot be known from
// outside, it was given no image and no button, and a bad access is NOT caught
// by @try, since only ObjC exceptions are. So nothing here belongs to Twitter:
// two UILabels in a container. Worst case it looks slightly off; it cannot
// bring the app down.
//
// The anchor is the sweep's verdict, which is measured on the running screen.
// Only a controller that earned YES can carry this panel.

static const NSInteger kNFBNotifEmptyTag = 90315;
static const NSInteger kNFBNotifEmptyTitleTag = 90316;
static const NSInteger kNFBNotifEmptyBodyTag = 90317;

// textDetailsColor is the palette entry Twitter uses for secondary copy. It is
// not declared in src/Headers, so this declaration shim serves as a cast
// target. Never instantiated, never messaged as a class.
@interface NFBNotifPaletteShim : NSObject
- (UIColor*)textDetailsColor;
@end

// The secondary grey Twitter itself draws with, taken from the live palette so
// it follows light and dark. Reached by the same path CurrentAccentColor uses.
// UIColor secondaryLabelColor is a warmer, lighter grey and reads as a
// different colour beside the native empty state.
static UIColor* NFBNotifDetailColor(void) {
    Class settingsClass = objc_getClass("TAEColorSettings");
    if (settingsClass) {
        id settings = [settingsClass sharedSettings];
        id current = [settings currentColorPalette];
        id palette = [current colorPalette];
        if ([palette respondsToSelector:@selector(textDetailsColor)]) {
            UIColor* colour = [(NFBNotifPaletteShim*)palette textDetailsColor];
            if ([colour isKindOfClass:[UIColor class]]) {
                return colour;
            }
        }
    }
    return [UIColor secondaryLabelColor];
}

// Twitter composes in Chirp, not in the system face, which is the whole of the
// difference once size and weight match. Twitter sets these large empty state
// headlines in Heavy. The font group is reached the way the
// settings screens already reach it; the system font is the fallback.
static UIFont* NFBNotifEmptyFont(CGFloat size, BOOL heavy) {
    id group = [BHTManager sharedFontGroup];
    TFNUIDefaultFontGroup* fonts = (TFNUIDefaultFontGroup*)group;
    if (heavy && [group respondsToSelector:@selector(heavyFontOfSize:)]) {
        UIFont* font = [fonts heavyFontOfSize:size];
        if ([font isKindOfClass:[UIFont class]]) {
            return font;
        }
    }
    if (!heavy && [group respondsToSelector:@selector(fontOfSize:)]) {
        UIFont* font = [fonts fontOfSize:size];
        if ([font isKindOfClass:[UIFont class]]) {
            return font;
        }
    }
    return heavy ? [UIFont systemFontOfSize:size weight:UIFontWeightHeavy]
                 : [UIFont systemFontOfSize:size];
}

// Geometry and type taken from the native empty state, measured two ways that
// agree: the view tree in a capture, and the rendered screenshot.
//
//   TFNViewHostTableViewCell {440 x 216}
//     TFNEmptyStateView
//       SemanticContentView {{18, 36}, {404, 164.33}}
//         UILabel          {{0,  0}, {404,  36}}     one line
//         TFNLinkTextLabel {{0, 44}, {404,  38.33}}  two lines
//
// 18 points of side inset, so 404 wide on a 440 wide table. The title label is
// 36 points tall for a single line, which is a 30 point face at the usual 1.2
// line height; the capital height measured on the screenshot agrees at about
// 21 points, and 21 / 0.72 is 29.4. The body is 38.33 for two lines, so a
// 19.17 line height, which is a 15 point face. The gap is 44 - 36 = 8.
static const CGFloat kNFBNotifEmptyTopInset = 36.0;
static const CGFloat kNFBNotifEmptySideInset = 18.0;
static const CGFloat kNFBNotifEmptyGap = 8.0;
static const CGFloat kNFBNotifEmptyTitleSize = 30.0;
static const CGFloat kNFBNotifEmptyBodySize = 15.0;

// Places the panel with frames in the table's CONTENT coordinate space, the
// same technique the reading marker uses. A subview of a scroll view placed in
// content coordinates travels with the list; a subview pinned to
// frameLayoutGuide stays welded to the viewport, which is why the panel used
// to sit still. Auto Layout against contentLayoutGuide is avoided on purpose:
// a table view owns its content size, and constraints that try to drive it
// fight the table.
//
// Called on every sync, so a width change is picked up at the next update.
static void NFBNotifLayoutEmptyPanel(UIView* panel, UITableView* table) {
    UILabel* title = (UILabel*)[panel viewWithTag:kNFBNotifEmptyTitleTag];
    UILabel* body = (UILabel*)[panel viewWithTag:kNFBNotifEmptyBodyTag];
    if (![title isKindOfClass:[UILabel class]] ||
        ![body isKindOfClass:[UILabel class]]) {
        return;
    }
    CGFloat tableWidth = CGRectGetWidth(table.bounds);
    CGFloat width = tableWidth - (kNFBNotifEmptySideInset * 2.0);
    if (width < 80.0) {
        return;                       // no room to read anything; leave as is
    }
    body.textColor = NFBNotifDetailColor();
    CGSize titleSize = [title sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)];
    CGSize bodySize = [body sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)];
    title.frame = CGRectMake(0.0, 0.0, width, ceil(titleSize.height));
    body.frame = CGRectMake(0.0, CGRectGetMaxY(title.frame) + kNFBNotifEmptyGap,
                            width, ceil(bodySize.height));
    panel.frame = CGRectMake(kNFBNotifEmptySideInset,
                             kNFBNotifEmptyTopInset,
                             width, CGRectGetMaxY(body.frame));
}

static void NFBNotifSyncEmptyState(id dataViewController) {
    if (!dataViewController) {
        return;
    }
    // The verdict the sweep earned by observation — never a class-name guess.
    id verdict = objc_getAssociatedObject(dataViewController, kNFBNotifVerdictKey);
    if (![verdict isEqual:@YES]) {
        return;
    }
    @try {
        UITableView* table = nil;
        SEL tableSel = NSSelectorFromString(@"tableView");
        if ([dataViewController respondsToSelector:tableSel]) {
            id maybe = ((id (*)(id, SEL))objc_msgSend)(dataViewController, tableSel);
            if ([maybe isKindOfClass:[UITableView class]]) {
                table = maybe;
            }
        }
        if (!table) {
            NFBDebugLog(@"[empty] no table on %@",
                        NSStringFromClass([dataViewController class]));
            return;
        }
        // MEASURED: with every notification hidden, the table still reports
        // one row on a visibly empty screen, repeatedly. That leftover row is
        // not a notification (the sweep, which
        // reads every model, never treats it as one): it is a header, a footer
        // or a zero-height cell.
        //
        // So the raw row count is the wrong measure. What decides whether the
        // screen is empty is how many rows carry a NOTIFICATION model — the
        // same test the sweep already uses to earn its verdict.
        NSInteger rows = 0;
        NSInteger notifRows = 0;
        SEL itemSel = NSSelectorFromString(@"itemAtIndexPath:");
        BOOL canRead = [dataViewController respondsToSelector:itemSel];
        for (NSInteger s = 0; s < table.numberOfSections; s++) {
            NSInteger count = [table numberOfRowsInSection:s];
            rows += count;
            if (!canRead) {
                continue;
            }
            for (NSInteger r = 0; r < count; r++) {
                NSIndexPath* path = [NSIndexPath indexPathForRow:r inSection:s];
                id item = ((id (*)(id, SEL, id))objc_msgSend)(dataViewController,
                                                             itemSel, path);
                id model = item ? unwrapDataViewItem(item) : nil;
                if (model && [NSStringFromClass([model class])
                                 containsString:@"Notification"]) {
                    notifRows++;
                }
            }
        }
        UIView* existing = [table viewWithTag:kNFBNotifEmptyTag];
        NSUInteger hidden = NFBHiddenNotifs().count;

        NFBDebugLog(@"[empty] %ld row(s), %ld notification(s), %lu hidden, panel %@",
                    (long)rows, (long)notifRows, (unsigned long)hidden,
                    existing ? @"placed" : @"absent");

        if (notifRows > 0 || hidden == 0) {
            if (existing) {
                [existing removeFromSuperview];
                NFBDebugLog(@"[empty] panel removed");
            }
            return;
        }
        if (existing) {
            // A width change (rotation, split view) moves the panel; the frames
            // are recomputed rather than left stale.
            NFBNotifLayoutEmptyPanel(existing, table);
            return;
        }

        UIView* panel = [[UIView alloc] init];
        panel.tag = kNFBNotifEmptyTag;
        panel.userInteractionEnabled = NO;    // never blocks a pull-to-refresh
        panel.autoresizingMask = UIViewAutoresizingFlexibleWidth;

        UILabel* title = [[UILabel alloc] init];
        title.tag = kNFBNotifEmptyTitleTag;
        title.text = [[BHTBundle sharedBundle]
                         localizedStringForKey:@"HIDDEN_NOTIFS_EMPTY_TITLE"];
        title.font = NFBNotifEmptyFont(kNFBNotifEmptyTitleSize, YES);
        title.textColor = [UIColor labelColor];
        title.textAlignment = NSTextAlignmentNatural;
        title.numberOfLines = 0;
        [panel addSubview:title];

        UILabel* body = [[UILabel alloc] init];
        body.tag = kNFBNotifEmptyBodyTag;
        body.text = [[BHTBundle sharedBundle]
                        localizedStringForKey:@"HIDDEN_NOTIFS_EMPTY_BODY"];
        body.font = NFBNotifEmptyFont(kNFBNotifEmptyBodySize, NO);
        body.textColor = NFBNotifDetailColor();
        body.textAlignment = NSTextAlignmentNatural;
        body.numberOfLines = 0;
        [panel addSubview:body];

        [table addSubview:panel];
        NFBNotifLayoutEmptyPanel(panel, table);
        NFBDebugLog(@"[empty] PANEL PLACED");
    } @catch (id exception) {
        NFBDebugLog(@"[vide] exception: %@", exception);
    }
}

static BOOL gNFBNotifSweeping;

static void NFBNotifSweep(id dataViewController) {
    if (gNFBNotifSweeping || !NFBNotifsEnabled() || !dataViewController) {
        return;
    }
    if (!NFBHiddenNotifs().count) {
        // Everything was brought back: the panel must go, so the sync still runs.
        NFBNotifSyncEmptyState(dataViewController);
        return;
    }
    if (!NFBNotifSweepAllowed(dataViewController)) {
        return;              // screen already ruled out — nothing to walk
    }
    SEL itemSel = NSSelectorFromString(@"itemAtIndexPath:");
    SEL deleteSel = NSSelectorFromString(@"deleteItemAtIndexPath:withRowAnimation:");
    if (![dataViewController respondsToSelector:itemSel] ||
        ![dataViewController respondsToSelector:deleteSel]) {
        return;
    }
    gNFBNotifSweeping = YES;              // deleting triggers updates: no recursion
    @try {
        UITableView* table = nil;
        SEL tableSel = NSSelectorFromString(@"tableView");
        if ([dataViewController respondsToSelector:tableSel]) {
            id maybe = ((id (*)(id, SEL))objc_msgSend)(dataViewController, tableSel);
            if ([maybe isKindOfClass:[UITableView class]]) {
                table = maybe;
            }
        }
        if (!table) {
            gNFBNotifSweeping = NO;
            return;
        }
        // MEASURE ONLY — no behaviour change.
        //
        // The sweep has no screen guard: it runs on every list controller,
        // the home timeline included. It deletes nothing there, since no tweet
        // is in the registry, but it walks every row on every reload. This line
        // names the controller the sweep touches, so a timeline flash can be
        // attributed to it or ruled out.
        //
        // Printed once per class, so the journal stays readable.
        static NSMutableSet* announced;
        if (!announced) {
            announced = [NSMutableSet set];
        }
        NSString* owner = NSStringFromClass([dataViewController class]);
        if (![announced containsObject:owner]) {
            [announced addObject:owner];
            NFBDebugLog(@"[sweep] running on %@ (%ld section(s))",
                        owner, (long)table.numberOfSections);
        }

        NSMutableArray<NSIndexPath*>* doomed = [NSMutableArray array];
        BOOL sawNotification = NO;
        NSInteger examined = 0;
        NSInteger sections = table.numberOfSections;
        for (NSInteger s = 0; s < sections; s++) {
            NSInteger rows = [table numberOfRowsInSection:s];
            for (NSInteger r = 0; r < rows; r++) {
                NSIndexPath* path = [NSIndexPath indexPathForRow:r inSection:s];
                id item = ((id (*)(id, SEL, id))objc_msgSend)(dataViewController, itemSel, path);
                id model = item ? unwrapDataViewItem(item) : nil;
                if (model) {
                    examined++;
                    if ([NSStringFromClass([model class]) containsString:@"Notification"]) {
                        sawNotification = YES;
                    }
                }
                if (model && NFBNotifIsHidden(model)) {
                    [doomed addObject:path];
                }
            }
        }
        // From the end, so earlier index paths stay valid.
        for (NSIndexPath* path in [doomed reverseObjectEnumerator]) {
            ((void (*)(id, SEL, id, NSInteger))objc_msgSend)(
                dataViewController, deleteSel, path, UITableViewRowAnimationNone);
        }
        NFBNotifRecordVerdict(dataViewController, sawNotification, examined);
        NFBNotifSyncEmptyState(dataViewController);
        if (doomed.count) {
            NFBDebugLog(@"[notifs] sweep: %lu hidden removed after reload",
                        (unsigned long)doomed.count);
        }
    } @catch (id exception) {
        NFBDebugLog(@"[notifs] sweep interrupted - no consequence");
    }
    gNFBNotifSweeping = NO;
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
    // The list is in place: remove what is hidden.
    dispatch_async(dispatch_get_main_queue(), ^{
        NFBNotifSweep(self);
    });
}

- (void)setSections:(NSArray*)sections {
    if (NFBSectionsAreNotifications(sections)) {
        gNFBNotifScreen = (UIViewController*)self;
    }
    %orig(NFBFilterNotifSections(sections));
    // The list is in place: remove what is hidden.
    dispatch_async(dispatch_get_main_queue(), ^{
        NFBNotifSweep(self);
    });
}

- (void)updateSections:(NSArray*)sections {
    if (NFBSectionsAreNotifications(sections)) {
        gNFBNotifScreen = (UIViewController*)self;
    }
    %orig(NFBFilterNotifSections(sections));
    // The list is in place: remove what is hidden.
    dispatch_async(dispatch_get_main_queue(), ^{
        NFBNotifSweep(self);
    });
}

// The four below are why hidden notifications came back on pull-to-refresh:
// the filter covered three doors out of seven. These names are the ones
// TFNItemsDataViewController actually implements, read from the binary — there
// is no eighth to cover.

- (void)updateSections:(NSArray*)sections completion:(id)completion {
    if (NFBSectionsAreNotifications(sections)) {
        gNFBNotifScreen = (UIViewController*)self;
    }
    %orig(NFBFilterNotifSections(sections), completion);
    // The list is in place: remove what is hidden.
    dispatch_async(dispatch_get_main_queue(), ^{
        NFBNotifSweep(self);
    });
}

- (void)updateSections:(NSArray*)sections withRowAnimation:(NSInteger)animation {
    if (NFBSectionsAreNotifications(sections)) {
        gNFBNotifScreen = (UIViewController*)self;
    }
    %orig(NFBFilterNotifSections(sections), animation);
    // The list is in place: remove what is hidden.
    dispatch_async(dispatch_get_main_queue(), ^{
        NFBNotifSweep(self);
    });
}

- (void)updateSections:(NSArray*)sections
      withRowAnimation:(NSInteger)animation
            completion:(id)completion {
    if (NFBSectionsAreNotifications(sections)) {
        gNFBNotifScreen = (UIViewController*)self;
    }
    %orig(NFBFilterNotifSections(sections), animation, completion);
    // The list is in place: remove what is hidden.
    dispatch_async(dispatch_get_main_queue(), ^{
        NFBNotifSweep(self);
    });
}

- (void)updateSections:(NSArray*)sections
reconfigureItemIdentifiers:(id)identifiers
      withRowAnimation:(NSInteger)animation
            completion:(id)completion {
    if (NFBSectionsAreNotifications(sections)) {
        gNFBNotifScreen = (UIViewController*)self;
    }
    %orig(NFBFilterNotifSections(sections), identifiers, animation, completion);
    // The list is in place: remove what is hidden.
    dispatch_async(dispatch_get_main_queue(), ^{
        NFBNotifSweep(self);
    });
}

%end

// MARK: - Quick access, the pattern shared with muted words
//
// Scoping is the whole difficulty of a bar button (TFNNavigationBar is generic
// — every screen has one). Rather than guess the notifications screen's class
// name, the screen NAMES ITSELF: the filter above runs on it, so it records the
// controller it saw. A bar then belongs to notifications when its owner is that
// controller or one of its ancestors. If nothing matches, no button is added —
// best effort, never destructive, and the list stays reachable from Settings.


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

// The sender is a UIBarButtonItem, the bar's own kind of button, since the
// entry point is Twitter's own. A bar item is NOT a view: it answers neither
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
        // Load the view now, so viewDidLoad → reload → preferredContentSize all
        // run BEFORE the popover picks its position. Otherwise it places itself
        // against a stale size and lands on top of the button instead of under
        // it.
        (void)controller.view;
        controller.modalPresentationStyle = UIModalPresentationPopover;
        UIPopoverPresentationController* popover =
            controller.popoverPresentationController;
        // A real view means a real arrow, pinned to the icon, which is what
        // anchoring on sourceView gives.
        if ([sender isKindOfClass:[UIView class]]) {
            popover.sourceView = sender;
            popover.sourceRect = ((UIView*)sender).bounds;
        } else if ([sender isKindOfClass:[UIBarButtonItem class]]) {
            UIView* anchor = ((UIBarButtonItem*)sender).customView;
            if (anchor) {
                popover.sourceView = anchor;
                popover.sourceRect = anchor.bounds;
            } else {
                popover.barButtonItem = sender;
            }
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
            NFBDebugLog(@"[notifs] no host screen for the list - presentation cancelled");
            return;
        }
        [host presentViewController:controller animated:YES completion:nil];
        NFBDebugLog(@"[notifs] hidden list presented from %@",
                    NSStringFromClass([host class]));
    } @catch (id exception) {
        NFBDebugLog(@"[notifs] list presentation abandoned - no consequence");
    }
}

// Without this a popover becomes full screen on iPhone.
- (UIModalPresentationStyle)adaptivePresentationStyleForPresentationController:
    (__unused UIPresentationController*)controller {
    return UIModalPresentationNone;
}

@end


%hook TFNItemsDataViewController

// Safety net, and a measurement in one: when the notifications list is not a
// plain T1URTViewController, the hook above never fires and the swipe silently
// does nothing. This one sits on the base class the whole app's lists inherit
// from, so it fires wherever the rows live; it declines immediately unless the
// row really is a nameable notification.
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
        NFBDebugLog(@"[notifs] swipe: added by the net on %@ (list class %@)",
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

// MARK: - recognising a hidden-capable row
//
// Measured in the binary: tableView:canEditRowAtIndexPath: is implemented ONLY
// by T1AccountsViewController and T1TweetDraftsViewController, never by the
// notifications list. Nothing refuses the swipe there, so no answer has to be
// forced on a method that does not exist.

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
                NFBDebugLog(@"[notifs] model read from the cell (%@)",
                            NSStringFromClass([model class]));
            }
        }
    }
    return model;
}

// Every refusal names itself ONCE, so a decline can be diagnosed from the
// journal alone.
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
            NFBDebugLog(@"[notifs] row %ld/%ld: NO model (source=%@) - "
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
            NFBDebugLog(@"[notifs] row carried by \"%@\" - not recognised as a notification",
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
            NFBDebugLog(@"[notifs] %@ has NO identity - selectors: %@", modelClass,
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
//     built with the added methods already in place;
//   · for a table already wired, re-assign delegate and data source once, which
//     is the documented way to make the table rebuild that cache.

// MARK: - the eye
//
// Measured: with T1TabNavigationController the eye is placed and journaled;
// with a TFNNavigationBar hook nothing is ever printed and the icon is simply
// absent. So the door that fires is used, and the glass is dealt with where it
// is actually painted:
// _TtCC5UIKit19NavigationButtonBar15ItemWrapperView, animating cornerRadii.
// That wrapper is UIKit's per-item container; the glyph's own view can do
// nothing about it, so the wrapper is walked up to and its background turned
// off.

static const NSInteger kNFBNotifBarItemTag = 90314;
static const CGFloat kNFBNotifEyeSide = 24.0;

static UIColor* NFBNotifIconGrey(UITraitCollection* traits) {
    UIColor* grey = [[UIColor labelColor] colorWithAlphaComponent:0.6];
    if (traits && [grey respondsToSelector:@selector(resolvedColorWithTraitCollection:)]) {
        return [grey resolvedColorWithTraitCollection:traits] ?: grey;
    }
    return grey;
}

// Flat bitmap + AlwaysOriginal: the theme's window tint cannot repaint it.
static UIImage* NFBNotifFlatGlyph(UIImage* source, UIColor* colour) {
    if (!source || !colour) {
        return source;
    }
    CGSize size = source.size;
    if (size.width < 1.0 || size.height < 1.0) {
        return source;
    }
    UIGraphicsImageRendererFormat* format = [UIGraphicsImageRendererFormat preferredFormat];
    format.opaque = NO;
    format.scale = source.scale;
    UIGraphicsImageRenderer* renderer =
        [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
    UIImage* painted = [renderer imageWithActions:^(UIGraphicsImageRendererContext* context) {
        CGRect rect = CGRectMake(0.0, 0.0, size.width, size.height);
        [source drawInRect:rect];
        CGContextSetBlendMode(context.CGContext, kCGBlendModeSourceIn);
        [colour setFill];
        CGContextFillRect(context.CGContext, rect);
    }];
    return [painted imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

// The eye's button reports its own container so the glass can be switched off.
@interface NFBNotifEyeButton : UIButton
- (void)nfbStripGlass;
@end

@implementation NFBNotifEyeButton

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self nfbStripGlass];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self nfbStripGlass];
}

- (void)nfbStripGlass {
    @try {
        UIView* node = self.superview;
        NSInteger hops = 0;
        while (node && hops < 5) {
            NSString* name = NSStringFromClass([node class]);
            BOOL wrapper = [name containsString:@"ItemWrapperView"] ||
                           [name containsString:@"GlassInteraction"] ||
                           [name containsString:@"SystemBackgroundView"] ||
                           [name containsString:@"PlatterContainer"];
            if (wrapper) {
                node.backgroundColor = [UIColor clearColor];
                node.layer.backgroundColor = [UIColor clearColor].CGColor;
                node.layer.borderWidth = 0.0;
                node.layer.shadowOpacity = 0.0;
                for (UIView* sub in node.subviews) {
                    NSString* subName = NSStringFromClass([sub class]);
                    if ([subName containsString:@"SystemBackgroundView"] ||
                        [subName containsString:@"VisualEffect"] ||
                        [subName containsString:@"Glass"]) {
                        sub.hidden = YES;
                    }
                }
                static BOOL said;
                if (!said) {
                    said = YES;
                    NFBDebugLog(@"[notifs] glass background neutralised on %@", name);
                }
            }
            node = node.superview;
            hops++;
        }
    } @catch (id exception) {
    }
}

@end

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
                return;
            }
        }
        UIImage* glyph = nil;
        if ([UIImage respondsToSelector:@selector(tfn_vectorImageNamed:fitsSize:fillColor:)]) {
            glyph = [UIImage tfn_vectorImageNamed:@"eye_off"
                                         fitsSize:CGSizeMake(kNFBNotifEyeSide, kNFBNotifEyeSide)
                                        fillColor:[UIColor labelColor]];
        }
        if (!glyph) {
            glyph = [UIImage systemImageNamed:@"eye.slash"];
        }
        UITraitCollection* traits = viewController.traitCollection;
        NFBNotifEyeButton* plain = [NFBNotifEyeButton buttonWithType:UIButtonTypeCustom];
        [plain setImage:NFBNotifFlatGlyph(glyph, NFBNotifIconGrey(traits))
               forState:UIControlStateNormal];
        plain.frame = CGRectMake(0, 0, kNFBNotifEyeSide, kNFBNotifEyeSide);
        plain.accessibilityLabel = @"Hidden notifications";
        // UIButtonTypeCustom, so no system highlight tint can flash over it.
        plain.adjustsImageWhenHighlighted = NO;
        [plain addTarget:[NFBNotifQuickPresenter shared]
                  action:@selector(present:)
        forControlEvents:UIControlEventTouchUpInside];

        UIBarButtonItem* ours = [[UIBarButtonItem alloc] initWithCustomView:plain];
        ours.tag = kNFBNotifBarItemTag;
        SEL hideShared = NSSelectorFromString(@"setHidesSharedBackground:");
        if ([ours respondsToSelector:hideShared]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(ours, hideShared, YES);
        }
        NSMutableArray<UIBarButtonItem*>* items =
            [NSMutableArray arrayWithArray:item.rightBarButtonItems ?: @[]];
        [items addObject:ours];
        item.rightBarButtonItems = items;
        NFBDebugLog(@"[notifs] eye placed in the bar of %@ (%lu button(s))",
                    NSStringFromClass([viewController class]),
                    (unsigned long)items.count);
    } @catch (id exception) {
        NFBDebugLog(@"[notifs] eye placement abandoned - no consequence");
    }
}

%end

// MARK: - the button that was already there
//
// Measured in the binary, and visible in a view hierarchy capture:
//   T1URTTimelineNotificationCell  ->  dismissButton, setDismissButton:,
//                                      dismissButtonWasTapped, layoutSubviews
//   the cell already holds a TFNDismissButton at {413, 12}, 18x18, HIDDEN.
//
// So Twitter ships a dismiss button on every notification row and simply keeps
// it hidden. Revealing it costs nothing and depends on no gesture, no menu, no
// delegate and no proxy. The tap is already wired to a method of the cell,
// which is where the hide is performed.

static const char* kNFBNotifRevealedKey = "nfbNotifRevealedDismiss";
static const char* kNFBNotifGlyphKey    = "nfbNotifDismissGlyph";
static const CGFloat kNFBNotifDismissTarget = 44.0;   // touch target
static const CGFloat kNFBNotifDismissGlyph  = 15.0;   // glyph body
static const CGFloat kNFBNotifDismissInset  = 16.0;   // margin from the right edge
static const CGFloat kNFBNotifDismissTop    = 4.0;    // top of the cell

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
        // re-hide the button. How it is hidden cannot be proven statically, so
        // every route is covered - hidden flag, alpha, and a zero frame - and
        // the button is marked so the tap handler recognises it.
        BOOL changed = NO;
        if (dismiss.hidden) { dismiss.hidden = NO; changed = YES; }
        if (dismiss.alpha < 0.5) { dismiss.alpha = 1.0; changed = YES; }
        dismiss.userInteractionEnabled = YES;

        // A 44 pt touch target, Apple's minimum, with the glyph itself staying
        // small at 22, and a 16 pt margin so the button lines up with the bell
        // on the left instead of hugging the screen edge at 9 pt.
        CGFloat side = kNFBNotifDismissTarget;
        CGRect wanted = CGRectMake(((UIView*)self).bounds.size.width - side - kNFBNotifDismissInset,
                                   kNFBNotifDismissTop, side, side);
        if (!CGRectEqualToRect(dismiss.frame, wanted)) {
            dismiss.frame = wanted;
            changed = YES;
        }

        // The cross replaces the ellipsis: this is not a "more options" menu.
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
                NFBDebugLog(@"[notifs] x button revealed on the notification");
            }
        }
    } @catch (id exception) {
    }
}

- (void)dismissButtonWasTapped {
    // One decision, taken outside the fence, so %orig is never called from
    // inside a protected block: either the hide ran here, or Twitter acts.
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
                NFBDebugLog(@"[notifs] x: hidden <%@>", identity);
                NFBNotifDropRow(source, indexPath);
                NFBShowNotifToast(identity);
                handled = YES;
            } else {
                NFBDebugLog(@"[notifs] x: row or identity not found - "
                            @"action left to Twitter");
            }
        } @catch (id exception) {
            NFBDebugLog(@"[notifs] x: hide interrupted - action left to Twitter");
        }
    }
    if (!handled) {
        %orig;
    }
}

%end
