// Hide a notification with its x, keep it out of the list, and list the hidden ones.

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

// A Tweet shown in the notifications list is named by its own ID, read from the status
// field of Twitter's Tweet view model.
static NSString* PFBNotifTweetIdentity(id model) {
    static Class statusItem;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      statusItem = objc_getClass("URTTimelineStatusItemViewModel");
    });
    if (!statusItem || ![model isKindOfClass:statusItem]) {
        return nil;
    }
    Ivar statusIvar = class_getInstanceVariable([model class], "status");
    id status = statusIvar ? object_getIvar(model, statusIvar) : nil;
    if (![status respondsToSelector:@selector(statusID)]) {
        return nil;
    }
    NSInteger statusID = ((TFNTwitterStatus*)status).statusID;
    return statusID > 0 ? [NSString stringWithFormat:@"tw:%ld", (long)statusID] : nil;
}

static NSString* PFBNotifIdentity(id model) {
    NSString* tweet = PFBNotifTweetIdentity(model);
    if (tweet) {
        return tweet;
    }
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
    // Durable names only: the ones inside scribeItem, then the usual entry ids.
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
        @"id", @"sortIndex", @"key", @"itemIdentifier"
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

// Whether a list belongs to the notifications tab, read up its controllers.
static BOOL PFBNotifOnNotificationsScreen(id dataViewController) {
    UIViewController* node = [dataViewController isKindOfClass:[UIViewController class]]
                                 ? (UIViewController*)dataViewController
                                 : nil;
    for (NSInteger hop = 0; node && hop < 6; hop++) {
        if ([NSStringFromClass([node class]) containsString:@"NotificationsViewController"]) {
            return YES;
        }
        node = node.parentViewController;
    }
    return NO;
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

// The notification's model carries no text, so the words shown in the hidden list
// are read from its cell when it is hidden: its labels are the only place they exist.
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

// MARK: - A row's notification

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
static BOOL gPFBNotifSweeping;

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

// MARK: - Keeping them out of the list

// Which lists the sweep walks: one that shows a notification is kept; one outside the
// notifications screens that shows five items and none is dropped for good.
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
    if (PFBNotifOnNotificationsScreen(dataViewController)) {
        return;
    }
    // Only decide against a screen once enough items have been seen: an empty
    // or still-loading list must not be condemned on a single empty pass.
    if (examined >= 5) {
        objc_setAssociatedObject(dataViewController, kPFBNotifVerdictKey, @NO,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

// MARK: - the empty panel

// A glyph over two centered labels in a container, laid out as Chat's empty inbox. Chat's view is only
// read: an internal view carries invariants unknowable from outside, and a bad access is not caught by @try.

static const NSInteger kPFBNotifEmptyTag = 90315;
static const NSInteger kPFBNotifEmptyTitleTag = 90316;
static const NSInteger kPFBNotifEmptyBodyTag = 90317;
static const NSInteger kPFBNotifEmptyGlyphTag = 90319;
static const void* kPFBNotifGlyphNameKey = &kPFBNotifGlyphNameKey;
static const void* kPFBNotifGlyphDrawnKey = &kPFBNotifGlyphDrawnKey;
static const void* kPFBNotifGlyphInkKey = &kPFBNotifGlyphInkKey;
static const void* kPFBNotifImageInkKey = &kPFBNotifImageInkKey;
static const char* kPFBNotifPanelTopKey = "pfbNotifPanelTop";

// Until Chat's empty inbox is read, the values measured on a capture of it, in points down from the screen's
// middle: the glyph's ink 48 tall, centered 13.7 down; the title's baseline 71.7 down, Chirp Bold 18; the
// line's baseline 31.7 under it, Chirp 16, in a gray of 102; lines wrapped 32 from each side.
static const CGFloat kPFBNotifEmptyGlyphInk = 48.0;
static const CGFloat kPFBNotifEmptyGlyphMid = 13.7;
static const CGFloat kPFBNotifEmptyTitleBase = 71.7;
static const CGFloat kPFBNotifEmptyBodyStep = 31.7;
static const CGFloat kPFBNotifEmptyTitleSize = 18.0;
static const CGFloat kPFBNotifEmptyBodySize = 16.0;
static const CGFloat kPFBNotifEmptySideInset = 32.0;

// Chirp as Twitter's font group gives it; the title in Chirp Bold, as Chat's, not the group's heavier face.
static UIFont* PFBNotifEmptyFont(CGFloat size, BOOL bold) {
    TFNUIDefaultFontGroup* fonts = (TFNUIDefaultFontGroup*)[PFBManager sharedFontGroup];
    if (!bold && [fonts respondsToSelector:@selector(fontOfSize:)]) {
        UIFont* font = [fonts fontOfSize:size];
        if ([font isKindOfClass:[UIFont class]]) {
            return font;
        }
    }
    UIFont* face = bold ? [UIFont fontWithName:@"Chirp-Bold" size:size] : nil;
    return PFBScaledFont(face ?: [TwitterChirpFont(bold ? TwitterFontStyleBold : TwitterFontStyleRegular) fontWithSize:size]);
}

// The line's gray until Chat is read: the one measured in light, the system's secondary gray in dark.
static UIColor* PFBNotifEmptyBodyColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor*(UITraitCollection* traits) {
      return traits.userInterfaceStyle == UIUserInterfaceStyleDark ? [UIColor.secondaryLabelColor resolvedColorWithTraitCollection:traits]
                                                                    : [UIColor colorWithWhite:102.0 / 255.0 alpha:1.0];
    }];
}

// Chat's empty inbox as Twitter lays it out, read off its own view and kept for later launches: the height
// of the glyph's ink, each line's font and colors, the width the lines wrap to, and where the glyph and the
// baselines sit from the screen's middle. A layout kept without the glyph's ink waits for the next read.
static NSString* const kPFBChatEmptyLayoutKey = @"PFBChatEmptyLayout";
static NSDictionary* gPFBChatEmptyLayout;

static NSDictionary* PFBChatEmptyLayout(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      if (!gPFBChatEmptyLayout) {
          NSDictionary* kept = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kPFBChatEmptyLayoutKey];
          gPFBChatEmptyLayout = [kept[@"glyphInk"] isKindOfClass:[NSNumber class]] ? kept : nil;
      }
    });
    return gPFBChatEmptyLayout;
}

