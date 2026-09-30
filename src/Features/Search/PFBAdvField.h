#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, PFBAdvFieldKind) {
    PFBAdvFieldText = 0,     // free words / phrases / account lists
    PFBAdvFieldNumber,       // minimum engagement counts
    PFBAdvFieldDate,         // calendar picker, optional
    PFBAdvFieldMenu,         // language pull-down
    PFBAdvFieldToggle,       // filters switches
};

@interface PFBAdvField : NSObject
@property (nonatomic, copy) NSString* storeKey;     // NSUserDefaults draft key
@property (nonatomic, copy) NSString* labelKey;     // field title key
@property (nonatomic, copy) NSString* exampleKey;   // example line key (nilable)
@property (nonatomic, assign) PFBAdvFieldKind kind;
+ (instancetype)key:(NSString*)k
              label:(NSString*)l
            example:(NSString*)e
               kind:(PFBAdvFieldKind)kind;
@end
