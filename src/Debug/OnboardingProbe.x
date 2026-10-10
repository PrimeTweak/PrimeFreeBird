// Measurement only, while recording: the onboarding subtasks that run, and for a
// permission prompt, its links, the way Twitter asks, the link followed and the iOS
// notification status. Prefix [nux].

#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import "Debug/PFBDebugger.h"

@interface ONBSubtaskController : NSObject
@end

@interface ONBPermissionPromptSubtaskController : ONBSubtaskController
@end

// An object getter reached by name, called only where it returns an object.
static id PFBNuxObject(id target, NSString* name) {
    SEL getter = NSSelectorFromString(name);
    if (![target respondsToSelector:getter] ||
        [target methodSignatureForSelector:getter].methodReturnType[0] != '@') {
        return nil;
    }
    return ((id (*)(id, SEL))objc_msgSend)(target, getter);
}

// An integer getter reached by name; -1 when the target has none.
static long PFBNuxInteger(id target, NSString* name) {
    SEL getter = NSSelectorFromString(name);
    if (![target respondsToSelector:getter]) {
        return -1;
    }
    char type = [target methodSignatureForSelector:getter].methodReturnType[0];
    if (type == 'q' || type == 'Q' || type == 'l' || type == 'L') {
        return ((long (*)(id, SEL))objc_msgSend)(target, getter);
    }
    if (type == 'i' || type == 'I') {
        return ((int (*)(id, SEL))objc_msgSend)(target, getter);
    }
    return -1;
}

static NSString* PFBNuxText(id value) {
    NSString* text = [value isKindOfClass:[NSString class]] ? value : [value description];
    if (!text.length) {
        return @"-";
    }
    return text.length > 80 ? [[text substringToIndex:80] stringByAppendingString:@"…"] : text;
}

// A navigation link as its id, label and type.
static NSString* PFBNuxLink(id link) {
    if (!link) {
        return @"none";
    }
    return [NSString stringWithFormat:@"%@ \"%@\" type %ld", PFBNuxText(PFBNuxObject(link, @"linkID")),
                                      PFBNuxText(PFBNuxObject(link, @"label")),
                                      PFBNuxInteger(link, @"type")];
}

// The block's type signature, from the blocks runtime, which tells whether a fix can
// call it.
static NSString* PFBNuxBlockSignature(id block) {
    if (!block) {
        return @"nil";
    }
    static const char* (*runtimeSignature)(void*);
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      runtimeSignature = (const char* (*)(void*))dlsym(RTLD_DEFAULT, "_Block_signature");
    });
    const char* signature = runtimeSignature ? runtimeSignature((__bridge void*)block) : NULL;
    return signature ? @(signature) : @"unknown";
}

static NSString* PFBNuxScreen(void) {
    for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }
        for (UIWindow* window in ((UIWindowScene*)scene).windows) {
            if (!window.isKeyWindow) {
                continue;
            }
            UIViewController* top = window.rootViewController;
            while (top.presentedViewController) {
                top = top.presentedViewController;
            }
            return top ? NSStringFromClass([top class]) : @"none";
        }
    }
    return @"no key window";
}

static void PFBNuxScreenSoon(NSString* subtask) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                     PFBDebugLog(@"[nux] %@: screen shown %@", subtask, PFBNuxScreen());
                   });
}

static NSString* PFBNuxName(id controller) {
    return [NSString stringWithFormat:@"%@ (%@)", NSStringFromClass([controller class]),
                                      PFBNuxText(PFBNuxObject(controller, @"subtaskID"))];
}

%hook ONBSubtaskController

- (void)startWithNavigationContext:(id)context navigationLink:(id)link {
    if (PFBDebugIsRecording()) {
        PFBDebugLog(@"[nux] subtask %@ starts", PFBNuxName(self));
    }
    %orig;
}

- (void)didActivateNavigationLink:(id)link {
    if (PFBDebugIsRecording() && [self isKindOfClass:%c(ONBPermissionPromptSubtaskController)]) {
        PFBDebugLog(@"[nux] %@ follows %@", PFBNuxName(self), PFBNuxLink(link));
    }
    %orig;
}

