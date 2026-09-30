#import "Features/General/PFBHiddenNotificationsViewController.h"
#import "Common/PFBBundle.h"
#import "Support/TwitterChirpFont.h"
#import "Support/HookHelpers.h"
#import "Features/General/PFBNotifPaddedLabel.h"

@implementation PFBNotifPaddedLabel

static const CGFloat kPFBNotifPillPadding = 8.0;   // gauche et droite seulement

- (CGSize)intrinsicContentSize {
    CGSize size = [super intrinsicContentSize];
    size.width += kPFBNotifPillPadding * 2.0;
    return size;
}

- (CGSize)sizeThatFits:(CGSize)size {
    CGSize fit = [super sizeThatFits:size];
    fit.width += kPFBNotifPillPadding * 2.0;
    return fit;
}

- (void)drawTextInRect:(CGRect)rect {
    [super drawTextInRect:UIEdgeInsetsInsetRect(
        rect, UIEdgeInsetsMake(0, kPFBNotifPillPadding, 0, kPFBNotifPillPadding))];
}

@end
