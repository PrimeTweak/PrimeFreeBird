// The clean video player: tap to play or pause, a minimal bar, no docking, no
// immersive scrolling, the restored timestamp, and the app's chrome held down
// while a video plays.

#import "Debug/PFBDebugger.h"
#import "Debug/PFBProbe.h"
#import "Support/HookHelpers.h"
#import "Support/TwitterChirpFont.h"
#import <stdatomic.h>

// MARK: - Immersive Player Timestamp

// The label's mode lives in progressLabelMode, a single byte started on the
// countdown, and a tap flips it. The byte is written directly, once per controls
// view: the tap handler is not exposed to the runtime on this build.

static const void* kPFBRestoredTimestampKey = &kPFBRestoredTimestampKey;

// The card on screen, so the bar can reach it the moment it mounts. Weak, so a
// card that goes away leaves nothing behind.
static __weak UIView* gPFBActiveCard = nil;
// When a card entered the window, read by the opening hold and the minimal bar.
static const void* kPFBCardShownAtKey = &kPFBCardShownAtKey;
// The app animates its overlay in over about six frames while the timeline is
// still leaving, and the chrome can only be raised once those views exist. The bar
// alone is kept clear for that span: the card's visibility gates autoplay.
static const NSTimeInterval kPFBBarRevealDelay = 0.3;
// When the last tap landed. The player reports its state asynchronously and for a
// moment still answers with the old one, so nothing else touches the bar for a
// beat after a tap has already placed it.
static NSTimeInterval gPFBLastUserTap = 0;
static const NSTimeInterval kPFBUserTapGrace = 0.6;

// Whether the chrome has been asked for on the video now showing. The app drives
// every piece with alpha and re-asserts 1 continuously, under every playback
// state, so only who asked tells a real request from the app's own ride up.
static BOOL gPFBWantPaused = NO;

// The chrome gate. Every chrome setAlpha: records the alpha the app wanted, then
// passes it through when open and pins 0 when closed. Opening replays the recorded
// alphas, so a pause shows chrome the app already raised.
static NSHashTable<UIView*>* gPFBGatedViews = nil;
static const void* kPFBWantedAlphaKey = &kPFBWantedAlphaKey;

// Synthetic taps left for the current pause. The app raises its chrome through
// its tap and through nothing else, so on a pause where the app's
// chrome is down a tap is sent - bounded, spaced, and never for a resume.
static NSInteger gPFBSyntheticBudget = 0;
static const NSInteger kPFBSyntheticPerPause = 3;

// Read once per video rather than on every setAlpha: the app re-asserts alpha
// hundreds of times while a video plays, and the setting cannot change while
// one is on screen - the settings page is not.
static BOOL gPFBCleanPlayerOn = NO;

static void pfbRefreshCleanPlayerFlag(void) {
    gPFBCleanPlayerOn = [PFBSettings boolForKey:@"tap_to_pause"];
}

static BOOL pfbChromeIsUnasked(void) {
    return gPFBCleanPlayerOn && !gPFBWantPaused;
}

static void pfbNoteChromeAlpha(UIView* view, CGFloat alpha) {
    if (!gPFBGatedViews) {
        gPFBGatedViews = [NSHashTable weakObjectsHashTable];
    }
    [gPFBGatedViews addObject:view];
    objc_setAssociatedObject(view, kPFBWantedAlphaKey, @(alpha),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// What the app wants shown, read from the alphas it asked for. The engagement
// row is the sentinel when it is on screen; failing that, any gated chrome.
static BOOL pfbAppChromeUp(UIView* card) {
    if (!card.window) {
        return NO;
    }
    Class sentinel =
        NSClassFromString(@"_TtC14T1TwitterSwift36ImmersiveEngagementActionsPluginView");
    BOOL sawSentinel = NO;
    BOOL anyUp = NO;
    for (UIView* view in gPFBGatedViews) {
        if (view.window != card.window) {
            continue;
        }
        CGFloat wanted = [objc_getAssociatedObject(view, kPFBWantedAlphaKey) doubleValue];
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
static void pfbReplayChromeAlphas(UIView* card) {
    for (UIView* view in [gPFBGatedViews allObjects]) {
        if (view.window != card.window) {
            continue;
        }
        NSNumber* wanted = objc_getAssociatedObject(view, kPFBWantedAlphaKey);
        if (wanted) {
            view.alpha = wanted.doubleValue;
        }
    }
}

// Playback held to the recorded intent on a short ladder after any tap: the app's
// own toggle lands a turn or more later. Each rung re-reads the state and acts
// only on a mismatch.
static void pfbShowPausedGlyph(UIView* card, BOOL paused);
static void pfbUpdateMinimalBar(UIView* card, TAVPlayer* player);
static TAVPlayer* pfbVisibleCardPlayer(UIView* card);
static void pfbEnforcePlayback(UIView* card) {
    __weak UIView* weakCard = card;
    NSArray<NSNumber*>* rungs = @[ @0.05, @0.15, @0.30, @0.60, @1.00 ];
    for (NSNumber* rung in rungs) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                     (int64_t)(rung.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
          UIView* strongCard = weakCard;
          TAVPlayer* player = strongCard ? pfbVisibleCardPlayer(strongCard) : nil;
          if (!player || !strongCard.window) {
              return;
          }
          BOOL paused = player.playbackState.timeControlStatus == 0;
          if (paused != gPFBWantPaused) {
              if (gPFBWantPaused) {
                  [player pause];
              } else {
                  [player playOrReplay];
              }
          }
          pfbShowPausedGlyph(strongCard, gPFBWantPaused);
          pfbUpdateMinimalBar(strongCard, player);
        });
    }
}

// Holds a view the app animates in with the presentation at alpha 0 until the
// card has been up for kPFBBarRevealDelay, then sets it to 1 unconditionally.
// Used on the controls bar only, never on the card: its visibility gates autoplay.
static void pfbHoldThroughOpening(UIView* view) {
    if (!view.window || ![PFBSettings boolForKey:@"tap_to_pause"]) {
        return;
    }
    UIView* card = gPFBActiveCard;
    NSTimeInterval shownAt =
        card ? [objc_getAssociatedObject(card, kPFBCardShownAtKey) doubleValue] : 0;
    NSTimeInterval since = [NSDate timeIntervalSinceReferenceDate] - shownAt;
    if (shownAt <= 0 || since >= kPFBBarRevealDelay) {
        return;
    }
    view.alpha = 0.0;
    __weak UIView* weakView = view;
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW,
                      (int64_t)((kPFBBarRevealDelay - since) * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
          UIView* strongView = weakView;
          if (strongView) {
              strongView.alpha = 1.0;
          }
        });
}

static BOOL pfbRaiseChromeIfDue(UIView* card);

// Probe: a one-byte ivar of a view, or -1 when it cannot be read.
static NSInteger pfbProbeByte(UIView* view, const char* name) {
    Ivar ivar = view ? class_getInstanceVariable(object_getClass(view), name) : NULL;
    ptrdiff_t offset = ivar ? ivar_getOffset(ivar) : 0;
    if (offset <= 0 || (size_t)offset >= class_getInstanceSize(object_getClass(view))) {
        return -1;
    }
    return *((uint8_t*)(__bridge void*)view + offset);
}

// Probe: progressLabelMode around the first write of the build, then whether Twitter writes
// it again on a bar already set; one line, at a rewrite or 30 s after the write.
static BOOL gPFBProbeTimestampDone;
static NSInteger gPFBProbeTimestampStart = -1;
static NSString* gPFBProbeTimestampWrite;
static NSUInteger gPFBProbeTimestampPasses;
static const void* kPFBProbeTimestampKey = &kPFBProbeTimestampKey;

static void pfbProbeTimestampVerdict(NSString* later) {
    gPFBProbeTimestampDone = YES;
    PFBProbeNote(@"SD-1 video time", @"SD-1 video time: %@; rewritten later: %@", gPFBProbeTimestampWrite ?: @"?", later);
}

// Called just before the write (before = YES) and just after it.
static void pfbProbeTimestampWrite(UIView* controls, BOOL before) {
    if (gPFBProbeTimestampDone || !PFBDebugIsRecording()) {
        return;
    }
    NSInteger mode = pfbProbeByte(controls, "progressLabelMode");
    if (before) {
        gPFBProbeTimestampStart = mode;
        return;
    }
    NSInteger applied = pfbProbeByte(controls, "hasAppliedDefaultProgressLabelMode");
    objc_setAssociatedObject(controls, kPFBProbeTimestampKey, @[ @(mode), @(applied), @(CACurrentMediaTime()) ],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (gPFBProbeTimestampWrite) {
        return;
    }
    if (!PFBProbeWants(@"SD-1 video time")) {
        gPFBProbeTimestampDone = YES;
        return;
    }
    gPFBProbeTimestampWrite = [NSString stringWithFormat:@"start %ld -> wrote %ld, default applied %ld at the write",
                                                         (long)gPFBProbeTimestampStart, (long)mode, (long)applied];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      if (!gPFBProbeTimestampDone && PFBProbeWants(@"SD-1 video time")) {
          pfbProbeTimestampVerdict([NSString stringWithFormat:@"no (%lu later passes over 30 s)",
                                                              (unsigned long)gPFBProbeTimestampPasses]);
      }
    });
}

