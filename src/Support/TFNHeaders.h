// Declarations of the app's TFN classes.

#import <UIKit/UIKit.h>
#import "Support/TFSHeaders.h"

@class TFNTwitterAccountModel;

@interface TFNTwitterAccount : NSObject
@property (readonly, nonatomic) NSString* displayUsername;
@property (readonly, nonatomic) TFNTwitterAccountModel* model;
// The second value Twitter's own Liquid Glass gate asks for.
- (BOOL)isDummyTest1FeatureEnabled;
@end

@interface TFNTableView : UITableView
@end

@interface TFNPillControl : UIControl
@property (nonatomic, copy) NSString* text;
@end

@interface TFNDataViewController : UIViewController
@property (readonly, nonatomic) NSString* adDisplayLocation;
// The list's pull-to-refresh control.
@property (retain, nonatomic) UIControl* pullToLoadTopControl;
@end

@interface TFNItemsDataViewController : TFNDataViewController
@property (copy, nonatomic) NSArray* sections;
@end

@interface TFNActionItem : NSObject
+ (instancetype)actionItemWithTitle:(NSString*)arg1 action:(void (^)(void))arg2;
+ (instancetype)actionItemWithTitle:(NSString*)arg1
                          imageName:(NSString*)arg2
                             action:(void (^)(void))arg3;
+ (instancetype)actionItemWithTitle:(NSString*)arg1
                           subtitle:(NSString*)arg2
                          imageName:(NSString*)arg3
                             action:(void (^)(void))arg4;
- (void)setDisabled:(BOOL)disabled;
@end

@interface TFNAttributedTextModel : NSObject
@property (copy, nonatomic) NSAttributedString* attributedString;
- (instancetype)initWithAttributedString:(NSMutableAttributedString*)arg;
@end

@interface TFNAttributedTextView : UIView
@end

@interface TFNActiveTextItem : NSObject
- (instancetype)initWithTextModel:(id)arg activeRanges:(id)arg1;
@end

@interface TFNMenuSheetViewController : TFNItemsDataViewController
- (instancetype)initWithActionItems:(NSArray*)actionItems;
- (instancetype)initWithTitle:(NSString*)title actionItems:(NSArray*)actionItems;
- (void)setShouldPresentAsMenu:(BOOL)asMenu;
- (void)tfnPresentedCustomPresentFromViewController:(id)arg1
                                           animated:(BOOL)arg2
                                         completion:(void (^)(void))arg3;
@end

// Twitter's own presentation: its Tray for a menu sheet, its alert for a bridged alert.
@interface UIViewController (TFNPresented)
- (void)tfn_presentFromViewController:(UIViewController*)presenter
                             animated:(BOOL)animated
                           completion:(void (^)(void))completion;
@end

// A button added this way is recorded, so Twitter can draw the alert in its own style.
@interface UIAlertController (TFNAdditions)
- (UIAlertAction*)tfn_addActionWithTitle:(NSString*)title
                                   style:(UIAlertActionStyle)style
                                 handler:(void (^)(void))handler;
@end

@interface TFNToastAction : NSObject
- (instancetype)initWithTitle:(NSString*)title scribeAction:(id)scribeAction handler:(void (^)(void))handler;
@end

@interface TFNInformationToast : NSObject
+ (instancetype)successToastWithMessageText:(NSString*)text detailText:(NSString*)detail;
+ (instancetype)errorToastWithMessageText:(NSString*)text detailText:(NSString*)detail;
- (instancetype)initWithMessageText:(NSString*)text
                         detailText:(NSString*)detail
                           iconName:(NSString*)iconName
                    displayDuration:(double)duration;
@end

@interface TFNToaster : NSObject
+ (instancetype)defaultToaster;
- (void)pushToast:(id)toast withPriority:(NSUInteger)priority;
- (void)dequeueToastsPassingTest:(BOOL (^)(id toast, NSUInteger priority))test;
// The toast on screen, nil when none shows.
- (id)activeToast;
@end

@interface TFNHUD : NSObject
- (instancetype)initWithText:(NSString*)text;
- (void)setText:(NSString*)text;
- (void)show;
- (void)hide;
@end

@interface TFNSettingsNavigationItem : NSObject
- (instancetype)initWithTitle:(NSString*)arg1
                       detail:(NSString*)arg2
                     iconName:(NSString*)arg3
            controllerFactory:(UIViewController* (^)(void))arg4;
@end

@interface TFNButton : UIButton
@end

@interface TFNTwitterStatus : NSObject
@property (readonly, nonatomic) _Bool isPromoted;
@property (readonly, nonatomic) TFSTwitterEntitySet* entities;
@property (readonly, copy, nonatomic) NSString* fromUserName;
@property (readonly, nonatomic) NSInteger statusID;
@property (readonly, nonatomic) long long quoteCount;
@property (readonly, nonatomic) long long retweetCount;
@end

@interface TFNTwitterAccountModel : NSObject
// The block runs before the call returns when the status is cached, else later on the
// main queue; the status may be nil.
- (void)lookUpStatusForID:(long long)statusID completionBlock:(void (^)(TFNTwitterStatus* status))block;
@end

@interface TFNTwitter : NSObject
+ (instancetype)sharedTwitter;
@property (readonly, nonatomic) NSArray* accounts;
@end

// The Tweets of a thread, which the outbox sends one composition at a time.
@interface TFNTwitterCompositionReplyChain : NSObject
@property (readonly, nonatomic, copy) NSOrderedSet* compositions;
@end

@interface TFNTwitterComposition : NSObject
@property (nonatomic, strong) NSDate* undoableAddedDate;
@property (nonatomic, assign) double undoTimeInterval;
@property (nonatomic, strong) TFNTwitterCompositionReplyChain* replyChain;
@end

@interface TFNTitleView : UIView
+ (instancetype)titleViewWithTitle:(NSString*)title
                          subtitle:(NSString*)subTitle;
@end

@interface UIImage (TFNAdditions)
+ (id)tfn_vectorImageNamed:(id)arg1
                  fitsSize:(struct CGSize)arg2
                 fillColor:(id)arg3;
@end

@interface TFNBarButtonItemButton : UIButton
// Added in src/Features/Appearance/NavBarIcons.x; declared so the compiler knows the
// selector when it is sent to self.
- (void)pfbPaintSettingsGlyphIfNeeded;
@end
