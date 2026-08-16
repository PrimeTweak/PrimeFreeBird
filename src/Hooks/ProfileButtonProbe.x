//
//  ProfileButtonProbe.x
//
//  TEMPORARY. Answers one question with evidence: at which step does the copy
//  button disappear? Delete once its output has been read.
//
//  Three steps can drop it, and each leaves a different trace:
//    · the provider is never added        → the setting or the hook is at fault
//    · the provider is added, no specs    → the header never consults it
//    · specs given, the view never built  → the width arbitration dropped it
//    · view built, but off-screen         → a layout problem, not arbitration
//
//  It also reads the POSITION and PRIORITY the native buttons declare, so the
//  fix uses their real numbers instead of a guessed one.
//
//  Console.app, filter on:  subsystem:com.primefreebird.probe
//

#import "HookHelpers.h"
#import <os/log.h>
#import <string.h>

static os_log_t NFBProfileProbeLog(void) {
    static os_log_t log;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        log = os_log_create("com.primefreebird.probe", "profile-button");
    });
    return log;
}

// Position and priority are numbers, and messaging a number-returning selector
// as an object is what crashed an earlier probe. The encoding decides the cast.
static NSString* NFBProfileProbeNumber(id target, NSString* name) {
    SEL selector = NSSelectorFromString(name);
    if (!target || ![target respondsToSelector:selector]) {
        return [NSString stringWithFormat:@"%@=<absent>", name];
    }
    NSMethodSignature* signature = [target methodSignatureForSelector:selector];
    const char* type = signature.methodReturnType;
    if (!type) {
        return [NSString stringWithFormat:@"%@=<sans signature>", name];
    }
    switch (type[0]) {
        case 'q': case 'l':
            return [NSString stringWithFormat:@"%@=%lld", name,
                    ((long long (*)(id, SEL))objc_msgSend)(target, selector)];
        case 'Q': case 'L':
            return [NSString stringWithFormat:@"%@=%llu", name,
                    ((unsigned long long (*)(id, SEL))objc_msgSend)(target, selector)];
        case 'i': case 's': case 'c':
            return [NSString stringWithFormat:@"%@=%d", name,
                    ((int (*)(id, SEL))objc_msgSend)(target, selector)];
        case 'I': case 'S': case 'C': case 'B':
            return [NSString stringWithFormat:@"%@=%u", name,
                    ((unsigned int (*)(id, SEL))objc_msgSend)(target, selector)];
        case 'd':
            return [NSString stringWithFormat:@"%@=%.2f", name,
                    ((double (*)(id, SEL))objc_msgSend)(target, selector)];
        case 'f':
            return [NSString stringWithFormat:@"%@=%.2f", name,
                    (double)((float (*)(id, SEL))objc_msgSend)(target, selector)];
        default:
            return [NSString stringWithFormat:@"%@=<encodage '%s'>", name, type];
    }
}

// Only called when the signature says an object comes back and no argument is
// expected, so nothing is invoked on a guess.
static id NFBProfileProbeCall(id target, SEL selector) {
    if (!target || ![target respondsToSelector:selector]) {
        return nil;
    }
    NSMethodSignature* signature = [target methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments != 2) {
        return nil;
    }
    const char* type = signature.methodReturnType;
    if (!type || strcmp(type, "@") != 0) {
        return nil;
    }
    return ((id (*)(id, SEL))objc_msgSend)(target, selector);
}

static void NFBProfileProbeDumpSpecs(id provider, NSString* label) {
    id specs = NFBProfileProbeCall(provider, @selector(buttonSpecs));
    if (![specs isKindOfClass:[NSArray class]]) {
        os_log(NFBProfileProbeLog(), "   %{public}@ → buttonSpecs indisponible", label);
        return;
    }
    if (![(NSArray*)specs count]) {
        os_log(NFBProfileProbeLog(), "   %{public}@ → 0 spec", label);
        return;
    }
    for (id spec in (NSArray*)specs) {
        os_log(NFBProfileProbeLog(), "   %{public}@ → %{public}@ | %{public}@ | %{public}@",
               label,
               NSStringFromClass([spec classForCoder]),
               NFBProfileProbeNumber(spec, @"position"),
               NFBProfileProbeNumber(spec, @"priority"));
    }
}

