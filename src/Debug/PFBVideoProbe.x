// Measurement only: journals how a full-screen video shrinks into the bottom player
// ([dock]) and how a video's sound is turned on or held ([sound]), with the state of
// the options involved. Nothing here changes what the app does.

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import "Common/PFBSettings.h"
#import "Debug/PFBDebugger.h"
#import "Support/T1Headers.h"

static NSString* pfbDockYes(BOOL value) {
    return value ? @"yes" : @"no";
}

static NSString* pfbDockOption(void) {
    return [PFBSettings boolForKey:@"disable_video_docking"] ? @"on" : @"off";
}

// Twitter reads its flags often; they are journaled only inside a closing decision.
static BOOL gPFBDockDeciding = NO;

// Getters read on every layout are journaled when their answer changes.
static void pfbDockLogChange(int* last, BOOL value, NSString* what) {
    if (*last == (int)value) {
        return;
    }
    *last = value;
    PFBDebugLog(@"[dock] %@: %@, option %@", what, pfbDockYes(value), pfbDockOption());
}

// Twitter's main window, not one of the tweak's overlays, decides what is in front.
static NSString* pfbSoundScreen(void) {
    for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }
        for (UIWindow* window in ((UIWindowScene*)scene).windows) {
            if (![NSStringFromClass([window class]) hasPrefix:@"T1Window"]) {
                continue;
            }
            UIViewController* top = window.rootViewController;
            while (top.presentedViewController) {
                top = top.presentedViewController;
            }
            return [NSStringFromClass([top class]) componentsSeparatedByString:@"."].lastObject ?: @"none";
        }
    }
    return @"none";
}

static NSString* pfbSoundContext(void) {
    NSString* category = [AVAudioSession sharedInstance].category ?: @"none";
    return [NSString stringWithFormat:@"on %@ · clean player %@ · opens %@ · session %@", pfbSoundScreen(),
                                      [PFBSettings boolForKey:@"tap_to_pause"] ? @"on" : @"off",
                                      [PFBSettings boolForKey:@"video_starts_muted"] ? @"muted" : @"with sound",
                                      [category stringByReplacingOccurrencesOfString:@"AVAudioSessionCategory"
                                                                          withString:@""]];
}

// Every video on the timeline hears the same switch; one line per change is enough.
static BOOL pfbSoundOncePerBurst(void) {
    static CFTimeInterval last = 0;
    CFTimeInterval now = CACurrentMediaTime();
    BOOL first = now - last > 0.5;
    last = now;
    return first;
}

// MARK: - Docking

%hook T1ImmersiveFullScreenViewController

- (void)dismissAnimationCompleteWithTransferPlayer:(BOOL)transfer {
    PFBDebugLog(@"[dock] full screen closed, player handed over: %@, option %@", pfbDockYes(transfer),
                pfbDockOption());
    %orig;
}

- (BOOL)_shouldAutoDockOnDismiss {
    gPFBDockDeciding = YES;
    BOOL result = %orig;
    gPFBDockDeciding = NO;
    PFBDebugLog(@"[dock] docks on closing: %@, option %@", pfbDockYes(result), pfbDockOption());
    return result;
}

- (BOOL)_canDockCurrentVideoToBottomSegment {
    BOOL result = %orig;
    PFBDebugLog(@"[dock] video can dock: %@", pfbDockYes(result));
    return result;
}

- (BOOL)isDropToDockEnabled {
    static int last = -1;
    BOOL result = %orig;
    pfbDockLogChange(&last, result, @"drop zone offered");
    return result;
}

- (void)_dockCurrentVideoToBottomSegmentAnimated:(BOOL)animated {
    PFBDebugLog(@"[dock] docking to the bottom player, animated: %@, option %@", pfbDockYes(animated),
                pfbDockOption());
    %orig;
}

- (void)_dockVideoToBottomSegmentAndDismiss {
    PFBDebugLog(@"[dock] docking asked by the drop zone or the dock button, option %@", pfbDockOption());
    %orig;
}

- (void)didDropOnDockZone {
    PFBDebugLog(@"[dock] video dropped on the dock zone, option %@", pfbDockOption());
    %orig;
}

