//
//  PTVehicleHealthViewController.swift
//  CrazyDashboard
//
//  EN: Read-only Build 78 vehicle health timeline and trend presentation.
//  ES: Presentación de solo lectura de la línea temporal y tendencias de salud de Build 78.
//  中文：Build 78 只读车辆健康时间线与趋势展示页面。
//

import UIKit
import PooTools
import SnapKit

@MainActor
final class PTVehicleHealthViewController: PTMotoBaseViewController {
    private let vehicleID: UUID
    private let repository: PTVehicleHealthRepository

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let vehicleLabel = UILabel()
    private let stateLabel = UILabel()
    private let sourceLabel = UILabel()
    private let summaryStack = UIStackView()
    private let metricControl = UISegmentedControl()
    private let chartView = PTVehicleHealthChartView()
    private let chartDetailLabel = UILabel()
    private let refreshButton = UIButton(type: .system)
    private let exportButton = UIButton(type: .system)
    private var isObservingRepository = false

    init(
        vehicleID: UUID,
        repository: PTVehicleHealthRepository? = nil
    ) {
        self.vehicleID = vehicleID
        self.repository = repository ?? PTVehicleHealthRepository.shared
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        pt_Title = localized("vehicle_health_timeline", fallback: "Vehicle Health")
        view.backgroundColor = .black
        configureView()
        repository.start()
        startObservingRepository()
        refreshView()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        repository.start()
        startObservingRepository()
        refreshView()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopObservingRepository()
    }

    private func configureView() {
        vehicleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        vehicleLabel.textColor = .white
        vehicleLabel.numberOfLines = 0

        stateLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        stateLabel.numberOfLines = 0

        sourceLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        sourceLabel.textColor = .systemGray2
        sourceLabel.numberOfLines = 0

        summaryStack.axis = .vertical
        summaryStack.spacing = 8

        metricControl.removeAllSegments()
        PTVehicleHealthChartMetric.allCases.enumerated().forEach { index, metric in
            metricControl.insertSegment(
                withTitle: chartTitle(for: metric),
                at: index,
                animated: false
            )
        }
        metricControl.selectedSegmentIndex = 0
        metricControl.selectedSegmentTintColor = PTDashboardConfig.shared.appMainColor
        metricControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)
        metricControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        metricControl.addTarget(self, action: #selector(chartMetricChanged), for: .valueChanged)

        chartView.backgroundColor = UIColor(white: 0.08, alpha: 1)
        chartView.layer.cornerRadius = 14
        chartView.layer.masksToBounds = true
        chartView.lineColor = PTDashboardConfig.shared.appMainColor

        chartDetailLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        chartDetailLabel.textColor = .systemGray2
        chartDetailLabel.numberOfLines = 0

        configureActionButton(refreshButton, title: localized("button_refresh", fallback: "Refresh"))
        refreshButton.addTarget(self, action: #selector(refreshTapped), for: .touchUpInside)
        configureActionButton(exportButton, title: localized("can_lab_share", fallback: "Share"))
        exportButton.addTarget(self, action: #selector(exportTapped), for: .touchUpInside)

        let header = UIStackView(arrangedSubviews: [vehicleLabel, stateLabel, sourceLabel])
        header.axis = .vertical
        header.spacing = 5

        let actionRow = UIStackView(arrangedSubviews: [refreshButton, exportButton])
        actionRow.axis = .horizontal
        actionRow.spacing = 8
        actionRow.distribution = .fillEqually

        contentStack.axis = .vertical
        contentStack.spacing = 12
        contentStack.addArrangedSubview(header)
        contentStack.addArrangedSubview(summaryStack)
        contentStack.addArrangedSubview(metricControl)
        contentStack.addArrangedSubview(chartView)
        contentStack.addArrangedSubview(chartDetailLabel)
        contentStack.addArrangedSubview(actionRow)

        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)

        scrollView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        contentStack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(16)
            make.width.equalTo(scrollView.snp.width).offset(-32)
        }
        chartView.snp.makeConstraints { make in
            make.height.equalTo(190)
        }
        metricControl.snp.makeConstraints { make in
            make.height.equalTo(34)
        }
        refreshButton.snp.makeConstraints { make in
            make.height.equalTo(44)
        }
        exportButton.snp.makeConstraints { make in
            make.height.equalTo(44)
        }
    }

    private func configureActionButton(_ button: UIButton, title: String) {
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = PTDashboardConfig.shared.appMainColor.withAlphaComponent(0.85)
        button.layer.cornerRadius = 10
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
    }

    @objc private func repositoryDidChange() {
        refreshView()
    }

