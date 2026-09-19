//
//  PTFeedbackBootstrap.swift
//  CrazyDashboard
//

import Foundation

@MainActor
public enum PTFeedbackBootstrap {
    /// Safe to call more than once. Visible notification permission is never
    /// requested here.
    public static func configureFromInfoPlist() async {
        // Build74 community surfaces use the same CloudKit container but do
        // not depend on Feedback encryption being configured successfully.
        if let cloudKit = try? PTCloudKitConfiguration.feedbackFromInfoPlist() {

            // CloudKit Push 注册应该只依赖 CloudKit，
            // 不应该依赖 Feedback encryption config。
            PTFeedbackPushManager.shared.registerForRemoteNotifications()

            await PTCommunityBootstrap.configure(
                cloudKit: cloudKit
            )
        }

        do {
            let configuration =
                try PTFeedbackConfiguration.fromInfoPlist()

            let manager = PTFeedbackManager.shared

            await manager.configure(configuration)

            await PTFeedbackAttachmentManager.shared.configure(
                configuration
            )

            let records = try await manager.feedbackRecords()

            await PTFeedbackSubscriptionManager.shared
                .ensureSubscriptions(
                    feedbackIDs: records.map(\.feedbackID),
                    configuration: configuration
                )

            _ = await manager.flushPendingUploads()

            await PTFeedbackAttachmentManager.shared
                .flushPendingUploads()

            _ = await PTFeedbackNotificationCoordinator.shared
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
