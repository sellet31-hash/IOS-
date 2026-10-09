#import <UIKit/UIKit.h>
#import "ABModels.h"

NS_ASSUME_NONNULL_BEGIN

@interface ABBackupActions : NSObject
+ (void)backupApp:(ABAppInfo *)app fromViewController:(UIViewController *)controller completion:(dispatch_block_t)completion;
+ (void)confirmCleanApp:(ABAppInfo *)app fromViewController:(UIViewController *)controller completion:(dispatch_block_t)completion;
+ (void)confirmRestore:(ABBackupInfo *)backup fromViewController:(UIViewController *)controller sourceView:(nullable UIView *)sourceView completion:(dispatch_block_t)completion;
+ (void)renameBackup:(ABBackupInfo *)backup fromViewController:(UIViewController *)controller completion:(dispatch_block_t)completion;
+ (void)shareBackup:(ABBackupInfo *)backup fromViewController:(UIViewController *)controller sourceView:(nullable UIView *)sourceView;
+ (void)confirmDelete:(ABBackupInfo *)backup fromViewController:(UIViewController *)controller completion:(dispatch_block_t)completion;
@end

NS_ASSUME_NONNULL_END
