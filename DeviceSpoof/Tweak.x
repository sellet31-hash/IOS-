#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AdSupport/AdSupport.h>
#import <Security/Security.h>
#import <substrate.h>
#import <dlfcn.h>
#import <errno.h>
#import <string.h>
#import <sys/sysctl.h>
#import <sys/utsname.h>
#import <unistd.h>
#import "DSPProfile.h"
#import "DSPShopeeReport.h"

static void DSPPrepareAnswers(void);

static int (*orig_sysctlbyname)(const char *, void *, size_t *, void *, size_t);
static int (*orig_sysctl)(int *, unsigned int, void *, size_t *, void *, size_t);
static int (*orig_uname)(struct utsname *);
static CFTypeRef (*orig_MGCopyAnswer)(CFStringRef);
static OSStatus (*orig_SecItemCopyMatching)(CFDictionaryRef, CFTypeRef *);
static __thread int gDSPSysctlbynameDepth;
static __thread int gDSPSysctlDepth;
static __thread int gDSPUnameDepth;
static __thread int gDSPStringHookDepth;

static const char *kDSPMachineUTF8;
static const char *kDSPModelUTF8;
static uint32_t gDSPReboundSlots = 0;
static BOOL gDSPAnswersReady = NO;
static NSString *gDSPSeenMachine = nil;

