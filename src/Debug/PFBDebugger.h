// The built-in debugger: hook health, a decision journal and a capture of the
// screen state. Inert unless debug_tools is on.

#import <UIKit/UIKit.h>

// Marks a view as claimed by PrimeFreeBird, with a short origin such as
// @"NavBarIcons/backArrow". Stored as an associated object and shown in a capture;
// a no-op when debugging is off.
extern void PFBMark(UIView* view, NSString* origin);

// Records a decision just made, like @"timeline: dropped 3 items" or
// @"inbox pill: pinned opaque". Kept in a small ring buffer and printed in the
// report. No-op when debugging is off.
extern void PFBDebugLog(NSString* format, ...) NS_FORMAT_FUNCTION(1, 2);

// Places the floating button when debug_tools is on. Called once at launch.
extern void PFBDebuggerInstall(void);

// Builds the full report as a string: environment, hook health, decision log
// and — when a capture has been taken — the frozen hierarchy.
extern NSString* PFBDebuggerReport(void);

// Presents the diagnostics screen over whatever is frontmost. Called after a capture
// by PFBDebuggerCaptureAndPresent, and directly by the compatibility tour when it
// ends with debug_tools off.
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
