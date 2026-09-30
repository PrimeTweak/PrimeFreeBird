#import "Features/Search/PFBAdvancedSearchViewController.h"
#import "Common/PFBBundle.h"
#import "Support/TwitterChirpFont.h"
#import <math.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "Features/Search/PFBAdvancedSearchStyle.h"
#import "Features/Search/PFBAdvField.h"

@implementation PFBAdvField
+ (instancetype)key:(NSString*)k
              label:(NSString*)l
            example:(NSString*)e
               kind:(PFBAdvFieldKind)kind {
    PFBAdvField* f = [PFBAdvField new];
    f.storeKey = k;
    f.labelKey = l;
    f.exampleKey = e;
    f.kind = kind;
    return f;
}
@end
