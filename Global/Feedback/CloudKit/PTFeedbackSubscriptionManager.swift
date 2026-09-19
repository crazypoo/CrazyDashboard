//
//  PTFeedbackSubscriptionManager.swift
//  CrazyDashboard
//
//  One narrow public-database query subscription per locally-owned feedback.
//  The CloudKit notification is signal-only; state is fetched afterwards.
//

@preconcurrency import CloudKit
import Foundation

public actor PTFeedbackSubscriptionManager {
    public static let shared = PTFeedbackSubscriptionManager()

    public static let subscriptionPrefix =
        "crazydashboard.feedback.status."

    private init() {}

    public func ensureSubscriptions(
        feedbackIDs: [UUID],
        configuration: PTFeedbackConfiguration
    ) async {
        for feedbackID in feedbackIDs {
            do {
                try Task.checkCancellation()
                try await ensureSubscription(
                    feedbackID: feedbackID,
                    configuration: configuration
                )
            } catch is CancellationError {
                return
            } catch {
                // Subscription recovery is best-effort. Foreground refresh
                // remains the fallback when CloudKit/APNs is unavailable.
            }
        }
    }

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

        // IMPORTANT:
        // Keep this signal-only. Apple documents that a background CloudKit
        // notification should set only shouldSendContentAvailable. The app
        // fetches the current record after receiving the signal.
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo

        _ = try await database.save(subscription)
    }
}
