//
//  PTCommunityPushCoordinator.swift
//  CrazyDashboard
//

@preconcurrency import CloudKit
import Foundation
import UIKit

@MainActor
final class PTCommunityPushCoordinator {
    static let shared = PTCommunityPushCoordinator()
    private init() {}

    func canHandleRemoteNotification(_ userInfo: [AnyHashable: Any]) -> Bool {
        guard let id = CKNotification(
            fromRemoteNotificationDictionary: userInfo
        )?.subscriptionID else { return false }
        return id.hasPrefix(PTAnnouncementSubscriptionManager.subscriptionPrefix)
            || id.hasPrefix(PTFeatureSuggestionSubscriptionManager.subscriptionPrefix)
    }

    func handleRemoteNotification(
        _ userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        guard let id = CKNotification(
            fromRemoteNotificationDictionary: userInfo
        )?.subscriptionID else { return .noData }

        if id.hasPrefix(PTAnnouncementSubscriptionManager.subscriptionPrefix) {
            do {
                let changed = try await PTAnnouncementManager.shared.refresh(
                    includeUnknownAsChange: true
                )
                await PTCommunityLocalNotificationManager.shared
                    .deliverAnnouncements(changed)
                return changed.isEmpty ? .noData : .newData
            } catch {
                return .failed
            }
        }

        if id.hasPrefix(PTFeatureSuggestionSubscriptionManager.subscriptionPrefix) {
            do {
                _ = try await PTFeatureSuggestionManager.shared.refresh()
                return .newData
            } catch {
                return .failed
            }
        }
        return .noData
    }

    func refreshOnForeground() async {
        _ = try? await PTAnnouncementManager.shared.refresh(
            includeUnknownAsChange: false
        )
        _ = try? await PTFeatureSuggestionManager.shared.refresh()
    }
}
