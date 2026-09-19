//
//  PTFeatureSuggestionDetailViewController.swift
//  CrazyDashboard
//

import UIKit
import PooTools
import SnapKit
import SwifterSwift

@MainActor
final class PTFeatureSuggestionDetailViewController: PTBaseViewController {
    private var suggestion: PTFeatureSuggestion
    private var voted = false

    private lazy var summaryLabel: UILabel = {
        let view = UILabel()
        view.numberOfLines = 0
        view.textColor = .label
        view.font = .systemFont(ofSize: 16)
        return view
    }()

    private lazy var metaLabel: UILabel = {
        let view = UILabel()
        view.numberOfLines = 0
        view.textColor = .secondaryLabel
        view.font = .systemFont(ofSize: 13)
        return view
    }()

    private lazy var voteButton: PTBaseButton = {
        let view = PTBaseButton(type: .custom)
        view.setTitleColor(.white, for: .normal)
        view.setBackgroundColor(
            color: PTDashboardConfig.shared.appMainColor,
            forState: .normal
        )
        view.viewCorner(radius: 10)
        view.addActionHandlers { [weak self] _ in
            self?.toggleVote()
        }
        return view
    }()

    init(suggestion: PTFeatureSuggestion) {
        self.suggestion = suggestion
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func preferredNavigationBarStyle() -> PTNavigationBarStyle {
        .solid(.systemBackground)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        pt_Title = suggestion.title
        view.backgroundColor = .systemBackground
        view.addSubviews([summaryLabel, metaLabel, voteButton])
        summaryLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().inset(CGFloat.kNavBarHeight_Total + 24)
            make.left.right.equalToSuperview().inset(24)
        }
        metaLabel.snp.makeConstraints { make in
            make.top.equalTo(summaryLabel.snp.bottom).offset(18)
            make.left.right.equalTo(summaryLabel)
        }
        voteButton.snp.makeConstraints { make in
            make.top.equalTo(metaLabel.snp.bottom).offset(24)
            make.left.right.equalTo(summaryLabel)
            make.height.equalTo(48)
        }
        refreshView()
        Task {
            voted = (try? await PTFeatureSuggestionManager.shared.isVoted(
                suggestionID: suggestion.suggestionID
            )) ?? false
            refreshView()
        }
    }

    private func refreshView() {
        summaryLabel.text = suggestion.summary
        metaLabel.text = "\(suggestion.module) · \(suggestion.voteCount) votes · \(suggestion.reportCount) reports · \(PTFeatureSuggestionPresentation.status(suggestion.state))"
        voteButton.isHidden = !suggestion.isVotingOpen
        voteButton.setTitle(
            voted
                ? PTFeedbackPresentation.text("feedback_vote_remove", fallback: "取消我也遇到了")
                : PTFeedbackPresentation.text("feedback_vote_add", fallback: "我也遇到了 / +1"),
            for: .normal
        )
    }

    private func toggleVote() {
        guard suggestion.isVotingOpen else { return }
        voteButton.isEnabled = false
        Task {
            do {
                try await PTFeatureSuggestionManager.shared.setVoted(
                    !voted,
                    suggestionID: suggestion.suggestionID
                )
                voted.toggle()
            } catch {
                // Keep UI state unchanged; CloudKit remains source of truth.
            }
            voteButton.isEnabled = true
            refreshView()
        }
    }
}
