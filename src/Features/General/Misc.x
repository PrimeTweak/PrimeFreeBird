// Assorted options: always open in Safari, expanded t.co links, RTL disabled,
// clean shared links, and no screenshot detection.

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

    NSURL* url = [self rootURL] ?: [self initialURL];
    if (url == nil || ShouldKeepBrowserURLInApp(url)) {
        return %orig;
    }
    // A path tour keeps the app in front: the link's route is noted, not followed.
    if (PFBCompatTourIsRunning()) {
        PFBCOMPAT_OBSERVE(PFBCompat_always_open_safari, @"link routed to Safari, kept in the app during the check");
        return %orig;
    }

    PFBCOMPAT_ACTION(PFBCompat_always_open_safari, @"link opened in Safari");
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];

    if (completion) {
        completion();
    }
}

%end

// Fallback for the plain SFSafariViewController surfaces (help pages, Grok,
// XLinkWebView), which don't go through the T1SafariViewController funnel.
%hook SFSafariViewController

- (void)viewWillAppear:(BOOL)animated {
    if (![PFBSettings boolForKey:@"always_open_safari"]) {
        PFBCOMPAT_OBSERVE(PFBCompat_always_open_safari, @"in-app browser opened");
        return %orig;
    }

    NSURL* url = [self initialURL];
    if (url == nil || ShouldKeepBrowserURLInApp(url)) {
        return %orig;
    }
    if (PFBCompatTourIsRunning()) {
        PFBCOMPAT_OBSERVE(PFBCompat_always_open_safari, @"link routed to Safari, kept in the app during the check");
        return %orig;
    }

    PFBCOMPAT_ACTION(PFBCompat_always_open_safari, @"link opened in Safari");
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    [self dismissViewControllerAnimated:NO completion:nil];
}

%end

// MARK: - Expand t.co links

%hook TFSTwitterEntityURL

- (NSString*)url {
    // The entity is also used for URLs that never had a t.co wrapper (e.g.
    // share links), where expandedURL is nil.
    NSString* expandedURL = self.expandedURL;
    return expandedURL ?: %orig;
}

%end

// MARK: - Disable RTL

// CoreText picks direction from the first strong directional character; forcing
// LTR on the render input's paragraph style is the only reliable override.

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

// MARK: - Clean shared/copied links

// Observes UIPasteboardChangedNotification so every copy path is caught, guarded against
// re-triggering. strip_url_tracking removes s, t, ref_src and ref_url; sharing_domain
// applies independently.

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
    // Strips tracking params when the option is on.
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
    NSString* selectedHost = [[NSUserDefaults standardUserDefaults] objectForKey:@"sharing_domain"];
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
    PFBCOMPAT_OBSERVE(PFBCompat_no_screenshot_detection, @"read by Twitter");
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

// The answer to Twitter's custom screenshot gates: NO while screenshot detection is
// disabled, counted as the option acting; otherwise YES, with the read noted.
static BOOL PFBCustomScreenshotsAllowed(void) {
    if (PFBScreenshotSuppressed()) {
        PFBCOMPAT_ACTION(PFBCompat_no_screenshot_detection, @"screenshot card off");
        return NO;
    }
    PFBCOMPAT_OBSERVE(PFBCompat_no_screenshot_detection, @"read by Twitter");
    return YES;
}

%hook TFSAccountFeatureSwitches

- (BOOL)isCustomScreenshotsEnabled {
    return PFBCustomScreenshotsAllowed();
}

- (BOOL)isCustomScreenshotsOnHTLEnabled {
    return PFBCustomScreenshotsAllowed();
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
