// Square avatars (square_avatars): the avatar views and their shadow layer.

#import "Support/HookHelpers.h"

// Style 2 is the circular default and style 3 the rounded square the app uses for
// organization accounts. The views mask and round themselves from the style; the
// circular shadow layer and pre-clipped images are handled below.

@interface TFNAvatarImageView : UIView
@property (nonatomic) NSInteger style;
@end

@interface TUIAvatarImageView : TFNAvatarImageView
@end

@interface UIBarButtonItem (PFBSharedBackground)
- (void)setHidesSharedBackground:(BOOL)hidden;
@end

// Coerced views are marked so disabling the setting can restore just those,
// leaving avatars that are natively rounded squares alone.
static char kCoercedAvatarStyle;

// The side menu's avatars draw a thin round ring, and the one on Home sits on a round
// Liquid Glass capsule of its own size. Square avatars give the ring the avatar's corners
// and hide the capsule; the originals come back when the option is off.
static char kPFBDashAvatarCorner;
static char kPFBAvatarBarBackground;

static NSHashTable* PFBAvatarBarItems(void) {
    static NSHashTable* items;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        items = [NSHashTable weakObjectsHashTable];
    });
    return items;
}

// The square avatar's corner: the layer's own when it is already square, else an eighth
// of the side, as the squared avatar images are cut.
static CGFloat PFBDashAvatarSquareCorner(UIView* avatar, CGFloat original) {
    CGFloat side = MIN(CGRectGetWidth(avatar.bounds), CGRectGetHeight(avatar.bounds));
    return original > 0 && original < side / 2.0 - 0.5 ? original : side / 8.0;
}