static NSArray<NSNumber*>* PFBNotifColorParts(UIColor* color, UIUserInterfaceStyle style) {
    UIColor* resolved = [color resolvedColorWithTraitCollection:[UITraitCollection traitCollectionWithUserInterfaceStyle:style]];
    CGFloat r = 0.0, g = 0.0, b = 0.0, a = 0.0;
    return [resolved getRed:&r green:&g blue:&b alpha:&a] ? @[ @(r), @(g), @(b), @(a) ] : @[];
}

// A color read in light and dark, given back as one that follows the appearance.
static UIColor* PFBNotifColorFromParts(NSArray* light, NSArray* dark, UIColor* fallback) {
    if (![light isKindOfClass:[NSArray class]] || ![dark isKindOfClass:[NSArray class]] || light.count != 4 || dark.count != 4) {
        return fallback;
    }
    UIColor* lightColor = [UIColor colorWithRed:[light[0] doubleValue] green:[light[1] doubleValue] blue:[light[2] doubleValue] alpha:[light[3] doubleValue]];
    UIColor* darkColor = [UIColor colorWithRed:[dark[0] doubleValue] green:[dark[1] doubleValue] blue:[dark[2] doubleValue] alpha:[dark[3] doubleValue]];
    return [UIColor colorWithDynamicProvider:^UIColor*(UITraitCollection* traits) {
      return traits.userInterfaceStyle == UIUserInterfaceStyleDark ? darkColor : lightColor;
    }];
}

static NSDictionary* PFBNotifFontParts(UIFont* font) {
    NSNumber* weight = font.fontDescriptor.fontAttributes[UIFontDescriptorTraitsAttribute][UIFontWeightTrait];
    BOOL bold = (font.fontDescriptor.symbolicTraits & UIFontDescriptorTraitBold) != 0;
    return @{@"name" : font.fontName ?: @"", @"size" : @(font.pointSize), @"weight" : weight ?: @(bold ? UIFontWeightBold : UIFontWeightRegular)};
}

// System fonts go by their weight, as their private names give Times; any other font by its name.
static UIFont* PFBNotifFontFromParts(NSDictionary* parts, UIFont* fallback) {
    NSString* name = [parts isKindOfClass:[NSDictionary class]] ? parts[@"name"] : nil;
    CGFloat size = [parts[@"size"] doubleValue];
    if (![name isKindOfClass:[NSString class]] || !name.length || size <= 0.0) {
        return fallback;
    }
    UIFont* font = [name hasPrefix:@"."] ? [UIFont systemFontOfSize:size weight:[parts[@"weight"] doubleValue]] : [UIFont fontWithName:name size:size];
    return font ?: fallback;
}

