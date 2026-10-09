#import <UIKit/UIKit.h>
#import <substrate.h>
#import <dlfcn.h>
#import <sys/sysctl.h>
#import <sys/utsname.h>
#import <string.h>
#import "DSPProfile.h"

static CFTypeRef (*orig_MGCopyAnswer)(CFStringRef property);

static BOOL DSPShouldSpoofScreen(UIScreen *screen) {
    if (![DSPProfile isSpoofEnabled]) {
        return NO;
    }
    UIScreen *main = [UIScreen mainScreen];
    return main != nil && (screen == main || screen == nil);
}

static BOOL DSPApplyStringAnswer(CFStringRef question, const char **keys, CFStringRef fake, CFTypeRef *out) {
    if (!question || !fake) {
        return NO;
    }
    for (const char **p = keys; *p; p++) {
        CFStringRef key = CFStringCreateWithCString(NULL, *p, kCFStringEncodingUTF8);
        if (!key) {
            continue;
        }
        Boolean match = CFEqual(question, key);
        CFRelease(key);
        if (match) {
            if (out) {
                *out = CFRetain(fake);
            }
            return YES;
        }
    }
    return NO;
}

static CFTypeRef DSP_MGCopyAnswer(CFStringRef property) {
    if (![DSPProfile isSpoofEnabled]) {
        return orig_MGCopyAnswer ? orig_MGCopyAnswer(property) : NULL;
    }

    CFStringRef product = (__bridge CFStringRef)[DSPProfile productType];
    CFStringRef hwModel = (__bridge CFStringRef)[DSPProfile hardwareModel];
    CFStringRef name = (__bridge CFStringRef)[DSPProfile marketingName];

    const char *productKeys[] = {"ProductType", NULL};
    CFTypeRef spoof = NULL;
    if (DSPApplyStringAnswer(property, productKeys, product, &spoof)) {
        return spoof;
    }

    const char *hwKeys[] = {"HardwareModel", "HWModelStr", NULL};
    if (DSPApplyStringAnswer(property, hwKeys, hwModel, &spoof)) {
        return spoof;
    }

    const char *nameKeys[] = {"MarketingName", NULL};
    if (DSPApplyStringAnswer(property, nameKeys, name, &spoof)) {
        return spoof;
    }

    return orig_MGCopyAnswer ? orig_MGCopyAnswer(property) : NULL;
}

static void DSPReplaceCStringBuffer(void *oldp, size_t *oldlenp, const char *value) {
    if (!oldp || !oldlenp || !value) {
        return;
    }
    size_t need = strlen(value) + 1;
    if (*oldlenp >= need) {
        memcpy(oldp, value, need);
        *oldlenp = need;
    }
}

static int (*orig_sysctlbyname)(const char *, void *, size_t *, void *, size_t);

static int DSP_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    int ret = orig_sysctlbyname ? orig_sysctlbyname(name, oldp, oldlenp, newp, newlen) : -1;
    if (ret != 0 || ![DSPProfile isSpoofEnabled] || !name || !oldp || !oldlenp) {
        return ret;
    }
    if (strcmp(name, "hw.machine") == 0) {
        DSPReplaceCStringBuffer(oldp, oldlenp, [DSPProfile hwMachineUTF8]);
    } else if (strcmp(name, "hw.model") == 0) {
        DSPReplaceCStringBuffer(oldp, oldlenp, [DSPProfile hardwareModelUTF8]);
    } else if (strcmp(name, "hw.product") == 0) {
        DSPReplaceCStringBuffer(oldp, oldlenp, [DSPProfile productTypeUTF8]);
    }
    return ret;
}

static int (*orig_sysctl)(int *, u_int, void *, size_t *, void *, size_t);

static int DSP_sysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    int ret = orig_sysctl ? orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen) : -1;
    if (ret != 0 || ![DSPProfile isSpoofEnabled] || !name || namelen < 2 || !oldp || !oldlenp) {
        return ret;
    }
    if (name[0] == CTL_HW) {
        if (name[1] == HW_MACHINE) {
            DSPReplaceCStringBuffer(oldp, oldlenp, [DSPProfile hwMachineUTF8]);
        } else if (name[1] == HW_MODEL) {
            DSPReplaceCStringBuffer(oldp, oldlenp, [DSPProfile hardwareModelUTF8]);
        }
    }
    return ret;
}

static int (*orig_uname)(struct utsname *);

static int DSP_uname(struct utsname *buf) {
    int ret = orig_uname ? orig_uname(buf) : -1;
    if (ret == 0 && buf && [DSPProfile isSpoofEnabled]) {
        strlcpy(buf->machine, [DSPProfile hwMachineUTF8], sizeof(buf->machine));
    }
    return ret;
}

%hook UIScreen

- (CGRect)bounds {
    if (DSPShouldSpoofScreen(self)) {
        return [DSPProfile screenBounds];
    }
    return %orig;
}

- (CGFloat)scale {
    if (DSPShouldSpoofScreen(self)) {
        return [DSPProfile screenScale];
    }
    return %orig;
}

- (CGFloat)nativeScale {
    if (DSPShouldSpoofScreen(self)) {
        return [DSPProfile screenScale];
    }
    return %orig;
}

- (CGRect)nativeBounds {
    if (DSPShouldSpoofScreen(self)) {
        return [DSPProfile nativeScreenBounds];
    }
    return %orig;
}

%end

%ctor {
    [DSPProfile reloadPreferences];

    void *gestalt = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_LAZY);
    if (gestalt) {
        void *sym = dlsym(gestalt, "MGCopyAnswer");
        if (sym) {
            MSHookFunction(sym, (void *)DSP_MGCopyAnswer, (void **)&orig_MGCopyAnswer);
        }
    }

    MSHookFunction((void *)sysctlbyname, (void *)DSP_sysctlbyname, (void **)&orig_sysctlbyname);
    MSHookFunction((void *)sysctl, (void *)DSP_sysctl, (void **)&orig_sysctl);
    MSHookFunction((void *)uname, (void *)DSP_uname, (void **)&orig_uname);
}
