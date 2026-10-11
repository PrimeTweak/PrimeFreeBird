// Declarations of the app classes PrimeFreeBird calls: T1, TUI, TTM, TTA, TFC, TAV and Swift.

#import <CoreMedia/CoreMedia.h>
#import <SafariServices/SafariServices.h>
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import "Support/TFNHeaders.h"

@interface T1AppDelegate : UIResponder <UIApplicationDelegate>
@end

// The "new posts" pill shown at the top of the timeline
@interface TUIUpdateIndicator : UIViewController
@property (nonatomic, strong) TFNPillControl* pillControl;
@end

@interface TUIFollowControlCustomScreenshot : UIView
@end

@interface TTMAssetVideoFile : NSObject
@property (nonatomic, copy, readonly) NSString* filePath;
@end

@interface TTMAssetVoiceRecording : TTMAssetVideoFile
@end

@interface T1MediaAttachmentsViewCell : UICollectionViewCell
@property (nonatomic, strong, readwrite) id attachment;
@property (nonatomic, strong) UIButton* uploadButton;
@end

@interface T1MediaAttachmentsViewCell () <UINavigationControllerDelegate,
                                          UIImagePickerControllerDelegate>
@end

@interface T1StandardStatusAttachmentViewAdapter : NSObject
@property (nonatomic, assign, readonly) NSUInteger attachmentType;
@end

#pragma mark - Tab bar

@interface T1PanelIdentity : NSObject
+ (NSString*)iconImageNameForPanelID:(long long)panelID;
@end

@interface T1TabView : UIView
@property (readonly, nonatomic) UILabel* titleLabel;
@property (readonly, nonatomic) UIImageView* imageView;
@property (readonly, nonatomic) long long panelID;
@property (copy, nonatomic) NSString* scribePage;
@property (readonly, nonatomic) NSString* title;
@property (readonly, nonatomic) NSString* imageName;
@property (retain, nonatomic) UIColor* iconColor;
@property (readonly, nonatomic, getter=isSelected) BOOL selected;
- (void)_t1_updateTitleLabel;
- (void)_t1_updateImageViewAnimated:(BOOL)animated;
@end

@interface T1TabBarViewController : UIViewController
@property (copy, nonatomic) NSArray* tabViews;
@end

// Each entry backs one tab and owns its T1TabView; the app orders both the tab
// buttons and their content view controllers from this single array.
@protocol T1AppNavigationTabEntry <NSObject>
- (T1TabView*)tabView;
@end

@interface T1TabbedAppNavigationViewController : UIViewController
- (void)setVisibleTabEntries:(NSArray<id<T1AppNavigationTabEntry>>*)entries;
// Recomputes the visible tab set at runtime (rebuilds buttons and content).
- (void)recalculateVisiblePanels;
@end

#pragma mark - Settings

// T1GenericSettingsViewController backs the settings root and its sub-pages.
@interface T1GenericSettingsViewController : TFNItemsDataViewController
@property (nonatomic, strong) TFNTwitterAccount* account;
@end

#pragma mark - Profile

@interface T1ProfileUserViewModel : NSObject
@property (readonly, copy, nonatomic) NSString* location;
@property (readonly, copy, nonatomic) NSString* fullName;
@property (readonly, copy, nonatomic) NSString* username;
@property (readonly, copy, nonatomic) NSString* bio;
@property (readonly, copy, nonatomic) NSString* url;
@end

@interface T1ProfileHeaderViewController : UIViewController
@property (retain, nonatomic) T1ProfileUserViewModel* viewModel;
@end

#pragma mark - Status views

@interface TTAStatusInlineShareButton : UIView
@end

@interface TTAStatusInlineReplyButton : UIView
@end

@interface T1PersistentComposeViewController : UIViewController
@property (readonly, nonatomic) id statusViewModel;
@end

@protocol TTACoreStatusViewEventHandler <NSObject>
@end

@interface T1StatusCell : UITableViewCell <TTACoreStatusViewEventHandler>
@end

@interface TTAStatusInlineActionsView : UIView
@property (readonly, nonatomic) id viewModel;
@end

@interface T1StandardStatusView : UIView
@property (nonatomic) __weak id<TTACoreStatusViewEventHandler> eventHandler;
@end

