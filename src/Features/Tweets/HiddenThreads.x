// Hide a conversation by its root identifier, from every list at once, through an
// entry added to the Tweet's menu.

#import "Support/HookHelpers.h"
#import "Support/TwitterChirpFont.h"
#import "Debug/PFBDebugger.h"
#import "Debug/PFBProbe.h"
#import <mach/mach_time.h>

static NSString* const kPFBHiddenThreadsKey = @"pfb_hidden_threads";
static NSString* const kPFBThreadIDKey = @"id";
static NSString* const kPFBThreadWhoKey = @"who";
static NSString* const kPFBThreadPreviewKey = @"preview";

static const CGFloat kPFBHideGlyphSide = 16.0;

// MARK: - Registry

NSArray<NSDictionary*>* PFBHiddenThreads(void) {
    NSArray* stored =
        [[NSUserDefaults standardUserDefaults] arrayForKey:kPFBHiddenThreadsKey];
    return [stored isKindOfClass:[NSArray class]] ? stored : @[];
}

static void PFBWriteHiddenThreads(NSArray<NSDictionary*>* threads) {
    [[NSUserDefaults standardUserDefaults] setObject:threads
                                              forKey:kPFBHiddenThreadsKey];
}

static BOOL PFBThreadIDIsHidden(NSString* threadID) {
    if (!threadID.length) {
        return NO;
    }
    for (NSDictionary* entry in PFBHiddenThreads()) {
        if ([entry[kPFBThreadIDKey] isEqualToString:threadID]) {
            return YES;
        }
    }
    return NO;
}

void PFBUnhideThread(NSString* threadID) {
    if (!threadID.length) {
        return;
    }
    NSMutableArray* kept = [PFBHiddenThreads() mutableCopy];
    NSMutableArray* removals = [NSMutableArray array];
    for (NSDictionary* entry in kept) {
        if ([entry[kPFBThreadIDKey] isEqualToString:threadID]) {
            [removals addObject:entry];
        }
    }
    [kept removeObjectsInArray:removals];
    PFBWriteHiddenThreads(kept);
}

// The newest goes first: the list is read as a history of what was just hidden.
static void PFBHideThread(NSString* threadID, NSString* who, NSString* preview) {
    if (!threadID.length || PFBThreadIDIsHidden(threadID)) {
        return;
    }
    NSMutableArray* kept = [PFBHiddenThreads() mutableCopy];
    [kept insertObject:@{
        kPFBThreadIDKey : threadID,
        kPFBThreadWhoKey : who ?: @"",
        kPFBThreadPreviewKey : preview ?: @""
    }
               atIndex:0];
    PFBWriteHiddenThreads(kept);
}

// MARK: - Reading a Tweet

// Values are asked of the model rather than assumed: a timeline carries several
// kinds of entry, and only some answer these.

