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

// Depth-first walk that also enters hidden and transparent views, down to maxDepth
// levels below view (HookHelpers.m)
void PFBWalkAllSubviews(UIView* view, NSInteger maxDepth, void (^block)(UIView* currentView));

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

// Pushes the accent through Twitter's palette again, so the surfaces that follow it
// repaint (Theme.x).
void PFBSyncAccentTheme(void);

// The custom accent color read from its stored hex, active or not; nil when none is
// stored or the value cannot be read (Theme.x).
UIColor* PFBCustomAccentColor(void);

// Muted-words rules reload after the editor changes them (Timeline.x)
void pfbRefreshMutedWords(void);

// Posts hidden by the muted-words filter since midnight (Timeline.x)
NSInteger pfbMutedHiddenCountToday(void);

// Live pinned-tabs refresh when the hide setting is toggled (Timeline.x)
void PFBApplyHideCustomTimelinesSetting(void);

// Runs the timeline filter again on the timelines already on screen (Timeline.x).
void pfbReapplyTimelineFilter(void);

// The hidden-conversation registry, and taking one entry out of it (HiddenThreads.x).
NSArray<NSDictionary*>* PFBHiddenThreads(void);
void PFBUnhideThread(NSString* threadID);
// Whether a timeline item belongs to a hidden conversation (HiddenThreads.x).
BOOL pfbThreadIsHidden(id viewModel);

// YES only for hide_explore_all, which takes the whole Explore chrome (ExploreTabs.x).
BOOL pfbShouldHideAllTrends(void);
// Records the accessory view the Explore guide vends, so the tab filter touches only
// that bar: the segmented bar class is shared with Notifications and search results.
void pfbNoteExploreAccessoryView(UIView* v);

// The hidden-notification registry, newest hidden first, unhiding one or all of it, and
// the days an entry has left (HiddenNotifications.x).
NSArray<NSDictionary*>* PFBHiddenNotifList(void);
void PFBUnhideNotif(NSString* notifID);
void PFBUnhideAllNotifs(void);
double PFBNotifDaysLeft(NSDictionary* entry);

// Removes tracking parameters from links copied to the pasteboard while
// strip_url_tracking is on (Misc.x).
void PFBInstallPasteboardObserver(void);

// Whether the account genuinely has a panel's tab, ignoring the forced tab
// gates (FeatureSwitches.x)
BOOL PFBPanelIsGenuinelyAvailable(long long panelID);
// The last panels Twitter gave the side menu and those PrimeFreeBird gave back, with why
// (FeatureSwitches.x).
NSString* PFBDashPanelFacts(void);

// Web session cookie harvesting (WebCreateTweet.x)
void PFBPrewarmWebCookiesIfNeeded(void);
void PFBMaybeHandleHarvestWebView(__unsafe_unretained id webViewController);

// The mobile Safari user agent presented by the web views and web requests (HookHelpers.m).
FOUNDATION_EXPORT NSString* const PFBMobileSafariUserAgent;

// Twitter's own Liquid Glass: whether its second gate value is given at this launch,
// and how many launches before it in a row ended early with it given (AppLifecycle.x).
FOUNDATION_EXPORT NSString* const PFBNativeGlassEarlyExitsKey;
FOUNDATION_EXPORT BOOL PFBNativeGlassAsked(void);
FOUNDATION_EXPORT NSInteger PFBNativeGlassEarlyExits(void);
// YES when a usable web session (auth_token + ct0) is available (WebCreateTweet.x).
BOOL PFBHasUsableWebCredentials(void);
// A GET signed with the web session; nil without one or for a URL that is not
// https on x.com (WebCreateTweet.x).
NSMutableURLRequest* PFBWebSessionGETRequest(NSURL* url);
// The current account's ID when the web session is that account's, else nil. Main thread.
NSString* PFBWebSessionAccountID(void);
// A POST to one of x.com's own operations, as the web client sends it. Off the main thread.
NSMutableURLRequest* PFBWebSessionPOSTRequest(NSString* path, NSData* body);
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
// Whether the top bar logo takes the accent: Twitter icon on and an accent active (Theme.x).
BOOL PFBTintedLogoWanted(void);

// A copy of `source` painted in `color` through its own alpha, rendered as
// AlwaysOriginal so no tint can change it afterward.
UIImage* PFBFlatGlyph(UIImage* source, UIColor* color);

// The same repaint, marked so the top bar repairs know the image is already theirs
// (NavBarIcons.x).
UIImage* PFBPaintedGlyph(UIImage* source, UIColor* color);
// Whether an image is one PFBPaintedGlyph made (NavBarIcons.x).
BOOL PFBIsPaintedBarGlyph(UIImage* image);

