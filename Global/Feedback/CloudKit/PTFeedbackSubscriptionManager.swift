//
//  PTFeedbackSubscriptionManager.swift
//  CrazyDashboard
//
//  Signal-only CloudKit subscriptions. State is fetched after wake-up.
//

@preconcurrency import CloudKit
import Foundation

public actor PTFeedbackSubscriptionManager {
    public static let shared = PTFeedbackSubscriptionManager()
    public static let subscriptionPrefix = "crazydashboard.feedback.status."
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
        let subscriptionID = Self.subscriptionPrefix + feedbackID.uuidString.lowercased()
        do {
            _ = try await database.subscription(for: subscriptionID)
            return
        } catch let error as CKError where error.code == .unknownItem {
        }
        let subscription = CKQuerySubscription(
            recordType: PTFeedbackConfiguration.recordType,
            predicate: NSPredicate(
                format: "feedbackID == %@",
                feedbackID.uuidString.lowercased()
            ),
            subscriptionID: subscriptionID,
            options: [.firesOnRecordUpdate]
        )
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        _ = try await database.save(subscription)
    }
}
