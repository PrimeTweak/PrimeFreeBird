//
//  ImmersivePlayer.x
//  PrimeFreeBird
//

#import "HookHelpers.h"
#import "Debug/NFBDebugger.h"

// MARK: - Immersive Player Timestamp

// The label's mode lives in progressLabelMode, a single byte started on the
// countdown, and a tap flips it. The byte is written directly, once per controls
// view: the tap handler is not exposed to the runtime on this build.

static const void* kNFBRestoredTimestampKey = &kNFBRestoredTimestampKey;

// The card on screen, so the bar can reach it the moment it mounts. Weak, so a
// card that goes away leaves nothing behind. The fold is defined with the tap
// section further down and announced here.
static __weak UIView* gNFBActiveCard = nil;
// When a card entered the window. The bar and the fold both read it, and the
// bar's hook sits at the top of this file, so it is declared here.
static const void* kNFBCardShownAtKey = &kNFBCardShownAtKey;
// The app animates its overlay in over about six frames while the timeline is
// still leaving, and the fold can only answer once those views exist. The bar
// alone is kept clear for that span: the card's visibility gates autoplay.
static const NSTimeInterval kNFBBarRevealDelay = 0.3;
// When the last tap landed. The player reports its state asynchronously and for a
// moment still answers with the old one, so nothing else touches the bar for a
// beat after a tap has already placed it.
static NSTimeInterval gNFBLastUserTap = 0;
static const NSTimeInterval kNFBUserTapGrace = 0.6;

// A view the app animates in with the presentation is held clear for that
// animation, then given back unconditionally. Only the overlay plugins, never the
// card or anything carrying the video: the card's visibility gates autoplay.
static UIView* nfbImmersiveControlsView(UIView* card);

// Whether the chrome has been asked for on the video now showing. The app drives
// every piece with alpha and re-asserts 1 continuously, under every playback
// state, so only who asked tells a real request from the app's own ride up.
static BOOL gNFBWantPaused = NO;

// The chrome gate. Every chrome setAlpha: records the alpha the app wanted, then
// passes it through when open and pins 0 when closed. Opening replays the recorded
// alphas, so a pause shows chrome the app already raised.
static NSHashTable<UIView*>* gNFBGatedViews = nil;
static const void* kNFBWantedAlphaKey = &kNFBWantedAlphaKey;

// Synthetic taps left for the current pause. The app raises its chrome through
// its tap and through nothing else, so on a pause where the app's
// chrome is down a tap is sent - bounded, spaced, and never for a resume.
static NSInteger gNFBSyntheticBudget = 0;
static const NSInteger kNFBSyntheticPerPause = 3;

// Read once per video rather than on every setAlpha: the app re-asserts alpha
// hundreds of times while a video plays, and the setting cannot change while
// one is on screen - the settings page is not.
static BOOL gNFBCleanPlayerOn = NO;

static void nfbRefreshCleanPlayerFlag(void) {
    gNFBCleanPlayerOn = [BHTSettings boolForKey:@"tap_to_pause"];
}

static BOOL nfbChromeIsUnasked(void) {
    return gNFBCleanPlayerOn && !gNFBWantPaused;
}