// Probe: a later layout pass of a bar already set, compared with what was written there.
static void pfbProbeTimestampPass(UIView* controls) {
    if (gPFBProbeTimestampDone || !gPFBProbeTimestampWrite || !PFBDebugIsRecording()) {
        return;
    }
    NSArray<NSNumber*>* written = objc_getAssociatedObject(controls, kPFBProbeTimestampKey);
    if (written.count != 3) {
        return;
    }
    gPFBProbeTimestampPasses++;
    NSInteger mode = pfbProbeByte(controls, "progressLabelMode");
    if (mode != written[0].integerValue) {
        pfbProbeTimestampVerdict([NSString
            stringWithFormat:@"yes (wrote %ld, now %ld, default applied %ld -> %ld, %.0f ms after the write)",
                             (long)written[0].integerValue, (long)mode, (long)written[1].integerValue,
                             (long)pfbProbeByte(controls, "hasAppliedDefaultProgressLabelMode"),
                             (CACurrentMediaTime() - written[2].doubleValue) * 1000.0]);
    } else if (gPFBProbeTimestampPasses >= 3000) {
        pfbProbeTimestampVerdict(@"no (3000 later passes)");
    }
}

static void pfbRestoreTimestamp(UIView* controls) {
    pfbProbeTimestampPass(controls);
    BOOL enabled = [PFBSettings boolForKey:@"restore_video_timestamp"];
    if (controls && !enabled) {
        PFBCOMPAT_OBSERVE(PFBCompat_restore_video_timestamp, @"video controls found");
    }
    if (!controls || !enabled ||
        objc_getAssociatedObject(controls, kPFBRestoredTimestampKey)) {
        return;
    }
    Ivar modeIvar =
        class_getInstanceVariable(object_getClass(controls), "progressLabelMode");
    if (!modeIvar) {
        return;
    }
    objc_setAssociatedObject(controls, kPFBRestoredTimestampKey, @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    uint8_t* mode = (uint8_t*)(__bridge void*)controls + ivar_getOffset(modeIvar);
    pfbProbeTimestampWrite(controls, YES);
    *mode = *mode ? 0 : 1;
    pfbProbeTimestampWrite(controls, NO);
    PFBCOMPAT_ACTION(PFBCompat_restore_video_timestamp, @"timestamp restored");
    // The mode is read while the controls build their configuration, so the
    // change needs one more pass to reach the label.
    [controls setNeedsLayout];
}

%hook _TtC14T1TwitterSwift17VideoControlsView

- (void)layoutSubviews {
    %orig;
    pfbRestoreTimestamp((UIView*)self);
}

// The bar announcing its own arrival is the earliest the chrome can be raised:
// one turn of the run loop, before the frame that would show it.
- (void)didMoveToWindow {
    %orig;
    UIView* bar = (UIView*)self;
    if (!bar.window) {
        return;
    }
    // Mounting while a card is opening means this is the overlay riding in on
    // the presentation, not a bar that was asked for.
    pfbHoldThroughOpening(bar);
    dispatch_async(dispatch_get_main_queue(), ^{
      pfbRaiseChromeIfDue(gPFBActiveCard);
    });
}

%end

// MARK: - A tap opens a video, it does not wake the sound

// The timeline's video view carries isAutoUnmuteEnabled, whose job is to let a
// tap turn the sound on — the same tap that opens full screen. It is cleared on
// the view before its handler runs; every other route to the sound is untouched.

// The full-screen player's sound is off unless the video had it on in the timeline or
// the speaker on its bar turned it on. Timeline videos keep Twitter's speaker and the
// silent switch, so the guards hold only while the full-screen player is up.
static BOOL gPFBSoundAllowed = NO;
static BOOL gPFBFullScreenShown = NO;

// Probe: the tour's video sound passage reads the flag before its tap and puts it back after,
// so the person's next full-screen video opens as it would have (PFBCompatibilityTour.m).
BOOL pfbProbeSoundAllowed(void);
void pfbProbeRestoreSoundAllowed(BOOL allowed);

BOOL pfbProbeSoundAllowed(void) {
    return gPFBSoundAllowed;
}

void pfbProbeRestoreSoundAllowed(BOOL allowed) {
    gPFBSoundAllowed = allowed;
}

// Whether a video opens silent, as the reader chose.
static BOOL pfbOpensMuted(void) {
    return [PFBSettings boolForKey:@"video_starts_muted"];
}

// The state the flag takes when a video is opened from the timeline.
static BOOL pfbSoundAllowedAtOpen(void) {
    return !pfbOpensMuted();
}

// A request for sound is held while the full-screen player is up with the clean
// player on, opening muted, and no sound allowed from its bar yet.
static BOOL pfbHoldsSound(void) {
    return gPFBFullScreenShown && !gPFBSoundAllowed &&
           [PFBSettings boolForKey:@"tap_to_pause"] && pfbOpensMuted();
}

static void pfbClearAutoUnmute(UIView* view) {
    Ivar flagIvar =
        class_getInstanceVariable(object_getClass(view), "isAutoUnmuteEnabled");
    if (!flagIvar) {
        return;
    }
    uint8_t* flag = (uint8_t*)(__bridge void*)view + ivar_getOffset(flagIvar);
    if (*flag) {
        *flag = 0;
        PFBCOMPAT_ACTION(PFBCompat_no_auto_unmute, @"auto-unmute off");
    } else {
        PFBCOMPAT_OBSERVE(PFBCompat_no_auto_unmute, @"auto-unmute already off");
    }
}

// Whether a timeline video plays with its sound on, read from its own player.
static BOOL pfbInlineVideoHasSound(UIView* view) {
    Ivar viewIvar = class_getInstanceVariable(object_getClass(view), "playerViewIfLoaded");
    id playerView = viewIvar ? object_getIvar(view, viewIvar) : nil;
    Class playerViewClass = objc_getClass("TAVPlayerView");
    SEL getter = @selector(player);
    if (!playerViewClass || ![playerView isKindOfClass:playerViewClass] ||
        ![playerView respondsToSelector:getter] ||
        [playerView methodSignatureForSelector:getter].methodReturnType[0] != '@') {
        return NO;
    }
    id player = ((id (*)(id, SEL))objc_msgSend)(playerView, getter);
    Class playerClass = objc_getClass("TAVPlayer");
    if (!playerClass || ![player isKindOfClass:playerClass]) {
        return NO;
    }
    return !((TAVPlayer*)player).isMuted && ((TAVPlayer*)player).volume > 0;
}

// Probe: Twitter's auto-unmute flag at a timeline tap, then the full-screen player's sound
// 1.5 s later, once per pill state and clean player state.
static void pfbProbeAutoUnmute(UIView* inlineVideo) {
    if (!PFBDebugIsRecording()) {
        return;
    }
    BOOL opensMuted = pfbOpensMuted();
    BOOL clean = [PFBSettings boolForKey:@"tap_to_pause"];
    NSString* key = [NSString stringWithFormat:@"10a#F034 %@ %@", opensMuted ? @"muted" : @"sound on",
                                               clean ? @"clean on" : @"clean off"];
    if (!PFBProbeWants(key)) {
        return;
    }
    NSInteger flag = pfbProbeByte(inlineVideo, "isAutoUnmuteEnabled");
    NSString* flagText = flag < 0 ? @"unreadable" : flag ? @"was set, cleared" : @"already off";
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      if (!PFBProbeWants(key)) {
          return;
      }
      UIView* card = gPFBActiveCard;
      TAVPlayer* player = card.window ? pfbVisibleCardPlayer(card) : nil;
      NSString* sound = !player ? @"not found" : !player.isMuted && player.volume > 0 ? @"with sound" : @"muted";
      PFBProbeNote(key,
                   @"10a#F034 auto-unmute: video opened with the pill on %@, Clean video player %@, Twitter's "
                   @"auto-unmute flag %@ · full-screen player %@ (isMuted %@, volume %.2f)",
                   opensMuted ? @"Muted" : @"Sound on", clean ? @"on" : @"off", flagText, sound,
                   player ? (player.isMuted ? @"yes" : @"no") : @"-", player ? (double)player.volume : 0.0);
    });
}

