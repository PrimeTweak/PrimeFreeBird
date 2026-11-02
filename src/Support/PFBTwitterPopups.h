// Twitter's own pop-ups reached from the tweak: its Tray, its toast and its alerts. Each says
// whether Twitter took the pop-up, so a caller keeps its own where the app no longer has one.

#import <UIKit/UIKit.h>

// Whether the app can show its Tray with rows the tweak builds.
BOOL PFBTrayAvailable(void);

// A row of Twitter's Tray with a Twitter glyph and, when given, a line under its title; nil when
// the app no longer builds them.
id PFBTrayRow(NSString* title, NSString* subtitle, NSString* iconName, BOOL disabled, void (^action)(void));

// Twitter's Tray titled title over from, with the rows given; NO when the app cannot show it.
BOOL PFBPresentTray(UIViewController* from, NSString* title, NSArray* rows);

// Runs block once nothing above the app is still opening or closing, so a Tray can follow one.
void PFBAfterPresentations(void (^block)(void));

typedef NS_ENUM(NSInteger, PFBToastKind) {
    PFBToastKindPlain,
    PFBToastKindSuccess,
    PFBToastKindError,
};

// A message in Twitter's toast, with a button when actionTitle is given. It replaces the tweak's
// toast on screen and leaves after Twitter's own time; a persistent one stays until another
// replaces it or the toasts are cleared. NO without a toaster.
BOOL PFBPushTwitterToast(NSString* text, NSString* detail, PFBToastKind kind, NSString* actionTitle,
                         void (^action)(void), BOOL persistent);

// Whether the last persistent toast pushed is the one Twitter shows.
BOOL PFBPersistentToastShowing(void);

// Takes the tweak's toasts off the screen and out of Twitter's queue.
void PFBClearTwitterToasts(void);

// Adds a button the way Twitter adds its own when twitter is YES, so the app can draw the alert
// in its style; the system's way otherwise.
UIAlertAction* PFBAlertAddAction(UIAlertController* alert, NSString* title, UIAlertActionStyle style, BOOL twitter,
                                 void (^handler)(void));

// Presents the alert through Twitter when twitter is YES, the system's way otherwise.
void PFBAlertPresent(UIAlertController* alert, UIViewController* from, BOOL twitter, void (^completion)(void));
