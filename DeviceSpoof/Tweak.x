#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <UIKit/UIKit.h>
#import <substrate.h>
#import <dlfcn.h>
#import <errno.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <sys/sysctl.h>
#import <sys/utsname.h>
#import <unistd.h>
#import "DSPProfile.h"
#import "DSPShopeeReport.h"

#ifndef VM_PROT_COPY
#define VM_PROT_COPY 0x10
#endif

static void DSPPrepareAnswers(void);

static CFTypeRef (*orig_MGCopyAnswer)(CFStringRef);
static int (*orig_sysctlbyname)(const char *, void *, size_t *, void *, size_t);
static int (*orig_sysctl)(int *, unsigned int, void *, size_t *, void *, size_t);
static int (*orig_uname)(struct utsname *);
static __thread int gDSPSysctlbynameDepth;
static __thread int gDSPSysctlDepth;
static __thread int gDSPUnameDepth;
static __thread int gDSPStringHookDepth;

static const char *kDSPMachineUTF8;
static const char *kDSPModelUTF8;
static const char *kDSPIOSVersionUTF8;
static uint32_t gDSPReboundSlots = 0;
static uint32_t gDSPProtectFails = 0;
static uint32_t gDSPImagesSeen = 0;
static BOOL gDSPAnswersReady = NO;
static NSString *gDSPSeenMachine = nil;
static NSString *gDSPSeenModel = nil;

static void DSPWriteLoadMarker(void) {
    NSDictionary *info = @{
        @"version" : @"1.2.24",
        @"bundle" : [[NSBundle mainBundle] bundleIdentifier] ?: @"",
        @"process" : [[NSProcessInfo processInfo] processName] ?: @"",
        @"productType" : [DSPProfile productType],
        @"marketingName" : [DSPProfile marketingName],
        @"enabled" : @([DSPProfile isSpoofEnabled]),
        @"hookSysctl" : @(orig_sysctlbyname != NULL),
        @"hookUname" : @(orig_uname != NULL),
        @"hookGestalt" : @(orig_MGCopyAnswer != NULL),
        @"reboundSlots" : @(gDSPReboundSlots),
        @"seenMachine" : gDSPSeenMachine ?: @"",
        @"seenModel" : gDSPSeenModel ?: @"",
        @"protectFails" : @(gDSPProtectFails),
        @"imagesSeen" : @(gDSPImagesSeen),
        @"loadedAt" : @((NSInteger)[[NSDate date] timeIntervalSince1970]),
        @"markerHint" : @"Filza: Shopee container Library/Caches, or /var/jb/tmp/",
    };
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:info
                                                            format:NSPropertyListXMLFormat_v1_0
                                                           options:0
                                                             error:nil];
    if (!data) {
        return;
    }
    NSString *fileName = @"com.appbackup.devicespoof.lastload.plist";
    NSString *sandboxCaches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    if (sandboxCaches.length) {
        [data writeToFile:[sandboxCaches stringByAppendingPathComponent:fileName] atomically:YES];
    }
    [data writeToFile:[@"/var/jb/tmp" stringByAppendingPathComponent:fileName] atomically:YES];
}

static void DSPEnsureReady(void) {
    if (gDSPAnswersReady) {
        return;
    }
    [DSPProfile reloadPreferences];
    if ([DSPProfile isSpoofEnabled]) {
        DSPPrepareAnswers();
    }
    gDSPAnswersReady = YES;
}

static const char *DSPSpoofForSysctlName(const char *name) {
    if (!name) {
        return NULL;
    }
    if ((strcmp(name, "hw.machine") == 0 || strcmp(name, "hw.product") == 0) && kDSPMachineUTF8) {
        return kDSPMachineUTF8;
    }
    if (strcmp(name, "hw.model") == 0 && kDSPModelUTF8) {
        return kDSPModelUTF8;
    }
    if (strcmp(name, "kern.osproductversion") == 0 && kDSPIOSVersionUTF8) {
        return kDSPIOSVersionUTF8;
    }
    return NULL;
}

