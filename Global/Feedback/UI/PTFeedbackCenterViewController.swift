//
//  PTFeedbackCenterViewController.swift
//  CrazyDashboard
//

import UIKit
import UserNotifications
import PooTools
import SwifterSwift
import SnapKit

@MainActor
final class PTFeedbackCenterViewController: PTMotoBaseViewController {
    private lazy var explanationLabel: UILabel = {
        let view = UILabel()
        view.numberOfLines = 0
        view.textColor = .secondaryLabel
        view.font = .systemFont(ofSize: 14)
        view.text = PTFeedbackPresentation.text(
            "feedback_privacy_summary",
            fallback: "反馈正文会在设备端脱敏并加密后通过 CloudKit 提交。公开的建议/Issue 只来自服务器再次脱敏后的人工发布内容。"
        )
        return view
    }()

    private lazy var stack = UIStackView()
    private lazy var composeButton = makeButton(
        title: PTFeedbackPresentation.text("feedback_submit", fallback: "提交反馈"),
        primary: true
    ) { [weak self] in
        self?.navigationController?.pushViewController(
            PTFeedbackComposeViewController(), animated: true
        )
    }
    private lazy var historyButton = makeButton(
        title: PTFeedbackPresentation.text("feedback_my_feedback", fallback: "我的反馈")
    ) { [weak self] in
        self?.navigationController?.pushViewController(
            PTMyFeedbackViewController(), animated: true
        )
    }
    private lazy var trendingButton = makeButton(
        title: PTFeedbackPresentation.text("feedback_trending", fallback: "热门反馈 / 投票")
    ) { [weak self] in
        self?.navigationController?.pushViewController(
            PTFeatureSuggestionListViewController(), animated: true
        )
    }
    private lazy var announcementButton = makeButton(
        title: PTFeedbackPresentation.text("feedback_announcements", fallback: "公告")
    ) { [weak self] in
        self?.navigationController?.pushViewController(
            PTAnnouncementListViewController(), animated: true
        )
    }
    private lazy var notificationButton = makeButton(title: "") { [weak self] in
        guard let self else { return }
        Task { await self.handleNotificationAction() }
    }
    private lazy var queueLabel: UILabel = {
        let view = UILabel()
        view.textColor = .tertiaryLabel
        view.font = .systemFont(ofSize: 12)
        view.numberOfLines = 0
        return view
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        pt_Title = PTFeedbackPresentation.text("feedback_center_title", fallback: "用户反馈")
        stack.axis = .vertical
        stack.spacing = 12
        stack.distribution = .fillEqually
        [composeButton, historyButton, trendingButton, announcementButton, notificationButton]
            .forEach(stack.addArrangedSubview)
        view.addSubviews([explanationLabel, stack, queueLabel])
        explanationLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().inset(CGFloat.kNavBarHeight_Total + 24)
            make.left.right.equalToSuperview().inset(24)
        }
        stack.snp.makeConstraints { make in
            make.top.equalTo(explanationLabel.snp.bottom).offset(24)
            make.left.right.equalToSuperview().inset(24)
            make.height.equalTo(288)
        }
        queueLabel.snp.makeConstraints { make in
            make.top.equalTo(stack.snp.bottom).offset(16)
            make.left.right.equalTo(stack)
        }
        Task {
            await PTFeedbackBootstrap.configureFromInfoPlist()
            await refreshState()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Task { await refreshState() }
    }

    private func makeButton(
        title: String,
        primary: Bool = false,
        action: @escaping @MainActor () -> Void
    ) -> PTBaseButton {
        let view = PTBaseButton(type: .custom)
        view.setTitle(title, for: .normal)
        view.setTitleColor(.white, for: .normal)
        view.viewCorner(radius: 10)
        view.addActionHandlers { _ in action() }
        return view
    }

    private func refreshState() async {
        let feedbackCount = await PTFeedbackManager.shared.pendingUploadCount()
        let attachmentCount = await PTFeedbackAttachmentManager.shared.pendingCount()
        let total = feedbackCount + attachmentCount
        queueLabel.text = total > 0
            ? PTFeedbackPresentation.text("feedback_pending_prefix", fallback: "等待 CloudKit 上传") + ": \(total)"
            : nil
        await refreshNotificationButton()
    }

    private func refreshNotificationButton() async {
        let status = await PTFeedbackLocalNotificationManager.shared.authorizationStatus()
        let title: String
        switch status {
        case .authorized, .provisional, .ephemeral:
            title = PTFeedbackPresentation.text("feedback_notifications_enabled", fallback: "反馈与公告通知：已开启")
        case .denied:
            title = PTFeedbackPresentation.text("feedback_notifications_denied", fallback: "反馈与公告通知：前往系统设置开启")
        case .notDetermined:
            title = PTFeedbackPresentation.text("feedback_notifications_enable", fallback: "开启反馈与公告通知")
        @unknown default:
            title = PTFeedbackPresentation.text("feedback_notifications_enable", fallback: "开启反馈与公告通知")
        }
        notificationButton.setTitle(title, for: .normal)
    }

    private func handleNotificationAction() async {
        let manager = PTFeedbackLocalNotificationManager.shared
        let status = await manager.authorizationStatus()
        switch status {
        case .notDetermined:
            _ = await manager.requestVisibleAuthorization()
        case .denied:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                await UIApplication.shared.open(url)
            }
        case .authorized, .provisional, .ephemeral:
            break
        @unknown default:
            break
        }
        await refreshNotificationButton()
    }
}
