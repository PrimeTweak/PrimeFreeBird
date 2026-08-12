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
static const void* kNFBMinimalClockKey = &kNFBMinimalClockKey;
static const CGFloat kNFBPausedGlyphSize = 72.0;

// Marks a toggle synthesized by the tweak: playback is left alone, only the
// bar moves.
static BOOL gNFBSyntheticToggle = NO;

// The player is not exposed by the page view: it is read from its ivar.
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

// MARK: - Timestamp beside the progress line
//
// The controls view is unmounted while only the progress line shows, and the
// line itself carries no label — it is a bare set of layers. The elapsed and
// total times are therefore drawn here, in a label of the tweak's own, placed
// above the line and following the same option as the one in the full bar.

static NSString* nfbClockText(CMTime time) {
    CGFloat seconds = CMTIME_IS_NUMERIC(time) ? CMTimeGetSeconds(time) : 0.0;
    if (seconds < 0 || !isfinite(seconds)) {
        seconds = 0.0;
    }
    NSInteger total = (NSInteger)seconds;
    NSInteger hours = total / 3600;
    if (hours > 0) {
        return [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)hours,
                                          (long)((total / 60) % 60), (long)(total % 60)];
    }
    return [NSString stringWithFormat:@"%ld:%02ld", (long)(total / 60),
                                      (long)(total % 60)];
}

// The bare progress line: the view that stays on screen once the controls are
// gone, and the anchor the label is placed against.
static UIView* nfbProgressLineView(UIView* card) {
    Class lineClass =
        NSClassFromString(@"_TtC14T1TwitterSwift26ImmersiveVideoTimelineView");
    if (!lineClass) {
        return nil;
    }
    __block UIView* line = nil;
    EnumerateSubviewsRecursively(card, ^(UIView* view) {
        if (!line && [view isKindOfClass:lineClass]) {
            line = view;
        }
    });
    return line;
}

static UILabel* nfbMinimalClock(UIView* card) {
    UILabel* clock = objc_getAssociatedObject(card, kNFBMinimalClockKey);
    if (clock) {
        return clock;
    }
    clock = [[UILabel alloc] init];
    clock.userInteractionEnabled = NO;
    clock.textColor = [UIColor whiteColor];
    clock.font = [UIFont monospacedDigitSystemFontOfSize:13
                                                  weight:UIFontWeightSemibold];
    clock.layer.shadowColor = [UIColor blackColor].CGColor;
    clock.layer.shadowOpacity = 0.45;
    clock.layer.shadowRadius = 3.0;
    clock.layer.shadowOffset = CGSizeZero;
    objc_setAssociatedObject(card, kNFBMinimalClockKey, clock,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return clock;
}

// Drawn only while the bar is away: the full bar carries a label of its own.
static void nfbUpdateMinimalClock(UIView* card, TAVPlayer* player) {
    UILabel* existing = objc_getAssociatedObject(card, kNFBMinimalClockKey);
    if (![BHTSettings boolForKey:@"restore_video_timestamp"] || !player ||
        nfbImmersiveControlsView(card) != nil) {
        existing.hidden = YES;
        return;
    }
    UIView* line = nfbProgressLineView(card);
    if (!line || !line.window) {
        existing.hidden = YES;
        return;
    }
    TAVPlaybackState* state = player.playbackState;
    UILabel* clock = nfbMinimalClock(card);
    clock.text = [NSString stringWithFormat:@"%@ / %@", nfbClockText(state.currentTime),
                                            nfbClockText(state.duration)];
    [clock sizeToFit];
    if (clock.superview != card) {
        [card addSubview:clock];
    }
    CGRect anchor = [line convertRect:line.bounds toView:card];
    clock.frame = CGRectMake(CGRectGetMinX(anchor),
                             CGRectGetMinY(anchor) - CGRectGetHeight(clock.bounds) - 8.0,
                             CGRectGetWidth(clock.bounds), CGRectGetHeight(clock.bounds));
    clock.hidden = NO;
    [card bringSubviewToFront:clock];
}

%hook _TtC14T1TwitterSwift17ImmersiveCardView

- (void)handleSingleTap:(UITapGestureRecognizer*)tap {
    UIView* card = (UIView*)self;
    UIView* controls = nfbImmersiveControlsView(card);

    // A synthesized tap only moves the bar; a tap with the option off keeps the
    // native behavior. The mirror follows the toggle in both cases.
    if (gNFBSyntheticToggle || ![BHTSettings boolForKey:@"tap_to_pause"]) {
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
    if (runsToggle) {
        %orig;
    }
    nfbShowPausedGlyph(card, paused);
    nfbUpdateMinimalClock(card, player);
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
    UIView* page = (UIView*)self;
    Class hostClass =
        NSClassFromString(@"_TtC14T1TwitterSwift17ImmersiveCardView");
    UIView* host = hostClass ? page.superview : nil;
    while (host && ![host isKindOfClass:hostClass]) {
        host = host.superview;
    }
    if (host) {
        nfbUpdateMinimalClock(host, nfbImmersivePagePlayer(page));
    }
    if (![BHTSettings boolForKey:@"tap_to_pause"]) {
        return;
    }
    UIView* card = host;
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
                return;
            }
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