static int DSPWriteSpoofedCString(void *oldp, size_t *oldlenp, const char *value) {
    size_t need = strlen(value) + 1;
    if (!oldp) {
        if (oldlenp) {
            *oldlenp = need;
        }
        return 0;
    }
    if (!oldlenp) {
        errno = EINVAL;
        return -1;
    }
    if (*oldlenp < need) {
        *oldlenp = need;
        errno = ENOMEM;
        return -1;
    }
    memcpy(oldp, value, need);
    *oldlenp = need;
    return 0;
}

static int DSP_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    const char *spoof = DSPSpoofForSysctlName(name);
    if (spoof) {
        return DSPWriteSpoofedCString(oldp, oldlenp, spoof);
    }
    if (!orig_sysctlbyname) {
        errno = ENOSYS;
        return -1;
    }
    if (gDSPSysctlbynameDepth > 0) {
        errno = EAGAIN;
        return -1;
    }
    gDSPSysctlbynameDepth++;
    int result = orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
    gDSPSysctlbynameDepth--;
    return result;
}

static int DSP_sysctl(int *name, unsigned int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (name && namelen >= 2 && name[0] == CTL_HW) {
        const char *spoof = NULL;
        if (name[1] == HW_MACHINE && kDSPMachineUTF8) {
            spoof = kDSPMachineUTF8;
        } else if (name[1] == HW_MODEL && kDSPModelUTF8) {
            spoof = kDSPModelUTF8;
        }
        if (spoof) {
            return DSPWriteSpoofedCString(oldp, oldlenp, spoof);
        }
    }
    if (!orig_sysctl) {
        errno = ENOSYS;
        return -1;
    }
    if (gDSPSysctlDepth > 0) {
        errno = EAGAIN;
        return -1;
    }
    gDSPSysctlDepth++;
    int result = orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen);
    gDSPSysctlDepth--;
    return result;
}

static int DSP_uname(struct utsname *buffer) {
    if (!orig_uname) {
        errno = ENOSYS;
        return -1;
    }
    if (gDSPUnameDepth > 0) {
        errno = EAGAIN;
        return -1;
    }
    gDSPUnameDepth++;
    int result = orig_uname(buffer);
    gDSPUnameDepth--;
    if (result == 0 && buffer && kDSPMachineUTF8) {
        strlcpy(buffer->machine, kDSPMachineUTF8, sizeof(buffer->machine));
    }
    return result;
}

static void DSPPrepareAnswers(void) {
    kDSPMachineUTF8 = [DSPProfile hwMachineUTF8];
    kDSPModelUTF8 = [DSPProfile hardwareModelUTF8];
    kDSPIOSVersionUTF8 = [DSPProfile osVersionUTF8];
}

__attribute__((constructor(1))) static void DSPEarlyLoadNote(void) {
    FILE *file = fopen("/var/jb/tmp/devicespoof-loaded.txt", "w");
    if (!file) {
        return;
    }
    fprintf(file, "pid=%d prog=%s\n", getpid(), getprogname() ? getprogname() : "");
    fclose(file);
}

%hook UIDevice

- (NSUUID *)identifierForVendor {
    DSPEnsureReady();
    if ([DSPProfile isSpoofEnabled]) {
        NSUUID *vendor = [DSPProfile spoofedVendorIdentifier];
        if (vendor) {
            return vendor;
        }
    }
    return %orig;
}

- (NSString *)systemVersion {
    DSPEnsureReady();
    if ([DSPProfile isSpoofEnabled]) {
        return [DSPProfile spoofedOSVersion];
    }
    return %orig;
}

- (NSString *)model {
    DSPEnsureReady();
    if ([DSPProfile isSpoofEnabled]) {
        return [DSPProfile marketingName];
    }
    return %orig;
}

- (NSString *)localizedModel {
    DSPEnsureReady();
    if ([DSPProfile isSpoofEnabled]) {
        return [DSPProfile marketingName];
    }
    return %orig;
}

- (NSString *)machineModel {
    DSPEnsureReady();
    if ([DSPProfile isSpoofEnabled]) {
        return [DSPProfile productType];
    }
    return %orig;
}