// The return type is checked before the call. A timeline model answers some of
// these with an integer, and reading an integer as an object hands a number to
// the runtime as if it were an address.
static id PFBAsk(id target, SEL selector) {
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

// The same question for values that arrive as numbers, boxed or not.
static long long PFBAskInteger(id target, SEL selector) {
    if (!target || ![target respondsToSelector:selector]) {
        return 0;
    }
    NSMethodSignature* signature = [target methodSignatureForSelector:selector];
    const char* returnType = signature.methodReturnType;
    if (!returnType) {
        return 0;
    }
    // Every integer encoding, signed and unsigned: a count on a timeline model
    // is an NSUInteger, which reads as "Q".
    switch (returnType[0]) {
        case 'q':
        case 'Q':
            return ((long long (*)(id, SEL))objc_msgSend)(target, selector);
        case 'l':
        case 'L':
            return (long long)((long (*)(id, SEL))objc_msgSend)(target, selector);
        case 'i':
        case 'I':
            return (long long)((int (*)(id, SEL))objc_msgSend)(target, selector);
        case 's':
        case 'S':
            return (long long)((short (*)(id, SEL))objc_msgSend)(target, selector);
        case 'c':
        case 'C':
        case 'B':
            return (long long)((char (*)(id, SEL))objc_msgSend)(target, selector);
        default:
            break;
    }
    if (strcmp(returnType, "@") == 0) {
        id value = ((id (*)(id, SEL))objc_msgSend)(target, selector);
        if ([value isKindOfClass:[NSNumber class]]) {
            return ((NSNumber*)value).longLongValue;
        }
        if ([value isKindOfClass:[NSString class]]) {
            return ((NSString*)value).longLongValue;
        }
    }
    return 0;
}

static NSString* PFBStringValue(id value) {
    if ([value isKindOfClass:[NSString class]]) {
        return (NSString*)value;
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        return [(NSNumber*)value stringValue];
    }
    return nil;
}

// The conversation's own identifier when the model carries one; the Tweet's own
// when it does not, which is the case for a root that has replies.
static NSString* PFBIdentifierValue(id model, SEL selector) {
    NSString* text = PFBStringValue(PFBAsk(model, selector));
    if (text.length) {
        return text;
    }
    long long number = PFBAskInteger(model, selector);
    return number ? [@(number) stringValue] : nil;
}

static NSString* PFBThreadIDForModel(id model) {
    NSString* conversation = PFBIdentifierValue(model, @selector(conversationID));
    if (conversation.length) {
        return conversation;
    }
    NSString* inReplyTo = PFBIdentifierValue(model, @selector(inReplyToStatusID));
    if (inReplyTo.length) {
        return inReplyTo;
    }
    return PFBIdentifierValue(model, @selector(statusID));
}

// The timeline's view model does not answer replyCount; its own name for the same
// number is aggregatedDisplayReplyCount, asked when answered; replyCount otherwise.
static NSInteger PFBReplyCountForModel(id model) {
    if ([model respondsToSelector:@selector(aggregatedDisplayReplyCount)]) {
        return (NSInteger)PFBAskInteger(model,
                                        @selector(aggregatedDisplayReplyCount));
    }
    return (NSInteger)PFBAskInteger(model, @selector(replyCount));
}

// What makes an object usable here: it answers at least one of the four values
// this file needs. Requiring replyCount alone rejects a model that answers
// inReplyToStatusID and not the count.
static BOOL PFBRespondsToStatusValue(id candidate) {
    return [candidate respondsToSelector:@selector(replyCount)] ||
           [candidate respondsToSelector:@selector(aggregatedDisplayReplyCount)] ||
           [candidate respondsToSelector:@selector(conversationID)] ||
           [candidate respondsToSelector:@selector(inReplyToStatusID)] ||
           [candidate respondsToSelector:@selector(statusID)];
}

// Probe 10b#F024: what the ivar scan finds, once per model class and caller, at most 12. The
// caller is a button walk while gPFBProbeWalkDepth is set, the timeline otherwise.
static NSUInteger gPFBProbeWalkDepth;
static BOOL gPFBProbeScanDone;
static NSUInteger gPFBProbeScanRuns;
static NSUInteger gPFBProbeScanNoted;
static NSMutableSet* gPFBProbeScanTimeline;
static NSMutableSet* gPFBProbeScanMenu;

static void pfbProbeStatusScan(id model, Ivar* ivars, unsigned int count, id found) {
    if (gPFBProbeScanDone || !NSThread.isMainThread) {
        return;
    }
    if (!PFBDebugIsRecording() || gPFBProbeScanNoted >= 12 || ++gPFBProbeScanRuns > 5000) {
        gPFBProbeScanDone = YES;
        gPFBProbeScanTimeline = nil;
        gPFBProbeScanMenu = nil;
        return;
    }
    if (!gPFBProbeScanTimeline) {
        gPFBProbeScanTimeline = [NSMutableSet set];
        gPFBProbeScanMenu = [NSMutableSet set];
    }
    Class modelClass = [model class];
    NSMutableSet* seen = gPFBProbeWalkDepth ? gPFBProbeScanMenu : gPFBProbeScanTimeline;
    if ([seen containsObject:modelClass]) {
        return;
    }
    [seen addObject:modelClass];
    // Only the ivars the scan itself read are read again, up to the one it took, and compared by
    // address: no object is messaged here.
    unsigned int objects = 0;
    const char* foundName = NULL;
    for (unsigned int i = 0; i < count; i++) {
        const char* type = ivar_getTypeEncoding(ivars[i]);
        if (!type || type[0] != '@') {
            continue;
        }
        objects++;
        if (found && !foundName) {
            __unsafe_unretained id value = object_getIvar(model, ivars[i]);
            if (value == found) {
                foundName = ivar_getName(ivars[i]);
            }
        }
    }
    NSString* caller = gPFBProbeWalkDepth ? @"menu button" : @"timeline";
    NSString* result = found ? [NSString stringWithFormat:@"found %s (%@)", foundName ?: "?", PFBProbeClassName(found)]
                             : @"nothing";
    NSString* key = [NSString stringWithFormat:@"10b#F024 %@ %@", NSStringFromClass(modelClass), caller];
    if (PFBProbeWants(key)) {
        gPFBProbeScanNoted++;
        PFBProbeNote(key, @"10b#F024 status scan on %@ from the %@: %u object ivars, %@", NSStringFromClass(modelClass),
                     caller, objects, result);
    }
}

static id PFBStatusFromModel(id model) {
    if (!model) {
        return nil;
    }
    if (PFBRespondsToStatusValue(model)) {
        return model;
    }
    for (NSString* key in @[ @"status", @"tweet", @"canonicalStatus" ]) {
        @try {
            id candidate = [model valueForKey:key];
            if (PFBRespondsToStatusValue(candidate)) {
                return candidate;
            }
        } @catch (__unused NSException* exception) {
        }
    }
    unsigned int count = 0;
    Ivar* ivars = class_copyIvarList(object_getClass(model), &count);
    id found = nil;
    for (unsigned int i = 0; i < count && !found; i++) {
        const char* type = ivar_getTypeEncoding(ivars[i]);
        if (!type || type[0] != '@') {
            continue;
        }
        id value = object_getIvar(model, ivars[i]);
        if (PFBRespondsToStatusValue(value)) {
            found = value;
        }
    }
    // Probe: notes what the scan found, for 10b#F024.
    pfbProbeStatusScan(model, ivars, count, found);
    free(ivars);
    return found;
}

// A Tweet is part of a conversation when someone has answered it, or when it is
// itself an answer. Anything else yields no conversation to hide.
static BOOL PFBModelIsConversation(id model) {
    if (!model) {
        return NO;
    }
    if (PFBIdentifierValue(model, @selector(inReplyToStatusID)).length > 0) {
        return YES;
    }
    // The count decides only when it can be read. Where the model does not carry
    // it the Tweet counts as a conversation: hiding one is harmless on a Tweet
    // that has none.
    if ([model respondsToSelector:@selector(replyCount)] ||
        [model respondsToSelector:@selector(aggregatedDisplayReplyCount)]) {
        return PFBReplyCountForModel(model) > 0;
    }
    return YES;
}

static NSString* PFBAuthorHandleForModel(id model) {
    id author = PFBAsk(model, @selector(author)) ?: PFBAsk(model, @selector(user));
    NSString* handle = PFBStringValue(PFBAsk(author, @selector(username)));
    return handle.length ? [@"@" stringByAppendingString:handle] : @"";
}

static NSString* PFBPreviewForModel(id model) {
    NSString* text = PFBStringValue(PFBAsk(model, @selector(text)));
    if (!text.length) {
        return @"";
    }
    NSString* flat = [[text componentsSeparatedByCharactersInSet:
                                [NSCharacterSet newlineCharacterSet]]
        componentsJoinedByString:@" "];
    return flat.length > 90 ? [[flat substringToIndex:90]
                                 stringByAppendingString:@"…"]
                            : flat;
}

// Read by the timeline predicate, which owns the decision to drop an entry.
// The toggle gates the whole feature: off, nothing is treated as hidden, so the
// list the user built is kept on disk but not removed from the timeline.
BOOL pfbThreadIsHidden(id viewModel) {
    if (![PFBSettings boolForKey:@"hide_threads"]) {
        return NO;
    }
    if (!PFBHiddenThreads().count) {
        return NO;
    }
    return PFBThreadIDIsHidden(PFBThreadIDForModel(PFBStatusFromModel(viewModel)));
}

// MARK: - The glyph

// Drawn rather than taken from the system set, since the icons of the Tweet's menu
// have a thin even stroke of their own. A speech bubble crossed by a stroke that
// leaves a gap around itself so both shapes stay legible at this size.

static UIImage* PFBHideThreadGlyph(UIColor* colour) {
    CGFloat side = kPFBHideGlyphSide;
    UIGraphicsImageRendererFormat* format =
        [UIGraphicsImageRendererFormat preferredFormat];
    format.opaque = NO;
    UIGraphicsImageRenderer* renderer =
        [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)
                                               format:format];
    UIImage* drawn = [renderer
        imageWithActions:^(UIGraphicsImageRendererContext* _Nonnull context) {
          CGContextRef ctx = context.CGContext;
          CGFloat line = 1.6;
          [colour setStroke];
          CGContextSetLineWidth(ctx, line);
          CGContextSetLineCap(ctx, kCGLineCapRound);
          CGContextSetLineJoin(ctx, kCGLineJoinRound);

          // The bubble: a rounded box across the top three quarters, with a
          // tail dropped from its lower left.
          CGRect box = CGRectMake(line, line, side - line * 2, side * 0.72);
          UIBezierPath* bubble = [UIBezierPath bezierPathWithRoundedRect:box
                                                            cornerRadius:side * 0.26];
          [bubble moveToPoint:CGPointMake(side * 0.30, CGRectGetMaxY(box))];
          [bubble addLineToPoint:CGPointMake(side * 0.26, side - line)];
          [bubble addLineToPoint:CGPointMake(side * 0.52, CGRectGetMaxY(box))];
          bubble.lineWidth = line;
          [bubble stroke];

          // The stroke across it, drawn twice: once clearing a gap, once in the
          // color, so it reads as passing over the bubble rather than through
          // it.
          UIBezierPath* slash = [UIBezierPath bezierPath];
          [slash moveToPoint:CGPointMake(side * 0.17, side * 0.83)];
          [slash addLineToPoint:CGPointMake(side * 0.83, side * 0.17)];
          slash.lineWidth = line * 2.6;
          slash.lineCapStyle = kCGLineCapRound;
          CGContextSetBlendMode(ctx, kCGBlendModeClear);
          [slash stroke];
          CGContextSetBlendMode(ctx, kCGBlendModeNormal);
          slash.lineWidth = line;
          [colour setStroke];
          [slash stroke];
        }];
    return [drawn imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

// Refreshing the muted words folds the hidden conversations into the timeline's memo
// signature. Reloading the table does nothing: the filter runs when sections are
// handed to the data view controller, so Timeline.x replays that hand-over.
static void PFBReloadList(void) {
    pfbRefreshMutedWords();
    pfbReapplyTimelineFilter();
}

// MARK: - The confirmation strip

// Built here end to end, since the app's own strip draws its label white with no
// way to change it. Placed where the app puts its own: a capsule at the top, over
// the header, with the text in the system label color.

static const NSInteger kPFBToastTag = 90312;

static void PFBDismissToast(UIView* toast) {
    [UIView animateWithDuration:0.22
        animations:^{
          toast.alpha = 0;
          toast.transform = CGAffineTransformMakeTranslation(0.0, -8.0);
        }
        completion:^(BOOL finished) {
          [toast removeFromSuperview];
        }];
}

static void PFBShowHiddenToast(NSString* threadID) {
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
    [[window viewWithTag:kPFBToastTag] removeFromSuperview];

    // Under Liquid Glass the capsule is real glass, which draws its own rounded
    // shape and edge. Under the standard interface it is the frosted material,
    // clipped to a rounded rect with a hairline border.
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
    toast.tag = kPFBToastTag;
    toast.translatesAutoresizingMaskIntoConstraints = NO;
    if (!liquidGlass) {
        // Real glass shapes itself; the material capsule needs the corners and
        // the border drawn on.
        toast.clipsToBounds = YES;
        toast.layer.cornerRadius = 22.0;
        toast.layer.cornerCurve = kCACornerCurveContinuous;
        toast.layer.borderWidth = 0.5;
        toast.layer.borderColor = [UIColor separatorColor].CGColor;
    } else {
        // The glass rounds its own corners once told the radius; nothing is
        // clipped, so its shadow and edge treatment survive.
        toast.layer.cornerRadius = 22.0;
        toast.layer.cornerCurve = kCACornerCurveContinuous;
    }
    [window addSubview:toast];

    UIView* content = toast.contentView;

    // The same veil as the hidden-notification toast: pure glass lets the timeline
    // read through the words, and 80 % of the background color keeps the material
    // visible. The rounded corners and masksToBounds are not optional.
    UIView* veil = [[UIView alloc] init];
    veil.backgroundColor = [[UIColor systemBackgroundColor] colorWithAlphaComponent:0.80];
    veil.userInteractionEnabled = NO;    // Undo must stay tappable
    veil.layer.cornerRadius = 22.0;      // exactly the capsule's radius above
    veil.layer.cornerCurve = kCACornerCurveContinuous;
    veil.layer.masksToBounds = YES;
    veil.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:veil];           // BEFORE the label, so it sits behind
    [NSLayoutConstraint activateConstraints:@[
        [veil.topAnchor constraintEqualToAnchor:content.topAnchor],
        [veil.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
        [veil.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [veil.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
    ]];

    UILabel* label = [[UILabel alloc] init];
    label.text = [[PFBBundle sharedBundle] localizedStringForKey:@"THREADS_HIDDEN_TOAST"];
    label.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:15]);
    label.textColor = [UIColor labelColor];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:label];

    UIButton* undo = [UIButton buttonWithType:UIButtonTypeSystem];
    [undo setTitle:[[PFBBundle sharedBundle] localizedStringForKey:@"THREADS_UNDO"]
          forState:UIControlStateNormal];
    [undo setTitleColor:PFBCurrentAccentColor() forState:UIControlStateNormal];
    undo.titleLabel.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleSemibold) fontWithSize:15]);
    undo.translatesAutoresizingMaskIntoConstraints = NO;
    // Weak: the toast holds the button, which holds this action.
    __weak UIVisualEffectView* weakToast = toast;
    [undo addAction:[UIAction actionWithHandler:^(__unused UIAction* action) {
              PFBUnhideThread(threadID);
              pfbRefreshMutedWords();
              pfbReapplyTimelineFilter();
              PFBDismissToast(weakToast);
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
                         PFBDismissToast(toast);
                     }
                   });
}

