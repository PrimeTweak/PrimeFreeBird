// The built-in debugger: hook health at launch, a decision journal, captures of
// the screen state and the watch list. Inert unless debug_tools is on.

#import <UIKit/UIKit.h>

// Marks a view as claimed by the tweak, with a short origin such as
// @"NavBarIcons/backArrow". Stored as an associated object and shown in a capture;
// a no-op when debugging is off.
extern void PFBMark(UIView* view, NSString* origin);

// Records a decision the tweak just made, like @"timeline: dropped 3 items" or
// @"inbox pill: pinned opaque". Kept in a small ring buffer and printed in the
// report. No-op when debugging is off.
extern void PFBDebugLog(NSString* format, ...) NS_FORMAT_FUNCTION(1, 2);

// Places the floating button and runs the launch health check. Called once
// from the app delegate, behind the flex_twitter gate.
extern void PFBDebuggerInstall(void);

// Builds the full report as a string: environment, hook health, decision log
// and — when a capture has been taken — the frozen hierarchy.
extern NSString* PFBDebuggerReport(void);

// The number of hooked classes, hooked methods and by-name classes that no
// longer exist in the running app. Zero means every dependency is present.
extern NSUInteger PFBDebuggerMissingCount(void);

// Writes the current report to a temp file and returns its URL, for the share
// sheet. Returns nil only if the write itself failed.
extern NSURL* PFBDebuggerWriteReportFile(void);

// Presents the diagnostics screen over whatever is frontmost. The floating button
// takes a capture first, then calls this; the settings row calls it directly.
extern void PFBDebuggerPresent(void);

// Captures the frontmost screen and opens the diagnostics sheet; the floating
// button calls it.
extern void PFBDebuggerCaptureAndPresent(void);

// Hides the floating button while the diagnostics sheet is up, so it does not
// sit on top of the report it produced.
extern void PFBDebuggerSetTriggerHidden(BOOL hidden);

// True only when debugging is on. Call sites in hot paths test this before
// building any log string, so the debugger costs one boolean when off.
extern BOOL PFBDebugIsRecording(void);

// One report of what the branding surfaces are on the running build: the top-bar
// logo, the bottom bar and its glass, the Explore bar, and the settings that drive
// them. Read only, once per launch, written next to the hook health.
extern void PFBReportBrandingSurfaces(void);

// Everything that can make the bottom bar opaque, in one pass: the view chain under
// the host with each view's color, alpha, hidden flag, contents and filters, plus
// where the glass sits. Run twice so a repaint between the two shows as a change.
extern void PFBReportTabBarStack(NSString* moment);

// The navigation bar's own tree with frames. Captured on a good screen and on a
// bad one, the difference names the view that moved.
extern void PFBReportNavigationBar(NSString* moment);

// The watch list: class-name fragments added at runtime from the diagnostics
// screen. Matching views have their lifecycle journaled with millisecond
// stamps and instance pointers.
extern NSArray<NSString*>* PFBWatchAll(void);
extern void PFBWatchAdd(NSString* fragment);
extern void PFBWatchRemove(NSString* fragment);
extern BOOL PFBWatchMatchesClassName(NSString* className);
