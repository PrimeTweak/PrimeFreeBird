// One group of a settings page in a sheet, as Twitter's new settings show theirs: its title and
// a close button, the group's rows, then Done.

#import "Settings/Native/PFBNativeSettingsSheetController.h"
#import "Common/PFBBundle.h"
#import "Settings/PFBSettingsCellStyle.h"
#import "Support/PFBManager.h"

// iOS draws the design it launched with: glass sheets under Liquid Glass, opaque ones under the
// Standard look. Visual style is read as it stood at launch, since a change waits for a restart.
static BOOL gPFBSheetGlassAtLaunch;

__attribute__((constructor)) static void PFBSheetReadLaunchDesign(void) {
    id glass = [[NSUserDefaults standardUserDefaults] objectForKey:@"enable_liquid_glass"];
    gPFBSheetGlassAtLaunch = glass ? [glass boolValue] : YES;
}

static BOOL PFBSheetUsesGlass(void) {
    if (@available(iOS 26.0, *)) {
        return gPFBSheetGlassAtLaunch;
    }
    return NO;
}

static void* kPFBSheetRowsContext = &kPFBSheetRowsContext;

// The room under the rows: the gap above Done, Done itself, and the margin below it.
static const CGFloat kPFBSheetDoneGap = 12;
static const CGFloat kPFBSheetDoneHeight = 48;
static const CGFloat kPFBSheetBottomMargin = 16;

@interface PFBNativeSettingsSheetController ()
@property (nonatomic, strong) UIViewController<PFBNativeSheetRows>* page;
@property (nonatomic, copy) NSString* groupTitle;
@property (nonatomic, copy) void (^closed)(void);
@property (nonatomic, strong) UILabel* titleLabel;
@property (nonatomic, strong) UIButton* closeButton;
@property (nonatomic, strong) UIView* divider;
@property (nonatomic, strong) UIButton* doneButton;
@property (nonatomic) CGFloat fittedHeight;
@property (nonatomic) BOOL watchingRows;
@end

@implementation PFBNativeSettingsSheetController

