// Probe for the Menu's Premium items: Twitter's own sidebar rebuilt three times with the menu
// closed, with Premium unlocked, with the real Premium, then with the real Premium and the real
// item gates. Removed once read.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Set while one of the probe's rebuilds runs.
FOUNDATION_EXPORT BOOL PFBMenuProbeRecording;

// What Twitter does during a probe rebuild, from the hooks in FeatureSwitches.x.
FOUNDATION_EXPORT NSArray* PFBMenuProbeAnswer(NSArray* panelIDs);
FOUNDATION_EXPORT void PFBMenuProbeNoteContent(id content);
FOUNDATION_EXPORT void PFBMenuProbeNoteNamed(long long panelID);
FOUNDATION_EXPORT void PFBMenuProbeNoteSwitch(NSString* key);
FOUNDATION_EXPORT void PFBMenuProbeNoteSubscription(NSUInteger tier, BOOL subscribed);

// From FeatureSwitches.x: whether the menu is open, and the account read as it really is.
FOUNDATION_EXPORT BOOL PFBMenuProbeMenuOpen(void);
FOUNDATION_EXPORT void PFBMenuProbeSetRealReads(BOOL subscription, BOOL gates);

NS_ASSUME_NONNULL_END
