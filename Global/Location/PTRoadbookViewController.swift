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
    private var weatherTask: Task<Void, Never>?

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
        navigationItem.leftBarButtonItems = [
            UIBarButtonItem(
                title: PTDashboardConfig.languageFunc(text: "roadbook_create"),
                style: .plain,
                target: self,
                action: #selector(createRoadbook)
            ),
            navigationItem.leftBarButtonItem
        ].compactMap { $0 }

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
        weatherTask?.cancel()
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

    @objc private func createRoadbook() {
        navigationController?.pushViewController(PTRoadbookEditorViewController(), animated: true)
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
            title: PTDashboardConfig.languageFunc(text: "roadbook_edit"),
            style: .default
        ) { [weak self] _ in
            self?.navigationController?.pushViewController(
                PTRoadbookEditorViewController(roadbook: roadbook),
                animated: true
            )
        })

        alert.addAction(UIAlertAction(
            title: PTDashboardConfig.languageFunc(text: "roadbook_view_waypoints"),
            style: .default
        ) { [weak self] _ in
            self?.showWaypoints(roadbook)
        })
        alert.addAction(UIAlertAction(
            title: PTDashboardConfig.languageFunc(text: "route_weather_risk"),
            style: .default
        ) { [weak self] _ in
            self?.showWeatherRisk(for: roadbook)
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

    // EN: Weather analysis is cancellable so leaving the Roadbook screen never keeps requests alive.
    // ES: El análisis meteorológico se puede cancelar para que salir de Roadbook no mantenga solicitudes activas.
    // 中文：天气分析支持取消，离开 Roadbook 页面后不会继续占用请求。
    private func showWeatherRisk(for roadbook: PTRoadbook) {
        weatherTask?.cancel()

        let loadingAlert = UIAlertController(
            title: PTDashboardConfig.languageFunc(text: "route_weather_risk"),
            message: PTDashboardConfig.languageFunc(text: "route_weather_loading"),
            preferredStyle: .alert
        )
        loadingAlert.addAction(UIAlertAction(
            title: PTDashboardConfig.languageFunc(text: "button_cancel"),
            style: .cancel
        ) { [weak self, weak loadingAlert] _ in
            self?.weatherTask?.cancel()
            loadingAlert?.dismiss(animated: true)
        })
        present(loadingAlert, animated: true)

        weatherTask = Task { @MainActor [weak self, weak loadingAlert] in
            guard let self else { return }
            do {
                let report = try await PTRouteWeatherRiskService.shared.analyze(roadbook: roadbook)
                guard !Task.isCancelled else { return }
                loadingAlert?.dismiss(animated: true) {
                    self.showWeatherReport(report)
                }
            } catch {
                guard !Task.isCancelled else { return }
                loadingAlert?.dismiss(animated: true) {
                    self.showError(error)
                }
            }
        }
    }

    private func showWeatherReport(_ report: PTRouteWeatherRiskReport) {
        let riskyPoints = report.points.filter { $0.level != .clear }.prefix(5)
        var lines = [
            PTDashboardConfig.language(key: "route_weather_worst", riskLevelTitle(report.worstLevel)),
            PTDashboardConfig.language(key: "route_weather_risky_points", report.riskyPointCount)
        ]

        if riskyPoints.isEmpty {
            lines.append(PTDashboardConfig.languageFunc(text: "route_weather_no_risk"))
        } else {
            lines.append(contentsOf: riskyPoints.map { point in
                let coordinate = String(
                    format: "%.4f, %.4f",
                    point.sample.coordinate.latitude,
                    point.sample.coordinate.longitude
                )
                let factors = point.factors.map(factorTitle).joined(separator: ", ")
                return "\(riskLevelTitle(point.level)) · \(coordinate) · \(factors)"
            })
        }

        let alert = UIAlertController(
            title: PTDashboardConfig.languageFunc(text: "route_weather_report"),
            message: lines.joined(separator: "\n"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(
            title: PTDashboardConfig.languageFunc(text: "button_confirm"),
            style: .default
        ))
        present(alert, animated: true)
    }

    private func riskLevelTitle(_ level: PTRouteWeatherRiskLevel) -> String {
        switch level {
        case .clear: return PTDashboardConfig.languageFunc(text: "route_weather_clear")
        case .caution: return PTDashboardConfig.languageFunc(text: "route_weather_caution")
        case .hazardous: return PTDashboardConfig.languageFunc(text: "route_weather_hazardous")
        }
    }

    private func factorTitle(_ factor: PTRouteWeatherRiskFactor) -> String {
        switch factor {
        case .precipitation: return PTDashboardConfig.languageFunc(text: "route_weather_factor_precipitation")
        case .wind: return PTDashboardConfig.languageFunc(text: "route_weather_factor_wind")
        case .cold: return PTDashboardConfig.languageFunc(text: "route_weather_factor_cold")
        case .heat: return PTDashboardConfig.languageFunc(text: "route_weather_factor_heat")
        case .lowVisibility: return PTDashboardConfig.languageFunc(text: "route_weather_factor_visibility")
        case .storm: return PTDashboardConfig.languageFunc(text: "route_weather_factor_storm")
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
