// Download entries: DM videos and voice messages, custom voice uploads, tweet to
// image, and the download entry in the media long-press menu.

#import "Support/HookHelpers.h"
#import "Debug/PFBDebugger.h"
#import "Debug/PFBProbe.h"
#import <os/lock.h>
#import <stdatomic.h>

// MARK: - DM video download

// DM media messages (ChatConversation.MessageAttachmentView) host a shared media
// view exposing its models through -inlineMediaInfos; the entities are collected
// from whichever descendant carries them.
static NSArray* DMVideoEntities(UIView* attachmentView) {
    NSMutableArray* entities = [NSMutableArray new];

    PFBEnumerateSubviewsRecursively(attachmentView, ^(UIView* view) {
        if (![view respondsToSelector:@selector(inlineMediaInfos)]) {
            return;
        }

        for (TFSTwitterMediaInfo* info in
             [(_TtC21TweetMediaAttachments14MultiMediaView*)view inlineMediaInfos]) {
            TFSTwitterEntityMedia* media = info.mediaEntity;
            if (media.videoInfo.variants.count > 0) {
                [entities addObject:media];
            }
        }
    });

    return [entities copy];
}

// MARK: - Voice messages

// A voice note is decrypted to disk before playing, so its URL passes through the
// asset opened to play it. The last one seen is taken as the one under the finger.

static NSURL* gPFBLastVoiceURL = nil;

// MARK: - Probe: voice notes

// Probe: the files opened through AVURLAsset by folder shape, the one the voice capture
// keeps, the audio view playing it, and what a long press then offers.
static const NSUInteger kPFBProbeVoiceShapeLimit = 12;
static atomic_bool gPFBProbeVoiceDone;
static atomic_bool gPFBProbeAudioSeen;
static os_unfair_lock gPFBProbeVoiceLock = OS_UNFAIR_LOCK_INIT;
static NSUInteger gPFBProbeVoiceShapes;
static NSUInteger gPFBProbeVoiceFiles;
static NSURL* gPFBProbeVoiceKeptURL;
static CFTimeInterval gPFBProbeVoiceKeptAt;
// Main thread only, from here on.
static BOOL gPFBProbeOwnAsset;
static BOOL gPFBProbeAudioIvarsNoted;
static NSUInteger gPFBProbeVoicePresses;
static NSHashTable<UIView*>* gPFBProbeAudioViews;
static NSURL* gPFBProbeVoiceBoundURL;
static const void* kPFBProbeVoiceFileKey = &kPFBProbeVoiceFileKey;

// Probe: a one-byte ivar of a view, or -1 when it cannot be read.
static NSInteger pfbProbeByte(UIView* view, const char* name) {
    Ivar ivar = view ? class_getInstanceVariable(object_getClass(view), name) : NULL;
    ptrdiff_t offset = ivar ? ivar_getOffset(ivar) : 0;
    if (offset <= 0 || (size_t)offset >= class_getInstanceSize(object_getClass(view))) {
        return -1;
    }
    return *((uint8_t*)(__bridge void*)view + offset);
}

// Probe: a path component masked as an identifier: digits, length or an @.
static BOOL pfbProbeLooksLikeID(NSString* component) {
    NSUInteger digits = 0;
    for (NSUInteger i = 0; i < component.length; i++) {
        unichar character = [component characterAtIndex:i];
        digits += character >= '0' && character <= '9' ? 1 : 0;
    }
    return digits >= 3 || component.length > 24 || [component containsString:@"@"];
}

// Probe: a file's folders from the app's home, identifiers masked and its name left out.
static NSString* pfbProbeVoiceShape(NSURL* url) {
    NSString* path = url.path ?: @"";
    NSString* home = NSHomeDirectory() ?: @"";
    path = [path hasPrefix:@"/private/"] ? [path substringFromIndex:8] : path;
    home = [home hasPrefix:@"/private/"] ? [home substringFromIndex:8] : home;
    NSMutableArray<NSString*>* parts = [NSMutableArray array];
    if (home.length > 1 && [path hasPrefix:home]) {
        [parts addObject:@"~"];
        path = [path substringFromIndex:home.length];
    }
    NSArray<NSString*>* components = path.pathComponents;
    for (NSUInteger i = 0; i < components.count; i++) {
        NSString* component = components[i];
        if ([component isEqualToString:@"/"]) {
            continue;
        }
        if (i + 1 < components.count) {
            [parts addObject:pfbProbeLooksLikeID(component) ? @"<id>" : component];
            continue;
        }
        NSString* extension = component.pathExtension;
        [parts addObject:extension.length && extension.length <= 5 ? [@"<file>." stringByAppendingString:extension]
                                                                   : @"<file>"];
    }
    if (parts.count > 9) {
        [parts replaceObjectsInRange:NSMakeRange(0, parts.count - 9) withObjectsFromArray:@[ @"..." ]];
    }
    NSString* shape = [parts componentsJoinedByString:@"/"];
    return [parts.firstObject isEqualToString:@"~"] ? shape : [@"/" stringByAppendingString:shape];
}

// Probe: closed once the kept and ivar lines and three long presses are noted.
static void pfbProbeVoiceCheckDone(void) {
    if (gPFBProbeVoicePresses >= 3 && !PFBProbeWants(@"10a#F030 kept") && !PFBProbeWants(@"10a#F030 ivars")) {
        atomic_store(&gPFBProbeVoiceDone, true);
    }
}

