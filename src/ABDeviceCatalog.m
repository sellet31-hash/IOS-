#import "ABDeviceCatalog.h"

@implementation ABDeviceModel
@end

static ABDeviceModel *ABModel(NSString *generation, NSString *name, NSString *identifier, NSString *board, double width, double height, double scale) {
    ABDeviceModel *model = [ABDeviceModel new];
    model.generation = generation;
    model.name = name;
    model.identifier = identifier;
    model.board = board;
    model.width = width;
    model.height = height;
    model.scale = scale;
    return model;
}

@implementation ABDeviceCatalog

+ (NSArray<ABDeviceModel *> *)allModels {
    static NSArray<ABDeviceModel *> *models;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        models = @[
            ABModel(@"iPhone 7", @"iPhone 7 Plus", @"iPhone9,2", @"D11AP", 414, 736, 3),
            ABModel(@"iPhone 8", @"iPhone 8", @"iPhone10,1", @"D20AP", 375, 667, 2),
            ABModel(@"iPhone 8", @"iPhone 8 Plus", @"iPhone10,2", @"D21AP", 414, 736, 3),
            ABModel(@"iPhone X", @"iPhone X", @"iPhone10,3", @"D22AP", 375, 812, 3),
            ABModel(@"iPhone X", @"iPhone XR", @"iPhone11,8", @"N841AP", 414, 896, 2),
            ABModel(@"iPhone X", @"iPhone XS", @"iPhone11,2", @"D321AP", 375, 812, 3),
            ABModel(@"iPhone X", @"iPhone XS Max", @"iPhone11,4", @"D331AP", 414, 896, 3),
            ABModel(@"iPhone 11", @"iPhone 11", @"iPhone12,1", @"N104AP", 414, 896, 2),
            ABModel(@"iPhone 11", @"iPhone 11 Pro", @"iPhone12,3", @"D421AP", 375, 812, 3),
            ABModel(@"iPhone 11", @"iPhone 11 Pro Max", @"iPhone12,5", @"D431AP", 414, 896, 3),
            ABModel(@"iPhone SE", @"iPhone SE（第二代）", @"iPhone12,8", @"D79AP", 375, 667, 2),
            ABModel(@"iPhone 12", @"iPhone 12 mini", @"iPhone13,1", @"D52gAP", 360, 780, 3),
            ABModel(@"iPhone 12", @"iPhone 12", @"iPhone13,2", @"D53gAP", 390, 844, 3),
            ABModel(@"iPhone 12", @"iPhone 12 Pro", @"iPhone13,3", @"D53pAP", 390, 844, 3),
            ABModel(@"iPhone 12", @"iPhone 12 Pro Max", @"iPhone13,4", @"D54pAP", 428, 926, 3),
            ABModel(@"iPhone 13", @"iPhone 13 mini", @"iPhone14,4", @"D16AP", 360, 780, 3),
            ABModel(@"iPhone 13", @"iPhone 13", @"iPhone14,5", @"D17AP", 390, 844, 3),
            ABModel(@"iPhone 13", @"iPhone 13 Pro", @"iPhone14,2", @"D63AP", 390, 844, 3),
            ABModel(@"iPhone 13", @"iPhone 13 Pro Max", @"iPhone14,3", @"D64AP", 428, 926, 3),
            ABModel(@"iPhone SE", @"iPhone SE（第三代）", @"iPhone14,6", @"D49AP", 375, 667, 2),
            ABModel(@"iPhone 14", @"iPhone 14", @"iPhone14,7", @"D27AP", 390, 844, 3),
            ABModel(@"iPhone 14", @"iPhone 14 Plus", @"iPhone14,8", @"D28AP", 428, 926, 3),
            ABModel(@"iPhone 14", @"iPhone 14 Pro", @"iPhone15,2", @"D73AP", 393, 852, 3),
            ABModel(@"iPhone 14", @"iPhone 14 Pro Max", @"iPhone15,3", @"D74AP", 430, 932, 3),
            ABModel(@"iPhone 15", @"iPhone 15", @"iPhone15,4", @"D37AP", 393, 852, 3),
            ABModel(@"iPhone 15", @"iPhone 15 Plus", @"iPhone15,5", @"D38AP", 430, 932, 3),
            ABModel(@"iPhone 15", @"iPhone 15 Pro", @"iPhone16,1", @"D83AP", 393, 852, 3),
            ABModel(@"iPhone 15", @"iPhone 15 Pro Max", @"iPhone16,2", @"D84AP", 430, 932, 3),
            ABModel(@"iPhone 16", @"iPhone 16", @"iPhone17,3", @"D47AP", 393, 852, 3),
            ABModel(@"iPhone 16", @"iPhone 16 Plus", @"iPhone17,4", @"D48AP", 430, 932, 3),
            ABModel(@"iPhone 16", @"iPhone 16 Pro", @"iPhone17,1", @"D93AP", 402, 874, 3),
            ABModel(@"iPhone 16", @"iPhone 16 Pro Max", @"iPhone17,2", @"D94AP", 440, 956, 3),
            ABModel(@"iPhone 16", @"iPhone 16e", @"iPhone17,5", @"V59AP", 390, 844, 3),
            ABModel(@"iPhone 17", @"iPhone 17", @"iPhone18,3", @"V57AP", 393, 852, 3),
        ];
    });
    return models;
}

+ (NSArray<NSString *> *)generations {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (ABDeviceModel *model in [self allModels]) {
        if (![names containsObject:model.generation]) {
            [names addObject:model.generation];
        }
    }
    return names;
}

+ (NSArray<ABDeviceModel *> *)modelsInGeneration:(NSString *)generation {
    NSMutableArray<ABDeviceModel *> *models = [NSMutableArray array];
    for (ABDeviceModel *model in [self allModels]) {
        if ([model.generation isEqualToString:generation]) {
            [models addObject:model];
        }
    }
    return models;
}

+ (ABDeviceModel *)modelForIdentifier:(NSString *)identifier {
    for (ABDeviceModel *model in [self allModels]) {
        if ([model.identifier isEqualToString:identifier]) {
            return model;
        }
    }
    return [self defaultModel];
}

+ (ABDeviceModel *)defaultModel {
    return [self allModels].lastObject;
}

@end
