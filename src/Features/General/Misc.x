// Links, left-to-right text, screenshot detection and Keep your place's return report.

#import <CoreText/CoreText.h>
#import "Support/HookHelpers.h"

// MARK: - Always open in Safari

// Two-factor sign-in with a security key runs in the in-app browser and cannot finish in
// Safari, so Twitter's account and sign-in pages stay in the app.
static BOOL ShouldKeepBrowserURLInApp(NSURL* url) {
    NSString* path = url.path;
    return PFBIsXDomain(url.host) && ([path hasPrefix:@"/account/"] || [path hasPrefix:@"/i/flow/"]);
}

// Every tapped link that resolves to the in-app Safari goes through this single
// present funnel, so diverting here avoids presenting anything at all.
%hook T1SafariViewController

- (void)tfnPresentedCustomPresentFromViewController:(UIViewController*)fromViewController
                                           animated:(BOOL)animated
                                         completion:(void (^)(void))completion {
    if (![PFBSettings boolForKey:@"always_open_safari"]) {
        PFBCOMPAT_OBSERVE(PFBCompat_always_open_safari, @"in-app browser opened");
        return %orig;
    }

    // initialURL is Safari's private getter: asked first, a missing one leaves the link in the app.
    NSURL* url = [self rootURL] ?: ([self respondsToSelector:@selector(initialURL)] ? [self initialURL] : nil);
    if (url == nil || ShouldKeepBrowserURLInApp(url)) {
        return %orig;
    }
    // A path tour keeps the app in front: the link's route is noted, not followed.
    if (PFBCompatTourIsRunning()) {
        PFBCOMPAT_OBSERVE(PFBCompat_always_open_safari, @"link routed to Safari, kept in the app during the check");
        return %orig;
    }

    [[UIApplication sharedApplication] openURL:url
                                       options:@{}
                             completionHandler:^(BOOL success) {
                               if (success) {
                                   PFBCOMPAT_ACTION(PFBCompat_always_open_safari, @"link opened in Safari");
                               }
                             }];

    if (completion) {
        completion();
    }
}

%end

// Fallback for links shown in a plain SFSafariViewController, which don't go through
// the T1SafariViewController funnel.
%hook SFSafariViewController

- (void)viewWillAppear:(BOOL)animated {
    if (![PFBSettings boolForKey:@"always_open_safari"]) {
        PFBCOMPAT_OBSERVE(PFBCompat_always_open_safari, @"in-app browser opened");
        return %orig;
    }

    NSURL* url = [self respondsToSelector:@selector(initialURL)] ? [self initialURL] : nil;
    if (url == nil || ShouldKeepBrowserURLInApp(url)) {
        return %orig;
    }
    if (PFBCompatTourIsRunning()) {
        PFBCOMPAT_OBSERVE(PFBCompat_always_open_safari, @"link routed to Safari, kept in the app during the check");
        return %orig;
    }

    [[UIApplication sharedApplication] openURL:url
                                       options:@{}
                             completionHandler:^(BOOL success) {
                               if (success) {
                                   PFBCOMPAT_ACTION(PFBCompat_always_open_safari, @"link opened in Safari");
                               }
                             }];
    [self dismissViewControllerAnimated:NO completion:nil];
}

%end

// MARK: - Expand t.co links

%hook TFSTwitterEntityURL

- (NSString*)url {
    // The entity is also used for URLs that never had a t.co wrapper (e.g.
    // share links), where expandedURL is nil.
    NSString* expandedURL = self.expandedURL;
    if (expandedURL) {
        PFBCOMPAT_ACTION(PFBCompat_expand_tco_links, @"link expanded");
        return expandedURL;
    }
    return %orig;
}

%end

// MARK: - t.co requests made in the background

%hook TNUTalonUtilities

// The request that counts a click on t.co; the link itself opens at its own address.
+ (BOOL)sendTalonRequestForAnalytics:(NSURL*)url {
    PFBCompatReach(PFBCompatPath_tco_requests);
    PFBCOMPAT_ACTION(PFBCompat_expand_tco_links, @"t.co click count not sent");
    return NO;
}

