// Measurements written to the compatibility report, under MEASUREMENTS.
#import <os/lock.h>
#import "Common/PFBCompatibility.h"

// Adds one line under topic, at most cap distinct lines; once the topic is full,
// the call site stops formatting and recording.
#define PFB_PROBE(topic, cap, ...)                                                               \
    do {                                                                                         \
        static BOOL pfbProbeFull;                                                                \
        if (!pfbProbeFull) {                                                                     \
            pfbProbeFull = !PFBCompatMeasure((topic), [NSString stringWithFormat:__VA_ARGS__], (cap)); \
        }                                                                                        \
    } while (0)

// True the first time this file sees a return address, for at most 64 of them, so a
// measurement that names its caller looks the image up once per call site.
static inline BOOL PFBProbeNewCaller(void* caller) {
    static NSMutableSet<NSNumber*>* seen;
    static os_unfair_lock lock = OS_UNFAIR_LOCK_INIT;
    os_unfair_lock_lock(&lock);
    if (!seen) {
        seen = [NSMutableSet set];
    }
    BOOL fresh = seen.count < 64 && ![seen containsObject:@((uintptr_t)caller)];
    if (fresh) {
        [seen addObject:@((uintptr_t)caller)];
    }
    os_unfair_lock_unlock(&lock);
    return fresh;
}

// The first character of a getter's return type, or 0 when the object has no such getter.
static inline char PFBProbeReturnKind(id object, SEL selector) {
    NSMethodSignature* signature = [object respondsToSelector:selector] ? [object methodSignatureForSelector:selector] : nil;
    return signature ? signature.methodReturnType[0] : 0;
}
