// The web form's look, shared by the advanced search cells.
#import <UIKit/UIKit.h>
#import "Support/TwitterChirpFont.h"

// x.com focus blue (#1D9BF0) — the web form's focus ring.
static inline UIColor* PFBAdvBlue(void) {
    return [UIColor colorWithRed:0x1D / 255.0
                           green:0x9B / 255.0
                            blue:0xF0 / 255.0
                           alpha:1.0];
}
// Builds the web form's bordered box with a floating label, hosting an
// arbitrary content view, plus the gray example line underneath. Returns the
// box view through outBox so cells can restyle the border on focus.
static inline UILabel* PFBAdvInstallBox(UITableViewCell* cell,
                                 UIView* content,
                                 UIView** outBox,
                                 UILabel** outExample) {
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.backgroundColor = [UIColor clearColor];

    UIView* box = [[UIView alloc] init];
    box.layer.borderWidth = 1.0;
    box.layer.borderColor = [UIColor systemGray3Color].CGColor;
    box.layer.cornerRadius = 6.0;
    box.translatesAutoresizingMaskIntoConstraints = NO;
    [cell.contentView addSubview:box];

    UILabel* floatLabel = [[UILabel alloc] init];
    floatLabel.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:13]);
    floatLabel.textColor = [UIColor secondaryLabelColor];
    floatLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [box addSubview:floatLabel];

    content.translatesAutoresizingMaskIntoConstraints = NO;
    [box addSubview:content];

    UILabel* example = [[UILabel alloc] init];
    example.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:13.5]);
    example.textColor = [UIColor secondaryLabelColor];
    example.numberOfLines = 0;
    example.translatesAutoresizingMaskIntoConstraints = NO;
    [cell.contentView addSubview:example];

    UILayoutGuide* margins = cell.contentView.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [box.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor
                                      constant:7.0],
        [box.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
        [box.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],

        [floatLabel.topAnchor constraintEqualToAnchor:box.topAnchor constant:7.0],
        [floatLabel.leadingAnchor constraintEqualToAnchor:box.leadingAnchor
                                                 constant:12.0],
        [floatLabel.trailingAnchor constraintEqualToAnchor:box.trailingAnchor
                                                  constant:-12.0],

        [content.topAnchor constraintEqualToAnchor:floatLabel.bottomAnchor
                                          constant:1.0],
        [content.leadingAnchor constraintEqualToAnchor:box.leadingAnchor
                                              constant:12.0],
        [content.trailingAnchor constraintEqualToAnchor:box.trailingAnchor
                                               constant:-12.0],
        [content.bottomAnchor constraintEqualToAnchor:box.bottomAnchor
                                             constant:-9.0],
        [content.heightAnchor constraintGreaterThanOrEqualToConstant:22.0],

        [example.topAnchor constraintEqualToAnchor:box.bottomAnchor constant:6.0],
        [example.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor
                                               constant:2.0],
        [example.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
        [example.bottomAnchor
            constraintEqualToAnchor:cell.contentView.bottomAnchor
                           constant:-7.0],
    ]];
    if (outBox) { *outBox = box; }
    if (outExample) { *outExample = example; }
    return floatLabel;
}