static void nfbNoteChromeAlpha(UIView* view, CGFloat alpha) {
    if (!gNFBGatedViews) {
        gNFBGatedViews = [NSHashTable weakObjectsHashTable];
    }
    [gNFBGatedViews addObject:view];
    objc_setAssociatedObject(view, kNFBWantedAlphaKey, @(alpha),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// What the app wants shown, read from the alphas it asked for. The engagement
// row is the sentinel when it is on screen; failing that, any gated chrome.
static BOOL nfbAppChromeUp(UIView* card) {
    if (!card.window) {
        return NO;
    }
    Class sentinel =
        NSClassFromString(@"_TtC14T1TwitterSwift36ImmersiveEngagementActionsPluginView");
    BOOL sawSentinel = NO;
    BOOL anyUp = NO;
    for (UIView* view in gNFBGatedViews) {
        if (view.window != card.window) {
            continue;
        }
        CGFloat wanted = [objc_getAssociatedObject(view, kNFBWantedAlphaKey) doubleValue];
        if (sentinel && [view isKindOfClass:sentinel]) {
            sawSentinel = YES;
            if (wanted > 0.5) {
                return YES;
            }
        } else if (wanted > 0.5) {
            anyUp = YES;
        }
    }
    return sawSentinel ? NO : anyUp;
}

// Opening the gate: every gated view gets the alpha the app last asked for,
// through its own setter, which now lets it through.
static void nfbReplayChromeAlphas(UIView* card) {
    for (UIView* view in [gNFBGatedViews allObjects]) {
        if (view.window != card.window) {
            continue;
        }
        NSNumber* wanted = objc_getAssociatedObject(view, kNFBWantedAlphaKey);
        if (wanted) {
            view.alpha = wanted.doubleValue;
        }
    }
}

// Playback held to the recorded intent on a short ladder after any tap: the app's
// own toggle lands a turn or more later. Each rung re-reads the state and acts
// only on a mismatch.
static void nfbShowPausedGlyph(UIView* card, BOOL paused);
static void nfbUpdateMinimalBar(UIView* card, TAVPlayer* player);
static TAVPlayer* nfbCardPlayer(UIView* card);
static void nfbEnforcePlayback(UIView* card) {
    __weak UIView* weakCard = card;
    NSArray<NSNumber*>* rungs = @[ @0.05, @0.15, @0.30, @0.60, @1.00 ];
    for (NSNumber* rung in rungs) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                     (int64_t)(rung.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
          UIView* strongCard = weakCard;
          TAVPlayer* player = strongCard ? nfbCardPlayer(strongCard) : nil;
          if (!player || !strongCard.window) {
              return;
          }
          BOOL paused = player.playbackState.timeControlStatus == 0;
          if (paused != gNFBWantPaused) {
              NFBDebugLog(@"[tap] +%.2fs playback is %@, intent is %@ - held", rung.doubleValue,
                          paused ? @"paused" : @"playing", gNFBWantPaused ? @"paused" : @"playing");
              if (gNFBWantPaused) {
                  [player pause];
              } else {
                  [player playOrReplay];
              }
          }
          nfbShowPausedGlyph(strongCard, gNFBWantPaused);
          nfbUpdateMinimalBar(strongCard, player);
        });
    }
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
    // the presentation, not a bar that was asked for.
    nfbHoldThroughOpening(bar);
    dispatch_async(dispatch_get_main_queue(), ^{
      nfbFoldIfDue(gNFBActiveCard);
    });
}

%end

// MARK: - Disable video docking

// Docking shrinks a full-screen video into a floating mini player. Two paths reach
// it, the drop-zone view and the controllers' eligibility check; closing both
// leaves swipe-to-dismiss working normally.

// MARK: - A tap opens a video, it does not wake the sound

// The timeline's video view carries isAutoUnmuteEnabled, whose job is to let a
// tap turn the sound on — the same tap that opens full screen. It is cleared on
// the view before its handler runs; every other route to the sound is untouched.

// One rule and no timing: the sound is off unless the speaker button on this bar
// turned it on. The app wakes it on opening, on leaving and mid-playback by
// different routes, so any window-based rule leaves a hole.
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
    gNFBWantPaused = NO;
    gNFBSyntheticBudget = 0;
    nfbRefreshCleanPlayerFlag();
    %orig;
}

%end

// Every door the sound comes through. The mute flag is one of two levers: the
// player also carries a volume, and the handover back to the timeline raises that
// one. Playback covers a player born loud.
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

// A tap toggles playback and the bar follows the state: paused shows the full
// controls, playing keeps the progress line. The bar's presence is its state, and
// the native tap handler runs whenever the two disagree.

// The synthetic tap goes through Twitter's handler, which moves the bar and the
// playback state, so the reconciler would measure a state its own tap changed.
// One tap per card per cooldown breaks that loop.
static const NSTimeInterval kNFBFoldCooldown = 0.5;
static const void* kNFBLastFoldKey = &kNFBLastFoldKey;

static const void* kNFBPausedGlyphKey = &kNFBPausedGlyphKey;
static const void* kNFBReconcilePendingKey = &kNFBReconcilePendingKey;
static const void* kNFBMinimalBarKey = &kNFBMinimalBarKey;
static const void* kNFBMinimalTimerKey = &kNFBMinimalTimerKey;
// The app's overlay is gone about 150 ms into the opening, and this waits just
// past that: two sets of times on screen at once read as a glitch, while every
// extra millisecond is a hole with nothing shown.
static const NSTimeInterval kNFBOpeningSettle = 0.18;
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

