#import "ABIcon.h"
#import <objc/message.h>

UIColor *ABAccentColor(void) {
    return [UIColor colorWithRed:31.0 / 255.0 green:75.0 / 255.0 blue:153.0 / 255.0 alpha:1];
}

UIImage *ABAppIcon(NSString *bundleIdentifier) {
    if (bundleIdentifier.length == 0) {
        return nil;
    }
    SEL selector = NSSelectorFromString(@"_applicationIconImageForBundleIdentifier:format:scale:");
    if (![UIImage respondsToSelector:selector]) {
        return nil;
    }
    typedef UIImage *(*ABIconFunction)(id, SEL, NSString *, int, CGFloat);
    ABIconFunction function = (ABIconFunction)objc_msgSend;
    CGFloat scale = UIScreen.mainScreen.scale;
    UIImage *image = function([UIImage class], selector, bundleIdentifier, 10, scale);
    if (!image) {
        image = function([UIImage class], selector, bundleIdentifier, 0, scale);
    }
    return image;
}
