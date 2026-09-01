//
//  PTWatchStatusStore.swift
//  xp400watch Watch App
//

import Foundation
import Combine
@preconcurrency import WatchConnectivity
import WatchKit

@MainActor
final class PTWatchStatusStore: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var status: PTWidgetSharedStatus
    @Published private(set) var navigation: PTWatchRideAssistantState

    private let session = WCSession.default
    private var lastHapticIdentifier: String?

    override init() {
        let initialContext = WCSession.default.receivedApplicationContext
        let initialStatus = PTWidgetSharedStatus(applicationContext: initialContext) ?? .placeholder
        let initialNavigation = PTWatchRideAssistantState(applicationContext: initialContext) ?? .placeholder
        status = initialStatus
        navigation = initialNavigation
        lastHapticIdentifier = initialNavigation.hapticIdentifier

        super.init()

        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated else { return }
        Task { @MainActor [weak self] in
            self?.apply(applicationContext: session.receivedApplicationContext, playHaptic: false)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor [weak self] in
            self?.apply(applicationContext: applicationContext, playHaptic: true)
        }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif

    // EN: Apply one merged context so Watch status and navigation never drift apart.
    // ES: Aplica un contexto combinado para que el estado y la navegación del Watch no se separen.
    // 中文：应用合并后的上下文，避免 Watch 车辆状态和导航状态相互脱节。
    private func apply(applicationContext: [String: Any], playHaptic: Bool) {
        if let nextStatus = PTWidgetSharedStatus(applicationContext: applicationContext) {
            status = nextStatus
        }

        guard let nextNavigation = PTWatchRideAssistantState(applicationContext: applicationContext) else {
            return
        }

        navigation = nextNavigation
        guard playHaptic else { return }
        playHapticIfNeeded(next: nextNavigation)
    }

    // EN: Haptics are edge-triggered by maneuver identity, never by every GPS update.
    // ES: Los hápticos se activan por el cambio de maniobra, nunca por cada actualización GPS.
    // 中文：触觉只在转向标识变化时触发，不会随每次 GPS 更新重复触发。
    private func playHapticIfNeeded(next: PTWatchRideAssistantState) {
        guard next.status.canTriggerHaptic,
              next.isFresh,
              let identifier = next.hapticIdentifier,
              identifier != lastHapticIdentifier else {
            if next.status == .idle {
                lastHapticIdentifier = nil
            }
            return
        }

        lastHapticIdentifier = identifier
        switch next.status {
        case .completed:
            WKInterfaceDevice.current().play(.success)
        case .offRoute:
            WKInterfaceDevice.current().play(.retry)
        case .rerouting, .searchingGPS:
            WKInterfaceDevice.current().play(.notification)
        case .active:
            switch next.maneuver {
            case .left, .keepLeft, .sharpLeft, .uTurnLeft:
                WKInterfaceDevice.current().play(.navigationLeftTurn)
            case .right, .keepRight, .sharpRight, .uTurnRight:
                WKInterfaceDevice.current().play(.navigationRightTurn)
            default:
                WKInterfaceDevice.current().play(.navigationGenericManeuver)
            }
        case .idle, .paused:
            break
        }

    }

}
