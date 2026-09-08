//
//  PTRideAnalysisViewController.swift
//  CrazyDashboard
//
//  EN: A read-only professional ride analysis built on the existing trip report.
//  ES: Un análisis profesional de solo lectura basado en el informe de ruta existente.
//  中文：基于现有行程报告的只读专业骑行分析页面。
//

import UIKit
import PooTools

// EN: This screen receives value-type snapshots so history reloads cannot change the open report underneath it.
// ES: Esta pantalla recibe instantáneas de tipos valor para que una recarga no cambie el informe abierto.
// 中文：页面接收值类型快照，避免历史记录刷新时改变当前打开的报告。
@MainActor
final class PTRideAnalysisViewController: PTMotoBaseViewController {
    private let report: PTTripReport
    private let comparisonPool: [PTTripReport]
    private var analysisTask: Task<Void, Never>?
    private var snapshot: PTRideAnalysisSnapshot?
    private var eventTimestamps: [Int: Date] = [:]
    private weak var routeImageView: UIImageView?

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)

    init(report: PTTripReport, comparisonPool: [PTTripReport]) {
        self.report = report
        self.comparisonPool = comparisonPool
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        pt_Title = localized("ride_analysis_title")
        view.backgroundColor = .black
        configureScrollView()
        showLoadingState()
        startAnalysis()
    }

    // EN: Cancel pending analysis/export work only when this screen is actually removed from navigation.
    // ES: Cancela el trabajo pendiente solo cuando esta pantalla se elimina realmente de la navegación.
    // 中文：只有页面真正从导航栈移除时才取消未完成的分析或导出任务。
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isMovingFromParent || navigationController?.isBeingDismissed == true else { return }
        analysisTask?.cancel()
        analysisTask = nil
    }

    private func configureScrollView() {
        scrollView.backgroundColor = .black
        scrollView.alwaysBounceVertical = true
        scrollView.accessibilityIdentifier = "rideAnalysisScrollView"

        contentStack.axis = .vertical
        contentStack.spacing = 12
        contentStack.alignment = .fill
        contentStack.isLayoutMarginsRelativeArrangement = true
        contentStack.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 28, right: 16)

        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)
        scrollView.addSubview(activityIndicator)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            activityIndicator.centerXAnchor.constraint(equalTo: scrollView.frameLayoutGuide.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: scrollView.frameLayoutGuide.centerYAnchor)
        ])
    }

    private func showLoadingState() {
        activityIndicator.color = PTDashboardConfig.shared.appMainColor
        activityIndicator.startAnimating()
        let label = makeBodyLabel(localized("ride_analysis_loading"))
        label.textAlignment = .center
        contentStack.addArrangedSubview(label)
    }

    private func startAnalysis() {
        let report = self.report
        let comparisonPool = self.comparisonPool
        analysisTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                PTRideAnalysisBuilder.make(report: report, comparisonPool: comparisonPool)
            }.value
            guard !Task.isCancelled else { return }
            self?.render(result)
        }
    }

    private func render(_ snapshot: PTRideAnalysisSnapshot) {
        analysisTask = nil
        self.snapshot = snapshot
        activityIndicator.stopAnimating()
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        contentStack.addArrangedSubview(makeHeader(snapshot))
        contentStack.addArrangedSubview(makeSection(
            title: localized("ride_analysis_overview"),
            content: makeMetricGrid([
                (localized("ride_analysis_distance"), distanceText(snapshot.distanceKm)),
                (localized("ride_analysis_duration"), durationText(snapshot.durationSeconds)),
                (localized("ride_analysis_moving_time"), durationText(snapshot.movingTimeSeconds)),
                (localized("ride_analysis_idle_ratio"), percentText(snapshot.idleRatio)),
                (localized("ride_analysis_start_odometer"), distanceText(snapshot.startOdoKm, zeroIsUnavailable: true)),
                (localized("ride_analysis_end_odometer"), distanceText(snapshot.endOdoKm, zeroIsUnavailable: true)),
                (localized("ride_analysis_distance_source"), distanceSourceText(snapshot.distanceSource)),
                (localized("ride_analysis_event_count"), "\(snapshot.eventCount)")
            ])))
        contentStack.addArrangedSubview(makeSection(
            title: localized("ride_analysis_performance"),
            content: makeMetricGrid([
                (localized("ride_analysis_average_speed"), speedText(snapshot.averageSpeedKmh)),
                (localized("ride_analysis_dashboard_max_speed"), speedText(snapshot.dashboardMaxSpeedKmh)),
                (localized("ride_analysis_gps_min_speed"), speedText(snapshot.gpsMinSpeedKmh)),
                (localized("ride_analysis_gps_max_speed"), speedText(snapshot.gpsMaxSpeedKmh)),
                (localized("ride_analysis_average_rpm"), numberText(snapshot.averageRpm, decimals: 0, unit: "rpm")),
                (localized("ride_analysis_max_rpm"), numberText(Double(snapshot.maxRpm), decimals: 0, unit: "rpm")),
                (localized("ride_analysis_consumption"), numberText(snapshot.averageConsumption, decimals: 1, unit: "L/100 km")),
                (localized("ride_analysis_zero_to_hundred"), durationText(snapshot.best0To100Time))
            ])))
        contentStack.addArrangedSubview(makeSection(
            title: localized("ride_analysis_dynamics"),
            content: makeMetricGrid([
                (localized("ride_analysis_left_lean"), numberText(snapshot.maxLeanLeftDegrees, decimals: 1, unit: "°")),
                (localized("ride_analysis_right_lean"), numberText(snapshot.maxLeanRightDegrees, decimals: 1, unit: "°")),
                (localized("ride_analysis_lean_difference"), numberText(snapshot.maxLeanDifferenceDegrees, decimals: 1, unit: "°")),
                (localized("ride_analysis_acceleration_g"), numberText(snapshot.maxAccelerationG, decimals: 2, unit: "G")),
                (localized("ride_analysis_braking_g"), numberText(snapshot.maxBrakingG, decimals: 2, unit: "G")),
                (localized("ride_analysis_cornering_g"), numberText(snapshot.maxCorneringG, decimals: 2, unit: "G")),
                (localized("ride_analysis_bump_g"), numberText(snapshot.maxBumpG, decimals: 2, unit: "G")),
                (localized("ride_analysis_pitch"), "↑ \(numberText(snapshot.maxPitchUpDegrees, decimals: 1, unit: "°"))  ↓ \(numberText(snapshot.maxPitchDownDegrees, decimals: 1, unit: "°"))")
            ])))
        contentStack.addArrangedSubview(makeSection(
            title: localized("ride_analysis_terrain"),
            content: makeMetricGrid([
                (localized("ride_analysis_altitude_gain"), numberText(snapshot.altitudeGainMeters, decimals: 1, unit: "m")),
                (localized("ride_analysis_altitude_loss"), numberText(snapshot.altitudeLossMeters, decimals: 1, unit: "m")),
                (localized("ride_analysis_altitude_range"), rangeText(min: snapshot.altitudeMinMeters, max: snapshot.altitudeMaxMeters, unit: "m")),
                (localized("ride_analysis_pressure_range"), rangeText(min: snapshot.pressureMinHpa, max: snapshot.pressureMaxHpa, unit: "hPa")),
                (localized("ride_analysis_gpx"), snapshot.quality.hasGPX ? localized("ride_analysis_available") : localized("ride_analysis_unavailable")),
                (localized("ride_analysis_common_samples"), "\(snapshot.quality.commonTraceSampleCount)")
            ])))
        contentStack.addArrangedSubview(makeSection(
            title: localized("ride_analysis_traction"),
            content: makeMetricGrid([
                (localized("ride_analysis_max_slip"), numberText(snapshot.maxSlipRatio, decimals: 1, unit: "%")),
                (localized("ride_analysis_heavy_slip"), "\(snapshot.heavySlipCount)"),
                (localized("ride_analysis_offroad_events"), "\(snapshot.offRoadEventCount)"),
                (localized("ride_analysis_event_rate"), numberText(snapshot.eventRatePer100Km, decimals: 1, unit: "/100 km"))
            ])))
        contentStack.addArrangedSubview(makeSection(
            title: localized("ride_analysis_charts"),
            content: makeCharts()))
        contentStack.addArrangedSubview(makeComparisonSection(snapshot))
        contentStack.addArrangedSubview(makeEventsSection(snapshot))
        contentStack.addArrangedSubview(makeQualitySection(snapshot))
        loadRouteThumbnail()
    }

    private func makeHeader(_ snapshot: PTRideAnalysisSnapshot) -> UIView {
        let card = makeCard()
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)

        let vehicleName = report.vehicleID.flatMap { PTMotorcycleGarageStore.shared.vehicle(id: $0)?.name }
            ?? localized("ride_analysis_unassigned_vehicle")
        let title = makeTitleLabel(vehicleName)
        let date = makeBodyLabel("\(formatDate(report.startTime)) → \(formatDate(report.endTime))")
        date.textColor = .lightGray

        let imageView = UIImageView()
        imageView.backgroundColor = UIColor(white: 0.15, alpha: 1)
        imageView.layer.cornerRadius = 12
        imageView.clipsToBounds = true
        imageView.contentMode = .scaleAspectFill
        imageView.image = UIImage(systemName: "map")?.withTintColor(.lightGray, renderingMode: .alwaysOriginal)
        imageView.heightAnchor.constraint(equalToConstant: 150).isActive = true
        routeImageView = imageView

        let summary = makeBodyLabel(
            "\(distanceText(snapshot.distanceKm)) · \(durationText(snapshot.durationSeconds)) · \(speedText(snapshot.averageSpeedKmh))"
        )
        summary.textColor = PTDashboardConfig.shared.appMainColor
        summary.font = UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold)

        let replayButton = makeActionButton(
            title: localized("ride_analysis_replay"),
            icon: "play.circle",
            action: #selector(openReplayButtonTapped)
        )
        let shareImageButton = makeActionButton(
            title: localized("ride_analysis_share_card"),
            icon: "square.and.arrow.up",
            action: #selector(shareSummaryCard)
        )
        let shareJSONButton = makeActionButton(
            title: localized("ride_analysis_share_json"),
            icon: "doc.text",
            action: #selector(shareJSON)
        )
        let actions: UIStackView = UIStackView(arrangedSubviews: [replayButton, shareImageButton, shareJSONButton])
        actions.axis = .horizontal
        actions.spacing = 8
        actions.distribution = .fillEqually

        stack.addArrangedSubview(title)
        stack.addArrangedSubview(date)
        stack.addArrangedSubview(imageView)
        stack.addArrangedSubview(summary)
        stack.addArrangedSubview(actions)
        card.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor)
        ])
        return card
    }

    private func makeCharts() -> UIView {
        let container = UIStackView()
        container.axis = .vertical
        container.spacing = 10

        let speedLines = sampledLines(
            names: [localized("ride_analysis_speed")],
            colors: [.systemRed],
            series: [report.speedTrace]
        )
        let rpmLines = sampledLines(
            names: [localized("ride_analysis_rpm")],
            colors: [.systemGreen],
            series: [report.rpmTrace.map(Double.init)]
        )
        let leanLines = sampledLines(
            names: [localized("ride_analysis_lean")],
            colors: [.systemOrange],
            series: [report.leanAngleTrace]
        )
        let gLines = sampledLines(
            names: [localized("ride_analysis_g_force_x"), localized("ride_analysis_g_force_y"), localized("ride_analysis_g_force_z")],
            colors: [.systemRed, .systemGreen, .systemBlue],
            series: [report.gForceXTrace, report.gForceYTrace, report.gForceZTrace]
        )
        let pitchLines = sampledLines(
            names: [localized("ride_analysis_pitch")],
            colors: [.systemPurple],
            series: [report.pitchTrace]
        )
        let altitudeLines = sampledLines(
            names: [localized("ride_analysis_altitude")],
            colors: [.systemTeal],
            series: [report.relativeAltitudeTrace]
        )
        let pressureLines = sampledLines(
            names: [localized("ride_analysis_pressure")],
            colors: [.systemYellow],
            series: [report.pressureTrace]
        )
        let slipLines = sampledLines(
            names: [localized("ride_analysis_slip")],
            colors: [.systemPink],
            series: [report.slipRatioTrace]
        )

        container.addArrangedSubview(PTRideAnalysisChartCard(
            title: localized("ride_analysis_chart_speed_engine"),
            tabs: [
                .init(title: localized("ride_analysis_speed"), lines: speedLines),
                .init(title: localized("ride_analysis_rpm"), lines: rpmLines)
            ]
        ))
        container.addArrangedSubview(PTRideAnalysisChartCard(
            title: localized("ride_analysis_chart_dynamics"),
            tabs: [
                .init(title: localized("ride_analysis_lean"), lines: leanLines),
                .init(title: localized("ride_analysis_g_force"), lines: gLines),
                .init(title: localized("ride_analysis_pitch"), lines: pitchLines)
            ]
        ))
        container.addArrangedSubview(PTRideAnalysisChartCard(
            title: localized("ride_analysis_chart_environment"),
            tabs: [
                .init(title: localized("ride_analysis_altitude"), lines: altitudeLines),
                .init(title: localized("ride_analysis_pressure"), lines: pressureLines)
            ]
        ))
        container.addArrangedSubview(PTRideAnalysisChartCard(
            title: localized("ride_analysis_chart_traction"),
            tabs: [.init(title: localized("ride_analysis_slip"), lines: slipLines)]
        ))
        return container
    }

    private func sampledLines(
        names: [String],
        colors: [UIColor],
        series: [[Double]]
    ) -> [PTChartLineModel] {
        let indices = PTRideAnalysisDownsampler.commonIndices(for: series, maximumCount: 600)
        let referenceCount = series.map(\.count).max() ?? 0
        guard referenceCount > 0 else { return [] }
        return zip(names, zip(colors, series)).compactMap { name, pair in
            let values = PTRideAnalysisDownsampler.values(
                pair.1,
                at: indices,
                referenceCount: referenceCount
            )
            guard !values.isEmpty else { return nil }
            return PTChartLineModel(name: name, color: pair.0, data: values)
        }
    }

    private func makeComparisonSection(_ snapshot: PTRideAnalysisSnapshot) -> UIView {
        let body: UIView
        if snapshot.comparisons.isEmpty {
            let key = report.vehicleID == nil
                ? "ride_analysis_history_no_vehicle"
                : "ride_analysis_history_insufficient"
            body = makeBodyLabel(localized(key))
        } else {
            let metrics = snapshot.comparisons.map { comparison in
                let title = comparisonTitle(comparison.metricKey)
                let value = comparisonValue(comparison)
                return (title, value)
            }
            body = makeMetricGrid(metrics)
        }
        return makeSection(title: localized("ride_analysis_history"), content: body)
    }

    private func makeEventsSection(_ snapshot: PTRideAnalysisSnapshot) -> UIView {
        let container = UIStackView()
        container.axis = .vertical
        container.spacing = 8
        eventTimestamps.removeAll()

        if !snapshot.eventBreakdown.isEmpty {
            let breakdown = snapshot.eventBreakdown
                .sorted { $0.key < $1.key }
                .map { "\(eventBreakdownTitle($0.key)): \($0.value)" }
                .joined(separator: " · ")
            container.addArrangedSubview(makeBodyLabel(breakdown))
        }

        if snapshot.events.isEmpty {
            container.addArrangedSubview(makeBodyLabel(localized("ride_analysis_no_events")))
        } else {
            for (index, event) in snapshot.events.enumerated() {
                eventTimestamps[index] = event.timestamp
                let button = UIButton(type: .system)
                button.tag = index
                button.contentHorizontalAlignment = .left
                button.titleLabel?.numberOfLines = 2
                button.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .medium)
                var configuration = UIButton.Configuration.plain()
                configuration.title = eventTitle(event)
                configuration.baseForegroundColor = .white
                configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)
                configuration.background.backgroundColor = UIColor(white: 0.14, alpha: 1)
                configuration.background.cornerRadius = 10
                button.configuration = configuration
                button.accessibilityLabel = eventTitle(event)
                button.accessibilityHint = localized("ride_analysis_event_open_hint")
                button.addTarget(self, action: #selector(openEventReplay(_:)), for: .touchUpInside)
                container.addArrangedSubview(button)
            }
        }
        return makeSection(title: localized("ride_analysis_events"), content: container)
    }

    private func eventBreakdownTitle(_ key: String) -> String {
        switch key {
        case PTRideReviewEventType.hardBraking.rawValue:
            return localized("ride_replay_event_hard_braking")
        case PTRideReviewEventType.hardAcceleration.rawValue:
            return localized("ride_replay_event_hard_acceleration")
        case PTRideReviewEventType.heavyBump.rawValue:
            return localized("ride_replay_event_heavy_bump")
        case PTRideReviewEventType.highLean.rawValue:
            return localized("ride_replay_event_high_lean")
        case PTRideReviewEventType.suspectedSlip.rawValue:
            return localized("ride_replay_event_suspected_slip")
        case "offRoad":
            return localized("ride_analysis_offroad_events")
        default:
            return key
        }
    }

    private func makeQualitySection(_ snapshot: PTRideAnalysisSnapshot) -> UIView {
        let counts = snapshot.quality.traceSampleCounts
            .sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: " · ")
        let body = UIStackView()
        body.axis = .vertical
        body.spacing = 6
        body.addArrangedSubview(makeBodyLabel(
            "\(localized("ride_analysis_schema")): \(snapshot.quality.reportSchemaVersion) · \(localized("ride_analysis_samples")): \(counts)"
        ))
        body.addArrangedSubview(makeBodyLabel(localized("ride_analysis_timeline_estimated")))
        if snapshot.quality.warnings.contains(PTRideAnalysisQualityWarning.noTrace) {
            body.addArrangedSubview(makeWarningLabel(localized("ride_analysis_no_data")))
        }
        if snapshot.quality.hasTraceLengthMismatch {
            body.addArrangedSubview(makeWarningLabel(localized("ride_analysis_warning_trace_length")))
        }
        if !snapshot.quality.hasGPX {
            body.addArrangedSubview(makeWarningLabel(localized("ride_analysis_warning_missing_gpx")))
        }
        if !snapshot.quality.hasVehicleBinding {
            body.addArrangedSubview(makeWarningLabel(localized("ride_analysis_warning_unbound_vehicle")))
        }
        return makeSection(title: localized("ride_analysis_data_quality"), content: body)
    }

    private func makeSection(title: String, content: UIView) -> UIView {
        let card = makeCard()
        let stack = UIStackView(arrangedSubviews: [makeTitleLabel(title), content])
        stack.axis = .vertical
        stack.spacing = 10
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        card.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor)
        ])
        return card
    }

    private func makeMetricGrid(_ values: [(String, String)]) -> UIView {
        let grid = UIStackView()
        grid.axis = .vertical
        grid.spacing = 10
        grid.distribution = .fillEqually

        for start in stride(from: 0, to: values.count, by: 2) {
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 10
            row.distribution = .fillEqually
            row.addArrangedSubview(makeMetric(title: values[start].0, value: values[start].1))
            if start + 1 < values.count {
                row.addArrangedSubview(makeMetric(title: values[start + 1].0, value: values[start + 1].1))
            } else {
                row.addArrangedSubview(UIView())
            }
            grid.addArrangedSubview(row)
        }
        return grid
    }

    private func makeMetric(title: String, value: String) -> UIView {
        let titleLabel = makeBodyLabel(title)
        titleLabel.font = UIFont.systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .lightGray
        let valueLabel = makeBodyLabel(value)
        valueLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        valueLabel.textColor = .white
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.7

        let stack = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        stack.axis = .vertical
        stack.spacing = 3
        stack.alignment = .fill
        return stack
    }

    private func makeCard() -> UIView {
        let card = UIView()
        card.backgroundColor = UIColor(white: 0.08, alpha: 1)
        card.layer.cornerRadius = 14
        card.clipsToBounds = true
        return card
    }

    private func makeTitleLabel(_ text: String) -> UILabel {
        let label = makeBodyLabel(text)
        label.font = UIFont.monospacedSystemFont(ofSize: 15, weight: .bold)
        label.textColor = PTDashboardConfig.shared.appMainColor
        return label
    }

    private func makeBodyLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 13, weight: .regular)
        label.numberOfLines = 0
        return label
    }

    private func makeWarningLabel(_ text: String) -> UILabel {
        let label = makeBodyLabel(text)
        label.textColor = .systemOrange
        return label
    }

    private func makeActionButton(title: String, icon: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.image = UIImage(systemName: icon)
        configuration.imagePadding = 4
        configuration.baseForegroundColor = .white
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 5, bottom: 8, trailing: 5)
        configuration.background.backgroundColor = UIColor(white: 0.15, alpha: 1)
        configuration.background.cornerRadius = 9
        button.configuration = configuration
        button.titleLabel?.font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        button.titleLabel?.numberOfLines = 2
        button.addTarget(self, action: action, for: .touchUpInside)
        button.accessibilityLabel = title
        return button
    }

    private func loadRouteThumbnail() {
        guard let gpxFileName = report.gpxFileName else { return }
        let imageName = gpxFileName.replacingOccurrences(of: ".gpx", with: ".jpg")
        PTiCloudFileManager.shared.fetchCloudFileIfNeeded(fileName: imageName) { [weak self] localURL in
            guard let localURL else { return }
            DispatchQueue.main.async {
                guard let self, let imageView = self.routeImageView else { return }
                imageView.image = UIImage(contentsOfFile: localURL.path) ?? imageView.image
            }
        }
    }

    @objc private func openReplayButtonTapped() {
        openReplay(at: nil)
    }

    @objc private func openEventReplay(_ sender: UIButton) {
        openReplay(at: eventTimestamps[sender.tag])
    }

    private func openReplay(at timestamp: Date?) {
        let replay = PTRideReplayViewController(report: report, initialTimestamp: timestamp)
        navigationController?.pushViewController(replay, animated: true)
    }

    @objc private func shareSummaryCard() {
        guard let snapshot else { return }
        let image = makeSummaryImage(snapshot)
        let activity = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        presentActivity(activity)
    }

    @objc private func shareJSON() {
        guard let snapshot else { return }
        let urlTask = Task { [weak self] in
            let url = await Task.detached(priority: .utility) {
                Self.makeJSONFile(snapshot: snapshot)
            }.value
            guard !Task.isCancelled, let self, let url else { return }
            let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            activity.completionWithItemsHandler = { _, _, _, _ in
                try? FileManager.default.removeItem(at: url)
            }
            self.presentActivity(activity)
        }
        analysisTask = urlTask
    }

    private func presentActivity(_ activity: UIActivityViewController) {
        if let popover = activity.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        }
        present(activity, animated: true)
    }

    nonisolated private static func makeJSONFile(snapshot: PTRideAnalysisSnapshot) -> URL? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return nil }
        let fileName = "PTSpeed-Ride-Analysis-\(Int(Date().timeIntervalSince1970)).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        return url
    }

    private func makeSummaryImage(_ snapshot: PTRideAnalysisSnapshot) -> UIImage {
        let size = CGSize(width: 900, height: 1_100)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor(white: 0.06, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 40, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            let bodyAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 25, weight: .medium),
                .foregroundColor: UIColor.white
            ]
            let accentAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 28, weight: .semibold),
                .foregroundColor: PTDashboardConfig.shared.appMainColor
            ]

            localized("ride_analysis_title").draw(at: CGPoint(x: 50, y: 55), withAttributes: titleAttributes)
            formatDate(report.startTime).draw(at: CGPoint(x: 50, y: 120), withAttributes: bodyAttributes)

            let lines = [
                "\(localized("ride_analysis_distance")): \(distanceText(snapshot.distanceKm))",
                "\(localized("ride_analysis_duration")): \(durationText(snapshot.durationSeconds))",
                "\(localized("ride_analysis_average_speed")): \(speedText(snapshot.averageSpeedKmh))",
                "\(localized("ride_analysis_dashboard_max_speed")): \(speedText(snapshot.dashboardMaxSpeedKmh))",
                "\(localized("ride_analysis_max_rpm")): \(numberText(Double(snapshot.maxRpm), decimals: 0, unit: "rpm"))",
                "\(localized("ride_analysis_left_lean")): \(numberText(snapshot.maxLeanLeftDegrees, decimals: 1, unit: "°"))",
                "\(localized("ride_analysis_right_lean")): \(numberText(snapshot.maxLeanRightDegrees, decimals: 1, unit: "°"))",
                "\(localized("ride_analysis_event_count")): \(snapshot.eventCount)"
            ]
            for (index, line) in lines.enumerated() {
                line.draw(at: CGPoint(x: 50, y: 220 + CGFloat(index * 75)), withAttributes: index == 0 ? accentAttributes : bodyAttributes)
            }
            localized("ride_analysis_share_redacted").draw(
                at: CGPoint(x: 50, y: 900),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 20),
                    .foregroundColor: UIColor.lightGray
                ]
            )
        }
    }

    private func eventTitle(_ event: PTRideAnalysisEvent) -> String {
        let title = localized(event.titleKey)
        let time = durationText(event.offsetSeconds)
        let speed = speedText(event.speedKmh)
        let peak = numberText(event.peakValue, decimals: 2, unit: "")
        return "\(title) · \(time)\n\(localized("ride_analysis_event_speed")): \(speed) · \(localized("ride_analysis_event_peak")): \(peak)"
    }

    private func comparisonTitle(_ key: String) -> String {
        switch key {
        case PTRideAnalysisMetricKey.distance: return localized("ride_analysis_distance")
        case PTRideAnalysisMetricKey.averageSpeed: return localized("ride_analysis_average_speed")
        case PTRideAnalysisMetricKey.maxSpeed: return localized("ride_analysis_dashboard_max_speed")
        case PTRideAnalysisMetricKey.idleRatio: return localized("ride_analysis_idle_ratio")
        case PTRideAnalysisMetricKey.eventRate: return localized("ride_analysis_event_rate")
        case PTRideAnalysisMetricKey.maxLean: return localized("ride_analysis_max_lean")
        default: return key
        }
    }

    private func comparisonValue(_ comparison: PTRideAnalysisComparison) -> String {
        let current = formattedComparisonValue(comparison.currentValue, key: comparison.metricKey)
        let baseline = formattedComparisonValue(comparison.historicalAverage, key: comparison.metricKey)
        let delta = formattedComparisonDelta(comparison.delta, key: comparison.metricKey)
        return "\(current) · \(localized("ride_analysis_recent_average")): \(baseline) · Δ \(delta)"
    }

    private func formattedComparisonValue(_ value: Double, key: String) -> String {
        switch key {
        case PTRideAnalysisMetricKey.distance: return distanceText(value)
        case PTRideAnalysisMetricKey.averageSpeed, PTRideAnalysisMetricKey.maxSpeed: return speedText(value)
        case PTRideAnalysisMetricKey.idleRatio: return percentText(value)
        case PTRideAnalysisMetricKey.eventRate: return numberText(value, decimals: 1, unit: "/100 km")
        case PTRideAnalysisMetricKey.maxLean: return numberText(value, decimals: 1, unit: "°")
        default: return numberText(value, decimals: 1, unit: "")
        }
    }

    private func formattedComparisonDelta(_ value: Double, key: String) -> String {
        switch key {
        case PTRideAnalysisMetricKey.distance: return signedDistanceText(value)
        case PTRideAnalysisMetricKey.averageSpeed, PTRideAnalysisMetricKey.maxSpeed: return signedSpeedText(value)
        case PTRideAnalysisMetricKey.idleRatio: return signedPercentText(value)
        case PTRideAnalysisMetricKey.eventRate: return numberText(value, decimals: 1, unit: "/100 km", signed: true)
        case PTRideAnalysisMetricKey.maxLean: return numberText(value, decimals: 1, unit: "°", signed: true)
        default: return numberText(value, decimals: 1, unit: "", signed: true)
        }
    }

    private func localized(_ key: String) -> String {
        PTDashboardConfig.languageFunc(text: key)
    }

    private func distanceSourceText(_ source: PTTripDistanceSource) -> String {
        localized(source == .odometer ? "ride_analysis_source_odometer" : "ride_analysis_source_gps")
    }

    private func distanceText(_ value: Double?, zeroIsUnavailable: Bool = false) -> String {
        guard let value, value.isFinite, (!zeroIsUnavailable || value > 0) else {
            return localized("ride_analysis_unavailable")
        }
        let displayValue = PTDashboardConfig.shared.appShowMileage(value)
        return "\(String(format: "%.2f", displayValue)) \(PTDashboardConfig.shared.appShowUniLabel)"
    }

    private func speedText(_ value: Double?) -> String {
        guard let value, value.isFinite, value > 0 else { return localized("ride_analysis_unavailable") }
        let displayValue = PTDashboardConfig.shared.appShowMileage(value)
        return "\(String(format: "%.1f", displayValue)) \(PTDashboardConfig.shared.appShowUniLabel)/h"
    }

    private func numberText(_ value: Double?, decimals: Int, unit: String, signed: Bool = false) -> String {
        guard let value, value.isFinite else { return localized("ride_analysis_unavailable") }
        let format = signed ? "%+.\(decimals)f" : "%.\(decimals)f"
        let number = String(format: format, value)
        return unit.isEmpty ? number : "\(number) \(unit)"
    }

    private func percentText(_ value: Double) -> String {
        "\(String(format: "%.1f", value * 100))%"
    }

    private func signedPercentText(_ value: Double) -> String {
        "\(String(format: "%+.1f", value * 100))%"
    }

    private func signedDistanceText(_ value: Double) -> String {
        guard value.isFinite else { return localized("ride_analysis_unavailable") }
        return distanceText(value).replacingOccurrences(of: "-", with: "−", options: .literal, range: nil)
    }

    private func signedSpeedText(_ value: Double) -> String {
        guard value.isFinite else { return localized("ride_analysis_unavailable") }
        let displayValue = PTDashboardConfig.shared.appShowMileage(abs(value))
        let sign = value >= 0 ? "+" : "−"
        return "\(sign)\(String(format: "%.1f", displayValue)) \(PTDashboardConfig.shared.appShowUniLabel)/h"
    }

    private func rangeText(min: Double?, max: Double?, unit: String) -> String {
        guard let min, let max, min.isFinite, max.isFinite else {
            return localized("ride_analysis_unavailable")
        }
        return "\(String(format: "%.1f", min))–\(String(format: "%.1f", max)) \(unit)"
    }

    private func durationText(_ value: TimeInterval?) -> String {
        guard let value, value.isFinite, value > 0 else { return localized("ride_analysis_unavailable") }
        return durationText(value)
    }

    private func durationText(_ value: TimeInterval) -> String {
        let totalSeconds = max(Int(value.rounded()), 0)
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        return hours > 0
            ? String(format: "%02d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// EN: A chart card keeps only one chart visible at a time, limiting layer count while retaining every telemetry series.
// ES: La tarjeta muestra un solo gráfico cada vez, limita las capas y conserva todas las series de telemetría.
// 中文：图表卡一次只显示一张图，限制图层数量，同时保留全部遥测序列。
@MainActor
private final class PTRideAnalysisChartCard: UIView {
    struct Tab {
        let title: String
        let lines: [PTChartLineModel]
    }

    private let titleLabel = UILabel()
    private let segmentedControl: UISegmentedControl
    private let chartView = PTNativeTelemetryChartView()
    private let emptyLabel = UILabel()
    private let tabs: [Tab]

    init(title: String, tabs: [Tab]) {
        self.tabs = tabs
        self.segmentedControl = UISegmentedControl(items: tabs.map(\.title))
        super.init(frame: .zero)
        backgroundColor = UIColor(white: 0.11, alpha: 1)
        layer.cornerRadius = 12
        clipsToBounds = true
        configure(title: title)
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func configure(title: String) {
        titleLabel.text = title
        titleLabel.textColor = .white
        titleLabel.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .bold)

        segmentedControl.selectedSegmentIndex = 0
        segmentedControl.selectedSegmentTintColor = PTDashboardConfig.shared.appMainColor
        segmentedControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)
        segmentedControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        segmentedControl.addTarget(self, action: #selector(selectionChanged), for: .valueChanged)
        if tabs.count < 2 {
            segmentedControl.isHidden = true
        }

        emptyLabel.text = PTDashboardConfig.languageFunc(text: "ride_analysis_no_data")
        emptyLabel.textColor = .gray
        emptyLabel.textAlignment = .center
        emptyLabel.isHidden = true

        let stack = UIStackView(arrangedSubviews: [titleLabel, segmentedControl, chartView, emptyLabel])
        stack.axis = .vertical
        stack.spacing = 8
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 12, left: 10, bottom: 10, right: 10)
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        chartView.heightAnchor.constraint(equalToConstant: 180).isActive = true
        emptyLabel.heightAnchor.constraint(equalToConstant: 180).isActive = true
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        updateChart()
    }

    @objc private func selectionChanged() {
        updateChart()
    }

    private func updateChart() {
        guard tabs.indices.contains(segmentedControl.selectedSegmentIndex) else { return }
        let lines = tabs[segmentedControl.selectedSegmentIndex].lines
        chartView.isHidden = lines.isEmpty
        emptyLabel.isHidden = !lines.isEmpty
        if !lines.isEmpty {
            chartView.bindData(lines: lines)
        }
    }
}