%hook T1InlineVideoView

- (void)didMoveToWindow {
    %orig;
    pfbClearAutoUnmute((UIView*)self);
}

- (void)handleTapWithTapRecognizer:(UITapGestureRecognizer*)recognizer {
    pfbProbeAutoUnmute((UIView*)self);
    pfbClearAutoUnmute((UIView*)self);
    // A video opened from the timeline starts in the chosen state, whatever the last
    // one was left as, unless it was already playing with its sound on.
    BOOL soundOn = pfbInlineVideoHasSound((UIView*)self);
    gPFBSoundAllowed = pfbSoundAllowedAtOpen() || soundOn;
    PFBDebugLog(@"[player] opened from the timeline, sound %@; full screen allows sound: %@",
                soundOn ? @"on" : @"off", gPFBSoundAllowed ? @"yes" : @"no");
    gPFBWantPaused = NO;
    gPFBSyntheticBudget = 0;
    pfbRefreshCleanPlayerFlag();
    %orig;
}

%end

// Probe: the controller presented in Twitter's window that holds the full-screen player, or nil;
// the player is presented inside a navigation controller.
static UIViewController* pfbProbeFullScreenController(void) {
    for (UIViewController* shown = PFBProbeAppWindow().rootViewController; shown; shown = shown.presentedViewController) {
        NSArray<UIViewController*>* stack =
            [shown isKindOfClass:[UINavigationController class]] ? ((UINavigationController*)shown).viewControllers : @[ shown ];
        for (UIViewController* controller in stack) {
            if ([NSStringFromClass([controller class]) isEqualToString:@"T1ImmersiveFullScreenViewController"]) {
                return shown;
            }
        }
    }
    return nil;
}

// Probe: the moment the full-screen player begins to leave, for the notes below.
static void pfbProbeFullScreenLeaving(void) {
    if (PFBDebugIsRecording()) {
        PFBProbeMark(@"10a#F035 full screen leaving");
    }
}

// Probe: a sound request held while no full-screen player is presented, once per build;
// looked at most every 0.5 s, on the main thread.
static BOOL gPFBProbeHeldDone;
static CFTimeInterval gPFBProbeHeldLook;
static atomic_bool gPFBProbeHeldPending;
static void pfbProbeSoundHeld(NSString* door) {
    if (gPFBProbeHeldDone || !PFBDebugIsRecording()) {
        return;
    }
    if (!NSThread.isMainThread) {
        if (!atomic_exchange(&gPFBProbeHeldPending, true)) {
            dispatch_async(dispatch_get_main_queue(), ^{
              atomic_store(&gPFBProbeHeldPending, false);
              pfbProbeSoundHeld(door);
            });
        }
        return;
    }
    CFTimeInterval now = CACurrentMediaTime();
    if (now - gPFBProbeHeldLook < 0.5) {
        return;
    }
    gPFBProbeHeldLook = now;
    if (!PFBProbeWants(@"10a#F035 held")) {
        gPFBProbeHeldDone = YES;
        return;
    }
    if (pfbProbeFullScreenController()) {
        return;
    }
    CFTimeInterval leaving = PFBProbeMarkAge(@"10a#F035 full screen leaving");
    gPFBProbeHeldDone = YES;
    PFBProbeNote(@"10a#F035 held", @"10a#F035 sound request held with no full-screen player up (%@, %@)", door,
                 leaving >= 0 ? [NSString stringWithFormat:@"%.1f s after the full-screen player began to leave", leaving]
                              : @"no full-screen player left in this launch");
}

// Every door the full-screen player's sound comes through. The mute flag is one of
// two levers, the volume is the other, and playback covers a player born loud.
%hook TAVPlayer

// Every guard below is gated on the clean player. With it off, Twitter's own
// controls are on screen and its own sound button must work: holding the mute
// there would silence the video with nothing left to lift it.
- (void)setIsMuted:(BOOL)muted {
    if (!muted && pfbHoldsSound()) {
        PFBCompatReach(PFBCompatPath_starts_muted);
        pfbProbeSoundHeld(@"setIsMuted:");
        return;
    }
    %orig;
}

- (void)setVolume:(float)volume {
    if (volume > 0 && pfbHoldsSound()) {
        PFBCompatReach(PFBCompatPath_starts_muted);
        pfbProbeSoundHeld(@"setVolume:");
        %orig(0);
        return;
    }
    %orig;
}

- (void)play {
    if (pfbHoldsSound()) {
        PFBCompatReach(PFBCompatPath_starts_muted);
        self.isMuted = YES;
        self.volume = 0;
    }
    %orig;
}

- (void)playOrReplay {
    if (pfbHoldsSound()) {
        PFBCompatReach(PFBCompatPath_starts_muted);
        self.isMuted = YES;
        self.volume = 0;
    }
    %orig;
}

%end

// MARK: - Disable video docking

// Docking shrinks a full-screen video into the bottom player. The drop zone, the
// eligibility check and the full-screen controller's can-dock question lead there;
// refusing all three leaves swipe-to-dismiss and closing working normally.

// The full-screen controller also bounds the sound guards above: they hold from its
// first card until it starts to leave, and again when a swipe to close is cancelled.
%hook T1ImmersiveFullScreenViewController

- (void)viewDidAppear:(BOOL)animated {
    gPFBFullScreenShown = YES;
    %orig;
}

- (void)dismissAnimationCancelled {
    gPFBFullScreenShown = YES;
    %orig;
}

- (void)viewWillDisappear:(BOOL)animated {
    pfbProbeFullScreenLeaving();
    gPFBFullScreenShown = NO;
    %orig;
}

// Closing a full-screen video and a notification opened over it both ask this
// before docking; a refusal makes Twitter close the video instead.
- (BOOL)_canDockCurrentVideoToBottomSegment {
    if ([PFBSettings boolForKey:@"disable_video_docking"]) {
        PFBCOMPAT_ACTION(PFBCompat_disable_video_docking, @"docking refused");
        return NO;
    }
    PFBCOMPAT_OBSERVE(PFBCompat_disable_video_docking, @"docking question asked");
    return %orig;
}

%end

%hook _TtC14T1TwitterSwift24ImmersivePiPDropZoneView

