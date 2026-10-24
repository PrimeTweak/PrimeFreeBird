// The Timelines settings page.

#import "Settings/Pages/PFBTimelinesSettingsViewController.h"
#import "Settings/PFBModernSettingsCells.h"
#import "Support/HookHelpers.h"

// The Retweets choices, in PFBRetweetsChoice order.
static NSArray<NSString*>* PFBRetweetsTitleKeys(void) {
    return @[ @"RETWEETS_SHOW_ALL", @"RETWEETS_HIDE_BLOCKED", @"RETWEETS_HIDE_ALL" ];
}

static NSInteger PFBRetweetsCurrent(void) {
    NSInteger choice = [PFBSettings integerForKey:@"hide_blocked_retweets"];
    return choice >= PFBRetweetsAll && choice <= PFBRetweetsNone ? choice : PFBRetweetsAll;
}

@implementation PFBTimelinesSettingsViewController

- (NSString*)pageKey {
    return @"timelines";
}

- (UITableViewCell*)tableView:(UITableView*)tableView
        cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    NSDictionary* settingData = self.visibleToggles[indexPath.row];
    if ([settingData[@"key"] isEqualToString:@"hide_blocked_retweets"]) {
        PFBModernSettingsCompactButtonCell* cell =
            [tableView dequeueReusableCellWithIdentifier:@"CompactButtonCell"
                                            forIndexPath:indexPath];
        PFBBundle* bundle = [PFBBundle sharedBundle];
        [cell configureWithTitle:[bundle localizedStringForKey:settingData[@"titleKey"]]
                        subtitle:[bundle localizedStringForKey:PFBRetweetsTitleKeys()[PFBRetweetsCurrent()]]
                          detail:[self localizedDetailForKey:@"hide_blocked_retweets"]];
        [self attachMenuIfNeeded:cell entry:settingData];
        return cell;
    }
    return [super tableView:tableView cellForRowAtIndexPath:indexPath];
}

- (UIMenu*)retweetsMenu {
    PFBBundle* bundle = [PFBBundle sharedBundle];
    NSArray<NSString*>* titleKeys = PFBRetweetsTitleKeys();
    NSInteger current = PFBRetweetsCurrent();
    NSMutableArray<UIAction*>* actions = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;
    for (NSInteger choice = 0; choice < (NSInteger)titleKeys.count; choice++) {
        UIAction* action = [UIAction actionWithTitle:[bundle localizedStringForKey:titleKeys[choice]]
                                               image:nil
                                          identifier:nil
                                             handler:^(__unused UIAction* chosen) {
                                                 [[NSUserDefaults standardUserDefaults]
                                                     setInteger:choice
                                                         forKey:@"hide_blocked_retweets"];
                                                 [weakSelf.tableView reloadData];
                                             }];
        action.state = choice == current ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:action];
    }
    return [UIMenu menuWithTitle:[bundle localizedStringForKey:@"HIDE_BLOCKED_RETWEETS_TITLE"]
                        children:actions];
}

- (void)switchChanged:(UISwitch*)sender {
    [super switchChanged:sender];
    NSString* key = objc_getAssociatedObject(sender, @"prefKey");
    if ([key isEqualToString:@"hide_custom_timelines"]) {
        PFBApplyHideCustomTimelinesSetting();
    }
}

@end