// MARK: - The entry in the Tweet's own menu

// The Tweet's menu is caught as it is set on its caret button (-[UIButton setMenu:]),
// and the entry is appended to it.

// Probe: milliseconds from mach_absolute_time ticks.
static double pfbProbeMs(uint64_t ticks) {
    static mach_timebase_info_data_t timebase;
    if (!timebase.denom) {
        mach_timebase_info(&timebase);
    }
    return (double)ticks * (double)timebase.numer / (double)timebase.denom / 1e6;
}

// Probe 10b#F023: the walks from a button up to its Tweet during the first full tour run to its
// end, the exceptions they catch, their time, the entries added and the buttons that start them;
// noted then or after 500 walks. A nested walk is counted for its caller only.
static int gPFBProbeWalkState;   // 0 not read yet, 1 open, 2 closed
static BOOL gPFBProbeWalkTimed;
static struct {
    NSUInteger walks, exceptions, entries;
    uint64_t ticks, longest;
} gPFBProbeWalk;
static NSCountedSet* gPFBProbeWalkButtons;

static void pfbProbeWalkNote(NSString* when) {
    if (gPFBProbeWalkState != 1) {
        return;
    }
    gPFBProbeWalkState = 2;
    NSCountedSet* buttons = gPFBProbeWalkButtons;
    NSArray* ranked = [buttons.allObjects sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
      NSUInteger countA = [buttons countForObject:a];
      NSUInteger countB = [buttons countForObject:b];
      return countA > countB ? NSOrderedAscending : (countA < countB ? NSOrderedDescending : NSOrderedSame);
    }];
    NSMutableArray<NSString*>* top = [NSMutableArray array];
    for (id buttonClass in ranked) {
        if (top.count == 3) {
            break;
        }
        [top addObject:[NSString stringWithFormat:@"%@ x%lu", NSStringFromClass((Class)buttonClass),
                                                  (unsigned long)[buttons countForObject:buttonClass]]];
    }
    PFBProbeNote(@"10b#F023 menu walk",
                 @"10b#F023 menu walk %@: %lu walks, %lu exceptions, %.1f ms in total, longest %.2f ms, entries "
                 @"added %lu, buttons: %@",
                 when, (unsigned long)gPFBProbeWalk.walks, (unsigned long)gPFBProbeWalk.exceptions,
                 pfbProbeMs(gPFBProbeWalk.ticks), pfbProbeMs(gPFBProbeWalk.longest),
                 (unsigned long)gPFBProbeWalk.entries, top.count ? [top componentsJoinedByString:@", "] : @"none");
    gPFBProbeWalkButtons = nil;
}

