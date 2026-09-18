//
//  PTFeedbackBootstrap.swift
//  CrazyDashboard
//

import Foundation

@MainActor
public enum PTFeedbackBootstrap {
    /// Call once from the app startup path that already configures
    /// PTTelemetryResearchManager.
    public static func configureFromInfoPlist() async {
        do {
            let configuration = try PTFeedbackConfiguration.fromInfoPlist()
            await PTFeedbackManager.shared.configure(configuration)
            PTFeedbackPushManager.shared.registerForRemoteNotifications()

            // Opportunistic retry; failure is intentionally isolated from
            // vehicle startup and app launch.
            _ = await PTFeedbackManager.shared.flushPendingUploads()
        } catch {
            #if DEBUG
            print("[Feedback] configure skipped: \(error)")
            #endif
        }
    }
}
