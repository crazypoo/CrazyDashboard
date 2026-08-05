//
//  xp400Widget.swift
//  xp400Widget
//
//  Created by 邓杰豪 on 30/7/2026.
//

import WidgetKit
import SwiftUI
import CoreLocation

// MARK: -  数据模型
struct MotoStatusEntry: TimelineEntry {
    let date: Date
    let fuelLevel: Int
    let tripKm: Double
    let isConnected: Bool
    let parkedLat: Double
    let parkedLon: Double
    let address: String
    let lastUpdateTime: Date
}

// MARK: - 数据提供者
struct MotoWidgetProvider: TimelineProvider {
    
    // 🚨 保持与主 App 一致的 App Group ID
    let appGroupID = "group.com.yd.PTSpeed.xp400"
    
    func placeholder(in context: Context) -> MotoStatusEntry {
        MotoStatusEntry(date: Date(), fuelLevel: 0, tripKm: 0, isConnected: false, parkedLat: 0, parkedLon: 0, address: "XXXX", lastUpdateTime: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (MotoStatusEntry) -> ()) {
        let entry = readDataFromSharedDefaults()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        // 获取实时数据
        let entry = readDataFromSharedDefaults()
        // 因为我们的数据是由主 App 主动推送刷新的 (reloadTimelines)，所以这里设为 .never (永不自动过期)
        let timeline = Timeline(entries: [entry], policy: .never)
        completion(timeline)
    }
    
    /// 从共享沙盒读取主 App 写进来的数据
    private func readDataFromSharedDefaults() -> MotoStatusEntry {
        let defaults = UserDefaults(suiteName: appGroupID)
        return MotoStatusEntry(
            date: Date(),
            fuelLevel: defaults?.integer(forKey: "widget_fuelLevel") ?? 0,
            tripKm: defaults?.double(forKey: "widget_tripKm") ?? 0.0,
            isConnected: defaults?.bool(forKey: "widget_isConnected") ?? false,
            parkedLat: defaults?.double(forKey: "widget_parkedLat") ?? 0.0,
            parkedLon: defaults?.double(forKey: "widget_parkedLon") ?? 0.0,
            address: defaults?.string(forKey: "widget_parkedAddress") ?? "暂无停车位置记录",
            lastUpdateTime: Date(timeIntervalSince1970: defaults?.double(forKey: "widget_lastUpdateTime") ?? 0)
        )
    }
}

// MARK: - 视觉呈现 (SwiftUI)
struct MotoWidgetEntryView : View {
    var entry: MotoWidgetProvider.Entry
    let mainColor = Color(red: 0.2, green: 0.6, blue: 1.0)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            
            // --- 顶部栏：状态与时间 ---
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: entry.isConnected ? "wave.3.right.circle.fill" : "wave.3.right.circle")
                        .foregroundColor(entry.isConnected ? .green : .gray)
                        .font(.title3)
                    Text(entry.isConnected ? "机车已连接" : "机车已断开")
                        .font(.headline)
                        .foregroundColor(entry.isConnected ? .green : .gray)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("同步时间")
                        .font(.caption2)
                        .foregroundColor(.gray)
                    Text(entry.lastUpdateTime, style: .time)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
            }
            
            Divider().background(Color.gray.opacity(0.3))
            
            // --- 数据模块区 ---
            HStack(spacing: 20) {
                // 油量卡片
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "fuelpump.fill")
                            .foregroundColor(mainColor)
                        Text("当前油量")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    Text("\(entry.fuelLevel)%")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // 里程卡片
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "flag.checkered")
                            .foregroundColor(mainColor)
                        Text("小计里程")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    Text(String(format: "%.1f", entry.tripKm))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.white) +
                    Text(" km")
                        .font(.headline)
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 8)
            
            Divider().background(Color.gray.opacity(0.3))
            
            // --- 底部：高德反解析停车地址区 ---
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "parkingsign.circle.fill")
                        .foregroundColor(.orange)
                        .font(.title3)
                    Text("最后停车位置")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                
                // 🌟 高德全称地址文字
                Text(entry.address)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .lineLimit(2) // 允许换行显示长地址
                    .fixedSize(horizontal: false, vertical: true)
                
                // 经纬度补充信息
                if entry.parkedLat != 0.0 {
                    HStack {
                        Image(systemName: "location.fill")
                        Text(String(format: "Lat: %.5f  Lon: %.5f", entry.parkedLat, entry.parkedLon))
                    }
                    .font(.caption)
                    .foregroundColor(mainColor)
                }
            }
            
            Spacer(minLength: 0)
        }
        .padding()
        .containerBackground(Color(white: 0.1), for: .widget) // 深色科技风背景
    }
}

// MARK: - 小组件注册入口
struct XP400Widget: Widget {
    // 这个 ID 必须和主 App 调用 reloadTimelines 时的 ID 绝对一致！
    let kind: String = "XP400Widget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MotoWidgetProvider()) { entry in
            MotoWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Moto simple info")
        .description("Can check fule,trip and last position")
        .supportedFamilies([.systemLarge]) // 限制只支持中号尺寸，最适合这种排版
    }
}