// 0 when no probe needs the walk, 1 when it only counts for 10b#F024, else its start time.
static uint64_t pfbProbeWalkBegin(UIView* button) {
    if (gPFBProbeWalkState == 2 && gPFBProbeScanDone) {
        return 0;
    }
    if (!PFBDebugIsRecording()) {
        gPFBProbeWalkState = 2;
        gPFBProbeScanDone = YES;
        return 0;
    }
    if (gPFBProbeWalkState == 0) {
        gPFBProbeWalkState = PFBProbeWants(@"10b#F023 menu walk") ? 1 : 2;
        if (gPFBProbeWalkState == 1) {
            gPFBProbeWalkButtons = [NSCountedSet set];
            [[NSNotificationCenter defaultCenter] addObserverForName:PFBProbeTourEndedNotification
                                                              object:nil
                                                               queue:nil
                                                          usingBlock:^(__unused NSNotification* note) {
                                                            // A tour stopped early or not full is left out.
                                                            if ([PFBCompatTourLastRun() hasPrefix:@"Full tour"]) {
                                                                pfbProbeWalkNote(@"during the tour");
                                                            } else if (gPFBProbeWalkState == 1) {
                                                                memset(&gPFBProbeWalk, 0, sizeof(gPFBProbeWalk));
                                                                [gPFBProbeWalkButtons removeAllObjects];
                                                            }
                                                          }];
        }
    }
    gPFBProbeWalkDepth++;
    if (gPFBProbeWalkState != 1 || gPFBProbeWalkDepth > 1 || !button || !PFBCompatTourIsRunning() ||
        !NSThread.isMainThread) {
        return 1;
    }
    [gPFBProbeWalkButtons addObject:[button class]];
    gPFBProbeWalkTimed = YES;
    return mach_absolute_time();
}

