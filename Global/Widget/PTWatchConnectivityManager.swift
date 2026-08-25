//
//  PTWatchConnectivityManager.swift
//  CrazyDashboard
//

import Foundation
@preconcurrency import WatchConnectivity

@objcMembers
@MainActor
public final class PTWatchConnectivityManager: NSObject, WCSessionDelegate {
    public static let shared = PTWatchConnectivityManager()

    private let session = WCSession.default
    private var pendingStatus: PTWidgetSharedStatus?

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
    }

    public func update(status: PTWidgetSharedStatus) {
        pendingStatus = status
        flushPendingStatusIfPossible()
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

    nonisolated public func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor [weak self] in
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
    nonisolated public func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated public func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif
}
