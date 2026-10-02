// Hide a notification: swipe or x on a row, a registry that expires on its own,
// a sweep that keeps hidden rows out of the list, an empty-state panel, and the
// hidden list reachable from the bar. Nothing is deleted server side.

#import "Support/HookHelpers.h"
#import "Debug/PFBDebugger.h"
#import <QuartzCore/QuartzCore.h>
#import "Support/TwitterChirpFont.h"

static NSString* const kPFBHiddenNotifsKey = @"pfb_hidden_notifs";
static NSString* const kPFBNotifHorizonKey = @"pfb_notif_horizon_days";
static NSString* const kPFBHideNotifsEnabledKey = @"hide_notifications";


// Absent key ⇒ ON. The feature must work on the very first build, before the
// settings row lands; once the row exists (default YES) the two agree.
static BOOL PFBNotifsEnabled(void) {
    id value = [[NSUserDefaults standardUserDefaults]
                   objectForKey:kPFBHideNotifsEnabledKey];
    return value ? [value boolValue] : YES;
}

// The notifications screen names itself: the filter below runs on it, so it
// records the controller it saw. The quick-access button uses that instead of
// guessing a class name.
static __weak UIViewController* gPFBNotifScreen;

// Writes the registry now. NSUserDefaults flushes when the system decides,
// usually at backgrounding, so a crash between hiding a notification and that
// flush loses it.
static void PFBWriteHiddenNotifs(NSDictionary* registry) {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    if (registry.count) {
        [defaults setObject:registry forKey:kPFBHiddenNotifsKey];
    } else {
        [defaults removeObjectForKey:kPFBHiddenNotifsKey];
    }
    [defaults synchronize];
}

static NSDictionary* PFBHiddenNotifs(void) {
    NSDictionary* stored =
        [[NSUserDefaults standardUserDefaults] dictionaryForKey:kPFBHiddenNotifsKey];
    return stored ?: @{};
}

double PFBNotifHorizonDays(void) {
    double stored = [[NSUserDefaults standardUserDefaults] doubleForKey:kPFBNotifHorizonKey];
    return stored > 0 ? stored : 30.0;
}

// Days left before the entry drops out on its own. Counted from the
// notification's own date when one can be read, otherwise from the moment it
// was hidden, and stated plainly in the UI rather than pretending to be exact.
double PFBNotifDaysLeft(NSDictionary* entry) {
    double base = [entry[@"d"] doubleValue];
    if (base <= 0) {
        base = [entry[@"h"] doubleValue];
    }
    if (base <= 0) {
        return PFBNotifHorizonDays();
    }
    double elapsed = ([[NSDate date] timeIntervalSince1970] - base) / 86400.0;
    double left = PFBNotifHorizonDays() - elapsed;
    return left > 0 ? left : 0;
}


// Purge on read: an entry past its horizon leaves by itself.
void PFBPurgeExpiredNotifs(void) {
    NSDictionary* current = PFBHiddenNotifs();
    if (!current.count) {
        return;
    }
    NSMutableDictionary* kept = [current mutableCopy];
    for (NSString* key in current) {
        if (PFBNotifDaysLeft(current[key]) <= 0) {
            [kept removeObjectForKey:key];
        }
    }
    if (kept.count != current.count) {
        PFBWriteHiddenNotifs(kept);
    }
}

