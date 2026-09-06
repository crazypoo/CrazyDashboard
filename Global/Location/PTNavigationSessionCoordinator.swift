//
//  PTNavigationSessionCoordinator.swift
//  CrazyDashboard
//
//  EN: One main-thread navigation session coordinates map output and vehicle guidance.
//  ES: Una sesión de navegación en el hilo principal coordina el mapa y la guía del vehículo.
//  中文：单一主线程导航会话统一协调地图输出和车辆导航提示。
//

import Foundation
import UIKit
import CoreLocation
import PooTools
import AMapNaviKit

public enum PTNavigationSessionState: Equatable, Sendable {
    case idle
    case calculating
    case routeReady
    case navigating
    case rerouting
    case arrived
    case failed(String)
}

public enum PTNavigationMode: String, Equatable, Sendable {
    case gps
    case emulator
}

public struct PTNavigationDestination: Equatable, Sendable {
    public let title: String
    public let latitude: Double
    public let longitude: Double

    public init(title: String, coordinate: CLLocationCoordinate2D) {
        self.title = title
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }
}

public struct PTNavigationGuidanceSnapshot: Equatable, Sendable {
    public let state: PTNavigationSessionState
    public let destination: PTNavigationDestination?
    public let currentRoad: String
    public let nextRoad: String
    public let maneuverCode: UInt8
    public let distanceToManeuverMeters: Double
    public let distanceToDestinationMeters: Double
    public let totalDistanceMeters: Double
    public let estimatedArrival: Date?
    public let speedLimit: UInt8
    public let mode: PTNavigationMode
    public let updatedAt: Date
}

public protocol PTNavigationSessionObserver: AnyObject {
    func navigationSessionDidCalculateRoutes(_ coordinator: PTNavigationSessionCoordinator)
    func navigationSession(_ coordinator: PTNavigationSessionCoordinator,
                            didUpdate naviInfo: AMapNaviInfo,
                            speedLimit: UInt8)
    func navigationSession(_ coordinator: PTNavigationSessionCoordinator,
                            didFail error: Error)
    func navigationSessionDidStop(_ coordinator: PTNavigationSessionCoordinator)
}

public enum PTNavigationSurface: String, Sendable {
    case phone
    case carPlay
}