// Probe: the audio views playing once a file has had time to start, read at 0.3 s and again
// at 1 s when none plays; a kept file is bound to the view when exactly one plays.
static void pfbProbeVoiceRead(NSURL* url, BOOL kept, NSString* shape, NSString* thread, double delay) {
    if (atomic_load(&gPFBProbeVoiceDone) || !PFBDebugIsRecording()) {
        return;
    }
    NSUInteger shown = 0;
    NSUInteger readable = 0;
    NSUInteger playing = 0;
    UIView* player = nil;
    for (UIView* view in gPFBProbeAudioViews.allObjects) {
        if (!view.window) {
            continue;
        }
        shown++;
        NSInteger state = pfbProbeByte(view, "isPlaying");
        readable += state >= 0 ? 1 : 0;
        if (state > 0) {
            playing++;
            player = view;
        }
    }
    if (playing == 0 && shown > 0 && delay < 1.0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.7 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
          pfbProbeVoiceRead(url, kept, shape, thread, 1.0);
        });
        return;
    }
    if (kept && playing == 1) {
        objc_setAssociatedObject(player, kPFBProbeVoiceFileKey, url, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        gPFBProbeVoiceBoundURL = url;
    }
    NSString* views = [NSString stringWithFormat:@"%lu audio view(s) play (%lu on screen, %lu readable, read %.1f s after "
                                                 @"it opened)",
                                                 (unsigned long)playing, (unsigned long)shown, (unsigned long)readable, delay];
    NSString* key = shape ? [@"10a#F030 file " stringByAppendingString:shape] : nil;
    if (key && PFBProbeWants(key)) {
        PFBProbeNote(key, @"10a#F030 voice: file opened from %@ on %@, kept as the voice note: %@; then %@", shape, thread,
                     kept ? @"yes" : @"no", views);
        os_unfair_lock_lock(&gPFBProbeVoiceLock);
        gPFBProbeVoiceShapes++;
        os_unfair_lock_unlock(&gPFBProbeVoiceLock);
    }
    if (kept && PFBProbeWants(@"10a#F030 kept")) {
        PFBProbeNote(@"10a#F030 kept", @"10a#F030 voice: kept file while %@", views);
        pfbProbeVoiceCheckDone();
    }
}

// Probe: a file opened through AVURLAsset, on any thread: every kept file, and a new folder
// shape once an audio view has shown (at most 12, over 300 files a launch), are looked at
// again on the main thread.
static void pfbProbeVoiceFileOpened(NSURL* url) {
    if (atomic_load_explicit(&gPFBProbeVoiceDone, memory_order_relaxed) || !PFBDebugIsRecording() || !url.isFileURL ||
        (NSThread.isMainThread && gPFBProbeOwnAsset)) {
        return;
    }
    BOOL kept = [url.path containsString:@"/decrypted-media-v2/"];
    os_unfair_lock_lock(&gPFBProbeVoiceLock);
    BOOL shapeOpen = atomic_load(&gPFBProbeAudioSeen) && gPFBProbeVoiceShapes < kPFBProbeVoiceShapeLimit &&
                     gPFBProbeVoiceFiles++ < 300;
    if (kept) {
        gPFBProbeVoiceKeptURL = url;
        gPFBProbeVoiceKeptAt = CACurrentMediaTime();
    }
    os_unfair_lock_unlock(&gPFBProbeVoiceLock);
    NSString* shape = shapeOpen ? pfbProbeVoiceShape(url) : nil;
    if (shape && !PFBProbeWants([@"10a#F030 file " stringByAppendingString:shape])) {
        shape = nil;
    }
    if (!kept && !shape) {
        return;
    }
    const char* label = dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL);
    NSString* thread = NSThread.isMainThread
                           ? @"the main thread"
                           : [NSString stringWithFormat:@"queue %@",
                                                        [NSString stringWithUTF8String:label && label[0] ? label : "unnamed"] ?: @"?"];
    if (kept && PFBProbeWants(@"10D#M2 voice asset")) {
        PFBProbeNote(@"10D#M2 voice asset", @"10D#M2 voice asset: main thread %@, %@", NSThread.isMainThread ? @"yes" : @"no",
                     thread);
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      pfbProbeVoiceRead(url, kept, shape, thread, 0.3);
    });
}

%hook AVURLAsset

- (id)initWithURL:(NSURL*)url options:(NSDictionary*)options {
    if ([url.path containsString:@"/decrypted-media-v2/"]) {
        gPFBLastVoiceURL = url;
    }
    pfbProbeVoiceFileOpened(url);
    return %orig;
}

%end

// The file is already on disk and already decrypted; copying it out under a
// fresh name is enough to hand it to the share sheet.
static void PFBSaveVoiceMessage(NSURL* sourceURL) {
    if (!sourceURL.isFileURL) {
        return;
    }
    NSString* extension = sourceURL.pathExtension.length ? sourceURL.pathExtension : @"m4a";
    NSURL* destination = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
        URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@",
                                                              NSUUID.UUID.UUIDString,
                                                              extension]];
    NSError* copyError = nil;
    [[NSFileManager defaultManager] copyItemAtURL:sourceURL
                                            toURL:destination
                                            error:&copyError];
    if (copyError) {
        return;
    }
    [PFBManager showSaveVC:destination];
}

// Probe: the audio views on screen, for the read above, and their ivars once per build.
static void pfbProbeAudioViewLaidOut(UIView* view) {
    if (atomic_load_explicit(&gPFBProbeVoiceDone, memory_order_relaxed) || !PFBDebugIsRecording()) {
        return;
    }
    if (!gPFBProbeAudioViews) {
        gPFBProbeAudioViews = [NSHashTable weakObjectsHashTable];
        atomic_store(&gPFBProbeAudioSeen, true);
    }
    [gPFBProbeAudioViews addObject:view];
    if (gPFBProbeAudioIvarsNoted) {
        return;
    }
    gPFBProbeAudioIvarsNoted = YES;
    if (!PFBProbeWants(@"10a#F030 ivars")) {
        return;
    }
    Class cls = object_getClass(view);
    NSMutableArray<NSString*>* parts = [NSMutableArray array];
    for (NSString* name in @[ @"currentFileURL", @"audioAttachment", @"messageID", @"isPlaying" ]) {
        Ivar ivar = class_getInstanceVariable(cls, name.UTF8String);
        const char* type = ivar ? ivar_getTypeEncoding(ivar) : NULL;
        [parts addObject:ivar ? [NSString stringWithFormat:@"%@ at %td type '%s'", name, ivar_getOffset(ivar), type ?: ""]
                              : [name stringByAppendingString:@" absent"]];
    }
    PFBProbeNote(@"10a#F030 ivars", @"10a#F030 voice: %@ ivars %@ (instance size %zu)", PFBProbeClassName(view),
                 [parts componentsJoinedByString:@", "], class_getInstanceSize(cls));
    pfbProbeVoiceCheckDone();
}