struct MotoNaviLiveActivity: Widget {
    // 我们 App 的主色调
    let mainThemeColor = Color(red: 0.2, green: 0.6, blue: 1.0)
    
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MotoNaviAttributes.self) { context in
            // MARK: - 1. 锁屏界面的卡片视图 (Lock Screen)
            VStack(alignment: .leading, spacing: 16) {
                // 顶部：目的地与到达时间
                HStack {
                    Image(systemName: "flag.checkered")
                        .foregroundColor(mainThemeColor)
                    Text(context.attributes.destinationName)
                        .font(.headline)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    VStack(alignment: .trailing) {
                        Text("预计抵达")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text(context.state.estimatedArrivalTime, style: .time)
                            .font(.headline)
                            .foregroundColor(.green)
                    }
                }
                
                // 中部：剩余公里数
                HStack(alignment: .lastTextBaseline) {
                    Text(String(format: "%.1f", context.state.remainingDistanceKm))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("km")
                        .font(.title3)
                        .foregroundColor(.gray)
                }
                
                // 底部：进度条
                VStack(spacing: 6) {
                    ProgressView(value: context.state.progress)
                        .progressViewStyle(LinearProgressViewStyle(tint: mainThemeColor))
                        .scaleEffect(x: 1, y: 1.5, anchor: .center) // 让进度条稍微粗一点
                    
                    HStack {
                        Text("起点")
                            .font(.caption2)
                            .foregroundColor(.gray)
                        Spacer()
                        Text("\(Int(context.state.progress * 100))%")
                            .font(.caption2)
                            .foregroundColor(mainThemeColor)
                            .fontWeight(.bold)
                    }
                }
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.8))
            
        } dynamicIsland: { context in
            // MARK: - 2. 灵动岛视图 (Dynamic Island)
            DynamicIsland {
                // 展开时的视图
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading) {
                        Text("剩余")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text(String(format: "%.1f km", context.state.remainingDistanceKm))
                            .font(.headline)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing) {
                        Text("ETA")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text(context.state.estimatedArrivalTime, style: .time)
                            .font(.headline)
                            .foregroundColor(.green)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(value: context.state.progress)
                        .progressViewStyle(LinearProgressViewStyle(tint: mainThemeColor))
                        .padding(.top, 8)
                }
            } compactLeading: {
                // 灵动岛收起时的左侧
                Image(systemName: "location.fill")
                    .foregroundColor(mainThemeColor)
            } compactTrailing: {
                // 灵动岛收起时的右侧 (直接显示剩余公里)
                Text(String(format: "%.1f", context.state.remainingDistanceKm))
                    .font(.caption)
                    .bold()
            } minimal: {
                Image(systemName: "location.fill")
                    .foregroundColor(mainThemeColor)
            }
        }
    }
}

struct AvatarImageView: View {
    let filename: String
    let appGroupID = "group.com.yd.PTSpeed.xp400"
    
    var body: some View {
        // 尝试从 App Group 中读取队友发来的自定义头像
        if !filename.isEmpty,
           let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?.appendingPathComponent(filename),
           let uiImage = UIImage(contentsOfFile: url.path) {
            
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                
        } else {
            // ✅ 完美回退：由于我们在 Xcode 里把 default_user_avatar 配置给了 Widget Target，这里可以直接读取！
            Image("placeholder")
                .resizable()
                .scaledToFill()
        }
    }
}

// 🌟 2. 锁屏展示卡片 UI
struct IntercomLiveActivityView: View {
    let context: ActivityViewContext<MotoIntercomAttributes>

    var body: some View {
        VStack(spacing: 12) {
            // 顶部信息 (保持不变)
            HStack {
                Text(context.attributes.channelName)
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Text(context.state.statusText)
                    .font(.subheadline)
                    .foregroundColor(context.state.isLocalTalking ? .green : .gray)
            }
            
            // 🌟 修复部分：移除 ScrollView，改为静态计算
            // 1. 我们限制最多只显示屏幕能装下的 4 个车友
            let displayPeers = Array(context.state.activePeers.prefix(4))
            // 2. 计算是否还有没显示出来的车友
            let overflowCount = context.state.activePeers.count - displayPeers.count
            
            // 🌟 直接使用 HStack 进行静态横向排列
            HStack(spacing: 16) {
                ForEach(displayPeers, id: \.peerID) { peer in
                    VStack(spacing: 4) {
                        AvatarImageView(filename: peer.avatarFileName)
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
                            // 🌟 核心动效：讲话时的发光和放大动画
                            .shadow(color: peer.isSpeaking ? Color.green : Color.clear, radius: peer.isSpeaking ? 10 : 0)
                            .scaleEffect(peer.isSpeaking ? 1.15 : 1.0)
                            .animation(.spring(response: 0.3, dampingFraction: 0.5), value: peer.isSpeaking)
                        
                        Text(peer.peerName)
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.8))
                            .lineLimit(1)
                            .frame(maxWidth: 50)
                    }
                }
                
                // 🌟 新增：如果车友数量超过了 4 个，显示一个溢出提示
                if overflowCount > 0 {
                    VStack(spacing: 4) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.15))
                                .frame(width: 44, height: 44)
                            Text("+\(overflowCount)")
                                .font(.subheadline.bold())
                                .foregroundColor(.white)
                        }
                        Text("更多")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.5))
                            .lineLimit(1)
                            .frame(maxWidth: 50)
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
        }
        .padding()
        .background(Color.black.opacity(0.85)) // 酷炫暗黑风
    }
}

struct MotoIntercomLiveActivity: Widget {
    
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MotoIntercomAttributes.self) { context in
            IntercomLiveActivityView(context: context)
        } dynamicIsland: { context in
            // 这里可以灵活配置灵动岛的三种形态 (Expanded, Compact, Minimal)
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Text("机车通讯").font(.caption) }
                DynamicIslandExpandedRegion(.center) {
                    HStack(spacing: 8) {
                        ForEach(context.state.activePeers.filter { $0.isSpeaking }, id: \.peerID) { peer in
                            AvatarImageView(filename: peer.avatarFileName)
                                .frame(width: 24, height: 24)
                                .clipShape(Circle())
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "mic")
            } compactTrailing: {
                Text(context.state.activePeers.contains(where: { $0.isSpeaking }) ? "🗣️" : "🤫")
            } minimal: {
                Image(systemName: "mic")
            }
        }
    }
}
