//
//  PTGPXRecorder.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 23/7/2026.
//

import Foundation
import CoreLocation
import PooTools

extension PTiCloudFileManager {
    
    /// 按需从 iCloud 拉取指定的 GPX 文件到本地沙盒
    /// - Parameters:
    ///   - fileName: 需要拉取的文件名 (例如: MotoRide_20260726.gpx)
    ///   - completion: 拉取完成后的回调，返回本地可用的完整文件 URL
    func fetchGPXFileIfNeeded(fileName: String, completion: @escaping (URL?) -> Void) {
        let localFileURL = localDocumentsURL.appendingPathComponent(fileName)
        
        // 1. 如果本地沙盒已经存在该文件，秒开！直接返回本地路径
        if fileManager.fileExists(atPath: localFileURL.path) {
            completion(localFileURL)
            return
        }
        
        // 2. 本地没有，去 iCloud 容器中寻找
        guard let cloudURL = iCloudDocumentsURL else {
            PTNSLogConsole("⚠️ 拉取失败：iCloud 未开启或未准备好")
            completion(nil)
            return
        }
        
        let cloudFileURL = cloudURL.appendingPathComponent(fileName)
        
        // 检查云端是否记录了这个文件
        guard fileManager.fileExists(atPath: cloudFileURL.path) else {
            PTNSLogConsole("⚠️ 拉取失败：iCloud 中也未找到该轨迹文件 \(fileName)")
            completion(nil)
            return
        }
        
        // 3. 开启后台线程进行文件拷贝与下载，绝不卡死用户正在操作的 UI 界面
        PTGCDManager.shared.runOnMain {
            do {
                // 🚨 核心魔法：如果该文件在 iCloud 处于“占位符”状态（未真实下载到本设备），
                // 这个方法会唤醒 iOS 底层系统去立刻下载它！
                try self.fileManager.startDownloadingUbiquitousItem(at: cloudFileURL)
                
                // 将真实的云端文件拷贝一份到我们随时可读写的本地沙盒中
                try self.fileManager.copyItem(at: cloudFileURL, to: localFileURL)
                
                DispatchQueue.main.async {
                    PTNSLogConsole("☁️✅ 成功从 iCloud 拉取轨迹文件并缓存至本地: \(fileName)")
                    completion(localFileURL)
                }
            } catch {
                PTGCDManager.shared.runOnMain {
                    PTNSLogConsole("❌ 从 iCloud 拉取文件失败: \(error.localizedDescription)")
                    completion(nil)
                }
            }
        }
    }
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
    
    private override init() {
        super.init()
    }
            
    // 🌟 修改返回值：直接返回生成的文件名（例如：MotoRide_20260726_105100.gpx）
    public func exportGPX(from points: [PTRoutePoint]) -> String? {
        guard !points.isEmpty else { return nil }
        let xmlString = generateGPXString(from: points) // (保留原有的拼装逻辑)
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let fileName = "MotoRide_\(formatter.string(from: Date())).gpx"
        
        if let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let fileURL = docsDir.appendingPathComponent(fileName)
            do {
                try xmlString.write(to: fileURL, atomically: true, encoding: .utf8)
                PTNSLogConsole("✅ [GPX 导出] 轨迹本地保存成功！: \(fileName)")
                
                // 🚨 新增：顺手把这趟骑行的轨迹也备份到 iCloud！
                PTiCloudFileManager.shared.backupDatabaseToICloud(dbName: fileName)
                
                return fileName
            } catch {
                PTNSLogConsole("❌ [GPX 导出] 轨迹保存失败: \(error)")
                return nil
            }
        }
        return nil
    }

    // MARK: - XML 拼装引擎
    private func generateGPXString(from points: [PTRoutePoint]) -> String {
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
                    <trkpt lat="\(point.lat)" lon="\(point.lon)">
                      <ele>\(point.altitude)</ele>
                      <time>\(timeStr)</time>
                      <extensions>
                        <speed>\(point.speed)</speed>
                        <rpm>\(point.rpm)</rpm>
                        <lean>\(point.leanAngle)</lean>
                        <gforce_y>\(point.gForceY)</gforce_y>
                        <gforce_x>\(point.gForceX)</gforce_x>
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
