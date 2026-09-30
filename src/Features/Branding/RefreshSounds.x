// Restores the classic pull-to-refresh sounds: the psst on release, detected through
// the scroll delegate, and the pop once the refresh that pull started completes. The
// files must be PCM, since AudioServicesCreateSystemSoundID has no AAC decoder.

#import "Support/HookHelpers.h"

// Pull distance, in points below the resting position, past which the gesture counts
// as a pull-to-refresh rather than an ordinary scroll. At rest the top of the feed
// can already sit slightly negative, and a real pull reaches far below -100.
static const CGFloat kPFBPullToRefreshThreshold = -100.0;

// Each sound is loaded once; a file that fails to load stays silent.
static void PFBPlayRefreshSound(NSString* file) {
    static NSMutableDictionary<NSString*, NSNumber*>* sounds;
    if (!sounds) {
        sounds = [NSMutableDictionary dictionary];
    }
    NSNumber* sound = sounds[file];
    if (!sound) {
        SystemSoundID created = 0;
        NSURL* url = [[PFBBundle sharedBundle] pathForFile:file];
        if (!url || AudioServicesCreateSystemSoundID((__bridge CFURLRef)url, &created) !=
                        kAudioServicesNoError) {
            created = 0;
        }
        sound = @(created);
        sounds[file] = sound;
    }
    if (sound.unsignedIntValue) {
        AudioServicesPlaySystemSound(sound.unsignedIntValue);
    }
}

%hook TFNItemsDataViewController

- (void)scrollViewDidEndDragging:(UIScrollView*)scrollView willDecelerate:(BOOL)decelerate {
    %orig;
    // contentOffset.y as the finger lifts: strongly negative means the list was
    // pulled below its top, which is the refresh intent.
    if (scrollView.contentOffset.y >= kPFBPullToRefreshThreshold) {
        return;
    }
    PFBCompatReach(PFBCompatPath_pull_sound);
    if (![PFBSettings boolForKey:@"restore_refresh_sounds"]) {
        PFBCOMPAT_OBSERVE(PFBCompat_restore_refresh_sounds, @"pull to refresh seen");
        return;
    }
    PFBPlayRefreshSound(@"psst2.caf");
    PFBCOMPAT_ACTION(PFBCompat_restore_refresh_sounds, @"sound played");
}

%end

// A pull commits a refresh by moving the control to status 1, and its return to 0
// means the new posts are in. The pop answers only the refreshes a pull started.
static char kPFBManualRefreshKey;

%hook TFNPullToRefreshControl
- (void)_setStatus:(unsigned long long)status fromScrolling:(BOOL)fromScrolling {
    id control = (id)self;
    SEL loadingSelector = @selector(loading);
    BOOL wasLoading = [control respondsToSelector:loadingSelector] &&
                      ((BOOL (*)(id, SEL))objc_msgSend)(control, loadingSelector);
    %orig;
    if (status == 1 && !wasLoading && fromScrolling) {
        objc_setAssociatedObject(control, &kPFBManualRefreshKey, @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    if (status != 0 || !wasLoading) {
        return;
    }
    BOOL manual = [objc_getAssociatedObject(control, &kPFBManualRefreshKey) boolValue];
    objc_setAssociatedObject(control, &kPFBManualRefreshKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!manual) {
        return;
    }
    PFBCompatReach(PFBCompatPath_refresh_end_sound);
    if (![PFBSettings boolForKey:@"restore_refresh_sounds"]) {
        PFBCOMPAT_OBSERVE(PFBCompat_restore_refresh_sounds, @"refresh end seen");
        return;
    }
    PFBPlayRefreshSound(@"pop.caf");
    PFBCOMPAT_ACTION(PFBCompat_restore_refresh_sounds, @"pop played");
}
%end

void PFBRefreshSoundsStart(void) {
    // AudioToolbox is not linked by the tweak: its symbols are loaded lazily before
    // any AudioServices call.
    dlopen("/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox", RTLD_LAZY);
}