- (NSString *)machineModelName {
    DSPEnsureReady();
    if ([DSPProfile isSpoofEnabled]) {
        return [DSPProfile marketingName];
    }
    return %orig;
}

%end

%hook UIScreen

- (CGRect)bounds {
    if ([DSPProfile isSpoofEnabled]) {
        return [DSPProfile screenBounds];
    }
    return %orig;
}

- (CGRect)nativeBounds {
    if ([DSPProfile isSpoofEnabled]) {
        return [DSPProfile nativeScreenBounds];
    }
    return %orig;
}

- (CGFloat)scale {
    if ([DSPProfile isSpoofEnabled]) {
        return [DSPProfile screenScale];
    }
    return %orig;
}

- (CGFloat)nativeScale {
    if ([DSPProfile isSpoofEnabled]) {
        return [DSPProfile screenScale];
    }
    return %orig;
}

%end

%hook NSProcessInfo

- (NSOperatingSystemVersion)operatingSystemVersion {
    if ([DSPProfile isSpoofEnabled]) {
        NSOperatingSystemVersion version = {0};
        version.majorVersion = 26;
        version.minorVersion = 0;
        version.patchVersion = 0;
        return version;
    }
    return %orig;
}

- (NSString *)operatingSystemVersionString {
    if ([DSPProfile isSpoofEnabled]) {
        return [DSPProfile spoofedOSVersion];
    }
    return %orig;
}

%end

%hook NSUserDefaults

- (NSString *)stringForKey:(NSString *)defaultName {
    if ([DSPProfile isSpoofEnabled] && defaultName.length > 0) {
        if ([DSPShopeeReport isDeviceFingerprintKey:defaultName]) {
            return [DSPShopeeReport deviceFingerprintHex];
        }
        if ([DSPShopeeReport isDeviceModelKey:defaultName]) {
            return [DSPShopeeReport productTypeForReports];
        }
        if ([DSPShopeeReport isOSVersionKey:defaultName]) {
            return [DSPShopeeReport osVersionForReports];
        }
        if ([DSPShopeeReport isMarketingNameKey:defaultName]) {
            return [DSPShopeeReport marketingNameForReports];
        }
    }
    return %orig;
}

- (id)objectForKey:(NSString *)defaultName {
    id value = %orig;
    if (![DSPProfile isSpoofEnabled] || defaultName.length == 0) {
        return value;
    }
    if ([DSPShopeeReport isDeviceFingerprintKey:defaultName]) {
        return [DSPShopeeReport deviceFingerprintHex];
    }
    if ([DSPShopeeReport isDeviceModelKey:defaultName] && [value isKindOfClass:[NSString class]]) {
        NSString *stringValue = (NSString *)value;
        if ([stringValue containsString:@"iPhone"] || [stringValue containsString:@"iPad"]) {
            return [DSPShopeeReport productTypeForReports];
        }
    }
    if ([DSPShopeeReport isOSVersionKey:defaultName]) {
        return [DSPShopeeReport osVersionForReports];
    }
    if ([DSPShopeeReport isMarketingNameKey:defaultName]) {
        return [DSPShopeeReport marketingNameForReports];
    }
    if ([value isKindOfClass:[NSString class]]) {
        NSString *replaced = [DSPShopeeReport replaceHardwareTokensInString:(NSString *)value];
        if (replaced.length > 0 && ![replaced isEqualToString:(NSString *)value]) {
            return replaced;
        }
    }
    return value;
}

- (void)setObject:(id)value forKey:(NSString *)defaultName {
    if ([DSPProfile isSpoofEnabled] && [value isKindOfClass:[NSString class]]) {
        value = [DSPShopeeReport replaceHardwareTokensInString:(NSString *)value];
    }
    %orig;
}

%end

%hook NSJSONSerialization

+ (NSData *)dataWithJSONObject:(id)obj options:(NSUInteger)opt error:(NSError **)error {
    if ([DSPProfile isSpoofEnabled] && obj) {
        id rewritten = [DSPShopeeReport rewritePayloadIfNeeded:obj];
        return %orig(rewritten, opt, error);
    }
    return %orig(obj, opt, error);
}

%end

%hook NSMutableURLRequest

