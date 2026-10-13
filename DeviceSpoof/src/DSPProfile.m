#import "DSPProfile.h"
#import <Foundation/Foundation.h>

static NSString *const kDSPPrefsPathRootless = @"/var/jb/Library/Preferences/com.appbackup.devicespoof.plist";

static const char kDSPProductTypeUTF8[] = "iPhone14,5";
static const char kDSPHardwareModelUTF8[] = "D17AP";
static const char kDSPSerialUTF8[] = "F3PF534FRQ7E";

static BOOL sDSPEnabled = YES;

@implementation DSPProfile

+ (void)reloadPreferences {
    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:kDSPPrefsPathRootless];
    if (!plist) {
        sDSPEnabled = YES;
        return;
    }
    id enabled = plist[@"enabled"];
    if ([enabled isKindOfClass:[NSNumber class]]) {
        sDSPEnabled = [(NSNumber *)enabled boolValue];
        return;
    }
    sDSPEnabled = YES;
}

+ (BOOL)isSpoofEnabled {
    return sDSPEnabled;
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
