//
//  PTFeedbackBootstrap.swift
//  CrazyDashboard
//

import Foundation

@MainActor
public enum PTFeedbackBootstrap {
    /// Safe to call more than once. No notification permission prompt is shown.
    public static func configureFromInfoPlist() async {
        do {
            let configuration =
                try PTFeedbackConfiguration.fromInfoPlist()

            let manager = PTFeedbackManager.shared
            await manager.configure(configuration)

            // CloudKit subscription pushes are signal-only. Registering with
            // APNs is independent from visible alert authorization.
            PTFeedbackPushManager.shared
                .registerForRemoteNotifications()

            // Restore subscriptions for already-known local records as well as
            // newly uploaded ones. Failure doesn't block startup.
            let records = try await manager.feedbackRecords()
            await PTFeedbackSubscriptionManager.shared
                .ensureSubscriptions(
                    feedbackIDs: records.map(\.feedbackID),
                    configuration: configuration
                )

            _ = await manager.flushPendingUploads()

            // Compensating sync for coalesced/missed CloudKit pushes.
            _ = await PTFeedbackNotificationCoordinator
                .shared
                .refresh(trigger: .foreground)
        } catch {
            #if DEBUG
            print(
                "[Feedback] configure skipped:",
                error.localizedDescription
            )
            #endif
        }
    }
}