- (void)didMoveToWindow {
    %orig;

    if (![PFBSettings boolForKey:@"disable_video_docking"]) {
        PFBCOMPAT_OBSERVE(PFBCompat_disable_video_docking, @"dock zone found");
        return;
    }
    UIView* zone = (UIView*)self;
    zone.hidden = YES;
    zone.alpha = 0.0;
    zone.userInteractionEnabled = NO;
    PFBCOMPAT_ACTION(PFBCompat_disable_video_docking, @"dock zone hidden");
    for (UIView* sub in zone.subviews) {
        sub.hidden = YES;
        sub.alpha = 0.0;
        sub.userInteractionEnabled = NO;
    }
}

%end

// MARK: - Disable Immersive Feed Scrolling

// The card pan drives vertical paging between videos; blocking it lets the
// swipe-down dismiss gesture take over. Twitter keeps it in a Swift lazy var,
// whose storage carries the $__lazy_storage_$_ prefix.
static BOOL isImmersiveCardPan(id viewController,
                               UIGestureRecognizer* gesture) {
    Class cls = [viewController class];
    Ivar panIvar = class_getInstanceVariable(cls, "panRecognizer")
                       ?: class_getInstanceVariable(cls, "$__lazy_storage_$_panRecognizer");
    return panIvar && object_getIvar(viewController, panIvar) == gesture;
}

%hook T1ImmersiveViewController

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer*)gesture {
    if ([PFBSettings boolForKey:@"disable_immersive_scroll"] &&
        isImmersiveCardPan(self, gesture)) {
        PFBCOMPAT_ACTION(PFBCompat_disable_immersive_scroll, @"swipe to next video blocked");
        return NO;
    }

    return %orig;
}

- (BOOL)isCurrentCardDockEligible {
    if ([PFBSettings boolForKey:@"disable_video_docking"]) {
        PFBCOMPAT_ACTION(PFBCompat_disable_video_docking, @"docking blocked");
        return NO;
    }
    PFBCOMPAT_OBSERVE(PFBCompat_disable_video_docking, @"dock check reached");
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
static const NSTimeInterval kPFBRaiseCooldown = 0.5;
static const void* kPFBLastRaiseKey = &kPFBLastRaiseKey;

static const void* kPFBPausedGlyphKey = &kPFBPausedGlyphKey;
static const void* kPFBReconcilePendingKey = &kPFBReconcilePendingKey;
static const void* kPFBMinimalBarKey = &kPFBMinimalBarKey;
static const void* kPFBMinimalTimerKey = &kPFBMinimalTimerKey;
// The app's overlay is gone about 150 ms into the opening, and this waits just
// past that: two sets of times on screen at once read as a glitch, while every
// extra millisecond is a hole with nothing shown.
static const NSTimeInterval kPFBOpeningSettle = 0.18;
static const NSInteger kPFBMinimalTrackTag = 90211;
static const NSInteger kPFBMinimalFillTag = 90212;
static const NSInteger kPFBMinimalClockTag = 90213;
static const NSInteger kPFBMinimalMuteTag = 90214;
static const NSInteger kPFBMinimalGripTag = 90215;
static const CGFloat kPFBMinimalMuteSize = 34.0;
// The track is three points tall — too thin to catch a thumb — so an invisible
// band of its own width carries the touch, and the track thickens under it.
static const CGFloat kPFBMinimalGripHeight = 26.0;
static const CGFloat kPFBScrubTrackHeight = 6.0;
static const void* kPFBScrubbingKey = &kPFBScrubbingKey;
static const void* kPFBScrubRatioKey = &kPFBScrubRatioKey;
static NSTimeInterval gPFBLastSeek = 0;
static const CGFloat kPFBPausedGlyphSize = 72.0;

// Marks a synthesized toggle: playback is left alone, only the bar moves.
static BOOL gPFBSyntheticToggle = NO;

// The player is not exposed by the page view: it is read from its ivar.
static TAVPlayer* pfbImmersivePagePlayer(UIView* pageView) {
    Ivar playerIvar = class_getInstanceVariable([pageView class], "player");
    return playerIvar ? object_getIvar(pageView, playerIvar) : nil;
}

// The page view of a card, and the player it holds — the timer has only the
// card to work from.
static TAVPlayer* pfbCardPlayer(UIView* card) {
    Class pageClass =
        NSClassFromString(@"_TtC14T1TwitterSwift22ImmersiveVideoPageView");
    if (!pageClass) {
        return nil;
    }
    __block UIView* pageView = nil;
    PFBEnumerateSubviewsRecursively(card, ^(UIView* view) {
        if (!pageView && [view isKindOfClass:pageClass]) {
            pageView = view;
        }
    });
    return pageView ? pfbImmersivePagePlayer(pageView) : nil;
}

// The video page on screen in a card. A Tweet with several media keeps the other
// pages mounted beside it, and a photo on screen leaves none.
static UIView* pfbVisibleVideoPage(UIView* card) {
    Class pageClass =
        NSClassFromString(@"_TtC14T1TwitterSwift22ImmersiveVideoPageView");
    if (!pageClass) {
        return nil;
    }
    __block UIView* pageView = nil;
    PFBEnumerateSubviewsRecursively(card, ^(UIView* view) {
        if (pageView || ![view isKindOfClass:pageClass]) {
            return;
        }
        CGRect frame = [view convertRect:view.bounds toView:card];
        if (CGRectContainsPoint(card.bounds, CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame)))) {
            pageView = view;
        }
    });
    return pageView;
}

static TAVPlayer* pfbVisibleCardPlayer(UIView* card) {
    UIView* pageView = pfbVisibleVideoPage(card);
    return pageView ? pfbImmersivePagePlayer(pageView) : nil;
}

