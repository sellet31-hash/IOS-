# DeviceSpoof（台湾虾皮 → iPhone 13）

多巴胺 **rootless** 越狱插件：仅在 **台湾虾皮**（`com.beeasy.shopee.tw`）进程内伪装硬件与 **IDFV**，用于配合「卸载重装虾皮」后重新注册。不改系统函数代码，不改屏幕。

固定值：

| 项目 | 值 |
|------|-----|
| 机型 | iPhone 13（`iPhone14,5` / `D17AP`） |
| 序列号 | `F3PF534FRQ7E` |
| 主板号 MLB | `F3PF534FRQ7EH7ABC` |
| IDFV | 首次注入时自动生成，写入 prefs；可手动换 |

## 推荐注册流程（设备上限）

1. **卸载**台湾虾皮（清沙盒 + 钥匙串里该 App 的项）。
2. Sileo 安装 / 更新 **DeviceSpoof 1.0.8+**，**Respring**。
3. **重新安装**虾皮（App Store 或原方式），**不要**先登录旧号。
4. 换 **新手机号**，尽量换 **网络/IP**，再注册。
5. 若仍提示设备上限：在 prefs 里设 `regenerateVendorId` 为 `true`，Respring，再卸载重装虾皮试一次。

插件**不能**解除服务端对已封禁手机号/IP 的限制；只能让虾皮进程内读到的指纹更像「另一台 13 + 新 IDFV」。

## 安装

1. 设备已越狱（多巴胺），并安装 ElleKit / Substitute。
2. 将 CI 产物 `com.appbackup.devicespoof_*.deb` 传到手机，用 Sileo 或 `dpkg -i` 安装。
3. **Respring** 后安装或打开虾皮。

## 配置文件

`/var/jb/Library/Preferences/com.appbackup.devicespoof.plist`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>enabled</key>
	<true/>
	<key>regenerateVendorId</key>
	<false/>
</dict>
</plist>
```

| 键 | 说明 |
|----|------|
| `enabled` | `false` 关闭伪装（需 Respring） |
| `vendorUUID` | 可选，固定 IDFV，如 `A1B2C3D4-E5F6-7890-ABCD-EF1234567890` |
| `storedVendorUUID` | 插件自动写入，一般不用手改 |
| `regenerateVendorId` | 设为 `true` 后 Respring，会生成新 IDFV 并写回 plist |

缺省 prefs 时：**开启**，并会在首次启动虾皮时 **自动生成** `storedVendorUUID`。

## Hook 范围

- `MGCopyAnswer`：`ProductType`、`HardwareModel`、`HWModelStr`、`SerialNumber`、`MLBSerialNumber`
- `sysctl` / `sysctlbyname` / `uname`：机型字符串（与 1.0.6 相同方式，只改虾皮进程内指针）
- `UIDevice identifierForVendor`：返回 prefs 里的 IDFV

不改屏幕、不改 IDFA、不改钥匙串、不改系统设置里的真序列号。

## 闪退排查

1. 确认 Sileo 版本 **1.0.8+**，Respring，强杀虾皮再开。
2. 仍闪：prefs 里 `enabled` = `false` 后 Respring；或 Choicy 对虾皮禁用 DeviceSpoof。

## 本地编译

```bash
make package FINALPACKAGE=1
```

产物在 `packages/*.deb`。
