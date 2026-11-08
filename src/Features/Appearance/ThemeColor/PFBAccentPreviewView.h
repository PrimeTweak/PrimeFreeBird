// A sample of Twitter in the accent color, for the new look's Theme color: a small home screen
// with the bird on top, the For you tab, a Tweet with a link, a mention and a hashtag, then the
// tab bar beside the compose button.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// The margin around the sample's screen.
static const CGFloat kPFBAccentPreviewInset = 10.0;

@interface PFBAccentPreviewView : UIView
// The selected tab and its underline take the accent only when Selected tab is on, and the bird on
// top only when Twitter icon is on, as in the app.
- (void)applyAccent:(UIColor*)accent tintsSelectedTab:(BOOL)tintsSelectedTab tintsLogo:(BOOL)tintsLogo;
// The reader's profile photo in the top bar, as on the home screen; the gray circle stays until it
// comes.
- (void)showReaderPhoto:(nullable UIImage*)photo;
@end

NS_ASSUME_NONNULL_END
