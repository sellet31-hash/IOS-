#import "ABIcon.h"

@interface UIImage (ABApplicationIcon)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleIdentifier format:(int)format scale:(CGFloat)scale;
@end

static NSCache<NSString *, id> *ABIconCache(void) {
    static NSCache<NSString *, id> *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [NSCache new];
        cache.countLimit = 300;
    });
    return cache;
}

static UIImage *ABIconFromBundle(NSURL *bundleURL) {
    if (bundleURL.path.length == 0) {
        return nil;
    }
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfURL:[bundleURL URLByAppendingPathComponent:@"Info.plist"]];
    id icons = info[@"CFBundleIcons"];
    NSArray *files = nil;
    if ([icons isKindOfClass:[NSDictionary class]]) {
        id primary = ((NSDictionary *)icons)[@"CFBundlePrimaryIcon"];
        if ([primary isKindOfClass:[NSDictionary class]]) {
            files = ((NSDictionary *)primary)[@"CFBundleIconFiles"];
        }
    }
    if (![files isKindOfClass:[NSArray class]]) {
        files = info[@"CFBundleIconFiles"];
    }
    if (![files isKindOfClass:[NSArray class]] || files.count == 0) {
        return nil;
    }
    NSString *base = [files.lastObject isKindOfClass:[NSString class]] ? files.lastObject : nil;
    if (base.length == 0) {
        return nil;
    }
    NSArray<NSString *> *names = @[
        [base stringByAppendingString:@"@3x.png"],
        [base stringByAppendingString:@"@2x.png"],
        [base stringByAppendingString:@".png"],
        base
    ];
    for (NSString *name in names) {
        NSData *data = [NSData dataWithContentsOfURL:[bundleURL URLByAppendingPathComponent:name]];
        UIImage *image = data.length ? [UIImage imageWithData:data] : nil;
        if (image) {
            return image;
        }
    }
    return nil;
}

UIColor *ABAccentColor(void) {
    return UIColor.systemBlueColor;
}

UIImage *ABAppIcon(NSString *bundleIdentifier) {
    return ABAppIconForBundle(bundleIdentifier, nil);
}

UIImage *ABAppIconForBundle(NSString *bundleIdentifier, NSURL *bundleURL) {
    if (bundleIdentifier.length == 0 && bundleURL.path.length == 0) {
        return nil;
    }
    NSString *key = bundleIdentifier.length ? bundleIdentifier : bundleURL.path;
    id cached = [ABIconCache() objectForKey:key];
    if (cached == [NSNull null]) {
        return nil;
    }
    if ([cached isKindOfClass:[UIImage class]]) {
        return cached;
    }
    UIImage *image = nil;
    if (bundleIdentifier.length && [UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)]) {
        image = [UIImage _applicationIconImageForBundleIdentifier:bundleIdentifier format:0 scale:0];
    }
    if (!image) {
        image = ABIconFromBundle(bundleURL);
    }
    [ABIconCache() setObject:image ?: [NSNull null] forKey:key];
    return image;
}
