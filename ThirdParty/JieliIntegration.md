# Jieli 集成边界

## 当前版本

- Jieli iOS OTA SDK：2.5.0
- 集成入口：`PTJieliSDKBridge`
- 实际协议实现：官方 `JL_OTALib` SDK

## 职责

`PTJieliSDKBridge` 只负责配置 SDK、转发启动/取消、翻译进度与事件回调，以及交接后的重连回调。RCSP、CRC、固件分块、认证和断点续传仍由 SDK 负责。

YMOBD 的 `AT+VERSION`、认证和固件服务属于 ELM327 Vendor Extension；Jieli OTA 属于 `PTYMOBDAdapterModeCoordinator` 管理的适配器维护模式。

## 禁止依赖

- 不依赖 XP400 仪表 BLE 会话。
- 不依赖 `PTBluetoothManager`。
- 不把 Jieli OTA 状态放入 `PTELM327State`。
- 不在 CrazyDashboard 内复制 RCSP、CRC、分块或恢复算法。

## 验证边界

静态编译和单元测试只能验证桥接契约与状态转换。真实 YMOBD OTA 仍必须在开发者安全开关开启、稳定电源、真实适配器和可回滚条件下验证。