// The t.co safety check is not sent: its answer is the one a link outside t.co gets.
+ (id)verifyTalonURL:(NSURL*)url completion:(void (^)(NSInteger result))completion {
    if (![url.host.lowercaseString isEqualToString:@"t.co"]) {
        return %orig;
    }
    if (completion) {
        dispatch_async(dispatch_get_main_queue(), ^{
          completion(0);
        });
    }
    PFBCompatReach(PFBCompatPath_tco_requests);
    PFBCOMPAT_ACTION(PFBCompat_expand_tco_links, @"t.co check not sent");
    return nil;
}

%end

// MARK: - Click IDs and ad redirects

// Twitter can add a click ID to a link it opens, or send an ad's link through a
// redirect: the link keeps its own address instead.
%hook T1TwitterClickIDHandler

+ (NSURL*)URLByAppendingTwitterClickIDIfNecessary:(NSURL*)url
                                           status:(id)status
                                          account:(id)account
                                       scribePage:(id)scribePage
                                  scribeComponent:(id)scribeComponent {
    PFBCompatReach(PFBCompatPath_click_ids);
    PFBCOMPAT_ACTION(PFBCompat_expand_tco_links, @"click ID not added to a link");
    return url;
}

%end

%hook T1UnifiedCardBrowserDestinationHandlerHelper

- (NSURL*)urlByAppendingTwitterClickIDToUrl:(NSURL*)url scribeComponent:(id)scribeComponent {
    PFBCompatReach(PFBCompatPath_click_ids);
    PFBCOMPAT_ACTION(PFBCompat_expand_tco_links, @"click ID not added to a card link");
    return url;
}

%end

%hook T1UnifiedCardXLinkDestinationHandlerHelper

- (NSURL*)urlByAppendingTwitterClickIDToUrl:(NSURL*)url scribeComponent:(id)scribeComponent {
    PFBCompatReach(PFBCompatPath_click_ids);
    PFBCOMPAT_ACTION(PFBCompat_expand_tco_links, @"click ID not added to a card link");
    return url;
}

%end

%hook TUCJobDetailsComponentModel

+ (id)conditionallyApplyPromotedContentClickID:(id)clickID toDestination:(id)destination {
    PFBCompatReach(PFBCompatPath_click_ids);
    PFBCOMPAT_ACTION(PFBCompat_expand_tco_links, @"click ID not added to a job link");
    return destination;
}

%end

%hook TFNTwitterAdsTPMIdSyncManager

- (BOOL)shouldCreateRedirectURLForURL:(NSURL*)url {
    PFBCompatReach(PFBCompatPath_ad_redirect);
    PFBCOMPAT_ACTION(PFBCompat_expand_tco_links, @"ad redirect not made");
    return NO;
}

- (NSURL*)createRedirectURLForURLIfNeeded:(NSURL*)url {
    PFBCompatReach(PFBCompatPath_ad_redirect);
    PFBCOMPAT_ACTION(PFBCompat_expand_tco_links, @"ad redirect not made");
    return url;
}

%end

// MARK: - Disable RTL

// CoreText picks direction from the first strong directional character, so the render
// input's paragraph style is set to left to right.

