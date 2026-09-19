//
//  PTFeatureSuggestionListViewController.swift
//  CrazyDashboard
//

import UIKit
import PooTools
import SnapKit

@MainActor
final class PTFeatureSuggestionListViewController: PTBaseViewController {
    private var values: [PTFeatureSuggestion] = []
    private lazy var tableView: UITableView = {
        let view = UITableView(frame: .zero, style: .insetGrouped)
        view.dataSource = self
        view.delegate = self
        view.register(UITableViewCell.self, forCellReuseIdentifier: "suggestion")
        return view
    }()

    override func preferredNavigationBarStyle() -> PTNavigationBarStyle {
        .solid(.systemBackground)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        pt_Title = PTFeedbackPresentation.text(
            "feedback_trending", fallback: "热门反馈"
        )
        view.backgroundColor = .systemBackground
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.top.equalToSuperview().inset(CGFloat.kNavBarHeight_Total)
            make.left.right.bottom.equalToSuperview()
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reloadFromCache),
            name: .ptFeatureSuggestionsDidChange,
            object: nil
        )
        Task {
            _ = try? await PTFeatureSuggestionManager.shared.refresh()
            reloadFromCache()
        }
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func reloadFromCache() {
        Task { @MainActor in
            values = await PTFeatureSuggestionManager.shared.suggestions()
            tableView.reloadData()
        }
    }
}

extension PTFeatureSuggestionListViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        values.count
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let item = values[indexPath.row]
        let cell = tableView.dequeueReusableCell(
            withIdentifier: "suggestion",
            for: indexPath
        )
        var config = cell.defaultContentConfiguration()
        config.text = item.title
        config.secondaryText = "\(item.voteCount) votes · \(item.reportCount) reports · \(PTFeatureSuggestionPresentation.status(item.state))"
        config.secondaryTextProperties.numberOfLines = 2
        cell.contentConfiguration = config
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        navigationController?.pushViewController(
            PTFeatureSuggestionDetailViewController(suggestion: values[indexPath.row]),
            animated: true
        )
    }
}
