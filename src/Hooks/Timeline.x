//
//  Timeline.x
//  PrimeFreeBird
//

#import <QuartzCore/QuartzCore.h>

#import "HookHelpers.h"

// MARK: - Hide custom timelines

static __weak NSObject* PinnedTimelinesRepository;
static NSArray* LastPinnedTimelineModels;
static BOOL PinnedTimelinesWriteBypass = NO;

// Applies a toggle without relaunching. Hiding rewrites the UNCHANGED pinned
// list purely to republish — updatePinnedTimelines: persists server-side, so
// anything else would unpin for real; the delegate hook below swaps in the
// empty list on the way through.
void applyHideCustomTimelinesSetting(void) {
    NSObject* repository = PinnedTimelinesRepository;
    if (!repository) {
        return;
    }

    if ([BHTSettings boolForKey:@"hide_custom_timelines"]) {
        NSArray* models = LastPinnedTimelineModels;
        if (models.count > 0) {
            PinnedTimelinesWriteBypass = YES;
            ((void (*)(id, SEL, id))objc_msgSend)(repository, @selector(updatePinnedTimelines:), models);
            PinnedTimelinesWriteBypass = NO;
        }
    } else if ([repository respondsToSelector:@selector(fetchPinnedTimelinesWithThrottleEnabled:)]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(
            repository, @selector(fetchPinnedTimelinesWithThrottleEnabled:), NO);
    }
}

// The trailing accessory is only reconfigured while the strip is showing, so a
// button built before hiding mid-session survives; sync its visibility here. The
// property is a Swift lazy var whose storage ivar KVC can't see, hence the fallback.
static void SyncHomeAddTabButton(id container, BOOL hidden) {
    UIView* button = nil;

    @try {
        button = [container valueForKey:@"addTabButton"];
    } @catch (__unused NSException* exception) {
        unsigned int ivarCount = 0;
        Ivar* ivars = class_copyIvarList([container class], &ivarCount);
        for (unsigned int i = 0; i < ivarCount; i++) {
            const char* name = ivar_getName(ivars[i]);
            if (name && strstr(name, "addTabButton")) {
                button = object_getIvar(container, ivars[i]);
                break;
            }
        }
        free(ivars);
    }

    if ([button isKindOfClass:[UIView class]]) {
        button.hidden = hidden;
    }
}

// The repository publishes the pinned list through this single delegate call, so
// handing it an empty array hides the tabs without touching persisted state.
%hook _TtC32TwitterHomeFeatureImplementation35HomeTimelineContainerViewController

- (void)pinnedTimelinesRepository:(id)repository
    didChangeWithPinnedTimelineModels:(NSArray*)models {
    PinnedTimelinesRepository = repository;
    if (models.count > 0) {
        LastPinnedTimelineModels = [models copy];
    }
    BOOL hide = [BHTSettings boolForKey:@"hide_custom_timelines"];

    %orig(repository, hide ? @[] : models);
    SyncHomeAddTabButton(self, hide);
}

- (id)tfn_navigationBarAccessoryView {
    id accessoryView = %orig;
    SyncHomeAddTabButton(self, [BHTSettings boolForKey:@"hide_custom_timelines"]);
    return accessoryView;
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    SyncHomeAddTabButton(self, [BHTSettings boolForKey:@"hide_custom_timelines"]);
}

%end

// While hiding, the overridden pinned-tabs feature switches make the app compute
// an empty pinned list; freeze writes so it can't overwrite the real tabs.
%hook _TtC32TwitterHomeFeatureImplementation31CachedPinnedTimelinesRepository

- (void)updatePinnedTimelines:(id)timelines {
    if (!PinnedTimelinesWriteBypass && [BHTSettings boolForKey:@"hide_custom_timelines"]) {
        return;
    }

    %orig;
}

%end

// MARK: - Force tweet images to full frame

%hook T1StandardStatusAttachmentViewAdapter

// attachmentType 2 = photos, displayType 1 = full frame
- (NSUInteger)displayType {
    if (self.attachmentType == 2) {
        return [BHTSettings boolForKey:@"force_tweet_full_frame"] ? 1 : %orig;
    }

    return %orig;
}

%end

// MARK: - Hide the Spaces bar

// The bar is still the repurposed Fleets line; both home timeline implementations
// share this visibility gate, re-evaluated on every content or settings update.
%hook T1FleetLineHeaderController

- (BOOL)_t1_shouldShowFleetLine {
    if ([BHTSettings boolForKey:@"hide_spaces"]) {
        return NO;
    }

    return %orig;
}

%end

// The header hook removes the content, but the T1FleetLineView itself keeps
// its height and blurred background. Collapse the view to zero as well.
static const void* kNFBFleetHiddenKey = &kNFBFleetHiddenKey;

