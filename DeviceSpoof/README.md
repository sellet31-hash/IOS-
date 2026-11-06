# DeviceSpoof（台湾虾皮 → iPhone 17 / iOS 26.0 · 免刷机注册向）

仅在 **台湾虾皮** 进程内生效。目标：在不重刷 iOS 的前提下，尽量模拟 **「刷机后首次安装虾皮」** 时客户端会上报的安装实例 ID，而不是只改序列号。

## 1.2.12

登录后装置管理仍显示「Apple iPhone 12」，是因为虾皮上报的还是真机标识 `iPhone13,2`，服务端照这个显示；同一条设备记录也只更新登录时间，不改已经记下的机型名。

1.2.12 会在挂钩之前先记下真机标识，再把上报字符串和请求体里的 `iPhone13,2` / `Apple iPhone 12` 换成 iPhone 17。同时把设备指纹轮换一次，让服务器记成一台新设备。屏幕尺寸改为 iPhone 17 的 393×852，而且不再在 `UIScreen` 回调里调用 `mainScreen`，避免以前那种递归崩溃。

装上后彻底划掉虾皮，退出账号再登录。列表里旧的 iPhone 12 可以还在，当前这台应变成 iPhone 17。

## 1.2.11

1.2.10 安装失败：`unable to open '/var/jb/usr/lib/TweakInject/DeviceSpoof.dylib.dpkg-new'`。包里同时放了 `DynamicLibraries` 和 `TweakInject` 两份，而这台手机上 `TweakInject` 不存在（多巴胺上它经常是一个还没建好的符号链接），dpkg 就解不开。

1.2.11 只安装到 `/var/jb/Library/MobileSubstrate/DynamicLibraries`。装完后如果 `TweakInject` 还不存在，postinst 会把它链接过去，不会再复制第二份。

## 1.2.10

1.2.9 能编译，但机型不会真正变。`dlsym("sysctlbyname")` / `dlsym("uname")` 在共享缓存里可能是另一个别名，`MSHookFunction` 钩在那个地址上，虾皮继续调用自己链接到的入口，读到的仍是 `iPhone13,2`。

1.2.10 改回最早能改成功的挂法：直接钩进程里的 `sysctlbyname`、`sysctl`、`uname`。`MGCopyAnswer` 仍用运行时地址挂钩，因为公开 SDK 没有这个符号，`%hookf` 会链接失败。

另外不再改 `kern.osversion`。那是内核构建号（如 `20B101`），写成 `26.0` 后整份设备信息会被丢掉，装置管理继续显示旧机型。`kern.osproductversion` 仍是 `26.0`。

装上后需要退出账号、卸载重装虾皮、再登录，装置管理才会换成新机型。

## 1.2.9

- 不再 `%hookf(MGCopyAnswer)`（公开 SDK 没有这个符号，链接失败，`make` 退出码 2）
- 打包脚本改为显式传入暂存目录
- CI 失败时把编译器最后几行打到 Actions 摘要

## 1.2.6

- 修复编译：`DSPBind` 类型顺序  

## 1.2.5

- **Filter 恢复仅 `Bundles`**（1.2.3 误加 `Executables` 会导致 ElleKit **整包不注入**）  
- 自检文件在 **虾皮沙盒** `Library/Caches/com.appbackup.devicespoof.lastload.plist`，或 `/var/jb/tmp/` 同名  

## 1.2.4

- **ElleKit `%hookf`**：全局 Hook `MGCopyAnswer` / `sysctl` / `uname`  
- JSON 补充 `device_name` 等 → `Apple iPhone 17`  

## 1.2.3

- 晚加载库（Cronet 等）自动 GOT rebind  
- 补充 `kern.osproductversion`、`NSProcessInfo` 系统版本  
- Filter 增加 `ShopeeTW` 可执行名  

**账号安全 → 装置管理** 显示的是**上次登录时服务器记录的机型**；装 1.2.4 后需 **退出账号 → 卸载重装虾皮 → 再登录**，列表才会更新，不会改历史那条「iPhone 12」。

**伪装只在台湾虾皮 App 内生效**，系统「设置 → 关于本机」仍是真机。

### 确认插件已注入（Filza）

1. 打开虾皮一次后，在 Filza 搜 **`com.appbackup.devicespoof.lastload.plist`**  
2. 常见位置：**虾皮数据容器** → `Library/Caches/`（不是系统根目录的 Caches）  
3. 或 **`/var/jb/tmp/com.appbackup.devicespoof.lastload.plist`**  
4. 若两处都没有：看下方「多巴胺 tweak 目录」  

