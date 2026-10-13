#import "DSPProfile.h"
#import <Foundation/Foundation.h>

static NSString *const kDSPPrefsPathRootless = @"/var/jb/Library/Preferences/com.appbackup.devicespoof.plist";
static NSString *const kDSPKeyEnabled = @"enabled";
static NSString *const kDSPKeyVendorUUID = @"vendorUUID";
static NSString *const kDSPKeyStoredVendorUUID = @"storedVendorUUID";
static NSString *const kDSPKeyRegenerateVendorId = @"regenerateVendorId";

static const char kDSPProductTypeUTF8[] = "iPhone14,5";
static const char kDSPHardwareModelUTF8[] = "D17AP";
static const char kDSPSerialUTF8[] = "F3PF534FRQ7E";
static const char kDSPMLBUTF8[] = "F3PF534FRQ7EH7ABC";

static BOOL sDSPEnabled = YES;
static NSUUID *sVendorUUID = nil;

static NSUUID *DSPParseUUID(NSString *value) {
    if (value.length == 0) {
        return nil;
    }
    return [[NSUUID alloc] initWithUUIDString:value];
}

static void DSPSavePlist(NSDictionary *plist) {
    if (!plist) {
        return;
    }
    [plist writeToFile:kDSPPrefsPathRootless atomically:YES];
}

@implementation DSPProfile

+ (void)reloadPreferences {
    NSMutableDictionary *plist = [[NSDictionary dictionaryWithContentsOfFile:kDSPPrefsPathRootless] mutableCopy];
    if (!plist) {
        plist = [NSMutableDictionary dictionary];
    }

    id enabled = plist[kDSPKeyEnabled];
    if ([enabled isKindOfClass:[NSNumber class]]) {
        sDSPEnabled = [(NSNumber *)enabled boolValue];
    } else {
        sDSPEnabled = YES;
    }

    BOOL dirty = NO;
    if ([plist[kDSPKeyRegenerateVendorId] boolValue]) {
        [plist removeObjectForKey:kDSPKeyRegenerateVendorId];
        NSString *fresh = [[NSUUID UUID] UUIDString];
        plist[kDSPKeyStoredVendorUUID] = fresh;
        sVendorUUID = DSPParseUUID(fresh);
        dirty = YES;
    } else {
        NSUUID *manual = DSPParseUUID(plist[kDSPKeyVendorUUID]);
        if (manual) {
            sVendorUUID = manual;
        } else {
            NSUUID *stored = DSPParseUUID(plist[kDSPKeyStoredVendorUUID]);
            if (stored) {
                sVendorUUID = stored;
            } else {
                NSString *fresh = [[NSUUID UUID] UUIDString];
                plist[kDSPKeyStoredVendorUUID] = fresh;
                sVendorUUID = DSPParseUUID(fresh);
                dirty = YES;
            }
        }
    }

    if (dirty) {
        DSPSavePlist(plist);
    }
}

+ (BOOL)isSpoofEnabled {
    return sDSPEnabled;
}

+ (NSUUID *)spoofedVendorIdentifier {
    return sVendorUUID;
}

+ (const char *)productTypeUTF8 {
    return kDSPProductTypeUTF8;
}

+ (const char *)hardwareModelUTF8 {
    return kDSPHardwareModelUTF8;
}

+ (const char *)hwMachineUTF8 {
    return kDSPProductTypeUTF8;
}

+ (const char *)serialNumberUTF8 {
    return kDSPSerialUTF8;
}

+ (const char *)mlbSerialUTF8 {
    return kDSPMLBUTF8;
}

+ (NSString *)productType {
    return @"iPhone14,5";
}

+ (NSString *)hardwareModel {
    return @"D17AP";
}

+ (NSString *)hwMachine {
    return @"iPhone14,5";
}

+ (NSString *)marketingName {
    return @"iPhone 13";
}

+ (CGRect)screenBounds {
    return CGRectMake(0, 0, 390, 844);
}

+ (CGFloat)screenScale {
    return 3.0;
}

+ (CGRect)nativeScreenBounds {
    return CGRectMake(0, 0, 1170, 2532);
}

@end
