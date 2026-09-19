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

    func canHandleRemoteNotification(
        _ userInfo: [AnyHashable: Any]
    ) -> Bool {
        guard let notification = CKNotification(
            fromRemoteNotificationDictionary: userInfo
        ),
              let subscriptionID = notification.subscriptionID else {
            return false
        }

        return subscriptionID.hasPrefix(
            PTFeedbackSubscriptionManager.subscriptionPrefix
        )
    }

    func handleRemoteNotification(
        _ userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        guard canHandleRemoteNotification(userInfo) else {
            return .noData
        }

        return await PTFeedbackNotificationCoordinator
            .shared
            .refresh(trigger: .cloudKitPush)
    }

    func refreshOnForeground() async {
        _ = await PTFeedbackNotificationCoordinator
            .shared
            .refresh(trigger: .foreground)
    }
}