static void PFBUpdateDashAvatar(UIView* avatar) {
    NSNumber* corner = objc_getAssociatedObject(avatar, &kPFBDashAvatarCorner);
    if (![PFBSettings boolForKey:@"square_avatars"]) {
        if (corner) {
            avatar.layer.cornerRadius = corner.doubleValue;
            objc_setAssociatedObject(avatar, &kPFBDashAvatarCorner, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return;
    }
    if (!corner) {
        corner = @(avatar.layer.cornerRadius);
        objc_setAssociatedObject(avatar, &kPFBDashAvatarCorner, corner, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CGFloat radius = PFBDashAvatarSquareCorner(avatar, corner.doubleValue);
    if (fabs(avatar.layer.cornerRadius - radius) > 0.01) {
        avatar.layer.cornerRadius = radius;
        avatar.layer.cornerCurve = kCACornerCurveContinuous;
        PFBCOMPAT_ACTION(PFBCompat_square_avatars, @"side menu avatar ring squared");
    }
    Ivar shadowIvar = class_getInstanceVariable(objc_getClass("TFNAvatarImageView"), "_circularShadowLayer");
    CALayer* shadow = shadowIvar ? object_getIvar(avatar, shadowIvar) : nil;
    if ([shadow isKindOfClass:[CALayer class]] && !shadow.hidden) {
        shadow.hidden = YES;
    }
}

static void PFBRefreshAvatarBarItems(void) {
    for (UIBarButtonItem* item in PFBAvatarBarItems().allObjects) {
        NSNumber* original = objc_getAssociatedObject(item, &kPFBAvatarBarBackground);
        SEL setter = NSSelectorFromString(@"setHidesSharedBackground:");
        if (original && [item respondsToSelector:setter]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(item, setter, original.boolValue);
        }
    }
}

static NSInteger CoercedStyle(UIView* view, NSInteger style) {
    if (style == 2) {
        if (![PFBSettings boolForKey:@"square_avatars"]) {
            PFBCOMPAT_OBSERVE(PFBCompat_square_avatars, @"round avatar found");
        }
        if ([PFBSettings boolForKey:@"square_avatars"]) {
            objc_setAssociatedObject(view, &kCoercedAvatarStyle, @YES,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            PFBCOMPAT_ACTION(PFBCompat_square_avatars, @"avatar squared");
            return 3;
        }
        objc_setAssociatedObject(view, &kCoercedAvatarStyle, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return style;
}

void PFBApplySquareAvatarsSetting(void) {
    BOOL enabled = [PFBSettings boolForKey:@"square_avatars"];
    Class avatarClass = objc_getClass("TFNAvatarImageView");
    Class dashAvatarClass = objc_getClass("_TtC11TwitterDash19DashAvatarImageView");
    PFBRefreshAvatarBarItems();

    for (UIWindow* window in UIApplication.sharedApplication.windows) {
        PFBEnumerateSubviewsRecursively(window, ^(UIView* view) {
            if (![view isKindOfClass:avatarClass] || ![view respondsToSelector:@selector(style)]) {
                return;
            }

            if (dashAvatarClass && [view isKindOfClass:dashAvatarClass]) {
                PFBUpdateDashAvatar(view);
            }
            TFNAvatarImageView* avatar = (TFNAvatarImageView*)view;
            if (enabled
                    ? avatar.style == 2
                    : objc_getAssociatedObject(avatar, &kCoercedAvatarStyle) != nil) {
                // Re-sent as circular; the hook coerces it when the setting is on.
                [avatar setStyle:2];
            }
        });
    }
}

%hook TFNAvatarImageView

- (void)setStyle:(NSInteger)style {
    %orig(CoercedStyle(self, style));
}

%end

// TUIAvatarImageView picks its circular pre-clip transformer from the incoming
// style, so the coercion runs first. Its style mapping also feeds the Swift avatar
// views, whose setter is unreachable from ObjC.
%hook TUIAvatarImageView

- (void)setStyle:(NSInteger)style {
    %orig(CoercedStyle(self, style));
}

+ (NSInteger)avatarImageViewStyleWithProfileImageShape:(NSInteger)shape
                                          identityType:(NSInteger)identityType {
    if (![PFBSettings boolForKey:@"square_avatars"]) {
        PFBCOMPAT_OBSERVE(PFBCompat_square_avatars, @"avatar style read");
        return %orig;
    }
    PFBCOMPAT_ACTION(PFBCompat_square_avatars, @"square style given");
    return 3;
}

%end

// Some fetch helpers install the circular transformer unconditionally, so
// images that get pre-clipped are rounded as squares instead of circles.
%hook UIImage

- (UIImage*)tfn_roundImageWithTargetDimensions:(CGSize)targetDimensions
                             targetContentMode:
                                 (UIViewContentMode)targetContentMode {
    if (![PFBSettings boolForKey:@"square_avatars"]) {
        return %orig;
    }

    if (targetDimensions.width <= 0 || targetDimensions.height <= 0) {
        return self;
    }

    CGRect imageRect =
        CGRectMake(0, 0, targetDimensions.width, targetDimensions.height);
    CGFloat cornerRadius =
        MIN(targetDimensions.width, targetDimensions.height) / 8.0;
    // Aspect fill and fit keep the image's proportions, centered; other modes fill the target.
    CGRect drawRect = imageRect;
    CGSize source = self.size;
    if (source.width > 0 && source.height > 0 &&
        (targetContentMode == UIViewContentModeScaleAspectFill ||
         targetContentMode == UIViewContentModeScaleAspectFit)) {
        CGFloat scaleX = targetDimensions.width / source.width;
        CGFloat scaleY = targetDimensions.height / source.height;
        CGFloat scale = targetContentMode == UIViewContentModeScaleAspectFill ? MAX(scaleX, scaleY)
                                                                              : MIN(scaleX, scaleY);
        CGSize drawn = {source.width * scale, source.height * scale};
        drawRect = CGRectMake((targetDimensions.width - drawn.width) / 2.0,
                              (targetDimensions.height - drawn.height) / 2.0, drawn.width, drawn.height);
    }

    UIGraphicsBeginImageContextWithOptions(targetDimensions, NO, self.scale);
    if (!UIGraphicsGetCurrentContext()) {
        UIGraphicsEndImageContext();
        return self;
    }

    [[UIBezierPath bezierPathWithRoundedRect:imageRect
                                cornerRadius:cornerRadius] addClip];
    [self drawInRect:drawRect];

    UIImage* roundedImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (roundedImage) {
        PFBCOMPAT_ACTION(PFBCompat_square_avatars, @"avatar image squared");
    }

    return roundedImage ?: self;
}

%end

%hook _TtC11TwitterDash19DashAvatarImageView

- (void)layoutSubviews {
    %orig;
    PFBUpdateDashAvatar((UIView*)self);
}

%end

%hook _TtC11TwitterDash26TabRootAvatarBarButtonItem

- (void)setHidesSharedBackground:(BOOL)hidden {
    objc_setAssociatedObject(self, &kPFBAvatarBarBackground, @(hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [PFBAvatarBarItems() addObject:self];
    if ([PFBSettings boolForKey:@"square_avatars"]) {
        PFBCOMPAT_ACTION(PFBCompat_square_avatars, @"side menu avatar round capsule hidden");
        %orig(YES);
        return;
    }
    %orig;
}

%end

%hook TFNCircularAvatarShadowLayer

- (void)setHidden:(BOOL)hidden {
    %orig([PFBSettings boolForKey:@"square_avatars"] ? YES : hidden);
}

%end
