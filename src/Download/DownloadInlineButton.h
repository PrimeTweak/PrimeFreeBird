// The inline download button under a Tweet's media.

@import UIKit;
#import "Core/BHTManager.h"

NS_ASSUME_NONNULL_BEGIN

// Presents the download quality/options sheet for a tweet's media. Formerly an
// inline action-bar button; now driven from the tweet overflow (3-dot) menu.
@interface DownloadInlineButton : NSObject

- (void)presentDownloadOptionsForMediaEntities:(NSArray*)mediaEntities;

@end

NS_ASSUME_NONNULL_END