// The drawn part of an image, in its own points: the pixels more than a quarter opaque, once per image.
static CGRect PFBNotifImageInk(UIImage* image) {
    NSValue* kept = image ? objc_getAssociatedObject(image, kPFBNotifImageInkKey) : nil;
    if (kept) {
        return kept.CGRectValue;
    }
    CGFloat scale = image.scale > 0.0 ? image.scale : 1.0;
    size_t width = (size_t)ceil(image.size.width * scale), height = (size_t)ceil(image.size.height * scale);
    if (width == 0 || height == 0 || width > 1024 || height > 1024) {
        return CGRectNull;
    }
    NSMutableData* alpha = [NSMutableData dataWithLength:width * height];
    CGContextRef context = CGBitmapContextCreate(alpha.mutableBytes, width, height, 8, width, NULL, (CGBitmapInfo)kCGImageAlphaOnly);
    if (!context) {
        return CGRectNull;
    }
    CGContextTranslateCTM(context, 0.0, height);
    CGContextScaleCTM(context, scale, -scale);
    UIGraphicsPushContext(context);
    [image drawInRect:CGRectMake(0.0, 0.0, image.size.width, image.size.height)];
    UIGraphicsPopContext();
    CGContextRelease(context);
    const uint8_t* bytes = alpha.bytes;
    NSInteger minX = (NSInteger)width, minY = (NSInteger)height, maxX = -1, maxY = -1;
    for (NSInteger y = 0; y < (NSInteger)height; y++) {
        for (NSInteger x = 0; x < (NSInteger)width; x++) {
            if (bytes[y * (NSInteger)width + x] > 64) {
                minX = MIN(minX, x);
                maxX = MAX(maxX, x);
                minY = MIN(minY, y);
                maxY = MAX(maxY, y);
            }
        }
    }
    CGRect ink = maxX < 0 ? CGRectNull : CGRectMake(minX / scale, minY / scale, (maxX - minX + 1) / scale, (maxY - minY + 1) / scale);
    objc_setAssociatedObject(image, kPFBNotifImageInkKey, [NSValue valueWithCGRect:ink], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return ink;
}

// An image view's ink in its own space, where its content mode puts the image.
static CGRect PFBNotifInkInView(UIImageView* view) {
    UIImage* image = view.image;
    CGRect ink = PFBNotifImageInk(image);
    CGSize size = image.size, box = view.bounds.size;
    if (CGRectIsNull(ink) || size.width <= 0.0 || size.height <= 0.0) {
        return CGRectNull;
    }
    UIViewContentMode mode = view.contentMode;
    CGFloat sx = 1.0, sy = 1.0;
    if (mode == UIViewContentModeScaleToFill || mode == UIViewContentModeRedraw) {
        sx = box.width / size.width;
        sy = box.height / size.height;
    } else if (mode == UIViewContentModeScaleAspectFit) {
        sx = sy = MIN(box.width / size.width, box.height / size.height);
    } else if (mode == UIViewContentModeScaleAspectFill) {
        sx = sy = MAX(box.width / size.width, box.height / size.height);
    }
    CGFloat w = size.width * sx, h = size.height * sy;
    CGFloat x = (box.width - w) / 2.0, y = (box.height - h) / 2.0;
    if (mode == UIViewContentModeTop || mode == UIViewContentModeTopLeft || mode == UIViewContentModeTopRight) {
        y = 0.0;
    } else if (mode == UIViewContentModeBottom || mode == UIViewContentModeBottomLeft || mode == UIViewContentModeBottomRight) {
        y = box.height - h;
    }
    if (mode == UIViewContentModeLeft || mode == UIViewContentModeTopLeft || mode == UIViewContentModeBottomLeft) {
        x = 0.0;
    } else if (mode == UIViewContentModeRight || mode == UIViewContentModeTopRight || mode == UIViewContentModeBottomRight) {
        x = box.width - w;
    }
    return CGRectMake(x + CGRectGetMinX(ink) * sx, y + CGRectGetMinY(ink) * sy, CGRectGetWidth(ink) * sx, CGRectGetHeight(ink) * sy);
}

// A label's first baseline from its top: UILabel centers its text in its height.
static CGFloat PFBNotifFirstBaseline(UILabel* label) {
    CGRect text = [label textRectForBounds:label.bounds limitedToNumberOfLines:label.numberOfLines];
    return (CGRectGetHeight(label.bounds) - CGRectGetHeight(text)) / 2.0 + label.font.ascender;
}

// Twitter's glyph drawn so its ink is as tall as Chat's, its ink kept with it; drawn again only when
// the glyph or the height changes.
static void PFBNotifDrawGlyph(UIImageView* glyph, NSString* name, CGFloat ink) {
    NSString* drawn = [NSString stringWithFormat:@"%@ %.2f", name, ink];
    if (!name || ink < 1.0 || [objc_getAssociatedObject(glyph, kPFBNotifGlyphDrawnKey) isEqualToString:drawn] ||
        ![UIImage respondsToSelector:@selector(tfn_vectorImageNamed:fitsSize:fillColor:)]) {
        return;
    }
    UIImage* probe = [UIImage tfn_vectorImageNamed:name fitsSize:CGSizeMake(100.0, 100.0) fillColor:[UIColor blackColor]];
    CGRect probeInk = [probe isKindOfClass:[UIImage class]] ? PFBNotifImageInk(probe) : CGRectNull;
    CGFloat side = CGRectIsNull(probeInk) ? ink : 100.0 * ink / CGRectGetHeight(probeInk);
    UIImage* image = [UIImage tfn_vectorImageNamed:name fitsSize:CGSizeMake(side, side) fillColor:[UIColor blackColor]];
    if (![image isKindOfClass:[UIImage class]]) {
        return;
    }
    CGRect shown = PFBNotifImageInk(image);
    glyph.image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    objc_setAssociatedObject(glyph, kPFBNotifGlyphInkKey, [NSValue valueWithCGRect:CGRectIsNull(shown) ? (CGRect){CGPointZero, image.size} : shown],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(glyph, kPFBNotifGlyphDrawnKey, drawn, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

static const char* kPFBNotifRestInsetKey = "pfbNotifRestInset";
static const char* kPFBNotifPanelKey = "pfbNotifPanel";

// Notes, once a launch, a list inset grown past the rest with no pull or refresh under way:
// Twitter's pull control adds its room above the list only while pulled or loading.
static void PFBNotifNoteInsetGrowth(UITableView* table) {
    static BOOL noted;
    if (noted || table.isDragging || table.contentOffset.y < -table.adjustedContentInset.top) {
        return;
    }
    id control = PFBNotifAsk(PFBOwningController(table), NSSelectorFromString(@"pullToLoadTopControl"));
    for (NSString* name in @[ @"loading", @"isCurrentlyInUse" ]) {
        SEL getter = NSSelectorFromString(name);
        if ([control respondsToSelector:getter] && ((BOOL (*)(id, SEL))objc_msgSend)(control, getter)) {
            return;
        }
    }
    noted = YES;
    PFBCompatMeasure(@"hidden notifications", @"list inset grew while the panel was open", 2);
}

// The list's top inset at rest: the smallest seen since the panel came, as a refresh only
// adds its spinner's room.
static CGFloat PFBNotifRestInset(UITableView* table) {
    CGFloat inset = table.adjustedContentInset.top;
    NSNumber* rest = objc_getAssociatedObject(table, kPFBNotifRestInsetKey);
    if (!rest || inset < rest.doubleValue) {
        objc_setAssociatedObject(table, kPFBNotifRestInsetKey, @(inset), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return inset;
    }
    if (inset > rest.doubleValue + 1.0) {
        PFBNotifNoteInsetGrowth(table);
    }
    return (CGFloat)rest.doubleValue;
}

// Whether a finger moves the list, or the list still glides or springs back from it.
static BOOL PFBNotifListMoving(UITableView* table) {
    return table.tracking || table.dragging || table.decelerating;
}

// The panel's top: its glyph where Chat's sits on the screen, from the screen's middle, then moved with the
// list as Twitter's own empty text is, down on a pull and up on a push. A jump up with no finger on the
// list, as after a refresh, leaves it at rest. The background view covers the list's visible bounds.
static CGFloat PFBNotifPanelTop(UITableView* table, UIView* panel) {
    NSNumber* top = objc_getAssociatedObject(panel, kPFBNotifPanelTopKey);
    if (!top || !table.window) {
        return CGRectGetMinY(panel.frame);
    }
    CGFloat rest = PFBNotifRestInset(table);
    CGFloat moved = -table.contentOffset.y - rest;
    if (moved < 0.0 && !PFBNotifListMoving(table)) {
        moved = 0.0;
    }
    CGFloat onScreen = CGRectGetHeight(table.window.bounds) / 2.0 + top.doubleValue;
    return [table convertPoint:CGPointMake(0.0, onScreen) fromView:nil].y - table.bounds.origin.y + moved;
}

// The panel sits behind the list, in its background view, so the list's jumps do not carry it.
static UIView* PFBNotifPanelHost(UITableView* table) {
    if (!table.backgroundView) {
        UIView* host = [[UIView alloc] init];
        host.backgroundColor = UIColor.clearColor;
        host.userInteractionEnabled = NO;
        table.backgroundView = host;
    }
    return table.backgroundView;
}

// Frames rather than Auto Layout, in the background view's space: Chat's glyph height, fonts, colors and
// places once read, the measured ones before. The title's lines and the line's follow from the baselines.
static void PFBNotifLayoutEmptyPanel(UIView* panel, UITableView* table) {
    UIImageView* glyph = (UIImageView*)[panel viewWithTag:kPFBNotifEmptyGlyphTag];
    UILabel* title = (UILabel*)[panel viewWithTag:kPFBNotifEmptyTitleTag];
    UILabel* body = (UILabel*)[panel viewWithTag:kPFBNotifEmptyBodyTag];
    if (![glyph isKindOfClass:[UIImageView class]] || ![title isKindOfClass:[UILabel class]] || ![body isKindOfClass:[UILabel class]]) {
        return;
    }
    NSDictionary* chat = PFBChatEmptyLayout();
    CGFloat tableWidth = CGRectGetWidth(table.bounds);
    CGFloat wrap = MIN(tableWidth - kPFBNotifEmptySideInset, MAX([chat[@"wrapWidth"] doubleValue], tableWidth - kPFBNotifEmptySideInset * 2.0));
    if (wrap < 80.0) {
        return;    // no room to read anything; leave as is
    }
    title.font = PFBNotifFontFromParts(chat[@"titleFont"], PFBNotifEmptyFont(kPFBNotifEmptyTitleSize, YES));
    body.font = PFBNotifFontFromParts(chat[@"bodyFont"], PFBNotifEmptyFont(kPFBNotifEmptyBodySize, NO));
    title.textColor = PFBNotifColorFromParts(chat[@"titleLight"], chat[@"titleDark"], [UIColor labelColor]);
    body.textColor = PFBNotifColorFromParts(chat[@"bodyLight"], chat[@"bodyDark"], PFBNotifEmptyBodyColor());
    glyph.tintColor = PFBNotifColorFromParts(chat[@"glyphLight"], chat[@"glyphDark"], title.textColor);
    PFBNotifDrawGlyph(glyph, objc_getAssociatedObject(panel, kPFBNotifGlyphNameKey),
                      chat ? [chat[@"glyphInk"] doubleValue] : kPFBNotifEmptyGlyphInk);
    CGRect ink = [objc_getAssociatedObject(glyph, kPFBNotifGlyphInkKey) CGRectValue];
    CGFloat glyphTop = (chat ? [chat[@"glyphMid"] doubleValue] : kPFBNotifEmptyGlyphMid) - CGRectGetMidY(ink);
    CGFloat titleBase = chat ? [chat[@"titleBase"] doubleValue] : kPFBNotifEmptyTitleBase;
    CGSize titleSize = [title sizeThatFits:CGSizeMake(wrap, CGFLOAT_MAX)];
    CGSize bodySize = [body sizeThatFits:CGSizeMake(wrap, CGFLOAT_MAX)];
    CGFloat bodyBase = titleBase + titleSize.height - title.font.lineHeight +
                       (chat ? [chat[@"bodyStep"] doubleValue] : kPFBNotifEmptyBodyStep);
    CGSize glyphSize = glyph.image.size;
    glyph.frame = CGRectMake((tableWidth - glyphSize.width) / 2.0, 0.0, glyphSize.width, glyphSize.height);
    title.frame = CGRectMake((tableWidth - wrap) / 2.0, titleBase - title.font.ascender - glyphTop, wrap, titleSize.height);
    body.frame = CGRectMake((tableWidth - wrap) / 2.0, bodyBase - body.font.ascender - glyphTop, wrap, bodySize.height);
    objc_setAssociatedObject(panel, kPFBNotifPanelTopKey, @(glyphTop), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    panel.frame = CGRectMake(0.0, PFBNotifPanelTop(table, panel), tableWidth, CGRectGetMaxY(body.frame));
}

// The panel weakly, for the list's layout passes.
@interface PFBNotifPanelRef : NSObject
@property (nonatomic, weak) UIView* panel;
@end

@implementation PFBNotifPanelRef
@end

// Each scroll of the list lays it out: the panel follows the list there, in the same pass that
// places the background view. A rise of more than a step with no finger on the list, as at the end
// of a refresh, glides in 0.2 s, as the list's own content does.
%hook UITableView

- (void)layoutSubviews {
    %orig;
    PFBNotifPanelRef* ref = objc_getAssociatedObject(self, kPFBNotifPanelKey);
    UIView* panel = ref.panel;
    if (!panel.superview) {
        return;
    }
    CGRect frame = panel.frame;
    frame.origin.y = PFBNotifPanelTop((UITableView*)self, panel);
    if (CGRectEqualToRect(frame, panel.frame)) {
        return;
    }
    if (!PFBNotifListMoving((UITableView*)self) && CGRectGetMinY(panel.frame) - CGRectGetMinY(frame) > 12.0) {
        [UIView animateWithDuration:0.2
                              delay:0.0
                            options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState
                         animations:^{
                           panel.frame = frame;
                         }
                         completion:nil];
    } else {
        panel.frame = frame;
    }
}

%end

// One of Twitter's glyphs over a title and a line, all centered.
UIView* PFBNotifEmptyPanel(NSString* glyphName, NSString* titleText, NSString* bodyText) {
    UIView* panel = [[UIView alloc] init];
    panel.userInteractionEnabled = NO;    // never blocks a pull-to-refresh
    panel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    objc_setAssociatedObject(panel, kPFBNotifGlyphNameKey, glyphName, OBJC_ASSOCIATION_COPY_NONATOMIC);
    UIImageView* glyph = [[UIImageView alloc] init];
    glyph.tag = kPFBNotifEmptyGlyphTag;
    glyph.contentMode = UIViewContentModeCenter;
    [panel addSubview:glyph];
    for (NSNumber* tag in @[ @(kPFBNotifEmptyTitleTag), @(kPFBNotifEmptyBodyTag) ]) {
        UILabel* label = [[UILabel alloc] init];
        label.tag = tag.integerValue;
        label.textAlignment = NSTextAlignmentCenter;
        label.numberOfLines = 0;
        [panel addSubview:label];
    }
    PFBNotifSetEmptyPanelText(panel, titleText, bodyText);
    return panel;
}

void PFBNotifSetEmptyPanelText(UIView* panel, NSString* title, NSString* body) {
    ((UILabel*)[panel viewWithTag:kPFBNotifEmptyTitleTag]).text = title;
    ((UILabel*)[panel viewWithTag:kPFBNotifEmptyBodyTag]).text = body;
}

// Behind the list's rows, under its bars, where the list's layout passes keep it.
void PFBNotifPlaceEmptyPanel(UIView* panel, UITableView* table) {
    if (panel.superview != PFBNotifPanelHost(table)) {
        [PFBNotifPanelHost(table) addSubview:panel];
        objc_setAssociatedObject(table, kPFBNotifRestInsetKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        PFBNotifPanelRef* ref = [[PFBNotifPanelRef alloc] init];
        ref.panel = panel;
        objc_setAssociatedObject(table, kPFBNotifPanelKey, ref, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    PFBNotifLayoutEmptyPanel(panel, table);
}

// Chat's empty inbox at rest: its glyph, then its two lines, the topmost first, placed from the screen's
// middle. Read again on each layout, kept when it changes.
static void PFBNotifReadChatEmpty(UIView* empty) {
    UIView* list = empty.superview;
    while (list && ![list isKindOfClass:[UIScrollView class]]) {
        list = list.superview;
    }
    UIScrollView* scroll = (UIScrollView*)list;
    if (!empty.window || scroll.tracking || scroll.dragging || scroll.decelerating ||
        (scroll && fabs(scroll.contentOffset.y + scroll.adjustedContentInset.top) > 0.5)) {
        return;
    }
    __block UIImageView* glyph = nil;
    NSMutableArray<UILabel*>* lines = [NSMutableArray array];
    PFBWalkAllSubviews(empty, 6, ^(UIView* view) {
      if (view.hidden || view.alpha < 0.01) {
          return;
      }
      if ([view isKindOfClass:[UIImageView class]] && ((UIImageView*)view).image && CGRectGetWidth(view.bounds) > CGRectGetWidth(glyph.bounds)) {
          glyph = (UIImageView*)view;
      } else if ([view isKindOfClass:[UILabel class]] && ((UILabel*)view).text.length) {
          [lines addObject:(UILabel*)view];
      }
    });
    [lines sortUsingComparator:^NSComparisonResult(UILabel* one, UILabel* other) {
      return [@(CGRectGetMinY([one convertRect:one.bounds toView:nil])) compare:@(CGRectGetMinY([other convertRect:other.bounds toView:nil]))];
    }];
    CGRect inkInGlyph = glyph ? PFBNotifInkInView(glyph) : CGRectNull;
    if (!glyph || lines.count < 2 || CGRectIsNull(inkInGlyph)) {
        PFBCompatMeasure(@"hidden notifications",
                         [NSString stringWithFormat:@"Chat's empty state not read: glyph %d, ink %d, %lu lines", glyph != nil,
                                                    !CGRectIsNull(inkInGlyph), (unsigned long)lines.count],
                         2);
        return;
    }
    UILabel* title = lines[0];
    UILabel* body = lines[1];
    CGFloat middle = CGRectGetHeight(empty.window.bounds) / 2.0;
    CGRect ink = [glyph convertRect:inkInGlyph toView:nil];
    CGRect t = [title convertRect:title.bounds toView:nil];
    CGRect b = [body convertRect:body.bounds toView:nil];
    CGFloat titleBase = CGRectGetMinY(t) + PFBNotifFirstBaseline(title);
    CGFloat titleLast = titleBase + CGRectGetHeight([title textRectForBounds:title.bounds limitedToNumberOfLines:title.numberOfLines]) -
                        title.font.lineHeight;
    CGFloat bodyBase = CGRectGetMinY(b) + PFBNotifFirstBaseline(body);
    BOOL template = glyph.image.renderingMode == UIImageRenderingModeAlwaysTemplate;
    UIColor* glyphColor = template ? glyph.tintColor : title.textColor;
    NSDictionary* layout = @{
        @"glyphInk" : @(CGRectGetHeight(ink)),
        @"glyphMid" : @(CGRectGetMidY(ink) - middle),
        @"glyphLight" : PFBNotifColorParts(glyphColor, UIUserInterfaceStyleLight),
        @"glyphDark" : PFBNotifColorParts(glyphColor, UIUserInterfaceStyleDark),
        @"titleFont" : PFBNotifFontParts(title.font),
        @"titleLight" : PFBNotifColorParts(title.textColor, UIUserInterfaceStyleLight),
        @"titleDark" : PFBNotifColorParts(title.textColor, UIUserInterfaceStyleDark),
        @"titleBase" : @(titleBase - middle),
        @"bodyFont" : PFBNotifFontParts(body.font),
        @"bodyLight" : PFBNotifColorParts(body.textColor, UIUserInterfaceStyleLight),
        @"bodyDark" : PFBNotifColorParts(body.textColor, UIUserInterfaceStyleDark),
        @"bodyStep" : @(bodyBase - titleLast),
        @"wrapWidth" : @(MAX(CGRectGetWidth(t), CGRectGetWidth(b))),
    };
    if ([layout isEqualToDictionary:PFBChatEmptyLayout() ?: @{}]) {
        return;
    }
    gPFBChatEmptyLayout = layout;
    [[NSUserDefaults standardUserDefaults] setObject:layout forKey:kPFBChatEmptyLayoutKey];
    PFBCompatMeasure(@"hidden notifications",
                     [NSString stringWithFormat:@"Chat's empty state read: glyph ink %.1f in %.0fx%.0f (image %.0fx%.0f, mode %ld%@), title %@ %.1f, "
                                                @"body %@ %.1f, from the screen's middle: ink %.1f, title baseline %.1f, line %.1f under it, wrap %.1f",
                                                CGRectGetHeight(ink), CGRectGetWidth(glyph.bounds), CGRectGetHeight(glyph.bounds), glyph.image.size.width,
                                                glyph.image.size.height, (long)glyph.contentMode, template ? @", template" : @"", title.font.fontName,
                                                title.font.pointSize, body.font.fontName, body.font.pointSize, CGRectGetMidY(ink) - middle,
                                                titleBase - middle, bodyBase - titleLast, MAX(CGRectGetWidth(t), CGRectGetWidth(b))],
                     6);
}

%hook _TtC6ChatUI18ChatEmptyStateView

- (void)layoutSubviews {
    %orig;
    @try {
        PFBNotifReadChatEmpty((UIView*)self);
    } @catch (__unused id exception) {
    }
}

%end

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
        // decided by how many rows carry a notification or a Tweet.
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
                if (model && ([NSStringFromClass([model class])
                                  containsString:@"Notification"] ||
                              PFBNotifTweetIdentity(model))) {
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

        PFBBundle* bundle = [PFBBundle sharedBundle];
        UIView* panel = PFBNotifEmptyPanel(@"notifications_stroke", [bundle localizedStringForKey:@"HIDDEN_NOTIFS_EMPTY_TITLE"],
                                           [bundle localizedStringForKey:@"HIDDEN_NOTIFS_EMPTY_BODY"]);
        panel.tag = kPFBNotifEmptyTag;

        // Faded in rather than popped, and timed to land as the last row finishes
        // sliding out, so the two read as one motion instead of a flash.
        panel.alpha = 0.0;
        PFBNotifPlaceEmptyPanel(panel, table);
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
        BOOL notificationsScreen = PFBNotifOnNotificationsScreen(dataViewController);
        BOOL sawNotification = NO;
        NSInteger examined = 0;
        NSInteger sections = table.numberOfSections;
        for (NSInteger s = 0; s < sections; s++) {
            NSInteger rows = [table numberOfRowsInSection:s];
            for (NSInteger r = 0; r < rows; r++) {
                NSIndexPath* path = [NSIndexPath indexPathForRow:r inSection:s];
                id item = ((id (*)(id, SEL, id))objc_msgSend)(dataViewController, itemSel, path);
                id model = item ? PFBUnwrapDataViewItem(item) : nil;
                BOOL notification = model && [NSStringFromClass([model class]) containsString:@"Notification"];
                // The All tab can hold only Tweet rows; on the notifications screen they
                // identify the list as well as a notification row does.
                BOOL tweetHere = model && notificationsScreen && PFBNotifTweetIdentity(model);
                if (model) {
                    examined++;
                    sawNotification = sawNotification || notification || tweetHere;
                }
                if ((notification || tweetHere) && PFBNotifIsHidden(model)) {
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
        // Rows this sweep removed were delivered: the list is loaded, only emptied.
        if (doomed.count) {
            objc_setAssociatedObject(dataViewController, kPFBNotifEverFilledKey, @YES,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
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
                PFBBarPairWithNeighbor(existing, item.rightBarButtonItems);
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
        // In the color of the bar's icons, which the Notifications bar pass repaints
        // when it changes (NavBarIcons.x). The same kind of item as the Explore
        // filters button, so both sit the same way beside the gear.
        UIBarButtonItem* ours = PFBBarGlyphItem(
            PFBFlatGlyph(glyph, PFBBarIconColor(viewController.traitCollection)),
            [[PFBBundle sharedBundle] localizedStringForKey:@"HIDDEN_NOTIFS_TITLE"],
            [PFBNotifQuickPresenter shared], @selector(present:));
        ours.tag = kPFBNotifBarItemTag;
        NSMutableArray<UIBarButtonItem*>* items =
            [NSMutableArray arrayWithArray:item.rightBarButtonItems ?: @[]];
        [items addObject:ours];
        item.rightBarButtonItems = items;
        PFBBarPairWithNeighbor(ours, item.rightBarButtonItems);
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
        id found = PFBNotifAsk(self, NSSelectorFromString(@"dismissButton"));
        if (![found isKindOfClass:[UIView class]]) {
            return;
        }
        UIView* dismiss = found;
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

// MARK: - The Tweet menu in the notifications tab (HiddenThreads.x)

BOOL PFBNotifControllerOnNotificationsScreen(UIViewController* controller) {
    return PFBNotifOnNotificationsScreen(controller);
}

BOOL PFBNotifViewOnNotificationsScreen(UIView* view) {
    UIResponder* responder = view;
    while (responder && ![responder isKindOfClass:[UIViewController class]]) {
        responder = responder.nextResponder;
    }
    return responder && PFBNotifOnNotificationsScreen(responder);
}

// Hides a Tweet's row in the notifications list: the row holding `source` when there is one,
// else the row of `status` among those `screen` shows. Filed as hidden, the row dropped and
// the toast shown; NO when no row is found.
BOOL PFBNotifHideTweet(id status, UIView* source, UIViewController* screen) {
    UIView* cell = source;
    while (cell && ![cell isKindOfClass:[UITableViewCell class]]) {
        cell = cell.superview;
    }
    UITableView* table = cell ? PFBNotifTableForCell(cell) : nil;
    NSIndexPath* path = table ? [table indexPathForCell:(UITableViewCell*)cell] : nil;
    if (!path && [status respondsToSelector:@selector(statusID)] && screen.viewIfLoaded) {
        NSString* identity = [NSString stringWithFormat:@"tw:%ld", (long)((TFNTwitterStatus*)status).statusID];
        __block UITableView* found = nil;
        __block NSIndexPath* foundPath = nil;
        PFBWalkAllSubviews(screen.view, 20, ^(UIView* view) {
          if (foundPath || ![view isKindOfClass:[UITableView class]]) {
              return;
          }
          UITableView* list = (UITableView*)view;
          for (NSIndexPath* candidate in list.indexPathsForVisibleRows) {
              id model = PFBModelAtIndexPath(list.dataSource, candidate) ?: PFBModelFromCell(list, candidate);
              if ([PFBNotifTweetIdentity(model) isEqualToString:identity]) {
                  found = list;
                  foundPath = candidate;
                  return;
              }
          }
        });
        table = found;
        path = foundPath;
    }
    if (!path || !PFBNotifOnNotificationsScreen(table.dataSource)) {
        return NO;
    }
    id model = PFBModelAtIndexPath(table.dataSource, path) ?: PFBModelFromCell(table, path);
    if (!PFBNotifTweetIdentity(model)) {
        return NO;
    }
    NSString* hiddenKey = PFBHideNotifWithText(model, PFBNotifTextFromCell(table, path));
    PFBNotifDropRow(table.dataSource, path);
    if (hiddenKey) {
        PFBShowNotifToast(hiddenKey);
    }
    return YES;
}
