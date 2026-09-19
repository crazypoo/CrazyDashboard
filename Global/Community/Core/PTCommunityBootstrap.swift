//
//  PTCommunityBootstrap.swift
//  CrazyDashboard
//

import Foundation

@MainActor
public enum PTCommunityBootstrap {
    public static func configure(
        cloudKit: PTCloudKitConfiguration
    ) async {
        await PTAnnouncementRepository.shared.configure(cloudKit)
        await PTAnnouncementManager.shared.configure(cloudKit)
        await PTFeatureSuggestionRepository.shared.configure(cloudKit)
        await PTFeatureSuggestionManager.shared.configure(cloudKit)

        await PTAnnouncementSubscriptionManager.shared
            .ensureSubscription(configuration: cloudKit)
        await PTFeatureSuggestionSubscriptionManager.shared
            .ensureSubscription(configuration: cloudKit)

        _ = try? await PTAnnouncementManager.shared.refresh(
            includeUnknownAsChange: false
        )
        _ = try? await PTFeatureSuggestionManager.shared.refresh()
    }
}
