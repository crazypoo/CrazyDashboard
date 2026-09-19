//
//  PTMyFeedbackViewController.swift
//  CrazyDashboard
//

import UIKit
import PooTools
import SwifterSwift
import SnapKit

@MainActor
final class PTMyFeedbackViewController: PTMotoBaseViewController {

    private var records: [PTFeedbackLocalRecord] = []

    private lazy var tableView: UITableView = {
        let view = UITableView(
            frame: .zero,
            style: .insetGrouped
        )
        view.backgroundColor = .systemBackground
        view.register(
            UITableViewCell.self,
            forCellReuseIdentifier: "FeedbackCell"
        )
        view.dataSource = self
        view.delegate = self

        let refresh = UIRefreshControl()
        refresh.addTarget(
            self,
            action: #selector(refreshRequested),
            for: .valueChanged
        )
        view.refreshControl = refresh

        return view
    }()

    private lazy var emptyLabel: UILabel = {
        let view = UILabel()
        view.numberOfLines = 0
        view.textAlignment = .center
        view.textColor = .secondaryLabel
        view.text = PTFeedbackPresentation.text(
            "feedback_empty",
            fallback: "还没有提交过反馈"
        )
        return view
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        pt_Title = PTFeedbackPresentation.text(
            "feedback_my_feedback",
            fallback: "我的反馈"
        )
        
        view.addSubviews([
            tableView,
            emptyLabel
        ])

        tableView.snp.makeConstraints { make in
            make.top.equalToSuperview()
                .inset(CGFloat.kNavBarHeight_Total)
            make.left.right.bottom.equalToSuperview()
        }

        emptyLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.left.right.equalToSuperview().inset(40)
        }

        Task {
            await loadLocalThenRefreshRemote()
        }
    }

    @objc
    private func refreshRequested() {
        Task {
            await loadLocalThenRefreshRemote()
        }
    }

    private func loadLocalThenRefreshRemote() async {
        if let local = try? await PTFeedbackManager.shared.feedbackRecords() {
            records = local
            updateUI()
        }

        do {
            records = try await PTFeedbackManager.shared.refreshStatuses()
        } catch {
            // Local history remains usable when CloudKit is unavailable.
        }

        tableView.refreshControl?.endRefreshing()
        updateUI()
    }

    private func updateUI() {
        emptyLabel.isHidden = !records.isEmpty
        tableView.isHidden = records.isEmpty
        tableView.reloadData()
    }
}

extension PTMyFeedbackViewController: UITableViewDataSource {
    func tableView(
        _ tableView: UITableView,
        numberOfRowsInSection section: Int
    ) -> Int {
        records.count
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: "FeedbackCell",
            for: indexPath
        )

        let record = records[indexPath.row]

        var content = cell.defaultContentConfiguration()
        content.text = record.title

        let status = PTFeedbackPresentation.statusTitle(
            record.status
        )
        let module = PTFeedbackPresentation.moduleTitle(
            record.module
        )
        content.secondaryText = "\(status) · \(module)"
        content.secondaryTextProperties.color = .secondaryLabel

        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator

        return cell
    }
}

extension PTMyFeedbackViewController: UITableViewDelegate {
    func tableView(
        _ tableView: UITableView,
        didSelectRowAt indexPath: IndexPath
    ) {
        tableView.deselectRow(
            at: indexPath,
            animated: true
        )

        let controller = PTFeedbackDetailViewController(
            record: records[indexPath.row]
        )

        navigationController?.pushViewController(
            controller,
            animated: true
        )
    }
}
