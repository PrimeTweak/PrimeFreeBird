// The look shared by the settings cells: selection shade, fonts and palette colors.
#import <UIKit/UIKit.h>
#import "Features/Appearance/ThemeColor/PFBDarkModeStyle.h"
#import "Features/Appearance/ThemeColor/PFBPalette.h"
#import "Support/TwitterChirpFont.h"

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

// Twitter's fonts and palette colors as the rows use them. Each is read by its getter, so
// one Twitter renamed gives the system equivalent instead of a crash.
static inline UIFont* PFBSettingsTitleFont(void) {
    return PFBFontGroupFont(@selector(bodyBoldFont), [UIFont systemFontOfSize:15 weight:UIFontWeightBold]);
}

static inline UIFont* PFBSettingsDetailFont(void) {
    return PFBFontGroupFont(@selector(subtext2Font), [UIFont systemFontOfSize:13]);
}

static inline UIFont* PFBSettingsActionFont(void) {
    return PFBFontGroupFont(@selector(subtext1BoldFont), [UIFont systemFontOfSize:14 weight:UIFontWeightBold]);
}

static inline UIColor* PFBSettingsTextColor(void) {
    return [PFBPalette colorFor:@selector(textColor) fallback:[UIColor labelColor]];
}

// The color of the lines under the titles.
static inline UIColor* PFBSettingsSubtitleColor(void) {
    return [PFBPalette colorFor:@selector(tabBarItemColor) fallback:[UIColor secondaryLabelColor]];
}

static inline UIColor* PFBSettingsFaintColor(void) {
    return [PFBPalette colorFor:@selector(faintBackgroundColor) fallback:[UIColor secondarySystemBackgroundColor]];
}

static inline UIColor* PFBSettingsAlertColor(void) {
    return [PFBPalette colorFor:@selector(alertColor) fallback:[UIColor systemRedColor]];
}

static inline UIColor* PFBSettingsDividerColor(void) {
    return [PFBPalette colorFor:@selector(dividerColor) fallback:[UIColor separatorColor]];
}
