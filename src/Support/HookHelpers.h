// Shared imports and helpers for the hook files.

#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <Foundation/Foundation.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
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
#import "Support/TWHeaders.h"
#import "Features/General/PFBAuthViewController.h"
#import "Settings/PFBModernSettingsViewController.h"
#import "Features/Appearance/ThemeColor/PFBPalette.h"

// Recursive view traversal (HookHelpers.m)
void PFBEnumerateSubviewsRecursively(UIView* view,
                                  void (^block)(UIView* currentView));

// TFNDataViewItem unwrapping for timeline section filtering (HookHelpers.m)
id PFBUnwrapDataViewItem(id item);

// With an arrow, a popover's content runs past the bubble's bottom edge by about
// the arrow's height; pinned footers reserve it so they open fully in view.
extern const CGFloat PFBPopoverArrowReserve;

// Journals how far an open popover's content runs past the bubble, beside the
// reserve. Debug only; it never touches the layout.
void PFBPopoverLogOverflow(UIView* content);

// A bar material pinned behind a view's contents, invisible until something
// scrolls under it.
UIVisualEffectView* PFBMaterialBehind(UIView* host);

// Module header/footer cleanup for timeline section filtering (HookHelpers.m)
BOOL PFBIsModuleHeaderItem(id item);
BOOL PFBIsModuleFooterItem(id item);
void PFBMarkEmptiedModuleChrome(NSArray* items, NSMutableIndexSet* removed);

// Live square-avatar restyling (Avatars.x)
void PFBApplySquareAvatarsSetting(void);

// Custom theme color re-apply (Theme.x)
void PFBApplySelectedThemeColor(void);

// Muted-words rules reload after the editor changes them (Timeline.x)
void pfbRefreshMutedWords(void);

// Posts hidden by the muted-words filter since midnight (Timeline.x)
NSInteger pfbMutedHiddenCountToday(void);

// Live pinned-tabs refresh when the hide setting is toggled (Timeline.x)
void PFBApplyHideCustomTimelinesSetting(void);

// Whether the account genuinely has a panel's tab, ignoring the forced tab
// gates (FeatureSwitches.x)
BOOL PFBPanelIsGenuinelyAvailable(long long panelID);

// Restored tweet source labels, keyed by tweet ID (SourceLabels.x)
extern NSMutableDictionary* gPFBTweetSources;

// Web session cookie harvesting (WebCreateTweet.x)
void PFBPrewarmWebCookiesIfNeeded(void);
void PFBMaybeHandleHarvestWebView(__unsafe_unretained id webViewController);
id PFBAccountForAuthenticatedWebView(void);

// Current web-session credentials (auth_token + ct0) for read-only web GraphQL
// requests such as restoring tweet source labels (WebCreateTweet.x)
NSDictionary* PFBCurrentWebCredentials(void);

// YES when a usable web session (auth_token + ct0) is available.
BOOL PFBHasUsableWebCredentials(void);
// Saves the web session cookies for the tweak's own requests.
void PFBStoreWebCookies(NSArray<NSHTTPCookie*>* cookies);

// The image view currently carrying the top-bar logo, or nil (Theme.x).
UIImageView* PFBTopBarLogoViewCurrent(void);

// Whether a themed tab bar is switched on and an accent is active (Theme.x).
BOOL PFBThemedTabBarWanted(void);

// A copy of `source` painted in `color` through its own alpha, rendered as
// AlwaysOriginal so no tint can change it afterwards (NavBarIcons.x).
UIImage* PFBPaintedGlyph(UIImage* source, UIColor* colour);

// Present the interactive "Log in to Web Session" screen. The completion fires with
// YES once cookies were harvested and stored, NO if the user cancelled.
void PFBPresentWebSessionLogin(void (^completion)(BOOL success));

// Wipe the stored web session (in-memory tokens + x/twitter cookies + WKWebView data).
void PFBClearWebSession(void);

// Seed a reply webview's own cookie store with the current session, then run done.
void PFBSeedReplyWebViewCookies(WKWebView* webView, void (^done)(void));

// Whether a host or cookie domain belongs to X or Twitter: an exact match or a
// subdomain, never a substring, so x.com.example.net does not pass.
BOOL PFBIsXDomain(NSString* domainOrHost);

// Bar items of the tweak's own screens carry this tag and keep UIKit's glass;
// the app-wide flattening in NavBarIcons.x leaves them alone.
static const NSInteger PFBNativeGlassTag = 0x4E4647;

// Tint laid on glass for legibility over busy content: the reply bar while the
// keyboard is up, and the path tour's box.
static const CGFloat PFBGlassTint = 0.42;

// A Twitter glyph in the box of the system symbol it replaces, which stays as the fallback.
FOUNDATION_EXPORT UIImage* PFBTwitterGlyphFor(NSString* name, UIImage* systemImage);