// Looks for the button that should have been placed, by the accessibility label
// the provider gives it. Reads only: nothing is moved, shown or recoloured.
static void NFBProfileProbeFindButton(UIViewController* controller) {
    NSString* wanted =
        [[BHTBundle sharedBundle] localizedStringForKey:@"COPY_PROFILE_INFO_TITLE"];
    UIView* root = controller.viewIfLoaded;
    if (!root) {
        os_log(NFBProfileProbeLog(), "BALAYAGE  vue non chargée");
        return;
    }
    NSMutableArray<UIView*>* queue = [NSMutableArray arrayWithObject:root];
    NSUInteger head = 0;
    NSUInteger seen = 0;
    while (head < queue.count) {
        UIView* view = queue[head++];
        seen++;
        if ([view.accessibilityLabel isEqualToString:wanted]) {
            os_log(NFBProfileProbeLog(),
                   "BALAYAGE  TROUVÉ %{public}@ frame=%{public}@ hidden=%{public}s "
                   "alpha=%.2f parent=%{public}@",
                   NSStringFromClass([view classForCoder]),
                   NSStringFromCGRect(view.frame),
                   view.hidden ? "OUI" : "non",
                   view.alpha,
                   view.superview ? NSStringFromClass([view.superview classForCoder]) : @"nil");
            return;
        }
        [queue addObjectsFromArray:view.subviews];
    }
    os_log(NFBProfileProbeLog(),
           "BALAYAGE  ABSENT de la hiérarchie (%{public}lu vues visitées) — "
           "le bouton n'a jamais été posé", (unsigned long)seen);
}

%hook T1ProfileHeaderViewController

- (NSArray*)actionButtonProviders {
    NSArray* providers = %orig;

    os_log(NFBProfileProbeLog(), "──────── SONDE BOUTON PROFIL ────────");
    os_log(NFBProfileProbeLog(), "RÉGLAGE   copy_profile_info=%{public}s",
           [BHTSettings boolForKey:@"copy_profile_info"] ? "ON" : "OFF");
    os_log(NFBProfileProbeLog(), "FOURNISSEURS  %{public}lu",
           (unsigned long)providers.count);

    // Both hooks sit on this method, so the array seen here may or may not
    // already carry ours depending on install order. The class list settles it.
    BOOL oursPresent = NO;
    for (id provider in providers) {
        NSString* cls = NSStringFromClass([provider classForCoder]);
        if ([cls isEqualToString:@"ProfileCopyButtonProvider"]) {
            oursPresent = YES;
        }
        os_log(NFBProfileProbeLog(), "  · %{public}@", cls);
        NFBProfileProbeDumpSpecs(provider, cls);
    }
    os_log(NFBProfileProbeLog(), "NOTRE FOURNISSEUR présent ici=%{public}s",
           oursPresent ? "OUI" : "non (ordre des hooks)");

    // The header needs a moment to arbitrate and lay the row out; the sweep
    // then reports what actually reached the screen.
    __weak UIViewController* weakController = (UIViewController*)self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        UIViewController* strong = weakController;
        if (strong) {
            NFBProfileProbeFindButton(strong);
        }
    });

    return providers;
}

%end

// Proves the header actually consults our provider, whatever the hook order,
// and reports the numbers our own spec declares next to the native ones.
%hook ProfileCopyButtonProvider

- (NSArray*)buttonSpecs {
    NSArray* specs = %orig;
    os_log(NFBProfileProbeLog(), "NOTRE PROVIDER  buttonSpecs appelé → %{public}lu spec(s)",
           (unsigned long)specs.count);
    for (id spec in specs) {
        os_log(NFBProfileProbeLog(), "   NÔTRE → %{public}@ | %{public}@",
               NFBProfileProbeNumber(spec, @"position"),
               NFBProfileProbeNumber(spec, @"priority"));
    }
    return specs;
}

// The creation block only runs if the arbitration kept our spec. Silence here,
// with buttonSpecs above having spoken, IS the answer: the row dropped it.
- (id)buttonView {
    os_log(NFBProfileProbeLog(), "NOTRE PROVIDER  buttonView appelé — le bouton EST construit");
    return %orig;
}

%end

%ctor {
    os_log(NFBProfileProbeLog(), "SONDE BOUTON PROFIL CHARGÉE — ouvre un profil");
}