NSArray<NSDictionary*>* PFBHiddenNotifList(void) {
    PFBPurgeExpiredNotifs();
    NSDictionary* current = PFBHiddenNotifs();
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

// The list filters what it is handed, and filtering empties the app's own sections,
// so unhiding changes nothing on screen by itself. The screen loads its top the way
// a pull does: loadTop: with its own pull control as the sender.
static void PFBNotifRefreshScreen(void) {
    UIViewController* screen = gPFBNotifScreen;
    SEL load = NSSelectorFromString(@"loadTop:");
    BOOL available = screen.isViewLoaded && [screen respondsToSelector:load];
    if (available) {
        SEL control = NSSelectorFromString(@"pullToLoadTopControl");
        id sender = [screen respondsToSelector:control]
                        ? ((id (*)(id, SEL))objc_msgSend)(screen, control)
                        : nil;
        ((void (*)(id, SEL, id))objc_msgSend)(screen, load, sender);
    }
    PFBDebugLog(@"[notifs] unhide: list refresh %@", available ? @"asked" : @"unavailable");
}

void PFBUnhideNotif(NSString* notifID) {
    NSMutableDictionary* current = [PFBHiddenNotifs() mutableCopy];
    [current removeObjectForKey:notifID];
    PFBWriteHiddenNotifs(current);
    PFBNotifRefreshScreen();
}

void PFBUnhideAllNotifs(void) {
    PFBWriteHiddenNotifs(nil);
    PFBNotifRefreshScreen();
}

// MARK: - Reading a notification without knowing its class

// A selector whose return type is not the expected one is never called: a guessed
// signature can make ARC retain an integer as if it were an object.

static id PFBNotifAsk(id target, SEL selector) {
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

static double PFBNotifAskNumber(id target, SEL selector) {
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

static NSString* PFBNotifString(id value) {
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
static SEL PFBNotifDiscover(id model, NSArray<NSString*>* wanted, char kind) {
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
                    if (PFBNotifString(PFBNotifAsk(model, selector)).length) {
                        winner = selector;
                    }
                } else {
                    double value = PFBNotifAskNumber(model, selector);
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

// A second key for the same notification, meant to survive a relaunch, built from
// the model's own description with hex addresses stripped. Used alongside the
// session identity below, never instead of it.
static NSString* PFBNotifDurableKey(id model) {
    if (!model) {
        return nil;
    }
    NSString* text = nil;
    @try {
        text = [model description];
    } @catch (id exception) {
        return nil;
    }
    if (text.length < 8) {
        return nil;
    }
    NSMutableString* stable = [text mutableCopy];
    NSRegularExpression* addresses =
        [NSRegularExpression regularExpressionWithPattern:@"0x[0-9a-fA-F]+"
                                                 options:0
                                                   error:NULL];
    [addresses replaceMatchesInString:stable
                              options:0
                                range:NSMakeRange(0, stable.length)
                         withTemplate:@""];
    // The class name is stripped too and what is left must still say something: a
    // model answering only the default <Class: 0x...> would give every notification
    // of that class the same key. Without it the session identity is used alone.
    NSString* className = NSStringFromClass([model class]);
    if (className.length) {
        [stable replaceOccurrencesOfString:className
                                withString:@""
                                   options:0
                                     range:NSMakeRange(0, stable.length)];
    }
    NSCharacterSet* noise =
        [NSCharacterSet characterSetWithCharactersInString:@"<>: \t\n"];
    NSString* meat = [[stable componentsSeparatedByCharactersInSet:noise]
        componentsJoinedByString:@""];
    if (meat.length < 12) {
        return nil;
    }
    return [NSString stringWithFormat:@"dk:%lu/%lu", (unsigned long)meat.hash,
                                      (unsigned long)meat.length];
}

// The entry id is printed in the model's description even when no accessor
// returns it, so it is read there before any accessor is asked.

// Its middle is rewritten on every refresh; only this many trailing characters
// were measured to stay put, so the key is built from them.
static const NSUInteger kPFBNotifIdTail = 8;

static NSString* PFBNotifEntryIdFromDescription(id model) {
    NSString* text = [model description];
    if (!text.length) {
        return nil;
    }
    static NSRegularExpression* pattern;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      pattern = [NSRegularExpression
          regularExpressionWithPattern:@"entryId[:= ]+([A-Za-z0-9_-]{8,})"
                               options:0
                                 error:NULL];
    });
    NSTextCheckingResult* match =
        [pattern firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    if (!match || match.numberOfRanges < 2) {
        return nil;
    }
    NSString* entryId = [text substringWithRange:[match rangeAtIndex:1]];
    // The middle of the id is rewritten on every refresh while its tail stays
    // put, so only the tail serves as a key.
    if (entryId.length <= kPFBNotifIdTail) {
        return entryId;
    }
    return [entryId substringFromIndex:entryId.length - kPFBNotifIdTail];
}

// Marks a class whose identity is read from the description rather than from
// an accessor, so the cache does not try to message a selector that is not one.
static NSString* const kPFBIdentityFromDescription = @"<description>";

static NSString* PFBNotifIdentity(id model) {
    static NSMutableDictionary<NSString*, NSString*>* cache;
    if (!cache) { cache = [NSMutableDictionary dictionary]; }
    NSString* className = NSStringFromClass([model class]);
    NSString* known = cache[className];
    if ([known isEqualToString:kPFBIdentityFromDescription]) {
        return PFBNotifEntryIdFromDescription(model);
    }
    if (known) {
        return PFBNotifString(PFBNotifAsk(model, NSSelectorFromString(known)));
    }
    NSString* fromDescription = PFBNotifEntryIdFromDescription(model);
    if (fromDescription.length) {
        cache[className] = kPFBIdentityFromDescription;
        return fromDescription;
    }
    // Durable names first, the ones inside scribeItem and then the usual entry
    // ids. The impression id is the last resort: it is minted per display, so a key
    // written from it never matches on a later pass.
    id scribeItem = PFBNotifAsk(model, NSSelectorFromString(@"scribeItem"));
    if (scribeItem && ![scribeItem isKindOfClass:[NSString class]]) {
        NSArray<NSString*>* inner = @[@"entryId", @"entryID", @"id", @"itemId",
                                      @"itemID", @"restId", @"identifier",
                                      @"tweetId", @"userId", @"notificationId"];
        for (NSString* name in inner) {
            NSString* value = PFBNotifString(PFBNotifAsk(scribeItem,
                                                         NSSelectorFromString(name)));
            if (value.length) {
                return [@"si:" stringByAppendingString:value];
            }
        }
    }
    NSArray<NSString*>* candidates = @[
        @"entryId", @"entryID", @"identifier", @"notificationId", @"notificationID",
        @"id", @"sortIndex", @"key", @"itemIdentifier",
        @"scribeItemImpressionID", @"scribeItemImpressionId"
    ];
    for (NSString* name in candidates) {
        NSString* value = PFBNotifString(PFBNotifAsk(model, NSSelectorFromString(name)));
        if (value.length) {
            cache[className] = name;
            return value;
        }
    }
    SEL found = PFBNotifDiscover(model, @[@"entryid", @"identifier", @"sortindex",
                                          @"itemid", @"restid"], '@');
    if (found) {
        cache[className] = NSStringFromSelector(found);
        return PFBNotifString(PFBNotifAsk(model, found));
    }
    return nil;
}

static double PFBNotifDate(id model) {
    NSArray<NSString*>* candidates = @[
        @"timestamp", @"sortTimestamp", @"createdAt", @"date", @"sortDate",
        @"timeInMs", @"createdAtMs", @"time"
    ];
    for (NSString* name in candidates) {
        double value = PFBNotifAskNumber(model, NSSelectorFromString(name));
        if (value > 1420000000 && value < 2050000000) {
            return value;
        }
        if (value > 1420000000000.0 && value < 2050000000000.0) {
            return value / 1000.0;
        }
    }
    SEL found = PFBNotifDiscover(model, @[@"date", @"time", @"created", @"sort"], 'd');
    if (found) {
        double discovered = PFBNotifAskNumber(model, found);
        return discovered > 1420000000000.0 ? discovered / 1000.0 : discovered;
    }
    return 0;
}

static NSString* PFBNotifText(id model) {
    NSArray<NSString*>* candidates = @[
        @"text", @"message", @"displayText", @"bodyText", @"title",
        @"formattedText", @"attributedText", @"summary", @"notificationText"
    ];
    for (NSString* name in candidates) {
        NSString* value = PFBNotifString(PFBNotifAsk(model, NSSelectorFromString(name)));
        if (value.length > 2) {
            return value;
        }
    }
    SEL found = PFBNotifDiscover(model, @[@"text", @"title", @"message", @"body",
                                          @"summary"], '@');
    if (found) {
        return PFBNotifString(PFBNotifAsk(model, found));
    }
    return nil;
}

BOOL PFBNotifIsHidden(id model) {
    if (!model) {
        return NO;
    }
    NSDictionary* hidden = PFBHiddenNotifs();
    if (!hidden.count) {
        return NO;   // the hot path costs one dictionary read
    }
    NSString* durableKey = PFBNotifDurableKey(model);
    if (durableKey.length && hidden[durableKey] != nil) {
        return YES;
    }
    // Read once and reused below: this call walks the model.
    NSString* identity = PFBNotifIdentity(model);
    if (identity.length) {
        for (NSDictionary* entry in hidden.allValues) {
            if (![entry isKindOfClass:[NSDictionary class]]) {
                continue;
            }
            // Type-checked: entries written before this key existed carry
            // nothing here, and a value of another kind would not answer
            // isEqualToString:.
            id session = entry[@"s"];
            if ([session isKindOfClass:[NSString class]] &&
                [session isEqualToString:identity]) {
                return YES;
            }
        }
    }
    return identity.length && hidden[identity] != nil;
}


// This view model carries no text either (same measurement), so the wording
// shown in the hidden list is read from the CELL at the moment of hiding —
// its labels are the only place the notification's words exist.
static NSString* PFBNotifTextFromCell(UITableView* table, NSIndexPath* indexPath) {
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


// The notification's own date, which the countdown hangs on. The model exposes no
// date and the timestamp view is Swift, so the date is recovered from the age the
// cell renders: relative forms (30s, 5h, 1w) and absolute ones. 0 when unreadable.
static NSTimeInterval PFBNotifDateFromDisplayedAge(NSString* text) {
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

static void PFBHideNotifWithText(id model, NSString* cellText) {
    NSString* identity = PFBNotifIdentity(model);
    if (!identity.length) {
        PFBDebugLog(@"[notifs] no readable identity - hide refused");
        return;
    }
    NSMutableDictionary* current = [PFBHiddenNotifs() mutableCopy];
    NSString* text = PFBNotifText(model) ?: (cellText ?: @"");
    if (text.length > 140) {
        text = [text substringToIndex:140];
    }
    // "d" is the notification's own date. The model has none, so it comes from
    // the age the cell displays; the countdown and the expiry date both read
    // "d" first and only fall back to "h", the moment it was hidden.
    NSTimeInterval notifDate = PFBNotifDate(model);
    if (notifDate <= 0) {
        notifDate = PFBNotifDateFromDisplayedAge(cellText ?: text);
    }
    // One entry per notification: the registry is keyed by the durable key when
    // there is one, and the session identity rides inside the value so the filter
    // can match either.
    NSString* durable = PFBNotifDurableKey(model);
    NSMutableDictionary* entry = [@{
        @"t": text,
        @"d": @(notifDate),
        @"h": @([[NSDate date] timeIntervalSince1970])
    } mutableCopy];
    entry[@"s"] = identity;
    [current removeObjectForKey:identity];
    current[durable.length ? durable : identity] = entry;
    PFBWriteHiddenNotifs(current);
    PFBDebugLog(@"[notifs] hidden <%@> - %lu total",
                identity, (unsigned long)current.count);
}

// MARK: - The toast (the capsule shared with Hidden Threads)

static const NSInteger kPFBNotifToastTag = 90313;

static void PFBDismissNotifToast(UIView* toast) {
    [UIView animateWithDuration:0.22
        animations:^{
          toast.alpha = 0;
          toast.transform = CGAffineTransformMakeTranslation(0.0, -8.0);
        }
        completion:^(__unused BOOL finished) {
          [toast removeFromSuperview];
        }];
}

static void PFBShowNotifToast(NSString* notifID) {
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
    [[window viewWithTag:kPFBNotifToastTag] removeFromSuperview];

    BOOL liquidGlass = [PFBSettings boolForKey:@"enable_liquid_glass"];
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
    toast.tag = kPFBNotifToastTag;
    toast.translatesAutoresizingMaskIntoConstraints = NO;
    toast.layer.cornerRadius = 22.0;
    toast.layer.cornerCurve = kCACornerCurveContinuous;
    if (!liquidGlass) {
        toast.clipsToBounds = YES;
        toast.layer.borderWidth = 0.5;
        toast.layer.borderColor = [UIColor separatorColor].CGColor;
    }
    // The material alone is thin enough for the navigation title to read through
    // the text, so a veil at 80 % sits behind the content.
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
    label.text = [[PFBBundle sharedBundle] localizedStringForKey:@"NOTIFS_HIDDEN_TOAST"];
    label.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:15]);
    label.textColor = [UIColor labelColor];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:label];

    UIButton* undo = [UIButton buttonWithType:UIButtonTypeSystem];
    [undo setTitle:[[PFBBundle sharedBundle] localizedStringForKey:@"THREADS_UNDO"]
          forState:UIControlStateNormal];
    extern UIColor* PFBCurrentAccentColor(void);
    [undo setTitleColor:PFBCurrentAccentColor() ?: [UIColor labelColor]
               forState:UIControlStateNormal];
    undo.titleLabel.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleSemibold) fontWithSize:15]);
    undo.translatesAutoresizingMaskIntoConstraints = NO;
    [undo addAction:[UIAction actionWithHandler:^(__unused UIAction* action) {
              PFBUnhideNotif(notifID);
              PFBDismissNotifToast(toast);
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
                         PFBDismissNotifToast(toast);
                     }
                   });
}

