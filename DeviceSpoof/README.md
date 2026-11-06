# DeviceSpoof（台湾虾皮 → iPhone 17 / iOS 26.0 · 免刷机注册向）

仅在 **台湾虾皮** 进程内生效。目标：在不重刷 iOS 的前提下，尽量模拟 **「刷机后首次安装虾皮」** 时客户端会上报的安装实例 ID，而不是只改序列号。

## 1.2.28

机型不再写死 iPhone 17。应用备份 1.1.0 的「机型」页把选择写入 `/var/jb/Library/Preferences/com.appbackup.devicespoof.plist`，本插件下次启动时读取。没有选择时仍使用 iPhone 17（iPhone18,3）。

## 1.2.27

只改 `hw.machine` 过不了风控。抓包里同一台手机会被这些值认出来：32 位 `deviceId` / `deviceFingerprint`、`tag.devices`、`tag.api`、钥匙串里的旧设备项，以及 Cookie `SPC_F` / `SPC_DID`。1.2.27 在保持机型伪装和系统版本不从 `sysctl` 改写的前提下，轮换 IDFV、IDFA、序列号和这组指纹；首次安装模式下，旧的设备钥匙串读不到，设备 Cookie 换成新的 32 位 HEX。账号 Cookie 不动。

## 1.2.26

1.2.25 已经能在虾皮保持打开时让 `hw.machine` 返回 `iPhone18,3`。1.2.26 不改这条路径。去掉不再使用的内存扫描和空诊断字段；系统调用重入时改走原函数，不再返回失败。安装身份改存到虾皮自己的偏好目录，避免每次冷启动都换成新的设备 ID。上报字段里不再把名叫 `model` 或 `api` 的无关值改掉。

## 1.2.25

1.2.24 能把 `hw.machine` 改成 `iPhone18,3`，但虾皮随后退出。系统版本仍是这台手机的 16.1.1，1.2.25 不再从 `sysctl` 把系统版本改成 26.0，只改机型。

## 1.2.24

1.2.23 改写了虾皮自己的导入表，构造函数能跑完，但进程随后退出。1.2.24 不再改虾皮的内存页，只让 ElleKit 挂钩 `sysctlbyname`、`sysctl` 和 `uname`。钩不上就保持原函数，避免把进程打崩。

## 1.2.23

1.2.23 不改系统函数入口，只改虾皮镜像里的 `sysctlbyname` 导入。导入能改上，但虾皮进程随后退出，所以没有留在手机上。

## 1.2.22

1.2.22 试图去掉崩溃路径，但编译失败，没有装到手机上。

## 1.2.21

1.2.20 在虾皮启动时直接改系统函数入口，并且扫描整个数据段，打开虾皮会闪退。1.2.21 去掉这两处。插件仍然加载，但不再碰会把进程打崩的内存。

## 1.2.20

1.2.19 能被虾皮加载，但 `hookSysctl` 仍是 0：ElleKit 没改掉系统函数，函数表里也找不到可替换的指针。1.2.20 会改用进程里已经启用的 `MSHookFunction`，不行就直接改函数入口，并扫描整个数据段。

## 1.2.19

1.2.16 已经注入虾皮，但 `hookSysctl`、`hookUname`、`hookGestalt` 都是 0，系统函数没换掉，上报的仍是 `iPhone13,2`。标记写在沙盒 `Library/Caches`，不在 `/var/jb/tmp`，因为当时 `/var/jb` 不存在。

1.2.19 用 `dlsym` 挂钩真正的系统函数；ElleKit 没挂上时，改写虾皮自己的函数指针。过滤条件改回 `com.beeasy.shopee.tw`，这是这台手机上实际注入成功的条件。请用 Filza 安装 deb，不要手工覆盖 dylib。

## 1.2.17

1.2.16 已经装上，但重新打开虾皮后仍然没有 `lastload.plist`，所以插件没被注入。过滤条件只写了 `com.beeasy.shopee.tw`，ElleKit 没有把 dylib 载入进程。

1.2.17 改为随 UIKit 注入。只有进程名或 Bundle ID 里带 shopee 才启用伪装。只要有界面程序加载了插件，就会写 `/var/jb/tmp/devicespoof-loaded.txt`。

## 1.2.16

1.2.15 直接往 `TweakInject` 解包。这台手机上 dpkg 写不进那个路径，升级时还把原来的 dylib 删了，所以两个路径都变成空的。

1.2.16 先装进已经存在的 `DynamicLibraries`，装完再复制到 `/var/jb/usr/lib/TweakInject`。另外写入 `/var/jb/tmp/devicespoof-installed.txt`，用来确认包确实装上了。

## 1.2.15

ElleKit 只读取 `/var/jb/usr/lib/TweakInject`。1.2.11 之后文件被放进 `DynamicLibraries`，这个目录在这台手机上又没有链过去，所以虾皮进程里没有插件，Filza 也搜不到 `lastload.plist`。

1.2.15 把 dylib 和 plist 直接装进 `TweakInject`。安装前会先建好这个目录，避免 1.2.10 那种解包失败。

## 1.2.14

登录时间在变、机型一直是 iPhone 12，说明虾皮进程里没有这段挂钩。多巴胺的 ElleKit 只从 `/var/jb/usr/lib/TweakInject` 加载插件。1.2.10 安装时这个目录打不开，之后的包又只放进 `DynamicLibraries`，所以插件不在 ElleKit 的扫描目录里。以前能改机型，是当时这个符号链接还在。

1.2.14 在安装前把 `TweakInject` 重新链回 `DynamicLibraries`。装完打开一次虾皮，用 Filza 搜 `com.appbackup.devicespoof.lastload.plist`。有这个文件且 `version` 是 1.2.14、`bundle` 是 `com.beeasy.shopee.tw`，才算注入成功。

## 1.2.13

装置管理还是「Apple iPhone 12」，是因为虾皮自己的机型表用真机标识 `iPhone13,2` 查出「iPhone 12」。系统函数即使被换掉，这张表仍会返回旧名字；TweakInject 目录不存在时 ElleKit 也不会加载插件。

1.2.13 在查这张表时直接改成 iPhone 17，并把插件复制进 `/var/jb/usr/lib/TweakInject`，保证注入。上报 JSON 里单独的 `"iPhone 12"` 也会换成 `"iPhone 17"`。

装完后在 NewTerm 执行 `killall -9 Shopee`，再打开虾皮并重新登录。

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
