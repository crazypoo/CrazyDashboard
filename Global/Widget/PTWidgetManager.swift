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
    private let appGroupID = PTWidgetDataKeys.appGroupID
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
            lastUpdateTime: updateDate,
            languageIdentifier: PTLanguage.share.language
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

        // EN: Watch receives the newest state immediately; persistence only transports Sendable Data.
        // ES: Watch recibe el estado más reciente de inmediato; la persistencia solo transporta Data Sendable.
        // 中文：Watch 立即接收最新状态；持久化任务只传递可安全跨并发域的 Data。
        PTWatchConnectivityManager.shared.update(status: status)
        let revision = Int64(updateDate.timeIntervalSince1970 * 1_000)
        Task.detached(priority: .utility) { [snapshotData, cloudFileName, revision] in
            do {
                let result = try await PTDataPersistenceActor.shared.writeData(
                    snapshotData,
                    fileName: cloudFileName,
                    revision: revision,
                    syncToICloud: true
                )
                if let cloudErrorDescription = result.cloudErrorDescription {
                    PTNSLogConsole("⚠️ [Widget同步] 本地快照已保存，但 iCloud 同步失败: \(cloudErrorDescription)")
                } else if !result.didSkipStaleWrite {
                    PTNSLogConsole("☁️ [Widget同步] 数据快照已原子保存并同步 iCloud: \(cloudFileName)")
                }
            } catch {
                PTNSLogConsole("❌ [Widget同步] 数据快照保存失败: \(error.localizedDescription)")
            }
        }
        
        WidgetCenter.shared.reloadTimelines(ofKind: "XP400Widget")
        PTNSLogConsole("📲 [Widget同步] 已将最新机车数据 (含高德地址) 推送到共享沙盒！")
    }

    // EN: Propagate a language-only change without pretending that vehicle telemetry was refreshed.
    // ES: Propaga un cambio de idioma sin fingir que se ha actualizado la telemetría del vehículo.
    // 中文：只同步语言变化，不把它伪装成车辆遥测数据刷新。
    public func updateLanguageIdentifier(_ languageIdentifier: String) {
        guard let defaults = sharedDefaults else { return }
        let current = PTWidgetSharedStatus.read(from: defaults)
        let status = PTWidgetSharedStatus(
            fuelLevel: current.fuelLevel,
            tripKm: current.tripKm,
            isConnected: current.isConnected,
            parkedLat: current.parkedLat,
            parkedLon: current.parkedLon,
            address: current.address,
            lastUpdateTime: current.lastUpdateTime,
            languageIdentifier: languageIdentifier
        )
        status.write(to: defaults)
        PTWatchConnectivityManager.shared.update(status: status)
        WidgetCenter.shared.reloadTimelines(ofKind: "XP400Widget")
    }
}
