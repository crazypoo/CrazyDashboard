//
//  PTFeedbackCenterViewController.swift
//  CrazyDashboard
//

import UIKit
import PooTools
import SwifterSwift
import SnapKit

@MainActor
final class PTFeedbackCenterViewController: PTBaseViewController {

    private lazy var explanationLabel: UILabel = {
        let view = UILabel()
        view.numberOfLines = 0
        view.textColor = .secondaryLabel
        view.font = .systemFont(ofSize: 14)
        view.text = PTFeedbackPresentation.text(
            "feedback_privacy_summary",
            fallback: "反馈正文会在设备端脱敏并加密后通过 CloudKit 提交。不会上传 Apple 账号、邮箱、VIN、蓝牙标识、GPS 或路线。"
        )
        return view
    }()

    private lazy var composeButton: PTBaseButton = {
        let view = PTBaseButton(type: .custom)
        view.setTitle(
            PTFeedbackPresentation.text(
                "feedback_submit",
                fallback: "提交反馈"
            ),
            for: .normal
        )
        view.setTitleColor(.white, for: .normal)
        view.setBackgroundColor(
            color: PTDashboardConfig.shared.appMainColor,
            forState: .normal
        )
        view.addActionHandlers { [weak self] _ in
            self?.navigationController?.pushViewController(
                PTFeedbackComposeViewController(),
                animated: true
            )
        }
        return view
    }()

    private lazy var historyButton: PTBaseButton = {
        let view = PTBaseButton(type: .custom)
        view.setTitle(
            PTFeedbackPresentation.text(
                "feedback_my_feedback",
                fallback: "我的反馈"
            ),
            for: .normal
        )
        view.setTitleColor(.label, for: .normal)
        view.backgroundColor = .secondarySystemBackground
        view.addActionHandlers { [weak self] _ in
            self?.navigationController?.pushViewController(
                PTMyFeedbackViewController(),
                animated: true
            )
        }
        return view
    }()

    private lazy var queueLabel: UILabel = {
        let view = UILabel()
        view.textColor = .tertiaryLabel
        view.font = .systemFont(ofSize: 12)
        return view
    }()

    override func preferredNavigationBarStyle() -> PTNavigationBarStyle {
        .solid(.systemBackground)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        pt_Title = PTFeedbackPresentation.text(
            "feedback_center_title",
            fallback: "用户反馈"
        )
        view.backgroundColor = .systemBackground

        view.addSubviews([
            explanationLabel,
            composeButton,
            historyButton,
            queueLabel
        ])

        explanationLabel.snp.makeConstraints { make in
            make.top.equalToSuperview()
                .inset(CGFloat.kNavBarHeight_Total + 24)
            make.left.right.equalToSuperview().inset(24)
        }

        composeButton.snp.makeConstraints { make in
            make.top.equalTo(explanationLabel.snp.bottom).offset(28)
            make.left.right.equalToSuperview().inset(24)
            make.height.equalTo(48)
        }

        historyButton.snp.makeConstraints { make in
            make.top.equalTo(composeButton.snp.bottom).offset(12)
            make.left.right.height.equalTo(composeButton)
        }

        queueLabel.snp.makeConstraints { make in
            make.top.equalTo(historyButton.snp.bottom).offset(16)
            make.left.right.equalTo(historyButton)
        }

        composeButton.viewCorner(radius: 10)
        historyButton.viewCorner(radius: 10)

        Task {
            await PTFeedbackBootstrap.configureFromInfoPlist()
            await refreshQueueCount()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        Task {
            await refreshQueueCount()
        }
    }

    private func refreshQueueCount() async {
        let count = await PTFeedbackManager.shared.pendingUploadCount()

        if count > 0 {
            queueLabel.text = PTFeedbackPresentation.text(
                "feedback_pending_prefix",
                fallback: "等待 CloudKit 上传"
            ) + ": \(count)"
        } else {
            queueLabel.text = nil
        }
    }
}
