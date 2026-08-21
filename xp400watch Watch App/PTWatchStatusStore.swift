//
//  PTWatchStatusStore.swift
//  xp400watch Watch App
//

import Foundation
import Combine
import WatchConnectivity

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

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated else { return }
        apply(applicationContext: session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        apply(applicationContext: applicationContext)
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif

    private func apply(applicationContext: [String: Any]) {
        guard let nextStatus = PTWidgetSharedStatus(applicationContext: applicationContext) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.status = nextStatus
        }
    }
}
