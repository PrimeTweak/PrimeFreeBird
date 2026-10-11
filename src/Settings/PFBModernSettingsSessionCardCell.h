#import <UIKit/UIKit.h>

// The state of the web session, with the two actions that change it.
@interface PFBModernSettingsSessionCardCell : UITableViewCell
- (void)configureWithHandle:(NSString*)handle
                   signedIn:(BOOL)signedIn
                     detail:(NSString*)detail
               primaryTitle:(NSString*)primaryTitle
           destructiveTitle:(NSString*)destructiveTitle;
- (void)addPrimaryTarget:(id)target action:(SEL)action;
- (void)addDestructiveTarget:(id)target action:(SEL)action;
- (void)loadAvatarFromURL:(NSURL*)url;
@end