// Probe: a long press on an audio view: whether it plays, the file offered, when it was
// kept and by which view; once per outcome.
static void pfbProbeVoiceLongPress(UIView* view, NSURL* offered) {
    if (atomic_load(&gPFBProbeVoiceDone) || !PFBDebugIsRecording() || !NSThread.isMainThread) {
        return;
    }
    NSInteger state = pfbProbeByte(view, "isPlaying");
    NSString* playing = state < 0 ? @"unreadable" : state ? @"playing" : @"not playing";
    NSURL* own = objc_getAssociatedObject(view, kPFBProbeVoiceFileKey);
    NSString* owner = !offered                                                       ? @"-"
                      : own && [own isEqual:offered]                                 ? @"this view"
                      : gPFBProbeVoiceBoundURL && [gPFBProbeVoiceBoundURL isEqual:offered] ? @"another view"
                                                                                     : @"no view";
    NSString* key = [NSString stringWithFormat:@"10a#F030 press %@ %@ %@", playing, offered ? @"file" : @"none", owner];
    if (!PFBProbeWants(key)) {
        return;
    }
    os_unfair_lock_lock(&gPFBProbeVoiceLock);
    NSURL* kept = gPFBProbeVoiceKeptURL;
    CFTimeInterval keptAt = gPFBProbeVoiceKeptAt;
    os_unfair_lock_unlock(&gPFBProbeVoiceLock);
    NSString* offer = !offered ? @"none"
                               : [NSString stringWithFormat:@"%@, kept %@ by %@", pfbProbeVoiceShape(offered),
                                                            kept && [kept isEqual:offered]
                                                                ? [NSString stringWithFormat:@"%.1f s ago",
                                                                                             CACurrentMediaTime() - keptAt]
                                                                : @"at an unknown time",
                                                            owner];
    PFBProbeNote(key, @"10a#F030 voice: long press on an audio view (%@), file offered %@; this view's own file %@", playing,
                 offer, !own ? @"none" : [own isEqual:offered] ? @"the one offered" : @"another");
    gPFBProbeVoicePresses++;
    pfbProbeVoiceCheckDone();
}

// MARK: - Probe: long press on chat bubbles

// Probe: the actions a gesture recognizer names in its description.
static NSString* pfbProbeActionNames(UIGestureRecognizer* recognizer) {
    NSString* text = recognizer.description;
    NSCharacterSet* stops = [NSCharacterSet characterSetWithCharactersInString:@", )>"];
    NSMutableArray<NSString*>* names = [NSMutableArray array];
    NSRange rest = NSMakeRange(0, text.length);
    while (names.count < 4) {
        NSRange mark = [text rangeOfString:@"action=" options:0 range:rest];
        if (mark.location == NSNotFound) {
            break;
        }
        NSUInteger start = NSMaxRange(mark);
        NSRange stop = [text rangeOfCharacterFromSet:stops options:0 range:NSMakeRange(start, text.length - start)];
        NSUInteger end = stop.location == NSNotFound ? text.length : stop.location;
        [names addObject:[text substringWithRange:NSMakeRange(start, end - start)]];
        rest = NSMakeRange(end, text.length - end);
    }
    return names.count ? [names componentsJoinedByString:@" "] : @"no action";
}

// Probe: whether an interaction is the menu added here.
static BOOL pfbProbeIsOurMenu(id<UIInteraction> interaction, UIView* view) {
    return [interaction isKindOfClass:[UIContextMenuInteraction class]] &&
           ((UIContextMenuInteraction*)interaction).delegate == (id)view;
}

// Probe: the interactions and gestures from a chat bubble up to its message cell, once per
// bubble class, the first time it is laid out on screen; nothing when ours is absent (option off).
static BOOL gPFBProbeChainAudioDone;
static BOOL gPFBProbeChainAttachmentDone;
static void pfbProbeChatChain(UIView* bubble, BOOL* done) {
    if (*done || !PFBDebugIsRecording() || !bubble.window) {
        return;
    }
    BOOL ours = NO;
    for (id<UIInteraction> interaction in bubble.interactions) {
        ours = ours || pfbProbeIsOurMenu(interaction, bubble);
    }
    *done = YES;
    if (!ours) {
        return;
    }
    NSString* key = [@"SD-2 chain " stringByAppendingString:PFBProbeClassName(bubble)];
    if (!PFBProbeWants(key)) {
        return;
    }
    NSMutableArray<NSString*>* levels = [NSMutableArray array];
    BOOL reachedCell = NO;
    NSUInteger depth = 0;
    for (UIView* view = bubble; view && depth < 14 && !reachedCell; view = view.superview, depth++) {
        NSMutableArray<NSString*>* parts = [NSMutableArray array];
        for (id<UIInteraction> interaction in view.interactions) {
            [parts addObject:[NSString stringWithFormat:@"%@%@", PFBProbeClassName(interaction),
                                                        pfbProbeIsOurMenu(interaction, view) ? @" (ours)" : @""]];
        }
        for (UIGestureRecognizer* recognizer in view.gestureRecognizers) {
            [parts addObject:[NSString stringWithFormat:@"%@ (%@)", PFBProbeClassName(recognizer),
                                                        pfbProbeActionNames(recognizer)]];
        }
        if (parts.count) {
            [levels addObject:[NSString stringWithFormat:@"%@ carries %@", PFBProbeClassName(view),
                                                         [parts componentsJoinedByString:@", "]]];
        }
        reachedCell = [NSStringFromClass([view class]) hasSuffix:@"MessageCell"];
    }
    NSString* chain = levels.count ? [levels componentsJoinedByString:@"; "] : @"nothing";
    PFBProbeNote(key, @"SD-2 chain from %@ up to %@: %@", PFBProbeClassName(bubble),
                 reachedCell ? @"its message cell" : @"14 levels, no message cell",
                 chain.length > 700 ? [[chain substringToIndex:700] stringByAppendingString:@"..."] : chain);
}

// Probe: a short title, handles masked.
static NSString* pfbProbeTitle(NSString* title) {
    if (!title.length) {
        return @"?";
    }
    NSString* masked = [title stringByReplacingOccurrencesOfString:@"@\\w+"
                                                        withString:@"@handle"
                                                           options:NSRegularExpressionSearch
                                                             range:NSMakeRange(0, title.length)];
    return masked.length > 28 ? [masked substringToIndex:28] : masked;
}

// Probe: a class name that reads as a message menu of Twitter's.
static BOOL pfbProbeLooksLikeMessageMenu(NSString* name) {
    for (NSString* part in @[ @"ActionSheet", @"MessageContextMenu", @"MessageAction", @"EmojiPicker", @"QuickReaction",
                              @"ReactionPicker" ]) {
        if ([name containsString:part]) {
            return YES;
        }
    }
    return NO;
}

