#import <CoreGraphics/CoreGraphics.h>

@class NSUUID;

@interface DSPProfile : NSObject

+ (const char *)productTypeUTF8;
+ (const char *)hardwareModelUTF8;
+ (const char *)hwMachineUTF8;
+ (const char *)serialNumberUTF8;
+ (const char *)mlbSerialUTF8;
+ (const char *)installSessionUUIDUTF8;

+ (NSString *)productType;
+ (NSString *)hardwareModel;
+ (NSString *)hwMachine;
+ (NSString *)marketingName;

+ (CGRect)screenBounds;
+ (CGFloat)screenScale;
+ (CGRect)nativeScreenBounds;

+ (BOOL)isSpoofEnabled;
+ (BOOL)simulateFreshInstall;
+ (NSUUID *)spoofedVendorIdentifier;
+ (void)reloadPreferences;

@end
