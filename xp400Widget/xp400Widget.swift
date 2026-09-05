//
//  xp400Widget.swift
//  xp400Widget
//
//  Created by 邓杰豪 on 30/7/2026.
//

import WidgetKit
import SwiftUI
import CoreLocation
import ActivityKit
import AppIntents
import AlarmKit

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
    let languageIdentifier: String?
}

// MARK: - 数据提供者
struct MotoWidgetProvider: TimelineProvider {
    
    // EN: Read the same shared container used by the main app.
    // ES: Lee el mismo contenedor compartido que utiliza la app principal.
    // 中文：读取主 App 使用的同一个共享容器。
    let appGroupID = PTWidgetDataKeys.appGroupID
    
    func placeholder(in context: Context) -> MotoStatusEntry {
        MotoStatusEntry(date: Date(), fuelLevel: 0, tripKm: 0, isConnected: false, parkedLat: 0, parkedLon: 0, address: "", lastUpdateTime: .distantPast, languageIdentifier: nil)
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
        let status = PTWidgetSharedStatus.read(from: defaults)
        return MotoStatusEntry(
            date: Date(),
            fuelLevel: status.fuelLevel,
            tripKm: status.tripKm,
            isConnected: status.isConnected,
            parkedLat: status.parkedLat,
            parkedLon: status.parkedLon,
            address: status.address,
            lastUpdateTime: status.lastUpdateTime,
            languageIdentifier: status.languageIdentifier
        )
    }
}

// MARK: - 视觉呈现 (SwiftUI)
struct MotoWidgetEntryView : View {
    var entry: MotoWidgetProvider.Entry
    let mainColor = Color(red: 0.2, green: 0.6, blue: 1.0)

