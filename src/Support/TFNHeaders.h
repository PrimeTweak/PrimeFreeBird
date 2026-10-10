// Declarations of the app's TFN classes.

#import <UIKit/UIKit.h>
#import "Support/TFSHeaders.h"

@class TFNTwitterAccountModel;

@interface TFNTwitterAccount : NSObject
@property (nonatomic, strong) NSString* username;
@property (nonatomic, strong) NSString* displayUsername;
@property (readonly, nonatomic) TFNTwitterAccountModel* model;
@end

@interface TFNTableView : UITableView
@end

@interface TFNPillControl : UIControl
@property (nonatomic, copy) NSString* text;
@end

@interface TFNDataViewController : UIViewController
@property (readonly, nonatomic) TFNTableView* tableView;
@property (readonly, nonatomic) NSString* adDisplayLocation;
@end

@interface TFNItemsDataViewController : TFNDataViewController
@property (copy, nonatomic) NSArray* sections;
@end

@interface TFNNavigationController : UINavigationController
@end

@interface TFNActionItem : NSObject
+ (instancetype)actionItemWithTitle:(NSString*)arg1 action:(void (^)(void))arg2;
+ (instancetype)actionItemWithTitle:(NSString*)arg1
                          imageName:(NSString*)arg2
                             action:(void (^)(void))arg3;
@end

@interface TFNAttributedTextModel : NSObject
@property (copy, nonatomic) NSAttributedString* attributedString;
- (instancetype)initWithAttributedString:(NSMutableAttributedString*)arg;
@end

@interface TFNAttributedTextView : UIView
- (void)setTextModel:(id)model;
@end

@interface TFNActiveTextItem : NSObject
- (instancetype)initWithTextModel:(id)arg activeRanges:(id)arg1;
@end

@interface TFNMenuSheetViewController : TFNItemsDataViewController
- (instancetype)initWithActionItems:(NSArray*)actionItems;
- (void)tfnPresentedCustomPresentFromViewController:(id)arg1
                                           animated:(BOOL)arg2
                                         completion:(void (^)(void))arg3;
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
@property (nonatomic, copy) NSString* fromUserName;
@property (nonatomic, assign) NSInteger statusID;
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
+ (id)tfn_vectorImageNamed:(id)arg1
    highContrastVariantNamed:(id)arg2
                    fitsSize:(struct CGSize)arg3
                   fillColor:(id)arg4;
+ (id)tfn_vectorImageNamed:(id)arg1 height:(double)arg2 fillColor:(id)arg3;
@end

@interface TFNBarButtonItemButton : UIButton
// Added by the tweak (see src/Features/Appearance/NavBarIcons.x); declared so the compiler
// knows the selector when it is sent to self.
- (void)pfbGreySettingsGlyphIfNeeded;
@end
