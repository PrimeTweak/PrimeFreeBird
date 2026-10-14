// Chat privacy: drops the typing-indicator frame from the chat websocket and
// leaves the rest of the socket alone.

#import "Support/HookHelpers.h"
#import "Debug/PFBDebugger.h"
#import "Debug/PFBProbe.h"
#import <os/lock.h>
#import <stdatomic.h>
#import <string.h>

// MARK: - Matching

static BOOL pfbIsChatWebSocketURL(NSURL* url) {
    NSString* host = url.host;
    return host.length > 0 && [host hasPrefix:@"chat-ws."];
}

// The typing heartbeat is a Thrift TBinaryProtocol struct with fixed first fields.
// Ten bytes are enough to tell it apart from delivery, receipt and presence frames,
// which differ from the third byte on.
static const uint8_t kPFBTypingFramePrefix[] = {
    0x0c, 0x00, 0x01, 0x0b, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00
};

static BOOL pfbIsTypingIndicatorFrame(NSData* data) {
    if (data.length < sizeof(kPFBTypingFramePrefix)) {
        return NO;
    }
    return memcmp(data.bytes, kPFBTypingFramePrefix, sizeof(kPFBTypingFramePrefix)) == 0;
}

// MARK: - Probe

// Probe: the chat socket's frames, counted by their first ten bytes; noted once at the first typing
// match, after 60 frames once one went out while typing, or 8 s after typing in a conversation stops.
enum { kPFBProbeChatPrefixLimit = 8 };
static const NSUInteger kPFBProbeChatFrameLimit = 60;
static const CFTimeInterval kPFBProbeChatTypingWindow = 4.0;
static const CFTimeInterval kPFBProbeChatTypingSettle = 8.0;

typedef struct {
    uint8_t bytes[10];
    NSUInteger length;
    NSUInteger count;
    NSUInteger typing;
    NSUInteger shortest;
    NSUInteger longest;
} PFBProbeChatPrefix;

static os_unfair_lock gPFBProbeChatLock = OS_UNFAIR_LOCK_INIT;
static PFBProbeChatPrefix gPFBProbeChatPrefixes[kPFBProbeChatPrefixLimit];
static NSUInteger gPFBProbeChatPrefixCount;
static NSUInteger gPFBProbeChatFrames;
static NSUInteger gPFBProbeChatTypingFrames;
static NSUInteger gPFBProbeChatUnlisted;
static NSUInteger gPFBProbeChatTexts;
static NSUInteger gPFBProbeChatTextsTyping;
static NSUInteger gPFBProbeChatTypingGeneration;
static CFTimeInterval gPFBProbeChatTypedAt;
static atomic_bool gPFBProbeChatDone;

static void pfbProbeChatNote(NSString* when) {
    PFBProbeChatPrefix table[kPFBProbeChatPrefixLimit];
    os_unfair_lock_lock(&gPFBProbeChatLock);
    NSUInteger count = gPFBProbeChatPrefixCount;
    memcpy(table, gPFBProbeChatPrefixes, sizeof(table));
    NSUInteger frames = gPFBProbeChatFrames;
    NSUInteger typingFrames = gPFBProbeChatTypingFrames;
    NSUInteger unlisted = gPFBProbeChatUnlisted;
    NSUInteger texts = gPFBProbeChatTexts;
    NSUInteger textsTyping = gPFBProbeChatTextsTyping;
    os_unfair_lock_unlock(&gPFBProbeChatLock);
    BOOL matched = NO;
    NSMutableArray<NSString*>* prefixes = [NSMutableArray array];
    for (NSUInteger i = 0; i < count; i++) {
        PFBProbeChatPrefix* entry = &table[i];
        matched = matched || (entry->length == sizeof(kPFBTypingFramePrefix) &&
                              memcmp(entry->bytes, kPFBTypingFramePrefix, sizeof(kPFBTypingFramePrefix)) == 0);
        NSMutableString* hex = [NSMutableString string];
        for (NSUInteger b = 0; b < entry->length; b++) {
            [hex appendFormat:@"%02x", entry->bytes[b]];
        }
        NSString* size = entry->shortest == entry->longest
                             ? [NSString stringWithFormat:@"%lu B", (unsigned long)entry->shortest]
                             : [NSString stringWithFormat:@"%lu-%lu B", (unsigned long)entry->shortest,
                                                          (unsigned long)entry->longest];
        [prefixes addObject:[NSString stringWithFormat:@"%@ x%lu (%@, %lu while typing)", hex, (unsigned long)entry->count,
                                                       size, (unsigned long)entry->typing]];
    }
    if (unlisted > 0) {
        [prefixes addObject:[NSString stringWithFormat:@"%lu more under other prefixes", (unsigned long)unlisted]];
    }
    PFBProbeNote(@"10b#F033 chat frames",
                 @"10b#F033 chat frames: %lu seen (%lu while typing in a conversation), typing prefix matched %@; "
                 @"prefixes: %@; text frames %lu (%lu while typing) · noted %@",
                 (unsigned long)frames, (unsigned long)typingFrames, matched ? @"yes" : @"no",
                 prefixes.count ? [prefixes componentsJoinedByString:@", "] : @"none", (unsigned long)texts,
                 (unsigned long)textsTyping, when);
    atomic_store(&gPFBProbeChatDone, true);
}

