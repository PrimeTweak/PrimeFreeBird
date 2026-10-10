// A settings page: builds its rows from PFBSettings and handles their actions.

#import <UIKit/UIKit.h>

@class TFNTwitterAccount;

@interface PFBModernSettingsPageViewController
    : UIViewController <UITableViewDataSource, UITableViewDelegate, UIDocumentPickerDelegate>

@property (nonatomic, strong) TFNTwitterAccount* account;
@property (nonatomic, strong) UITableView* tableView;
@property (nonatomic, strong) NSArray<NSDictionary*>* toggles;
@property (nonatomic, strong) NSArray<NSDictionary*>* visibleToggles;

- (instancetype)initWithAccount:(TFNTwitterAccount*)account;

// Redraws the rows whose `disabledWhen` names this key.
- (void)reloadRowsHeldBy:(NSString*)key;

// Data-only pages are created directly with their registry key; pages with
// custom behavior subclass this and override -pageKey instead.
- (instancetype)initWithAccount:(TFNTwitterAccount*)account pageKey:(NSString*)pageKey;

// Identifies the page's entry in the PFBSettings registry
- (NSString*)pageKey;

- (NSString*)pageTitleKey;
- (NSString*)pageSubtitleKey;
- (void)buildSettingsList;

- (void)updateVisibleToggles;
- (void)switchChanged:(UISwitch*)sender;
- (void)showRestartRequiredAlert;

// Adds one option to a picker alert and marks it when it is the current choice.
// Every picker goes through here so the mark is decided in one place.
- (void)addOption:(NSString*)title
         selected:(BOOL)selected
         toPicker:(UIAlertController*)picker
          handler:(void (^)(void))handler;

// Opens the menu an entry names under "menu" from anywhere on its row.
- (void)attachMenuIfNeeded:(UITableViewCell*)cell entry:(NSDictionary*)entry;
@end