// Twitter's tap handler turns the sound on as well as moving the controls, so the
// handler runs and the audio state is restored around it: the session manager's
// isMuted byte, which every card reads, and the player itself.

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

// The bar does not live inside the card, which only forwards its state, so the
// search starts from the window. Looking under the card alone finds nothing.
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

// Present means visible, not merely mounted: 12.21 keeps the controls view
// mounted at alpha 1 under a BottomBarControls held at alpha 0. A view that
// cannot be seen is answered as absent.
static BOOL nfbViewCanBeSeen(UIView* view) {
    for (UIView* v = view; v; v = v.superview) {
        if (v.hidden || v.alpha <= 0.01) {
            return NO;
        }
    }
    return view.window != nil;
}

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
    UIView* controls = nfbFirstDescendantOfClass(root, controlsClass);
    return nfbViewCanBeSeen(controls) ? controls : nil;
}
// Built once per card and kept as an associated object. Touches pass through
// it, so the card's own tap gesture stays the only thing handling them.

// One census of the card's chrome, taken twice after it opens and once on every
// pause. Each mounted plugin is named with its alpha, so the hide list below can
// be extended from what is actually on screen.
static void nfbCensusWalk(UIView* view, NSInteger depth, NSMutableArray* lines) {
    NSString* name = NSStringFromClass([view class]);
    if (depth > 0 && lines.count < 40 &&
        ([name containsString:@"Plugin"] || [name containsString:@"Controls"] ||
         [name containsString:@"Timeline"] || [name containsString:@"Scrub"] ||
         [name containsString:@"PlayPause"] || [name containsString:@"BottomBar"])) {
        NSString* shortName = [name componentsSeparatedByString:@"Swift"].lastObject;
        shortName = [shortName stringByTrimmingCharactersInSet:
                                   [NSCharacterSet decimalDigitCharacterSet]];
        [lines addObject:[NSString stringWithFormat:@"%@ a=%.2f%@ %.0fx%.0f", shortName,
                                                    view.alpha, view.hidden ? @" HIDDEN" : @"",
                                                    view.bounds.size.width,
                                                    view.bounds.size.height]];
    }
    if (depth < 14) {
        for (UIView* sub in view.subviews) {
            nfbCensusWalk(sub, depth + 1, lines);
        }
    }
}

static void nfbChromeCensus(UIView* card, NSString* moment) {
    if (!card.window) {
        return;
    }
    NSMutableArray* lines = [NSMutableArray array];
    nfbCensusWalk(card.window, 0, lines);
    NFBDebugLog(@"[chrome:%@] %@", moment,
                lines.count ? [lines componentsJoinedByString:@" | "] : @"(nothing matched)");
    Class controlsClass = NSClassFromString(@"_TtC14T1TwitterSwift17VideoControlsView");
    UIView* mounted = controlsClass
                          ? nfbFirstDescendantOfClass(card.window ?: card, controlsClass)
                          : nil;
    TAVPlayer* censusPlayer = nfbCardPlayer(card);
    NFBDebugLog(@"[chrome:%@] VideoControlsView mounted=%@ visible=%@ | playback=%ld", moment,
                mounted ? @"yes" : @"no", nfbImmersiveControlsView(card) ? @"yes" : @"no",
                censusPlayer ? (long)censusPlayer.playbackState.timeControlStatus : -1L);
}

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

// Twitter mounts and unmounts its whole bottom bar as one piece, so nothing is
// left over the video. A track, its fill and the times are drawn here while the
// app's bar is away, polled on a timer so the fill advances at a steady rate.

// Taken off the app's own bar: the line sits 49 pt above the safe area, 3 pt tall
// edge to edge, with the times 20 pt above it at 15 pt regular. The same geometry
// means the line does not move when Twitter's bar takes over.
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
    // While a drag is in progress the position under the thumb is the truth; the
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

// Dragging the track moves the video: the band above it takes the touch, the track
// thickens while held, and the player is sent to the position under the thumb,
// throttled, with a last seek on release so the final position is exact.
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

// The gap between the app raising its overlay and the fold taking it down is what
// shows. Nothing here touches opacity or visibility, since the card's visibility
// gates autoplay; the bar is watched on a short repeat and folded as it appears.

