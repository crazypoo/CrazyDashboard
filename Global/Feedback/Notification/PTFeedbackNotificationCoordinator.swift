//
//  PTFeedbackNotificationCoordinator.swift
//  CrazyDashboard
//

import Foundation
import UIKit

nonisolated public enum PTFeedbackRefreshTrigger: Sendable {
    case cloudKitPush
    case foreground
    case manual
}

public actor PTFeedbackNotificationCoordinator {
    public static let shared = PTFeedbackNotificationCoordinator()

    private init() {}

    public func refresh(
        trigger: PTFeedbackRefreshTrigger
    ) async -> UIBackgroundFetchResult {
        do {
            let changes =
                try await PTFeedbackManager.shared
                    .refreshStatusChanges()

            guard !changes.isEmpty else {
                return .noData
            }

            await MainActor.run {
                NotificationCenter.default.post(
                    name: .ptFeedbackStatusDidChange,
                    object: changes
                )
            }

            if trigger == .cloudKitPush {
                await PTFeedbackLocalNotificationManager
                    .shared
                    .deliverStatusChanges(changes)
            }

            return .newData
        } catch {
            #if DEBUG
            print(
                "[Feedback] status refresh failed:",
                error.localizedDescription
            )
            #endif
            return .failed
        }
    }
}