// MARK: - The swipe, on the list's own delegate

// The action is appended to whatever Twitter already returns, so nothing native
// is dropped and an empty return carries the added action alone.

// Ask the CELL. The delegate is a shared proxy and the data source is the
// controller, and neither of them yields the row, so the cell is the one
// object that certainly holds its own model.
static id PFBModelFromCell(UITableView* table, NSIndexPath* indexPath) {
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
        id model = PFBUnwrapDataViewItem(value) ?: value;
        if (model) {
            return model;
        }
    }
    return nil;
}

static id PFBModelAtIndexPath(id dataViewController, NSIndexPath* indexPath) {
    SEL itemSel = NSSelectorFromString(@"itemAtIndexPath:");
    if ([dataViewController respondsToSelector:itemSel]) {
        id item = ((id (*)(id, SEL, id))objc_msgSend)(dataViewController, itemSel, indexPath);
        id model = PFBUnwrapDataViewItem(item);
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
    return PFBUnwrapDataViewItem(items[indexPath.row]);
}


// TFNItemsDataViewController implements -deleteItemAtIndexPath:withRowAnimation:,
// so a hidden row leaves the list on the spot rather than waiting for a sections
// replay. The registry and filter still handle later reloads.
static void PFBNotifSyncEmptyState(id dataViewController);
static const char* kPFBNotifVerdictKey = "pfbNotifSweepVerdict";
static const char* kPFBNotifEverFilledKey = "pfbNotifEverFilled";

static void PFBNotifDropRow(id dataViewController, NSIndexPath* indexPath) {
    if (!dataViewController || !indexPath) {
        return;
    }
    @try {
        SEL deleteSel = NSSelectorFromString(@"deleteItemAtIndexPath:withRowAnimation:");
        if ([dataViewController respondsToSelector:deleteSel]) {
            ((void (*)(id, SEL, id, NSInteger))objc_msgSend)(
                dataViewController, deleteSel, indexPath, UITableViewRowAnimationLeft);
            PFBDebugLog(@"[notifs] row removed from the list (%ld/%ld)",
                        (long)indexPath.section, (long)indexPath.row);
            PFBCOMPAT_ACTION(PFBCompat_hide_notifications, @"notification hidden");
            // A hide from this list proves it is the notifications screen: it is the one
            // an unhide refreshes, and its verdict gates the empty-state sync.
            gPFBNotifScreen = (UIViewController*)dataViewController;
            if (!objc_getAssociatedObject(dataViewController, kPFBNotifVerdictKey)) {
                objc_setAssociatedObject(dataViewController, kPFBNotifVerdictKey, @YES,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                PFBDebugLog(@"[notifs] verdict recorded on removal - notifications screen");
            }
            // Deferred: the row count is only truthful once the delete animation
            // has finished, so a second pass follows the first.
            dispatch_async(dispatch_get_main_queue(), ^{
                PFBNotifSyncEmptyState(dataViewController);
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                             PFBNotifSyncEmptyState(dataViewController);
                           });
            return;
        }
        PFBDebugLog(@"[notifs] direct removal unavailable on %@",
                    NSStringFromClass([dataViewController class]));
    } @catch (id exception) {
        PFBDebugLog(@"[notifs] direct removal refused - the row goes on reload");
    }
}

%hook T1URTViewController

- (UISwipeActionsConfiguration*)tableView:(UITableView*)tableView
    trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath*)indexPath {
    UISwipeActionsConfiguration* original = %orig;
    if (!PFBNotifsEnabled()) {
        PFBCOMPAT_OBSERVE(PFBCompat_hide_notifications, @"notification swipe seen");
        return original;
    }
    id model = PFBModelAtIndexPath(self, indexPath) ?: PFBModelFromCell(tableView, indexPath);
    // Only rows that carry a notification and can be named: one that cannot be
    // identified could never be unhidden. Each refusal is journaled once with its
    // reason.
    NSString* modelClass = model ? NSStringFromClass([model class]) : @"(none)";
    if (!model) {
        static BOOL saidNoModel;
        if (!saidNoModel) {
            saidNoModel = YES;
            PFBDebugLog(@"[notifs] swipe: no model at row %ld/%ld - "
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
            PFBDebugLog(@"[notifs] swipe: unrecognised class \"%@\" - no action added",
                        modelClass);
        }
        return original;
    }
    if (!PFBNotifIdentity(model)) {
        static BOOL saidNoIdentity;
        if (!saidNoIdentity) {
            saidNoIdentity = YES;
            PFBDebugLog(@"[notifs] swipe: %@ has no readable identity - action refused",
                        modelClass);
        }
        return original;
    }
    static BOOL saidArmed;
    if (!saidArmed) {
        saidArmed = YES;
        PFBDebugLog(@"[notifs] swipe: \"Hide\" action added on %@", modelClass);
    }

    NSString* title = [[PFBBundle sharedBundle] localizedStringForKey:@"NOTIFS_HIDE_ACTION"];
    UIContextualAction* hide = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleDestructive
                            title:title
                          handler:^(__unused UIContextualAction* action,
                                    __unused UIView* sourceView,
                                    void (^completion)(BOOL)) {
            NSString* identity = PFBNotifIdentity(model);
            PFBHideNotifWithText(model, PFBNotifTextFromCell(tableView, indexPath));
            completion(YES);
            PFBNotifDropRow(self, indexPath);
            PFBShowNotifToast(identity);
        }];
    hide.backgroundColor = [UIColor systemGrayColor];
    UIImage* glyph = PFBTwitterGlyphFor(@"eye_off", [UIImage systemImageNamed:@"eye.slash.fill"]);
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

// The sections are filtered on their way in. An id in the registry can only belong
// to a hidden notification, so the filter needs no scoping of its own.
static NSArray* PFBFilterNotifSections(NSArray* sections) {
    if (!PFBNotifsEnabled()) {
        return sections;
    }
    if (!PFBHiddenNotifs().count) {
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
            if (PFBNotifIsHidden(PFBUnwrapDataViewItem(item))) {
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


// MARK: - the sweep

// No section class exposes -items in Objective-C, so the section filter reaches
// no rows. TFNItemsDataViewController implements -itemAtIndexPath:, so the rows
// are walked after each content replacement and the hidden ones deleted.


// Which screens the sweep may touch, decided by observation rather than by class
// name. One notification model keeps a controller, several without drops it, and
// the home timeline is then never walked again.
static BOOL PFBNotifSweepAllowed(id dataViewController) {
    id verdict = objc_getAssociatedObject(dataViewController, kPFBNotifVerdictKey);
    return verdict ? [verdict boolValue] : YES;   // undecided: observe once
}

static void PFBNotifRecordVerdict(id dataViewController, BOOL sawNotification,
                                  NSInteger examined) {
    if (objc_getAssociatedObject(dataViewController, kPFBNotifVerdictKey)) {
        return;
    }
    if (sawNotification) {
        objc_setAssociatedObject(dataViewController, kPFBNotifVerdictKey, @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        gPFBNotifScreen = (UIViewController*)dataViewController;
        PFBDebugLog(@"[sweep] %@ kept - this is the notifications screen",
                    NSStringFromClass([dataViewController class]));
        return;
    }
    // A screen belonging to the notifications tab is never condemned: it could be
    // dropped for showing placeholder rows before its notifications arrive. Staying
    // undecided costs one extra walk; being wrong costs the feature.
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
        objc_setAssociatedObject(dataViewController, kPFBNotifVerdictKey, @NO,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

// MARK: - the empty panel

// Two UILabels in a container, nothing borrowed: an internal view such as
// TFNEmptyStateView carries invariants unknowable from outside, and a bad access
// is not caught by @try. Anchored on the sweep's verdict.

static const NSInteger kPFBNotifEmptyTag = 90315;
static const NSInteger kPFBNotifEmptyTitleTag = 90316;
static const NSInteger kPFBNotifEmptyBodyTag = 90317;

// textDetailsColor is the palette entry Twitter uses for secondary copy. It is
// not declared in src/Headers, so this declaration shim serves as a cast
// target. Never instantiated, never messaged as a class.
@interface PFBNotifPaletteShim : NSObject
- (UIColor*)textDetailsColor;
@end

// The secondary gray Twitter draws with, taken from the live palette so it
// follows light and dark. secondaryLabelColor is warmer and reads as a different
// color beside the native empty state.
static UIColor* PFBNotifDetailColor(void) {
    Class settingsClass = objc_getClass("TAEColorSettings");
    if (settingsClass) {
        id settings = [settingsClass sharedSettings];
        id current = [settings currentColorPalette];
        id palette = [current colorPalette];
        if ([palette respondsToSelector:@selector(textDetailsColor)]) {
            UIColor* colour = [(PFBNotifPaletteShim*)palette textDetailsColor];
            if ([colour isKindOfClass:[UIColor class]]) {
                return colour;
            }
        }
    }
    return [UIColor secondaryLabelColor];
}

// Twitter composes in Chirp, and sets these large empty-state headlines in Heavy.
// The font group is reached the way the settings screens reach it; the system font
// is the fallback.
static UIFont* PFBNotifEmptyFont(CGFloat size, BOOL heavy) {
    id group = [PFBManager sharedFontGroup];
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
    return heavy ? PFBScaledFont([TwitterChirpFont(TwitterFontStyleBold) fontWithSize:size])
                 : PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:size]);
}

// Geometry and type taken from the native empty state: 18 pt of side inset, a
// 30 pt title face, a 15 pt body face and an 8 pt gap between them.
static const CGFloat kPFBNotifEmptyTopInset = 36.0;
static const CGFloat kPFBNotifEmptySideInset = 18.0;
static const CGFloat kPFBNotifEmptyGap = 8.0;
static const CGFloat kPFBNotifEmptyTitleSize = 30.0;
static const CGFloat kPFBNotifEmptyBodySize = 15.0;

// Places the panel with frames in the table's content coordinate space, so it
// travels with the list; pinned to frameLayoutGuide it would stay welded to the
// viewport. Auto Layout is avoided: a table view owns its own content size.
static void PFBNotifLayoutEmptyPanel(UIView* panel, UITableView* table) {
    UILabel* title = (UILabel*)[panel viewWithTag:kPFBNotifEmptyTitleTag];
    UILabel* body = (UILabel*)[panel viewWithTag:kPFBNotifEmptyBodyTag];
    if (![title isKindOfClass:[UILabel class]] ||
        ![body isKindOfClass:[UILabel class]]) {
        return;
    }
    CGFloat tableWidth = CGRectGetWidth(table.bounds);
    CGFloat width = tableWidth - (kPFBNotifEmptySideInset * 2.0);
    if (width < 80.0) {
        return;                       // no room to read anything; leave as is
    }
    body.textColor = PFBNotifDetailColor();
    CGSize titleSize = [title sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)];
    CGSize bodySize = [body sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)];
    title.frame = CGRectMake(0.0, 0.0, width, ceil(titleSize.height));
    body.frame = CGRectMake(0.0, CGRectGetMaxY(title.frame) + kPFBNotifEmptyGap,
                            width, ceil(bodySize.height));
    panel.frame = CGRectMake(kPFBNotifEmptySideInset,
                             kPFBNotifEmptyTopInset,
                             width, CGRectGetMaxY(body.frame));
}

static void PFBNotifSyncEmptyState(id dataViewController) {
    if (!dataViewController) {
        return;
    }
    // The verdict the sweep earned by observation — never a class-name guess.
    id verdict = objc_getAssociatedObject(dataViewController, kPFBNotifVerdictKey);
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
            PFBDebugLog(@"[empty] no table on %@",
                        NSStringFromClass([dataViewController class]));
            return;
        }
        // The raw row count is the wrong measure: a header, a footer or a
        // zero-height cell leaves one row on a visibly empty screen. Emptiness is
        // decided by how many rows carry a notification model.
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
                id model = item ? PFBUnwrapDataViewItem(item) : nil;
                if (model && [NSStringFromClass([model class])
                                 containsString:@"Notification"]) {
                    notifRows++;
                }
            }
        }
        UIView* existing = [table viewWithTag:kPFBNotifEmptyTag];
        NSUInteger hidden = PFBHiddenNotifs().count;

        // A table that has not delivered anything yet is loading, not emptied (a
        // relaunch before the list arrives): the panel waits for the first rows.
        NSNumber* everFilled = objc_getAssociatedObject(dataViewController,
                                                        kPFBNotifEverFilledKey);
        if (rows > 0) {
            everFilled = @YES;
            objc_setAssociatedObject(dataViewController, kPFBNotifEverFilledKey, @YES,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (![everFilled isEqual:@YES]) {
            if (existing) {
                [existing removeFromSuperview];
            }
            return;
        }
        if (notifRows > 0 || hidden == 0) {
            if (existing) {
                // The panel fades out the way it came in. Its tag goes first, so no
                // later pass finds it mid-fade.
                existing.tag = 0;
                [UIView animateWithDuration:0.3
                    animations:^{
                      existing.alpha = 0.0;
                    }
                    completion:^(__unused BOOL finished) {
                      [existing removeFromSuperview];
                    }];
                PFBDebugLog(@"[empty] panel removed");
            }
            return;
        }
        if (existing) {
            // A width change (rotation, split view) moves the panel; the frames
            // are recomputed rather than left stale.
            PFBNotifLayoutEmptyPanel(existing, table);
            return;
        }

        UIView* panel = [[UIView alloc] init];
        panel.tag = kPFBNotifEmptyTag;
        panel.userInteractionEnabled = NO;    // never blocks a pull-to-refresh
        panel.autoresizingMask = UIViewAutoresizingFlexibleWidth;

        UILabel* title = [[UILabel alloc] init];
        title.tag = kPFBNotifEmptyTitleTag;
        title.text = [[PFBBundle sharedBundle]
                         localizedStringForKey:@"HIDDEN_NOTIFS_EMPTY_TITLE"];
        title.font = PFBNotifEmptyFont(kPFBNotifEmptyTitleSize, YES);
        title.textColor = [UIColor labelColor];
        title.textAlignment = NSTextAlignmentNatural;
        title.numberOfLines = 0;
        [panel addSubview:title];

        UILabel* body = [[UILabel alloc] init];
        body.tag = kPFBNotifEmptyBodyTag;
        body.text = [[PFBBundle sharedBundle]
                        localizedStringForKey:@"HIDDEN_NOTIFS_EMPTY_BODY"];
        body.font = PFBNotifEmptyFont(kPFBNotifEmptyBodySize, NO);
        body.textColor = PFBNotifDetailColor();
        body.textAlignment = NSTextAlignmentNatural;
        body.numberOfLines = 0;
        [panel addSubview:body];

        // Faded in rather than popped, and timed to land as the last row finishes
        // sliding out, so the two read as one motion instead of a flash.
        panel.alpha = 0.0;
        [table addSubview:panel];
        PFBNotifLayoutEmptyPanel(panel, table);
        [UIView animateWithDuration:0.3
                              delay:0.15
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{
                           panel.alpha = 1.0;
                         }
                         completion:nil];
        PFBDebugLog(@"[empty] PANEL PLACED");
    } @catch (id exception) {
        PFBDebugLog(@"[empty] exception: %@", exception);
    }
}

static BOOL gPFBNotifSweeping;

static void PFBNotifSweep(id dataViewController) {
    if (gPFBNotifSweeping || !PFBNotifsEnabled() || !dataViewController) {
        return;
    }
    if (!PFBHiddenNotifs().count) {
        // Everything was brought back: the panel must go, so the sync still runs.
        PFBNotifSyncEmptyState(dataViewController);
        return;
    }
    if (!PFBNotifSweepAllowed(dataViewController)) {
        return;              // screen already ruled out — nothing to walk
    }
    SEL itemSel = NSSelectorFromString(@"itemAtIndexPath:");
    SEL deleteSel = NSSelectorFromString(@"deleteItemAtIndexPath:withRowAnimation:");
    if (![dataViewController respondsToSelector:itemSel] ||
        ![dataViewController respondsToSelector:deleteSel]) {
        return;
    }
    gPFBNotifSweeping = YES;              // deleting triggers updates: no recursion
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
            gPFBNotifSweeping = NO;
            return;
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
                id model = item ? PFBUnwrapDataViewItem(item) : nil;
                if (model) {
                    examined++;
                    if ([NSStringFromClass([model class]) containsString:@"Notification"]) {
                        sawNotification = YES;
                    }
                }
                if (model && PFBNotifIsHidden(model)) {
                    [doomed addObject:path];
                }
            }
        }
        // From the end, so earlier index paths stay valid.
        for (NSIndexPath* path in [doomed reverseObjectEnumerator]) {
            ((void (*)(id, SEL, id, NSInteger))objc_msgSend)(
                dataViewController, deleteSel, path, UITableViewRowAnimationNone);
        }
        PFBNotifRecordVerdict(dataViewController, sawNotification, examined);
        PFBNotifSyncEmptyState(dataViewController);
        if (doomed.count) {
            PFBCOMPAT_ACTION(PFBCompat_hide_notifications, @"hidden notification removed");
        }
    } @catch (id exception) {
        PFBDebugLog(@"[notifs] sweep interrupted - no consequence");
    }
    gPFBNotifSweeping = NO;
}