// One display frame on a 120 Hz screen, so the net behind the mount signal is
// never late by more than a frame; the count keeps the same 0.7 s of watch.
static const NSTimeInterval kNFBFoldTick = 0.05;
static const NSInteger kNFBFoldAttempts = 60;

// Folds when the bar and the playback state disagree, and returns NO while the
// answer is still to come, which is the signal to look again. A tap is sent only
// to raise the app's chrome for a pause; a resume is handled by the gate.
static BOOL nfbFoldIfDue(UIView* card) {
    if (!card || !card.window || ![BHTSettings boolForKey:@"tap_to_pause"]) {
        return YES;
    }
    if ([NSDate timeIntervalSinceReferenceDate] - gNFBLastUserTap < kNFBUserTapGrace) {
        return NO;
    }
    if (!gNFBWantPaused || nfbAppChromeUp(card)) {
        return NO;
    }
    if (gNFBSyntheticBudget <= 0) {
        return NO;
    }
    NSTimeInterval lastFold = [objc_getAssociatedObject(card, kNFBLastFoldKey) doubleValue];
    NSTimeInterval nowStamp = [NSDate timeIntervalSinceReferenceDate];
    if (lastFold > 0 && nowStamp - lastFold < kNFBFoldCooldown) {
        return NO;
    }
    Ivar recognizerIvar = class_getInstanceVariable(object_getClass(card), "singleTapRecognizer");
    id recognizer = recognizerIvar ? object_getIvar(card, recognizerIvar) : nil;
    if (!recognizer) {
        return YES;
    }
    objc_setAssociatedObject(card, kNFBLastFoldKey, @(nowStamp), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    gNFBSyntheticBudget--;
    NFBDebugLog(@"[loop] paused but the app's chrome is down - tapping (%ld left)",
                (long)gNFBSyntheticBudget);
    gNFBSyntheticToggle = YES;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    [card performSelector:@selector(handleSingleTap:) withObject:recognizer];
#pragma clang diagnostic pop
    gNFBSyntheticToggle = NO;
    nfbEnforcePlayback(card);
    return NO;
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
    {
        __weak UIView* tappedCard = (UIView*)self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ nfbChromeCensus(tappedCard, @"tap"); });
    }
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
    // A synthetic tap is the loop asking the app to raise its chrome: it goes
    // straight through. Playback is held afterwards by the caller.
    if (gNFBSyntheticToggle || ![BHTSettings boolForKey:@"tap_to_pause"]) {
        %orig;
        return;
    }
    __block UIView* pageView = nil;
    EnumerateSubviewsRecursively(card, ^(UIView* view) {
        if (!pageView && [view isKindOfClass:%c(_TtC14T1TwitterSwift22ImmersiveVideoPageView)]) {
            pageView = view;
        }
    });
    TAVPlayer* player = pageView ? nfbImmersivePagePlayer(pageView) : nil;
    if (!player) {
        %orig;
        return;
    }
    // A real tap sets the intent from the state it found. The gate follows at
    // once: open, it replays the alphas the app asked for; closed, everything goes
    // dark now.
    gNFBLastUserTap = [NSDate timeIntervalSinceReferenceDate];
    BOOL wasPlaying = player.playbackState.timeControlStatus != 0;
    gNFBWantPaused = wasPlaying;
    gNFBSyntheticBudget = gNFBWantPaused ? kNFBSyntheticPerPause : 0;
    BOOL appChromeUp = nfbAppChromeUp(card);
    NFBDebugLog(@"[tap] reader %@ | app chrome %@", gNFBWantPaused ? @"pauses" : @"resumes",
                appChromeUp ? @"up" : @"down");
    if (gNFBWantPaused) {
        nfbReplayChromeAlphas(card);
    } else {
        for (UIView* view in [gNFBGatedViews allObjects]) {
            if (view.window == card.window) {
                view.alpha = 0.0;
            }
        }
    }
    // The app's tap is forwarded only when its chrome intent must flip: down
    // on a pause. On a resume the gate has already hidden the chrome and the
    // app's intent is left as it is - its next raise comes for free.
    if (gNFBWantPaused && !appChromeUp) {
        objc_setAssociatedObject(card, kNFBLastFoldKey, @(gNFBLastUserTap),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        gNFBSyntheticBudget--;
        %orig;
    }
    [(_TtC14T1TwitterSwift17ImmersiveCardView*)self setPausedByUser:gNFBWantPaused];
    if (wasPlaying) {
        [player pause];
    } else {
        [player playOrReplay];
    }
    nfbShowPausedGlyph(card, gNFBWantPaused);
    nfbEnforcePlayback(card);
    nfbStartFoldWatch(card);
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
        gNFBWantPaused = NO;
        gNFBSyntheticBudget = 0;
        nfbRefreshCleanPlayerFlag();
        objc_setAssociatedObject(
            card, kNFBCardShownAtKey,
            @([NSDate timeIntervalSinceReferenceDate]),
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        nfbStartFoldWatch(card);
        __weak UIView* censusCard = card;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ nfbChromeCensus(censusCard, @"1s"); });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ nfbChromeCensus(censusCard, @"3s"); });
    } else {
        if (gNFBActiveCard == card) {
            gNFBActiveCard = nil;
        }
        nfbStopMinimalTimer(card);
    }
}

