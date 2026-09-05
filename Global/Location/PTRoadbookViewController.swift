//
//  PTRoadbookViewController.swift
//  CrazyDashboard
//
//  EN: Minimal UIKit management screen for imported ADV Roadbooks.
//  ES: Pantalla UIKit mínima para gestionar Roadbooks ADV importados.
//  中文：用于管理导入 ADV Roadbook 的轻量 UIKit 页面。
//

import UIKit
import MapKit
import UniformTypeIdentifiers
import PooTools
import SnapKit
import SafeSFSymbols

@MainActor
final class PTRoadbookViewController: PTListViewController, UIDocumentPickerDelegate {
    // EN: This key prevents a navigation heartbeat from rebuilding an unchanged list.
    // ES: Esta clave evita reconstruir una lista sin cambios en cada latido de navegación.
    // 中文：通过这个状态键避免每次导航心跳都重建未变化的列表。
    private struct ListRenderState: Equatable {
        let roadbookIDs: [UUID]
        let roadbookNames: [String]
        let activeRoadbookID: UUID?
        let sessionState: PTRoadbookState
        let isSessionActive: Bool
    }

    private let manager = PTCustomRouteManager.shared
    private var roadbooks: [PTRoadbook] = []
    private var renderedListState: ListRenderState?
    private var loadTask: Task<Void, Never>?
    private var weatherTask: Task<Void, Never>?
    private var lookAroundRequest: MKLookAroundSceneRequest?

