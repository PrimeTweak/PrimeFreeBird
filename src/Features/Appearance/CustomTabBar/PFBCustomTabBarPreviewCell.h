// The tab-bar preview cell of the tab editor.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface PFBCustomTabBarPreviewCell : UICollectionViewCell

- (void)configureWithImageName:(nullable NSString*)imageName;

+ (NSString*)reuseIdentifier;

@end

NS_ASSUME_NONNULL_END
