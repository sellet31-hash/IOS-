#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ABTweakInstallerDidChangeNotification;

@interface ABTweakInstaller : NSObject
+ (BOOL)isInstalled;
+ (NSString *)statusText;
+ (void)presentInstallerFromViewController:(UIViewController *)controller userInitiated:(BOOL)userInitiated;
@end

NS_ASSUME_NONNULL_END