// Probe: the controller presented on top in Twitter's window.
static NSString* pfbProbeTopControllerName(void) {
    UIViewController* top = PFBProbeAppWindow().rootViewController;
    for (NSUInteger depth = 0; top.presentedViewController && depth < 12; depth++) {
        top = top.presentedViewController;
    }
    return PFBProbeClassName(top);
}

// Probe: the labels of a UIKit menu, its preview left out.
static void pfbProbeMenuLabels(UIView* view, NSMutableArray<NSString*>* titles, NSUInteger* budget) {
    if (*budget == 0 || titles.count >= 6 || view.hidden) {
        return;
    }
    (*budget)--;
    NSString* name = NSStringFromClass([view class]);
    for (NSString* skip in @[ @"Platter", @"Preview", @"Portal", @"Snapshot", @"Morph" ]) {
        if ([name containsString:skip]) {
            return;
        }
    }
    if ([view isKindOfClass:[UILabel class]] && ((UILabel*)view).text.length) {
        [titles addObject:pfbProbeTitle(((UILabel*)view).text)];
    }
    for (UIView* sub in view.subviews) {
        pfbProbeMenuLabels(sub, titles, budget);
    }
}

// Probe: UIKit's context menu and any message menu of Twitter's on screen, from every
// window of the app, within 4000 views.
static NSString* pfbProbeScreenMenus(NSString* topBefore) {
    NSMutableArray<NSString*>* titles = [NSMutableArray array];
    NSMutableArray<NSString*>* windows = [NSMutableArray array];
    NSString* uikitMenu = nil;
    NSString* twitterMenu = nil;
    NSUInteger budget = 4000;
    for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }
        for (UIWindow* window in ((UIWindowScene*)scene).windows) {
            NSString* windowName = PFBProbeClassName(window);
            if (window.hidden || [windowName hasPrefix:@"PFB"]) {
                continue;
            }
            if (![windowName isEqualToString:@"T1Window"] && windows.count < 4) {
                [windows addObject:windowName];
            }
            NSMutableArray<UIView*>* pending = [NSMutableArray arrayWithObject:window];
            while (pending.count && budget > 0) {
                UIView* view = pending.lastObject;
                [pending removeLastObject];
                budget--;
                if (view.hidden || view.alpha < 0.01) {
                    continue;
                }
                NSString* name = NSStringFromClass([view class]);
                if (!uikitMenu && [name containsString:@"ContextMenu"]) {
                    uikitMenu = name;
                    NSUInteger labelBudget = 600;
                    pfbProbeMenuLabels(view, titles, &labelBudget);
                    continue;
                }
                if (!twitterMenu && pfbProbeLooksLikeMessageMenu(name)) {
                    twitterMenu = name;
                }
                [pending addObjectsFromArray:view.subviews];
            }
        }
    }
    NSString* topAfter = pfbProbeTopControllerName();
    if (!twitterMenu && pfbProbeLooksLikeMessageMenu(topAfter)) {
        twitterMenu = topAfter;
    }
    return [NSString stringWithFormat:@"UIKit menu %@ · Twitter menu %@ (top controller %@ before, %@ after; other "
                                      @"windows %@)",
                                      uikitMenu ? [NSString stringWithFormat:@"%@ [%@]", uikitMenu,
                                                                             [titles componentsJoinedByString:@" | "]]
                                                : @"none",
                                      twitterMenu ?: @"none", topBefore, topAfter,
                                      windows.count ? [windows componentsJoinedByString:@", "] : @"none"];
}

// Probe: ours asked for a menu on a chat bubble, then what is on screen 0.8 s later; once
// per bubble class and answer.
static void pfbProbeChatLongPress(UIView* bubble, BOOL menu) {
    if (!PFBDebugIsRecording() || !NSThread.isMainThread) {
        return;
    }
    NSString* name = PFBProbeClassName(bubble);
    NSString* key = [NSString stringWithFormat:@"SD-2 asked %@ %@", name, menu ? @"menu" : @"nil"];
    if (!PFBProbeWants(key)) {
        return;
    }
    NSString* before = pfbProbeTopControllerName();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      if (PFBProbeWants(key)) {
          PFBProbeNote(key, @"SD-2 chat long press on %@: ours asked (%@); on screen: %@", name, menu ? @"menu" : @"nil",
                       pfbProbeScreenMenus(before));
      }
    });
}

// The audio view carries its own interaction, since it is a separate view and wins
// the touch first. It is held by association and the view addressed as a UIView:
// the class is known to the compiler only by a forward declaration.
static const void* kPFBVoiceInteractionKey = &kPFBVoiceInteractionKey;

%hook _TtC16ChatConversation26MessageAttachmentAudioView

