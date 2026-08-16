//
//  NFBDiagnosticsViewController.m
//
//  A sheet, not a console. The banner answers the only question that matters
//  at a glance — is anything missing — and the body carries the full report:
//  environment, every dead hook with the file it lives in, the decision log,
//  and the last shaken capture. The share button hands the same text off as a
//  file, so nothing is ever copied by hand.
//

#import "Debug/NFBDiagnosticsViewController.h"
#import "Debug/NFBDebugger.h"
#import "Core/TwitterChirpFont.h"

@interface NFBDiagnosticsViewController ()
@property (nonatomic, strong) UILabel* statusLabel;
@property (nonatomic, strong) UIView* statusBanner;
@property (nonatomic, strong) UITextView* reportView;
@end

@implementation NFBDiagnosticsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Diagnostic";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose
                                                      target:self
                                                      action:@selector(dismissSheet)];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"square.and.arrow.up"]
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(shareReport)];

    // The banner: one line, one colour. Green reads "nothing to do here",
    // red names the count and the list below names the culprits.
    UIView* banner = [UIView new];
    banner.translatesAutoresizingMaskIntoConstraints = NO;
    banner.layer.cornerRadius = 14.0;
    banner.layer.cornerCurve = kCACornerCurveContinuous;
    [self.view addSubview:banner];
    self.statusBanner = banner;

    UILabel* status = [UILabel new];
    status.translatesAutoresizingMaskIntoConstraints = NO;
    status.font = [TwitterChirpFont(TwitterFontStyleBold) fontWithSize:16.0];
    status.textColor = [UIColor whiteColor];
    status.numberOfLines = 1;
    status.adjustsFontSizeToFitWidth = YES;
    [banner addSubview:status];
    self.statusLabel = status;

    // The body: the report verbatim, monospaced, selectable. The same text the
    // share button sends, so what is read here is exactly what is received.
    UITextView* report = [UITextView new];
    report.translatesAutoresizingMaskIntoConstraints = NO;
    report.editable = NO;
    report.alwaysBounceVertical = YES;
    report.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    report.layer.cornerRadius = 14.0;
    report.layer.cornerCurve = kCACornerCurveContinuous;
    report.font = [UIFont monospacedSystemFontOfSize:12.0 weight:UIFontWeightRegular];
    report.textColor = [UIColor labelColor];
    report.textContainerInset = UIEdgeInsetsMake(12, 12, 12, 12);
    [self.view addSubview:report];
    self.reportView = report;

    UILayoutGuide* safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [banner.topAnchor constraintEqualToAnchor:safe.topAnchor constant:12],
        [banner.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [banner.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
        [banner.heightAnchor constraintEqualToConstant:44],

        [status.leadingAnchor constraintEqualToAnchor:banner.leadingAnchor constant:14],
        [status.trailingAnchor constraintEqualToAnchor:banner.trailingAnchor constant:-14],
        [status.centerYAnchor constraintEqualToAnchor:banner.centerYAnchor],

        [report.topAnchor constraintEqualToAnchor:banner.bottomAnchor constant:12],
        [report.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [report.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
        [report.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-12],
    ]];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refresh];
}

// Recomputed on every appearance, so reopening the sheet after a capture or a
// relaunch always shows the current truth, never a stale one.
- (void)refresh {
    NSUInteger missing = NFBDebuggerMissingCount();
    if (missing == 0) {
        self.statusBanner.backgroundColor = [UIColor systemGreenColor];
        self.statusLabel.text = @"Accroches : toutes présentes";
    } else {
        self.statusBanner.backgroundColor = [UIColor systemRedColor];
        self.statusLabel.text = [NSString stringWithFormat:
            @"%lu accroche%@ manquante%@ — fonctions mortes",
            (unsigned long)missing, missing > 1 ? @"s" : @"",
            missing > 1 ? @"s" : @""];
    }
    self.reportView.text = NFBDebuggerReport();
}

- (void)dismissSheet {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)shareReport {
    NSURL* url = NFBDebuggerWriteReportFile();
    if (!url) {
        return;
    }
    UIActivityViewController* share =
        [[UIActivityViewController alloc] initWithActivityItems:@[url]
                                          applicationActivities:nil];
    share.popoverPresentationController.barButtonItem =
        self.navigationItem.rightBarButtonItem;
    [self presentViewController:share animated:YES completion:nil];
}

@end