static void pfbProbeWalkEnd(uint64_t* start) {
    if (!*start) {
        return;
    }
    gPFBProbeWalkDepth--;
    if (*start == 1) {
        return;
    }
    uint64_t ticks = mach_absolute_time() - *start;
    gPFBProbeWalkTimed = NO;
    gPFBProbeWalk.walks++;
    gPFBProbeWalk.ticks += ticks;
    gPFBProbeWalk.longest = MAX(gPFBProbeWalk.longest, ticks);
    if (gPFBProbeWalk.walks >= 500) {
        pfbProbeWalkNote(@"after 500 walks");
    }
}

static void pfbProbeWalkException(void) {
    if (gPFBProbeWalkTimed) {
        gPFBProbeWalk.exceptions++;
    }
}

// From the caret button up to the Tweet it belongs to. The chain is walked at
// the moment it is needed — when the menu is built, and again when the entry is
// tapped — so nothing is cached and nothing can go stale.
static id PFBStatusForButton(UIView* button) {
    // Probe: times this walk for 10b#F023 and names it the scan's caller for 10b#F024; the
    // cleanup runs on every return.
    uint64_t probeWalk __attribute__((cleanup(pfbProbeWalkEnd))) = pfbProbeWalkBegin(button);
    UIView* node = button;
    NSInteger depth = 0;
    while (node && depth < 14) {
        id model = nil;
        @try {
            model = [node valueForKey:@"viewModel"];
        } @catch (__unused NSException* exception) {
            // Probe: counts the exception for 10b#F023.
            pfbProbeWalkException();
            model = nil;
        }
        id status = PFBStatusFromModel(model);
        if (status && PFBModelIsConversation(status)) {
            return status;
        }
        node = node.superview;
        depth++;
    }
    return nil;
}