// Probe: typing in a conversation, from the text-change notifications; the note follows
// once typing has stopped for a while, whether frames were sent or not.
static void pfbProbeChatTyped(id field) {
    if (atomic_load(&gPFBProbeChatDone) || !PFBDebugIsRecording() || ![field isKindOfClass:[UIView class]] ||
        !NSThread.isMainThread) {
        return;
    }
    UIViewController* controller = PFBProbeControllerOfView(field);
    UIWindow* window = PFBProbeAppWindow();
    UIView* front = [window hitTest:CGPointMake(CGRectGetMidX(window.bounds), CGRectGetMidY(window.bounds)) withEvent:nil];
    UIViewController* frontController = front ? PFBProbeControllerOfView(front) : nil;
    NSString* names = [NSString stringWithFormat:@"%@ %@ %@ %@", PFBProbeClassName(controller), PFBProbeScreenName(controller),
                                                 PFBProbeClassName(frontController), PFBProbeScreenName(frontController)];
    if (![names containsString:@"Chat"] || ![names containsString:@"Conversation"]) {
        return;
    }
    os_unfair_lock_lock(&gPFBProbeChatLock);
    gPFBProbeChatTypedAt = CACurrentMediaTime();
    NSUInteger generation = ++gPFBProbeChatTypingGeneration;
    os_unfair_lock_unlock(&gPFBProbeChatLock);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kPFBProbeChatTypingSettle * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                     if (atomic_load(&gPFBProbeChatDone) || !PFBProbeWants(@"10b#F033 chat frames")) {
                         return;
                     }
                     os_unfair_lock_lock(&gPFBProbeChatLock);
                     BOOL settled = generation == gPFBProbeChatTypingGeneration;
                     os_unfair_lock_unlock(&gPFBProbeChatLock);
                     if (settled) {
                         pfbProbeChatNote(@"8 s after typing in a conversation stopped");
                     }
                   });
}

// Probe: the text-change observers, registered once while recording.
static void pfbProbeChatWatchTyping(void) {
    if (atomic_load(&gPFBProbeChatDone) || !PFBDebugIsRecording()) {
        return;
    }
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      dispatch_async(dispatch_get_main_queue(), ^{
        for (NSNotificationName name in @[ UITextViewTextDidChangeNotification, UITextFieldTextDidChangeNotification ]) {
            [[NSNotificationCenter defaultCenter] addObserverForName:name
                                                              object:nil
                                                               queue:nil
                                                          usingBlock:^(NSNotification* note) {
                                                            pfbProbeChatTyped(note.object);
                                                          }];
        }
      });
    });
}

// Probe: one message sent on the chat socket: a data frame counted under its first ten
// bytes, a text frame only counted.
static void pfbProbeChatFrame(BOOL onChatSocket, NSURLSessionWebSocketMessage* message) {
    if (atomic_load_explicit(&gPFBProbeChatDone, memory_order_relaxed) || !PFBDebugIsRecording() || !onChatSocket) {
        return;
    }
    pfbProbeChatWatchTyping();
    NSData* data = message.data;
    if (!data) {
        CFTimeInterval now = CACurrentMediaTime();
        os_unfair_lock_lock(&gPFBProbeChatLock);
        gPFBProbeChatTexts++;
        gPFBProbeChatTextsTyping += gPFBProbeChatTypedAt > 0 && now - gPFBProbeChatTypedAt < kPFBProbeChatTypingWindow;
        os_unfair_lock_unlock(&gPFBProbeChatLock);
        return;
    }
    PFBProbeChatPrefix frame = {{0}, 0, 0, 0, 0, 0};
    frame.length = MIN(data.length, sizeof(frame.bytes));
    [data getBytes:frame.bytes length:frame.length];
    CFTimeInterval now = CACurrentMediaTime();
    os_unfair_lock_lock(&gPFBProbeChatLock);
    BOOL typing = gPFBProbeChatTypedAt > 0 && now - gPFBProbeChatTypedAt < kPFBProbeChatTypingWindow;
    gPFBProbeChatFrames++;
    gPFBProbeChatTypingFrames += typing ? 1 : 0;
    PFBProbeChatPrefix* slot = NULL;
    for (NSUInteger i = 0; i < gPFBProbeChatPrefixCount && !slot; i++) {
        PFBProbeChatPrefix* entry = &gPFBProbeChatPrefixes[i];
        if (entry->length == frame.length && memcmp(entry->bytes, frame.bytes, frame.length) == 0) {
            slot = entry;
        }
    }
    if (!slot && gPFBProbeChatPrefixCount < kPFBProbeChatPrefixLimit) {
        slot = &gPFBProbeChatPrefixes[gPFBProbeChatPrefixCount++];
        *slot = frame;
        slot->shortest = data.length;
        slot->longest = data.length;
    }
    if (slot) {
        slot->count++;
        slot->typing += typing ? 1 : 0;
        slot->shortest = MIN(slot->shortest, data.length);
        slot->longest = MAX(slot->longest, data.length);
    } else {
        gPFBProbeChatUnlisted++;
    }
    NSUInteger frames = gPFBProbeChatFrames;
    NSUInteger typingFrames = gPFBProbeChatTypingFrames;
    os_unfair_lock_unlock(&gPFBProbeChatLock);
    if (pfbIsTypingIndicatorFrame(data)) {
        pfbProbeChatNote(@"at the first typing match");
    } else if (frames >= kPFBProbeChatFrameLimit && typingFrames > 0) {
        pfbProbeChatNote(@"after 60 frames");
    }
}

