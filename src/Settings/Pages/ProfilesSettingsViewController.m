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

    NSArray<NSString*>* titleKeys = @[
        @"PROFILE_TAB_DEFAULT",
        @"PROFILE_TAB_REPLIES",
        @"PROFILE_TAB_HIGHLIGHTS",
        @"PROFILE_TAB_ARTICLES",
        @"PROFILE_TAB_MEDIA",
        @"PROFILE_TAB_VIDEOS"
    ];
    NSInteger current = [BHTSettings integerForKey:@"profile_initial_tab"];

    __weak typeof(self) weakSelf = self;
    for (NSInteger i = 0; i < (NSInteger)titleKeys.count; i++) {
        NSString* title = [bundle localizedStringForKey:titleKeys[i]];
        if (i == current) {
            title = [NSString stringWithFormat:@"\u2713 %@", title];
        }
        [sheet addAction:[UIAlertAction
                             actionWithTitle:title
                                       style:UIAlertActionStyleDefault
                                     handler:^(UIAlertAction* a) {
                                         [[NSUserDefaults standardUserDefaults]
                                             setInteger:i
                                                 forKey:@"profile_initial_tab"];
                                         [[NSUserDefaults standardUserDefaults] synchronize];
                                         [weakSelf.tableView reloadData];
                                     }]];
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
