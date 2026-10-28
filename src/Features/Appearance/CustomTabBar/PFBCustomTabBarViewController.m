// The tab editor: a grid of every available tab above a reorderable preview row.

#import "Features/Appearance/CustomTabBar/PFBCustomTabBarViewController.h"
#import <objc/runtime.h>
#import "Common/PFBBundle.h"
#import "Support/TwitterChirpFont.h"
#import "Features/Appearance/CustomTabBar/PFBCustomTabBarCell.h"
#import "Features/Appearance/CustomTabBar/CustomTabBarNativeColors.h"
#import "Features/Appearance/CustomTabBar/PFBCustomTabBarPreviewCell.h"
#import "Features/Appearance/CustomTabBar/PFBCustomTabBarUtility.h"
#import "Support/Helpers.h"
#import "Support/HookHelpers.h"
#import "Support/T1Headers.h"
#import "Debug/PFBDebugger.h"

// The floating compose button, hidden while the editor is on screen.
@interface TFNFloatingActionButton : UIView
- (void)showAnimated:(_Bool)animated completion:(id)completion;
- (void)hideAnimated:(_Bool)animated completion:(id)completion;
@end

static NSString* const kGridHeaderID = @"gridHeader";
static NSString* const kGridFooterID = @"gridFooter";

@interface PFBCustomTabBarViewController () <UICollectionViewDataSource,
                                          UICollectionViewDelegateFlowLayout>
@property (nonatomic, strong) UICollectionView* gridView;
@property (nonatomic, strong) UICollectionView* previewView;
@property (nonatomic, strong) UIView* separator;

// All available tab pageIDs; and the selected ones in tab-bar order (Home
// first).
@property (nonatomic, strong) NSMutableArray<NSString*>* allPages;
@property (nonatomic, strong) NSMutableArray<NSString*>* selectedPages;
@property (nonatomic, strong) NSArray<NSString*>* originalSelection;
@property (nonatomic, assign) BOOL hasChanges;
// The grid's instructions, which a refused tap replaces for a moment.
@property (nonatomic, weak) UILabel* headerLabel;
// The swipe back's state before the editor held it while changes are pending.
@property (nonatomic, assign) BOOL popGestureWasEnabled;
// The compose buttons the editor hid, shown again when it leaves.
@property (nonatomic, strong) NSHashTable<UIView*>* hiddenComposeButtons;
@end

@implementation PFBCustomTabBarViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = PFBCustomTabBarScreenBackgroundColor();
    self.hasChanges = NO;

    [self setupGridView];
    [self setupPreviewRow];
    [self setupSaveButton];
    [self loadData];
    [self updateSaveButtonState];

    // Leaving with unsaved picks asks first: the back button runs this action instead
    // of going back.
    if (@available(iOS 16.0, *)) {
        __weak typeof(self) weakSelf = self;
        self.navigationItem.backAction = [UIAction actionWithHandler:^(__unused UIAction* action) {
            [weakSelf leaveEditor];
        }];
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.popGestureWasEnabled = self.navigationController.interactivePopGestureRecognizer.enabled;
    [self updateSaveButtonState];

    // Hide the floating compose button so it doesn't overlap the editor.
    self.hiddenComposeButtons = [NSHashTable weakObjectsHashTable];
    for (UIWindow* window in [UIApplication sharedApplication].windows) {
        [self findAndHideFloatingActionButtonInView:window];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    self.navigationController.interactivePopGestureRecognizer.enabled = self.popGestureWasEnabled;
    for (UIView* button in self.hiddenComposeButtons) {
        if ([button respondsToSelector:@selector(showAnimated:completion:)]) {
            [(TFNFloatingActionButton*)button showAnimated:YES completion:nil];
        }
    }
    [self.hiddenComposeButtons removeAllObjects];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    [self.gridView.collectionViewLayout invalidateLayout];
    [self.previewView.collectionViewLayout invalidateLayout];
}

// The Restore button's border is a CGColor, set again when the appearance switches.
- (void)traitCollectionDidChange:(UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    CGColorRef border = [[UIColor systemGray4Color] resolvedColorWithTraitCollection:self.traitCollection].CGColor;
    for (UICollectionReusableView* footer in
         [self.gridView visibleSupplementaryViewsOfKind:UICollectionElementKindSectionFooter]) {
        for (UIView* button in footer.subviews) {
            button.layer.borderColor = border;
        }
    }
}

// Only a visible button is hidden, so leaving the editor never reveals one that
// Twitter or the Hide Tweet button option keeps out of sight.
- (void)findAndHideFloatingActionButtonInView:(UIView*)view {
    if ([view isKindOfClass:NSClassFromString(@"TFNFloatingActionButton")]) {
        if (!view.hidden && view.alpha > 0.01 &&
            [view respondsToSelector:@selector(hideAnimated:completion:)]) {
            [self.hiddenComposeButtons addObject:view];
            [(TFNFloatingActionButton*)view hideAnimated:YES completion:nil];
        }
        return;
    }
    for (UIView* subview in view.subviews) {
        [self findAndHideFloatingActionButtonInView:subview];
    }
}

#pragma mark - UI Setup

- (void)setupSaveButton {
    UIBarButtonItem* saveButton = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemSave
                             target:self
                             action:@selector(saveButtonTapped)];
    self.navigationItem.rightBarButtonItem = saveButton;
    saveButton.enabled = NO;
}

