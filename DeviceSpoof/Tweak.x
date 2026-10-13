#import <substrate.h>
#import <dlfcn.h>
#import <sys/sysctl.h>
#import <sys/utsname.h>
#import <string.h>
#import "DSPProfile.h"

static CFTypeRef (*orig_MGCopyAnswer)(CFStringRef property);
static int (*orig_sysctlbyname)(const char *, void *, size_t *, void *, size_t);
static int (*orig_uname)(struct utsname *);
static __thread int gDSPSysctlDepth;

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
    if (!orig_MGCopyAnswer) {
        return NULL;
    }
    if (!property || ![DSPProfile isSpoofEnabled]) {
        return orig_MGCopyAnswer(property);
    }

    CFStringRef product = (__bridge CFStringRef)[DSPProfile productType];
    CFStringRef hwModel = (__bridge CFStringRef)[DSPProfile hardwareModel];
    CFStringRef name = (__bridge CFStringRef)[DSPProfile marketingName];
    CFTypeRef spoof = NULL;

    const char *productKeys[] = {"ProductType", NULL};
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
    return orig_MGCopyAnswer(property);
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

static int DSP_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (!orig_sysctlbyname) {
        return -1;
    }
    if (gDSPSysctlDepth > 0) {
        return orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
    }
    gDSPSysctlDepth++;
    int ret = orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
    if (ret == 0 && [DSPProfile isSpoofEnabled] && name && oldp && oldlenp) {
        if (strcmp(name, "hw.machine") == 0) {
            DSPReplaceCStringBuffer(oldp, oldlenp, [DSPProfile hwMachineUTF8]);
        } else if (strcmp(name, "hw.model") == 0) {
            DSPReplaceCStringBuffer(oldp, oldlenp, [DSPProfile hardwareModelUTF8]);
        } else if (strcmp(name, "hw.product") == 0) {
            DSPReplaceCStringBuffer(oldp, oldlenp, [DSPProfile productTypeUTF8]);
        }
    }
    gDSPSysctlDepth--;
    return ret;
}

static int DSP_uname(struct utsname *buf) {
    if (!orig_uname) {
        return -1;
    }
    int ret = orig_uname(buf);
    if (ret == 0 && buf && [DSPProfile isSpoofEnabled]) {
        strlcpy(buf->machine, [DSPProfile hwMachineUTF8], sizeof(buf->machine));
    }
    return ret;
}

static void DSPInstallHooks(void) {
    void *gestalt = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_LAZY);
    if (!gestalt) {
        gestalt = dlopen("/System/Library/Frameworks/MobileGestalt.framework/MobileGestalt", RTLD_LAZY);
    }
    if (gestalt) {
        void *sym = dlsym(gestalt, "MGCopyAnswer");
        if (sym) {
            MSHookFunction(sym, (void *)DSP_MGCopyAnswer, (void **)&orig_MGCopyAnswer);
        }
    }

    MSHookFunction((void *)sysctlbyname, (void *)DSP_sysctlbyname, (void **)&orig_sysctlbyname);
    MSHookFunction((void *)uname, (void *)DSP_uname, (void **)&orig_uname);
}

%ctor {
    [DSPProfile reloadPreferences];
    DSPInstallHooks();
}