// Measured: T1URTViewController implements NEITHER -sections NOR -setSections:.
// Both are inherited from TFNItemsDataViewController, so the filter belongs
// there — hooking the subclass meant it could never speak.
%hook TFNItemsDataViewController

- (void)setSections:(NSArray*)sections restoreScrollPosition:(BOOL)restore {
    %orig(PFBFilterNotifSections(sections), restore);
    // The list is in place: remove what is hidden.
    __weak id host = self;
    dispatch_async(dispatch_get_main_queue(), ^{
      id alive = host;
      if (alive) {
          PFBNotifSweep(alive);
      }
    });
}

- (void)setSections:(NSArray*)sections {
    %orig(PFBFilterNotifSections(sections));
    // The list is in place: remove what is hidden.
    __weak id host = self;
    dispatch_async(dispatch_get_main_queue(), ^{
      id alive = host;
      if (alive) {
          PFBNotifSweep(alive);
      }
    });
}

- (void)updateSections:(NSArray*)sections {
    %orig(PFBFilterNotifSections(sections));
    // The list is in place: remove what is hidden.
    __weak id host = self;
    dispatch_async(dispatch_get_main_queue(), ^{
      id alive = host;
      if (alive) {
          PFBNotifSweep(alive);
      }
    });
}

// The four below complete the filter: these are the content-replacement entry
// points TFNItemsDataViewController implements. Covering fewer lets hidden rows
// return on a refresh.

