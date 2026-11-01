// Journal lines on how far the rows of a settings list move after an update, and on the
// sheet's height changes. Written only while Record activity is on.

#import <UIKit/UIKit.h>

// Follows the first visible row from now until any animation has ended.
void PFBSettingsWatchRows(UITableView* table, NSString* reason);

// A sheet fitting its height to its rows, while it opens or once open.
void PFBSettingsNoteSheetHeight(CGFloat from, CGFloat to, BOOL opening);