- (void)layoutSubviews {
    %orig;
    UIView* view = (UIView*)self;
    BOOL enabled = [PFBSettings boolForKey:@"download_voice_messages"];
    if (!enabled) {
        PFBCOMPAT_OBSERVE(PFBCompat_download_voice_messages, @"voice note found");
    }
    if (enabled &&
        !objc_getAssociatedObject(view, kPFBVoiceInteractionKey)) {
        UIContextMenuInteraction* interaction = [[UIContextMenuInteraction alloc]
            initWithDelegate:(id<UIContextMenuInteractionDelegate>)self];
        objc_setAssociatedObject(view, kPFBVoiceInteractionKey, interaction,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [view addInteraction:interaction];
        PFBCOMPAT_ACTION(PFBCompat_download_voice_messages, @"save menu on a voice note");
    }
    pfbProbeAudioViewLaidOut(view);
    pfbProbeChatChain(view, &gPFBProbeChainAudioDone);
}

%new
- (UIContextMenuConfiguration*)contextMenuInteraction:(UIContextMenuInteraction*)interaction
                       configurationForMenuAtLocation:(CGPoint)location {
    NSURL* voiceURL = gPFBLastVoiceURL;
    pfbProbeVoiceLongPress((UIView*)self, voiceURL);
    pfbProbeChatLongPress((UIView*)self, voiceURL != nil);
    if (!voiceURL) {
        return nil;
    }
    return [UIContextMenuConfiguration
        configurationWithIdentifier:nil
                    previewProvider:nil
                     actionProvider:^UIMenu* _Nullable(
                         NSArray<UIMenuElement*>* _Nonnull suggestedActions) {
                       UIAction* saveAction = [UIAction
                           actionWithTitle:[[PFBBundle sharedBundle]
                                               localizedTwitterStringForKey:
                                                   @"DOWNLOAD_ACTIVITY_VIEW_LABEL"]
                                     image:PFBTwitterGlyphFor(@"arrow_down_circle_stroke", [UIImage systemImageNamed:@"square.and.arrow.down"])
                                identifier:nil
                                   handler:^(__kindof UIAction* _Nonnull action) {
                                     PFBSaveVoiceMessage(voiceURL);
                                   }];
                       return [UIMenu menuWithTitle:@"" children:@[ saveAction ]];
                     }];
}

%end

%hook _TtC16ChatConversation21MessageAttachmentView
%property (nonatomic, strong) UIContextMenuInteraction* pfbDownloadMenuInteraction;
%property (nonatomic, strong) PFBDownloadInlineButton* pfbDownloadHandler;
- (void)layoutSubviews {
    %orig;

    BOOL enabled = [PFBSettings boolForKey:@"download_videos"];
    if (enabled && self.pfbDownloadMenuInteraction == nil) {
        self.pfbDownloadMenuInteraction = [[UIContextMenuInteraction alloc] initWithDelegate:self];
        [self addInteraction:self.pfbDownloadMenuInteraction];
        PFBCOMPAT_ACTION(PFBCompat_download_videos, @"save menu on chat media");
    } else if (!enabled) {
        PFBCOMPAT_OBSERVE(PFBCompat_download_videos, @"chat media found");
    }
    pfbProbeChatChain(self, &gPFBProbeChainAttachmentDone);
}
%new
- (UIContextMenuConfiguration*)contextMenuInteraction:(UIContextMenuInteraction*)interaction
                       configurationForMenuAtLocation:(CGPoint)location {
    NSArray* videoEntities = DMVideoEntities(self);
    pfbProbeChatLongPress(self, videoEntities.count > 0);
    if (videoEntities.count == 0) {
        return nil;
    }

    return [UIContextMenuConfiguration
        configurationWithIdentifier:nil
                    previewProvider:nil
                     actionProvider:^UIMenu* _Nullable(
                         NSArray<UIMenuElement*>* _Nonnull suggestedActions) {
                         UIAction* saveAction = [UIAction
                             actionWithTitle:
                                 [[PFBBundle sharedBundle]
                                     localizedTwitterStringForKey:@"DOWNLOAD_ACTIVITY_VIEW_LABEL"]
                                       image:PFBTwitterGlyphFor(@"arrow_down_circle_stroke", [UIImage systemImageNamed:@"square.and.arrow.down"])
                                  identifier:nil
                                     handler:^(__kindof UIAction* _Nonnull action) {
                                         if (self.pfbDownloadHandler == nil) {
                                             self.pfbDownloadHandler = [%c(PFBDownloadInlineButton) new];
                                         }
                                         [self.pfbDownloadHandler
                                             presentDownloadOptionsForMediaEntities:videoEntities];
                                     }];
                         return [UIMenu menuWithTitle:@"" children:@[saveAction]];
                     }];
}
%end

// MARK: - Upload custom voice

// Probe: where a voice recording reaches the attachment cell, and the colors around the
// upload button, once per build; read 0.3 s after the cell is updated, once it is on screen.
static BOOL gPFBProbeVoiceCellDone;
static BOOL gPFBProbeVoiceCellPending;
static void pfbProbeVoiceCellNote(UIView* cell) {
    if (gPFBProbeVoiceCellDone || !cell.window) {
        return;
    }
    gPFBProbeVoiceCellDone = YES;
    if (!PFBProbeWants(@"14b#F016b cell")) {
        return;
    }
    UIViewController* controller = PFBProbeControllerOfView(cell);
    NSString* screen = PFBProbeScreenName(controller);
    NSString* names = [PFBProbeClassName(controller) stringByAppendingFormat:@" %@", screen];
    NSString* place = [names containsString:@"Chat"] ? @"Messages" : [names containsString:@"Compose"] ? @"Tweet composer" : @"other";
    UITraitCollection* traits = cell.traitCollection;
    NSString* style = traits.userInterfaceStyle == UIUserInterfaceStyleDark    ? @"dark"
                      : traits.userInterfaceStyle == UIUserInterfaceStyleLight ? @"light"
                                                                               : @"unspecified";
    Ivar removeIvar = class_getInstanceVariable(object_getClass(cell), "_removeButton");
    id removeButton = removeIvar ? object_getIvar(cell, removeIvar) : nil;
    UIView* remove = [removeButton isKindOfClass:[UIView class]] ? removeButton : nil;
    UIButton* upload = ((T1MediaAttachmentsViewCell*)cell).pfbUploadButton;
    PFBProbeNote(@"14b#F016b cell",
                 @"14b#F016b voice recording attachment in %@ (%@, screen %@) · cell style %@ · remove button %@; "
                 @"upload button %@",
                 PFBProbeClassName(controller), place, screen, style,
                 remove ? [NSString stringWithFormat:@"background %@, glyph tint %@", PFBProbeColor(remove.backgroundColor, traits),
                                                     PFBProbeColor(remove.tintColor, traits)]
                        : @"absent",
                 upload ? [NSString stringWithFormat:@"background %@, glyph tint %@", PFBProbeColor(upload.backgroundColor, traits),
                                                     PFBProbeColor(upload.tintColor, traits)]
                        : @"absent");
}

static void pfbProbeVoiceRecordingCell(UIView* cell, BOOL isVoiceRecording) {
    if (gPFBProbeVoiceCellDone || !isVoiceRecording || gPFBProbeVoiceCellPending || !PFBDebugIsRecording()) {
        return;
    }
    gPFBProbeVoiceCellPending = YES;
    __weak UIView* weakCell = cell;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      gPFBProbeVoiceCellPending = NO;
      UIView* strongCell = weakCell;
      if (strongCell) {
          pfbProbeVoiceCellNote(strongCell);
      }
    });
}

