---
doc_id: CD-HISTORY-BUILD-076B-ASSET-001
title: Build 76B 3D Asset Import Guide
type: history
status: stable
canonical: false
domain: build-076b-assets
owner: Jax
created: 2026-09-20
last_reviewed: 2026-09-20
related_builds:
  - 76
supersedes: []
superseded_by: []
---

# Build 76B 3D Asset Import Guide

## 资源位置

3D 资源清单与预览位于：

`Global/VehicleTwin/Assets/XP400Twin3DAssets/`

当前目录包含：

- `manifest.json`：schema、模型名、坐标、节点、移动端预算和纹理来源；
- `preview.svg`：不依赖第三方素材的静态预览。

SceneKit 的实际低面数几何由：

`Global/VehicleTwin/PTVehicleTwin3DAsset.swift`

中的 `PTVehicleTwin3DAssetFactory` 程序化生成。这样工程不需要把来源不明的 `.usdz`、`.scn` 或网络纹理打进 App，也可以在 manifest 约束下保持可重复构建。

## 稳定节点契约

Renderer 只通过这些稳定名称获取节点：

```text
xp400.root
xp400.body
xp400.frontWheel.pivot
xp400.rearWheel.pivot
xp400.light.headlight
xp400.light.brake
xp400.light.indicator.left
xp400.light.indicator.right
xp400.kickstand.pivot
xp400.rpm.indicator
xp400.motion.gVector
```

前后轮、灯光和边撑不能合并成单一网格；它们必须保持独立节点或独立 pivot。坐标约定为 `x=front, y=up, z=left`，模型原点在车辆中部附近，轮半径统一为 0.34 m。

## 移动端预算

`manifest.json` 当前约束：

- 最大三角形数：2400；
- 最大材质数：8；
- 外部纹理：关闭；
- SceneKit 抗锯齿：关闭；
- renderer 目标帧率：30 FPS。

如果后续替换为正式授权模型，导入前必须复核：

1. 节点名、父子层级和 wheel/kickstand pivot；
2. 原点、朝向、单位和比例；
3. 三角形、材质、纹理尺寸和内存预算；
4. XP400 与 XP400 GT 是否仍能使用同一状态映射；
5. Mock、断连和低电量/thermal fallback；
6. 不携带任何车辆写入、刷写或控制逻辑。

## 工程接入

`XP400Twin3DAssets` 已作为 PTSpeed bundle resource 导入；`SceneKit.framework` 已加入主 App。`PTXP400Twin3DView` 是唯一的 SceneKit 展示层，`PTVehicleTwinViewController` 通过 `PTMotoBaseViewController` 承载页面。Renderer 不直接监听 BLE/OBD，也不直接修改连接状态。

验证命令：

```text
xcodebuild -workspace CrazyDashboard.xcworkspace -scheme PTSpeed -configuration Debug -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO
xcodebuild -workspace CrazyDashboard.xcworkspace -scheme PTSpeed -configuration Debug -destination 'generic/platform=iOS' build-for-testing CODE_SIGNING_ALLOWED=NO
```

静态构建和 manifest 契约测试不能替代真机渲染、Instruments 和真实 XP400 GT 视觉/语义验证。

## 来源与许可

当前资源是 CrazyDashboard 项目内原创的近似低面数几何，不包含 Peugeot 官方商标、官方模型或外部照片纹理。若后续接入用户自有或已授权素材，应在 manifest 的 source/provenance 中记录来源，并保持本导入契约不变。

