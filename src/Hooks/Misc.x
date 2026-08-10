//
//  Misc.x
//  PrimeFreeBird
//

#import <CoreText/CoreText.h>
#import "HookHelpers.h"

// MARK: - Always open in Safari

// In-app browser is used for two-factor authentication with security key,
// login will not complete successfully if it's redirected to Safari
static BOOL ShouldKeepBrowserURLInApp(NSURL* url) {
    NSString* urlStr = [url absoluteString];

    return [urlStr containsString:@"twitter.com/account/"] ||
           [urlStr containsString:@"twitter.com/i/flow/"] ||
           [urlStr containsString:@"x.com/account/"] || [urlStr containsString:@"x.com/i/flow/"];
}

// Every tapped link that resolves to the in-app Safari goes through this single
// present funnel, so diverting here avoids presenting anything at all.
%hook T1SafariViewController

- (void)tfnPresentedCustomPresentFromViewController:(UIViewController*)fromViewController
                                           animated:(BOOL)animated
                                         completion:(void (^)(void))completion {
    if (![BHTSettings boolForKey:@"always_open_safari"]) {
        return %orig;
    }

    NSURL* url = [self rootURL] ?: [self initialURL];
    if (url == nil || ShouldKeepBrowserURLInApp(url)) {
        return %orig;
    }

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
    if (![BHTSettings boolForKey:@"always_open_safari"]) {
        return %orig;
    }

    NSURL* url = [self initialURL];
    if (url == nil || ShouldKeepBrowserURLInApp(url)) {
        return %orig;
    }

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
    if (![BHTSettings boolForKey:@"disable_rtl"] || attributedString.length == 0) {
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

    %orig(text);
}

%end

// MARK: - Clean shared/copied links
//
// The tweak observes UIPasteboardChangedNotification and clean any twitter/x URL that
// lands in the pasteboard — catching every copy path (setString:, setURL:,
// setItems:, or the Swift share kit) rather than hooking one write API. A
// last-cleaned guard stops the tweak's re-write from re-triggering the observer.
// Removes ?s=, &t= and ref_* when strip_url_tracking is on; the custom
// sharing_domain is applied independently. Mirrors the reference build's
// BHTPasteboardChangeObserver.

static NSString* NFBProcessSharedURL(NSString* urlString) {
    if (urlString.length == 0) {
        return urlString;
    }
    // Only touch twitter/x links; leave every other copied URL untouched.
    if (![urlString containsString:@"twitter.com"] &&
        ![urlString containsString:@"x.com"]) {
        return urlString;
    }
    NSURLComponents* c = [NSURLComponents componentsWithString:urlString];
    if (!c) {
        return urlString;
    }

    // Strip tracking params only when the option is on.
    if ([BHTSettings boolForKey:@"strip_url_tracking"] && c.queryItems.count > 0) {
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
        c.queryItems = kept.count > 0 ? kept : nil;
    }

    // Apply the custom sharing domain independently of the strip option.
    NSString* selectedHost = [[NSUserDefaults standardUserDefaults] objectForKey:@"sharing_domain"];
    if (selectedHost.length > 0) {
        c.host = selectedHost;
    }

    return c.URL.absoluteString ?: urlString;
}

// Every share surface funnels through these builders, so cleaning here covers
// what the pasteboard observer below cannot see: sharing a link STRAIGHT to
// another app (Messages, Notes, AirDrop) never touches the clipboard, and
// profile links have their own builders. A link that is already clean simply
// passes through unchanged.

%hook TFNTwitterStatus

- (NSString*)twitterURLForShareWithSParam:(unsigned int)sParam {
    NSString* url = %orig;
    return NFBProcessSharedURL(url);
}

+ (NSString*)twitterURLForShareWithSParam:(unsigned int)sParam
                                 username:(NSString*)username
                                 statusID:(long long)statusID {
    NSString* url = %orig;
    return NFBProcessSharedURL(url);
}

%end

// Profile links
%hook TFSTwitterUserReference

- (NSString*)twitterURLForShare {
    NSString* url = %orig;
    return NFBProcessSharedURL(url);
}

- (NSString*)twitterURLForCopy {
    NSString* url = %orig;
    return NFBProcessSharedURL(url);
}

%end

// Called from AppLifecycle's applicationDidBecomeActive (declared extern there).
static NSString* NFBLastCleanedURL = nil;

void NFBInstallPasteboardObserver(void) {
    static dispatch_once_t observerOnce;
    dispatch_once(&observerOnce, ^{
        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIPasteboardChangedNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification* note) {
            if (![BHTSettings boolForKey:@"strip_url_tracking"]) {
                return;
            }
            UIPasteboard* pb = [UIPasteboard generalPasteboard];
            NSString* current = pb.string;
            if (current.length == 0) {
                return;
            }
            if ([current isEqualToString:NFBLastCleanedURL]) {
                return;
            }
            NSString* cleaned = NFBProcessSharedURL(current);
            if (![cleaned isEqualToString:current]) {
                NFBLastCleanedURL = [cleaned copy];
                pb.string = cleaned;
            }
        }];
    });
}

// MARK: - Disable screenshot detection

static BOOL NFBScreenshotSuppressed(void) {
    return [BHTSettings boolForKey:@"no_screenshot_detection"];
}

// (1) Notification-based suppression (theacrat's approach), now gated.
%hook NSNotificationCenter

- (id)addObserverForName:(NSNotificationName)name
                  object:(id)obj
                   queue:(NSOperationQueue*)queue
              usingBlock:(void (^)(NSNotification* note))block {
    if (NFBScreenshotSuppressed() &&
        [name isEqualToString:UIApplicationUserDidTakeScreenshotNotification]) {
        return %orig(name, obj, queue, ^(NSNotification* note){});
    }
    return %orig;
}

- (void)addObserver:(id)observer
           selector:(SEL)aSelector
               name:(NSNotificationName)aName
             object:(id)anObject {
    if (NFBScreenshotSuppressed() &&
        [aName isEqualToString:UIApplicationUserDidTakeScreenshotNotification]) {
        return;
    }
    return %orig;
}

%end

// (2) Watermark suppression (the tweak's approach), gated.
@interface TFSAccountFeatureSwitches : NSObject
@end

%hook TFSAccountFeatureSwitches

- (BOOL)isCustomScreenshotsEnabled {
    if (NFBScreenshotSuppressed()) {
        return NO;
    }
    return YES;
}

- (BOOL)isCustomScreenshotsOnHTLEnabled {
    if (NFBScreenshotSuppressed()) {
        return NO;
    }
    return YES;
}

%end


%hook TUIFollowControlCustomScreenshot
- (void)didMoveToWindow {
    %orig;
    if ([BHTSettings boolForKey:@"no_screenshot_detection"]) {
        self.hidden = YES;
        self.alpha = 0.0;
        self.userInteractionEnabled = NO;
    }
}
%end
