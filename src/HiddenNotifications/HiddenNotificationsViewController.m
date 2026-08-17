#import "HiddenNotificationsViewController.h"
#import "../Core/BHTBundle.h"

// The registry lives in HiddenNotifications.x; these are its public reads.
extern NSArray<NSDictionary*>* NFBHiddenNotifList(void);
extern void NFBUnhideNotif(NSString* notifID);
extern void NFBUnhideAllNotifs(void);
extern double NFBNotifDaysLeft(NSDictionary* entry);
extern void nfbReapplyTimelineFilter(void);
extern UIColor* CurrentAccentColor(void);

// MARK: - The row
//
// Same construction as the muted-word row he signed off on: text on the left,
// a soft pill on the right, a ⊗ to remove. Colours are DERIVED FROM labelColor
// rather than taken from the semantic system fills — Twitter reinterprets
// those, and a badge came out unreadable once because of it.

@interface NFBHiddenNotifCell : UITableViewCell
@property (nonatomic, strong) UILabel* snippet;
@property (nonatomic, strong) UILabel* expiry;
@property (nonatomic, strong) UIButton* unhide;
@end

@implementation NFBHiddenNotifCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString*)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self) {
        return nil;
    }
    self.backgroundColor = [UIColor clearColor];
    self.selectionStyle = UITableViewCellSelectionStyleNone;

    _snippet = [[UILabel alloc] init];
    _snippet.font = [UIFont systemFontOfSize:14.5];
    _snippet.textColor = [UIColor labelColor];
    _snippet.numberOfLines = 2;
    _snippet.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_snippet];

    _expiry = [[UILabel alloc] init];
    _expiry.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightSemibold];
    _expiry.textColor = [[UIColor labelColor] colorWithAlphaComponent:0.6];
    _expiry.backgroundColor = [[UIColor labelColor] colorWithAlphaComponent:0.07];
    _expiry.textAlignment = NSTextAlignmentCenter;
    _expiry.layer.cornerRadius = 10.0;
    _expiry.layer.cornerCurve = kCACornerCurveContinuous;
    _expiry.clipsToBounds = YES;
    _expiry.translatesAutoresizingMaskIntoConstraints = NO;
    [_expiry setContentCompressionResistancePriority:UILayoutPriorityRequired
                                             forAxis:UILayoutConstraintAxisHorizontal];
    [self.contentView addSubview:_expiry];

    _unhide = [UIButton buttonWithType:UIButtonTypeSystem];
    [_unhide setImage:[UIImage systemImageNamed:@"xmark.circle.fill"]
             forState:UIControlStateNormal];
    _unhide.tintColor = [[UIColor labelColor] colorWithAlphaComponent:0.25];
    _unhide.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_unhide];

    [NSLayoutConstraint activateConstraints:@[
        [_snippet.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor
                                               constant:4],
        [_snippet.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [_snippet.trailingAnchor constraintLessThanOrEqualToAnchor:_expiry.leadingAnchor
                                                          constant:-8],
        [_expiry.trailingAnchor constraintEqualToAnchor:_unhide.leadingAnchor constant:-8],
        [_expiry.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [_expiry.heightAnchor constraintEqualToConstant:20],
        [_unhide.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor
                                               constant:-4],
        [_unhide.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [_unhide.widthAnchor constraintEqualToConstant:22],
        [_unhide.heightAnchor constraintEqualToConstant:22],
    ]];
    return self;
}

// The pill sizes itself around its text — a plain label needs the padding drawn.
- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize fit = [self.expiry sizeThatFits:CGSizeMake(CGFLOAT_MAX, 20)];
    CGRect frame = self.expiry.frame;
    frame.size.width = fit.width + 18;
    frame.origin.x = CGRectGetMinX(self.unhide.frame) - 8 - frame.size.width;
    self.expiry.frame = frame;
}

@end

// MARK: - The screen

@interface HiddenNotificationsViewController ()
@property (nonatomic, assign) BOOL compact;
@property (nonatomic, strong) NSArray<NSDictionary*>* rows;
@end

@implementation HiddenNotificationsViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleGrouped];
    return self;
}

- (instancetype)initCompact {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        _compact = YES;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = [[BHTBundle sharedBundle] localizedStringForKey:@"HIDDEN_NOTIFS_TITLE"];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = 52;
    // A popover paints its own material: forcing an opaque background here is
    // what once killed the glass on the muted-words popover.
    self.tableView.backgroundColor =
        self.compact ? [UIColor clearColor] : [UIColor systemBackgroundColor];
    if (self.compact) {
        self.view.backgroundColor = [UIColor clearColor];
    }
    [self reload];
}

- (void)reload {
    self.rows = NFBHiddenNotifList();
    [self.tableView reloadData];
    [self updatePreferredSize];
}

- (void)updatePreferredSize {
    if (!self.compact) {
        return;
    }
    [self.tableView layoutIfNeeded];
    CGFloat height = MIN(self.tableView.contentSize.height + 8, 330);
    self.preferredContentSize = CGSizeMake(330, MAX(height, 120));
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self updatePreferredSize];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView*)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
    return self.rows.count ? (NSInteger)self.rows.count : 1;   // 1 = the example
}

