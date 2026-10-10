// The Profiles settings page.

#import "Settings/Pages/PFBProfilesSettingsViewController.h"
#import "Common/PFBBundle.h"
#import "Common/PFBSettings.h"
#import "Support/TWHeaders.h"
#import "Settings/PFBModernSettingsCells.h"

extern void PFBApplySquareAvatarsSetting(void);

// Seven values, offered as a menu on the row. "Default" keeps whatever Twitter chooses,
// which is also what a profile without that tab falls back to.
static NSArray<NSString*>* PFBProfileTabTitleKeys(void) {
    return @[
        @"PROFILE_TAB_DEFAULT",
        @"PROFILE_TAB_REPLIES",
        @"PROFILE_TAB_HIGHLIGHTS",
        @"PROFILE_TAB_ARTICLES",
        @"PROFILE_TAB_MEDIA",
        @"PROFILE_TAB_VIDEOS",
        @"PROFILE_TAB_REPOSTS"
    ];
}

// A hidden tab is not offered: Highlights, Articles and Videos each have their own
// switch on this page, and a tab that never appears would be a silent no-op.
static NSArray<NSString*>* PFBProfileTabHiders(void) {
    return @[
        @"",                      // Default, never hidden
        @"",                      // Replies, no hide option
        @"disable_highlights",
        @"disable_articles",
        @"",                      // Media, no hide option
        @"disable_videos_tab",
        @""                       // Reposts, no hide option
    ];
}

// The chosen tab; one that has since been hidden falls back to Default, as the profile does.
static NSInteger PFBProfileTabCurrent(void) {
    NSArray<NSString*>* hiddenBy = PFBProfileTabHiders();
    NSInteger current = [PFBSettings integerForKey:@"profile_initial_tab"];
    if (current < 0 || current >= (NSInteger)hiddenBy.count) {
        return 0;
    }
    NSString* hider = hiddenBy[current];
    return hider.length && [PFBSettings boolForKey:hider] ? 0 : current;
}

@implementation PFBProfilesSettingsViewController

- (NSString*)pageKey {
    return @"profiles";
}

// The tab row reads like Undo Tweet's: its title, the chosen tab and a chevron.
- (UITableViewCell*)tableView:(UITableView*)tableView
        cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    NSDictionary* settingData = self.visibleToggles[indexPath.row];
    if ([settingData[@"menu"] isEqualToString:@"profileTabMenu"]) {
        PFBModernSettingsCompactButtonCell* cell =
            [tableView dequeueReusableCellWithIdentifier:@"CompactButtonCell"
                                            forIndexPath:indexPath];
        PFBBundle* bundle = [PFBBundle sharedBundle];
        [cell configureWithTitle:[bundle localizedStringForKey:settingData[@"titleKey"]]
                        subtitle:[bundle localizedStringForKey:PFBProfileTabTitleKeys()[PFBProfileTabCurrent()]]];
        [self attachMenuIfNeeded:cell entry:settingData];
        return cell;
    }
    return [super tableView:tableView cellForRowAtIndexPath:indexPath];
}

- (UIMenu*)profileTabMenu {
    PFBBundle* bundle = [PFBBundle sharedBundle];
    NSArray<NSString*>* titleKeys = PFBProfileTabTitleKeys();
    NSArray<NSString*>* hiddenBy = PFBProfileTabHiders();
    NSInteger current = PFBProfileTabCurrent();

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
