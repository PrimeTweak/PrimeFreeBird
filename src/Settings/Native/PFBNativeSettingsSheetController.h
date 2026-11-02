// One group of a settings page in a sheet, as Twitter's new settings show theirs.

#import <UIKit/UIKit.h>

// What a sheet holds: a controller whose view shows its rows in this table.
@protocol PFBNativeSheetRows <NSObject>
@property (nonatomic, strong, readonly) UITableView* tableView;
@end

@interface PFBNativeSettingsSheetController : UIViewController

// The rows show a single group; closed runs once the sheet has gone, however it was closed.
+ (void)presentRows:(UIViewController<PFBNativeSheetRows>*)rows
             titled:(NSString*)title
               from:(UIViewController*)presenter
             closed:(void (^)(void))closed;

@end
