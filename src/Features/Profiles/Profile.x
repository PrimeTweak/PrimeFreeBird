// Profile options: copy profile info, hide the premium offer, unrounded follower
// and post counts, a chosen opening tab, no Videos tab, expanded bios.

#import "Support/HookHelpers.h"
#import "Debug/PFBDebugger.h"
#import "Debug/PFBProbe.h"

// MARK: - Copy profile info

static char kCopyProviderKey;

@interface PFBProfileCopyButtonProvider : NSObject
@property (nonatomic, weak) T1ProfileHeaderViewController* headerViewController;
@end

// A getter reached by name, whatever it returns: an object, or a whole number
// boxed; nil when the class does not answer it.
static id pfbGetterValue(id object, NSString* name) {
    SEL selector = NSSelectorFromString(name);
    Method method = object ? class_getInstanceMethod([object class], selector) : NULL;
    if (!method) {
        return nil;
    }
    char type[8] = {0};
    method_getReturnType(method, type, sizeof(type));
    switch (type[0]) {
        case '@':
            return ((id (*)(id, SEL))objc_msgSend)(object, selector);
        case 'q':
            return @(((long long (*)(id, SEL))objc_msgSend)(object, selector));
        case 'Q':
            return @(((unsigned long long (*)(id, SEL))objc_msgSend)(object, selector));
        default:
            return nil;
    }
}

// The account behind the header, reached through its data source.
static id pfbProfileUser(T1ProfileUserViewModel* viewModel) {
    return pfbGetterValue(pfbGetterValue(viewModel, @"userDataSource"), @"user");
}

static NSString* pfbProfileUserID(T1ProfileUserViewModel* viewModel) {
    id userID = pfbGetterValue(pfbProfileUser(viewModel), @"userID");
    if ([userID isKindOfClass:[NSNumber class]]) {
        return [userID longLongValue] > 0 ? [userID stringValue] : nil;
    }
    return [userID isKindOfClass:[NSString class]] ? userID : nil;
}

static NSString* pfbProfileJoinDate(T1ProfileUserViewModel* viewModel) {
    id date = pfbGetterValue(pfbProfileUser(viewModel), @"createdDate");
    if (![date isKindOfClass:[NSDate class]]) {
        return nil;
    }
    NSDateFormatter* formatter = [[NSDateFormatter alloc] init];
    formatter.dateStyle = NSDateFormatterLongStyle;
    return [formatter stringFromDate:date];
}

// The view controller a view belongs to, from the responder chain.
static UIViewController* pfbOwningController(UIView* view) {
    UIResponder* responder = view;
    while (responder && ![responder isKindOfClass:[UIViewController class]]) {
        responder = responder.nextResponder;
    }
    return (UIViewController*)responder;
}

// The user ID and join date the copy menu offers, read whether or not the option is
// on, so an update that loses either shows in the report.
static void pfbReachCopyIDAndDate(UIView* row) {
    if (PFBCompatPathReached(PFBCompatPath_copy_id_and_date)) {
        return;
    }
    id viewModel = pfbGetterValue(pfbOwningController(row), @"viewModel");
    if (pfbProfileUserID(viewModel) && pfbProfileJoinDate(viewModel)) {
        PFBCompatReach(PFBCompatPath_copy_id_and_date);
    }
}

@implementation PFBProfileCopyButtonProvider

