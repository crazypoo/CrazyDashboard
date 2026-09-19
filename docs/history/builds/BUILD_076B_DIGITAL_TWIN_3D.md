---
doc_id: CD-HISTORY-BUILD-076B-001
title: Build 76B Digital Twin 3D
type: history
status: draft
canonical: false
domain: build-076b
owner: Jax
created: 2026-09-20
last_reviewed: 2026-09-20
related_builds:
  - 76
supersedes: []
superseded_by: []
---

# Build 76B — XP400 Vehicle Digital Twin 3D

## 版本定位

Build 76B 在 Build 76A 的统一 `PTVehicleTwinSnapshot` 之上增加正式 3D 展示。3D 仍然是只读渲染层：它不读取 BLE/OBD 回调、不发送车辆指令，也不创建第二套遥测或回放解析链。

营销版本继续为 `2.0.8`，工程 Build 继续为 `76`；本文件记录的是 Build 76 的 3D 阶段，不自行递增版本号。

Build 76B keeps the ELM327 transport, YMOBD extension boundary, CoreBluetooth dashboard manager and standard OBD command behavior unchanged.

La fase 3D mantiene intactos el transporte ELM327, el límite de extensión YMOBD, el gestor CoreBluetooth del tablero y los comandos OBD estándar.

## B76-13 — Renderer 技术选择

正式 Renderer 选择 **SceneKit**：

- 工程已经使用 SceneKit/ARKit 相关能力，新增依赖最小；
- iOS 17+ 可直接使用，UIKit 页面接入成本低；
- 支持节点层级、独立 pivot、灯光材质、相机控制和低面数移动渲染；
- 不需要为了普通 3D Twin 引入 ARSession 或 RealityKit 的第二套运行时；
- RealityKit 保留为未来 AR/空间展示的候选，不作为本 Build 的正式 Renderer。

业务层只依赖 `PTVehicleTwinSnapshot` 和配置模型；SceneKit 只存在于 `PTXP400Twin3DView` 与资产工厂中。

## B76-14 — 3D Asset Pack

工程新增：

- `Global/VehicleTwin/Assets/XP400Twin3DAssets/manifest.json`
- `Global/VehicleTwin/Assets/XP400Twin3DAssets/preview.svg`
- `PTVehicleTwin3DAssetFactory` 的原创程序化低面数 XP400 / XP400 GT 资源
- `docs/history/builds/BUILD_076B_ASSET_IMPORT_GUIDE.md`

资产清单固定：

- `xp400.root`、`xp400.body`；
- 前后轮独立旋转 pivot；
- 头灯、刹车灯、左右转向灯独立节点；
- 边撑独立 pivot；
- RPM indicator 与 G-vector 辅助节点；
- 坐标约定为 `x=front, y=up, z=left`；
- 轮半径 0.34 m，最大三角形预算 2400，最大材质预算 8；
- 当前不引入外部纹理、网络下载或来源不明的车型图片。

当前 Build 76 页面固定选择 `PTVehicleTwinConfiguration.xp400`，使用 XP400 的配色和资源契约；`xp400_gt` 只作为未来素材替换的保留目录，不作为本次页面来源。3D 几何是项目内原创的低面数近似资源，不是 Peugeot 官方模型，也不声称具有照片级车型精度。后续如替换为用户自有或已授权 XP400 模型，必须保持 manifest 中的节点名、pivot、原点、比例和朝向。

## B76-15 / B76-16 — Renderer 与车辆状态映射

`PTXP400Twin3DView` 只接受 `PTVehicleTwinSnapshot`：

- Speed 驱动前后轮旋转；
- RPM 驱动 RPM 环和 HUD；
- Fuel / Voltage 驱动 HUD；
- TCS / ABS / Engine 映射到 HUD；
- 边撑、头灯、近光/远光、左右转向灯和危险灯映射到节点；
- 共享快照没有可靠刹车语义，因此刹车灯保持关闭，不用速度或减速度臆测；
- 当前没有可靠转向角数据，因此不伪造车把转向动画。

