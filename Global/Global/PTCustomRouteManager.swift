//
//  PTCustomRouteManager.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 23/7/2026.
//

import Foundation
import CoreLocation
import AMapLocationKit
import PooTools

// EN: Posted whenever the active Roadbook session changes.
// ES: Se publica cada vez que cambia la sesión activa de Roadbook.
// 中文：活动 Roadbook 会话发生变化时发送此通知。
public let PTRoadbookStateDidChange = NSNotification.Name("PTRoadbookStateDidChange")

// EN: The coordinate reference used by a persisted Roadbook.
// ES: El sistema de referencia usado por un Roadbook persistido.
// 中文：持久化 Roadbook 使用的坐标参考系。
nonisolated public enum PTRoadbookCoordinateSystem: String, Codable, Hashable, Sendable {
    case wgs84
    case amapGCJ02
}

// EN: The lifecycle state of a Roadbook session.
// ES: El estado de ciclo de vida de una sesión de Roadbook.
// 中文：Roadbook 会话的生命周期状态。
nonisolated public enum PTRoadbookState: String, Codable, Hashable, Sendable {
    case idle
    case active
    case paused
    case offRoute
    case completed
}

// EN: Errors that can be shown by the Roadbook UI without relying on logs.
// ES: Errores que la interfaz puede mostrar sin depender de los registros.
// 中文：Roadbook 界面可直接展示的错误，不依赖日志作为数据接口。
nonisolated public enum PTRoadbookError: Error, Equatable, LocalizedError, Sendable {
    case emptyRoute
    case invalidWaypoint
    case invalidDocument
    case normalNavigationActive
    case activeSession
    case cannotDeleteActiveRoadbook
    case roadbookNotFound

    public var errorDescription: String? {
        switch self {
        case .emptyRoute:
            return "Roadbook 路线不能为空"
        case .invalidWaypoint:
            return "Roadbook 包含无效路点"
        case .invalidDocument:
            return "Roadbook 文件格式无效"
        case .normalNavigationActive:
            return "请先结束普通导航"
        case .activeSession:
            return "已有 Roadbook 会话正在运行"
        case .cannotDeleteActiveRoadbook:
            return "请先结束当前 Roadbook 会话"
        case .roadbookNotFound:
            return "找不到 Roadbook"
        }
    }
}

// EN: A Codable waypoint keeps its raw coordinate while exposing Core Location for runtime calculations.
// ES: Un punto Codable conserva su coordenada original y expone Core Location para los cálculos en tiempo real.
// 中文：可 Codable 的路点保存原始坐标，同时为运行时计算提供 Core Location 坐标。
nonisolated public struct PTCruiseWaypoint: Codable, Hashable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let instruction: String
    public let maneuverCode: UInt8

    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    public init(coordinate: CLLocationCoordinate2D,
                instruction: String,
                maneuverCode: UInt8) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.instruction = instruction
        self.maneuverCode = maneuverCode
    }

    public init(latitude: Double,
                longitude: Double,
                instruction: String,
                maneuverCode: UInt8) {
        self.latitude = latitude
        self.longitude = longitude
        self.instruction = instruction
        self.maneuverCode = maneuverCode
    }

    private enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
        case instruction
        case maneuverCode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let latitude = try container.decode(Double.self, forKey: .latitude)
        let longitude = try container.decode(Double.self, forKey: .longitude)
        guard latitude.isFinite,
              longitude.isFinite,
              (-90...90).contains(latitude),
              (-180...180).contains(longitude) else {
            throw PTRoadbookError.invalidWaypoint
        }

        self.latitude = latitude
        self.longitude = longitude
        self.instruction = try container.decode(String.self, forKey: .instruction)
        self.maneuverCode = try container.decode(UInt8.self, forKey: .maneuverCode)
    }
}

