// NotifProbe.x — read-only reconnaissance for "Hide a notification".
//
// GO given 17/08. Before a single line of the feature, one measurement build
// that names the whole terrain at once (the lesson that unblocked Muted Words
// and Hidden Threads: a complete probe beats a string of blind builds). This
// file HIDES NOTHING, changes NOTHING, adds no button — it only reads and
// writes to the Diagnostic log. Delete it (git rm) once its capture is in.
//
// It answers, in one screenshot of DÉCISIONS:
//   1. The notifications list's view-model class, and which of its selectors
//      carry the STABLE ID, the DATE, and the TEXT — the three fields the
//      feature needs. Printed once per distinct class seen.
//   2. The owning view controller's class name — the scope anchor for the
//      quick-access button, resolved the proven way (childViewControllers,
//      not just self — the ScrollEdgeEffect lesson).
//   3. Whether the notifications list speaks the NATIVE swipe mechanism the
//      conversations list uses (his lead) — i.e. does its data view controller
//      or table delegate answer trailingSwipeActionsConfigurationForRowAt.
//   4. The AGE of the oldest visible notification — to calibrate the real
//      expiry horizon Twitter enforces, instead of guessing 30 days.
//
// Everything is gated so it fires ONLY on the notifications surface and only
// while recording, and every value is read through the type-safe askers so a
// wrong signature can never retain a stray integer (the statusDidUpdate crash
// lesson).

#import "HookHelpers.h"
#import "Debug/NFBDebugger.h"

