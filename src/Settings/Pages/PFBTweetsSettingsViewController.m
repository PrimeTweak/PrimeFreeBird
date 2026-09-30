// The Tweets settings page.

#import "Settings/Pages/PFBTweetsSettingsViewController.h"
#import "Common/PFBBundle.h"
#import "Common/PFBSettings.h"
#import "Support/TWHeaders.h"
#import "Settings/PFBModernSettingsCells.h"

@implementation PFBTweetsSettingsViewController

- (NSString*)pageKey {
    return @"tweets";
}

- (UITableViewCell*)tableView:(UITableView*)tableView
        cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    NSDictionary* settingData = self.visibleToggles[indexPath.row];
    if ([settingData[@"key"] isEqualToString:@"undo_tweet_timeout"]) {
        PFBModernSettingsCompactButtonCell* cell =
            [tableView dequeueReusableCellWithIdentifier:@"CompactButtonCell"
                                            forIndexPath:indexPath];
        NSString* title = [[PFBBundle sharedBundle] localizedStringForKey:settingData[@"titleKey"]];
        [cell configureWithTitle:title subtitle:[self undoTimeoutSubtitle]];
        [self attachMenuIfNeeded:cell entry:settingData];
        return cell;
    }
    return [super tableView:tableView cellForRowAtIndexPath:indexPath];
}

// A timeout of 0 reads as "Off"; any positive value shows its seconds.
- (NSString*)labelForTimeout:(NSInteger)seconds {
    if (seconds <= 0) {
        return [[PFBBundle sharedBundle] localizedTwitterStringForKey:@"GENERIC_OFF_LABEL"];
    }
    NSString* format = [[PFBBundle sharedBundle]
        localizedTwitterStringForKey:@"SUBSCRIPTION_UNDO_SEND_DURATION_LABEL"];
    return [NSString stringWithFormat:format, (long)seconds];
}

- (NSString*)undoTimeoutSubtitle {
    return [self labelForTimeout:[PFBSettings integerForKey:@"undo_tweet_timeout"]];
}

// Off plus the durations Twitter offers in its own undo settings, the current one checked.
- (UIMenu*)undoTimeoutMenu {
    NSInteger current = [PFBSettings integerForKey:@"undo_tweet_timeout"];
    NSMutableArray<UIAction*>* actions = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;
    for (NSNumber* seconds in @[@0, @5, @10, @20, @30, @60]) {
        UIAction* action = [UIAction actionWithTitle:[self labelForTimeout:seconds.integerValue]
                                               image:nil
                                          identifier:nil
                                             handler:^(__unused UIAction* chosen) {
                                                 [[NSUserDefaults standardUserDefaults]
                                                     setInteger:seconds.integerValue
                                                         forKey:@"undo_tweet_timeout"];
                                                 [weakSelf.tableView reloadData];
                                             }];
        action.state = seconds.integerValue == current ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:action];
    }
    return [UIMenu menuWithTitle:@"" children:actions];
}

@end
