//
//  PTAnnouncementListViewController.swift
//  CrazyDashboard
//

import UIKit
import PooTools
import SnapKit

@MainActor
final class PTAnnouncementListViewController: PTBaseViewController {
    private var values: [PTAnnouncement] = []
    private lazy var tableView: UITableView = {
        let view = UITableView(frame: .zero, style: .insetGrouped)
        view.dataSource = self
        view.delegate = self
        view.register(UITableViewCell.self, forCellReuseIdentifier: "announcement")
        return view
    }()

    override func preferredNavigationBarStyle() -> PTNavigationBarStyle {
        .solid(.systemBackground)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        pt_Title = PTFeedbackPresentation.text(
            "feedback_announcements", fallback: "公告"
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
            name: .ptAnnouncementsDidChange,
            object: nil
        )
        Task {
            _ = try? await PTAnnouncementManager.shared.refresh(
                includeUnknownAsChange: false
            )
            reloadFromCache()
        }
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func reloadFromCache() {
        Task { @MainActor in
            values = await PTAnnouncementManager.shared.announcements()
            tableView.reloadData()
        }
    }
}

extension PTAnnouncementListViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        values.count
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: "announcement",
            for: indexPath
        )
        let item = values[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = item.localizedTitle(
            languageIdentifier: PTDashboardConfig.selectedLanguageIdentifier
        )
        config.secondaryText = String(
            item.localizedBody(
                languageIdentifier: PTDashboardConfig.selectedLanguageIdentifier
            ).prefix(120)
        )
        config.secondaryTextProperties.numberOfLines = 2
        cell.contentConfiguration = config
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        navigationController?.pushViewController(
            PTAnnouncementDetailViewController(announcement: values[indexPath.row]),
            animated: true
        )
    }
}
