//
//  ImmersivePlayer.x
//  PrimeFreeBird
//

#import "HookHelpers.h"

// MARK: - Immersive Player Timestamp

// The controls view keeps the label's mode in progressLabelMode, a payload-free
// Swift enum held in a single byte, and Twitter starts it on the countdown.
// Tapping the label flips that byte, so flipping it once per controls view has
// the same effect while leaving later taps free to flip it back. The byte is
// written rather than the tap replayed: the tap handler is not exposed to the
// Objective-C runtime on this build, so no message can reach it.
//
// The bar is unmounted while only the progress line shows and mounts fresh for
// the full strip, so each appearance starts from Twitter's countdown and gets
// one flip, on its first layout.

static const void* kNFBRestoredTimestampKey = &kNFBRestoredTimestampKey;

static void nfbRestoreTimestamp(UIView* controls) {
    if (!controls || ![BHTSettings boolForKey:@"restore_video_timestamp"] ||
        objc_getAssociatedObject(controls, kNFBRestoredTimestampKey)) {
        return;
    }
    Ivar modeIvar =
        class_getInstanceVariable(object_getClass(controls), "progressLabelMode");
    if (!modeIvar) {
        return;
    }
    objc_setAssociatedObject(controls, kNFBRestoredTimestampKey, @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    uint8_t* mode = (uint8_t*)(__bridge void*)controls + ivar_getOffset(modeIvar);
    *mode = *mode ? 0 : 1;
    // The mode is read while the controls build their configuration, so the
    // change needs one more pass to reach the label.
    [controls setNeedsLayout];
}

%hook _TtC14T1TwitterSwift17VideoControlsView

- (void)layoutSubviews {
    %orig;
    nfbRestoreTimestamp((UIView*)self);
}

%end

// MARK: - Disable video docking

// Docking shrinks a full-screen video into a floating mini player. Two paths
// reach it: the drop-zone view the card is dragged onto, and the controllers'
// own eligibility check — closing both leaves the swipe-to-dismiss gesture
// free to work normally.

%hook _TtC14T1TwitterSwift24ImmersivePiPDropZoneView

- (void)didMoveToWindow {
    %orig;

    if (![BHTSettings boolForKey:@"disable_video_docking"]) {
        return;
    }
    UIView* zone = (UIView*)self;
    zone.hidden = YES;
    zone.alpha = 0.0;
    zone.userInteractionEnabled = NO;
    for (UIView* sub in zone.subviews) {
        sub.hidden = YES;
        sub.alpha = 0.0;
        sub.userInteractionEnabled = NO;
    }
}

%end

// MARK: - Disable Immersive Feed Scrolling

// The card pan drives vertical paging between videos; blocking it lets the
// swipe-down dismiss gesture take over.
static BOOL isImmersiveCardPan(id viewController,
                               UIGestureRecognizer* gesture) {
    Ivar panIvar =
        class_getInstanceVariable([viewController class], "panRecognizer");
    return panIvar && object_getIvar(viewController, panIvar) == gesture;
}

%hook T1ImmersiveViewController

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer*)gesture {
    if ([BHTSettings boolForKey:@"disable_immersive_scroll"] &&
        isImmersiveCardPan(self, gesture)) {
        return NO;
    }

    return %orig;
}

- (BOOL)isCurrentCardDockEligible {
    if ([BHTSettings boolForKey:@"disable_video_docking"]) {
        return NO;
    }

    return %orig;
}

%end

// MARK: - Tap to pause
//
// A single tap on an immersive video toggles playback, and the bar follows the
// playback state: paused shows the full controls, playing keeps the bare
// progress line. The bar's presence is its state — Twitter unmounts the
// controls view entirely behind the progress line and mounts it back for the
// full strip — so mounted-or-not is read directly, and the native tap handler,
// the only lever that moves the bar, runs when that reading disagrees with the
// playback state. Videos open playing with the bar mounted, so the same match
// is applied again after every playback-state change: that folds the bar at
// open and on each swipe to the next video, and heals any drift. A glyph marks
// the pause at the centre of the card, where the app draws none of its own.

static const void* kNFBPausedGlyphKey = &kNFBPausedGlyphKey;
static const void* kNFBReconcilePendingKey = &kNFBReconcilePendingKey;
static const CGFloat kNFBPausedGlyphSize = 72.0;

// Marks a toggle synthesized by the tweak: playback is left alone, only the
// bar moves.
static BOOL gNFBSyntheticToggle = NO;

// Temporary instrumentation: a small on-screen readout of every decision this
// section takes, so a screenshot carries the ground truth out.
static NSMutableArray<NSString*>* gNFBImmersiveDiagLines = nil;