// CTParagraphStyle is immutable with no mutable counterpart, so forcing the
// writing direction means rebuilding the style with its specifiers copied over.
static CTParagraphStyleRef CreateLTRParagraphStyle(CTParagraphStyleRef original) {
    static const struct {
        CTParagraphStyleSpecifier specifier;
        size_t valueSize;
    } copiedSpecifiers[] = {
        {kCTParagraphStyleSpecifierAlignment, sizeof(CTTextAlignment)},
        {kCTParagraphStyleSpecifierFirstLineHeadIndent, sizeof(CGFloat)},
        {kCTParagraphStyleSpecifierHeadIndent, sizeof(CGFloat)},
        {kCTParagraphStyleSpecifierTailIndent, sizeof(CGFloat)},
        {kCTParagraphStyleSpecifierTabStops, sizeof(CFArrayRef)},
        {kCTParagraphStyleSpecifierDefaultTabInterval, sizeof(CGFloat)},
        {kCTParagraphStyleSpecifierLineBreakMode, sizeof(CTLineBreakMode)},
        {kCTParagraphStyleSpecifierLineHeightMultiple, sizeof(CGFloat)},
        {kCTParagraphStyleSpecifierMaximumLineHeight, sizeof(CGFloat)},
        {kCTParagraphStyleSpecifierMinimumLineHeight, sizeof(CGFloat)},
        {kCTParagraphStyleSpecifierLineSpacingAdjustment, sizeof(CGFloat)},
        {kCTParagraphStyleSpecifierMaximumLineSpacing, sizeof(CGFloat)},
        {kCTParagraphStyleSpecifierMinimumLineSpacing, sizeof(CGFloat)},
        {kCTParagraphStyleSpecifierParagraphSpacing, sizeof(CGFloat)},
        {kCTParagraphStyleSpecifierParagraphSpacingBefore, sizeof(CGFloat)},
        {kCTParagraphStyleSpecifierLineBoundsOptions, sizeof(CTLineBoundsOptions)},
    };
    enum { copiedCount = sizeof(copiedSpecifiers) / sizeof(copiedSpecifiers[0]) };

    uint8_t values[copiedCount][sizeof(CFArrayRef)];
    CTParagraphStyleSetting settings[copiedCount + 1];
    size_t count = 0;

    for (size_t i = 0; i < copiedCount; i++) {
        if (CTParagraphStyleGetValueForSpecifier(original, copiedSpecifiers[i].specifier,
                                                 copiedSpecifiers[i].valueSize, values[count])) {
            settings[count] = (CTParagraphStyleSetting){copiedSpecifiers[i].specifier,
                                                        copiedSpecifiers[i].valueSize, values[count]};
            count++;
        }
    }

    CTWritingDirection direction = kCTWritingDirectionLeftToRight;
    settings[count++] = (CTParagraphStyleSetting){kCTParagraphStyleSpecifierBaseWritingDirection,
                                                  sizeof(direction), &direction};

    return CTParagraphStyleCreate(settings, count);
}

%hook TFNAttributedTextModel

- (void)setAttributedString:(NSAttributedString*)attributedString {
    if (attributedString.length > 0 && ![PFBSettings boolForKey:@"disable_rtl"]) {
        PFBCOMPAT_OBSERVE(PFBCompat_disable_rtl, @"text laid out");
    }
    if (![PFBSettings boolForKey:@"disable_rtl"] || attributedString.length == 0) {
        return %orig;
    }

    NSMutableAttributedString* text = [attributedString mutableCopy];
    [attributedString
        enumerateAttribute:NSParagraphStyleAttributeName
                   inRange:NSMakeRange(0, attributedString.length)
                   options:0
                usingBlock:^(id value, NSRange range, BOOL* stop) {
                    // Some models carry a raw CTParagraphStyleRef under the same key.
                    if (value != nil && ![value isKindOfClass:[NSParagraphStyle class]]) {
                        if (CFGetTypeID((__bridge CFTypeRef)value) == CTParagraphStyleGetTypeID()) {
                            CTParagraphStyleRef ltrStyle =
                                CreateLTRParagraphStyle((__bridge CTParagraphStyleRef)value);
                            [text addAttribute:NSParagraphStyleAttributeName
                                         value:(__bridge_transfer id)ltrStyle
                                         range:range];
                        }
                        return;
                    }

                    NSMutableParagraphStyle* style =
                        value ? [value mutableCopy] : [NSMutableParagraphStyle new];
                    style.baseWritingDirection = NSWritingDirectionLeftToRight;
                    [text addAttribute:NSParagraphStyleAttributeName value:style range:range];
                }];

    PFBCOMPAT_ACTION(PFBCompat_disable_rtl, @"text set left to right");
    %orig(text);
}

%end

// Before laying a text out, Twitter asks whether it reads right to left, to align and
// cut it. Off: right-to-left text is noted; on: left to right is answered.
static BOOL PFBKeepLeftToRight(BOOL rightToLeft) {
    PFBCompatReach(PFBCompatPath_rtl_checks);
    if (!rightToLeft) {
        return NO;
    }
    if (![PFBSettings boolForKey:@"disable_rtl"]) {
        PFBCOMPAT_OBSERVE(PFBCompat_disable_rtl, @"right-to-left text found");
        return YES;
    }
    PFBCOMPAT_ACTION(PFBCompat_disable_rtl, @"right-to-left text kept left to right");
    return NO;
}

%hook NSString

- (BOOL)tfs_plainTextShouldBeRenderedFromRight {
    BOOL rightToLeft = %orig;
    return PFBKeepLeftToRight(rightToLeft);
}