- (void)updateSections:(NSArray*)sections completion:(id)completion {
    %orig(PFBFilterNotifSections(sections), completion);
    // The list is in place: remove what is hidden.
    __weak id host = self;
    dispatch_async(dispatch_get_main_queue(), ^{
      id alive = host;
      if (alive) {
          PFBNotifSweep(alive);
      }
    });
}

- (void)updateSections:(NSArray*)sections withRowAnimation:(NSInteger)animation {
    %orig(PFBFilterNotifSections(sections), animation);
    // The list is in place: remove what is hidden.
    __weak id host = self;
    dispatch_async(dispatch_get_main_queue(), ^{
      id alive = host;
      if (alive) {
          PFBNotifSweep(alive);
      }
    });
}

- (void)updateSections:(NSArray*)sections
      withRowAnimation:(NSInteger)animation
            completion:(id)completion {
    %orig(PFBFilterNotifSections(sections), animation, completion);
    // The list is in place: remove what is hidden.
    __weak id host = self;
    dispatch_async(dispatch_get_main_queue(), ^{
      id alive = host;
      if (alive) {
          PFBNotifSweep(alive);
      }
    });
}

- (void)updateSections:(NSArray*)sections
reconfigureItemIdentifiers:(id)identifiers
      withRowAnimation:(NSInteger)animation
            completion:(id)completion {
    %orig(PFBFilterNotifSections(sections), identifiers, animation, completion);
    // The list is in place: remove what is hidden.
    __weak id host = self;
    dispatch_async(dispatch_get_main_queue(), ^{
      id alive = host;
      if (alive) {
          PFBNotifSweep(alive);
      }
    });
}

