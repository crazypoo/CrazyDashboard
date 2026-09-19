//
//  PTFeedbackDetailViewController.swift
//  CrazyDashboard
//  Build75: developer reply / resolution note presentation.
//

import UIKit
import PooTools
import SnapKit

@MainActor
final class PTFeedbackDetailViewController: PTMotoBaseViewController {
    private let record: PTFeedbackLocalRecord

    init(record: PTFeedbackLocalRecord) {
        self.record = record
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private lazy var scrollView: UIScrollView = UIScrollView()

    private lazy var stackView: UIStackView = {
        let view = UIStackView()
        view.axis = .vertical
        view.spacing = 14
        return view
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        pt_Title = PTFeedbackPresentation.text("feedback_detail", fallback: "反馈详情")

        view.addSubview(scrollView)
        scrollView.addSubview(stackView)
        scrollView.snp.makeConstraints { make in
            make.top.equalToSuperview().inset(CGFloat.kNavBarHeight_Total)
            make.left.right.bottom.equalToSuperview()
        }
        stackView.snp.makeConstraints { make in
            make.edges.equalTo(scrollView.contentLayoutGuide).inset(24)
            make.width.equalTo(scrollView.frameLayoutGuide).offset(-48)
        }

        stackView.addArrangedSubview(makeValueLabel(title: record.title, font: .systemFont(ofSize: 22, weight: .bold)))
        stackView.addArrangedSubview(makeValueLabel(title: PTFeedbackPresentation.statusTitle(record.status), font: .systemFont(ofSize: 16, weight: .semibold)))
        stackView.addArrangedSubview(makeValueLabel(title: PTFeedbackPresentation.moduleTitle(record.module), font: .systemFont(ofSize: 14)))
        stackView.addArrangedSubview(makeValueLabel(title: record.bodyPreview, font: .systemFont(ofSize: 15)))

        let language = Locale.preferredLanguages.first ?? "en"
        if let reply = record.localizedDeveloperReply(languageIdentifier: language), !reply.isEmpty {
            stackView.addArrangedSubview(makeDivider())
            stackView.addArrangedSubview(
                makeValueLabel(
                    title: PTFeedbackPresentation.text("feedback_developer_reply", fallback: "开发者回复"),
                    font: .systemFont(ofSize: 16, weight: .semibold)
                )
            )
            let replyLabel = makeValueLabel(title: reply, font: .systemFont(ofSize: 15))
            replyLabel.textColor = .secondaryLabel
            stackView.addArrangedSubview(replyLabel)

            if let epoch = record.developerReplyUpdatedAtEpochMilliseconds {
                let date = Date(timeIntervalSince1970: TimeInterval(epoch) / 1000)
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                let time = makeValueLabel(
                    title: formatter.string(from: date),
                    font: .systemFont(ofSize: 12)
                )
                time.textColor = .tertiaryLabel
                stackView.addArrangedSubview(time)
            }
        }

        if let resolutionBuild = record.resolutionBuild, !resolutionBuild.isEmpty {
            stackView.addArrangedSubview(
                makeValueLabel(
                    title: PTFeedbackPresentation.text("feedback_resolution_build", fallback: "解决版本") + ": \(resolutionBuild)",
                    font: .systemFont(ofSize: 14)
                )
            )
        }

        if let issueNumber = record.issueNumber {
            let button = PTBaseButton(type: .custom)
            button.setTitle("GitHub Issue #\(issueNumber)", for: .normal)
            button.setTitleColor(PTDashboardConfig.shared.appMainColor, for: .normal)
            button.addActionHandlers { _ in
                guard let url = URL(string: "https://github.com/crazypoo/CrazyDashboard/issues/\(issueNumber)") else { return }
                UIApplication.shared.open(url)
            }
            stackView.addArrangedSubview(button)
            button.snp.makeConstraints { make in make.height.equalTo(44) }
        }
    }

    private func makeValueLabel(title: String, font: UIFont) -> UILabel {
        let view = UILabel()
        view.numberOfLines = 0
        view.text = title
        view.font = font
        view.textColor = .label
        return view
    }

    private func makeDivider() -> UIView {
        let view = UIView()
        view.backgroundColor = .separator
        view.snp.makeConstraints { make in make.height.equalTo(1 / UIScreen.main.scale) }
        return view
    }
}
