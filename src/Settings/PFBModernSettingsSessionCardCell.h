#import <UIKit/UIKit.h>

// The state of the web session, with the two actions that change it. It replaces
// a sign-in row and a clear row that could say nothing about whether there was
// anything to sign out of.
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
