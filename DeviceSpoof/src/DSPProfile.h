#import <CoreGraphics/CoreGraphics.h>

/// Fixed iPhone 11 hardware profile (ProductType iPhone12,1).
@interface DSPProfile : NSObject

/// Stable C strings for use from sysctl/uname hooks (any thread).
+ (const char *)productTypeUTF8;
+ (const char *)hardwareModelUTF8;
+ (const char *)hwMachineUTF8;

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
