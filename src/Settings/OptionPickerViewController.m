//
//  OptionPickerViewController.m
//  PrimeFreeBird
//

#import "Settings/OptionPickerViewController.h"
#import "Core/TwitterChirpFont.h"

static const CGFloat kNFBPickerWidth = 300.0;
static const CGFloat kNFBPickerPillHeight = 48.0;
static const CGFloat kNFBPickerGap = 8.0;
static const CGFloat kNFBPickerMargin = 14.0;
static const CGFloat kNFBPickerCheckColumn = 22.0;

@interface OptionPickerViewController () <UIPopoverPresentationControllerDelegate>
@property (nonatomic, copy) NSString* pickerTitle;
@property (nonatomic, copy) NSString* pickerMessage;
@property (nonatomic, copy) NSArray<NSString*>* options;
@property (nonatomic, assign) NSInteger selectedIndex;
@property (nonatomic, copy) void (^handler)(NSInteger index);
@property (nonatomic, strong) UIStackView* stack;
@end

@implementation OptionPickerViewController

- (instancetype)initWithTitle:(NSString*)title
                      message:(NSString*)message
                      options:(NSArray<NSString*>*)options
                selectedIndex:(NSInteger)selectedIndex
                      handler:(void (^)(NSInteger index))handler {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _pickerTitle = [title copy];
        _pickerMessage = [message copy];
        _options = [options copy];
        _selectedIndex = selectedIndex;
        _handler = [handler copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // Never paint a background here: the popover supplies its own material,
    // and that material is what follows the app's design mode.
    self.view.backgroundColor = [UIColor clearColor];

    self.stack = [[UIStackView alloc] init];
    self.stack.axis = UILayoutConstraintAxisVertical;
    self.stack.spacing = kNFBPickerGap;
    self.stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.stack];
    [NSLayoutConstraint activateConstraints:@[
        [self.stack.topAnchor constraintEqualToAnchor:self.view.topAnchor
                                             constant:kNFBPickerMargin],
        [self.stack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor
                                                 constant:kNFBPickerMargin],
        [self.stack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor
                                                  constant:-kNFBPickerMargin],
        [self.stack.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor
                                                constant:-kNFBPickerMargin],
    ]];

    // Title and message are left-aligned, following the iOS 26 move away from
    // centred text in this kind of container.
    if (self.pickerTitle.length) {
        UILabel* titleLabel = [[UILabel alloc] init];
        titleLabel.text = self.pickerTitle;
        titleLabel.font = [TwitterChirpFont(TwitterFontStyleBold) fontWithSize:16.5];
        titleLabel.textColor = [UIColor labelColor];
        titleLabel.numberOfLines = 0;
        [self.stack addArrangedSubview:titleLabel];
        [self.stack setCustomSpacing:4.0 afterView:titleLabel];
    }
    if (self.pickerMessage.length) {
        UILabel* messageLabel = [[UILabel alloc] init];
        messageLabel.text = self.pickerMessage;
        messageLabel.font = [TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:13.0];
        messageLabel.textColor = [UIColor secondaryLabelColor];
        messageLabel.numberOfLines = 0;
        [self.stack addArrangedSubview:messageLabel];
        [self.stack setCustomSpacing:12.0 afterView:messageLabel];
    }

    for (NSInteger i = 0; i < (NSInteger)self.options.count; i++) {
        [self.stack addArrangedSubview:[self pillForIndex:i]];
    }
}

// One grey pill per choice: a fixed check column, then the label, both flush
// left so the words line up whether or not the row is the selected one.
- (UIView*)pillForIndex:(NSInteger)index {
    UIButton* pill = [UIButton buttonWithType:UIButtonTypeCustom];
    pill.tag = index;
    // Derived from the label colour rather than a semantic fill: Twitter
    // re-themes the system fills, which turns them into dark blocks.
    pill.backgroundColor = [[UIColor labelColor] colorWithAlphaComponent:0.08];
    pill.layer.cornerRadius = 14.0;
    pill.clipsToBounds = YES;
    [pill addTarget:self
                  action:@selector(pillTapped:)
        forControlEvents:UIControlEventTouchUpInside];

    UILabel* check = [[UILabel alloc] init];
    check.text = (index == self.selectedIndex) ? @"\u2713" : @"";
    check.font = [TwitterChirpFont(TwitterFontStyleBold) fontWithSize:17.0];
    check.textColor = self.view.tintColor ?: [UIColor labelColor];
    check.textAlignment = NSTextAlignmentLeft;

    UILabel* label = [[UILabel alloc] init];
    label.text = self.options[(NSUInteger)index];
    label.font = [TwitterChirpFont(TwitterFontStyleBold) fontWithSize:17.0];
    label.textColor = [UIColor labelColor];

    for (UIView* v in @[ check, label ]) {
        v.translatesAutoresizingMaskIntoConstraints = NO;
        v.userInteractionEnabled = NO;
        [pill addSubview:v];
    }
    [NSLayoutConstraint activateConstraints:@[
        [pill.heightAnchor constraintEqualToConstant:kNFBPickerPillHeight],
        [check.leadingAnchor constraintEqualToAnchor:pill.leadingAnchor constant:16.0],
        [check.centerYAnchor constraintEqualToAnchor:pill.centerYAnchor],
        [check.widthAnchor constraintEqualToConstant:kNFBPickerCheckColumn],
        [label.leadingAnchor constraintEqualToAnchor:check.trailingAnchor],
        [label.centerYAnchor constraintEqualToAnchor:pill.centerYAnchor],
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:pill.trailingAnchor
                                                       constant:-16.0],
    ]];
    return pill;
}

- (void)pillTapped:(UIButton*)sender {
    NSInteger index = sender.tag;
    void (^handler)(NSInteger) = self.handler;
    [self dismissViewControllerAnimated:YES
                             completion:^{
                                 if (handler) {
                                     handler(index);
                                 }
                             }];
}

// MARK: presentation

- (void)presentFrom:(UIViewController*)presenter sourceView:(UIView*)sourceView {
    self.modalPresentationStyle = UIModalPresentationPopover;

    UIPopoverPresentationController* popover = self.popoverPresentationController;
    popover.delegate = self;
    popover.permittedArrowDirections =
        UIPopoverArrowDirectionUp | UIPopoverArrowDirectionDown;
    if (sourceView) {
        popover.sourceView = sourceView;
        popover.sourceRect = sourceView.bounds;
    } else {
        popover.sourceView = presenter.view;
        popover.sourceRect = CGRectMake(CGRectGetMidX(presenter.view.bounds), 0, 0, 0);
    }

    [presenter presentViewController:self animated:YES completion:nil];
}

// Without this a popover turns into a full-screen sheet on iPhone.
- (UIModalPresentationStyle)adaptivePresentationStyleForPresentationController:
                                (UIPresentationController*)controller
                                                          traitCollection:
                                (UITraitCollection*)traitCollection {
    return UIModalPresentationNone;
}

// Size measured from the laid-out content rather than estimated.
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self.view layoutIfNeeded];
    CGSize fitting = [self.stack
        systemLayoutSizeFittingSize:CGSizeMake(kNFBPickerWidth - kNFBPickerMargin * 2,
                                               UILayoutFittingCompressedSize.height)
             withHorizontalFittingPriority:UILayoutPriorityRequired
                   verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    CGSize wanted = CGSizeMake(kNFBPickerWidth, fitting.height + kNFBPickerMargin * 2);
    if (!CGSizeEqualToSize(self.preferredContentSize, wanted)) {
        self.preferredContentSize = wanted;
    }
}

@end