static NSString* PFBThreadIDForButton(UIView* button) {
    return PFBThreadIDForModel(PFBStatusForButton(button));
}

static NSString* PFBAuthorForButton(UIView* button) {
    return PFBAuthorHandleForModel(PFBStatusForButton(button));
}

static NSString* PFBPreviewForButton(UIView* button) {
    return PFBPreviewForModel(PFBStatusForButton(button));
}

static BOOL PFBMenuBelongsToTweet(UIMenu* menu) {
    NSString* mark = [[PFBBundle sharedBundle]
        localizedTwitterStringForKey:@"NOT_INTERESTED_IN_THIS_LABEL"];
    if (!mark.length) {
        return NO;
    }
    for (UIMenuElement* element in menu.children) {
        if ([element.title isEqualToString:mark]) {
            return YES;
        }
    }
    return NO;
}

// Probe 10B#B8: whether a Tweet's menu already holds the hide entry before it is appended, once
// for each case; also counts the entries added during the tour for 10b#F023.
static BOOL gPFBProbeEntryDone;
static NSUInteger gPFBProbeEntryLooks;

// Probe: the elements titled like the hide entry, submenus included.
static NSUInteger pfbProbeEntryCount(NSArray<UIMenuElement*>* elements, NSString* title) {
    NSUInteger held = 0;
    for (UIMenuElement* element in elements) {
        if ([element.title isEqualToString:title]) {
            held++;
        }
        if ([element isKindOfClass:[UIMenu class]]) {
            held += pfbProbeEntryCount(((UIMenu*)element).children, title);
        }
    }
    return held;
}

