---
doc_id: CD-HISTORY-BUILD-079-VALIDATION-001
title: Build 79 Real Data Validation
type: history
status: draft
canonical: false
domain: build-079-real-data-validation
owner: Jax
created: 2026-09-20
last_reviewed: 2026-09-20
related_builds:
  - 79
supersedes: []
superseded_by:
---

# Build 79 — XP400/XP400 GT 道路体验真车验收清单

静态编译、Mock、固定样本和回放测试不能替代真实手机、固定支架、GPS、Motion、XP400/XP400 GT 和 Release/TestFlight 证据。

## 设备信息

~~~text
iPhone / iOS：
App：PTSpeed 2.0.8 (Build 79)
车辆：XP400 / XP400 GT：
仪表固件：
BLE / ELM327 / YMOBD 型号与固件：
手机固定位置与方向：
测试日期、地点与天气：
车库车辆 UUID / 自定义名称：
~~~

## A. 采集门控

- [ ] 静止、未连接车辆、Motion 未启动时不会写入道路体验样本。
- [ ] 低于 3 km/h、GPS 精度大于 50 m、位置超过 15 秒时不会形成有效路段。
- [ ] 真实仪表/OBD 连接、断连、重连和轮询变化不改变 ELM327/YMOBD 初始化顺序或 BLE 行为。
- [ ] Mock/Replay 生成的数据标记为 synthetic，不会伪装成真实道路证据。

## B. 路面场景

- [ ] 平整道路：主要为 smooth/moderate，不能持续生成 severe。
- [ ] 连续颠簸：能形成 rough 或 repeated vibration，并按时间/距离合理分段。
- [ ] 单个坑洼候选：能形成 pothole candidate，但页面明确标注为候选而非确诊。
- [ ] 减速带：能形成 speed bump candidate，重复通过不会无限重复写入相同路段。
- [ ] 强冲击：Twin 页面短暂显示 Road Impact，Trace 记录事件位置 marker。
- [ ] 同一路段重复 Trip flush、前后台切换和重新打开页面不会重复计数。

## C. 校准与多车

- [ ] 每辆车停车后独立校准，切换车库车辆不会读取另一辆车的偏置。
- [ ] 行驶中或 Motion 未启动时点击校准会拒绝且不写入设置。
- [ ] 切换车辆后地图、摘要、事件和 JSON 分享只包含当前车辆。

## D. 回放、存储与性能

- [ ] CrazyTrace 录制包含既有 Motion/GPS/Telemetry；回放后道路事件位置和分类可重算。
- [ ] 首次安装、已有 JSON、损坏 JSON、iCloud 无网络、恢复网络和原子写入残留均可恢复。
- [ ] 180 天保留和每车 2,000 路段上限有效，空数据分享不会生成误导文件。
- [ ] 连续运行至少 30 分钟，记录内存、CPU、Energy、Thermal 和 Road Surface 通知频率。
- [ ] MapKit 页面在不同尺寸 iPhone 上滚动、缩放、分享和返回均正常。
- [ ] Debug、Release 和 TestFlight 包均不发送任何车辆写入、刷写或未知命令。

## 结论

~~~text
结果：通过 / 有条件通过 / 失败
问题与复现步骤：
道路体验 JSON 路径：
CrazyTrace / 原始遥测证据路径：
日志与 Instruments 路径：
是否允许把 B79-10 更新为 ✅：
~~~

