//
//  PTRoadbookViewController.swift
//  CrazyDashboard
//
//  EN: Minimal UIKit management screen for imported ADV Roadbooks.
//  ES: Pantalla UIKit mínima para gestionar Roadbooks ADV importados.
//  中文：用于管理导入 ADV Roadbook 的轻量 UIKit 页面。
//

import UIKit
import UniformTypeIdentifiers

@MainActor
final class PTRoadbookViewController: UITableViewController, UIDocumentPickerDelegate {
    private let manager = PTCustomRouteManager.shared
    private var roadbooks: [PTRoadbook] = []
    private var loadTask: Task<Void, Never>?

    private let cellIdentifier = "PTRoadbookCell"

    override func viewDidLoad() {
        super.viewDidLoad()
        title = PTDashboardConfig.languageFunc(text: "roadbook_title")
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(close)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(importGPX)
        )

        tableView.rowHeight = 68
        tableView.tableFooterView = UIView(frame: .zero)
        tableView.backgroundColor = .systemGroupedBackground
        tableView.refreshControl = UIRefreshControl()
        tableView.refreshControl?.addTarget(self, action: #selector(refresh), for: .valueChanged)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshVisibleState),
            name: PTRoadbookStateDidChange,
            object: manager
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadRoadbooks()
    }

