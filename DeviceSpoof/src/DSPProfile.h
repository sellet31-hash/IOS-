#import <CoreGraphics/CoreGraphics.h>

/// Fixed iPhone 13 hardware profile (ProductType iPhone14,5).
@interface DSPProfile : NSObject

/// Stable C strings for use from sysctl/uname hooks (any thread).
+ (const char *)productTypeUTF8;
+ (const char *)hardwareModelUTF8;
+ (const char *)hwMachineUTF8;
+ (const char *)serialNumberUTF8;

+ (NSString *)productType;
+ (NSString *)hardwareModel;
+ (NSString *)hwMachine;
+ (NSString *)marketingName;

+ (CGRect)screenBounds;
+ (CGFloat)screenScale;
+ (CGRect)nativeScreenBounds;

+ (BOOL)isSpoofEnabled;
+ (void)reloadPreferences;

@end