    // EN: Resolve visible Widget labels using the language selected in the companion app.
    // ES: Resuelve las etiquetas visibles del Widget usando el idioma elegido en la app compañera.
    // 中文：根据主 App 选择的语言解析 Widget 的可见文案。
    private func localized(_ key: String) -> String {
        PTWidgetLocalized.string(key, languageIdentifier: entry.languageIdentifier)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            
            // --- 顶部栏：状态与时间 ---
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: entry.isConnected ? "wave.3.right.circle.fill" : "wave.3.right.circle")
                        .foregroundColor(entry.isConnected ? .green : .gray)
                        .font(.title3)
                    Text(localized(entry.isConnected ? "ride_connected" : "ride_disconnected"))
                        .font(.headline)
                        .foregroundColor(entry.isConnected ? .green : .gray)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text(localized("ride_last_sync"))
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
                        Text(localized("watch_assistant_fuel_level"))
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
                        Text(localized("casa_card_little_trip"))
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
                    Text(localized("ride_parking"))
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                
                // EN: Avoid showing a hard-coded language when no parking record exists.
                // ES: Evita mostrar un idioma fijo cuando no existe un registro de estacionamiento.
                // 中文：没有停车记录时不显示硬编码语言的占位文本。
                if entry.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(localized("ride_no_parking"))
                        .font(.body)
                        .foregroundColor(.gray)
                } else {
                    Text(entry.address)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                // 经纬度补充信息
                if entry.parkedLat.isFinite && entry.parkedLon.isFinite &&
                    (abs(entry.parkedLat) > 0.000001 || abs(entry.parkedLon) > 0.000001) {
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
    let appGroupID = PTWidgetDataKeys.appGroupID
    
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

// EN: AlarmKit countdown presentation stays visually consistent with the existing motorcycle activities.
// ES: La presentación de cuenta atrás de AlarmKit mantiene el estilo visual de las actividades existentes.
// 中文：AlarmKit 倒计时界面沿用现有摩托车 Live Activity 的视觉风格。
@available(iOS 26.0, *)
struct MotoAlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<PTMotoAlarmMetadata>.self) { context in
            MotoAlarmLockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.88))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(alarmTitle(context), systemImage: iconName(context))
                        .font(.caption)
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    alarmTimeView(context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        if isCountdown(context) {
                            Button(intent: PTPauseMotoAlarmIntent(alarmID: alarmID(context))) {
                                Image(systemName: "pause.circle")
                            }
                            .tint(.orange)
                        }
                        Button(intent: PTStopMotoAlarmIntent(alarmID: alarmID(context))) {
                            Image(systemName: "stop.circle")
                        }
                        .tint(.red)
                    }
                }
            } compactLeading: {
                Image(systemName: iconName(context))
                    .foregroundColor(.blue)
            } compactTrailing: {
                alarmTimeView(context)
            } minimal: {
                Image(systemName: iconName(context))
                    .foregroundColor(.blue)
            }
        }
    }

    private func alarmTitle(_ context: ActivityViewContext<AlarmAttributes<PTMotoAlarmMetadata>>) -> String {
        context.attributes.metadata?.title
            ?? String(localized: LocalizedStringResource("alarm_fallback_title", table: "Localizable"))
    }

    private func alarmID(_ context: ActivityViewContext<AlarmAttributes<PTMotoAlarmMetadata>>) -> UUID {
        context.attributes.metadata?.alarmID ?? context.state.alarmID
    }

    private func iconName(_ context: ActivityViewContext<AlarmAttributes<PTMotoAlarmMetadata>>) -> String {
        switch context.attributes.metadata?.kind {
        case .departure:
            return "flag.checkered"
        case .maintenance:
            return "wrench.and.screwdriver.fill"
        case .parking:
            return "parkingsign.circle.fill"
        case .rideBreak:
            return "cup.and.saucer.fill"
        case .none:
            return "motorcycle"
        }
    }

    private func isCountdown(_ context: ActivityViewContext<AlarmAttributes<PTMotoAlarmMetadata>>) -> Bool {
        switch context.state.mode {
        case .countdown, .paused:
            return true
        case .alert:
            return false
        @unknown default:
            return false
        }
    }

    @ViewBuilder
    private func alarmTimeView(_ context: ActivityViewContext<AlarmAttributes<PTMotoAlarmMetadata>>) -> some View {
        switch context.state.mode {
        case .countdown(let countdown):
            Text(timerInterval: countdown.startDate...countdown.fireDate, countsDown: true)
                .font(.headline.monospacedDigit())
                .foregroundColor(.green)
        case .paused(let paused):
            Text(remainingText(
                duration: paused.totalCountdownDuration - paused.previouslyElapsedDuration
            ))
            .font(.headline.monospacedDigit())
            .foregroundColor(.orange)
        case .alert(let alert):
            Text(String(format: "%02d:%02d", alert.time.hour, alert.time.minute))
                .font(.headline.monospacedDigit())
                .foregroundColor(.red)
        @unknown default:
            Text(LocalizedStringResource("alarm_fallback_title", table: "Localizable"))
                .font(.headline)
                .foregroundColor(.gray)
        }
    }

    private func remainingText(duration: TimeInterval) -> String {
        let seconds = max(Int(duration.rounded()), 0)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

@available(iOS 26.0, *)
private struct MotoAlarmLockScreenView: View {
    let context: ActivityViewContext<AlarmAttributes<PTMotoAlarmMetadata>>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(
                    context.attributes.metadata?.title
                        ?? String(localized: LocalizedStringResource("alarm_fallback_title", table: "Localizable")),
                    systemImage: iconName
                )
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(1)
                Spacer()
                Text(context.attributes.metadata?.vehicleName ?? "")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }

            switch context.state.mode {
            case .countdown(let countdown):
                Text(timerInterval: countdown.startDate...countdown.fireDate, countsDown: true)
                    .font(.system(size: 38, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundColor(.green)
                HStack {
                    Button(intent: PTPauseMotoAlarmIntent(alarmID: alarmID)) {
                        Label(
                            LocalizedStringResource("alarm_pause", table: "Localizable"),
                            systemImage: "pause.circle"
                        )
                    }
                    .tint(.orange)
                    Button(intent: PTStopMotoAlarmIntent(alarmID: alarmID)) {
                        Label(
                            LocalizedStringResource("alarm_stop", table: "Localizable"),
                            systemImage: "stop.circle"
                        )
                    }
                    .tint(.red)
                }
            case .paused(let paused):
                Text(String(format: "%02d:%02d", max(Int((paused.totalCountdownDuration - paused.previouslyElapsedDuration).rounded()), 0) / 60, max(Int((paused.totalCountdownDuration - paused.previouslyElapsedDuration).rounded()), 0) % 60))
                    .font(.system(size: 38, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundColor(.orange)
                HStack {
                    Button(intent: PTResumeMotoAlarmIntent(alarmID: alarmID)) {
                        Label(
                            LocalizedStringResource("alarm_resume", table: "Localizable"),
                            systemImage: "play.circle"
                        )
                    }
                    .tint(.green)
                    Button(intent: PTStopMotoAlarmIntent(alarmID: alarmID)) {
                        Label(
                            LocalizedStringResource("alarm_stop", table: "Localizable"),
                            systemImage: "stop.circle"
                        )
                    }
                    .tint(.red)
                }
            case .alert(let alert):
                Text(String(format: "%02d:%02d", alert.time.hour, alert.time.minute))
                    .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundColor(.red)
                Button(intent: PTStopMotoAlarmIntent(alarmID: alarmID)) {
                    Label(
                        LocalizedStringResource("alarm_stop", table: "Localizable"),
                        systemImage: "stop.circle"
                    )
                }
                .tint(.red)
            @unknown default:
                Text(LocalizedStringResource("alarm_fallback_title", table: "Localizable"))
                    .font(.headline)
                    .foregroundColor(.gray)
            }
        }
        .padding()
    }

    private var alarmID: UUID {
        context.attributes.metadata?.alarmID ?? context.state.alarmID
    }

    private var iconName: String {
        switch context.attributes.metadata?.kind {
        case .departure:
            return "flag.checkered"
        case .maintenance:
            return "wrench.and.screwdriver.fill"
        case .parking:
            return "parkingsign.circle.fill"
        case .rideBreak:
            return "cup.and.saucer.fill"
        case .none:
            return "motorcycle"
        }
    }
}
