#import "Common/PFBCompatibility.h"
#import "Settings/PFBModernSettingsCells.h"
#import <QuartzCore/QuartzCore.h>
#import "Support/PFBManager.h"
#import "Common/PFBSettings.h"
#import "Support/TWHeaders.h"
#import "Features/Appearance/ThemeColor/PFBPalette.h"
#import "Features/Appearance/ThemeColor/PFBDarkModeStyle.h"
#import "Support/TwitterChirpFont.h"
#import "Debug/PFBDebugger.h"
#import "Settings/PFBTabFlowView.h"

@implementation PFBTabFlowView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _lineHeight = 36.0;
        _gap = 4.0;
        _reportedHeight = 36.0;
    }
    return self;
}

- (CGFloat)flowInWidth:(CGFloat)available applyingFrames:(BOOL)apply {
    if (available <= 0 || self.subviews.count == 0) {
        return self.lineHeight;
    }
    CGFloat x = 0;
    CGFloat y = 0;
    for (UIView* sub in self.subviews) {
        CGSize size = [sub sizeThatFits:CGSizeMake(available, self.lineHeight)];
        CGFloat width = MIN(ceil(size.width), available);
        if (x > 0 && x + width > available) {
            x = 0;
            y += self.lineHeight;
        }
        if (apply) {
            sub.frame = CGRectMake(x, y, width, self.lineHeight);
        }
        x += width + self.gap;
    }
    return y + self.lineHeight;
}

- (CGSize)intrinsicContentSize {
    return CGSizeMake(UIViewNoIntrinsicMetric, self.reportedHeight);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat needed = [self flowInWidth:self.bounds.size.width applyingFrames:YES];
    if (fabs(needed - self.reportedHeight) > 0.5) {
        self.reportedHeight = needed;
        // Auto Layout schedules its own pass; nothing is asked of the table.
        [self invalidateIntrinsicContentSize];
    }
}

@end