static void pfbProbeHideEntry(UIMenu* menu, UIView* button, NSString* title) {
    if (gPFBProbeWalkState == 1 && PFBCompatTourIsRunning()) {
        gPFBProbeWalk.entries++;
    }
    if (gPFBProbeEntryDone) {
        return;
    }
    if (!PFBDebugIsRecording() || ++gPFBProbeEntryLooks > 500) {
        gPFBProbeEntryDone = YES;
        return;
    }
    NSUInteger held = pfbProbeEntryCount(menu.children, title);
    NSUInteger children = menu.children.count;
    if (held && PFBProbeWants(@"10B#B8 twice")) {
        PFBProbeNote(@"10B#B8 twice",
                     @"10B#B8 hide entry: Tweet menu on %@ already holds the hide entry (%lu times, %lu children) "
                     @"before the append: it would show twice",
                     PFBProbeClassName(button), (unsigned long)held, (unsigned long)children);
    } else if (!held && PFBProbeWants(@"10B#B8 normal")) {
        PFBProbeNote(@"10B#B8 normal", @"10B#B8 hide entry: appended to a menu of %lu children with none yet",
                     (unsigned long)children);
    }
    gPFBProbeEntryDone = !PFBProbeWants(@"10B#B8 twice") && !PFBProbeWants(@"10B#B8 normal");
}

%hook UIButton

- (void)setMenu:(UIMenu*)menu {
    // A Tweet's menu reaching here is the path, whatever the toggle and the Tweet.
    if ([menu isKindOfClass:[UIMenu class]] && PFBCompatNeedsObservation(PFBCompat_hide_threads) &&
        (PFBMenuBelongsToTweet(menu) || PFBThreadIDForButton((UIView*)self).length)) {
        PFBCOMPAT_OBSERVE(PFBCompat_hide_threads, @"Tweet menu found");
    }
    if (![menu isKindOfClass:[UIMenu class]] ||
        ![PFBSettings boolForKey:@"hide_threads"]) {
        %orig;
        return;
    }
    UIView* button = (UIView*)self;
    // Either the menu names itself — an entry the app puts there — or the button
    // sits under a Tweet. The second covers a menu still being assembled, whose
    // entries are not readable yet.
    if (!PFBMenuBelongsToTweet(menu) && !PFBThreadIDForButton(button).length) {
        %orig;
        return;
    }
    __weak UIView* weakButton = button;
    NSString* title =
        [[PFBBundle sharedBundle] localizedStringForKey:@"THREADS_HIDE_ACTION"];
    UIColor* colour = [UIColor labelColor];
    colour = [colour resolvedColorWithTraitCollection:button.traitCollection] ?: colour;
    UIAction* hide = [UIAction
        actionWithTitle:title
                  image:PFBHideThreadGlyph(colour)
             identifier:nil
                handler:^(__unused UIAction* action) {
                  UIView* source = weakButton;
                  NSString* threadID = PFBThreadIDForButton(source);
                  if (!threadID.length) {
                      return;
                  }
                  PFBHideThread(threadID, PFBAuthorForButton(source),
                                PFBPreviewForButton(source));
                  PFBReloadList();
                  PFBShowHiddenToast(threadID);
                }];
    PFBCOMPAT_ACTION(PFBCompat_hide_threads, @"hide entry in a Tweet menu");
    // Probe: counts the hide entries the menu already holds, for 10B#B8 and 10b#F023.
    pfbProbeHideEntry(menu, button, title);
    %orig([menu menuByReplacingChildren:[menu.children arrayByAddingObject:hide]]);
}

%end