// Probe: a getter's floating-point value, read only when its signature says it returns one.
static double pfbProbeDoubleGetter(id object, NSString* name) {
    SEL selector = NSSelectorFromString(name);
    if (!object || ![object respondsToSelector:selector]) {
        return -1;
    }
    NSMethodSignature* signature = [object methodSignatureForSelector:selector];
    if (signature.numberOfArguments != 2) {
        return -1;
    }
    switch (signature.methodReturnType[0]) {
        case 'd':
            return ((double (*)(id, SEL))objc_msgSend)(object, selector);
        case 'f':
            return ((float (*)(id, SEL))objc_msgSend)(object, selector);
        default:
            return -1;
    }
}

// Probe: the recording's own duration against the video copied over its file, and whether
// the copy is in place, once per build.
static void pfbProbeVoiceReplaced(id attachment, NSURL* videoURL, NSURL* recorderURL) {
    if (!PFBDebugIsRecording() || !NSThread.isMainThread || !PFBProbeWants(@"13#T1.e-16 replaced")) {
        return;
    }
    BOOL found = NO;
    long long millis = PFBProbeIntegerGetter(attachment, @"totalDurationMillis", &found);
    double recording = found && millis > 0 ? (double)millis / 1000.0 : pfbProbeDoubleGetter(attachment, @"cachedAssetDuration");
    NSFileManager* files = [NSFileManager defaultManager];
    NSNumber* videoSize = videoURL.path ? [files attributesOfItemAtPath:videoURL.path error:nil][NSFileSize] : nil;
    NSNumber* copiedSize = recorderURL.path ? [files attributesOfItemAtPath:recorderURL.path error:nil][NSFileSize] : nil;
    NSString* copy = !recorderURL ? @"not tried, no recording file"
                     : !copiedSize ? @"error, no file at the recording's path"
                     : [copiedSize isEqual:videoSize] ? @"ok"
                                                      : @"error, sizes differ";
    NSURL* source = copiedSize ? recorderURL : videoURL;
    if (!source) {
        PFBProbeNote(@"13#T1.e-16 replaced", @"13#T1.e-16 voice note replaced: recording %.1f s, video unknown, copy %@",
                     recording, copy);
        return;
    }
    gPFBProbeOwnAsset = YES;
    AVURLAsset* asset = [AVURLAsset URLAssetWithURL:source options:nil];
    gPFBProbeOwnAsset = NO;
    [asset loadValuesAsynchronouslyForKeys:@[ @"duration" ]
                         completionHandler:^{
                           if (!PFBProbeWants(@"13#T1.e-16 replaced")) {
                               return;
                           }
                           CMTime time = asset.duration;
                           PFBProbeNote(@"13#T1.e-16 replaced",
                                        @"13#T1.e-16 voice note replaced: recording %.1f s, video %.1f s, copy %@", recording,
                                        CMTIME_IS_NUMERIC(time) ? CMTimeGetSeconds(time) : -1.0, copy);
                         }];
}

// Overwrites the recording at the attachment's existing file path, so the
// composer picks up the replacement without any model changes.
%hook T1MediaAttachmentsViewCell
%property (nonatomic, strong) UIButton* pfbUploadButton;
- (void)updateCellElements {
    %orig;

    BOOL isVoiceRecording = [self.attachment isKindOfClass:%c(TTMAssetVoiceRecording)];
    BOOL enabled = [PFBSettings boolForKey:@"voice_note_from_video"];
    pfbProbeVoiceRecordingCell((UIView*)self, isVoiceRecording);
    if (isVoiceRecording && !enabled) {
        PFBCOMPAT_OBSERVE(PFBCompat_voice_note_from_video, @"voice note attached");
    }

    if (enabled && isVoiceRecording && self.pfbUploadButton == nil) {
        // Read from the ivar: a key-value read of a name Twitter dropped would throw.
        Ivar removeIvar = class_getInstanceVariable(object_getClass(self), "_removeButton");
        TFNButton* removeButton = removeIvar ? object_getIvar(self, removeIvar) : nil;
        if (![removeButton isKindOfClass:[UIView class]]) {
            return;
        }

        self.pfbUploadButton = [UIButton buttonWithType:UIButtonTypeCustom];
        UIImageSymbolConfiguration* smallConfig =
            [UIImageSymbolConfiguration configurationWithScale:UIImageSymbolScaleSmall];
        UIImage* arrowUpImage = [UIImage systemImageNamed:@"arrow.up" withConfiguration:smallConfig];
        [self.pfbUploadButton setImage:arrowUpImage forState:UIControlStateNormal];
        [self.pfbUploadButton addTarget:self
                                 action:@selector(pfbHandleUploadButton:)
                       forControlEvents:UIControlEventTouchUpInside];
        [self.pfbUploadButton setTintColor:UIColor.labelColor];
        [self.pfbUploadButton setBackgroundColor:[UIColor blackColor]];
        [self.pfbUploadButton.layer setCornerRadius:29 / 2];
        [self.pfbUploadButton setTranslatesAutoresizingMaskIntoConstraints:false];

        [self addSubview:self.pfbUploadButton];
        [NSLayoutConstraint activateConstraints:@[
            [self.pfbUploadButton.trailingAnchor constraintEqualToAnchor:removeButton.leadingAnchor
                                                                constant:-10],
            [self.pfbUploadButton.topAnchor constraintEqualToAnchor:removeButton.topAnchor],
            [self.pfbUploadButton.widthAnchor constraintEqualToConstant:29],
            [self.pfbUploadButton.heightAnchor constraintEqualToConstant:29],
        ]];
    }

    self.pfbUploadButton.hidden = !(isVoiceRecording && enabled);
    if (isVoiceRecording && enabled && self.pfbUploadButton) {
        PFBCOMPAT_ACTION(PFBCompat_voice_note_from_video, @"upload button on a voice note");
    }
}
%new
- (void)pfbHandleUploadButton:(UIButton*)sender {
    UIImagePickerController* videoPicker = [[UIImagePickerController alloc] init];
    videoPicker.mediaTypes = @[(NSString*)kUTTypeMovie];
    videoPicker.delegate = self;

    [topMostController() presentViewController:videoPicker animated:YES completion:nil];
}
%new
- (void)imagePickerController:(UIImagePickerController*)picker
    didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id>*)info {
    NSURL* videoURL = info[UIImagePickerControllerMediaURL];
    TTMAssetVoiceRecording* attachment = self.attachment;
    NSString* recorderPath = attachment.filePath;
    NSURL* recorder_url = recorderPath ? [NSURL fileURLWithPath:recorderPath] : nil;

    if (recorder_url != nil) {
        NSFileManager* fileManager = [NSFileManager defaultManager];

        NSError* error = nil;
        if ([fileManager fileExistsAtPath:[recorder_url path]]) {
            [fileManager removeItemAtURL:recorder_url error:&error];
        }

        [fileManager copyItemAtURL:videoURL toURL:recorder_url error:&error];
    }
    pfbProbeVoiceReplaced(attachment, videoURL, recorder_url);

    [picker dismissViewControllerAnimated:true completion:nil];
}
%new
- (void)imagePickerControllerDidCancel:(UIImagePickerController*)picker {
    [picker dismissViewControllerAnimated:true completion:nil];
}
%end

