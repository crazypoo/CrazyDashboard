//
//  PTWidgetManager.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 30/7/2026.
//

import Foundation
import WidgetKit
import PooTools

@objcMembers
public class PTWidgetDataManager: NSObject {
    public static let shared = PTWidgetDataManager()
    private let appGroupID = "group.com.yd.PTSpeed.xp400" // 保持你的 App Group ID
    private let iCloudFileName = "PTWidgetDataSnapshot.json"
    
    private var sharedDefaults: UserDefaults? {
        return UserDefaults(suiteName: appGroupID)
    }
    
    private override init() { super.init() }
    
    /// 更新并同步数据给小组件 (新增了 address 参数)
    public func updateWidgetData(fuelLevel: Int, tripKm: Double, isConnected: Bool, parkedLat: Double, parkedLon: Double, address: String) {
        guard let defaults = sharedDefaults else { return }
        let updateDate = Date()

        let status = PTWidgetSharedStatus(
            fuelLevel: fuelLevel,
            tripKm: tripKm,
            isConnected: isConnected,
            parkedLat: parkedLat,
            parkedLon: parkedLon,
            address: address,
            lastUpdateTime: updateDate
        )
        status.write(to: defaults)
        let cloudFileName = iCloudFileName

        // 中文：App Group 继续作为 Widget 实时源；Español: App Group sigue siendo la fuente en tiempo real del Widget.
        let snapshotData: Data
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            snapshotData = try encoder.encode(status)
        } catch {
            PTNSLogConsole("❌ [Widget同步] iCloud 快照编码失败: \(error.localizedDescription)")
            return
        }

        // 中文：Watch 立即接收最新状态，iCloud 写入只携带 Sendable 的 Data；Español: Watch recibe el estado de inmediato y la tarea de iCloud solo transporta Data Sendable.
        PTWatchConnectivityManager.shared.update(status: status)
        Task.detached(priority: .utility) { [snapshotData, cloudFileName] in
            await MainActor.run {
                PTiCloudFileManager.shared.saveFileToICloud(data: snapshotData, fileName: cloudFileName)
                PTNSLogConsole("☁️ [Widget同步] 数据快照已发起 iCloud 保存: \(cloudFileName)")
            }
        }
        
        WidgetCenter.shared.reloadTimelines(ofKind: "XP400Widget")
        PTNSLogConsole("📲 [Widget同步] 已将最新机车数据 (含高德地址) 推送到共享沙盒！")
    }
}
