//
//  PTCloudNotificationRouter.swift
//  CrazyDashboard
//
//  One app-level remote notification entry point. Additional CloudKit domains
//  can be routed here later without adding duplicate AppDelegate callbacks.
//

import UIKit

@MainActor
final class PTCloudNotificationRouter {
    static let shared = PTCloudNotificationRouter()

    private init() {}

    func handleRemoteNotification(
        _ userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        let feedback = PTFeedbackPushManager.shared

        if feedback.canHandleRemoteNotification(userInfo) {
            return await feedback.handleRemoteNotification(
                userInfo
            )
        }

        return .noData
    }
}
