//
//  PTWatchConnectivityManager.swift
//  CrazyDashboard
//

import Foundation
import WatchConnectivity

@objcMembers
public final class PTWatchConnectivityManager: NSObject, WCSessionDelegate {
    public static let shared = PTWatchConnectivityManager()

    private let session = WCSession.default
    private let queue = DispatchQueue(label: "com.yd.PTSpeed.watchConnectivity")
    private var pendingStatus: PTWidgetSharedStatus?

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
    }

    public func update(status: PTWidgetSharedStatus) {
        queue.async { [weak self] in
            guard let self else { return }
            self.pendingStatus = status
            self.flushPendingStatusIfPossible()
        }
    }

    private func flushPendingStatusIfPossible() {
        guard WCSession.isSupported(), session.activationState == .activated,
              let status = pendingStatus else { return }

        do {
            try session.updateApplicationContext(status.applicationContext)
            pendingStatus = nil
        } catch {
            print("[WatchConnectivity] updateApplicationContext failed: \(error.localizedDescription)")
        }
    }

    public func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            if let error {
                print("[WatchConnectivity] activation failed: \(error.localizedDescription)")
            }
            if activationState == .activated {
                self.flushPendingStatusIfPossible()
            }
        }
    }

    #if os(iOS)
    public func sessionDidBecomeInactive(_ session: WCSession) {}

    public func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif
}