// For the probes: how the hide code reads one notifications row and whether an image is
// its cross (HiddenNotifications.x); how one glass tab bar accessory is seen (Branding.x).
NSString* PFBNotifRowFacts(UITableView* table, NSIndexPath* indexPath);
BOOL PFBNotifIsCrossImage(UIImage* image);
// For the Tweet menu in the notifications tab (HiddenThreads.x): whether a screen or a view
// belongs to that tab, and the hide of a Tweet's row there (HiddenNotifications.x).
BOOL PFBNotifControllerOnNotificationsScreen(UIViewController* controller);
BOOL PFBNotifViewOnNotificationsScreen(UIView* view);
BOOL PFBNotifHideTweet(id status, UIView* source, UIViewController* screen);
NSString* PFBGlassAccessoryFacts(UIView* host);
// Why the feather is missing from a compose button that should carry it, or nil; and whether
// an image is that feather (Branding.x).
NSString* PFBGlassComposeMiss(UIView* host);
BOOL PFBGlassIsFeather(UIImage* image);

// The color of the icons added to the top bars, resolved to a fixed color for the traits.
UIColor* PFBBarIconColor(UITraitCollection* traits);

// A one-page PDF of the bundle drawn centered in `size`, at `fill` of the largest size
// that fits (1 fills it), in the PDF's own colors; nil when it cannot be read.
UIImage* PFBBundlePDFImage(NSString* file, CGSize size, CGFloat fill);

// A capsule at the top of the window (nil: the key window) with the text, and an Undo
// that runs `undo` when one is given. It replaces the capsule shown before it and leaves
// after a few seconds.
void PFBShowToast(UIWindow* window, NSString* text, void (^undo)(void));

// A button whose touch area reaches 44 × 44 points around its center, Apple's minimum,
// while its glyph keeps its own size.
@interface PFBHitButton : UIButton
@end

// An icon placed beside one of Twitter's bar glyph buttons. Its glyph moves toward that
// button by the empty part of the button's slot, as far as its own slot allows (NavBarIcons.x).
@interface PFBBarGlyphButton : UIControl
@property (nonatomic, strong) UIImage* glyph;
@property (nonatomic, readonly) CGRect glyphFrame;
@end

// A bar item drawn as `glyph`, off the shared glass, sending `action` to `target` with its
// PFBBarGlyphButton as the sender (NavBarIcons.x).
UIBarButtonItem* PFBBarGlyphItem(UIImage* glyph, NSString* label, id target, SEL action);

// Pairs `ours` with the glyph button just outside it among `items`; the compatibility
// report notes, under `screen`, how far apart their glyphs land (NavBarIcons.x).
void PFBBarPairWithNeighbor(UIBarButtonItem* ours, NSArray<UIBarButtonItem*>* items, NSString* screen);

// The first view controller up a view's responder chain, or nil.
UIViewController* PFBOwningController(UIView* view);
// The same, with a navigation controller replaced by its top controller.
UIViewController* PFBOwningTopController(UIView* view);
// Whether the controller sits in Twitter's own Liquid Glass navigation, whose top bar
// draws the buttons of the controller's navigation item.
BOOL PFBOnNativeGlassStack(UIViewController* controller);

// Present the interactive "Log in to Web Session" screen. The completion fires with
// YES once cookies were harvested and stored, NO if the user canceled.
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

// Sort replies as stored; a stored YES (1) reads as Recent (ReplySorting.x).
typedef NS_ENUM(NSInteger, PFBReplySortChoice) {
    PFBReplySortOff = 0,
    PFBReplySortRecent = 1,
    PFBReplySortLiked = 2,
    PFBReplySortRelevant = 3,
};

// Retweets as stored; a stored YES (1) reads as "Not from accounts that blocked you"
// (Timeline.x).
typedef NS_ENUM(NSInteger, PFBRetweetsChoice) {
    PFBRetweetsAll = 0,
    PFBRetweetsNotFromBlockers = 1,
    PFBRetweetsNone = 2,
};

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

// Twitter's own Liquid Glass tab bar (GlassTabBar.x): its tabs styled again at once, and
// its chrome hidden while a settings screen is open.
void PFBRestyleGlassTabBars(void);
void PFBGlassTabBarHideForSettings(BOOL hidden);

// Reapplies each glass stack's configuration so an Always visible change takes effect now
// (GlassTabBar.x), and how many times the bar has been pinned, for the probe.
void PFBGlassRefreshAlwaysVisible(void);
NSUInteger PFBGlassAlwaysVisiblePinCount(void);

// Sizes the glass bar's pill for Tab labels before Twitter builds the bar, and applies a
// Hide bottom fade change to the lists on screen (GlassTabBar.x).
void PFBGlassTabBarStart(void);
void PFBGlassRefreshBottomFades(void);

// Posted on the main thread just before the stethoscope builds its report, so a probe can write
// a fresh measurement into it (PFBDebugger.m).
FOUNDATION_EXPORT NSString* const PFBDebuggerWillCaptureNotification;

// Bar items of PrimeFreeBird's own screens carry this tag and keep UIKit's glass;
// the app-wide flattening in NavBarIcons.x leaves them alone.
static const NSInteger PFBNativeGlassTag = 0x504647;

// Tint laid on glass for legibility over busy content: the reply bar while the
// keyboard is up, and the path tour's box.
static const CGFloat PFBGlassTint = 0.42;

// A Twitter glyph in the box of the system symbol it replaces, which stays as the fallback.
FOUNDATION_EXPORT UIImage* PFBTwitterGlyphFor(NSString* name, UIImage* systemImage);
