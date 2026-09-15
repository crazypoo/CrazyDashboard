---
doc_id: CD-RESEARCH-FIRMWARE-001
title: Firmware Research Log
type: research
status: active
canonical: true
domain: firmware-research
owner: Jax
created: 2026-09-15
last_reviewed: 2026-09-15
related_builds:
  - 57
  - 64
supersedes: []
superseded_by:
---

# 固件与开机画面研究日志

## 当前结论

- 社区资料显示，部分 PSA 产品的开机品牌/主题可能来自既有 calibration 或资源；这不能直接证明 XP400 GT 仪表可以使用同一方法。
- 当前工程已有 YMOBD/Jieli OTA 外围桥接和 Dev 前置状态机，但没有足够的 XP400 仪表 Bootloader、固件格式、CRC、ACK、断点和回滚证据。
- `backupOriginalFirmware`、固定成功校验或模拟流程不能被记录为真实备份/完整性成功。

## 安全实验边界

所有新发现先作为只读 Evidence、CAN/协议样本或 Replay 输入。未确认车型和固件之前，不发送未知写入、SecurityAccess、RoutineControl、固件下载或重启帧。真实测试必须使用开发者开关、稳定供电、原始备份、可恢复设备和明确停止条件。

## 待验证问题

- XP400 仪表是否存在可识别的 boot/GUI calibration 入口。
- 目标固件是否接受 Jieli/其他 OTA SDK 的模式切换。
- 断电、断连和失败时是否存在硬件/官方恢复路径。
- 修改语言或开机画面是否会影响车辆安全相关配置。

研究依据和旧实施计划见 [`YMOBD_JIELI_OTA_REFERENCE.md`](../protocols/obd/YMOBD_JIELI_OTA_REFERENCE.md) 以及已归档路线图；任何结论都必须绑定设备和原始证据，不能只引用社区视频或推测。

