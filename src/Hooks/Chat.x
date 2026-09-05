//
//  Chat.x
//  PrimeFreeBird
//
//  Chat privacy.
//
//  The typing indicator is pushed periodically over the chat websocket, which
//  also carries message delivery, receipts and presence — so the socket is left
//  alone and only the frame shape used by the typing heartbeat is dropped. That
//  shape is described on nfbIsTypingIndicatorFrame.
//
//  The read marker travels on the same socket, and its logic lives in a Kotlin
//  Multiplatform module (Subsystem_ios_iosArm64_main…), so no selector exists
//  to intercept it. Identifying its frame is the same exercise the typing
//  shape once was, and the recorder at the end of this file is what it takes:
//  with the debug switch on, every outgoing frame of the chat socket is logged
//  as hex, so the shape can be read from the log rather than guessed.
//

#import "HookHelpers.h"
#import <os/log.h>
#import <string.h>

// MARK: - Matching

static BOOL nfbIsChatWebSocketURL(NSURL* url) {
    NSString* host = url.host;
    return host.length > 0 && [host hasPrefix:@"chat-ws."];
}

// The typing heartbeat is a Thrift TBinaryProtocol struct whose first fields
// are fixed: a struct opener, field 1 as a struct, field 2 as a string of
// length zero. Ten bytes are enough to tell it apart from delivery, receipt
// and presence frames, which differ from the third byte on.
static const uint8_t kNFBTypingFramePrefix[] = {
    0x0c, 0x00, 0x01, 0x0b, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00
};

static BOOL nfbIsTypingIndicatorFrame(NSData* data) {
    if (data.length < sizeof(kNFBTypingFramePrefix)) {
        return NO;
    }
    return memcmp(data.bytes, kNFBTypingFramePrefix, sizeof(kNFBTypingFramePrefix)) == 0;
}

// MARK: - Socket identity

static const void* kNFBChatSocketKey = &kNFBChatSocketKey;

static void nfbTagIfChatSocket(NSURLSessionWebSocketTask* task, NSURL* url) {
    if (task && nfbIsChatWebSocketURL(url)) {
        objc_setAssociatedObject(task, kNFBChatSocketKey, @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

// MARK: - Recorder
//
// Off unless the debug switch is on. Prints the first sixteen bytes of every
// outgoing frame on the chat socket, which is what naming a new frame shape
// takes: open a conversation, read the log, compare the frames that appear on
// opening with those that appear while typing.

static void nfbLogChatFrame(NSData* data) {
    if (!data.length || ![BHTSettings boolForKey:@"debug_tools"]) {
        return;
    }
    static os_log_t log;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      log = os_log_create("com.primefreebird.chat", "frames");
    });
    NSUInteger shown = MIN(data.length, (NSUInteger)16);
    const uint8_t* bytes = data.bytes;
    NSMutableString* hex = [NSMutableString stringWithCapacity:shown * 3];
    for (NSUInteger i = 0; i < shown; i++) {
        [hex appendFormat:@"%02x ", bytes[i]];
    }
    os_log(log, "out %{public}lu bytes: %{public}@", (unsigned long)data.length, hex);
}

// MARK: - Send interception
//
// The websocket task's class is private, so its send is swizzled on the first
// instance seen rather than hooked by name.

typedef void (*NFBSendMessageIMP)(id, SEL, NSURLSessionWebSocketMessage*,
                                  void (^)(NSError*));
static NFBSendMessageIMP nfbOriginalSendMessage;

static void nfbSendMessageReplacement(id self, SEL _cmd,
                                      NSURLSessionWebSocketMessage* message,
                                      void (^completionHandler)(NSError*)) {
    BOOL onChatSocket = objc_getAssociatedObject(self, kNFBChatSocketKey) != nil;
    if (onChatSocket && message.data) {
        nfbLogChatFrame(message.data);
        if (nfbIsTypingIndicatorFrame(message.data) &&
            [BHTSettings boolForKey:@"hide_typing_indicator"]) {
            // Reported as sent: the caller keeps its own state machine intact.
            if (completionHandler) {
                completionHandler(nil);
            }
            return;
        }
    }
    nfbOriginalSendMessage(self, _cmd, message, completionHandler);
}

static void nfbSwizzleSendMessageIfNeeded(NSURLSessionWebSocketTask* task) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      Class taskClass = object_getClass(task);
      SEL selector = @selector(sendMessage:completionHandler:);
      Method method = class_getInstanceMethod(taskClass, selector);
      if (!method) {
          return;
      }
      nfbOriginalSendMessage = (NFBSendMessageIMP)method_getImplementation(method);
      method_setImplementation(method, (IMP)nfbSendMessageReplacement);
    });
}

// MARK: - Hooks

%hook NSURLSession

- (NSURLSessionWebSocketTask*)webSocketTaskWithURL:(NSURL*)url {
    NSURLSessionWebSocketTask* task = %orig;
    nfbSwizzleSendMessageIfNeeded(task);
    nfbTagIfChatSocket(task, url);
    return task;
}

- (NSURLSessionWebSocketTask*)webSocketTaskWithURL:(NSURL*)url
                                         protocols:(NSArray<NSString*>*)protocols {
    NSURLSessionWebSocketTask* task = %orig;
    nfbSwizzleSendMessageIfNeeded(task);
    nfbTagIfChatSocket(task, url);
    return task;
}

- (NSURLSessionWebSocketTask*)webSocketTaskWithRequest:(NSURLRequest*)request {
    NSURLSessionWebSocketTask* task = %orig;
    nfbSwizzleSendMessageIfNeeded(task);
    nfbTagIfChatSocket(task, request.URL);
    return task;
}

%end