// Plain C rather than a %new method: a %new selector isn't known to the
// compiler when called through an id handle.
static void nfbApplyFleetVisibility(UIView* view) {
    // Restore what the tweak hid: without this the bar stays gone after the option is
    // switched back off, until the app is relaunched. The tweak only ever restores a
    // view the tweak hid, so Twitter's own hiding is never overridden.
    BOOL hide = [BHTSettings boolForKey:@"hide_spaces"];
    BOOL hiddenByUs = objc_getAssociatedObject(view, kNFBFleetHiddenKey) != nil;
    if (hide) {
        if (!view.hidden) {
            view.hidden = YES;
        }
        if (!hiddenByUs) {
            objc_setAssociatedObject(view, kNFBFleetHiddenKey, @YES,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    } else if (hiddenByUs) {
        view.hidden = NO;
        objc_setAssociatedObject(view, kNFBFleetHiddenKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

%hook T1FleetLineView

- (void)didMoveToWindow {
    %orig;
    nfbApplyFleetVisibility((UIView*)self);
}

// Also on every layout pass: coming back from the settings screen doesn't
// always move the view to a new window, and the bar would stay gone until the
// app was relaunched.
- (void)layoutSubviews {
    %orig;
    nfbApplyFleetVisibility((UIView*)self);
}

- (CGSize)intrinsicContentSize {
    if ([BHTSettings boolForKey:@"hide_spaces"]) {
        return CGSizeZero;
    }
    return %orig;
}

- (CGSize)sizeThatFits:(CGSize)size {
    if ([BHTSettings boolForKey:@"hide_spaces"]) {
        return CGSizeZero;
    }
    return %orig;
}

%end

// MARK: - Scroll edge effect
//
// Stock Twitter opts out of the iOS 26 design; this tweak opts back in
// (AppLifecycle.x), and iOS 26 then draws a scroll edge effect under every
// bar. This option switches that effect off wherever it appears, keeping
// Liquid Glass everywhere else.

static void NFBReadingLayoutTick(UIScrollView* scrollView);

static const void* kNFBEdgeMarkKey = &kNFBEdgeMarkKey;

// The option is cached: reading NSUserDefaults on every layout pass of every
// scroll view in the app would be far too costly, and a refresh twice a second
// is plenty for a settings toggle.
static BOOL gNFBEdgeHide = NO;
static CFAbsoluteTime gNFBEdgeChecked = 0;

static BOOL nfbEdgeHideEnabled(void) {
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (now - gNFBEdgeChecked > 0.5) {
        gNFBEdgeChecked = now;
        gNFBEdgeHide = [BHTSettings boolForKey:@"hide_scroll_edge_blur"];
    }
    return gNFBEdgeHide;
}

// Applies (or lifts) the effect on one scroll view, and only ever lifts what
// the tweak hid ourselves.
static void nfbApplyEdgeEffect(UIScrollView* scrollView, BOOL hide) {
    if (![scrollView respondsToSelector:@selector(topEdgeEffect)]) {
        return;   // avant iOS 26 : rien à faire
    }
    id effect = ((id (*)(id, SEL))objc_msgSend)(scrollView, @selector(topEdgeEffect));
    if (![effect respondsToSelector:@selector(setHidden:)] ||
        ![effect respondsToSelector:@selector(isHidden)]) {
        return;
    }
    BOOL alreadyHidden = ((BOOL (*)(id, SEL))objc_msgSend)(effect, @selector(isHidden));
    if (alreadyHidden == hide) {
        return;   // rien à faire : le cas le plus fréquent, et le moins cher
    }
    ((void (*)(id, SEL, BOOL))objc_msgSend)(effect, @selector(setHidden:), hide);
    objc_setAssociatedObject(scrollView, kNFBEdgeMarkKey, hide ? @YES : nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%hook UIScrollView

// Modal screens are left alone. Hiding the effect on Twitter's own settings
// sheet broke its content inset — the list slid up under the title. The tabs
// the tweak cares about are never presented modally, so this costs nothing.
static UIViewController* nfbOwningController(UIView* view) {
    UIResponder* responder = view;
    while ((responder = responder.nextResponder)) {
        if ([responder isKindOfClass:[UIViewController class]]) {
            return (UIViewController*)responder;
        }
    }
    return nil;
}

static BOOL nfbScrollViewIsModal(UIScrollView* scrollView) {
    UIViewController* owner = nfbOwningController(scrollView);
    return owner != nil && owner.presentingViewController != nil;
}

// One of those spared screens still needs something: the root of Twitter's own
// settings, the page carrying the "Search settings" field. Leaving its effect
// alone keeps the bar, but under Liquid Glass iOS draws that bar as a gradual
// fade — the list shows through above the field and nothing marks where the bar
// ends. The hard style puts an opaque background and a boundary back under it.
//
// Sub-pages share the controller class, so the root is the first settings
// controller in the navigation stack — the same test Settings.x already uses.
static BOOL nfbIsTwitterSettingsClass(UIViewController* controller) {
    Class generic = objc_getClass("T1GenericSettingsViewController");
    Class settings = objc_getClass("T1SettingsViewController");
    return (generic && [controller isKindOfClass:generic]) ||
           (settings && [controller isKindOfClass:settings]);
}

static BOOL nfbControllerIsSettingsRoot(UIViewController* controller) {
    if (!controller || !nfbIsTwitterSettingsClass(controller)) {
        return NO;
    }
    for (UIViewController* each in controller.navigationController.viewControllers) {
        if (each == controller) {
            return YES;
        }
        if (nfbIsTwitterSettingsClass(each)) {
            return NO;
        }
    }
    return NO;
}

// An opaque-ish band in the settings sheet's navigation bar, spanning the
// header zone from the sheet's top to the bar's bottom — under the title and
// the search field, over the list. iOS 26 draws that zone as a scroll edge
// effect that stops partway down the search field, and the effect's views
// ignore UIView-level geometry setters, so the strip is covered rather than
// resized.
//
// A plain UIView, not a UIVisualEffectView: the confirm-button treatment in
// Theme.x repaints every UIVisualEffectView under the platter's resolved
// subtree, which can span the whole bar. Installed from the BAR's layout, not
// the table's: the table can settle before the bar background exists and then
// not lay out again until a scroll or a push. The frame is copied from
// _UIBarBackground each pass, so it holds on any device and through rotation;
// systemBackground at 0.9 reads as near-opaque white and follows dark mode.
static const CGFloat kNFBSettingsBandWhiteness = 0.9;

static const void* kNFBSettingsBarBandKey = &kNFBSettingsBarBandKey;

static UINavigationController* nfbSettingsNavigationForBar(UINavigationBar* bar) {
    UIResponder* responder = bar;
    while ((responder = responder.nextResponder)) {
        if ([responder isKindOfClass:[UINavigationController class]]) {
            UINavigationController* navigation = (UINavigationController*)responder;
            if (navigation.presentingViewController != nil &&
                nfbControllerIsSettingsRoot(navigation.viewControllers.firstObject)) {
                return navigation;
            }
            return nil;
        }
    }
    return nil;
}

static void nfbLayBandIntoSettingsBar(UINavigationBar* bar,
                                      UINavigationController* navigation) {
    UIView* background = nil;
    for (UIView* subview in bar.subviews) {
        if ([NSStringFromClass([subview class]) isEqualToString:@"_UIBarBackground"]) {
            background = subview;
            break;
        }
    }
    if (!background) {
        return;   // not built yet; the bar will lay out again
    }
    UIView* band = objc_getAssociatedObject(bar, kNFBSettingsBarBandKey);
    if (!band) {
        band = [[UIView alloc] init];
        band.userInteractionEnabled = NO;
        band.backgroundColor = [[UIColor systemBackgroundColor]
            colorWithAlphaComponent:kNFBSettingsBandWhiteness];
        objc_setAssociatedObject(bar, kNFBSettingsBarBandKey, band,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (band.superview != bar || [bar.subviews indexOfObject:band] != 0) {
        [bar insertSubview:band atIndex:0];
    }
    if (!CGRectEqualToRect(band.frame, background.frame)) {
        band.frame = background.frame;
    }
    // Only the root page carries the search field; pushed pages keep their
    // bar untouched.
    BOOL onRoot =
        navigation.topViewController == navigation.viewControllers.firstObject;
    if (band.hidden == onRoot) {
        band.hidden = !onRoot;
    }
}

- (void)didMoveToWindow {
    %orig;

    @try {
        if (self.window && !nfbScrollViewIsModal(self)) {
            nfbApplyEdgeEffect(self, nfbEdgeHideEnabled());
        }
    } @catch (id exception) {
    }
}

// Checked on every layout of every scroll view, on purpose. iOS re-enables the
// effect whenever a bar reconfigures — changing tab, coming back to a screen —
// and acting only on views the tweak had already marked left Search untouched and the
// timeline correct only after a few swipes. The work is two message sends when
// the state already matches, which is nearly always.
- (void)layoutSubviews {
    %orig;

    @try {
        if (!self.window) {
            return;
        }
        BOOL marked = objc_getAssociatedObject(self, kNFBEdgeMarkKey) != nil;
        BOOL hide = nfbEdgeHideEnabled();
        NFBReadingLayoutTick(self);
        if (!marked && (!hide || nfbScrollViewIsModal(self))) {
            return;
        }
        nfbApplyEdgeEffect(self, hide);
    } @catch (id exception) {
    }
}

%end

%hook TFNTableView

// Twitter's own table does not route its layout through UIScrollView, so the
// wash would only be repositioned on a data change and would drift as
// self-sizing rows settle.
- (void)layoutSubviews {
    %orig;
    @try {
        NFBReadingLayoutTick(self);
    } @catch (id exception) {
    }
}

%end

%hook UINavigationBar

- (void)didMoveToWindow {
    %orig;

    @try {
        if (self.window) {
            UINavigationController* navigation = nfbSettingsNavigationForBar(self);
            if (navigation) {
                nfbLayBandIntoSettingsBar(self, navigation);
            }
        }
    } @catch (id exception) {
    }
}

- (void)layoutSubviews {
    %orig;

    @try {
        if (self.window) {
            UINavigationController* navigation = nfbSettingsNavigationForBar(self);
            if (navigation) {
                nfbLayBandIntoSettingsBar(self, navigation);
            }
        }
    } @catch (id exception) {
    }
}

%end





// MARK: - Hide "Discover more", who-to-follow and prompts

// Resolves the class by name so mangled Swift names work; NSStringFromClass
// would only ever produce the demangled dotted form.
static BOOL IsInHierarchyOfClass(UIViewController* viewController, NSString* className) {
    Class targetClass = NSClassFromString(className);
    if (!targetClass) {
        return NO;
    }

    UIViewController* currentVC = viewController;

    while (currentVC) {
        if ([currentVC isKindOfClass:targetClass]) {
            return YES;
        }

        if (currentVC.parentViewController) {
            currentVC = currentVC.parentViewController;
        } else if (currentVC.navigationController) {
            currentVC = currentVC.navigationController;
        } else if (currentVC.presentingViewController) {
            currentVC = currentVC.presentingViewController;
        } else {
            break;
        }
    }

    return NO;
}

static NSString* ItemEntryID(id viewModel) {
    if (![viewModel respondsToSelector:@selector(entryID)]) {
        return nil;
    }

    NSString* entryID = [viewModel performSelector:@selector(entryID)];
    return [entryID isKindOfClass:[NSString class]] ? entryID : nil;
}

static NSString* ItemScribeComponent(id viewModel) {
    if (![viewModel respondsToSelector:@selector(scribeComponent)]) {
        return nil;
    }

    NSString* component = [viewModel performSelector:@selector(scribeComponent)];
    return [component isKindOfClass:[NSString class]] ? component : nil;
}

static BOOL ItemRespondsAndInvokesBOOL(id viewModel, SEL selector) {
    if (![viewModel respondsToSelector:selector]) {
        return NO;
    }
    return ((BOOL (*)(id, SEL))objc_msgSend)(viewModel, selector);
}

// Set when a reply is only on the feed because a followed account replied to
// someone else's tweet.
static BOOL ItemIsReplyWithSocialContext(id viewModel) {
    return ItemRespondsAndInvokesBOOL(viewModel, @selector(isReplyAndShouldShowSocialContext));
}

static BOOL ItemIsConversationThreadReply(id viewModel) {
    return [ItemEntryID(viewModel) containsString:@"conversationthread"];
}

// The tweet's author and who it's directly replying to, for recognizing an
// exchange between the thread's own author and a verified user. Real user IDs
// are never 0, so that doubles as "unknown/unsupported".
static long long ItemRepresentedFromUserID(id viewModel) {
    SEL selector = @selector(representedFromUserID);
    if (![viewModel respondsToSelector:selector]) {
        return 0;
    }
    return ((long long (*)(id, SEL))objc_msgSend)(viewModel, selector);
}

static long long ItemInReplyToUserID(id viewModel) {
    SEL selector = @selector(inReplyToUserID);
    if (![viewModel respondsToSelector:selector]) {
        return 0;
    }
    return ((long long (*)(id, SEL))objc_msgSend)(viewModel, selector);
}

// Twitter's *ByCurrentAccountState fields are a tri-state
// (0 unknown, 1 yes, 2 no).
static const NSInteger kFollowedByCurrentAccountStateFollowing = 1;

static BOOL BHShouldHideVerifiedItem(id viewModel, BOOL inConversation,
                                     long long conversationRootUserID,
                                     NSSet<NSNumber*>* authorRepliedToUserIDs) {
    SEL verifiedSelector = @selector(isFromUserVerified);
    if (![viewModel respondsToSelector:verifiedSelector]) {
        return NO;
    }

    BOOL verified = ((BOOL (*)(id, SEL))objc_msgSend)(viewModel, verifiedSelector);
    if (!verified) {
        return NO;
    }

    if (inConversation) {
        if (!ItemIsConversationThreadReply(viewModel)) {
            return NO;
        }

        if (conversationRootUserID != 0) {
            long long repliedUserID = ItemRepresentedFromUserID(viewModel);

            BOOL isAuthorsOwnReply = repliedUserID == conversationRootUserID;
            BOOL authorRepliedToThisUser =
                [authorRepliedToUserIDs containsObject:@(repliedUserID)];
            if (isAuthorsOwnReply || authorRepliedToThisUser) {
                return NO;
            }
        }
    }

    if (!inConversation && ItemIsReplyWithSocialContext(viewModel)) {
        return NO;
    }

    SEL followStateSelector = @selector(representedFromUserFollowedByCurrentAccountState);
    if ([viewModel respondsToSelector:followStateSelector]) {
        NSInteger followState =
            ((NSInteger (*)(id, SEL))objc_msgSend)(viewModel, followStateSelector);
        if (followState == kFollowedByCurrentAccountStateFollowing) {
            return NO;
        }
    }

    return YES;
}

// MARK: - Muted words
//
// The rule list is cached here rather than read per item: the editor calls
// nfbRefreshMutedWords() whenever it changes something, and the signature
// below invalidates the memo cache so the timeline re-evaluates at once.
// Text and handle are read defensively through several known selectors —
// verified present in T1Twitter — so a renamed accessor degrades to "no
// match" instead of breaking the timeline.

static NSArray<NSString*>* gNFBMutedWords = nil;      // lowercased, no "@"
static NSArray<NSString*>* gNFBMutedHandles = nil;    // lowercased, no "@"
static BOOL gNFBMutedWholeWords = YES;
static BOOL gNFBMutedInConversations = YES;
static BOOL gNFBMutedSkipFollowing = YES;
static BOOL gNFBMutedIncludeReposts = NO;
static NSInteger gNFBMutedHiddenToday = 0;
static NSInteger gNFBMutedFlushCounter = 0;
static NSString* gNFBMutedCountDay = nil;
static NSUInteger gNFBMutedSignature = 0;
static BOOL gNFBMutedLoaded = NO;

void nfbRefreshMutedWords(void) {
    NSUserDefaults* d = [NSUserDefaults standardUserDefaults];
    NSArray* raw = [d arrayForKey:@"nfb_muted_words"] ?: @[];
    // term -> expiry timestamp; a missing entry means "forever".
    NSDictionary* expiry = [d dictionaryForKey:@"nfb_muted_expiry"] ?: @{};
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSMutableArray* words = [NSMutableArray array];
    NSMutableArray* handles = [NSMutableArray array];
    NSUInteger signature = 1;
    for (id entry in raw) {
        if (![entry isKindOfClass:[NSString class]]) { continue; }
        NSString* original = (NSString*)entry;
        id deadline = expiry[original];
        if ([deadline respondsToSelector:@selector(doubleValue)] &&
            [deadline doubleValue] > 0 && [deadline doubleValue] <= now) {
            continue;   // expired: ignored until the editor prunes it
        }
        NSString* term = [[original
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]
            lowercaseString];
        if (term.length == 0) { continue; }
        signature = signature * 31 + term.hash;
        if ([term hasPrefix:@"@"]) {
            NSString* handle = [term substringFromIndex:1];
            if (handle.length) { [handles addObject:handle]; }
        } else {
            [words addObject:term];
        }
    }
    gNFBMutedWords = words;
    gNFBMutedHandles = handles;
    gNFBMutedWholeWords =
        ([d objectForKey:@"nfb_muted_whole_words"] == nil) ? YES
                                                           : [d boolForKey:@"nfb_muted_whole_words"];
    gNFBMutedInConversations =
        ([d objectForKey:@"nfb_muted_in_conversations"] == nil)
            ? YES
            : [d boolForKey:@"nfb_muted_in_conversations"];
    gNFBMutedSkipFollowing =
        ([d objectForKey:@"nfb_muted_skip_following"] == nil)
            ? YES
            : [d boolForKey:@"nfb_muted_skip_following"];
    gNFBMutedIncludeReposts = [d boolForKey:@"nfb_muted_include_reposts"];

    // Daily counter: kept in memory and flushed sparingly, so the hot path
    // never touches NSUserDefaults.
    NSString* today = [NSString stringWithFormat:@"%ld",
                                                 (long)(now / 86400.0)];
    NSString* storedDay = [d stringForKey:@"nfb_muted_count_day"];
    if ([storedDay isEqualToString:today]) {
        gNFBMutedHiddenToday = [d integerForKey:@"nfb_muted_hidden_count"];
    } else {
        gNFBMutedHiddenToday = 0;
        [d setObject:today forKey:@"nfb_muted_count_day"];
        [d setInteger:0 forKey:@"nfb_muted_hidden_count"];
    }
    gNFBMutedCountDay = today;

    gNFBMutedSignature = signature * 31 + (gNFBMutedWholeWords ? 2 : 1) +
                         (gNFBMutedSkipFollowing ? 4 : 0) +
                         (gNFBMutedIncludeReposts ? 8 : 0);
    gNFBMutedLoaded = YES;
}

static void NFBEnsureMutedLoaded(void) {
    if (!gNFBMutedLoaded) { nfbRefreshMutedWords(); }
}

// First non-empty string among a list of selectors, on the object itself and
// then on its status/tweet child.
static NSString* NFBStringFromSelectors(id object, BOOL descend) {
    if (!object) { return nil; }
    SEL textSels[] = { @selector(fullText), @selector(tweetText), @selector(text),
                       @selector(displayText), @selector(bodyText) };
    for (size_t i = 0; i < sizeof(textSels) / sizeof(textSels[0]); i++) {
        if (![object respondsToSelector:textSels[i]]) { continue; }
        id value = ((id (*)(id, SEL))objc_msgSend)(object, textSels[i]);
        if ([value isKindOfClass:[NSString class]] && ((NSString*)value).length) {
            return (NSString*)value;
        }
        if ([value isKindOfClass:[NSAttributedString class]] &&
            ((NSAttributedString*)value).string.length) {
            return ((NSAttributedString*)value).string;
        }
    }
    if (!descend) { return nil; }
    SEL childSels[] = { @selector(status), @selector(tweet) };
    for (size_t i = 0; i < sizeof(childSels) / sizeof(childSels[0]); i++) {
        if (![object respondsToSelector:childSels[i]]) { continue; }
        id child = ((id (*)(id, SEL))objc_msgSend)(object, childSels[i]);
        NSString* text = NFBStringFromSelectors(child, NO);
        if (text.length) { return text; }
    }
    return nil;
}

static NSString* NFBHandleFromSelectors(id object, BOOL descend) {
    if (!object) { return nil; }
    SEL sels[] = { @selector(screenName), @selector(authorScreenName),
                   @selector(username), @selector(handle) };
    for (size_t i = 0; i < sizeof(sels) / sizeof(sels[0]); i++) {
        if (![object respondsToSelector:sels[i]]) { continue; }
        id value = ((id (*)(id, SEL))objc_msgSend)(object, sels[i]);
        if ([value isKindOfClass:[NSString class]] && ((NSString*)value).length) {
            return (NSString*)value;
        }
    }
    if (!descend) { return nil; }
    SEL childSels[] = { @selector(status), @selector(tweet), @selector(author),
                        @selector(user) };
    for (size_t i = 0; i < sizeof(childSels) / sizeof(childSels[0]); i++) {
        if (![object respondsToSelector:childSels[i]]) { continue; }
        id child = ((id (*)(id, SEL))objc_msgSend)(object, childSels[i]);
        NSString* handle = NFBHandleFromSelectors(child, NO);
        if (handle.length) { return handle; }
    }
    return nil;
}

// Whole-word matching without a regex: find the needle, then require that
// neither neighbouring character is alphanumeric.
static BOOL NFBHaystackContainsTerm(NSString* haystack, NSString* term, BOOL wholeWords) {
    NSRange search = NSMakeRange(0, haystack.length);
    while (search.length > 0) {
        NSRange found = [haystack rangeOfString:term options:0 range:search];
        if (found.location == NSNotFound) { return NO; }
        if (!wholeWords) { return YES; }
        NSCharacterSet* alnum = [NSCharacterSet alphanumericCharacterSet];
        BOOL leftOK = YES;
        BOOL rightOK = YES;
        if (found.location > 0) {
            leftOK = ![alnum characterIsMember:
                                 [haystack characterAtIndex:found.location - 1]];
        }
        NSUInteger after = found.location + found.length;
        if (after < haystack.length) {
            rightOK = ![alnum characterIsMember:[haystack characterAtIndex:after]];
        }
        if (leftOK && rightOK) { return YES; }
        NSUInteger next = found.location + 1;
        if (next >= haystack.length) { return NO; }
        search = NSMakeRange(next, haystack.length - next);
    }
    return NO;
}

// Read by the muted-words editor to show "N posts filtered today".
NSInteger nfbMutedHiddenCountToday(void) {
    NFBEnsureMutedLoaded();
    return gNFBMutedHiddenToday;
}

static void NFBNoteMutedHidden(void) {
    gNFBMutedHiddenToday++;
    // Persist every so often rather than on every hidden post.
    if (++gNFBMutedFlushCounter >= 25) {
        gNFBMutedFlushCounter = 0;
        NSUserDefaults* d = [NSUserDefaults standardUserDefaults];
        [d setInteger:gNFBMutedHiddenToday forKey:@"nfb_muted_hidden_count"];
        if (gNFBMutedCountDay) {
            [d setObject:gNFBMutedCountDay forKey:@"nfb_muted_count_day"];
        }
    }
}

// "Do you follow this author?" — several accessors exist depending on the
// model, so try them in turn and treat an unknown answer as "not following"
// (the safe side: the filter still applies).
static BOOL NFBAuthorIsFollowed(id viewModel) {
    SEL sels[] = { @selector(isFollowing), @selector(following) };
    id candidates[] = { viewModel, nil, nil };
    if ([viewModel respondsToSelector:@selector(author)]) {
        candidates[1] = ((id (*)(id, SEL))objc_msgSend)(viewModel, @selector(author));
    }
    if ([viewModel respondsToSelector:@selector(user)]) {
        candidates[2] = ((id (*)(id, SEL))objc_msgSend)(viewModel, @selector(user));
    }
    for (size_t c = 0; c < 3; c++) {
        id object = candidates[c];
        if (!object) { continue; }
        for (size_t i = 0; i < sizeof(sels) / sizeof(sels[0]); i++) {
            if (![object respondsToSelector:sels[i]]) { continue; }
            if (((BOOL (*)(id, SEL))objc_msgSend)(object, sels[i])) { return YES; }
        }
    }
    return NO;
}

static BOOL NFBObjectMatchesMutedRule(id object) {
    if (!object) { return NO; }
    if (gNFBMutedHandles.count) {
        NSString* handle = NFBHandleFromSelectors(object, YES);
        if (handle.length) {
            NSString* lower = [handle lowercaseString];
            if ([lower hasPrefix:@"@"]) { lower = [lower substringFromIndex:1]; }
            for (NSString* muted in gNFBMutedHandles) {
                if ([lower isEqualToString:muted]) { return YES; }
            }
        }
    }
    if (gNFBMutedWords.count) {
        NSString* text = NFBStringFromSelectors(object, YES);
        if (text.length) {
            NSString* lower = [text lowercaseString];
            for (NSString* term in gNFBMutedWords) {
                if (NFBHaystackContainsTerm(lower, term, gNFBMutedWholeWords)) {
                    return YES;
                }
            }
        }
    }
    return NO;
}

static BOOL NFBItemIsMuted(id viewModel) {
    if (gNFBMutedSkipFollowing && NFBAuthorIsFollowed(viewModel)) {
        return NO;
    }
    if (NFBObjectMatchesMutedRule(viewModel)) {
        return YES;
    }
    if (gNFBMutedIncludeReposts &&
        [viewModel respondsToSelector:@selector(retweetedStatus)]) {
        id reposted =
            ((id (*)(id, SEL))objc_msgSend)(viewModel, @selector(retweetedStatus));
        if (NFBObjectMatchesMutedRule(reposted)) {
            return YES;
        }
    }
    return NO;
}

static BOOL ShouldHideTimelineItem(id item, BOOL hideWhoToFollow, BOOL hidePrompts,
                                   BOOL hideTopics, BOOL hideTopicsToFollow,
                                   BOOL hideVerified, BOOL inConversation, BOOL inProfile,
                                   long long conversationRootUserID,
                                   NSSet<NSNumber*>* authorRepliedToUserIDs) {
    id viewModel = unwrapDataViewItem(item);
    NSString* className = NSStringFromClass([viewModel classForCoder]);

    if ((gNFBMutedWords.count || gNFBMutedHandles.count) &&
        (!inConversation || gNFBMutedInConversations) && NFBItemIsMuted(viewModel)) {
        NFBNoteMutedHidden();
        return YES;
    }

    if (hideVerified && BHShouldHideVerifiedItem(viewModel, inConversation, conversationRootUserID,
                                                 authorRepliedToUserIDs)) {
        return YES;
    }

    if (hidePrompts && [className isEqualToString:@"TwitterURT.URTTimelinePromptViewModel"]) {
        return YES;
    }

if (hideTopics && [className isEqualToString:@"TFNTwitterURTTimelineStatusTopicBanner"]) {
        return YES;
    }

    if (hideTopicsToFollow &&
        [className isEqualToString:@"T1TwitterSwift.URTTimelineTopicCollectionViewModel"]) {
        return YES;
    }

    if (hideWhoToFollow && [ItemScribeComponent(viewModel)
                               isEqualToString:@"suggest_who_to_follow"]) {
        return YES;
    }

    if (hideWhoToFollow && inProfile &&
        [className isEqualToString:@"T1TwitterSwift.URTTimelineCarouselViewModel"]) {
        return YES;
    }

    NSString* entryID = ItemEntryID(viewModel);

    if (!entryID) {
        return NO;
    }

    if (inConversation && [entryID hasPrefix:@"tweetdetailrelatedtweets"]) {
        return YES;
    }

    if (hideWhoToFollow && [entryID containsString:@"who-to-follow"]) {
        return YES;
    }

    return NO;
}

// More efficient than calling ShouldHideTimelineItem() repeatedly, which slows
// the app down a lot when hide-verified scans every reply.
static BOOL MemoizedShouldHideTimelineItem(id item, BOOL hideWhoToFollow, BOOL hidePrompts,
                                           BOOL hideTopics, BOOL hideTopicsToFollow,
                                           BOOL hideVerified, BOOL inConversation,
                                           BOOL inProfile, long long conversationRootUserID,
                                           NSSet<NSNumber*>* authorRepliedToUserIDs) {
    static NSCache<NSString*, NSNumber*>* cache;
    static NSUInteger cachedFlags = NSUIntegerMax;
    static NSUInteger cachedMutedSignature = NSUIntegerMax;
    static long long cachedRootUserID = 0;
    static NSSet<NSNumber*>* cachedAuthorRepliedToUserIDs;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [NSCache new];
        cache.countLimit = 4000;
    });

    NSUInteger flags = (hideWhoToFollow << 0) | (hidePrompts << 1) | (hideTopics << 2) |
                       (hideTopicsToFollow << 3) | (hideVerified << 4) |
                       (inConversation << 5) | (inProfile << 6);
    BOOL repliedSetChanged = authorRepliedToUserIDs != cachedAuthorRepliedToUserIDs &&
                             ![authorRepliedToUserIDs isEqualToSet:cachedAuthorRepliedToUserIDs];
    NFBEnsureMutedLoaded();
    if (flags != cachedFlags || conversationRootUserID != cachedRootUserID ||
        repliedSetChanged || gNFBMutedSignature != cachedMutedSignature) {
        [cache removeAllObjects];
        cachedMutedSignature = gNFBMutedSignature;
        cachedFlags = flags;
        cachedRootUserID = conversationRootUserID;
        cachedAuthorRepliedToUserIDs = authorRepliedToUserIDs;
    }

    NSString* entryID = ItemEntryID(unwrapDataViewItem(item));
    if (!entryID) {
        return ShouldHideTimelineItem(item, hideWhoToFollow, hidePrompts, hideTopics,
                                      hideTopicsToFollow, hideVerified, inConversation, inProfile,
                                      conversationRootUserID, authorRepliedToUserIDs);
    }

    NSNumber* cached = [cache objectForKey:entryID];
    if (cached) {
        return cached.boolValue;
    }

    BOOL hide = ShouldHideTimelineItem(item, hideWhoToFollow, hidePrompts, hideTopics,
                                       hideTopicsToFollow, hideVerified, inConversation, inProfile,
                                       conversationRootUserID, authorRepliedToUserIDs);
    [cache setObject:@(hide) forKey:entryID];
    return hide;
}

static long long ConversationRootUserID(NSArray* sections) {
    for (id section in sections) {
        if (![section isKindOfClass:[NSArray class]]) {
            continue;
        }
        for (id item in (NSArray*)section) {
            id viewModel = unwrapDataViewItem(item);
            if (ItemIsConversationThreadReply(viewModel)) {
                continue;
            }
            long long userID = ItemRepresentedFromUserID(viewModel);
            if (userID != 0) {
                return userID;
            }
        }
    }
    return 0;
}

static NSSet<NSNumber*>* ConversationAuthorRepliedToUserIDs(NSArray* sections,
                                                            long long rootUserID) {
    NSMutableSet<NSNumber*>* repliedToUserIDs = [NSMutableSet set];
    if (rootUserID == 0) {
        return repliedToUserIDs;
    }
    for (id section in sections) {
        if (![section isKindOfClass:[NSArray class]]) {
            continue;
        }
        for (id item in (NSArray*)section) {
            id viewModel = unwrapDataViewItem(item);
            if (!ItemIsConversationThreadReply(viewModel)) {
                continue;
            }
            if (ItemRepresentedFromUserID(viewModel) != rootUserID) {
                continue;
            }
            long long repliedToUserID = ItemInReplyToUserID(viewModel);
            if (repliedToUserID != 0) {
                [repliedToUserIDs addObject:@(repliedToUserID)];
            }
        }
    }
    return repliedToUserIDs;
}

// MARK: - Reading marker
//
// Marks where the reading stopped when new Tweets arrive above — an accent
// wash over that Tweet's header, fading out before the media. With nothing
// new above the anchor there is nothing to say, and nothing is drawn. The
// anchor is the topmost visible row, captured when the screen is left, when
// the app backgrounds, and just before a delivery that puts new content on
// top. Chronological tabs (Following, Lists) keep their
// anchor through refreshes, so the marker lives there; a tab that discards
// its anchor on a large list is algorithmic, and the marker retires on it for
// the session rather than lying. Tabs whose controllers name themselves
// "ForYou" never get a marker at all.

static const void* kNFBReadingAnchorIDKey = &kNFBReadingAnchorIDKey;
static const void* kNFBReadingAnchorPathKey = &kNFBReadingAnchorPathKey;
static const void* kNFBReadingMarkerViewKey = &kNFBReadingMarkerViewKey;
static const void* kNFBListViewKey = &kNFBListViewKey;
static const void* kNFBReadingTopAtCaptureKey = &kNFBReadingTopAtCaptureKey;
static const void* kNFBReadingRetiredKey = &kNFBReadingRetiredKey;
static const void* kNFBReadingMissCountKey = &kNFBReadingMissCountKey;
static const void* kNFBReadingForYouKey = &kNFBReadingForYouKey;

// The wash covers the Tweet's header and fades out before the media: solid
// for the first points, gone by the reach. Low enough to read through, high
// enough to spot at a glance.
static const CGFloat kNFBReadingMarkerAlpha = 0.18;
static const CGFloat kNFBReadingFadeSolid = 34.0;
static const CGFloat kNFBReadingFadeReach = 110.0;
static NSHashTable* gNFBReadingControllers = nil;

// A list scroll view is one that can name its visible index paths.
static BOOL NFBViewIsList(UIView* view) {
    return [view isKindOfClass:[UIScrollView class]] &&
           ([view respondsToSelector:@selector(indexPathsForVisibleRows)] ||
            [view respondsToSelector:@selector(indexPathsForVisibleItems)]);
}

static UIScrollView* NFBFindListInView(UIView* view) {
    if (NFBViewIsList(view)) {
        return (UIScrollView*)view;
    }
    for (UIView* subview in view.subviews) {
        UIScrollView* found = NFBFindListInView(subview);
        if (found) {
            return found;
        }
    }
    return nil;
}

// The controller's list, found in its mounted view tree. Asking the
// controller for -tableView or -collectionView instead would invoke a lazy
// getter, which builds a view that was never meant to exist — and on a
// collection view that raises, taking the app down. Only what is already on
// screen is inspected here.
static UIScrollView* NFBListScrollView(TFNItemsDataViewController* dataViewController) {
    if (![dataViewController isViewLoaded]) {
        return nil;
    }
    UIScrollView* cached =
        objc_getAssociatedObject(dataViewController, kNFBListViewKey);
    if (cached.window && [cached isDescendantOfView:dataViewController.view]) {
        return cached;
    }
    UIScrollView* found = NFBFindListInView(dataViewController.view);
    objc_setAssociatedObject(dataViewController, kNFBListViewKey, found,
                             OBJC_ASSOCIATION_ASSIGN);
    return found;
}

static NSArray<NSIndexPath*>* NFBListVisibleIndexPaths(UIScrollView* scrollView) {
    if ([scrollView respondsToSelector:@selector(indexPathsForVisibleRows)]) {
        return ((NSArray* (*)(id, SEL))objc_msgSend)(
            scrollView, @selector(indexPathsForVisibleRows));
    }
    if ([scrollView respondsToSelector:@selector(indexPathsForVisibleItems)]) {
        return ((NSArray* (*)(id, SEL))objc_msgSend)(
            scrollView, @selector(indexPathsForVisibleItems));
    }
    return @[];
}

static BOOL NFBListCellFrame(UIScrollView* scrollView, NSIndexPath* path,
                             CGRect* outFrame) {
    if ([scrollView respondsToSelector:@selector(cellForRowAtIndexPath:)]) {
        UIView* cell = ((UIView* (*)(id, SEL, id))objc_msgSend)(
            scrollView, @selector(cellForRowAtIndexPath:), path);
        if (cell) {
            *outFrame = cell.frame;
            return YES;
        }
        if ([scrollView respondsToSelector:@selector(rectForRowAtIndexPath:)]) {
            *outFrame = ((CGRect (*)(id, SEL, id))objc_msgSend)(
                scrollView, @selector(rectForRowAtIndexPath:), path);
            return YES;
        }
    }
    if ([scrollView respondsToSelector:@selector(cellForItemAtIndexPath:)]) {
        UIView* cell = ((UIView* (*)(id, SEL, id))objc_msgSend)(
            scrollView, @selector(cellForItemAtIndexPath:), path);
        if (cell) {
            *outFrame = cell.frame;
            return YES;
        }
    }
    if ([scrollView respondsToSelector:@selector(layoutAttributesForItemAtIndexPath:)]) {
        id attributes = ((id (*)(id, SEL, id))objc_msgSend)(
            scrollView, @selector(layoutAttributesForItemAtIndexPath:), path);
        if (attributes && [attributes respondsToSelector:@selector(frame)]) {
            *outFrame = ((CGRect (*)(id, SEL))objc_msgSend)(attributes,
                                                            @selector(frame));
            return YES;
        }
    }
    return NO;
}

static BOOL NFBReadingIsHomeTimeline(TFNItemsDataViewController* dataViewController) {
    return IsInHierarchyOfClass(
        dataViewController,
        @"_TtC32TwitterHomeFeatureImplementation35HomeTimelineContainerViewController");
}

// The topmost visible row's entry ID; nil when the table or the item cannot
// be resolved. Sections that are not item arrays are opaque and skipped.
static NSString* NFBReadingTopVisibleEntryID(TFNItemsDataViewController* dataViewController) {
    UIScrollView* list = NFBListScrollView(dataViewController);
    NSIndexPath* top = NFBListVisibleIndexPaths(list).firstObject;
    if (!top) {
        return nil;
    }
    NSArray* sections = dataViewController.sections;
    if (top.section >= (NSInteger)sections.count) {
        return nil;
    }
    id section = sections[top.section];
    if (![section isKindOfClass:[NSArray class]] ||
        top.row >= (NSInteger)((NSArray*)section).count) {
        return nil;
    }
    return ItemEntryID(((NSArray*)section)[top.row]);
}

// The list's first datable item — the reference for "has anything new
// arrived above the anchor since it was captured".
static NSString* NFBReadingFirstEntryID(NSArray* sections) {
    for (id section in sections) {
        if (![section isKindOfClass:[NSArray class]]) {
            continue;
        }
        for (id item in (NSArray*)section) {
            NSString* entryID = ItemEntryID(item);
            if (entryID.length) {
                return entryID;
            }
        }
    }
    return nil;
}

static NSIndexPath* NFBReadingIndexPathForEntryID(
    TFNItemsDataViewController* dataViewController, NSString* target) {
    if (!target.length) {
        return nil;
    }
    NSArray* sections = dataViewController.sections;
    for (NSUInteger sectionIndex = 0; sectionIndex < sections.count; sectionIndex++) {
        id section = sections[sectionIndex];
        if (![section isKindOfClass:[NSArray class]]) {
            continue;
        }
        NSArray* items = section;
        for (NSUInteger row = 0; row < items.count; row++) {
            if ([target isEqualToString:ItemEntryID(items[row])]) {
                return [NSIndexPath indexPathForRow:row inSection:sectionIndex];
            }
        }
    }
    return nil;
}

// Anchors outlive the process. Which tab an anchor belongs to is never
// recorded: on the next launch each list looks for the first stored anchor it
// still contains, so Following and every List recover their own without the
// tweak having to name them. A list that contains none of them simply starts
// fresh.
static NSString* const kNFBReadingStoreKey = @"nfb_reading_anchors";
static const NSUInteger kNFBReadingStoreLimit = 12;

static void NFBReadingStoreRemember(NSString* previousAnchor, NSString* anchor,
                                    NSString* head) {
    if (!anchor.length || !head.length) {
        return;
    }
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSMutableArray* entries =
        [NSMutableArray arrayWithObject:@{@"anchor": anchor, @"head": head}];
    for (id entry in [defaults arrayForKey:kNFBReadingStoreKey]) {
        if (entries.count >= kNFBReadingStoreLimit) {
            break;
        }
        if (![entry isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSString* storedAnchor = ((NSDictionary*)entry)[@"anchor"];
        // The tab's own previous entry is replaced, not stacked.
        if (![storedAnchor isKindOfClass:[NSString class]] ||
            [storedAnchor isEqualToString:anchor] ||
            (previousAnchor.length &&
             [storedAnchor isEqualToString:previousAnchor])) {
            continue;
        }
        [entries addObject:entry];
    }
    [defaults setObject:entries forKey:kNFBReadingStoreKey];
}

static BOOL NFBReadingStoreRestore(TFNItemsDataViewController* dataViewController) {
    for (id entry in
         [[NSUserDefaults standardUserDefaults] arrayForKey:kNFBReadingStoreKey]) {
        if (![entry isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSString* anchor = ((NSDictionary*)entry)[@"anchor"];
        NSString* head = ((NSDictionary*)entry)[@"head"];
        if (![anchor isKindOfClass:[NSString class]] ||
            ![head isKindOfClass:[NSString class]] ||
            !NFBReadingIndexPathForEntryID(dataViewController, anchor)) {
            continue;
        }
        objc_setAssociatedObject(dataViewController, kNFBReadingAnchorIDKey,
                                 anchor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(dataViewController, kNFBReadingTopAtCaptureKey,
                                 head, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return YES;
    }
    return NO;
}

// The controller chain names the algorithmic tab on builds where the child
// controllers carry "ForYou" in their class names; the verdict is cached per
// controller. A chain that names nothing changes nothing.
static BOOL NFBReadingLooksLikeForYou(TFNItemsDataViewController* dataViewController) {
    NSNumber* cached =
        objc_getAssociatedObject(dataViewController, kNFBReadingForYouKey);
    if (cached) {
        return cached.boolValue;
    }
    BOOL forYou = NO;
    BOOL chainComplete = NO;
    UIResponder* responder = dataViewController;
    while ((responder = responder.nextResponder)) {
        if ([NSStringFromClass([responder class]) containsString:@"ForYou"]) {
            forYou = YES;
            chainComplete = YES;
            break;
        }
        if ([responder isKindOfClass:[UIWindow class]]) {
            chainComplete = YES;
            break;
        }
    }
    // A controller asked before it is mounted has no chain to walk, and a "no"
    // read from it would be cached for the session. Only a walk that reached
    // the window, or found the tab outright, is worth keeping.
    if (chainComplete) {
        objc_setAssociatedObject(dataViewController, kNFBReadingForYouKey,
                                 @(forYou), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return forYou;
}

static BOOL NFBReadingMarkerAllowed(TFNItemsDataViewController* dataViewController) {
    return [BHTSettings boolForKey:@"reading_line"] &&
           NFBReadingIsHomeTimeline(dataViewController) &&
           ![objc_getAssociatedObject(dataViewController, kNFBReadingRetiredKey)
               boolValue] &&
           !NFBReadingLooksLikeForYou(dataViewController);
}

static NSUInteger NFBReadingItemCount(NSArray* sections) {
    NSUInteger count = 0;
    for (id section in sections) {
        if ([section isKindOfClass:[NSArray class]]) {
            count += ((NSArray*)section).count;
        }
    }
    return count;
}

static void NFBReadingCaptureAnchor(TFNItemsDataViewController* dataViewController) {
    if (!NFBReadingMarkerAllowed(dataViewController)) {
        return;
    }
    NSString* top = NFBReadingTopVisibleEntryID(dataViewController);
    if (!top.length) {
        return;
    }
    NSString* listHead = NFBReadingFirstEntryID(dataViewController.sections);
    NSString* storedHead =
        objc_getAssociatedObject(dataViewController, kNFBReadingTopAtCaptureKey);
    // An active boundary survives every capture until the reader has reached
    // the top of the list: a refresh that brings nothing, a backgrounding or
    // an opened Tweet mid-catch-up must not erase it. Reaching the top IS the
    // catch-up, and only then does the reference reset.
    BOOL boundaryActive = storedHead.length && listHead.length &&
                          ![storedHead isEqualToString:listHead];
    if (boundaryActive && ![top isEqualToString:listHead]) {
        return;
    }
    NSString* previousAnchor =
        objc_getAssociatedObject(dataViewController, kNFBReadingAnchorIDKey);
    objc_setAssociatedObject(dataViewController, kNFBReadingAnchorIDKey, top,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(dataViewController, kNFBReadingTopAtCaptureKey,
                             listHead, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NFBReadingStoreRemember(previousAnchor, top, listHead);
}

// One row's true geometry. The rendered cell is authoritative when it is on
// screen — data sections and table rows do not always map one-to-one on For
// You, and the computed rect can span the wrong range there. Off screen, the
// computed rect only decides visibility, so the fallback is harmless.
static void NFBReadingPlaceMarker(UIScrollView* table, UIView* marker,
                                  NSIndexPath* path) {
    CGRect rowRect;
    if (!NFBListCellFrame(table, path, &rowRect)) {
        marker.hidden = YES;
        return;
    }
    extern UIColor* CurrentAccentColor(void);
    UIColor* accent = CurrentAccentColor() ?: [UIColor systemBlueColor];
    CGFloat reach = MIN(CGRectGetHeight(rowRect), kNFBReadingFadeReach);
    marker.frame = CGRectMake(CGRectGetMinX(rowRect), CGRectGetMinY(rowRect),
                              CGRectGetWidth(rowRect), reach);
    CAGradientLayer* fade =
        (CAGradientLayer*)marker.layer.sublayers.firstObject;
    if (![fade isKindOfClass:[CAGradientLayer class]]) {
        fade = [CAGradientLayer layer];
        [marker.layer addSublayer:fade];
    }
    UIColor* tint = [accent colorWithAlphaComponent:kNFBReadingMarkerAlpha];
    // The layer would animate every reposition; the marker must simply be
    // where its Tweet is.
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    fade.frame = marker.bounds;
    fade.colors = @[
        (id)tint.CGColor, (id)tint.CGColor, (id)UIColor.clearColor.CGColor
    ];
    fade.locations = @[
        @0, @(reach > 0.0 ? MIN(kNFBReadingFadeSolid / reach, 1.0) : 0.0), @1
    ];
    [CATransaction commit];
    if (marker.superview != table) {
        [table addSubview:marker];
    }
    marker.hidden = NO;
    [table bringSubviewToFront:marker];
}

// Places (or hides) the marker for the current data. The row rect is content-
// space, so the placed wash scrolls with the feed; only data changes move it.
// It sits above the cell at low alpha — beneath it, the opaque cell would
// hide it entirely.
static void NFBReadingPositionMarker(TFNItemsDataViewController* dataViewController) {
    UIScrollView* table = NFBListScrollView(dataViewController);
    if (!table) {
        return;
    }
    UIView* marker = objc_getAssociatedObject(table, kNFBReadingMarkerViewKey);
    // A launch starts with no anchor in memory; the stored ones are tried
    // against this list a few times while it fills in.
    if (NFBReadingMarkerAllowed(dataViewController) &&
        !objc_getAssociatedObject(dataViewController, kNFBReadingAnchorIDKey)) {
        // Retried while the list still has nothing to match against: a fixed
        // number of attempts runs out before the first page arrives.
        if (NFBReadingItemCount(dataViewController.sections) > 0) {
            NFBReadingStoreRestore(dataViewController);
        }
    }
    NSString* anchor =
        objc_getAssociatedObject(dataViewController, kNFBReadingAnchorIDKey);
    NSIndexPath* path = NFBReadingMarkerAllowed(dataViewController)
                            ? NFBReadingIndexPathForEntryID(dataViewController, anchor)
                            : nil;
    objc_setAssociatedObject(table, kNFBReadingAnchorPathKey, path,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!path) {
        // An anchor that vanishes from a large list marks an algorithmic tab:
        // the data was replaced, not extended. But a large load can also land
        // in phases, with the anchor's stretch arriving after the gap row —
        // one absent pass is not a verdict. Two consecutive ones are, and only
        // then does the marker retire for the session instead of reappearing
        // to lie after the next capture.
        // A replaced list has a new first item as well as a missing anchor;
        // an anchor that merely fell out of a list whose head is unchanged is
        // a loading phase, not an algorithmic wipe.
        NSString* headNow = NFBReadingFirstEntryID(dataViewController.sections);
        NSString* headThen =
            objc_getAssociatedObject(dataViewController, kNFBReadingTopAtCaptureKey);
        BOOL replaced = headNow.length && headThen.length &&
                        ![headNow isEqualToString:headThen];
        if (anchor.length && replaced &&
            NFBReadingItemCount(dataViewController.sections) >= 10) {
            NSInteger misses =
                [objc_getAssociatedObject(dataViewController,
                                          kNFBReadingMissCountKey) integerValue] +
                1;
            if (misses >= 2) {
                objc_setAssociatedObject(dataViewController,
                                         kNFBReadingRetiredKey, @YES,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                objc_setAssociatedObject(dataViewController,
                                         kNFBReadingAnchorIDKey, nil,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                objc_setAssociatedObject(dataViewController,
                                         kNFBReadingMissCountKey, nil,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            } else {
                objc_setAssociatedObject(dataViewController,
                                         kNFBReadingMissCountKey, @(misses),
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }
        marker.hidden = YES;
        return;
    }
    objc_setAssociatedObject(dataViewController, kNFBReadingMissCountKey, nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // Nothing new above the anchor means nothing to say: at the top of an
    // unchanged list the reader already knows where they are.
    NSString* topAtCapture =
        objc_getAssociatedObject(dataViewController, kNFBReadingTopAtCaptureKey);
    NSString* topNow = NFBReadingFirstEntryID(dataViewController.sections);
    if (!topAtCapture.length || !topNow.length ||
        [topAtCapture isEqualToString:topNow]) {
        marker.hidden = YES;
        return;
    }
    if (!marker) {
        marker = [[UIView alloc] init];
        marker.userInteractionEnabled = NO;
        objc_setAssociatedObject(table, kNFBReadingMarkerViewKey, marker,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NFBReadingPlaceMarker(table, marker, path);
}

// Row heights settle after the reload, so the scan waits one runloop turn.
static void NFBReadingRescanSoon(TFNItemsDataViewController* dataViewController) {
    if (!NFBReadingIsHomeTimeline(dataViewController)) {
        return;
    }
    __weak TFNItemsDataViewController* weakController = dataViewController;
    dispatch_async(dispatch_get_main_queue(), ^{
        TFNItemsDataViewController* controller = weakController;
        if (controller) {
            NFBReadingPositionMarker(controller);
        }
    });
}

// Self-sizing rows shift their rects as cells realise; the layout tick keeps
// the wash on its row from the cached index path, without rescanning.
static void NFBReadingLayoutTick(UIScrollView* scrollView) {
    UIView* marker = objc_getAssociatedObject(scrollView, kNFBReadingMarkerViewKey);
    if (!marker || marker.hidden) {
        return;
    }
    NSIndexPath* path =
        objc_getAssociatedObject(scrollView, kNFBReadingAnchorPathKey);
    if (!path) {
        marker.hidden = YES;
        return;
    }
    NFBReadingPlaceMarker(scrollView, marker, path);
}

// The app backgrounding is the one leave moment no view callback covers.
static void NFBReadingTrack(TFNItemsDataViewController* dataViewController) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gNFBReadingControllers = [NSHashTable weakObjectsHashTable];
        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidEnterBackgroundNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification* note) {
                        for (TFNItemsDataViewController* controller in
                             gNFBReadingControllers.allObjects) {
                            NFBReadingCaptureAnchor(controller);
                        }
                    }];
    });
    [gNFBReadingControllers addObject:dataViewController];
}

// MARK: - Language filter
//
// A Tweet carries the language of its original text. The kept set lists the
// languages the reader selected; an empty set means the filter is off. A Tweet
// whose language could not be detected always passes, so image-only posts are
// never lost.

static NSString* const kNFBLanguagesKey = @"nfb_filter_languages";

static id NFBStatusForItem(id item) {
    SEL reach[] = { @selector(status), @selector(tweet) };
    for (NSUInteger index = 0; index < sizeof(reach) / sizeof(reach[0]); index++) {
        if ([item respondsToSelector:reach[index]]) {
            id value = ((id (*)(id, SEL))objc_msgSend)(item, reach[index]);
            if (value) {
                return value;
            }
        }
    }
    return item;
}

static BOOL NFBItemLanguageAllowed(id item, NSSet<NSString*>* kept) {
    if (!kept.count) {
        return YES;
    }
    id status = NFBStatusForItem(item);
    if (![status respondsToSelector:@selector(lang)]) {
        return YES;
    }
    NSString* language =
        ((NSString* (*)(id, SEL))objc_msgSend)(status, @selector(lang));
    if (![language isKindOfClass:[NSString class]] || !language.length ||
        [language isEqualToString:@"und"]) {
        return YES;
    }
    // A regional code ("pt-BR") matches the language it belongs to.
    NSString* base = [language componentsSeparatedByString:@"-"].firstObject;
    return [kept containsObject:base.lowercaseString];
}

static NSSet<NSString*>* NFBKeptLanguages(void) {
    NSArray* stored =
        [[NSUserDefaults standardUserDefaults] arrayForKey:kNFBLanguagesKey];
    if (![stored isKindOfClass:[NSArray class]] || !stored.count) {
        return nil;
    }
    NSMutableSet* set = [NSMutableSet setWithCapacity:stored.count];
    for (id code in stored) {
        if ([code isKindOfClass:[NSString class]]) {
            [set addObject:((NSString*)code).lowercaseString];
        }
    }
    return set;
}

static NSArray* FilteredTimelineSections(TFNItemsDataViewController* dataViewController,
                                         NSArray* sections) {
    BOOL hideWhoToFollow = [BHTSettings boolForKey:@"hide_who_to_follow"];
    BOOL hidePrompts = [BHTSettings boolForKey:@"hide_timeline_prompts"];
    BOOL hideTopics = [BHTSettings boolForKey:@"hide_topics"];
    BOOL hideTopicsToFollow = [BHTSettings boolForKey:@"hide_topics_to_follow"];
    BOOL inConversation =
        IsInHierarchyOfClass(dataViewController, @"T1ConversationContainerViewController");
    BOOL inProfile = IsInHierarchyOfClass(dataViewController, @"T1ProfileViewController");

    BOOL hideVerified = [BHTSettings boolForKey:@"hide_verified_tweets"] && !inProfile;
    // The language filter belongs to the timelines, not to a conversation or a
    // profile opened on purpose.
    NSSet<NSString*>* keptLanguages =
        (inConversation || inProfile) ? nil : NFBKeptLanguages();

    if (!hideWhoToFollow && !hidePrompts && !hideTopics && !hideTopicsToFollow &&
        !hideVerified && !inConversation && !keptLanguages.count) {
        return sections;
    }

    long long conversationRootUserID =
        (hideVerified && inConversation) ? ConversationRootUserID(sections) : 0;
    NSSet<NSNumber*>* authorRepliedToUserIDs =
        (hideVerified && inConversation)
            ? ConversationAuthorRepliedToUserIDs(sections, conversationRootUserID)
            : nil;

    // Modules can share a section with unrelated items, so filtering is per item;
    // a purely filtered section (like the Discover More one) empties and is dropped.
    BOOL modified = NO;
    NSMutableArray* filteredSections = [NSMutableArray arrayWithCapacity:sections.count];

    for (id section in sections) {
        if (![section isKindOfClass:[NSArray class]]) {
            [filteredSections addObject:section];
            continue;
        }

        NSArray* items = section;
        NSMutableIndexSet* removed = [NSMutableIndexSet indexSet];

        for (NSUInteger i = 0; i < items.count; i++) {
            if (MemoizedShouldHideTimelineItem(items[i], hideWhoToFollow, hidePrompts, hideTopics,
                                               hideTopicsToFollow, hideVerified, inConversation,
                                               inProfile, conversationRootUserID,
                                               authorRepliedToUserIDs) ||
                !NFBItemLanguageAllowed(items[i], keptLanguages)) {
                [removed addIndex:i];
            }
        }

        if (removed.count == 0) {
            [filteredSections addObject:section];
            continue;
        }

        MarkEmptiedModuleChrome(items, removed);

        modified = YES;
        NSMutableArray* keptItems = [items mutableCopy];
        [keptItems removeObjectsAtIndexes:removed];
        if (keptItems.count > 0) {
            [filteredSections addObject:keptItems];
        }
    }

    return modified ? [filteredSections copy] : sections;
}

%hook TFNItemsDataViewController

- (void)setSections:(NSArray*)sections restoreScrollPosition:(BOOL)restoreScrollPosition {
    BOOL keepPlace = restoreScrollPosition;
    if (NFBReadingIsHomeTimeline(self)) {
        // Every home controller is tracked, the algorithmic tab included: tracking is pure
        // registration, and each reading action gates itself on MarkerAllowed.
        // The badge pass resolves its controller from this registry.
        NFBReadingTrack(self);
        if (NFBReadingMarkerAllowed(self)) {
            NFBReadingCaptureAnchor(self);
        }
        // Twitter's own restore flag, forced on the home timeline so a reload
        // keeps the reading position instead of jumping to the top.
        keepPlace = YES;
    }
    %orig(FilteredTimelineSections(self, sections), keepPlace);
    NFBReadingRescanSoon(self);
}

- (void)updateSections:(NSArray*)sections
    reconfigureItemIdentifiers:(NSArray*)identifiers
              withRowAnimation:(long long)animation
                    completion:(id)completion {
    if (NFBReadingMarkerAllowed(self)) {
        NSString* incomingTop = NFBReadingFirstEntryID(sections);
        NSString* currentTop = NFBReadingFirstEntryID(self.sections);
        if (incomingTop.length && currentTop.length &&
            ![incomingTop isEqualToString:currentTop]) {
            NFBReadingCaptureAnchor(self);
        }
    }
    %orig(FilteredTimelineSections(self, sections), identifiers, animation, completion);
    NFBReadingRescanSoon(self);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    NFBReadingRescanSoon(self);
}

- (void)viewWillDisappear:(BOOL)animated {
    NFBReadingCaptureAnchor(self);
    %orig;
}

%end

// MARK: - Poll results before voting
//
// Twitter hides the tallies until a vote is cast. The counts travel with the
// card data all along, so the percentage is simply appended to each option's
// label. Ported from Orion's fork, whose comment saved the hard part: don't
// derive the choice count from the card name — text polls are named
// "poll2choice_text_only", but image polls carry no count in their name at
// all, so the per-choice bindings are probed instead.

static const NSUInteger kNFBPollMaxChoices = 4;

// "choice2_label" -> 2, anything else -> 0.
static NSUInteger nfbPollChoiceIndexForKey(NSString* key) {
    if (![key hasPrefix:@"choice"] || ![key hasSuffix:@"_label"]) {
        return 0;
    }
    NSRange digits = NSMakeRange(6, key.length - 6 - 6);
    NSInteger index = [key substringWithRange:digits].integerValue;
    return index > 0 ? (NSUInteger)index : 0;
}

static BOOL nfbPollAlreadyShowsResults(TFCCardData* cardData) {
    if ([cardData boolForKey:@"counts_are_final"]) {
        return YES;
    }
    return [cardData stringForKey:@"selected_choice"].length > 0;
}

static NSString* nfbPollPercentageString(double fraction) {
    static NSNumberFormatter* formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        formatter = [[NSNumberFormatter alloc] init];
        formatter.numberStyle = NSNumberFormatterPercentStyle;
        formatter.maximumFractionDigits = 0;
    });
    return [formatter stringFromNumber:@(fraction)];
}

static NSString* nfbPollTitleWithPercentage(TFCCardData* cardData,
                                            NSString* key,
                                            NSString* title) {
    NSUInteger choice = nfbPollChoiceIndexForKey(key);
    if (choice == 0 || choice > kNFBPollMaxChoices || title.length == 0 ||
        ![BHTSettings boolForKey:@"show_poll_results"]) {
        return title;
    }
    if (nfbPollAlreadyShowsResults(cardData)) {
        return title;
    }

    // numberForKey: tells a missing binding apart from a zero tally, and
    // neither it nor numberFromStringForKey: is hooked below, so probing the
    // siblings cannot recurse back in here.
    long long total = 0;
    long long votes = 0;
    for (NSUInteger i = 1; i <= kNFBPollMaxChoices; i++) {
        NSString* countKey =
            [NSString stringWithFormat:@"choice%lu_count", (unsigned long)i];
        NSNumber* count = [cardData numberForKey:countKey]
                              ?: [cardData numberFromStringForKey:countKey];
        if (!count) {
            continue;
        }
        total += count.longLongValue;
        if (i == choice) {
            votes = count.longLongValue;
        }
    }
    if (total <= 0) {
        return title;
    }
    return [NSString
        stringWithFormat:@"%@ (%@)", title,
                         nfbPollPercentageString((double)votes / (double)total)];
}

%hook TFCCardData

- (NSString*)stringForKey:(NSString*)key {
    NSString* title = %orig;
    return nfbPollTitleWithPercentage(self, key, title);
}

- (NSString*)stringForKey:(NSString*)key defaultValue:(NSString*)value {
    NSString* title = %orig;
    return nfbPollTitleWithPercentage(self, key, title);
}

%end
