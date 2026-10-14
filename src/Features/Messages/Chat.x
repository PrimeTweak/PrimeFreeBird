// Chat privacy: drops the typing-indicator frame from the chat websocket and
// leaves the rest of the socket alone.

#import "Support/HookHelpers.h"
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

// MARK: - Socket identity

static const void* kPFBChatSocketKey = &kPFBChatSocketKey;

static void pfbTagIfChatSocket(NSURLSessionWebSocketTask* task, NSURL* url) {
    if (task && pfbIsChatWebSocketURL(url)) {
        objc_setAssociatedObject(task, kPFBChatSocketKey, @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
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
