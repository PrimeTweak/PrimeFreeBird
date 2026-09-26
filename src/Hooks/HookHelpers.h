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
#import "Core/BHTBundle.h"
#import "Core/BHTManager.h"
#import "Core/BHTSettings.h"
#import "CustomTabBar/CustomTabBarUtility.h"
#import "Download/DownloadInlineButton.h"
#import "Headers/TWHeaders.h"
#import "Padlock/AuthViewController.h"
#import "Settings/ModernSettingsViewController.h"
#import "ThemeColor/Palette.h"

// Recursive view traversal (HookHelpers.m)
void EnumerateSubviewsRecursively(UIView* view,
                                  void (^block)(UIView* currentView));

// TFNDataViewItem unwrapping for timeline section filtering (HookHelpers.m)
id unwrapDataViewItem(id item);

// With an arrow, a popover's content runs past the bubble's bottom edge by about
// the arrow's height; pinned footers reserve it so they open fully in view.
extern const CGFloat NFBPopoverArrowReserve;

// Journals how far an open popover's content runs past the bubble, beside the
// reserve. Debug only; it never touches the layout.
void NFBPopoverLogOverflow(UIView* content);

// A bar material pinned behind a view's contents, invisible until something
// scrolls under it.
UIVisualEffectView* NFBMaterialBehind(UIView* host);

// Module header/footer cleanup for timeline section filtering (HookHelpers.m)
BOOL IsModuleHeaderItem(id item);
BOOL IsModuleFooterItem(id item);
void MarkEmptiedModuleChrome(NSArray* items, NSMutableIndexSet* removed);

// Live square-avatar restyling (Avatars.x)
void applySquareAvatarsSetting(void);

// Custom theme color re-apply (Theme.x)
void applySelectedThemeColor(void);

// Muted-words rules reload after the editor changes them (Timeline.x)
void nfbRefreshMutedWords(void);

// Posts hidden by the muted-words filter since midnight (Timeline.x)
NSInteger nfbMutedHiddenCountToday(void);

// Live pinned-tabs refresh when the hide setting is toggled (Timeline.x)
void applyHideCustomTimelinesSetting(void);

// Whether the account genuinely has a panel's tab, ignoring the forced tab
// gates (FeatureSwitches.x)
BOOL panelIsGenuinelyAvailable(long long panelID);

// Restored tweet source labels, keyed by tweet ID (SourceLabels.x)
extern NSMutableDictionary* tweetSources;

// Web session cookie harvesting (WebCreateTweet.x)
void prewarmWebCookiesIfNeeded(void);
void maybeHandleHarvestWebView(__unsafe_unretained id webViewController);
id accountForAuthenticatedWebView(void);

// Current web-session credentials (auth_token + ct0) for read-only web GraphQL
// requests such as restoring tweet source labels (WebCreateTweet.x)
NSDictionary* currentWebCredentials(void);

// YES when a usable web session (auth_token + ct0) is available.
BOOL hasUsableWebCredentials(void);

// The image view currently carrying the top-bar logo, or nil (Theme.x).
UIImageView* NFBTopBarLogoViewCurrent(void);

// Whether a themed tab bar is switched on and an accent is active (Theme.x).
BOOL NFBThemedTabBarWanted(void);

// A copy of `source` painted in `colour` through its own alpha, rendered as
// AlwaysOriginal so no tint can change it afterwards (NavBarIcons.x).
UIImage* NFBPaintedGlyph(UIImage* source, UIColor* colour);

// Present the interactive "Log in to Web Session" screen. The completion fires with
// YES once cookies were harvested and stored, NO if the user cancelled.
void presentWebSessionLogin(void (^completion)(BOOL success));

// Wipe the stored web session (in-memory tokens + x/twitter cookies + WKWebView data).
void clearWebSession(void);

// Seed a reply webview's own cookie store with the current session, then run done.
void seedReplyWebViewCookies(WKWebView* webView, void (^done)(void));

// Whether a host or cookie domain belongs to X or Twitter: an exact match or a
// subdomain, never a substring, so x.com.example.net does not pass.
BOOL NFBIsXDomain(NSString* domainOrHost);
