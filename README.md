# 应用备份

这是一个给 iOS 15 用的 TrollStore 应用。它在手机上列出已安装的用户应用，把数据容器和 App Group 打成 `.abackup` 文件，之后可以按 Bundle ID 写回去。应用重装后容器 UUID 会变，恢复时会找现在的目录。

不需要 OpenSSH。备份和恢复都在手机上完成。

## 备份里有什么

- `Documents`
- `Library`，默认不含 `Library/Caches` 和 `Library/SplashBoard`
- 该应用的 App Group
- 不含 `tmp`，不含容器身份文件，不含钥匙串

钥匙串不在备份里。只靠文件恢复时，有些应用会要求重新登录。

## 编译

Windows 不能直接编出 IPA。下面两种方式都可以。

### GitHub Actions

把这个目录推到 GitHub，打开 Actions，运行 **Build TrollStore IPA**。完成后在 Artifacts 里下载 `AppBackup.ipa`。

### Mac 或 Linux 上的 Theos

```bash
export THEOS=~/theos
# 安装 Theos 后，把 iPhoneOS 16.5 SDK 放到 $THEOS/sdks
make stage FINALPACKAGE=1
```

产物是 `packages/AppBackup.ipa`。

## 安装

把 IPA 传到手机，用 TrollStore 安装。不要用轻松签、AltStore 或普通开发者签名。那些方式会丢掉 `entitlements.plist` 里的权限，应用就读不到其他应用的数据。

安装后打开「应用备份」。如果列表提示无法读取，说明当前安装方式仍然在沙盒里。

## 使用

1. 在「应用」里点一个应用。
2. 需要的话关掉「排除缓存」，或关掉「包含 App Group」。
3. 点「开始备份」。文件出现在「文件」App 的「应用备份 / Backups」。
4. 恢复前先安装同一个 Bundle ID 的应用，并打开一次。恢复会先退出它，再覆盖现在的数据目录。

备份文件可以分享到电脑上长期保存。

## 本地检查归档格式

`src/abtar.c` 是打包格式。在有 C 编译器的机器上：

```bash
cc -std=c11 -DABTAR_USTAR_MAX_SIZE=64 -Isrc -o test-out/test_abtar tests/test_abtar.c src/abtar.c
./test-out/test_abtar test-out
python tests/verify_tar.py test-out/sample.tar
```

`ABTAR_USTAR_MAX_SIZE=64` 只用于测试大文件的 PAX 头。正式编译不要加这个宏。
