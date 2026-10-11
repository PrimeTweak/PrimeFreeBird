// Shared imports and helpers for the hook files.

#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <dlfcn.h>
#import <math.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "Common/PFBBundle.h"
#import "Support/PFBManager.h"
#import "Common/PFBSettings.h"
#import "Features/Appearance/CustomTabBar/PFBCustomTabBarUtility.h"
#import "Common/PFBCompatibility.h"
#import "Features/Media/PFBDownloadInlineButton.h"

// Recursive view traversal (HookHelpers.m)
void PFBEnumerateSubviewsRecursively(UIView* view,
                                  void (^block)(UIView* currentView));

// TFNDataViewItem unwrapping for timeline section filtering (HookHelpers.m)
id PFBUnwrapDataViewItem(id item);

// A bar material pinned behind a view's contents, invisible until something
// scrolls under it.
UIVisualEffectView* PFBMaterialBehind(UIView* host);

// Module header/footer cleanup for timeline section filtering (HookHelpers.m)
void PFBMarkEmptiedModuleChrome(NSArray* items, NSMutableIndexSet* removed);

// Live square-avatar restyling (Avatars.x)
void PFBApplySquareAvatarsSetting(void);

// Custom theme color re-apply (Theme.x)
void PFBApplySelectedThemeColor(void);

// The custom accent color read from its stored hex, active or not; nil when none is
// stored or the value cannot be read (Theme.x).
UIColor* PFBCustomAccentColor(void);

// Muted-words rules reload after the editor changes them (Timeline.x)
void pfbRefreshMutedWords(void);

// Posts hidden by the muted-words filter since midnight (Timeline.x)
NSInteger pfbMutedHiddenCountToday(void);

// Live pinned-tabs refresh when the hide setting is toggled (Timeline.x)
void PFBApplyHideCustomTimelinesSetting(void);

// Whether the account genuinely has a panel's tab, ignoring the forced tab
// gates (FeatureSwitches.x)
BOOL PFBPanelIsGenuinelyAvailable(long long panelID);

// Web session cookie harvesting (WebCreateTweet.x)
void PFBPrewarmWebCookiesIfNeeded(void);
void PFBMaybeHandleHarvestWebView(__unsafe_unretained id webViewController);

// The mobile Safari user agent presented by the web views and web requests (HookHelpers.m).
FOUNDATION_EXPORT NSString* const PFBMobileSafariUserAgent;
// YES when a usable web session (auth_token + ct0) is available (WebCreateTweet.x).
BOOL PFBHasUsableWebCredentials(void);
// A GET signed with the web session; nil without one or for a URL that is not
// https on x.com (WebCreateTweet.x).
NSMutableURLRequest* PFBWebSessionGETRequest(NSURL* url);
// Saves the web session cookies for PrimeFreeBird's own requests.
void PFBStoreWebCookies(NSArray<NSHTTPCookie*>* cookies);
// The web auth_token a request was signed with: a bridged account signs with its own
// session's token, which holds no dash. nil for any other request (WebCreateTweet.x).
NSString* PFBWebAuthTokenOfRequest(NSURLRequest* request);
// The ct0 of a web auth_token, or nil while unknown; never blocks. With mint set, an
// unknown one is fetched in the background for the next request (WebCreateTweet.x).
NSString* PFBWebCt0ForAuthToken(NSString* authToken, BOOL mint);

// The image view currently carrying the top-bar logo, or nil (Theme.x).
UIImageView* PFBTopBarLogoViewCurrent(void);

// Whether a themed tab bar is switched on and an accent is active (Theme.x).
BOOL PFBThemedTabBarWanted(void);

// A copy of `source` painted in `color` through its own alpha, rendered as
// AlwaysOriginal so no tint can change it afterwards (NavBarIcons.x).
UIImage* PFBPaintedGlyph(UIImage* source, UIColor* colour);

// The same repaint, without the mark PFBPaintedGlyph leaves on its result
// (HiddenNotifications.x).
UIImage* PFBFlatGlyph(UIImage* source, UIColor* colour);

// Present the interactive "Log in to Web Session" screen. The completion fires with
// YES once cookies were harvested and stored, NO if the user cancelled.
void PFBPresentWebSessionLogin(void (^completion)(BOOL success));

// Wipes the stored web session: the tokens in memory, and X's and Twitter's cookies and
// web view data.
void PFBClearWebSession(void);

// Seed a reply webview's own cookie store with the current session, then run done.
void PFBSeedReplyWebViewCookies(WKWebView* webView, void (^done)(void));

// Whether a host or cookie domain belongs to X or Twitter: an exact match or a
// subdomain, never a substring, so x.com.example.net does not pass.
BOOL PFBIsXDomain(NSString* domainOrHost);

// Whether a send sound is stored, and the name of the file it was imported from (SendSound.x).
BOOL PFBSendSoundIsSet(void);
NSString* PFBSendSoundName(void);
// Stores an audio file of at most 7 s as the send sound, off the main thread; the completion
// runs on the main thread with nil, or the string key of the reason it was refused.
void PFBSendSoundImport(NSURL* source, void (^completion)(NSString* failureKey));
// Deletes the stored send sound and its name.
void PFBSendSoundRemove(void);

// Text filled in after a lookup, such as a plural format, in Twitter's terminology when
// Restore Twitter terminology is on (Branding.x).
NSString* PFBTwitterTerminology(NSString* text);

// Brackets a read of the real verified flags, which Hide blue verified otherwise answers
// NO for (HideUI.x).
void PFBBeginRawVerifiedRead(void);
void PFBEndRawVerifiedRead(void);

// A screen joins, then leaves, the count of open screens that whiten the confirm glyph
// of the navigation bar (Theme.x); each screen counts once however often it appears.
void PFBThemeScreenEnter(UIViewController* screen);
void PFBThemeScreenLeave(UIViewController* screen);

// Bar items of PrimeFreeBird's own screens carry this tag and keep UIKit's glass;
// the app-wide flattening in NavBarIcons.x leaves them alone.
static const NSInteger PFBNativeGlassTag = 0x4E4647;

// Tint laid on glass for legibility over busy content: the reply bar while the
// keyboard is up, and the path tour's box.
static const CGFloat PFBGlassTint = 0.42;

// A Twitter glyph in the box of the system symbol it replaces, which stays as the fallback.
FOUNDATION_EXPORT UIImage* PFBTwitterGlyphFor(NSString* name, UIImage* systemImage);
