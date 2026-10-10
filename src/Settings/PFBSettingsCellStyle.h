// The selection shade shared by the settings cells.
#import <UIKit/UIKit.h>
#import "Features/Appearance/ThemeColor/PFBDarkModeStyle.h"

// UIKit paints its own selection in a system gray bright enough to sit above
// the dark-style filter's ceiling, so the row stays gray while the rest of the
// screen is recolored. The shade is handed to the cell directly instead.
static inline void pfbApplySelectedBackground(UITableViewCell* cell) {
    UIColor* shade = [PFBDarkModeStyle elevatedBackgroundColor];
    if (!shade) {
        cell.selectedBackgroundView = nil;
        return;
    }
    UIView* selected = [[UIView alloc] init];
    selected.backgroundColor = shade;
    cell.selectedBackgroundView = selected;
}
