// The languages of the advanced search in the choices of the new look's steps: the ring moves
// at once, the choice is kept, and the form comes back.

#import "Features/Search/PFBAdvLanguageViewController.h"
#import "Common/PFBBundle.h"
#import "Settings/PFBSettingsCellStyle.h"
#import "Settings/Native/PFBNativeSettingsSheetController.h"

@implementation PFBAdvLanguageViewController {
    NSArray<NSString*>* _titles;
    NSArray<NSString*>* _codes;
    NSString* _chosen;
    void (^_pick)(NSString*);
    NSArray<PFBSheetChoiceRow*>* _rows;
    BOOL _leaving;
}

- (instancetype)initWithTitles:(NSArray<NSString*>*)titles
                         codes:(NSArray<NSString*>*)codes
                        chosen:(NSString*)chosen
                          pick:(void (^)(NSString* code))pick {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _titles = [titles copy];
        _codes = [codes copy];
        _chosen = [chosen copy] ?: @"";
        _pick = [pick copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = [[PFBBundle sharedBundle] localizedStringForKey:@"ADVSEARCH_LANGUAGE"];
    NSMutableArray<PFBSheetChoiceRow*>* rows = [NSMutableArray array];
    for (NSUInteger i = 0; i < MIN(_titles.count, _codes.count); i++) {
        PFBSheetChoiceRow* row = [[PFBSheetChoiceRow alloc] initWithTitle:_titles[i]];
        row.chosen = [_codes[i] isEqualToString:_chosen];
        [row addTarget:self action:@selector(choose:) forControlEvents:UIControlEventTouchUpInside];
        [rows addObject:row];
    }
    _rows = rows;
    UIStackView* list = [[UIStackView alloc] initWithArrangedSubviews:rows];
    list.axis = UILayoutConstraintAxisVertical;
    UIScrollView* scroll = [[UIScrollView alloc] init];
    scroll.alwaysBounceVertical = YES;
    for (UIView* part in @[ scroll, list ]) {
        part.translatesAutoresizingMaskIntoConstraints = NO;
    }
    [self.view addSubview:scroll];
    [scroll addSubview:list];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [list.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:8.0],
        [list.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
        [list.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [list.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-16.0],
        [list.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor],
    ]];
    self.view.backgroundColor = [PFBPalette currentBackgroundColor];
}

- (void)traitCollectionDidChange:(UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    self.view.backgroundColor = [PFBPalette currentBackgroundColor];
}

// The ring moves first, so the choice shows before the form comes back; a second tap meanwhile
// is the one kept.
- (void)choose:(PFBSheetChoiceRow*)row {
    NSUInteger index = [_rows indexOfObjectIdenticalTo:row];
    if (index == NSNotFound) {
        return;
    }
    for (PFBSheetChoiceRow* other in _rows) {
        other.chosen = other == row;
    }
    if (_pick) {
        _pick(_codes[index]);
    }
    if (_leaving) {
        return;
    }
    _leaving = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf.navigationController popViewControllerAnimated:YES];
    });
}

@end