2D 与 3D 的状态来源统一经过 `PTVehicleTwinStateMapper`，页面仍通过 `PTVehicleTwinStore`/`PTVehicleTelemetryConsumerHub` 接收更新。Live、Mock 和后续 Replay 都沿用同一快照边界。

## B76-17 — Motion Mapping

已接入：

- Lean → 车身滚转；
- Pitch → 车身俯仰；
- longitudinal/lateral G → G-vector 辅助箭头；
- 没有可靠 Motion 数据时显示中性姿态，并按 freshness 降低辅助图层透明度。

不把缺失的 Motion 数据补成假角度，也不让 Motion 回调直接操作 SceneKit 节点。

## B76-18 — Camera System

提供六组相机预设：Front、Rear、Left、Right、Top、Follow。

- 停车或速度不可用时允许 SceneKit 的旋转/缩放交互；
- 禁止平移，避免车辆模型离开可视区域；
- 有新鲜速度且速度大于 1 km/h 时自动切换 Follow，并关闭用户相机控制，降低骑行干扰；
- 相机切换不改变车辆状态，也不触碰 BLE/OBD。

## B76-19 — 2D / 3D / Auto

全屏 `PTVehicleTwinViewController` 使用 `PTMotoBaseViewController`，提供：

- Auto：正常使用 3D，低电量/严重温度压力/渲染器不可用时安全回退 2D；
- 2D：强制使用 Build 76A 2D renderer；
- 3D：优先使用 3D，但同样服从系统安全回退门禁。

用户选择保存在 `UserDefaults`，切换只更换展示层，不重建连接、轮询或遥测会话。

## B76-20 — 性能与 Thermal 策略

已实施静态保护：

- 目标帧率上限 30 FPS；
- 关闭抗锯齿；
- 关闭持续无意义重绘，快照变化时刷新；
- 低电量模式或 serious/critical thermal state 自动回退 2D；
- 使用低面数程序化几何、少量材质和无外部纹理；
- 只读 HUD 与 SceneKit 节点同一更新事务内更新。

Time Profiler、Core Animation、Allocations、Energy Log 和真实 thermal 压力仍需真机执行；静态策略不等同于性能 Gate 已通过。

## B76-21 — Real XP400 Gate

代码已为以下现场验证保留统一输入和 stale 语义，但本轮尚未声称实车通过：

- Speed / RPM / Fuel / Voltage；
- TCS / ABS / Kickstand；
- Lean / Pitch；
- 头灯、远光、转向灯；
- BLE/OBD 断开后的 stale/unavailable；
- Live 与 Mock 的状态一致性。

刹车灯和转向角因为当前没有可靠共享语义，现场验证前不展示为已支持功能。

## B76-22 — Dual-Mode Regression

已加入 3D renderer boundary/manifest/performance policy 的纯 Swift XCTest，并通过通用 iOS `build-for-testing` 编译。待真实环境完成：

- 2D Live / 3D Live；
- 2D Mock / 3D Mock；
- 2D stale/disconnected / 3D stale/disconnected；
- 2D ↔ 3D 切换；
- Auto fallback；
- 真实 XP400 GT 和长时间性能/温度测试。

## 稳定核心与验证结论

本 Build 未修改：

- `Global/BLE/PTBluetoothManager.swift`
- `Global/OBD/Function/PTHiddenOBDConnector.swift`
- `Global/OBD/Function/PTOBDCommand.swift`

ELM327 仍是 OBD 底层，YMOBD 仍是 ELM327 扩展；未改动 YMOBD 初始化、握手、能力识别、特征订阅、命令顺序、时序和 fallback。

| 门禁 | 当前状态 |
| --- | --- |
| SceneKit 技术选型与工程编译 | ✅ |
| 3D manifest / preview / 节点契约 | ✅ |
| 3D renderer 与统一 Snapshot | ✅ |
| 2D / 3D / Auto 入口 | ✅ |
| 通用 iOS Debug build | ✅ |
| 通用 iOS build-for-testing | ✅ |
| Instruments 性能与 thermal | 待真机 |
| XP400/XP400 GT 实车 | 待实车 |
| Build 76 Final Gate | 待 B76A/B76B 现场证据 |
