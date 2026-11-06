#import "ABTweakInstaller.h"

#import <spawn.h>
#import <signal.h>
#import <sys/wait.h>
#import <unistd.h>

NSString *const ABTweakInstallerDidChangeNotification = @"ABTweakInstallerDidChangeNotification";

extern char **environ;

static NSError *ABInstallError(NSString *message) {
    return [NSError errorWithDomain:@"ABTweakInstaller" code:1 userInfo:@{
        NSLocalizedDescriptionKey : message ?: @"没有安装伪装插件"
    }];
}

static NSString *ABBundleFile(NSString *type) {
    return [NSBundle.mainBundle pathForResource:@"DeviceSpoof" ofType:type];
}

static NSString *ABToolRoot(void) {
    NSFileManager *files = NSFileManager.defaultManager;
    if ([files isExecutableFileAtPath:@"/var/jb/usr/bin/sudo"] && [files isExecutableFileAtPath:@"/var/jb/usr/bin/bash"]) {
        return @"/var/jb/usr/bin";
    }
    if ([files isExecutableFileAtPath:@"/usr/bin/sudo"] && [files isExecutableFileAtPath:@"/bin/bash"]) {
        return @"/usr/bin";
    }
    return nil;
}

static BOOL ABFilesMatch(NSString *source, NSString *destination) {
    NSData *left = [NSData dataWithContentsOfFile:source];
    NSData *right = [NSData dataWithContentsOfFile:destination];
    return left.length > 0 && [left isEqualToData:right];
}

static NSArray<NSString *> *ABInjectDirectories(void) {
    NSFileManager *files = NSFileManager.defaultManager;
    BOOL rootless = [files fileExistsAtPath:@"/var/jb"];
    NSString *inject = rootless ? @"/var/jb/usr/lib/TweakInject" : @"/usr/lib/TweakInject";
    NSString *libraries = rootless ? @"/var/jb/Library/MobileSubstrate/DynamicLibraries" : @"/Library/MobileSubstrate/DynamicLibraries";
    if ([[libraries stringByResolvingSymlinksInPath] isEqualToString:[inject stringByResolvingSymlinksInPath]]) {
        return @[inject];
    }
    return @[inject, libraries];
}

static BOOL ABDirectoryReady(NSString *directory) {
    NSString *dylib = ABBundleFile(@"dylib");
    NSString *plist = ABBundleFile(@"plist");
    return ABFilesMatch(dylib, [directory stringByAppendingPathComponent:@"DeviceSpoof.dylib"])
        && ABFilesMatch(plist, [directory stringByAppendingPathComponent:@"DeviceSpoof.plist"]);
}

static BOOL ABCopyIntoDirectory(NSString *directory, NSError **error) {
    NSFileManager *files = NSFileManager.defaultManager;
    if (![files createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:error]) {
        return NO;
    }
    for (NSString *type in @[@"dylib", @"plist"]) {
        NSString *source = ABBundleFile(type);
        NSString *destination = [directory stringByAppendingPathComponent:[@"DeviceSpoof." stringByAppendingString:type]];
        if (ABFilesMatch(source, destination)) {
            continue;
        }
        [files removeItemAtPath:destination error:nil];
        if (![files copyItemAtPath:source toPath:destination error:error]) {
            return NO;
        }
    }
    return YES;
}

