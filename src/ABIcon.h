#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

UIImage *_Nullable ABAppIcon(NSString *bundleIdentifier);
UIImage *_Nullable ABAppIconForBundle(NSString *bundleIdentifier, NSURL *_Nullable bundleURL);
UIColor *ABAccentColor(void);

NS_ASSUME_NONNULL_END
