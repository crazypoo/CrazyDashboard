//
//  PTCloudNotificationRouter.swift
//  CrazyDashboard
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
            return await feedback.handleRemoteNotification(userInfo)
        }
        let community = PTCommunityPushCoordinator.shared
        if community.canHandleRemoteNotification(userInfo) {
            return await community.handleRemoteNotification(userInfo)
        }
        return .noData
    }
}
