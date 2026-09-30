// The inline download button under a Tweet's media.

@import UIKit;
#import "Support/PFBManager.h"

NS_ASSUME_NONNULL_BEGIN

// Presents the download options for a Tweet's media, from the media's long-press menu
// and from chat media.
@interface PFBDownloadInlineButton : NSObject

- (void)presentDownloadOptionsForMediaEntities:(NSArray*)mediaEntities;

// Reads a video's variants and picks the best MP4 as a download would, without
// downloading, and notes both options as proven.
- (void)dryRunForMediaEntities:(NSArray*)mediaEntities;

@end

NS_ASSUME_NONNULL_END
