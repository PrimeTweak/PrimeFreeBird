//
//  RefreshSounds.x
//  PrimeFreeBird
//
//  Restores the classic pull-to-refresh sound.
//
//  The feed's pull-to-refresh moved to SwiftUI: the old control hook is gone from
//  the binary, neither the request setter nor the central sound player sits on the
//  gesture path, and the native sound files were removed from the app.
//
//  The gesture is still a scroll, so the pull is detected through the ObjC scroll
//  delegate on TFNItemsDataViewController and the sound played on release past a
//  threshold. The file must be PCM: AudioServicesCreateSystemSoundID has no AAC
//  decoder, and an .aac created without error stays silent.

#import "HookHelpers.h"

// Pull distance, in points below the resting position, past which the gesture counts
// as a pull-to-refresh rather than an ordinary scroll. At rest the top of the feed
// can already sit slightly negative, and a real pull reaches far below -100.
static const CGFloat kNFBPullToRefreshThreshold = -100.0;

static void NFBPlayRefreshSound(void) {
    static SystemSoundID sound = 0;
    static BOOL triedToLoad = NO;

    if (!triedToLoad) {
        triedToLoad = YES;
        NSURL* url = [[BHTBundle sharedBundle] pathForFile:@"psst2.caf"];
        if (url) {
            if (AudioServicesCreateSystemSoundID((__bridge CFURLRef)url, &sound) !=
                kAudioServicesNoError) {
                sound = 0;
            }
        }
    }
    if (sound) {
        AudioServicesPlaySystemSound(sound);
    }
}

%hook TFNItemsDataViewController

- (void)scrollViewDidEndDragging:(UIScrollView*)scrollView willDecelerate:(BOOL)decelerate {
    %orig;

    if (![BHTSettings boolForKey:@"restore_refresh_sounds"]) {
        return;
    }

    // contentOffset.y as the finger lifts: strongly negative means the list was
    // pulled below its top, which is the refresh intent.
    if (scrollView.contentOffset.y < kNFBPullToRefreshThreshold) {
        NFBPlayRefreshSound();
    }
}

%end

%ctor {
    // AudioToolbox n'est pas lie au tweak : on lie ses symboles paresseusement
    // avant tout appel a AudioServices.
    dlopen("/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox", RTLD_LAZY);
    %init;
}
