// Twitter's own pop-ups reached from the tweak: its Tray, its toast and its alerts.

#import "Support/PFBTwitterPopups.h"
#import <objc/runtime.h>
#import "Support/Helpers.h"
#import "Support/TFNHeaders.h"

static const void* kPFBToastActionKey = &kPFBToastActionKey;

// Twitter drops a toast of priority 0 when toasts come too fast, keeps one of priority 2 on screen
// until it is replaced, and replaces the toast on screen with one of higher priority. The tweak's
// start at 3, each above the one before it.
static const NSUInteger kPFBToastPersistent = 2;
static NSUInteger gPFBToastRank = kPFBToastPersistent;

BOOL PFBTrayAvailable(void) {
    Class sheetClass = objc_getClass("TFNMenuSheetViewController");
    return [objc_getClass("TFNActionItem") respondsToSelector:@selector(actionItemWithTitle:subtitle:imageName:action:)] &&
           [sheetClass instancesRespondToSelector:@selector(initWithTitle:actionItems:)] &&
           [sheetClass instancesRespondToSelector:@selector(tfn_presentFromViewController:animated:completion:)];
}

id PFBTrayRow(NSString* title, NSString* subtitle, NSString* iconName, BOOL disabled, void (^action)(void)) {
    if (!title.length || !PFBTrayAvailable()) {
        return nil;
    }
    Class rowClass = objc_getClass("TFNActionItem");
    TFNActionItem* row = [rowClass actionItemWithTitle:title subtitle:subtitle imageName:iconName action:action ?: ^{}];
    if (disabled && [row respondsToSelector:@selector(setDisabled:)]) {
        [row setDisabled:YES];
    }
    return row;
}

BOOL PFBPresentTray(UIViewController* from, NSString* title, NSArray* rows) {
    if (!from || rows.count == 0 || !PFBTrayAvailable()) {
        return NO;
    }
    Class sheetClass = objc_getClass("TFNMenuSheetViewController");
    TFNMenuSheetViewController* sheet = [[sheetClass alloc] initWithTitle:title actionItems:rows];
    // Twitter would turn a sheet raised from a prepared button into a system menu.
    if ([sheet respondsToSelector:@selector(setShouldPresentAsMenu:)]) {
        [sheet setShouldPresentAsMenu:NO];
    }
    [sheet tfn_presentFromViewController:from animated:YES completion:nil];
    return YES;
}

void PFBAfterPresentations(void (^block)(void)) {
    if (!block) {
        return;
    }
    __block NSUInteger looks = 0;
    __block void (^look)(void);
    look = ^{
        UIViewController* top = topMostController();
        BOOL moving = top.isBeingPresented || top.isBeingDismissed || top.transitionCoordinator != nil;
        // Twenty looks, a second in all, before running anyway.
        if (moving && looks++ < 20) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(),
                           look);
            return;
        }
        look = nil;
        block();
    };
    dispatch_async(dispatch_get_main_queue(), look);
}

// Twitter's information toast, given the button its protocol asks a toast for.
static Class PFBActionToastClass(void) {
    static Class actionToast;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class base = objc_getClass("TFNInformationToast");
        Class made = base ? objc_allocateClassPair(base, "PFBActionToast", 0) : Nil;
        if (!made) {
            return;
        }
        IMP button = imp_implementationWithBlock(^id(id toast) {
            return objc_getAssociatedObject(toast, kPFBToastActionKey);
        });
        class_addMethod(made, NSSelectorFromString(@"alternateAction"), button, "@@:");
        objc_registerClassPair(made);
        actionToast = made;
    });
    return actionToast;
}

static TFNToaster* PFBToaster(void) {
    Class toasterClass = objc_getClass("TFNToaster");
    TFNToaster* toaster = [toasterClass respondsToSelector:@selector(defaultToaster)] ? [toasterClass defaultToaster] : nil;
    return [toaster respondsToSelector:@selector(pushToast:withPriority:)] ? toaster : nil;
}

BOOL PFBPushTwitterToast(NSString* text, NSString* detail, PFBToastKind kind, NSString* actionTitle,
                         void (^action)(void), BOOL persistent) {
    Class toastClass = PFBActionToastClass();
    TFNToaster* toaster = PFBToaster();
    if (!text.length || !toaster ||
        ![toastClass instancesRespondToSelector:@selector(initWithMessageText:detailText:iconName:displayDuration:)]) {
        return NO;
    }
    TFNToastAction* button = nil;
    if (actionTitle.length && action) {
        Class actionClass = objc_getClass("TFNToastAction");
        if (![actionClass instancesRespondToSelector:@selector(initWithTitle:scribeAction:handler:)]) {
            return NO;
        }
        button = [[actionClass alloc] initWithTitle:actionTitle scribeAction:nil handler:action];
    }
    // Twitter's own success and error toasts, built by its own factories on the tweak's class.
    TFNInformationToast* toast = nil;
    if (kind == PFBToastKindSuccess && [toastClass respondsToSelector:@selector(successToastWithMessageText:detailText:)]) {
        toast = [toastClass successToastWithMessageText:text detailText:detail];
    } else if (kind == PFBToastKindError &&
               [toastClass respondsToSelector:@selector(errorToastWithMessageText:detailText:)]) {
        toast = [toastClass errorToastWithMessageText:text detailText:detail];
    }
    toast = toast ?: [[toastClass alloc] initWithMessageText:text detailText:detail iconName:nil displayDuration:0];
    if (![toast isKindOfClass:toastClass]) {
        return NO;
    }
    objc_setAssociatedObject(toast, kPFBToastActionKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (persistent) {
        PFBClearTwitterToasts();
    }
    [toaster pushToast:toast withPriority:persistent ? kPFBToastPersistent : ++gPFBToastRank];
    return YES;
}

void PFBClearTwitterToasts(void) {
    Class ours = PFBActionToastClass();
    TFNToaster* toaster = PFBToaster();
    if (!ours || ![toaster respondsToSelector:@selector(dequeueToastsPassingTest:)]) {
        return;
    }
    [toaster dequeueToastsPassingTest:^BOOL(id toast, __unused NSUInteger priority) {
        return [toast isKindOfClass:ours];
    }];
}

UIAlertAction* PFBAlertAddAction(UIAlertController* alert, NSString* title, UIAlertActionStyle style, BOOL twitter,
                                 void (^handler)(void)) {
    if (twitter && [alert respondsToSelector:@selector(tfn_addActionWithTitle:style:handler:)]) {
        id added = [alert tfn_addActionWithTitle:title style:style handler:handler ?: ^{}];
        return [added isKindOfClass:[UIAlertAction class]] ? added : alert.actions.lastObject;
    }
    UIAlertAction* action = [UIAlertAction actionWithTitle:title
                                                     style:style
                                                   handler:handler ? ^(__unused UIAlertAction* chosen) {
                                                       handler();
                                                   }
                                                                   : nil];
    [alert addAction:action];
    return action;
}

void PFBAlertPresent(UIAlertController* alert, UIViewController* from, BOOL twitter, void (^completion)(void)) {
    if (!alert || !from) {
        return;
    }
    if (twitter && [alert respondsToSelector:@selector(tfn_presentFromViewController:animated:completion:)]) {
        [alert tfn_presentFromViewController:from animated:YES completion:completion];
        return;
    }
    [from presentViewController:alert animated:YES completion:completion];
}
