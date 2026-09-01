//
//  PTWatchConnectivityManager.swift
//  CrazyDashboard
//

import Foundation
@preconcurrency import WatchConnectivity
import os

@objcMembers
@MainActor
public final class PTWatchConnectivityManager: NSObject, WCSessionDelegate {
    public static let shared = PTWatchConnectivityManager()

    private let session = WCSession.default
    private var latestContext: [String: Any]
    private var pendingContext: [String: Any]?
    private let logger = Logger(subsystem: "com.yd.PTSpeed", category: "WatchConnectivity")

    private override init() {
        latestContext = session.applicationContext
        super.init()
        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
    }

    public func update(status: PTWidgetSharedStatus) {
        mergeAndSend(status.applicationContext)
    }

    // EN: Roadbook progress shares the same latest-state channel as vehicle status.
    // ES: El progreso del Roadbook comparte el mismo canal de último estado que el estado del vehículo.
    // 中文：Roadbook 进度与车辆状态共用同一个最新状态通道。
    public func update(roadbookSnapshot snapshot: PTRoadbookNavigationSnapshot) {
        guard let roadbookID = snapshot.roadbookID else {
            update(navigation: .placeholder)
            return
        }

        let totalSteps = max(snapshot.waypointCount, 0)
        let currentStep = totalSteps == 0
            ? 0
            : min(max(snapshot.currentWaypointIndex + 1, 1), totalSteps)
        let navigation = PTWatchRideAssistantState(
            source: .roadbook,
            status: Self.watchStatus(for: snapshot.state),
            routeName: snapshot.roadbookName ?? "",
            instruction: snapshot.targetInstruction ?? "",
            maneuver: PTWatchNavigationManeuver(dashboardCode: snapshot.targetManeuverCode ?? 0),
            maneuverIdentifier: "roadbook:\(roadbookID.uuidString):\(snapshot.currentWaypointIndex)",
            distanceToManeuverMeters: snapshot.distanceToTargetMeters,
            distanceToDestinationMeters: snapshot.distanceToDestinationMeters,
            currentStep: currentStep,
            totalSteps: totalSteps,
            updatedAt: snapshot.updatedAt
        )
        update(navigation: navigation)
    }

    // EN: Normal AMap navigation is projected into the same read-only Watch model without exposing BLE.
    // ES: La navegación normal de AMap se proyecta al mismo modelo de solo lectura del Watch sin exponer BLE.
    // 中文：普通高德导航投影到同一个 Watch 只读模型，不向 Watch 暴露 BLE。
    public func updateTurnByTurnNavigation(
        routeName: String,
        instruction: String,
        maneuverCode: UInt8,
        distanceToManeuverMeters: Double,
        distanceToDestinationMeters: Double,
        maneuverIdentifier: String? = nil
    ) {
        let fallbackIdentifier = "turn-by-turn:\(routeName)|\(instruction)|\(maneuverCode)"
        let navigation = PTWatchRideAssistantState(
            source: .turnByTurn,
            status: .active,
            routeName: routeName,
            instruction: instruction,
            maneuver: PTWatchNavigationManeuver(dashboardCode: maneuverCode),
            maneuverIdentifier: maneuverIdentifier ?? fallbackIdentifier,
            distanceToManeuverMeters: distanceToManeuverMeters,
            distanceToDestinationMeters: distanceToDestinationMeters,
            currentStep: 0,
            totalSteps: 0
        )
        update(navigation: navigation)
    }

    // EN: Ending either navigation mode removes stale prompts while preserving the last parking state.
    // ES: Terminar cualquier modo de navegación elimina avisos obsoletos y conserva el último estacionamiento.
    // 中文：结束任一导航模式时清除过期提示，但保留最近停车状态。
    public func clearNavigation() {
        update(navigation: .placeholder)
    }

    private func update(navigation: PTWatchRideAssistantState) {
        mergeAndSend(navigation.applicationContext)
    }

    private func mergeAndSend(_ values: [String: Any]) {
        latestContext.merge(values) { _, newValue in newValue }
        pendingContext = latestContext
        flushPendingContextIfPossible()
    }

    private func flushPendingContextIfPossible() {
        guard WCSession.isSupported(), session.activationState == .activated,
              let context = pendingContext else { return }

        do {
            try session.updateApplicationContext(context)
            pendingContext = nil
        } catch {
            logger.error("updateApplicationContext failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private nonisolated static func watchStatus(for state: PTRoadbookState) -> PTWatchNavigationStatus {
        switch state {
        case .idle:
            return .idle
        case .active:
            return .active
        case .paused:
            return .paused
        case .offRoute:
            return .offRoute
        case .completed:
            return .completed
        }
    }

    nonisolated public func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let error {
                self.logger.error("activation failed: \(error.localizedDescription, privacy: .public)")
            }
            if activationState == .activated {
                self.flushPendingContextIfPossible()
            }
        }
    }

    #if os(iOS)
    nonisolated public func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated public func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif
}
