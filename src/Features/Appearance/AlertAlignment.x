// Twitter's alerts set their title and message as iOS's alerts do: from the leading edge, not
// centered.

#import "Support/HookHelpers.h"
#import "Common/PFBCompatibility.h"

// A label held in one of the view's stored properties; nil for a slot outside the instance or a
// value that cannot be an object.
static UILabel* PFBAlertLabel(UIView* content, Ivar field) {
    if (!field) {
        return nil;
    }
    ptrdiff_t offset = ivar_getOffset(field);
    if (offset < (ptrdiff_t)sizeof(void*) || (size_t)offset + sizeof(id) > class_getInstanceSize(object_getClass(content))) {
        return nil;
    }
    uintptr_t reference = 0;
    memcpy(&reference, (const uint8_t*)(__bridge void*)content + offset, sizeof(reference));
    if (reference < 4096 || reference % sizeof(void*)) {
        return nil;
    }
    id value = object_getIvar(content, field);
    return [value isKindOfClass:[UILabel class]] ? value : nil;
}

// The alert's title and message, aligned to the reading direction.
static void PFBAlignAlertText(UIView* content) {
    static Ivar title;
    static Ivar message;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      Class cls = objc_getClass("_TtC13XDesignSystem16AlertContentView");
      title = cls ? class_getInstanceVariable(cls, "titleLabel") : NULL;
      message = cls ? class_getInstanceVariable(cls, "messageLabel") : NULL;
    });
    Ivar fields[2] = {title, message};
    BOOL found = NO;
    for (NSUInteger i = 0; i < 2; i++) {
        UILabel* label = PFBAlertLabel(content, fields[i]);
        if (!label) {
            continue;
        }
        found = YES;
        if (label.textAlignment != NSTextAlignmentNatural) {
            label.textAlignment = NSTextAlignmentNatural;
        }
    }
    if (found) {
        PFBCOMPAT_ACTION(PFBCompat_left_aligned_alerts, @"alert text aligned");
    }
}

%hook _TtC13XDesignSystem16AlertContentView

- (void)layoutSubviews {
    %orig;
    PFBAlignAlertText((UIView*)self);
}

%end