%end

// MARK: - Quick access, the pattern shared with muted words

// TFNNavigationBar is generic, so the screen names itself instead: the filter
// above records the controller it ran on, and a bar belongs to notifications when
// its owner is that controller or an ancestor. No match means no button.


@interface PFBNotifQuickPresenter : NSObject
+ (instancetype)shared;
- (void)present:(UIButton*)sender;
@end

@implementation PFBNotifQuickPresenter

+ (instancetype)shared {
    static PFBNotifQuickPresenter* instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[PFBNotifQuickPresenter alloc] init];
    });
    return instance;
}

// The sender can be a UIBarButtonItem, which is not a view: it answers neither
// -bounds nor -nextResponder. Both kinds are handled here, and the host
// controller does not come from the sender.
- (void)present:(id)sender {
    Class screenClass = NSClassFromString(@"PFBHiddenNotificationsViewController");
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
        // Load the view now so viewDidLoad, reload and preferredContentSize all run
        // before the popover picks its position, otherwise it places itself against
        // a stale size.
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
            UIBarButtonItem* item = (UIBarButtonItem*)sender;
            UIView* anchor = item.customView;
            if (!anchor) {
                // An image item has no customView, and barButtonItem anchoring
                // draws no arrow inside this bar; its rendered view carries the
                // on-screen rect the arrow needs.
                @try {
                    UIView* rendered = [item valueForKey:@"view"];
                    if ([rendered isKindOfClass:[UIView class]]) {
                        anchor = rendered;
                    }
                } @catch (id exception) {
                }
            }
            if (anchor) {
                popover.sourceView = anchor;
                popover.sourceRect = anchor.bounds;
            } else {
                popover.barButtonItem = item;
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
            PFBDebugLog(@"[notifs] no host screen for the list - presentation cancelled");
            return;
        }
        [host presentViewController:controller animated:YES completion:nil];
        PFBDebugLog(@"[notifs] hidden list presented from %@",
                    NSStringFromClass([host class]));
    } @catch (id exception) {
        PFBDebugLog(@"[notifs] list presentation abandoned - no consequence");
    }
}

// Without this a popover becomes full screen on iPhone.
- (UIModalPresentationStyle)adaptivePresentationStyleForPresentationController:
    (__unused UIPresentationController*)controller {
    return UIModalPresentationNone;
}

@end


// MARK: - recognizing a hidden-capable row

// tableView:canEditRowAtIndexPath: is implemented only by the accounts and drafts
// controllers, never by the notifications list, so nothing refuses the swipe there
// and no answer has to be forced.

static BOOL PFBNotifRowIsOursInTable(id dataViewController, UITableView* table,
                                     NSIndexPath* indexPath);

// The row's model, from the data source or — failing that — from the cell.
static id PFBNotifModelForRow(id dataViewController, UITableView* table,
                              NSIndexPath* indexPath) {
    id model = PFBModelAtIndexPath(dataViewController, indexPath);
    if (!model) {
        model = PFBModelFromCell(table, indexPath);
        if (model) {
            static BOOL said;
            if (!said) {
                said = YES;
                PFBDebugLog(@"[notifs] model read from the cell (%@)",
                            NSStringFromClass([model class]));
            }
        }
    }
    return model;
}

// Every refusal names itself ONCE, so a decline can be diagnosed from the
// journal alone.
static BOOL PFBNotifRowIsOursInTable(id dataViewController, UITableView* table,
                                     NSIndexPath* indexPath) {
    if (!PFBNotifsEnabled()) {
        return NO;
    }
    id model = PFBNotifModelForRow(dataViewController, table, indexPath);
    if (!model) {
        static BOOL saidNoModel;
        if (!saidNoModel) {
            saidNoModel = YES;
            PFBDebugLog(@"[notifs] row %ld/%ld: NO model (source=%@) - "
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
            PFBDebugLog(@"[notifs] row carried by \"%@\" - not recognized as a notification",
                        modelClass);
        }
        return NO;
    }
    if (!PFBNotifIdentity(model)) {
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
            PFBDebugLog(@"[notifs] %@ has NO identity - selectors: %@", modelClass,
                        [names componentsJoinedByString:@" "]);
        }
        return NO;
    }
    return YES;
}


