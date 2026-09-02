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

// The card on screen, so the bar can reach it the moment it mounts. Weak: a
// card that goes away leaves nothing behind. The fold itself is defined with
// the tap section further down, and announced here because the controls view —
// hooked just below — is what asks for it.
static __weak UIView* gNFBActiveCard = nil;
// When a card entered the window. The bar and the fold both read it, and the
// bar's hook sits at the top of this file, so it is declared here.
static const void* kNFBCardShownAtKey = &kNFBCardShownAtKey;
// Measured on screen at 60 frames a second: the app animates its overlay in
// over about six frames while the timeline is still on its way out, and the
// fold can only answer once those views exist. The bar is therefore kept clear
// for the length of that animation — the bar alone, never the card: the card's
// visibility is what gates autoplay, and dimming it stops playback outright.
static const NSTimeInterval kNFBBarRevealDelay = 0.3;
// When the reader last tapped. The player reports its state through an
// asynchronous machine, so for a moment after a tap it still answers with the
// old one — long enough for the fold to read "playing" while the bar is coming
// up for a pause, and take it straight back down. The reader's own tap already
// put the bar where it belongs, so nothing else touches it for a beat.
static NSTimeInterval gNFBLastUserTap = 0;
static const NSTimeInterval kNFBUserTapGrace = 0.6;

// A view the app animates in with the presentation and folds away a moment
// later is held clear for the length of that animation, then given back
// unconditionally — an invisible one would be worse than a visible flash.
// Only the app's own overlay plugins are treated this way, never the card and
// never anything carrying the video: the card's visibility is what gates
// autoplay, and dimming it stops playback outright.
// TEMPORARY probe for the opening flash. Read only: it adds no view, changes
// no alpha and takes no decision. Milliseconds are counted from the moment the
// card registers, so every line below is comparable on one timeline.
static UIView* nfbImmersiveControlsView(UIView* card);

// The app's own chrome for a full-screen video: avatar, name, follow control,
// engagement actions, back button, top gradient and the bottom bar. It is
// painted while the video is opening and taken down a moment later, and that
// moment is what the reader sees. Every one of these was read off the screen,
// not guessed, and each name is present in the binary.
//
// They are kept out of sight for the length of the opening only. Afterwards the
// view is left entirely alone, so a tap that asks for the controls still gets
// them.
// Whether the reader has asked for the app's chrome on the video now showing.
// Measured: the app drives every piece of chrome with alpha and re-asserts
// alpha 1 continuously - hundreds of times while a video plays - so no window
// of time can hold it down. It is also asserted while the player reports
// playing, paused and no state at all, so the playback state cannot tell the
// two apart either. What does tell them apart is who asked: a tap the reader
// made, or the app bringing it up on its own. Cleared for every new video,
// raised by a real tap.
//
// Nothing that is visible once a video has settled is suppressed by this: every
// one of these views ends at alpha 0 on its own. Only the ride up and back down
// is taken away.
static BOOL gNFBReaderAskedForChrome = NO;

// Read once per video rather than on every setAlpha: the app re-asserts alpha
// hundreds of times while a video plays, and the setting cannot change while
// one is on screen - the settings page is not.
static BOOL gNFBCleanPlayerOn = NO;

static void nfbRefreshCleanPlayerFlag(void) {
    gNFBCleanPlayerOn = [BHTSettings boolForKey:@"tap_to_pause"];
}

static BOOL nfbChromeIsUnasked(void) {
    return !gNFBReaderAskedForChrome && gNFBCleanPlayerOn;
}
static void nfbHoldThroughOpening(UIView* view) {
    if (!view.window || ![BHTSettings boolForKey:@"tap_to_pause"]) {
        return;
    }
    UIView* card = gNFBActiveCard;
    NSTimeInterval shownAt =
        card ? [objc_getAssociatedObject(card, kNFBCardShownAtKey) doubleValue] : 0;
    NSTimeInterval since = [NSDate timeIntervalSinceReferenceDate] - shownAt;
    if (shownAt <= 0 || since >= kNFBBarRevealDelay) {
        return;
    }
    view.alpha = 0.0;
    __weak UIView* weakView = view;
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW,
                      (int64_t)((kNFBBarRevealDelay - since) * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
          UIView* strongView = weakView;
          if (strongView) {
              strongView.alpha = 1.0;
          }
        });
}

static BOOL nfbFoldIfDue(UIView* card);

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

// The bar announcing its own arrival is the earliest the fold can possibly be
// asked for — one turn of the run loop, before the frame that would show it.
// Polling only ever caught it later.
- (void)didMoveToWindow {
    %orig;
    UIView* bar = (UIView*)self;
    if (!bar.window) {
        return;
    }
    // Mounting while a card is opening means this is the overlay riding in on
    // the presentation, not a bar the reader asked for.
    nfbHoldThroughOpening(bar);
    dispatch_async(dispatch_get_main_queue(), ^{
      nfbFoldIfDue(gNFBActiveCard);
    });
}

%end

// MARK: - Disable video docking

// Docking shrinks a full-screen video into a floating mini player. Two paths
// reach it: the drop-zone view the card is dragged onto, and the controllers'
// own eligibility check — closing both leaves the swipe-to-dismiss gesture
// free to work normally.

