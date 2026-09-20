//
//  PTVehicleTwinViewController.swift
//  CrazyDashboard
//
//  EN: Full-screen UIKit presentation of the read-only XP400 2D/3D Digital Twin.
//  ES: Presentación UIKit a pantalla completa del Digital Twin 2D/3D de XP400 de solo lectura.
//  中文：只读 XP400 2D/3D 数字孪生的全屏 UIKit 页面。
//

import UIKit
import UniformTypeIdentifiers
import PooTools
import SnapKit
import SafeSFSymbols

@MainActor
final class PTVehicleTwinViewController: PTMotoBaseViewController, UIDocumentPickerDelegate {
    private let store = PTVehicleTwinStore()
    private let twin2DView = PTXP400TwinView()
    private let twin3DView = PTXP400Twin3DView()
    private let twinContainer = UIView()
    private let statusLabel = UILabel()
    private let freshnessLabel = UILabel()
    private let modeHintLabel = UILabel()
    private let displayModeControl = UISegmentedControl()
    private let cameraControl = UISegmentedControl()
    private let metricsStack = UIStackView()
    private let healthSummaryLabel = UILabel()
    private let roadSurfaceLabel = UILabel()

    private var selectedMode: PTVehicleTwinDisplayMode = .automatic
    private var currentSnapshot = PTVehicleTwinSnapshot.empty
    private var replaySource: PTReplayVehicleStateSource?
    private var roadSurfaceImpactID: UUID?
    private let dashboardContextEngine = PTDashboardContextEngine.shared

    lazy var stopButton:PTBaseButton = {
        let view = PTBaseButton(type:.custom)
        view.setImage(UIImage(.stop.fill).withTintColor(.white, renderingMode: .alwaysOriginal), for: .normal)
        view.bounds = .init(origin: .zero, size: .init(width: PTAppBaseConfig.share.navBarButtonSize, height: PTAppBaseConfig.share.navBarButtonSize))
        view.addActionHandlers(handler: { _ in
            self.stopReplayTapped()
        })
        return view
    }()
    