// EN: A persisted Roadbook is deliberately small: ordered waypoints plus the original GPX reference.
// ES: Un Roadbook persistido es deliberadamente pequeño: puntos ordenados y la referencia al GPX original.
// 中文：持久化 Roadbook 保持精简：有序路点加原始 GPX 引用。
nonisolated public struct PTRoadbook: Codable, Hashable, Identifiable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let id: UUID
    public var name: String
    public let coordinateSystem: PTRoadbookCoordinateSystem
    public let sourceFileName: String?
    public let waypoints: [PTCruiseWaypoint]
    public let createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(),
                name: String,
                coordinateSystem: PTRoadbookCoordinateSystem = .wgs84,
                sourceFileName: String? = nil,
                waypoints: [PTCruiseWaypoint],
                createdAt: Date = Date(),
                updatedAt: Date = Date()) {
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.coordinateSystem = coordinateSystem
        self.sourceFileName = sourceFileName
        self.waypoints = waypoints
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id
        case name
        case coordinateSystem
        case sourceFileName
        case waypoints
        case createdAt
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard schemaVersion <= Self.currentSchemaVersion else {
            throw PTRoadbookError.invalidDocument
        }

        self.schemaVersion = Self.currentSchemaVersion
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.coordinateSystem = try container.decodeIfPresent(PTRoadbookCoordinateSystem.self, forKey: .coordinateSystem) ?? .amapGCJ02
        self.sourceFileName = try container.decodeIfPresent(String.self, forKey: .sourceFileName)
        self.waypoints = try container.decode([PTCruiseWaypoint].self, forKey: .waypoints)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? self.createdAt
    }
}

// EN: This value is sent through NotificationCenter so UIKit and future Watch adapters can observe one stable state.
// ES: Este valor se envía mediante NotificationCenter para que UIKit y futuros adaptadores de Watch observen un estado estable.
// 中文：通过 NotificationCenter 发送该快照，UIKit 和未来 Watch 适配器都能观察统一状态。
nonisolated public struct PTRoadbookNavigationSnapshot: Equatable, Sendable {
    public let roadbookID: UUID?
    public let roadbookName: String?
    public let state: PTRoadbookState
    public let currentWaypointIndex: Int
    public let waypointCount: Int
    public let targetInstruction: String?
    public let targetManeuverCode: UInt8?
    public let distanceToTargetMeters: CLLocationDistance
    public let distanceToDestinationMeters: CLLocationDistance
    public let deviationMeters: CLLocationDistance
    public let offRouteSampleCount: Int
    public let latitude: Double?
    public let longitude: Double?
    public let updatedAt: Date

    public init(roadbookID: UUID? = nil,
                roadbookName: String? = nil,
                state: PTRoadbookState = .idle,
                currentWaypointIndex: Int = 0,
                waypointCount: Int = 0,
                targetInstruction: String? = nil,
                targetManeuverCode: UInt8? = nil,
                distanceToTargetMeters: CLLocationDistance = 0,
                distanceToDestinationMeters: CLLocationDistance = 0,
                deviationMeters: CLLocationDistance = 0,
                offRouteSampleCount: Int = 0,
                latitude: Double? = nil,
                longitude: Double? = nil,
                updatedAt: Date = Date()) {
        self.roadbookID = roadbookID
        self.roadbookName = roadbookName
        self.state = state
        self.currentWaypointIndex = currentWaypointIndex
        self.waypointCount = waypointCount
        self.targetInstruction = targetInstruction
        self.targetManeuverCode = targetManeuverCode
        self.distanceToTargetMeters = distanceToTargetMeters
        self.distanceToDestinationMeters = distanceToDestinationMeters
        self.deviationMeters = deviationMeters
        self.offRouteSampleCount = offRouteSampleCount
        self.latitude = latitude
        self.longitude = longitude
        self.updatedAt = updatedAt
    }
}

