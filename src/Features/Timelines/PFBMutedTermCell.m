#import "Features/Timelines/PFBMutedWordsViewController.h"
#import "Common/PFBBundle.h"
#import "Support/PFBManager.h"
#import "Support/TwitterChirpFont.h"
#import "Support/HookHelpers.h"
#import "Features/Timelines/PFBMutedWordsStyle.h"
#import "Features/Timelines/PFBMutedTermCell.h"

@implementation PFBMutedTermCell {
    // The text leads from the badge or from the row's edge, and ends either
    // before the accessories or at the far edge. One of each pair is active.
    NSLayoutConstraint* _termLeadingToBadge;
    NSLayoutConstraint* _termLeadingToEdge;
    NSLayoutConstraint* _termTrailingToButtons;
    NSLayoutConstraint* _termTrailingToEdge;
    NSLayoutConstraint* _kindLeading;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString*)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [UIColor clearColor];

        _kindLabel = [[UILabel alloc] init];
        _kindLabel.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:12]);
        // Derived from the label color rather than a semantic fill: Twitter
        // re-themes the system fills, which turned this badge into a dark
        // block with unreadable text.
        _kindLabel.textColor = [[UIColor labelColor] colorWithAlphaComponent:0.6];
        _kindLabel.textAlignment = NSTextAlignmentCenter;
        _kindLabel.backgroundColor = [[UIColor labelColor] colorWithAlphaComponent:0.07];
        _kindLabel.layer.cornerRadius = 5.0;
        _kindLabel.layer.masksToBounds = YES;
        [_kindLabel setContentHuggingPriority:UILayoutPriorityRequired
                                      forAxis:UILayoutConstraintAxisHorizontal];

        _termLabel = [[UILabel alloc] init];
        _termLabel.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:16.5]);

        // Expiry pill: tapping it opens a native duration menu.
        _durationButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _durationButton.titleLabel.font =
            PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:13]);
        _durationButton.backgroundColor = [[UIColor labelColor] colorWithAlphaComponent:0.05];
        _durationButton.layer.cornerRadius = 11.0;
        _durationButton.contentEdgeInsets = UIEdgeInsetsMake(0, 10, 0, 10);
        _durationButton.showsMenuAsPrimaryAction = YES;
        [_durationButton setContentHuggingPriority:UILayoutPriorityRequired
                                           forAxis:UILayoutConstraintAxisHorizontal];

        _removeButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_removeButton setImage:PFBTwitterGlyphFor(@"close_circle_fill", [UIImage systemImageNamed:@"xmark.circle.fill"])
                       forState:UIControlStateNormal];
        _removeButton.tintColor = [[UIColor labelColor] colorWithAlphaComponent:0.25];

        for (UIView* v in @[ _kindLabel, _termLabel, _durationButton, _removeButton ]) {
            v.translatesAutoresizingMaskIntoConstraints = NO;
            [self.contentView addSubview:v];
        }
        [NSLayoutConstraint activateConstraints:@[
            [_kindLabel.centerYAnchor
                constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_kindLabel.heightAnchor constraintEqualToConstant:22.0],
            [_kindLabel.widthAnchor constraintGreaterThanOrEqualToConstant:58.0],
            [_termLabel.centerYAnchor
                constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_durationButton.trailingAnchor
                constraintEqualToAnchor:_removeButton.leadingAnchor
                               constant:-8.0],
            [_durationButton.centerYAnchor
                constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_durationButton.heightAnchor constraintEqualToConstant:22.0],
            [_termLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor
                                                 constant:11.0],
            [_termLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor
                                                    constant:-11.0],
            [_removeButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor
                                                         constant:-kPFBMutedSideMargin],
            [_removeButton.centerYAnchor
                constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_removeButton.widthAnchor constraintEqualToConstant:26.0],
        ]];

        _kindLeading =
            [_kindLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor
                                                     constant:kPFBMutedSideMargin];
        _kindLeading.active = YES;
        _termLeadingToBadge =
            [_termLabel.leadingAnchor constraintEqualToAnchor:_kindLabel.trailingAnchor
                                                     constant:12.0];
        _termLeadingToEdge =
            [_termLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor
                                                     constant:kPFBMutedSideMargin];
        _termTrailingToButtons = [_termLabel.trailingAnchor
            constraintLessThanOrEqualToAnchor:_durationButton.leadingAnchor
                                     constant:-8.0];
        _termTrailingToEdge = [_termLabel.trailingAnchor
            constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor
                                     constant:-kPFBMutedSideMargin];
        // The Words list is the default shape.
        [self applyTermRow];
    }
    return self;
}

// Each switch drops the outgoing constraint before adding the incoming one: the
// two of a pair must never both be active, even for an instant.
- (void)applyTermRow {
    self.contentView.alpha = 1.0;
    self.kindLabel.hidden = NO;
    self.durationButton.hidden = NO;
    self.removeButton.hidden = NO;
    _kindLeading.constant = kPFBMutedSideMargin;
    _termLeadingToEdge.active = NO;
    _termLeadingToBadge.active = YES;
    _termTrailingToEdge.active = NO;
    _termTrailingToButtons.active = YES;
}

- (void)applyThreadRowWithMargin:(CGFloat)margin showBadge:(BOOL)showBadge {
    self.contentView.alpha = 1.0;
    self.kindLabel.hidden = !showBadge;
    self.durationButton.hidden = YES;
    self.removeButton.hidden = YES;
    _kindLeading.constant = margin;
    // Nothing sits beside the text here, so it ends at the row's own edge
    // instead of where the accessories would have been.
    _termTrailingToButtons.active = NO;
    _termTrailingToEdge.constant = -margin;
    _termTrailingToEdge.active = YES;
    if (showBadge) {
        _termLeadingToEdge.active = NO;
        _termLeadingToBadge.active = YES;
    } else {
        _termLeadingToBadge.active = NO;
        _termLeadingToEdge.constant = margin;
        _termLeadingToEdge.active = YES;
    }
}

@end
