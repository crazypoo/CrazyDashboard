# 🏍️ Peugeot XP400 connector (机车全能战术终端)

Peugeot XP400 connector 是一款专为极客骑手打造的硬核 iOS 机车仪表盘与通讯助理。项目深度整合了局域网底层通讯、高精度导航引擎以及苹果最新的系统特性，致力于打破传统机车仪表的孤岛效应，提供车规级的骑行与车队社交体验。

## ✨ 核心特性 (Core Features)

### 1. 战术级车队对讲 (Tactical Intercom)
- **无网局域网组网**：基于 `MultipeerConnectivity` 构建，支持在无蜂窝网络的深山、隧道中实现车队自动发现与低延迟语音对讲。
- **智能免提声控 (VOX)**：深度定制 `AVFoundation` 音频引擎，支持硬件级防爆音裁剪与 RMS 音量检测，自动识别骑手语音并触发对讲。
- **动态车友状态流**：支持跨设备实时同步队友自定义头像、名字，并伴随全局广播在界面上呈现说话时的发光特效。

### 2. 专业级导航与雷达 (Pro Navigation & Radar)
- **高德地图深度接入**：基于 `AMapNaviKit`，支持骑行导航、路线偏好设置（躲避拥堵、不走高速）及实时天气联动。
- **双屏独立渲染**：完美适配 Apple CarPlay，手机主屏与车机屏幕双向数据同步，支持 CarPlay 独立地图实例渲染。
- **队友实时雷达**：巧妙融合定位引擎与局域网通道，在导航地图上实时绘制队友坐标，利用电子罗盘数据平滑旋转车头航向。

### 3. 系统级深度融合 (System Integration)
- **双轨 Live Activity & 灵动岛**：打破系统限制，同时并发监控“导航实时进度”与“车队对讲发音状态”，实现极客级的锁屏多任务交互。
- **全自动防盗保活**：拥有智能骑行省电模式与防盗保活模式，引擎熄火后自动触发位置快照，记录最终泊车坐标 (Smart Parking)。

## 🛠 技术架构与依赖 (Tech Stack & Dependencies)
- **核心语言与 UI**：Swift, UIKit, SwiftUI (用于 WidgetKit 扩展)
- **地图生态**：AMapNaviKit, AMapLocationKit, AMapSearchKit
- **硬件与传感器**：CoreBluetooth, CoreMotion, AVFoundation
- **基础依赖组件**：项目底层强依赖于高可用、模块化的自定义组件库 `ptools`。

## ⚙️ 编译与运行要求 (Requirements)
- **iOS 版本**：iOS 17+
- **必需配置**：
  - 请确保在 Xcode 的 `Signing & Capabilities` 中为主 App 和 Widget 扩展配置了相同的 **App Groups**。
  - 需要在 `Info.plist` 中开启后台音频、后台定位等 `Background Modes`。

## 👨‍💻 开发者 (Author)
**Jax Tsang**