    lazy var importButton:PTBaseButton = {
        let view = PTBaseButton(type:.custom)
        view.setImage(UIImage(.square.andArrowDownFill).withTintColor(.white, renderingMode: .alwaysOriginal), for: .normal)
        view.bounds = .init(origin: .zero, size: .init(width: PTAppBaseConfig.share.navBarButtonSize, height: PTAppBaseConfig.share.navBarButtonSize))
        view.addActionHandlers(handler: { _ in
            self.importTraceTapped()
        })
        return view
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        pt_Title = PTDashboardConfig.languageFunc(text: "Vehicle Twin")
        selectedMode = PTVehicleTwinDisplayPreferences.shared.mode
        setupUI()
        PTVehicleHealthRepository.shared.start()
        PTRoadSurfaceRepository.shared.start()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(healthRepositoryDidChange),
            name: PTVehicleHealthRepository.didChange,
            object: PTVehicleHealthRepository.shared
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(roadSurfaceImpactDidDetect(_:)),
            name: PTRoadSurfaceRepository.impactDidDetect,
            object: PTRoadSurfaceRepository.shared
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(dashboardContextDidChange(_:)),
            name: PTDashboardContextEngine.didChange,
            object: dashboardContextEngine
        )
        store.onChange = { [weak self] snapshot in
            self?.render(snapshot)
        }
        render(store.snapshot)
        applyDashboardContext(dashboardContextEngine.snapshot)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        dashboardContextEngine.start()
        applyDashboardContext(dashboardContextEngine.snapshot)
        store.start()
        store.refresh()
        setCustomRightButtons(buttons: [importButton,stopButton], buttonSpacing: CGFloat.GlobalItemSpacing)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        dashboardContextEngine.stop()
        store.stop()
    }

    override func handleMotorcycleDisconnect() {
        super.handleMotorcycleDisconnect()
        store.refresh()
    }

    override func handleMotorcycleConnect() {
        super.handleMotorcycleConnect()
        store.refresh()
    }

    private func setupUI() {
        view.backgroundColor = .black

        statusLabel.font = .appfont(size: 15, bold: true)
        statusLabel.textColor = .white
        statusLabel.numberOfLines = 2
        freshnessLabel.font = .appfont(size: 12)
        freshnessLabel.textColor = .lightGray

        let header = UIStackView(arrangedSubviews: [statusLabel, freshnessLabel])
        header.axis = .vertical
        header.spacing = 4

        displayModeControl.removeAllSegments()
        PTVehicleTwinDisplayMode.allCases.enumerated().forEach { index, mode in
            displayModeControl.insertSegment(
                withTitle: PTVehicleTwinCopy.text(mode.localizationKey),
                at: index,
                animated: false
            )
        }
        displayModeControl.selectedSegmentIndex = index(for: selectedMode)
        displayModeControl.selectedSegmentTintColor = PTDashboardConfig.shared.appMainColor
        displayModeControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)
        displayModeControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        displayModeControl.addTarget(self, action: #selector(displayModeChanged), for: .valueChanged)

        cameraControl.removeAllSegments()
        PTVehicleTwin3DCameraPreset.allCases.enumerated().forEach { index, preset in
            cameraControl.insertSegment(
                withTitle: PTVehicleTwinCopy.text(preset.localizationKey),
                at: index,
                animated: false
            )
        }
        cameraControl.selectedSegmentIndex = index(for: .follow)
        cameraControl.selectedSegmentTintColor = PTDashboardConfig.shared.appMainColor
        cameraControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)
        cameraControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        cameraControl.addTarget(self, action: #selector(cameraChanged), for: .valueChanged)

        modeHintLabel.font = .appfont(size: 11)
        modeHintLabel.textColor = .systemOrange
        modeHintLabel.numberOfLines = 2

        twin2DView.configure(.xp400)
        twin2DView.backgroundColor = UIColor(white: 0.08, alpha: 1)
        twin2DView.layer.cornerRadius = 18

        twin3DView.configure(.xp400)
        twin3DView.onFallbackSuggested = { [weak self] reason in
            self?.modeHintLabel.text = PTVehicleTwinCopy.text(reason.localizationKey)
        }

        twinContainer.backgroundColor = UIColor(white: 0.08, alpha: 1)
        twinContainer.layer.cornerRadius = 18
        twinContainer.clipsToBounds = true
        twinContainer.addSubview(twin2DView)
        twinContainer.addSubview(twin3DView)
        twin2DView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        twin3DView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        metricsStack.axis = .vertical
        metricsStack.spacing = 8
        metricsStack.distribution = .fillEqually

        healthSummaryLabel.font = .appfont(size: 12)
        healthSummaryLabel.textColor = .systemGray2
        healthSummaryLabel.numberOfLines = 0

        roadSurfaceLabel.font = .appfont(size: 13, bold: true)
        roadSurfaceLabel.textColor = .systemOrange
        roadSurfaceLabel.numberOfLines = 2
        roadSurfaceLabel.isHidden = true

        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        let contentView = UIView()
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.addSubview(header)
        contentView.addSubview(displayModeControl)
        contentView.addSubview(cameraControl)
        contentView.addSubview(modeHintLabel)
        contentView.addSubview(twinContainer)
        contentView.addSubview(metricsStack)
        contentView.addSubview(healthSummaryLabel)
        contentView.addSubview(roadSurfaceLabel)

        scrollView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        contentView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.width.equalTo(scrollView.snp.width)
        }
        header.snp.makeConstraints { make in
            make.top.left.right.equalToSuperview().inset(16)
        }
        displayModeControl.snp.makeConstraints { make in
            make.top.equalTo(header.snp.bottom).offset(12)
            make.left.right.equalToSuperview().inset(16)
            make.height.equalTo(34)
        }
        cameraControl.snp.makeConstraints { make in
            make.top.equalTo(displayModeControl.snp.bottom).offset(8)
            make.left.right.equalTo(displayModeControl)
            make.height.equalTo(34)
        }
        modeHintLabel.snp.makeConstraints { make in
            make.top.equalTo(cameraControl.snp.bottom).offset(5)
            make.left.right.equalTo(displayModeControl)
        }
        twinContainer.snp.makeConstraints { make in
            make.top.equalTo(modeHintLabel.snp.bottom).offset(8)
            make.left.right.equalToSuperview().inset(16)
            make.height.equalTo(280)
        }
        metricsStack.snp.makeConstraints { make in
            make.top.equalTo(twinContainer.snp.bottom).offset(14)
            make.left.right.equalToSuperview().inset(16)
        }
        healthSummaryLabel.snp.makeConstraints { make in
            make.top.equalTo(metricsStack.snp.bottom).offset(12)
            make.left.right.equalTo(metricsStack)
        }
        roadSurfaceLabel.snp.makeConstraints { make in
            make.top.equalTo(healthSummaryLabel.snp.bottom).offset(8)
            make.left.right.equalTo(metricsStack)
            make.bottom.equalToSuperview().inset(24)
        }
        rebuildMetricRows()
    }

    @objc private func displayModeChanged() {
        guard displayModeControl.selectedSegmentIndex >= 0,
              displayModeControl.selectedSegmentIndex < PTVehicleTwinDisplayMode.allCases.count else { return }
        selectedMode = PTVehicleTwinDisplayMode.allCases[displayModeControl.selectedSegmentIndex]
        PTVehicleTwinDisplayPreferences.shared.mode = selectedMode
        render(currentSnapshot)
    }

    @objc private func cameraChanged() {
        guard cameraControl.selectedSegmentIndex >= 0,
              cameraControl.selectedSegmentIndex < PTVehicleTwin3DCameraPreset.allCases.count else { return }
        let preset = PTVehicleTwin3DCameraPreset.allCases[cameraControl.selectedSegmentIndex]
        twin3DView.setCameraPreset(preset)
    }

    @objc private func healthRepositoryDidChange() {
        refreshHealthSummary()
    }

    @objc private func dashboardContextDidChange(_ notification: Notification) {
        guard let snapshot = notification.userInfo?["snapshot"] as? PTDashboardContextSnapshot else { return }
        applyDashboardContext(snapshot)
    }

    // EN: Twin remains visible while its size and emphasis follow the shared dashboard policy.
    // ES: El Twin permanece visible mientras su tamaño y énfasis siguen la política común del tablero.
    // 中文：Twin 始终保留，只根据统一仪表盘策略调整尺寸和强调程度。
    private func applyDashboardContext(_ snapshot: PTDashboardContextSnapshot) {
        let presentation = snapshot.presentation(for: .vehicleTwin)
        twin2DView.applyDashboardPresentation(presentation)
        twin3DView.applyDashboardPresentation(presentation)
        let healthPresentation = snapshot.presentation(for: .health)
        healthSummaryLabel.isHidden = !healthPresentation.isVisible
        twinContainer.alpha = presentation.isEmphasized ? 1 : 0.96
        twinContainer.accessibilityLabel = "Vehicle Twin · \(snapshot.primaryContext.rawValue)"
    }

    // EN: Show the latest read-only road impact briefly without opening a vehicle command path.
    // ES: Muestra brevemente el último impacto de carretera de solo lectura sin abrir comandos del vehículo.
    // 中文：短暂显示最新的只读道路冲击提示，不会打开任何车辆指令通道。
    @objc private func roadSurfaceImpactDidDetect(_ notification: Notification) {
        guard let segment = notification.userInfo?["segment"] as? PTRoadSurfaceSegment else { return }
        roadSurfaceImpactID = segment.id
        roadSurfaceLabel.text = "\(PTDashboardConfig.languageFunc(text: "road_surface_impact")) · \(String(format: "%.2f G", segment.maxVerticalImpactG))"
        roadSurfaceLabel.isHidden = false
        let expectedID = segment.id
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self, self.roadSurfaceImpactID == expectedID else { return }
            self.roadSurfaceLabel.isHidden = true
        }
    }

    // EN: Importing a trace only feeds the existing replay bridge; it never opens BLE or OBD.
    // ES: Importar una traza solo alimenta el puente de reproducción existente; nunca abre BLE ni OBD.
    // 中文：导入 Trace 只进入现有回放桥接器，不会打开 BLE 或 OBD。
    @objc private func importTraceTapped() {
        let traceType = UTType(filenameExtension: "crazytrace") ?? .package
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [traceType, .data])
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    @objc private func stopReplayTapped() {
        replaySource?.stop()
        replaySource = nil
        store.refresh()
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        Task { @MainActor [weak self] in
            defer {
                if hasSecurityScope {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                let document = try await PTCrazyTraceRecorder.load(from: url)
                let source = PTReplayVehicleStateSource(document: document)
                self?.replaySource = source
                source.start()
            } catch {
                self?.showReplayError(error)
            }
        }
    }

    private func showReplayError(_ error: Error) {
        let alert = UIAlertController(
            title: PTDashboardConfig.languageFunc(text: "Replay Error"),
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(
            title: PTDashboardConfig.languageFunc(text: "button_confirm"),
            style: .default
        ))
        present(alert, animated: true)
    }

    private func render(_ snapshot: PTVehicleTwinSnapshot) {
        currentSnapshot = snapshot
        twin3DView.refreshFallbackState()
        if selectedMode != .twoD, !twin3DView.shouldFallbackTo2D {
            twin3DView.update(snapshot: snapshot)
        }

        let effectiveMode: PTVehicleTwinDisplayMode = selectedMode == .twoD || twin3DView.shouldFallbackTo2D
            ? .twoD
            : .threeD
        if effectiveMode == .threeD {
            twin3DView.isHidden = false
            twin2DView.isHidden = true
        } else {
            twin3DView.isHidden = true
            twin2DView.isHidden = false
            twin2DView.update(snapshot: snapshot)
        }
        cameraControl.isHidden = effectiveMode != .threeD
        if effectiveMode == .twoD,
           selectedMode != .twoD,
           let reason = twin3DView.fallbackReason {
            modeHintLabel.text = PTVehicleTwinCopy.text(reason.localizationKey)
        } else if selectedMode == .twoD {
            modeHintLabel.text = PTVehicleTwinCopy.text(.modeTwoD)
        } else {
            modeHintLabel.text = ""
        }

        let dashboard = snapshot.dashboardConnected
            ? PTDashboardConfig.languageFunc(text: "Dashboard") + " " + PTDashboardConfig.languageFunc(text: "connect_success")
            : PTDashboardConfig.languageFunc(text: "Dashboard") + " " + PTDashboardConfig.languageFunc(text: "ride_not_available")
        let obd = snapshot.obdConnected
            ? "OBD " + PTDashboardConfig.languageFunc(text: "connect_success")
            : "OBD " + PTDashboardConfig.languageFunc(text: "ride_not_available")
        statusLabel.text = "\(dashboard) · \(obd)"
        freshnessLabel.text = "\(PTDashboardConfig.languageFunc(text: "State")): \(freshnessText(snapshot.freshness))"
        rebuildMetricRows(snapshot: snapshot)
        refreshHealthSummary()
    }

    // EN: The health summary is auxiliary context and never replaces live twin metrics.
    // ES: El resumen de salud es contexto auxiliar y nunca sustituye las métricas vivas del gemelo.
    // 中文：健康摘要只是辅助信息，不会替换数字孪生的实时指标。
    private func refreshHealthSummary() {
        guard let vehicleID = PTVehicleConnectivityCoordinator.shared.dashboardGarageVehicleID
                ?? PTMotorcycleGarageStore.shared.selectedVehicleID else {
            healthSummaryLabel.text = PTDashboardConfig.languageFunc(text: "Unavailable")
            return
        }
        let summary = PTVehicleHealthRepository.shared.summary(for: vehicleID, includeSynthetic: true)
        let battery = summary.battery.latest.map { String(format: "%.2f V", $0) } ?? "--"
        let dtc = summary.latestConfirmedDTCCount.map(String.init) ?? "--"
        let maintenance = summary.latestMaintenanceDistanceKm.map {
            "\(String(format: "%.0f", $0)) \(PTDashboardConfig.shared.appShowUniLabel)"
        } ?? "--"
        let ride = summary.lastRideDistanceKm.map {
            "\(String(format: "%.1f", $0)) \(PTDashboardConfig.shared.appShowUniLabel)"
        } ?? "--"
        healthSummaryLabel.text = [
            "\(PTDashboardConfig.languageFunc(text: "vehicle_health_timeline")) · \(freshnessText(currentSnapshot.freshness))",
            "\(PTDashboardConfig.languageFunc(text: "obd_diagnostic_battery")): \(battery)  ·  DTC: \(dtc)",
            "\(PTDashboardConfig.languageFunc(text: "garage_maintenance")): \(maintenance)  ·  \(PTDashboardConfig.languageFunc(text: "ride_analysis_history")): \(ride)"
        ].joined(separator: "\n")
    }

    private func index(for mode: PTVehicleTwinDisplayMode) -> Int {
        PTVehicleTwinDisplayMode.allCases.firstIndex(of: mode) ?? 0
    }

    private func index(for preset: PTVehicleTwin3DCameraPreset) -> Int {
        PTVehicleTwin3DCameraPreset.allCases.firstIndex(of: preset) ?? 0
    }

    private func rebuildMetricRows(snapshot: PTVehicleTwinSnapshot? = nil) {
        let snapshot = snapshot ?? .empty
        metricsStack.arrangedSubviews.forEach { view in
            metricsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        metricsStack.addArrangedSubview(metricRow(
            title: "Speed",
            value: metricText(snapshot.speedKmh) { value in
                "\(String(format: "%.1f", PTDashboardConfig.shared.appShowMileage(value))) \(PTDashboardConfig.shared.appShowUniLabel)"
            }
        ))
        metricsStack.addArrangedSubview(metricRow(
            title: "RPM",
            value: metricText(snapshot.rpm) { value in "\(String(format: "%.0f", value)) \(RPMUnit)" }
        ))
        metricsStack.addArrangedSubview(metricRow(
            title: "Fuel",
            value: metricText(snapshot.fuelPercent) { value in "\(String(format: "%.0f", value))%" }
        ))
        metricsStack.addArrangedSubview(metricRow(
            title: "Voltage",
            value: metricText(snapshot.voltage) { value in "\(String(format: "%.2f", value)) V" }
        ))
        metricsStack.addArrangedSubview(metricRow(
            title: "Engine",
            value: statusText(snapshot.engineState?.value.rawValue)
        ))
        metricsStack.addArrangedSubview(metricRow(
            title: "TCS / ABS",
            value: "\(statusText(snapshot.tcsState?.value.rawValue)) / \(statusText(snapshot.absState?.value.rawValue))"
        ))
        metricsStack.addArrangedSubview(metricRow(
            title: "Motion",
            value: motionText(snapshot)
        ))
        metricsStack.addArrangedSubview(metricRow(
            title: "Stand / Light",
            value: "\(standText(snapshot.kickstandDown?.value)) / \(lightText(snapshot))"
        ))
    }

    private func metricRow(title: String, value: String) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = PTDashboardConfig.languageFunc(text: title)
        titleLabel.textColor = .lightGray
        titleLabel.font = .appfont(size: 13)
        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.textColor = .white
        valueLabel.font = .appfont(size: 14, bold: true)
        valueLabel.textAlignment = .right
        let row = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        row.axis = .horizontal
        row.alignment = .center
        row.distribution = .fill
        row.spacing = 12
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        row.backgroundColor = UIColor(white: 0.12, alpha: 1)
        row.layer.cornerRadius = 10
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        return row
    }

    private func metricText<Value>(_ metric: PTVehicleTwinMetric<Value>?, transform: (Value) -> String) -> String {
        guard let metric, metric.freshness != .unavailable else { return "--" }
        let value = transform(metric.value)
        switch metric.freshness {
        case .fresh:
            return value
        case .aging:
            return "~" + value
        case .stale:
            return "? " + value
        case .unavailable:
            return "--"
        }
    }

    private func statusText(_ rawValue: String?) -> String {
        guard let rawValue else { return "--" }
        return PTDashboardConfig.languageFunc(text: rawValue)
    }

    private func freshnessText(_ freshness: PTVehicleTwinFreshness) -> String {
        switch freshness {
        case .fresh:
            return PTDashboardConfig.languageFunc(text: "Live")
        case .aging:
            return PTDashboardConfig.languageFunc(text: "Updating")
        case .stale:
            return PTDashboardConfig.languageFunc(text: "Stale")
        case .unavailable:
            return PTDashboardConfig.languageFunc(text: "Unavailable")
        }
    }

    private func standText(_ value: Bool?) -> String {
        guard let value else { return "--" }
        return PTDashboardConfig.languageFunc(text: value ? "Down" : "Up")
    }

    private func lightText(_ snapshot: PTVehicleTwinSnapshot) -> String {
        if snapshot.highBeamOn?.value == true {
            return PTDashboardConfig.languageFunc(text: "High")
        }
        if snapshot.lowBeamOn?.value == true {
            return PTDashboardConfig.languageFunc(text: "Low")
        }
        return PTDashboardConfig.languageFunc(text: "Off")
    }

    private func motionText(_ snapshot: PTVehicleTwinSnapshot) -> String {
        let lean = snapshot.leanDegrees.map { String(format: "L %.1f°", $0.value) } ?? "L --"
        let pitch = snapshot.pitchDegrees.map { String(format: "P %.1f°", $0.value) } ?? "P --"
        let g = snapshot.lateralG.map { String(format: "G %.2f", $0.value) } ?? "G --"
        return "\(lean) · \(pitch) · \(g)"
    }
}
