---
doc_id: CD-RESEARCH-XP400-001
title: XP400 Research Log
type: research
status: active
canonical: true
domain: xp400-research
owner: Jax
created: 2026-09-15
last_reviewed: 2026-09-15
related_builds:
  - 49
  - 55
  - 60
  - 64
supersedes: []
superseded_by:
---

# XP400 研究日志

## 当前证据快照

| 主题 | 状态 | 说明 |
| --- | --- | --- |
| FEFB/TIO GATT、认证、Credits、分片 | Confirmed in implementation | 规范和纯逻辑测试已覆盖；真实固件兼容仍单独记录 |
| Data1～Data3、Control、ABS 原始值与不可用值 | Confirmed for recorded samples | 字段语义和跨固件差异仍需继续采样 |
| 配置颜色、单位、语言的 Data3 回读 | Inferred / partially confirmed | 已有代码和真车字段证据；每个仪表固件仍需 A/B 记录 |
| TCS、灯光、ABS 前轮速度和断开 Frame ID | Confirmed for BLE-OPT-009 evidence | 写入 Payload 的完整语义和可逆性仍不是正式产品能力 |
| ANCS 风格自有测试通道 | Implemented but limited | 不读取其他 App 通知，不替代系统 ANCS；第三方通知和多固件行为待验证 |
| 任意仪表/ECU 写入、开机画面、固件刷写 | Unknown / Dev only | 没有足够车型、Seed-Key、Bootloader 和回滚证据 |

## 记录要求

每次真车或抓包记录车辆型号、仪表固件、iOS、App Build、BLE 中心标识摘要、操作步骤、完整上下行 Hex、分片边界、UI 结果和文件位置。认证查找表、密钥和不必要的精确位置不得进入共享文档。

## 下一步

- 扩充多语言、单位、颜色配置的 A/B/A 证据。
- 对连接、断开、后台、重连和通知链路建立时间轴样本。
- 将未知帧先进入 Evidence/CAN/Replay，不直接进入 `PTFrameBuilder` 的正式调用。
- 真实证据确认后才更新 [`XP400_BLE_PROTOCOL.md`](../protocols/xp400/XP400_BLE_PROTOCOL.md) 的状态；旧协议规范保留在同一 canonical 文件，不另建 V2/V3 副本。