// MARK: - A tap opens a video, it does not wake the sound

// The timeline's video view carries a flag whose whole job is "a tap turns the
// sound on": isAutoUnmuteEnabled, one byte beside isHoldingInlineAudioFocus.
// That is why a tapped video came out of the timeline unmuted and stayed that
// way, while its neighbours kept quiet — the tap that opens full screen is the
// same tap that lifts the mute. The flag is cleared here, on the view itself,
// before its handler runs. The speaker button in the controls is untouched, and
// so is every other route to the sound.

// One rule, and no timing at all: the sound is off unless the reader turned it
// on, and the only thing that turns it on is the speaker button on this bar.
// Stretches of silence armed around each suspected moment were always one
// signal short — the app wakes the sound on opening, on leaving, and on its own
// mid-playback, each by a different route, and a stretch that ends is a hole.
static BOOL gNFBSoundAllowed = NO;

// Whether a video opens silent. The reader chooses; the stored default keeps
// the previous behaviour.
static BOOL nfbOpensMuted(void) {
    return [BHTSettings boolForKey:@"video_starts_muted"];
}

// The state the flag takes when a video is opened from the timeline.
static BOOL nfbSoundAllowedAtOpen(void) {
    return !nfbOpensMuted();
}

static void nfbClearAutoUnmute(UIView* view) {
    Ivar flagIvar =
        class_getInstanceVariable(object_getClass(view), "isAutoUnmuteEnabled");
    if (!flagIvar) {
        return;
    }
    uint8_t* flag = (uint8_t*)(__bridge void*)view + ivar_getOffset(flagIvar);
    *flag = 0;
}

%hook T1InlineVideoView

- (void)didMoveToWindow {
    %orig;
    nfbClearAutoUnmute((UIView*)self);
}

- (void)handleTapWithTapRecognizer:(UITapGestureRecognizer*)recognizer {
    nfbClearAutoUnmute((UIView*)self);
    // A video opened from the timeline starts in the chosen state, whatever the
    // last one was left as.
    gNFBSoundAllowed = nfbSoundAllowedAtOpen();
    gNFBReaderAskedForChrome = NO;
    nfbRefreshCleanPlayerFlag();
    %orig;
}

%end

// Every door the sound comes through, all closed unless the reader opened them.
// The mute flag is only one of two levers: the player also carries a volume,
// and the handover back to the timeline raises that one — which is why a
// player left muted still made a sound on the way out. Playback covers a player
// born loud, which is how a full-screen video arrives and how the timeline
// takes one back.
%hook TAVPlayer

// Every guard below is gated on the clean player. With it off, Twitter's own
// controls are on screen and its own sound button must work: holding the mute
// there would silence the video with nothing left to lift it.
- (void)setIsMuted:(BOOL)muted {
    if (!muted && !gNFBSoundAllowed &&
        [BHTSettings boolForKey:@"tap_to_pause"] && nfbOpensMuted()) {
        return;
    }
    %orig;
}

- (void)setVolume:(float)volume {
    if (volume > 0 && !gNFBSoundAllowed &&
        [BHTSettings boolForKey:@"tap_to_pause"] && nfbOpensMuted()) {
        %orig(0);
        return;
    }
    %orig;
}

- (void)play {
    if (!gNFBSoundAllowed && [BHTSettings boolForKey:@"tap_to_pause"] &&
        nfbOpensMuted()) {
        self.isMuted = YES;
        self.volume = 0;
    }
    %orig;
}

- (void)playOrReplay {
    if (!gNFBSoundAllowed && [BHTSettings boolForKey:@"tap_to_pause"] &&
        nfbOpensMuted()) {
        self.isMuted = YES;
        self.volume = 0;
    }
    %orig;
}

%end

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

// Leaving full screen hands the sound back to the timeline, and it escapes for
// a moment on the way. The same window is armed here, so the handover is silent
// from the first frame of the dismissal.
%hook T1ImmersiveFullScreenViewController

%end

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

// The synthetic tap goes through Twitter's own handler, which moves the bar AND
// the playback state. The reconciler then measures a state its own tap just
// changed and asks again, which is how a single opening produced dozens of taps
// in bursts. One tap per card per cooldown breaks that loop: the first fold
// still happens at once, and nothing can chase its own tail afterwards.
static const NSTimeInterval kNFBFoldCooldown = 0.4;
static const void* kNFBLastFoldKey = &kNFBLastFoldKey;

