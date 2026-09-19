//
//  PTFeatureSuggestionSubscriptionManager.swift
//  CrazyDashboard
//

@preconcurrency import CloudKit
import Foundation

public actor PTFeatureSuggestionSubscriptionManager {
    public static let shared = PTFeatureSuggestionSubscriptionManager()
    public static let subscriptionPrefix = "crazydashboard.suggestion."
    private static let subscriptionID = subscriptionPrefix + "visible"

    private init() {}

    public func ensureSubscription(configuration: PTCloudKitConfiguration) async {
        let container = PTCloudKitContainerProvider.makeContainer(
            identifier: configuration.containerIdentifier
        )
        let database = container.publicCloudDatabase
        do {
            _ = try await database.subscription(for: Self.subscriptionID)
            return
        } catch let error as CKError where error.code == .unknownItem {
        } catch {
            return
        }

        let subscription = CKQuerySubscription(
            recordType: PTFeatureSuggestionRepository.recordType,
            predicate: NSPredicate(format: "isVisible == %d", 1),
            subscriptionID: Self.subscriptionID,
            options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
        )
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        _ = try? await database.save(subscription)
    }
}
