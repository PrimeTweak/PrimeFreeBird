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

// FLEX showed the settings gear is a plain UIImageView, not a button — which
// is why tinting buttons alone did nothing. Both are handled here, and only in
// the right-hand part of the bar: the avatar and the search field stay put.
static void nfbTintIconButtons(UIView* view, UIView* bar, UIColor* grey) {
    for (UIView* subview in view.subviews) {
        CGRect inBar = [subview convertRect:subview.bounds toView:bar];
        BOOL onTheRight = CGRectGetMidX(inBar) > CGRectGetWidth(bar.bounds) * 0.6;

        if (onTheRight && [subview isKindOfClass:[UIButton class]]) {
            UIButton* button = (UIButton*)subview;
            if (button.currentImage && button.currentTitle.length == 0 &&
                ![button.tintColor isEqual:grey]) {
                button.tintColor = grey;
            }
        } else if (onTheRight && [subview isKindOfClass:[UIImageView class]]) {
            UIImageView* imageView = (UIImageView*)subview;
            CGFloat side = CGRectGetWidth(inBar);
            // Glyph-sized only: leaves photos and banners alone.
            if (imageView.image && side > 14.0 && side < 34.0 &&
                ![imageView.tintColor isEqual:grey]) {
                // Force template rendering, otherwise the tint is ignored.
                if (imageView.image.renderingMode != UIImageRenderingModeAlwaysTemplate) {
                    imageView.image = [imageView.image
                        imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
                }
                imageView.tintColor = grey;
            }
        }
        nfbTintIconButtons(subview, bar, grey);
    }
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

        // Twitter also puts glyphs in an accessory view rather than in bar
        // button items, and those keep their own colour. Walk the right-hand
        // side of the bar and tint the icon buttons found there: image-only
        // buttons past the middle. A text button like "Cancel" has a title and
        // is skipped; the avatar sits on the left and never matches.
        nfbTintIconButtons(bar, bar, grey);
    } @catch (id exception) {
    }
}

%end