%end

// Playback-state changes fire at autoplay, at every swipe to a new video and at
// the end of one, so the bar is re-matched here, off the tap path. Without the
// card's own recognizer nothing is sent.
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

// None of these are unmounted between openings: the app leaves them in place and
// drives them with alpha, so the ramp back to alpha 1 is what is intercepted, and
// only for the length of the opening.

// author, handle and follow control
%hook _TtC14T1TwitterSwift25ImmersiveStatusPluginView
- (void)setAlpha:(CGFloat)alpha {
    nfbNoteChromeAlpha((UIView*)self, alpha);
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
    nfbNoteChromeAlpha((UIView*)self, alpha);
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
    nfbNoteChromeAlpha((UIView*)self, alpha);
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
    nfbNoteChromeAlpha((UIView*)self, alpha);
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
    nfbNoteChromeAlpha((UIView*)self, alpha);
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
    nfbNoteChromeAlpha((UIView*)self, alpha);
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
    nfbNoteChromeAlpha((UIView*)self, alpha);
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
    nfbNoteChromeAlpha((UIView*)self, alpha);
    BOOL blocked = alpha > 0 && nfbChromeIsUnasked();
    if (blocked) {
        %orig(0);
        return;
    }
    %orig;
}
%end

// scrubber, timer and playback buttons

// The native timeline, its scrub label strip and the attribution line stay at
// alpha 1 with the chrome folded, so the app's own bar shows through under the
// minimal one. Same rule as every plugin above.
%hook _TtC14T1TwitterSwift32ImmersiveVideoTimelinePluginView
- (void)setAlpha:(CGFloat)alpha {
    nfbNoteChromeAlpha((UIView*)self, alpha);
    BOOL blocked = alpha > 0 && nfbChromeIsUnasked();
    if (blocked) {
        %orig(0);
        return;
    }
    %orig;
}
%end

%hook _TtC14T1TwitterSwift37ImmersiveScrubProgressLabelPluginView
- (void)setAlpha:(CGFloat)alpha {
    nfbNoteChromeAlpha((UIView*)self, alpha);
    BOOL blocked = alpha > 0 && nfbChromeIsUnasked();
    if (blocked) {
        %orig(0);
        return;
    }
    %orig;
}
%end

%hook _TtC14T1TwitterSwift34ImmersivePlayPauseButtonPluginView
- (void)setAlpha:(CGFloat)alpha {
    nfbNoteChromeAlpha((UIView*)self, alpha);
    BOOL blocked = alpha > 0 && nfbChromeIsUnasked();
    if (blocked) {
        %orig(0);
        return;
    }
    %orig;
}
%end

%hook _TtC14T1TwitterSwift30ImmersiveAttributionPluginView
- (void)setAlpha:(CGFloat)alpha {
    nfbNoteChromeAlpha((UIView*)self, alpha);
    BOOL blocked = alpha > 0 && nfbChromeIsUnasked();
    if (blocked) {
        %orig(0);
        return;
    }
    %orig;
}
%end

%hook _TtC14T1TwitterSwift17BottomBarControls
- (void)setAlpha:(CGFloat)alpha {
    nfbNoteChromeAlpha((UIView*)self, alpha);
    BOOL blocked = alpha > 0 && nfbChromeIsUnasked();
    if (blocked) {
        %orig(0);
        return;
    }
    %orig;
}
%end
