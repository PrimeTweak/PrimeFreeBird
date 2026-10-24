// A muted-words button in the Home timeline's top bar.

#import "Support/HookHelpers.h"
#import "Debug/PFBProbe.h"
#import "Features/Timelines/PFBMutedWordsViewController.h"

static const void* kPFBQuickMutedBtnKey = &kPFBQuickMutedBtnKey;

// The avatar is the square view furthest to the left of the bar. Using it as the
// reference makes the added button match Twitter's own vertical rhythm and
// horizontal margin, whatever the bar's height.
static UIView* pfbFindAvatarView(UIView* view, UIView* bar) {
    UIView* best = nil;
    CGFloat bestX = CGFLOAT_MAX;
    for (UIView* subview in view.subviews) {
        CGRect inBar = [subview convertRect:subview.bounds toView:bar];
        CGFloat w = CGRectGetWidth(inBar);
        CGFloat h = CGRectGetHeight(inBar);
        BOOL squarish = (w > 24.0 && w < 44.0 && fabs(w - h) < 2.0);
        if (squarish && CGRectGetMinX(inBar) < CGRectGetWidth(bar.bounds) * 0.25 &&
            CGRectGetMinX(inBar) < bestX) {
            bestX = CGRectGetMinX(inBar);
            best = subview;
        }
        UIView* deeper = pfbFindAvatarView(subview, bar);
        if (deeper) {
            CGRect deepRect = [deeper convertRect:deeper.bounds toView:bar];
            if (CGRectGetMinX(deepRect) < bestX) {
                bestX = CGRectGetMinX(deepRect);
                best = deeper;
            }
        }
    }
    return best;
}

// Measurement: the screens whose bar receives the button, one line per screen class.
static void pfbProbeQuickButtonOwner(UIViewController* owner) {
    static NSMutableSet<Class>* seen;
    Class kind = [owner class];
    if (!seen) {
        seen = [NSMutableSet set];
    }
    if (seen.count >= 12 || [seen containsObject:kind]) {
        return;
    }
    [seen addObject:kind];
    PFB_PROBE(@"Home bar button screens", 10, @"%@", NSStringFromClass(kind));
}

static BOOL pfbControllerIsHome(UIViewController* owner) {
    if (!owner) {
        return NO;
    }
    NSString* name = NSStringFromClass([owner class]);
    // Classes with the PFB prefix, the Timelines settings among them, are never Home.
    if ([name hasPrefix:@"PFB"]) {
        return NO;
    }
    return [name containsString:@"Home"] || [name containsString:@"Timelines"] ||
           [name containsString:@"TimelineContainer"];
}

// Twitter's filter_bars geometry, drawn at the settings gear's weight: three bars
// centered on x=12 on a 24-unit canvas, spans 3-21, 6-18 and 9-15. A block cannot
// capture a local C array, so the table lives at file scope.
static const CGFloat kPFBBarGeometry[3][3] = {
    {3.0, 21.0, 7.0}, {6.0, 18.0, 12.5}, {9.0, 15.0, 18.0}
};

static UIImage* PFBFilterBarsGlyph(void) {
    const CGFloat kUnit = 24.0;
    const CGFloat kThickness = 2.07;
    // The settings gear's side in the same bar.
    const CGFloat side = 27.33;
    CGFloat scale = side / kUnit;
    UIGraphicsImageRendererFormat* format =
        [UIGraphicsImageRendererFormat preferredFormat];
    format.opaque = NO;
    UIGraphicsImageRenderer* renderer =
        [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)
                                               format:format];
    UIImage* drawn = [renderer
        imageWithActions:^(UIGraphicsImageRendererContext* context) {
            [[UIColor blackColor] setFill];
            for (NSInteger i = 0; i < 3; i++) {
                CGRect bar =
                    CGRectMake(kPFBBarGeometry[i][0] * scale,
                               (kPFBBarGeometry[i][2] - kThickness / 2.0) * scale,
                               (kPFBBarGeometry[i][1] - kPFBBarGeometry[i][0]) * scale,
                               kThickness * scale);
                CGContextFillRect(context.CGContext, bar);
            }
        }];
    return drawn;
}

%hook TFNNavigationBar