// MARK: - Socket identity

static const void* kPFBChatSocketKey = &kPFBChatSocketKey;

static void pfbTagIfChatSocket(NSURLSessionWebSocketTask* task, NSURL* url) {
    if (task && pfbIsChatWebSocketURL(url)) {
        objc_setAssociatedObject(task, kPFBChatSocketKey, @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        pfbProbeChatWatchTyping();
    }
}

// MARK: - Send interception

// The websocket task's class is private, so its send is swizzled on the first
// instance seen rather than hooked by name.

typedef void (*PFBSendMessageIMP)(id, SEL, NSURLSessionWebSocketMessage*,
                                  void (^)(NSError*));
static PFBSendMessageIMP pfbOriginalSendMessage;

static void pfbSendMessageReplacement(id self, SEL _cmd,
                                      NSURLSessionWebSocketMessage* message,
                                      void (^completionHandler)(NSError*)) {
    BOOL onChatSocket = objc_getAssociatedObject(self, kPFBChatSocketKey) != nil;
    pfbProbeChatFrame(onChatSocket, message);
    if (onChatSocket && message.data) {
        // Any frame proves the chat channel passes here; a typing one only comes
        // while typing, which the path tour does not do.
        PFBCOMPAT_OBSERVE(PFBCompat_hide_typing_indicator, @"chat frame seen");
        if (pfbIsTypingIndicatorFrame(message.data) &&
            [PFBSettings boolForKey:@"hide_typing_indicator"]) {
            PFBCOMPAT_ACTION(PFBCompat_hide_typing_indicator, @"typing signal not sent");
            // Reported as sent: the caller keeps its own state machine intact.
            if (completionHandler) {
                completionHandler(nil);
            }
            return;
        }
    }
    pfbOriginalSendMessage(self, _cmd, message, completionHandler);
}

static void pfbSwizzleSendMessageIfNeeded(NSURLSessionWebSocketTask* task) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      Class taskClass = object_getClass(task);
      SEL selector = @selector(sendMessage:completionHandler:);
      Method method = class_getInstanceMethod(taskClass, selector);
      if (!method) {
          return;
      }
      pfbOriginalSendMessage = (PFBSendMessageIMP)method_getImplementation(method);
      method_setImplementation(method, (IMP)pfbSendMessageReplacement);
    });
}

// MARK: - Hooks

%hook NSURLSession

- (NSURLSessionWebSocketTask*)webSocketTaskWithURL:(NSURL*)url {
    NSURLSessionWebSocketTask* task = %orig;
    pfbSwizzleSendMessageIfNeeded(task);
    pfbTagIfChatSocket(task, url);
    return task;
}

- (NSURLSessionWebSocketTask*)webSocketTaskWithURL:(NSURL*)url
                                         protocols:(NSArray<NSString*>*)protocols {
    NSURLSessionWebSocketTask* task = %orig;
    pfbSwizzleSendMessageIfNeeded(task);
    pfbTagIfChatSocket(task, url);
    return task;
}

- (NSURLSessionWebSocketTask*)webSocketTaskWithRequest:(NSURLRequest*)request {
    NSURLSessionWebSocketTask* task = %orig;
    pfbSwizzleSendMessageIfNeeded(task);
    pfbTagIfChatSocket(task, request.URL);
    return task;
}

%end
