// A muted-words shortcut in the Home timeline's top bar, added only to the bar the
// Home timeline owns; if that owner cannot be identified, no button appears.

#import "Support/HookHelpers.h"
#import "Features/Timelines/PFBMutedWordsViewController.h"
#import "Debug/PFBDebugger.h"
#import "Debug/PFBProbe.h"
#import <mach/mach_time.h>

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

static UIViewController* pfbOwningViewController(UIView* view) {
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

static BOOL pfbControllerIsHome(UIViewController* owner) {
    if (!owner) {
        return NO;
    }
    NSString* name = NSStringFromClass([owner class]);
    // PrimeFreeBird's own pages, its Timelines settings among them, are never Home.
    if ([name hasPrefix:@"PFB"]) {
        return NO;
    }
    return [name containsString:@"Home"] || [name containsString:@"Timelines"] ||
           [name containsString:@"TimelineContainer"];
}

// One gray for every icon added here, frozen to a static color. The gear is dimmed
// to 60 % because its glyph refuses to be tinted, so these icons use the label
// color at the same 60 %. Resolving it here also keeps the window tint off it.
static UIColor* PFBBarIconGrey(UITraitCollection* traits) {
    // Resolved to a concrete color: Twitter's vector renderer turns a dynamic one
    // black, and the theme would claim it later.
    UIColor* grey = [[UIColor labelColor] colorWithAlphaComponent:0.6];
    if (traits && [grey respondsToSelector:@selector(resolvedColorWithTraitCollection:)]) {
        return [grey resolvedColorWithTraitCollection:traits] ?: grey;
    }
    return grey;
}

// Twitter's filter_bars geometry, drawn at the settings gear's weight: three bars
// centered on x=12 on a 24-unit canvas, spans 3-21, 6-18 and 9-15. A block cannot
// capture a local C array, so the table lives at file scope.
static const CGFloat kPFBBarGeometry[3][3] = {
    {3.0, 21.0, 7.0}, {6.0, 18.0, 12.5}, {9.0, 15.0, 18.0}
};

static UIImage* PFBFilterBarsGlyph(CGFloat side) {
    const CGFloat kUnit = 24.0;
    const CGFloat kThickness = 2.07;
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

// Probe: milliseconds from mach_absolute_time ticks.
static double pfbProbeMs(uint64_t ticks) {
    static mach_timebase_info_data_t timebase;
    if (!timebase.denom) {
        mach_timebase_info(&timebase);
    }
    return (double)ticks * (double)timebase.numer / (double)timebase.denom / 1e6;
}

// Probe 09#F063: the time each layout pass of a bar takes during the first full tour run to its
// end, noted then. A pass that notes a probe line is counted, not timed.
static int gPFBProbeBarState;   // 0 not read yet, 1 open, 2 closed
static BOOL gPFBProbeBarNoted;
static BOOL gPFBProbeBarButtonPass;
static struct {
    NSUInteger passes, buttonPasses, timed;
    uint64_t start, ticks, longest;
} gPFBProbeBar;

static void pfbProbeBarTourEnded(void) {
    if (gPFBProbeBarState != 1 || !gPFBProbeBar.start) {
        return;
    }
    // A tour stopped early or not full is left out; the next one is measured afresh.
    if (![PFBCompatTourLastRun() hasPrefix:@"Full tour"]) {
        memset(&gPFBProbeBar, 0, sizeof(gPFBProbeBar));
        return;
    }
    gPFBProbeBarState = 2;
    double tour = pfbProbeMs(mach_absolute_time() - gPFBProbeBar.start) / 1000.0;
    double total = pfbProbeMs(gPFBProbeBar.ticks);
    PFBProbeNote(@"09#F063 home bar",
                 @"09#F063 layout during the tour (%.0f s): Home bar button %lu passes (%lu placing the button), "
                 @"%.1f ms over %lu timed (%.2f%%), longest %.0f µs",
                 tour, (unsigned long)gPFBProbeBar.passes, (unsigned long)gPFBProbeBar.buttonPasses, total,
                 (unsigned long)gPFBProbeBar.timed, tour > 0 ? total / (tour * 10.0) : 0.0,
                 pfbProbeMs(gPFBProbeBar.longest) * 1000.0);
}

static uint64_t pfbProbeBarPassBegin(void) {
    if (gPFBProbeBarState == 2) {
        return 0;
    }
    if (gPFBProbeBarState == 0) {
        if (!PFBProbeWants(@"09#F063 home bar")) {
            gPFBProbeBarState = 2;
            return 0;
        }
        gPFBProbeBarState = 1;
        [[NSNotificationCenter defaultCenter] addObserverForName:PFBProbeTourEndedNotification
                                                          object:nil
                                                           queue:nil
                                                      usingBlock:^(__unused NSNotification* note) {
                                                        pfbProbeBarTourEnded();
                                                      }];
    }
    if (!PFBCompatTourIsRunning() || !NSThread.isMainThread) {
        return 0;
    }
    if (!gPFBProbeBar.start) {
        gPFBProbeBar.start = mach_absolute_time();
    }
    gPFBProbeBarNoted = NO;
    gPFBProbeBarButtonPass = NO;
    return mach_absolute_time();
}

static void pfbProbeBarPassEnd(uint64_t* start) {
    if (!*start) {
        return;
    }
    uint64_t ticks = mach_absolute_time() - *start;
    gPFBProbeBar.passes++;
    if (gPFBProbeBarButtonPass) {
        gPFBProbeBar.buttonPasses++;
    }
    if (gPFBProbeBarNoted) {
        return;
    }
    gPFBProbeBar.timed++;
    gPFBProbeBar.ticks += ticks;
    gPFBProbeBar.longest = MAX(gPFBProbeBar.longest, ticks);
}

// Probe 09#F021: the owners whose bar shows the button, once per build each, at most 8.
static BOOL gPFBProbeOwnersDone;
static Class gPFBProbeOwnerLast;
static NSUInteger gPFBProbeOwnersNoted;

static void pfbProbeBarOwner(UIViewController* owner) {
    if (gPFBProbeOwnersDone || !owner) {
        return;
    }
    Class ownerClass = [owner class];
    if (ownerClass == gPFBProbeOwnerLast) {
        return;
    }
    if (!PFBDebugIsRecording() || gPFBProbeOwnersNoted >= 8) {
        gPFBProbeOwnersDone = YES;
        return;
    }
    gPFBProbeOwnerLast = ownerClass;
    NSString* name = NSStringFromClass(ownerClass);
    NSString* key = [@"09#F021 " stringByAppendingString:name];
    if (PFBProbeWants(key)) {
        gPFBProbeOwnersNoted++;
        gPFBProbeBarNoted = YES;
        PFBProbeNote(key, @"09#F021 muted words button on the bar of %@", name);
    }
}

// Probe 09#F038: the button's place against the avatar, once per layout direction, read once
// per launch when the bar has settled: an avatar found, or the tenth pass placing the button.
static BOOL gPFBProbeDirectionDone;
static NSUInteger gPFBProbeDirectionPasses;

// Probe: the square view furthest right in the bar's last quarter, the button aside: where a
// mirrored bar would put the avatar.
static UIView* pfbProbeRightSquare(UIView* view, UIView* bar, UIView* button) {
    UIView* best = nil;
    CGFloat bestMaxX = -CGFLOAT_MAX;
    for (UIView* subview in view.subviews) {
        if (subview == button) {
            continue;
        }
        CGRect inBar = [subview convertRect:subview.bounds toView:bar];
        CGFloat w = CGRectGetWidth(inBar);
        if (w > 24.0 && w < 44.0 && fabs(w - CGRectGetHeight(inBar)) < 2.0 &&
            CGRectGetMaxX(inBar) > CGRectGetWidth(bar.bounds) * 0.75 && CGRectGetMaxX(inBar) > bestMaxX) {
            bestMaxX = CGRectGetMaxX(inBar);
            best = subview;
        }
        UIView* deeper = pfbProbeRightSquare(subview, bar, button);
        if (deeper) {
            CGFloat deepMaxX = CGRectGetMaxX([deeper convertRect:deeper.bounds toView:bar]);
            if (deepMaxX > bestMaxX) {
                bestMaxX = deepMaxX;
                best = deeper;
            }
        }
    }
    return best;
}

static NSString* pfbProbeSpan(CGRect frame) {
    return [NSString stringWithFormat:@"%.0f-%.0f", CGRectGetMinX(frame), CGRectGetMaxX(frame)];
}

static void pfbProbeBarDirection(UIView* bar, UIButton* button, UIView* avatar) {
    if (gPFBProbeDirectionDone || !NSThread.isMainThread) {
        return;
    }
    if (!PFBDebugIsRecording()) {
        gPFBProbeDirectionDone = YES;
        return;
    }
    if (!avatar && ++gPFBProbeDirectionPasses < 10) {
        return;
    }
    gPFBProbeDirectionDone = YES;
    BOOL rtl = bar.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    NSString* key = rtl ? @"09#F038 RTL" : @"09#F038 LTR";
    if (!PFBProbeWants(key)) {
        return;
    }
    CGRect avatarFrame = avatar ? [avatar convertRect:avatar.bounds toView:bar] : CGRectNull;
    UIView* right = pfbProbeRightSquare(bar, bar, button);
    CGRect rightFrame = right ? [right convertRect:right.bounds toView:bar] : CGRectNull;
    BOOL overlap = (avatar && CGRectIntersectsRect(button.frame, avatarFrame)) ||
                   (right && CGRectIntersectsRect(button.frame, rightFrame));
    gPFBProbeBarNoted = YES;
    PFBProbeNote(key, @"09#F038 %@ bar width %.0f: avatar %@, right-side square %@, button %@, overlap %@",
                 rtl ? @"RTL" : @"LTR", CGRectGetWidth(bar.bounds), avatar ? pfbProbeSpan(avatarFrame) : @"none",
                 right ? pfbProbeSpan(rightFrame) : @"none", pfbProbeSpan(button.frame), overlap ? @"yes" : @"no");
}

// Probe: marks a pass that places the button, then notes for 09#F021 and 09#F038.
static void pfbProbeBarButton(UIView* bar, UIViewController* owner, UIButton* button, UIView* avatar) {
    if (gPFBProbeBarState == 1) {
        gPFBProbeBarButtonPass = YES;
    }
    pfbProbeBarOwner(owner);
    pfbProbeBarDirection(bar, button, avatar);
}

%hook TFNNavigationBar

%new
- (void)pfbShowQuickMutedWords:(id)sender {
    UIView* bar = (UIView*)self;
    UIViewController* owner = pfbOwningViewController(bar);
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
    // Probe: times this pass for 09#F063; the cleanup runs on every return.
    uint64_t probeStart __attribute__((cleanup(pfbProbeBarPassEnd))) = pfbProbeBarPassBegin();

    @try {
        UIView* bar = (UIView*)self;
        if (!bar.window) {
            return;
        }

        UIButton* button = objc_getAssociatedObject(self, kPFBQuickMutedBtnKey);

        // Three states, not two, because TFNNavigationBar is reused across screens.
        // Owner known and home: create or maintain. Owner known and not home:
        // remove. Owner unknown, the chain being incomplete: change nothing.
        UIViewController* owner = pfbOwningViewController(bar);
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
            // Twitter's filter_bars shape drawn at the gear's weight, repainted
            // through the same path so the color survives the window tint. Drawing
            // the shape here cannot come back empty, so no symbol fallback.
            UIImage* icon = PFBFlatGlyph(PFBFilterBarsGlyph(27.33),
                                         PFBBarIconGrey(bar.traitCollection));
            button = [UIButton buttonWithType:UIButtonTypeSystem];
            [button setImage:icon forState:UIControlStateNormal];

            button.contentMode = UIViewContentModeCenter;
            button.accessibilityLabel = [[PFBBundle sharedBundle] localizedStringForKey:@"QUICK_MUTED_WORDS_LABEL"];
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
        // theme's window tint claims the icon until the first tab swipe.
        UIColor* grey = PFBBarIconGrey(bar.traitCollection);
        if (![button.tintColor isEqual:grey]) {
            button.tintColor = grey;
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
        // Probe: notes the owner and the button's place, for 09#F021 and 09#F038.
        pfbProbeBarButton(bar, owner, button, avatar);
    } @catch (id exception) {
    }
}

%end