%new
- (void)pfbShowQuickMutedWords:(id)sender {
    UIView* bar = (UIView*)self;
    UIViewController* owner = PFBOwningTopController(bar);
    if (!owner) {
        return;
    }
    while (owner.presentedViewController) {
        owner = owner.presentedViewController;
    }

    PFBMutedWordsViewController* editor = [[PFBMutedWordsViewController alloc] initCompact];
    editor.modalPresentationStyle = UIModalPresentationPopover;

    UIPopoverPresentationController* popover = editor.popoverPresentationController;
    popover.delegate = (id<UIPopoverPresentationControllerDelegate>)editor;
    popover.permittedArrowDirections = UIPopoverArrowDirectionUp;
    UIView* anchor = [sender isKindOfClass:[UIView class]] ? (UIView*)sender : bar;
    popover.sourceView = anchor;
    popover.sourceRect = anchor.bounds;

    [owner presentViewController:editor animated:YES completion:nil];
}

// A plain subview pinned to the trailing edge, re-positioned on every layout pass.
// Bar button items do not show in this container: the bar draws its contents
// through a full-width SwiftUI platter that can cover or ignore them.
- (void)layoutSubviews {
    %orig;

    @try {
        UIView* bar = (UIView*)self;
        if (!bar.window) {
            return;
        }

        UIButton* button = objc_getAssociatedObject(self, kPFBQuickMutedBtnKey);

        // Three states, not two, because TFNNavigationBar is reused across screens.
        // Owner known and home: create or maintain. Owner known and not home:
        // remove. Owner unknown, the chain being incomplete: change nothing.
        UIViewController* owner = PFBOwningTopController(bar);
        if (owner) {
            if (!pfbControllerIsHome(owner)) {
                if (button) {
                    [button removeFromSuperview];
                    objc_setAssociatedObject(self, kPFBQuickMutedBtnKey, nil,
                                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
                return;
            }
            pfbProbeQuickButtonOwner(owner);
        } else if (!button) {
            return;
        }
        if (!button) {
            // Twitter's filter_bars shape drawn at the gear's weight, repainted
            // through the same path so the color survives the window tint. Drawing
            // the shape here cannot come back empty, so no symbol fallback.
            UIImage* icon = PFBFlatGlyph(PFBFilterBarsGlyph(),
                                         PFBBarIconGray(bar.traitCollection));
            button = [UIButton buttonWithType:UIButtonTypeSystem];
            [button setImage:icon forState:UIControlStateNormal];

            button.contentMode = UIViewContentModeCenter;
            button.accessibilityLabel = [[PFBBundle sharedBundle] localizedStringForKey:@"FILTERS_TITLE"];
            [button addTarget:self
                          action:@selector(pfbShowQuickMutedWords:)
                forControlEvents:UIControlEventTouchUpInside];
            objc_setAssociatedObject(self, kPFBQuickMutedBtnKey, button,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (button.superview != bar) {
            [bar addSubview:button];
        }
        [bar bringSubviewToFront:button];

        // Re-asserted every pass, not just at creation: on a cold launch the
        // theme's window tint claims the icon until the first tab swipe. The icon
        // is baked in its gray, so a new gray (light or dark) repaints it.
        UIColor* gray = PFBBarIconGray(bar.traitCollection);
        if (![button.tintColor isEqual:gray]) {
            button.tintColor = gray;
            [button setImage:PFBFlatGlyph(PFBFilterBarsGlyph(), gray) forState:UIControlStateNormal];
        }

        // Aligned on the avatar rather than on the bar's box: the bar is taller
        // than its content, so centering in its bounds would leave the icon high.
        CGFloat side = 34.0;
        CGFloat inset = 16.0;
        CGFloat centerY = CGRectGetMidY(bar.bounds);
        UIView* avatar = pfbFindAvatarView(bar, bar);
        if (avatar) {
            CGRect inBar = [avatar convertRect:avatar.bounds toView:bar];
            centerY = CGRectGetMidY(inBar);
            side = CGRectGetHeight(inBar);
            inset = CGRectGetMinX(inBar);   // mirrors the left margin
        }
        button.frame = CGRectMake(CGRectGetWidth(bar.bounds) - side - inset,
                                  centerY - side / 2.0, side, side);
        PFBCompatReach(PFBCompatPath_home_bar_button);
    } @catch (id exception) {
    }
}

%end
