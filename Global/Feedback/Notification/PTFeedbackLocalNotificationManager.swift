//
//  PTFeedbackLocalNotificationManager.swift
//  CrazyDashboard
//
//  CloudKit sends a silent signal. User-visible feedback notifications are
//  generated locally only after the latest state is fetched and compared.
//

import Foundation
import UIKit
import UserNotifications

@MainActor
public final class PTFeedbackLocalNotificationManager {
    public static let shared = PTFeedbackLocalNotificationManager()

    public static let notificationKind = "feedback"

    private let center = UNUserNotificationCenter.current()

    private init() {}

    public func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// Call this only from an explicit Feedback UI action. CrazyDashboard's
    /// existing notification policy intentionally doesn't prompt at launch.
    @discardableResult
    public func requestVisibleAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(
                options: [.alert, .badge, .sound]
            )
        } catch {
            return false
        }
    }

    public func deliverStatusChanges(
        _ changes: [PTFeedbackStatusChange]
    ) async {
        guard !changes.isEmpty,
              UIApplication.shared.applicationState != .active else {
            return
        }

        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            break
        case .denied, .notDetermined:
            return
        @unknown default:
            return
        }

        let meaningful = changes.filter {
            Self.shouldNotify(status: $0.current.status)
        }

        guard !meaningful.isEmpty else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = PTFeedbackPresentation.text(
            "feedback_notification_title",
            fallback: "CrazyDashboard 反馈状态有更新"
        )

        if meaningful.count == 1,
           let change = meaningful.first {
            content.body =
                PTFeedbackPresentation.text(
                    "feedback_notification_status_prefix",
                    fallback: "你的反馈状态："
                )
                + PTFeedbackPresentation.statusTitle(
                    change.current.status
                )

            content.userInfo = [
                "pt_notification_kind": Self.notificationKind,
                "pt_feedback_id":
                    change.feedbackID.uuidString.lowercased()
            ]
        } else {
            content.body = String(
                format: PTFeedbackPresentation.text(
                    "feedback_notification_multiple",
                    fallback: "有 %d 条反馈状态发生变化。"
                ),
                meaningful.count
            )
            content.userInfo = [
                "pt_notification_kind": Self.notificationKind
            ]
        }

        content.sound = .default

        let request = UNNotificationRequest(
            identifier:
                "crazydashboard.feedback.status."
                + UUID().uuidString.lowercased(),
            content: content,
            trigger: nil
        )

        try? await center.add(request)
    }

    private static func shouldNotify(
        status: PTFeedbackStatus
    ) -> Bool {
        switch status {
        case .reviewing,
             .published,
             .planned,
             .resolved,
             .declined,
             .duplicate,
             .rejected:
            return true
        case .submitted,
             .accepted,
             .grouped:
            return false
        }
    }
}
