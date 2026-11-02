// A sample of Twitter in the accent color, for the new look's Theme color: a Tweet with a link, a
// mention and a hashtag, then the tab bar beside the compose button, on glass.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface PFBAccentPreviewView : UIView
// The selected tab takes the accent only when Selected tab is on, as on the real bar.
- (void)applyAccent:(UIColor*)accent tintsSelectedTab:(BOOL)tintsSelectedTab;
@end

NS_ASSUME_NONNULL_END
