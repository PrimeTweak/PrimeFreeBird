// Restores the classic pull-to-refresh sound: the pull is detected through the
// scroll delegate and the sound played on release. The file must be PCM, since
// AudioServicesCreateSystemSoundID has no AAC decoder.

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
    // AudioToolbox is not linked by the tweak: its symbols are loaded lazily before
    // any AudioServices call.
    dlopen("/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox", RTLD_LAZY);
    %init;
}
