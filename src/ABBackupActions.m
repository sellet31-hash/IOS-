#import "ABBackupActions.h"
#import "ABBackupEngine.h"
#import "ABProgressOverlay.h"

@implementation ABBackupActions

+ (void)presentAlert:(UIAlertController *)alert from:(UIViewController *)controller sourceView:(UIView *)sourceView {
    UIPopoverPresentationController *popover = alert.popoverPresentationController;
    if (popover) {
        UIView *anchor = sourceView ?: controller.view;
        popover.sourceView = anchor;
        popover.sourceRect = CGRectMake(CGRectGetMidX(anchor.bounds), CGRectGetMidY(anchor.bounds), 1, 1);
    }
    [controller presentViewController:alert animated:YES completion:nil];
}

+ (UIView *)hostViewForController:(UIViewController *)controller {
    return controller.view.window ?: controller.view;
}

+ (void)backupApp:(ABAppInfo *)app fromViewController:(UIViewController *)controller completion:(dispatch_block_t)completion {
    ABBackupEngine *engine = [ABBackupEngine sharedEngine];
    UIView *host = [self hostViewForController:controller];
    ABProgressOverlay *overlay = [ABProgressOverlay showInView:host title:@"正在备份" cancelHandler:^{
        [engine cancel];
    }];
    [engine backupApp:app options:[ABBackupOptions currentOptions] progress:^(NSString *message, double fraction, uint64_t bytesDone, uint64_t bytesTotal) {
        [overlay updateMessage:message fraction:fraction bytesDone:bytesDone bytesTotal:bytesTotal];
    } completion:^(NSURL *archiveURL, NSError *error) {
        [overlay dismiss];
        if (completion) {
            completion();
        }
        if (error.code == ABErrorCancelled && [error.domain isEqualToString:ABErrorDomain]) {
            return;
        }
        if (error) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"没有完成备份" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
            [self presentAlert:alert from:controller sourceView:nil];
            return;
        }
        UINotificationFeedbackGenerator *feedback = [UINotificationFeedbackGenerator new];
        [feedback notificationOccurred:UINotificationFeedbackTypeSuccess];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"备份已保存" message:@"文件在「文件」App 的「应用备份」里，文件夹名是 Backups。" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"分享" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            ABBackupInfo *info = [ABBackupInfo new];
            info.fileURL = archiveURL;
            info.displayName = app.displayName;
            [self shareBackup:info fromViewController:controller sourceView:controller.view];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
        [self presentAlert:alert from:controller sourceView:nil];
    }];
}

+ (void)confirmRestore:(ABBackupInfo *)backup fromViewController:(UIViewController *)controller sourceView:(UIView *)sourceView completion:(dispatch_block_t)completion {
    NSString *when = ABFormatDate(backup.createdAt);
    NSString *message = [NSString stringWithFormat:@"会先退出「%@」，再用 %@ 的备份覆盖它现在的数据。缓存会被清掉。此操作不能撤销。", backup.displayName, when.length ? when : @"这份"];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"恢复应用数据" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"恢复" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        [self restoreBackup:backup fromViewController:controller completion:completion];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentAlert:alert from:controller sourceView:sourceView];
}

+ (void)restoreBackup:(ABBackupInfo *)backup fromViewController:(UIViewController *)controller completion:(dispatch_block_t)completion {
    ABBackupEngine *engine = [ABBackupEngine sharedEngine];
    ABProgressOverlay *overlay = [ABProgressOverlay showInView:[self hostViewForController:controller] title:@"正在恢复" cancelHandler:^{
        [engine cancel];
    }];
    [engine restoreBackupAtURL:backup.fileURL bundleIdentifier:backup.bundleIdentifier progress:^(NSString *message, double fraction, uint64_t bytesDone, uint64_t bytesTotal) {
        [overlay updateMessage:message fraction:fraction bytesDone:bytesDone bytesTotal:bytesTotal];
    } completion:^(NSArray<NSString *> *warnings, NSError *error) {
        [overlay dismiss];
        if (completion) {
            completion();
        }
        if (error.code == ABErrorCancelled && [error.domain isEqualToString:ABErrorDomain]) {
            return;
        }
        if (error) {
            UINotificationFeedbackGenerator *feedback = [UINotificationFeedbackGenerator new];
            [feedback notificationOccurred:UINotificationFeedbackTypeError];
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"没有完成恢复" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
            [self presentAlert:alert from:controller sourceView:nil];
            return;
        }
        UINotificationFeedbackGenerator *feedback = [UINotificationFeedbackGenerator new];
        [feedback notificationOccurred:UINotificationFeedbackTypeSuccess];
        NSString *message = warnings.count > 0 ? [warnings componentsJoinedByString:@"\n"] : @"数据已写回当前的应用容器。";
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"恢复完成" message:message preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentAlert:alert from:controller sourceView:nil];
    }];
}

+ (void)shareBackup:(ABBackupInfo *)backup fromViewController:(UIViewController *)controller sourceView:(UIView *)sourceView {
    if (!backup.fileURL) {
        return;
    }
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[backup.fileURL] applicationActivities:nil];
    UIPopoverPresentationController *popover = activity.popoverPresentationController;
    if (popover) {
        UIView *anchor = sourceView ?: controller.view;
        popover.sourceView = anchor;
        popover.sourceRect = anchor.bounds;
    }
    [controller presentViewController:activity animated:YES completion:nil];
}

+ (void)confirmDelete:(ABBackupInfo *)backup fromViewController:(UIViewController *)controller completion:(dispatch_block_t)completion {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"删除备份" message:[NSString stringWithFormat:@"删除「%@」的这份备份文件？应用里的数据不会变。", backup.displayName] preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        [[NSFileManager defaultManager] removeItemAtURL:backup.fileURL error:nil];
        if (completion) {
            completion();
        }
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentAlert:alert from:controller sourceView:nil];
}

@end
