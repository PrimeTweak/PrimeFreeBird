// Declarations of the app's font group and color palette classes.

#import <UIKit/UIKit.h>

// Twitter's shared font group.
@interface TFNUIDefaultFontGroup : NSObject
+ (instancetype)sharedFontGroup;
- (UIFont*)headline2BoldFont;
// Three of the five root builders every named font getter dispatches through.
- (UIFont*)fontOfSize:(CGFloat)size;
- (UIFont*)boldFontOfSize:(CGFloat)size;
- (UIFont*)heavyFontOfSize:(CGFloat)size;
@end

@protocol TAEColorPalette
- (UIColor*)primaryColorForOption:(NSUInteger)colorOption;
@end

@interface TAETwitterColorPaletteSettingInfo : NSObject
@property (readonly, nonatomic) id<TAEColorPalette> colorPalette;
@property (readonly, nonatomic) _Bool isDark;
@end

@interface TAEColorSettings : NSObject
@property (retain, nonatomic)
    TAETwitterColorPaletteSettingInfo* currentColorPalette;
- (void)setPrimaryColorOption:(NSInteger)colorOption;
- (void)applyCurrentColorPalette;
+ (instancetype)sharedSettings;
@end

// Applies the TAE color options above to the UI
@interface T1ColorSettings : NSObject
+ (void)_t1_applyPrimaryColorOption;
@end