### 多巴胺 tweak 目录（NewTerm）

```bash
ls /var/jb/Library/MobileSubstrate/DynamicLibraries/DeviceSpoof.*
ls /var/jb/usr/lib/TweakInject/DeviceSpoof.*
```

若只有前者没有后者，执行（ElleKit 官方 workaround）：

```bash
cp /var/jb/Library/MobileSubstrate/DynamicLibraries/DeviceSpoof.* /var/jb/usr/lib/TweakInject/
killall -9 com.beeasy.shopee.tw
```

## 1.2.0

| 硬件档 | `iPhone18,3`（iPhone 17）、`V57AP` |
| 系统档 | **iOS 26.0**（`UIDevice.systemVersion`、`ProductVersion`、上报 JSON `os_version`/`api`） |

## 1.1.0（基于 Frida 抓包）

抓包确认虾皮客户端主键是 **32 位 HEX** 的 `deviceId` / `deviceFingerprint` / `device_id`（三处同值），机型字段为 `device_model` / `devices`。详见 [CAPTURE-SUMMARY.md](./CAPTURE-SUMMARY.md)。

| 新增 | 作用 |
|------|------|
| `storedDeviceFingerprint` | 与 IDFV/InstallUUID 一并轮换 |
| `NSJSONSerialization` |  outgoing JSON 改写设备字段 |
| `NSUserDefaults` | 读缓存时返回 spoof 指纹/机型 |

Frida 对这台虾皮易白屏，**不要再依赖进程注入抓注册**；用插件 + 必要时 Reqable。

## 1.0.9 相对刷机多做了什么

刷机后序列号不变仍能注册 → 上限主键多半是 **安装实例 / 客户端持久化 ID**，不是硬件字符串。

| 层级 | 1.0.9 行为 |
|------|------------|
| 硬件档 | iPhone 13 + 固定序列号 / MLB（与 1.0.7 相同） |
| IDFV | `identifierForVendor` → prefs 里的 UUID |
| **安装实例 UUID** | `MGCopyAnswer`：`InstallUUID`、`InstallationUUID`、`SystemSessionUUID`、`BootSessionUUID` → 同一套 `storedInstallUUID` |
| **旧设备 token** | `simulateFreshInstall` 开启时，对钥匙串里名称像 device/fingerprint/install 的项 **假装不存在**，逼虾皮重新生成 |

插件 **不能** 重写整台 iOS 的数据分区，也 **不能** 伪造 Apple DeviceCheck 真 token。若 1.0.9 仍不过，需要抓注册接口再 Hook 上报 JSON（见下文）。

## 免刷机注册推荐流程

1. **卸载**台湾虾皮。
2. 编辑 `/var/jb/Library/Preferences/com.appbackup.devicespoof.plist`：

```xml
<key>enabled</key><true/>
<key>simulateFreshInstall</key><true/>
<key>regenerateFreshInstall</key><true/>
```

3. **Respring**（会写入新的 `storedVendorUUID` + `storedInstallUUID`，并清掉 regenerate 标志）。
4. 确认 Sileo 里 **DeviceSpoof ≥ 1.0.9**，再 **安装虾皮**。
5. **新手机号 + 换网络/IP** 再注册（插件改不了这两项）。

每次要「换一台新设备」再注册：重复 1–5，或只设 `regenerateFreshInstall` = true 后 Respring + 卸载重装虾皮。

## 配置键

| 键 | 说明 |
|----|------|
| `enabled` | 总开关 |
| `simulateFreshInstall` | 默认 true；模拟首次安装（InstallUUID + 钥匙串读拦截） |
| `regenerateFreshInstall` | true 一次 → 换新的 IDFV + InstallUUID + **deviceFingerprint** |
| `storedDeviceFingerprint` | **自动随机** 32 位 HEX，写入 plist 后持久化（一般不用管） |
| `deviceFingerprint` | 可选；仅当你要固定某一串时才填，不填则全程自动随机 |
| `regenerateVendorId` | 同 regenerateFreshInstall（兼容旧键） |
| `vendorUUID` / `installUUID` | 可选，手动固定 UUID |

## 仍失败时（第二阶段）

抓 **注册失败** 与 **刷机后成功** 各一次 HTTPS 请求体，对比 `device_id` / `install_id` / `fingerprint` 等字段名。下一版只对虾皮 **上报 JSON** 做替换，仍只在虾皮进程内、仍不刷机。

## 安装

Sileo 安装 deb → Respring。与 AppBackup 无关。
