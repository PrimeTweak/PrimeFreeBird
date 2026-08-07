//
//  Profile.x
//  PrimeFreeBird
//

#import "HookHelpers.h"

// MARK: - Copy profile info

static char kCopyProviderKey;

@interface ProfileCopyButtonProvider : NSObject
@property (nonatomic, weak) T1ProfileHeaderViewController* headerViewController;
@property (nonatomic, weak) id delegate;
@property (nonatomic, strong) TFNButton* infoButton;
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

- (TFNButton*)buttonView {
    if (!self.infoButton) {
        // Style 2 in size class 2 is the bordered round icon style the other
        // header buttons use.
        TFNButton* button = [%c(TFNButton) buttonWithTitle:nil
                                                    imageNamed:@"copy_stroke"
                                                         style:2
                                                     sizeClass:2];
        button.accessibilityLabel =
            [[BHTBundle sharedBundle] localizedStringForKey:@"COPY_PROFILE_INFO_TITLE"];
        button.showsMenuAsPrimaryAction = YES;

        // Deferred so each open rebuilds the actions with the loaded profile
        // data and the current theme's icon color.
        __weak ProfileCopyButtonProvider* weakSelf = self;
        void (^actionsProvider)(void (^)(NSArray<UIMenuElement*>*)) =
            ^(void (^completion)(NSArray<UIMenuElement*>*)) {
                completion([weakSelf copyActions] ?: @[]);
            };
        UIDeferredMenuElement* deferredActions;
        if (@available(iOS 15.0, *)) {
            deferredActions = [UIDeferredMenuElement elementWithUncachedProvider:actionsProvider];
        } else {
            deferredActions = [UIDeferredMenuElement elementWithProvider:actionsProvider];
        }
        button.menu = [UIMenu menuWithTitle:@"" children:@[deferredActions]];

        self.infoButton = button;
    }
    return self.infoButton;
}

- (NSArray*)buttonSpecs {
    // Native positions run from 2 (follow) to 10 (mute), so 100 lands at the
    // far end; priority 1 lets every native button win the width fight.
    __weak ProfileCopyButtonProvider* weakSelf = self;
    T1ProfileActionButtonSpec* spec = [[%c(T1ProfileActionButtonSpec) alloc] initWithPosition:100
        priority:1
        visibilityBlock:^BOOL(double availableWidth) {
            return YES;
        }
        buttonCreationBlock:^UIView* {
            return [weakSelf buttonView];
        }];
    return spec ? @[spec] : @[];
}

@end

%hook T1ProfileHeaderViewController

- (NSArray*)actionButtonProviders {
    NSArray* providers = %orig;

    if (![BHTSettings boolForKey:@"copy_profile_info"]) {
        return providers;
    }

    ProfileCopyButtonProvider* copyProvider = objc_getAssociatedObject(self, &kCopyProviderKey);
    if (!copyProvider) {
        copyProvider = [ProfileCopyButtonProvider new];
        copyProvider.headerViewController = self;
        objc_setAssociatedObject(self, &kCopyProviderKey, copyProvider,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return [providers arrayByAddingObject:copyProvider];
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

// No guesswork here: the Objective-C metadata in the decrypted binary was
// parsed to find who really owns this. T1ProfileDisplayContentProvider carries
// initialTabIndex and setInitialTabIndex:, and its subclass exposes one entry
// per tab — allPostsEntry, tweetsAndRepliesEntry, highlightsEntry,
// articlesEntry, photoEntry, videoEntry.
//
// The index is never hardcoded: the wanted entry is looked up inside
// contentMainEntries, so a profile that lacks Articles or Highlights still
// lands on the right tab. If the entry is missing entirely — a profile with no
// media — the original value is returned and nothing changes.

static NSInteger nfbProfileTabIndex(id provider, NSInteger fallback) {
    NSString* wanted = nil;
    switch ([BHTSettings integerForKey:@"profile_initial_tab"]) {
        case 1: wanted = @"tweetsAndRepliesEntry"; break;
        case 2: wanted = @"highlightsEntry"; break;
        case 3: wanted = @"articlesEntry"; break;
        case 4: wanted = @"photoEntry"; break;
        case 5: wanted = @"videoEntry"; break;
        default: return fallback;   // 0 = laisser Twitter décider
    }

    SEL entrySelector = NSSelectorFromString(wanted);
    if (![provider respondsToSelector:entrySelector] ||
        ![provider respondsToSelector:@selector(contentMainEntries)]) {
        return fallback;
    }
    id entry = ((id (*)(id, SEL))objc_msgSend)(provider, entrySelector);
    NSArray* entries =
        ((id (*)(id, SEL))objc_msgSend)(provider, @selector(contentMainEntries));
    if (!entry || ![entries isKindOfClass:[NSArray class]]) {
        return fallback;
    }
    NSUInteger index = [entries indexOfObject:entry];
    return index == NSNotFound ? fallback : (NSInteger)index;
}

%hook T1ProfileDisplayContentProvider

- (NSInteger)initialTabIndex {
    NSInteger original = %orig;

    @try {
        return nfbProfileTabIndex(self, original);
    } @catch (id exception) {
        return original;
    }
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

// No more "Show more" on a truncated bio. The binary's metadata settled what I
// had first guessed wrong: T1ProfileUserInfoView holds _bioExpanded, a plain
// BOOL paired with a tap recogniser, and exposes it as isBioExpanded /
// setBioExpanded:. That is the inline truncation.
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