- (BOOL)tfs_statusTextShouldBeRenderedFromRight {
    BOOL rightToLeft = %orig;
    return PFBKeepLeftToRight(rightToLeft);
}

- (BOOL)tfs_labelTextShouldBeRenderedFromRight {
    BOOL rightToLeft = %orig;
    return PFBKeepLeftToRight(rightToLeft);
}

%end

%hook TFNTwitterDisplayTextModel

- (BOOL)_tfn_shouldBeRenderedFromRight {
    BOOL rightToLeft = %orig;
    return PFBKeepLeftToRight(rightToLeft);
}

%end

%hook TFNTwitterStatus

- (BOOL)shouldBeRenderedFromRight {
    BOOL rightToLeft = %orig;
    return PFBKeepLeftToRight(rightToLeft);
}

%end

// MARK: - Clean links

// Shared and copied links: UIPasteboardChangedNotification catches every copy path,
// guarded against re-triggering. strip_url_tracking removes s, t, ref_src and ref_url;
// the share builders apply sharing_domain on their own, copies only with Clean links on.

static NSString* PFBProcessSharedURL(NSString* urlString) {
    if (urlString.length == 0) {
        return urlString;
    }
    // Only Twitter's own links change; any other copied URL stays as it is.
    NSURLComponents* c = [NSURLComponents componentsWithString:urlString];
    if (!c || !PFBIsXDomain(c.host)) {
        return urlString;
    }

    // Option off: a tracked link is only noted for the Compatibility sheet.
    if (![PFBSettings boolForKey:@"strip_url_tracking"] && c.queryItems.count > 0) {
        PFBCOMPAT_OBSERVE(PFBCompat_strip_url_tracking, @"tracked link seen");
    }
    if ([PFBSettings boolForKey:@"strip_url_tracking"] && c.queryItems.count > 0) {
        static NSSet* tracking = nil;
        static dispatch_once_t trackingOnce;
        dispatch_once(&trackingOnce, ^{
            tracking = [NSSet setWithObjects:@"s", @"t", @"ref_src", @"ref_url", nil];
        });
        NSMutableArray<NSURLQueryItem*>* kept = [NSMutableArray array];
        for (NSURLQueryItem* item in c.queryItems) {
            if (![tracking containsObject:item.name]) {
                [kept addObject:item];
            }
        }
        if (kept.count < c.queryItems.count) {
            PFBCOMPAT_ACTION(PFBCompat_strip_url_tracking, @"tracking removed from a link");
        }
        c.queryItems = kept.count > 0 ? kept : nil;
    }

    // Apply the custom sharing domain independently of the strip option.
    // A restored backup can hold another type under this key.
    id storedHost = [[NSUserDefaults standardUserDefaults] objectForKey:@"sharing_domain"];
    NSString* selectedHost = [storedHost isKindOfClass:[NSString class]] ? storedHost : nil;
    if (selectedHost.length > 0) {
        c.host = selectedHost;
        PFBCOMPAT_ACTION(PFBCompat_sharing_domain, @"link host set to %@", selectedHost);
    } else {
        PFBCOMPAT_OBSERVE(PFBCompat_sharing_domain, @"shared link seen");
    }

    return c.URL.absoluteString ?: urlString;
}

// Every share surface funnels through these builders, which covers what the
// pasteboard observer cannot see: a link shared straight to another app never
// touches the clipboard. A clean link passes through unchanged.

%hook TFNTwitterStatus

- (NSString*)twitterURLForShareWithSParam:(unsigned int)sParam {
    NSString* url = %orig;
    return PFBProcessSharedURL(url);
}

+ (NSString*)twitterURLForShareWithSParam:(unsigned int)sParam
                                 username:(NSString*)username
                                 statusID:(long long)statusID {
    NSString* url = %orig;
    return PFBProcessSharedURL(url);
}

%end

// Profile links
%hook TFSTwitterUserReference

- (NSString*)twitterURLForShare {
    NSString* url = %orig;
    return PFBProcessSharedURL(url);
}

- (NSString*)twitterURLForCopy {
    NSString* url = %orig;
    return PFBProcessSharedURL(url);
}

%end

// The last link written back, so the observer's own write does not re-trigger it.
static NSString* PFBLastCleanedURL = nil;