static int ABRunSudo(NSString *directory, NSString *password, NSString **failure) {
    NSString *root = ABToolRoot();
    if (root.length == 0) {
        if (failure) {
            *failure = @"没有找到 sudo";
        }
        return -1;
    }
    NSString *sudo = [root stringByAppendingPathComponent:@"sudo"];
    NSString *bash = [root stringByAppendingPathComponent:@"bash"];
    if ([root isEqualToString:@"/usr/bin"]) {
        bash = @"/bin/bash";
    }
    NSString *script = @"set -eu\n"
                       @"dir=$1\n"
                       @"dylib=$2\n"
                       @"plist=$3\n"
                       @"bin=$4\n"
                       @"\"$bin/mkdir\" -p \"$dir\"\n"
                       @"\"$bin/cp\" -f \"$dylib\" \"$dir/DeviceSpoof.dylib\"\n"
                       @"\"$bin/cp\" -f \"$plist\" \"$dir/DeviceSpoof.plist\"\n"
                       @"\"$bin/chmod\" 755 \"$dir/DeviceSpoof.dylib\"\n"
                       @"\"$bin/chmod\" 644 \"$dir/DeviceSpoof.plist\"\n";
    NSArray<NSString *> *argv = @[
        sudo, @"-S", @"-p", @"", @"--", bash, @"-c", script, @"embed",
        directory, ABBundleFile(@"dylib") ?: @"", ABBundleFile(@"plist") ?: @"", root
    ];
    char **cargv = calloc(argv.count + 1, sizeof(char *));
    for (NSUInteger index = 0; index < argv.count; index++) {
        cargv[index] = (char *)argv[index].UTF8String;
    }

    int inputPipe[2] = {-1, -1};
    int outputPipe[2] = {-1, -1};
    if (pipe(inputPipe) != 0 || pipe(outputPipe) != 0) {
        free(cargv);
        if (failure) {
            *failure = @"无法创建安装管道";
        }
        return -1;
    }
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, inputPipe[0], STDIN_FILENO);
    posix_spawn_file_actions_addclose(&actions, inputPipe[0]);
    posix_spawn_file_actions_addclose(&actions, inputPipe[1]);
    posix_spawn_file_actions_adddup2(&actions, outputPipe[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, outputPipe[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&actions, outputPipe[0]);
    posix_spawn_file_actions_addclose(&actions, outputPipe[1]);

    pid_t pid = 0;
    int spawned = posix_spawn(&pid, sudo.UTF8String, &actions, NULL, cargv, environ);
    posix_spawn_file_actions_destroy(&actions);
    close(inputPipe[0]);
    close(outputPipe[1]);
    if (spawned != 0) {
        close(inputPipe[1]);
        close(outputPipe[0]);
        free(cargv);
        if (failure) {
            *failure = @"无法启动 sudo";
        }
        return -1;
    }

    NSData *secret = [[(password ?: @"") stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
    if (secret.length) {
        write(inputPipe[1], secret.bytes, secret.length);
    }
    close(inputPipe[1]);

    dispatch_semaphore_t finished = dispatch_semaphore_create(0);
    __block int status = -1;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        waitpid(pid, &status, 0);
        dispatch_semaphore_signal(finished);
    });
    if (dispatch_semaphore_wait(finished, dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC)) != 0) {
        kill(pid, SIGKILL);
        waitpid(pid, &status, 0);
        close(outputPipe[0]);
        free(cargv);
        if (failure) {
            *failure = @"安装超时";
        }
        return -1;
    }

    NSMutableData *output = [NSMutableData data];
    char buffer[512];
    ssize_t count = 0;
    while ((count = read(outputPipe[0], buffer, sizeof(buffer))) > 0) {
        [output appendBytes:buffer length:(NSUInteger)count];
    }
    close(outputPipe[0]);
    free(cargv);
    int code = WIFEXITED(status) ? WEXITSTATUS(status) : -1;
    if (code != 0 && failure) {
        NSString *text = [[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding];
        if (text.length == 0 || [text localizedCaseInsensitiveContainsString:@"password"] || [text localizedCaseInsensitiveContainsString:@"sorry"]) {
            *failure = @"密码不正确";
        } else {
            *failure = text;
        }
    }
    return code;
}

@implementation ABTweakInstaller

+ (BOOL)isInstalled {
    if (ABBundleFile(@"dylib").length == 0 || ABBundleFile(@"plist").length == 0) {
        return NO;
    }
    for (NSString *directory in ABInjectDirectories()) {
        if (!ABDirectoryReady(directory)) {
            return NO;
        }
    }
    return ABInjectDirectories().count > 0;
}

+ (NSString *)statusText {
    if (ABBundleFile(@"dylib").length == 0) {
        return @"安装包里没有插件";
    }
    return [self isInstalled] ? @"已写入注入目录" : @"未安装，点此安装";
}

+ (BOOL)installWithPassword:(NSString *)password error:(NSError **)error {
    if (ABBundleFile(@"dylib").length == 0 || ABBundleFile(@"plist").length == 0) {
        if (error) {
            *error = ABInstallError(@"这个安装包里没有 DeviceSpoof。");
        }
        return NO;
    }
    if (![NSFileManager.defaultManager fileExistsAtPath:@"/var/jb"] && ![NSFileManager.defaultManager fileExistsAtPath:@"/Library/MobileSubstrate"]) {
        if (error) {
            *error = ABInstallError(@"没有找到 Dopamine 的 /var/jb。只安装应用备份时，虾皮不会加载伪装插件。");
        }
        return NO;
    }

    NSMutableArray<NSString *> *pending = [NSMutableArray array];
    for (NSString *directory in ABInjectDirectories()) {
        if (ABDirectoryReady(directory)) {
            continue;
        }
        if (!ABCopyIntoDirectory(directory, NULL)) {
            [pending addObject:directory];
        }
    }
    if (pending.count == 0) {
        return [self isInstalled];
    }
    if (password == nil) {
        if (error) {
            *error = ABInstallError(ABToolRoot() ? @"需要越狱密码才能写入注入目录。" : @"注入目录不可写，也没有找到 sudo。");
        }
        return NO;
    }
    for (NSString *directory in pending) {
        NSString *failure = nil;
        if (ABRunSudo(directory, password, &failure) != 0 || !ABDirectoryReady(directory)) {
            if (error) {
                *error = ABInstallError(failure ?: @"没有写入注入目录");
            }
            return NO;
        }
    }
    return [self isInstalled];
}

+ (void)presentInstallerFromViewController:(UIViewController *)controller userInitiated:(BOOL)userInitiated {
    if ([self isInstalled]) {
        if (userInitiated) {
            [self showOn:controller title:@"插件已安装" message:@"重新打开虾皮后，机型伪装才会生效。"];
        }
        return;
    }
    NSError *error = nil;
    if ([self installWithPassword:nil error:&error]) {
        [self notify];
        if (userInitiated) {
            [self showOn:controller title:@"插件已安装" message:@"重新打开虾皮后，机型伪装才会生效。"];
        }
        return;
    }
    BOOL needsPassword = [error.localizedDescription containsString:@"越狱密码"];
    if (!needsPassword || !controller) {
        if (userInitiated) {
            [self showOn:controller title:@"无法安装插件" message:error.localizedDescription];
        }
        return;
    }
    static BOOL triedDefaultPassword = NO;
    if (!triedDefaultPassword) {
        triedDefaultPassword = YES;
        __weak UIViewController *weakController = controller;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSError *autoError = nil;
            BOOL installed = [ABTweakInstaller installWithPassword:@"alpine" error:&autoError];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (installed) {
                    [ABTweakInstaller notify];
                    if (userInitiated) {
                        [ABTweakInstaller showOn:weakController title:@"插件已安装" message:@"重新打开虾皮后，机型伪装才会生效。"];
                    }
                    return;
                }
                [ABTweakInstaller promptForPasswordFromViewController:weakController];
            });
        });
        return;
    }
    [self promptForPasswordFromViewController:controller];
}

