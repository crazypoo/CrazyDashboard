---
doc_id: CD-HISTORY-BUILD-078-VALIDATION-001
title: Build 78 Real Data Validation
type: history
status: draft
canonical: false
domain: build-078-real-data-validation
owner: Jax
created: 2026-09-20
last_reviewed: 2026-09-20
related_builds:
  - 78
supersedes: []
superseded_by:
---

# Build 78 — XP400/XP400 GT 健康时间线真车验收清单

本文件是现场验证模板。静态编译、Mock、历史迁移和离线测试不能替代真实车辆证据。

## 设备信息

~~~text
iPhone / iOS：
App：PTSpeed 2.0.8 (Build 78)
车辆：XP400 / XP400 GT：
仪表固件：
ELM327/YMOBD 型号与固件：
测试日期与地点：
当前车库车辆 UUID / 自定义名称：
~~~

## A. 数据来源与身份

- [ ] 连接真实仪表后确认健康页使用当前车辆，不会写入另一辆车。
- [ ] 连接 ELM327/YMOBD 后确认诊断数据进入同一车辆 UUID；不改变 ELM327/YMOBD 初始化顺序。
- [ ] 记录一次真实电池、电压、里程和保养剩余里程；保存原始来源与时间。
- [ ] 记录一次真实诊断报告或 DTC 状态，并确认 confirmed/pending/permanent 分开显示。
- [ ] 结束一次真实行程，确认距离和结束里程只归属当前车辆。

## B. 健康时间线

- [ ] 从 Garage 打开 Vehicle Health；检查状态、来源、最近时间、电池、电压、里程、DTC 和保养摘要。
- [ ] 切换 Battery、Mileage、DTC 三个图表；确认图表只展示当前车辆。
- [ ] 用 Mock 数据生成 synthetic 点，确认页面显示来源为 Mock，且不会替换更高可信的真实历史。
- [ ] 切换车库车辆；确认摘要、图表和 JSON 导出全部切换到新车辆。
- [ ] 导出 JSON；确认文件可读、日期为 ISO 8601、没有其他车辆数据。

## C. 生命周期、存储与性能

- [ ] 首次安装、已有健康 JSON、损坏 JSON、旧数据迁移和无数据启动。
- [ ] iCloud 无网络、恢复网络、冲突和容器不可用；确认本地健康页面仍可读。
- [ ] 前台 → 后台 → 锁屏 → 前台；确认健康时间线不会启动额外车辆命令。
- [ ] 仪表断开 → 重连；确认健康页面显示历史/过期语义，不把旧值标作新鲜实时值。
- [ ] 连续运行至少 30 分钟，检查每车点数、内存、CPU、Energy 和 Thermal。
- [ ] 生成 Release/TestFlight 包并重复 A/B；保存健康 JSON、日志和 Instruments 结果。

## 结论

~~~text
结果：通过 / 有条件通过 / 失败
问题与复现步骤：
健康时间线 JSON 路径：
原始诊断/遥测证据路径：
日志与 Instruments 路径：
是否允许把 B78-10 更新为 ✅：
~~~

