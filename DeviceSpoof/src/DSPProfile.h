#import <CoreGraphics/CoreGraphics.h>

@class NSUUID;

/// Fixed iPhone 13 hardware profile (ProductType iPhone14,5).
@interface DSPProfile : NSObject

+ (const char *)productTypeUTF8;
+ (const char *)hardwareModelUTF8;
+ (const char *)hwMachineUTF8;
+ (const char *)serialNumberUTF8;
+ (const char *)mlbSerialUTF8;

+ (NSString *)productType;
+ (NSString *)hardwareModel;
+ (NSString *)hwMachine;
+ (NSString *)marketingName;

+ (CGRect)screenBounds;
+ (CGFloat)screenScale;
+ (CGRect)nativeScreenBounds;

+ (BOOL)isSpoofEnabled;
+ (NSUUID *)spoofedVendorIdentifier;
+ (void)reloadPreferences;

@end
