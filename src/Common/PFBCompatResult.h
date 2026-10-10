#import <UIKit/UIKit.h>

// OK: proven on this Twitter version. Not tested: no proof yet, whether or not the tour
// showed its screen. Broken: a path is lost, something it relies on is not in Twitter.
typedef NS_ENUM(NSInteger, PFBCompatVerdict) {
    PFBCompatVerdictOK,
    PFBCompatVerdictNotTested,
    PFBCompatVerdictBroken,
};

@interface PFBCompatResult : NSObject
@property(nonatomic, copy) NSString* section;
@property(nonatomic, copy) NSString* title;
@property(nonatomic, copy) NSString* detail;
// What the option did on this install; only the copied report shows it.
@property(nonatomic, copy) NSString* evidence;
@property(nonatomic) PFBCompatVerdict verdict;
@property(nonatomic) BOOL enabled;
// No switch: the behavior is always active.
@property(nonatomic) BOOL alwaysOn;
// A hooked file rather than an option: counted only when broken.
@property(nonatomic) BOOL internal;
@end
