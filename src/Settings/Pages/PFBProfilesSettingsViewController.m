// The Profiles settings page.

#import "Settings/Pages/PFBProfilesSettingsViewController.h"
#import "Common/PFBBundle.h"
#import "Common/PFBSettings.h"
#import "Support/TWHeaders.h"

extern void PFBApplySquareAvatarsSetting(void);

@implementation PFBProfilesSettingsViewController

- (NSString*)pageKey {
    return @"profiles";
}

// Seven values, offered as a menu on the row. "Default" keeps whatever Twitter chooses,
// which is also what a profile without that tab falls back to.
- (UIMenu*)profileTabMenu {
    PFBBundle* bundle = [PFBBundle sharedBundle];
    // A hidden tab is not offered: Highlights, Articles and Videos each have their own
    // switch on this page, and a tab that never appears would be a silent no-op.
    NSArray<NSString*>* titleKeys = @[
        @"PROFILE_TAB_DEFAULT",
        @"PROFILE_TAB_REPLIES",
        @"PROFILE_TAB_HIGHLIGHTS",
        @"PROFILE_TAB_ARTICLES",
        @"PROFILE_TAB_MEDIA",
        @"PROFILE_TAB_VIDEOS",
        @"PROFILE_TAB_REPOSTS"
    ];
    NSArray<NSString*>* hiddenBy = @[
        @"",                      // Default, never hidden
        @"",                      // Replies, no hide option
        @"disable_highlights",
        @"disable_articles",
        @"",                      // Media, no hide option
        @"disable_videos_tab",
        @""                       // Reposts, no hide option
    ];
    NSInteger current = [PFBSettings integerForKey:@"profile_initial_tab"];
    // A chosen tab that has since been hidden falls back to Default, as the profile does.
    NSString* currentHider = (current < (NSInteger)hiddenBy.count) ? hiddenBy[current] : @"";
    if (currentHider.length && [PFBSettings boolForKey:currentHider]) {
        current = 0;
    }

    NSMutableArray<UIAction*>* actions = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;
    for (NSInteger i = 0; i < (NSInteger)titleKeys.count; i++) {
        NSString* hider = hiddenBy[i];
        if (hider.length && [PFBSettings boolForKey:hider]) {
            continue;
        }
        UIAction* action = [UIAction actionWithTitle:[bundle localizedStringForKey:titleKeys[i]]
                                               image:nil
                                          identifier:nil
                                             handler:^(__unused UIAction* chosen) {
                                                 [[NSUserDefaults standardUserDefaults]
                                                     setInteger:i
                                                         forKey:@"profile_initial_tab"];
                                                 [weakSelf.tableView reloadData];
                                             }];
        action.state = i == current ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:action];
    }
    return [UIMenu menuWithTitle:[bundle localizedStringForKey:@"PROFILE_INITIAL_TAB_TITLE"]
                        children:actions];
}

- (void)switchChanged:(UISwitch*)sender {
    [super switchChanged:sender];
    NSString* key = objc_getAssociatedObject(sender, @"prefKey");
    if ([key isEqualToString:@"square_avatars"]) {
        PFBApplySquareAvatarsSetting();
    }
}

@end
