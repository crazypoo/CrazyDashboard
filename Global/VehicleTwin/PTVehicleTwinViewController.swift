//
//  PTVehicleTwinViewController.swift
//  CrazyDashboard
//
//  EN: Full-screen UIKit presentation of the read-only XP400 2D/3D Digital Twin.
//  ES: Presentación UIKit a pantalla completa del Digital Twin 2D/3D de XP400 de solo lectura.
//  中文：只读 XP400 2D/3D 数字孪生的全屏 UIKit 页面。
//

import UIKit
import PooTools
import SnapKit

@MainActor
final class PTVehicleTwinViewController: PTMotoBaseViewController {
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

    private var selectedMode: PTVehicleTwinDisplayMode = .automatic
    private var currentSnapshot = PTVehicleTwinSnapshot.empty

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = PTDashboardConfig.languageFunc(text: "Vehicle Twin")
        selectedMode = PTVehicleTwinDisplayPreferences.shared.mode
        setupUI()
        store.onChange = { [weak self] snapshot in
            self?.render(snapshot)
        }
        render(store.snapshot)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        store.start()
        store.refresh()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
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

        twin2DView.configure(.xp400GT)
        twin2DView.backgroundColor = UIColor(white: 0.08, alpha: 1)
        twin2DView.layer.cornerRadius = 18

        twin3DView.configure(.xp400GT)
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