+ (void)presentRows:(UIViewController<PFBNativeSheetRows>*)rows
             titled:(NSString*)title
               from:(UIViewController*)presenter
             closed:(void (^)(void))closed {
    PFBNativeSettingsSheetController* sheet = [[self alloc] init];
    sheet.page = rows;
    sheet.groupTitle = title;
    sheet.closed = closed;
    sheet.modalPresentationStyle = UIModalPresentationPageSheet;
    // Sized once at the window's width before it opens, so the sheet comes up at its rows' height.
    [sheet loadViewIfNeeded];
    sheet.view.frame = presenter.view.window ? presenter.view.window.bounds : UIScreen.mainScreen.bounds;
    [sheet.view layoutIfNeeded];
    [rows.tableView layoutIfNeeded];
    sheet.fittedHeight = [sheet contentHeight];
    UISheetPresentationController* presentation = sheet.sheetPresentationController;
    if (@available(iOS 16.0, *)) {
        __weak PFBNativeSettingsSheetController* weakSheet = sheet;
        presentation.detents = @[ [UISheetPresentationControllerDetent
            customDetentWithIdentifier:@"pfb.group"
                              resolver:^CGFloat(id<UISheetPresentationControllerDetentResolutionContext> context) {
                                  CGFloat height = weakSheet.fittedHeight;
                                  return height > 0 ? MIN(height, context.maximumDetentValue)
                                                    : context.maximumDetentValue;
                              }] ];
    } else {
        presentation.detents = @[ [UISheetPresentationControllerDetent mediumDetent],
                                  [UISheetPresentationControllerDetent largeDetent] ];
    }
    [presenter presentViewController:sheet animated:YES completion:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    PFBBundle* bundle = [PFBBundle sharedBundle];
    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.text = self.groupTitle;
    self.titleLabel.numberOfLines = 0;
    self.titleLabel.accessibilityTraits = UIAccessibilityTraitHeader;
    self.closeButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.closeButton.accessibilityLabel = [bundle localizedTwitterStringForKey:@"CLOSE_ACTION_LABEL"];
    [self.closeButton addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    self.divider = [[UIView alloc] init];
    self.doneButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.doneButton setTitle:[bundle localizedTwitterStringForKey:@"DONE_ACTION_LABEL"]
                     forState:UIControlStateNormal];
    self.doneButton.layer.cornerRadius = kPFBSheetDoneHeight / 2;
    [self.doneButton addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];

    [self addChildViewController:self.page];
    UIView* rows = self.page.view;
    for (UIView* part in @[ self.titleLabel, self.closeButton, self.divider, rows, self.doneButton ]) {
        part.translatesAutoresizingMaskIntoConstraints = NO;
        [self.view addSubview:part];
    }
    [self.page didMoveToParentViewController:self];

    // With the rows' own 10 pt margin, these 14 pt put their text under the title.
    [NSLayoutConstraint activateConstraints:@[
        [self.titleLabel.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:24],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24],
        [self.titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.closeButton.leadingAnchor
                                                                 constant:-12],
        [self.closeButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-14],
        [self.closeButton.centerYAnchor constraintEqualToAnchor:self.titleLabel.centerYAnchor],
        [self.closeButton.widthAnchor constraintEqualToConstant:36],
        [self.closeButton.heightAnchor constraintEqualToConstant:36],
        [self.divider.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:18],
        [self.divider.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.divider.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.divider.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
        [rows.topAnchor constraintEqualToAnchor:self.divider.bottomAnchor],
        [rows.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:14],
        [rows.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-14],
        [rows.bottomAnchor constraintEqualToAnchor:self.doneButton.topAnchor constant:-kPFBSheetDoneGap],
        [self.doneButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.doneButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.doneButton.heightAnchor constraintEqualToConstant:kPFBSheetDoneHeight],
        [self.doneButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor
                                                     constant:-kPFBSheetBottomMargin],
    ]];
    [self.page.tableView addObserver:self forKeyPath:@"contentSize" options:0 context:kPFBSheetRowsContext];
    self.watchingRows = YES;
    [self applyTheme];
}

- (void)dealloc {
    if (_watchingRows) {
        [_page.tableView removeObserver:self forKeyPath:@"contentSize" context:kPFBSheetRowsContext];
    }
}

// Done is drawn in the text color with the background's color on it, as Twitter's own.
- (void)applyTheme {
    UIColor* ink = PFBSettingsTextColor();
    UIColor* ground = [PFBPalette currentBackgroundColor];
    UIFont* bold = PFBFontGroupFont(@selector(headline2BoldFont), [UIFont systemFontOfSize:17 weight:UIFontWeightBold]);
    self.view.backgroundColor = PFBSheetUsesGlass() ? [UIColor clearColor] : ground;
    self.titleLabel.font = PFBScaledFont([bold fontWithSize:20]);
    self.titleLabel.textColor = ink;
    self.divider.backgroundColor = PFBSettingsDividerColor();
    self.doneButton.backgroundColor = ink;
    self.doneButton.titleLabel.font = bold;
    [self.doneButton setTitleColor:ground forState:UIControlStateNormal];
    [self.doneButton setTitleColor:[ground colorWithAlphaComponent:0.6] forState:UIControlStateHighlighted];
    UIImage* cross = [UIImage respondsToSelector:@selector(tfn_vectorImageNamed:fitsSize:fillColor:)]
                         ? [UIImage tfn_vectorImageNamed:@"close_nomargin" fitsSize:CGSizeMake(16, 16) fillColor:ink]
                         : nil;
    [self.closeButton setImage:cross ?: [UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
    self.closeButton.tintColor = ink;
}

// The rows keep their sheet's clear ground on their own; the title and Done follow here.
- (void)traitCollectionDidChange:(UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self applyTheme];
}

- (void)close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

// Done, the X and a swipe down all end here.
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    void (^closed)(void) = self.closed;
    if (self.isBeingDismissed && closed) {
        self.closed = nil;
        closed();
    }
}

// The header, the rows and Done.
- (CGFloat)contentHeight {
    return CGRectGetMinY(self.page.view.frame) + self.page.tableView.contentSize.height + kPFBSheetDoneGap +
           kPFBSheetDoneHeight + kPFBSheetBottomMargin;
}

// Rows that appear, go or change size resize the sheet, once the table's own update is over.
- (void)refit {
    if (self.fittedHeight <= 0) {
        return;
    }
    CGFloat height = [self contentHeight];
    if (fabs(height - self.fittedHeight) < 1) {
        return;
    }
    self.fittedHeight = height;
    if (@available(iOS 16.0, *)) {
        UISheetPresentationController* sheet = self.sheetPresentationController;
        // While the sheet comes up, the height joins its opening rather than following it.
        if (self.isBeingPresented) {
            [sheet invalidateDetents];
            return;
        }
        [sheet animateChanges:^{
            [sheet invalidateDetents];
        }];
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self refit];
}

- (void)observeValueForKeyPath:(NSString*)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey, id>*)change
                       context:(void*)context {
    if (context == kPFBSheetRowsContext) {
        [self.view setNeedsLayout];
        return;
    }
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

@end