- (void)setHTTPBody:(NSData *)HTTPBody {
    if ([DSPProfile isSpoofEnabled] && HTTPBody.length > 0) {
        NSData *replaced = [DSPShopeeReport replaceHardwareTokensInData:HTTPBody];
        %orig(replaced ?: HTTPBody);
        return;
    }
    %orig;
}

%end

%hook NSString

+ (instancetype)stringWithUTF8String:(const char *)bytes {
    const char *realMachine = [DSPProfile realMachineUTF8];
    if (gDSPStringHookDepth > 0 || ![DSPProfile isSpoofEnabled] || !bytes || !realMachine || !strstr(bytes, realMachine)) {
        return %orig;
    }
    gDSPStringHookDepth++;
    NSString *value = %orig;
    NSString *replaced = value ? [DSPShopeeReport replaceHardwareTokensInString:value] : value;
    gDSPStringHookDepth--;
    return replaced ?: value;
}

+ (instancetype)stringWithCString:(const char *)bytes encoding:(NSStringEncoding)encoding {
    const char *realMachine = [DSPProfile realMachineUTF8];
    if (gDSPStringHookDepth > 0 || ![DSPProfile isSpoofEnabled] || !bytes || !realMachine || !strstr(bytes, realMachine)) {
        return %orig;
    }
    gDSPStringHookDepth++;
    NSString *value = %orig;
    NSString *replaced = value ? [DSPShopeeReport replaceHardwareTokensInString:value] : value;
    gDSPStringHookDepth--;
    return replaced ?: value;
}

%end

static BOOL DSPHookOne(const char *name, void *linked, void *replacement, void **original) {
    void *symbol = name ? dlsym(RTLD_DEFAULT, name) : NULL;
    if (!symbol) {
        symbol = linked;
    }
    if (!symbol || !replacement || !original || *original) {
        return NO;
    }
    void *previous = NULL;
    MSHookFunction(symbol, replacement, &previous);
    if (!previous || previous == symbol || previous == replacement) {
        return NO;
    }
    *original = previous;
    gDSPReboundSlots++;
    return YES;
}

static void DSPInstallSafeHooks(void) {
    if (access("/var/jb/tmp/devicespoof-nohook", F_OK) == 0) {
        return;
    }
    DSPHookOne("sysctlbyname", (void *)sysctlbyname, (void *)DSP_sysctlbyname, (void **)&orig_sysctlbyname);
    DSPHookOne("sysctl", (void *)sysctl, (void *)DSP_sysctl, (void **)&orig_sysctl);
    DSPHookOne("uname", (void *)uname, (void *)DSP_uname, (void **)&orig_uname);
}

%ctor {
    static BOOL installed = NO;
    if (installed) {
        return;
    }
    DSPWriteLoadMarker();
    NSString *bundleIdentifier = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
    NSString *processName = [[NSProcessInfo processInfo] processName] ?: @"";
    BOOL isShopee = [bundleIdentifier rangeOfString:@"shopee" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                    [processName rangeOfString:@"shopee" options:NSCaseInsensitiveSearch].location != NSNotFound;
    if (!isShopee) {
        installed = YES;
        return;
    }
    [DSPProfile reloadPreferences];
    DSPEnsureReady();
    if ([DSPProfile isSpoofEnabled]) {
        char realMachine[32] = {0};
        size_t realMachineLength = sizeof(realMachine);
        if (sysctlbyname("hw.machine", realMachine, &realMachineLength, NULL, 0) == 0 && realMachine[0]) {
            [DSPProfile captureRealMachine:realMachine];
        }
        DSPInstallSafeHooks();
        char seenMachine[32] = {0};
        size_t seenLength = sizeof(seenMachine);
        if (sysctlbyname("hw.machine", seenMachine, &seenLength, NULL, 0) == 0 && seenMachine[0]) {
            gDSPSeenMachine = [[NSString alloc] initWithBytes:seenMachine length:strlen(seenMachine) encoding:NSUTF8StringEncoding];
        }
        gDSPSeenModel = [[UIDevice currentDevice] model];
    }
    DSPWriteLoadMarker();
    installed = YES;
}
