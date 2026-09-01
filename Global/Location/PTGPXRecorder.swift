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
        // EN: The compatibility callback remains, while the actor waits for a real cloud download.
        // ES: Se conserva el callback compatible y el actor espera a que termine la descarga real.
        // 中文：保留兼容回调，同时由 actor 等待云端文件真正下载完成。
        Task {
            do {
                let localURL = try await PTDataPersistenceActor.shared.ensureLocalFileURL(
                    fileName: fileName,
                    downloadTimeout: 8
                )
                PTNSLogConsole("☁️✅ 文件已准备好并缓存至本地: \(fileName)")
                completion(localURL)
            } catch {
                PTNSLogConsole("❌ 文件恢复失败 [\(fileName)]: \(error.localizedDescription)")
                completion(nil)
            }
        }
    }
}

extension PTiCloudFileManager {
    
    /// 从 iCloud 中彻底删除指定文件
    /// - Parameter fileName: 需要删除的文件名 (例如: MotoRide_xxx.gpx 或 MotoRide_xxx.jpg)
    public func deleteCloudFile(fileName: String) {
        // EN: Keep this legacy facade, but move the destructive file operation into the persistence actor.
        // ES: Se conserva esta fachada heredada, pero la operación destructiva pasa al actor de persistencia.
        // 中文：保留旧门面，但把删除操作交给持久化 actor，避免阻塞主线程。
        Task {
            do {
                let result = try await PTDataPersistenceActor.shared.deleteCloudFileOnly(fileName: fileName)
                if let error = result.cloudErrorDescription {
                    PTNSLogConsole("❌ 从 iCloud 删除文件失败 [\(fileName)]: \(error)")
                } else if result.didDeleteCloud {
                    PTNSLogConsole("☁️🗑️ 已从 iCloud 删除文件: \(fileName)")
                } else {
                    PTNSLogConsole("ℹ️ 云端不存在此文件，无需删除: \(fileName)")
                }
            } catch {
                PTNSLogConsole("❌ 从 iCloud 删除文件失败 [\(fileName)]: \(error.localizedDescription)")
            }
        }
    }
}

// EN: GPX track points preserve the raw WGS84 coordinate and optional route metadata.
// ES: Los puntos GPX conservan la coordenada WGS84 original y metadatos opcionales de la ruta.
// 中文：GPX 轨迹点保存原始 WGS84 坐标和可选路线元数据。
nonisolated public struct PTGPXTrackPoint: Codable, Hashable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let altitude: Double?
    public let timestamp: Date?

    public init(latitude: Double,
                longitude: Double,
                altitude: Double? = nil,
                timestamp: Date? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.timestamp = timestamp
    }

    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// EN: GPX parsing errors are explicit so import UI can explain a bad file.
// ES: Los errores de análisis GPX son explícitos para que la interfaz explique un archivo inválido.
// 中文：GPX 解析错误显式返回，让导入界面能解释无效文件。
nonisolated public enum PTGPXParseError: Error, Equatable, LocalizedError, Sendable {
    case emptyData
    case invalidXML(String)
    case noTrackPoints

    public var errorDescription: String? {
        switch self {
        case .emptyData:
            return "GPX 文件为空"
        case .invalidXML(let message):
            return "GPX 文件格式无效：\(message)"
        case .noTrackPoints:
            return "GPX 文件没有可用路线点"
        }
    }
}