// The audio session manager held by the host view above the card, or nil.
static id pfbImmersiveAudioManager(UIView* card) {
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
static uint8_t* pfbAudioMutedByte(id manager) {
    if (!manager) {
        return NULL;
    }
    Ivar mutedIvar = class_getInstanceVariable(object_getClass(manager), "isMuted");
    if (!mutedIvar) {
        return NULL;
    }
    return (uint8_t*)(__bridge void*)manager + ivar_getOffset(mutedIvar);
}

static void pfbApplyMuted(TAVPlayer* player, id manager, BOOL muted) {
    uint8_t* sessionMuted = pfbAudioMutedByte(manager);
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
static BOOL pfbCurrentMuted(UIView* card, TAVPlayer* player) {
    if (player) {
        return player.isMuted;
    }
    uint8_t* sessionMuted = pfbAudioMutedByte(pfbImmersiveAudioManager(card));
    return sessionMuted ? *sessionMuted != 0 : NO;
}

// The bar does not live inside the card, which only forwards its state, so the
// search starts from the window. Looking under the card alone finds nothing.
static UIView* pfbFirstDescendantOfClass(UIView* root, Class cls) {
    for (UIView* sub in root.subviews) {
        if ([sub isKindOfClass:cls]) {
            return sub;
        }
        UIView* found = pfbFirstDescendantOfClass(sub, cls);
        if (found) {
            return found;
        }
    }
    return nil;
}

// Present means visible, not merely mounted: the controls view stays mounted at
// alpha 1 under a BottomBarControls held at alpha 0. A view that cannot be seen
// is answered as absent.
static BOOL pfbViewCanBeSeen(UIView* view) {
    for (UIView* v = view; v; v = v.superview) {
        if (v.hidden || v.alpha <= 0.01) {
            return NO;
        }
    }
    return view.window != nil;
}

static UIView* pfbImmersiveControlsView(UIView* card) {
    Class controlsClass =
        NSClassFromString(@"_TtC14T1TwitterSwift17VideoControlsView");
    if (!controlsClass) {
        return nil;
    }
    UIView* root = card.window ?: card;
    // Depth-first, out at the first match.
    UIView* controls = pfbFirstDescendantOfClass(root, controlsClass);
    return pfbViewCanBeSeen(controls) ? controls : nil;
}

// Built once per card and kept as an associated object. Touches pass through
// it, so the card's own tap gesture stays the only thing handling them.
static UIView* pfbPausedGlyph(UIView* card) {
    UIView* glyph = objc_getAssociatedObject(card, kPFBPausedGlyphKey);
    if (glyph) {
        return glyph;
    }
    UIBlurEffect* blur =
        [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark];
    UIVisualEffectView* backdrop = [[UIVisualEffectView alloc] initWithEffect:blur];
    backdrop.userInteractionEnabled = NO;
    backdrop.frame = CGRectMake(0, 0, kPFBPausedGlyphSize, kPFBPausedGlyphSize);
    backdrop.layer.cornerRadius = kPFBPausedGlyphSize / 2.0;
    backdrop.clipsToBounds = YES;
    backdrop.autoresizingMask =
        UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin |
        UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    UIImageSymbolConfiguration* size =
        [UIImageSymbolConfiguration configurationWithPointSize:30
                                                        weight:UIImageSymbolWeightBold];
    UIImageView* icon = [[UIImageView alloc]
        initWithImage:PFBTwitterGlyphFor(@"immersive_play", [UIImage systemImageNamed:@"play.fill" withConfiguration:size])];
    icon.tintColor = [UIColor whiteColor];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [backdrop.contentView addSubview:icon];
    [NSLayoutConstraint activateConstraints:@[
        [icon.centerXAnchor constraintEqualToAnchor:backdrop.contentView.centerXAnchor
                                           constant:2.0],
        [icon.centerYAnchor constraintEqualToAnchor:backdrop.contentView.centerYAnchor]
    ]];
    objc_setAssociatedObject(card, kPFBPausedGlyphKey, backdrop,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return backdrop;
}

// Shown centered over the card while paused, taken down as soon as playback
// resumes or the card is remounted for another video.
static void pfbShowPausedGlyph(UIView* card, BOOL paused) {
    UIView* glyph = paused ? pfbPausedGlyph(card)
                           : objc_getAssociatedObject(card, kPFBPausedGlyphKey);
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
static const CGFloat kPFBMinimalTrackHeight = 3.0;
static const CGFloat kPFBMinimalTrackLift = 49.0;
static const CGFloat kPFBMinimalClockLift = 20.0;
static const CGFloat kPFBMinimalTextInset = 14.0;
static const CGFloat kPFBMinimalFade = 0.25;

static NSString* pfbClockText(CMTime time) {
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

// Track, fill, clock, scrub grip and sound button in one container, built once
// per card and kept as an associated object.

static UIView* pfbMinimalBar(UIView* card) {
    UIView* bar = objc_getAssociatedObject(card, kPFBMinimalBarKey);
    if (bar) {
        return bar;
    }
    bar = [[UIView alloc] init];
    // Born hidden and clear: a view created visible skips the fade on its very
    // first appearance, which is the one appearance that matters.
    bar.hidden = YES;
    bar.alpha = 0.0;

    UIView* track = [[UIView alloc] init];
    track.tag = kPFBMinimalTrackTag;
    track.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.28];
    track.layer.cornerRadius = kPFBMinimalTrackHeight / 2.0;
    [bar addSubview:track];

    UIView* fill = [[UIView alloc] init];
    fill.tag = kPFBMinimalFillTag;
    fill.backgroundColor = [UIColor whiteColor];
    fill.layer.cornerRadius = kPFBMinimalTrackHeight / 2.0;
    [track addSubview:fill];

    UILabel* clock = [[UILabel alloc] init];
    clock.tag = kPFBMinimalClockTag;
    clock.textColor = [UIColor colorWithRed:0.569 green:0.569 blue:0.569 alpha:1.0];
    clock.font = [TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:15];
    // The app draws its own times on an opaque strip; these sit on the video,
    // so they keep a shadow to stay readable on a bright frame.
    clock.layer.shadowColor = [UIColor blackColor].CGColor;
    clock.layer.shadowOpacity = 0.35;
    clock.layer.shadowRadius = 3.0;
    clock.layer.shadowOffset = CGSizeZero;
    [bar addSubview:clock];

    UIView* grip = [[UIView alloc] init];
    grip.tag = kPFBMinimalGripTag;
    grip.backgroundColor = [UIColor clearColor];
    UILongPressGestureRecognizer* scrub = [[UILongPressGestureRecognizer alloc]
        initWithTarget:card
                action:NSSelectorFromString(@"pfbHandleScrub:")];
    // Zero delay: the track answers the moment it is held, not half a second
    // later, and movement must not cancel what is meant to be a drag.
    scrub.minimumPressDuration = 0.0;
    scrub.allowableMovement = CGFLOAT_MAX;
    [grip addGestureRecognizer:scrub];
    [bar addSubview:grip];

    // The card's own tap handler steps aside over this button's frame, as over
    // the grip's, so a press here changes the sound and nothing else.
    UIButton* mute = [UIButton buttonWithType:UIButtonTypeSystem];
    mute.tag = kPFBMinimalMuteTag;
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
              TAVPlayer* player = pfbVisibleCardPlayer(strongCard);
              BOOL muted = pfbCurrentMuted(strongCard, player);
              // The one place the sound is allowed to come on.
              gPFBSoundAllowed = muted;
              pfbApplyMuted(player, pfbImmersiveAudioManager(strongCard), !muted);
              pfbUpdateMinimalBar(strongCard, player);
            }]
        forControlEvents:UIControlEventTouchUpInside];
    [bar addSubview:mute];

    objc_setAssociatedObject(card, kPFBMinimalBarKey, bar,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return bar;
}

static void pfbStopMinimalTimer(UIView* card) {
    NSTimer* timer = objc_getAssociatedObject(card, kPFBMinimalTimerKey);
    [timer invalidate];
    objc_setAssociatedObject(card, kPFBMinimalTimerKey, nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// Probe: the view a touch would reach at a point of the card, and what it carries.
static NSString* pfbProbeHitAt(UIView* card, CGPoint point) {
    UIView* hit = [card.window hitTest:[card convertPoint:point toView:nil] withEvent:nil];
    if (!hit) {
        return @"nothing";
    }
    NSUInteger above = 0;
    for (UIView* view = hit.superview; view && view != card; view = view.superview) {
        above += view.gestureRecognizers.count;
    }
    return [NSString stringWithFormat:@"%@ (in card %@, control %@, gestures %lu, %lu more above it up to the card)",
                                      PFBProbeClassName(hit), hit == card || [hit isDescendantOfView:card] ? @"yes" : @"no",
                                      [hit isKindOfClass:[UIControl class]] ? @"yes" : @"no",
                                      (unsigned long)hit.gestureRecognizers.count, (unsigned long)above];
}

// Probe: the band of the sound button below the bar and what lies under it, once per
// build, 0.6 s after the bar first shows.
static BOOL gPFBProbeBandDone;
static CFTimeInterval gPFBProbeBandSince;
static void pfbProbeMinimalBand(UIView* card, UIView* bar, UIView* mute) {
    if (gPFBProbeBandDone || !PFBDebugIsRecording()) {
        return;
    }
    CFTimeInterval now = CACurrentMediaTime();
    if (gPFBProbeBandSince <= 0) {
        gPFBProbeBandSince = now;
    }
    if (now - gPFBProbeBandSince < 0.6 || !card.window) {
        return;
    }
    gPFBProbeBandDone = YES;
    if (!PFBProbeWants(@"10a#F041 band")) {
        return;
    }
    CGRect muteInCard = [bar convertRect:mute.frame toView:card];
    CGFloat barBottom = CGRectGetMaxY(bar.frame);
    CGFloat muteBottom = CGRectGetMaxY(muteInCard);
    NSString* under = @"none, the sound button ends inside the bar";
    if (muteBottom > barBottom) {
        CGFloat y = (barBottom + muteBottom) / 2.0;
        under = [NSString stringWithFormat:@"at the middle %@ · at the sound button %@",
                                           pfbProbeHitAt(card, CGPointMake(CGRectGetWidth(card.bounds) / 2.0, y)),
                                           pfbProbeHitAt(card, CGPointMake(CGRectGetMidX(muteInCard), y))];
    }
    PFBProbeNote(@"10a#F041 band", @"10a#F041 minimal bar: bar %@, mute %@ in card, band %.1f pt; under the dead band: %@",
                 NSStringFromCGRect(bar.frame), NSStringFromCGRect(muteInCard), MAX(0.0, muteBottom - barBottom), under);
}

// Laid out against the card, above the home indicator, and hidden as soon as
// the app's own bar comes back or the card leaves the screen.
static void pfbUpdateMinimalBar(UIView* card, TAVPlayer* player) {
    UIView* existing = objc_getAssociatedObject(card, kPFBMinimalBarKey);

    // Still crossing over from the timeline: stay down, and come back when the
    // crossing is done.
    NSTimeInterval shownAt =
        [objc_getAssociatedObject(card, kPFBCardShownAtKey) doubleValue];
    NSTimeInterval since = [NSDate timeIntervalSinceReferenceDate] - shownAt;
    if (shownAt > 0 && since < kPFBOpeningSettle) {
        existing.hidden = YES;
        __weak UIView* weakCard = card;
        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW,
                          (int64_t)((kPFBOpeningSettle - since) * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{
              UIView* strongCard = weakCard;
              if (strongCard) {
                  pfbUpdateMinimalBar(strongCard, pfbVisibleCardPlayer(strongCard));
              }
            });
        return;
    }

    BOOL wanted = card.window && player && player == pfbVisibleCardPlayer(card) &&
                  [PFBSettings boolForKey:@"tap_to_pause"] &&
                  pfbImmersiveControlsView(card) == nil;
    if (!wanted) {
        if (existing && !existing.hidden) {
            [UIView animateWithDuration:kPFBMinimalFade * 0.6
                                  delay:0
                                options:UIViewAnimationOptionCurveEaseIn |
                                        UIViewAnimationOptionBeginFromCurrentState
                             animations:^{
                               existing.alpha = 0.0;
                             }
                             completion:^(BOOL finished) {
                               // A fade-in started meanwhile has set the alpha back.
                               if (existing.alpha == 0.0) {
                                   existing.hidden = YES;
                               }
                             }];
        }
        pfbStopMinimalTimer(card);
        return;
    }

    UIView* bar = pfbMinimalBar(card);
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

    UILabel* clock = (UILabel*)[bar viewWithTag:kPFBMinimalClockTag];
    UIView* track = [bar viewWithTag:kPFBMinimalTrackTag];
    UIView* fill = [track viewWithTag:kPFBMinimalFillTag];
    UIButton* mute = (UIButton*)[bar viewWithTag:kPFBMinimalMuteTag];
    UIView* grip = [bar viewWithTag:kPFBMinimalGripTag];
    BOOL scrubbing =
        [objc_getAssociatedObject(card, kPFBScrubbingKey) boolValue];
    CGFloat trackHeight =
        scrubbing ? kPFBScrubTrackHeight : kPFBMinimalTrackHeight;

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
        ratio = [objc_getAssociatedObject(card, kPFBScrubRatioKey) doubleValue];
        elapsed = ratio * total;
    }

    BOOL showsClock = [PFBSettings boolForKey:@"restore_video_timestamp"];
    clock.hidden = !showsClock;
    if (showsClock) {
        PFBCOMPAT_ACTION(PFBCompat_restore_video_timestamp, @"clock shown");
        CMTime shown = scrubbing ? CMTimeMakeWithSeconds(elapsed, 600)
                                 : state.currentTime;
        clock.text = [NSString stringWithFormat:@"%@ / %@", pfbClockText(shown),
                                                pfbClockText(state.duration)];
        [clock sizeToFit];
    }

    CGFloat width = CGRectGetWidth(card.bounds);
    CGFloat floorY = CGRectGetHeight(card.bounds) - card.safeAreaInsets.bottom;
    CGFloat trackTop = floorY - kPFBMinimalTrackLift - trackHeight;
    CGFloat clockHeight = CGRectGetHeight(clock.bounds);
    CGFloat clockTop = floorY - kPFBMinimalClockLift - clockHeight / 2.0;
    // The grip reaches above the track, and a subview only takes touches inside
    // its parent — so the bar has to start where the grip starts, not where the
    // track does.
    CGFloat gripTop = trackTop + trackHeight / 2.0 - kPFBMinimalGripHeight / 2.0;
    CGFloat barTop = MIN(trackTop, gripTop);
    CGFloat barBottom = MAX(clockTop + clockHeight, trackTop + trackHeight);
    bar.frame = CGRectMake(0, barTop, width, barBottom - barTop);
    track.frame = CGRectMake(0, trackTop - barTop, width, trackHeight);
    track.layer.cornerRadius = trackHeight / 2.0;
    fill.frame = CGRectMake(0, 0, width * ratio, trackHeight);
    fill.layer.cornerRadius = trackHeight / 2.0;
    grip.frame = CGRectMake(0, gripTop - barTop, width, kPFBMinimalGripHeight);
    clock.frame = CGRectMake(kPFBMinimalTextInset, clockTop - barTop,
                             CGRectGetWidth(clock.bounds), clockHeight);

    BOOL muted = pfbCurrentMuted(card, player);
    UIImageSymbolConfiguration* symbol =
        [UIImageSymbolConfiguration configurationWithPointSize:15
                                                        weight:UIImageSymbolWeightUnspecified];
    [mute setImage:PFBTwitterGlyphFor(muted ? @"sound_off" : @"sound",
                                      [UIImage systemImageNamed:muted ? @"speaker.slash.fill"
                                                                      : @"speaker.wave.2.fill"
                                                withConfiguration:symbol])
          forState:UIControlStateNormal];
    mute.frame = CGRectMake(width - kPFBMinimalTextInset - kPFBMinimalMuteSize,
                            CGRectGetMidY(clock.frame) - kPFBMinimalMuteSize / 2.0,
                            kPFBMinimalMuteSize, kPFBMinimalMuteSize);
    pfbProbeMinimalBand(card, bar, mute);

    if (bar.alpha < 1.0) {
        [UIView animateWithDuration:kPFBMinimalFade
                              delay:0
                            options:UIViewAnimationOptionCurveEaseOut |
                                    UIViewAnimationOptionBeginFromCurrentState
                         animations:^{
                           bar.alpha = 1.0;
                         }
                         completion:nil];
    }

    if (!objc_getAssociatedObject(card, kPFBMinimalTimerKey)) {
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
                                       pfbUpdateMinimalBar(strongCard,
                                                           pfbVisibleCardPlayer(strongCard));
                                     }];
        objc_setAssociatedObject(card, kPFBMinimalTimerKey, timer,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

// Dragging the track moves the video: the band above it takes the touch, the track
// thickens while held, and the player is sent to the position under the thumb,
// throttled, with a last seek on release so the final position is exact.
static void pfbHandleScrubGesture(UIView* card, UILongPressGestureRecognizer* press) {
    UIView* bar = objc_getAssociatedObject(card, kPFBMinimalBarKey);
    UIView* track = bar ? [bar viewWithTag:kPFBMinimalTrackTag] : nil;
    TAVPlayer* player = pfbVisibleCardPlayer(card);
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
        objc_setAssociatedObject(card, kPFBScrubbingKey, @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    objc_setAssociatedObject(card, kPFBScrubRatioKey, @(ratio),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (total > 0 && (ending || now - gPFBLastSeek > 0.06)) {
        gPFBLastSeek = now;
        [player seekToTime:CMTimeMakeWithSeconds(ratio * total, 600)];
    }

    if (ending) {
        objc_setAssociatedObject(card, kPFBScrubbingKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (press.state == UIGestureRecognizerStateBegan || ending) {
        [UIView animateWithDuration:0.15
                              delay:0
                            options:UIViewAnimationOptionCurveEaseOut |
                                    UIViewAnimationOptionBeginFromCurrentState
                         animations:^{
                           pfbUpdateMinimalBar(card, player);
                         }
                         completion:nil];
    } else {
        pfbUpdateMinimalBar(card, player);
    }
}

// MARK: - Raising the app's chrome on a pause

// On a pause the reader asked for, the app's chrome is raised by sending the card
// its own tap, checked when the bar mounts and on a short repeat behind that.

// Spacing and number of the checks behind the mount signal: about 3 s of watch.
static const NSTimeInterval kPFBRaiseTick = 0.05;
static const NSInteger kPFBRaiseAttempts = 60;

// Sends the card its own tap when the reader has paused and the app's chrome is
// down, past the grace after a real tap and within the budget and cooldown.
// Returns YES when there is nothing left to watch, NO to look again.
static BOOL pfbRaiseChromeIfDue(UIView* card) {
    if (!card || !card.window || ![PFBSettings boolForKey:@"tap_to_pause"]) {
        return YES;
    }
    if ([NSDate timeIntervalSinceReferenceDate] - gPFBLastUserTap < kPFBUserTapGrace) {
        return NO;
    }
    if (!gPFBWantPaused || pfbAppChromeUp(card)) {
        return NO;
    }
    if (gPFBSyntheticBudget <= 0) {
        return NO;
    }
    NSTimeInterval lastRaise = [objc_getAssociatedObject(card, kPFBLastRaiseKey) doubleValue];
    NSTimeInterval nowStamp = [NSDate timeIntervalSinceReferenceDate];
    if (lastRaise > 0 && nowStamp - lastRaise < kPFBRaiseCooldown) {
        return NO;
    }
    Ivar recognizerIvar = class_getInstanceVariable(object_getClass(card), "singleTapRecognizer");
    id recognizer = recognizerIvar ? object_getIvar(card, recognizerIvar) : nil;
    if (!recognizer) {
        return YES;
    }
    objc_setAssociatedObject(card, kPFBLastRaiseKey, @(nowStamp), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    gPFBSyntheticBudget--;
    PFBDebugLog(@"[loop] paused but the app's chrome is down - tapping (%ld left)",
                (long)gPFBSyntheticBudget);
    gPFBSyntheticToggle = YES;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    [card performSelector:@selector(handleSingleTap:) withObject:recognizer];
#pragma clang diagnostic pop
    gPFBSyntheticToggle = NO;
    pfbEnforcePlayback(card);
    return NO;
}

// The safety net behind the mount signal: a card whose bar never announces
// itself is still checked, until a check is final or the attempts run out.
static void pfbRaiseChromeWhenReady(UIView* card, NSInteger attemptsLeft) {
    if (attemptsLeft <= 0 || pfbRaiseChromeIfDue(card)) {
        objc_setAssociatedObject(card, kPFBReconcilePendingKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    __weak UIView* weakCard = card;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                 (int64_t)(kPFBRaiseTick * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                     UIView* strongCard = weakCard;
                     if (strongCard) {
                         pfbRaiseChromeWhenReady(strongCard, attemptsLeft - 1);
                     }
                   });
}

// One chain per card at a time, started wherever the card first shows a sign of
// life: entering the window, or its first playback state.
static void pfbStartRaiseWatch(UIView* card) {
    if (!card || ![PFBSettings boolForKey:@"tap_to_pause"] ||
        [objc_getAssociatedObject(card, kPFBReconcilePendingKey) boolValue]) {
        return;
    }
    objc_setAssociatedObject(card, kPFBReconcilePendingKey, @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    pfbRaiseChromeWhenReady(card, kPFBRaiseAttempts);
}

// Probe: the share of a view inside its window, 0 to 1.
static CGFloat pfbProbeOnScreen(UIView* view) {
    CGRect shown = [view convertRect:view.bounds toView:nil];
    CGRect visible = CGRectIntersection(shown, view.window.bounds);
    CGFloat area = CGRectGetWidth(shown) * CGRectGetHeight(shown);
    return area > 0 && !CGRectIsNull(visible) ? CGRectGetWidth(visible) * CGRectGetHeight(visible) / area : 0;
}

// Probe: a card mounting while another, paused card is still on screen, and a card
// mounting less than 1 s after the full-screen player began to leave; each once per build.
static BOOL gPFBProbeMountDone;
static void pfbProbeCardMount(UIView* card) {
    if (gPFBProbeMountDone || !PFBDebugIsRecording()) {
        return;
    }
    BOOL pauseOpen = PFBProbeWants(@"10a#F035 pause cleared");
    BOOL lateOpen = PFBProbeWants(@"10a#F035 late mount");
    gPFBProbeMountDone = !pauseOpen && !lateOpen;
    UIView* previous = gPFBActiveCard;
    if (pauseOpen && gPFBWantPaused && previous && previous != card && previous.window) {
        TAVPlayer* pausedPlayer = pfbVisibleCardPlayer(previous);
        NSString* paused = !pausedPlayer ? @"none" : pausedPlayer.playbackState.timeControlStatus == 0 ? @"paused" : @"playing";
        UIScrollView* list = nil;
        for (UIView* view = card.superview; view && !list; view = view.superview) {
            list = [view isKindOfClass:[UIScrollView class]] ? (UIScrollView*)view : nil;
        }
        NSString* motion = !list ? @"none" : list.isDragging ? @"dragging" : list.isDecelerating ? @"decelerating" : @"still";
        PFBProbeNote(@"10a#F035 pause cleared",
                     @"10a#F035 pause request cleared by another card mounting while the paused card is on screen "
                     @"(%.0f ms after the pause tap; paused card %.0f%% on screen, its player %@; new card %.0f%% on "
                     @"screen, list %@)",
                     ([NSDate timeIntervalSinceReferenceDate] - gPFBLastUserTap) * 1000.0, pfbProbeOnScreen(previous) * 100.0,
                     paused, pfbProbeOnScreen(card) * 100.0, motion);
    }
    CFTimeInterval leaving = PFBProbeMarkAge(@"10a#F035 full screen leaving");
    if (lateOpen && leaving >= 0 && leaving < 1.0) {
        UIViewController* player = pfbProbeFullScreenController();
        PFBProbeNote(@"10a#F035 late mount",
                     @"10a#F035 card mounted %.0f ms after the full-screen player began to leave: full-screen flag "
                     @"set back to YES (was %@, player %@)",
                     leaving * 1000.0, gPFBFullScreenShown ? @"YES" : @"NO",
                     !player ? @"gone" : player.isBeingDismissed ? @"being dismissed" : @"still presented");
    }
}

%hook _TtC14T1TwitterSwift17ImmersiveCardView

- (void)handleSingleTap:(UITapGestureRecognizer*)tap {
    UIView* card = (UIView*)self;
    // The sound button and the scrub grip handle their own touches.
    UIView* ourBar = objc_getAssociatedObject(card, kPFBMinimalBarKey);
    CGPoint where = [tap locationInView:card];
    for (NSNumber* tag in @[ @(kPFBMinimalMuteTag), @(kPFBMinimalGripTag) ]) {
        UIView* part = [ourBar viewWithTag:tag.integerValue];
        if (part && !ourBar.hidden &&
            CGRectContainsPoint([part convertRect:part.bounds toView:card], where)) {
            return;
        }
    }
    // A synthetic tap is the loop asking the app to raise its chrome: it goes
    // straight through. Playback is held afterwards by the caller.
    if (gPFBSyntheticToggle || ![PFBSettings boolForKey:@"tap_to_pause"]) {
        if (!gPFBSyntheticToggle) {
            PFBCOMPAT_OBSERVE(PFBCompat_tap_to_pause, @"tap on a video");
        }
        %orig;
        return;
    }
    TAVPlayer* player = pfbVisibleCardPlayer(card);
    if (!player) {
        %orig;
        return;
    }
    PFBCOMPAT_ACTION(PFBCompat_tap_to_pause, @"tap to pause");
    // A real tap sets the intent from the state it found. The gate follows at
    // once: open, it replays the alphas the app asked for; closed, everything goes
    // dark now.
    gPFBLastUserTap = [NSDate timeIntervalSinceReferenceDate];
    BOOL wasPlaying = player.playbackState.timeControlStatus != 0;
    gPFBWantPaused = wasPlaying;
    gPFBSyntheticBudget = gPFBWantPaused ? kPFBSyntheticPerPause : 0;
    BOOL appChromeUp = pfbAppChromeUp(card);
    PFBDebugLog(@"[tap] reader %@ | app chrome %@", gPFBWantPaused ? @"pauses" : @"resumes",
                appChromeUp ? @"up" : @"down");
    if (gPFBWantPaused) {
        pfbReplayChromeAlphas(card);
    } else {
        // The gate's own 0 goes through the recording setter, so the app's last request is put back: its intent is left as it is.
        for (UIView* view in [gPFBGatedViews allObjects]) {
            if (view.window == card.window) {
                NSNumber* wanted = objc_getAssociatedObject(view, kPFBWantedAlphaKey);
                view.alpha = 0.0;
                objc_setAssociatedObject(view, kPFBWantedAlphaKey, wanted, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }
    }
    // The app's tap is forwarded only when its chrome intent must flip: down
    // on a pause. On a resume the gate has already hidden the chrome and the
    // app's intent is left as it is - its next raise comes for free.
    if (gPFBWantPaused && !appChromeUp) {
        objc_setAssociatedObject(card, kPFBLastRaiseKey, @(gPFBLastUserTap),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        gPFBSyntheticBudget--;
        %orig;
    }
    if ([self respondsToSelector:@selector(setPausedByUser:)]) {
        [(_TtC14T1TwitterSwift17ImmersiveCardView*)self setPausedByUser:gPFBWantPaused];
    }
    if (wasPlaying) {
        [player pause];
    } else {
        [player playOrReplay];
    }
    pfbShowPausedGlyph(card, gPFBWantPaused);
    pfbEnforcePlayback(card);
    pfbStartRaiseWatch(card);
}
%new
- (void)pfbHandleScrub:(UILongPressGestureRecognizer*)press {
    pfbHandleScrubGesture((UIView*)self, press);
}

// A recycled card carries its glyph into the next video; playback there starts
// on its own, so the glyph comes down with the move.
- (void)didMoveToWindow {
    %orig;
    UIView* card = (UIView*)self;
    pfbShowPausedGlyph(card, NO);
    if (card.window) {
        pfbProbeCardMount(card);
        gPFBFullScreenShown = YES;
        if ([PFBSettings boolForKey:@"tap_to_pause"]) {
            PFBCOMPAT_ACTION(PFBCompat_tap_to_pause, @"clean player on a video");
        } else {
            PFBCOMPAT_OBSERVE(PFBCompat_tap_to_pause, @"full-screen card shown");
        }
        if (pfbHoldsSound()) {
            pfbApplyMuted(pfbCardPlayer(card), pfbImmersiveAudioManager(card), YES);
        }
        gPFBActiveCard = card;
        // A swipe to the next video never goes through the timeline tap, so the
        // request is cleared here too.
        gPFBWantPaused = NO;
        gPFBSyntheticBudget = 0;
        pfbRefreshCleanPlayerFlag();
        objc_setAssociatedObject(
            card, kPFBCardShownAtKey,
            @([NSDate timeIntervalSinceReferenceDate]),
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        pfbStartRaiseWatch(card);
    } else {
        if (gPFBActiveCard == card) {
            gPFBActiveCard = nil;
        }
        pfbStopMinimalTimer(card);
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
        pfbUpdateMinimalBar(host, pfbImmersivePagePlayer(page));
    } else if (gPFBActiveCard.window) {
        // A page outside any card leaves the card on screen as the active one.
        return;
    }
    gPFBActiveCard = host;
    pfbStartRaiseWatch(host);
}

%end

// MARK: - The app's chrome stays down while a video plays

// None of these are unmounted between openings: the app drives them with alpha,
// so the ramp back to alpha 1 is intercepted while the clean player is on and the
// reader has not paused.

// Records the alpha the app asked for on a chrome view. YES when the view must stay
// at 0 instead: a visible alpha while the chrome has not been asked for.
static BOOL pfbChromeAlphaBlocked(UIView* view, CGFloat alpha) {
    pfbNoteChromeAlpha(view, alpha);
    return alpha > 0 && pfbChromeIsUnasked();
}

// author, handle and follow control
%hook _TtC14T1TwitterSwift25ImmersiveStatusPluginView
- (void)setAlpha:(CGFloat)alpha {
    if (pfbChromeAlphaBlocked((UIView*)self, alpha)) {
        %orig(0);
        return;
    }
    %orig;
}
%end

// reply, retweet, like, bookmark, share
%hook _TtC14T1TwitterSwift36ImmersiveEngagementActionsPluginView
- (void)setAlpha:(CGFloat)alpha {
    if (pfbChromeAlphaBlocked((UIView*)self, alpha)) {
        %orig(0);
        return;
    }
    %orig;
}
%end

// the row holding those actions
%hook _TtC14T1TwitterSwift25ImmersiveActionsStackView
- (void)setAlpha:(CGFloat)alpha {
    if (pfbChromeAlphaBlocked((UIView*)self, alpha)) {
        %orig(0);
        return;
    }
    %orig;
}
%end

// one action pill
%hook _TtC14T1TwitterSwift19ImmersiveActionView
- (void)setAlpha:(CGFloat)alpha {
    if (pfbChromeAlphaBlocked((UIView*)self, alpha)) {
        %orig(0);
        return;
    }
    %orig;
}
%end

// back button, top left
%hook _TtC14T1TwitterSwift29ImmersiveBackButtonPluginView
- (void)setAlpha:(CGFloat)alpha {
    if (pfbChromeAlphaBlocked((UIView*)self, alpha)) {
        %orig(0);
        return;
    }
    %orig;
}
%end

// overflow button, top right
%hook _TtC14T1TwitterSwift35ImmersiveTopRightActionsPluginsView
- (void)setAlpha:(CGFloat)alpha {
    if (pfbChromeAlphaBlocked((UIView*)self, alpha)) {
        %orig(0);
        return;
    }
    %orig;
}
%end

// the shade behind the top row
%hook _TtC14T1TwitterSwift30ImmersiveTopGradientPluginView
- (void)setAlpha:(CGFloat)alpha {
    if (pfbChromeAlphaBlocked((UIView*)self, alpha)) {
        %orig(0);
        return;
    }
    %orig;
}
%end

// the shade behind the bottom row
%hook _TtC14T1TwitterSwift33ImmersiveBottomGradientPluginView
- (void)setAlpha:(CGFloat)alpha {
    if (pfbChromeAlphaBlocked((UIView*)self, alpha)) {
        %orig(0);
        return;
    }
    %orig;
}
%end

// progress line, time labels, play button, attribution and bottom controls
%hook _TtC14T1TwitterSwift32ImmersiveVideoTimelinePluginView
- (void)setAlpha:(CGFloat)alpha {
    if (pfbChromeAlphaBlocked((UIView*)self, alpha)) {
        %orig(0);
        return;
    }
    %orig;
}
%end

%hook _TtC14T1TwitterSwift37ImmersiveScrubProgressLabelPluginView
- (void)setAlpha:(CGFloat)alpha {
    if (pfbChromeAlphaBlocked((UIView*)self, alpha)) {
        %orig(0);
        return;
    }
    %orig;
}
%end

%hook _TtC14T1TwitterSwift34ImmersivePlayPauseButtonPluginView
- (void)setAlpha:(CGFloat)alpha {
    if (pfbChromeAlphaBlocked((UIView*)self, alpha)) {
        %orig(0);
        return;
    }
    %orig;
}
%end

%hook _TtC14T1TwitterSwift30ImmersiveAttributionPluginView
- (void)setAlpha:(CGFloat)alpha {
    if (pfbChromeAlphaBlocked((UIView*)self, alpha)) {
        %orig(0);
        return;
    }
    %orig;
}
%end

%hook _TtC14T1TwitterSwift17BottomBarControls
- (void)setAlpha:(CGFloat)alpha {
    if (pfbChromeAlphaBlocked((UIView*)self, alpha)) {
        %orig(0);
        return;
    }
    %orig;
}
%end
