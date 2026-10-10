// Color helpers around the app's active palette.

#import <UIKit/UIKit.h>

@interface PFBPalette : NSObject

// Twitter's current app background color, read straight from the active
// TAEColorPalette so it always matches the app chrome.
+ (UIColor*)currentBackgroundColor;

@end