// EN: Native XMLParser keeps the existing parser dependency-free while adding route metadata support.
// ES: XMLParser nativo conserva el parser sin dependencias y añade soporte para metadatos de ruta.
// 中文：使用原生 XMLParser，不增加依赖，同时支持路线元数据。
nonisolated public class PTGPXParser: NSObject, XMLParserDelegate {
    private struct MutableTrackPoint {
        var latitude: Double
        var longitude: Double
        var altitude: Double?
        var timestamp: Date?
    }

    private var trackPoints: [PTGPXTrackPoint] = []
    private var currentPoint: MutableTrackPoint?
    private var activeTextElement: String?
    private var textBuffer = ""
    private let isoFormatter: ISO8601DateFormatter

    public override init() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.isoFormatter = formatter
        super.init()
    }

    // EN: This compatibility method still returns only coordinates, as existing callers expect.
    // ES: Este método compatible sigue devolviendo solo coordenadas, como esperan los llamadores existentes.
    // 中文：保留兼容方法，仍只返回坐标，确保现有调用方不变。
    public func parse(fileURL: URL) -> [CLLocationCoordinate2D] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? Self.parseTrack(data: data).map(\.coordinate)) ?? []
    }

    public func parseTrack(fileURL: URL) throws -> [PTGPXTrackPoint] {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        } catch {
            throw PTGPXParseError.invalidXML(error.localizedDescription)
        }
        return try Self.parseTrack(data: data)
    }

    nonisolated public static func parseTrack(data: Data) throws -> [PTGPXTrackPoint] {
        guard !data.isEmpty else { throw PTGPXParseError.emptyData }
        let delegate = PTGPXParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw PTGPXParseError.invalidXML(parser.parserError?.localizedDescription ?? "无法解析 XML")
        }
        guard !delegate.trackPoints.isEmpty else {
            throw PTGPXParseError.noTrackPoints
        }
        return delegate.trackPoints
    }

    // EN: Convert a dense GPX track into bounded ordered navigation points.
    // ES: Convierte una traza GPX densa en puntos de navegación ordenados y acotados.
    // 中文：将密集 GPX 轨迹转换为有界的有序导航点。
    nonisolated public static func makeRoadbookWaypoints(from points: [PTGPXTrackPoint],
                                                         minimumSpacingMeters: CLLocationDistance = 35,
                                                         maximumWaypointCount: Int = 500) -> [PTCruiseWaypoint] {
        guard points.count >= 2, maximumWaypointCount >= 2 else { return [] }

        var selected: [PTGPXTrackPoint] = [points[0]]
        for point in points.dropFirst() {
            guard let last = selected.last else { continue }
            let distance = CLLocation(latitude: last.latitude, longitude: last.longitude)
                .distance(from: CLLocation(latitude: point.latitude, longitude: point.longitude))
            if distance >= max(1, minimumSpacingMeters) {
                selected.append(point)
            }
        }

        if let last = points.last,
           selected.last?.coordinate.latitude != last.coordinate.latitude ||
           selected.last?.coordinate.longitude != last.coordinate.longitude {
            selected.append(last)
        }

        if selected.count > maximumWaypointCount {
            let lastIndex = selected.count - 1
            selected = (0..<maximumWaypointCount).map { index in
                let position = Double(index) / Double(maximumWaypointCount - 1)
                return selected[Int((position * Double(lastIndex)).rounded())]
            }
        }

        return selected.enumerated().map { index, point in
            PTCruiseWaypoint(
                latitude: point.latitude,
                longitude: point.longitude,
                instruction: "Waypoint \(index + 1)",
                // EN: Keep the literal outside the main-actor dashboard map for detached parsing.
                // ES: Mantener el literal fuera del mapa del dashboard aislado al actor principal.
                // 中文：在脱离主线程解析时使用字面量，避免依赖主 actor 的仪表映射。
                maneuverCode: 1
            )
        }
    }

    // MARK: - XMLParserDelegate

    public func parser(_ parser: XMLParser,
                       didStartElement elementName: String,
                       namespaceURI: String?,
                       qualifiedName qName: String?,
                       attributes attributeDict: [String: String] = [:]) {
        let name = Self.localName(elementName)
        guard Self.pointElementNames.contains(name) else {
            if currentPoint != nil, Self.metadataElementNames.contains(name) {
                activeTextElement = name
                textBuffer = ""
            }
            return
        }

        guard let latitude = Double(attributeDict["lat"] ?? ""),
              let longitude = Double(attributeDict["lon"] ?? ""),
              latitude.isFinite,
              longitude.isFinite,
              (-90...90).contains(latitude),
              (-180...180).contains(longitude) else {
            currentPoint = nil
            return
        }
        currentPoint = MutableTrackPoint(latitude: latitude,
                                         longitude: longitude,
                                         altitude: nil,
                                         timestamp: nil)
    }

    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard activeTextElement != nil else { return }
        textBuffer.append(string)
    }

    public func parser(_ parser: XMLParser,
                       didEndElement elementName: String,
                       namespaceURI: String?,
                       qualifiedName qName: String?) {
        let name = Self.localName(elementName)
        if name == activeTextElement {
            let value = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if name == "ele", let altitude = Double(value) {
                currentPoint?.altitude = altitude
            } else if name == "time" {
                currentPoint?.timestamp = isoFormatter.date(from: value) ?? Self.fallbackISODate(from: value)
            }
            activeTextElement = nil
            textBuffer = ""
        }

        guard Self.pointElementNames.contains(name),
              let point = currentPoint else { return }
        trackPoints.append(PTGPXTrackPoint(latitude: point.latitude,
                                           longitude: point.longitude,
                                           altitude: point.altitude,
                                           timestamp: point.timestamp))
        currentPoint = nil
    }

    nonisolated private static let pointElementNames: Set<String> = ["trkpt", "rtept", "wpt"]
    nonisolated private static let metadataElementNames: Set<String> = ["ele", "time"]

    nonisolated private static func localName(_ name: String) -> String {
        String(name.split(separator: ":").last ?? Substring(name))
    }

    nonisolated private static func fallbackISODate(from value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
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
            
    /// EN: Legacy facade. The write is asynchronous; new flows should await `exportGPXAsync`.
    /// ES: Fachada heredada. La escritura es asíncrona; los flujos nuevos deben esperar `exportGPXAsync`.
    /// 中文：兼容旧门面。写入是异步的；新流程应等待 `exportGPXAsync`。
    public func exportGPX(from points: [PTRoutePoint]) -> String? {
        guard !points.isEmpty else { return nil }
        let fileName = makeGPXFileName()
        Task { [weak self] in
            do {
                _ = try await self?.exportGPXAsync(from: points, fileName: fileName)
            } catch {
                PTNSLogConsole("❌ [GPX 导出] 轨迹保存失败 [\(fileName)]: \(error.localizedDescription)")
            }
        }
        return fileName
    }

    /// EN: Generate and persist a GPX file without blocking the caller's thread.
    /// ES: Genera y guarda un archivo GPX sin bloquear el hilo del llamador.
    /// 中文：异步生成并保存 GPX，避免阻塞调用方线程。
    @nonobjc
    public func exportGPXAsync(from points: [PTRoutePoint], fileName: String? = nil) async throws -> String? {
        guard !points.isEmpty else { return nil }
        let resolvedFileName = fileName ?? makeGPXFileName()
        let xmlData = try await Task.detached(priority: .utility) {
            guard let data = Self.generateGPXString(from: points).data(using: .utf8) else {
                throw PTDataPersistenceError.localWriteFailed("GPX 编码失败")
            }
            return data
        }.value

        let result = try await PTDataPersistenceActor.shared.writeData(
            xmlData,
            fileName: resolvedFileName,
            revision: Int64(Date().timeIntervalSince1970 * 1_000),
            syncToICloud: true
        )
        if let cloudErrorDescription = result.cloudErrorDescription {
            PTNSLogConsole("⚠️ [GPX 导出] 本地已保存，但 iCloud 同步失败: \(cloudErrorDescription)")
        } else {
            PTNSLogConsole("✅ [GPX 导出] 轨迹已原子保存: \(resolvedFileName)")
        }
        return resolvedFileName
    }

    // EN: Export a Roadbook as a standard GPX route while preserving its stored coordinate values.
    // ES: Exporta un Roadbook como una ruta GPX estándar y conserva sus coordenadas almacenadas.
    // 中文：将 Roadbook 导出为标准 GPX 路线，并保留存储的原始坐标值。
    @nonobjc
    public func exportRoadbookAsync(from roadbook: PTRoadbook,
                                    fileName: String? = nil) async throws -> String? {
        guard roadbook.waypoints.count >= 2 else { return nil }
        let resolvedFileName = fileName ?? "Roadbook_\(makeGPXFileName().replacingOccurrences(of: "MotoRide_", with: ""))"
        let xmlData = try await Task.detached(priority: .utility) {
            guard let data = Self.generateRoadbookGPXString(from: roadbook).data(using: .utf8) else {
                throw PTDataPersistenceError.localWriteFailed("Roadbook GPX 编码失败")
            }
            return data
        }.value

        let result = try await PTDataPersistenceActor.shared.writeData(
            xmlData,
            fileName: resolvedFileName,
            revision: Int64(Date().timeIntervalSince1970 * 1_000),
            syncToICloud: true
        )
        if let cloudErrorDescription = result.cloudErrorDescription {
            PTNSLogConsole("⚠️ [Roadbook GPX] 本地已保存，但 iCloud 同步失败: \(cloudErrorDescription)")
        }
        return resolvedFileName
    }

    // EN: Persist an imported GPX in the shared file store so it remains shareable after import.
    // ES: Guarda el GPX importado en el almacén compartido para que siga siendo compartible.
    // 中文：将导入的 GPX 保存到共享文件存储，确保导入后仍可分享。
    @nonobjc
    public func persistImportedGPXAsync(_ data: Data,
                                        suggestedName: String) async throws -> String {
        guard !data.isEmpty else {
            throw PTGPXParseError.emptyData
        }
        let baseName = Self.sanitizedBaseName(suggestedName)
        let timestamp = makeGPXFileName().replacingOccurrences(of: "MotoRide_", with: "")
        let uniqueSuffix = String(UUID().uuidString.prefix(8))
        let fileName = "Roadbook_\(baseName)_\(timestamp)_\(uniqueSuffix).gpx"
        let result = try await PTDataPersistenceActor.shared.writeData(
            data,
            fileName: fileName,
            revision: Int64(Date().timeIntervalSince1970 * 1_000),
            syncToICloud: true
        )
        if let cloudErrorDescription = result.cloudErrorDescription {
            PTNSLogConsole("⚠️ [Roadbook 导入] 本地已保存，但 iCloud 同步失败: \(cloudErrorDescription)")
        }
        return fileName
    }

    public func makeGPXFileName(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return "MotoRide_\(formatter.string(from: date)).gpx"
    }

    // MARK: - XML 拼装引擎
    nonisolated private static func generateGPXString(from points: [PTRoutePoint]) -> String {
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

    nonisolated private static func generateRoadbookGPXString(from roadbook: PTRoadbook) -> String {
        let escapedName = xmlEscaped(roadbook.name)
        let coordinateSystem = roadbook.coordinateSystem.rawValue
        var gpx = """
            <?xml version="1.0" encoding="UTF-8"?>
            <gpx version="1.1" creator="PTMotoTracker" xmlns="http://www.topografix.com/GPX/1/1">
              <metadata><name>\(escapedName)</name></metadata>
              <rte>
                <name>\(escapedName)</name>
                <extensions><coordinate_system>\(coordinateSystem)</coordinate_system></extensions>
            """

        for waypoint in roadbook.waypoints {
            gpx += """
                <rtept lat="\(waypoint.latitude)" lon="\(waypoint.longitude)">
                  <name>\(xmlEscaped(waypoint.instruction))</name>
                </rtept>
            """
        }

        gpx += """
              </rte>
            </gpx>
            """
        return gpx
    }

    nonisolated private static func xmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    nonisolated private static func sanitizedBaseName(_ value: String) -> String {
        let source = URL(fileURLWithPath: value).deletingPathExtension().lastPathComponent
        let allowed = source.unicodeScalars.filter { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_"
        }
        let result = String(String.UnicodeScalarView(allowed)).trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? "route" : String(result.prefix(40))
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
