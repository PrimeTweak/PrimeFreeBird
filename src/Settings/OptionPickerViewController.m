//
//  OptionPickerViewController.m
//  PrimeFreeBird
//

#import "Settings/OptionPickerViewController.h"
#import "Core/TwitterChirpFont.h"

// Same accent the tinted switches use, so the checkmark follows the theme
// instead of falling back to the system blue.
extern UIColor* CurrentAccentColor(void);

static UIColor* NFBPickerAccentColor(void) {
    UIColor* accent = CurrentAccentColor();
    return accent ?: [UIColor labelColor];
}

static const CGFloat kNFBPickerWidth = 300.0;
static const CGFloat kNFBPickerRowHeight = 46.0;
static const CGFloat kNFBPickerGap = 0.0;   // rangées jointives
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
                                             constant:kNFBPickerMargin],   // 14 en haut
        // Edge to edge: the rows carry their own 16pt inset, and their
        // separators must reach both sides of the popover.
        [self.stack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.stack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.stack.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    // Title and message are left-aligned, following the iOS 26 move away from
    // centred text in this kind of container.
    if (self.pickerTitle.length) {
        UILabel* titleLabel = [[UILabel alloc] init];
        titleLabel.text = self.pickerTitle;
        titleLabel.font = [TwitterChirpFont(TwitterFontStyleBold) fontWithSize:16.5];
        titleLabel.textColor = [UIColor labelColor];
        titleLabel.numberOfLines = 0;
        [self.stack addArrangedSubview:[self inset:titleLabel]];
        
    }
    if (self.pickerMessage.length) {
        UILabel* messageLabel = [[UILabel alloc] init];
        messageLabel.text = self.pickerMessage;
        messageLabel.font = [TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:13.0];
        messageLabel.textColor = [UIColor secondaryLabelColor];
        messageLabel.numberOfLines = 0;
        [self.stack addArrangedSubview:[self inset:messageLabel]];
        
    }

    for (NSInteger i = 0; i < (NSInteger)self.options.count; i++) {
        [self.stack addArrangedSubview:[self rowForIndex:i]];
    }
}

// Wraps a label so the header keeps its side margins while the rows below go
// edge to edge.
- (UIView*)inset:(UIView*)content {
    UIView* container = [[UIView alloc] init];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [content.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16.0],
        [content.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-16.0],
        [content.topAnchor constraintEqualToAnchor:container.topAnchor constant:2.0],
        [content.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-6.0],
    ]];
    return container;
}

// A flat row per choice. The popover is already the container, so nothing is
// boxed inside it: the current choice reads from the checkmark and the bolder
// weight, the way iOS settings and menus do it.
- (UIView*)rowForIndex:(NSInteger)index {
    BOOL isSelected = (index == self.selectedIndex);
    UIButton* row = [UIButton buttonWithType:UIButtonTypeCustom];
    row.tag = index;
    [row addTarget:self
                  action:@selector(rowTapped:)
        forControlEvents:UIControlEventTouchUpInside];

    // Hairline above every row but the first, drawn from the label colour so
    // it holds up on glass in both light and dark.
    if (index > 0) {
        UIView* separator = [[UIView alloc] init];
        separator.backgroundColor = [[UIColor labelColor] colorWithAlphaComponent:0.10];
        separator.translatesAutoresizingMaskIntoConstraints = NO;
        separator.userInteractionEnabled = NO;
        [row addSubview:separator];
        [NSLayoutConstraint activateConstraints:@[
            [separator.topAnchor constraintEqualToAnchor:row.topAnchor],
            [separator.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
            [separator.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
            [separator.heightAnchor constraintEqualToConstant:0.5],
        ]];
    }

    UILabel* label = [[UILabel alloc] init];
    label.text = self.options[(NSUInteger)index];
    label.font = [TwitterChirpFont(isSelected ? TwitterFontStyleBold
                                              : TwitterFontStyleRegular) fontWithSize:17.0];
    label.textColor = [UIColor labelColor];

    UILabel* check = [[UILabel alloc] init];
    check.text = isSelected ? @"\u2713" : @"";
    check.font = [TwitterChirpFont(TwitterFontStyleBold) fontWithSize:17.0];
    check.textColor = NFBPickerAccentColor();
    check.textAlignment = NSTextAlignmentRight;

    for (UIView* v in @[ label, check ]) {
        v.translatesAutoresizingMaskIntoConstraints = NO;
        v.userInteractionEnabled = NO;
        [row addSubview:v];
    }
    [NSLayoutConstraint activateConstraints:@[
        [row.heightAnchor constraintEqualToConstant:kNFBPickerRowHeight],
        [label.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:16.0],
        [label.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [check.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-16.0],
        [check.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [check.widthAnchor constraintEqualToConstant:kNFBPickerCheckColumn],
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:check.leadingAnchor
                                                        constant:-8.0],
    ]];
    return row;
}

- (void)rowTapped:(UIButton*)sender {
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
        systemLayoutSizeFittingSize:CGSizeMake(kNFBPickerWidth,
                                               UILayoutFittingCompressedSize.height)
             withHorizontalFittingPriority:UILayoutPriorityRequired
                   verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    CGSize wanted = CGSizeMake(kNFBPickerWidth, fitting.height + kNFBPickerMargin + 6.0);
    if (!CGSizeEqualToSize(self.preferredContentSize, wanted)) {
        self.preferredContentSize = wanted;
    }
}

@end
