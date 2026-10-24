#import <Foundation/Foundation.h>

/// Frida 成功路径里反复出现的 Shopee 客户端主键（32 位 HEX，非 IDFV 格式）。
@interface DSPShopeeReport : NSObject

+ (NSString *)deviceFingerprintHex;
+ (NSString *)productTypeForReports;
+ (NSString *)osVersionForReports;

+ (BOOL)isDeviceFingerprintKey:(NSString *)key;
+ (BOOL)isDeviceModelKey:(NSString *)key;
+ (BOOL)isOSVersionKey:(NSString *)key;
+ (BOOL)isMarketingNameKey:(NSString *)key;
+ (NSString *)marketingNameForReports;

/// 深拷贝并改写上报 JSON 里的设备字段（仅字段名匹配，不碰 token/phone）。
+ (id)rewritePayloadIfNeeded:(id)object;

@end