- (void)didActivateNavigationLink:(id)link listener:(id)listener {
    if (PFBDebugIsRecording() && [self isKindOfClass:%c(ONBPermissionPromptSubtaskController)]) {
        PFBDebugLog(@"[nux] %@ follows %@, with a listener", PFBNuxName(self), PFBNuxLink(link));
    }
    %orig;
}

%end

%hook ONBPermissionPromptSubtaskController

- (void)startWithNavigationContext:(id)context navigationLink:(id)link {
    if (PFBDebugIsRecording()) {
        NSString* name = PFBNuxName(self);
        Ivar ivar = class_getInstanceVariable([self class], "_subtask");
        id subtask = ivar ? object_getIvar(self, ivar) : nil;
        PFBDebugLog(@"[nux] permission %@ starts on %@ · subtask %@ style %ld · granted %@ · denied %@ · "
                    @"previously granted %@ · previously denied %@",
                    name, PFBNuxScreen(), subtask ? NSStringFromClass([subtask class]) : @"none",
                    PFBNuxInteger(subtask, @"style"), PFBNuxLink(PFBNuxObject(subtask, @"grantedLink")),
                    PFBNuxLink(PFBNuxObject(subtask, @"deniedLink")),
                    PFBNuxLink(PFBNuxObject(subtask, @"previouslyGrantedLink")),
                    PFBNuxLink(PFBNuxObject(subtask, @"previouslyDeniedLink")));
        [[UNUserNotificationCenter currentNotificationCenter]
            getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings* settings) {
              PFBDebugLog(@"[nux] %@: iOS notifications %ld (0 not asked, 1 denied, 2 allowed, "
                          @"3 provisional, 4 ephemeral)",
                          name, (long)settings.authorizationStatus);
            }];
        PFBNuxScreenSoon(name);
    }
    %orig;
}

- (void)private_showPrepromptWithStyle:(NSInteger)style okAction:(id)ok cancelAction:(id)cancel {
    if (PFBDebugIsRecording()) {
        PFBDebugLog(@"[nux] %@ preprompt style %ld · ok %@ · cancel %@", PFBNuxName(self), (long)style,
                    PFBNuxBlockSignature(ok), PFBNuxBlockSignature(cancel));
        PFBNuxScreenSoon(PFBNuxName(self));
    }
    %orig;
}

- (void)private_showAlertPrepromptWithOkAction:(id)ok cancelAction:(id)cancel {
    if (PFBDebugIsRecording()) {
        PFBDebugLog(@"[nux] %@ alert preprompt · ok %@ · cancel %@", PFBNuxName(self),
                    PFBNuxBlockSignature(ok), PFBNuxBlockSignature(cancel));
        PFBNuxScreenSoon(PFBNuxName(self));
    }
    %orig;
}

- (void)private_showComponentsCoverPrepromptWithOkAction:(id)ok cancelAction:(id)cancel {
    if (PFBDebugIsRecording()) {
        PFBDebugLog(@"[nux] %@ cover preprompt · ok %@ · cancel %@", PFBNuxName(self),
                    PFBNuxBlockSignature(ok), PFBNuxBlockSignature(cancel));
        PFBNuxScreenSoon(PFBNuxName(self));
    }
    %orig;
}

- (void)private_requestAuthorizationWithStyle:(NSInteger)style
                                   forceGrant:(BOOL)forceGrant
                                 forceDecline:(BOOL)forceDecline {
    if (PFBDebugIsRecording()) {
        PFBDebugLog(@"[nux] %@ asks iOS · style %ld · force grant %d · force decline %d", PFBNuxName(self),
                    (long)style, forceGrant, forceDecline);
    }
    %orig;
}

- (void)private_requestOneStepAuthorizationWithAccount:(id)account {
    if (PFBDebugIsRecording()) {
        PFBDebugLog(@"[nux] %@ asks iOS in one step", PFBNuxName(self));
    }
    %orig;
}

%end
