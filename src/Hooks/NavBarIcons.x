//
//  NavBarIcons.x
//  PrimeFreeBird
//
//  Twitter draws the settings gear at full label strength on Explore and
//  Notifications, which reads as black next to the muted grey of the tab
//  labels beside it. This tints the right-hand bar buttons of those two
//  screens to the same secondary grey.
//
//  Scoped on purpose: TFNNavigationBar is used by every screen, so the tint is
//  applied only when the bar belongs to Explore or Notifications. Anywhere
//  else — profiles, messages, the home timeline — nothing is touched.
//
//  Note: QuickMutedWords.x also hooks TFNNavigationBar's layoutSubviews, for
//  the home bar. Logos chains both, and the two never act on the same screen.
//

#import "HookHelpers.h"

// Nearest view controller above a view, unwrapping a navigation controller to
// the screen it is actually showing.
static UIViewController* nfbBarOwningController(UIView* view) {
    UIResponder* responder = view;
    while ((responder = responder.nextResponder)) {
        if (![responder isKindOfClass:[UIViewController class]]) {
            continue;
        }
        UIViewController* controller = (UIViewController*)responder;
        if ([controller isKindOfClass:[UINavigationController class]]) {
            UIViewController* top = ((UINavigationController*)controller).topViewController;
            return top ?: controller;
        }
        return controller;
    }
    return nil;
}

%hook TFNNavigationBar

- (void)layoutSubviews {
    %orig;

    @try {
        UIView* bar = (UIView*)self;
        if (!bar.window) {
            return;
        }

        UIViewController* owner = nfbBarOwningController(bar);
        if (!owner) {
            return;
        }
        NSString* name = NSStringFromClass([owner class]);
        // Explore is the guide container; Notifications keeps its name.
        BOOL isTintedScreen = [name containsString:@"GuideContainer"] ||
                              [name containsString:@"Notifications"] ||
                              [name containsString:@"ActivityHistory"];
        if (!isTintedScreen) {
            return;
        }

        // The class isn't declared in our headers, so the top item goes
        // through an id handle rather than a typed message to self.
        id navigationBar = self;
        if (![navigationBar respondsToSelector:@selector(topItem)]) {
            return;
        }
        UINavigationItem* item =
            ((id (*)(id, SEL))objc_msgSend)(navigationBar, @selector(topItem));
        if (!item) {
            return;
        }

        UIColor* grey = [UIColor secondaryLabelColor];
        for (UIBarButtonItem* button in item.rightBarButtonItems) {
            if (![button.tintColor isEqual:grey]) {
                button.tintColor = grey;
            }
        }
    } @catch (id exception) {
    }
}

%end