- (UITableViewCell*)tableView:(UITableView*)tableView
        cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    NFBHiddenNotifCell* cell =
        [tableView dequeueReusableCellWithIdentifier:@"nfbHiddenNotif"];
    if (!cell) {
        cell = [[NFBHiddenNotifCell alloc] initWithStyle:UITableViewCellStyleDefault
                                         reuseIdentifier:@"nfbHiddenNotif"];
    }
    // Recycling: every state a previous row could have left behind is reset.
    cell.contentView.alpha = 1.0;
    cell.unhide.hidden = NO;

    if (!self.rows.count) {
        cell.snippet.text =
            [[BHTBundle sharedBundle] localizedStringForKey:@"HIDDEN_NOTIFS_EXAMPLE"];
        cell.expiry.text = @"";
        cell.expiry.hidden = YES;
        cell.unhide.hidden = YES;
        cell.contentView.alpha = 0.38;
        return cell;
    }

    NSDictionary* row = self.rows[indexPath.row];
    NSString* text = row[@"t"];
    cell.snippet.text = text.length
        ? text
        : [[BHTBundle sharedBundle] localizedStringForKey:@"HIDDEN_NOTIFS_UNTITLED"];
    cell.expiry.hidden = NO;
    NSInteger days = (NSInteger)ceil(NFBNotifDaysLeft(row));
    NSString* format =
        [[BHTBundle sharedBundle] localizedStringForKey:@"HIDDEN_NOTIFS_EXPIRES_IN"];
    cell.expiry.text = [NSString stringWithFormat:format, (long)days];
    cell.unhide.tag = indexPath.row;
    [cell.unhide removeTarget:self
                       action:@selector(unhideTapped:)
             forControlEvents:UIControlEventTouchUpInside];
    [cell.unhide addTarget:self
                    action:@selector(unhideTapped:)
          forControlEvents:UIControlEventTouchUpInside];
    return cell;
}

- (void)unhideTapped:(UIButton*)sender {
    if (sender.tag >= (NSInteger)self.rows.count) {
        return;
    }
    NSDictionary* row = self.rows[sender.tag];
    NFBUnhideNotif(row[@"id"]);
    nfbReapplyTimelineFilter();
    [self reload];
}

// Swipe on this list unhides — the mirror of the gesture that hid it.
- (BOOL)tableView:(UITableView*)tableView canEditRowAtIndexPath:(NSIndexPath*)indexPath {
    return self.rows.count > 0;
}

- (UISwipeActionsConfiguration*)tableView:(UITableView*)tableView
    trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath*)indexPath {
    if (!self.rows.count) {
        return nil;
    }
    NSString* title = [[BHTBundle sharedBundle] localizedStringForKey:@"HIDDEN_NOTIFS_UNHIDE"];
    __weak typeof(self) weakSelf = self;
    NSDictionary* row = self.rows[indexPath.row];
    UIContextualAction* unhide = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleNormal
                            title:title
                          handler:^(__unused UIContextualAction* action,
                                    __unused UIView* view,
                                    void (^completion)(BOOL)) {
            NFBUnhideNotif(row[@"id"]);
            nfbReapplyTimelineFilter();
            completion(YES);
            [weakSelf reload];
        }];
    return [UISwipeActionsConfiguration configurationWithActions:@[unhide]];
}

// MARK: footer — the count and "clear all"

- (CGFloat)tableView:(UITableView*)tableView heightForFooterInSection:(NSInteger)section {
    return self.rows.count ? 78 : 0.01;
}

- (UIView*)tableView:(UITableView*)tableView viewForFooterInSection:(NSInteger)section {
    if (!self.rows.count) {
        return nil;
    }
    UIView* footer = [[UIView alloc] init];

    UILabel* count = [[UILabel alloc] init];
    NSString* format =
        [[BHTBundle sharedBundle] localizedStringForKey:@"HIDDEN_NOTIFS_COUNT"];
    count.text = [NSString stringWithFormat:format, (long)self.rows.count];
    count.font = [UIFont systemFontOfSize:12];
    count.textColor = [UIColor secondaryLabelColor];
    count.translatesAutoresizingMaskIntoConstraints = NO;
    [footer addSubview:count];

    UIButton* clear = [UIButton buttonWithType:UIButtonTypeSystem];
    [clear setTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"HIDDEN_NOTIFS_CLEAR_ALL"]
           forState:UIControlStateNormal];
    [clear setTitleColor:[UIColor secondaryLabelColor] forState:UIControlStateNormal];
    clear.titleLabel.font = [UIFont systemFontOfSize:15.5];
    clear.layer.borderWidth = 1.0;
    clear.layer.borderColor = [UIColor systemGray4Color].CGColor;
    clear.layer.cornerRadius = 22.0;
    clear.layer.cornerCurve = kCACornerCurveContinuous;
    clear.translatesAutoresizingMaskIntoConstraints = NO;
    [clear addTarget:self
                  action:@selector(clearAllTapped)
        forControlEvents:UIControlEventTouchUpInside];
    [footer addSubview:clear];

    [NSLayoutConstraint activateConstraints:@[
        [count.leadingAnchor constraintEqualToAnchor:footer.leadingAnchor constant:20],
        [count.topAnchor constraintEqualToAnchor:footer.topAnchor constant:8],
        [clear.trailingAnchor constraintEqualToAnchor:footer.trailingAnchor constant:-16],
        [clear.leadingAnchor constraintGreaterThanOrEqualToAnchor:count.trailingAnchor
                                                         constant:12],
        [clear.topAnchor constraintEqualToAnchor:footer.topAnchor constant:20],
        [clear.heightAnchor constraintEqualToConstant:44],
        [clear.widthAnchor constraintGreaterThanOrEqualToConstant:120],
    ]];
    return footer;
}

- (void)clearAllTapped {
    NFBUnhideAllNotifs();
    nfbReapplyTimelineFilter();
    [self reload];
}

@end
