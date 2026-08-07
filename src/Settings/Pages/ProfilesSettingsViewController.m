//
//  ProfilesSettingsViewController.m
//  PrimeFreeBird
//
//  Created by nyaathea
//

#import "Settings/Pages/ProfilesSettingsViewController.h"
#import "Core/BHTBundle.h"
#import "Core/BHTSettings.h"
#import "Headers/TWHeaders.h"

extern void applySquareAvatarsSetting(void);

@implementation ProfilesSettingsViewController

- (NSString*)pageKey {
    return @"profiles";
}

// Six values, so a picker rather than a toggle — same native alert the
// Appearance page uses. "Default" keeps whatever Twitter chooses, which is
// also what a profile without that tab falls back to.
- (void)showProfileTabPicker:(NSDictionary*)sender {
    BHTBundle* bundle = [BHTBundle sharedBundle];
    UIAlertController* sheet = [UIAlertController
        alertControllerWithTitle:[bundle localizedStringForKey:@"PROFILE_INITIAL_TAB_TITLE"]
                         message:[bundle localizedStringForKey:@"PROFILE_INITIAL_TAB_DETAIL"]
                  preferredStyle:UIAlertControllerStyleAlert];

    // A tab you have hidden is not offered here. Highlights, Articles and
    // Videos each have their own switch on this very page, and listing a tab
    // that will never appear invites a choice that silently does nothing.
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
        @"",                      // Default, jamais masqué
        @"",                      // Replies, pas d'option
        @"disable_highlights",
        @"disable_articles",
        @"",                      // Media, pas d'option
        @"disable_videos_tab",
        @""                       // Reposts, pas d'option
    ];
    NSInteger current = [BHTSettings integerForKey:@"profile_initial_tab"];
    // If the chosen tab has since been hidden, the checkmark falls back to
    // Default — which is exactly what the profile will do.
    NSString* currentHider = (current < (NSInteger)hiddenBy.count) ? hiddenBy[current] : @"";
    if (currentHider.length && [BHTSettings boolForKey:currentHider]) {
        current = 0;
    }

    __weak typeof(self) weakSelf = self;
    for (NSInteger i = 0; i < (NSInteger)titleKeys.count; i++) {
        NSString* hider = hiddenBy[i];
        if (hider.length && [BHTSettings boolForKey:hider]) {
            continue;
        }
        NSString* title = [bundle localizedStringForKey:titleKeys[i]];
        [self addOption:title
               selected:(i == current)
               toPicker:sheet
                handler:^{
                    [[NSUserDefaults standardUserDefaults]
                        setInteger:i
                            forKey:@"profile_initial_tab"];
                    [[NSUserDefaults standardUserDefaults] synchronize];
                    [weakSelf.tableView reloadData];
                }];
    }
    [sheet addAction:[UIAlertAction
                         actionWithTitle:[bundle localizedTwitterStringForKey:@"CANCEL_ACTION_LABEL"]
                                   style:UIAlertActionStyleCancel
                                 handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)switchChanged:(UISwitch*)sender {
    [super switchChanged:sender];
    NSString* key = objc_getAssociatedObject(sender, @"prefKey");
    if ([key isEqualToString:@"square_avatars"]) {
        applySquareAvatarsSetting();
    }
}

@end
