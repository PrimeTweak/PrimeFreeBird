// Entry point: starts, in their established order, the parts that need work at launch.
// Hooks install themselves.

#import <Foundation/Foundation.h>

void PFBCompatStart(void);
void PFBCompatTourResumeAtLaunch(void);
void PFBAppLifecycleStart(void);
void PFBRefreshSoundsStart(void);
void PFBThemeStart(void);
void PFBWebReplyStart(void);
void PFBSendSoundStart(void);

%ctor {
    PFBCompatStart();
    PFBCompatTourResumeAtLaunch();
    PFBAppLifecycleStart();
    PFBRefreshSoundsStart();
    PFBThemeStart();
    PFBWebReplyStart();
    PFBSendSoundStart();
}