@interface T1ConversationFocalStatusView : UIView
@property (nonatomic) __weak id<TTACoreStatusViewEventHandler> eventHandler;
@property (nonatomic, readonly) id viewModel;
@end

@interface T1TweetComposeViewController : UIViewController
@end

// The screen a Tweet's Quotes, Retweets and Likes counts open.
@interface T1PostInteractionsViewController : UIViewController
@end

// The line under an opened Tweet: its time, then its view count.
@interface T1ConversationFooterItem : NSObject
@property (nonatomic, copy) NSString* timeAgo;
@end

@interface T1ConversationFooterTextView : UIView
@property (nonatomic, readonly) id viewModel;
@property (nonatomic, strong) T1ConversationFooterItem* footerItem;
- (void)updateFooterTextView;
@end

#pragma mark - Media views

@class PFBDownloadInlineButton;

// DM media message container (ChatConversation.MessageAttachmentView).
@interface _TtC16ChatConversation21MessageAttachmentView : UIView
@property (nonatomic, strong) UIContextMenuInteraction* downloadMenuInteraction;
@property (nonatomic, strong) PFBDownloadInlineButton* downloadHandler;
@end

@interface _TtC16ChatConversation21MessageAttachmentView () <
    UIContextMenuInteractionDelegate>
@end

// Shared media view (TweetMediaAttachments.MultiMediaView); its carousel
// variant exposes -inlineMediaInfos as well
@interface _TtC21TweetMediaAttachments14MultiMediaView : UIView
@property (nonatomic, readonly) NSArray* inlineMediaInfos;
@end

#pragma mark - Host & web views

@interface T1HostViewController : UIViewController
+ (instancetype)sharedHostViewController;
- (id)currentAccount;
@end

@interface T1BaseWebViewController : UIViewController
- (WKWebView*)webView;
@end

@interface T1WebViewController : T1BaseWebViewController
- (instancetype)initWithRootURL:(NSURL*)rootURL
                        account:(id)account
             shouldAuthenticate:(BOOL)shouldAuthenticate
      shouldPresentAsNativePage:(BOOL)shouldPresentAsNativePage
                   sourceStatus:(id)sourceStatus
                scribeComponent:(id)scribeComponent
               scribeParameters:(id)scribeParameters;
@end

@interface T1SafariViewController : SFSafariViewController
@property (nonatomic, readonly) NSURL* rootURL;
@end

#pragma mark - Status & timeline text

@interface _TtC10TwitterURT25URTTimelineTrendViewModel : NSObject
@property (nonatomic, readonly) NSDictionary* scribeItem;
@end

// Hooked for unrounded follower/following counts
@interface T1ProfileFriendsFollowingViewModel : NSObject
- (id)_t1_followCountTextWithLabel:(id)arg1
                     singularLabel:(id)arg2
                             count:(id)arg3
                       highlighted:(_Bool)arg4;
@end

@interface TFCCardData : NSObject
- (NSString*)stringForKey:(NSString*)key;
- (NSString*)stringForKey:(NSString*)key defaultValue:(NSString*)value;
- (NSNumber*)numberForKey:(NSString*)key;
- (NSNumber*)numberFromStringForKey:(NSString*)key;
- (BOOL)boolForKey:(NSString*)key;
@end

@interface TAVPlaybackState : NSObject
// AVPlayer semantics: 0 = paused, 1 = waiting to play, 2 = playing.
@property (nonatomic, readonly) long long timeControlStatus;
// Both are CMTime: the runtime reports {int64, int32, uint32, int64}.
@property (nonatomic, readonly) CMTime currentTime;
@property (nonatomic, readonly) CMTime duration;
@end

@interface TAVPlayer : NSObject
@property (nonatomic, readonly) TAVPlaybackState* playbackState;
// Selectors are isMuted / setIsMuted: on this class.
@property (nonatomic) BOOL isMuted;
// The other half of the audio state, and the one the timeline handover raises.
@property (nonatomic) float volume;
- (void)play;
- (void)pause;
- (void)playOrReplay;
- (void)seekToTime:(CMTime)time;
@end

@interface _TtC14T1TwitterSwift22ImmersiveVideoPageView : UIView
@end

@interface _TtC14T1TwitterSwift17ImmersiveCardView : UIView
- (void)setPausedByUser:(BOOL)paused;
@end
