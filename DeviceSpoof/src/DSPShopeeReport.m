#import "DSPShopeeReport.h"
#import "DSPProfile.h"

static NSArray<NSString *> *DSPFingerprintKeys(void) {
    return @[ @"devicefingerprint", @"deviceid", @"device_id", @"devid", @"dfp" ];
}

static NSArray<NSString *> *DSPModelKeys(void) {
    return @[ @"device_model", @"devicemodel", @"devices" ];
}

static NSArray<NSString *> *DSPOSVersionKeys(void) {
    return @[ @"os_version", @"osversion", @"api", @"systemversion", @"ios_version" ];
}

@implementation DSPShopeeReport

+ (NSString *)deviceFingerprintHex {
    return [DSPProfile shopeeDeviceFingerprintHex];
}

+ (NSString *)productTypeForReports {
    return [DSPProfile productType];
}

+ (BOOL)isDeviceFingerprintKey:(NSString *)key {
    if (key.length == 0) {
        return NO;
    }
    return [DSPFingerprintKeys() containsObject:key.lowercaseString];
}

+ (BOOL)isDeviceModelKey:(NSString *)key {
    if (key.length == 0) {
        return NO;
    }
    return [DSPModelKeys() containsObject:key.lowercaseString];
}

+ (BOOL)isOSVersionKey:(NSString *)key {
    if (key.length == 0) {
        return NO;
    }
    return [DSPOSVersionKeys() containsObject:key.lowercaseString];
}

+ (NSString *)osVersionForReports {
    return [DSPProfile spoofedOSVersion];
}

+ (id)rewritePayloadIfNeeded:(id)object {
    if (![DSPProfile isSpoofEnabled]) {
        return object;
    }
    return [self rewriteNode:object depth:0];
}

+ (id)rewriteNode:(id)node depth:(NSUInteger)depth {
    if (depth > 12 || !node || node == [NSNull null]) {
        return node;
    }

    if ([node isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *out = [NSMutableDictionary dictionaryWithCapacity:[(NSDictionary *)node count]];
        [(NSDictionary *)node enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
            NSString *keyString = [key isKindOfClass:[NSString class]] ? (NSString *)key : key.description;
            id child = [self rewriteNode:obj depth:depth + 1];
            if ([self isDeviceFingerprintKey:keyString]) {
                out[key] = [self deviceFingerprintHex];
            } else if ([self isDeviceModelKey:keyString]) {
                if ([child isKindOfClass:[NSString class]] && [(NSString *)child hasPrefix:@"iPhone"]) {
                    out[key] = [self productTypeForReports];
                } else {
                    out[key] = child;
                }
            } else if ([self isOSVersionKey:keyString]) {
                out[key] = [self osVersionForReports];
            } else {
                out[key] = child;
            }
        }];
        return out;
    }

    if ([node isKindOfClass:[NSArray class]]) {
        NSMutableArray *out = [NSMutableArray arrayWithCapacity:[(NSArray *)node count]];
        for (id item in (NSArray *)node) {
            [out addObject:[self rewriteNode:item depth:depth + 1] ?: [NSNull null]];
        }
        return out;
    }

    return node;
}

@end