- (void)setupGridView {
    // Grid metrics mirror the native TabCustomizationGridViewController.
    UICollectionViewFlowLayout* layout =
        [[UICollectionViewFlowLayout alloc] init];
    layout.minimumInteritemSpacing = 12;
    layout.minimumLineSpacing = 24;
    layout.sectionInset = UIEdgeInsetsMake(8, 16, 24, 16);

    self.gridView = [[UICollectionView alloc] initWithFrame:CGRectZero
                                       collectionViewLayout:layout];
    self.gridView.translatesAutoresizingMaskIntoConstraints = NO;
    self.gridView.backgroundColor = [UIColor clearColor];
    self.gridView.alwaysBounceVertical = YES;
    self.gridView.delegate = self;
    self.gridView.dataSource = self;
    [self.gridView registerClass:[PFBCustomTabBarCell class]
        forCellWithReuseIdentifier:[PFBCustomTabBarCell reuseIdentifier]];
    [self.gridView registerClass:[UICollectionReusableView class]
        forSupplementaryViewOfKind:UICollectionElementKindSectionHeader
               withReuseIdentifier:kGridHeaderID];
    [self.gridView registerClass:[UICollectionReusableView class]
        forSupplementaryViewOfKind:UICollectionElementKindSectionFooter
               withReuseIdentifier:kGridFooterID];
    [self.view addSubview:self.gridView];
}

