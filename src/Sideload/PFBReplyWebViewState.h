// State the reply web view shares with the hooks that keep its keyboard and focus in line.
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

extern BOOL gPFBReplyWebViewActive;
extern BOOL gPFBForceNextFocus;
extern __weak UIScrollView* gPFBReplyScroller;
extern int gPFBAnimsKilled;
extern CFTimeInterval gPFBSquelchUntil;
extern WKWebView* gPFBIconBar;
extern __weak WKWebView* gPFBRelayWebView;

// The first responder under a view, searched depth-first.
UIView* PFBFindFirstResponder(UIView* v);
// Opens a Tweet in the app from its ID.
void PFBOpenStatusNatively(NSString* statusID);