static void nfbImmersiveDiagShow(UIView* anchor, NSString* line) {
    if (!gNFBImmersiveDiagLines) {
        gNFBImmersiveDiagLines = [NSMutableArray array];
    }
    [gNFBImmersiveDiagLines addObject:line];
    while (gNFBImmersiveDiagLines.count > 7) {
        [gNFBImmersiveDiagLines removeObjectAtIndex:0];
    }
    UIWindow* window = anchor.window;
    if (!window) {
        return;
    }
    static const void* kNFBDiagHudKey = &kNFBDiagHudKey;
    UILabel* hud = objc_getAssociatedObject(window, kNFBDiagHudKey);
    if (!hud) {
        hud = [[UILabel alloc] init];
        hud.numberOfLines = 0;
        hud.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightMedium];
        hud.textColor = [UIColor whiteColor];
        hud.backgroundColor = [UIColor colorWithWhite:0 alpha:0.65];
        hud.layer.cornerRadius = 6;
        hud.clipsToBounds = YES;
        hud.userInteractionEnabled = NO;
        objc_setAssociatedObject(window, kNFBDiagHudKey, hud,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (hud.superview != window) {
        [window addSubview:hud];
    }
    hud.text = [gNFBImmersiveDiagLines componentsJoinedByString:@"\n"];
    CGSize fit = [hud sizeThatFits:CGSizeMake(280, 400)];
    hud.frame = CGRectMake(12, 64, fit.width + 12, fit.height + 8);
    [window bringSubviewToFront:hud];
}

static NSString* nfbDiagControls(UIView* controls) {
    if (!controls) {
        return @"c=\u2014";
    }
    return [NSString stringWithFormat:@"c=%.0fx%.0f a=%.1f",
                                      controls.bounds.size.width,
                                      controls.bounds.size.height, controls.alpha];
}


static TAVPlayer* nfbImmersivePagePlayer(UIView* pageView) {
    Ivar playerIvar = class_getInstanceVariable([pageView class], "player");
    return playerIvar ? object_getIvar(pageView, playerIvar) : nil;
}

// timeControlStatus follows AVPlayer: 0 paused, 1 waiting to play, 2 playing.
static void nfbTogglePlayback(TAVPlayer* player) {
    if (player.playbackState.timeControlStatus != 0) {
        [player pause];
    } else {
        // playOrReplay restarts at the end instead of doing nothing.
        [player playOrReplay];
    }
}

// The bar does not live inside the card — the card only forwards its state to
// it — so the search starts from the window the card is in. Looking under the
// card alone finds nothing, and a state that cannot be read is a state that
// cannot be matched.
static UIView* nfbImmersiveControlsView(UIView* card) {
    Class controlsClass =
        NSClassFromString(@"_TtC14T1TwitterSwift17VideoControlsView");
    if (!controlsClass) {
        return nil;
    }
    UIView* root = card.window ?: card;
    __block UIView* controls = nil;
    EnumerateSubviewsRecursively(root, ^(UIView* view) {
        if (!controls && [view isKindOfClass:controlsClass]) {
            controls = view;
        }
    });
    return controls;
}

// Built once per card and kept as an associated object. Touches pass through
// it, so the card's own tap gesture stays the only thing handling them.
static UIView* nfbPausedGlyph(UIView* card) {
    UIView* glyph = objc_getAssociatedObject(card, kNFBPausedGlyphKey);
    if (glyph) {
        return glyph;
    }
    UIBlurEffect* blur =
        [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark];
    UIVisualEffectView* backdrop = [[UIVisualEffectView alloc] initWithEffect:blur];
    backdrop.userInteractionEnabled = NO;
    backdrop.frame = CGRectMake(0, 0, kNFBPausedGlyphSize, kNFBPausedGlyphSize);
    backdrop.layer.cornerRadius = kNFBPausedGlyphSize / 2.0;
    backdrop.clipsToBounds = YES;
    backdrop.autoresizingMask =
        UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin |
        UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    UIImageSymbolConfiguration* size =
        [UIImageSymbolConfiguration configurationWithPointSize:30
                                                        weight:UIImageSymbolWeightBold];
    UIImageView* icon = [[UIImageView alloc]
        initWithImage:[UIImage systemImageNamed:@"play.fill" withConfiguration:size]];
    icon.tintColor = [UIColor whiteColor];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [backdrop.contentView addSubview:icon];
    [NSLayoutConstraint activateConstraints:@[
        [icon.centerXAnchor constraintEqualToAnchor:backdrop.contentView.centerXAnchor
                                           constant:2.0],
        [icon.centerYAnchor constraintEqualToAnchor:backdrop.contentView.centerYAnchor]
    ]];
    objc_setAssociatedObject(card, kNFBPausedGlyphKey, backdrop,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return backdrop;
}

// Shown centred over the card while paused, taken down as soon as playback
// resumes or the card is remounted for another video.
static void nfbShowPausedGlyph(UIView* card, BOOL paused) {
    UIView* glyph = paused ? nfbPausedGlyph(card)
                           : objc_getAssociatedObject(card, kNFBPausedGlyphKey);
    if (!glyph) {
        return;
    }
    if (paused) {
        if (glyph.superview != card) {
            [card addSubview:glyph];
        }
        glyph.center = CGPointMake(CGRectGetMidX(card.bounds),
                                   CGRectGetMidY(card.bounds));
        [card bringSubviewToFront:glyph];
    }
    glyph.hidden = !paused;
}

%hook _TtC14T1TwitterSwift17ImmersiveCardView

- (void)handleSingleTap:(UITapGestureRecognizer*)tap {
    UIView* card = (UIView*)self;
    UIView* controls = nfbImmersiveControlsView(card);

    // A synthesized tap only moves the bar; a tap with the option off keeps the
    // native behavior. The mirror follows the toggle in both cases.
    if (gNFBSyntheticToggle || ![BHTSettings boolForKey:@"tap_to_pause"]) {
        nfbImmersiveDiagShow(
            card, [NSString stringWithFormat:@"%@ %@",
                                             gNFBSyntheticToggle ? @"syn" : @"off",
                                             nfbDiagControls(controls)]);
        %orig;
        return;
    }

    __block UIView* pageView = nil;
    EnumerateSubviewsRecursively(card, ^(UIView* view) {
        if (!pageView &&
            [view isKindOfClass:%c(_TtC14T1TwitterSwift22ImmersiveVideoPageView)]) {
            pageView = view;
        }
    });

    TAVPlayer* player = pageView ? nfbImmersivePagePlayer(pageView) : nil;
    if (!player) {
        nfbImmersiveDiagShow(card, [NSString stringWithFormat:@"nop %@",
                                                             nfbDiagControls(controls)]);
        %orig;
        return;
    }

    BOOL wasPlaying = player.playbackState.timeControlStatus != 0;
    nfbTogglePlayback(player);
    [(_TtC14T1TwitterSwift17ImmersiveCardView*)self setPausedByUser:wasPlaying];

    // The bar belongs mounted while paused and gone while playing.
    BOOL paused = wasPlaying;
    BOOL expanded = (controls != nil);
    BOOL runsToggle = (expanded != paused);
    nfbImmersiveDiagShow(
        card, [NSString stringWithFormat:@"tap %@ exp=%@ p=%@ orig=%@",
                                         nfbDiagControls(controls),
                                         expanded ? @"Y" : @"N", paused ? @"P" : @"J",
                                         runsToggle ? @"Y" : @"N"]);
    if (runsToggle) {
        %orig;
    }
    nfbShowPausedGlyph(card, paused);
}

// A recycled card carries its glyph into the next video; playback there starts
// on its own, so the glyph comes down with the move.
- (void)didMoveToWindow {
    %orig;
    nfbShowPausedGlyph((UIView*)self, NO);
}

%end

// Playback-state changes are the one signal that fires at autoplay, at every
// swipe to a new video and at the end of one, so the bar is re-matched to the
// playback state here, off the tap path. The synthesized tap goes through the
// card's own recognizer; without it nothing is sent — a bar out of place is
// better than a crash on a handler that may read it.
%hook _TtC14T1TwitterSwift22ImmersiveVideoPageView

- (void)player:(id)player didUpdatePlaybackState:(id)playbackState {
    %orig;
    if (![BHTSettings boolForKey:@"tap_to_pause"]) {
        return;
    }
    UIView* page = (UIView*)self;
    Class cardClass =
        NSClassFromString(@"_TtC14T1TwitterSwift17ImmersiveCardView");
    UIView* card = cardClass ? page.superview : nil;
    while (card && ![card isKindOfClass:cardClass]) {
        card = card.superview;
    }
    if (!card ||
        [objc_getAssociatedObject(card, kNFBReconcilePendingKey) boolValue]) {
        return;
    }
    objc_setAssociatedObject(card, kNFBReconcilePendingKey, @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
            objc_setAssociatedObject(card, kNFBReconcilePendingKey, nil,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            if (!card.window) {
                return;
            }
            TAVPlayer* current = nfbImmersivePagePlayer(page);
            NSInteger status = current.playbackState.timeControlStatus;
            // 1 is waiting to play: not a state worth matching the bar to.
            if (!current || status == 1) {
                return;
            }
            BOOL paused = (status == 0);
            BOOL expanded = (nfbImmersiveControlsView(card) != nil);
            if (expanded == paused) {
                return;
            }
            Ivar recognizerIvar = class_getInstanceVariable(
                object_getClass(card), "singleTapRecognizer");
            id recognizer =
                recognizerIvar ? object_getIvar(card, recognizerIvar) : nil;
            if (!recognizer) {
                nfbImmersiveDiagShow(card, @"rec skip norec");
                return;
            }
            nfbImmersiveDiagShow(
                card, [NSString stringWithFormat:@"rec p=%@ exp=%@ syn",
                                                 paused ? @"P" : @"J",
                                                 expanded ? @"Y" : @"N"]);
            gNFBSyntheticToggle = YES;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [card performSelector:@selector(handleSingleTap:)
                       withObject:recognizer];
#pragma clang diagnostic pop
            gNFBSyntheticToggle = NO;
        });
}

%end
