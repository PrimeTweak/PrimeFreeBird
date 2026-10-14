// Restores the classic pull-to-refresh sounds: the psst on release, detected through
// the scroll delegate, and the pop once the refresh that pull started completes. The
// files must be PCM, since AudioServicesCreateSystemSoundID has no AAC decoder.

#import "Support/HookHelpers.h"
#import "Debug/PFBDebugger.h"
#import "Debug/PFBProbe.h"

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

// Probe (11#F036): outside tours, the last eight refresh status changes are kept, and each
// finger lift past -100 is checked against them 0.8 s later; one line per outcome.
static int gPFBProbePsstState;
static uint32_t gPFBProbePsstSeen;
static NSMutableArray<NSDictionary*>* gPFBProbeRefreshEvents;

static BOOL PFBProbePsstOpen(void) {
    if (gPFBProbePsstState == 0) {
        gPFBProbePsstState = PFBDebugIsRecording() ? 1 : 2;
    }
    return gPFBProbePsstState == 1 && NSThread.isMainThread && !PFBCompatTourIsRunning();
}

// Probe: a status change of a pull-to-refresh control, with the scroll view it sits in.
static void PFBProbeRefreshStatus(UIView* control, unsigned long long status, BOOL fromScrolling, BOOL wasLoading) {
    if (!PFBProbePsstOpen()) {
        return;
    }
    UIView* node = control.superview;
    for (NSInteger depth = 0; node && depth < 6 && ![node isKindOfClass:[UIScrollView class]]; depth++) {
        node = node.superview;
    }
    if (!gPFBProbeRefreshEvents) {
        gPFBProbeRefreshEvents = [NSMutableArray array];
    }
    [gPFBProbeRefreshEvents addObject:@{
        @"at": @(CACurrentMediaTime()),
        @"status": @(status),
        @"scrolling": @(fromScrolling),
        @"loading": @(wasLoading),
        @"scroll": [NSValue valueWithPointer:(__bridge const void*)node]
    }];
    if (gPFBProbeRefreshEvents.count > 8) {
        [gPFBProbeRefreshEvents removeObjectAtIndex:0];
    }
}

// Probe: the status 1 nearest to a lift, from 3 s before it to 0.8 s after, on the same list.
static void PFBProbePsstCheck(NSString* owner, CFTimeInterval lift, CGFloat offset, CGFloat top, const void* scroll) {
    if (!PFBProbePsstOpen()) {
        return;
    }
    NSDictionary* nearest = nil;
    double nearestDelta = 0;
    for (NSDictionary* event in gPFBProbeRefreshEvents) {
        double delta = [event[@"at"] doubleValue] - lift;
        const void* eventScroll = [event[@"scroll"] pointerValue];
        if ([event[@"status"] unsignedLongLongValue] != 1 || delta < -3.0 || delta > 0.8 ||
            (eventScroll && eventScroll != scroll)) {
            continue;
        }
        if (!nearest || fabs(delta) < fabs(nearestDelta)) {
            nearest = event;
            nearestDelta = delta;
        }
    }
    CGFloat past = -(offset + top);
    BOOL pulled = past > 40.0;
    NSUInteger outcome = !nearest ? 2 : ([nearest[@"scrolling"] boolValue] ? 0 : 1);
    uint32_t bit = 1u << (outcome * 2 + (pulled ? 0 : 1));
    if (gPFBProbePsstSeen & bit) {
        return;
    }
    gPFBProbePsstSeen |= bit;
    if ((gPFBProbePsstSeen & 0x3F) == 0x3F) {
        gPFBProbePsstState = 2;
    }
    static NSString* const outcomes[] = {@"status1 YES", @"status1 NO", @"none"};
    NSString* key = [NSString stringWithFormat:@"11#F036 %@ %@", outcomes[outcome], pulled ? @"pulled" : @"at rest"];
    if (!PFBProbeWants(key)) {
        return;
    }
    NSString* lifted = [NSString stringWithFormat:@"lift on %@ at %.0f (inset %.0f, %.0f pt past rest)", owner, offset, top, past];
    if (nearest) {
        PFBProbeNote(key, @"11#F036 psst check: %@ \u00b7 Twitter status 1 fromScrolling=%@ wasLoading=%@ %.0f ms %@ the lift",
                     lifted, [nearest[@"scrolling"] boolValue] ? @"YES" : @"NO", [nearest[@"loading"] boolValue] ? @"YES" : @"NO",
                     fabs(nearestDelta) * 1000.0, nearestDelta < 0 ? @"before" : @"after");
    } else {
        PFBProbeNote(key, @"11#F036 psst check: %@ \u00b7 no status 1 from 3 s before to 0.8 s after: psst without a refresh",
                     lifted);
    }
}

// Probe: a finger lift past -100, checked 0.8 s later; the scroll view is kept as an address only.
static void PFBProbePsstLift(id controller, UIScrollView* scrollView) {
    if (!PFBProbePsstOpen()) {
        return;
    }
    CFTimeInterval lift = CACurrentMediaTime();
    CGFloat offset = scrollView.contentOffset.y;
    CGFloat top = scrollView.adjustedContentInset.top;
    NSString* owner = NSStringFromClass([controller class]);
    const void* scroll = (__bridge const void*)scrollView;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      PFBProbePsstCheck(owner, lift, offset, top, scroll);
    });
}

%hook TFNItemsDataViewController

- (void)scrollViewDidEndDragging:(UIScrollView*)scrollView willDecelerate:(BOOL)decelerate {
    %orig;
    // contentOffset.y as the finger lifts: strongly negative means the list was
    // pulled below its top, which is the refresh intent.
    if (scrollView.contentOffset.y >= kPFBPullToRefreshThreshold) {
        return;
    }
    // Probe: the lift past -100, checked against Twitter's refresh status 0.8 s later.
    PFBProbePsstLift(self, scrollView);
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

// The control's loading state, read by name.
@protocol PFBRefreshControlLoading
@property (nonatomic, readonly) BOOL loading;
@end

%hook TFNPullToRefreshControl
- (void)_setStatus:(unsigned long long)status fromScrolling:(BOOL)fromScrolling {
    id control = (id)self;
    SEL loadingSelector = @selector(loading);
    BOOL wasLoading = [control respondsToSelector:loadingSelector] &&
                      ((BOOL (*)(id, SEL))objc_msgSend)(control, loadingSelector);
    %orig;
    // Probe: the status change, for the psst check of a finger lift.
    PFBProbeRefreshStatus((UIView*)control, status, fromScrolling, wasLoading);
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
