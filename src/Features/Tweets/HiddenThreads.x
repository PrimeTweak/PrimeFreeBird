// Hide a conversation by its root identifier, from every list at once. The button
// joins the actions under a Tweet only when the Tweet is part of a conversation.

#import "Support/HookHelpers.h"
#import <string.h>
#import "Support/TwitterChirpFont.h"

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
// the runtime as if it were an address — which is exactly how this crashed.
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
    // is an NSUInteger, which reads as "Q" — accepting only "q", "l" and "i"
    // answered zero for every Tweet, so no button was ever shown.
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
// number is aggregatedDisplayReplyCount. Both are asked, in that order.
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

static id PFBStatusFromModel(id model) {
    if (!model) {
        return nil;
    }
    if (PFBRespondsToStatusValue(model)) {
        return model;
    }
    for (NSString* key in @[ @"status", @"tweet", @"canonicalStatus", @"statusModel" ]) {
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
    free(ivars);
    return found;
}

// A Tweet is part of a conversation when someone has answered it, or when it is
// itself an answer. Anything else gets no button.
static BOOL PFBModelIsConversation(id model) {
    if (!model) {
        return NO;
    }
    if (PFBIdentifierValue(model, @selector(inReplyToStatusID)).length > 0) {
        return YES;
    }
    // The count decides only when it can be read. Where the model does not carry
    // it the button is shown rather than withheld: hiding a conversation is
    // harmless on a Tweet that has none.
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

// Drawn rather than taken from the system set, since the icons in this row have a
// thin even stroke of their own. A speech bubble crossed by a stroke that leaves a
// gap around itself so both shapes stay legible at this size.

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

// The timeline memoises its filtering verdict per item, keyed by a signature that
// folds in the number of hidden conversations, so hiding one invalidates the memo.
// The list is then reloaded, which drops the row with the right heights.
extern void pfbRefreshMutedWords(void);

static UIScrollView* PFBListForButton(UIView* view) {
    UIView* node = view;
    NSInteger depth = 0;
    while (node && depth < 14) {
        if ([node isKindOfClass:[UITableView class]] ||
            [node isKindOfClass:[UICollectionView class]]) {
            return (UIScrollView*)node;
        }
        node = node.superview;
        depth++;
    }
    return nil;
}

// Reloading the table does nothing: the filter is applied when the sections are
// handed to the data view controller, not when the table draws. Timeline.x
// therefore replays that hand-over on every list on screen.
extern void pfbReapplyTimelineFilter(void);

static void PFBReloadList(__unused UIScrollView* list) {
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
    extern UIColor* PFBCurrentAccentColor(void);
    [undo setTitleColor:PFBCurrentAccentColor() ?: [UIColor labelColor]
               forState:UIControlStateNormal];
    undo.titleLabel.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleSemibold) fontWithSize:15]);
    undo.translatesAutoresizingMaskIntoConstraints = NO;
    [undo addAction:[UIAction actionWithHandler:^(__unused UIAction* action) {
              PFBUnhideThread(threadID);
              pfbRefreshMutedWords();
              pfbReapplyTimelineFilter();
              PFBDismissToast(toast);
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

// The menu under the caret is a UIKit context menu built from a UIMenu, vended by
// TFNButton and TFNMenuCompatibleControl. The action provider is wrapped in the
// public factory below rather than read out of the configuration.

// From the caret button up to the Tweet it belongs to. The chain is walked at
// the moment it is needed — when the menu is built, and again when the entry is
// tapped — so nothing is cached and nothing can go stale.
static id PFBStatusForButton(UIView* button) {
    UIView* node = button;
    NSInteger depth = 0;
    while (node && depth < 14) {
        id model = nil;
        @try {
            model = [node valueForKey:@"viewModel"];
        } @catch (__unused NSException* exception) {
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
    // The list is noted here, while the button is still in the cell: by the time
    // the entry is tapped, the menu has taken the button out of the hierarchy
    // and the walk upwards finds nothing to reload.
    __weak UIScrollView* weakList = PFBListForButton(button);
    NSString* title =
        [[PFBBundle sharedBundle] localizedStringForKey:@"THREADS_HIDE_ACTION"];
    UIColor* colour = [UIColor labelColor];
    if ([colour respondsToSelector:@selector(resolvedColorWithTraitCollection:)]) {
        colour = [colour resolvedColorWithTraitCollection:button.traitCollection] ?: colour;
    }
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
                  PFBReloadList(weakList ?: (UIScrollView*)PFBListForButton(source));
                  PFBShowHiddenToast(threadID);
                }];
    PFBCOMPAT_ACTION(PFBCompat_hide_threads, @"hide entry in a Tweet menu");
    %orig([menu menuByReplacingChildren:[menu.children arrayByAddingObject:hide]]);
}

%end
