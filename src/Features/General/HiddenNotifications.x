// Hide a notification with its x or a swipe, keep it out of the list, and list the hidden ones.

#import "Support/HookHelpers.h"
#import "Debug/PFBDebugger.h"
#import "Support/TwitterChirpFont.h"
#import "Features/General/PFBHiddenNotificationsViewController.h"

static NSString* const kPFBHiddenNotifsKey = @"pfb_hidden_notifs";

// The notifications screen, recorded when a hide drops one of its rows or when the
// sweep first finds a notification in it. An unhide reloads it.
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

static NSTimeInterval PFBNotifDateFromDisplayedAge(NSString* text, NSTimeInterval reference);
static NSTimeInterval PFBNotifDateFromAgePiece(NSString* tail, NSTimeInterval reference);

// Days a hidden entry lasts, counted from the notification's date.
static const double kPFBNotifHorizonDays = 30.0;

// Days left before the entry drops out on its own, counted from the notification's
// own date when one can be read, otherwise from the moment it was hidden.
double PFBNotifDaysLeft(NSDictionary* entry) {
    double base = [entry[@"d"] doubleValue];
    double hidden = [entry[@"h"] doubleValue];
    if (base <= 0 && hidden > 0 && [entry[@"t"] isKindOfClass:[NSString class]]) {
        base = PFBNotifDateFromDisplayedAge(entry[@"t"], hidden);
    }
    if (base <= 0) {
        base = hidden;
    }
    if (base <= 0) {
        return kPFBNotifHorizonDays;
    }
    double elapsed = ([[NSDate date] timeIntervalSince1970] - base) / 86400.0;
    double left = kPFBNotifHorizonDays - elapsed;
    return left > 0 ? left : 0;
}

// Purge on read: an entry past its horizon leaves by itself.
static void PFBPurgeExpiredNotifs(void) {
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

// Hidden rows are deleted from the app's own list, so unhiding changes nothing on
// screen by itself. The screen loads its top the way
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

// The last resort: the first of the class's own zero-argument object getters whose name
// holds a wanted word and that yields a value. Used by the identity reader when its
// candidate lists come up empty.
static SEL PFBNotifDiscover(id model, NSArray<NSString*>* wanted) {
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
            BOOL usable = returnType[0] == '@';
            free(returnType);
            if (usable) {
                // Confirm it actually yields something before adopting it.
                if (PFBNotifString(PFBNotifAsk(model, selector)).length) {
                    winner = selector;
                }
            }
        }
    }
    free(methods);
    return winner;
}

// The entry id's middle is rewritten on every refresh; only this many trailing
// characters stay put, so the key is built from them.
static const NSUInteger kPFBNotifIdTail = 8;

// Reads the entry id from the model's description, which prints it even when no
// accessor returns it; tried before any accessor is asked.
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
                                          @"itemid", @"restid"]);
    if (found) {
        cache[className] = NSStringFromSelector(found);
        return PFBNotifString(PFBNotifAsk(model, found));
    }
    return nil;
}

static BOOL PFBNotifIsHidden(id model) {
    if (!model) {
        return NO;
    }
    // Entries past their horizon also leave once per launch, not only when the list is read.
    static dispatch_once_t purgeOnce;
    dispatch_once(&purgeOnce, ^{
        PFBPurgeExpiredNotifs();
    });
    NSDictionary* hidden = PFBHiddenNotifs();
    if (!hidden.count) {
        return NO;   // the hot path costs one dictionary read
    }
    NSString* identity = PFBNotifIdentity(model);
    return identity.length && hidden[identity] != nil;
}

// The notification's view model carries no text, so the wording shown in the hidden
// list is read from the CELL at the moment of hiding — its labels are the only place
// the notification's words exist.
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