    public override func installListViewConstraints(_ listView: PTCollectionView) {
        listView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.top.equalToSuperview().inset(CGFloat.kNavBarHeight_Total)
        }
    }
    
    public override func makeListViewConfiguration() -> PTCollectionViewConfig {
        let cConfig = PTCollectionViewConfig()
        cConfig.viewType = .Normal
        cConfig.itemOriginalX = PTAppBaseConfig.share.defaultViewSpace
        cConfig.itemHeight = 68
        cConfig.topRefresh = true
        return cConfig
    }
    
    public override func configureListView(_ listView: PTCollectionView) {
        listView.headerRefreshTask = {
            PTGCDManager.shared.runOnMain {
                self.refresh()
            }
        }
        listView.cellInCollection = { collectionView ,dataModel,indexPath in
            if let itemRow = dataModel.rows?[indexPath.row],let cell = collectionView.dequeueReusableCell(withReuseIdentifier: itemRow.reuseID, for: indexPath) as? PTFusionCell,let cellModel = itemRow.dataModel as? PTFusionCellModel {
                cell.cellModel  = cellModel
                return cell
            }
            return nil
        }
        listView.collectionDidSelect = { [weak self] collectionView, sectionModel, indexPath in
            guard let self else { return }
            let cell = collectionView.cellForItem(at: indexPath)
            self.presentActions(for: self.roadbooks[indexPath.row], sourceView: cell)
        }
    }
    
    lazy var importGPXButton:PTBaseButton = {
        let view = PTBaseButton(type:.custom)
        view.setImage(UIImage(.plus).withTintColor(.white, renderingMode: .alwaysOriginal), for: .normal)
        view.bounds = .init(origin: .zero, size: .init(width: PTAppBaseConfig.share.navBarButtonSize, height: PTAppBaseConfig.share.navBarButtonSize))
        view.addActionHandlers(handler: { _ in
            self.importGPX()
        })
        return view
    }()

    lazy var createButton:PTBaseButton = {
        let view = PTBaseButton(type:.custom)
        view.titleLabel?.font = .appfont(size: 16)
        view.setTitleColor(.white, for: .normal)
        view.setTitle(PTDashboardConfig.languageFunc(text: "roadbook_create"), for: .normal)
        view.bounds = .init(origin: .zero, size: .init(width: view.sizeFor().width + 20, height: PTAppBaseConfig.share.navBarButtonSize))
        view.addActionHandlers(handler: { _ in
            self.createRoadbook()
        })
        return view
    }()
    
    public override func preferredNavigationBarStyle() -> PTNavigationBarStyle {
        return .transparent
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        pt_Title = PTDashboardConfig.languageFunc(text: "roadbook_title")
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshVisibleState),
            name: PTRoadbookStateDidChange,
            object: manager
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refresh),
            name: PTRoadbookLibraryDidChange,
            object: manager
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setCustomRightButtons(buttons: [createButton,importGPXButton], buttonSpacing: CGFloat.GlobalItemSpacing)
        reloadRoadbooks()
    }

    @MainActor
    deinit {
        loadTask?.cancel()
        weatherTask?.cancel()
        lookAroundRequest?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    func showDetail(force: Bool = false) {
        let renderState = ListRenderState(
            roadbookIDs: roadbooks.map(\.id),
            roadbookNames: roadbooks.map(\.name),
            activeRoadbookID: manager.activeRoadbook?.id,
            sessionState: manager.state,
            isSessionActive: manager.isSessionActive
        )
        guard force || renderedListState != renderState else { return }
        renderedListState = renderState

        var mSections = [PTSection]()
        let permissionRows = roadbooks.map {
            let cellModel = PTFusionCellModel()
            cellModel.nameColor = .white
            cellModel.contentTextColor = .white
            cellModel.name = $0.name
            let active = manager.activeRoadbook?.id == $0.id && manager.isSessionActive
            let stateText = active ? " · \(stateTitle(manager.state))" : ""
            let waypointText = PTDashboardConfig.language(
                key: "roadbook_waypoint_count",
                $0.waypoints.count
            )
            cellModel.content = waypointText + stateText
            let row = PTRows(ID: PTFusionCell.ID,dataModel: cellModel)
            row.cellClass = PTFusionCell.self
            return row
        }
        let section = PTSection(rows: permissionRows)
        mSections.append(section)
        
        listView.layoutIfNeeded()
        listView.showCollectionDetail(collectionData: mSections)
    }
    
    @objc private func refresh() {
        reloadRoadbooks()
    }

    @objc private func refreshVisibleState() {
        self.showDetail()
    }

    private func reloadRoadbooks() {
        loadTask?.cancel()
        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                self.roadbooks = try await self.manager.loadRoadbooks()
                self.showDetail(force: true)
            } catch {
                self.showError(error)
            }
            self.listView.endRefresh()
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
                self.showDetail(force: true)
            } catch {
                self.showError(error)
            }
        }
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
        if isLookAroundEligible(roadbook) {
            alert.addAction(UIAlertAction(
                title: PTDashboardConfig.languageFunc(text: "roadbook_look_around"),
                style: .default
            ) { [weak self] _ in
                self?.showLookAroundPicker(for: roadbook)
            })
        }
        alert.addAction(UIAlertAction(
            title: PTDashboardConfig.languageFunc(text: "route_weather_risk"),
            style: .default
        ) { [weak self] _ in
            self?.showWeatherRisk(for: roadbook)
        })
        alert.addAction(UIAlertAction(
            title: PTDashboardConfig.languageFunc(text: "roadbook_add_to_calendar"),
            style: .default
        ) { [weak self] _ in
            guard let self else { return }
            PTMotoCalendarManager.shared.presentRoadbookReminder(
                roadbook: roadbook,
                from: self
            )
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

    // EN: Look Around is offered only for imported WGS84 GPX data so coordinates are never guessed.
    // ES: Look Around solo se ofrece para GPX WGS84 importado, sin adivinar coordenadas.
    // 中文：仅对导入的 WGS84 GPX 开放 Look Around，绝不猜测坐标系。
    private func isLookAroundEligible(_ roadbook: PTRoadbook) -> Bool {
        roadbook.coordinateSystem == .wgs84
            && roadbook.sourceFileName?.lowercased().hasSuffix(".gpx") == true
            && !roadbook.waypoints.isEmpty
    }

    // EN: Let the rider choose a bounded number of route points to preview.
    // ES: Permite al piloto elegir un número limitado de puntos de la ruta para previsualizar.
    // 中文：让骑手从有限数量的路线点中选择预览位置。
    private func showLookAroundPicker(for roadbook: PTRoadbook) {
        let alert = UIAlertController(
            title: PTDashboardConfig.languageFunc(text: "roadbook_look_around"),
            message: nil,
            preferredStyle: .actionSheet
        )
        for (index, waypoint) in roadbook.waypoints.prefix(8).enumerated() {
            let instruction = waypoint.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = instruction.isEmpty
                ? PTDashboardConfig.language(key: "roadbook_look_around_waypoint", index + 1)
                : "\(index + 1). \(instruction)"
            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.requestLookAround(at: waypoint.coordinate)
            })
        }
        alert.addAction(UIAlertAction(
            title: PTDashboardConfig.languageFunc(text: "button_cancel"),
            style: .cancel
        ))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(
                x: view.bounds.midX,
                y: view.bounds.midY,
                width: 1,
                height: 1
            )
        }
        present(alert, animated: true)
    }

    // EN: Request a single panorama and release it when cancelled or completed.
    // ES: Solicita una sola panorámica y la libera al cancelar o terminar.
    // 中文：每次只请求一个全景场景，取消或完成后立即释放请求。
    private func requestLookAround(at coordinate: CLLocationCoordinate2D) {
        lookAroundRequest?.cancel()
        let request = MKLookAroundSceneRequest(coordinate: coordinate)
        lookAroundRequest = request

        let loadingAlert = UIAlertController(
            title: PTDashboardConfig.languageFunc(text: "roadbook_look_around"),
            message: PTDashboardConfig.languageFunc(text: "roadbook_look_around_loading"),
            preferredStyle: .alert
        )
        loadingAlert.addAction(UIAlertAction(
            title: PTDashboardConfig.languageFunc(text: "button_cancel"),
            style: .cancel
        ) { [weak self] _ in
            self?.lookAroundRequest?.cancel()
            self?.lookAroundRequest = nil
        })
        present(loadingAlert, animated: true)

        request.getSceneWithCompletionHandler { [weak self, weak loadingAlert] scene, _ in
            Task { @MainActor [weak self] in
                guard let self, self.lookAroundRequest === request else { return }
                self.lookAroundRequest = nil
                loadingAlert?.dismiss(animated: true) {
                    guard let scene else {
                        self.showLookAroundUnavailable()
                        return
                    }
                    let controller = MKLookAroundViewController(scene: scene)
                    controller.showsRoadLabels = true
                    self.present(controller, animated: true)
                }
            }
        }
    }

    // EN: Coverage is optional; explain an unavailable panorama without treating it as a route error.
    // ES: La cobertura es opcional; informa de una panorámica no disponible sin tratarlo como error de ruta.
    // 中文：Look Around 覆盖范围不是必有，未覆盖时单独提示，不把它当作路线错误。
    private func showLookAroundUnavailable() {
        let alert = UIAlertController(
            title: PTDashboardConfig.languageFunc(text: "roadbook_look_around"),
            message: PTDashboardConfig.languageFunc(text: "roadbook_look_around_unavailable"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(
            title: PTDashboardConfig.languageFunc(text: "button_confirm"),
            style: .default
        ))
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
                let report = try await PTRouteWeatherRiskService.shared.analyzeRiding(roadbook: roadbook)
                guard !Task.isCancelled else { return }
                loadingAlert?.dismiss(animated: true) {
                    self.showRidingRiskReport(report)
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
            PTDashboardConfig.language(
                key: "route_weather_source",
                weatherProviderTitle(report.provider)
            ),
            PTDashboardConfig.language(key: "route_weather_worst", riskLevelTitle(report.worstLevel)),
            PTDashboardConfig.language(key: "route_weather_risky_points", report.riskyPointCount)
        ]

        if report.provider == .qWeather {
            lines.append(PTDashboardConfig.languageFunc(text: "route_weather_fallback_used"))
        }

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

    // EN: Show the combined report as preparation guidance, never as a racing or speed recommendation.
    // ES: Muestra el informe combinado como preparación, nunca como recomendación de velocidad o competición.
    // 中文：把综合报告作为出发准备提示展示，绝不提供竞速或速度建议。
    private func showRidingRiskReport(_ report: PTRouteRidingRiskReport) {
        let riskyPoints = report.points.filter { $0.level != .clear }.prefix(5)
        var lines = [
            PTDashboardConfig.languageFunc(text: "route_weather_riding_report"),
            PTDashboardConfig.language(
                key: "route_weather_source",
                report.weatherProvider.map(weatherProviderTitle)
                    ?? PTDashboardConfig.languageFunc(text: "route_weather_source_unavailable")
            ),
            PTDashboardConfig.language(key: "route_weather_worst", riskLevelTitle(report.worstLevel)),
            PTDashboardConfig.language(key: "route_weather_risky_points", report.riskyPointCount),
            PTDashboardConfig.languageFunc(text: "route_weather_riding_note")
        ]

        if !report.missingData.isEmpty {
            let missing = report.missingData.map(ridingFactorTitle).joined(separator: ", ")
            lines.append(PTDashboardConfig.language(key: "route_weather_missing_data", missing))
        }

        if riskyPoints.isEmpty {
            lines.append(PTDashboardConfig.languageFunc(text: "route_weather_no_risk"))
        } else {
            lines.append(contentsOf: riskyPoints.map { point in
                let coordinate = String(
                    format: "%.4f, %.4f",
                    point.coordinate.latitude,
                    point.coordinate.longitude
                )
                let factors = point.factors.map(ridingFactorTitle).joined(separator: ", ")
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

    private func ridingFactorTitle(_ factor: PTRouteRidingRiskFactor) -> String {
        switch factor {
        case .precipitation: return PTDashboardConfig.languageFunc(text: "route_weather_factor_precipitation")
        case .wind: return PTDashboardConfig.languageFunc(text: "route_weather_factor_wind")
        case .cold: return PTDashboardConfig.languageFunc(text: "route_weather_factor_cold")
        case .heat: return PTDashboardConfig.languageFunc(text: "route_weather_factor_heat")
        case .lowVisibility: return PTDashboardConfig.languageFunc(text: "route_weather_factor_visibility")
        case .storm: return PTDashboardConfig.languageFunc(text: "route_weather_factor_storm")
        case .night: return PTDashboardConfig.languageFunc(text: "route_weather_factor_night")
        case .continuousCurves: return PTDashboardConfig.languageFunc(text: "route_weather_factor_curves")
        case .weatherUnavailable: return PTDashboardConfig.languageFunc(text: "route_weather_factor_unavailable")
        }
    }

    // EN: The report explains which single provider supplied every route point.
    // ES: El informe explica qué único proveedor suministró todos los puntos de la ruta.
    // 中文：报告明确说明整条路线的所有采样点来自哪个单一提供方。
    private func weatherProviderTitle(_ provider: PTRouteWeatherProvider) -> String {
        switch provider {
        case .weatherKit:
            return PTDashboardConfig.languageFunc(text: "route_weather_source_weatherkit")
        case .qWeather:
            return PTDashboardConfig.languageFunc(text: "route_weather_source_qweather")
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
                    self.showDetail(force: true)
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
            message: weatherErrorMessage(error),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(
            title: PTDashboardConfig.languageFunc(text: "button_confirm"),
            style: .default
        ))
        present(alert, animated: true)
    }

    // EN: Route-weather errors use the app catalog; unrelated errors keep their existing message.
    // ES: Los errores meteorológicos de ruta usan el catálogo de la app; los demás conservan su mensaje.
    // 中文：路线天气错误统一使用应用本地化目录，其他错误保持原有提示。
    private func weatherErrorMessage(_ error: Error) -> String {
        guard let routeError = error as? PTRouteWeatherRiskError else {
            return error.localizedDescription
        }

        let key: String
        switch routeError {
        case .invalidRoute:
            key = "route_weather_error_invalid_route"
        case .noForecast:
            key = "route_weather_error_no_forecast"
        case .fallbackUnavailable:
            key = "route_weather_error_fallback_unavailable"
        case .allProvidersFailed:
            key = "route_weather_error_all_providers_failed"
        case .forecastOutsideSupportedRange:
            key = "route_weather_error_outside_range"
        case .cancelled:
            key = "route_weather_error_cancelled"
        }
        return PTDashboardConfig.languageFunc(text: key)
    }
}