static void DSPWriteLoadMarker(void) {
    NSDictionary *info = @{
        @"version" : @"1.2.28",
        @"bundle" : [[NSBundle mainBundle] bundleIdentifier] ?: @"",
        @"process" : [[NSProcessInfo processInfo] processName] ?: @"",
        @"productType" : [DSPProfile productType],
        @"marketingName" : [DSPProfile marketingName],
        @"enabled" : @([DSPProfile isSpoofEnabled]),
        @"hookSysctl" : @(orig_sysctlbyname != NULL),
        @"hookUname" : @(orig_uname != NULL),
        @"reboundSlots" : @(gDSPReboundSlots),
        @"seenMachine" : gDSPSeenMachine ?: @"",
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
    // kern.osproductversion stays on the real iOS. Reporting 26.0 from sysctl makes Shopee quit.
    if ((strcmp(name, "hw.machine") == 0 || strcmp(name, "hw.product") == 0) && kDSPMachineUTF8) {
        return kDSPMachineUTF8;
    }
    if (strcmp(name, "hw.model") == 0 && kDSPModelUTF8) {
        return kDSPModelUTF8;
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
        return orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
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
        return orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen);
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
        return orig_uname(buffer);
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

- (NSString *)name {
    DSPEnsureReady();
    if ([DSPProfile isSpoofEnabled]) {
        return [DSPProfile spoofedDeviceName];
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

%hook ASIdentifierManager

- (NSUUID *)advertisingIdentifier {
    DSPEnsureReady();
    if ([DSPProfile isSpoofEnabled]) {
        NSUUID *identifier = [DSPProfile spoofedAdvertisingIdentifier];
        if (identifier) {
            return identifier;
        }
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

static NSArray<NSHTTPCookie *> *DSPRewriteCookies(NSArray<NSHTTPCookie *> *cookies) {
    if (![DSPProfile isSpoofEnabled] || ![DSPProfile simulateFreshInstall] || cookies.count == 0) {
        return cookies;
    }
    NSMutableArray<NSHTTPCookie *> *rewritten = [NSMutableArray arrayWithCapacity:cookies.count];
    for (NSHTTPCookie *cookie in cookies) {
        if (![DSPShopeeReport isPersistentDeviceCookieName:cookie.name]) {
            [rewritten addObject:cookie];
            continue;
        }
        NSMutableDictionary *properties = [cookie.properties mutableCopy];
        properties[NSHTTPCookieValue] = [DSPShopeeReport deviceFingerprintHex];
        NSHTTPCookie *replacement = properties ? [NSHTTPCookie cookieWithProperties:properties] : nil;
        [rewritten addObject:replacement ?: cookie];
    }
    return rewritten;
}

%hook NSHTTPCookieStorage

- (NSArray<NSHTTPCookie *> *)cookies {
    return DSPRewriteCookies(%orig);
}

- (NSArray<NSHTTPCookie *> *)cookiesForURL:(NSURL *)URL {
    return DSPRewriteCookies(%orig);
}

- (void)setCookie:(NSHTTPCookie *)cookie {
    if ([DSPProfile isSpoofEnabled] && [DSPProfile simulateFreshInstall] && [DSPShopeeReport isPersistentDeviceCookieName:cookie.name]) {
        NSMutableDictionary *properties = [cookie.properties mutableCopy];
        if (properties) {
            properties[NSHTTPCookieValue] = [DSPShopeeReport deviceFingerprintHex];
            NSHTTPCookie *replacement = [NSHTTPCookie cookieWithProperties:properties];
            if (replacement) {
                %orig(replacement);
                return;
            }
        }
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

static BOOL DSPCFEquals(CFStringRef string, const char *utf8) {
    if (!string || !utf8 || CFGetTypeID(string) != CFStringGetTypeID()) {
        return NO;
    }
    CFStringRef key = CFStringCreateWithCString(NULL, utf8, kCFStringEncodingUTF8);
    BOOL equal = key && CFStringCompare(string, key, 0) == kCFCompareEqualTo;
    if (key) {
        CFRelease(key);
    }
    return equal;
}

static CFTypeRef DSP_MGCopyAnswer(CFStringRef property) {
    if ([DSPProfile isSpoofEnabled] && property && CFGetTypeID(property) == CFStringGetTypeID()) {
        if (DSPCFEquals(property, "ProductType")) {
            return CFStringCreateWithCString(NULL, [DSPProfile productTypeUTF8], kCFStringEncodingUTF8);
        }
        if (DSPCFEquals(property, "HardwareModel") || DSPCFEquals(property, "HWModelStr")) {
            return CFStringCreateWithCString(NULL, [DSPProfile hardwareModelUTF8], kCFStringEncodingUTF8);
        }
        if (DSPCFEquals(property, "SerialNumber")) {
            return CFStringCreateWithCString(NULL, [DSPProfile serialNumberUTF8], kCFStringEncodingUTF8);
        }
        if (DSPCFEquals(property, "MLBSerialNumber")) {
            return CFStringCreateWithCString(NULL, [DSPProfile mlbSerialUTF8], kCFStringEncodingUTF8);
        }
        if (DSPCFEquals(property, "InstallUUID") || DSPCFEquals(property, "InstallationUUID")) {
            return CFStringCreateWithCString(NULL, [DSPProfile installSessionUUIDUTF8], kCFStringEncodingUTF8);
        }
    }
    return orig_MGCopyAnswer ? orig_MGCopyAnswer(property) : NULL;
}

static BOOL DSPSecItemNamesDeviceIdentity(CFDictionaryRef query) {
    if (!query || CFGetTypeID(query) != CFDictionaryGetTypeID()) {
        return NO;
    }
    const void *keys[] = { kSecAttrAccount, kSecAttrService, kSecAttrLabel, kSecAttrGeneric };
    for (unsigned int index = 0; index < sizeof(keys) / sizeof(keys[0]); index++) {
        const void *value = CFDictionaryGetValue(query, keys[index]);
        if (!value || CFGetTypeID(value) != CFStringGetTypeID()) {
            continue;
        }
        NSString *text = [(__bridge NSString *)value lowercaseString];
        if ([text containsString:@"devicefingerprint"] || [text containsString:@"deviceid"] || [text containsString:@"device_id"] ||
            [text containsString:@"spc_f"] || [text containsString:@"spc_did"] || [text containsString:@"installuuid"] ||
            [text containsString:@"idfv"] || [text containsString:@"idfa"]) {
            return YES;
        }
    }
    return NO;
}

static OSStatus DSP_SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    if (![DSPProfile isSpoofEnabled] || ![DSPProfile simulateFreshInstall]) {
        return orig_SecItemCopyMatching ? orig_SecItemCopyMatching(query, result) : errSecParam;
    }
    if (DSPSecItemNamesDeviceIdentity(query)) {
        if (result) {
            *result = NULL;
        }
        return errSecItemNotFound;
    }
    if (!orig_SecItemCopyMatching) {
        return errSecParam;
    }
    OSStatus status = orig_SecItemCopyMatching(query, result);
    if (status != errSecSuccess || !result || !*result || CFGetTypeID(*result) != CFArrayGetTypeID()) {
        return status;
    }
    CFArrayRef items = (CFArrayRef)*result;
    CFIndex count = CFArrayGetCount(items);
    CFMutableArrayRef kept = CFArrayCreateMutable(NULL, (CFIndex)count, &kCFTypeArrayCallBacks);
    for (CFIndex index = 0; index < count; index++) {
        CFTypeRef item = CFArrayGetValueAtIndex(items, index);
        if (item && CFGetTypeID(item) == CFDictionaryGetTypeID() && DSPSecItemNamesDeviceIdentity((CFDictionaryRef)item)) {
            continue;
        }
        if (item) {
            CFArrayAppendValue(kept, item);
        }
    }
    if (CFArrayGetCount(kept) == 0) {
        CFRelease(kept);
        CFRelease(*result);
        *result = NULL;
        return errSecItemNotFound;
    }
    if (CFArrayGetCount(kept) != count) {
        CFRelease(*result);
        *result = kept;
    } else {
        CFRelease(kept);
    }
    return status;
}

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
    // Hook the shared functions. Do not rewrite Shopee's own pages; that makes the process exit.
    DSPHookOne("sysctlbyname", (void *)sysctlbyname, (void *)DSP_sysctlbyname, (void **)&orig_sysctlbyname);
    DSPHookOne("sysctl", (void *)sysctl, (void *)DSP_sysctl, (void **)&orig_sysctl);
    DSPHookOne("uname", (void *)uname, (void *)DSP_uname, (void **)&orig_uname);
    DSPHookOne("SecItemCopyMatching", (void *)SecItemCopyMatching, (void *)DSP_SecItemCopyMatching, (void **)&orig_SecItemCopyMatching);
    void *gestalt = dlsym(RTLD_DEFAULT, "MGCopyAnswer");
    if (!gestalt) {
        void *library = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_LAZY);
        gestalt = library ? dlsym(library, "MGCopyAnswer") : NULL;
    }
    DSPHookOne("MGCopyAnswer", gestalt, (void *)DSP_MGCopyAnswer, (void **)&orig_MGCopyAnswer);
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
    }
    DSPWriteLoadMarker();
    installed = YES;
}
