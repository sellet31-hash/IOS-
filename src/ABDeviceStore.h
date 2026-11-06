#import <Foundation/Foundation.h>
#import "ABDeviceCatalog.h"

NS_ASSUME_NONNULL_BEGIN

@interface ABDeviceStore : NSObject
+ (BOOL)isEnabled;
+ (BOOL)setEnabled:(BOOL)enabled error:(NSError *_Nullable *_Nullable)error;
+ (ABDeviceModel *)selectedModel;
+ (BOOL)selectModel:(ABDeviceModel *)model error:(NSError *_Nullable *_Nullable)error;
+ (BOOL)requestFreshIdentity:(NSError *_Nullable *_Nullable)error;
@end

NS_ASSUME_NONNULL_END
