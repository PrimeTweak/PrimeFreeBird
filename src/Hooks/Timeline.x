//
//  Timeline.x
//  PrimeFreeBird
//

#import <QuartzCore/QuartzCore.h>

#import "HookHelpers.h"
#import "Debug/NFBDebugger.h"   // [p24] probe only, remove with it

// Declared once at file scope: two distant passes read the hidden-thread
// list, and a block-scope extern is invisible to the second one.
extern NSArray<NSDictionary*>* NFBHiddenThreads(void);

// MARK: - Hide custom timelines

static __weak NSObject* PinnedTimelinesRepository;
static NSArray* LastPinnedTimelineModels;
static BOOL PinnedTimelinesWriteBypass = NO;

// Applies the toggle without relaunching. The unchanged pinned list is rewritten
// purely to republish, since updatePinnedTimelines: persists server-side; the
// delegate hook below swaps in the empty list on the way through.
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

// Opting back into the iOS 26 design makes iOS draw a scroll edge effect under
// every bar. This option switches that effect off wherever it appears.

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
        return;   // nothing to do before iOS 26
    }
    id effect = ((id (*)(id, SEL))objc_msgSend)(scrollView, @selector(topEdgeEffect));
    if (![effect respondsToSelector:@selector(setHidden:)] ||
        ![effect respondsToSelector:@selector(isHidden)]) {
        return;
    }
    BOOL alreadyHidden = ((BOOL (*)(id, SEL))objc_msgSend)(effect, @selector(isHidden));
    if (alreadyHidden == hide) {
        return;   // nothing to do: the common case, and the cheapest
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

// The root of Twitter's own settings is spared but still needs a boundary: iOS
// draws its bar as a gradual fade, so the list shows through above the search
// field. Sub-pages share the class, so the root is the first one in the stack.
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

// A near-opaque band covering the settings sheet's header zone: the scroll edge
// effect stops partway down the search field and ignores geometry setters. A plain
// UIView, installed from the bar's layout, with the frame copied from the bar.
static const CGFloat kNFBSettingsBandWhiteness = 0.9;

static const void* kNFBSettingsBarBandKey = &kNFBSettingsBarBandKey;
// Set while a change to the band is already queued for the next run-loop turn,
// so a run of layout passes queues one block and not one per pass.
static const void* kNFBSettingsBandPendingKey = &kNFBSettingsBandPendingKey;

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

// The bar's own background view, which the band is sized from.
static UIView* nfbSettingsBarBackground(UINavigationBar* bar) {
    for (UIView* subview in bar.subviews) {
        if ([NSStringFromClass([subview class]) isEqualToString:@"_UIBarBackground"]) {
            return subview;
        }
    }
    return nil;   // not built yet; the bar will lay out again
}

// The band view, created once and kept on the bar.
static UIView* nfbSettingsBandView(UINavigationBar* bar) {
    UIView* band = objc_getAssociatedObject(bar, kNFBSettingsBarBandKey);
    if (!band) {
        band = [[UIView alloc] init];
        band.userInteractionEnabled = NO;
        band.backgroundColor = [[UIColor systemBackgroundColor]
            colorWithAlphaComponent:kNFBSettingsBandWhiteness];
        objc_setAssociatedObject(bar, kNFBSettingsBarBandKey, band,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return band;
}

// Hierarchy work, never called from a layout pass: inserting a subview there
// invalidates the bar's layout, which lays out again and inserts again. The back
// index is re-asserted here, where a further layout pass costs nothing.
static void nfbInstallSettingsBand(UINavigationBar* bar) {
    if (!nfbSettingsBarBackground(bar)) {
        return;
    }
    UIView* band = nfbSettingsBandView(bar);
    if (band.superview == bar && [bar.subviews indexOfObject:band] == 0) {
        return;
    }
    [bar insertSubview:band atIndex:0];
    NFBDebugLog(@"[p24] band installed at index 0 (subviews=%lu)",
                (unsigned long)bar.subviews.count);
}

// Only the root page carries the search field, so a pushed page keeps its bar
// untouched. Never called from a layout pass: `hidden` takes a view out of layout
// participation, so writing it there re-invalidates the layout that is running.
static void nfbSyncSettingsBandVisibility(UINavigationBar* bar,
                                          UINavigationController* navigation) {
    UIView* band = objc_getAssociatedObject(bar, kNFBSettingsBarBandKey);
    if (!band || band.superview != bar) {
        return;
    }
    BOOL onRoot =
        navigation.topViewController == navigation.viewControllers.firstObject;
    if (band.hidden != onRoot) {
        return;
    }
    band.hidden = !onRoot;
    NFBDebugLog(@"[p24] band visibility settled: hidden=%d", band.hidden ? 1 : 0);
}

// Queues one pass over the band for the next turn of the run loop, and only one:
// a run of layout passes must not queue a block per pass.
static void nfbQueueSettingsBandPass(UINavigationBar* bar,
                                     UINavigationController* navigation) {
    if (objc_getAssociatedObject(bar, kNFBSettingsBandPendingKey)) {
        return;
    }
    objc_setAssociatedObject(bar, kNFBSettingsBandPendingKey, @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    dispatch_async(dispatch_get_main_queue(), ^{
      objc_setAssociatedObject(bar, kNFBSettingsBandPendingKey, nil,
                               OBJC_ASSOCIATION_RETAIN_NONATOMIC);
      if (!bar.window) {
          return;
      }
      nfbInstallSettingsBand(bar);
      nfbSyncSettingsBandVisibility(bar, navigation);
    });
}

// Frame only. Setting a subview's frame does not invalidate the superview's
// layout, so this is the one part that is safe inside layoutSubviews. Anything
// else the band needs is answered NO and settled off the layout pass.
static BOOL nfbUpdateSettingsBand(UINavigationBar* bar,
                                  UINavigationController* navigation) {
    UIView* background = nfbSettingsBarBackground(bar);
    if (!background) {
        return YES;
    }
    UIView* band = nfbSettingsBandView(bar);
    if (band.superview != bar) {
        return NO;
    }
    if (!CGRectEqualToRect(band.frame, background.frame)) {
        band.frame = background.frame;
    }
    BOOL onRoot =
        navigation.topViewController == navigation.viewControllers.firstObject;
    return band.hidden != onRoot;
}

// [p24] probe only: how often a settings bar lays out and where the band sits
// while it does. Reported at most twice a second, with the counts since the last
// line, so a runaway layout reads as a rate rather than a flood.
static void nfbNoteSettingsBarLayout(UINavigationBar* bar, BOOL inPlace) {
    static NSInteger passes = 0;
    static NSInteger strays = 0;
    static NSTimeInterval lastNote = 0;
    passes++;
    if (!inPlace) {
        strays++;
    }
    NSTimeInterval now = CACurrentMediaTime();
    if (now - lastNote < 0.5) {
        return;
    }
    UIView* band = objc_getAssociatedObject(bar, kNFBSettingsBarBandKey);
    NSInteger index = (band && band.superview == bar)
                          ? (NSInteger)[bar.subviews indexOfObject:band]
                          : -1;
    NFBDebugLog(@"[p24] settings bar: %ld pass(es) in %.1f s, %ld stray, band "
                @"index=%ld, subviews=%lu",
                (long)passes, now - lastNote, (long)strays, (long)index,
                (unsigned long)bar.subviews.count);
    passes = 0;
    strays = 0;
    lastNote = now;
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

// Checked on every layout of every scroll view, since iOS re-enables the effect
// whenever a bar reconfigures. The work is two message sends when the state
// already matches, which is nearly always.
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
                nfbInstallSettingsBand(self);
                nfbUpdateSettingsBand(self, navigation);
                nfbSyncSettingsBandVisibility(self, navigation);
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
                BOOL settled = nfbUpdateSettingsBand(self, navigation);
                nfbNoteSettingsBarLayout(self, settled);
                if (!settled) {
                    nfbQueueSettingsBandPass(self, navigation);
                }
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

// The rule list is cached rather than read per item; the editor calls
// nfbRefreshMutedWords() and the signature below invalidates the memo. Text and
// handle are read through several known selectors, so a rename means no match.

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

    // Hidden conversations share this memo: without them in the signature, the
    // timeline keeps its previous verdict and a hidden thread only vanishes on
    // the next reload.
    signature = signature * 31 + NFBHiddenThreads().count;
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

// Hidden conversations live in HiddenThreads.x, which owns the registry and
// the button that fills it.
extern BOOL nfbThreadIsHidden(id viewModel);

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

    // Hidden conversations are their own filter: they were tested inside
    // NFBItemIsMuted, which is only reached when a muted word or handle exists —
    // so hiding a thread did nothing on an empty word list.
    if (nfbThreadIsHidden(viewModel)) {
        return YES;
    }

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

// An accent wash over the first Tweet under an arriving batch. The anchor is the
// list's head, recaptured only when incoming data carries a different one; every
// other delivery keeps the boundary. Only the Following tab is eligible.

static const void* kNFBReadingAnchorIDKey = &kNFBReadingAnchorIDKey;
static const void* kNFBReadingAnchorPathKey = &kNFBReadingAnchorPathKey;
static const void* kNFBReadingMarkerViewKey = &kNFBReadingMarkerViewKey;
static const void* kNFBListViewKey = &kNFBListViewKey;
static const void* kNFBReadingTopAtCaptureKey = &kNFBReadingTopAtCaptureKey;
static const void* kNFBReadingRetiredKey = &kNFBReadingRetiredKey;
static const void* kNFBReadingMissCountKey = &kNFBReadingMissCountKey;

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

// The controller's list, found in its mounted view tree. Asking for -tableView or
// -collectionView invokes a lazy getter that builds a view never meant to exist,
// and on a collection view that raises.
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
    // Retained, not assigned: an assigned pointer is a raw address, and the check
    // above would message freed memory once the app releases the list. Holding it
    // costs one stale scroll view until the next lookup.
    objc_setAssociatedObject(dataViewController, kNFBListViewKey, found,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
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

// Anchors outlive the process. Which tab one belongs to is never recorded: each
// list looks for the first stored anchor it still contains, so a list holding none
// of them simply starts fresh.
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

// scribeSection is not declared in src/Headers. This shim is only a cast target:
// never instantiated, never messaged as a class, so no class symbol is
// referenced.
@interface NFBReadingScribeShim : NSObject
- (NSString*)scribeSection;
@end

// Identifies the Following tab by the timeline's own scribe section: For you
// reports "home", Following reports "latest". An allowlist on purpose, so a
// section that cannot be read denies the marker rather than granting it.
static BOOL NFBReadingIsFollowingTab(TFNItemsDataViewController* dataViewController) {
    if (![dataViewController respondsToSelector:@selector(scribeSection)]) {
        return NO;
    }
    NFBReadingScribeShim* shim = (NFBReadingScribeShim*)dataViewController;
    NSString* section = [shim scribeSection];
    if (![section isKindOfClass:[NSString class]]) {
        return NO;
    }
    return [section isEqualToString:@"latest"];
}

static BOOL NFBReadingMarkerAllowed(TFNItemsDataViewController* dataViewController) {
    return [BHTSettings boolForKey:@"reading_line"] &&
           NFBReadingIsHomeTimeline(dataViewController) &&
           ![objc_getAssociatedObject(dataViewController, kNFBReadingRetiredKey)
               boolValue] &&
           NFBReadingIsFollowingTab(dataViewController);
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

// The boundary is taken from the list as it stands, and only when incoming data
// has a different head. Deliveries that change nothing above only write the held
// boundary out.
static void NFBReadingCaptureAnchor(TFNItemsDataViewController* dataViewController,
                                    NSArray* incomingSections) {
    if (!NFBReadingMarkerAllowed(dataViewController)) {
        return;
    }
    // A list with nothing on screen has nothing to record.
    if (!NFBReadingTopVisibleEntryID(dataViewController).length) {
        return;
    }
    // A controller with no anchor is new or just relaunched, and claiming the head
    // would bury the one on disk. The stored anchors are tried first; with nothing
    // stored the head becomes the first boundary.
    if (!objc_getAssociatedObject(dataViewController, kNFBReadingAnchorIDKey)) {
        if (NFBReadingStoreRestore(dataViewController)) {
            return;
        }
        NSArray* stored =
            [[NSUserDefaults standardUserDefaults] arrayForKey:kNFBReadingStoreKey];
        if ([stored isKindOfClass:[NSArray class]] && stored.count &&
            NFBReadingItemCount(dataViewController.sections) < 10) {
            return;
        }
    } else {
        NSString* incomingHead = NFBReadingFirstEntryID(incomingSections);
        NSString* currentHead =
            NFBReadingFirstEntryID(dataViewController.sections);
        if (!incomingHead.length || !currentHead.length ||
            [incomingHead isEqualToString:currentHead]) {
            // Nothing arrives above: the boundary stays, and is written out
            // as it is.
            NSString* held =
                objc_getAssociatedObject(dataViewController, kNFBReadingAnchorIDKey);
            NFBReadingStoreRemember(
                held, held,
                objc_getAssociatedObject(dataViewController,
                                         kNFBReadingTopAtCaptureKey));
            return;
        }
    }
    NSString* listHead = NFBReadingFirstEntryID(dataViewController.sections);
    if (!listHead.length) {
        return;
    }
    // The list's first Tweet is the boundary: the batch lands above it, and the
    // wash falls on the first Tweet under that batch.
    NSString* previousAnchor =
        objc_getAssociatedObject(dataViewController, kNFBReadingAnchorIDKey);
    objc_setAssociatedObject(dataViewController, kNFBReadingAnchorIDKey, listHead,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(dataViewController, kNFBReadingTopAtCaptureKey,
                             listHead, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NFBReadingStoreRemember(previousAnchor, listHead, listHead);
}

// One row's true geometry. The rendered cell is authoritative on screen, since
// data sections and table rows do not always map one-to-one. Off screen the
// computed rect only decides visibility.
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

// Places or hides the marker for the current data. The row rect is content-space,
// so the wash scrolls with the feed. It sits above the cell at low alpha, since an
// opaque cell would hide it entirely.
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
        // A replaced list has a new first item as well as a missing anchor; an
        // anchor that fell out of a list whose head is unchanged is a loading
        // phase. Two consecutive absent passes retire the marker for the session.
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
    // An anchor that is still the first row has nothing above it to mark.
    NSString* topNow = NFBReadingFirstEntryID(dataViewController.sections);
    if (!topNow.length || [anchor isEqualToString:topNow]) {
        // The layout tick draws from the cached path: an anchor with nothing
        // to mark leaves none behind.
        objc_setAssociatedObject(table, kNFBReadingAnchorPathKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
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

// Self-sizing rows shift their rects as cells realise, so the tick keeps the wash
// on its row from the cached index path. A row with no measurable rect at first
// placement is retried here.
static void NFBReadingLayoutTick(UIScrollView* scrollView) {
    UIView* marker = objc_getAssociatedObject(scrollView, kNFBReadingMarkerViewKey);
    if (!marker) {
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
                            NFBReadingCaptureAnchor(controller, nil);
                        }
                    }];
    });
    [gNFBReadingControllers addObject:dataViewController];
}

// MARK: - Language filter

// A Tweet carries the language of its original text, and the kept set lists the
// selected ones; empty means off. A Tweet whose language cannot be detected always
// passes, so image-only posts are never lost.

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

    // Hidden conversations open this pass like any other option: without them
    // here, a reader with no other filter on kept every hidden thread, because
    // the whole loop below was skipped.
    BOOL hasHiddenThreads = NFBHiddenThreads().count > 0;

    if (!hideWhoToFollow && !hidePrompts && !hideTopics && !hideTopicsToFollow &&
        !hideVerified && !inConversation && !keptLanguages.count && !hasHiddenThreads) {
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

// Every data view controller currently on screen, asked to set again what it
// already has.
static void NFBReapplyInHierarchy(UIViewController* controller) {
    if (!controller) {
        return;
    }
    if ([controller isKindOfClass:%c(TFNItemsDataViewController)] &&
        [controller respondsToSelector:@selector(sections)] &&
        [controller respondsToSelector:@selector(setSections:restoreScrollPosition:)]) {
        id sections = ((id (*)(id, SEL))objc_msgSend)(controller, @selector(sections));
        if ([sections isKindOfClass:[NSArray class]]) {
            ((void (*)(id, SEL, id, BOOL))objc_msgSend)(
                controller, @selector(setSections:restoreScrollPosition:), sections, YES);
        }
    }
    for (UIViewController* child in controller.childViewControllers) {
        NFBReapplyInHierarchy(child);
    }
    NFBReapplyInHierarchy(controller.presentedViewController);
}

// Re-applies the filter to what is already on screen. It runs when sections are
// handed to the controller, not when the table draws, so the sections are set
// again with what the controller already holds.
void nfbReapplyTimelineFilter(void) {
    for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }
        for (UIWindow* window in ((UIWindowScene*)scene).windows) {
            NFBReapplyInHierarchy(window.rootViewController);
        }
    }
}

%hook TFNItemsDataViewController

- (void)setSections:(NSArray*)sections restoreScrollPosition:(BOOL)restoreScrollPosition {
    BOOL keepPlace = restoreScrollPosition;
    NSArray* filtered = FilteredTimelineSections(self, sections);
    if (NFBReadingIsHomeTimeline(self)) {
        // Every home controller is tracked, the algorithmic tab included: tracking is pure
        // registration, and each reading action gates itself on MarkerAllowed.
        // The badge pass resolves its controller from this registry.
        NFBReadingTrack(self);
        if (NFBReadingMarkerAllowed(self)) {
            NFBReadingCaptureAnchor(self, filtered);
        }
        // Twitter's own restore flag, forced on the home timeline so a reload
        // keeps the reading position instead of jumping to the top.
        keepPlace = YES;
    }
    %orig(filtered, keepPlace);
    NFBReadingRescanSoon(self);
}

- (void)updateSections:(NSArray*)sections
    reconfigureItemIdentifiers:(NSArray*)identifiers
              withRowAnimation:(long long)animation
                    completion:(id)completion {
    NSArray* filtered = FilteredTimelineSections(self, sections);
    if (NFBReadingMarkerAllowed(self)) {
        NFBReadingCaptureAnchor(self, filtered);
    }
    %orig(filtered, identifiers, animation, completion);
    NFBReadingRescanSoon(self);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    NFBReadingRescanSoon(self);
}

- (void)viewWillDisappear:(BOOL)animated {
    NFBReadingCaptureAnchor(self, nil);
    %orig;
}

%end

// MARK: - Poll results before voting

// The counts travel with the card data before a vote, so the percentage is
// appended to each option's label. The choice count is not derived from the card
// name, since image polls carry none; the per-choice bindings are probed instead.

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