- (NSArray<UIMenuElement*>*)copyActions {
    // Each value is read only where its owner still answers for it.
    T1ProfileHeaderViewController* header = self.headerViewController;
    T1ProfileUserViewModel* viewModel =
        [header respondsToSelector:@selector(viewModel)] ? header.viewModel : nil;
    NSString* fullName = [viewModel respondsToSelector:@selector(fullName)] ? viewModel.fullName : nil;
    NSString* username = [viewModel respondsToSelector:@selector(username)] ? viewModel.username : nil;
    NSString* bio = [viewModel respondsToSelector:@selector(bio)] ? viewModel.bio : nil;
    NSString* location = [viewModel respondsToSelector:@selector(location)] ? viewModel.location : nil;
    NSString* url = [viewModel respondsToSelector:@selector(url)] ? viewModel.url : nil;

    UIAction* (^copyAction)(NSString*, NSString*, NSString*) =
        ^(NSString* titleKey, NSString* iconName, NSString* value) {
            UIImage* icon = [UIImage respondsToSelector:@selector(tfn_vectorImageNamed:fitsSize:fillColor:)]
                                ? [UIImage tfn_vectorImageNamed:iconName fitsSize:CGSizeMake(16.0, 16.0) fillColor:UIColor.labelColor]
                                : nil;
            UIAction* action =
                [UIAction actionWithTitle:[[PFBBundle sharedBundle] localizedStringForKey:titleKey]
                                    image:icon
                               identifier:nil
                                  handler:^(__kindof UIAction* act) {
                                      if (value.length) {
                                          UIPasteboard.generalPasteboard.string = value;
                                      }
                                  }];
            if (!value.length) {
                action.attributes = UIMenuElementAttributesDisabled;
            }
            return action;
        };

    return @[
        copyAction(@"COPY_PROFILE_INFO_MENU_OPTION_3", @"account", fullName),
        copyAction(@"COPY_PROFILE_INFO_MENU_OPTION_2", @"at", username),
        copyAction(@"COPY_PROFILE_INFO_MENU_OPTION_1", @"news_stroke", bio),
        copyAction(@"COPY_PROFILE_INFO_MENU_OPTION_5", @"location_stroke", location),
        copyAction(@"COPY_PROFILE_INFO_MENU_OPTION_4", @"link", url),
        copyAction(@"COPY_PROFILE_INFO_MENU_OPTION_6", @"link",
                   username.length
                       ? [NSString stringWithFormat:@"https://x.com/%@", username]
                       : nil),
        copyAction(@"COPY_PROFILE_INFO_MENU_OPTION_7", @"bar_chart", pfbProfileUserID(viewModel)),
        copyAction(@"COPY_PROFILE_INFO_MENU_OPTION_8", @"calendar", pfbProfileJoinDate(viewModel)),
    ];
}

@end

// MARK: - placing the button

// The Swift action-button factory exposes no ObjC selector, so the button is placed
// directly in the row Twitter built: one slot left of the leftmost button, same
// size, 8 pt apart, with the style copied from that button.

static char kPFBCopyButtonKey;

// The header's row of the bell and the share, the one Twitter keeps as the header's
// active action row. Its two other rows are laid out in the top bar, over the banner.
static BOOL pfbRowIsHeaderActions(UIView* header, UIView* row) {
    return pfbGetterValue(pfbGetterValue(header, @"topRightActionButtonsController"), @"rowView") == row;
}

// The leftmost native button in the row, the anchor the copy button sits beside.
static UIView* pfbLeftmostRowButton(UIView* row) {
    UIView* leftmost = nil;
    for (UIView* candidate in row.subviews) {
        if (![NSStringFromClass([candidate classForCoder]) isEqualToString:@"XDSButton"]) {
            continue;
        }
        if (!leftmost || CGRectGetMinX(candidate.frame) < CGRectGetMinX(leftmost.frame)) {
            leftmost = candidate;
        }
    }
    return leftmost;
}

// Reads the neighbor's own look so the copy button matches it.
static void pfbMatchNeighbourStyle(UIButton* ours, UIView* neighbour) {
    ours.layer.cornerRadius = neighbour.layer.cornerRadius > 0
        ? neighbour.layer.cornerRadius
        : neighbour.bounds.size.height / 2.0;
    ours.layer.cornerCurve = kCACornerCurveContinuous;
    ours.layer.borderWidth = neighbour.layer.borderWidth;
    ours.layer.borderColor = neighbour.layer.borderColor;
    if (neighbour.backgroundColor) {
        ours.backgroundColor = neighbour.backgroundColor;
    }
    // The neighbour draws its thin gray ring in a subview, so copying the button's
    // own borderWidth yields zero and the ring is drawn here instead. Derived from
    // labelColor, never a semantic system fill, which Twitter reinterprets.
    if (ours.layer.borderWidth <= 0) {
        BOOL ringFound = NO;
        for (UIView* node in neighbour.subviews) {
            if (node.layer.borderWidth > 0 && node.layer.borderColor) {
                ours.layer.borderWidth = node.layer.borderWidth;
                ours.layer.borderColor = node.layer.borderColor;
                ringFound = YES;
                break;
            }
        }
        if (!ringFound) {
            ours.layer.borderWidth = 1.0;
            ours.layer.borderColor =
                [[UIColor labelColor] colorWithAlphaComponent:0.14].CGColor;
        }
    }
    // The neighbor's glyph carries the tint the row expects; the copy button's template
    // image then renders in the same color.
    for (UIView* node in neighbour.subviews) {
        for (UIView* deeper in node.subviews) {
            if ([deeper isKindOfClass:[UIImageView class]] && deeper.tintColor) {
                ours.tintColor = deeper.tintColor;
                return;
            }
        }
        if ([node isKindOfClass:[UIImageView class]] && node.tintColor) {
            ours.tintColor = node.tintColor;
            return;
        }
    }
}

