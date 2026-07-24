//
//  PTGPXRecorder.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 23/7/2026.
//

import Foundation
import CoreLocation
import PooTools

/// 单个轨迹点模型，包含位置与机车遥测数据
public struct PTTrackPoint {
    let coordinate: CLLocationCoordinate2D
    let altitude: CLLocationDistance
    let timestamp: Date
    let speed: Double // 机车传来的真实速度
    let rpm: Int      // 机车传来的真实转速
    
    let fuelLevel: Int        // 油量百分比
    let temperature: Int      // 外界温度
    let batteryVolt: Double   // 电瓶电压
    let tcsMode: String       // TCS 当前模式
    let isAbsActive: Bool     // ABS 是否正在亮灯/触发
}

// MARK: - UI 列表数据模型
/// 骑行历史记录模型，专门用于在列表中展示
public struct PTRideHistoryModel {
    /// 文件名 (例如: MotoRide_20260724_143000.gpx)
    public let fileName: String
    /// 本地沙盒中的绝对路径，用于后续的分享或地图绘制
    public let fileURL: URL
    /// 文件的创建时间
    public let creationDate: Date
    /// 文件大小（字节）
    public let fileSize: Int64
    
    /// 格式化后的文件大小（例如：2.5 MB 或 150 KB），可直接赋值给 UILabel
    public var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }
    
    /// 格式化后的时间（例如：2026-07-24 14:30），可直接赋值给 UILabel
    public var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: creationDate)
    }
}

@objcMembers
public class PTGPXRecorder: NSObject {
    
    public static let shared = PTGPXRecorder()
    
    private var isRecording: Bool = false
    private var currentTrack: [PTTrackPoint] = []
    
    // 缓存最新收到的遥测数据，等待 GPS 点刷新时一并打包
    private var latestSpeed: Double = 0
    private var latestRpm: Int = 0
    private var lastSampleTime: Date = Date()
    
    private var latestFuel: Int = 0
    private var latestTemp: Int = 0
    private var latestVolt: Double = 0.0
    private var latestTCS: String = "Unknown"
    private var latestAbsActive: Bool = false
    
    private override init() {
        super.init()
        setupObservers()
    }
    
