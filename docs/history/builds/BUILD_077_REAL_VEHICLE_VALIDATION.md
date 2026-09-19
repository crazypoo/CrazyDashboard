---
doc_id: CD-HISTORY-BUILD-077-VALIDATION-001
title: Build 77 Real Vehicle Validation
type: history
status: draft
canonical: false
domain: build-077-real-vehicle-validation
owner: Jax
created: 2026-09-20
last_reviewed: 2026-09-20
related_builds:
  - 77
supersedes: []
superseded_by:
---

# Build 77 — XP400/XP400 GT 真车验证清单

本文件是现场验证记录模板。静态编译、Mock、包校验和离线 Replay 不能替代真实车辆证据。

## 设备信息

```text
iPhone / iOS：
App：PTSpeed 2.0.8 (Build 77)
车辆：XP400 / XP400 GT：
仪表固件：
ELM327/YMOBD 型号与固件：
测试日期与地点：
```

## A. 黑匣子采集

- [ ] 连接仪表和 ELM327/YMOBD 后开启 Black Box；确认没有发送额外车辆命令。
- [ ] 连续骑行或怠速超过 60 秒；记录滚动事件数量和 App 内存趋势。
- [ ] 通过 Dev 入口触发一次 Incident；记录触发时间、网络/蓝牙状态和 UI 状态。
- [ ] 等待后置窗口完成并导出 raw 与 redacted 两份 `.crazytrace`。
- [ ] 检查 `manifest.json`、`samples/`、`events/`、`diagnostics/summary.json` 和 legacy streams。
- [ ] 对比事件触发前 60 秒、触发 Marker 和事件后 30 秒的时间范围。

## B. 回放与 Digital Twin

- [ ] 在无车辆写入操作的情况下导入 `.crazytrace`。
- [ ] 2D 模式检查速度、RPM、燃油、电压、TCS/ABS、边撑、Lean/Pitch 和 fresh/stale 状态。
- [ ] 3D 模式检查相同字段、轮组、灯光、边撑、相机和低电量/thermal fallback。
- [ ] 暂停、继续、停止 Replay；确认停止后回到 Live 状态且没有残留回放计时器。
- [ ] 断开车辆后检查 Live stale/unavailable；重新连接后检查实时数据可以接管。

## C. 生命周期与性能

- [ ] 采集期间前台 → 后台 → 锁屏 → 前台。
- [ ] 采集期间蓝牙断开 → 重连；记录连接恢复时间和任何命令顺序变化。
- [ ] Replay 期间确认 BLE、ELM327、YMOBD 和 OTA 写入入口均未被调用。
- [ ] 使用 Instruments 记录内存、CPU、Energy、Core Animation、Thermal；至少覆盖 30 分钟。
- [ ] 生成 Release/TestFlight 包并重复 A/B；保存原始包、脱敏包、日志和 Instruments 结果。

## 结论

```text
结果：通过 / 有条件通过 / 失败
问题与复现步骤：
导出的 Trace 路径：
日志与 Instruments 路径：
是否允许把 B77-12 更新为 ✅：
```

