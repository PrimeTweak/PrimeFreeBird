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