// Called from applicationDidBecomeActive in AppLifecycle.x.
void PFBInstallPasteboardObserver(void) {
    static dispatch_once_t observerOnce;
    dispatch_once(&observerOnce, ^{
        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIPasteboardChangedNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification* note) {
            if (![PFBSettings boolForKey:@"strip_url_tracking"]) {
                return;
            }
            UIPasteboard* pb = [UIPasteboard generalPasteboard];
            NSString* current = pb.string;
            if (current.length == 0) {
                return;
            }
            if ([current isEqualToString:PFBLastCleanedURL]) {
                return;
            }
            NSString* cleaned = PFBProcessSharedURL(current);
            if (![cleaned isEqualToString:current]) {
                PFBLastCleanedURL = [cleaned copy];
                pb.string = cleaned;
            }
        }];
    });
}

// Opened links: query parameters that only tell a site where the click came from. "si"
// is a share ID on the hosts listed with it and can mean anything elsewhere.
static BOOL PFBIsTrackingParameter(NSString* name, NSString* host) {
    static NSSet<NSString*>* names;
    static NSSet<NSString*>* shareIDHosts;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = [NSSet setWithArray:@[
            @"fbclid", @"gclid", @"gclsrc", @"dclid", @"gbraid", @"wbraid", @"msclkid", @"twclid", @"ttclid",
            @"li_fat_id", @"igshid", @"igsh", @"mc_cid", @"mc_eid", @"_hsenc", @"_hsmi", @"mkt_tok", @"yclid",
            @"ref_src"
        ]];
        shareIDHosts = [NSSet setWithArray:@[
            @"youtube.com", @"m.youtube.com", @"music.youtube.com", @"youtu.be", @"open.spotify.com"
        ]];
    });
    NSString* lowercaseName = name.lowercaseString;
    if ([lowercaseName hasPrefix:@"utm_"] || [names containsObject:lowercaseName]) {
        return YES;
    }
    NSString* lowercaseHost = host.lowercaseString;
    if ([lowercaseHost hasPrefix:@"www."]) {
        lowercaseHost = [lowercaseHost substringFromIndex:4];
    }
    return [lowercaseName isEqualToString:@"si"] && [shareIDHosts containsObject:lowercaseHost];
}

// The web link without its tracking parameters, or the same object when it has none. The
// percent-encoded items keep the other parameters byte for byte.
static NSURL* PFBURLWithoutTracking(NSURL* url) {
    NSString* scheme = [url isKindOfClass:[NSURL class]] ? url.scheme.lowercaseString : nil;
    if (![scheme isEqualToString:@"https"] && ![scheme isEqualToString:@"http"]) {
        return url;
    }
    NSURLComponents* components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    NSArray<NSURLQueryItem*>* items = components.percentEncodedQueryItems;
    if (items.count == 0) {
        return url;
    }
    NSMutableArray<NSURLQueryItem*>* kept = [NSMutableArray arrayWithCapacity:items.count];
    for (NSURLQueryItem* item in items) {
        if (!PFBIsTrackingParameter(item.name.stringByRemovingPercentEncoding ?: item.name, components.host)) {
            [kept addObject:item];
        }
    }
    if (kept.count == items.count) {
        return url;
    }
    components.percentEncodedQueryItems = kept.count > 0 ? kept : nil;
    return components.URL ?: url;
}

// The link as it leaves for the browser: without its tracking parameters when the option
// is on. Off, a tracked link is only noted.
static NSURL* PFBOpenedURL(NSURL* url) {
    PFBCompatReach(PFBCompatPath_opened_links);
    NSURL* cleanURL = PFBURLWithoutTracking(url);
    if (cleanURL == url) {
        return url;
    }
    if (![PFBSettings boolForKey:@"strip_url_tracking"]) {
        PFBCOMPAT_OBSERVE(PFBCompat_strip_url_tracking, @"tracked link opened");
        return url;
    }
    PFBCOMPAT_ACTION(PFBCompat_strip_url_tracking, @"tracking removed from an opened link");
    return cleanURL;
}

// Every tapped link, in a Tweet, a card or a bio, passes one of these two builders, and the
// browser they prepare keeps the link they were given.
%hook T1ViewControllerNavigationHelper

