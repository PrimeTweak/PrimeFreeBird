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

static const NSInteger kNFBHideButtonTag = 90311;
static const CGFloat kNFBHideGlyphSide = 18.5;

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
    if (strcmp(returnType, "q") == 0 || strcmp(returnType, "l") == 0) {
        return ((long long (*)(id, SEL))objc_msgSend)(target, selector);
    }
    if (strcmp(returnType, "i") == 0) {
        return ((int (*)(id, SEL))objc_msgSend)(target, selector);
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

static NSInteger NFBReplyCountForModel(id model) {
    return (NSInteger)NFBAskInteger(model, @selector(replyCount));
}

// A Tweet is part of a conversation when someone has answered it, or when it is
// itself an answer. Anything else gets no button.
static BOOL NFBModelIsConversation(id model) {
    if (!model) {
        return NO;
    }
    if (NFBReplyCountForModel(model) > 0) {
        return YES;
    }
    return NFBIdentifierValue(model, @selector(inReplyToStatusID)).length > 0;
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
    return NFBThreadIDIsHidden(NFBThreadIDForModel(viewModel));
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

// MARK: - The undo strip
//
// A strip above the tab bar rather than an alert: hiding is a small, reversible
// act, and it should not stop the reader to be confirmed. It carries its own
// undo and clears itself after a few seconds.

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
    toast.backgroundColor = [UIColor colorWithWhite:0.07 alpha:0.94];
    toast.layer.cornerRadius = 12.0;
    toast.clipsToBounds = YES;
    toast.translatesAutoresizingMaskIntoConstraints = NO;
    [window addSubview:toast];

    UILabel* label = [[UILabel alloc] init];
    label.text = [[BHTBundle sharedBundle] localizedStringForKey:@"THREADS_HIDDEN_TOAST"];
    label.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    label.textColor = [UIColor whiteColor];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [toast addSubview:label];

    UIButton* undo = [UIButton buttonWithType:UIButtonTypeSystem];
    [undo setTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"THREADS_UNDO"]
          forState:UIControlStateNormal];
    [undo setTitleColor:CurrentAccentColor() ?: [UIColor whiteColor]
               forState:UIControlStateNormal];
    undo.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    undo.translatesAutoresizingMaskIntoConstraints = NO;
    [undo addAction:[UIAction actionWithHandler:^(__unused UIAction* action) {
              NFBUnhideThread(threadID);
              NFBDismissToast(toast);
            }]
        forControlEvents:UIControlEventTouchUpInside];
    [toast addSubview:undo];

    [NSLayoutConstraint activateConstraints:@[
        [toast.leadingAnchor constraintEqualToAnchor:window.leadingAnchor constant:16],
        [toast.trailingAnchor constraintEqualToAnchor:window.trailingAnchor constant:-16],
        [toast.bottomAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.bottomAnchor
                                           constant:-64],
        [toast.heightAnchor constraintEqualToConstant:46],
        [label.leadingAnchor constraintEqualToAnchor:toast.leadingAnchor constant:14],
        [label.centerYAnchor constraintEqualToAnchor:toast.centerYAnchor],
        [undo.trailingAnchor constraintEqualToAnchor:toast.trailingAnchor constant:-14],
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

// MARK: - The button
//
// The row lays its own buttons out; ours is placed after the last of them, on
// the trailing edge, and only when there is room left. Where the reader has
// hidden one of Twitter's buttons, that room is exactly what was freed.

static void NFBLayoutHideButton(UIView* row) {
    UIButton* button = (UIButton*)[row viewWithTag:kNFBHideButtonTag];
    if (!button) {
        return;
    }
    CGFloat right = 0;
    for (UIView* view in row.subviews) {
        if (view == button || view.hidden) {
            continue;
        }
        right = MAX(right, CGRectGetMaxX(view.frame));
    }
    CGFloat side = 30.0;
    CGFloat width = CGRectGetWidth(row.bounds);
    CGFloat x = width - side;
    // Overlapping a native button would be worse than not appearing at all.
    button.hidden = (right > x - 6.0);
    button.frame = CGRectMake(x, (CGRectGetHeight(row.bounds) - side) / 2.0, side, side);
}

// Kept on the row by association rather than by a declared property: this
// class is already declared in the headers, so nothing can be added to its
// interface.
static const void* kNFBRowThreadKey = &kNFBRowThreadKey;
static const void* kNFBRowWhoKey = &kNFBRowWhoKey;
static const void* kNFBRowPreviewKey = &kNFBRowPreviewKey;

%hook TTAStatusInlineActionsView

- (void)layoutSubviews {
    %orig;

    UIView* row = (UIView*)self;
    UIButton* existing = (UIButton*)[row viewWithTag:kNFBHideButtonTag];

    // The model is read from the view rather than passed in: the row is
    // configured before it is laid out, and a recycled row keeps the property
    // of the Tweet it now shows.
    id model = nil;
    @try {
        model = [row valueForKey:@"viewModel"];
    } @catch (__unused NSException* exception) {
        model = nil;
    }

    if (!NFBModelIsConversation(model)) {
        existing.hidden = YES;
        return;
    }

    objc_setAssociatedObject(row, kNFBRowThreadKey, NFBThreadIDForModel(model),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(row, kNFBRowWhoKey, NFBAuthorHandleForModel(model),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(row, kNFBRowPreviewKey, NFBPreviewForModel(model),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    if (!existing) {
        existing = [UIButton buttonWithType:UIButtonTypeCustom];
        existing.tag = kNFBHideButtonTag;
        UIColor* grey = [[UIColor labelColor] colorWithAlphaComponent:0.6];
        if ([grey respondsToSelector:@selector(resolvedColorWithTraitCollection:)]) {
            grey = [grey resolvedColorWithTraitCollection:row.traitCollection] ?: grey;
        }
        [existing setImage:NFBHideThreadGlyph(grey) forState:UIControlStateNormal];
        [existing addTarget:self
                      action:@selector(nfbHideThreadTapped)
            forControlEvents:UIControlEventTouchUpInside];
        [row addSubview:existing];
    }
    existing.hidden = NO;
    NFBLayoutHideButton(row);
}

%new
- (void)nfbHideThreadTapped {
    UIView* row = (UIView*)self;
    NSString* threadID = objc_getAssociatedObject(row, kNFBRowThreadKey);
    if (!threadID.length) {
        return;
    }
    NFBHideThread(threadID, objc_getAssociatedObject(row, kNFBRowWhoKey),
                  objc_getAssociatedObject(row, kNFBRowPreviewKey));
    NFBShowHiddenToast(threadID);
}

%end

