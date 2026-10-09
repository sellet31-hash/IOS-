#import "DSPProfile.h"
#import <Foundation/Foundation.h>

static NSString *const kDSPPrefsPathRootless = @"/var/jb/Library/Preferences/com.appbackup.devicespoof.plist";

static const char kDSPProductTypeUTF8[] = "iPhone12,1";
static const char kDSPHardwareModelUTF8[] = "N104AP";

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

+ (NSString *)productType {
    return @"iPhone12,1";
}

+ (NSString *)hardwareModel {
    return @"N104AP";
}

+ (NSString *)hwMachine {
    return @"iPhone12,1";
}

+ (NSString *)marketingName {
    return @"iPhone 11";
}

+ (CGRect)screenBounds {
    return CGRectMake(0, 0, 414, 896);
}

+ (CGFloat)screenScale {
    return 2.0;
}

+ (CGRect)nativeScreenBounds {
    return CGRectMake(0, 0, 828, 1792);
}

@end
