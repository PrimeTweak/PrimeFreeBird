// Entry point: starts, in order, the parts that need work at launch.

#import <Foundation/Foundation.h>

void PFBCompatStart(void);
void PFBCompatTourResumeAtLaunch(void);
void PFBAppLifecycleStart(void);
void PFBThemeStart(void);
void PFBWebReplyStart(void);
void PFBSendSoundStart(void);

%ctor {
    PFBCompatStart();
    PFBCompatTourResumeAtLaunch();
    PFBAppLifecycleStart();
    PFBThemeStart();
    PFBWebReplyStart();
    PFBSendSoundStart();
}
