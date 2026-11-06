#import "DSPShopeeReport.h"
#import "DSPProfile.h"
#import <string.h>

static NSArray<NSString *> *DSPFingerprintKeys(void) {
    return @[ @"devicefingerprint", @"deviceid", @"device_id", @"devid", @"dfp" ];
}

static NSArray<NSString *> *DSPModelKeys(void) {
    return @[
        @"device_model", @"devicemodel", @"devices", @"machine", @"hardware_model",
        @"phone_model", @"model", @"platform_model", @"hw_machine", @"product_type"
    ];
}

static NSArray<NSString *> *DSPMarketingNameKeys(void) {
    return @[
        @"device_name", @"devicename", @"model_name", @"phone_name", @"device_model_name",
        @"display_model", @"client_model"
    ];
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

+ (BOOL)isMarketingNameKey:(NSString *)key {
    if (key.length == 0) {
        return NO;
    }
    return [DSPMarketingNameKeys() containsObject:key.lowercaseString];
}

+ (NSString *)marketingNameForReports {
    return [NSString stringWithFormat:@"Apple %@", [DSPProfile marketingName]];
}

+ (NSString *)rewriteModelStringIfNeeded:(NSString *)value {
    if (value.length == 0) {
        return value;
    }
    if ([value hasPrefix:@"iPhone"] || [value containsString:@"iPhone"]) {
        return [self productTypeForReports];
    }
    return value;
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

+ (NSString *)replaceHardwareTokensInString:(NSString *)value {
    if (value.length == 0 || ![DSPProfile isSpoofEnabled]) {
        return value;
    }
    NSString *result = value;
    const char *realMachineUTF8 = [DSPProfile realMachineUTF8];
    if (realMachineUTF8) {
        NSString *realMachine = [[NSString alloc] initWithBytes:realMachineUTF8
                                                           length:strlen(realMachineUTF8)
                                                         encoding:NSUTF8StringEncoding];
        if (realMachine.length > 0 && [result containsString:realMachine]) {
            result = [result stringByReplacingOccurrencesOfString:realMachine withString:[self productTypeForReports]];
        }
    }
    NSString *realName = [DSPProfile realMarketingName];
    if (realName.length > 0) {
        NSString *appleName = [@"Apple " stringByAppendingString:realName];
        NSString *spoofAppleName = [self marketingNameForReports];
        if ([result containsString:appleName]) {
            result = [result stringByReplacingOccurrencesOfString:appleName withString:spoofAppleName];
        }
        if ([result isEqualToString:realName]) {
            result = [DSPProfile marketingName];
        }
    }
    return result;
}

+ (NSData *)replaceHardwareTokensInData:(NSData *)data {
    if (data.length == 0 || ![DSPProfile isSpoofEnabled]) {
        return data;
    }
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (text.length == 0) {
        return data;
    }
    NSString *replaced = [self replaceHardwareTokensInString:text];
    if (replaced == text || [replaced isEqualToString:text]) {
        return data;
    }
    return [replaced dataUsingEncoding:NSUTF8StringEncoding] ?: data;
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
            NSString *keyString = nil;
            if ([key isKindOfClass:[NSString class]]) {
                keyString = (NSString *)key;
            } else if ([key respondsToSelector:@selector(description)]) {
                keyString = [(id)key description];
            } else {
                keyString = [NSString stringWithFormat:@"%@", key];
            }
            id child = [self rewriteNode:obj depth:depth + 1];
            if ([self isDeviceFingerprintKey:keyString]) {
                out[key] = [self deviceFingerprintHex];
            } else if ([self isMarketingNameKey:keyString]) {
                if ([child isKindOfClass:[NSString class]] && [(NSString *)child containsString:@"iPhone"]) {
                    out[key] = [self marketingNameForReports];
                } else {
                    out[key] = child;
                }
            } else if ([self isDeviceModelKey:keyString]) {
                if ([child isKindOfClass:[NSString class]]) {
                    out[key] = [self rewriteModelStringIfNeeded:(NSString *)child];
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

    if ([node isKindOfClass:[NSString class]]) {
        return [self replaceHardwareTokensInString:(NSString *)node];
    }

    return node;
}

@end