static const void* kNFBPausedGlyphKey = &kNFBPausedGlyphKey;
static const void* kNFBReconcilePendingKey = &kNFBReconcilePendingKey;
static const void* kNFBMinimalBarKey = &kNFBMinimalBarKey;
static const void* kNFBMinimalTimerKey = &kNFBMinimalTimerKey;
// The app cross-fades the timeline into the immersive player, and the timeline
// carries its own control bar out of the frame. This bar waits for that to
// finish rather than joining it: two sets of times on screen at once read as a
// glitch, however brief.
// Measured at 60 frames a second on the opening: the app's overlay is gone by
// the ninth frame, about 150 ms. This waits just past that and no longer —
// every extra millisecond is a hole where nothing is on screen.
static const NSTimeInterval kNFBOpeningSettle = 0.18;
// While a card is opening, a player that reports "waiting to play" is a player
// about to play: the app draws its overlay over the outgoing timeline for the
// length of that transition, and waiting for the first frame of video before
// folding is what leaves it on screen.
static const NSTimeInterval kNFBOpeningWindow = 0.9;
static const NSInteger kNFBMinimalTrackTag = 90211;
static const NSInteger kNFBMinimalFillTag = 90212;
static const NSInteger kNFBMinimalClockTag = 90213;
static const NSInteger kNFBMinimalMuteTag = 90214;
static const NSInteger kNFBMinimalGripTag = 90215;
static const CGFloat kNFBMinimalMuteSize = 34.0;
// The track is three points tall — too thin to catch a thumb — so an invisible
// band of its own width carries the touch, and the track thickens under it.
static const CGFloat kNFBMinimalGripHeight = 26.0;
static const CGFloat kNFBScrubTrackHeight = 6.0;
static const void* kNFBScrubbingKey = &kNFBScrubbingKey;
static const void* kNFBScrubRatioKey = &kNFBScrubRatioKey;
static NSTimeInterval gNFBLastSeek = 0;
static const CGFloat kNFBPausedGlyphSize = 72.0;

// Marks a toggle synthesized by the tweak: playback is left alone, only the
// bar moves.
static BOOL gNFBSyntheticToggle = NO;

// The player is not exposed by the page view: it is read from its ivar.
static TAVPlayer* nfbImmersivePagePlayer(UIView* pageView) {
    Ivar playerIvar = class_getInstanceVariable([pageView class], "player");
    return playerIvar ? object_getIvar(pageView, playerIvar) : nil;
}

// The page view of a card, and the player it holds — the timer has only the
// card to work from.
static TAVPlayer* nfbCardPlayer(UIView* card) {
    Class pageClass =
        NSClassFromString(@"_TtC14T1TwitterSwift22ImmersiveVideoPageView");
    if (!pageClass) {
        return nil;
    }
    __block UIView* pageView = nil;
    EnumerateSubviewsRecursively(card, ^(UIView* view) {
        if (!pageView && [view isKindOfClass:pageClass]) {
            pageView = view;
        }
    });
    return pageView ? nfbImmersivePagePlayer(pageView) : nil;
}

// Twitter's own tap handler turns the sound on as well as moving the controls,
// and this tweak has always kept that off: before, by swallowing the tap
// entirely — which is why the controls never came back either. Now the handler
// runs and the audio state is put back around it.
//
// The decision does not live on the player. The immersive session owns it, in
// an ImmersiveAudioSessionManager held by the card host, whose isMuted byte is
// what every card reads — a player put back on its own is overruled by the next
// pass. Both are restored: the session's byte, so the decision stands, and the
// player, so the sound stops now. Sound changes go through the same
// asynchronous machine as playback, so it is done on this turn and the next few.

// The session manager sits on the host view above the cards.
static id nfbImmersiveAudioManager(UIView* card) {
    Class hostClass =
        NSClassFromString(@"_TtC14T1TwitterSwift21ImmersiveCardHostView");
    if (!hostClass) {
        return nil;
    }
    UIView* host = card;
    while (host && ![host isKindOfClass:hostClass]) {
        host = host.superview;
    }
    if (!host) {
        return nil;
    }
    Ivar managerIvar =
        class_getInstanceVariable(object_getClass(host), "audioSessionManager");
    return managerIvar ? object_getIvar(host, managerIvar) : nil;
}

// isMuted is a single byte on that manager, as progressLabelMode is on the
// controls: read and written in place, since no setter is exposed.
static uint8_t* nfbAudioMutedByte(id manager) {
    if (!manager) {
        return NULL;
    }
    Ivar mutedIvar = class_getInstanceVariable(object_getClass(manager), "isMuted");
    if (!mutedIvar) {
        return NULL;
    }
    return (uint8_t*)(__bridge void*)manager + ivar_getOffset(mutedIvar);
}

static void nfbApplyMuted(TAVPlayer* player, id manager, BOOL muted) {
    uint8_t* sessionMuted = nfbAudioMutedByte(manager);
    if (sessionMuted) {
        *sessionMuted = muted ? 1 : 0;
    }
    if (player) {
        if (player.isMuted != muted) {
            player.isMuted = muted;
        }
        // The volume is the other half of the state: a player unmuted at zero
        // volume is still silent.
        player.volume = muted ? 0.0 : 1.0;
    }
}

