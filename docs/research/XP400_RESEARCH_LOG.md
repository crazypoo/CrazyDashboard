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
  - 67
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

## Build 67 仪表字段纠偏证据

| 字段 | 当前等级 | 代码行为 | 仍需的真实证据 |
| --- | --- | --- | --- |
| Data2 RTC | Confirmed in recorded samples | `B0 >> 2` 秒、`B1 >> 2` 分、`B2 >> 3` 时；非法时钟不发布为有效 Clock | 多固件跨分钟/跨小时连续采样 |
| Data2 Engine low bits | Confirmed in implementation | `B1 & 0x03`；高位不再作为背光、电瓶显示或边撑 | 启动、运行、熄火现场矩阵 |
| Data2 low bits | Unknown / raw only | 保存 `B0.low2`、`B2.low3`，相关业务字段为 `nil` | Backlight、Kickstand、Battery Display A/B/A |
| Control TCS Ready | Corrected in implementation | TCS Mode 从低半字节读取，Ready 从完整 byte3 bit7 读取 | 三种 TCS 模式和 Ready 的真车观察 |
| Control rolling counter | Confirmed as raw sequence | 保留原始 byte0，计算模 256 delta；暂不声明时间单位 | 长时间丢帧/重复/回卷统计 |
| ABS front wheel speed | Confirmed for sample | `03 10` 按 `0.01` 解码为 `7.84 km/h` | 多速度段与后轮/仪表对照 |
| ABS warning lamp | Unknown | `absWarningState = .unknown`，避免误报并保留 raw bytes | ABS 自检灯人工 Marker 与连续帧对照 |

本 Build 的结论是“纠正已知错误解释并保留研究证据”，不是对未知位做新的协议猜测。实现只修改外围解码、模型、Mock、开发者采样和测试，未改变 `PTBluetoothManager`、ELM327 或 YMOBD 传输核心。
