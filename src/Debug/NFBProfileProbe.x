//
//  NFBProfileProbe.x
//
//  TEMPORARY. The copy-profile button died because Twitter 12.15 removed the
//  whole mechanism it used: T1ProfileActionButtonSpec, actionButtonProviders
//  and their initialiser are all gone, and the Swift replacement
//  (ProfileActionButtonsCatalog) exposes no Objective-C selector to hook. The
//  remaining route is to insert the button into the header's button row after
//  it is built — which needs the row's real classes and frames in this version.
//
//  This reports exactly that: every small round control in the header's
//  trailing area, with its ancestor chain, so the insertion point can be
//  written once instead of guessed. Delete once its output has been read.
//
//  Read-only: no view is created, moved or painted. The single hook is
//  viewDidLayoutSubviews, a UIViewController method whose signature is not in
//  question, and T1ProfileHeaderViewController is confirmed present in the
//  binary by the health check.
//

#import "Hooks/HookHelpers.h"
#import "Debug/NFBDebugger.h"

// One report per header, so scrolling a profile does not repeat it.
static BOOL NFBProfileProbeFirstTime(id header) {
    static NSMutableSet<NSString*>* seen;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ seen = [NSMutableSet set]; });
    NSString* key = [NSString stringWithFormat:@"%p", header];
    if ([seen containsObject:key]) {
        return NO;
    }
    if (seen.count > 12) {
        return NO;
    }
    [seen addObject:key];
    return YES;
}

static NSString* NFBProfileProbeChain(UIView* view, UIView* root) {
    NSMutableArray<NSString*>* names = [NSMutableArray array];
    UIView* node = view.superview;
    NSInteger depth = 0;
    while (node && node != root && depth < 6) {
        [names addObject:NSStringFromClass([node classForCoder])];
        node = node.superview;
        depth++;
    }
    return names.count ? [names componentsJoinedByString:@" ← "] : @"(direct)";
}

// The round action buttons sit in the trailing half of the header, are roughly
// square, and are small. Those three together pick them out without naming a
// class that may change again.
static void NFBProfileProbeSweep(UIView* view, UIView* root, NSInteger depth) {
    if (!view || depth > 14) {
        return;
    }
    CGSize size = view.bounds.size;
    BOOL smallish = size.width >= 26 && size.width <= 56 &&
                    size.height >= 26 && size.height <= 56;
    BOOL squarish = fabs(size.width - size.height) < 10;
    if (smallish && squarish && view.window) {
        CGRect inWindow = [view convertRect:view.bounds toView:nil];
        if (inWindow.origin.x > root.bounds.size.width * 0.5) {
            NFBDebugLog(@"profil: %@ frame=%@ win=%@ corner=%.1f ← %@",
                        NSStringFromClass([view classForCoder]),
                        NSStringFromCGRect(view.frame),
                        NSStringFromCGRect(CGRectIntegral(inWindow)),
                        view.layer.cornerRadius,
                        NFBProfileProbeChain(view, root));
        }
    }
    for (UIView* sub in view.subviews) {
        NFBProfileProbeSweep(sub, root, depth + 1);
    }
}

%hook T1ProfileHeaderViewController

- (void)viewDidLayoutSubviews {
    %orig;
    if (!NFBDebugIsRecording()) {
        return;
    }
    UIView* root = ((UIViewController*)self).viewIfLoaded;
    if (!root || !root.window || !NFBProfileProbeFirstTime(self)) {
        return;
    }
    NFBDebugLog(@"──── RANGÉE DE BOUTONS DU PROFIL ────");
    NFBDebugLog(@"profil: entête %@ frame=%@",
                NSStringFromClass(object_getClass(self)),
                NSStringFromCGRect(root.frame));
    NFBProfileProbeSweep(root, root, 0);
    NFBDebugLog(@"──── FIN ────");
}

%end

%ctor {
    // Silent unless debugging is on; the banner confirms the file compiled in.
    NFBDebugLog(@"sonde profil chargée");
}
