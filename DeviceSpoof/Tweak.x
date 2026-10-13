#import <substrate.h>
#import <dlfcn.h>
#import <CoreFoundation/CoreFoundation.h>
#import "DSPProfile.h"

static CFTypeRef (*orig_MGCopyAnswer)(CFStringRef property);
static CFStringRef kDSPProductTypeKey;
static CFStringRef kDSPHardwareModelKey;
static CFStringRef kDSPHWModelStrKey;
static CFStringRef kDSPProductTypeValue;
static CFStringRef kDSPHardwareModelValue;

static CFStringRef DSPAnswer(CFStringRef property) {
    if (!property || CFGetTypeID(property) != CFStringGetTypeID()) {
        return NULL;
    }
    if (kDSPProductTypeKey && CFEqual(property, kDSPProductTypeKey)) {
        return kDSPProductTypeValue;
    }
    if ((kDSPHardwareModelKey && CFEqual(property, kDSPHardwareModelKey)) ||
        (kDSPHWModelStrKey && CFEqual(property, kDSPHWModelStrKey))) {
        return kDSPHardwareModelValue;
    }
    return NULL;
}

static CFTypeRef DSP_MGCopyAnswer(CFStringRef property) {
    if (!orig_MGCopyAnswer) {
        return NULL;
    }
    CFStringRef answer = DSPAnswer(property);
    if (answer) {
        return CFRetain(answer);
    }
    return orig_MGCopyAnswer(property);
}

static void DSPPrepareAnswers(void) {
    kDSPProductTypeKey = CFStringCreateWithCString(NULL, "ProductType", kCFStringEncodingUTF8);
    kDSPHardwareModelKey = CFStringCreateWithCString(NULL, "HardwareModel", kCFStringEncodingUTF8);
    kDSPHWModelStrKey = CFStringCreateWithCString(NULL, "HWModelStr", kCFStringEncodingUTF8);
    kDSPProductTypeValue = CFStringCreateWithCString(NULL, [DSPProfile productTypeUTF8], kCFStringEncodingUTF8);
    kDSPHardwareModelValue = CFStringCreateWithCString(NULL, [DSPProfile hardwareModelUTF8], kCFStringEncodingUTF8);
}

static void DSPInstallHooks(void) {
    if (!kDSPProductTypeValue || !kDSPHardwareModelValue) {
        return;
    }
    void *gestalt = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_LAZY);
    if (!gestalt) {
        gestalt = dlopen("/System/Library/Frameworks/MobileGestalt.framework/MobileGestalt", RTLD_LAZY);
    }
    if (!gestalt) {
        return;
    }
    void *sym = dlsym(gestalt, "MGCopyAnswer");
    if (!sym) {
        return;
    }
    MSHookFunction(sym, (void *)DSP_MGCopyAnswer, (void **)&orig_MGCopyAnswer);
}

%ctor {
    [DSPProfile reloadPreferences];
    if (![DSPProfile isSpoofEnabled]) {
        return;
    }
    DSPPrepareAnswers();
    DSPInstallHooks();
}
