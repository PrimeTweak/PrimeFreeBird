// Hide conversations: a Tweet menu entry that hides a conversation from every list. In the
// notifications tab the entry hides the notification instead.

#import "Support/HookHelpers.h"

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

// An identifier as text, whether the model answers with a string or a number.
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
    if (flat.length <= 90) {
        return flat;
    }
    // Cut before the character that holds unit 90, never inside an emoji.
    NSUInteger cut = [flat rangeOfComposedCharacterSequenceAtIndex:90].location;
    return [[flat substringToIndex:cut] stringByAppendingString:@"…"];
}

// Read by the timeline filter, which decides whether an entry is dropped. With the
// option off nothing counts as hidden: the list stays saved and its conversations show.
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

// Drawn rather than taken from the system set, since the icons of the Tweet's pop-up menu
// have a thin even stroke of their own. A speech bubble crossed by a stroke that
// leaves a gap around itself so both shapes stay legible at this size.

static UIImage* PFBHideThreadGlyph(UIColor* color) {
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
          [color setStroke];
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
          [color setStroke];
          [slash stroke];
        }];
    return [drawn imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

// Refreshing the muted words makes the timeline filter see the changed list. Reloading
// the table is not enough: the filter runs when sections are handed to the data view
// controller, so Timeline.x replays that hand-over.
static void PFBReloadList(void) {
    pfbRefreshMutedWords();
    pfbReapplyTimelineFilter();
}

// MARK: - The confirmation

// Its Undo brings the conversation back.
static void PFBShowHiddenToast(NSString* threadID) {
    PFBShowToast(nil, [[PFBBundle sharedBundle] localizedStringForKey:@"THREADS_HIDDEN_TOAST"], ^{
        PFBUnhideThread(threadID);
        PFBReloadList();
    });
}

// MARK: - The entry in the Tweet's own menu

// The Tweet's menu is caught as it is set on its caret button (-[UIButton setMenu:]),
// and the entry is appended to it.

// From the caret button up to the Tweet it belongs to, a conversation's when asked. The
// chain is walked at the moment it is needed — when the menu is built, and again when the
// entry is tapped — so nothing is cached and nothing can go stale.
static id PFBStatusUpFrom(UIView* button, BOOL conversationOnly) {
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
        if (status && (!conversationOnly || PFBModelIsConversation(status))) {
            return status;
        }
        node = node.superview;
        depth++;
    }
    return nil;
}