+ (void)promptForPasswordFromViewController:(UIViewController *)controller {
    if (!controller) {
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"安装伪装插件" message:@"把 DeviceSpoof 写入越狱注入目录。需要这台手机的越狱用户密码，没改过的话一般是 alpine。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.secureTextEntry = YES;
        textField.placeholder = @"密码";
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak UIViewController *weakController = controller;
    [alert addAction:[UIAlertAction actionWithTitle:@"安装" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSString *password = alert.textFields.firstObject.text ?: @"";
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSError *installError = nil;
            BOOL installed = [ABTweakInstaller installWithPassword:password error:&installError];
            dispatch_async(dispatch_get_main_queue(), ^{
                [ABTweakInstaller notify];
                UIViewController *presenter = weakController;
                if (!presenter) {
                    return;
                }
                [ABTweakInstaller showOn:presenter title:installed ? @"插件已安装" : @"没有安装" message:installed ? @"重新打开虾皮后，机型伪装才会生效。" : installError.localizedDescription];
            });
        });
    }]];
    [controller presentViewController:alert animated:YES completion:nil];
}

+ (void)notify {
    [[NSNotificationCenter defaultCenter] postNotificationName:ABTweakInstallerDidChangeNotification object:nil];
}

+ (void)showOn:(UIViewController *)controller title:(NSString *)title message:(NSString *)message {
    if (!controller) {
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [controller presentViewController:alert animated:YES completion:nil];
}

@end
