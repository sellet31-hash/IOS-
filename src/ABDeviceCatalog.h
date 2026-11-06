#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ABDeviceModel : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *board;
@property (nonatomic, copy) NSString *generation;
@property (nonatomic) double width;
@property (nonatomic) double height;
@property (nonatomic) double scale;
@end

@interface ABDeviceCatalog : NSObject
+ (NSArray<NSString *> *)generations;
+ (NSArray<ABDeviceModel *> *)modelsInGeneration:(NSString *)generation;
+ (ABDeviceModel *)modelForIdentifier:(NSString *)identifier;
+ (ABDeviceModel *)defaultModel;
@end

NS_ASSUME_NONNULL_END
