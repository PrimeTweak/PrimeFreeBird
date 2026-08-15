//
//  HiddenThreads.x
//  PrimeFreeBird
//
//  Hiding a conversation.
//
//  A conversation is kept by its root identifier, so hiding one from any list
//  hides it in every other: there is no per-tab state to fall out of step. The
//  registry lives in NSUserDefaults beside the muted words, and the timeline
//  predicate reads it through nfbThreadIsHidden.
//
//  The button is added to the row of actions under a Tweet, and only when the
//  Tweet is part of a conversation — a root with replies, or a reply itself.
//  Under a lone Tweet there is nothing to hide, and the row is left as Twitter
//  built it.
//

#import "HookHelpers.h"
#import <string.h>

static NSString* const kNFBHiddenThreadsKey = @"nfb_hidden_threads";
static NSString* const kNFBThreadIDKey = @"id";
static NSString* const kNFBThreadWhoKey = @"who";
static NSString* const kNFBThreadPreviewKey = @"preview";

static const CGFloat kNFBHideGlyphSide = 16.0;

// MARK: - Registry

NSArray<NSDictionary*>* NFBHiddenThreads(void) {
    NSArray* stored =
        [[NSUserDefaults standardUserDefaults] arrayForKey:kNFBHiddenThreadsKey];
    return [stored isKindOfClass:[NSArray class]] ? stored : @[];
}

static void NFBWriteHiddenThreads(NSArray<NSDictionary*>* threads) {
    [[NSUserDefaults standardUserDefaults] setObject:threads
                                              forKey:kNFBHiddenThreadsKey];
}

static BOOL NFBThreadIDIsHidden(NSString* threadID) {
    if (!threadID.length) {
        return NO;
    }
    for (NSDictionary* entry in NFBHiddenThreads()) {
        if ([entry[kNFBThreadIDKey] isEqualToString:threadID]) {
            return YES;
        }
    }
    return NO;
}

void NFBUnhideThread(NSString* threadID) {
    if (!threadID.length) {
        return;
    }
    NSMutableArray* kept = [NFBHiddenThreads() mutableCopy];
    NSMutableArray* removals = [NSMutableArray array];
    for (NSDictionary* entry in kept) {
        if ([entry[kNFBThreadIDKey] isEqualToString:threadID]) {
            [removals addObject:entry];
        }
    }
    [kept removeObjectsInArray:removals];
    NFBWriteHiddenThreads(kept);
}

// The newest goes first: the list is read as a history of what was just hidden.
static void NFBHideThread(NSString* threadID, NSString* who, NSString* preview) {
    if (!threadID.length || NFBThreadIDIsHidden(threadID)) {
        return;
    }
    NSMutableArray* kept = [NFBHiddenThreads() mutableCopy];
    [kept insertObject:@{
        kNFBThreadIDKey : threadID,
        kNFBThreadWhoKey : who ?: @"",
        kNFBThreadPreviewKey : preview ?: @""
    }
               atIndex:0];
    NFBWriteHiddenThreads(kept);
}

// MARK: - Reading a Tweet
//
// Values are asked of the model rather than assumed: a timeline carries several
// kinds of entry, and only some of them answer these.

