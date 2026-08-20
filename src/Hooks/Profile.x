//
//  Profile.x
//  PrimeFreeBird
//

#import "HookHelpers.h"
#import "Debug/NFBDebugger.h"

// MARK: - Copy profile info

static char kCopyProviderKey;

@interface ProfileCopyButtonProvider : NSObject
@property (nonatomic, weak) T1ProfileHeaderViewController* headerViewController;
@property (nonatomic, weak) id delegate;
@end

@implementation ProfileCopyButtonProvider

- (NSArray<UIMenuElement*>*)copyActions {
    T1ProfileUserViewModel* viewModel = self.headerViewController.viewModel;

    UIAction* (^copyAction)(NSString*, NSString*, NSString*) =
        ^(NSString* titleKey, NSString* iconName, NSString* value) {
            UIAction* action =
                [UIAction actionWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:titleKey]
                                    image:[UIImage tfn_vectorImageNamed:iconName
                                                               fitsSize:CGSizeMake(16.0, 16.0)
                                                              fillColor:UIColor.labelColor]
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
        copyAction(@"COPY_PROFILE_INFO_MENU_OPTION_3", @"account", viewModel.fullName),
        copyAction(@"COPY_PROFILE_INFO_MENU_OPTION_2", @"at", viewModel.username),
        copyAction(@"COPY_PROFILE_INFO_MENU_OPTION_1", @"news_stroke", viewModel.bio),
        copyAction(@"COPY_PROFILE_INFO_MENU_OPTION_5", @"location_stroke", viewModel.location),
        copyAction(@"COPY_PROFILE_INFO_MENU_OPTION_4", @"link", viewModel.url),
        copyAction(@"COPY_PROFILE_INFO_MENU_OPTION_6", @"link",
                   viewModel.username.length
                       ? [NSString stringWithFormat:@"https://x.com/%@",
                                                    viewModel.username]
                       : nil),
    ];
}

@end

// MARK: - placing the button
//
// The mechanism this feature was built on is gone from Twitter 12.15: the
// health check named T1ProfileActionButtonSpec, actionButtonProviders and their
// initialiser as all missing, and the Swift replacement exposes no Objective-C
// selector to hook. So the button is no longer OFFERED to a factory — it is
// placed directly in the row Twitter already built.
//
// A device capture gave that row exactly:
//
//   T1ProfileHeaderView {{0,0},{440,311}}
//     XDSButtonRow {{0,176},{440,54}}
//       XDSButton {{343,12},{40,40}}      the bell
//       XDSButton {{391,12},{40,40}}      the share
//
// Forty by forty, spaced forty-eight apart, each holding a 20x20 glyph. The
// added button goes one slot further left, at 295.
//
// Style is COPIED from a neighbour at layout time rather than guessed: corner
// radius, border, background and glyph tint all come from the button beside it,
// so a Twitter restyle carries over instead of leaving ours mismatched.

static char kNFBCopyButtonKey;

// The row that holds the bell and the share, not the overlay row that floats on
// the banner. The overlay buttons carry an XDSBlur; these do not.
static BOOL nfbRowIsOverlay(UIView* row) {
    for (UIView* button in row.subviews) {
        for (UIView* node in button.subviews) {
            if ([NSStringFromClass([node classForCoder]) isEqualToString:@"XDSBlur"]) {
                return YES;
            }
            for (UIView* deeper in node.subviews) {
                if ([NSStringFromClass([deeper classForCoder]) isEqualToString:@"XDSBlur"]) {
                    return YES;
                }
            }
        }
    }
    return NO;
}

