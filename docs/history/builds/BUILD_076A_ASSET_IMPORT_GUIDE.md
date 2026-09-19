---
doc_id: CD-HISTORY-BUILD-076A-ASSET-001
title: Build 76A 2D Asset Import Guide
type: history
status: stable
canonical: false
domain: build-076a-assets
owner: Jax
created: 2026-09-19
last_reviewed: 2026-09-19
related_builds:
  - 76
supersedes: []
superseded_by: []
---

# Build 76A 2D Asset Import Guide

## 资源位置

资源包位于：

`Global/VehicleTwin/Assets/XP400Twin2DAssets/`

包含：

- `manifest.json`
- `xp400/` 与 `xp400_gt/` 两套透明 SVG 分层资源
- body、body mask、前后轮、头灯、刹车灯、左右转向灯、边撑、阴影和 preview

## 资产说明

当前资源是为 CrazyDashboard 制作的原创近似矢量轮廓，不是 Peugeot 官方 车型图片，也不声称是照片级精确模型。`manifest.json` 记录画布尺寸、provenance、部件名称、车轮中心、车身 pivot、边撑 pivot 和头灯锚点。若后续获得用户自有照片或授权素材，只需按相同文件名替换 SVG，并复核 anchor/pivot。

## 工程使用

Build 76A 已将整个 `XP400Twin2DAssets` 目录作为 PTSpeed 的 bundle resource 导入，构建产物中目录名保持为 `XP400Twin2DAssets`，因此 manifest、两套车型目录和 preview 可以随包交付。`PTXP400TwinView` 仍使用程序化 Core Animation 轮廓作为稳定 fallback；资源包不通过网络下载，也不会阻塞真实车辆遥测。

若后续把 SVG 替换为正式授权素材或接入 Asset Catalog，应：

1. 保留透明背景和独立动画部件。
2. 按 manifest 的 2048×1024 坐标核对车轮旋转中心。
3. 为 1x/2x/3x 或矢量 PDF/SVG 选择项目统一的 Asset Catalog 规范。
4. 替换后分别用 Mock、断连和真实 XP400 检查不可用状态、灯光和边撑，不要改变遥测映射代码。

## 许可证与来源

本目录内 SVG 为项目内原创近似素材；没有把来源不明的网络图片或 Peugeot 商标资源打包进 App。若后续使用官方公开图片作为参考，仍应只用于重新绘制或建模，并在 provenance 中记录授权/来源。
