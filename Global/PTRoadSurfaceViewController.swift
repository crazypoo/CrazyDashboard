//
//  PTRoadSurfaceViewController.swift
//  CrazyDashboard
//
//  EN: A read-only Build 79 road-surface summary built on PTMotoBaseViewController.
//  ES: Un resumen de superficie de carretera de solo lectura construido sobre PTMotoBaseViewController.
//  中文：基于 PTMotoBaseViewController 构建的 Build 79 只读道路体验摘要页面。
//

import UIKit
import MapKit
import PooTools
import SnapKit

@MainActor
final class PTRoadSurfaceViewController: PTMotoBaseViewController, MKMapViewDelegate {
    private let vehicleID: UUID
    private let repository: PTRoadSurfaceRepository

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let mapView = MKMapView()
    private let vehicleLabel = UILabel()
    private let qualityLabel = UILabel()
    private let sourceLabel = UILabel()
    private let summaryStack = UIStackView()
    private let segmentsTitleLabel = UILabel()
    private let segmentsStack = UIStackView()
    private let refreshButton = UIButton(type: .system)
    private let exportButton = UIButton(type: .system)
    private let calibrationButton = UIButton(type: .system)
    private var isObservingRepository = false

    init(vehicleID: UUID, repository: PTRoadSurfaceRepository? = nil) {
        self.vehicleID = vehicleID
        self.repository = repository ?? PTRoadSurfaceRepository.shared
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        pt_Title = localized("road_surface_intelligence", fallback: "Road Surface")
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

        qualityLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        qualityLabel.numberOfLines = 0

        sourceLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        sourceLabel.textColor = .systemGray2
        sourceLabel.numberOfLines = 0

        summaryStack.axis = .vertical
        summaryStack.spacing = 8

        segmentsTitleLabel.text = localized("road_surface_segments", fallback: "Recent road segments")
        segmentsTitleLabel.textColor = .white
        segmentsTitleLabel.font = .systemFont(ofSize: 17, weight: .semibold)

        segmentsStack.axis = .vertical
        segmentsStack.spacing = 8

        mapView.delegate = self
        mapView.mapType = .standard
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
        mapView.layer.cornerRadius = 14
        mapView.clipsToBounds = true

        configureActionButton(refreshButton, title: localized("button_refresh", fallback: "Refresh"))
        refreshButton.addTarget(self, action: #selector(refreshTapped), for: .touchUpInside)
        configureActionButton(exportButton, title: localized("can_lab_share", fallback: "Share"))
        exportButton.addTarget(self, action: #selector(exportTapped), for: .touchUpInside)
        configureActionButton(calibrationButton, title: localized("road_surface_calibrate", fallback: "Calibrate mount"))
        calibrationButton.addTarget(self, action: #selector(calibrateTapped), for: .touchUpInside)

        let header = UIStackView(arrangedSubviews: [vehicleLabel, qualityLabel, sourceLabel])
        header.axis = .vertical
        header.spacing = 5

        let actionRow = UIStackView(arrangedSubviews: [refreshButton, exportButton])
        actionRow.axis = .horizontal
        actionRow.spacing = 8
        actionRow.distribution = .fillEqually

        contentStack.axis = .vertical
        contentStack.spacing = 12
        contentStack.addArrangedSubview(mapView)
        contentStack.addArrangedSubview(header)
        contentStack.addArrangedSubview(summaryStack)
        contentStack.addArrangedSubview(segmentsTitleLabel)
        contentStack.addArrangedSubview(segmentsStack)
        contentStack.addArrangedSubview(actionRow)
        contentStack.addArrangedSubview(calibrationButton)

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
        mapView.snp.makeConstraints { make in
            make.height.equalTo(220)
        }
        refreshButton.snp.makeConstraints { make in
            make.height.equalTo(44)
        }
        exportButton.snp.makeConstraints { make in
            make.height.equalTo(44)
        }
        calibrationButton.snp.makeConstraints { make in
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

    private func startObservingRepository() {
        guard !isObservingRepository else { return }
        isObservingRepository = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(repositoryDidChange),
            name: PTRoadSurfaceRepository.didChange,
            object: repository
        )
    }

    private func stopObservingRepository() {
        guard isObservingRepository else { return }
        isObservingRepository = false
        NotificationCenter.default.removeObserver(
            self,
            name: PTRoadSurfaceRepository.didChange,
            object: repository
        )
    }

    @objc private func repositoryDidChange() {
        refreshView()
    }

    @objc private func refreshTapped() {
        refreshView()
    }

    // EN: Calibration is allowed only while parked and never sends a vehicle command.
    // ES: La calibración solo se permite estando estacionado y nunca envía un comando al vehículo.
    // 中文：只有停车状态才能校准，而且校准绝不会向车辆发送指令。
    @objc private func calibrateTapped() {
        let success = repository.calibrateCurrentMount(for: vehicleID)
        showMessage(localized(
            success ? "road_surface_calibration_success" : "road_surface_calibration_unavailable",
            fallback: success ? "Mount calibration saved" : "Stop the vehicle before calibrating"
        ))
    }

    @objc private func exportTapped() {
        do {
            guard let url = try repository.exportURL(for: vehicleID) else {
                showMessage(localized("road_surface_no_data", fallback: "No road-surface data"))
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
            qualityLabel.text = localized("road_surface_no_data", fallback: "No road-surface data")
            qualityLabel.textColor = .systemGray2
            sourceLabel.text = nil
            clearStack(summaryStack)
            clearStack(segmentsStack)
            renderMap([])
            return
        }

        let summary = repository.summary(for: vehicleID)
        vehicleLabel.text = vehicle.name
        qualityLabel.text = "\(localized("road_surface_quality", fallback: "Surface")): \(qualityText(summary.overallQuality))"
        qualityLabel.textColor = qualityColor(summary.overallQuality)
        sourceLabel.text = sourceText(summary)
        rebuildSummary(summary)
        let segments = repository.segments(for: vehicleID)
        rebuildSegments(segments)
        renderMap(segments)
    }

    private func rebuildSummary(_ summary: PTRoadSurfaceSummary) {
        clearStack(summaryStack)
        let average = summary.averageScore.map { String(format: "%.0f / 100", $0) } ?? "--"
        let maximum = summary.maximumScore.map { String(format: "%.0f / 100", $0) } ?? "--"
        let impact = summary.maximumVerticalImpactG.map { String(format: "%.2f G", $0) } ?? "--"
        let distance = formatDistance(summary.coveredDistanceMeters)
        let rows = [
            (localized("road_surface_score", fallback: "Average score"), average),
            (localized("road_surface_peak", fallback: "Peak score"), maximum),
            (localized("road_surface_max_impact", fallback: "Peak impact"), impact),
            (localized("road_surface_coverage", fallback: "Coverage"), distance),
            (localized("road_surface_rough_segments", fallback: "Rough segments"), String(summary.roughSegmentCount)),
            (localized("road_surface_severe_segments", fallback: "Severe segments"), String(summary.severeSegmentCount))
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

    private func rebuildSegments(_ segments: [PTRoadSurfaceSegment]) {
        clearStack(segmentsStack)
        let visible = segments.prefix(12)
        guard !visible.isEmpty else {
            segmentsStack.addArrangedSubview(summaryCard(
                title: localized("road_surface_no_data", fallback: "No road-surface data"),
                value: "--"
            ))
            return
        }

        visible.forEach { segment in
            let card = summaryCard(
                title: "\(formattedDate(segment.endedAt)) · \(qualityText(segment.quality))",
                value: "\(localized("road_surface_score", fallback: "Score")): \(String(format: "%.0f", segment.score)) · \(String(format: "%.2f G", segment.maxVerticalImpactG)) · \(formatDistance(segment.distanceMeters))"
            )
            segmentsStack.addArrangedSubview(card)
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
        valueLabel.numberOfLines = 3

        card.addArrangedSubview(titleLabel)
        card.addArrangedSubview(valueLabel)
        return card
    }

    private func clearStack(_ stack: UIStackView) {
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
    }

    private func sourceText(_ summary: PTRoadSurfaceSummary) -> String {
        let kind = summary.isSyntheticOnly
            ? localized("road_surface_source_mock", fallback: "Mock")
            : localized("road_surface_source_live", fallback: "Live / history")
        let date = summary.latestSegmentAt.map(formattedDate) ?? "--"
        return "\(kind) · \(summary.segmentCount) · \(date)"
    }

    private func qualityText(_ quality: PTRoadSurfaceQuality) -> String {
        switch quality {
        case .smooth: return localized("road_surface_smooth", fallback: "Smooth")
        case .moderate: return localized("road_surface_moderate", fallback: "Moderate")
        case .rough: return localized("road_surface_rough", fallback: "Rough")
        case .severe: return localized("road_surface_severe", fallback: "Severe")
        case .unknown: return localized("road_surface_no_data", fallback: "No data")
        }
    }

    private func qualityColor(_ quality: PTRoadSurfaceQuality) -> UIColor {
        switch quality {
        case .smooth: return .systemGreen
        case .moderate: return .systemYellow
        case .rough: return .systemOrange
        case .severe: return .systemRed
        case .unknown: return .systemGray2
        }
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1_000 {
            return String(format: "%.2f km", meters / 1_000)
        }
        return String(format: "%.0f m", meters)
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    private func renderMap(_ segments: [PTRoadSurfaceSegment]) {
        mapView.removeOverlays(mapView.overlays)
        mapView.removeAnnotations(mapView.annotations)
        let coordinates = segments.flatMap { segment in
            [
                CLLocationCoordinate2D(latitude: segment.startLatitude, longitude: segment.startLongitude),
                CLLocationCoordinate2D(latitude: segment.endLatitude, longitude: segment.endLongitude)
            ]
        }
        guard !coordinates.isEmpty else { return }
        if coordinates.count > 1 {
            mapView.addOverlay(MKPolyline(coordinates: coordinates, count: coordinates.count))
        }
        segments.prefix(20).forEach { segment in
            let annotation = MKPointAnnotation()
            annotation.coordinate = CLLocationCoordinate2D(
                latitude: segment.endLatitude,
                longitude: segment.endLongitude
            )
            annotation.title = qualityText(segment.quality)
            mapView.addAnnotation(annotation)
        }
        var rect = MKMapRect.null
        coordinates.forEach { rect = rect.union(MKMapRect(origin: MKMapPoint($0), size: MKMapSize(width: 1, height: 1))) }
        mapView.setVisibleMapRect(
            rect,
            edgePadding: UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24),
            animated: false
        )
    }

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        guard let polyline = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
        let renderer = MKPolylineRenderer(polyline: polyline)
        renderer.strokeColor = PTDashboardConfig.shared.appMainColor
        renderer.lineWidth = 4
        renderer.lineJoin = .round
        return renderer
    }

    private func showMessage(_ message: String) {
        let alert = UIAlertController(
            title: localized("road_surface_intelligence", fallback: "Road Surface"),
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
