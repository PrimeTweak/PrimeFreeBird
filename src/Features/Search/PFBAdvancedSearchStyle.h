// The new look's parts as the advanced search cells use them: a title over a capsule field, and
// the example under it.
#import <UIKit/UIKit.h>
#import "Settings/PFBSettingsCellStyle.h"
#import "Settings/Native/PFBShowcase.h"
#import "Settings/Native/PFBNativeSettingsRowCell.h"

static const CGFloat kPFBAdvFieldHeight = 50.0;
// The text's side margin, and the capsule's, as the new look's sheets place theirs.
static const CGFloat kPFBAdvTextSide = 24.0;
static const CGFloat kPFBAdvFieldSide = 20.0;

// The font of a row's title in Twitter's new settings.
static inline UIFont* PFBAdvTitleFont(void) {
    return [PFBNativeSettingsRowStyle shared].titleFont
               ?: PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:16]);
}

// The title and the example in the palette's fonts and colors, set again on every appearance change.
static inline void PFBAdvThemeLabels(UILabel* title, UILabel* example) {
    title.font = PFBAdvTitleFont();
    title.textColor = PFBSettingsTextColor();
    example.font = PFBSettingsDetailFont();
    example.textColor = PFBSettingsSubtitleColor();
}

// Lays the cell out as the title, the capsule holding content, then the example.
static inline void PFBAdvInstallField(UITableViewCell* cell, UIView* content, UILabel** outTitle,
                                      UILabel** outExample) {
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.backgroundColor = [UIColor clearColor];
    UILabel* title = [[UILabel alloc] init];
    title.numberOfLines = 0;
    PFBShowcaseSurface* surface = [[PFBShowcaseSurface alloc] initWithCornerRadius:-1];
    UILabel* example = [[UILabel alloc] init];
    example.numberOfLines = 0;
    UIView* box = cell.contentView;
    for (UIView* part in @[ title, surface, example ]) {
        part.translatesAutoresizingMaskIntoConstraints = NO;
        [box addSubview:part];
    }
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [surface.contentView addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:box.topAnchor constant:10.0],
        [title.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:kPFBAdvTextSide],
        [title.trailingAnchor constraintEqualToAnchor:box.trailingAnchor constant:-kPFBAdvTextSide],
        [surface.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:8.0],
        [surface.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:kPFBAdvFieldSide],
        [surface.trailingAnchor constraintEqualToAnchor:box.trailingAnchor constant:-kPFBAdvFieldSide],
        [surface.heightAnchor constraintEqualToConstant:kPFBAdvFieldHeight],
        [content.leadingAnchor constraintEqualToAnchor:surface.contentView.leadingAnchor constant:18.0],
        [content.trailingAnchor constraintEqualToAnchor:surface.contentView.trailingAnchor constant:-12.0],
        [content.topAnchor constraintEqualToAnchor:surface.contentView.topAnchor],
        [content.bottomAnchor constraintEqualToAnchor:surface.contentView.bottomAnchor],
        [example.topAnchor constraintEqualToAnchor:surface.bottomAnchor constant:6.0],
        [example.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:kPFBAdvTextSide],
        [example.trailingAnchor constraintEqualToAnchor:box.trailingAnchor constant:-kPFBAdvTextSide],
        [example.bottomAnchor constraintEqualToAnchor:box.bottomAnchor constant:-10.0],
    ]];
    PFBAdvThemeLabels(title, example);
    *outTitle = title;
    *outExample = example;
}
