//
//  Timeline.x
//  PrimeFreeBird
//

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
// compiler when it's called through an id handle, which is exactly what broke
// the previous build.
static void nfbApplyFleetVisibility(UIView* view) {
    // Restore what we hid: without this the bar stays gone after the option is
    // switched back off, until the app is relaunched. We only ever restore a
    // view WE hid, so Twitter's own hiding is never overridden.
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
// Native Twitter never shows a band under its bars — he checked against a
// clean IPA. The band exists only because this tweak makes the app opt INTO
// the iOS 26 design (AppLifecycle.x lies about UIDesignRequiresCompatibility
// so Liquid Glass turns on), and iOS 26 draws a scroll edge effect under every
// bar. So it appears on the timeline, on search, everywhere — which is exactly
// what he observed.
//
// The option therefore switches that effect off wherever it appears, giving
// back the stock behaviour while keeping Liquid Glass everywhere else. Earlier
// versions only targeted the home timeline's scroll view, which is why they
// never caught it.

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
// we hid ourselves.
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
// we care about are never presented modally, so this costs us nothing.
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

// A scroll edge effect's style is an OBJECT, not an enum. That is not a guess:
// an earlier attempt passed the integer 2 to setStyle:, UIKit retained it, and
// the crash report shows objc_retain dereferencing address 0x2. So the hard
// style is asked of the style's own class rather than invented — every no-
// argument class method returning an object is examined, and the one whose name
// carries "hard" is used, after checking the value really is a style. Nothing is
// assumed about numbering, ordering, or naming beyond that one word, and if
// nothing matches the screen is left exactly as it was.
static id nfbHardEdgeStyleLike(id currentStyle) {
    if (!currentStyle) {
        return nil;
    }
    Class styleClass = [currentStyle class];
    unsigned int count = 0;
    Method* methods = class_copyMethodList(object_getClass(styleClass), &count);
    if (!methods) {
        return nil;
    }
    id found = nil;
    for (unsigned int i = 0; i < count && !found; i++) {
        if (method_getNumberOfArguments(methods[i]) != 2) {
            continue;   // on ne veut que les +foo, sans argument
        }
        char returnType[8] = {0};
        method_getReturnType(methods[i], returnType, sizeof(returnType));
        if (returnType[0] != '@') {
            continue;
        }
        SEL selector = method_getName(methods[i]);
        NSString* name = [NSStringFromSelector(selector) lowercaseString];
        if (![name hasPrefix:@"hard"]) {
            continue;
        }
        id candidate = ((id (*)(id, SEL))objc_msgSend)(styleClass, selector);
        if ([candidate isKindOfClass:styleClass]) {
            found = candidate;
        }
    }
    free(methods);
    return found;
}

// The view tree finally names it, and it was never where I was looking. The
// frosted strip is not drawn by the navigation bar: _UIBarBackground reads as
// #000000 at zero alpha, so it paints nothing at all. What draws it lives
// INSIDE the table, as two of its own subviews — a UIKit.ScrollEdgeEffectView
// and its backdrop, both {0, 0, 440, 94}.
//
// Ninety-four points. The navigation bar ends at 128, and the search field ends
// with it. The effect is thirty-four points short, and that is the whole
// problem. It is also why the boundary sat in the same place through every
// attempt: none of them ever touched these two views.
//
// Stretching them to the bar's own bottom edge reproduces the strip above
// exactly — same view, same material, same tone — because it IS the view that
// draws the part it has to match. Nothing is added and nothing is matched by
// hand. The height is converted from the bar rather than written down, so it
// holds on any device and through rotation.
// Nineteen attempts have gone at the strip from the effect's side — styling
// it, stretching it, clamping every geometry channel it has — and the drawn
// result never followed. His read on it replaces all of that: the bar itself
// is the one input every derived number follows, so the bar is made taller and
// iOS is left to redo its own arithmetic. The 34 comes from his view tree:
// the field ends at 128, the effect stops at 94.
static const CGFloat kNFBSettingsBarExtraHeight = 34.0;

static BOOL nfbBarBelongsToSettingsSheet(UINavigationBar* bar) {
    UIResponder* responder = bar;
    while ((responder = responder.nextResponder)) {
        if ([responder isKindOfClass:[UINavigationController class]]) {
            UINavigationController* navigation = (UINavigationController*)responder;
            return navigation.presentingViewController != nil &&
                   nfbControllerIsSettingsRoot(navigation.viewControllers.firstObject);
        }
    }
    return NO;
}

static const void* kNFBEdgeStyleWritesKey = &kNFBEdgeStyleWritesKey;

// Two things keep this safe. The setter is only ever called once the runtime has
// confirmed it takes an object — the check that was missing when this crashed —
// and the writes are capped, so no chain of write, relayout, write can run away
// even if the value refuses to stick.
//
// The cap is carried by the EFFECT, not by the scroll view. Counting on the
// scroll view was what undid the whole thing when the header widened: the extra
// layout passes that the safe-area change triggers spent the budget, iOS then
// handed the scroll view a fresh effect object, and there was nothing left to
// style it with — the bar quietly went back to its gradient. A new object is a
// new subject and gets its own budget; a runaway loop still hammers one object
// and is still stopped after three.
static void nfbApplyHardEdgeIfSettingsRoot(UIScrollView* scrollView) {
    if (![scrollView respondsToSelector:@selector(topEdgeEffect)]) {
        return;   // avant iOS 26 : rien à faire
    }
    UIViewController* owner = nfbOwningController(scrollView);
    if (!nfbControllerIsSettingsRoot(owner)) {
        return;
    }
    id effect = ((id (*)(id, SEL))objc_msgSend)(scrollView, @selector(topEdgeEffect));
    if (!effect ||
        ![effect respondsToSelector:@selector(style)] ||
        ![effect respondsToSelector:@selector(setStyle:)]) {
        return;
    }
    NSNumber* writes = objc_getAssociatedObject(effect, kNFBEdgeStyleWritesKey);
    if (writes.integerValue >= 3) {
        return;
    }
    // respondsToSelector: proves the selector exists, never what it expects.
    NSMethodSignature* getter = [effect methodSignatureForSelector:@selector(style)];
    NSMethodSignature* setter = [effect methodSignatureForSelector:@selector(setStyle:)];
    if (!getter || !setter || setter.numberOfArguments != 3) {
        return;
    }
    const char* returnType = getter.methodReturnType;
    const char* argumentType = [setter getArgumentTypeAtIndex:2];
    if (!returnType || returnType[0] != '@' || !argumentType || argumentType[0] != '@') {
        return;
    }
    id current = ((id (*)(id, SEL))objc_msgSend)(effect, @selector(style));
    id hard = nfbHardEdgeStyleLike(current);
    if (!hard || hard == current) {
        return;
    }
    objc_setAssociatedObject(effect, kNFBEdgeStyleWritesKey,
                             @(writes.integerValue + 1),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    ((void (*)(id, SEL, id))objc_msgSend)(effect, @selector(setStyle:), hard);
}

- (void)didMoveToWindow {
    %orig;

    @try {
        if (!self.window) {
            return;
        }
        if (nfbScrollViewIsModal(self)) {
            nfbApplyHardEdgeIfSettingsRoot(self);
            return;
        }
        nfbApplyEdgeEffect(self, nfbEdgeHideEnabled());
    } @catch (id exception) {
    }
}

// Checked on every layout of every scroll view, on purpose. iOS re-enables the
// effect whenever a bar reconfigures — changing tab, coming back to a screen —
// and acting only on views we had already marked left Search untouched and the
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
        if (!marked && nfbScrollViewIsModal(self)) {
            nfbApplyHardEdgeIfSettingsRoot(self);
            return;
        }
        if (!marked && !hide) {
            return;
        }
        nfbApplyEdgeEffect(self, hide);
    } @catch (id exception) {
    }
}

%end

%hook UINavigationBar

- (CGSize)sizeThatFits:(CGSize)size {
    CGSize fitted = %orig;

    @try {
        if (nfbBarBelongsToSettingsSheet(self)) {
            fitted.height += kNFBSettingsBarExtraHeight;
        }
    } @catch (id exception) {
    }
    return fitted;
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

// Twitter's *ByCurrentAccountState fields are a tri-state (0 unknown, 1 yes,
// 2 no); if follows still get hidden, flip this to the value logged for a
// known-followed account.
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

    if (!hideWhoToFollow && !hidePrompts && !hideTopics && !hideTopicsToFollow &&
        !hideVerified && !inConversation) {
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
                                               authorRepliedToUserIDs)) {
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
    %orig(FilteredTimelineSections(self, sections), restoreScrollPosition);
}

- (void)updateSections:(NSArray*)sections
    reconfigureItemIdentifiers:(NSArray*)identifiers
              withRowAnimation:(long long)animation
                    completion:(id)completion {
    %orig(FilteredTimelineSections(self, sections), identifiers, animation, completion);
}

%end

// MARK: - Poll results before voting
//
// Twitter hides the tallies until you have voted. The counts travel with the
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
