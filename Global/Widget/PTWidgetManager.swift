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
        PTWatchConnectivityManager.shared.update(status: status)
        let cloudFileName = iCloudFileName

        // App Group 继续作为 Widget 的实时数据源；同时异步备份一份
        // 独立 JSON 快照到 iCloud，不阻塞定位回调和 Widget 刷新。
        Task { @MainActor [status, cloudFileName] in
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(status)
                PTiCloudFileManager.shared.saveFileToICloud(
                    data: data,
                    fileName: cloudFileName
                )
                PTNSLogConsole("☁️ [Widget同步] 数据快照已发起 iCloud 保存: \(cloudFileName)")
            } catch {
                PTNSLogConsole("❌ [Widget同步] iCloud 快照编码失败: \(error.localizedDescription)")
            }
        }
        
        WidgetCenter.shared.reloadTimelines(ofKind: "XP400Widget")
        PTNSLogConsole("📲 [Widget同步] 已将最新机车数据 (含高德地址) 推送到共享沙盒！")
    }
}