// EN: Pure route geometry keeps the off-route decision deterministic and easy to test.
// ES: La geometría pura mantiene determinista la decisión de desviación y facilita las pruebas.
// 中文：纯路线几何计算让偏航判断可重复且容易测试。
nonisolated enum PTRoadbookGeometry {
    static func distanceFromRoute(location: CLLocationCoordinate2D,
                                  route: [CLLocationCoordinate2D]) -> CLLocationDistance {
        guard !route.isEmpty else { return .infinity }
        guard route.count > 1 else {
            return CLLocation(latitude: location.latitude, longitude: location.longitude)
                .distance(from: CLLocation(latitude: route[0].latitude, longitude: route[0].longitude))
        }

        var minimumDistance = CLLocationDistance.infinity
        for index in 0..<(route.count - 1) {
            minimumDistance = min(
                minimumDistance,
                distanceFromSegment(location: location, start: route[index], end: route[index + 1])
            )
        }
        return minimumDistance
    }

    private static func distanceFromSegment(location: CLLocationCoordinate2D,
                                            start: CLLocationCoordinate2D,
                                            end: CLLocationCoordinate2D) -> CLLocationDistance {
        let referenceLatitude = location.latitude * .pi / 180
        let metersPerLatitude = 111_320.0
        let metersPerLongitude = metersPerLatitude * max(cos(referenceLatitude), 0.01)

        func point(_ coordinate: CLLocationCoordinate2D) -> (x: Double, y: Double) {
            (
                (coordinate.longitude - location.longitude) * metersPerLongitude,
                (coordinate.latitude - location.latitude) * metersPerLatitude
            )
        }

        let startPoint = point(start)
        let endPoint = point(end)
        let segmentX = endPoint.x - startPoint.x
        let segmentY = endPoint.y - startPoint.y
        let segmentLengthSquared = segmentX * segmentX + segmentY * segmentY

        guard segmentLengthSquared > 0 else {
            return hypot(startPoint.x, startPoint.y)
        }

        let projection = ((-startPoint.x * segmentX) + (-startPoint.y * segmentY)) / segmentLengthSquared
        let clampedProjection = min(max(projection, 0), 1)
        let closestX = startPoint.x + clampedProjection * segmentX
        let closestY = startPoint.y + clampedProjection * segmentY
        return hypot(closestX, closestY)
    }
}

// EN: MainActor serializes route state because location notifications and UIKit actions share this singleton.
// ES: MainActor serializa el estado porque las notificaciones de ubicación y UIKit comparten este singleton.
// 中文：使用 MainActor 串行化路线状态，避免定位通知与 UIKit 操作竞争单例数据。
@MainActor
@objcMembers
public class PTCustomRouteManager: NSObject {
    public static let shared = PTCustomRouteManager()

    public static let roadbooksFileName = "PTRoadbooks.json"
    public static let arrivalRadiusMeters: CLLocationDistance = 30
    public static let offRouteThresholdMeters: CLLocationDistance = 100
    public static let offRouteRequiredSamples = 3

    public private(set) var roadbooks: [PTRoadbook] = []
    public private(set) var activeRoadbook: PTRoadbook?
    public private(set) var currentTargetIndex = 0
    public private(set) var state: PTRoadbookState = .idle
    public private(set) var navigationSnapshot = PTRoadbookNavigationSnapshot()

    public var isSessionActive: Bool {
        switch state {
        case .active, .paused, .offRoute:
            return activeRoadbook != nil
        case .idle, .completed:
            return false
        }
    }

