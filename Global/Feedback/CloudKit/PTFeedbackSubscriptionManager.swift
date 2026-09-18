//
//  PTFeedbackSubscriptionManager.swift
//  CrazyDashboard
//
//  One narrow public-database query subscription per locally-owned feedback.
//  The push only signals "status changed"; the app then fetches CloudKit state.
//

@preconcurrency import CloudKit
import Foundation

public actor PTFeedbackSubscriptionManager {
    public static let shared = PTFeedbackSubscriptionManager()

    public static let subscriptionPrefix =
        "crazydashboard.feedback.status."

    private init() {}

    public func ensureSubscription(
        feedbackID: UUID,
        configuration: PTFeedbackConfiguration
    ) async throws {
        let container = PTCloudKitContainerProvider.makeContainer(
            identifier: configuration.cloudKit.containerIdentifier
        )
        let database = container.publicCloudDatabase

        let subscriptionID = Self.subscriptionPrefix
            + feedbackID.uuidString.lowercased()

        do {
            _ = try await database.subscription(
                for: subscriptionID
            )
            return
        } catch let error as CKError
            where error.code == .unknownItem {
            // Expected for a new feedback record.
        }

        let predicate = NSPredicate(
            format: "feedbackID == %@",
            feedbackID.uuidString.lowercased()
        )

        let subscription = CKQuerySubscription(
            recordType: PTFeedbackConfiguration.recordType,
            predicate: predicate,
            subscriptionID: subscriptionID,
            options: [.firesOnRecordUpdate]
        )

        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        notificationInfo.desiredKeys = [
            "triageState",
            "statusRevision",
            "issueNumber",
            "resolutionBuild"
        ]
        subscription.notificationInfo = notificationInfo

        _ = try await database.save(
            subscription
        )
    }
}