    @MainActor
    deinit {
        loadTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func close() {
        if let navigationController, navigationController.presentingViewController != nil {
            dismiss(animated: true)
        } else {
            navigationController?.popViewController(animated: true)
        }
    }

    @objc private func refresh() {
        reloadRoadbooks()
    }

    @objc private func refreshVisibleState() {
        tableView.reloadData()
    }

    private func reloadRoadbooks() {
        loadTask?.cancel()
        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                self.roadbooks = try await self.manager.loadRoadbooks()
                self.tableView.reloadData()
            } catch {
                self.showError(error)
            }
            self.tableView.refreshControl?.endRefreshing()
        }
    }

    @objc private func importGPX() {
        let contentType = UTType(filenameExtension: "gpx") ?? .data
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [contentType], asCopy: true)
        picker.delegate = self
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController,
                        didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let data = try await Task.detached(priority: .utility) {
                    try Data(contentsOf: url, options: .mappedIfSafe)
                }.value
                _ = try await self.manager.importRoadbook(
                    gpxData: data,
                    suggestedName: url.deletingPathExtension().lastPathComponent
                )
                self.roadbooks = try await self.manager.loadRoadbooks()
                self.tableView.reloadData()
            } catch {
                self.showError(error)
            }
        }
    }

    override func tableView(_ tableView: UITableView,
                            numberOfRowsInSection section: Int) -> Int {
        roadbooks.count
    }

    override func tableView(_ tableView: UITableView,
                            cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier)
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: cellIdentifier)
        let roadbook = roadbooks[indexPath.row]
        let active = manager.activeRoadbook?.id == roadbook.id && manager.isSessionActive
        let waypointText = PTDashboardConfig.language(
            key: "roadbook_waypoint_count",
            roadbook.waypoints.count
        )
        let stateText = active ? " · \(stateTitle(manager.state))" : ""
        cell.textLabel?.text = roadbook.name
        cell.textLabel?.font = .preferredFont(forTextStyle: .headline)
        cell.detailTextLabel?.text = waypointText + stateText
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView,
                            didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        presentActions(for: roadbooks[indexPath.row], sourceView: tableView.cellForRow(at: indexPath))
    }

    private func presentActions(for roadbook: PTRoadbook, sourceView: UIView?) {
        let active = manager.activeRoadbook?.id == roadbook.id && manager.isSessionActive
        let alert = UIAlertController(
            title: roadbook.name,
            message: PTDashboardConfig.language(
                key: "roadbook_waypoint_count",
                roadbook.waypoints.count
            ),
            preferredStyle: .actionSheet
        )

        if active {
            let title = manager.state == .paused
                ? PTDashboardConfig.languageFunc(text: "roadbook_resume")
                : PTDashboardConfig.languageFunc(text: "roadbook_pause")
            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                if self?.manager.state == .paused {
                    self?.manager.resumeRoadbook()
                } else {
                    self?.manager.pauseRoadbook()
                }
            })
            alert.addAction(UIAlertAction(
                title: PTDashboardConfig.languageFunc(text: "roadbook_previous"),
                style: .default
            ) { [weak self] _ in
                self?.manager.goToPreviousWaypoint()
            })
            alert.addAction(UIAlertAction(
                title: PTDashboardConfig.languageFunc(text: "roadbook_next"),
                style: .default
            ) { [weak self] _ in
                self?.manager.skipToNextWaypoint()
            })
            alert.addAction(UIAlertAction(
                title: PTDashboardConfig.languageFunc(text: "roadbook_stop"),
                style: .destructive
            ) { [weak self] _ in
                self?.manager.stopCruise()
            })
        } else {
            alert.addAction(UIAlertAction(
                title: PTDashboardConfig.languageFunc(text: "roadbook_start"),
                style: .default
            ) { [weak self] _ in
                do {
                    try self?.manager.startRoadbook(roadbook)
                    self?.dismiss(animated: true)
                } catch {
                    self?.showError(error)
                }
            })
        }

        alert.addAction(UIAlertAction(
            title: PTDashboardConfig.languageFunc(text: "roadbook_view_waypoints"),
            style: .default
        ) { [weak self] _ in
            self?.showWaypoints(roadbook)
        })
        alert.addAction(UIAlertAction(
            title: PTDashboardConfig.languageFunc(text: "roadbook_share"),
            style: .default
        ) { [weak self] _ in
            self?.share(roadbook)
        })

        if !active {
            alert.addAction(UIAlertAction(
                title: PTDashboardConfig.languageFunc(text: "roadbook_delete"),
                style: .destructive
            ) { [weak self] _ in
                self?.confirmDelete(roadbook)
            })
        }
        alert.addAction(UIAlertAction(
            title: PTDashboardConfig.languageFunc(text: "button_cancel"),
            style: .cancel
        ))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = sourceView ?? view
            popover.sourceRect = sourceView?.bounds ?? view.bounds
        }
        present(alert, animated: true)
    }

    private func showWaypoints(_ roadbook: PTRoadbook) {
        let maxVisible = 24
        var lines = roadbook.waypoints.prefix(maxVisible).enumerated().map { index, waypoint in
            "\(index + 1). \(waypoint.instruction) (\(String(format: "%.5f", waypoint.latitude)), \(String(format: "%.5f", waypoint.longitude)))"
        }
        if roadbook.waypoints.count > maxVisible {
            lines.append("…")
        }
        let alert = UIAlertController(
            title: PTDashboardConfig.languageFunc(text: "roadbook_view_waypoints"),
            message: lines.joined(separator: "\n"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(
            title: PTDashboardConfig.languageFunc(text: "button_confirm"),
            style: .default
        ))
        present(alert, animated: true)
    }

    private func share(_ roadbook: PTRoadbook) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let fileName: String
                if let sourceFileName = roadbook.sourceFileName {
                    fileName = sourceFileName
                } else {
                    fileName = try await PTGPXRecorder.shared.exportRoadbookAsync(from: roadbook)
                        ?? "Roadbook.gpx"
                }
                let fileURL = try await PTDataPersistenceActor.shared.ensureLocalFileURL(fileName: fileName)
                let activity = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
                if let popover = activity.popoverPresentationController {
                    popover.sourceView = self.view
                    popover.sourceRect = CGRect(x: self.view.bounds.midX,
                                                y: self.view.bounds.midY,
                                                width: 1,
                                                height: 1)
                }
                self.present(activity, animated: true)
            } catch {
                self.showError(error)
            }
        }
    }

    private func confirmDelete(_ roadbook: PTRoadbook) {
        let alert = UIAlertController(
            title: PTDashboardConfig.languageFunc(text: "roadbook_delete"),
            message: PTDashboardConfig.languageFunc(text: "roadbook_delete_confirm"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(
            title: PTDashboardConfig.languageFunc(text: "roadbook_delete"),
            style: .destructive
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try await self.manager.deleteRoadbook(id: roadbook.id)
                    self.roadbooks = try await self.manager.loadRoadbooks()
                    self.tableView.reloadData()
                } catch {
                    self.showError(error)
                }
            }
        })
        alert.addAction(UIAlertAction(
            title: PTDashboardConfig.languageFunc(text: "button_cancel"),
            style: .cancel
        ))
        present(alert, animated: true)
    }

    private func stateTitle(_ state: PTRoadbookState) -> String {
        switch state {
        case .active: return PTDashboardConfig.languageFunc(text: "roadbook_status_active")
        case .paused: return PTDashboardConfig.languageFunc(text: "roadbook_status_paused")
        case .offRoute: return PTDashboardConfig.languageFunc(text: "roadbook_status_off_route")
        case .completed: return PTDashboardConfig.languageFunc(text: "roadbook_status_completed")
        case .idle: return PTDashboardConfig.languageFunc(text: "roadbook_status_ready")
        }
    }

    private func showError(_ error: Error) {
        guard viewIfLoaded?.window != nil else { return }
        let alert = UIAlertController(
            title: PTDashboardConfig.languageFunc(text: "alert_title"),
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(
            title: PTDashboardConfig.languageFunc(text: "button_confirm"),
            style: .default
        ))
        present(alert, animated: true)
    }
}
