---
doc_id: CD-PLANNING-BACKLOG-001
title: Backlog
type: planning
status: active
canonical: true
domain: backlog
owner: Jax
created: 2026-09-15
last_reviewed: 2026-09-15
related_builds: []
supersedes: []
superseded_by:
---

# 后续候选工作池

这里记录未进入当前 Build 的想法、验证缺口和技术债。它不是承诺清单；排期时先移动到 [`ACTIVE_WORK.md`](ACTIVE_WORK.md)，再补齐验收、隐私和回滚条件。

## P1：优先补齐真实验证

- `NAV-013`：自定义路线编辑的真实地图、自动规划和异常 GPX 验证。
- `RIDE-007`、`RIDE-009`、`RIDE-012`、`RIDE-013`：黑匣子、续航、防盗和安全通知的真实道路、后台、误报与恢复矩阵。
- `OBD-006`：只读 UDS 的真实车型 DID 证据、否定响应和多帧响应记录。
- `OBD-009`～`OBD-012`：CAN Capture 的多适配器、大文件、异常退出、历史恢复与离线回放验证。
- `OBD-014`、`OBD-015`：诊断中心和 CAN Lab 的完整构建、真实设备与 UX 验收。
- `PTT-007`、`PTT-009`、`SYS-004`、`SYS-005`、`SYS-006`、`SYS-008`：PTT/Live Activity、Watch、导航 Live Activity 和 CarPlay 的真实生命周期验证。

## P2：Build 67 候选

- 统一骑行速度采样：让 Trip、Widget、Watch、CarPlay 和 LiDAR 逐步消费统一速度快照，并为每个消费者保留 freshness/来源诊断。
- 行程与车辆档案绑定：让多车库的历史行程、保养、续航基线和 iCloud 冲突按车辆身份隔离。
- 研究资料中心：将脱敏 Evidence、CAN、BLE、OBD 和 CrazyTrace 统一提供分页查询与可追溯导出。
- 离线回放回归：扩充合法零值、截断、多帧、断线和混合 XP400 + YMOBD 的固定样本。

## P3：研究或 Dev 专属

- `DEV-006`：仪表配置/开机画面实验只接受已有真实协议证据，未知帧保持拒绝。
- `DEV-007`～`DEV-010`：真实 OTA、ECU 刷写、备份和完整性校验只有在 Bootloader、CRC、ACK、断点、恢复和电源方案均有证据后再排期。
- `OBD-007`、`OBD-008`、`IDEA-009`、`IDEA-010`：节点扫描、深度读取、协议证据晋级和固件状态机继续受 Dev 门禁约束。

## 暂不计划

- 不创建第二套 BLE、ELM327、YMOBD、UDS、CAN 或 Jieli 传输层。
- 不把研究日志、Mock 结果或静态编译结果当成真车协议确认。
- 不在普通用户入口暴露 SecurityAccess、CAN injection、未知写入或刷写。

