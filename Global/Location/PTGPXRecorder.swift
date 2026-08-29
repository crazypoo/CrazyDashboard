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
    
    /// 按需从 iCloud 拉取指定的文件 (GPX 或 JPG) 到本地沙盒
    /// - Parameters:
    ///   - fileName: 需要拉取的文件名 (例如: MotoRide_xxx.gpx 或 MotoRide_xxx.jpg)
    ///   - completion: 拉取完成后的回调，返回本地可用的完整文件 URL
    func fetchCloudFileIfNeeded(fileName: String, completion: @escaping (URL?) -> Void) {
        // EN: Resolve both local and ubiquitous paths inside the utility queue so directory checks never block the UI.
        // ES: Resolvemos las rutas local y ubicua dentro de la cola de utilidad para que las comprobaciones no bloqueen la UI.
        // 中文：在后台队列解析本地和 iCloud 路径，避免目录检查阻塞 UI。
        DispatchQueue.global(qos: .utility).async {
            let fileManager = FileManager.default
            let localDocumentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            let localFileURL = localDocumentsURL.appendingPathComponent(fileName)

            // EN: A local copy is the fast path and does not touch iCloud.
            // ES: La copia local es la ruta rápida y no accede a iCloud.
            // 中文：本地缓存是最快路径，不再访问 iCloud。
            if fileManager.fileExists(atPath: localFileURL.path) {
                DispatchQueue.main.async {
                    completion(localFileURL)
                }
                return
            }

            guard let containerURL = fileManager.url(forUbiquityContainerIdentifier: nil) else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }

            let cloudDocumentsURL = containerURL.appendingPathComponent("Documents")
            do {
                if !fileManager.fileExists(atPath: cloudDocumentsURL.path) {
                    try fileManager.createDirectory(at: cloudDocumentsURL, withIntermediateDirectories: true)
                }
            } catch {
                PTNSLogConsole("❌ 创建 iCloud Documents 目录失败: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }

            let cloudFileURL = cloudDocumentsURL.appendingPathComponent(fileName)
            guard fileManager.fileExists(atPath: cloudFileURL.path) else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }

            do {
                try fileManager.startDownloadingUbiquitousItem(at: cloudFileURL)
                try fileManager.copyItem(at: cloudFileURL, to: localFileURL)

                PTNSLogConsole("☁️✅ 成功从 iCloud 拉取文件并缓存至本地: \(fileName)")
                DispatchQueue.main.async {
                    completion(localFileURL)
                }
            } catch {
                PTNSLogConsole("❌ 从 iCloud 拉取文件失败: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }
}

extension PTiCloudFileManager {
    
    /// 从 iCloud 中彻底删除指定文件
    /// - Parameter fileName: 需要删除的文件名 (例如: MotoRide_xxx.gpx 或 MotoRide_xxx.jpg)
    public func deleteCloudFile(fileName: String) {
        guard let cloudURL = iCloudDocumentsURL else {
            PTNSLogConsole("⚠️ 无法删除：iCloud 未准备好。")
            return
        }
        
        let fileURL = cloudURL.appendingPathComponent(fileName)
        
        // 检查云端文件是否存在
        guard fileManager.fileExists(atPath: fileURL.path) else {
            PTNSLogConsole("ℹ️ 云端不存在此文件，无需删除: \(fileName)")
            return
        }
        
        // 执行物理销毁
        do {
            try fileManager.removeItem(at: fileURL)
            PTNSLogConsole("☁️🗑️ 成功：已从 iCloud 彻底删除文件 \(fileName)")
        } catch {
            PTNSLogConsole("❌ 从 iCloud 删除文件失败: \(error.localizedDescription)")
        }
    }
}

/// 极简的 GPX 坐标提取工具
public class PTGPXParser: NSObject, XMLParserDelegate {
    
    private var coordinates: [CLLocationCoordinate2D] = []
    
    /// 传入本地的 GPX 文件 URL，返回所有的坐标点
    public func parse(fileURL: URL) -> [CLLocationCoordinate2D] {
        coordinates.removeAll()
        
        // 使用苹果原生的 XML 解析器，性能极高
        guard let parser = XMLParser(contentsOf: fileURL) else { return [] }
        parser.delegate = self
        parser.parse()
        
        return coordinates
    }
    
    // MARK: - XMLParserDelegate
    public func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        // 只要遇到 <trkpt lat="..." lon="..."> 标签，就把坐标提出来
        if elementName == "trkpt" {
            if let latStr = attributeDict["lat"], let lonStr = attributeDict["lon"],
               let lat = Double(latStr), let lon = Double(lonStr) {
                coordinates.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
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
            // 🚨 升级：在 extensions 标签中注入新增的 slip_ratio 遥测数据
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
                        <gforce_z>\(point.gForceZ)</gforce_z>
                        <slip_ratio>\(point.slipRatio)</slip_ratio>
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
