---
doc_id: CD-PLANNING-ACTIVE-001
title: Active Work
type: planning
status: active
canonical: true
domain: active-work
owner: Jax
created: 2026-09-15
last_reviewed: 2026-09-15
related_builds:
  - 66
  - 67
supersedes: []
superseded_by:
---

# 当前工作

快照日期：2026-09-15。当前工程版本为 `2.0.8 (Build 67)`。本文件只保留仍需要完成或验收的工作；已完成 Build 的完整实施正文进入 [`history/BUILD_HISTORY_2026.md`](../history/BUILD_HISTORY_2026.md) 或对应的验收记录。

## Build 66 收口：统一车速真实验证 🟨

代码和离线门禁已完成，以下项目仍需真实 iPhone、GPS、OBD 和 XP400 验证：

- GPS-only 前台道路测试，确认合法 `0 km/h`、弱信号和精度门禁。
- GPS → ELM327 OBD：连续两个有效新鲜样本后切换到 OBD。
- OBD → GPS：车速回传过期后及时回退，不保留旧速度。
- OBD → XP400：XP400 的两个新鲜样本接管；XP400 断开后回落到 OBD/GPS。
- 前后台、定位权限变化、低电量和弱 GPS 条件下的显示稳定性。
- 主仪表与 Peugeot 仪表没有 `0 → -- → speed` 异常跳变。
- Release 签名包、后台行为和版本门禁复核。

验收证据必须记录设备型号、iOS、App Build、适配器、车辆/道路条件、开始结束时间、来源切换、内存/电量和日志位置。完成后把 B66-13 从 `🟨` 更新为对应状态，并同步产品总纲与 Build History。

## Build 67 收口：XP400 仪表协议真实验证 🟨

代码、纯数据测试和外围安全边界已完成；以下项目仍需真实 iPhone、XP400 仪表和 Release 包验证：

- 三组日志 RTC 样例与实车时钟连续性，包括跨分钟和跨小时；
- Engine、Voltage、TCS Off/Mode1/Mode2 与 Ready 状态；
- ABS 自检灯开/关与前轮速度 `0x0310 → 7.84 km/h` 的现场对应关系；
- Backlight、Kickstand 和 Battery Display 的命名 Marker A/B 采样，不能把未知位直接升级为产品字段；
- 长时间 Counter `+5`、回卷、重复和丢帧诊断；
- CAN Lab、主仪表、导航、Widget、Watch、CarPlay 的回归；
- Debug/Release 构建、安装和版本门禁。

验收记录必须包括车辆型号、仪表固件、iOS、App Build、适配器、测试时间、完整原始 Hex、Marker、解析结果和失败/断连表现。完成后把产品总纲中的 B67-09 从 `🟨` 更新为对应状态，并同步 Build History、协议文档和研究日志。

## 不在当前工作中

- Build 68 尚未在仓库登记为正式工作包；新任务先写入 [`BACKLOG.md`](BACKLOG.md)，不要新建根目录计划。
- `PTBluetoothManager.swift`、`PTHiddenOBDConnector.swift` 和 `PTOBDCommand.swift` 仍是冻结核心；本文件不授权解冻。
- QWeather 现有可用链路不在本轮治理范围。

## 发布与回滚门

在真实验证未完成前，不把 Build 66 标记为完整发布通过。若速度回退出现异常，先关闭 `PTBuild66FeatureFlags.gpsSpeedFallbackEnabled` 或回滚外围 Resolver/Bridge；不得回滚或修改 BLE/ELM327 核心来掩盖问题。
