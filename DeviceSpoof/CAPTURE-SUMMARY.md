# Frida 抓包结论 → DeviceSpoof 1.1.0

## 能确认（成功注册 / 启动路径）

| 字段 | 出现位置 | 说明 |
|------|----------|------|
| `deviceFingerprint` | RN/埋点 JSON `meta` | 与 `deviceId` 同值 |
| `deviceId` | 同上 | **32 位大写 HEX**（非 IDFV 带横线格式） |
| `device_id` | 另一路上报 JSON | 与上相同 |
| `device_model` / `tag.devices` | 上报 JSON | 机型字符串，如 `iPhone13,2` |
| `os_version` / `api` | 上报 | 系统版本 |
| `app_version` | 上报 | 如 `3.83.46` |
| `platform` / `os` / `uid` | 上报 | 平台枚举；注册前 `uid` 常为 0 |

示例结构（值已抽象）：

```json
{
  "meta": {
    "deviceFingerprint": "<32-HEX>",
    "deviceId": "<32-HEX>",
    "region": "TW"
  },
  "tag": { "devices": "iPhone13,2", "api": "16.1.1" }
}
```

```json
{
  "device_id": "<32-HEX>",
  "device_model": "iPhone13,2",
  "os_version": "16.1.1"
}
```

## 本次未稳定抓到

- `df.infra.shopee.tw` 明文 URL（Cronet/QUIC，Frida 易白屏）
- `blackbox` / 同盾字段名
- FB 授权后的 **account/register** 明文 body

## 风控含义（结合你之前的观察）

- **10～15 天冷却**：服务端对同一 **32-HEX 设备指纹** 计时；刷机/`regenerateFreshInstall` 换 ID 可不等冷却。
- **Frida 注入**：spawn/attach 均易白屏或崩溃，不宜再作为日常手段；插件应在 **JSON / UserDefaults** 层对齐字段。

## 1.1.0 插件对策

1. `storedDeviceFingerprint`：与 IDFV/InstallUUID 一起在 `regenerateFreshInstall` 时轮换。
2. Hook `NSJSONSerialization` + `NSUserDefaults`：改写 `deviceId` / `deviceFingerprint` / `device_id` / `device_model` / `devices`。
3. 保留 1.0.x：MGCopyAnswer、sysctl、IDFV、InstallUUID、钥匙串读拦截。

## 换「新设备」注册流程

1. 卸载台湾虾皮  
2. plist 设置 `regenerateFreshInstall` = true  
3. Respring → 安装 **DeviceSpoof ≥ 1.1.0** → 重装虾皮  
4. 新手机号 + 换 IP +（可选）新 FB  
