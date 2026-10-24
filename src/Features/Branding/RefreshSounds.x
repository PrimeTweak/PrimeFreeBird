// Classic pull-to-refresh sounds: a psst on release, a pop when that refresh ends.

#import "Support/HookHelpers.h"

// Each sound is loaded once; a file that fails to load stays silent. Files must be
// PCM: AudioServicesCreateSystemSoundID has no AAC decoder. Returns whether it played.
static BOOL PFBPlayRefreshSound(NSString* file) {
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
    if (!sound.unsignedIntValue) {
        return NO;
    }
    AudioServicesPlaySystemSound(sound.unsignedIntValue);
    return YES;
}

// A pull commits a refresh by moving the control to status 1, before the finger lifts,
// and its return to 0 means the new posts are in. The psst waits for the lift; the pop
// answers only the refreshes a pull started.
static char kPFBManualRefreshKey;
static char kPFBPsstPendingKey;

// The contentOffset.y below which a lifted finger leaves the list pulled past its top.
static const CGFloat kPFBPullToRefreshThreshold = -100.0;

%hook TFNItemsDataViewController

- (void)scrollViewDidEndDragging:(UIScrollView*)scrollView willDecelerate:(BOOL)decelerate {
    %orig;
    UIControl* control = [self respondsToSelector:@selector(pullToLoadTopControl)] ? self.pullToLoadTopControl : nil;
    if (!control || ![objc_getAssociatedObject(control, &kPFBPsstPendingKey) boolValue] ||
        scrollView.contentOffset.y >= kPFBPullToRefreshThreshold) {
        return;
    }
    objc_setAssociatedObject(control, &kPFBPsstPendingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    PFBCompatReach(PFBCompatPath_pull_sound);
    if (![PFBSettings boolForKey:@"restore_refresh_sounds"]) {
        PFBCOMPAT_OBSERVE(PFBCompat_restore_refresh_sounds, @"pull to refresh seen");
        return;
    }
    if (PFBPlayRefreshSound(@"psst2.caf")) {
        PFBCOMPAT_ACTION(PFBCompat_restore_refresh_sounds, @"sound played");
    }
}

%end

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
        objc_setAssociatedObject(control, &kPFBPsstPendingKey, @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    if (status != 0 || !wasLoading) {
        return;
    }
    BOOL manual = [objc_getAssociatedObject(control, &kPFBManualRefreshKey) boolValue];
    objc_setAssociatedObject(control, &kPFBManualRefreshKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(control, &kPFBPsstPendingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!manual) {
        return;
    }
    PFBCompatReach(PFBCompatPath_refresh_end_sound);
    if (![PFBSettings boolForKey:@"restore_refresh_sounds"]) {
        PFBCOMPAT_OBSERVE(PFBCompat_restore_refresh_sounds, @"refresh end seen");
        return;
    }
    if (PFBPlayRefreshSound(@"pop.caf")) {
        PFBCOMPAT_ACTION(PFBCompat_restore_refresh_sounds, @"pop played");
    }
}
%end