%hook XDSButtonRow

- (void)layoutSubviews {
    %orig;

    BOOL copyOn = [PFBSettings boolForKey:@"copy_profile_info"];
    if (!copyOn && !PFBCompatNeedsObservation(PFBCompat_copy_profile_info) &&
        PFBCompatPathReached(PFBCompatPath_copy_button) &&
        PFBCompatPathReached(PFBCompatPath_copy_id_and_date)) {
        return;
    }
    UIView* row = (UIView*)self;
    UIView* header = row.superview;
    if (![NSStringFromClass([header classForCoder]) isEqualToString:@"T1ProfileHeaderView"] ||
        !pfbRowIsHeaderActions(header, row)) {
        return;
    }
    UIView* anchor = pfbLeftmostRowButton(row);
    if (!anchor || CGRectIsEmpty(anchor.frame)) {
        return;
    }
    PFBCompatReach(PFBCompatPath_copy_button);
    pfbReachCopyIDAndDate(row);
    if (!copyOn) {
        PFBCOMPAT_OBSERVE(PFBCompat_copy_profile_info, @"profile buttons found");
        return;
    }
    PFBCOMPAT_ACTION(PFBCompat_copy_profile_info, @"copy button on a profile");

    UIButton* copyButton = objc_getAssociatedObject(row, &kPFBCopyButtonKey);
    if (!copyButton) {
        copyButton = [UIButton buttonWithType:UIButtonTypeSystem];
        copyButton.accessibilityLabel =
            [[PFBBundle sharedBundle] localizedStringForKey:@"COPY_PROFILE_INFO_TITLE"];
        copyButton.showsMenuAsPrimaryAction = YES;

        PFBProfileCopyButtonProvider* provider = [PFBProfileCopyButtonProvider new];
        // The provider reads the profile through the header's view controller,
        // found once from the responder chain and held weakly.
        provider.headerViewController = (id)pfbOwningController(row);
        objc_setAssociatedObject(copyButton, &kCopyProviderKey, provider,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        __weak PFBProfileCopyButtonProvider* weakProvider = provider;
        void (^actionsProvider)(void (^)(NSArray<UIMenuElement*>*)) =
            ^(void (^completion)(NSArray<UIMenuElement*>*)) {
                completion([weakProvider copyActions] ?: @[]);
            };
        UIDeferredMenuElement* deferred =
            [UIDeferredMenuElement elementWithUncachedProvider:actionsProvider];
        copyButton.menu = [UIMenu menuWithTitle:@"" children:@[deferred]];

        UIImage* glyph = [UIImage respondsToSelector:@selector(tfn_vectorImageNamed:fitsSize:fillColor:)]
                             ? [UIImage tfn_vectorImageNamed:@"copy_stroke" fitsSize:CGSizeMake(20, 20) fillColor:nil]
                             : nil;
        [copyButton setImage:[glyph imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
                    forState:UIControlStateNormal];

        objc_setAssociatedObject(row, &kPFBCopyButtonKey, copyButton,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    if (copyButton.superview != row) {
        [row addSubview:copyButton];
    }
    // Positioned every pass: the row lays its own buttons out and the copy button follows
    // them, not a remembered place.
    CGRect slot = anchor.frame;
    slot.origin.x = CGRectGetMinX(anchor.frame) - CGRectGetWidth(anchor.frame) - 8.0;
    copyButton.frame = slot;
    pfbMatchNeighbourStyle(copyButton, anchor);
    PFBMark(copyButton, @"Profile/copyButton");
}

%end

// MARK: - Hide premium offer

%hook T1ProfileSummaryView

- (BOOL)shouldShowGetVerifiedButton {
    if ([PFBSettings boolForKey:@"hide_premium_offer"]) {
        PFBCOMPAT_ACTION(PFBCompat_hide_premium_offer, @"Get verified hidden");
        return NO;
    }
    PFBCOMPAT_OBSERVE(PFBCompat_hide_premium_offer, @"read by Twitter");
    return %orig;
}

%end

// MARK: - Show unrounded follower, following and post counts

// Where the abbreviated count sits in text, with the full number to put there;
// NSNotFound when the count is too small to be abbreviated or the app's abbreviation
// is unavailable.
static NSRange pfbAbbreviatedCountRange(NSString* text, NSNumber* count, NSString** fullCount) {
    if (![count respondsToSelector:@selector(tfs_twitterAbbreviated)]) {
        return NSMakeRange(NSNotFound, 0);
    }
    NSString* abbreviated = [count tfs_twitterAbbreviated];
    NSNumberFormatter* formatter = [[NSNumberFormatter alloc] init];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    NSString* full = [formatter stringFromNumber:count];
    if (!text.length || !abbreviated.length || !full.length || [abbreviated isEqualToString:full]) {
        return NSMakeRange(NSNotFound, 0);
    }
    *fullCount = full;
    return [text rangeOfString:abbreviated];
}

%hook T1ProfileFriendsFollowingViewModel
- (id)_t1_followCountTextWithLabel:(__unsafe_unretained id)label
                     singularLabel:(__unsafe_unretained id)singularLabel
                             count:(NSNumber*)count
                       highlighted:(BOOL)highlighted {
    id original = %orig;
    if (![count isKindOfClass:[NSNumber class]] ||
        ![original isKindOfClass:[NSAttributedString class]]) {
        return original;
    }
    PFBCompatReach(PFBCompatPath_follower_counts);
    NSString* fullCount = nil;
    NSRange range = pfbAbbreviatedCountRange([original string], count, &fullCount);
    if (range.location == NSNotFound) {
        PFBCOMPAT_OBSERVE(PFBCompat_unrounded_counts, @"count found");
        return original;
    }
    PFBCOMPAT_ACTION(PFBCompat_unrounded_counts, @"count shown in full");
    NSMutableAttributedString* expanded = [original mutableCopy];
    [expanded replaceCharactersInRange:range withString:fullCount];
    return [expanded copy];
}
%end

// The post count under the name, from the header's view model.
%hook T1ProfileDisplayNormalMainContentProvider
- (id)_tweetsSubtitle {
    id original = %orig;
    id count = pfbGetterValue(pfbGetterValue(self, @"viewModel"), @"tweetCount");
    if (![original isKindOfClass:[NSString class]] || ![count isKindOfClass:[NSNumber class]]) {
        return original;
    }
    PFBCompatReach(PFBCompatPath_post_count);
    NSString* fullCount = nil;
    NSRange range = pfbAbbreviatedCountRange(original, count, &fullCount);
    if (range.location == NSNotFound) {
        PFBCOMPAT_OBSERVE(PFBCompat_unrounded_counts, @"count found");
        return original;
    }
    PFBCOMPAT_ACTION(PFBCompat_unrounded_counts, @"count shown in full");
    return [(NSString*)original stringByReplacingCharactersInRange:range withString:fullCount];
}
%end

// MARK: - Open profiles on a chosen tab

// T1ProfileDisplayContentProvider carries initialTabIndex, and its subclass exposes
// one entry per tab. The index is never hardcoded: the wanted entry is looked up in
// contentMainEntries, and a missing entry returns the original value.

// The wanted tab, as the entry object itself: each tab is a T1ProfileContentMainEntry
// that the provider hands out through a getter per tab (photoEntry, videoEntry...).
static id pfbWantedEntry(id provider) {
    NSString* name = nil;
    switch ([PFBSettings integerForKey:@"profile_initial_tab"]) {
        case 1: name = @"tweetsAndRepliesEntry"; break;
        case 2: name = @"highlightsEntry"; break;
        case 3: name = @"articlesEntry"; break;
        case 4: name = @"photoEntry"; break;
        case 5: name = @"videoEntry"; break;
        case 6: name = @"repostsEntry"; break;
        default:
            if ([provider respondsToSelector:@selector(contentMainEntries)]) {
                PFBCOMPAT_OBSERVE(PFBCompat_profile_initial_tab, @"profile tabs found");
            }
            return nil;   // 0 leaves the choice to Twitter
    }

    // A tab hidden by one of PrimeFreeBird's own switches is refused here too, in case an
    // old choice survives in the settings after the tab was switched off.
    NSString* hider = nil;
    switch ([PFBSettings integerForKey:@"profile_initial_tab"]) {
        case 2: hider = @"disable_highlights"; break;
        case 3: hider = @"disable_articles"; break;
        case 5: hider = @"disable_videos_tab"; break;
        default: break;
    }
    if (hider && [PFBSettings boolForKey:hider]) {
        return nil;
    }
    SEL selector = NSSelectorFromString(name);
    if (![provider respondsToSelector:selector] ||
        ![provider respondsToSelector:@selector(contentMainEntries)]) {
        return nil;
    }
    id entry = ((id (*)(id, SEL))objc_msgSend)(provider, selector);
    if (!entry) {
        return nil;
    }
    // No identity check against contentMainEntries: the entry can exist without the
    // array holding that exact object. Whether a tab is on screen is answered by the
    // controller further down.
    return entry;
}

// Probe 10b#F025: whether the index the provider computes gives the chosen tab, once for each
// outcome; when it does not, the first element shows what the tab list holds (10b#F001).
static BOOL gPFBProbeLookupDone[2];

static void pfbProbeTabLookup(id provider, NSArray* entries, NSUInteger index) {
    NSUInteger found = index != NSNotFound ? 1 : 0;
    // Without a tab list the index answers no lookup (a nil list gives 0).
    if (gPFBProbeLookupDone[found] || ![entries isKindOfClass:[NSArray class]]) {
        return;
    }
    gPFBProbeLookupDone[found] = YES;
    NSString* key = found ? @"10b#F025 provider index" : @"10b#F025 provider no index";
    if (!PFBProbeWants(key)) {
        return;
    }
    if (found) {
        PFBProbeNote(key, @"10b#F025 profile tab: provider gave the chosen tab (index %lu) on %@",
                     (unsigned long)index, PFBProbeClassName(provider));
        return;
    }
    PFBProbeNote(key, @"10b#F025 profile tab: chosen entry not in contentMainEntries (%lu entries, first %@) on %@",
                 (unsigned long)entries.count, PFBProbeClassName(entries.firstObject), PFBProbeClassName(provider));
}

static NSInteger pfbProfileTabIndex(id provider, NSInteger fallback) {
    id entry = pfbWantedEntry(provider);
    if (!entry) {
        return fallback;
    }
    NSArray* entries =
        ((id (*)(id, SEL))objc_msgSend)(provider, @selector(contentMainEntries));
    NSUInteger index = [entries indexOfObject:entry];
    // Probe: notes whether this index gives the chosen tab, for 10b#F025.
    pfbProbeTabLookup(provider, entries, index);
    return index == NSNotFound ? fallback : (NSInteger)index;
}

// The provider only *describes* the tabs; the controller is what selects
// one. T1ProfileViewController owns _t1_selectMainEntry:, and asking it
// directly is what actually moves the profile.

static const void* kPFBTabAppliedKey = &kPFBTabAppliedKey;

// Probe 10b#F025 and 10b#F001: each appearance of a profile until its chosen tab is applied, once
// per outcome, and, once per provider class, what its tab list holds when it holds something.
static NSMapTable* gPFBProbeAppearances;

static void pfbProbeProfileAppearance(id controller, id provider, id entry) {
    if (!PFBDebugIsRecording() || !NSThread.isMainThread) {
        return;
    }
    NSString* entriesKey = [@"10b#F001 entries " stringByAppendingString:PFBProbeClassName(provider)];
    if (PFBProbeWants(entriesKey)) {
        id entries = PFBProbeGetter(provider, @"contentMainEntries");
        NSArray* list = [entries isKindOfClass:[NSArray class]] ? entries : nil;
        // An empty list (a profile still loading) waits for a later appearance.
        if (list.count || (entries && !list)) {
            PFBProbeNote(entriesKey, @"10b#F001 profile tab: provider=%@ entries=%@ first=%@",
                         PFBProbeClassName(provider), list ? [@(list.count) stringValue] : PFBProbeClassName(entries),
                         PFBProbeClassName(list.firstObject));
        }
    }
    if ([PFBSettings integerForKey:@"profile_initial_tab"] == 0) {
        return;
    }
    if (!gPFBProbeAppearances) {
        gPFBProbeAppearances = [NSMapTable weakToStrongObjectsMapTable];
    }
    NSUInteger appearance = [[gPFBProbeAppearances objectForKey:controller] unsignedIntegerValue] + 1;
    [gPFBProbeAppearances setObject:@(appearance) forKey:controller];
    NSString* key = [NSString stringWithFormat:@"10b#F025 appearance %@ %@", appearance == 1 ? @"first" : @"later",
                                               entry ? @"found" : @"not yet"];
    if (PFBProbeWants(key)) {
        PFBProbeNote(key, @"10b#F025 profile tab: appearance %lu of %@ (provider %@), wanted entry %@",
                     (unsigned long)appearance, PFBProbeClassName(controller), PFBProbeClassName(provider),
                     entry ? @"found" : @"not yet");
    }
}

static void pfbProbeProfileSelect(id controller) {
    if (!PFBDebugIsRecording() || !NSThread.isMainThread) {
        return;
    }
    NSUInteger appearance = [[gPFBProbeAppearances objectForKey:controller] unsignedIntegerValue];
    NSString* key = appearance > 1 ? @"10b#F025 selected later" : @"10b#F025 selected first";
    if (!PFBProbeWants(key)) {
        return;
    }
    BOOL read = NO;
    long long shown =
        PFBProbeIntegerGetter(PFBProbeGetter(controller, @"segmentedViewController"), @"selectedIndex", &read);
    PFBProbeNote(key, @"10b#F025 profile tab: chosen tab selected at appearance %lu, the profile showed tab %@",
                 (unsigned long)appearance, read ? [@(shown) stringValue] : @"unread");
}

%hook T1ProfileViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;

    @try {
        id controller = self;
        if (objc_getAssociatedObject(controller, kPFBTabAppliedKey)) {
            return;
        }
        if (![controller respondsToSelector:@selector(currentDisplayContentProvider)] ||
            ![controller respondsToSelector:@selector(_t1_selectMainEntry:)]) {
            return;
        }

        id provider = ((id (*)(id, SEL))objc_msgSend)(
            controller, @selector(currentDisplayContentProvider));
        id entry = pfbWantedEntry(provider);
        // Probe: notes this appearance and the provider's tab list, for 10b#F025 and 10b#F001.
        pfbProbeProfileAppearance(controller, provider, entry);

        if (!entry) {
            return;
        }
        // The controller knows whether that entry has a tab on screen; asking it beats
        // comparing objects, and keeps the guard: a profile without that tab is left alone.
        if ([controller respondsToSelector:@selector(_t1_outerTabIndexForEntry:)]) {
            NSInteger index = ((NSInteger (*)(id, SEL, id))objc_msgSend)(
                controller, @selector(_t1_outerTabIndexForEntry:), entry);
            if (index < 0 || index == NSNotFound) {
                return;
            }
        }
        objc_setAssociatedObject(controller, kPFBTabAppliedKey, @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        // Probe: notes the appearance that applies the chosen tab, for 10b#F025.
        pfbProbeProfileSelect(controller);
        ((void (*)(id, SEL, id))objc_msgSend)(
            controller, @selector(_t1_selectMainEntry:), entry);
        PFBCOMPAT_ACTION(PFBCompat_profile_initial_tab, @"chosen tab opened");
    } @catch (id exception) {
    }
}

%end

// Probe 10b#F001: whether each hook of the provider is called on 12.31, once per method.
static BOOL gPFBProbeProviderDone[3];

static void pfbProbeProviderCall(NSUInteger hook, id provider, long long number, id entry) {
    if (gPFBProbeProviderDone[hook]) {
        return;
    }
    gPFBProbeProviderDone[hook] = YES;
    NSString* const keys[] = {@"10b#F001 initialTabIndex", @"10b#F001 defaultMainContentEntry",
                              @"10b#F001 setInitialTabIndex:"};
    if (!PFBProbeWants(keys[hook])) {
        return;
    }
    switch (hook) {
        case 0:
            PFBProbeNote(keys[0], @"10b#F001 profile tab: initialTabIndex on %@ orig=%lld", PFBProbeClassName(provider),
                         number);
            break;
        case 1:
            PFBProbeNote(keys[1], @"10b#F001 profile tab: defaultMainContentEntry on %@ orig=%@",
                         PFBProbeClassName(provider), entry ? PFBProbeClassName(entry) : @"nil");
            break;
        default:
            PFBProbeNote(keys[2], @"10b#F001 profile tab: setInitialTabIndex: %lld on %@", number,
                         PFBProbeClassName(provider));
            break;
    }
}

// Probe 10b#F025: a chosen tab the provider gives through its default entry, noted once.
static BOOL gPFBProbeProviderEntryDone;

static void pfbProbeProviderEntry(id provider, id wanted) {
    if (gPFBProbeProviderEntryDone || !wanted) {
        return;
    }
    gPFBProbeProviderEntryDone = YES;
    if (PFBProbeWants(@"10b#F025 provider entry")) {
        PFBProbeNote(@"10b#F025 provider entry",
                     @"10b#F025 profile tab: provider gave the chosen tab (entry %@) through defaultMainContentEntry "
                     @"on %@",
                     PFBProbeClassName(wanted), PFBProbeClassName(provider));
    }
}

%hook T1ProfileDisplayContentProvider

- (NSInteger)initialTabIndex {
    NSInteger original = %orig;
    // Probe: notes the call for 10b#F001.
    pfbProbeProviderCall(0, self, (long long)original, nil);

    @try {
        return pfbProfileTabIndex(self, original);
    } @catch (id exception) {
        return original;
    }
}

// defaultMainContentEntry holds the entry object Twitter treats as the landing tab;
// initialTabIndex is only an index derived from it.
- (id)defaultMainContentEntry {
    id original = %orig;
    // Probe: notes the call for 10b#F001.
    pfbProbeProviderCall(1, self, 0, original);

    @try {
        id wanted = pfbWantedEntry(self);
        // Probe: notes a chosen tab given here, for 10b#F025.
        pfbProbeProviderEntry(self, wanted);
        return wanted ?: original;
    } @catch (id exception) {
        return original;
    }
}

- (void)setInitialTabIndex:(NSInteger)index {
    // Probe: notes the call for 10b#F001.
    pfbProbeProviderCall(2, self, (long long)index, nil);
    NSInteger wanted = index;

    @try {
        wanted = pfbProfileTabIndex(self, index);
    } @catch (id exception) {
        wanted = index;
    }
    %orig(wanted);
}

%end

// MARK: - Hide the Videos tab

// Articles and Highlights are switched off through their feature flags, but no flag
// governs the Videos tab. The model decides instead, through shouldDisplayVideosTab
// on T1ProfileUserViewModel.

%hook T1ProfileUserViewModel

- (BOOL)shouldDisplayVideosTab {
    if ([PFBSettings boolForKey:@"disable_videos_tab"]) {
        PFBCOMPAT_ACTION(PFBCompat_disable_videos_tab, @"Videos tab hidden");
        return NO;
    }
    PFBCOMPAT_OBSERVE(PFBCompat_disable_videos_tab, @"read by Twitter");
    return %orig;
}

%end

// MARK: - Expand bios

// The inline bio truncation is _bioExpanded, exposed as isBioExpanded, not
// _expandedBioButton, which belongs to the Premium long bio and opens a modal.
// Forcing the getter is enough: the layout asks it whether to clip.

%hook T1ProfileUserInfoView

- (BOOL)isBioExpanded {
    if ([PFBSettings boolForKey:@"expand_bio"]) {
        PFBCOMPAT_ACTION(PFBCompat_expand_bio, @"bio expanded");
        return YES;
    }
    PFBCOMPAT_OBSERVE(PFBCompat_expand_bio, @"read by Twitter");
    return %orig;
}

%end
