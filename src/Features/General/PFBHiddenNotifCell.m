#import "Features/General/PFBHiddenNotificationsViewController.h"
#import "Common/PFBBundle.h"
#import "Support/TwitterChirpFont.h"
#import "Support/HookHelpers.h"
#import "Features/General/PFBHiddenNotifCell.h"
#import "Features/General/PFBNotifPaddedLabel.h"

@implementation PFBHiddenNotifCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString*)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self) {
        return nil;
    }
    self.backgroundColor = [UIColor clearColor];
    self.selectionStyle = UITableViewCellSelectionStyleNone;

    _snippet = [[UILabel alloc] init];
    _snippet.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:14.5]);
    _snippet.textColor = [UIColor labelColor];
    _snippet.numberOfLines = 2;
    _snippet.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_snippet];

    _expiry = [[PFBNotifPaddedLabel alloc] init];
    // Dimensions taken from the Muted words kindLabel: Chirp regular 12, text
    // at 60 %, background at 7 %, radius 5. Bold is deliberately not used, as
    // it made the pill too loud.
    _expiry.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:12]);
    _expiry.textColor = [[UIColor labelColor] colorWithAlphaComponent:0.6];
    _expiry.backgroundColor = [[UIColor labelColor] colorWithAlphaComponent:0.07];
    _expiry.textAlignment = NSTextAlignmentCenter;
    _expiry.layer.cornerRadius = 5.0;
    _expiry.layer.cornerCurve = kCACornerCurveContinuous;
    _expiry.clipsToBounds = YES;
    _expiry.translatesAutoresizingMaskIntoConstraints = NO;
    [_expiry setContentCompressionResistancePriority:UILayoutPriorityRequired
                                             forAxis:UILayoutConstraintAxisHorizontal];
    [self.contentView addSubview:_expiry];

    // The remove glyph is gone: the left swipe is the only way to unhide, and
    // it already existed. The text now runs to the 14 pt margin, with the
    // expiry stacked underneath it.
    self.layoutMargins = UIEdgeInsetsZero;
    self.contentView.layoutMargins = UIEdgeInsetsZero;
    self.preservesSuperviewLayoutMargins = NO;
    self.contentView.preservesSuperviewLayoutMargins = NO;

    [_snippet setContentCompressionResistancePriority:UILayoutPriorityDefaultLow
                                              forAxis:UILayoutConstraintAxisHorizontal];

    [NSLayoutConstraint activateConstraints:@[
        // Text: two lines at most, then an ellipsis.
        [_snippet.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor
                                               constant:14],
        (_snippetTop = [_snippet.topAnchor
            constraintEqualToAnchor:self.contentView.topAnchor constant:12]),
        // With no remove glyph, the text runs to the margin.
        [_snippet.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor
                                               constant:-14],

        // The expiry sits under the text and never competes with it for width.
        [_expiry.leadingAnchor constraintEqualToAnchor:_snippet.leadingAnchor],
        [_expiry.topAnchor constraintEqualToAnchor:_snippet.bottomAnchor constant:6],
        [_expiry.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor
                                                         constant:-14],
        (_expiryBottom = [_expiry.bottomAnchor
            constraintEqualToAnchor:self.contentView.bottomAnchor constant:-12]),
        [_expiry.heightAnchor constraintEqualToConstant:20],
    ]];
    return self;
}

// Empty state: the text stands alone, centered, with air above and below, using
// the dimensions of the Hide thread screen. With rows, everything returns to
// the normal two-line layout.
- (void)applyEmptyLayout:(BOOL)empty {
    if (!self.snippetBottom) {
        self.snippetBottom =
            [self.snippet.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor
                                                     constant:-28];
    }
    self.snippetTop.constant = empty ? 26 : 12;
    self.expiryBottom.active = !empty;
    self.snippetBottom.active = empty;
    self.snippet.numberOfLines = empty ? 0 : 2;
}

// Auto Layout owns the pill's position, at the leading edge under the text, and the
// padding comes from the label's own intrinsic size.

@end