// MARK: - the optional-method cache

// A UITableView asks its delegate and data source which optional methods they
// answer once, when they are assigned, and caches the answer. So methods are
// installed before the assignment, and an already-wired table is re-assigned.

// MARK: - the eye

// Placed through T1TabNavigationController, the door that fires here. The glass
// is painted on UIKit's per-item wrapper, not on the glyph's own view, so the
// wrapper is walked up to and its background turned off.

static const NSInteger kPFBNotifBarItemTag = 90314;
static const CGFloat kPFBNotifEyeSide = 24.0;

static UIColor* PFBNotifIconGrey(UITraitCollection* traits) {
    UIColor* grey = [[UIColor labelColor] colorWithAlphaComponent:0.6];
    if (traits && [grey respondsToSelector:@selector(resolvedColorWithTraitCollection:)]) {
        return [grey resolvedColorWithTraitCollection:traits] ?: grey;
    }
    return grey;
}

// Flat bitmap + AlwaysOriginal: the theme's window tint cannot repaint it.
static UIImage* PFBNotifFlatGlyph(UIImage* source, UIColor* colour) {
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


%hook T1TabNavigationController

- (void)_t1_main_updateNavigationItemForViewController:(UIViewController*)viewController
                                                isRoot:(BOOL)isRoot
                           providingLeftBarButtonItems:(BOOL)left
                                 rightBarButtonItems:(BOOL)right {
    %orig;
    if (!PFBNotifsEnabled() || !viewController) {
        return;
    }
    @try {
        if (![NSStringFromClass([viewController class])
                containsString:@"NotificationsViewController"]) {
            return;
        }
        UINavigationItem* item = viewController.navigationItem;
        for (UIBarButtonItem* existing in item.rightBarButtonItems) {
            if (existing.tag == kPFBNotifBarItemTag) {
                return;
            }
        }
        UIImage* glyph = nil;
        if ([UIImage respondsToSelector:@selector(tfn_vectorImageNamed:fitsSize:fillColor:)]) {
            glyph = [UIImage tfn_vectorImageNamed:@"eye_off"
                                         fitsSize:CGSizeMake(kPFBNotifEyeSide, kPFBNotifEyeSide)
                                        fillColor:[UIColor labelColor]];
        }
        if (!glyph) {
            glyph = [UIImage systemImageNamed:@"eye.slash"];
        }
        // The color is read from the neighbouring gear, as the search filters
        // button does, so the two glyphs are drawn in the same ink.
        __block UIColor* ink = nil;
        for (UIBarButtonItem* neighbour in item.rightBarButtonItems) {
            if (neighbour.customView) {
                PFBEnumerateSubviewsRecursively(neighbour.customView, ^(UIView* view) {
                  if (!ink && [view isKindOfClass:[UIImageView class]] && view.tintColor) {
                      ink = view.tintColor;
                  }
                });
            } else if (neighbour.tintColor) {
                ink = neighbour.tintColor;
            }
            if (ink) {
                break;
            }
        }
        if (!ink) {
            ink = PFBNotifIconGrey(viewController.traitCollection);
        }
        // An image item, the same kind as the search filters button: the bar
        // gives both the same box and the same spacing next to the gear.
        UIBarButtonItem* ours = [[UIBarButtonItem alloc]
            initWithImage:PFBNotifFlatGlyph(glyph, ink)
                    style:UIBarButtonItemStylePlain
                   target:[PFBNotifQuickPresenter shared]
                   action:@selector(present:)];
        ours.tintColor = ink;
        ours.accessibilityLabel = @"Hidden notifications";
        ours.tag = kPFBNotifBarItemTag;
        SEL hideShared = NSSelectorFromString(@"setHidesSharedBackground:");
        if ([ours respondsToSelector:hideShared]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(ours, hideShared, YES);
        }
        NSMutableArray<UIBarButtonItem*>* items =
            [NSMutableArray arrayWithArray:item.rightBarButtonItems ?: @[]];
        [items addObject:ours];
        item.rightBarButtonItems = items;
    } @catch (id exception) {
        PFBDebugLog(@"[notifs] eye placement abandoned - no consequence");
    }
}

%end

// MARK: - the button that was already there

// Every notification cell already holds a hidden TFNDismissButton, wired to a
// method of the cell. Revealing it depends on no gesture, menu, delegate or
// proxy, and the hide is performed where the tap already lands.

static const char* kPFBNotifRevealedKey = "pfbNotifRevealedDismiss";
static const char* kPFBNotifGlyphKey    = "pfbNotifDismissGlyph";
static const char* kPFBNotifXmarkImageKey = "pfbNotifXmarkImage";
static const CGFloat kPFBNotifDismissTarget = 44.0;   // touch target
static const CGFloat kPFBNotifDismissGlyph  = 15.0;   // glyph body
static const CGFloat kPFBNotifDismissInset  = 16.0;   // margin from the right edge
static const CGFloat kPFBNotifDismissTop    = 4.0;    // top of the cell

// The table a cell lives in, walked from the cell itself.
static UITableView* PFBNotifTableForCell(UIView* cell) {
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

// A hidden notification is laid out between Twitter's delivery and the sweep that
// removes its row. Its cell is made transparent at every layout and held there
// against any opacity written back to it. The row is read the way the cross reads it.
static const char* kPFBNotifMaskedKey = "pfbNotifMasked";

static void PFBNotifMaskHiddenCell(UITableViewCell* cell) {
    BOOL hide = NO;
    if (PFBNotifsEnabled() && PFBHiddenNotifs().count) {
        @try {
            UITableView* table = PFBNotifTableForCell(cell);
            NSIndexPath* indexPath = table ? [table indexPathForCell:cell] : nil;
            id model = indexPath ? (PFBModelAtIndexPath(table.dataSource, indexPath)
                                    ?: PFBModelFromCell(table, indexPath))
                                 : nil;
            hide = model && PFBNotifIsHidden(model);
        } @catch (id exception) {
            hide = NO;
        }
    }
    BOOL masked = objc_getAssociatedObject(cell, kPFBNotifMaskedKey) != nil;
    if (hide) {
        if (!masked) {
            objc_setAssociatedObject(cell, kPFBNotifMaskedKey, @YES,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            static BOOL said;
            if (!said) {
                said = YES;
                PFBDebugLog(@"[notifs] hidden notification kept transparent until its row goes");
            }
        }
        [cell.layer removeAnimationForKey:@"opacity"];
        cell.alpha = 0;
    } else if (masked) {
        // The mark goes first: while it is set, the cell refuses any opacity.
        objc_setAssociatedObject(cell, kPFBNotifMaskedKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        cell.alpha = 1;
    }
}

%hook T1URTTimelineNotificationCell

- (void)setAlpha:(CGFloat)alpha {
    BOOL masked = objc_getAssociatedObject(self, kPFBNotifMaskedKey) != nil;
    if (masked && alpha > 0) {
        static BOOL said;
        if (!said) {
            said = YES;
            PFBDebugLog(@"[notifs] opacity written back on a hidden notification - held at 0");
        }
    }
    %orig(masked ? 0.0 : alpha);
}

- (void)layoutSubviews {
    %orig;
    PFBNotifMaskHiddenCell((UITableViewCell*)self);
    if (!PFBNotifsEnabled()) {
        return;
    }
    @try {
        id button = PFBNotifAsk(self, NSSelectorFromString(@"dismissButton"));
        if (![button isKindOfClass:[UIView class]]) {
            return;
        }
        UIView* dismiss = button;
        // How the button is hidden cannot be established statically, so every
        // route is covered: hidden flag, alpha and a zero frame. The button is
        // marked so the tap handler recognizes it.
        BOOL changed = NO;
        if (dismiss.hidden) { dismiss.hidden = NO; changed = YES; }
        if (dismiss.alpha < 0.5) { dismiss.alpha = 1.0; changed = YES; }
        dismiss.userInteractionEnabled = YES;

        // A 44 pt touch target, Apple's minimum, with the glyph itself staying
        // small at 22, and a 16 pt margin so the button lines up with the bell
        // on the left instead of hugging the screen edge at 9 pt.
        CGFloat side = kPFBNotifDismissTarget;
        CGRect wanted = CGRectMake(((UIView*)self).bounds.size.width - side - kPFBNotifDismissInset,
                                   kPFBNotifDismissTop, side, side);
        if (!CGRectEqualToRect(dismiss.frame, wanted)) {
            dismiss.frame = wanted;
            changed = YES;
        }

        // The cross replaces the ellipsis: this is not a "more options" menu.
        if ([dismiss isKindOfClass:[UIButton class]]) {
            UIButton* button = (UIButton*)dismiss;
            if (!objc_getAssociatedObject(dismiss, kPFBNotifGlyphKey)) {
                UIImage* cross = nil;
                if (@available(iOS 13.0, *)) {
                    UIImageSymbolConfiguration* cfg =
                        [UIImageSymbolConfiguration configurationWithPointSize:kPFBNotifDismissGlyph
                                                                       weight:UIImageSymbolWeightSemibold];
                    cross = PFBTwitterGlyphFor(@"close", [UIImage systemImageNamed:@"xmark" withConfiguration:cfg]);
                }
                if (cross) {
                    [button setImage:[cross imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
                            forState:UIControlStateNormal];
                    button.tintColor = [UIColor secondaryLabelColor];
                    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
                    button.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
                    objc_setAssociatedObject(dismiss, kPFBNotifGlyphKey, @YES,
                                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
            }
            // Touch feedback before the finger lifts.
            extern UIColor* PFBCurrentAccentColor(void);
            UIColor* accent = PFBCurrentAccentColor();
            if (accent) {
                [button addAction:[UIAction actionWithHandler:^(__unused UIAction* a) {
                    button.tintColor = accent;
                }] forControlEvents:UIControlEventTouchDown];
                [button addAction:[UIAction actionWithHandler:^(__unused UIAction* a) {
                    button.tintColor = [UIColor secondaryLabelColor];
                }] forControlEvents:UIControlEventTouchUpOutside | UIControlEventTouchCancel];
            }
        }
        objc_setAssociatedObject(self, kPFBNotifRevealedKey, @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (changed) {
            static BOOL said;
            if (!said) {
                said = YES;
                PFBDebugLog(@"[notifs] x button revealed on the notification");
            }
        }
    } @catch (id exception) {
    }
}

- (void)dismissButtonWasTapped {
    // One decision, taken outside the fence, so %orig is never called from
    // inside a protected block: either the hide ran here, or Twitter acts.
    BOOL handled = NO;
    BOOL ours = objc_getAssociatedObject(self, kPFBNotifRevealedKey) != nil;
    if (PFBNotifsEnabled() && ours) {
        @try {
            UITableView* table = PFBNotifTableForCell((UIView*)self);
            NSIndexPath* indexPath =
                table ? [table indexPathForCell:(UITableViewCell*)self] : nil;
            id source = table.dataSource;
            id model = indexPath ? (PFBModelAtIndexPath(source, indexPath)
                                    ?: PFBModelFromCell(table, indexPath))
                                 : nil;
            NSString* identity = model ? PFBNotifIdentity(model) : nil;
            if (identity.length) {
                PFBHideNotifWithText(model, PFBNotifTextFromCell(table, indexPath));
                PFBDebugLog(@"[notifs] x: hidden <%@>", identity);
                PFBNotifDropRow(source, indexPath);
                PFBShowNotifToast(identity);
                handled = YES;
            } else {
                PFBDebugLog(@"[notifs] x: row or identity not found - "
                            @"action left to Twitter");
            }
        } @catch (id exception) {
            PFBDebugLog(@"[notifs] x: hide interrupted - action left to Twitter");
        }
    }
    if (!handled) {
        %orig;
    }
}

%end

// The dismiss button lays itself out after the cell and reinstates its native
// glyph, so the cross is enforced in the button's own layout, and only while its
// image is not already the tweak's, so there is no re-layout loop.
@interface TFNDismissButton : UIButton
@end

%hook TFNDismissButton

- (void)layoutSubviews {
    %orig;
    if (!PFBNotifsEnabled()) {
        return;
    }
    @try {
        // Scoped to notification rows: other dismiss buttons in the app keep theirs.
        UIView* node = self.superview;
        BOOL inNotifCell = NO;
        for (NSInteger hop = 0; node && hop < 8; hop++) {
            if ([NSStringFromClass([node class]) containsString:@"NotificationCell"]) {
                inNotifCell = YES;
                break;
            }
            node = node.superview;
        }
        if (!inNotifCell) {
            return;
        }
        UIImage* current = [self imageForState:UIControlStateNormal];
        if (current && objc_getAssociatedObject(current, kPFBNotifXmarkImageKey)) {
            return;   // the cross is already in place; setting it again would loop
        }
        UIImage* cross = nil;
        if (@available(iOS 13.0, *)) {
            UIImageSymbolConfiguration* cfg = [UIImageSymbolConfiguration
                configurationWithPointSize:kPFBNotifDismissGlyph
                                    weight:UIImageSymbolWeightSemibold];
            cross = PFBTwitterGlyphFor(@"close", [UIImage systemImageNamed:@"xmark" withConfiguration:cfg]);
        }
        if (!cross) {
            return;
        }
        cross = [cross imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        objc_setAssociatedObject(cross, kPFBNotifXmarkImageKey, @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self setImage:cross forState:UIControlStateNormal];
        self.tintColor = [UIColor secondaryLabelColor];
    } @catch (id exception) {
    }
}

%end
