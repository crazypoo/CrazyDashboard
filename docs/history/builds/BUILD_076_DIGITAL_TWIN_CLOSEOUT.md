---
doc_id: CD-HISTORY-BUILD-076-CLOSEOUT-001
title: Build 76 Digital Twin Final Closeout
type: history
status: draft
canonical: false
domain: build-076-closeout
owner: Jax
created: 2026-09-20
last_reviewed: 2026-09-20
related_builds:
  - 76
supersedes: []
superseded_by: []
---

# Build 76 — Digital Twin 收尾记录

## 本次收尾修复

### 1. 统一使用 XP400 素材

2D 和 3D 页面当前都明确使用 `PTVehicleTwinConfiguration.xp400`。2D renderer 从 App bundle 的：

`XP400Twin2DAssets/xp400/`

加载 XP400 的 body、shadow、灯光、边撑和轮组素材，不再把 `xp400_gt` 作为当前页面素材来源。3D renderer 使用 XP400 配置和对应的 XP400 低面数材质配色；GT 目录保留为后续已授权素材替换的扩展位，但不参与当前 Build 76 页面。

### 2. 修复 2D 轮子轨迹

原实现把整个 wheel path 作为一个覆盖全屏的 `CAShapeLayer` 旋转，旋转中心等于视图中心，因此视觉上会出现轮子绕圈或“自转轨迹异常”。现在：

- 轮胎圆环保持静止；
- 轮辐放入独立 layer/image，并以各自轮心为 anchor point；
- XP400 全画布素材固定在原生 2:1 canvas 内，避免 `scaleAspectFit` 留白导致图片坐标与 layer anchor 错位；
- 旋转角使用 `speed × deltaTime ÷ wheelCircumference` 计算；
- 无效、过期或断开时停止累加，避免旧速度继续转动；
- XP400 PNG 资产和程序化 fallback 都使用同一轮心和同一角速度规则。

### 3. 改善 Digital Twin 入口点击

`PTXP400TwinCardView` 现在：

- 禁止 2D renderer 子视图抢占卡片点击；
- 增加明确的 `Open` 按钮，满足最小 44 pt 触控区域；
- 卡片和按钮都进入同一个 `PTVehicleTwinViewController`；
- 保留 VoiceOver 的按钮语义和状态值。

## 验证结果

| 项目 | 状态 |
| --- | --- |
| XP400 PNG 资源生成并随 App bundle 复制 | ✅ |
| 2D/3D 当前配置固定为 XP400 | ✅ |
| 2D wheel pivot 与时间积分修复 | ✅ |
| Card 子视图点击穿透与显式入口 | ✅ |
| 干净 DerivedData 通用 iOS Debug build | ✅ |
| 干净 DerivedData 通用 iOS build-for-testing | ✅ |
| 受保护 BLE/ELM327/YMOBD 核心零改动 | ✅ |
| iPhone 视觉点击与滚动冲突验证 | 待真机 |
| XP400/XP400 GT 实车语义与长时间性能 | 待实车/Instruments |

## 发布结论

Build 76 的代码范围已收口：2D、3D、Mock、stale/disconnected、模式切换、XP400 资源、入口点击和测试构建均已落地。Build 76 不应在没有真实 iPhone、XP400 和 Instruments 证据的情况下标记为“现场 Gate 全部通过”；现场验证只剩视觉、车辆语义、性能和温度证据，不再需要修改 BLE、ELM327、YMOBD 或标准 OBD 连接代码。
