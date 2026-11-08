// An entry of the app icon picker.

#import "Features/Branding/AppIcon/PFBAppIconItem.h"

@implementation PFBAppIconItem

- (instancetype)initWithBundleIconName:(NSString*)iconName
                         iconFileNames:(NSArray<NSString*>*)files
                         isPrimaryIcon:(BOOL)isPrimary {
    if (self = [super init]) {
        _bundleIconName = [iconName copy];
        _bundleIconFiles = [files copy];
        _isPrimaryIcon = isPrimary;
    }
    return self;
}

@end