- (void)setupPreviewRow {
    UICollectionViewFlowLayout* layout =
        [[UICollectionViewFlowLayout alloc] init];
    layout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
    layout.minimumLineSpacing = 0;
    layout.minimumInteritemSpacing = 0;

    self.previewView = [[UICollectionView alloc] initWithFrame:CGRectZero
                                          collectionViewLayout:layout];
    self.previewView.translatesAutoresizingMaskIntoConstraints = NO;
    self.previewView.backgroundColor = [UIColor clearColor];
    self.previewView.showsHorizontalScrollIndicator = NO;
    self.previewView.delegate = self;
    self.previewView.dataSource = self;
    [self.previewView registerClass:[PFBCustomTabBarPreviewCell class]
         forCellWithReuseIdentifier:[PFBCustomTabBarPreviewCell reuseIdentifier]];
    [self.view addSubview:self.previewView];

    UILongPressGestureRecognizer* longPress =
        [[UILongPressGestureRecognizer alloc]
            initWithTarget:self
                    action:@selector(handleReorderGesture:)];
    [self.previewView addGestureRecognizer:longPress];

    // Hairline separator above the preview row.
    self.separator = [UIView new];
    self.separator.translatesAutoresizingMaskIntoConstraints = NO;
    self.separator.backgroundColor = PFBCustomTabBarSeparatorColor();
    [self.view addSubview:self.separator];

    CGFloat hairline = 1.0 / UIScreen.mainScreen.scale;
    [NSLayoutConstraint activateConstraints:@[
        [self.previewView.leadingAnchor
            constraintEqualToAnchor:self.view.leadingAnchor],
        [self.previewView.trailingAnchor
            constraintEqualToAnchor:self.view.trailingAnchor],
        [self.previewView.bottomAnchor
            constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [self.previewView.heightAnchor constraintEqualToConstant:49],

        [self.separator.leadingAnchor
            constraintEqualToAnchor:self.view.leadingAnchor],
        [self.separator.trailingAnchor
            constraintEqualToAnchor:self.view.trailingAnchor],
        [self.separator.bottomAnchor
            constraintEqualToAnchor:self.previewView.topAnchor],
        [self.separator.heightAnchor constraintEqualToConstant:hairline],

        [self.gridView.topAnchor
            constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.gridView.leadingAnchor
            constraintEqualToAnchor:self.view.leadingAnchor],
        [self.gridView.trailingAnchor
            constraintEqualToAnchor:self.view.trailingAnchor],
        [self.gridView.bottomAnchor
            constraintEqualToAnchor:self.separator.topAnchor]
    ]];
}

#pragma mark - Data

- (void)loadData {
    // Offers the captured tabs the account genuinely has; panels that exist only
    // through the forced tab gates stay out of the grid.
    self.allPages = [NSMutableArray array];
    for (NSDictionary* entry in [PFBCustomTabBarUtility availableTabs]) {
        NSNumber* panelID = entry[PFBTabPanelIDKey];
        if (panelID && !PFBPanelIsGenuinelyAvailable(panelID.longLongValue)) {
            continue;
        }
        [self.allPages addObject:entry[PFBTabPageKey]];
    }

    NSArray<NSString*>* saved = [PFBCustomTabBarUtility visiblePageIDsInOrder];
    [self selectPages:saved ?: [PFBCustomTabBarUtility defaultVisiblePageIDs]];

    self.originalSelection = [self.selectedPages copy];
    self.hasChanges = NO;

    [self.gridView reloadData];
    [self.previewView reloadData];
}

// The pages of the list the account has, in its order, Home first.
- (void)selectPages:(NSArray<NSString*>*)source {
    self.selectedPages = [NSMutableArray array];
    for (NSString* page in source) {
        if ([self.allPages containsObject:page] &&
            ![self.selectedPages containsObject:page]) {
            [self.selectedPages addObject:page];
        }
    }
    [self pinHomeFirst];
}

- (void)pinHomeFirst {
    [self.selectedPages removeObject:PFBCustomTabBarHomePageID];
    if ([PFBCustomTabBarUtility metadataForPage:PFBCustomTabBarHomePageID]) {
        [self.selectedPages insertObject:PFBCustomTabBarHomePageID atIndex:0];
    }
}

- (void)recomputeChanges {
    self.hasChanges = ![self.selectedPages isEqualToArray:self.originalSelection];
    [self updateSaveButtonState];
}

// Pending changes also hold the swipe back, so they are never dropped without the question.
- (void)updateSaveButtonState {
    self.navigationItem.rightBarButtonItem.enabled = self.hasChanges;
    if (self.viewIfLoaded.window) {
        self.navigationController.interactivePopGestureRecognizer.enabled =
            self.popGestureWasEnabled && !self.hasChanges;
    }
}

- (void)leaveEditor {
    if (!self.hasChanges) {
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    PFBBundle* bundle = [PFBBundle sharedBundle];
    UIAlertController* alert =
        [UIAlertController alertControllerWithTitle:[bundle localizedStringForKey:@"CUSTOM_TAB_BAR_DISCARD_TITLE"]
                                            message:[bundle localizedStringForKey:@"CUSTOM_TAB_BAR_DISCARD_MESSAGE"]
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:[bundle localizedTwitterStringForKey:@"CANCEL_ACTION_LABEL"]
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:[bundle localizedStringForKey:@"CUSTOM_TAB_BAR_DISCARD_ACTION"]
                                              style:UIAlertActionStyleDestructive
                                            handler:^(__unused UIAlertAction* action) {
                                                [weakSelf.navigationController popViewControllerAnimated:YES];
                                            }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Save / Reset

- (void)saveButtonTapped {
    [self persistChanges];

    // Apply the new layout live by asking the app to recompute its visible tabs;
    // this re-runs the tab-entry hook with the freshly saved order.
    [self applyLiveLayout];
    [self.navigationController popViewControllerAnimated:YES];
}

static UIViewController* findViewControllerOfClass(UIViewController* vc,
                                                   Class cls) {
    if (!vc) {
        return nil;
    }
    if ([vc isKindOfClass:cls]) {
        return vc;
    }
    for (UIViewController* child in vc.childViewControllers) {
        UIViewController* found = findViewControllerOfClass(child, cls);
        if (found) {
            return found;
        }
    }
    return findViewControllerOfClass(vc.presentedViewController, cls);
}

- (UIViewController*)tabNavigationController {
    Class navClass = objc_getClass("T1TabbedAppNavigationViewController");
    if (!navClass) {
        return nil;
    }
    for (UIWindow* window in UIApplication.sharedApplication.windows) {
        UIViewController* tabNav = findViewControllerOfClass(window.rootViewController, navClass);
        if (tabNav) {
            return tabNav;
        }
    }
    return nil;
}

- (void)applyLiveLayout {
    UIViewController* tabNav = [self tabNavigationController];
    if (![tabNav respondsToSelector:@selector(recalculateVisiblePanels)]) {
        // Twitter's own Liquid Glass has no tab view controller: its navigation lists again.
        [PFBCustomTabBarUtility refreshGlassBar];
        return;
    }

    [(T1TabbedAppNavigationViewController*)tabNav recalculateVisiblePanels];
}

// How many tabs Twitter's bar shows; 0 when the count is unread.
- (NSInteger)barCapacity {
    UIViewController* tabNav = [self tabNavigationController];
    if (![tabNav respondsToSelector:@selector(_t1_bottomTabItemCapacity)]) {
        return 0;
    }
    NSInteger capacity = [(T1TabbedAppNavigationViewController*)tabNav _t1_bottomTabItemCapacity];
    PFBDebugLog(@"[tabbar] editor capacity %ld", (long)capacity);
    return capacity >= 2 ? capacity : 0;
}

- (void)persistChanges {
    [self pinHomeFirst];

    [PFBCustomTabBarUtility setVisiblePageIDs:self.selectedPages];

    self.originalSelection = [self.selectedPages copy];
    self.hasChanges = NO;
    [self updateSaveButtonState];
}

// Restore puts Twitter's default tabs in the editor only; Save keeps them, as it keeps any pick.
- (void)restoreTapped {
    PFBBundle* bundle = [PFBBundle sharedBundle];
    UIAlertController* alert = [UIAlertController
        alertControllerWithTitle:[bundle localizedTwitterStringForKey:@"SUBSCRIPTION_TAB_CUSTOMIZATION_RESTORE_BUTTON_TITLE"]
                         message:[bundle localizedStringForKey:@"CUSTOM_TAB_BAR_RESET_MESSAGE"]
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:[bundle localizedTwitterStringForKey:@"CANCEL_ACTION_LABEL"]
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    __weak typeof(self) weakSelf = self;
    UIAlertAction* restore =
        [UIAlertAction actionWithTitle:[bundle localizedStringForKey:@"CUSTOM_TAB_BAR_RESTORE_ACTION"]
                                 style:UIAlertActionStyleDefault
                               handler:^(__unused UIAlertAction* action) {
                                   [weakSelf selectPages:[PFBCustomTabBarUtility defaultVisiblePageIDs]];
                                   [weakSelf recomputeChanges];
                                   [weakSelf.gridView reloadData];
                                   [weakSelf.previewView reloadData];
                               }];
    [alert addAction:restore];
    alert.preferredAction = restore;
    [self presentViewController:alert animated:YES completion:nil];
}

// The refusal takes the instructions' place in the alert color for a moment, and the
// tile shakes, as the Explore bar of the settings does.
- (void)refuseTileAtIndexPath:(NSIndexPath*)indexPath withMessage:(NSString*)message {
    UILabel* header = self.headerLabel;
    header.text = message;
    header.textColor = [UIColor systemRedColor];
    CAKeyframeAnimation* nudge = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
    nudge.values = @[ @0, @(-4), @4, @(-2), @0 ];
    nudge.duration = 0.32;
    [[self.gridView cellForItemAtIndexPath:indexPath].layer addAnimation:nudge forKey:@"pfbRefuse"];
    NSString* instructions = [[PFBBundle sharedBundle] localizedStringForKey:@"CUSTOM_TAB_BAR_GRID_DETAIL"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if ([header.text isEqualToString:message]) {
            header.text = instructions;
            header.textColor = [UIColor secondaryLabelColor];
        }
    });
}

#pragma mark - Reordering (preview row)

- (void)handleReorderGesture:(UILongPressGestureRecognizer*)gesture {
    CGPoint location = [gesture locationInView:self.previewView];

    switch (gesture.state) {
        case UIGestureRecognizerStateBegan: {
            NSIndexPath* indexPath =
                [self.previewView indexPathForItemAtPoint:location];
            // Home stays pinned first and can't be dragged.
            if (!indexPath || indexPath.item == 0) {
                return;
            }
            [self.previewView beginInteractiveMovementForItemAtIndexPath:indexPath];
            break;
        }
        case UIGestureRecognizerStateChanged:
            [self.previewView updateInteractiveMovementTargetPosition:location];
            break;
        case UIGestureRecognizerStateEnded:
            [self.previewView endInteractiveMovement];
            break;
        default:
            [self.previewView cancelInteractiveMovement];
            break;
    }
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)collectionView:(UICollectionView*)collectionView
     numberOfItemsInSection:(NSInteger)section {
    return collectionView == self.gridView ? self.allPages.count
                                           : self.selectedPages.count;
}

- (__kindof UICollectionViewCell*)collectionView:
                                      (UICollectionView*)collectionView
                          cellForItemAtIndexPath:(NSIndexPath*)indexPath {
    if (collectionView == self.previewView) {
        PFBCustomTabBarPreviewCell* cell = [collectionView
            dequeueReusableCellWithReuseIdentifier:[PFBCustomTabBarPreviewCell
                                                       reuseIdentifier]
                                      forIndexPath:indexPath];
        NSDictionary* meta = [PFBCustomTabBarUtility
            metadataForPage:self.selectedPages[indexPath.item]];
        [cell configureWithImageName:meta[PFBTabImageKey]];
        return cell;
    }

    PFBCustomTabBarCell* cell = [collectionView
        dequeueReusableCellWithReuseIdentifier:[PFBCustomTabBarCell reuseIdentifier]
                                  forIndexPath:indexPath];
    NSString* page = self.allPages[indexPath.item];
    NSDictionary* meta = [PFBCustomTabBarUtility metadataForPage:page];
    [cell configureWithTitle:(meta[PFBTabTitleKey] ?: page)
                   imageName:meta[PFBTabImageKey]
                    selected:[self.selectedPages containsObject:page]
                       fixed:[page isEqualToString:PFBCustomTabBarHomePageID]
                 accentColor:PFBCurrentAccentColor()];
    return cell;
}

- (UICollectionReusableView*)collectionView:(UICollectionView*)collectionView
          viewForSupplementaryElementOfKind:(NSString*)kind
                                atIndexPath:(NSIndexPath*)indexPath {
    if ([kind isEqualToString:UICollectionElementKindSectionHeader]) {
        UICollectionReusableView* header =
            [collectionView dequeueReusableSupplementaryViewOfKind:kind
                                               withReuseIdentifier:kGridHeaderID
                                                      forIndexPath:indexPath];
        [header.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];

        UILabel* label =
            [[UILabel alloc] initWithFrame:CGRectInset(header.bounds, 4, 0)];
        label.autoresizingMask =
            UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        label.numberOfLines = 0;
        label.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:13]);
        label.textColor = [UIColor secondaryLabelColor];
        label.text = [[PFBBundle sharedBundle]
            localizedStringForKey:@"CUSTOM_TAB_BAR_GRID_DETAIL"];
        [header addSubview:label];
        self.headerLabel = label;
        return header;
    }

    UICollectionReusableView* footer =
        [collectionView dequeueReusableSupplementaryViewOfKind:kind
                                           withReuseIdentifier:kGridFooterID
                                                  forIndexPath:indexPath];
    [footer.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];

    NSString* title = [[PFBBundle sharedBundle]
        localizedTwitterStringForKey:
            @"SUBSCRIPTION_TAB_CUSTOMIZATION_RESTORE_BUTTON_TITLE"];
    UIButton* restore = [UIButton buttonWithType:UIButtonTypeSystem];
    [restore setTitle:title forState:UIControlStateNormal];
    // Same quiet outlined pill as the theme picker's "Reset to default" button.
    restore.titleLabel.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:15]);
    [restore setTitleColor:[UIColor secondaryLabelColor] forState:UIControlStateNormal];
    restore.backgroundColor = [UIColor clearColor];
    restore.layer.cornerRadius = 20;
    restore.layer.borderWidth = 1.0;
    restore.layer.borderColor = [UIColor systemGray4Color].CGColor;
    restore.clipsToBounds = YES;
    restore.translatesAutoresizingMaskIntoConstraints = NO;
    [restore addTarget:self
                  action:@selector(restoreTapped)
        forControlEvents:UIControlEventTouchUpInside];
    [footer addSubview:restore];
    [NSLayoutConstraint activateConstraints:@[
        [restore.leadingAnchor constraintEqualToAnchor:footer.leadingAnchor constant:16],
        [restore.trailingAnchor constraintEqualToAnchor:footer.trailingAnchor constant:-16],
        [restore.centerYAnchor constraintEqualToAnchor:footer.centerYAnchor],
        [restore.heightAnchor constraintEqualToConstant:40]
    ]];
    return footer;
}