// The player is asked first: it is what is actually heard. The session byte is
// only the app's memory of the decision, and a mute imposed at playback goes
// straight to the player without touching it.
static BOOL nfbCurrentMuted(UIView* card, TAVPlayer* player) {
    if (player) {
        return player.isMuted;
    }
    uint8_t* sessionMuted = nfbAudioMutedByte(nfbImmersiveAudioManager(card));
    return sessionMuted ? *sessionMuted != 0 : NO;
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
static UIView* nfbFirstDescendantOfClass(UIView* root, Class cls) {
    for (UIView* sub in root.subviews) {
        if ([sub isKindOfClass:cls]) {
            return sub;
        }
        UIView* found = nfbFirstDescendantOfClass(sub, cls);
        if (found) {
            return found;
        }
    }
    return nil;
}

// The controls bar on screen. Measured: the bar is NOT a descendant of the
// card, so the search has to start at the window. Narrowing it to the card
// returns nil every time, the reconciler never folds, and Twitter's overlay
// stays up for good.
static UIView* nfbImmersiveControlsView(UIView* card) {
    Class controlsClass =
        NSClassFromString(@"_TtC14T1TwitterSwift17VideoControlsView");
    if (!controlsClass) {
        return nil;
    }
    UIView* root = card.window ?: card;
    // Depth-first and out at the first match. The enumerator it replaces kept
    // visiting every view after finding the bar, and this runs on every tick
    // of the fold watch.
    return nfbFirstDescendantOfClass(root, controlsClass);
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

// MARK: - Minimal bar
//
// Twitter mounts and unmounts its whole bottom bar as one piece: when the
// controls go, the progress line goes with them and nothing is left over the
// video. The minimal state is therefore drawn here — a track, its fill, and the
// times above — and it lives only while the app's own bar is away. The player
// is polled on a timer rather than driven by playback callbacks, so the fill
// advances at a steady rate whatever the app reports and when.

// Measured off the app's own bar: the line sits 49 pt above the safe area and
// is 3 pt tall edge to edge, and the times ride 20 pt above it in the system
// face at 15 pt, regular, in the app's secondary gray. Keeping the same
// geometry means the line does not move when Twitter's bar takes over.
static const CGFloat kNFBMinimalTrackHeight = 3.0;
static const CGFloat kNFBMinimalTrackLift = 49.0;
static const CGFloat kNFBMinimalClockLift = 20.0;
static const CGFloat kNFBMinimalTextInset = 14.0;
static const CGFloat kNFBMinimalFade = 0.25;

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

// Track, fill and clock in one container, built once per card and kept as an
// associated object. Touches pass through: the card's tap gesture stays the
// only thing handling them.
static void nfbUpdateMinimalBar(UIView* card, TAVPlayer* player);

static UIView* nfbMinimalBar(UIView* card) {
    UIView* bar = objc_getAssociatedObject(card, kNFBMinimalBarKey);
    if (bar) {
        return bar;
    }
    bar = [[UIView alloc] init];
    // Born hidden and clear: a view created visible skips the fade on its very
    // first appearance, which is the one appearance that matters.
    bar.hidden = YES;
    bar.alpha = 0.0;

    UIView* track = [[UIView alloc] init];
    track.tag = kNFBMinimalTrackTag;
    track.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.28];
    track.layer.cornerRadius = kNFBMinimalTrackHeight / 2.0;
    [bar addSubview:track];

    UIView* fill = [[UIView alloc] init];
    fill.tag = kNFBMinimalFillTag;
    fill.backgroundColor = [UIColor whiteColor];
    fill.layer.cornerRadius = kNFBMinimalTrackHeight / 2.0;
    [track addSubview:fill];

    UILabel* clock = [[UILabel alloc] init];
    clock.tag = kNFBMinimalClockTag;
    clock.textColor = [UIColor colorWithRed:0.569 green:0.569 blue:0.569 alpha:1.0];
    clock.font = [UIFont systemFontOfSize:15];
    // The app draws its own times on an opaque strip; these sit on the video,
    // so they keep a shadow to stay readable on a bright frame.
    clock.layer.shadowColor = [UIColor blackColor].CGColor;
    clock.layer.shadowOpacity = 0.35;
    clock.layer.shadowRadius = 3.0;
    clock.layer.shadowOffset = CGSizeZero;
    [bar addSubview:clock];

    UIView* grip = [[UIView alloc] init];
    grip.tag = kNFBMinimalGripTag;
    grip.backgroundColor = [UIColor clearColor];
    UILongPressGestureRecognizer* scrub = [[UILongPressGestureRecognizer alloc]
        initWithTarget:card
                action:NSSelectorFromString(@"nfbHandleScrub:")];
    // Zero delay: the track answers the moment it is held, not half a second
    // later, and movement must not cancel what is meant to be a drag.
    scrub.minimumPressDuration = 0.0;
    scrub.allowableMovement = CGFLOAT_MAX;
    [grip addGestureRecognizer:scrub];
    [bar addSubview:grip];

    // The one thing on this bar that answers a touch. The container stays
    // interactive for it, and the card's own tap handler steps aside over its
    // frame, so a press here changes the sound and nothing else.
    UIButton* mute = [UIButton buttonWithType:UIButtonTypeSystem];
    mute.tag = kNFBMinimalMuteTag;
    mute.tintColor = [UIColor whiteColor];
    mute.layer.shadowColor = [UIColor blackColor].CGColor;
    mute.layer.shadowOpacity = 0.35;
    mute.layer.shadowRadius = 3.0;
    mute.layer.shadowOffset = CGSizeZero;
    __weak UIView* weakCard = card;
    [mute addAction:[UIAction actionWithHandler:^(UIAction* action) {
              UIView* strongCard = weakCard;
              if (!strongCard) {
                  return;
              }
              TAVPlayer* player = nfbCardPlayer(strongCard);
              BOOL muted = nfbCurrentMuted(strongCard, player);
              // The one place the sound is allowed to come on.
              gNFBSoundAllowed = muted;
              nfbApplyMuted(player, nfbImmersiveAudioManager(strongCard), !muted);
              nfbUpdateMinimalBar(strongCard, player);
            }]
        forControlEvents:UIControlEventTouchUpInside];
    [bar addSubview:mute];

    objc_setAssociatedObject(card, kNFBMinimalBarKey, bar,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return bar;
}

static void nfbStopMinimalTimer(UIView* card) {
    NSTimer* timer = objc_getAssociatedObject(card, kNFBMinimalTimerKey);
    [timer invalidate];
    objc_setAssociatedObject(card, kNFBMinimalTimerKey, nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// Laid out against the card, above the home indicator, and hidden as soon as
// the app's own bar comes back or the card leaves the screen.
static void nfbUpdateMinimalBar(UIView* card, TAVPlayer* player) {
    UIView* existing = objc_getAssociatedObject(card, kNFBMinimalBarKey);

    // Still crossing over from the timeline: stay down, and come back when the
    // crossing is done.
    NSTimeInterval shownAt =
        [objc_getAssociatedObject(card, kNFBCardShownAtKey) doubleValue];
    NSTimeInterval since = [NSDate timeIntervalSinceReferenceDate] - shownAt;
    if (shownAt > 0 && since < kNFBOpeningSettle) {
        existing.hidden = YES;
        __weak UIView* weakCard = card;
        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW,
                          (int64_t)((kNFBOpeningSettle - since) * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{
              UIView* strongCard = weakCard;
              if (strongCard) {
                  nfbUpdateMinimalBar(strongCard, nfbCardPlayer(strongCard));
              }
            });
        return;
    }

    BOOL wanted = card.window && player &&
                  [BHTSettings boolForKey:@"tap_to_pause"] &&
                  nfbImmersiveControlsView(card) == nil;
    if (!wanted) {
        if (existing && !existing.hidden) {
            [UIView animateWithDuration:kNFBMinimalFade * 0.6
                                  delay:0
                                options:UIViewAnimationOptionCurveEaseIn |
                                        UIViewAnimationOptionBeginFromCurrentState
                             animations:^{
                               existing.alpha = 0.0;
                             }
                             completion:^(BOOL finished) {
                               existing.hidden = YES;
                             }];
        }
        nfbStopMinimalTimer(card);
        return;
    }

    UIView* bar = nfbMinimalBar(card);
    if (bar.superview != card) {
        [card addSubview:bar];
    }
    [card bringSubviewToFront:bar];
    // Twitter's own bar is still fading out when this one arrives, so it fades
    // in rather than landing at full strength on top of it — from wherever its
    // opacity currently sits, which keeps a fast tap sequence smooth.
    if (bar.hidden) {
        bar.alpha = 0.0;
        bar.hidden = NO;
    }

    UILabel* clock = (UILabel*)[bar viewWithTag:kNFBMinimalClockTag];
    UIView* track = [bar viewWithTag:kNFBMinimalTrackTag];
    UIView* fill = [track viewWithTag:kNFBMinimalFillTag];
    UIButton* mute = (UIButton*)[bar viewWithTag:kNFBMinimalMuteTag];
    UIView* grip = [bar viewWithTag:kNFBMinimalGripTag];
    BOOL scrubbing =
        [objc_getAssociatedObject(card, kNFBScrubbingKey) boolValue];
    CGFloat trackHeight =
        scrubbing ? kNFBScrubTrackHeight : kNFBMinimalTrackHeight;

    TAVPlaybackState* state = player.playbackState;
    CGFloat elapsed = CMTIME_IS_NUMERIC(state.currentTime)
                          ? CMTimeGetSeconds(state.currentTime)
                          : 0.0;
    CGFloat total = CMTIME_IS_NUMERIC(state.duration)
                        ? CMTimeGetSeconds(state.duration)
                        : 0.0;
    CGFloat ratio = (total > 0 && isfinite(elapsed)) ? elapsed / total : 0.0;
    ratio = MAX(0.0, MIN(1.0, ratio));
    // While the reader drags, the position under the thumb is the truth; the
    // player is following it, not the other way round.
    if (scrubbing) {
        ratio = [objc_getAssociatedObject(card, kNFBScrubRatioKey) doubleValue];
        elapsed = ratio * total;
    }

    BOOL showsClock = [BHTSettings boolForKey:@"restore_video_timestamp"];
    clock.hidden = !showsClock;
    if (showsClock) {
        CMTime shown = scrubbing ? CMTimeMakeWithSeconds(elapsed, 600)
                                 : state.currentTime;
        clock.text = [NSString stringWithFormat:@"%@ / %@", nfbClockText(shown),
                                                nfbClockText(state.duration)];
        [clock sizeToFit];
    }

    CGFloat width = CGRectGetWidth(card.bounds);
    CGFloat floorY = CGRectGetHeight(card.bounds) - card.safeAreaInsets.bottom;
    CGFloat trackTop = floorY - kNFBMinimalTrackLift - trackHeight;
    CGFloat clockHeight = CGRectGetHeight(clock.bounds);
    CGFloat clockTop = floorY - kNFBMinimalClockLift - clockHeight / 2.0;
    // The grip reaches above the track, and a subview only takes touches inside
    // its parent — so the bar has to start where the grip starts, not where the
    // track does. Getting that wrong left half the band dead to the touch.
    CGFloat gripTop = trackTop + trackHeight / 2.0 - kNFBMinimalGripHeight / 2.0;
    CGFloat barTop = MIN(trackTop, gripTop);
    CGFloat barBottom = MAX(clockTop + clockHeight, trackTop + trackHeight);
    bar.frame = CGRectMake(0, barTop, width, barBottom - barTop);
    track.frame = CGRectMake(0, trackTop - barTop, width, trackHeight);
    track.layer.cornerRadius = trackHeight / 2.0;
    fill.frame = CGRectMake(0, 0, width * ratio, trackHeight);
    fill.layer.cornerRadius = trackHeight / 2.0;
    grip.frame = CGRectMake(0, gripTop - barTop, width, kNFBMinimalGripHeight);
    clock.frame = CGRectMake(kNFBMinimalTextInset, clockTop - barTop,
                             CGRectGetWidth(clock.bounds), clockHeight);

    BOOL muted = nfbCurrentMuted(card, player);
    UIImageSymbolConfiguration* symbol =
        [UIImageSymbolConfiguration configurationWithPointSize:15
                                                        weight:UIFontWeightMedium];
    [mute setImage:[UIImage systemImageNamed:muted ? @"speaker.slash.fill"
                                             : @"speaker.wave.2.fill"
                           withConfiguration:symbol]
          forState:UIControlStateNormal];
    mute.frame = CGRectMake(width - kNFBMinimalTextInset - kNFBMinimalMuteSize,
                            CGRectGetMidY(clock.frame) - kNFBMinimalMuteSize / 2.0,
                            kNFBMinimalMuteSize, kNFBMinimalMuteSize);

    if (bar.alpha < 1.0) {
        [UIView animateWithDuration:kNFBMinimalFade
                              delay:0
                            options:UIViewAnimationOptionCurveEaseOut |
                                    UIViewAnimationOptionBeginFromCurrentState
                         animations:^{
                           bar.alpha = 1.0;
                         }
                         completion:nil];
    }

    if (!objc_getAssociatedObject(card, kNFBMinimalTimerKey)) {
        __weak UIView* weakCard = card;
        NSTimer* timer = [NSTimer
            scheduledTimerWithTimeInterval:0.25
                                   repeats:YES
                                     block:^(NSTimer* scheduled) {
                                       UIView* strongCard = weakCard;
                                       if (!strongCard) {
                                           [scheduled invalidate];
                                           return;
                                       }
                                       nfbUpdateMinimalBar(strongCard,
                                                           nfbCardPlayer(strongCard));
                                     }];
        objc_setAssociatedObject(card, kNFBMinimalTimerKey, timer,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

// Dragging the track moves the video. The band above it takes the touch, the
// track thickens while it is held, and the player is sent to the position under
// the thumb — throttled, since a seek on every frame of the drag would stutter,
// with a last one on release so the final position is exact.
static void nfbHandleScrubGesture(UIView* card, UILongPressGestureRecognizer* press) {
    UIView* bar = objc_getAssociatedObject(card, kNFBMinimalBarKey);
    UIView* track = bar ? [bar viewWithTag:kNFBMinimalTrackTag] : nil;
    TAVPlayer* player = nfbCardPlayer(card);
    if (!track || !player) {
        return;
    }
    CGFloat width = CGRectGetWidth(track.bounds);
    CGFloat ratio =
        width > 0 ? [press locationInView:track].x / width : 0.0;
    ratio = MAX(0.0, MIN(1.0, ratio));
    CGFloat total = CMTIME_IS_NUMERIC(player.playbackState.duration)
                        ? CMTimeGetSeconds(player.playbackState.duration)
                        : 0.0;

    BOOL ending = (press.state == UIGestureRecognizerStateEnded ||
                   press.state == UIGestureRecognizerStateCancelled ||
                   press.state == UIGestureRecognizerStateFailed);
    if (!ending) {
        objc_setAssociatedObject(card, kNFBScrubbingKey, @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    objc_setAssociatedObject(card, kNFBScrubRatioKey, @(ratio),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (total > 0 && (ending || now - gNFBLastSeek > 0.06)) {
        gNFBLastSeek = now;
        [player seekToTime:CMTimeMakeWithSeconds(ratio * total, 600)];
    }

    if (ending) {
        objc_setAssociatedObject(card, kNFBScrubbingKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (press.state == UIGestureRecognizerStateBegan || ending) {
        [UIView animateWithDuration:0.15
                              delay:0
                            options:UIViewAnimationOptionCurveEaseOut |
                                    UIViewAnimationOptionBeginFromCurrentState
                         animations:^{
                           nfbUpdateMinimalBar(card, player);
                         }
                         completion:nil];
    } else {
        nfbUpdateMinimalBar(card, player);
    }
}

// MARK: - Folding the bar as early as it exists
//
// The app raises its whole overlay as a video opens and the fold takes it back
// down, so the gap between the two is what shows. Nothing here touches opacity
// or visibility: the card's own visibility is what the app reads to decide
// whether a video may autoplay, and dimming it stops playback outright. The
// gap is closed by acting sooner instead — the bar is watched on a short
// repeat and folded on the very tick it appears, while the video plays.

// One display frame on a 120 Hz screen, so the net behind the mount signal is
// never late by more than a frame; the count keeps the same 0.7 s of watch.
static const NSTimeInterval kNFBFoldTick = 0.008;
static const NSInteger kNFBFoldAttempts = 90;

// Folds when the bar and the playback state disagree. Returns NO while the
// answer is still to come — the video not yet playing, or the bar not yet
// mounted — which is the signal to look again.
static BOOL nfbFoldIfDue(UIView* card) {
    if (!card || !card.window || ![BHTSettings boolForKey:@"tap_to_pause"]) {
        return YES;
    }
    if ([NSDate timeIntervalSinceReferenceDate] - gNFBLastUserTap <
        kNFBUserTapGrace) {
        return YES;
    }
    TAVPlayer* player = nfbCardPlayer(card);
    if (!player) {
        return NO;
    }
    NSTimeInterval shownAt =
        [objc_getAssociatedObject(card, kNFBCardShownAtKey) doubleValue];
    BOOL opening = shownAt > 0 && [NSDate timeIntervalSinceReferenceDate] -
                                          shownAt < kNFBOpeningWindow;
    NSInteger status = player.playbackState.timeControlStatus;
    // 1 is waiting to play: transient everywhere else, but at the opening it is
    // the state the whole transition runs in.
    if (status == 1 && !opening) {
        return NO;
    }
    // 0 is paused. A real state once the video runs, but at the opening it is
    // the state the transition starts in, before the first frame plays. Acting
    // on it there reads "paused, so the bar must be up" and synthesises taps to
    // MOUNT Twitter's controls - the flash. A tap the reader actually made is
    // already excluded by the grace period above, so nothing is lost by sitting
    // this out until the player reports playing.
    if (status == 0 && opening) {
        return NO;
    }
    BOOL paused = (status == 0);
    if ((nfbImmersiveControlsView(card) != nil) == paused) {
        return NO;
    }
    Ivar recognizerIvar =
        class_getInstanceVariable(object_getClass(card), "singleTapRecognizer");
    id recognizer = recognizerIvar ? object_getIvar(card, recognizerIvar) : nil;
    if (!recognizer) {
        return YES;
    }

    NSTimeInterval lastFold =
        [objc_getAssociatedObject(card, kNFBLastFoldKey) doubleValue];
    NSTimeInterval nowStamp = [NSDate timeIntervalSinceReferenceDate];
    if (lastFold > 0 && nowStamp - lastFold < kNFBFoldCooldown) {
        return YES;
    }
    objc_setAssociatedObject(card, kNFBLastFoldKey, @(nowStamp),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    gNFBSyntheticToggle = YES;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    [card performSelector:@selector(handleSingleTap:) withObject:recognizer];
#pragma clang diagnostic pop
    gNFBSyntheticToggle = NO;
    return YES;
}

// The safety net behind the mount signal: a card whose bar never announces
// itself still gets folded, within a fraction of a second.
static void nfbFoldWhenReady(UIView* card, NSInteger attemptsLeft) {
    if (attemptsLeft <= 0 || nfbFoldIfDue(card)) {
        objc_setAssociatedObject(card, kNFBReconcilePendingKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    __weak UIView* weakCard = card;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                 (int64_t)(kNFBFoldTick * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                     UIView* strongCard = weakCard;
                     if (strongCard) {
                         nfbFoldWhenReady(strongCard, attemptsLeft - 1);
                     }
                   });
}

// One chain per card at a time, started wherever the card first shows a sign of
// life: entering the window, or its first playback state.
static void nfbStartFoldWatch(UIView* card) {
    if (!card || ![BHTSettings boolForKey:@"tap_to_pause"] ||
        [objc_getAssociatedObject(card, kNFBReconcilePendingKey) boolValue]) {
        return;
    }
    objc_setAssociatedObject(card, kNFBReconcilePendingKey, @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    nfbFoldWhenReady(card, kNFBFoldAttempts);
}

%hook _TtC14T1TwitterSwift17ImmersiveCardView

- (void)handleSingleTap:(UITapGestureRecognizer*)tap {
    UIView* card = (UIView*)self;
    // The sound button owns its own corner of the screen.
    UIView* ourBar = objc_getAssociatedObject(card, kNFBMinimalBarKey);
    CGPoint where = [tap locationInView:card];
    for (NSNumber* tag in @[ @(kNFBMinimalMuteTag), @(kNFBMinimalGripTag) ]) {
        UIView* part = [ourBar viewWithTag:tag.integerValue];
        if (part && !ourBar.hidden &&
            CGRectContainsPoint([part convertRect:part.bounds toView:card], where)) {
            return;
        }
    }
    if (!gNFBSyntheticToggle) {
        gNFBLastUserTap = [NSDate timeIntervalSinceReferenceDate];
        gNFBReaderAskedForChrome = YES;
    }
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
    nfbUpdateMinimalBar(card, player);
}

%new
- (void)nfbHandleScrub:(UILongPressGestureRecognizer*)press {
    nfbHandleScrubGesture((UIView*)self, press);
}

// A recycled card carries its glyph into the next video; playback there starts
// on its own, so the glyph comes down with the move.
- (void)didMoveToWindow {
    %orig;
    UIView* card = (UIView*)self;
    nfbShowPausedGlyph(card, NO);
    if (card.window) {
        if (!gNFBSoundAllowed && [BHTSettings boolForKey:@"tap_to_pause"] &&
            nfbOpensMuted()) {
            nfbApplyMuted(nfbCardPlayer(card), nfbImmersiveAudioManager(card), YES);
        }
        gNFBActiveCard = card;
        // A swipe to the next video never goes through the timeline tap, so the
        // request is cleared here too.
        gNFBReaderAskedForChrome = NO;
        nfbRefreshCleanPlayerFlag();
        objc_setAssociatedObject(
            card, kNFBCardShownAtKey,
            @([NSDate timeIntervalSinceReferenceDate]),
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        nfbStartFoldWatch(card);
    } else {
        if (gNFBActiveCard == card) {
            gNFBActiveCard = nil;
        }
        nfbStopMinimalTimer(card);
    }
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
        nfbUpdateMinimalBar(host, nfbImmersivePagePlayer(page));
    }
    gNFBActiveCard = host;
    nfbStartFoldWatch(host);
}

%end

// MARK: - The app's chrome stays down while a video opens
//
// Measured: none of these are unmounted between openings. The app leaves them
// in place and drives them with alpha, so a hook on didMoveToWindow fires once
// in the app's lifetime and never again on a recycled card. What repeats on
// every opening is the ramp back to alpha 1, and that is what is intercepted.
//
// Only for the length of the opening. Afterwards every one of them is left
// alone, so a tap that asks for the controls still gets them.

// author, handle and follow control
%hook _TtC14T1TwitterSwift25ImmersiveStatusPluginView
- (void)setAlpha:(CGFloat)alpha {
    BOOL blocked = alpha > 0 && nfbChromeIsUnasked();
    if (blocked) {
        %orig(0);
        return;
    }
    %orig;
}
%end

// reply, retweet, like, bookmark, share
%hook _TtC14T1TwitterSwift36ImmersiveEngagementActionsPluginView
- (void)setAlpha:(CGFloat)alpha {
    BOOL blocked = alpha > 0 && nfbChromeIsUnasked();
    if (blocked) {
        %orig(0);
        return;
    }
    %orig;
}
%end

// the row holding those actions
%hook _TtC14T1TwitterSwift25ImmersiveActionsStackView
- (void)setAlpha:(CGFloat)alpha {
    BOOL blocked = alpha > 0 && nfbChromeIsUnasked();
    if (blocked) {
        %orig(0);
        return;
    }
    %orig;
}
%end

// one action pill
%hook _TtC14T1TwitterSwift19ImmersiveActionView
- (void)setAlpha:(CGFloat)alpha {
    BOOL blocked = alpha > 0 && nfbChromeIsUnasked();
    if (blocked) {
        %orig(0);
        return;
    }
    %orig;
}
%end

// back button, top left
%hook _TtC14T1TwitterSwift29ImmersiveBackButtonPluginView
- (void)setAlpha:(CGFloat)alpha {
    BOOL blocked = alpha > 0 && nfbChromeIsUnasked();
    if (blocked) {
        %orig(0);
        return;
    }
    %orig;
}
%end

// overflow button, top right
%hook _TtC14T1TwitterSwift35ImmersiveTopRightActionsPluginsView
- (void)setAlpha:(CGFloat)alpha {
    BOOL blocked = alpha > 0 && nfbChromeIsUnasked();
    if (blocked) {
        %orig(0);
        return;
    }
    %orig;
}
%end

// the shade behind the top row
%hook _TtC14T1TwitterSwift30ImmersiveTopGradientPluginView
- (void)setAlpha:(CGFloat)alpha {
    BOOL blocked = alpha > 0 && nfbChromeIsUnasked();
    if (blocked) {
        %orig(0);
        return;
    }
    %orig;
}
%end

// the shade behind the bottom row
%hook _TtC14T1TwitterSwift33ImmersiveBottomGradientPluginView
- (void)setAlpha:(CGFloat)alpha {
    BOOL blocked = alpha > 0 && nfbChromeIsUnasked();
    if (blocked) {
        %orig(0);
        return;
    }
    %orig;
}
%end

// scrubber, timer and playback buttons
%hook _TtC14T1TwitterSwift17BottomBarControls
- (void)setAlpha:(CGFloat)alpha {
    BOOL blocked = alpha > 0 && nfbChromeIsUnasked();
    if (blocked) {
        %orig(0);
        return;
    }
    %orig;
}
%end
