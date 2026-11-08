// The Filters button in the Home timeline's top bar.

#import "Support/HookHelpers.h"
#import "Features/Timelines/PFBMutedWordsViewController.h"

static const void* kPFBQuickMutedBtnKey = &kPFBQuickMutedBtnKey;
static const void* kPFBQuickMutedColorKey = &kPFBQuickMutedColorKey;
static const void* kPFBQuickMutedItemKey = &kPFBQuickMutedItemKey;

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

// The muted words editor as a popover from `anchor`, its arrow on `rect`.
static void pfbPresentQuickMutedWords(UIViewController* owner, UIView* anchor, CGRect rect) {
    if (!owner || !anchor) {
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
    popover.sourceView = anchor;
    popover.sourceRect = rect;

    [owner presentViewController:editor animated:YES completion:nil];
}

%hook TFNNavigationBar

%new
- (void)pfbShowQuickMutedWords:(id)sender {
    UIView* bar = (UIView*)self;
    UIView* anchor = [sender isKindOfClass:[UIView class]] ? (UIView*)sender : bar;
    pfbPresentQuickMutedWords(PFBOwningTopController(bar), anchor, anchor.bounds);
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
        } else if (!button) {
            return;
        }
        if (!button) {
            // Twitter's filter_bars shape at the gear's weight, painted in the bar's icon color so the
            // window tint cannot recolor it.
            UIImage* icon = PFBFlatGlyph(PFBFilterBarsGlyph(),
                                         PFBBarIconColor(bar.traitCollection));
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
        // is baked in its color, so a new color (light or dark) repaints it.
        UIColor* color = PFBBarIconColor(bar.traitCollection);
        if (![button.tintColor isEqual:color]) {
            button.tintColor = color;
            [button setImage:PFBFlatGlyph(PFBFilterBarsGlyph(), color) forState:UIControlStateNormal];
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

@interface _TtC32TwitterHomeFeatureImplementation35HomeTimelineContainerViewController : UIViewController
- (void)pfbShowQuickMutedWordsFrom:(PFBBarGlyphButton*)sender;
@end

// On Twitter's native glass stack the top bar draws the screen's navigation item, so
// there the button is a bar item of Home, placed again once the screen is up since
// Twitter may set its own items after it appears.
static void pfbPlaceHomeFiltersItem(UIViewController* home) {
    if (!PFBOnNativeGlassStack(home)) {
        return;
    }
    @try {
        UINavigationItem* item = home.navigationItem;
        if (!item) {
            return;
        }
        PFBCompatReach(PFBCompatPath_home_bar_button);
        UIColor* color = PFBBarIconColor(home.traitCollection);
        UIBarButtonItem* button = objc_getAssociatedObject(home, kPFBQuickMutedBtnKey);
        if (!button) {
            button = PFBBarGlyphItem(PFBFlatGlyph(PFBFilterBarsGlyph(), color),
                                     [[PFBBundle sharedBundle] localizedStringForKey:@"FILTERS_TITLE"], home,
                                     @selector(pfbShowQuickMutedWordsFrom:));
            objc_setAssociatedObject(home, kPFBQuickMutedBtnKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        } else if (![objc_getAssociatedObject(button, kPFBQuickMutedColorKey) isEqual:color]) {
            // The glyph carries its color, so a new color (light or dark) redraws it.
            PFBBarGlyphButton* view = (PFBBarGlyphButton*)button.customView;
            if ([view isKindOfClass:[PFBBarGlyphButton class]]) {
                view.glyph = PFBFlatGlyph(PFBFilterBarsGlyph(), color);
            }
        }
        objc_setAssociatedObject(button, kPFBQuickMutedColorKey, color, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        // The item keeps the button, so Twitter setting its own right items puts it back.
        objc_setAssociatedObject(item, kPFBQuickMutedItemKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (![item.rightBarButtonItems containsObject:button]) {
            item.rightBarButtonItems = [(item.rightBarButtonItems ?: @[]) arrayByAddingObject:button];
        }
    } @catch (id exception) {
    }
}

// Twitter sets Home's right items as a whole once the screen is up, which drops the Filters
// button: it is kept among the items Twitter sets.
static NSArray* pfbHomeItemsKeepingFilters(UINavigationItem* item, NSArray* items) {
    UIBarButtonItem* button = objc_getAssociatedObject(item, kPFBQuickMutedItemKey);
    if (!button || [items containsObject:button]) {
        return items;
    }
    PFBCOMPAT_ACTION(PFBCompat_muted_words, @"Home bar button put back");
    return [(items ?: @[]) arrayByAddingObject:button];
}

%hook UINavigationItem

- (void)setRightBarButtonItems:(NSArray*)items {
    %orig(pfbHomeItemsKeepingFilters(self, items));
}

- (void)setRightBarButtonItems:(NSArray*)items animated:(BOOL)animated {
    %orig(pfbHomeItemsKeepingFilters(self, items), animated);
}

%end

%hook _TtC32TwitterHomeFeatureImplementation35HomeTimelineContainerViewController

%new
- (void)pfbShowQuickMutedWordsFrom:(PFBBarGlyphButton*)sender {
    pfbPresentQuickMutedWords((UIViewController*)self, sender, sender.glyphFrame);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    pfbPlaceHomeFiltersItem((UIViewController*)self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    pfbPlaceHomeFiltersItem((UIViewController*)self);
}

%end
