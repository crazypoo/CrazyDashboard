//
//  PTCommunityLocalNotificationManager.swift
//  CrazyDashboard
//

import Foundation
import UIKit
import UserNotifications

@MainActor
public final class PTCommunityLocalNotificationManager {
    public static let shared = PTCommunityLocalNotificationManager()
    public static let announcementNotificationKind = "community_announcement"

    private let center = UNUserNotificationCenter.current()
    private init() {}

    public func deliverAnnouncements(_ values: [PTAnnouncement]) async {
        guard
            !values.isEmpty,
            UIApplication.shared.applicationState != .active
        else { return }

        let settings = await center.notificationSettings()
        guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else {
            return
        }

        guard let item = values.sorted(by: {
            $0.publishedAtEpochMilliseconds > $1.publishedAtEpochMilliseconds
        }).first else { return }

        let language = PTDashboardConfig.selectedLanguageIdentifier
        let content = UNMutableNotificationContent()
        content.title = item.localizedTitle(languageIdentifier: language)
        content.body = String(
            item.localizedBody(languageIdentifier: language).prefix(180)
        )
        content.sound = .default
        content.userInfo = [
            "pt_notification_kind": Self.announcementNotificationKind,
            "pt_announcement_id": item.announcementID
        ]

        let request = UNNotificationRequest(
            identifier: "crazydashboard.announcement.\(item.announcementID).\(item.revision)",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }
}
