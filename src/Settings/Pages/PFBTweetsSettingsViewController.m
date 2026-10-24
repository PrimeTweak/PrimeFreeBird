// The Tweets settings page.

#import "Settings/Pages/PFBTweetsSettingsViewController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "Common/PFBBundle.h"
#import "Common/PFBSettings.h"
#import "Support/HookHelpers.h"
#import "Settings/PFBModernSettingsCells.h"

// Off, then Twitter's three orders under its own names, in the order its menu lists them.
static NSArray<NSArray*>* PFBReplySortingChoices(void) {
    return @[
        @[ @(PFBReplySortOff), @"GENERIC_OFF_LABEL" ],
        @[ @(PFBReplySortRelevant), @"TIMELINE_SORT_REPLIES_BY_RELEVANT" ],
        @[ @(PFBReplySortRecent), @"TIMELINE_SORT_REPLIES_BY_RECENT" ],
        @[ @(PFBReplySortLiked), @"TIMELINE_SORT_REPLIES_BY_LIKED" ],
    ];
}

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
        [cell configureWithTitle:title
                        subtitle:[self undoTimeoutSubtitle]
                          detail:[self localizedDetailForKey:@"undo_tweet_timeout"]];
        [self attachMenuIfNeeded:cell entry:settingData];
        return cell;
    }
    if ([settingData[@"key"] isEqualToString:@"reply_sorting"]) {
        PFBModernSettingsCompactButtonCell* cell =
            [tableView dequeueReusableCellWithIdentifier:@"CompactButtonCell"
                                            forIndexPath:indexPath];
        NSString* title = [[PFBBundle sharedBundle] localizedStringForKey:settingData[@"titleKey"]];
        [cell configureWithTitle:title
                        subtitle:[self replySortingSubtitle]
                          detail:[self localizedDetailForKey:@"reply_sorting"]];
        [self attachMenuIfNeeded:cell entry:settingData];
        return cell;
    }
    // The sound's name sits on the right; the buttons below the row change it.
    if ([settingData[@"key"] isEqualToString:@"send_sound"]) {
        PFBModernSettingsCompactButtonCell* cell =
            [tableView dequeueReusableCellWithIdentifier:@"CompactButtonCell"
                                            forIndexPath:indexPath];
        NSString* title = [[PFBBundle sharedBundle] localizedStringForKey:settingData[@"titleKey"]];
        [cell configureWithTitle:title
                        subtitle:[self sendSoundSubtitle]
                          detail:[self localizedDetailForKey:@"send_sound"]];
        [cell setShowsChevron:NO];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    if ([settingData[@"key"] isEqualToString:@"send_sound_actions"]) {
        PFBModernSettingsButtonPairCell* cell =
            (PFBModernSettingsButtonPairCell*)[super tableView:tableView cellForRowAtIndexPath:indexPath];
        [cell setSecondEnabled:PFBSendSoundIsSet()];
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

- (NSString*)replySortingSubtitle {
    NSInteger current = [PFBSettings integerForKey:@"reply_sorting"];
    for (NSArray* choice in PFBReplySortingChoices()) {
        if ([choice[0] integerValue] == current) {
            return [[PFBBundle sharedBundle] localizedTwitterStringForKey:choice[1]];
        }
    }
    return [[PFBBundle sharedBundle] localizedTwitterStringForKey:@"GENERIC_OFF_LABEL"];
}

- (UIMenu*)replySortingMenu {
    PFBBundle* bundle = [PFBBundle sharedBundle];
    NSInteger current = [PFBSettings integerForKey:@"reply_sorting"];
    NSMutableArray<UIAction*>* actions = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;
    for (NSArray* choice in PFBReplySortingChoices()) {
        NSInteger value = [choice[0] integerValue];
        UIAction* action = [UIAction actionWithTitle:[bundle localizedTwitterStringForKey:choice[1]]
                                               image:nil
                                          identifier:nil
                                             handler:^(__unused UIAction* chosen) {
                                                 [[NSUserDefaults standardUserDefaults] setInteger:value
                                                                                            forKey:@"reply_sorting"];
                                                 [weakSelf.tableView reloadData];
                                             }];
        action.state = value == current ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:action];
    }
    return [UIMenu menuWithTitle:[bundle localizedTwitterStringForKey:@"TIMELINE_SORT_REPLIES_TITLE"]
                        children:actions];
}

// MARK: - Send sound

// The imported sound's name, or None. The file on disk decides, since the stored name
// can outlive it.
- (NSString*)sendSoundSubtitle {
    NSString* name = PFBSendSoundIsSet() ? PFBSendSoundName() : nil;
    return name.length ? name : [[PFBBundle sharedBundle] localizedStringForKey:@"SEND_SOUND_NONE"];
}

- (void)importSendSound:(UIButton*)sender {
    UIDocumentPickerViewController* picker =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[ UTTypeAudio ] asCopy:YES];
    picker.delegate = self;
    objc_setAssociatedObject(picker, @"pickerType", @"sendSound", OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)removeSendSound:(UIButton*)sender {
    PFBSendSoundRemove();
    [self reloadSendSoundRows];
}

// The sound picker's file becomes the send sound; any other picker is the settings import.
- (void)documentPicker:(UIDocumentPickerViewController*)controller
    didPickDocumentsAtURLs:(NSArray<NSURL*>*)urls {
    if (![objc_getAssociatedObject(controller, @"pickerType") isEqualToString:@"sendSound"]) {
        [super documentPicker:controller didPickDocumentsAtURLs:urls];
        return;
    }
    NSURL* url = urls.firstObject;
    if (!url) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    PFBSendSoundImport(url, ^(NSString* failureKey) {
        // The picker handed over a copy, no longer needed once read.
        [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
        [weakSelf reloadSendSoundRows];
        if (failureKey) {
            [weakSelf showSendSoundFailure:failureKey];
        }
    });
}

// The name row and the Remove button both follow the stored sound.
- (void)reloadSendSoundRows {
    NSMutableArray<NSIndexPath*>* paths = [NSMutableArray array];
    [self.visibleToggles enumerateObjectsUsingBlock:^(NSDictionary* entry, NSUInteger row, BOOL* stop) {
        NSString* key = entry[@"key"];
        if ([key isEqualToString:@"send_sound"] || [key isEqualToString:@"send_sound_actions"]) {
            [paths addObject:[NSIndexPath indexPathForRow:(NSInteger)row inSection:0]];
        }
    }];
    if (paths.count) {
        [self.tableView reloadRowsAtIndexPaths:paths withRowAnimation:UITableViewRowAnimationNone];
    }
}

- (void)showSendSoundFailure:(NSString*)messageKey {
    PFBBundle* bundle = [PFBBundle sharedBundle];
    UIAlertController* alert =
        [UIAlertController alertControllerWithTitle:[bundle localizedStringForKey:@"SEND_SOUND_FAILED_TITLE"]
                                            message:[bundle localizedStringForKey:messageKey]
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:[bundle localizedStringForKey:@"OK_ACTION"]
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