// The notification's date, recovered from the age its cell renders (the model has none):
// relative forms (30s, 5h, 1w) counted back from `reference` and absolute ones, in any
// " · " piece. 0 when unreadable.
static NSTimeInterval PFBNotifDateFromDisplayedAge(NSString* text, NSTimeInterval reference) {
    for (NSString* piece in [text componentsSeparatedByString:@" · "]) {
        NSString* tail = [piece stringByTrimmingCharactersInSet:
                                    [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSTimeInterval when = tail.length ? PFBNotifDateFromAgePiece(tail, reference) : 0;
        if (when > 0) {
            return when;
        }
    }
    return 0;
}

static NSTimeInterval PFBNotifDateFromAgePiece(NSString* tail, NSTimeInterval reference) {

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

    NSTimeInterval now = reference;
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
        // A short form carries no year, so the day and month are grafted onto the
        // current year, and pushed back a year if that would place the notification
        // in the future.
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

// Files the notification as hidden. Returns the key of its entry, which Undo removes, or
// nil when the notification has no readable identity.
static NSString* PFBHideNotifWithText(id model, NSString* cellText) {
    NSString* identity = PFBNotifIdentity(model);
    if (!identity.length) {
        return nil;
    }
    NSMutableDictionary* current = [PFBHiddenNotifs() mutableCopy];
    NSString* text = cellText ?: @"";
    if (text.length > 140) {
        text = [text substringToIndex:140];
    }
    // "d" is the notification's own date. The model has none, so it comes from
    // the age the cell displays; the countdown and the expiry date both read
    // "d" first and only fall back to "h", the moment it was hidden.
    NSTimeInterval notifDate = PFBNotifDateFromDisplayedAge(cellText ?: @"", [[NSDate date] timeIntervalSince1970]);
    // One entry per notification, keyed by its identity.
    current[identity] = @{
        @"t": text,
        @"d": @(notifDate),
        @"h": @([[NSDate date] timeIntervalSince1970])
    };
    PFBWriteHiddenNotifs(current);
    return identity;
}

// MARK: - The confirmation

// Its Undo takes the entry filed under the key back out.
static void PFBShowNotifToast(NSString* notifID) {
    PFBShowToast(nil, [[PFBBundle sharedBundle] localizedStringForKey:@"NOTIFS_HIDDEN_TOAST"], ^{
        PFBUnhideNotif(notifID);
    });
}

// MARK: - The swipe, on the list's own delegate

// The action is placed before whatever Twitter already returns, so nothing native
// is dropped and an empty return carries the added action alone.

// The fallback when the controller yields no model: the cell's own model
// accessors, unwrapped from their data-view item when wrapped.
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
// replay. The registry and sweep still handle later reloads.
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
            PFBCOMPAT_ACTION(PFBCompat_hide_notifications, @"notification hidden");
            // A hide from this list proves it is the notifications screen: it is the one
            // an unhide refreshes, and its verdict gates the empty-state sync.
            gPFBNotifScreen = (UIViewController*)dataViewController;
            if (!objc_getAssociatedObject(dataViewController, kPFBNotifVerdictKey)) {
                objc_setAssociatedObject(dataViewController, kPFBNotifVerdictKey, @YES,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
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
    id model = PFBModelAtIndexPath(self, indexPath) ?: PFBModelFromCell(tableView, indexPath);
    // Only rows that carry a notification and can be named: one that cannot be
    // identified could never be unhidden. A notification with no readable identity
    // is journaled once.
    if (!model) {
        return original;
    }
    NSString* modelClass = NSStringFromClass([model class]);
    if (![modelClass containsString:@"Notification"]) {
        return original;
    }
    PFBCompatReach(PFBCompatPath_notification_swipe);
    if (![PFBSettings boolForKey:@"hide_notifications"]) {
        PFBCOMPAT_OBSERVE(PFBCompat_hide_notifications, @"notification swipe seen");
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

    NSString* title = [[PFBBundle sharedBundle] localizedStringForKey:@"NOTIFS_HIDE_ACTION"];
    UIContextualAction* hide = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleDestructive
                            title:title
                          handler:^(__unused UIContextualAction* action,
                                    __unused UIView* sourceView,
                                    void (^completion)(BOOL)) {
            // Rows can shift while the swipe is open: the row is found again by its notification.
            NSString* identity = PFBNotifIdentity(model);
            NSMutableArray<NSIndexPath*>* candidates = [NSMutableArray arrayWithObject:indexPath];
            [candidates addObjectsFromArray:tableView.indexPathsForVisibleRows ?: @[]];
            NSIndexPath* row = nil;
            for (NSIndexPath* candidate in candidates) {
                id current = PFBModelAtIndexPath(self, candidate) ?: PFBModelFromCell(tableView, candidate);
                if (current && (current == model || [PFBNotifIdentity(current) isEqualToString:identity])) {
                    row = candidate;
                    break;
                }
            }
            NSString* hiddenKey = PFBHideNotifWithText(model, row ? PFBNotifTextFromCell(tableView, row) : nil);
            completion(YES);
            if (row) {
                PFBNotifDropRow(self, row);
            }
            if (hiddenKey) {
                PFBShowNotifToast(hiddenKey);
            }
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

// Which screens the sweep may touch, decided by observation rather than by class
// name. One notification model keeps a controller, several without drops it, and
// the home timeline is then never walked again.
static BOOL PFBNotifSweepAllowed(id dataViewController) {
    id verdict = objc_getAssociatedObject(dataViewController, kPFBNotifVerdictKey);
    return verdict ? [verdict boolValue] : YES;   // undecided: walk it
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
// not declared in Support/TAEHeaders.h, so this declaration shim serves as a cast
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
            UIColor* color = [(PFBNotifPaletteShim*)palette textDetailsColor];
            if ([color isKindOfClass:[UIColor class]]) {
                return color;
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
    } @catch (id exception) {
        PFBDebugLog(@"[empty] exception: %@", exception);
    }
}

static BOOL gPFBNotifSweeping;

// Takes the empty-list panel off a notifications list at once, without the fade.
static void PFBNotifRemoveEmptyPanel(id dataViewController) {
    if (![objc_getAssociatedObject(dataViewController, kPFBNotifVerdictKey) isEqual:@YES]) {
        return;
    }
    SEL tableSel = NSSelectorFromString(@"tableView");
    if (![dataViewController respondsToSelector:tableSel]) {
        return;
    }
    id table = ((id (*)(id, SEL))objc_msgSend)(dataViewController, tableSel);
    if ([table isKindOfClass:[UITableView class]]) {
        [[(UITableView*)table viewWithTag:kPFBNotifEmptyTag] removeFromSuperview];
    }
}

static void PFBNotifSweep(id dataViewController) {
    if (gPFBNotifSweeping || !dataViewController) {
        return;
    }
    if (![PFBSettings boolForKey:@"hide_notifications"]) {
        // Off, the list is Twitter's own again: a panel left from before goes.
        PFBNotifRemoveEmptyPanel(dataViewController);
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

// Sweeps the controller on the next turn of the main queue, if it is still alive.
static void PFBNotifSweepLater(id dataViewController) {
    __weak id host = dataViewController;
    dispatch_async(dispatch_get_main_queue(), ^{
      id alive = host;
      if (alive) {
          PFBNotifSweep(alive);
      }
    });
}

// T1URTViewController inherits -sections and -setSections: from
// TFNItemsDataViewController, so the hooks sit there. Each content replacement is
// followed by a sweep of the list once it is in place.
%hook TFNItemsDataViewController

- (void)setSections:(NSArray*)sections restoreScrollPosition:(BOOL)restore {
    %orig;
    PFBNotifSweepLater(self);
}

- (void)setSections:(NSArray*)sections {
    %orig;
    PFBNotifSweepLater(self);
}

- (void)updateSections:(NSArray*)sections {
    %orig;
    PFBNotifSweepLater(self);
}

// The four below complete the set: these are the content-replacement entry points
// TFNItemsDataViewController implements. Covering fewer lets hidden rows return on a
// refresh.

- (void)updateSections:(NSArray*)sections completion:(id)completion {
    %orig;
    PFBNotifSweepLater(self);
}

- (void)updateSections:(NSArray*)sections withRowAnimation:(NSInteger)animation {
    %orig;
    PFBNotifSweepLater(self);
}

- (void)updateSections:(NSArray*)sections
      withRowAnimation:(NSInteger)animation
            completion:(id)completion {
    %orig;
    PFBNotifSweepLater(self);
}

- (void)updateSections:(NSArray*)sections
reconfigureItemIdentifiers:(id)identifiers
      withRowAnimation:(NSInteger)animation
            completion:(id)completion {
    %orig;
    PFBNotifSweepLater(self);
}

%end

// MARK: - Quick access, the pattern shared with muted words

// Presents the hidden list as a popover from the eye, which the
// T1TabNavigationController hook below places on the notifications screen.
@interface PFBNotifQuickPresenter : NSObject
+ (instancetype)shared;
- (void)present:(PFBBarGlyphButton*)sender;
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

// The arrow points at the eye's glyph; the host controller does not come from the sender.
- (void)present:(PFBBarGlyphButton*)sender {
    @try {
        UIViewController* controller =
            [[PFBHiddenNotificationsViewController alloc] initCompact];
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
        popover.sourceView = sender;
        popover.sourceRect = sender.glyphFrame;
        popover.permittedArrowDirections = UIPopoverArrowDirectionUp;
        popover.delegate = (id)self;

        // Host: the visible controller of the key window, never derived from
        // the sender.
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
            return;
        }
        [host presentViewController:controller animated:YES completion:nil];
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

// MARK: - the eye

// A PFBBarGlyphItem paired with the gear beside it, placed on the Notifications screen's
// own bar items: by Twitter's navigation when it builds them, and on Twitter's native
// glass stack, whose top bar draws the screen's navigation item, when the screen appears.

static const NSInteger kPFBNotifBarItemTag = 90314;
static const CGFloat kPFBNotifEyeSide = 24.0;

static void PFBNotifPlaceEye(UIViewController* viewController) {
    if (!viewController) {
        return;
    }
    @try {
        if (![NSStringFromClass([viewController class])
                containsString:@"NotificationsViewController"]) {
            return;
        }
        PFBCompatReach(PFBCompatPath_eye_button);
        if (![PFBSettings boolForKey:@"hide_notifications"]) {
            PFBCOMPAT_OBSERVE(PFBCompat_hide_notifications, @"Notifications bar found");
            return;
        }
        UINavigationItem* item = viewController.navigationItem;
        for (UIBarButtonItem* existing in item.rightBarButtonItems) {
            if (existing.tag == kPFBNotifBarItemTag) {
                PFBBarPairWithNeighbor(existing, item.rightBarButtonItems, @"Notifications");
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
        // In the gray of the bar's icons, which the Notifications bar pass repaints
        // when it changes (NavBarIcons.x). The same kind of item as the Explore
        // filters button, so both sit the same way beside the gear.
        UIBarButtonItem* ours = PFBBarGlyphItem(
            PFBFlatGlyph(glyph, PFBBarIconGray(viewController.traitCollection)),
            [[PFBBundle sharedBundle] localizedStringForKey:@"HIDDEN_NOTIFS_TITLE"],
            [PFBNotifQuickPresenter shared], @selector(present:));
        ours.tag = kPFBNotifBarItemTag;
        NSMutableArray<UIBarButtonItem*>* items =
            [NSMutableArray arrayWithArray:item.rightBarButtonItems ?: @[]];
        [items addObject:ours];
        item.rightBarButtonItems = items;
        PFBBarPairWithNeighbor(ours, item.rightBarButtonItems, @"Notifications");
        PFBCOMPAT_ACTION(PFBCompat_hide_notifications, @"eye placed");
    } @catch (id exception) {
        PFBDebugLog(@"[notifs] eye placement abandoned - no consequence");
    }
}

%hook T1TabNavigationController

// The last two arguments are objects in Twitter's binary, passed on untouched.
- (void)_t1_main_updateNavigationItemForViewController:(UIViewController*)viewController
                                                isRoot:(BOOL)isRoot
                           providingLeftBarButtonItems:(__unsafe_unretained id)left
                                 rightBarButtonItems:(__unsafe_unretained id)right {
    %orig;
    PFBNotifPlaceEye(viewController);
}

%end

// Twitter may set its own items after the screen appears, so both moments place it.
%hook T1NotificationsViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    if (PFBOnNativeGlassStack((UIViewController*)self)) {
        PFBNotifPlaceEye((UIViewController*)self);
    }
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (PFBOnNativeGlassStack((UIViewController*)self)) {
        PFBNotifPlaceEye((UIViewController*)self);
    }
}

%end

// MARK: - the x button

// Every notification cell holds a hidden TFNDismissButton wired to a method of
// the cell: it is shown as an x, and the hide runs where its tap lands.

static const char* kPFBNotifRevealedKey = "pfbNotifRevealedDismiss";
static const char* kPFBNotifGlyphKey    = "pfbNotifDismissGlyph";
static const char* kPFBNotifFeedbackKey = "pfbNotifDismissFeedback";
static const char* kPFBNotifXmarkImageKey = "pfbNotifXmarkImage";
static const CGFloat kPFBNotifDismissTarget = 44.0;   // touch target
static const CGFloat kPFBNotifDismissGlyph  = 15.0;   // glyph body
static const CGFloat kPFBNotifDismissInset  = 16.0;   // margin from the right edge
static const CGFloat kPFBNotifDismissTop    = 4.0;    // top of the cell

// Twitter's close glyph at the cross's size, in template mode and marked as the cross.
static UIImage* PFBNotifCrossImage(void) {
    UIImageSymbolConfiguration* cfg =
        [UIImageSymbolConfiguration configurationWithPointSize:kPFBNotifDismissGlyph
                                                        weight:UIImageSymbolWeightSemibold];
    UIImage* cross =
        PFBTwitterGlyphFor(@"close", [UIImage systemImageNamed:@"xmark" withConfiguration:cfg]);
    if (!cross) {
        return nil;
    }
    cross = [cross imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    objc_setAssociatedObject(cross, kPFBNotifXmarkImageKey, @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return cross;
}

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
    if ([PFBSettings boolForKey:@"hide_notifications"] && PFBHiddenNotifs().count) {
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
    %orig(masked ? 0.0 : alpha);
}

- (void)layoutSubviews {
    %orig;
    PFBNotifMaskHiddenCell((UITableViewCell*)self);
    if (![PFBSettings boolForKey:@"hide_notifications"]) {
        return;
    }
    @try {
        id button = PFBNotifAsk(self, NSSelectorFromString(@"dismissButton"));
        if (![button isKindOfClass:[UIView class]]) {
            return;
        }
        UIView* dismiss = button;
        // Every way the button can be hidden is undone: hidden flag, alpha and
        // frame. The cell is marked so the tap handler recognizes it.
        if (dismiss.hidden) { dismiss.hidden = NO; }
        if (dismiss.alpha < 0.5) { dismiss.alpha = 1.0; }
        dismiss.userInteractionEnabled = YES;

        // A 44 pt touch target, Apple's minimum, with the glyph itself staying
        // small at 15, and a 16 pt margin so the button lines up with the bell
        // on the left instead of hugging the screen edge at 9 pt.
        CGFloat side = kPFBNotifDismissTarget;
        CGRect wanted = CGRectMake(((UIView*)self).bounds.size.width - side - kPFBNotifDismissInset,
                                   kPFBNotifDismissTop, side, side);
        if (!CGRectEqualToRect(dismiss.frame, wanted)) {
            dismiss.frame = wanted;
        }

        // The cross replaces the ellipsis: this is not a "more options" menu.
        if ([dismiss isKindOfClass:[UIButton class]]) {
            UIButton* button = (UIButton*)dismiss;
            if (!objc_getAssociatedObject(dismiss, kPFBNotifGlyphKey)) {
                UIImage* cross = PFBNotifCrossImage();
                if (cross) {
                    [button setImage:cross forState:UIControlStateNormal];
                    button.tintColor = [UIColor secondaryLabelColor];
                    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
                    button.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
                    objc_setAssociatedObject(dismiss, kPFBNotifGlyphKey, @YES,
                                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
            }
            // Touch feedback before the finger lifts, attached once per button: layout
            // runs again and again, and actions added each time would pile up.
            if (!objc_getAssociatedObject(dismiss, kPFBNotifFeedbackKey)) {
                __weak UIButton* weakButton = button;
                [button addAction:[UIAction actionWithHandler:^(__unused UIAction* a) {
                    weakButton.tintColor = PFBCurrentAccentColor();
                }] forControlEvents:UIControlEventTouchDown];
                [button addAction:[UIAction actionWithHandler:^(__unused UIAction* a) {
                    weakButton.tintColor = [UIColor secondaryLabelColor];
                }] forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
                objc_setAssociatedObject(dismiss, kPFBNotifFeedbackKey, @YES,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }
        objc_setAssociatedObject(self, kPFBNotifRevealedKey, @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } @catch (id exception) {
    }
}

- (void)dismissButtonWasTapped {
    // One decision, taken outside the @try block so %orig is never called from
    // inside it: either the hide ran here, or Twitter's own action runs.
    BOOL handled = NO;
    BOOL ours = objc_getAssociatedObject(self, kPFBNotifRevealedKey) != nil;
    if ([PFBSettings boolForKey:@"hide_notifications"] && ours) {
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
                NSString* hiddenKey = PFBHideNotifWithText(model, PFBNotifTextFromCell(table, indexPath));
                PFBNotifDropRow(source, indexPath);
                if (hiddenKey) {
                    PFBShowNotifToast(hiddenKey);
                }
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

// The dismiss button lays itself out after the cell and reinstates its native glyph, so
// the cross is enforced in the button's own layout, only while its image is not already
// the cross, so there is no re-layout loop.
@interface TFNDismissButton : UIButton
@end

%hook TFNDismissButton

- (void)layoutSubviews {
    %orig;
    if (![PFBSettings boolForKey:@"hide_notifications"]) {
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
        UIImage* cross = PFBNotifCrossImage();
        if (!cross) {
            return;
        }
        [self setImage:cross forState:UIControlStateNormal];
        self.tintColor = [UIColor secondaryLabelColor];
    } @catch (id exception) {
    }
}

%end