    private var offRouteSampleCount = 0
    private var lastLocation: CLLocation?

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLocationUpdate(_:)),
            name: PTLocationEngineDidUpdate,
            object: nil
        )
    }

    @MainActor
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Persistence

    // EN: Loads the local copy first and restores it from iCloud when needed.
    // ES: Carga primero la copia local y la restaura desde iCloud cuando es necesario.
    // 中文：优先读取本地副本，需要时从 iCloud 恢复。
    public func loadRoadbooks() async throws -> [PTRoadbook] {
        do {
            let data = try await PTDataPersistenceActor.shared.readData(
                fileName: Self.roadbooksFileName,
                restoreFromICloud: true
            )
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let document = try decoder.decode(PTRoadbookDocument.self, from: data)
                roadbooks = document.roadbooks.filter { !$0.waypoints.isEmpty }
                return roadbooks
            } catch {
                _ = try? await PTDataPersistenceActor.shared.preserveCorruptData(
                    data,
                    fileName: Self.roadbooksFileName
                )
                throw PTRoadbookError.invalidDocument
            }
        } catch let error as PTDataPersistenceError {
            if case .fileNotFound = error {
                roadbooks = []
                return roadbooks
            }
            throw error
        }
    }

    // EN: Saves the whole small Roadbook document atomically through the shared persistence actor.
    // ES: Guarda atómicamente el pequeño documento completo mediante el actor de persistencia compartido.
    // 中文：通过共享持久化 actor 原子保存整个精简 Roadbook 文档。
    public func saveRoadbook(_ roadbook: PTRoadbook) async throws {
        try validate(roadbook)
        var updatedRoadbook = roadbook
        updatedRoadbook.updatedAt = Date()

        var candidateRoadbooks = roadbooks
        if let index = roadbooks.firstIndex(where: { $0.id == updatedRoadbook.id }) {
            candidateRoadbooks[index] = updatedRoadbook
        } else {
            candidateRoadbooks.append(updatedRoadbook)
        }
        candidateRoadbooks.sort { $0.updatedAt > $1.updatedAt }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(PTRoadbookDocument(roadbooks: candidateRoadbooks))
        let result = try await PTDataPersistenceActor.shared.writeData(
            data,
            fileName: Self.roadbooksFileName,
            revision: Int64(Date().timeIntervalSince1970 * 1_000),
            syncToICloud: true
        )
        if let cloudErrorDescription = result.cloudErrorDescription {
            PTNSLogConsole("⚠️ [Roadbook] 本地保存成功，但 iCloud 同步失败: \(cloudErrorDescription)")
        }
        roadbooks = candidateRoadbooks
        publishSnapshot()
    }

    // EN: Imports GPX bytes, persists the original file, then creates a bounded ordered route.
    // ES: Importa los bytes GPX, conserva el archivo original y crea una ruta ordenada y acotada.
    // 中文：导入 GPX 数据、保存原文件，再生成有界的有序路线。
    public func importRoadbook(gpxData: Data, suggestedName: String) async throws -> PTRoadbook {
        try Task.checkCancellation()
        let trackPoints = try await Task.detached(priority: .utility) {
            try PTGPXParser.parseTrack(data: gpxData)
        }.value
        let waypoints = PTGPXParser.makeRoadbookWaypoints(from: trackPoints)
        guard waypoints.count >= 2 else {
            throw PTRoadbookError.emptyRoute
        }

        let sourceFileName = try await PTGPXRecorder.shared.persistImportedGPXAsync(
            gpxData,
            suggestedName: suggestedName
        )
        let roadbookName = suggestedName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty ? "ADV Roadbook" : suggestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let roadbook = PTRoadbook(
            name: roadbookName,
            coordinateSystem: .wgs84,
            sourceFileName: sourceFileName,
            waypoints: waypoints
        )

        do {
            try await saveRoadbook(roadbook)
            return roadbook
        } catch {
            _ = try? await PTDataPersistenceActor.shared.delete(
                fileName: sourceFileName,
                deleteFromICloud: true
            )
            throw error
        }
    }

    public func deleteRoadbook(id: UUID) async throws {
        guard let index = roadbooks.firstIndex(where: { $0.id == id }) else {
            throw PTRoadbookError.roadbookNotFound
        }
        guard activeRoadbook?.id != id else {
            throw PTRoadbookError.cannotDeleteActiveRoadbook
        }

        var candidateRoadbooks = roadbooks
        let deletedRoadbook = candidateRoadbooks.remove(at: index)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(PTRoadbookDocument(roadbooks: candidateRoadbooks))
        let result = try await PTDataPersistenceActor.shared.writeData(
            data,
            fileName: Self.roadbooksFileName,
            revision: Int64(Date().timeIntervalSince1970 * 1_000),
            syncToICloud: true
        )
        if let cloudErrorDescription = result.cloudErrorDescription {
            PTNSLogConsole("⚠️ [Roadbook] 删除已写入本地，但 iCloud 同步失败: \(cloudErrorDescription)")
        }
        roadbooks = candidateRoadbooks

        if let sourceFileName = deletedRoadbook.sourceFileName {
            let sourceResult = try? await PTDataPersistenceActor.shared.delete(
                fileName: sourceFileName,
                deleteFromICloud: true
            )
            if let cloudErrorDescription = sourceResult?.cloudErrorDescription {
                PTNSLogConsole("⚠️ [Roadbook] 路线已删除，但 GPX 云端文件删除失败: \(cloudErrorDescription)")
            }
        }
    }

    // MARK: - Session lifecycle

    // EN: Legacy API remains available and treats caller-provided coordinates as AMap coordinates.
    // ES: La API heredada sigue disponible y trata las coordenadas recibidas como coordenadas de AMap.
    // 中文：保留旧 API，并将调用方传入的坐标视为高德坐标。
    public func startCruise(route: [PTCruiseWaypoint]) {
        let roadbook = PTRoadbook(
            name: "ADV Roadbook",
            coordinateSystem: .amapGCJ02,
            waypoints: route
        )
        do {
            try startRoadbook(roadbook)
        } catch {
            PTNSLogConsole("❌ [Roadbook] 启动失败: \(error.localizedDescription)")
        }
    }

    public func startRoadbook(_ roadbook: PTRoadbook) throws {
        try validate(roadbook)
        guard !PTDashboardConfig.shared.naving else {
            throw PTRoadbookError.normalNavigationActive
        }
        guard !isSessionActive else {
            throw PTRoadbookError.activeSession
        }

        activeRoadbook = roadbook
        currentTargetIndex = 0
        offRouteSampleCount = 0
        lastLocation = nil
        state = .active
        PTNSLogConsole("🗺️ [Roadbook] 已加载路线 \(roadbook.name)，共 \(roadbook.waypoints.count) 个路点")
        publishSnapshot()
    }

    public func pauseRoadbook() {
        guard isSessionActive else { return }
        state = .paused
        publishSnapshot()
    }

    public func resumeRoadbook() {
        guard activeRoadbook != nil else { return }
        guard state == .paused || state == .offRoute else { return }
        state = offRouteSampleCount >= Self.offRouteRequiredSamples ? .offRoute : .active
        publishSnapshot()
    }

    public func stopCruise() {
        activeRoadbook = nil
        currentTargetIndex = 0
        offRouteSampleCount = 0
        lastLocation = nil
        state = .idle
        PTNSLogConsole("🗺️ [Roadbook] 会话已结束")
        publishSnapshot()
    }

    public func skipToNextWaypoint() {
        guard let roadbook = activeRoadbook, isSessionActive else { return }
        guard currentTargetIndex + 1 < roadbook.waypoints.count else {
            completeRoadbook()
            return
        }
        currentTargetIndex += 1
        offRouteSampleCount = 0
        state = .active
        sendNavigation(for: lastLocation)
        publishSnapshot()
    }

    public func goToPreviousWaypoint() {
        guard activeRoadbook != nil, isSessionActive else { return }
        currentTargetIndex = max(0, currentTargetIndex - 1)
        offRouteSampleCount = 0
        state = .active
        sendNavigation(for: lastLocation)
        publishSnapshot()
    }

    // EN: Location notifications are the single runtime input for Roadbook progress.
    // ES: Las notificaciones de ubicación son la única entrada de tiempo real del Roadbook.
    // 中文：定位通知是 Roadbook 进度的唯一运行时输入。
    @objc private func handleLocationUpdate(_ notification: Notification) {
        guard let tripData = notification.object as? PTTripData,
              let location = tripData.currentLocation else { return }
        processCurrentLocation(location)
    }

    public func processCurrentLocation(_ currentLocation: CLLocation) {
        guard isSessionActive,
              let roadbook = activeRoadbook,
              state != .paused,
              currentTargetIndex < roadbook.waypoints.count,
              currentLocation.coordinate.latitude.isFinite,
              currentLocation.coordinate.longitude.isFinite,
              (-90...90).contains(currentLocation.coordinate.latitude),
              (-180...180).contains(currentLocation.coordinate.longitude),
              currentLocation.horizontalAccuracy >= 0,
              currentLocation.horizontalAccuracy <= 50,
              Date().timeIntervalSince(currentLocation.timestamp) <= 10 else { return }

        lastLocation = currentLocation
        let runtimeRoute = roadbook.waypoints.map { runtimeCoordinate(for: $0, in: roadbook) }
        let locationCoordinate = currentLocation.coordinate
        let targetCoordinate = runtimeRoute[currentTargetIndex]
        let targetDistance = CLLocation(latitude: locationCoordinate.latitude, longitude: locationCoordinate.longitude)
            .distance(from: CLLocation(latitude: targetCoordinate.latitude, longitude: targetCoordinate.longitude))
        let deviation = PTRoadbookGeometry.distanceFromRoute(location: locationCoordinate, route: runtimeRoute)

        if deviation > Self.offRouteThresholdMeters {
            offRouteSampleCount += 1
        } else {
            offRouteSampleCount = 0
        }

        if targetDistance <= Self.arrivalRadiusMeters {
            PTNSLogConsole("✅ [Roadbook] 已到达路点 \(currentTargetIndex + 1)/\(roadbook.waypoints.count)")
            if currentTargetIndex + 1 >= roadbook.waypoints.count {
                sendNavigation(for: currentLocation, forceArrival: true)
                completeRoadbook()
                return
            }
            currentTargetIndex += 1
            offRouteSampleCount = 0
        }

        if offRouteSampleCount >= Self.offRouteRequiredSamples {
            state = .offRoute
        } else if state == .offRoute {
            state = .active
        }

        sendNavigation(for: currentLocation)
        publishSnapshot(deviationMeters: deviation)
    }

    // MARK: - Runtime helpers

    public func runtimeCoordinate(for waypoint: PTCruiseWaypoint,
                                  in roadbook: PTRoadbook? = nil) -> CLLocationCoordinate2D {
        let coordinateSystem = (roadbook ?? activeRoadbook)?.coordinateSystem ?? .amapGCJ02
        guard coordinateSystem == .wgs84 else { return waypoint.coordinate }
        return AMapLocationCoordinateConvert(waypoint.coordinate, AMapLocationCoordinateType.GPS)
    }

    private func sendNavigation(for location: CLLocation?, forceArrival: Bool = false) {
        guard let roadbook = activeRoadbook,
              currentTargetIndex < roadbook.waypoints.count else { return }

        let target = roadbook.waypoints[currentTargetIndex]
        let runtimeRoute = roadbook.waypoints.map { runtimeCoordinate(for: $0, in: roadbook) }
        let targetCoordinate = runtimeRoute[currentTargetIndex]
        let currentCoordinate = location?.coordinate ?? targetCoordinate
        let targetDistance = CLLocation(latitude: currentCoordinate.latitude, longitude: currentCoordinate.longitude)
            .distance(from: CLLocation(latitude: targetCoordinate.latitude, longitude: targetCoordinate.longitude))
        let destinationDistance = remainingDistance(from: currentCoordinate, route: runtimeRoute)
        let speedMetersPerSecond = max(location?.speed ?? 0, 10.0 / 3.6)
        let estimatedSeconds = Int(max(0, destinationDistance / speedMetersPerSecond))
        let maneuver = forceArrival
            ? PTManeuverMap.arrive
            : PTXP400BLEProtocol.normalizedManeuverCode(target.maneuverCode)

        let navInfo = PTNavigationInfo(
            nextManeuver: maneuver,
            metersToNextManeuver: safeUInt32(targetDistance),
            nameNextRoad: target.instruction.toMotorcycleCompatiblePinyin(),
            nameCurrentRoad: "ADV Roadbook",
            currentSpeedLimit: 0,
            distanceToDestination: safeUInt32(destinationDistance),
            estimatedTimeToDestinationSec: estimatedSeconds
        )
        PTBluetoothServerManager.shared.sendNavigation(info: navInfo)
    }

    private func remainingDistance(from location: CLLocationCoordinate2D,
                                   route: [CLLocationCoordinate2D]) -> CLLocationDistance {
        guard !route.isEmpty, currentTargetIndex < route.count else { return 0 }
        var result = CLLocation(latitude: location.latitude, longitude: location.longitude)
            .distance(from: CLLocation(latitude: route[currentTargetIndex].latitude,
                                        longitude: route[currentTargetIndex].longitude))
        if currentTargetIndex + 1 < route.count {
            for index in currentTargetIndex..<(route.count - 1) {
                result += CLLocation(latitude: route[index].latitude, longitude: route[index].longitude)
                    .distance(from: CLLocation(latitude: route[index + 1].latitude,
                                               longitude: route[index + 1].longitude))
            }
        }
        return result
    }

    private func completeRoadbook() {
        state = .completed
        currentTargetIndex = activeRoadbook?.waypoints.count ?? 0
        offRouteSampleCount = 0
        PTNSLogConsole("🎉 [Roadbook] 路线已完成")
        publishSnapshot()
    }

    private func publishSnapshot(deviationMeters: CLLocationDistance = 0) {
        guard let roadbook = activeRoadbook else {
            navigationSnapshot = PTRoadbookNavigationSnapshot(state: .idle)
            NotificationCenter.default.post(name: PTRoadbookStateDidChange, object: self, userInfo: ["snapshot": navigationSnapshot])
            PTWatchConnectivityManager.shared.update(roadbookSnapshot: navigationSnapshot)
            return
        }

        let targetIndex = min(currentTargetIndex, max(roadbook.waypoints.count - 1, 0))
        let target = roadbook.waypoints.indices.contains(targetIndex) ? roadbook.waypoints[targetIndex] : nil
        let route = roadbook.waypoints.map { runtimeCoordinate(for: $0, in: roadbook) }
        let currentCoordinate = lastLocation?.coordinate
        let distanceToTarget: CLLocationDistance
        let distanceToDestination: CLLocationDistance
        if let currentCoordinate, let target {
            let targetCoordinate = runtimeCoordinate(for: target, in: roadbook)
            distanceToTarget = CLLocation(latitude: currentCoordinate.latitude, longitude: currentCoordinate.longitude)
                .distance(from: CLLocation(latitude: targetCoordinate.latitude, longitude: targetCoordinate.longitude))
            distanceToDestination = remainingDistance(from: currentCoordinate, route: route)
        } else {
            distanceToTarget = 0
            distanceToDestination = 0
        }

        navigationSnapshot = PTRoadbookNavigationSnapshot(
            roadbookID: roadbook.id,
            roadbookName: roadbook.name,
            state: state,
            currentWaypointIndex: currentTargetIndex,
            waypointCount: roadbook.waypoints.count,
            targetInstruction: target?.instruction,
            targetManeuverCode: target?.maneuverCode,
            distanceToTargetMeters: distanceToTarget,
            distanceToDestinationMeters: distanceToDestination,
            deviationMeters: deviationMeters,
            offRouteSampleCount: offRouteSampleCount,
            latitude: currentCoordinate?.latitude,
            longitude: currentCoordinate?.longitude,
            updatedAt: Date()
        )
        NotificationCenter.default.post(name: PTRoadbookStateDidChange, object: self, userInfo: ["snapshot": navigationSnapshot])
        PTWatchConnectivityManager.shared.update(roadbookSnapshot: navigationSnapshot)
    }

    private func validate(_ roadbook: PTRoadbook) throws {
        guard !roadbook.waypoints.isEmpty else { throw PTRoadbookError.emptyRoute }
        guard roadbook.waypoints.allSatisfy({
            $0.latitude.isFinite && $0.longitude.isFinite &&
            (-90...90).contains($0.latitude) && (-180...180).contains($0.longitude)
        }) else {
            throw PTRoadbookError.invalidWaypoint
        }
    }

    private func safeUInt32(_ value: CLLocationDistance) -> UInt32 {
        guard value.isFinite else { return 0 }
        return UInt32(min(max(value.rounded(), 0), Double(UInt32.max)))
    }
}

private struct PTRoadbookDocument: Codable, Sendable {
    let schemaVersion: Int
    let roadbooks: [PTRoadbook]

    init(roadbooks: [PTRoadbook]) {
        self.schemaVersion = PTRoadbook.currentSchemaVersion
        self.roadbooks = roadbooks
    }
}