#pragma mark - UICollectionViewDelegate

- (void)collectionView:(UICollectionView*)collectionView
    didSelectItemAtIndexPath:(NSIndexPath*)indexPath {
    // Only the grid toggles selection; the preview row is reorder-only.
    if (collectionView != self.gridView) {
        return;
    }

    NSString* page = self.allPages[indexPath.item];
    if ([page isEqualToString:PFBCustomTabBarHomePageID]) {
        return;
    }

    if ([self.selectedPages containsObject:page]) {
        [self.selectedPages removeObject:page];
    } else {
        // Twitter shows only the tabs its bar holds: a pick beyond that would be saved and
        // never seen.
        NSInteger capacity = [self barCapacity];
        if (capacity > 0 && (NSInteger)self.selectedPages.count >= capacity) {
            NSString* format = [[PFBBundle sharedBundle] localizedStringForKey:@"CUSTOM_TAB_BAR_FULL_FORMAT"];
            [self refuseTileAtIndexPath:indexPath withMessage:[NSString stringWithFormat:format, (long)capacity]];
            return;
        }
        [self.selectedPages addObject:page];
    }

    [self recomputeChanges];
    [self.gridView reloadItemsAtIndexPaths:@[indexPath]];
    [self.previewView reloadData];
}

- (BOOL)collectionView:(UICollectionView*)collectionView
    canMoveItemAtIndexPath:(NSIndexPath*)indexPath {
    return collectionView == self.previewView && indexPath.item != 0;
}