    private func startObservingRepository() {
        guard !isObservingRepository else { return }
        isObservingRepository = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(repositoryDidChange),
            name: PTVehicleHealthRepository.didChange,
            object: repository
        )
    }

    private func stopObservingRepository() {
        guard isObservingRepository else { return }
        isObservingRepository = false
        NotificationCenter.default.removeObserver(
            self,
            name: PTVehicleHealthRepository.didChange,
            object: repository
        )
    }

    @objc private func chartMetricChanged() {
        refreshChart()
    }

    @objc private func refreshTapped() {
        refreshView()
    }

    @objc private func exportTapped() {
        do {
            guard let url = try repository.exportURL(for: vehicleID) else {
                showMessage(localized("empty_data_normal", fallback: "No health data"))
                return
            }
            let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            if let popover = activity.popoverPresentationController {
                popover.sourceView = exportButton
                popover.sourceRect = exportButton.bounds
            }
            present(activity, animated: true)
        } catch {
            showMessage(error.localizedDescription)
        }
    }

    private func refreshView() {
        guard let vehicle = PTMotorcycleGarageStore.shared.vehicle(id: vehicleID) else {
            vehicleLabel.text = localized("garage_no_vehicle", fallback: "Vehicle unavailable")
            stateLabel.text = localized("empty_data_normal", fallback: "No health data")
            sourceLabel.text = nil
            summaryStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
            chartView.samples = []
            chartDetailLabel.text = nil
            return
        }

        let summary = repository.summary(for: vehicleID, includeSynthetic: true)
        vehicleLabel.text = vehicle.name
        stateLabel.text = "\(localized("obd_diagnostic_health", fallback: "Health")): \(stateText(summary.overallState))"
        stateLabel.textColor = stateColor(summary.overallState)
        sourceLabel.text = sourceText(summary)
        rebuildSummary(summary)
        refreshChart()
    }

    private func rebuildSummary(_ summary: PTVehicleHealthSummary) {
        summaryStack.arrangedSubviews.forEach {
            summaryStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let battery = summary.battery.latest.map { String(format: "%.2f V", $0) } ?? "--"
        let resting = summary.restingVoltage.latest.map { String(format: "%.2f V", $0) } ?? "--"
        let crank = summary.crankVoltage.latest.map { String(format: "%.2f V", $0) } ?? "--"
        let running = summary.runningVoltage.latest.map { String(format: "%.2f V", $0) } ?? "--"
        let mileage = summary.mileage.latest.map(formattedMileage) ?? "--"
        let dtc = summary.latestConfirmedDTCCount.map(String.init) ?? "--"
        let maintenance = summary.latestMaintenanceDistanceKm.map(formattedMileage) ?? "--"
        let connection = summary.latestConnectionQuality.map(connectionText) ?? "--"

        let rows = [
            (localized("obd_diagnostic_battery", fallback: "Battery"), battery),
            (localized("garage_observation_mileage", fallback: "Mileage"), mileage),
            (localized("obd_diagnostic_connection", fallback: "Connection"), connection),
            ("DTC", dtc),
            (localized("garage_maintenance", fallback: "Maintenance"), maintenance),
            (localized("obd_diagnostic_battery_resting", fallback: "Resting"), resting),
            (localized("obd_diagnostic_battery_cranking_min", fallback: "Crank min"), crank),
            (localized("obd_diagnostic_battery_running", fallback: "Running"), running)
        ]

        for pair in stride(from: 0, to: rows.count, by: 2) {
            let end = min(pair + 2, rows.count)
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 8
            row.distribution = .fillEqually
            for item in rows[pair..<end] {
                row.addArrangedSubview(summaryCard(title: item.0, value: item.1))
            }
            if end - pair == 1 {
                row.addArrangedSubview(UIView())
            }
            summaryStack.addArrangedSubview(row)
        }
    }

    private func summaryCard(title: String, value: String) -> UIView {
        let card = UIStackView()
        card.axis = .vertical
        card.spacing = 4
        card.isLayoutMarginsRelativeArrangement = true
        card.layoutMargins = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        card.backgroundColor = UIColor.white.withAlphaComponent(0.09)
        card.layer.cornerRadius = 12

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textColor = .systemGray2
        titleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        titleLabel.numberOfLines = 2

        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.textColor = .white
        valueLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        valueLabel.numberOfLines = 2

        card.addArrangedSubview(titleLabel)
        card.addArrangedSubview(valueLabel)
        return card
    }

    private func refreshChart() {
        guard PTVehicleHealthChartMetric.allCases.indices.contains(metricControl.selectedSegmentIndex) else {
            return
        }
        let index = metricControl.selectedSegmentIndex
        let metric = PTVehicleHealthChartMetric.allCases[index]
        let samples = repository.chartValues(for: metric, vehicleID: vehicleID, includeSynthetic: true)
        chartView.samples = samples.map { .init(date: $0.date, value: $0.value) }
        let values = samples.map(\.value)
        if let minimum = values.min(), let maximum = values.max() {
            chartDetailLabel.text = "\(chartTitle(for: metric)): \(String(format: "%.2f", minimum)) — \(String(format: "%.2f", maximum)) · \(values.count)"
        } else {
            chartDetailLabel.text = localized("empty_data_normal", fallback: "No health data")
        }
    }

    private func chartTitle(for metric: PTVehicleHealthChartMetric) -> String {
        switch metric {
        case .battery:
            return localized("obd_diagnostic_battery", fallback: "Battery")
        case .mileage:
            return localized("garage_observation_mileage", fallback: "Mileage")
        case .confirmedDTC:
            return "DTC"
        }
    }

    private func sourceText(_ summary: PTVehicleHealthSummary) -> String {
        let freshness = summary.latestPointAt.map { formattedDate($0) } ?? "--"
        let kind = summary.isSyntheticOnly ? "Mock" : "Live / history"
        return "\(kind) · \(summary.totalPointCount) · \(freshness)"
    }

    private func stateText(_ state: PTVehicleHealthOverallState) -> String {
        switch state {
        case .unknown: return localized("Unavailable", fallback: "Unavailable")
        case .healthy: return localized("maintenance_state_normal", fallback: "Normal")
        case .attention: return localized("maintenance_state_due_soon", fallback: "Attention")
        case .critical: return localized("maintenance_state_required", fallback: "Critical")
        }
    }

    private func stateColor(_ state: PTVehicleHealthOverallState) -> UIColor {
        switch state {
        case .unknown: return .systemGray2
        case .healthy: return .systemGreen
        case .attention: return .systemOrange
        case .critical: return .systemRed
        }
    }

    private func connectionText(_ quality: PTVehicleConnectionQuality) -> String {
        localized(
            "obd_diagnostic_connection_\(quality.rawValue)",
            fallback: quality.rawValue.capitalized
        )
    }

    private func formattedMileage(_ value: Double) -> String {
        let shown = PTDashboardConfig.shared.appShowMileage(value)
        return String(format: "%.1f %@", shown, PTDashboardConfig.shared.appShowUniLabel)
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    private func showMessage(_ message: String) {
        let alert = UIAlertController(
            title: localized("vehicle_health_timeline", fallback: "Vehicle Health"),
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(
            title: localized("button_confirm", fallback: "OK"),
            style: .default
        ))
        present(alert, animated: true)
    }

    private func localized(_ key: String, fallback: String) -> String {
        let value = PTDashboardConfig.languageFunc(text: key)
        return value == key ? fallback : value
    }
}

// EN: A lightweight Core Animation chart keeps the health screen dependency-free and bounded.
// ES: Un gráfico ligero de Core Animation mantiene la pantalla sin dependencias y con memoria acotada.
// 中文：轻量 Core Animation 图表让健康页面无额外依赖并保持内存有界。
@MainActor
private final class PTVehicleHealthChartView: UIView {
    struct Sample {
        let date: Date
        let value: Double
    }

    var samples: [Sample] = [] {
        didSet { setNeedsLayout() }
    }
    var lineColor: UIColor = .systemBlue

    private let lineLayer = CAShapeLayer()
    private let gridLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = true
        layer.addSublayer(gridLayer)
        layer.addSublayer(lineLayer)
        gridLayer.strokeColor = UIColor.white.withAlphaComponent(0.1).cgColor
        gridLayer.fillColor = UIColor.clear.cgColor
        gridLayer.lineWidth = 1
        lineLayer.fillColor = UIColor.clear.cgColor
        lineLayer.lineWidth = 2.5
        lineLayer.lineCap = .round
        lineLayer.lineJoin = .round
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gridLayer.frame = bounds
        lineLayer.frame = bounds
        redraw()
    }

    private func redraw() {
        let inset = bounds.insetBy(dx: 18, dy: 18)
        let grid = UIBezierPath()
        for index in 0...3 {
            let y = inset.minY + inset.height * CGFloat(index) / 3
            grid.move(to: CGPoint(x: inset.minX, y: y))
            grid.addLine(to: CGPoint(x: inset.maxX, y: y))
        }
        gridLayer.path = grid.cgPath

        guard samples.count >= 2,
              inset.width > 0,
              inset.height > 0,
              let minimum = samples.map(\.value).min(),
              let maximum = samples.map(\.value).max() else {
            lineLayer.path = nil
            return
        }

        let range = max(maximum - minimum, 0.001)
        let path = UIBezierPath()
        for (index, sample) in samples.enumerated() {
            let x = inset.minX + inset.width * CGFloat(index) / CGFloat(max(samples.count - 1, 1))
            let normalized = (sample.value - minimum) / range
            let y = inset.maxY - inset.height * CGFloat(normalized)
            let point = CGPoint(x: x, y: y)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        lineLayer.strokeColor = lineColor.cgColor
        lineLayer.path = path.cgPath
    }
}