// MARK: - Save tweet as an image

%hook TTAStatusInlineShareButton
- (void)didLongPressActionButton:(UILongPressGestureRecognizer*)gestureRecognizer {
    if ([PFBSettings boolForKey:@"tweet_to_image"]) {
        if (gestureRecognizer.state == UIGestureRecognizerStateBegan) {
            UIView* statusView = self.superview;
            while (statusView && ![statusView respondsToSelector:@selector(eventHandler)]) {
                statusView = statusView.superview;
            }

            UIView* tweetView = nil;
            id eventHandler = [(T1StandardStatusView*)statusView eventHandler];
            if ([eventHandler isKindOfClass:UIView.class]) {
                tweetView = eventHandler;
            }

            if (tweetView == nil) {
                UIView* ancestor = self.superview;
                while (ancestor && ![ancestor isKindOfClass:UITableViewCell.class] &&
                       ![ancestor isKindOfClass:UICollectionViewCell.class]) {
                    ancestor = ancestor.superview;
                }
                tweetView = ancestor;
            }

            if (tweetView == nil) {
                return %orig;
            }

            UIImage* tweetImage = imageFromView(tweetView);
            NSData* pngData = UIImagePNGRepresentation(tweetImage);
            NSURL* pngURL = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
                URLByAppendingPathComponent:[NSString
                                                stringWithFormat:@"%@.png", [[NSUUID UUID] UUIDString]]];
            [pngData writeToURL:pngURL atomically:YES];
            UIActivityViewController* acVC =
                [[UIActivityViewController alloc] initWithActivityItems:@[pngURL]
                                                  applicationActivities:nil];
            if (is_iPad()) {
                acVC.popoverPresentationController.sourceView = self;
                acVC.popoverPresentationController.sourceRect = self.bounds;
            }
            [topMostController() presentViewController:acVC
                                              animated:true
                                            completion:^{
                                              PFBCOMPAT_ACTION(PFBCompat_tweet_to_image, @"Tweet saved as image");
                                            }];
            return;
        }
    }
    if (gestureRecognizer.state == UIGestureRecognizerStateBegan &&
        ![PFBSettings boolForKey:@"tweet_to_image"]) {
        PFBCOMPAT_OBSERVE(PFBCompat_tweet_to_image, @"long press on share");
    }
    return %orig;
}
%end

// MARK: - Tweet media download, in the media long-press menu

// That menu has no Objective-C builder, so the only point on its path is the
// two-argument +[UIMenu menuWithTitle:children:]. The tweet comes from the
// T1ActivityItemProvider built shortly before.

// T1ActivityItemProvider is not declared in src/Support, so a declaration
// shim is used purely as a cast target. It is never instantiated and never
// messaged as a class, so no class symbol is referenced and linking is safe.
@interface PFBVMDProviderShim : NSObject
- (id)status;
@end

// Freshness window between the share sheet and the menu; past it nothing is added,
// since no entry is better than the wrong media.
static const NSTimeInterval kPFBVMDFreshness = 3.0;

// The added entry is told apart by identifier: the app's own entry can carry the
// very same title.
static NSString* const kPFBVMDActionIdentifier = @"com.primefreebird.download-video";

static id                    gPFBVMDStatus;        // tweet under the long press
static NSTimeInterval        gPFBVMDStatusTime;
static PFBDownloadInlineButton* gPFBVMDDownloader;    // reused downloader instance

// A Tweet's media when one of them is a video or a GIF (mediaType 2 or 3), else nil.
static NSArray* PFBVMDVideoEntities(id status) {
    if (![status respondsToSelector:@selector(entities)]) {
        return nil;
    }
    NSArray* mediaEntities = [[status entities] media];
    for (TFSTwitterEntityMedia* media in mediaEntities) {
        if ([media isKindOfClass:%c(TFSTwitterEntityMedia)] &&
            (media.mediaType == 2 || media.mediaType == 3)) {
            return mediaEntities;
        }
    }
    return nil;
}

%hook UIActivityViewController

- (id)initWithActivityItems:(NSArray*)activityItems
      applicationActivities:(NSArray*)applicationActivities {
    id result = %orig;
    @try {
        for (id item in activityItems) {
            if (![item respondsToSelector:@selector(status)]) {
                continue;
            }
            id status = [(PFBVMDProviderShim*)item status];
            if (!status) {
                continue;
            }
            gPFBVMDStatus = status;
            gPFBVMDStatusTime = [NSDate timeIntervalSinceReferenceDate];
            break;
        }
    } @catch (id exception) {
    }
    return result;
}

%end

// The captured Tweet's video media while still fresh; nil otherwise.
static NSArray* PFBVMDFreshVideoEntities(void) {
    NSTimeInterval age = [NSDate timeIntervalSinceReferenceDate] - gPFBVMDStatusTime;
    if (!gPFBVMDStatus || age < 0 || age > kPFBVMDFreshness) {
        return nil;
    }
    return PFBVMDVideoEntities(gPFBVMDStatus);
}

// The title comes from Twitter's own strings, so it matches the native entry; the bundled
// TW_ copy covers a miss. The lookup returns the key itself when both miss, hence the
// explicit fallback.
static NSString* PFBVMDMenuTitle(void) {
    NSString* key = @"DOWNLOAD_VIDEO_ACTIVITY_VIEW_LABEL";
    NSString* title = [[PFBBundle sharedBundle] localizedTwitterStringForKey:key];
    if (title.length == 0 || [title isEqualToString:key]) {
        return @"Download Video";
    }
    return title;
}

