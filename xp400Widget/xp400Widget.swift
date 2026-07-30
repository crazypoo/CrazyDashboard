//
//  xp400Widget.swift
//  xp400Widget
//
//  Created by 邓杰豪 on 30/7/2026.
//

import WidgetKit
import SwiftUI
import CoreLocation

// MARK: - 1. 数据模型
struct MotoStatusEntry: TimelineEntry {
    let date: Date
    let fuelLevel: Int
    let tripKm: Double
    let isConnected: Bool
    let parkedLat: Double
    let parkedLon: Double
    let address: String // 🌟 新增地址属性
    let lastUpdateTime: Date
}

// MARK: - 2. 数据提供者
struct MotoWidgetProvider: TimelineProvider {
    
    // 🚨 保持与主 App 一致的 App Group ID
    let appGroupID = "group.com.yd.PTSpeed.xp400"
    
    func placeholder(in context: Context) -> MotoStatusEntry {
        MotoStatusEntry(date: Date(), fuelLevel: 100, tripKm: 125.5, isConnected: false, parkedLat: 22.5833, parkedLon: 113.0833, address: "广东省江门市蓬江区建设二路", lastUpdateTime: Date())
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

// MARK: - 3. 视觉呈现 (SwiftUI)
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

// MARK: - 4. 小组件注册入口
struct XP400Widget: Widget {
    // 这个 ID 必须和主 App 调用 reloadTimelines 时的 ID 绝对一致！
    let kind: String = "XP400Widget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MotoWidgetProvider()) { entry in
            MotoWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("机车状态看板")
        .description("在桌面上快速查看机车油量、里程与停车位置。")
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
