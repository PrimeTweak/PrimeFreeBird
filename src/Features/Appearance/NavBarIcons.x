// Navigation bars and their glyphs: bar buttons off UIKit's shared glass, the Done item
// styled, gear, back-arrow and chat-bar glyphs repainted, the reply bar's glass, the inbox
// pill held opaque, logo and tab icons free of vibrancy, avatars as pictures, the damper.

#import "Support/HookHelpers.h"
#import "Debug/PFBDebugger.h"
#import "Debug/PFBProbe.h"
#import <QuartzCore/QuartzCore.h>
#import <mach/mach_time.h>
#import <pthread.h>

static const void* kPFBGreyedImageKey = &kPFBGreyedImageKey;
// Holds the color forced on a taken-over view, so any image set later goes
// through the same repaint.
static const void* kPFBGreyTargetKey = &kPFBGreyTargetKey;
// The untouched glyph. Repainting is not idempotent — a color at 60% opacity
// laid over a color already at 60% lands at 36% — so every repaint starts
// from this original.
static const void* kPFBOriginalImageKey = &kPFBOriginalImageKey;
// Marks a repainted image. Two paths repaint on Notifications, and without the mark
// each treats the other's result as unpainted; the mark travels with the image.
static const void* kPFBPaintedFlagKey = &kPFBPaintedFlagKey;
// Marks a layer that must never render at partial opacity. Correcting afterwards
// is too late, so every route that could lower it is refused as it is used: the
// alpha, the layer's opacity and the animation.
static const void* kPFBNoFadeKey = &kPFBNoFadeKey;

// Probe: microseconds in a span of mach ticks.
static double pfbProbeMicros(uint64_t ticks) {
    static mach_timebase_info_data_t timebase;
    if (timebase.denom == 0) {
        mach_timebase_info(&timebase);
    }
    return (double)ticks * timebase.numer / timebase.denom / 1000.0;
}

// Probe: runs a block on the main thread when a full compatibility tour ends; a cancelled or
// remaining-only tour, which has no probe passages, leaves the measurement open.
static void pfbOnTourEndProbe(dispatch_block_t block) {
    [[NSNotificationCenter defaultCenter] addObserverForName:PFBProbeTourEndedNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification* note) {
                                                      if ([PFBCompatTourLastRun() hasPrefix:@"Full tour"]) {
                                                          block();
                                                      }
                                                  }];
}

// One gray for every added or recolored icon: the label color at 60%, resolved
// to a concrete value so nothing can re-resolve it later.
static UIColor* PFBBarIconGrey(UITraitCollection* traits) {
    UIColor* grey = [[UIColor labelColor] colorWithAlphaComponent:0.6];
    if (traits && [grey respondsToSelector:@selector(resolvedColorWithTraitCollection:)]) {
        return [grey resolvedColorWithTraitCollection:traits] ?: grey;
    }
    return grey;
}

