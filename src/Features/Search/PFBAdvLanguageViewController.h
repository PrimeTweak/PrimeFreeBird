// The languages a search can keep to, as the new look's choices.

#import <UIKit/UIKit.h>

@interface PFBAdvLanguageViewController : UIViewController
// codes pairs with titles; the empty code stands for any language. pick runs with the code
// chosen, then the page goes back.
- (instancetype)initWithTitles:(NSArray<NSString*>*)titles
                         codes:(NSArray<NSString*>*)codes
                        chosen:(NSString*)chosen
                          pick:(void (^)(NSString* code))pick;
@end
