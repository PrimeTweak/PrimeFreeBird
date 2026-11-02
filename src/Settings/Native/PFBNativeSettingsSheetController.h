// One group of a settings page in a sheet, as Twitter's new settings show theirs.

#import <UIKit/UIKit.h>

// What a sheet holds: a controller whose view shows its rows in this table.
@protocol PFBNativeSheetRows <NSObject>
@property (nonatomic, strong, readonly) UITableView* tableView;
@end

// The head of the new look's sheets, as Twitter's Tray draws its own: the title with a close
// button after it, or for a step the title centered after a back button, then a line.
@interface PFBNativeSheetHead : UIView
- (instancetype)initWithTitle:(NSString*)title step:(BOOL)step;
@property (nonatomic, strong, readonly) UILabel* titleLabel;
// The close button, or a step's back button.
@property (nonatomic, strong, readonly) UIButton* button;
@end

@interface PFBNativeSettingsSheetController : UIViewController

// The rows show a single group; closed runs once the sheet has gone, however it was closed.
+ (void)presentRows:(UIViewController<PFBNativeSheetRows>*)rows
             titled:(NSString*)title
               from:(UIViewController*)presenter
             closed:(void (^)(void))closed;

// A sheet of its own for a value to type: the title, the note, the field and Save, which hands the
// text over before the sheet closes.
+ (void)presentFieldTitled:(NSString*)title
                      note:(NSString*)note
                     value:(NSString*)value
               placeholder:(NSString*)placeholder
                      from:(UIViewController*)presenter
                      save:(void (^)(NSString* text))save;

// A step of the sheet with the menu's choices under its title and the note, the current one
// marked; picking one runs its action, and the back button returns to the rows.
- (void)showChoices:(UIMenu*)menu note:(NSString*)note;

@end
