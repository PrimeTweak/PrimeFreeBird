// The built-in debugger: hook health, a decision journal and a capture of the screen.

#import <UIKit/UIKit.h>

// Marks a view as claimed by PrimeFreeBird, with a short origin such as
// @"NavBarIcons/backArrow". Stored as an associated object and shown in a capture;
// a no-op when debugging is off.
extern void PFBMark(UIView* view, NSString* origin);

// A color as rgba(255 scale, alpha), or white(level, alpha), for reports.
extern NSString* PFBColorText(UIColor* color);

// The average color of an image's visible pixels as rgb(255 scale), or "transparent"; nil
// without an image.
extern NSString* PFBImageInk(UIImage* image);

// A class name as Swift writes it ("XNavigation.TabBarView"), for reports.
extern NSString* PFBReadableClassName(id object);

// Records a decision just made, like @"timeline: dropped 3 items". Kept in a small
// ring buffer and printed in the report. No-op when debugging is off.
extern void PFBDebugLog(NSString* format, ...) NS_FORMAT_FUNCTION(1, 2);

// Places the floating button when debug_tools is on, and again whenever Twitter comes
// to the front without it. Called once at launch.
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
// sit on top of the report it produced. A button placed meanwhile starts hidden.
extern void PFBDebuggerSetTriggerHidden(BOOL hidden);

// True only when debugging is on. Call sites in hot paths test this before
// building any log string, so the debugger costs one boolean when off.
extern BOOL PFBDebugIsRecording(void);

// True once Twitter's new settings menu has been read in this launch, so the tour
// keeps it open until then (PFBSettingsMenuProbe.x).
extern BOOL PFBSettingsMenuProbeRead(void);

// The same for Twitter's tab editor (PFBTabEditorProbe.x).
extern BOOL PFBTabEditorProbeRead(void);

// The opacity a view shows with: zero when it or a parent is hidden (PFBScreenProbe.x).
extern CGFloat PFBShownOpacity(UIView* view);
