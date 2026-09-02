//
//  NFBDebugger.h
//
//  A built-in debugger for the tweak. Three jobs:
//
//    1. HEALTH — at launch, check every class and method the tweak hooks, and
//       every class it resolves by name, against the running app. A missing one
//       means Twitter renamed or removed it and that feature is silently dead.
//       This is the check that would have named today's profile-button bug in
//       one line instead of a probe, a build and a Console session.
//
//    2. CAPTURE — shake the device on a misbehaving screen and the whole view
//       hierarchy is frozen into a report: classes, frames, colours, render
//       modes, and the tweak's own marks (below).
//
//    3. MARKS + LOG — the tweak calls NFBMark() wherever it claims a view, and
//       NFBDebugLog() wherever it makes a decision. Both surface in the report,
//       so a capture says not just what a view is but what the tweak did to it.
//
//  The report is written to a file and opened in the share sheet. All of it is
//  gated behind the existing flex_twitter setting: zero cost when off.
//

#import <UIKit/UIKit.h>

// Marks a view as claimed by the tweak, with a short origin like
// @"NavBarIcons/backArrow". Stored as an associated object; shown in a capture
// beneath the view it belongs to. No-op when debugging is off. Reads nothing,
// changes nothing about the view itself.
extern void NFBMark(UIView* view, NSString* origin);

// Records a decision the tweak just made, like @"timeline: dropped 3 items" or
// @"inbox pill: pinned opaque". Kept in a small ring buffer and printed in the
// report. No-op when debugging is off.
extern void NFBDebugLog(NSString* format, ...) NS_FORMAT_FUNCTION(1, 2);

// Installs the shake recogniser and runs the launch health check. Called once
// from the app delegate, behind the flex_twitter gate.
extern void NFBDebuggerInstall(void);

// Builds the full report as a string: environment, hook health, decision log
// and — when a capture has been taken — the frozen hierarchy.
extern NSString* NFBDebuggerReport(void);

// The number of hooked classes, hooked methods and by-name classes that no
// longer exist in the running app. Zero means every dependency is present.
extern NSUInteger NFBDebuggerMissingCount(void);

// Writes the current report to a temp file and returns its URL, for the share
// sheet. Returns nil only if the write itself failed.
extern NSURL* NFBDebuggerWriteReportFile(void);

// Presents the diagnostics screen over whatever is frontmost. The shake takes
// a capture first, then calls this; the settings row calls it directly.
extern void NFBDebuggerPresent(void);

// Captures the frontmost screen and opens the diagnostics sheet. This is what
// the floating button calls; the shake, when it works, calls it too.
extern void NFBDebuggerCaptureAndPresent(void);

// Hides the floating button while the diagnostics sheet is up, so it does not
// sit on top of the report it produced.
extern void NFBDebuggerSetTriggerHidden(BOOL hidden);

// True only when debugging is on. Call sites in hot paths test this before
// building any log string, so the debugger costs one boolean when off.
extern BOOL NFBDebugIsRecording(void);

// One report of what the branding surfaces actually are on the running build:
// the top-bar logo, the bottom bar and its glass, the Explore bar, and the four
// settings that drive them. Read only, once per launch, written into the
// journal next to the hook health. Reach for this first when a surface stops
// behaving, instead of scattering one-off probes through the hooks.
extern void NFBReportBrandingSurfaces(void);

// The watch list: class-name fragments added at runtime from the diagnostics
// screen. Matching views have their lifecycle journaled with millisecond
// stamps and instance pointers.
extern NSArray<NSString*>* NFBWatchAll(void);
extern void NFBWatchAdd(NSString* fragment);
extern void NFBWatchRemove(NSString* fragment);
extern BOOL NFBWatchMatchesClassName(NSString* className);
