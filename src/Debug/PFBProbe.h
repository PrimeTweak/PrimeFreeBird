// The measurement probe: each line is noted once per PrimeFreeBird build, kept across
// launches and printed in the report's PROBE section. Inert unless debug_tools is on.

#import <UIKit/UIKit.h>

// Whether a key has not been noted yet on this build; NO while debug_tools is off.
FOUNDATION_EXPORT BOOL PFBProbeWants(NSString* key);
// Notes a line under the key, once per build; the tour step in front is named with it.
FOUNDATION_EXPORT void PFBProbeNote(NSString* key, NSString* format, ...) NS_FORMAT_FUNCTION(2, 3);
// The report's PROBE section.
FOUNDATION_EXPORT NSString* PFBProbeReportText(void);

// The tour step whose screen is up, or nil outside a tour (PFBCompatibilityTour.m).
FOUNDATION_EXPORT NSString* PFBProbeTourStep(void);
// Posted on the main thread when a tour ends, completed or cancelled.
FOUNDATION_EXPORT NSNotificationName const PFBProbeTourEndedNotification;

// Seconds since PrimeFreeBird was loaded in this launch.
FOUNDATION_EXPORT CFTimeInterval PFBProbeSinceLaunch(void);
// A moment one file marks and another reads: the age in seconds, or -1 if never marked.
FOUNDATION_EXPORT void PFBProbeMark(NSString* name);
FOUNDATION_EXPORT CFTimeInterval PFBProbeMarkAge(NSString* name);
// A counter shared across threads: adds one and returns the new value.
FOUNDATION_EXPORT NSUInteger PFBProbeCount(NSString* name);
FOUNDATION_EXPORT NSUInteger PFBProbeCountValue(NSString* name);

// Reading the app without acting on it.
FOUNDATION_EXPORT NSString* PFBProbeClassName(id object);
FOUNDATION_EXPORT UIViewController* PFBProbeControllerOfView(UIView* view);
// The topmost parent of a controller below its navigation stack, by class name.
FOUNDATION_EXPORT NSString* PFBProbeScreenName(UIViewController* controller);
// Twitter's main window, and the screen in front in it (main thread only, else "?").
FOUNDATION_EXPORT UIWindow* PFBProbeAppWindow(void);
FOUNDATION_EXPORT NSString* PFBProbeFrontScreen(void);
// The class of the key window, or "none".
FOUNDATION_EXPORT NSString* PFBProbeKeyWindowName(void);
// A getter's object or integer, read only when its signature says it returns one.
FOUNDATION_EXPORT id PFBProbeGetter(id object, NSString* name);
FOUNDATION_EXPORT long long PFBProbeIntegerGetter(id object, NSString* name, BOOL* found);
// A color as "r,g,b,a" (0-255), resolved with the given traits when there are some.
FOUNDATION_EXPORT NSString* PFBProbeColor(UIColor* color, UITraitCollection* traits);
