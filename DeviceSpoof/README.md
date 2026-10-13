# DeviceSpoof（台湾虾皮 → iPhone 11）

多巴胺 **rootless** 越狱插件：仅在 **台湾虾皮**（`com.beeasy.shopee.tw`）进程内，把 `MGCopyAnswer` 读到的机型改成 **iPhone 11**（`iPhone12,1` / `N104AP`）。不改屏幕，不改 `sysctl`。

与 TrollStore 的 **AppBackup** 无关，需通过 **Sileo / `.deb`** 安装。

## 安装

1. 设备已越狱（多巴胺），并安装 ElleKit / Substitute。
2. 将 CI 产物 `com.appbackup.devicespoof_*.deb` 传到手机，用 Sileo 或 `dpkg -i` 安装。
3. **Respring** 或强杀虾皮后重新打开。

## 开关（可选）

创建或编辑：

`/var/jb/Library/Preferences/com.appbackup.devicespoof.plist`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>enabled</key>
	<true/>
</dict>
</plist>
```

缺省文件时视为 **开启**。改为 `<false/>` 后 **Respring**，插件不再挂钩。

## Hook 范围

只挂钩 `MGCopyAnswer` 的三个字符串：

- `ProductType` → `iPhone12,1`
- `HardwareModel` / `HWModelStr` → `N104AP`

不挂钩 `UIScreen`、`sysctl`、`sysctlbyname`、`uname`。这些函数被内联改写后，虾皮会在启动或使用中闪退。

## 闪退排查

1. 覆盖安装 **1.0.4**，Respring，强杀虾皮后再打开。请确认 Sileo 里版本是 1.0.4，不要留着 1.0.2。
2. 1.0.3 及更早版本改过屏幕或 `sysctl`，容易闪退。
3. 若 1.0.4 仍闪退：把上面的 `enabled` 设为 `false` 并 Respring。若这样就不闪，说明是机型返回值触发了虾皮自己的校验；若这样仍闪，再用 Choicy 对虾皮禁用本插件。

## 限制

- **不修改** iOS 版本、IDFV、钥匙串、IDFA。
- 虾皮风控还可能使用网络、行为、账号等维度；本插件只改进程内读的硬件参数。
- 屏幕分辨率仍是真机。只改了型号字符串，虾皮若同时核对屏幕，仍可能认出是 iPhone X。

## 本地编译

需 macOS + Theos + iOS SDK，在 `DeviceSpoof` 目录：

```bash
make package FINALPACKAGE=1
```

产物在 `packages/*.deb`。

## Choicy

若与其它注入冲突，可在 Choicy 中仅对 `com.beeasy.shopee.tw` 启用 DeviceSpoof。