- (void)immersiveViewControllerDockVideo:(id)controller {
    PFBDebugLog(@"[dock] player asked to dock, option %@", pfbDockOption());
    %orig;
}

%end

%hook T1ImmersiveVideoBottomSegment

- (void)dockWithStatus:(id)status
                  broadcast:(id)broadcast
                    account:(id)account
                     player:(id)player
      playerSessionProducer:(id)producer
                 viewSource:(long long)viewSource
                 mediaIndex:(long long)mediaIndex
                    isMuted:(BOOL)isMuted
        lingerScribeContext:(id)linger
                   animated:(BOOL)animated {
    PFBDebugLog(@"[dock] bottom player built: source %lld, broadcast %@, muted %@, option %@", viewSource,
                pfbDockYes(broadcast != nil), pfbDockYes(isMuted), pfbDockOption());
    %orig;
}

- (void)undock {
    PFBDebugLog(@"[dock] bottom player closed");
    %orig;
}

%end

%hook T1ExploreRelaunchFeatures

- (long long)immersiveAutoDockMinDurationSeconds {
    long long result = %orig;
    if (gPFBDockDeciding) {
        PFBDebugLog(@"[dock] shortest video that docks on closing: %lld s", result);
    }
    return result;
}

- (BOOL)isImmersiveDragToDockEnabled {
    static int last = -1;
    BOOL result = %orig;
    pfbDockLogChange(&last, result, @"drag to dock allowed by Twitter");
    return result;
}

- (BOOL)isImmersiveBroadcastAutoDockOnDismissEnabled {
    BOOL result = %orig;
    if (gPFBDockDeciding) {
        PFBDebugLog(@"[dock] live videos dock on closing: %@", pfbDockYes(result));
    }
    return result;
}

- (BOOL)isImmersiveAirplayAutoDockOnDismissEnabled {
    BOOL result = %orig;
    if (gPFBDockDeciding) {
        PFBDebugLog(@"[dock] AirPlay videos dock on closing: %@", pfbDockYes(result));
    }
    return result;
}

- (BOOL)isAutoUnmuteEnabled {
    static int last = -1;
    BOOL result = %orig;
    if (last != (int)result) {
        last = result;
        PFBDebugLog(@"[sound] a tap may unmute, says Twitter: %@ · %@", pfbDockYes(result), pfbSoundContext());
    }
    return result;
}

%end

%hook MTMediaTabFeatureAccess

- (BOOL)isImmersivePipDockOwnedControllerEnabled {
    static int last = -1;
    BOOL result = %orig;
    pfbDockLogChange(&last, result, @"bottom player owned by the media tab");
    return result;
}

%end

%hook T1VideoAVControlBar

- (BOOL)shouldShowDockButton {
    static int last = -1;
    BOOL result = %orig;
    pfbDockLogChange(&last, result, @"dock button shown");
    return result;
}

- (void)_tfn_dockButtonTapped {
    PFBDebugLog(@"[dock] dock button tapped, option %@", pfbDockOption());
    %orig;
}

- (void)_muteUnmuteButtonTapped {
    PFBDebugLog(@"[sound] player bar speaker tapped · %@", pfbSoundContext());
    %orig;
}

%end

%hook T1PushNotificationDerivedToast

- (void)_t1_dockImmersiveVideoIfNeeded {
    PFBDebugLog(@"[dock] notification banner asked to dock the video, option %@", pfbDockOption());
    %orig;
}

%end

%hook T1TabbedAppNavigation

- (void)dockViewController:(UIViewController*)controller
                  delegate:(id)delegate
                userAction:(long long)userAction
       animationTransition:(long long)transition {
    PFBDebugLog(@"[dock] floating player for %@, user action %lld, option %@",
                NSStringFromClass([controller class]), userAction, pfbDockOption());
    %orig;
}

%end

%hook T1LiveEventLegacyFloatingMiniPlayerController

- (void)dockViewController:(UIViewController*)controller
                  onWindow:(UIWindow*)window
                  delegate:(id)delegate
                userAction:(long long)userAction
       animationTransition:(long long)transition {
    PFBDebugLog(@"[dock] live event mini player for %@, user action %lld, option %@",
                NSStringFromClass([controller class]), userAction, pfbDockOption());
    %orig;
}

