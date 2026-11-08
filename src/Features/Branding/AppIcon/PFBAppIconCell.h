// A cell of the app icon picker, styled like the app's native AppIconCell.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// The selection mark under each icon, and the room above it, as on Twitter's Premium page.
static const CGFloat kAppIconIndicatorSize = 24.0;
static const CGFloat kAppIconIndicatorGap = 17.0;

@interface PFBAppIconCell : UICollectionViewCell

- (void)configureWithImage:(nullable UIImage*)image
                    active:(BOOL)active
               accentColor:(UIColor*)accentColor;

+ (NSString*)reuseIdentifier;

@end

NS_ASSUME_NONNULL_END