// The leftmost native button in the row — the anchor ours sits beside.
static UIView* nfbLeftmostRowButton(UIView* row) {
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

// Reads the neighbour's own look so ours matches whatever Twitter is doing.
static void nfbMatchNeighbourStyle(UIButton* ours, UIView* neighbour) {
    ours.layer.cornerRadius = neighbour.layer.cornerRadius > 0
        ? neighbour.layer.cornerRadius
        : neighbour.bounds.size.height / 2.0;
    ours.layer.cornerCurve = kCACornerCurveContinuous;
    ours.layer.borderWidth = neighbour.layer.borderWidth;
    ours.layer.borderColor = neighbour.layer.borderColor;
    if (neighbour.backgroundColor) {
        ours.backgroundColor = neighbour.backgroundColor;
    }
    // Measured on a capture: the bell and the share button wear a thin
    // grey ring, ours had none — because the neighbour draws that ring in a
    // SUBVIEW (its own background/blur layer), so copying the button's own
    // borderWidth yields zero. When nothing came across, draw the ring here.
    // Derived from labelColor, never from a semantic system fill: Twitter
    // reinterprets those, and contrast is lost.
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
    // The neighbour's glyph carries the tint the row expects; a template image
    // of ours then renders in the same colour.
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

    if (![BHTSettings boolForKey:@"copy_profile_info"]) {
        return;
    }
    UIView* row = (UIView*)self;
    // Only the profile header's own row, and only the one under the banner.
    UIView* header = row.superview;
    if (![NSStringFromClass([header classForCoder])
            isEqualToString:@"T1ProfileHeaderView"] || nfbRowIsOverlay(row)) {
        return;
    }
    UIView* anchor = nfbLeftmostRowButton(row);
    if (!anchor || CGRectIsEmpty(anchor.frame)) {
        return;
    }

    UIButton* copyButton = objc_getAssociatedObject(row, &kNFBCopyButtonKey);
    if (!copyButton) {
        copyButton = [UIButton buttonWithType:UIButtonTypeSystem];
        copyButton.accessibilityLabel =
            [[BHTBundle sharedBundle] localizedStringForKey:@"COPY_PROFILE_INFO_TITLE"];
        copyButton.showsMenuAsPrimaryAction = YES;

        ProfileCopyButtonProvider* provider = [ProfileCopyButtonProvider new];
        // The provider reads the profile through the header's view controller,
        // reached from the responder chain rather than stored — the header is
        // rebuilt more often than the row.
        UIResponder* responder = row;
        while (responder && ![responder isKindOfClass:[UIViewController class]]) {
            responder = responder.nextResponder;
        }
        provider.headerViewController = (id)responder;
        objc_setAssociatedObject(copyButton, &kCopyProviderKey, provider,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        __weak ProfileCopyButtonProvider* weakProvider = provider;
        void (^actionsProvider)(void (^)(NSArray<UIMenuElement*>*)) =
            ^(void (^completion)(NSArray<UIMenuElement*>*)) {
                completion([weakProvider copyActions] ?: @[]);
            };
        UIDeferredMenuElement* deferred;
        if (@available(iOS 15.0, *)) {
            deferred = [UIDeferredMenuElement elementWithUncachedProvider:actionsProvider];
        } else {
            deferred = [UIDeferredMenuElement elementWithProvider:actionsProvider];
        }
        copyButton.menu = [UIMenu menuWithTitle:@"" children:@[deferred]];

        UIImage* glyph = [UIImage tfn_vectorImageNamed:@"copy_stroke"
                                                  fitsSize:CGSizeMake(20, 20)
                                                 fillColor:nil];
        [copyButton setImage:[glyph imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
                    forState:UIControlStateNormal];

        objc_setAssociatedObject(row, &kNFBCopyButtonKey, copyButton,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    if (copyButton.superview != row) {
        [row addSubview:copyButton];
    }
    // Positioned every pass: the row lays its own buttons out and ours has to
    // follow them, not a remembered place.
    CGRect slot = anchor.frame;
    slot.origin.x = CGRectGetMinX(anchor.frame) - CGRectGetWidth(anchor.frame) - 8.0;
    copyButton.frame = slot;
    nfbMatchNeighbourStyle(copyButton, anchor);
    NFBMark(copyButton, @"Profile/copyButton");
}

%end


// MARK: - Hide premium offer

%hook T1ProfileSummaryView

- (BOOL)shouldShowGetVerifiedButton {
    return [BHTSettings boolForKey:@"hide_premium_offer"] ? NO : %orig;
}

%end

// MARK: - Show unrounded follower/following counts

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

    NSString* abbreviated = [count tfs_twitterAbbreviated];
    NSNumberFormatter* formatter = [[NSNumberFormatter alloc] init];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    NSString* fullCount = [formatter stringFromNumber:count];

    if (!abbreviated.length || !fullCount.length || [abbreviated isEqualToString:fullCount]) {
        return original;
    }

    NSRange range = [[original string] rangeOfString:abbreviated];
    if (range.location == NSNotFound) {
        return original;
    }

    NSMutableAttributedString* expanded = [original mutableCopy];
    [expanded replaceCharactersInRange:range withString:fullCount];
    return [expanded copy];
}

%end

// MARK: - Open profiles on a chosen tab

// From the Objective-C metadata in the app binary:
// T1ProfileDisplayContentProvider carries
// initialTabIndex and setInitialTabIndex:, and its subclass exposes one entry
// per tab — allPostsEntry, tweetsAndRepliesEntry, highlightsEntry,
// articlesEntry, photoEntry, videoEntry.
//
// The index is never hardcoded: the wanted entry is looked up inside
// contentMainEntries, so a profile that lacks Articles or Highlights still
// lands on the right tab. If the entry is missing entirely — a profile with no
// media — the original value is returned and nothing changes.

// The wanted tab, as the entry object itself. Each tab is a
// T1ProfileContentMainEntry, and the provider keeps one per tab —
// _photoEntry, _videoEntry and so on, straight from the class's ivars.
static id nfbWantedEntry(id provider) {
    NSString* name = nil;
    switch ([BHTSettings integerForKey:@"profile_initial_tab"]) {
        case 1: name = @"tweetsAndRepliesEntry"; break;
        case 2: name = @"highlightsEntry"; break;
        case 3: name = @"articlesEntry"; break;
        case 4: name = @"photoEntry"; break;
        case 5: name = @"videoEntry"; break;
        case 6: name = @"repostsEntry"; break;
        default: return nil;   // 0 leaves the choice to Twitter
    }

    // A tab hidden by one of the tweak's own switches is refused here too, in case an
    // old choice survives in the settings after the tab was switched off.
    NSString* hider = nil;
    switch ([BHTSettings integerForKey:@"profile_initial_tab"]) {
        case 2: hider = @"disable_highlights"; break;
        case 3: hider = @"disable_articles"; break;
        case 5: hider = @"disable_videos_tab"; break;
        default: break;
    }
    if (hider && [BHTSettings boolForKey:hider]) {
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
    // No identity check against contentMainEntries: the diagnostic came back
    // yellow, which means the entry existed but the array did not contain that
    // exact object. Whether a tab is actually on screen is answered further
    // down by the controller itself, which is the authority on it.
    return entry;
}

static NSInteger nfbProfileTabIndex(id provider, NSInteger fallback) {
    id entry = nfbWantedEntry(provider);
    if (!entry) {
        return fallback;
    }
    NSArray* entries =
        ((id (*)(id, SEL))objc_msgSend)(provider, @selector(contentMainEntries));
    NSUInteger index = [entries indexOfObject:entry];
    return index == NSNotFound ? fallback : (NSInteger)index;
}

// The provider only *describes* the tabs; the controller is what selects
// one. T1ProfileViewController owns _t1_selectMainEntry:, and asking it
// directly is what actually moves the profile.

static const void* kNFBTabAppliedKey = &kNFBTabAppliedKey;

%hook T1ProfileViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;

    @try {
        id controller = self;
        if (objc_getAssociatedObject(controller, kNFBTabAppliedKey)) {
            return;
        }
        if (![controller respondsToSelector:@selector(currentDisplayContentProvider)] ||
            ![controller respondsToSelector:@selector(_t1_selectMainEntry:)]) {
            return;
        }

        id provider = ((id (*)(id, SEL))objc_msgSend)(
            controller, @selector(currentDisplayContentProvider));
        id entry = nfbWantedEntry(provider);


        if (!entry) {
            return;
        }
        // The controller knows whether that entry has a tab on screen. Asking
        // it is more reliable than comparing objects ourselves, and it keeps
        // the guard: a profile without that tab is left alone.
        if ([controller respondsToSelector:@selector(_t1_outerTabIndexForEntry:)]) {
            NSInteger index = ((NSInteger (*)(id, SEL, id))objc_msgSend)(
                controller, @selector(_t1_outerTabIndexForEntry:), entry);
            if (index < 0 || index == NSNotFound) {
                return;
            }
        }
        objc_setAssociatedObject(controller, kNFBTabAppliedKey, @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        ((void (*)(id, SEL, id))objc_msgSend)(
            controller, @selector(_t1_selectMainEntry:), entry);
    } @catch (id exception) {
    }
}

%end

%hook T1ProfileDisplayContentProvider

- (NSInteger)initialTabIndex {
    NSInteger original = %orig;

    @try {
        return nfbProfileTabIndex(self, original);
    } @catch (id exception) {
        return original;
    }
}

// The real lever. defaultMainContentEntry holds the entry object Twitter
// treats as the landing tab — initialTabIndex is only an index derived from
// it, which is why forcing the index alone changed nothing.
- (id)defaultMainContentEntry {
    id original = %orig;

    @try {
        return nfbWantedEntry(self) ?: original;
    } @catch (id exception) {
        return original;
    }
}

- (void)setInitialTabIndex:(NSInteger)index {
    NSInteger wanted = index;

    @try {
        wanted = nfbProfileTabIndex(self, index);
    } @catch (id exception) {
        wanted = index;
    }
    %orig(wanted);
}

%end

// MARK: - Hide the Videos tab

// Articles and Highlights are switched off through their feature flags, but no
// flag governs the Videos tab. The model decides instead: shouldDisplayVideosTab
// on T1ProfileUserViewModel, read straight from the binary's method table. Same
// shape as the premium-offer hook above — one boolean, nothing to walk.

%hook T1ProfileUserViewModel

- (BOOL)shouldDisplayVideosTab {
    return [BHTSettings boolForKey:@"disable_videos_tab"] ? NO : %orig;
}

%end

// MARK: - Expand bios

// No more "Show more" on a truncated bio. T1ProfileUserInfoView holds
// _bioExpanded, a plain BOOL paired with a tap recogniser, and exposes it as
// isBioExpanded / setBioExpanded:. That is the inline truncation.
//
// It is NOT _expandedBioButton, which belongs to the Premium long bio and
// opens a modal — forcing that one would pop a sheet on every profile.
//
// Forcing the getter is enough: the layout asks it whether to clip, and the
// button that offered the tap has nothing left to reveal.

%hook T1ProfileUserInfoView

- (BOOL)isBioExpanded {
    return [BHTSettings boolForKey:@"expand_bio"] ? YES : %orig;
}

%end