static id PFBStatusForButton(UIView* button) {
    return PFBStatusUpFrom(button, YES);
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

static BOOL PFBMenuHasEntry(UIMenu* menu, NSString* title) {
    if (!title.length) {
        return NO;
    }
    for (UIMenuElement* element in menu.children) {
        if ([element.title isEqualToString:title]) {
            return YES;
        }
    }
    return NO;
}

static BOOL PFBMenuBelongsToTweet(UIMenu* menu) {
    return PFBMenuHasEntry(menu, [[PFBBundle sharedBundle] localizedTwitterStringForKey:@"NOT_INTERESTED_IN_THIS_LABEL"]);
}

// In the notifications tab, a Tweet's menu offers to hide the notification instead of the
// conversation. Its icon is Twitter's crossed eye, as on the hidden notifications screen.
static UIMenu* PFBMenuWithNotificationHide(UIMenu* menu, UIView* button) {
    PFBCompatReach(PFBCompatPath_notification_tweet_menu);
    if (![PFBSettings boolForKey:@"hide_notifications"]) {
        PFBCOMPAT_OBSERVE(PFBCompat_hide_notifications, @"Tweet menu in the notifications tab found");
        return menu;
    }
    NSString* title = [[PFBBundle sharedBundle] localizedStringForKey:@"NOTIFS_HIDE_MENU_ACTION"];
    if (PFBMenuHasEntry(menu, title)) {
        return menu;
    }
    UIColor* color = [[UIColor labelColor] resolvedColorWithTraitCollection:button.traitCollection] ?: [UIColor labelColor];
    UIImage* glyph = [UIImage respondsToSelector:@selector(tfn_vectorImageNamed:fitsSize:fillColor:)]
                         ? [UIImage tfn_vectorImageNamed:@"eye_off"
                                                fitsSize:CGSizeMake(kPFBHideGlyphSide, kPFBHideGlyphSide)
                                               fillColor:color]
                         : nil;
    __weak UIView* weakButton = button;
    UIAction* hide = [UIAction actionWithTitle:title
                                         image:glyph
                                    identifier:nil
                                       handler:^(__unused UIAction* action) {
                                         UIView* source = weakButton;
                                         PFBNotifHideTweet(PFBStatusUpFrom(source, NO), source, nil);
                                       }];
    PFBCOMPAT_ACTION(PFBCompat_hide_notifications, @"hide entry in a Tweet menu of the notifications tab");
    return [menu menuByReplacingChildren:[menu.children arrayByAddingObject:hide]];
}

%hook UIButton

- (void)setMenu:(UIMenu*)menu {
    // A Tweet's menu reaching here is the path, whatever the toggle and the Tweet.
    if ([menu isKindOfClass:[UIMenu class]] && PFBCompatNeedsObservation(PFBCompat_hide_threads) &&
        (PFBMenuBelongsToTweet(menu) || PFBThreadIDForButton((UIView*)self).length)) {
        PFBCompatReach(PFBCompatPath_threads_popup_menu);
        PFBCOMPAT_OBSERVE(PFBCompat_hide_threads, @"Tweet menu found");
    }
    UIView* button = (UIView*)self;
    if ([menu isKindOfClass:[UIMenu class]] && PFBNotifViewOnNotificationsScreen(button) &&
        (PFBMenuBelongsToTweet(menu) || PFBStatusUpFrom(button, NO))) {
        %orig(PFBMenuWithNotificationHide(menu, button));
        return;
    }
    if (![menu isKindOfClass:[UIMenu class]] ||
        ![PFBSettings boolForKey:@"hide_threads"]) {
        %orig;
        return;
    }
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
    // A menu made from the Tweet's menu sheet already carries the entry.
    if (PFBMenuHasEntry(menu, title)) {
        %orig;
        return;
    }
    PFBCompatReach(PFBCompatPath_threads_popup_menu);
    UIColor* color = [UIColor labelColor];
    color = [color resolvedColorWithTraitCollection:button.traitCollection] ?: color;
    UIAction* hide = [UIAction
        actionWithTitle:title
                  image:PFBHideThreadGlyph(color)
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
    %orig([menu menuByReplacingChildren:[menu.children arrayByAddingObject:hide]]);
}

%end

// MARK: - The entry in the Tweet's menu sheet

// A Tweet's menu is built as a sheet of action items and shown as the "About this post"
// tray, where an entry Twitter does not know lands under "More". The Tweet, and the
// notifications screen it is built from if any, are held for the one sheet made then.
static id gPFBSheetStatus;
static __weak UIViewController* gPFBSheetScreen;

// As in the pop-up menu, the entry is on every Tweet's menu and acts on a Tweet in a
// conversation. Its icon is Twitter's own crossed speech bubble.
static TFNActionItem* PFBHideActionItem(id status) {
    Class itemClass = %c(TFNActionItem);
    if (![itemClass respondsToSelector:@selector(actionItemWithTitle:imageName:action:)]) {
        return nil;
    }
    return [itemClass
        actionItemWithTitle:[[PFBBundle sharedBundle] localizedStringForKey:@"THREADS_HIDE_ACTION"]
                  imageName:@"chat_bubble_strikethrough_stroke"
                     action:^{
                       NSString* threadID = PFBModelIsConversation(status) ? PFBThreadIDForModel(status) : nil;
                       if (!threadID.length) {
                           return;
                       }
                       PFBHideThread(threadID, PFBAuthorHandleForModel(status), PFBPreviewForModel(status));
                       PFBReloadList();
                       PFBShowHiddenToast(threadID);
                     }];
}

// The sheet's entry in the notifications tab: hide the notification.
static TFNActionItem* PFBHideNotificationItem(id status, UIViewController* screen) {
    Class itemClass = %c(TFNActionItem);
    if (![itemClass respondsToSelector:@selector(actionItemWithTitle:imageName:action:)]) {
        return nil;
    }
    __weak UIViewController* weakScreen = screen;
    return [itemClass actionItemWithTitle:[[PFBBundle sharedBundle] localizedStringForKey:@"NOTIFS_HIDE_MENU_ACTION"]
                                imageName:@"eye_off"
                                   action:^{
                                     PFBNotifHideTweet(status, nil, weakScreen);
                                   }];
}

%hook UIViewController

- (id)t1_actionsViewControllerForStatus:(id)status
                                account:(id)account
                                 source:(id)source
                                options:(unsigned long long)options
                              doneBlock:(id)doneBlock {
    id heldStatus = gPFBSheetStatus;
    UIViewController* heldScreen = gPFBSheetScreen;
    gPFBSheetStatus = status;
    gPFBSheetScreen = PFBNotifControllerOnNotificationsScreen((UIViewController*)self) ? (UIViewController*)self : nil;
    id sheet = %orig;
    gPFBSheetStatus = heldStatus;
    gPFBSheetScreen = heldScreen;
    return sheet;
}

%end

%hook TFNMenuSheetViewController

- (id)initWithActionItems:(NSArray*)items {
    id status = PFBStatusFromModel(gPFBSheetStatus);
    UIViewController* screen = gPFBSheetScreen;
    gPFBSheetStatus = nil;
    gPFBSheetScreen = nil;
    if (!status || ![items isKindOfClass:[NSArray class]]) {
        return %orig;
    }
    if (screen) {
        PFBCompatReach(PFBCompatPath_notification_tweet_menu);
        if (![PFBSettings boolForKey:@"hide_notifications"]) {
            PFBCOMPAT_OBSERVE(PFBCompat_hide_notifications, @"Tweet menu in the notifications tab found");
            return %orig;
        }
        TFNActionItem* hide = PFBHideNotificationItem(status, screen);
        if (!hide) {
            return %orig;
        }
        PFBCOMPAT_ACTION(PFBCompat_hide_notifications, @"hide entry in a Tweet menu of the notifications tab");
        return %orig([items arrayByAddingObject:hide]);
    }
    PFBCompatReach(PFBCompatPath_threads_post_menu);
    PFBCOMPAT_OBSERVE(PFBCompat_hide_threads, @"Tweet menu found");
    if (![PFBSettings boolForKey:@"hide_threads"]) {
        return %orig;
    }
    TFNActionItem* hide = PFBHideActionItem(status);
    if (!hide) {
        return %orig;
    }
    PFBCOMPAT_ACTION(PFBCompat_hide_threads, @"hide entry in a Tweet menu");
    return %orig([items arrayByAddingObject:hide]);
}

%end
