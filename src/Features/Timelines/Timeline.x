// Timeline options: hidden custom timelines, full-frame images, no Spaces bar, the
// scroll edge effect, hidden prompts, muted words, the reading marker and the
// language filter.

#import <QuartzCore/QuartzCore.h>

#import "Support/HookHelpers.h"
#import "Debug/PFBDebugger.h"

// Declared once at file scope: two distant passes read the hidden-thread
// list, and a block-scope extern is invisible to the second one.
extern NSArray<NSDictionary*>* PFBHiddenThreads(void);

// MARK: - Hide custom timelines

static __weak NSObject* PinnedTimelinesRepository;
static NSArray* LastPinnedTimelineModels;
static BOOL PinnedTimelinesWriteBypass = NO;

// Applies the toggle without relaunching. The unchanged pinned list is rewritten
// purely to republish, since updatePinnedTimelines: persists server-side; the
// delegate hook below swaps in the empty list on the way through.
void PFBApplyHideCustomTimelinesSetting(void) {
    NSObject* repository = PinnedTimelinesRepository;
    if (!repository) {
        return;
    }

    if ([PFBSettings boolForKey:@"hide_custom_timelines"]) {
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
    BOOL hide = [PFBSettings boolForKey:@"hide_custom_timelines"];
    if (hide && models.count > 0) {
        PFBCOMPAT_ACTION(PFBCompat_hide_custom_timelines, @"pinned tabs hidden");
    }

    %orig(repository, hide ? @[] : models);
    SyncHomeAddTabButton(self, hide);
}

- (id)tfn_navigationBarAccessoryView {
    id accessoryView = %orig;
    SyncHomeAddTabButton(self, [PFBSettings boolForKey:@"hide_custom_timelines"]);
    return accessoryView;
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    SyncHomeAddTabButton(self, [PFBSettings boolForKey:@"hide_custom_timelines"]);
}

%end

// While hiding, the overridden pinned-tabs feature switches make the app compute
// an empty pinned list; freeze writes so it can't overwrite the real tabs.
%hook _TtC32TwitterHomeFeatureImplementation31CachedPinnedTimelinesRepository

- (void)updatePinnedTimelines:(id)timelines {
    if (!PinnedTimelinesWriteBypass && [PFBSettings boolForKey:@"hide_custom_timelines"]) {
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
        if ([PFBSettings boolForKey:@"force_tweet_full_frame"]) {
            PFBCOMPAT_ACTION(PFBCompat_force_tweet_full_frame, @"image shown uncropped");
            return 1;
        }
        PFBCOMPAT_OBSERVE(PFBCompat_force_tweet_full_frame, @"read by Twitter");
        return %orig;
    }

    return %orig;
}

%end

// MARK: - Hide the Spaces bar

// The bar is still the repurposed Fleets line; both home timeline implementations
// share this visibility gate, re-evaluated on every content or settings update.
%hook T1FleetLineHeaderController

- (BOOL)_t1_shouldShowFleetLine {
    if ([PFBSettings boolForKey:@"hide_spaces"]) {
        PFBCOMPAT_ACTION(PFBCompat_hide_spaces, @"Spaces bar hidden");
        return NO;
    }
    PFBCOMPAT_OBSERVE(PFBCompat_hide_spaces, @"Spaces bar asked");

    return %orig;
}

%end

// The header hook removes the content, but the T1FleetLineView itself keeps
// its height and blurred background. Collapse the view to zero as well.
static const void* kPFBFleetHiddenKey = &kPFBFleetHiddenKey;

// Plain C rather than a %new method: a %new selector isn't known to the
// compiler when called through an id handle.
static void pfbApplyFleetVisibility(UIView* view) {
    // Restore what the tweak hid: without this the bar stays gone after the option is
    // switched back off, until the app is relaunched. The tweak only ever restores a
    // view the tweak hid, so Twitter's own hiding is never overridden.
    BOOL hide = [PFBSettings boolForKey:@"hide_spaces"];
    BOOL hiddenByUs = objc_getAssociatedObject(view, kPFBFleetHiddenKey) != nil;
    if (hide) {
        if (!view.hidden) {
            view.hidden = YES;
        }
        if (!hiddenByUs) {
            objc_setAssociatedObject(view, kPFBFleetHiddenKey, @YES,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    } else if (hiddenByUs) {
        view.hidden = NO;
        objc_setAssociatedObject(view, kPFBFleetHiddenKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

%hook T1FleetLineView

- (void)didMoveToWindow {
    %orig;
    pfbApplyFleetVisibility((UIView*)self);
}

// Also on every layout pass: coming back from the settings screen doesn't
// always move the view to a new window, and the bar would stay gone until the
// app was relaunched.
- (void)layoutSubviews {
    %orig;
    pfbApplyFleetVisibility((UIView*)self);
}

- (CGSize)intrinsicContentSize {
    if ([PFBSettings boolForKey:@"hide_spaces"]) {
        return CGSizeZero;
    }
    return %orig;
}

- (CGSize)sizeThatFits:(CGSize)size {
    if ([PFBSettings boolForKey:@"hide_spaces"]) {
        return CGSizeZero;
    }
    return %orig;
}

%end

// MARK: - Scroll edge effect

// Opting back into the iOS 26 design makes iOS draw a scroll edge effect under
// every bar. This option switches that effect off wherever it appears.

static void PFBReadingLayoutTick(UIScrollView* scrollView);

static const void* kPFBEdgeMarkKey = &kPFBEdgeMarkKey;

// The option is cached: reading NSUserDefaults on every layout pass of every
// scroll view in the app would be far too costly, and a refresh twice a second
// is plenty for a settings toggle.
static BOOL gPFBEdgeHide = NO;
static CFAbsoluteTime gPFBEdgeChecked = 0;

static BOOL pfbEdgeHideEnabled(void) {
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (now - gPFBEdgeChecked > 0.5) {
        gPFBEdgeChecked = now;
        gPFBEdgeHide = [PFBSettings boolForKey:@"hide_scroll_edge_blur"];
    }
    return gPFBEdgeHide;
}

// Applies (or lifts) the effect on one scroll view, and only ever lifts what
// the tweak hid ourselves.
static void pfbApplyEdgeEffect(UIScrollView* scrollView, BOOL hide) {
    if (![scrollView respondsToSelector:@selector(topEdgeEffect)]) {
        return;   // nothing to do before iOS 26
    }
    id effect = ((id (*)(id, SEL))objc_msgSend)(scrollView, @selector(topEdgeEffect));
    if (![effect respondsToSelector:@selector(setHidden:)] ||
        ![effect respondsToSelector:@selector(isHidden)]) {
        return;
    }
    BOOL alreadyHidden = ((BOOL (*)(id, SEL))objc_msgSend)(effect, @selector(isHidden));
    if (!hide) {
        PFBCOMPAT_OBSERVE(PFBCompat_hide_scroll_edge_blur, @"edge blur found");
    }
    if (alreadyHidden == hide) {
        return;   // nothing to do: the common case, and the cheapest
    }
    ((void (*)(id, SEL, BOOL))objc_msgSend)(effect, @selector(setHidden:), hide);
    if (hide) {
        PFBCOMPAT_ACTION(PFBCompat_hide_scroll_edge_blur, @"edge blur hidden");
    }
    objc_setAssociatedObject(scrollView, kPFBEdgeMarkKey, hide ? @YES : nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%hook UIScrollView

// Modal screens are left alone. Hiding the effect on Twitter's own settings
// sheet broke its content inset — the list slid up under the title. The tabs
// the tweak cares about are never presented modally, so this costs nothing.
static UIViewController* pfbOwningController(UIView* view) {
    UIResponder* responder = view;
    while ((responder = responder.nextResponder)) {
        if ([responder isKindOfClass:[UIViewController class]]) {
            return (UIViewController*)responder;
        }
    }
    return nil;
}

static BOOL pfbScrollViewIsModal(UIScrollView* scrollView) {
    UIViewController* owner = pfbOwningController(scrollView);
    return owner != nil && owner.presentingViewController != nil;
}


- (void)didMoveToWindow {
    %orig;

    @try {
        if (self.window && !pfbScrollViewIsModal(self)) {
            pfbApplyEdgeEffect(self, pfbEdgeHideEnabled());
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
        BOOL marked = objc_getAssociatedObject(self, kPFBEdgeMarkKey) != nil;
        BOOL hide = pfbEdgeHideEnabled();
        PFBReadingLayoutTick(self);
        if (!marked && (!hide || pfbScrollViewIsModal(self))) {
            return;
        }
        pfbApplyEdgeEffect(self, hide);
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
        PFBReadingLayoutTick(self);
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

// Tweets a topic brought in carry Twitter's own label for it, "From <topic>" in
// the app's language, as their context banner.
static BOOL ItemIsTopicPost(id viewModel) {
    static NSString* prefix;
    static NSString* suffix;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      NSString* path = [NSBundle.mainBundle pathForResource:@"TwitterTweetAnatomy_TwitterTweetAnatomyStrings"
                                                     ofType:@"bundle"];
      NSString* format = [[NSBundle bundleWithPath:path] localizedStringForKey:@"FROM_TAG_TOPIC_SOCIAL_CONTEXT_LABEL_FORMAT"
                                                                         value:nil
                                                                         table:nil];
      NSRange slot = [format rangeOfString:@"%1$@"];
      if (format && slot.location != NSNotFound) {
          prefix = [format substringToIndex:slot.location];
          suffix = [format substringFromIndex:NSMaxRange(slot)];
      }
    });
    SEL selector = NSSelectorFromString(@"socialContextBannerText");
    if (prefix.length == 0 || ![viewModel respondsToSelector:selector]) {
        return NO;
    }
    id banner = ((id (*)(id, SEL))objc_msgSend)(viewModel, selector);
    NSString* text = [banner isKindOfClass:[NSAttributedString class]] ? [(NSAttributedString*)banner string]
                     : [banner isKindOfClass:[NSString class]]         ? banner
                                                                       : nil;
    return text.length > prefix.length + suffix.length && [text hasPrefix:prefix] && [text hasSuffix:suffix];
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

static BOOL PFBShouldHideVerifiedItem(id viewModel, BOOL inConversation,
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
// pfbRefreshMutedWords() and the signature below invalidates the memo. Text and
// handle are read through several known selectors, so a rename means no match.

static NSArray<NSString*>* gPFBMutedWords = nil;      // lowercased, no "@"
static NSArray<NSString*>* gPFBMutedHandles = nil;    // lowercased, no "@"
static BOOL gPFBMutedWholeWords = YES;
static BOOL gPFBMutedInConversations = YES;
static BOOL gPFBMutedSkipFollowing = YES;
static BOOL gPFBMutedIncludeReposts = NO;
static NSInteger gPFBMutedHiddenToday = 0;
static NSInteger gPFBMutedFlushCounter = 0;
static NSString* gPFBMutedCountDay = nil;
static NSUInteger gPFBMutedSignature = 0;
static BOOL gPFBMutedLoaded = NO;

void pfbRefreshMutedWords(void) {
    NSUserDefaults* d = [NSUserDefaults standardUserDefaults];
    NSArray* raw = [d arrayForKey:@"pfb_muted_words"] ?: @[];
    // term -> expiry timestamp; a missing entry means "forever".
    NSDictionary* expiry = [d dictionaryForKey:@"pfb_muted_expiry"] ?: @{};
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
    gPFBMutedWords = words;
    gPFBMutedHandles = handles;
    gPFBMutedWholeWords =
        ([d objectForKey:@"pfb_muted_whole_words"] == nil) ? YES
                                                           : [d boolForKey:@"pfb_muted_whole_words"];
    gPFBMutedInConversations =
        ([d objectForKey:@"pfb_muted_in_conversations"] == nil)
            ? YES
            : [d boolForKey:@"pfb_muted_in_conversations"];
    gPFBMutedSkipFollowing =
        ([d objectForKey:@"pfb_muted_skip_following"] == nil)
            ? YES
            : [d boolForKey:@"pfb_muted_skip_following"];
    gPFBMutedIncludeReposts = [d boolForKey:@"pfb_muted_include_reposts"];

    // Daily counter: kept in memory and flushed sparingly, so the hot path
    // never touches NSUserDefaults.
    NSString* today = [NSString stringWithFormat:@"%ld",
                                                 (long)(now / 86400.0)];
    NSString* storedDay = [d stringForKey:@"pfb_muted_count_day"];
    if ([storedDay isEqualToString:today]) {
        gPFBMutedHiddenToday = [d integerForKey:@"pfb_muted_hidden_count"];
    } else {
        gPFBMutedHiddenToday = 0;
        [d setObject:today forKey:@"pfb_muted_count_day"];
        [d setInteger:0 forKey:@"pfb_muted_hidden_count"];
    }
    gPFBMutedCountDay = today;

    // Hidden conversations share this memo: without them in the signature, the
    // timeline keeps its previous verdict and a hidden thread only vanishes on
    // the next reload.
    signature = signature * 31 + PFBHiddenThreads().count;
    gPFBMutedSignature = signature * 31 + (gPFBMutedWholeWords ? 2 : 1) +
                         (gPFBMutedSkipFollowing ? 4 : 0) +
                         (gPFBMutedIncludeReposts ? 8 : 0);
    gPFBMutedLoaded = YES;
}

static void PFBEnsureMutedLoaded(void) {
    if (!gPFBMutedLoaded) { pfbRefreshMutedWords(); }
}

// First non-empty string among a list of selectors, on the object itself and
// then on its status/tweet child.
static NSString* PFBStringFromSelectors(id object, BOOL descend) {
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
        NSString* text = PFBStringFromSelectors(child, NO);
        if (text.length) { return text; }
    }
    return nil;
}

static NSString* PFBHandleFromSelectors(id object, BOOL descend) {
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
        NSString* handle = PFBHandleFromSelectors(child, NO);
        if (handle.length) { return handle; }
    }
    return nil;
}

// Whole-word matching without a regex: find the needle, then require that
// neither neighbouring character is alphanumeric.
static BOOL PFBHaystackContainsTerm(NSString* haystack, NSString* term, BOOL wholeWords) {
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
NSInteger pfbMutedHiddenCountToday(void) {
    PFBEnsureMutedLoaded();
    return gPFBMutedHiddenToday;
}

static void PFBNoteMutedHidden(void) {
    PFBCOMPAT_ACTION(PFBCompat_muted_words, @"muted post hidden");
    gPFBMutedHiddenToday++;
    // Persist every so often rather than on every hidden post.
    if (++gPFBMutedFlushCounter >= 25) {
        gPFBMutedFlushCounter = 0;
        NSUserDefaults* d = [NSUserDefaults standardUserDefaults];
        [d setInteger:gPFBMutedHiddenToday forKey:@"pfb_muted_hidden_count"];
        if (gPFBMutedCountDay) {
            [d setObject:gPFBMutedCountDay forKey:@"pfb_muted_count_day"];
        }
    }
}

// "Do you follow this author?" — several accessors exist depending on the
// model, so try them in turn and treat an unknown answer as "not following"
// (the safe side: the filter still applies).
static BOOL PFBAuthorIsFollowed(id viewModel) {
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

static BOOL PFBObjectMatchesMutedRule(id object) {
    if (!object) { return NO; }
    if (gPFBMutedHandles.count) {
        NSString* handle = PFBHandleFromSelectors(object, YES);
        if (handle.length) {
            NSString* lower = [handle lowercaseString];
            if ([lower hasPrefix:@"@"]) { lower = [lower substringFromIndex:1]; }
            for (NSString* muted in gPFBMutedHandles) {
                if ([lower isEqualToString:muted]) { return YES; }
            }
        }
    }
    if (gPFBMutedWords.count) {
        NSString* text = PFBStringFromSelectors(object, YES);
        if (text.length) {
            NSString* lower = [text lowercaseString];
            for (NSString* term in gPFBMutedWords) {
                if (PFBHaystackContainsTerm(lower, term, gPFBMutedWholeWords)) {
                    return YES;
                }
            }
        }
    }
    return NO;
}

// Hidden conversations live in HiddenThreads.x, which owns the registry and
// the button that fills it.
extern BOOL pfbThreadIsHidden(id viewModel);

static BOOL PFBItemIsMuted(id viewModel) {
    if (gPFBMutedSkipFollowing && PFBAuthorIsFollowed(viewModel)) {
        return NO;
    }
    if (PFBObjectMatchesMutedRule(viewModel)) {
        return YES;
    }
    if (gPFBMutedIncludeReposts &&
        [viewModel respondsToSelector:@selector(retweetedStatus)]) {
        id reposted =
            ((id (*)(id, SEL))objc_msgSend)(viewModel, @selector(retweetedStatus));
        if (PFBObjectMatchesMutedRule(reposted)) {
            return YES;
        }
    }
    return NO;
}

// The object a getter returns, read only when its signature says it returns one.
static id PFBTimelineObject(id object, NSString* name) {
    SEL selector = NSSelectorFromString(name);
    if (![object respondsToSelector:selector]) {
        return nil;
    }
    NSMethodSignature* signature = [object methodSignatureForSelector:selector];
    if (signature.numberOfArguments != 2 || signature.methodReturnType[0] != '@') {
        return nil;
    }
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

static NSString* gPFBFirstRetweet;

// The first retweet of the launch, logged once and kept, with each link of the chain
// it reached, for the path tour to report.
static void PFBLogFirstRetweet(id author, id relationship, char type, NSInteger value) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString* state = (type == 'q' || type == 'l')
                              ? [NSString stringWithFormat:@"%ld", (long)value]
                              : (type ? [NSString stringWithFormat:@"typed '%c'", type] : @"missing");
        gPFBFirstRetweet = [NSString
            stringWithFormat:@"author %@ · relationship %@ · blocking state %@",
                             author ? NSStringFromClass([author class]) : @"none",
                             relationship ? NSStringFromClass([relationship class]) : @"none", state];
        PFBDebugLog(@"[filter] first retweet: %@", gPFBFirstRetweet);
    });
}

// What the blocked-retweet filter saw first this launch; nil until a retweet comes by.
NSString* PFBFirstRetweetSummary(void) {
    return gPFBFirstRetweet;
}

// Whether a retweet's original author blocks this account (state 1). *checked is
// set once the whole chain answered, so a missing link is told from "not blocking".
static BOOL PFBRetweetAuthorBlocksAccount(id viewModel, BOOL* checked) {
    *checked = NO;
    if (!ItemRespondsAndInvokesBOOL(viewModel, NSSelectorFromString(@"isRetweet"))) {
        return NO;
    }
    id author = PFBTimelineObject(viewModel, @"representedFromUser");
    id relationship = PFBTimelineObject(author, @"relationship");
    SEL state = NSSelectorFromString(@"blockingCurrentAccountState");
    char type = [relationship respondsToSelector:state]
                    ? [relationship methodSignatureForSelector:state].methodReturnType[0]
                    : 0;
    if (type != 'q' && type != 'l') {
        PFBLogFirstRetweet(author, relationship, type, 0);
        return NO;
    }
    *checked = YES;
    NSInteger value = ((NSInteger (*)(id, SEL))objc_msgSend)(relationship, state);
    PFBLogFirstRetweet(author, relationship, type, value);
    return value == 1;
}

static BOOL ShouldHideTimelineItem(id item, BOOL hideWhoToFollow, BOOL hidePrompts,
                                   BOOL hideTopics, BOOL hideTopicsToFollow,
                                   BOOL hideVerified, BOOL hideBlockedRetweets,
                                   BOOL inConversation, BOOL inProfile,
                                   long long conversationRootUserID,
                                   NSSet<NSNumber*>* authorRepliedToUserIDs) {
    id viewModel = PFBUnwrapDataViewItem(item);
    NSString* className = NSStringFromClass([viewModel classForCoder]);

    // Hidden conversations are their own filter: they were tested inside
    // PFBItemIsMuted, which is only reached when a muted word or handle exists —
    // so hiding a thread did nothing on an empty word list.
    if (pfbThreadIsHidden(viewModel)) {
        PFBCOMPAT_ACTION(PFBCompat_hide_threads, @"conversation hidden");
        return YES;
    }

    // Reached with or without a muted word: the filter's path, proven either way.
    PFBCOMPAT_OBSERVE(PFBCompat_muted_words, @"timeline filter reached");
    if ((gPFBMutedWords.count || gPFBMutedHandles.count) &&
        (!inConversation || gPFBMutedInConversations) && PFBItemIsMuted(viewModel)) {
        PFBNoteMutedHidden();
        return YES;
    }

    if (hideVerified && PFBShouldHideVerifiedItem(viewModel, inConversation, conversationRootUserID,
                                                 authorRepliedToUserIDs)) {
        PFBCOMPAT_ACTION(PFBCompat_hide_verified_tweets, @"verified Tweet hidden");
        return YES;
    }

    if (hideBlockedRetweets || PFBCompatNeedsObservation(PFBCompat_hide_blocked_retweets)) {
        BOOL checked = NO;
        BOOL blocking = PFBRetweetAuthorBlocksAccount(viewModel, &checked);
        if (checked) {
            PFBCOMPAT_OBSERVE(PFBCompat_hide_blocked_retweets, @"retweet checked");
        }
        if (blocking && hideBlockedRetweets) {
            PFBCOMPAT_ACTION(PFBCompat_hide_blocked_retweets, @"blocked retweet hidden");
            return YES;
        }
    }

    if (!hidePrompts && [className isEqualToString:@"TwitterURT.URTTimelinePromptViewModel"]) {
        PFBCOMPAT_OBSERVE(PFBCompat_hide_timeline_prompts, @"prompt found");
    }
    if (!hideTopics && ItemIsTopicPost(viewModel)) {
        PFBCOMPAT_OBSERVE(PFBCompat_hide_topics, @"topic label found");
    }
    if (!hideTopicsToFollow && [ItemScribeComponent(viewModel) isEqualToString:@"suggest_topics_module"]) {
        PFBCOMPAT_OBSERVE(PFBCompat_hide_topics_to_follow, @"topic suggestions found");
    }
    if (!hideVerified && PFBCompatNeedsObservation(PFBCompat_hide_verified_tweets) &&
        PFBShouldHideVerifiedItem(viewModel, inConversation, conversationRootUserID,
                                                 authorRepliedToUserIDs)) {
        PFBCOMPAT_OBSERVE(PFBCompat_hide_verified_tweets, @"verified Tweet found");
    }
    if (hidePrompts && [className isEqualToString:@"TwitterURT.URTTimelinePromptViewModel"]) {
        PFBCOMPAT_ACTION(PFBCompat_hide_timeline_prompts, @"prompt hidden");
        return YES;
    }

    if (hideTopics && ItemIsTopicPost(viewModel)) {
        PFBCOMPAT_ACTION(PFBCompat_hide_topics, @"topic Tweet hidden");
        return YES;
    }

    // Topic suggestions arrive as a module marked like Who to follow's.
    if (hideTopicsToFollow && [ItemScribeComponent(viewModel) isEqualToString:@"suggest_topics_module"]) {
        PFBCOMPAT_ACTION(PFBCompat_hide_topics_to_follow, @"topic suggestions hidden");
        return YES;
    }

    if (hideWhoToFollow && [ItemScribeComponent(viewModel)
                               isEqualToString:@"suggest_who_to_follow"]) {
        PFBCOMPAT_ACTION(PFBCompat_hide_who_to_follow, @"who-to-follow module hidden");
        return YES;
    }

    if (hideWhoToFollow && inProfile &&
        [className isEqualToString:@"T1TwitterSwift.URTTimelineCarouselViewModel"]) {
        PFBCOMPAT_ACTION(PFBCompat_hide_who_to_follow, @"profile suggestions hidden");
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
        PFBCOMPAT_ACTION(PFBCompat_hide_who_to_follow, @"who-to-follow entry hidden");
        return YES;
    }

    return NO;
}

// More efficient than calling ShouldHideTimelineItem() repeatedly, which slows
// the app down a lot when hide-verified scans every reply.
static BOOL MemoizedShouldHideTimelineItem(id item, BOOL hideWhoToFollow, BOOL hidePrompts,
                                           BOOL hideTopics, BOOL hideTopicsToFollow,
                                           BOOL hideVerified, BOOL hideBlockedRetweets,
                                           BOOL inConversation, BOOL inProfile,
                                           long long conversationRootUserID,
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
                       (inConversation << 5) | (inProfile << 6) |
                       (hideBlockedRetweets << 7);
    BOOL repliedSetChanged = authorRepliedToUserIDs != cachedAuthorRepliedToUserIDs &&
                             ![authorRepliedToUserIDs isEqualToSet:cachedAuthorRepliedToUserIDs];
    PFBEnsureMutedLoaded();
    if (flags != cachedFlags || conversationRootUserID != cachedRootUserID ||
        repliedSetChanged || gPFBMutedSignature != cachedMutedSignature) {
        [cache removeAllObjects];
        cachedMutedSignature = gPFBMutedSignature;
        cachedFlags = flags;
        cachedRootUserID = conversationRootUserID;
        cachedAuthorRepliedToUserIDs = authorRepliedToUserIDs;
    }

    NSString* entryID = ItemEntryID(PFBUnwrapDataViewItem(item));
    if (!entryID) {
        return ShouldHideTimelineItem(item, hideWhoToFollow, hidePrompts, hideTopics,
                                      hideTopicsToFollow, hideVerified, hideBlockedRetweets, inConversation, inProfile,
                                      conversationRootUserID, authorRepliedToUserIDs);
    }

    NSNumber* cached = [cache objectForKey:entryID];
    if (cached) {
        return cached.boolValue;
    }

    BOOL hide = ShouldHideTimelineItem(item, hideWhoToFollow, hidePrompts, hideTopics,
                                       hideTopicsToFollow, hideVerified, hideBlockedRetweets, inConversation, inProfile,
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
            id viewModel = PFBUnwrapDataViewItem(item);
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
            id viewModel = PFBUnwrapDataViewItem(item);
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

static const void* kPFBReadingAnchorIDKey = &kPFBReadingAnchorIDKey;
static const void* kPFBReadingAnchorPathKey = &kPFBReadingAnchorPathKey;
static const void* kPFBReadingMarkerViewKey = &kPFBReadingMarkerViewKey;
static const void* kPFBListViewKey = &kPFBListViewKey;
static const void* kPFBReadingTopAtCaptureKey = &kPFBReadingTopAtCaptureKey;
static const void* kPFBReadingRetiredKey = &kPFBReadingRetiredKey;
static const void* kPFBReadingMissCountKey = &kPFBReadingMissCountKey;

// The wash covers the Tweet's header and fades out before the media: solid
// for the first points, gone by the reach. Low enough to read through, high
// enough to spot at a glance.
static const CGFloat kPFBReadingMarkerAlpha = 0.18;
static const CGFloat kPFBReadingFadeSolid = 34.0;
static const CGFloat kPFBReadingFadeReach = 110.0;
static NSHashTable* gPFBReadingControllers = nil;

// A list scroll view is one that can name its visible index paths.
static BOOL PFBViewIsList(UIView* view) {
    return [view isKindOfClass:[UIScrollView class]] &&
           ([view respondsToSelector:@selector(indexPathsForVisibleRows)] ||
            [view respondsToSelector:@selector(indexPathsForVisibleItems)]);
}

static UIScrollView* PFBFindListInView(UIView* view) {
    if (PFBViewIsList(view)) {
        return (UIScrollView*)view;
    }
    for (UIView* subview in view.subviews) {
        UIScrollView* found = PFBFindListInView(subview);
        if (found) {
            return found;
        }
    }
    return nil;
}

// The controller's list, found in its mounted view tree. Asking for -tableView or
// -collectionView invokes a lazy getter that builds a view never meant to exist,
// and on a collection view that raises.
static UIScrollView* PFBListScrollView(TFNItemsDataViewController* dataViewController) {
    if (![dataViewController isViewLoaded]) {
        return nil;
    }
    UIScrollView* cached =
        objc_getAssociatedObject(dataViewController, kPFBListViewKey);
    if (cached.window && [cached isDescendantOfView:dataViewController.view]) {
        return cached;
    }
    UIScrollView* found = PFBFindListInView(dataViewController.view);
    // Retained, not assigned: an assigned pointer is a raw address, and the check
    // above would message freed memory once the app releases the list. Holding it
    // costs one stale scroll view until the next lookup.
    objc_setAssociatedObject(dataViewController, kPFBListViewKey, found,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return found;
}

static NSArray<NSIndexPath*>* PFBListVisibleIndexPaths(UIScrollView* scrollView) {
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

static BOOL PFBListCellFrame(UIScrollView* scrollView, NSIndexPath* path,
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

static BOOL PFBReadingIsHomeTimeline(TFNItemsDataViewController* dataViewController) {
    return IsInHierarchyOfClass(
        dataViewController,
        @"_TtC32TwitterHomeFeatureImplementation35HomeTimelineContainerViewController");
}

// The topmost visible row's entry ID; nil when the table or the item cannot
// be resolved. Sections that are not item arrays are opaque and skipped.
static NSString* PFBReadingTopVisibleEntryID(TFNItemsDataViewController* dataViewController) {
    UIScrollView* list = PFBListScrollView(dataViewController);
    NSIndexPath* top = PFBListVisibleIndexPaths(list).firstObject;
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
static NSString* PFBReadingFirstEntryID(NSArray* sections) {
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

static NSIndexPath* PFBReadingIndexPathForEntryID(
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
static NSString* const kPFBReadingStoreKey = @"pfb_reading_anchors";
static const NSUInteger kPFBReadingStoreLimit = 12;

static void PFBReadingStoreRemember(NSString* previousAnchor, NSString* anchor,
                                    NSString* head) {
    if (!anchor.length || !head.length) {
        return;
    }
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSMutableArray* entries =
        [NSMutableArray arrayWithObject:@{@"anchor": anchor, @"head": head}];
    for (id entry in [defaults arrayForKey:kPFBReadingStoreKey]) {
        if (entries.count >= kPFBReadingStoreLimit) {
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
    [defaults setObject:entries forKey:kPFBReadingStoreKey];
}

static BOOL PFBReadingStoreRestore(TFNItemsDataViewController* dataViewController) {
    for (id entry in
         [[NSUserDefaults standardUserDefaults] arrayForKey:kPFBReadingStoreKey]) {
        if (![entry isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSString* anchor = ((NSDictionary*)entry)[@"anchor"];
        NSString* head = ((NSDictionary*)entry)[@"head"];
        if (![anchor isKindOfClass:[NSString class]] ||
            ![head isKindOfClass:[NSString class]] ||
            !PFBReadingIndexPathForEntryID(dataViewController, anchor)) {
            continue;
        }
        objc_setAssociatedObject(dataViewController, kPFBReadingAnchorIDKey,
                                 anchor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(dataViewController, kPFBReadingTopAtCaptureKey,
                                 head, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return YES;
    }
    return NO;
}

// scribeSection is not declared in src/Headers. This shim is only a cast target:
// never instantiated, never messaged as a class, so no class symbol is
// referenced.
@interface PFBReadingScribeShim : NSObject
- (NSString*)scribeSection;
@end

// Identifies the Following tab by the timeline's own scribe section: For you
// reports "home", Following reports "latest". An allowlist on purpose, so a
// section that cannot be read denies the marker rather than granting it.
static BOOL PFBReadingIsFollowingTab(TFNItemsDataViewController* dataViewController) {
    if (![dataViewController respondsToSelector:@selector(scribeSection)]) {
        return NO;
    }
    PFBReadingScribeShim* shim = (PFBReadingScribeShim*)dataViewController;
    NSString* section = [shim scribeSection];
    if (![section isKindOfClass:[NSString class]]) {
        return NO;
    }
    return [section isEqualToString:@"latest"];
}

static BOOL PFBReadingMarkerAllowed(TFNItemsDataViewController* dataViewController) {
    if (![PFBSettings boolForKey:@"reading_line"]) {
        if (PFBCompatNeedsObservation(PFBCompat_reading_line) &&
            PFBReadingIsHomeTimeline(dataViewController) &&
            PFBReadingIsFollowingTab(dataViewController)) {
            PFBCOMPAT_OBSERVE(PFBCompat_reading_line, @"Following timeline found");
        }
        return NO;
    }
    return PFBReadingIsHomeTimeline(dataViewController) &&
           ![objc_getAssociatedObject(dataViewController, kPFBReadingRetiredKey)
               boolValue] &&
           PFBReadingIsFollowingTab(dataViewController);
}

static NSUInteger PFBReadingItemCount(NSArray* sections) {
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
static void PFBReadingCaptureAnchor(TFNItemsDataViewController* dataViewController,
                                    NSArray* incomingSections) {
    if (!PFBReadingMarkerAllowed(dataViewController)) {
        return;
    }
    // A list with nothing on screen has nothing to record.
    if (!PFBReadingTopVisibleEntryID(dataViewController).length) {
        return;
    }
    // A controller with no anchor is new or just relaunched, and claiming the head
    // would bury the one on disk. The stored anchors are tried first; with nothing
    // stored the head becomes the first boundary.
    if (!objc_getAssociatedObject(dataViewController, kPFBReadingAnchorIDKey)) {
        if (PFBReadingStoreRestore(dataViewController)) {
            return;
        }
        NSArray* stored =
            [[NSUserDefaults standardUserDefaults] arrayForKey:kPFBReadingStoreKey];
        if ([stored isKindOfClass:[NSArray class]] && stored.count &&
            PFBReadingItemCount(dataViewController.sections) < 10) {
            return;
        }
    } else {
        NSString* incomingHead = PFBReadingFirstEntryID(incomingSections);
        NSString* currentHead =
            PFBReadingFirstEntryID(dataViewController.sections);
        if (!incomingHead.length || !currentHead.length ||
            [incomingHead isEqualToString:currentHead]) {
            // Nothing arrives above: the boundary stays, and is written out
            // as it is.
            NSString* held =
                objc_getAssociatedObject(dataViewController, kPFBReadingAnchorIDKey);
            PFBReadingStoreRemember(
                held, held,
                objc_getAssociatedObject(dataViewController,
                                         kPFBReadingTopAtCaptureKey));
            return;
        }
    }
    NSString* listHead = PFBReadingFirstEntryID(dataViewController.sections);
    if (!listHead.length) {
        return;
    }
    // The list's first Tweet is the boundary: the batch lands above it, and the
    // wash falls on the first Tweet under that batch.
    NSString* previousAnchor =
        objc_getAssociatedObject(dataViewController, kPFBReadingAnchorIDKey);
    objc_setAssociatedObject(dataViewController, kPFBReadingAnchorIDKey, listHead,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(dataViewController, kPFBReadingTopAtCaptureKey,
                             listHead, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    PFBReadingStoreRemember(previousAnchor, listHead, listHead);
}

// One row's true geometry. The rendered cell is authoritative on screen, since
// data sections and table rows do not always map one-to-one. Off screen the
// computed rect only decides visibility.
static void PFBReadingPlaceMarker(UIScrollView* table, UIView* marker,
                                  NSIndexPath* path) {
    CGRect rowRect;
    if (!PFBListCellFrame(table, path, &rowRect)) {
        marker.hidden = YES;
        return;
    }
    extern UIColor* PFBCurrentAccentColor(void);
    UIColor* accent = PFBCurrentAccentColor() ?: [UIColor systemBlueColor];
    CGFloat reach = MIN(CGRectGetHeight(rowRect), kPFBReadingFadeReach);
    marker.frame = CGRectMake(CGRectGetMinX(rowRect), CGRectGetMinY(rowRect),
                              CGRectGetWidth(rowRect), reach);
    CAGradientLayer* fade =
        (CAGradientLayer*)marker.layer.sublayers.firstObject;
    if (![fade isKindOfClass:[CAGradientLayer class]]) {
        fade = [CAGradientLayer layer];
        [marker.layer addSublayer:fade];
    }
    UIColor* tint = [accent colorWithAlphaComponent:kPFBReadingMarkerAlpha];
    // The layer would animate every reposition; the marker must simply be
    // where its Tweet is.
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    fade.frame = marker.bounds;
    fade.colors = @[
        (id)tint.CGColor, (id)tint.CGColor, (id)UIColor.clearColor.CGColor
    ];
    fade.locations = @[
        @0, @(reach > 0.0 ? MIN(kPFBReadingFadeSolid / reach, 1.0) : 0.0), @1
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
static void PFBReadingPositionMarker(TFNItemsDataViewController* dataViewController) {
    UIScrollView* table = PFBListScrollView(dataViewController);
    if (!table) {
        return;
    }
    UIView* marker = objc_getAssociatedObject(table, kPFBReadingMarkerViewKey);
    // A launch starts with no anchor in memory; the stored ones are tried
    // against this list a few times while it fills in.
    if (PFBReadingMarkerAllowed(dataViewController) &&
        !objc_getAssociatedObject(dataViewController, kPFBReadingAnchorIDKey)) {
        // Retried while the list still has nothing to match against: a fixed
        // number of attempts runs out before the first page arrives.
        if (PFBReadingItemCount(dataViewController.sections) > 0) {
            PFBReadingStoreRestore(dataViewController);
        }
    }
    NSString* anchor =
        objc_getAssociatedObject(dataViewController, kPFBReadingAnchorIDKey);
    NSIndexPath* path = PFBReadingMarkerAllowed(dataViewController)
                            ? PFBReadingIndexPathForEntryID(dataViewController, anchor)
                            : nil;
    objc_setAssociatedObject(table, kPFBReadingAnchorPathKey, path,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (path) {
        PFBCOMPAT_ACTION(PFBCompat_reading_line, @"marker placed");
    }
    if (!path) {
        // A replaced list has a new first item as well as a missing anchor; an
        // anchor that fell out of a list whose head is unchanged is a loading
        // phase. Two consecutive absent passes retire the marker for the session.
        NSString* headNow = PFBReadingFirstEntryID(dataViewController.sections);
        NSString* headThen =
            objc_getAssociatedObject(dataViewController, kPFBReadingTopAtCaptureKey);
        BOOL replaced = headNow.length && headThen.length &&
                        ![headNow isEqualToString:headThen];
        if (anchor.length && replaced &&
            PFBReadingItemCount(dataViewController.sections) >= 10) {
            NSInteger misses =
                [objc_getAssociatedObject(dataViewController,
                                          kPFBReadingMissCountKey) integerValue] +
                1;
            if (misses >= 2) {
                objc_setAssociatedObject(dataViewController,
                                         kPFBReadingRetiredKey, @YES,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                objc_setAssociatedObject(dataViewController,
                                         kPFBReadingAnchorIDKey, nil,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                objc_setAssociatedObject(dataViewController,
                                         kPFBReadingMissCountKey, nil,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            } else {
                objc_setAssociatedObject(dataViewController,
                                         kPFBReadingMissCountKey, @(misses),
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }
        marker.hidden = YES;
        return;
    }
    objc_setAssociatedObject(dataViewController, kPFBReadingMissCountKey, nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // An anchor that is still the first row has nothing above it to mark.
    NSString* topNow = PFBReadingFirstEntryID(dataViewController.sections);
    if (!topNow.length || [anchor isEqualToString:topNow]) {
        // The layout tick draws from the cached path: an anchor with nothing
        // to mark leaves none behind.
        objc_setAssociatedObject(table, kPFBReadingAnchorPathKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        marker.hidden = YES;
        return;
    }
    if (!marker) {
        marker = [[UIView alloc] init];
        marker.userInteractionEnabled = NO;
        objc_setAssociatedObject(table, kPFBReadingMarkerViewKey, marker,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    PFBReadingPlaceMarker(table, marker, path);
}

// Row heights settle after the reload, so the scan waits one runloop turn.
static void PFBReadingRescanSoon(TFNItemsDataViewController* dataViewController) {
    if (!PFBReadingIsHomeTimeline(dataViewController)) {
        return;
    }
    __weak TFNItemsDataViewController* weakController = dataViewController;
    dispatch_async(dispatch_get_main_queue(), ^{
        TFNItemsDataViewController* controller = weakController;
        if (controller) {
            PFBReadingPositionMarker(controller);
        }
    });
}

// Self-sizing rows shift their rects as cells realise, so the tick keeps the wash
// on its row from the cached index path. A row with no measurable rect at first
// placement is retried here.
static void PFBReadingLayoutTick(UIScrollView* scrollView) {
    UIView* marker = objc_getAssociatedObject(scrollView, kPFBReadingMarkerViewKey);
    if (!marker) {
        return;
    }
    NSIndexPath* path =
        objc_getAssociatedObject(scrollView, kPFBReadingAnchorPathKey);
    if (!path) {
        marker.hidden = YES;
        return;
    }
    PFBReadingPlaceMarker(scrollView, marker, path);
}

// The app backgrounding is the one leave moment no view callback covers.
static void PFBReadingTrack(TFNItemsDataViewController* dataViewController) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gPFBReadingControllers = [NSHashTable weakObjectsHashTable];
        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidEnterBackgroundNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification* note) {
                        for (TFNItemsDataViewController* controller in
                             gPFBReadingControllers.allObjects) {
                            PFBReadingCaptureAnchor(controller, nil);
                        }
                    }];
    });
    [gPFBReadingControllers addObject:dataViewController];
}

// MARK: - Language filter

// A Tweet carries the language of its original text, and the kept set lists the
// selected ones; empty means off. A Tweet whose language cannot be detected always
// passes, so image-only posts are never lost.

static NSString* const kPFBLanguagesKey = @"pfb_filter_languages";

static id PFBStatusForItem(id item) {
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

static BOOL PFBItemLanguageAllowed(id item, NSSet<NSString*>* kept) {
    if (!kept.count) {
        return YES;
    }
    id status = PFBStatusForItem(item);
    if (![status respondsToSelector:@selector(language)]) {
        return YES;
    }
    NSString* language =
        ((NSString* (*)(id, SEL))objc_msgSend)(status, @selector(language));
    if (![language isKindOfClass:[NSString class]] || !language.length ||
        [language isEqualToString:@"und"]) {
        return YES;
    }
    // A regional code ("pt-BR") matches the language it belongs to.
    NSString* base = [language componentsSeparatedByString:@"-"].firstObject;
    return [kept containsObject:base.lowercaseString];
}

static NSSet<NSString*>* PFBKeptLanguages(void) {
    NSArray* stored =
        [[NSUserDefaults standardUserDefaults] arrayForKey:kPFBLanguagesKey];
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

// Off filters keep classifying the timeline until each has found its items once
// this launch, so the report can show they still would.
static BOOL PFBTimelineFiltersNeedObservation(void) {
    return PFBCompatNeedsObservation(PFBCompat_hide_timeline_prompts) ||
           PFBCompatNeedsObservation(PFBCompat_hide_topics) ||
           PFBCompatNeedsObservation(PFBCompat_hide_topics_to_follow) ||
           PFBCompatNeedsObservation(PFBCompat_hide_verified_tweets) ||
           PFBCompatNeedsObservation(PFBCompat_hide_blocked_retweets);
}

static NSArray* FilteredTimelineSections(TFNItemsDataViewController* dataViewController,
                                         NSArray* sections) {
    BOOL hideWhoToFollow = [PFBSettings boolForKey:@"hide_who_to_follow"];
    BOOL hidePrompts = [PFBSettings boolForKey:@"hide_timeline_prompts"];
    BOOL hideTopics = [PFBSettings boolForKey:@"hide_topics"];
    BOOL hideTopicsToFollow = [PFBSettings boolForKey:@"hide_topics_to_follow"];
    BOOL inConversation =
        IsInHierarchyOfClass(dataViewController, @"T1ConversationContainerViewController");
    BOOL inProfile = IsInHierarchyOfClass(dataViewController, @"T1ProfileViewController");
    // A search is opened on purpose, like a profile: its results keep verified Tweets.
    BOOL inSearch = IsInHierarchyOfClass(dataViewController, @"TTSSearchContainerViewControllerV2") ||
                    IsInHierarchyOfClass(dataViewController, @"TTSSearchContainerViewController");

    BOOL hideVerified = [PFBSettings boolForKey:@"hide_verified_tweets"] && !inProfile && !inSearch;
    BOOL hideBlockedRetweets = [PFBSettings boolForKey:@"hide_blocked_retweets"];
    // The language filter belongs to the timelines, not to a conversation or a
    // profile opened on purpose.
    NSSet<NSString*>* keptLanguages =
        (inConversation || inProfile) ? nil : PFBKeptLanguages();

    // Hidden conversations open this pass like any other option: without them
    // here, a reader with no other filter on kept every hidden thread, because
    // the whole loop below was skipped.
    BOOL hasHiddenThreads = PFBHiddenThreads().count > 0;

    if (!hideWhoToFollow && !hidePrompts && !hideTopics && !hideTopicsToFollow &&
        !hideVerified && !hideBlockedRetweets && !inConversation && !keptLanguages.count &&
        !hasHiddenThreads && !inSearch &&
        !PFBTimelineFiltersNeedObservation()) {
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
                                               hideTopicsToFollow, hideVerified, hideBlockedRetweets,
                                               inConversation, inProfile, conversationRootUserID,
                                               authorRepliedToUserIDs) ||
                !PFBItemLanguageAllowed(items[i], keptLanguages)) {
                [removed addIndex:i];
            } else if (inSearch && PFBShouldHideVerifiedItem(PFBUnwrapDataViewItem(items[i]), NO, 0, nil)) {
                PFBCompatReach(PFBCompatPath_verified_search);
            }
        }

        if (removed.count == 0) {
            [filteredSections addObject:section];
            continue;
        }

        PFBMarkEmptiedModuleChrome(items, removed);

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
static void PFBReapplyInHierarchy(UIViewController* controller) {
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
        PFBReapplyInHierarchy(child);
    }
    PFBReapplyInHierarchy(controller.presentedViewController);
}

// Re-applies the filter to what is already on screen. It runs when sections are
// handed to the controller, not when the table draws, so the sections are set
// again with what the controller already holds.
void pfbReapplyTimelineFilter(void) {
    for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }
        for (UIWindow* window in ((UIWindowScene*)scene).windows) {
            PFBReapplyInHierarchy(window.rootViewController);
        }
    }
}

%hook TFNItemsDataViewController

- (void)setSections:(NSArray*)sections restoreScrollPosition:(BOOL)restoreScrollPosition {
    BOOL keepPlace = restoreScrollPosition;
    NSArray* filtered = FilteredTimelineSections(self, sections);
    if (PFBReadingIsHomeTimeline(self)) {
        // Every home controller is tracked, the algorithmic tab included: tracking is pure
        // registration, and each reading action gates itself on MarkerAllowed.
        // The badge pass resolves its controller from this registry.
        PFBReadingTrack(self);
        if (PFBReadingMarkerAllowed(self)) {
            PFBReadingCaptureAnchor(self, filtered);
        }
        // Twitter's own restore flag, forced on the home timeline so a reload
        // keeps the reading position instead of jumping to the top.
        keepPlace = YES;
    }
    %orig(filtered, keepPlace);
    PFBReadingRescanSoon(self);
}

- (void)updateSections:(NSArray*)sections
    reconfigureItemIdentifiers:(NSArray*)identifiers
              withRowAnimation:(long long)animation
                    completion:(id)completion {
    NSArray* filtered = FilteredTimelineSections(self, sections);
    if (PFBReadingMarkerAllowed(self)) {
        PFBReadingCaptureAnchor(self, filtered);
    }
    %orig(filtered, identifiers, animation, completion);
    PFBReadingRescanSoon(self);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    PFBReadingRescanSoon(self);
}

- (void)viewWillDisappear:(BOOL)animated {
    PFBReadingCaptureAnchor(self, nil);
    %orig;
}

%end

// MARK: - Poll results before voting

// The counts travel with the card data before a vote, so the percentage is
// appended to each option's label. The choice count is not derived from the card
// name, since image polls carry none; the per-choice bindings are probed instead.

static const NSUInteger kPFBPollMaxChoices = 4;

// "choice2_label" -> 2, anything else -> 0.
static NSUInteger pfbPollChoiceIndexForKey(NSString* key) {
    if (![key hasPrefix:@"choice"] || ![key hasSuffix:@"_label"]) {
        return 0;
    }
    NSRange digits = NSMakeRange(6, key.length - 6 - 6);
    NSInteger index = [key substringWithRange:digits].integerValue;
    return index > 0 ? (NSUInteger)index : 0;
}

static BOOL pfbPollAlreadyShowsResults(TFCCardData* cardData) {
    if ([cardData boolForKey:@"counts_are_final"]) {
        return YES;
    }
    return [cardData stringForKey:@"selected_choice"].length > 0;
}

static NSString* pfbPollPercentageString(double fraction) {
    static NSNumberFormatter* formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        formatter = [[NSNumberFormatter alloc] init];
        formatter.numberStyle = NSNumberFormatterPercentStyle;
        formatter.maximumFractionDigits = 0;
    });
    return [formatter stringFromNumber:@(fraction)];
}

static NSString* pfbPollTitleWithPercentage(TFCCardData* cardData,
                                            NSString* key,
                                            NSString* title) {
    NSUInteger choice = pfbPollChoiceIndexForKey(key);
    if (choice > 0 && choice <= kPFBPollMaxChoices && title.length > 0 &&
        ![PFBSettings boolForKey:@"show_poll_results"]) {
        PFBCOMPAT_OBSERVE(PFBCompat_show_poll_results, @"poll found");
    }
    if (choice == 0 || choice > kPFBPollMaxChoices || title.length == 0 ||
        ![PFBSettings boolForKey:@"show_poll_results"]) {
        return title;
    }
    if (pfbPollAlreadyShowsResults(cardData)) {
        return title;
    }

    // numberForKey: tells a missing binding apart from a zero tally, and
    // neither it nor numberFromStringForKey: is hooked below, so probing the
    // siblings cannot recurse back in here.
    long long total = 0;
    long long votes = 0;
    for (NSUInteger i = 1; i <= kPFBPollMaxChoices; i++) {
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
    PFBCOMPAT_ACTION(PFBCompat_show_poll_results, @"results shown");
    return [NSString
        stringWithFormat:@"%@ (%@)", title,
                         pfbPollPercentageString((double)votes / (double)total)];
}

%hook TFCCardData

- (NSString*)stringForKey:(NSString*)key {
    NSString* title = %orig;
    return pfbPollTitleWithPercentage(self, key, title);
}

- (NSString*)stringForKey:(NSString*)key defaultValue:(NSString*)value {
    NSString* title = %orig;
    return pfbPollTitleWithPercentage(self, key, title);
}

%end