+ (id)_t1_handlerForURL:(NSURL*)url
             expandedURL:(NSURL*)expandedURL
                 account:(id)account
           scribeContext:(id)scribeContext
    sourceViewController:(id)sourceViewController {
    return %orig(PFBOpenedURL(url), PFBOpenedURL(expandedURL), account, scribeContext, sourceViewController);
}

// Twitter looks the link up among the Tweet's own by its address; a cleaned one matches
// none, and the browser opens the cleaned link.
+ (id)_t1_handlerForURL:(NSURL*)url
                  account:(id)account
            scribeContext:(id)scribeContext
         fromSourceStatus:(id)status
    applyAdURLTransforms:(BOOL)applyAdURLTransforms
     sourceViewController:(id)sourceViewController {
    return %orig(PFBOpenedURL(url), account, scribeContext, status, applyAdURLTransforms, sourceViewController);
}

%end

// MARK: - Keep your place

// Back in the app, each Twitter screen on show reports itself as seen again. With Keep
// your place on, that report is not sent.
%hook T1ViewControllerScribeEventObserver

- (void)viewControllerApplicationDidBecomeActive:(id)viewController {
    PFBCompatReach(PFBCompatPath_return_report);
    if (![PFBSettings boolForKey:@"no_focus_lost"]) {
        PFBCOMPAT_OBSERVE(PFBCompat_no_focus_lost, @"return report sent");
        return %orig;
    }
    PFBCOMPAT_ACTION(PFBCompat_no_focus_lost, @"return report not sent");
}

%end

// MARK: - Disable screenshot detection

static BOOL PFBScreenshotSuppressed(void) {
    return [PFBSettings boolForKey:@"no_screenshot_detection"];
}

// (1) Notification-based suppression, gated on the setting.
%hook NSNotificationCenter

- (id)addObserverForName:(NSNotificationName)name
                  object:(id)obj
                   queue:(NSOperationQueue*)queue
              usingBlock:(void (^)(NSNotification* note))block {
    if (PFBScreenshotSuppressed() &&
        [name isEqualToString:UIApplicationUserDidTakeScreenshotNotification]) {
        PFBCOMPAT_ACTION(PFBCompat_no_screenshot_detection, @"screenshot listener muted");
        return %orig(name, obj, queue, ^(NSNotification* note){});
    }
    if ([name isEqualToString:UIApplicationUserDidTakeScreenshotNotification]) {
        PFBCOMPAT_OBSERVE(PFBCompat_no_screenshot_detection, @"read by Twitter");
    }
    return %orig;
}

- (void)addObserver:(id)observer
           selector:(SEL)aSelector
               name:(NSNotificationName)aName
             object:(id)anObject {
    if (PFBScreenshotSuppressed() &&
        [aName isEqualToString:UIApplicationUserDidTakeScreenshotNotification]) {
        PFBCOMPAT_ACTION(PFBCompat_no_screenshot_detection, @"screenshot listener muted");
        return;
    }
    return %orig;
}

%end

// (2) Watermark suppression, gated.
@class TFSAccountFeatureSwitches;

// Whether Twitter's custom screenshot gates are refused: YES while screenshot detection
// is disabled, counted as the option acting; otherwise Twitter's own answer stands.
static BOOL PFBCustomScreenshotsRefused(void) {
    if (PFBScreenshotSuppressed()) {
        PFBCOMPAT_ACTION(PFBCompat_no_screenshot_detection, @"screenshot card off");
        return YES;
    }
    PFBCOMPAT_OBSERVE(PFBCompat_no_screenshot_detection, @"read by Twitter");
    return NO;
}

%hook TFSAccountFeatureSwitches

- (BOOL)isCustomScreenshotsEnabled {
    return PFBCustomScreenshotsRefused() ? NO : %orig;
}

- (BOOL)isCustomScreenshotsOnHTLEnabled {
    return PFBCustomScreenshotsRefused() ? NO : %orig;
}

%end

%hook TUIFollowControlCustomScreenshot
- (void)didMoveToWindow {
    %orig;
    if ([PFBSettings boolForKey:@"no_screenshot_detection"]) {
        self.hidden = YES;
        self.alpha = 0.0;
        self.userInteractionEnabled = NO;
        PFBCOMPAT_ACTION(PFBCompat_no_screenshot_detection, @"screenshot card hidden");
    }
}
%end