// A download entry by its title: the added one, which the app's video entry also shows,
// the app's generic one, or a raw key when the app shows one.
static BOOL PFBVMDTitleIsDownload(NSString* title, NSString* ours,
                                  NSString* generic) {
    if ([title isEqualToString:ours] ||
        (generic.length > 0 && [title isEqualToString:generic])) {
        return YES;
    }
    NSString* upper = title.uppercaseString;
    return [upper containsString:@"DOWNLOAD"] &&
           [upper containsString:@"ACTIVITY_VIEW_LABEL"];
}

static BOOL PFBVMDIsOurs(id element) {
    return [element isKindOfClass:[UIAction class]] &&
           [((UIAction*)element).identifier isEqualToString:kPFBVMDActionIdentifier];
}

// Guards against adding the entry twice when a menu is rebuilt.
static BOOL PFBVMDAlreadyHasOurs(NSArray* children) {
    for (id element in children) {
        if (PFBVMDIsOurs(element)) {
            return YES;
        }
    }
    return NO;
}

static UIImage* PFBVMDGlyph(void) {
    UIImage* glyph = nil;
    if ([UIImage respondsToSelector:@selector(tfn_vectorImageNamed:fitsSize:fillColor:)]) {
        glyph = [UIImage tfn_vectorImageNamed:@"arrow_down_circle_stroke"
                                     fitsSize:CGSizeMake(24.0, 24.0)
                                    fillColor:[UIColor labelColor]];
    }
    if (!glyph) {
        glyph = [UIImage systemImageNamed:@"arrow.down.circle"];
    }
    return glyph;
}

// The app's own download entries leave a menu that holds the added entry, so one entry
// remains; without it, the app's stay untouched.
static NSArray* PFBVMDWithoutNativeDownload(NSArray* children) {
    NSString* ours = PFBVMDMenuTitle();
    NSString* generic = [[PFBBundle sharedBundle]
                            localizedTwitterStringForKey:@"DOWNLOAD_ACTIVITY_VIEW_LABEL"];
    NSMutableArray* kept = nil;
    for (id element in children) {
        if (PFBVMDIsOurs(element) || ![element respondsToSelector:@selector(title)]) {
            continue;
        }
        NSString* title = [element title];
        if (title.length == 0 || !PFBVMDTitleIsDownload(title, ours, generic)) {
            continue;
        }
        if (!kept) {
            kept = [children mutableCopy];
        }
        [kept removeObject:element];
    }
    return kept ?: children;
}

// Probe: the menus that receive the added entry, once per first entry (at most 8).
static BOOL gPFBProbeMenuDone;
static NSUInteger gPFBProbeMenuNotes;
static void pfbProbeMenuEntryAdded(NSArray* children) {
    if (gPFBProbeMenuDone || !PFBDebugIsRecording()) {
        return;
    }
    NSMutableArray<NSString*>* titles = [NSMutableArray array];
    for (id element in children) {
        NSString* title = [element isKindOfClass:[UIMenuElement class]] ? pfbProbeTitle(((UIMenuElement*)element).title) : @"?";
        title = [element isKindOfClass:[UIMenu class]] ? [NSString stringWithFormat:@"[%@]", title] : title;
        [titles addObject:PFBVMDIsOurs(element) ? [@"*" stringByAppendingString:title] : title];
    }
    NSString* key = [@"10a#F028 " stringByAppendingString:titles.firstObject ?: @"empty"];
    if (!PFBProbeWants(key)) {
        return;
    }
    PFBProbeNote(key, @"10a#F028 Download Video added %.1f s after the share sheet to a menu of %lu entries: %@",
                 [NSDate timeIntervalSinceReferenceDate] - gPFBVMDStatusTime, (unsigned long)children.count,
                 [titles componentsJoinedByString:@" | "]);
    gPFBProbeMenuDone = ++gPFBProbeMenuNotes >= 8;
}

// The children to install: the added entry before the last item ("Share via..."), in
// place of the app's own; unchanged without a fresh video Tweet or with the option off.
static NSArray* PFBVMDMenuChildren(NSArray* children) {
    if (children.count == 0) {
        return children;
    }
    if (PFBVMDAlreadyHasOurs(children)) {
        return PFBVMDWithoutNativeDownload(children);
    }
    NSArray* mediaEntities = PFBVMDFreshVideoEntities();
    if (mediaEntities.count == 0) {
        return children;
    }
    if (!gPFBVMDDownloader) {
        gPFBVMDDownloader = [%c(PFBDownloadInlineButton) new];
    }
    PFBDownloadInlineButton* downloader = gPFBVMDDownloader;
    // A path tour reads the download path without downloading anything.
    if (PFBCompatTourIsRunning()) {
        [downloader dryRunForMediaEntities:mediaEntities];
    }
    if (![PFBSettings boolForKey:@"download_videos"]) {
        PFBCOMPAT_OBSERVE(PFBCompat_download_videos, @"video menu found");
        return children;
    }
    PFBCOMPAT_ACTION(PFBCompat_download_videos, @"download entry in a video menu");

    UIAction* action = [UIAction actionWithTitle:PFBVMDMenuTitle()
                                           image:PFBVMDGlyph()
                                      identifier:kPFBVMDActionIdentifier
                                         handler:^(UIAction* sender) {
        [downloader presentDownloadOptionsForMediaEntities:mediaEntities];
    }];
    NSMutableArray* augmented = [PFBVMDWithoutNativeDownload(children) mutableCopy];
    [augmented insertObject:action atIndex:augmented.count ? augmented.count - 1 : 0];
    pfbProbeMenuEntryAdded(augmented);
    return augmented;
}

%hook UIMenu

+ (id)menuWithTitle:(NSString*)title children:(NSArray*)children {
    NSArray* finalChildren = children;
    @try {
        finalChildren = PFBVMDMenuChildren(children);
    } @catch (id exception) {
        finalChildren = children;
    }
    return %orig(title, finalChildren);
}

// The app appends its own entry after the menu is first built.
- (UIMenu*)menuByReplacingChildren:(NSArray*)children {
    NSArray* finalChildren = children;
    @try {
        if (PFBVMDAlreadyHasOurs(children)) {
            finalChildren = PFBVMDWithoutNativeDownload(children);
        }
    } @catch (id exception) {
        finalChildren = children;
    }
    return %orig(finalChildren);
}

%end
