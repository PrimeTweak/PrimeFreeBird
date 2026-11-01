// A row of Twitter's new settings: icon, title, the current choice when it has one, and a chevron
// or a three-dot glyph.

#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, PFBNativeSettingsRowAccessory) {
    // The row leads to a page.
    PFBNativeSettingsRowAccessoryChevron,
    // The row opens a sheet.
    PFBNativeSettingsRowAccessoryMore,
};

// The look of Twitter's rows, copied from one of them once on screen (Settings.x), their usual
// layout until then. Frames are left to right; the chevron's x counts from the trailing edge.
@interface PFBNativeSettingsRowStyle : NSObject
@property (nonatomic, strong) UIFont* titleFont;
@property (nonatomic) CGFloat rowHeight;
@property (nonatomic) CGRect iconFrame;
@property (nonatomic) CGRect titleFrame;
@property (nonatomic) CGRect chevronFrame;
+ (PFBNativeSettingsRowStyle*)shared;
@end

@interface PFBNativeSettingsRowCell : UITableViewCell
// value is the row's current choice, shown before its glyph; nil for none.
- (void)configureWithTitle:(NSString*)title
                  iconName:(NSString*)iconName
                     value:(NSString*)value
                 accessory:(PFBNativeSettingsRowAccessory)accessory;
@end
