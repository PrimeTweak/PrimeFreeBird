//
//  OptionPickerViewController.h
//  PrimeFreeBird
//
//  A small list of choices shown inside a popover, drawn with the fork's own
//  fonts and spacing. Modal system components — menus, alerts, action sheets —
//  all force the system font, which clashes with Chirp everywhere else; this
//  keeps the settings coherent.
//
//  The popover's own background is left untouched, so it follows whatever the
//  app's design mode is: Liquid Glass when the app opts in, the flat container
//  when it opts out.
//

#import <UIKit/UIKit.h>

@interface OptionPickerViewController : UIViewController

// `handler` receives the chosen index; the popover dismisses itself first.
- (instancetype)initWithTitle:(NSString*)title
                      message:(NSString*)message
                      options:(NSArray<NSString*>*)options
                selectedIndex:(NSInteger)selectedIndex
                      handler:(void (^)(NSInteger index))handler;

// Presents it anchored on a row, the way iOS 26 expects a popover to behave.
- (void)presentFrom:(UIViewController*)presenter sourceView:(UIView*)sourceView;

@end