// ---- type-safe readers (same contract as HiddenThreads' NFBAsk) ----
static id NFBProbeAsk(id target, SEL selector) {
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

static double NFBProbeAskDouble(id target, SEL selector) {
    if (!target || ![target respondsToSelector:selector]) {
        return 0;
    }
    NSMethodSignature* signature = [target methodSignatureForSelector:selector];
    const char* type = signature.methodReturnType;
    if (!type) {
        return 0;
    }
    // Accept the numeric shapes a date/timestamp arrives in.
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

// The notifications surface, resolved defensively: the controller itself or a
// child whose class name marks it. URT notifications live under classes that
// carry "Notification" (e.g. the activity/notifications timeline); the account
// tab's own list does too. Never the home timeline (that has its own owner).
static BOOL NFBProbeIsNotifications(UIViewController* vc) {
    if (!vc) {
        return NO;
    }
    NSString* own = NSStringFromClass([vc classForCoder]);
    if ([own containsString:@"Notification"] || [own containsString:@"Activity"]) {
        return YES;
    }
    for (UIViewController* child in vc.childViewControllers) {
        NSString* childName = NSStringFromClass([child classForCoder]);
        if ([childName containsString:@"Notification"] ||
            [childName containsString:@"Activity"]) {
            return YES;
        }
    }
    return NO;
}

static UIViewController* NFBProbeOwningVC(id dataViewController) {
    UIResponder* responder = dataViewController;
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

// Try a list of selectors on a target, return the first that yields a value,
// naming it — so the capture shows WHICH selector carries the field.
static NSString* NFBProbeFindStringField(id vm, NSArray<NSString*>* selectors,
                                         NSString** outSel) {
    for (NSString* name in selectors) {
        SEL sel = NSSelectorFromString(name);
        id value = NFBProbeAsk(vm, sel);
        NSString* text = nil;
        if ([value isKindOfClass:[NSString class]]) {
            text = value;
        } else if (value && [value respondsToSelector:@selector(string)]) {
            id s = ((id (*)(id, SEL))objc_msgSend)(value, @selector(string));
            if ([s isKindOfClass:[NSString class]]) {
                text = s;
            }
        }
        if (text.length) {
            if (outSel) { *outSel = name; }
            return text;
        }
    }
    return nil;
}

static NSString* NFBProbeFindIdField(id vm, NSArray<NSString*>* selectors,
                                     NSString** outSel) {
    for (NSString* name in selectors) {
        SEL sel = NSSelectorFromString(name);
        id value = NFBProbeAsk(vm, sel);
        if ([value isKindOfClass:[NSString class]] && ((NSString*)value).length) {
            if (outSel) { *outSel = name; }
            return (NSString*)value;
        }
    }
    return nil;
}

static double NFBProbeFindDateField(id vm, NSArray<NSString*>* selectors,
                                    NSString** outSel) {
    for (NSString* name in selectors) {
        SEL sel = NSSelectorFromString(name);
        double t = NFBProbeAskDouble(vm, sel);
        // A plausible unix timestamp (after 2015, before 2035).
        if (t > 1420000000 && t < 2050000000) {
            if (outSel) { *outSel = name; }
            return t;
        }
        // Some dates arrive in ms.
        if (t > 1420000000000.0 && t < 2050000000000.0) {
            if (outSel) { *outSel = name; }
            return t / 1000.0;
        }
    }
    return 0;
}

%hook TFNItemsDataViewController

- (void)setSections:(NSArray*)sections restoreScrollPosition:(BOOL)restore {
    %orig;

    if (!NFBDebugIsRecording()) {
        return;
    }
    UIViewController* owner = NFBProbeOwningVC(self);
    if (!NFBProbeIsNotifications(owner)) {
        return;  // not the notifications surface — stay silent
    }

    // (2) the scope anchor, printed once.
    static NSMutableSet<NSString*>* seenOwners;
    if (!seenOwners) { seenOwners = [NSMutableSet set]; }
    NSString* ownerName = NSStringFromClass([owner classForCoder]);
    NSMutableArray<NSString*>* childNames = [NSMutableArray array];
    for (UIViewController* child in owner.childViewControllers) {
        [childNames addObject:NSStringFromClass([child classForCoder])];
    }
    if (![seenOwners containsObject:ownerName]) {
        [seenOwners addObject:ownerName];
        NFBDebugLog(@"notifprobe: écran=%@ | enfants=%@ | dataVC=%@",
                    ownerName,
                    childNames.count ? [childNames componentsJoinedByString:@","] : @"-",
                    NSStringFromClass([self classForCoder]));
    }

    // (3) native swipe support — his lead. Does this list answer the same
    // trailing-swipe delegate call the conversations list uses?
    static BOOL swipeReported;
    if (!swipeReported) {
        swipeReported = YES;
        SEL swipeSel = NSSelectorFromString(
            @"tableView:trailingSwipeActionsConfigurationForRowAtIndexPath:");
        SEL leadingSel = NSSelectorFromString(
            @"tableView:leadingSwipeActionsConfigurationForRowAtIndexPath:");
        SEL editSel = NSSelectorFromString(
            @"tableView:commitEditingStyle:forRowAtIndexPath:");
        BOOL trailing = [self respondsToSelector:swipeSel];
        BOOL leading = [self respondsToSelector:leadingSel];
        BOOL legacy = [self respondsToSelector:editSel];
        NFBDebugLog(@"notifprobe: swipe natif — trailing=%d leading=%d legacy=%d "
                    @"(dataVC est le delegate?)",
                    trailing, leading, legacy);
    }

    // (1)+(4) walk the items: catalogue each distinct view-model class once,
    // and track the oldest date seen across the visible set.
    static NSMutableSet<NSString*>* seenVMs;
    if (!seenVMs) { seenVMs = [NSMutableSet set]; }

    NSArray<NSString*>* idSelectors = @[
        @"entryId", @"entryID", @"identifier", @"clientEventInfo",
        @"sortIndex", @"notificationId", @"notificationID", @"id"
    ];
    NSArray<NSString*>* dateSelectors = @[
        @"timestamp", @"sortTimestamp", @"createdAt", @"date",
        @"sortDate", @"timeInMs", @"createdAtMs", @"time"
    ];
    NSArray<NSString*>* textSelectors = @[
        @"text", @"message", @"displayText", @"bodyText", @"title",
        @"formattedText", @"attributedText", @"summary", @"notificationText"
    ];

    double oldest = 0;
    NSInteger counted = 0;
    for (id section in sections) {
        NSArray* items = nil;
        if ([section respondsToSelector:@selector(items)]) {
            id maybe = ((id (*)(id, SEL))objc_msgSend)(section, @selector(items));
            if ([maybe isKindOfClass:[NSArray class]]) { items = maybe; }
        } else if ([section isKindOfClass:[NSArray class]]) {
            items = section;
        }
        for (id item in items) {
            id vm = unwrapDataViewItem(item);
            if (!vm) { continue; }
            counted++;
            NSString* vmClass = NSStringFromClass([vm classForCoder]);

            if (![seenVMs containsObject:vmClass]) {
                [seenVMs addObject:vmClass];
                NSString* idSel = nil, *dateSel = nil, *textSel = nil;
                NSString* idVal = NFBProbeFindIdField(vm, idSelectors, &idSel);
                double dateVal = NFBProbeFindDateField(vm, dateSelectors, &dateSel);
                NSString* textVal = NFBProbeFindStringField(vm, textSelectors, &textSel);
                NSString* preview = textVal.length > 40
                    ? [textVal substringToIndex:40] : (textVal ?: @"-");
                NFBDebugLog(@"notifprobe: VM=%@ | id=%@(%@) | date=%@(%@) | texte=%@(«%@»)",
                            vmClass,
                            idSel ?: @"INTROUVABLE", idVal ? @"ok" : @"-",
                            dateSel ?: @"INTROUVABLE",
                            dateVal > 0 ? @"ok" : @"-",
                            textSel ?: @"INTROUVABLE", preview);
            }

            // oldest date across everything visible (for horizon calibration)
            double t = NFBProbeFindDateField(vm, dateSelectors, NULL);
            if (t > 0 && (oldest == 0 || t < oldest)) {
                oldest = t;
            }
        }
    }

    if (oldest > 0) {
        double ageDays = ([[NSDate date] timeIntervalSince1970] - oldest) / 86400.0;
        NFBDebugLog(@"notifprobe: %ld items | plus vieille notif ≈ %.1f jours (horizon)",
                    (long)counted, ageDays);
    } else if (counted > 0) {
        NFBDebugLog(@"notifprobe: %ld items | aucune date lisible (voir selecteurs ci-dessus)",
                    (long)counted);
    }
}

%end