%end

%hook TAVPlayerView

- (void)pictureInPictureControllerWillStartPictureInPicture:(id)controller {
    PFBDebugLog(@"[dock] system picture in picture starting, option %@", pfbDockOption());
    %orig;
}

%end

// MARK: - Sound

%hook T1InlineVideoView

- (void)muteSelectorDidChangeWithNotification:(NSNotification*)notification {
    if (pfbSoundOncePerBurst()) {
        PFBDebugLog(@"[sound] timeline sound switch changed · %@", pfbSoundContext());
    }
    %orig;
}

%end

%hook T1InlineMediaView

- (void)_t1_updateAudioToggleIconForMuted:(BOOL)muted {
    static int last = -1;
    if (last != (int)muted) {
        last = muted;
        PFBDebugLog(@"[sound] timeline speaker icon shows %@ · %@", muted ? @"muted" : @"sound on", pfbSoundContext());
    }
    %orig;
}

%end

%hook T1ControlBarMuteButton

- (void)_t1_didTapMuteButton {
    PFBDebugLog(@"[sound] control bar speaker tapped · %@", pfbSoundContext());
    %orig;
}

%end

%hook _TtC14T1TwitterSwift10XVideoView

- (void)toggleMute {
    PFBDebugLog(@"[sound] video speaker toggled · %@", pfbSoundContext());
    %orig;
}

%end

%hook AVAudioSession

- (BOOL)setCategory:(AVAudioSessionCategory)category
                mode:(AVAudioSessionMode)mode
             options:(AVAudioSessionCategoryOptions)options
               error:(NSError**)error {
    NSString* before = self.category;
    BOOL result = %orig;
    if (![before isEqualToString:category]) {
        PFBDebugLog(@"[sound] audio session %@ -> %@, options %lu", before, category, (unsigned long)options);
    }
    return result;
}

- (BOOL)setCategory:(AVAudioSessionCategory)category
        withOptions:(AVAudioSessionCategoryOptions)options
              error:(NSError**)error {
    NSString* before = self.category;
    BOOL result = %orig;
    if (![before isEqualToString:category]) {
        PFBDebugLog(@"[sound] audio session %@ -> %@, options %lu", before, category, (unsigned long)options);
    }
    return result;
}

- (BOOL)setCategory:(AVAudioSessionCategory)category error:(NSError**)error {
    NSString* before = self.category;
    BOOL result = %orig;
    if (![before isEqualToString:category]) {
        PFBDebugLog(@"[sound] audio session %@ -> %@", before, category);
    }
    return result;
}

- (BOOL)setActive:(BOOL)active withOptions:(AVAudioSessionSetActiveOptions)options error:(NSError**)error {
    static int last = -1;
    BOOL result = %orig;
    if (!result || last != (int)active) {
        last = result ? active : last;
        PFBDebugLog(@"[sound] audio session %@%@", active ? @"activated" : @"released", result ? @"" : @" (refused)");
    }
    return result;
}

%end

// The player's own levers are watched from outside the clean player's guards, so a
// held unmute shows: these hooks are installed after every other one.
%group PFBSoundProbe

%hook TAVPlayer

- (void)setIsMuted:(BOOL)muted {
    BOOL before = self.isMuted;
    %orig;
    BOOL after = self.isMuted;
    if (!muted && after) {
        PFBDebugLog(@"[sound] unmute asked, player stays muted · %@", pfbSoundContext());
    } else if (before != after) {
        PFBDebugLog(@"[sound] player %@ · %@", after ? @"muted" : @"unmuted", pfbSoundContext());
    }
}

- (void)setVolume:(float)volume {
    float before = self.volume;
    %orig;
    float after = self.volume;
    if (volume > 0 && after <= 0) {
        PFBDebugLog(@"[sound] volume %.1f asked, stays at 0 · %@", volume, pfbSoundContext());
    } else if ((before > 0) != (after > 0)) {
        PFBDebugLog(@"[sound] volume %.1f -> %.1f · %@", before, after, pfbSoundContext());
    }
}

%end

%end

%ctor {
    %init;
    dispatch_async(dispatch_get_main_queue(), ^{
        %init(PFBSoundProbe);
    });
}
