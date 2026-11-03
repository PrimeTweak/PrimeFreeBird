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
// Fetches a profile photo through the card's cache; the block runs on the main queue, with nil
// when the download fails.
+ (void)fetchAvatarFromURL:(NSURL*)url completion:(void (^)(UIImage* image))completion;
@end