- (NSIndexPath*)collectionView:(UICollectionView*)collectionView
    targetIndexPathForMoveFromItemAtIndexPath:(NSIndexPath*)originalIndexPath
                          toProposedIndexPath:(NSIndexPath*)proposedIndexPath {
    // Keep Home pinned first.
    if (proposedIndexPath.item == 0) {
        return [NSIndexPath indexPathForItem:1 inSection:0];
    }
    return proposedIndexPath;
}

- (void)collectionView:(UICollectionView*)collectionView
    moveItemAtIndexPath:(NSIndexPath*)sourceIndexPath
            toIndexPath:(NSIndexPath*)destinationIndexPath {
    NSString* page = self.selectedPages[sourceIndexPath.item];
    [self.selectedPages removeObjectAtIndex:sourceIndexPath.item];
    [self.selectedPages insertObject:page atIndex:destinationIndexPath.item];
    [self recomputeChanges];
}

#pragma mark - UICollectionViewDelegateFlowLayout

- (CGSize)collectionView:(UICollectionView*)collectionView
                    layout:(UICollectionViewLayout*)collectionViewLayout
    sizeForItemAtIndexPath:(NSIndexPath*)indexPath {
    if (collectionView == self.previewView) {
        // Native sizes each preview item to 1/6 of the width; full row height.
        CGFloat width = floor(CGRectGetWidth(collectionView.bounds) / 6.0);
        return CGSizeMake(width, CGRectGetHeight(collectionView.bounds));
    }

    UICollectionViewFlowLayout* flow =
        (UICollectionViewFlowLayout*)collectionViewLayout;
    UIEdgeInsets insets = flow.sectionInset;
    CGFloat spacing = flow.minimumInteritemSpacing;

    // Four columns spread across the full width, instead of the native
    // three-column grid.
    const CGFloat columns = 4.0;
    CGFloat available =
        CGRectGetWidth(collectionView.bounds) - insets.left - insets.right;
    CGFloat itemWidth = floor((available - spacing * (columns - 1)) / columns);
    return CGSizeMake(itemWidth, itemWidth + 27.0);
}

- (CGSize)collectionView:(UICollectionView*)collectionView
                             layout:
                                 (UICollectionViewLayout*)collectionViewLayout
    referenceSizeForHeaderInSection:(NSInteger)section {
    if (collectionView != self.gridView) {
        return CGSizeZero;
    }
    return CGSizeMake(CGRectGetWidth(collectionView.bounds), 60);
}

- (CGSize)collectionView:(UICollectionView*)collectionView
                             layout:
                                 (UICollectionViewLayout*)collectionViewLayout
    referenceSizeForFooterInSection:(NSInteger)section {
    if (collectionView != self.gridView) {
        return CGSizeZero;
    }
    return CGSizeMake(CGRectGetWidth(collectionView.bounds), 72);
}

@end
