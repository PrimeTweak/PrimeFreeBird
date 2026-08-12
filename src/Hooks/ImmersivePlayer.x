//
//  ImmersivePlayer.x
//  PrimeFreeBird
//

#import "HookHelpers.h"

// MARK: - Immersive Player Timestamp

// The controls view keeps the label's mode in progressLabelMode, a payload-free
// Swift enum held in a single byte, and Twitter starts it on the countdown.
// Tapping the label flips that byte, so flipping it here once per controls view
// has the same effect while leaving later taps free to flip it back. The byte is
// written rather than the tap replayed: the tap handler is not exposed to the
// Objective-C runtime on this build, so no message can reach it.

static const void* kNFBRestoredTimestampKey = &kNFBRestoredTimestampKey;

%hook _TtC14T1TwitterSwift17VideoControlsView

- (void)layoutSubviews {
    %orig;

    if (![BHTSettings boolForKey:@"restore_video_timestamp"]) {
        return;
    }
    if (objc_getAssociatedObject(self, kNFBRestoredTimestampKey)) {
        return;
    }
    Ivar modeIvar = class_getInstanceVariable([self class], "progressLabelMode");
    if (!modeIvar) {
        return;
    }
    objc_setAssociatedObject(self, kNFBRestoredTimestampKey, @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    uint8_t* mode = (uint8_t*)(__bridge void*)self + ivar_getOffset(modeIvar);
    *mode = *mode ? 0 : 1;
    // The mode is read while the controls build themselves, so the change needs
    // one more pass to reach the label.
    [self setNeedsLayout];
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
// A single tap on an immersive video toggles playback. The player is not
// exposed, so it is read from the page view's ivar. The controls follow the
// playback state rather than flipping with every tap: paused shows them,
// playing hides them. The native handler is what moves them, so it runs only
// when the state it would produce is the one wanted. A glyph marks the pause
// at the centre of the card, where the app draws none of its own.

static const void* kNFBPausedGlyphKey = &kNFBPausedGlyphKey;
static const CGFloat kNFBPausedGlyphSize = 72.0;

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

// The controls bar mounted in this card, or nil while it is not built yet.
static UIView* nfbImmersiveControlsView(UIView* card) {
    Class controlsClass =
        NSClassFromString(@"_TtC14T1TwitterSwift17VideoControlsView");
    if (!controlsClass) {
        return nil;
    }
    __block UIView* controls = nil;
    EnumerateSubviewsRecursively(card, ^(UIView* view) {
        if (!controls && [view isKindOfClass:controlsClass]) {
            controls = view;
        }
    });
    return controls;
}

static BOOL nfbControlsAreVisible(UIView* controls) {
    return controls && !controls.hidden && controls.alpha > 0.5;
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
    if (![BHTSettings boolForKey:@"tap_to_pause"]) {
        %orig;
        return;
    }

    UIView* card = (UIView*)self;
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

    // The controls belong up while paused and down while playing. The native
    // handler only flips them, so it is called when — and only when — the flip
    // lands on the wanted state. With no controls mounted, it keeps its say.
    UIView* controls = nfbImmersiveControlsView(card);
    BOOL paused = wasPlaying;
    if (!controls || nfbControlsAreVisible(controls) != paused) {
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
