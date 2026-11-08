// An entry of the app icon picker.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PFBAppIconItem : NSObject

// The icon's key in Info.plist, the name an alternate icon passes to setAlternateIconName:.
@property (nonatomic, copy, readonly) NSString* bundleIconName;

// The icon's file names from CFBundleIconFiles, without the .png extension.
@property (nonatomic, copy, readonly) NSArray<NSString*>* bundleIconFiles;

// Whether this is the app's primary (default) icon.
@property (nonatomic, assign, readonly) BOOL isPrimaryIcon;

- (instancetype)initWithBundleIconName:(NSString*)iconName
                         iconFileNames:(NSArray<NSString*>*)files
                         isPrimaryIcon:(BOOL)isPrimary;

@end

NS_ASSUME_NONNULL_END