    private func setupObservers() {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(startRecording), name: BLEConnectSuccess, object: nil)
        nc.addObserver(self, selector: #selector(stopAndExport), name: MotorcycleDisconnected, object: nil)
        nc.addObserver(self, selector: #selector(handleControlData(_:)), name: MotorcycleCONTROL, object: nil)
        nc.addObserver(self, selector: #selector(handleData1(_:)), name: MotorcycleDATA1, object: nil)
        nc.addObserver(self, selector: #selector(handleData2(_:)), name: MotorcycleDATA2, object: nil)
        nc.addObserver(self, selector: #selector(handleAbsData(_:)), name: MotorcycleABS, object: nil)
    }
    
    @objc private func handleControlData(_ notification: Notification) {
        guard let control = notification.object as? PTDashboardControl else { return }
        latestSpeed = control.vehicleSpeedKmh
        latestRpm = control.engineRpm
    }
    
    // 🚨 提取油耗
    @objc private func handleData1(_ notification: Notification) {
        guard let data1 = notification.object as? PTDashboardData1 else { return }
        latestFuel = data1.fuelLevelPct
    }
    
    // 🚨 提取温度和电压
    @objc private func handleData2(_ notification: Notification) {
        guard let data2 = notification.object as? PTDashboardData2 else { return }
        latestTemp = data2.outsideTempC
        latestVolt = data2.batteryVolt
    }
    
    // 🚨 提取 ABS 状态
    @objc private func handleAbsData(_ notification: Notification) {
        guard let absData = notification.object as? PTAbsStatus else { return }
        latestAbsActive = absData.isAbsLightOn
    }
    
    @objc private func startRecording() {
        isRecording = true
        currentTrack.removeAll()
        PTNSLogConsole("🗺️ [GPX 录制] 开始全新骑行轨迹录制...")
    }
    
    /// 外部调用：当你的高德地图 `didUpdate` 代理拿到新坐标时，调用此方法写入数据
    public func appendLocation(_ location: CLLocation) {
        guard isRecording else { return }
        
        // 采样控制：每隔 2 秒记录一个点，防止长途骑行文件过大
        let now = Date()
        guard now.timeIntervalSince(lastSampleTime) >= 2.0 else { return }
        lastSampleTime = now
        
        let point = PTTrackPoint(
            coordinate: location.coordinate,
            altitude: location.altitude,
            timestamp: now,
            speed: latestSpeed,
            rpm: latestRpm,
            fuelLevel: latestFuel,
            temperature: latestTemp,
            batteryVolt: latestVolt,
            tcsMode: latestTCS,
            isAbsActive: latestAbsActive
        )
        currentTrack.append(point)
    }
    
    @objc private func stopAndExport() {
        guard isRecording, !currentTrack.isEmpty else { return }
        isRecording = false
        
        // 生成遵循 GPX 1.1 标准的 XML 文本
        let xmlString = generateGPXString(from: currentTrack)
        
        // 保存到 App 沙盒的 Documents 目录
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let fileName = "MotoRide_\(formatter.string(from: Date())).gpx"
        
        if let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let fileURL = docsDir.appendingPathComponent(fileName)
            do {
                try xmlString.write(to: fileURL, atomically: true, encoding: .utf8)
                PTNSLogConsole("✅ [GPX 录制] 轨迹保存成功！可至文件 App 查看: \(fileURL.path)")
            } catch {
                PTNSLogConsole("❌ [GPX 录制] 轨迹保存失败: \(error)")
            }
        }
        currentTrack.removeAll()
    }
    
    // MARK: - XML 拼装引擎
    private func generateGPXString(from points: [PTTrackPoint]) -> String {
        let isoFormatter = ISO8601DateFormatter()
        
        var gpx = """
            <?xml version="1.0" encoding="UTF-8"?>
            <gpx version="1.1" creator="PTMotoTracker" xmlns="http://www.topografix.com/GPX/1/1">
              <trk>
                <name>Moto Ride</name>
                <trkseg>\n
            """
        
        for point in points {
            let timeStr = isoFormatter.string(from: point.timestamp)
            // 🚨 在 extensions 标签中注入所有高级遥测数据
            let trkpt = """
                    <trkpt lat="\(point.coordinate.latitude)" lon="\(point.coordinate.longitude)">
                      <ele>\(point.altitude)</ele>
                      <time>\(timeStr)</time>
                      <extensions>
                        <speed>\(point.speed)</speed>
                        <rpm>\(point.rpm)</rpm>
                        <fuel>\(point.fuelLevel)</fuel>
                        <temp>\(point.temperature)</temp>
                        <volt>\(point.batteryVolt)</volt>
                        <tcs>\(point.tcsMode)</tcs>
                        <abs>\(point.isAbsActive ? "1" : "0")</abs>
                      </extensions>
                    </trkpt>\n
                """
            gpx += trkpt
        }
        
        gpx += """
                </trkseg>
              </trk>
            </gpx>
            """
        return gpx
    }
}

// MARK: - 本地文件读取扩展
extension PTGPXRecorder {
    
    /// 获取所有已保存的 GPX 轨迹列表（按时间倒序排列，最新的在最上边）
    /// - Returns: 骑行历史模型数组，可以直接作为 UITableView 的 DataSource
    public func fetchSavedTracks() -> [PTRideHistoryModel] {
        let fileManager = FileManager.default
        guard let docsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return []
        }
        
        var rideHistory: [PTRideHistoryModel] = []
        
        do {
            // 扫描文档目录，同时预先请求创建时间和文件大小属性，提高性能
            let fileURLs = try fileManager.contentsOfDirectory(
                at: docsDir,
                includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
                options: .skipsHiddenFiles
            )
            
            // 过滤出 .gpx 文件并构建模型
            for url in fileURLs where url.pathExtension.lowercased() == "gpx" {
                // 提取文件属性
                let resourceValues = try url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
                let creationDate = resourceValues.creationDate ?? Date.distantPast
                let fileSize = Int64(resourceValues.fileSize ?? 0)
                
                let model = PTRideHistoryModel(
                    fileName: url.lastPathComponent,
                    fileURL: url,
                    creationDate: creationDate,
                    fileSize: fileSize
                )
                rideHistory.append(model)
            }
            
            // 按创建时间倒序排序 (最新录制的轨迹排在数组首位)
            rideHistory.sort { $0.creationDate > $1.creationDate }
            
        } catch {
            PTNSLogConsole("❌ [GPX 读取] 获取轨迹列表失败: \(error.localizedDescription)")
        }
        
        return rideHistory
    }
    
    /// 删除指定的轨迹文件（可用于 UI 列表的左滑删除）
    /// - Parameter track: 要删除的轨迹模型
    /// - Returns: 是否删除成功
    public func deleteTrack(_ track: PTRideHistoryModel) -> Bool {
        do {
            try FileManager.default.removeItem(at: track.fileURL)
            PTNSLogConsole("🗑️ [GPX 管理] 成功删除轨迹: \(track.fileName)")
            return true
        } catch {
            PTNSLogConsole("❌ [GPX 管理] 删除轨迹失败: \(error.localizedDescription)")
            return false
        }
    }
}