// Repaints a glyph into a flat bitmap of the given color.
static UIImage* PFBGreyGlyph(UIImage* source, UIColor* colour) {
    if (!source || !colour) {
        return source;
    }
    CGSize size = source.size;
    if (size.width < 1.0 || size.height < 1.0) {
        return source;
    }
    UIGraphicsImageRendererFormat* format = [UIGraphicsImageRendererFormat preferredFormat];
    format.opaque = NO;
    format.scale = source.scale;
    UIGraphicsImageRenderer* renderer =
        [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
    UIImage* painted = [renderer
        imageWithActions:^(UIGraphicsImageRendererContext* context) {
            CGRect rect = CGRectMake(0.0, 0.0, size.width, size.height);
            [source drawInRect:rect];
            CGContextSetBlendMode(context.CGContext, kCGBlendModeSourceIn);
            [colour setFill];
            CGContextFillRect(context.CGContext, rect);
        }];
    UIImage* result = [painted imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    objc_setAssociatedObject(result, kPFBPaintedFlagKey, @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return result;
}

// The same painter, exported for the other files.
UIImage* PFBPaintedGlyph(UIImage* source, UIColor* colour) {
    return PFBGreyGlyph(source, colour);
}

static UIViewController* pfbBarOwningController(UIView* view);
static BOOL pfbLooksLikeSettingsButton(UIView* view);

// Probe: notes a repainted gear asked for another color, the case no repaint branch
// takes (07#F040, per path), and an image view still showing its repaint in the older
// color a second later (07#F018).
static const void* kPFBStaleGearProbeKey = &kPFBStaleGearProbeKey;
static BOOL gPFBStaleGearProbeDone;
static BOOL gPFBStaleGearProbeNoted[3];

static void pfbStaleGearProbe(UIView* view, BOOL showsOurs, UIColor* painted,
                              UIColor* wanted, BOOL barItem) {
    if (!PFBDebugIsRecording()) {
        gPFBStaleGearProbeDone = YES;
        return;
    }
    if (!NSThread.isMainThread) {
        return;
    }
    NSUInteger slot = barItem ? 1 : 0;
    if (!gPFBStaleGearProbeNoted[slot]) {
        gPFBStaleGearProbeNoted[slot] = YES;
        NSString* key = barItem ? @"07#F040 bar item" : @"07#F040 image view";
        if (PFBProbeWants(key)) {
            PFBProbeNote(key, @"07#F040 gear kept its old color: painted %@, wanted %@, %@ path on %@",
                         PFBProbeColor(painted, nil), PFBProbeColor(wanted, nil),
                         barItem ? @"bar item" : @"image view",
                         PFBProbeScreenName(pfbBarOwningController(view)));
        }
    }
    if (!barItem && showsOurs && !gPFBStaleGearProbeNoted[2]) {
        NSArray* seen = objc_getAssociatedObject(view, kPFBStaleGearProbeKey);
        CFTimeInterval now = CACurrentMediaTime();
        if (![seen.lastObject isEqual:wanted]) {
            objc_setAssociatedObject(view, kPFBStaleGearProbeKey, @[ @(now), wanted ],
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        } else if (now - [seen.firstObject doubleValue] >= 1.0) {
            gPFBStaleGearProbeNoted[2] = YES;
            if (PFBProbeWants(@"07#F018")) {
                PFBProbeNote(@"07#F018", @"07#F018 gear stale color: painted %@ wanted %@, seen again after %.1f s on %@",
                             PFBProbeColor(painted, nil), PFBProbeColor(wanted, nil),
                             now - [seen.firstObject doubleValue],
                             PFBProbeScreenName(pfbBarOwningController(view)));
            }
        }
    }
    gPFBStaleGearProbeDone =
        gPFBStaleGearProbeNoted[0] && gPFBStaleGearProbeNoted[1] && gPFBStaleGearProbeNoted[2];
}

// Probe: counts the repaints and restores of the Notifications gear's two paths, and of
// Explore's gear, and notes them when a tour ends.
static int gPFBGearPathProbeState;
static NSUInteger gPFBGearPathProbeCounts[6];

static BOOL pfbGearPathProbeOpen(void) {
    if (!NSThread.isMainThread) {
        return NO;
    }
    if (gPFBGearPathProbeState == 0) {
        gPFBGearPathProbeState = PFBProbeWants(@"07#F059 counts") ? 1 : 2;
        if (gPFBGearPathProbeState == 1) {
            pfbOnTourEndProbe(^{
                NSUInteger* counts = gPFBGearPathProbeCounts;
                if (PFBProbeWants(@"07#F059 counts")) {
                    PFBProbeNote(@"07#F059 counts",
                                 @"07#F059 Notifications gear: bar item path %lu repaints / %lu restores, "
                                 @"image view path %lu / %lu; Explore gear %lu / %lu (since launch)",
                                 (unsigned long)counts[0], (unsigned long)counts[1],
                                 (unsigned long)counts[2], (unsigned long)counts[3],
                                 (unsigned long)counts[4], (unsigned long)counts[5]);
                }
                gPFBGearPathProbeState = 2;
            });
        }
    }
    return gPFBGearPathProbeState == 1;
}

// The image view path runs for Explore's gear too: a glyph under the settings button is
// Explore's, any other one the Notifications path's.
static void pfbGearPathProbe(UIView* view, BOOL repaint, BOOL barItem) {
    if (!pfbGearPathProbeOpen()) {
        return;
    }
    NSUInteger slot = 0;
    if (!barItem) {
        slot = 2;
        UIView* node = view;
        for (NSInteger up = 0; node && up < 8; up++) {
            if (pfbLooksLikeSettingsButton(node)) {
                slot = 4;
                break;
            }
            node = node.superview;
        }
    }
    gPFBGearPathProbeCounts[slot + (repaint ? 0 : 1)]++;
}

// Replaces the image of every image view under a view. The result
// is remembered so the work happens once, and happens again only if Twitter
// puts its own image back.
static void pfbRepaintGlyphs(UIView* view, UIColor* colour) {
    for (UIView* subview in view.subviews) {
        if ([subview isKindOfClass:[UIImageView class]]) {
            UIImageView* imageView = (UIImageView*)subview;
            UIImage* current = imageView.image;
            UIImage* ours = objc_getAssociatedObject(imageView, kPFBGreyedImageKey);
            // Repaint when the image changed or when the color did. At launch the
            // trait collection is unsettled, so labelColor resolves differently and
            // the first paint comes out pale.
            UIColor* usedColour = objc_getAssociatedObject(imageView, kPFBGreyTargetKey);
            BOOL colourChanged = usedColour && ![usedColour isEqual:colour];
            BOOL alreadyOurs =
                objc_getAssociatedObject(current, kPFBPaintedFlagKey) != nil;

            // The painted flag says the image was repainted, not that it was repainted for
            // this view: a glyph baked elsewhere carries it too, so the recorded image is compared.
            if (current && alreadyOurs && ours && current != ours && !colourChanged) {
                imageView.image = ours;
                // Probe: counts this restore.
                if (gPFBGearPathProbeState != 2) {
                    pfbGearPathProbe(imageView, NO, NO);
                }
            } else if (current && !alreadyOurs && (current != ours || colourChanged)) {
                // Remembers the original only when this image is not a repainted one.
                UIImage* source = current;
                UIImage* original =
                    objc_getAssociatedObject(imageView, kPFBOriginalImageKey);
                if (original) {
                    source = original;
                } else {
                    objc_setAssociatedObject(imageView, kPFBOriginalImageKey, current,
                                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
                UIImage* painted = PFBGreyGlyph(source, colour);
                objc_setAssociatedObject(imageView, kPFBGreyTargetKey, colour,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                objc_setAssociatedObject(imageView, kPFBGreyedImageKey, painted,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                imageView.image = painted;
                PFBCOMPAT_ACTION(PFBCompat_bar_repairs, @"settings gear repainted");
                // Probe: counts this repaint.
                if (gPFBGearPathProbeState != 2) {
                    pfbGearPathProbe(imageView, YES, NO);
                }
            }
            // Probe: notes a repainted glyph asked for another color, which no branch above takes.
            if (!gPFBStaleGearProbeDone && current && alreadyOurs && colourChanged) {
                pfbStaleGearProbe(imageView, current == ours, usedColour, colour, NO);
            }
        }
        pfbRepaintGlyphs(subview, colour);
    }
}

// Probe: notes each fragment's first match (07#F016) and the first XChatDM match on each
// of eight screens (07#F042), and counts them: per fragment when a tour ends, per screen
// at the first move to the background after an XChatDM match.
static int gPFBChatProbeState;
static BOOL gPFBChatProbeTourNoted;
static BOOL gPFBChatProbeBackgroundNoted;
static BOOL gPFBChatProbeFragmentNoted[2];
static NSUInteger gPFBChatProbeMatches[2];
static NSMutableDictionary<NSString*, NSNumber*>* gPFBChatProbeScreens;

// Closes only with recording off: a screen line (07#F042) can follow both counts.
static void pfbChatProbeSettle(void) {
    if (gPFBChatProbeTourNoted && gPFBChatProbeBackgroundNoted && !PFBDebugIsRecording()) {
        gPFBChatProbeState = 2;
    }
}

static BOOL pfbChatProbeOpen(void) {
    if (!NSThread.isMainThread) {
        return NO;
    }
    if (gPFBChatProbeState == 0) {
        gPFBChatProbeState = 1;
        gPFBChatProbeTourNoted = !PFBProbeWants(@"07#F016 counts");
        gPFBChatProbeBackgroundNoted = !PFBProbeWants(@"07#F042 counts");
        pfbChatProbeSettle();
        if (gPFBChatProbeState == 1) {
            gPFBChatProbeScreens = [NSMutableDictionary dictionary];
            pfbOnTourEndProbe(^{
                if (PFBProbeWants(@"07#F016 counts")) {
                    PFBProbeNote(@"07#F016 counts", @"07#F016 chat-bar matches: XChatDM %lu, ConversationContainer %lu (since launch)",
                                 (unsigned long)gPFBChatProbeMatches[0],
                                 (unsigned long)gPFBChatProbeMatches[1]);
                }
                gPFBChatProbeTourNoted = YES;
                pfbChatProbeSettle();
            });
            [[NSNotificationCenter defaultCenter]
                addObserverForName:UIApplicationDidEnterBackgroundNotification
                            object:nil
                             queue:[NSOperationQueue mainQueue]
                        usingBlock:^(NSNotification* note) {
                            if (gPFBChatProbeBackgroundNoted || !gPFBChatProbeScreens.count) {
                                return;
                            }
                            NSMutableArray<NSString*>* parts = [NSMutableArray array];
                            [gPFBChatProbeScreens enumerateKeysAndObjectsUsingBlock:^(NSString* screen, NSNumber* count, BOOL* stop) {
                                [parts addObject:[NSString stringWithFormat:@"%@ %@", screen, count]];
                            }];
                            if (PFBProbeWants(@"07#F042 counts")) {
                                PFBProbeNote(@"07#F042 counts", @"07#F042 XChatDM matches by screen in front: %@",
                                             [parts componentsJoinedByString:@", "]);
                            }
                            gPFBChatProbeBackgroundNoted = YES;
                            pfbChatProbeSettle();
                        }];
        }
    }
    return gPFBChatProbeState == 1;
}

// The depth is the number of responders climbed, 1 being the view's next responder; the
// holder is the bar-button ancestor that made the view a bar glyph.
static void pfbChatMatchProbe(UIView* view, NSString* name, NSInteger depth) {
    if (!pfbChatProbeOpen()) {
        return;
    }
    BOOL dm = [name containsString:@"XChatDM"];
    gPFBChatProbeMatches[dm ? 0 : 1]++;
    NSString* holder = @"none";
    UIView* ancestor = view.superview;
    for (NSInteger up = 0; ancestor && up < 4; up++) {
        NSString* ancestorName = NSStringFromClass([ancestor class]);
        if ([ancestorName isEqualToString:@"_UIModernBarButton"] ||
            [ancestorName isEqualToString:@"_UIBackButtonMaskView"] ||
            [ancestorName isEqualToString:@"_UIButtonBarButton"] ||
            [ancestorName isEqualToString:@"TFNBarButtonItemButton"] ||
            [ancestorName containsString:@"SelfSizingStackView"]) {
            holder = ancestorName;
            break;
        }
        ancestor = ancestor.superview;
    }
    NSString* screen = PFBProbeScreenName(pfbBarOwningController(view));
    if (!gPFBChatProbeFragmentNoted[dm ? 0 : 1]) {
        gPFBChatProbeFragmentNoted[dm ? 0 : 1] = YES;
        NSString* key = dm ? @"07#F016 XChatDM" : @"07#F016 ConversationContainer";
        if (PFBProbeWants(key)) {
            PFBProbeNote(key, @"07#F016 %@ matched %@ at depth %ld, holder %@, front screen %@",
                         dm ? @"XChatDM" : @"ConversationContainer", name, (long)depth + 1, holder, screen);
        }
    }
    if (!dm) {
        return;
    }
    NSNumber* count = gPFBChatProbeScreens[screen];
    gPFBChatProbeScreens[screen] = @(count.unsignedIntegerValue + 1);
    if (!count && gPFBChatProbeScreens.count <= 8) {
        NSString* key = [@"07#F042 " stringByAppendingString:screen];
        if (PFBProbeWants(key)) {
            PFBProbeNote(key, @"07#F042 XChatDM matched on %@, holder %@, depth %ld", screen, holder,
                         (long)depth + 1);
        }
    }
}

// Whether a view sits under the Chat tab's navigation controller (XChatDM) or a
// post's conversation screen (ConversationContainer), named by controller rather
// than by geometry, within twelve responders.
static BOOL pfbIsChatConversationBar(UIView* view) {
    // Probe: arms the end-of-tour counts before any match, so a count of zero is noted too.
    if (gPFBChatProbeState == 0) {
        pfbChatProbeOpen();
    }
    UIResponder* responder = view;
    NSInteger depth = 0;
    while ((responder = responder.nextResponder) && depth < 12) {
        NSString* name = NSStringFromClass([responder class]);
        if ([name containsString:@"XChatDM"] ||
            [name containsString:@"ConversationContainer"]) {
            // Probe: notes the fragment that matched, how deep and on which screen.
            if (gPFBChatProbeState != 2) {
                pfbChatMatchProbe(view, name, depth);
            }
            return YES;
        }
        depth++;
    }
    return NO;
}


static BOOL pfbLooksLikeSettingsButton(UIView* view) {
    NSString* identifier = view.accessibilityIdentifier;
    NSString* label = view.accessibilityLabel;
    return [identifier hasPrefix:@"NavigationBarSettings"] ||
           [label hasPrefix:@"NavigationBarSettings"];
}

// A navigation transition fades the bar. Refusing that fade leaves the
// transition unable to settle, and the bar oscillates between the two
// screens' heights. Fades pass through for its duration.
static NSTimeInterval gPFBFadeWindowUntil = 0;

static BOOL pfbFadesAllowed(void) {
    return CACurrentMediaTime() < gPFBFadeWindowUntil;
}

static void pfbOpenFadeWindow(void) {
    gPFBFadeWindowUntil = CACurrentMediaTime() + 0.8;
}

// Brings one view back to full strength and marks it, so that anything lowering
// it later — an alpha, a layer opacity, an animation — is refused rather than
// undone after the fact.
static void pfbPinOpaque(UIView* view) {
    if (pfbFadesAllowed()) {
        return;
    }
    if (view.alpha < 1.0) {
        view.alpha = 1.0;
    }
    if (view.layer.opacity < 1.0f) {
        view.layer.opacity = 1.0f;
    }
    [view.layer removeAnimationForKey:@"opacity"];
    objc_setAssociatedObject(view.layer, kPFBNoFadeKey, @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// The gear and everything inside it.
static void pfbForceOpaque(UIView* view) {
    pfbPinOpaque(view);
    for (UIView* subview in view.subviews) {
        pfbForceOpaque(subview);
    }
}

// The container holding the bar and the tab strip, reached from the bar upwards.
// The walk stops before the first view tall enough to be the screen itself, so
// only the header band is held.
static void pfbPinHeaderOpacity(UIView* bar) {
    UIWindow* window = bar.window;
    if (!window) {
        return;
    }
    CGFloat screenful = CGRectGetHeight(window.bounds) * 0.5;
    UIView* view = bar;
    while (view && view != window) {
        if (CGRectGetHeight(view.bounds) > screenful) {
            return;
        }
        pfbPinOpaque(view);
        view = view.superview;
    }
}

// Depth-first search for the settings button by its identifier or label.
static UIView* pfbFindSettingsButton(UIView* view) {
    for (UIView* subview in view.subviews) {
        if (pfbLooksLikeSettingsButton(subview)) {
            return subview;
        }
        UIView* found = pfbFindSettingsButton(subview);
        if (found) {
            return found;
        }
    }
    return nil;
}

// Notifications is recognized by a controller, one of its children or an
// ancestor whose class name contains "Notification" or "ActivityHistory".
static BOOL pfbNameIsNotifications(UIViewController* controller) {
    NSString* name = controller ? NSStringFromClass([controller class]) : @"";
    // "Activity" alone would also match UIActivityViewController, the share sheet.
    return [name containsString:@"Notification"] ||
           [name containsString:@"ActivityHistory"];
}

static BOOL pfbControllerIsNotifications(UIViewController* controller) {
    if (!controller) {
        return NO;
    }
    if (pfbNameIsNotifications(controller)) {
        return YES;
    }
    for (UIViewController* child in controller.childViewControllers) {
        if (pfbNameIsNotifications(child)) {
            return YES;
        }
    }
    UIViewController* parent = controller.parentViewController;
    while (parent) {
        if (pfbNameIsNotifications(parent)) {
            return YES;
        }
        parent = parent.parentViewController;
    }
    return NO;
}

static UIViewController* pfbBarOwningController(UIView* view) {
    UIResponder* responder = view;
    while ((responder = responder.nextResponder)) {
        if (![responder isKindOfClass:[UIViewController class]]) {
            continue;
        }
        UIViewController* controller = (UIViewController*)responder;
        if ([controller isKindOfClass:[UINavigationController class]]) {
            return ((UINavigationController*)controller).topViewController ?: controller;
        }
        return controller;
    }
    return nil;
}

// On Notifications the gear is a bar button item, so its image is repainted
// directly. The caller has established the bar; icon-only items are picked here,
// so a text button is never touched.
static void pfbRepaintNotificationsGear(UIView* bar, UIColor* colour) {
    // The item has no view of its own, so the fade is removed from whatever
    // renders it: the icon buttons on the right of this bar.
    for (UIView* subview in bar.subviews) {
        CGRect inBar = [subview convertRect:subview.bounds toView:bar];
        if (CGRectGetMidX(inBar) > CGRectGetWidth(bar.bounds) * 0.6) {
            pfbForceOpaque(subview);
        }
    }
    if (![bar respondsToSelector:@selector(topItem)]) {
        return;
    }
    UINavigationItem* item = ((id (*)(id, SEL))objc_msgSend)(bar, @selector(topItem));
    for (UIBarButtonItem* button in item.rightBarButtonItems) {
        if (button.title.length > 0 || !button.image) {
            continue;
        }
        UIImage* ours = objc_getAssociatedObject(button, kPFBGreyedImageKey);
        UIColor* usedColour = objc_getAssociatedObject(button, kPFBGreyTargetKey);
        BOOL colourChanged = usedColour && ![usedColour isEqual:colour];
        BOOL alreadyOurs =
            objc_getAssociatedObject(button.image, kPFBPaintedFlagKey) != nil;

        // The painted flag says the image was repainted, not that it was repainted for this
        // button. A repainted image other than the recorded one came from another path, so
        // the recorded one is put back.
        if (alreadyOurs && ours && button.image != ours && !colourChanged) {
            button.image = ours;
            // Probe: counts this restore.
            if (gPFBGearPathProbeState != 2) {
                pfbGearPathProbe(bar, NO, YES);
            }
            continue;
        }
        // Probe: notes a repainted glyph asked for another color, which no branch takes.
        if (!gPFBStaleGearProbeDone && alreadyOurs && colourChanged) {
            pfbStaleGearProbe(bar, button.image == ours, usedColour, colour, YES);
        }
        if (!alreadyOurs && (button.image != ours || colourChanged)) {
            UIImage* original =
                objc_getAssociatedObject(button, kPFBOriginalImageKey);
            UIImage* source = original ?: button.image;
            if (!original) {
                objc_setAssociatedObject(button, kPFBOriginalImageKey, button.image,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            UIImage* painted = PFBGreyGlyph(source, colour);
            objc_setAssociatedObject(button, kPFBGreyTargetKey, colour,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(button, kPFBGreyedImageKey, painted,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            button.image = painted;
            PFBCOMPAT_ACTION(PFBCompat_bar_repairs, @"Notifications gear repainted");
            // Probe: counts this repaint.
            if (gPFBGearPathProbeState != 2) {
                pfbGearPathProbe(bar, YES, YES);
            }
        }
    }
}

// The bar button's shared-background setter, resolved by name once.
static SEL pfbHideSharedSelector(void) {
    static SEL selector;
    if (!selector) {
        selector = NSSelectorFromString(@"setHidesSharedBackground:");
    }
    return selector;
}

// A Done item, the screen's primary action, keeps its iOS 26 glass capsule, tinted
// system blue so it never fills with the bar's ink, with a white label. Returns
// whether anything was owed; writes only when apply is YES.
static BOOL pfbStyleDoneItem(UIBarButtonItem* button, BOOL apply) {
    BOOL owed = NO;
    SEL hideShared = pfbHideSharedSelector();
    id current = nil;
    @try {
        current = [button valueForKey:@"hidesSharedBackground"];
    } @catch (id exception) {
    }
    if ([current respondsToSelector:@selector(boolValue)] && [current boolValue]) {
        owed = YES;
        if (apply && [button respondsToSelector:hideShared]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(button, hideShared, NO);
        }
    }
    UIColor* blue = [UIColor systemBlueColor];
    if (![button.tintColor isEqual:blue]) {
        owed = YES;
        if (apply) {
            button.tintColor = blue;
        }
    }
    UIControlState states[2] = { UIControlStateNormal, UIControlStateHighlighted };
    for (NSUInteger s = 0; s < 2; s++) {
        NSDictionary* existing = [button titleTextAttributesForState:states[s]];
        if ([existing[NSForegroundColorAttributeName] isEqual:[UIColor whiteColor]]) {
            continue;
        }
        owed = YES;
        if (apply) {
            NSMutableDictionary* attributes = [(existing ?: @{}) mutableCopy];
            attributes[NSForegroundColorAttributeName] = [UIColor whiteColor];
            [button setTitleTextAttributes:attributes forState:states[s]];
        }
    }
    return owed;
}

// The forced iOS 26 design puts UIKit's shared background behind every bar button,
// which this app never had; this pass takes it off plain items. With apply NO it
// only returns whether a pass is owed, so nothing is written inside a layout pass.
static BOOL pfbBarGlassPass(UIView* bar, BOOL apply) {
    if (![PFBSettings boolForKey:@"enable_liquid_glass"] ||
        ![bar respondsToSelector:@selector(topItem)]) {
        return NO;
    }
    UINavigationItem* item =
        ((id (*)(id, SEL))objc_msgSend)(bar, @selector(topItem));
    if (!item) {
        return NO;
    }
    BOOL owed = NO;
    NSMutableArray<UIBarButtonItem*>* items = [NSMutableArray array];
    [items addObjectsFromArray:item.leftBarButtonItems ?: @[]];
    [items addObjectsFromArray:item.rightBarButtonItems ?: @[]];
    // Groups carry the items on iOS 16 and later, and an item posted through one
    // never reaches the two arrays above.
    SEL groupSelectors[2] = { @selector(leadingItemGroups),
                              @selector(trailingItemGroups) };
    for (NSUInteger i = 0; i < 2; i++) {
        if (![item respondsToSelector:groupSelectors[i]]) {
            continue;
        }
        NSArray* groups =
            ((id (*)(id, SEL))objc_msgSend)(item, groupSelectors[i]);
        for (UIBarButtonItemGroup* group in groups) {
            if ([group isKindOfClass:[UIBarButtonItemGroup class]]) {
                [items addObjectsFromArray:group.barButtonItems ?: @[]];
            }
        }
    }
    if ([item respondsToSelector:@selector(pinnedTrailingGroup)]) {
        UIBarButtonItemGroup* pinned =
            ((id (*)(id, SEL))objc_msgSend)(item, @selector(pinnedTrailingGroup));
        if ([pinned isKindOfClass:[UIBarButtonItemGroup class]]) {
            [items addObjectsFromArray:pinned.barButtonItems ?: @[]];
        }
    }
    SEL hideShared = pfbHideSharedSelector();
    for (UIBarButtonItem* button in items) {
        if (button.tag == PFBNativeGlassTag) {
            continue;
        }
        if (![button isKindOfClass:[UIBarButtonItem class]] ||
            ![button respondsToSelector:hideShared]) {
            continue;
        }
        // Read before writing rather than marking once: UIKit rebuilds an item's
        // hosting on a re-host, and a mark would leave the rebuilt one glazed.
        id current = nil;
        @try {
            current = [button valueForKey:@"hidesSharedBackground"];
        } @catch (id exception) {
        }
        BOOL flat =
            [current respondsToSelector:@selector(boolValue)] && [current boolValue];

        // A marked item built here keeps the plain capsule iOS gives it, with no color of
        // its own: the cancel control of a sheet reads as chrome, not as the primary action.
        if (objc_getAssociatedObject(button, @selector(pfbKeepsBarGlass))) {
            if (flat) {
                owed = YES;
                if (!apply) {
                    continue;
                }
                ((void (*)(id, SEL, BOOL))objc_msgSend)(button, hideShared, NO);
            }
            continue;
        }

        if (button.style == UIBarButtonItemStyleDone) {
            if (pfbStyleDoneItem(button, apply)) {
                owed = YES;
            }
            continue;
        }

        if (flat) {
            continue;
        }
        owed = YES;
        if (!apply) {
            continue;
        }
        ((void (*)(id, SEL, BOOL))objc_msgSend)(button, hideShared, YES);
    }
    return owed;
}

// Queues one pass for the next turn of the run loop, and only one: a run of
// layout passes must not queue a block per pass.
static void pfbQueueBarGlassPass(UIView* bar) {
    if (objc_getAssociatedObject(bar, @selector(pfbBarGlassPending))) {
        return;
    }
    objc_setAssociatedObject(bar, @selector(pfbBarGlassPending), @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    dispatch_async(dispatch_get_main_queue(), ^{
      objc_setAssociatedObject(bar, @selector(pfbBarGlassPending), nil,
                               OBJC_ASSOCIATION_RETAIN_NONATOMIC);
      if (bar.window) {
          pfbBarGlassPass(bar, YES);
      }
    });
}

// The glass is taken off as the items are set, before the bar is ever drawn: from
// the layout pass alone, the capsule would show for one run-loop turn.
static void pfbFlattenItemsNow(NSArray<UIBarButtonItem*>* items) {
    if (![PFBSettings boolForKey:@"enable_liquid_glass"]) {
        return;
    }
    SEL hideShared = pfbHideSharedSelector();
    for (UIBarButtonItem* button in items) {
        if (button.tag == PFBNativeGlassTag) {
            continue;
        }
        if (![button isKindOfClass:[UIBarButtonItem class]] ||
            ![button respondsToSelector:hideShared] ||
            objc_getAssociatedObject(button, @selector(pfbKeepsBarGlass))) {
            continue;
        }
        // Styled as it is set, so a re-hosted Done never draws one frame in
        // the bar's ink before the layout pass paints it blue.
        if (button.style == UIBarButtonItemStyleDone) {
            pfbStyleDoneItem(button, YES);
            continue;
        }
        ((void (*)(id, SEL, BOOL))objc_msgSend)(button, hideShared, YES);
    }
}

%hook UINavigationItem

- (void)setRightBarButtonItems:(NSArray<UIBarButtonItem*>*)items {
    pfbFlattenItemsNow(items);
    %orig;
}

- (void)setRightBarButtonItems:(NSArray<UIBarButtonItem*>*)items
                      animated:(BOOL)animated {
    pfbFlattenItemsNow(items);
    %orig;
}

- (void)setLeftBarButtonItems:(NSArray<UIBarButtonItem*>*)items {
    pfbFlattenItemsNow(items);
    %orig;
}

- (void)setLeftBarButtonItems:(NSArray<UIBarButtonItem*>*)items
                     animated:(BOOL)animated {
    pfbFlattenItemsNow(items);
    %orig;
}

// Groups carry the items on iOS 16 and later, and an item posted through one
// never reaches the arrays above.
- (void)setTrailingItemGroups:(NSArray<UIBarButtonItemGroup*>*)groups {
    for (UIBarButtonItemGroup* group in groups) {
        if ([group isKindOfClass:[UIBarButtonItemGroup class]]) {
            pfbFlattenItemsNow(group.barButtonItems);
        }
    }
    %orig;
}

- (void)setRightBarButtonItem:(UIBarButtonItem*)item {
    pfbFlattenItemsNow(item ? @[ item ] : @[]);
    %orig;
}

- (void)setLeftBarButtonItem:(UIBarButtonItem*)item {
    pfbFlattenItemsNow(item ? @[ item ] : @[]);
    %orig;
}

%end

// Probe: how the Notifications test matched (07#F041): the screen itself, a child or a
// parent, and through "ActivityHistory". Each controller is looked at once, 200 at most.
static const void* kPFBNotificationsProbeKey = &kPFBNotificationsProbeKey;
static int gPFBNotificationsProbeState;
static NSUInteger gPFBNotificationsProbeLooks;

static BOOL pfbNotificationsProbeOpen(void) {
    if (!NSThread.isMainThread) {
        return NO;
    }
    if (gPFBNotificationsProbeState == 0) {
        BOOL wanted = PFBProbeWants(@"07#F041 itself") || PFBProbeWants(@"07#F041 child") ||
                      PFBProbeWants(@"07#F041 parent") || PFBProbeWants(@"07#F041 ActivityHistory");
        gPFBNotificationsProbeState = wanted ? 1 : 2;
    }
    return gPFBNotificationsProbeState == 1;
}

static void pfbNotificationsMatchProbe(UIView* view, NSString* caller) {
    if (!pfbNotificationsProbeOpen()) {
        return;
    }
    UIViewController* controller = pfbBarOwningController(view);
    if (!controller || objc_getAssociatedObject(controller, kPFBNotificationsProbeKey)) {
        return;
    }
    objc_setAssociatedObject(controller, kPFBNotificationsProbeKey, @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (++gPFBNotificationsProbeLooks > 200) {
        gPFBNotificationsProbeState = 2;
        return;
    }
    NSString* how = nil;
    UIViewController* match = nil;
    if (pfbNameIsNotifications(controller)) {
        how = @"itself";
        match = controller;
    }
    for (UIViewController* child in controller.childViewControllers) {
        if (!match && pfbNameIsNotifications(child)) {
            how = @"child";
            match = child;
        }
    }
    for (UIViewController* parent = controller.parentViewController; parent && !match;
         parent = parent.parentViewController) {
        if (pfbNameIsNotifications(parent)) {
            how = @"parent";
            match = parent;
        }
    }
    if (!match) {
        return;
    }
    NSString* screenName = NSStringFromClass([controller class]);
    NSString* matchName = NSStringFromClass([match class]);
    NSString* key = [@"07#F041 " stringByAppendingString:how];
    if (PFBProbeWants(key)) {
        if (match == controller) {
            PFBProbeNote(key, @"07#F041 Notifications test matched %@ itself (%@)", screenName, caller);
        } else {
            PFBProbeNote(key, @"07#F041 Notifications test matched %@ through %@ %@ (%@)", screenName, how,
                         matchName, caller);
        }
    }
    if ([matchName containsString:@"ActivityHistory"] && ![matchName containsString:@"Notification"] &&
        PFBProbeWants(@"07#F041 ActivityHistory")) {
        PFBProbeNote(@"07#F041 ActivityHistory", @"07#F041 ActivityHistory matched %@ as %@ of %@ (%@)", matchName,
                     how, screenName, caller);
    }
    if (!PFBProbeWants(@"07#F041 itself") && !PFBProbeWants(@"07#F041 child") &&
        !PFBProbeWants(@"07#F041 parent") && !PFBProbeWants(@"07#F041 ActivityHistory")) {
        gPFBNotificationsProbeState = 2;
    }
}

// Probe: a pinned bar whose top item changes (07#F047), inside or outside the fade
// window, with the screens before and after; 500 changes looked at, at most.
static const void* kPFBPinnedBarProbeKey = &kPFBPinnedBarProbeKey;
static BOOL gPFBPinnedBarProbeOpen;
static NSUInteger gPFBPinnedBarProbeChanges;

static void pfbPinnedBarProbe(UINavigationBar* bar) {
    if (!objc_getAssociatedObject(bar.layer, kPFBNoFadeKey)) {
        return;
    }
    UINavigationItem* top = bar.topItem;
    NSArray* last = objc_getAssociatedObject(bar, kPFBPinnedBarProbeKey);
    if (last && [last.firstObject pointerValue] == (__bridge void*)top) {
        return;
    }
    NSString* screen = PFBProbeScreenName(pfbBarOwningController(bar));
    objc_setAssociatedObject(bar, kPFBPinnedBarProbeKey,
                             @[ [NSValue valueWithPointer:(__bridge void*)top], screen ],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!last) {
        return;
    }
    BOOL inside = pfbFadesAllowed();
    NSString* key = inside ? @"07#F047 inside" : @"07#F047 outside";
    if (PFBProbeWants(key)) {
        PFBProbeNote(key, @"07#F047 pinned bar changed screen %@ the fade window: %@ -> %@",
                     inside ? @"inside" : @"outside", last.lastObject, screen);
    }
    if (!inside || ++gPFBPinnedBarProbeChanges > 500) {
        gPFBPinnedBarProbeOpen = NO;
    }
}

// Probe: the cost of the gear and Notifications tests of every bar layout pass, with the
// views the settings search visits on one pass in eight, noted when a tour ends or after
// 200000 passes (07#F064).
static int gPFBBarProbeState;
static BOOL gPFBBarCostProbeOpen;
static NSUInteger gPFBBarProbePasses;
static NSUInteger gPFBBarProbeSamples;
static NSUInteger gPFBBarProbeWalked;
static uint64_t gPFBBarProbeTicks;
static uint64_t gPFBBarProbeMax;
static uint64_t gPFBBarProbeSecond;
static uint64_t gPFBBarProbeSecondTicks;
static NSUInteger gPFBBarProbeSecondPasses;
static uint64_t gPFBBarProbeBusiestTicks;
static NSUInteger gPFBBarProbeBusiestPasses;

// The views the settings search visits: the whole tree, or up to the button it finds.
static NSUInteger pfbBarWalkProbe(UIView* view, UIView* found, BOOL* reached) {
    NSUInteger visited = 0;
    for (UIView* subview in view.subviews) {
        if (*reached) {
            break;
        }
        visited++;
        if (subview == found) {
            *reached = YES;
            break;
        }
        visited += pfbBarWalkProbe(subview, found, reached);
    }
    return visited;
}

static void pfbBarProbeSettle(void) {
    if (!gPFBBarCostProbeOpen && !gPFBPinnedBarProbeOpen && gPFBNotificationsProbeState == 2) {
        gPFBBarProbeState = 2;
    }
}

static void pfbBarCostProbeEnd(void) {
    if (!gPFBBarCostProbeOpen) {
        return;
    }
    gPFBBarCostProbeOpen = NO;
    if (gPFBBarProbeSecondTicks > gPFBBarProbeBusiestTicks) {
        gPFBBarProbeBusiestTicks = gPFBBarProbeSecondTicks;
        gPFBBarProbeBusiestPasses = gPFBBarProbeSecondPasses;
    }
    if (PFBProbeWants(@"07#F064 cost")) {
        NSUInteger passes = MAX(gPFBBarProbePasses, (NSUInteger)1);
        PFBProbeNote(@"07#F064 cost", @"07#F064 bar pass: %lu passes, mean %.1f us, max %.0f us, busiest second %lu passes / %.2f ms, views walked mean %.0f (%lu passes sampled)",
                     (unsigned long)gPFBBarProbePasses,
                     pfbProbeMicros(gPFBBarProbeTicks) / (double)passes,
                     pfbProbeMicros(gPFBBarProbeMax), (unsigned long)gPFBBarProbeBusiestPasses,
                     pfbProbeMicros(gPFBBarProbeBusiestTicks) / 1000.0,
                     (double)gPFBBarProbeWalked / (double)MAX(gPFBBarProbeSamples, (NSUInteger)1),
                     (unsigned long)gPFBBarProbeSamples);
    }
    pfbBarProbeSettle();
}

static uint64_t pfbBarProbeStart(void) {
    if (!pthread_main_np()) {
        return 0;
    }
    if (gPFBBarProbeState == 0) {
        gPFBBarProbeState = 1;
        gPFBBarCostProbeOpen = PFBProbeWants(@"07#F064 cost");
        gPFBPinnedBarProbeOpen = PFBProbeWants(@"07#F047 outside");
        pfbNotificationsProbeOpen();
        if (gPFBBarCostProbeOpen) {
            pfbOnTourEndProbe(^{
                pfbBarCostProbeEnd();
            });
        }
        pfbBarProbeSettle();
    }
    if (gPFBBarProbeState != 1) {
        return 0;
    }
    return gPFBBarCostProbeOpen ? mach_absolute_time() : 1;
}

static void pfbBarProbePass(UINavigationBar* bar, UIView* settingsButton, BOOL notifications,
                            uint64_t start) {
    if (gPFBBarCostProbeOpen && start > 1) {
        uint64_t elapsed = mach_absolute_time() - start;
        gPFBBarProbePasses++;
        gPFBBarProbeTicks += elapsed;
        gPFBBarProbeMax = MAX(gPFBBarProbeMax, elapsed);
        uint64_t second = (uint64_t)(pfbProbeMicros(start) / 1000000.0);
        if (second != gPFBBarProbeSecond) {
            if (gPFBBarProbeSecondTicks > gPFBBarProbeBusiestTicks) {
                gPFBBarProbeBusiestTicks = gPFBBarProbeSecondTicks;
                gPFBBarProbeBusiestPasses = gPFBBarProbeSecondPasses;
            }
            gPFBBarProbeSecond = second;
            gPFBBarProbeSecondTicks = 0;
            gPFBBarProbeSecondPasses = 0;
        }
        gPFBBarProbeSecondTicks += elapsed;
        gPFBBarProbeSecondPasses++;
        if (gPFBBarProbePasses % 8 == 1) {
            BOOL reached = NO;
            gPFBBarProbeWalked += pfbBarWalkProbe(bar, settingsButton, &reached);
            gPFBBarProbeSamples++;
        }
        if (gPFBBarProbePasses >= 200000) {
            pfbBarCostProbeEnd();
        }
    }
    if (notifications && gPFBNotificationsProbeState == 1) {
        pfbNotificationsMatchProbe(bar, @"bar");
    }
    if (gPFBPinnedBarProbeOpen) {
        pfbPinnedBarProbe(bar);
    }
    pfbBarProbeSettle();
}

%hook UINavigationBar

- (void)layoutSubviews {
    %orig;

    @try {
        UIView* bar = (UIView*)self;
        if (!bar.window) {
            return;
        }
        // Every navigation bar, before the two-screen guard below: the glass the
        // forced design adds is on all of them, not only on these two. Read here,
        // written off the pass.
        if (pfbBarGlassPass(bar, NO)) {
            pfbQueueBarGlassPass(bar);
        }

        // Probe: times the gear and Notifications tests below.
        uint64_t probeStart = gPFBBarProbeState == 2 ? 0 : pfbBarProbeStart();
        UIColor* grey = PFBBarIconGrey(bar.traitCollection);

        // Explore is recognized by the button, Notifications by the screen.
        // Anything else is left exactly as Twitter draws it — the header is
        // held opaque on these two bars only.
        UIView* settingsButton = pfbFindSettingsButton(bar);
        BOOL notifications =
            settingsButton
                ? NO
                : pfbControllerIsNotifications(pfbBarOwningController(bar));
        // Probe: notes the cost, how Notifications matched, and a pinned bar's change of screen.
        if (probeStart) {
            pfbBarProbePass(self, settingsButton, notifications, probeStart);
        }
        if (!settingsButton && !notifications) {
            return;
        }

        pfbPinHeaderOpacity(bar);

        if (settingsButton) {
            pfbRepaintGlyphs(settingsButton, grey);
            pfbForceOpaque(settingsButton);
            return;
        }
        pfbRepaintNotificationsGear(bar, grey);
    } @catch (id exception) {
        static BOOL reported;
        if (!reported && PFBDebugIsRecording()) {
            reported = YES;
            PFBDebugLog(@"[navbar] bar pass stopped: %@", exception);
        }
    }
}

%end

// The color a bar glyph should carry: the text color, resolved for the
// current appearance.
static UIColor* pfbBarGlyphColour(UIView* view) {
    UIColor* colour = [UIColor labelColor];
    if (view && [colour respondsToSelector:@selector(resolvedColorWithTraitCollection:)]) {
        return [colour resolvedColorWithTraitCollection:view.traitCollection] ?: colour;
    }
    return colour;
}

// The button's own chain, four levels at most, and never past the button. Above it
// sits the platter host every item of the bar draws from, so a tint written there
// fills the glass capsule of the siblings too.
static void pfbTintGlyphChain(UIView* view, UIColor* colour) {
    UIView* node = view;
    NSInteger depth = 0;
    while (node && depth < 4) {
        NSString* name = NSStringFromClass([node class]);
        if ([node isKindOfClass:[UINavigationBar class]] ||
            [name containsString:@"Platter"] ||
            [name containsString:@"ItemWrapperView"]) {
            return;
        }
        if (![node.tintColor isEqual:colour]) {
            node.tintColor = colour;
        }
        node = node.superview;
        depth++;
    }
}

// True of a back button's own subtree only: _UIBackButtonMaskView is created for
// back buttons and nothing else. Class names are read, never touched, and no view
// in the subtree is painted.
static BOOL pfbSubtreeHasBackMask(UIView* view, NSInteger depth) {
    if (!view || depth > 4) {
        return NO;
    }
    if ([NSStringFromClass([view class]) isEqualToString:@"_UIBackButtonMaskView"]) {
        return YES;
    }
    for (UIView* sub in view.subviews) {
        if (pfbSubtreeHasBackMask(sub, depth + 1)) {
            return YES;
        }
    }
    return NO;
}

static BOOL pfbIsBackArrowGlyph(UIView* view) {
    UIView* container = nil;
    UIView* node = view.superview;
    NSInteger depth = 0;
    while (node && depth < 5) {
        if ([NSStringFromClass([node class]) isEqualToString:@"_UIButtonBarButton"]) {
            container = node;
            break;
        }
        node = node.superview;
        depth++;
    }
    if (!container) {
        return NO;
    }
    return pfbSubtreeHasBackMask(container, 0);
}

static BOOL pfbIsChatBarGlyph(UIView* view) {
    UIView* ancestor = view.superview;
    NSInteger depth = 0;
    BOOL inHolder = NO;
    while (ancestor && depth < 4) {
        NSString* name = NSStringFromClass([ancestor class]);
        // A back button carries two image views, one under the modern button and
        // one under the mask; the mask's is the one UIKit draws, so both count.
        if ([name isEqualToString:@"_UIModernBarButton"] ||
            [name isEqualToString:@"_UIBackButtonMaskView"] ||
            [name isEqualToString:@"_UIButtonBarButton"] ||
            [name isEqualToString:@"TFNBarButtonItemButton"] ||
            [name containsString:@"SelfSizingStackView"]) {
            inHolder = YES;
            break;
        }
        ancestor = ancestor.superview;
        depth++;
    }
    return inHolder && pfbIsChatConversationBar(view);
}

// Probe: the cost of -setImage:'s two glyph tests and how often they match, with the
// blocks queued for views without a superview (07#F067); noted when a tour ends, or
// after 500000 calls. Main thread only.
static int gPFBImageProbeState;
static NSUInteger gPFBImageProbeCalls;
static NSUInteger gPFBImageProbeNils;
static NSUInteger gPFBImageProbeQueued;
static NSUInteger gPFBImageProbeChat;
static NSUInteger gPFBImageProbeBack;
static uint64_t gPFBImageProbeTicks;
static uint64_t gPFBImageProbeMax;
static uint64_t gPFBImageProbeSecond;
static uint64_t gPFBImageProbeSecondTicks;
static uint64_t gPFBImageProbeBusiest;

static void pfbImageProbeEnd(void) {
    if (gPFBImageProbeState != 1) {
        return;
    }
    gPFBImageProbeState = 2;
    uint64_t busiest = MAX(gPFBImageProbeBusiest, gPFBImageProbeSecondTicks);
    if (PFBProbeWants(@"07#F067 cost")) {
        PFBProbeNote(@"07#F067 cost", @"07#F067 setImage: %lu calls tested (%lu nil, %lu queued), tests mean %.2f us, max %.0f us, busiest second %.2f ms, matches chat %lu, back %lu",
                     (unsigned long)gPFBImageProbeCalls, (unsigned long)gPFBImageProbeNils,
                     (unsigned long)gPFBImageProbeQueued,
                     pfbProbeMicros(gPFBImageProbeTicks) / (double)MAX(gPFBImageProbeCalls, (NSUInteger)1),
                     pfbProbeMicros(gPFBImageProbeMax), pfbProbeMicros(busiest) / 1000.0,
                     (unsigned long)gPFBImageProbeChat, (unsigned long)gPFBImageProbeBack);
    }
}

static uint64_t pfbImageProbeStart(void) {
    if (!pthread_main_np()) {
        return 0;
    }
    if (gPFBImageProbeState == 0) {
        gPFBImageProbeState = PFBProbeWants(@"07#F067 cost") ? 1 : 2;
        if (gPFBImageProbeState == 1) {
            pfbOnTourEndProbe(^{
                pfbImageProbeEnd();
            });
        }
    }
    if (gPFBImageProbeState != 1) {
        return 0;
    }
    return mach_absolute_time();
}

static void pfbImageProbeTests(UIImageView* view, UIImage* image, uint64_t start, BOOL chat,
                               BOOL backArrow) {
    uint64_t elapsed = mach_absolute_time() - start;
    gPFBImageProbeCalls++;
    gPFBImageProbeTicks += elapsed;
    gPFBImageProbeMax = MAX(gPFBImageProbeMax, elapsed);
    uint64_t second = (uint64_t)(pfbProbeMicros(start) / 1000000.0);
    if (second != gPFBImageProbeSecond) {
        gPFBImageProbeBusiest = MAX(gPFBImageProbeBusiest, gPFBImageProbeSecondTicks);
        gPFBImageProbeSecond = second;
        gPFBImageProbeSecondTicks = 0;
    }
    gPFBImageProbeSecondTicks += elapsed;
    if (!image) {
        gPFBImageProbeNils++;
    }
    if (chat) {
        gPFBImageProbeChat++;
    }
    if (backArrow) {
        gPFBImageProbeBack++;
    }
    if (!chat && !backArrow && !view.superview) {
        gPFBImageProbeQueued++;
    }
    if (gPFBImageProbeCalls >= 500000) {
        pfbImageProbeEnd();
    }
}

// Probe: the blocks -setImage: queues for a view without a superview and the switches
// they make (07#F044): the first switch is noted, both counted and noted when a tour ends.
static int gPFBDeferredProbeState;
static NSUInteger gPFBDeferredProbeQueued;
static NSUInteger gPFBDeferredProbeSwitched;

static BOOL pfbDeferredProbeOpen(void) {
    if (!NSThread.isMainThread) {
        return NO;
    }
    if (gPFBDeferredProbeState == 0) {
        gPFBDeferredProbeState =
            PFBProbeWants(@"07#F044 switch") || PFBProbeWants(@"07#F044 counts") ? 1 : 2;
        if (gPFBDeferredProbeState == 1) {
            pfbOnTourEndProbe(^{
                if (PFBProbeWants(@"07#F044 counts")) {
                    PFBProbeNote(@"07#F044 counts", @"07#F044 deferred blocks queued %lu, switched %lu (since launch)",
                                 (unsigned long)gPFBDeferredProbeQueued,
                                 (unsigned long)gPFBDeferredProbeSwitched);
                }
                // A switch after the tour, in the Chat gesture, is still noted.
                gPFBDeferredProbeState = PFBProbeWants(@"07#F044 switch") ? 1 : 2;
            });
        }
    }
    return gPFBDeferredProbeState == 1;
}

static void pfbDeferredQueuedProbe(void) {
    if (pfbDeferredProbeOpen()) {
        gPFBDeferredProbeQueued++;
    }
}

static void pfbDeferredSwitchProbe(UIImageView* view, UIImage* image) {
    if (!pfbDeferredProbeOpen()) {
        return;
    }
    gPFBDeferredProbeSwitched++;
    if (PFBProbeWants(@"07#F044 switch")) {
        PFBProbeNote(@"07#F044 switch", @"07#F044 deferred block switched a %@ glyph to original mode, %.0fx%.0f, front screen %@",
                     pfbIsBackArrowGlyph(view) ? @"back" : @"chat", image.size.width, image.size.height,
                     PFBProbeScreenName(pfbBarOwningController(view)));
        if (!PFBProbeWants(@"07#F044 counts")) {
            gPFBDeferredProbeState = 2;
        }
    }
}

// Probe: in a taken-over view, whether the image Twitter sets, which is discarded for the
// first one, is a re-wrap of the repaint, the first glyph again or another glyph (SA-6);
// one line per screen and verdict, 8 at most, 300 images looked at.
static int gPFBIconProbeState;
static NSUInteger gPFBIconProbeLooks;
static NSUInteger gPFBIconProbeLines;

// The pixels whose alpha differs by more than 32 of 255 when both glyphs are drawn at
// 32x32, or NSNotFound when they cannot be drawn.
static NSUInteger pfbGlyphDifferenceProbe(UIImage* first, UIImage* second) {
    const size_t side = 32;
    uint8_t* pixels = calloc(side * side * 2, 1);
    if (!pixels) {
        return NSNotFound;
    }
    UIImage* images[2] = { first, second };
    for (NSUInteger i = 0; i < 2; i++) {
        // Alpha only: the documented format takes no color space.
        CGContextRef context = CGBitmapContextCreate(pixels + i * side * side, side, side, 8, side,
                                                     NULL, kCGImageAlphaOnly);
        if (!context) {
            free(pixels);
            return NSNotFound;
        }
        UIGraphicsPushContext(context);
        [images[i] drawInRect:CGRectMake(0, 0, side, side)];
        UIGraphicsPopContext();
        CGContextRelease(context);
    }
    NSUInteger differing = 0;
    for (size_t k = 0; k < side * side; k++) {
        if (abs((int)pixels[k] - (int)pixels[k + side * side]) > 32) {
            differing++;
        }
    }
    free(pixels);
    return differing;
}

static void pfbDiscardedIconProbe(UIImageView* view, UIImage* incoming, UIImage* original,
                                  UIImage* painted) {
    if (!NSThread.isMainThread) {
        return;
    }
    if (gPFBIconProbeState == 0) {
        gPFBIconProbeState = PFBDebugIsRecording() ? 1 : 2;
    }
    if (gPFBIconProbeState != 1) {
        return;
    }
    if (++gPFBIconProbeLooks > 300 || gPFBIconProbeLines >= 8) {
        gPFBIconProbeState = 2;
        return;
    }
    NSString* kind = @"different";
    NSString* verdict = nil;
    if (incoming.CGImage && incoming.CGImage == painted.CGImage) {
        kind = @"rewrap";
        verdict = @"re-wrap of the painted image";
    } else if (incoming.CGImage && incoming.CGImage == original.CGImage) {
        kind = @"same";
        verdict = @"same glyph as the first image (same bitmap)";
    } else {
        NSUInteger differing = pfbGlyphDifferenceProbe(incoming, original);
        if (differing == 0) {
            kind = @"same";
            verdict = @"same glyph as the first image (same pixels)";
        } else if (differing == NSNotFound) {
            kind = @"unread";
            verdict = @"not comparable";
        } else {
            verdict = [NSString stringWithFormat:@"a different glyph (%lu of 1024 pixels differ)",
                                                 (unsigned long)differing];
        }
    }
    NSString* screen = PFBProbeScreenName(pfbBarOwningController(view));
    NSString* key = [NSString stringWithFormat:@"SA-6 %@ %@", screen, kind];
    if (PFBProbeWants(key)) {
        gPFBIconProbeLines++;
        PFBProbeNote(key, @"SA-6 bar icon on %@: Twitter set %.0fx%.0f: %@; the first image (%.0fx%.0f) kept",
                     screen, incoming.size.width, incoming.size.height, verdict, original.size.width,
                     original.size.height);
    }
}

%hook UIImageView

- (void)didMoveToWindow {
    %orig;
    if (!((UIView*)self).window) {
        return;
    }
    // Cold-start belt for the conversation bar: on the first conversation after a
    // relaunch, setImage: fires before the button is attached and the retry cannot
    // read the chain. Here the chain is complete by definition.
    UIImage* chatImage = self.image;
    if (chatImage &&
        chatImage.renderingMode != UIImageRenderingModeAlwaysOriginal &&
        (pfbIsChatBarGlyph((UIView*)self) ||
         pfbIsBackArrowGlyph((UIView*)self))) {
        UIColor* colour = pfbBarGlyphColour((UIView*)self);
        UIImage* baked = PFBGreyGlyph(chatImage, colour);
        if (baked) {
            PFBMark((UIView*)self, @"NavBarIcons/chatBarGlyph -> baked (window)");
            PFBCOMPAT_ACTION(PFBCompat_bar_repairs, @"bar glyph baked");
            pfbTintGlyphChain((UIView*)self, colour);
            self.image = baked;  // AlwaysOriginal: re-enters the setter and passes through
        }
    }
}

// Twitter puts its own image back after a repaint, so images are caught as they are
// set: a view taken over is repainted in its color, a chat-bar or back-arrow glyph
// is baked in the label color, and any other image passes through.
- (void)setImage:(UIImage*)image {
    UIColor* target = objc_getAssociatedObject(self, kPFBGreyTargetKey);
    if (!target || !image) {
        // Not "== AlwaysTemplate": a bar glyph usually arrives in automatic mode,
        // which a bar button draws as a template all the same, so anything not
        // already original is claimed. Correcting the mode provokes no layout.
        if (image.renderingMode != UIImageRenderingModeAlwaysOriginal) {
            // Probe: times the two tests below.
            uint64_t probeStart = gPFBImageProbeState == 2 ? 0 : pfbImageProbeStart();
            BOOL backArrow = pfbIsBackArrowGlyph((UIView*)self);
            BOOL chat = pfbIsChatBarGlyph((UIView*)self);
            // Probe: counts the call, its matches and a block queued below.
            if (probeStart) {
                pfbImageProbeTests((UIImageView*)self, image, probeStart, chat, backArrow);
            }
            if (chat || backArrow) {
                // Baked at the setter: whoever writes last, the pixels that
                // land carry the color. A mode change alone leaves an alpha mask,
                // which a bar button re-tints per its own contrast rule.
                UIColor* colour = pfbBarGlyphColour((UIView*)self);
                UIImage* baked = PFBGreyGlyph(image, colour);
                PFBMark((UIView*)self, backArrow ? @"NavBarIcons/backArrow -> baked"
                                                 : @"NavBarIcons/chatBarGlyph -> baked");
                // Belt for the one frame a freshly created button can show
                // before its first baked image lands: with the button's own
                // chain tinted, even a frame treated as a template is right.
                pfbTintGlyphChain((UIView*)self, colour);
                PFBCOMPAT_ACTION(PFBCompat_bar_repairs, @"bar glyph baked");
                %orig(baked ?: image);
                return;
            }
            // A bar button is given its image before it is placed in the bar, so
            // the ancestors that name it do not exist yet. The question is asked
            // again on the next run-loop turn, outside any layout pass.
            if (!((UIView*)self).superview) {
                // Probe: counts the block queued here.
                if (gPFBDeferredProbeState != 2) {
                    pfbDeferredQueuedProbe();
                }
                __weak UIImageView* weakView = (UIImageView*)self;
                dispatch_async(dispatch_get_main_queue(), ^{
                  UIImageView* view = weakView;
                  UIImage* current = view.image;
                  if (!view || !current ||
                      current.renderingMode == UIImageRenderingModeAlwaysOriginal ||
                      (!pfbIsChatBarGlyph(view) && !pfbIsBackArrowGlyph(view))) {
                      return;
                  }
                  // Probe: counts this switch and notes the first.
                  if (gPFBDeferredProbeState != 2) {
                      pfbDeferredSwitchProbe(view, current);
                  }
                  view.image =
                      [current imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
                });
            }
        }
        %orig;
        return;
    }
    UIImage* ours = objc_getAssociatedObject(self, kPFBGreyedImageKey);
    if (image == ours ||
        objc_getAssociatedObject(image, kPFBPaintedFlagKey) != nil) {
        %orig;
        return;
    }
    // Twitter's own image is the source; repainting a repainted image would compound and go pale.
    if (objc_getAssociatedObject(self, kPFBOriginalImageKey)) {
        // Probe: notes what the image discarded here was.
        if (gPFBIconProbeState != 2) {
            pfbDiscardedIconProbe((UIImageView*)self, image,
                                  objc_getAssociatedObject(self, kPFBOriginalImageKey), ours);
        }
        image = objc_getAssociatedObject(self, kPFBOriginalImageKey);
    }
    objc_setAssociatedObject(self, kPFBOriginalImageKey, image,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIImage* painted = PFBGreyGlyph(image, target);
    objc_setAssociatedObject(self, kPFBGreyedImageKey, painted,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig(painted);
}

%end

%hook UIBarButtonItem

- (void)setImage:(UIImage*)image {
    UIColor* target = objc_getAssociatedObject(self, kPFBGreyTargetKey);
    if (!target || !image) {
        %orig;
        return;
    }
    UIImage* ours = objc_getAssociatedObject(self, kPFBGreyedImageKey);
    if (image == ours ||
        objc_getAssociatedObject(image, kPFBPaintedFlagKey) != nil) {
        %orig;
        return;
    }
    UIImage* painted = PFBGreyGlyph(image, target);
    objc_setAssociatedObject(self, kPFBGreyedImageKey, painted,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig(painted);
}

%end

// A bar button qualifies only as an icon on the right-hand side: no title, a
// glyph-sized image inside, and past the middle of its own bar. A back chevron
// and a text button are both excluded by that.
static BOOL pfbIsRightHandGlyphButton(UIView* button) {
    if ([button isKindOfClass:[UIButton class]] &&
        ((UIButton*)button).currentTitle.length > 0) {
        return NO;
    }

    __block BOOL hasGlyph = NO;
    PFBEnumerateSubviewsRecursively(button, ^(UIView* view) {
        if (hasGlyph || ![view isKindOfClass:[UIImageView class]]) {
            return;
        }
        UIImageView* imageView = (UIImageView*)view;
        CGFloat side = CGRectGetWidth(imageView.bounds);
        if (imageView.image && side > 14.0 && side < 34.0) {
            hasGlyph = YES;
        }
    });
    if (!hasGlyph) {
        return NO;
    }

    UIView* bar = button.superview;
    while (bar && ![bar isKindOfClass:[UINavigationBar class]]) {
        bar = bar.superview;
    }
    if (!bar) {
        return NO;
    }
    CGRect inBar = [button convertRect:button.bounds toView:bar];
    return CGRectGetMidX(inBar) > CGRectGetWidth(bar.bounds) * 0.6;
}

// The same treatment as Explore, reached from the other side: Notifications
// builds its bar differently, so the gear is not found in the bar's subtree, but
// the button class is the one Twitter uses everywhere.
%hook TFNBarButtonItemButton

// The repaint runs on both entry points: didMoveToWindow alone catches the button
// before its image view exists on Notifications, so nothing is marked and the
// interception never arms.
%new
- (void)pfbGreySettingsGlyphIfNeeded {
    @try {
        UIView* button = (UIView*)self;
        if (!button.window) {
            return;
        }
        // Either the button identifies itself as the settings one, which covers
        // Explore, or the screen is Notifications, where no view carries that
        // identifier and every icon on the right of the bar is treated.
        BOOL wanted = pfbLooksLikeSettingsButton(button) ||
                      (pfbControllerIsNotifications(pfbBarOwningController(button)) &&
                       pfbIsRightHandGlyphButton(button));
        if (!wanted) {
            return;
        }
        // Probe: notes how the Notifications test matched for a button it lets through.
        if (gPFBNotificationsProbeState != 2 && !pfbLooksLikeSettingsButton(button)) {
            pfbNotificationsMatchProbe(button, @"bar button");
        }
        pfbRepaintGlyphs(button, PFBBarIconGrey(button.traitCollection));
        pfbForceOpaque(button);
    } @catch (id exception) {
        static BOOL reported;
        if (!reported && PFBDebugIsRecording()) {
            reported = YES;
            PFBDebugLog(@"[navbar] gear repaint stopped: %@", exception);
        }
    }
}

- (void)didMoveToWindow {
    %orig;
    [self pfbGreySettingsGlyphIfNeeded];
}

- (void)layoutSubviews {
    %orig;
    [self pfbGreySettingsGlyphIfNeeded];
}

%end

// Probe: notes the first fade refused while a screen pushed above its navigation root is
// in front, where the shared bar's mark would leak, and the first refused on a root for
// comparison. One look every 50 ms at most, 20000 in all.
static int gPFBFadeProbeState;
static BOOL gPFBFadeProbeRootNoted;
static CFTimeInterval gPFBFadeProbeLast;
static NSUInteger gPFBFadeProbeLooks;

static void pfbFadeRefusedProbe(id refused, const char* route) {
    if (!NSThread.isMainThread) {
        return;
    }
    if (gPFBFadeProbeState == 0) {
        gPFBFadeProbeState = PFBProbeWants(@"07#F046 pushed") ? 1 : 2;
        gPFBFadeProbeRootNoted = !PFBProbeWants(@"07#F046 root");
    }
    if (gPFBFadeProbeState != 1) {
        return;
    }
    CFTimeInterval now = CACurrentMediaTime();
    if (now - gPFBFadeProbeLast < 0.05) {
        return;
    }
    gPFBFadeProbeLast = now;
    if (++gPFBFadeProbeLooks > 20000) {
        gPFBFadeProbeState = 2;
        return;
    }
    UIView* view = nil;
    if ([refused isKindOfClass:[UIView class]]) {
        view = refused;
    } else if ([refused isKindOfClass:[CALayer class]]) {
        id delegate = ((CALayer*)refused).delegate;
        view = [delegate isKindOfClass:[UIView class]] ? delegate : nil;
    }
    UIViewController* controller = PFBProbeControllerOfView(view);
    UINavigationController* navigation = nil;
    UIViewController* screen = controller;
    if ([controller isKindOfClass:[UINavigationController class]]) {
        navigation = (UINavigationController*)controller;
        screen = navigation.topViewController;
    } else {
        while (screen.parentViewController &&
               ![screen.parentViewController isKindOfClass:[UINavigationController class]]) {
            screen = screen.parentViewController;
        }
        navigation = (UINavigationController*)screen.parentViewController;
    }
    if (!navigation || !screen) {
        return;
    }
    NSString* viewName = NSStringFromClass([view class]);
    NSString* screenName = NSStringFromClass([screen class]);
    if (navigation.viewControllers.firstObject != screen) {
        if (PFBProbeWants(@"07#F046 pushed")) {
            PFBProbeNote(@"07#F046 pushed", @"07#F046 fade refused (%s) on %@ while %@ is in front, %lu screens deep above %@",
                         route, viewName, screenName, (unsigned long)navigation.viewControllers.count,
                         PFBProbeClassName(navigation.viewControllers.firstObject));
        }
        gPFBFadeProbeState = 2;
    } else if (!gPFBFadeProbeRootNoted) {
        gPFBFadeProbeRootNoted = YES;
        if (PFBProbeWants(@"07#F046 root")) {
            PFBProbeNote(@"07#F046 root", @"07#F046 fade refused (%s) on %@ on the root screen %@", route,
                         viewName, screenName);
        }
    }
}

// Partial opacity is refused where it is set, by all three routes into it. In
// setAlpha: and setOpacity:, any other view or layer pays one float comparison,
// which fails on the overwhelming majority of calls before anything else is read.

%hook UIView

- (void)setAlpha:(CGFloat)alpha {
    if (alpha < 1.0 && !pfbFadesAllowed() &&
        objc_getAssociatedObject(self.layer, kPFBNoFadeKey) != nil) {
        // Probe: notes where this refusal happens.
        if (gPFBFadeProbeState != 2) {
            pfbFadeRefusedProbe(self, "alpha");
        }
        %orig(1.0);
        return;
    }
    %orig;
}

%end

// True of the inbox filter pill or anything inside it. Tighter than the bar
// test below: the avatar in the same bar fades legitimately, and only this
// control must be held. Class name only, no message to a Swift class.
static BOOL pfbViewSitsInInboxPill(UIView* view) {
    UIView* node = view;
    NSInteger depth = 0;
    while (node && depth < 6) {
        if ([NSStringFromClass([node classForCoder])
                isEqualToString:@"_TtC10TFNUISwift34NavigationBarMenuBarButtonItemView"]) {
            return YES;
        }
        node = node.superview;
        depth++;
    }
    return NO;
}

// The app also animates the vibrancy filter onto the tab bar's icons. Handled only
// while a themed bar is switched on; otherwise the bar keeps its glass.
static BOOL PFBViewSitsInXTabBar(UIView* view) {
    if (!PFBThemedTabBarWanted()) {
        return NO;
    }
    Class xBar = NSClassFromString(@"_TtC11XNavigation10TabBarView");
    if (!xBar) {
        return NO;
    }
    for (UIView* v = view; v; v = v.superview) {
        if ([v isKindOfClass:xBar]) {
            return YES;
        }
    }
    return NO;
}

%hook CALayer

- (void)setOpacity:(float)opacity {
    if (opacity < 1.0f && !pfbFadesAllowed() &&
        objc_getAssociatedObject(self, kPFBNoFadeKey) != nil) {
        // Probe: notes where this refusal happens.
        if (gPFBFadeProbeState != 2) {
            pfbFadeRefusedProbe(self, "opacity");
        }
        %orig(1.0f);
        return;
    }
    %orig;
}

- (void)addAnimation:(CAAnimation*)animation forKey:(NSString*)key {
    UIView* owner = (UIView*)self.delegate;
    BOOL ownerIsView = [owner isKindOfClass:[UIView class]];

    // On iOS 27 the glass vibrancy filter is animated back onto the logo after the
    // tint is set; refusing it and dropping the filter keeps the chosen color. The
    // same holds for the tab bar's icons while a themed tab bar is wanted.
    if (ownerIsView && [key hasPrefix:@"filters."] &&
        (owner == (UIView*)PFBTopBarLogoViewCurrent() || PFBViewSitsInXTabBar(owner))) {
        self.filters = nil;
        return;
    }

    // Every animation on this one control is refused, not just opacity: the fade
    // never announces itself as an opacity change. Its neighbours in the same bar
    // are untouched.
    if (ownerIsView && pfbViewSitsInInboxPill(owner)) {
        return;
    }

    if (pfbFadesAllowed() || !objc_getAssociatedObject(self, kPFBNoFadeKey)) {
        %orig;
        return;
    }

    BOOL isFade = [key isEqualToString:@"opacity"];
    if (!isFade && [animation isKindOfClass:[CABasicAnimation class]]) {
        isFade = [((CABasicAnimation*)animation).keyPath isEqualToString:@"opacity"];
    }
    if (isFade) {
        // Probe: notes where this refusal happens.
        if (gPFBFadeProbeState != 2) {
            pfbFadeRefusedProbe(self, "animation");
        }
        return;
    }
    %orig;
}

%end

// The app recomputes its bar height on every layout pass, and under the iOS 26
// design the two heights alternate without end. Owner is identity only, never
// messaged: the state is dropped as soon as another bar comes through.
typedef struct {
    void* owner;
    double last;
    double before;
    double held;
    NSInteger flips;
    NSInteger writes;
    NSTimeInterval window;
    NSTimeInterval hold;
    const char* site;
} PFBHeightDamper;

static PFBHeightDamper gPFBFrameDamper = { NULL, -1, -1, -1, 0, 0, 0, 0, "frame" };
static PFBHeightDamper gPFBSimulatedDamper = { NULL, -1, -1, -1, 0, 0, 0, 0,
                                               "simulated" };

// A storm is a height that only undoes the previous one, or a sheer rate of writes:
// a storm runs at about 1500 writes a second, while a 120 Hz scroll, which moves
// this height on every frame, cannot exceed 60 per half second.
#define PFB_DAMP_FLIPS 8
#define PFB_DAMP_WRITES 250

// Probe: notes the first storm each site damps, with the fade window and the screen in
// front. The owner is the object whose own call is being damped, so it is alive here.
static BOOL gPFBStormProbeDone[2];

static void pfbStormProbe(PFBHeightDamper* state, void* owner, double height,
                          const char* pattern) {
    NSUInteger site = state == &gPFBSimulatedDamper ? 1 : 0;
    if (gPFBStormProbeDone[site]) {
        return;
    }
    gPFBStormProbeDone[site] = YES;
    NSString* key = site ? @"07#F004 simulated" : @"07#F004 frame";
    if (!PFBProbeWants(key)) {
        return;
    }
    NSString* screen = @"?";
    if (NSThread.isMainThread) {
        id object = (__bridge id)owner;
        if ([object isKindOfClass:[UINavigationController class]]) {
            screen = PFBProbeScreenName(((UINavigationController*)object).topViewController);
        } else if ([object isKindOfClass:[UIView class]]) {
            screen = PFBProbeScreenName(pfbBarOwningController(object));
        }
    }
    PFBProbeNote(key, @"07#F004 %s storm damped at %.0f pt (%s), fade window %@, front screen %@", state->site,
                 height, pattern, pfbFadesAllowed() ? @"open" : @"closed", screen);
}

// Returns the height to pass on. The caller always calls through: refusing the
// call leaves UIKit believing it set a geometry it never did, and its own
// invariants then run on a value it cannot see.
static double pfbDampedHeight(PFBHeightDamper* state, void* owner,
                              double height) {
    NSTimeInterval now = CACurrentMediaTime();
    if (owner != state->owner) {
        state->owner = owner;
        state->last = state->before = state->held = -1.0;
        state->flips = state->writes = 0;
        state->window = now;
        state->hold = 0;
    }
    if (now < state->hold) {
        return state->held >= 0.0 ? state->held : height;
    }
    if (now - state->window > 0.5) {
        state->window = now;
        state->flips = state->writes = 0;
    }
    state->writes++;
    if (height == state->before && height != state->last) {
        state->flips++;
    } else {
        state->flips = 0;
    }
    state->before = state->last;
    state->last = height;
    if (state->flips < PFB_DAMP_FLIPS && state->writes < PFB_DAMP_WRITES) {
        return height;
    }
    // Held long enough for the run loop to settle, then the app drives again.
    const char* pattern = state->flips >= PFB_DAMP_FLIPS ? "alternating" : "rate";
    state->held = height;
    state->hold = now + 0.5;
    state->flips = state->writes = 0;
    PFBDebugLog(@"[navbar] %s storm damped at %.0f pt (%s)", state->site, height,
                pattern);
    PFBCOMPAT_ACTION(PFBCompat_bar_repairs, @"bar height storm damped");
    // Probe: notes the first storm of each site.
    pfbStormProbe(state, owner, height, pattern);
    return height;
}

// Breaking the storm leaves the transition's fade unfinished: UIKit animates
// layer opacity, not view alpha. Removing the animation snaps each layer back
// to its model value, so views the app keeps hidden stay hidden.
static void pfbClearStaleFades(UIView* view, NSInteger depth) {
    if (!view || depth > 8) {
        return;
    }
    if ([view.layer animationForKey:@"opacity"]) {
        [view.layer removeAnimationForKey:@"opacity"];
    }
    for (UIView* subview in view.subviews) {
        pfbClearStaleFades(subview, depth + 1);
    }
}

// MARK: - the reply bar

// The reply bar is drawn by Twitter with no UIKit glass container, so the forced
// design never decorates it. Glass is laid behind its content as the toasts do:
// real glass when the class is there, thick material otherwise.
static const NSInteger kPFBReplyGlassTag = 0x50464247;
// Side margin of the floating capsule. At rest it matches the tab bar; while
// the keyboard is up it widens toward the native composer. The change rides the
// keyboard animation (see the keyboard observers below).
static const CGFloat kPFBReplyGlassInsetRest = 21.0;
static const CGFloat kPFBReplyGlassInsetFocused = 14.0;
static BOOL gPFBReplyFocused = NO;
static __weak UIView* gPFBReplyBar = nil;

static CGFloat pfbReplyInset(void) {
    return gPFBReplyFocused ? kPFBReplyGlassInsetFocused : kPFBReplyGlassInsetRest;
}

// The bar sits flush on the tab bar. The capsule is lifted off its bottom edge
// so the two read as two floating pieces rather than one two-storey block.
static const CGFloat kPFBReplyGlassGap = 8.0;
static const CGFloat kPFBReplyGlassRadius = 26.0;

static const void* kPFBReplyTintKey = &kPFBReplyTintKey;

// The label above the field sits flush on the capsule edge while the field
// carries its own text inset, so it gets the same padding to line up with it.
static const CGFloat kPFBReplyTextPad = 12.0;

// The app lays its content across the bar's full box while the capsule is inset
// and shorter, so text and buttons hang over the edges. Any child that reaches
// near the full width is brought inside the capsule, on both axes.
static void pfbInsetReplyContent(UIView* bar, CGFloat inset, CGFloat gap) {
    CGFloat wanted = bar.bounds.size.width - inset * 2.0;
    CGFloat capsule = bar.bounds.size.height - gap;
    if (wanted <= 0.0 || capsule <= 0.0) {
        return;
    }
    for (UIView* sub in bar.subviews) {
        if ([sub isKindOfClass:[UIVisualEffectView class]] || sub.hidden ||
            sub.bounds.size.width < bar.bounds.size.width * 0.9) {
            continue;
        }
        CGRect frame = sub.frame;
        BOOL label = [NSStringFromClass([sub class]) containsString:@"SocialContext"];
        frame.origin.x = inset + (label ? kPFBReplyTextPad : 0.0);
        frame.size.width = wanted - (label ? kPFBReplyTextPad * 2.0 : 0.0);
        // The capsule loses the gap at its bottom, so the whole stack moves up
        // by half of it to keep even margins. Relative order is preserved; only
        // a child that would still overrun the capsule is clamped.
        frame.origin.y = MAX(frame.origin.y - gap / 2.0, 0.0);
        if (CGRectGetMaxY(frame) > capsule) {
            if (frame.size.height >= capsule) {
                frame.origin.y = 0.0;
                frame.size.height = capsule;
            } else {
                frame.origin.y = capsule - frame.size.height;
            }
        }
        if (!CGRectEqualToRect(sub.frame, frame)) {
            sub.frame = frame;
        }
    }
}

// The field the text sits in carries its own opaque fill, the width of the bar,
// which covers the glass entirely. Cleared so the capsule shows through.
static void pfbClearReplyFieldFill(UIView* bar) {
    for (UIView* sub in bar.subviews) {
        if ([sub isKindOfClass:[UIVisualEffectView class]] || sub.hidden ||
            sub.bounds.size.height < 8.0) {
            continue;
        }
        CGFloat alpha = 0.0;
        [sub.backgroundColor getRed:NULL green:NULL blue:NULL alpha:&alpha];
        if (alpha > 0.05 && sub.bounds.size.width > bar.bounds.size.width * 0.8) {
            sub.backgroundColor = [UIColor clearColor];
        }
    }
}

// The bar draws hairline separators above and inside its button row. They read
// as leftover edges on a floating capsule, so any one-point colored strip goes.
static void pfbHideReplyHairlines(UIView* node, NSInteger depth) {
    if (!node || depth > 3) {
        return;
    }
    for (UIView* sub in node.subviews) {
        BOOL strip = sub.bounds.size.height <= 1.0 && sub.bounds.size.width > 100.0 &&
                     sub.backgroundColor != nil && sub.subviews.count == 0;
        if (strip && !sub.hidden) {
            sub.hidden = YES;
        }
        pfbHideReplyHairlines(sub, depth + 1);
    }
}

// The app lays an opaque backdrop behind the bar's host, level with it and
// running to the bottom of the screen. Cleared so the content shows through, as
// it does under a native floating bar.
static void pfbClearReplyBackdrop(UIView* bar) {
    UIView* host = bar.superview;
    UIView* stage = host.superview;
    if (!host || !stage) {
        return;
    }
    for (UIView* sibling in stage.subviews) {
        if (sibling == host || sibling.subviews.count > 0) {
            continue;
        }
        CGFloat alpha = 0.0;
        [sibling.backgroundColor getRed:NULL green:NULL blue:NULL alpha:&alpha];
        BOOL levelWithHost = fabs(sibling.frame.origin.y - host.frame.origin.y) < 1.0;
        if (levelWithHost && alpha >= 0.9 &&
            sibling.frame.size.height >= host.frame.size.height) {
            sibling.backgroundColor = [UIColor clearColor];
        }
    }
}

static void pfbGlassifyReplyBar(UIView* bar) {
    UIView* glass = [bar viewWithTag:kPFBReplyGlassTag];
    if (![PFBSettings boolForKey:@"enable_liquid_glass"]) {
        [glass removeFromSuperview];
        return;
    }
    if (!glass) {
        Class glassClass = NSClassFromString(@"UIGlassEffect");
        UIVisualEffect* effect = glassClass ? [[glassClass alloc] init] : nil;
        BOOL real = effect != nil;
        if (!effect) {
            effect =
                [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThickMaterial];
        }
        UIVisualEffectView* view =
            [[UIVisualEffectView alloc] initWithEffect:effect];
        view.tag = kPFBReplyGlassTag;
        view.userInteractionEnabled = NO;
        if (!real) {
            // Real glass shapes itself; the material needs its corners drawn.
            view.clipsToBounds = YES;
            view.layer.cornerCurve = kCACornerCurveContinuous;
        }
        [bar insertSubview:view atIndex:0];
        glass = view;
    }
    // A floating capsule, inset from both edges, not a full-bleed slab. The keyboard
    // resizes this bar, so the frame is taken on every pass.
    CGFloat inset = pfbReplyInset();
    CGRect box = CGRectInset(bar.bounds, inset, 0.0);
    box.size.height = MAX(box.size.height - kPFBReplyGlassGap, 1.0);
    if (!CGRectEqualToRect(glass.frame, box)) {
        glass.frame = box;
    }
    CGFloat radius = MIN(box.size.height / 2.0, kPFBReplyGlassRadius);
    if (glass.layer.cornerRadius != radius) {
        glass.layer.cornerRadius = radius;
        glass.layer.cornerCurve = kCACornerCurveContinuous;
    }
    // While the keyboard is up the glass takes a subtle tint, for legibility over
    // busy media. Set inside the keyboard animation, so it fades in step with it.
    BOOL tinted = gPFBReplyFocused;
    if ([objc_getAssociatedObject(glass, kPFBReplyTintKey) boolValue] != tinted) {
        objc_setAssociatedObject(glass, kPFBReplyTintKey, @(tinted),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        Class glassClass = NSClassFromString(@"UIGlassEffect");
        UIVisualEffect* effect = glassClass ? [[glassClass alloc] init] : nil;
        if (effect && [glass isKindOfClass:[UIVisualEffectView class]]) {
            if (tinted && [effect respondsToSelector:@selector(setTintColor:)]) {
                [(id)effect setTintColor:[[UIColor systemBackgroundColor]
                                             colorWithAlphaComponent:PFBGlassTint]];
            }
            ((UIVisualEffectView*)glass).effect = effect;
        }
    }
    pfbHideReplyHairlines(bar, 0);
    pfbClearReplyBackdrop(bar);
    pfbClearReplyFieldFill(bar);
    pfbInsetReplyContent(bar, inset, kPFBReplyGlassGap);
}

// The keyboard sets the focused state, and the width change is run inside the
// keyboard's own animation so the capsule widens or narrows in step with it.
static void pfbReplyInstallKeyboardObservers(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void (^apply)(NSNotification*, BOOL) = ^(NSNotification* note, BOOL focused) {
            gPFBReplyFocused = focused;
            UIView* bar = gPFBReplyBar;
            if (!bar.window) {
                return;
            }
            NSTimeInterval duration =
                [note.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
            UIViewAnimationCurve curve = (UIViewAnimationCurve)
                [note.userInfo[UIKeyboardAnimationCurveUserInfoKey] integerValue];
            [UIView animateWithDuration:duration
                                  delay:0.0
                                options:(UIViewAnimationOptions)(curve << 16)
                             animations:^{
                [bar setNeedsLayout];
                [bar layoutIfNeeded];
            }
                             completion:nil];
        };
        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIKeyboardWillShowNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification* note) {
            apply(note, YES);
        }];
        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIKeyboardWillHideNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification* note) {
            apply(note, NO);
        }];
    });
}

%hook T1PersistentComposeView

- (void)layoutSubviews {
    %orig;
    @try {
        gPFBReplyBar = (UIView*)self;
        pfbReplyInstallKeyboardObservers();
        pfbGlassifyReplyBar((UIView*)self);
    } @catch (id exception) {
        static BOOL reported;
        if (!reported && PFBDebugIsRecording()) {
            reported = YES;
            PFBDebugLog(@"[navbar] reply bar pass stopped: %@", exception);
        }
    }
}

%end

// Queued once per damping, after the hold has expired and the app drives again.
static void pfbQueueFadeRepair(UIView* bar) {
    if (objc_getAssociatedObject(bar, @selector(pfbFadeRepairPending))) {
        return;
    }
    objc_setAssociatedObject(bar, @selector(pfbFadeRepairPending), @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
      objc_setAssociatedObject(bar, @selector(pfbFadeRepairPending), nil,
                               OBJC_ASSOCIATION_RETAIN_NONATOMIC);
      if (bar.window) {
          pfbClearStaleFades(bar, 0);
          [bar setNeedsLayout];
          [bar.superview setNeedsLayout];
      }
    });
}

%hook TFNNavigationBar

// The app writes this bar's alternating heights through setFrame:, which sets the
// geometry without going through setBounds:, so the damper sits on it.
- (void)setFrame:(CGRect)frame {
    double damped =
        pfbDampedHeight(&gPFBFrameDamper, (__bridge void*)self, frame.size.height);
    if (damped != frame.size.height) {
        frame.size.height = damped;
        pfbQueueFadeRepair((UIView*)self);
    }
    %orig(frame);
}

%end

%hook TFNNavigationController

- (void)_tfn_setCurrentNavigationBarSimulatedHeight:(double)height
                                         isAnimated:(BOOL)animated {
    %orig(pfbDampedHeight(&gPFBSimulatedDamper, (__bridge void*)self, height),
          animated);
}

%end

// Each of these transition entry points opens the window in which the bar is
// allowed to fade.
%hook UINavigationController

- (BOOL)navigationBar:(UINavigationBar*)bar shouldPopItem:(UINavigationItem*)item {
    pfbOpenFadeWindow();
    return %orig;
}

- (UIViewController*)popViewControllerAnimated:(BOOL)animated {
    pfbOpenFadeWindow();
    return %orig;
}

- (void)pushViewController:(UIViewController*)controller animated:(BOOL)animated {
    pfbOpenFadeWindow();
    %orig;
}

%end

// MARK: - a portrait is not a glyph

// The avatar's image arrives as a template with the accent as its tint, so the
// picture is drawn as a flat disc of it. The rendering mode is corrected on this
// class alone; nothing is repainted and no view is walked.

%hook T1AvatarImageView

- (void)setImage:(UIImage*)image {
    if (image.renderingMode == UIImageRenderingModeAlwaysTemplate) {
        PFBCOMPAT_ACTION(PFBCompat_bar_repairs, @"avatar drawn as a picture");
        %orig([image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal]);
        return;
    }
    %orig;
}

%end
