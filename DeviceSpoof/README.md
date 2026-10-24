# DeviceSpoof（台湾虾皮 → iPhone 17 / iOS 26.0 · 免刷机注册向）

仅在 **台湾虾皮** 进程内生效。目标：在不重刷 iOS 的前提下，尽量模拟 **「刷机后首次安装虾皮」** 时客户端会上报的安装实例 ID，而不是只改序列号。

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