// The return type is checked before the call. A timeline model answers some of
// these with an integer, and reading an integer as an object hands a number to
// the runtime as if it were an address — which is exactly how this crashed.
static id NFBAsk(id target, SEL selector) {
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
static long long NFBAskInteger(id target, SEL selector) {
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

static NSString* NFBStringValue(id value) {
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
static NSString* NFBIdentifierValue(id model, SEL selector) {
    NSString* text = NFBStringValue(NFBAsk(model, selector));
    if (text.length) {
        return text;
    }
    long long number = NFBAskInteger(model, selector);
    return number ? [@(number) stringValue] : nil;
}

static NSString* NFBThreadIDForModel(id model) {
    NSString* conversation = NFBIdentifierValue(model, @selector(conversationID));
    if (conversation.length) {
        return conversation;
    }
    NSString* inReplyTo = NFBIdentifierValue(model, @selector(inReplyToStatusID));
    if (inReplyTo.length) {
        return inReplyTo;
    }
    return NFBIdentifierValue(model, @selector(statusID));
}

// Measured on the device: the timeline's view model is a
// T1URTTimelineStatusItemViewModel, and it does not answer replyCount. Its own
// name for the same number is aggregatedDisplayReplyCount. Both are asked, in
// that order, so a model that carries either is understood.
static NSInteger NFBReplyCountForModel(id model) {
    if ([model respondsToSelector:@selector(aggregatedDisplayReplyCount)]) {
        return (NSInteger)NFBAskInteger(model,
                                        @selector(aggregatedDisplayReplyCount));
    }
    return (NSInteger)NFBAskInteger(model, @selector(replyCount));
}

// The row holds a view model, but the numbers this file needs — the reply
// count, the conversation identifier — live on the status object underneath it
// (TFNTwitterStatus, verified in the binary: it alone carries replyCount,
// conversationID, inReplyToStatusID and statusID). Asking the view model for
// them answered nothing, which is why no button was ever built.
//
// The link between the two is not guessed: the object that answers replyCount
// is looked for, first among the usual names, then among the model's own
// instance variables. Only something that actually answers is accepted.
// What makes an object usable here: it answers at least one of the four values
// this file needs. Requiring replyCount alone rejected the very model the crash
// report proved was reachable — it answers inReplyToStatusID, not the count.
static BOOL NFBRespondsToStatusValue(id candidate) {
    return [candidate respondsToSelector:@selector(replyCount)] ||
           [candidate respondsToSelector:@selector(aggregatedDisplayReplyCount)] ||
           [candidate respondsToSelector:@selector(conversationID)] ||
           [candidate respondsToSelector:@selector(inReplyToStatusID)] ||
           [candidate respondsToSelector:@selector(statusID)];
}

static id NFBStatusFromModel(id model) {
    if (!model) {
        return nil;
    }
    if (NFBRespondsToStatusValue(model)) {
        return model;
    }
    for (NSString* key in @[ @"status", @"tweet", @"canonicalStatus", @"statusModel" ]) {
        @try {
            id candidate = [model valueForKey:key];
            if (NFBRespondsToStatusValue(candidate)) {
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
        if (NFBRespondsToStatusValue(value)) {
            found = value;
        }
    }
    free(ivars);
    return found;
}

// A Tweet is part of a conversation when someone has answered it, or when it is
// itself an answer. Anything else gets no button.
static BOOL NFBModelIsConversation(id model) {
    if (!model) {
        return NO;
    }
    if (NFBIdentifierValue(model, @selector(inReplyToStatusID)).length > 0) {
        return YES;
    }
    // The count decides only when it can actually be read. Where the model does
    // not carry it, the button is shown rather than silently withheld: hiding a
    // conversation is harmless on a Tweet that has none, whereas a button that
    // never appears is the failure this file has been chasing.
    if ([model respondsToSelector:@selector(replyCount)] ||
        [model respondsToSelector:@selector(aggregatedDisplayReplyCount)]) {
        return NFBReplyCountForModel(model) > 0;
    }
    return YES;
}

static NSString* NFBAuthorHandleForModel(id model) {
    id author = NFBAsk(model, @selector(author)) ?: NFBAsk(model, @selector(user));
    NSString* handle = NFBStringValue(NFBAsk(author, @selector(username)));
    return handle.length ? [@"@" stringByAppendingString:handle] : @"";
}

static NSString* NFBPreviewForModel(id model) {
    NSString* text = NFBStringValue(NFBAsk(model, @selector(text)));
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
BOOL nfbThreadIsHidden(id viewModel) {
    if (!NFBHiddenThreads().count) {
        return NO;
    }
    return NFBThreadIDIsHidden(NFBThreadIDForModel(NFBStatusFromModel(viewModel)));
}

// MARK: - The glyph
//
// Drawn rather than taken from the system set: the icons in this row have a
// thin, even stroke of their own, and a symbol from elsewhere reads as pasted
// on. A speech bubble with a tail, crossed by a stroke that leaves a gap around
// itself so the two shapes stay legible at this size.

static UIImage* NFBHideThreadGlyph(UIColor* colour) {
    CGFloat side = kNFBHideGlyphSide;
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
          // colour, so it reads as passing over the bubble rather than through
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

// Making it disappear at once.
//
// The timeline memoises its filtering verdict per item, and that memo is keyed
// by a signature the muted-word editor already bumps through
// nfbRefreshMutedWords(). Timeline.x now folds the number of hidden
// conversations into the same signature, so hiding one invalidates the memo the
// way adding a muted word does. The list that carries the Tweet is then asked
// to reload, which drops the row with the right heights rather than leaving a
// hole behind.
extern void nfbRefreshMutedWords(void);

static UIScrollView* NFBListForButton(UIView* view) {
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
extern void nfbReapplyTimelineFilter(void);

static void NFBReloadList(__unused UIScrollView* list) {
    nfbRefreshMutedWords();
    nfbReapplyTimelineFilter();
}

// MARK: - The confirmation strip
//
// Our own, not the app's. TFNInformationToast draws its label white and gives
// no way to change it — on this build the strip is rendered by
// XDSToastContentView, whose label is out of reach — so a light strip with dark
// text is impossible through it. This one is ours end to end: light background,
// text in the system label colour, and an undo that puts the conversation back.

static const NSInteger kNFBToastTag = 90312;

static void NFBDismissToast(UIView* toast) {
    [UIView animateWithDuration:0.2
        animations:^{
          toast.alpha = 0;
        }
        completion:^(BOOL finished) {
          [toast removeFromSuperview];
        }];
}

static void NFBShowHiddenToast(NSString* threadID) {
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
    [[window viewWithTag:kNFBToastTag] removeFromSuperview];

    UIView* toast = [[UIView alloc] init];
    toast.tag = kNFBToastTag;
    toast.backgroundColor = [UIColor systemBackgroundColor];
    toast.layer.cornerRadius = 14.0;
    toast.layer.cornerCurve = kCACornerCurveContinuous;
    // A light strip needs an edge and a shadow to sit on the timeline; the dark
    // one did not.
    toast.layer.borderWidth = 1.0;
    toast.layer.borderColor = [UIColor separatorColor].CGColor;
    toast.layer.shadowColor = [UIColor blackColor].CGColor;
    toast.layer.shadowOpacity = 0.12;
    toast.layer.shadowRadius = 12.0;
    toast.layer.shadowOffset = CGSizeMake(0.0, 4.0);
    toast.translatesAutoresizingMaskIntoConstraints = NO;
    [window addSubview:toast];

    UILabel* label = [[UILabel alloc] init];
    label.text = [[BHTBundle sharedBundle] localizedStringForKey:@"THREADS_HIDDEN_TOAST"];
    label.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    label.textColor = [UIColor labelColor];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [toast addSubview:label];

    UIButton* undo = [UIButton buttonWithType:UIButtonTypeSystem];
    [undo setTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"THREADS_UNDO"]
          forState:UIControlStateNormal];
    extern UIColor* CurrentAccentColor(void);
    [undo setTitleColor:CurrentAccentColor() ?: [UIColor labelColor]
               forState:UIControlStateNormal];
    undo.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    undo.translatesAutoresizingMaskIntoConstraints = NO;
    [undo addAction:[UIAction actionWithHandler:^(__unused UIAction* action) {
              NFBUnhideThread(threadID);
              nfbRefreshMutedWords();
              nfbReapplyTimelineFilter();
              NFBDismissToast(toast);
            }]
        forControlEvents:UIControlEventTouchUpInside];
    [toast addSubview:undo];

    [NSLayoutConstraint activateConstraints:@[
        [toast.leadingAnchor constraintEqualToAnchor:window.leadingAnchor constant:16],
        [toast.trailingAnchor constraintEqualToAnchor:window.trailingAnchor constant:-16],
        [toast.bottomAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.bottomAnchor
                                           constant:-72],
        [toast.heightAnchor constraintEqualToConstant:48],
        [label.leadingAnchor constraintEqualToAnchor:toast.leadingAnchor constant:16],
        [label.centerYAnchor constraintEqualToAnchor:toast.centerYAnchor],
        [undo.trailingAnchor constraintEqualToAnchor:toast.trailingAnchor constant:-16],
        [undo.centerYAnchor constraintEqualToAnchor:toast.centerYAnchor],
    ]];

    toast.alpha = 0;
    [UIView animateWithDuration:0.2
                     animations:^{
                       toast.alpha = 1;
                     }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                     if (toast.superview) {
                         NFBDismissToast(toast);
                     }
                   });
}

// MARK: - The entry in the Tweet's own menu
//
// Measured rather than assumed:
//   · the menu under the caret is a UIKit context menu (FLEX: _UIContextMenuView
//     → _UIContextMenuListView), so it is built from a UIMenu;
//   · TFNButton and TFNMenuCompatibleControl are the two classes in the binary
//     that vend one for a Tweet;
//   · the row's model is a T1URTTimelineStatusItemViewModel and it answers
//     conversationID — the probe printed it.
//
// The action provider is not read out of the configuration, which would mean
// touching a property Apple does not expose: it is wrapped where it is passed,
// in the public factory below. Twitter builds its menu, ours is appended after.

// From the caret button up to the Tweet it belongs to. The chain is walked at
// the moment it is needed — when the menu is built, and again when the entry is
// tapped — so nothing is cached and nothing can go stale.
static id NFBStatusForButton(UIView* button) {
    UIView* node = button;
    NSInteger depth = 0;
    while (node && depth < 14) {
        id model = nil;
        @try {
            model = [node valueForKey:@"viewModel"];
        } @catch (__unused NSException* exception) {
            model = nil;
        }
        id status = NFBStatusFromModel(model);
        if (status && NFBModelIsConversation(status)) {
            return status;
        }
        node = node.superview;
        depth++;
    }
    return nil;
}

static NSString* NFBThreadIDForButton(UIView* button) {
    return NFBThreadIDForModel(NFBStatusForButton(button));
}

static NSString* NFBAuthorForButton(UIView* button) {
    return NFBAuthorHandleForModel(NFBStatusForButton(button));
}

static NSString* NFBPreviewForButton(UIView* button) {
    return NFBPreviewForModel(NFBStatusForButton(button));
}

static BOOL NFBMenuBelongsToTweet(UIMenu* menu) {
    NSString* mark = [[BHTBundle sharedBundle]
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
    if (![menu isKindOfClass:[UIMenu class]]) {
        %orig;
        return;
    }
    UIView* button = (UIView*)self;
    // Either the menu names itself — an entry the app puts there — or the button
    // sits under a Tweet. The second covers a menu still being assembled, whose
    // entries are not readable yet.
    if (!NFBMenuBelongsToTweet(menu) && !NFBThreadIDForButton(button).length) {
        %orig;
        return;
    }
    __weak UIView* weakButton = button;
    // The list is noted here, while the button is still in the cell: by the time
    // the entry is tapped, the menu has taken the button out of the hierarchy
    // and the walk upwards finds nothing to reload.
    __weak UIScrollView* weakList = NFBListForButton(button);
    NSString* title =
        [[BHTBundle sharedBundle] localizedStringForKey:@"THREADS_HIDE_ACTION"];
    UIColor* colour = [UIColor labelColor];
    if ([colour respondsToSelector:@selector(resolvedColorWithTraitCollection:)]) {
        colour = [colour resolvedColorWithTraitCollection:button.traitCollection] ?: colour;
    }
    UIAction* hide = [UIAction
        actionWithTitle:title
                  image:NFBHideThreadGlyph(colour)
             identifier:nil
                handler:^(__unused UIAction* action) {
                  UIView* source = weakButton;
                  NSString* threadID = NFBThreadIDForButton(source);
                  if (!threadID.length) {
                      return;
                  }
                  NFBHideThread(threadID, NFBAuthorForButton(source),
                                NFBPreviewForButton(source));
                  NFBReloadList(weakList ?: (UIScrollView*)NFBListForButton(source));
                  NFBShowHiddenToast(threadID);
                }];
    %orig([menu menuByReplacingChildren:[menu.children arrayByAddingObject:hide]]);
}

%end
