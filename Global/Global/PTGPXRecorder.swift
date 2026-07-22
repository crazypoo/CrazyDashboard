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
    
    private override init() {
        super.init()
        setupObservers()
    }
    
    private func setupObservers() {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(startRecording), name: BLEConnectSuccess, object: nil)
        nc.addObserver(self, selector: #selector(stopAndExport), name: MotorcycleDisconnected, object: nil)
        nc.addObserver(self, selector: #selector(handleControlData(_:)), name: MotorcycleCONTROL, object: nil)
    }
    
    @objc private func handleControlData(_ notification: Notification) {
        guard let control = notification.object as? PTDashboardControl else { return }
        latestSpeed = control.vehicleSpeedKmh
        latestRpm = control.engineRpm
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
            rpm: latestRpm
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
            // 在 extensions 标签中注入赛道级遥测数据
            let trkpt = """
                <trkpt lat="\(point.coordinate.latitude)" lon="\(point.coordinate.longitude)">
                  <ele>\(point.altitude)</ele>
                  <time>\(timeStr)</time>
                  <extensions>
                    <speed>\(point.speed)</speed>
                    <rpm>\(point.rpm)</rpm>
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
