# DeviceSpoof（台湾虾皮 → iPhone 11）

多巴胺 **rootless** 越狱插件：仅在 **台湾虾皮**（`com.beeasy.shopee.tw`）进程内，将硬件信息伪装为 **iPhone 11**（`iPhone12,1`，414×896 @2x）。

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

缺省文件时视为 **开启**。改为 `<false/>` 可关闭伪装（仍仅注入虾皮）。

## Hook 范围

- `MGCopyAnswer`：`ProductType`、`HardwareModel` / `HWModelStr`、`MarketingName`
- `sysctlbyname`：`hw.machine`、`hw.model`、`hw.product`
- `uname`：`machine`

不改 `UIScreen`。把 iPhone X 的 375×812@3x 改成 11 的 414×896@2x 会在启动时把 UIKit 打崩。

## 闪退排查

1. 覆盖安装 **1.0.3** 或更新版本，然后 respring，再强杀虾皮。
2. 1.0.2 及更早版本会 Hook 屏幕尺寸和 `sysctl`，打开虾皮会闪退。
3. 若仍闪退：在 Choicy 里只对 `com.beeasy.shopee.tw` 启用 DeviceSpoof。

## 限制

- **不修改** iOS 版本、IDFV、钥匙串、IDFA。
- 虾皮风控还可能使用网络、行为、账号等维度；本插件只改进程内读的硬件参数。
- 真机分辨率与 11 不一致时，部分 Web/原生混合页仍可能异常；已同步改主屏几何参数以降低不一致。

## 本地编译

需 macOS + Theos + iOS SDK，在 `DeviceSpoof` 目录：

```bash
make package FINALPACKAGE=1
```

产物在 `packages/*.deb`。

## Choicy

若与其它注入冲突，可在 Choicy 中仅对 `com.beeasy.shopee.tw` 启用 DeviceSpoof。