/// EN: Owns AMap delegate and representative registration; the existing BLE/OBD managers remain untouched.
/// ES: Posee el delegado de AMap y el registro de representantes; los gestores BLE/OBD existentes no cambian.
/// 中文：统一持有高德代理和数据代表注册，现有 BLE/OBD 管理器保持不变。
public final class PTNavigationSessionCoordinator: NSObject,
                                                    AMapNaviDriveManagerDelegate,
                                                    AMapNaviDriveDataRepresentable {
    public static let shared = PTNavigationSessionCoordinator()
    public static let stateDidChangeNotification = Notification.Name("PTNavigationSessionCoordinator.stateDidChange")
    public static let guidanceDidUpdateNotification = Notification.Name("PTNavigationSessionCoordinator.guidanceDidUpdate")

    public private(set) var state: PTNavigationSessionState = .idle
    public private(set) var mode: PTNavigationMode = .gps
    public private(set) var destination: PTNavigationDestination?
    public private(set) var snapshot: PTNavigationGuidanceSnapshot

    public weak var observer: PTNavigationSessionObserver?

    private var selectedRouteID: Int?
    private var selectedRouteDistanceMeters: Double = 0
    private var selectedRouteDuration: TimeInterval = 0
    private var currentSpeedLimit: UInt8 = 0
    private weak var attachedDriveView: AMapNaviDriveView?
    private var attachedSurface: PTNavigationSurface?
    private var coordinatorIsDataRepresentative = false
    private var isStopping = false

    private override init() {
        snapshot = PTNavigationGuidanceSnapshot(
            state: .idle,
            destination: nil,
            currentRoad: "",
            nextRoad: "",
            maneuverCode: PTManeuverMap.straight,
            distanceToManeuverMeters: 0,
            distanceToDestinationMeters: 0,
            totalDistanceMeters: 0,
            estimatedArrival: nil,
            speedLimit: 0,
            mode: .gps,
            updatedAt: .distantPast
        )
        super.init()
    }

    public var isEmulatorNavigation: Bool {
        mode == .emulator
    }

    public var isSessionActive: Bool {
        switch state {
        case .calculating, .routeReady, .navigating, .rerouting:
            return true
        case .idle, .arrived, .failed:
            return false
        }
    }

    // EN: Convert route distance into a safe progress value for Live Activity and Watch updates.
    // ES: Convierte la distancia de la ruta en un progreso seguro para Live Activity y Watch.
    // 中文：将路线距离转换为 Live Activity 和 Watch 可用的安全进度值。
    public static func normalizedProgress(remainingDistanceMeters: Double,
                                         totalDistanceMeters: Double) -> Double {
        guard remainingDistanceMeters.isFinite, totalDistanceMeters.isFinite else { return 0 }
        let remaining = max(0, remainingDistanceMeters)
        let total = max(0, totalDistanceMeters)
        guard total > 0 else { return remaining == 0 ? 1 : 0 }
        return min(max(1 - (remaining / total), 0), 1)
    }

    public func setEmulatorNavigation(_ enabled: Bool) {
        mode = enabled ? .emulator : .gps
        publishState()
    }

    public func prepareRoute(to coordinate: CLLocationCoordinate2D, title: String) {
        destination = PTNavigationDestination(title: title, coordinate: coordinate)
        selectedRouteID = nil
        selectedRouteDistanceMeters = 0
        selectedRouteDuration = 0
        setState(.calculating)
        ensureManagerOwnership()
    }

    public func selectRoute(routeID: Int, distanceMeters: Double, duration: TimeInterval) {
        selectedRouteID = routeID
        selectedRouteDistanceMeters = max(0, distanceMeters)
        selectedRouteDuration = max(0, duration)
        setState(.routeReady)
    }

    public func start(driveView: AMapNaviDriveView, estimatedDuration: TimeInterval? = nil) {
        guard state == .routeReady || state == .rerouting else { return }
        guard destination != nil else { return }

        if let estimatedDuration {
            selectedRouteDuration = max(0, estimatedDuration)
        }

        mode = mode == .emulator ? .emulator : .gps
        attach(surface: attachedSurface ?? .phone, driveView: driveView)
        PTDashboardConfig.shared.naving = true
        setState(.navigating)

        let arrival = Date().addingTimeInterval(selectedRouteDuration)
        let destinationName = destination?.title.trimmingCharacters(in: .whitespacesAndNewlines)
        PTLiveActivityManager.shared.startNavigationActivity(
            destination: destinationName?.isEmpty == false ? destinationName! : PTDashboardConfig.languageFunc(text: "tab_navigation"),
            expectedArrival: arrival
        )

        if mode == .emulator {
            AMapNaviDriveManager.sharedInstance().startEmulatorNavi()
        } else {
            AMapNaviDriveManager.sharedInstance().startGPSNavi()
        }
    }

    public func stop(reason: String = "user") {
        guard !isStopping else { return }
        isStopping = true

        let manager = AMapNaviDriveManager.sharedInstance()
        if state == .navigating || state == .rerouting {
            manager.stopNavi()
        }
        detachActiveDriveView()
        detachCoordinatorRepresentative()

        PTDashboardConfig.shared.naving = false
        PTWatchConnectivityManager.shared.clearNavigation()
        PTLiveActivityManager.shared.stopNavigationActivity()
        mode = .gps
        destination = nil
        selectedRouteID = nil
        selectedRouteDistanceMeters = 0
        selectedRouteDuration = 0
        currentSpeedLimit = 0
        setState(.idle)
        observer?.navigationSessionDidStop(self)
        isStopping = false
        PTNSLogConsole("Navigation session stopped: %@", reason)
    }

    public func attach(surface: PTNavigationSurface, driveView: AMapNaviDriveView) {
        ensureManagerOwnership()
        let manager = AMapNaviDriveManager.sharedInstance()

        if let attachedDriveView,
           attachedDriveView !== driveView {
            manager.removeDataRepresentative(attachedDriveView)
        }

        if attachedDriveView !== driveView {
            manager.addDataRepresentative(driveView)
        }
        attachedDriveView = driveView
        attachedSurface = surface
    }

    public func detach(surface: PTNavigationSurface) {
        guard attachedSurface == surface else { return }
        detachActiveDriveView()
        attachedSurface = nil
    }

    private func ensureManagerOwnership() {
        let manager = AMapNaviDriveManager.sharedInstance()
        manager.delegate = self
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        if !coordinatorIsDataRepresentative {
            manager.addDataRepresentative(self)
            coordinatorIsDataRepresentative = true
        }
    }

    private func detachActiveDriveView() {
        if let attachedDriveView {
            AMapNaviDriveManager.sharedInstance().removeDataRepresentative(attachedDriveView)
        }
        attachedDriveView = nil
        attachedSurface = nil
    }

    private func detachCoordinatorRepresentative() {
        guard coordinatorIsDataRepresentative else { return }
        AMapNaviDriveManager.sharedInstance().removeDataRepresentative(self)
        coordinatorIsDataRepresentative = false
    }

    private func setState(_ newState: PTNavigationSessionState) {
        state = newState
        let isResetState = newState == .idle
        snapshot = PTNavigationGuidanceSnapshot(
            state: newState,
            destination: destination,
            currentRoad: isResetState ? "" : snapshot.currentRoad,
            nextRoad: isResetState ? "" : snapshot.nextRoad,
            maneuverCode: isResetState ? PTManeuverMap.straight : snapshot.maneuverCode,
            distanceToManeuverMeters: isResetState ? 0 : snapshot.distanceToManeuverMeters,
            distanceToDestinationMeters: isResetState ? 0 : snapshot.distanceToDestinationMeters,
            totalDistanceMeters: isResetState ? 0 : snapshot.totalDistanceMeters,
            estimatedArrival: isResetState ? nil : snapshot.estimatedArrival,
            speedLimit: currentSpeedLimit,
            mode: mode,
            updatedAt: Date()
        )
        publishState()
    }

    private func publishState() {
        NotificationCenter.default.post(
            name: Self.stateDidChangeNotification,
            object: self,
            userInfo: ["state": state]
        )
    }

    private func handleGuidance(_ naviInfo: AMapNaviInfo) {
        guard state == .navigating || state == .rerouting else { return }

        let distanceToDestination = Double(max(0, naviInfo.routeRemainDistance))
        let distanceToManeuver = Double(max(0, naviInfo.segmentRemainDistance))
        let totalDistance = max(
            selectedRouteDistanceMeters,
            Double(max(0, naviInfo.travelRealPathLength))
        )
        let maneuverCode = PTMotoDashBoardNavFunction.convertAMapIconToPTManeuver(iconType: naviInfo.iconType)
        let arrival = Date().addingTimeInterval(TimeInterval(max(0, naviInfo.routeRemainTime)))

        snapshot = PTNavigationGuidanceSnapshot(
            state: state,
            destination: destination,
            currentRoad: naviInfo.currentRoadName ?? "",
            nextRoad: naviInfo.nextRoadName ?? "",
            maneuverCode: maneuverCode,
            distanceToManeuverMeters: distanceToManeuver,
            distanceToDestinationMeters: distanceToDestination,
            totalDistanceMeters: totalDistance,
            estimatedArrival: arrival,
            speedLimit: currentSpeedLimit,
            mode: mode,
            updatedAt: Date()
        )

        // EN: One callback produces one dashboard packet and one synchronized system snapshot.
        // ES: Un callback produce un paquete para el tablero y una instantánea sincronizada del sistema.
        // 中文：一次导航回调只产生一条仪表盘数据和一份系统同步快照。
        PTMotoDashBoardNavFunction.sendNavDataToDashboard(
            naviInfo: naviInfo,
            currentSpeedLimit: currentSpeedLimit
        )
        let progress = Self.normalizedProgress(
            remainingDistanceMeters: distanceToDestination,
            totalDistanceMeters: totalDistance
        )
        PTLiveActivityManager.shared.updateNavigationActivity(
            progress: progress,
            remainingKm: distanceToDestination / 1000,
            expectedArrival: arrival
        )
        PTWatchConnectivityManager.shared.updateTurnByTurnNavigation(
            routeName: snapshot.currentRoad,
            instruction: snapshot.nextRoad,
            maneuverCode: maneuverCode,
            distanceToManeuverMeters: distanceToManeuver,
            distanceToDestinationMeters: distanceToDestination
        )

        NotificationCenter.default.post(
            name: Self.guidanceDidUpdateNotification,
            object: self,
            userInfo: ["naviInfo": naviInfo, "speedLimit": currentSpeedLimit]
        )
        observer?.navigationSession(self, didUpdate: naviInfo, speedLimit: currentSpeedLimit)
    }

    // MARK: AMapNaviDriveManagerDelegate

    public func driveManager(onArrivedDestination driveManager: AMapNaviDriveManager) {
        setState(.arrived)
        stop(reason: "arrived")
    }

    public func driveManagerDidEndEmulatorNavi(_ driveManager: AMapNaviDriveManager) {
        stop(reason: "emulatorEnded")
    }

    public func driveManager(_ driveManager: AMapNaviDriveManager, error: Error) {
        state = .failed(error.localizedDescription)
        observer?.navigationSession(self, didFail: error)
        stop(reason: "error")
    }

    public func driveManager(_ driveManager: AMapNaviDriveManager, onCalculateRouteFailure error: Error) {
        // EN: AMap does not stop navigation automatically after route calculation failure.
        // ES: AMap no detiene la navegación automáticamente después de fallar el cálculo.
        // 中文：高德在算路失败后不会自动停止导航，因此这里显式清理会话资源。
        state = .failed(error.localizedDescription)
        observer?.navigationSession(self, didFail: error)
        detachActiveDriveView()
        detachCoordinatorRepresentative()
        PTDashboardConfig.shared.naving = false
        PTWatchConnectivityManager.shared.clearNavigation()
        PTLiveActivityManager.shared.stopNavigationActivity()
        mode = .gps
        destination = nil
        selectedRouteID = nil
        selectedRouteDistanceMeters = 0
        selectedRouteDuration = 0
        publishState()
        setState(.idle)
        observer?.navigationSessionDidStop(self)
    }

    public func driveManager(onCalculateRouteSuccess driveManager: AMapNaviDriveManager) {
        setState(.routeReady)
        observer?.navigationSessionDidCalculateRoutes(self)
    }

    public func driveManager(_ driveManager: AMapNaviDriveManager,
                             onCalculateRouteSuccessWith type: AMapNaviRoutePlanType) {
        setState(.routeReady)
        observer?.navigationSessionDidCalculateRoutes(self)
    }

    public func driveManager(_ driveManager: AMapNaviDriveManager,
                             postRouteNotification notifyData: AMapNaviRouteNotifyData) {
        if state == .navigating {
            setState(.rerouting)
            setState(.navigating)
        }
    }

    public func driveManager(_ manager: AMapNaviDriveManager?, onUpdateNaviSpeedLimitSection speed: Int) {
        currentSpeedLimit = UInt8(clamping: speed)
    }

    public func driveManagerIsNaviSoundPlaying(_ driveManager: AMapNaviDriveManager) -> Bool {
        SpeechSynthesizer.Shared.isSpeaking()
    }

    public func driveManager(_ driveManager: AMapNaviDriveManager,
                             playNaviSound soundString: String,
                             soundStringType: AMapNaviSoundType) {
        if !PTMotoUserDefaultStruct.NavMute {
            SpeechSynthesizer.Shared.speak(soundString)
        }
    }

    public func driveManager(_ driveManager: AMapNaviDriveManager,
                             update gpsSignalStrength: AMapNaviGPSSignalStrength) {
        guard gpsSignalStrength != .smartPos else { return }
        PTBluetoothServerManager.shared.sendWelcomeMessage(
            next: "Searching GPS...",
            title: "",
            nextManeuver: PTXP400BLEProtocol.noValidActionManeuverCode
        )
    }

    // MARK: AMapNaviDriveDataRepresentable

    public func driveManager(_ driveManager: AMapNaviDriveManager,
                             updateCruiseElecCameraInfos cameraInfos: [AMapNaviTrafficFacilityInfo]) {
        if let speed = cameraInfos.first?.limitSpeed, speed > 0 {
            currentSpeedLimit = UInt8(clamping: speed)
        }
    }

    public func driveManager(_ driveManager: AMapNaviDriveManager,
                             update cameraInfos: [AMapNaviCameraInfo]?) {
        if let speed = cameraInfos?.first?.cameraSpeed, speed > 0 {
            currentSpeedLimit = UInt8(clamping: speed)
        }
    }

    public func driveManager(_ driveManager: AMapNaviDriveManager,
                             update naviInfo: AMapNaviInfo?) {
        guard let naviInfo else { return }
        handleGuidance(naviInfo)
    }

    public func driveManager(_ driveManager: AMapNaviDriveManager,
                             update naviLocation: AMapNaviLocation?) {
        guard mode == .emulator, let naviLocation else { return }
        PTLocationEngine.shared.amapEmulatorNavi(
            naviLocation: naviLocation,
            roadName: snapshot.currentRoad
        )
    }
}
