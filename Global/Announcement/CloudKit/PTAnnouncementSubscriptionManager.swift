//
//  PTAnnouncementSubscriptionManager.swift
//  CrazyDashboard
//

@preconcurrency import CloudKit
import Foundation

public actor PTAnnouncementSubscriptionManager {
    public static let shared = PTAnnouncementSubscriptionManager()
    public static let subscriptionPrefix = "crazydashboard.announcement."
    private static let subscriptionID = subscriptionPrefix + "active"

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
            recordType: PTAnnouncementRepository.recordType,
            predicate: NSPredicate(format: "isActive == %d", 1),
            subscriptionID: Self.subscriptionID,
            options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
        )
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        _ = try? await database.save(subscription)
    }
}
