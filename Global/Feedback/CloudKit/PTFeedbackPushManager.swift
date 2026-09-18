//
//  PTFeedbackPushManager.swift
//  CrazyDashboard
//

@preconcurrency import CloudKit
import Foundation
import UIKit

extension Notification.Name {
    static let ptFeedbackStatusDidChange = Notification.Name(
        "CrazyDashboard.PTFeedbackStatusDidChange"
    )
}

@MainActor
final class PTFeedbackPushManager {
    static let shared = PTFeedbackPushManager()

    private init() {}

    func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// Call from UIApplicationDelegate's remote-notification callback.
    /// Returns true only for this module's CloudKit subscription.
    @discardableResult
    func handleRemoteNotification(
        _ userInfo: [AnyHashable: Any]
    ) -> Bool {
        guard let notification = CKNotification(
            fromRemoteNotificationDictionary: userInfo
        ),
              let subscriptionID = notification.subscriptionID,
              subscriptionID.hasPrefix(
                PTFeedbackSubscriptionManager.subscriptionPrefix
              ) else {
            return false
        }

        Task {
            do {
                let records = try await PTFeedbackManager.shared.refreshStatuses()
                NotificationCenter.default.post(
                    name: .ptFeedbackStatusDidChange,
                    object: records
                )
            } catch {
                // Push is only a change signal. Foreground refresh remains
                // the fallback and the source of truth stays CloudKit.
            }
        }

        return true
    }
}
