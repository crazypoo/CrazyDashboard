//
//  PTWatchStatusStore.swift
//  xp400watch Watch App
//

import Foundation
import Combine
@preconcurrency import WatchConnectivity

@MainActor
final class PTWatchStatusStore: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var status: PTWidgetSharedStatus

    private let session = WCSession.default

    override init() {
        if WCSession.isSupported(),
           let initialStatus = PTWidgetSharedStatus(applicationContext: WCSession.default.receivedApplicationContext) {
            status = initialStatus
        } else {
            status = .placeholder
        }

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
        guard let nextStatus = PTWidgetSharedStatus(applicationContext: session.receivedApplicationContext) else { return }
        Task { @MainActor [weak self] in
            self?.status = nextStatus
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let nextStatus = PTWidgetSharedStatus(applicationContext: applicationContext) else { return }
        Task { @MainActor [weak self] in
            self?.status = nextStatus
        }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif

}
