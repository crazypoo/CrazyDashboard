//
//  PTRideReplayViewController.swift
//  CrazyDashboard
//
//  EN: Map-based offline ride replay with synchronized telemetry and events.
//  ES: Reproducción offline basada en mapa con telemetría y eventos sincronizados.
//  中文：基于地图的离线骑行回放，同时同步遥测数据和事件。
//

import UIKit
import SnapKit
import AMapNaviKit
import PooTools

@MainActor
final class PTRideReplayViewController: PTMotoBaseViewController,
                                         MAMapViewDelegate,
                                         UITableViewDataSource,
                                         UITableViewDelegate {
    private let report: PTTripReport
    private var session: PTRideReplaySession?
    private var player: PTRideReplayPlayer?
    private var loadTask: Task<Void, Never>?
    private var routeOverlay: MAPolyline?
    private var eventAnnotations: [MAPointAnnotation] = []
    private var currentEventID: UUID?
    private var hasConfiguredMap = false

    private lazy var mapView: MAMapView = {
        let view = PTGlobalMapManager.shared.makeMapView()
        view.delegate = self
        view.showsUserLocation = false
        view.userTrackingMode = .none
        view.showsCompass = false
        view.showsScale = false
        view.isShowTraffic = false
        view.logoEnable = false
        return view
    }()

    private let replayAnnotation = MAPointAnnotation()
    private let summaryLabel = UILabel()
    private let stateLabel = UILabel()
    private let timeLabel = UILabel()
    private let speedValueLabel = UILabel()
    private let rpmValueLabel = UILabel()
    private let leanValueLabel = UILabel()
    private let gValueLabel = UILabel()
    private let progressSlider = UISlider()
    private let playButton = UIButton(type: .system)
    private let previousButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private let eventsTitleLabel = UILabel()
    private let eventsTableView = UITableView(frame: .zero, style: .insetGrouped)
    private let activityIndicator = UIActivityIndicatorView(style: .medium)

    init(report: PTTripReport) {
        self.report = report
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = PTDashboardConfig.languageFunc(text: "ride_replay_title")
        view.backgroundColor = .black
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(close)
        )
        configureLabels()
        configureControls()
        configureLayout()
        loadReplay()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        player?.pause()
    }

    @objc private func close() {
        dismiss(animated: true)
    }

    private func configureLabels() {
        summaryLabel.textColor = .lightGray
        summaryLabel.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        summaryLabel.numberOfLines = 2

        stateLabel.textColor = PTDashboardConfig.shared.appMainColor
        stateLabel.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .bold)

        timeLabel.textColor = .white
        timeLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        timeLabel.textAlignment = .center

        [speedValueLabel, rpmValueLabel, leanValueLabel, gValueLabel].forEach {
            $0.textColor = .white
            $0.font = UIFont.monospacedDigitSystemFont(ofSize: 15, weight: .bold)
            $0.textAlignment = .center
            $0.adjustsFontSizeToFitWidth = true
            $0.minimumScaleFactor = 0.7
        }

        eventsTitleLabel.text = PTDashboardConfig.languageFunc(text: "ride_replay_events")
        eventsTitleLabel.textColor = PTDashboardConfig.shared.appMainColor
        eventsTitleLabel.font = UIFont.monospacedSystemFont(ofSize: 15, weight: .bold)
    }

    private func configureControls() {
        progressSlider.minimumValue = 0
        progressSlider.maximumValue = 1
        progressSlider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
        progressSlider.minimumTrackTintColor = PTDashboardConfig.shared.appMainColor
        progressSlider.accessibilityIdentifier = "rideReplayProgress"

        configureControlButton(previousButton, title: "⏮", action: #selector(previousSample))
        configureControlButton(playButton, title: "▶︎", action: #selector(togglePlayback))
        configureControlButton(nextButton, title: "⏭", action: #selector(nextSample))
        playButton.accessibilityIdentifier = "rideReplayPlayPause"

        eventsTableView.dataSource = self
        eventsTableView.delegate = self
        eventsTableView.backgroundColor = .clear
        eventsTableView.separatorColor = UIColor.white.withAlphaComponent(0.12)
        eventsTableView.rowHeight = 50
        eventsTableView.tableFooterView = UIView(frame: .zero)
        eventsTableView.backgroundView = emptyEventsView()

        activityIndicator.color = PTDashboardConfig.shared.appMainColor
        activityIndicator.hidesWhenStopped = true
    }

    private func configureControlButton(_ button: UIButton,
                                         title: String,
                                         action: Selector) {
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 20, weight: .bold)
        button.backgroundColor = UIColor(white: 0.14, alpha: 1)
        button.layer.cornerRadius = 10
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private func configureLayout() {
        view.addSubview(mapView)
        view.addSubview(summaryLabel)
        view.addSubview(stateLabel)

        let metrics = UIStackView(arrangedSubviews: [
            makeMetric(title: PTDashboardConfig.languageFunc(text: "ride_replay_speed"), valueLabel: speedValueLabel),
            makeMetric(title: PTDashboardConfig.languageFunc(text: "ride_replay_rpm"), valueLabel: rpmValueLabel),
            makeMetric(title: PTDashboardConfig.languageFunc(text: "ride_replay_lean"), valueLabel: leanValueLabel),
            makeMetric(title: PTDashboardConfig.languageFunc(text: "ride_replay_g_force"), valueLabel: gValueLabel)
        ])
        metrics.axis = .horizontal
        metrics.distribution = .fillEqually
        metrics.spacing = 8
        view.addSubview(metrics)

        view.addSubview(timeLabel)
        view.addSubview(progressSlider)

        let controls = UIStackView(arrangedSubviews: [previousButton, playButton, nextButton])
        controls.axis = .horizontal
        controls.distribution = .fillEqually
        controls.spacing = 8
        view.addSubview(controls)

        view.addSubview(eventsTitleLabel)
        view.addSubview(eventsTableView)
        view.addSubview(activityIndicator)

        mapView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.left.right.equalToSuperview()
            make.height.equalTo(250)
        }
        summaryLabel.snp.makeConstraints { make in
            make.top.equalTo(mapView.snp.bottom).offset(8)
            make.left.right.equalToSuperview().inset(16)
        }
        stateLabel.snp.makeConstraints { make in
            make.top.equalTo(summaryLabel.snp.bottom).offset(4)
            make.left.right.equalTo(summaryLabel)
        }
        metrics.snp.makeConstraints { make in
            make.top.equalTo(stateLabel.snp.bottom).offset(10)
            make.left.right.equalToSuperview().inset(12)
            make.height.equalTo(56)
        }
        timeLabel.snp.makeConstraints { make in
            make.top.equalTo(metrics.snp.bottom).offset(8)
            make.left.right.equalToSuperview().inset(16)
            make.height.equalTo(20)
        }
        progressSlider.snp.makeConstraints { make in
            make.top.equalTo(timeLabel.snp.bottom).offset(2)
            make.left.right.equalToSuperview().inset(16)
        }
        controls.snp.makeConstraints { make in
            make.top.equalTo(progressSlider.snp.bottom).offset(6)
            make.left.right.equalToSuperview().inset(16)
            make.height.equalTo(38)
        }
        eventsTitleLabel.snp.makeConstraints { make in
            make.top.equalTo(controls.snp.bottom).offset(10)
            make.left.right.equalToSuperview().inset(16)
            make.height.equalTo(20)
        }
        eventsTableView.snp.makeConstraints { make in
            make.top.equalTo(eventsTitleLabel.snp.bottom)
            make.left.right.bottom.equalToSuperview()
        }
        activityIndicator.snp.makeConstraints { make in
            make.center.equalTo(mapView)
        }
    }

    private func makeMetric(title: String, valueLabel: UILabel) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textColor = .lightGray
        titleLabel.font = UIFont.monospacedSystemFont(ofSize: 10, weight: .medium)
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontSizeToFitWidth = true

        let stack = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        stack.axis = .vertical
        stack.spacing = 4
        stack.alignment = .fill
        return stack
    }

    private func emptyEventsView() -> UIView {
        let label = UILabel()
        label.text = PTDashboardConfig.languageFunc(text: "ride_replay_no_events")
        label.textColor = .gray
        label.font = UIFont.systemFont(ofSize: 14)
        label.textAlignment = .center
        return label
    }

    private func loadReplay() {
        activityIndicator.startAnimating()
        stateLabel.text = PTDashboardConfig.languageFunc(text: "ride_replay_loading")
        loadTask?.cancel()
        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                guard let gpxFileName = self.report.gpxFileName else {
                    throw PTRideReplayError.missingTrack
                }
                let data = try await PTDataPersistenceActor.shared.readData(
                    fileName: gpxFileName,
                    restoreFromICloud: true
                )
                try Task.checkCancellation()
                let points = try await Task.detached(priority: .utility) {
                    try PTGPXParser.parseTrack(data: data)
                }.value
                let session = try PTRideReplayBuilder.makeSession(
                    report: self.report,
                    trackPoints: points
                )
                self.apply(session: session)
            } catch is CancellationError {
                return
            } catch {
                self.activityIndicator.stopAnimating()
                self.stateLabel.text = self.localizedErrorMessage(error)
                self.eventsTableView.backgroundView = self.emptyEventsView()
            }
        }
    }

    // EN: Localize replay failures while preserving unknown persistence errors for diagnostics.
    // ES: Localiza los fallos de reproducción y conserva los errores de persistencia desconocidos para diagnóstico.
    // 中文：本地化回放失败信息，同时保留未知持久化错误供诊断。
    private func localizedErrorMessage(_ error: Error) -> String {
        switch error {
        case PTRideReplayError.missingTrack:
            return PTDashboardConfig.languageFunc(text: "ride_replay_missing_track")
        case PTRideReplayError.invalidTrack:
            return PTDashboardConfig.languageFunc(text: "ride_replay_invalid_track")
        default:
            return error.localizedDescription
        }
    }

    private func apply(session: PTRideReplaySession) {
        self.session = session
        let player = PTRideReplayPlayer(session: session)
        player.onUpdate = { [weak self, weak player] sample, elapsed, progress in
            guard let self, let player else { return }
            self.render(sample: sample, elapsed: elapsed, progress: progress, isPlaying: player.isPlaying)
        }
        self.player = player
        configureMap(for: session)
        summaryLabel.text = summary(for: session)
        eventsTableView.reloadData()
        eventsTableView.backgroundView = session.events.isEmpty ? emptyEventsView() : nil
        activityIndicator.stopAnimating()
        render(sample: player.currentSample, elapsed: 0, progress: 0, isPlaying: false)
    }

    private func configureMap(for session: PTRideReplaySession) {
        guard let firstSample = session.samples.first else { return }
        routeOverlay = nil
        if session.samples.count > 1 {
            var coordinates = session.samples.map(\.coordinate)
            if let polyline = MAPolyline(coordinates: &coordinates, count: UInt(coordinates.count)) {
                routeOverlay = polyline
                mapView.add(polyline)
            }
        }

        replayAnnotation.title = "PTRideReplayPosition"
        replayAnnotation.coordinate = firstSample.coordinate
        mapView.addAnnotation(replayAnnotation)

        eventAnnotations = session.events.map { event in
            let annotation = MAPointAnnotation()
            annotation.coordinate = CLLocationCoordinate2D(latitude: event.latitude, longitude: event.longitude)
            annotation.title = "PTRideReplayEvent:\(event.kind.rawValue)"
            annotation.subtitle = event.titleKey
            return annotation
        }
        if !eventAnnotations.isEmpty {
            mapView.addAnnotations(eventAnnotations)
        }
        if let routeOverlay {
            mapView.setVisibleMapRect(
                routeOverlay.boundingMapRect,
                edgePadding: UIEdgeInsets(top: 28, left: 28, bottom: 28, right: 28),
                animated: false
            )
        } else {
            mapView.setCenter(firstSample.coordinate, animated: false)
        }
        hasConfiguredMap = true
    }

    private func render(sample: PTRideReplaySample?,
                        elapsed: TimeInterval,
                        progress: Float,
                        isPlaying: Bool) {
        progressSlider.setValue(progress, animated: false)
        playButton.setTitle(isPlaying ? "❚❚" : "▶︎", for: .normal)
        stateLabel.text = isPlaying
            ? PTDashboardConfig.languageFunc(text: "ride_replay_playing")
            : PTDashboardConfig.languageFunc(text: "ride_replay_paused")
        timeLabel.text = "\(formatDuration(elapsed)) / \(formatDuration(session?.duration ?? 0))"

        guard let sample else {
            speedValueLabel.text = "-"
            rpmValueLabel.text = "-"
            leanValueLabel.text = "-"
            gValueLabel.text = "-"
            return
        }

        let unit = PTDashboardConfig.shared.appShowUniLabel
        speedValueLabel.text = "\(PTDashboardConfig.shared.appShowMileageValueString(sample.speedKmh)) \(unit)/h"
        rpmValueLabel.text = "\(sample.rpm)"
        leanValueLabel.text = String(format: "%.1f°", sample.leanAngle)
        gValueLabel.text = String(format: "X %.2f · Y %.2f · Z %.2f", sample.gForceX, sample.gForceY, sample.gForceZ)
        replayAnnotation.coordinate = sample.coordinate

        guard let session else { return }
        let activeEventID = session.events.last(where: { $0.timestamp <= sample.timestamp })?.id
        if activeEventID != currentEventID {
            currentEventID = activeEventID
            eventsTableView.reloadData()
        }
        let samplePoint = MAMapPointForCoordinate(sample.coordinate)
        if hasConfiguredMap, !MAMapRectContainsPoint(mapView.visibleMapRect, samplePoint) {
            mapView.setCenter(sample.coordinate, animated: true)
        }
    }

    private func summary(for session: PTRideReplaySession) -> String {
        let distance = PTDashboardConfig.shared.appShowMileageValueString(session.report.distanceKm)
        let unit = PTDashboardConfig.shared.appShowUniLabel
        let eventText = PTDashboardConfig.language(key: "ride_replay_event_count", session.events.count)
        return "\(distance)\(unit) · \(formatDuration(session.duration)) · \(eventText)"
    }

    private func title(for event: PTRideReplayEvent) -> String {
        guard event.kind == .review else {
            return PTDashboardConfig.languageFunc(text: "ride_replay_event_offroad")
        }
        switch event.titleKey {
        case PTRideReviewEventType.hardBraking.rawValue:
            return PTDashboardConfig.languageFunc(text: "ride_replay_event_hard_braking")
        case PTRideReviewEventType.hardAcceleration.rawValue:
            return PTDashboardConfig.languageFunc(text: "ride_replay_event_hard_acceleration")
        case PTRideReviewEventType.heavyBump.rawValue:
            return PTDashboardConfig.languageFunc(text: "ride_replay_event_heavy_bump")
        case PTRideReviewEventType.highLean.rawValue:
            return PTDashboardConfig.languageFunc(text: "ride_replay_event_high_lean")
        case PTRideReviewEventType.suspectedSlip.rawValue:
            return PTDashboardConfig.languageFunc(text: "ride_replay_event_suspected_slip")
        default:
            return event.titleKey
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(Int(duration.rounded()), 0)
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        return hours > 0
            ? String(format: "%02d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }

    @objc private func sliderChanged() {
        player?.seek(progress: progressSlider.value)
    }

    @objc private func togglePlayback() {
        player?.togglePlayback()
    }

    @objc private func previousSample() {
        player?.stepBackward()
    }

    @objc private func nextSample() {
        player?.stepForward()
    }

    // MARK: - UITableViewDataSource

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        session?.events.count ?? 0
    }

    func tableView(_ tableView: UITableView,
                   cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        guard let event = session?.events[indexPath.row] else { return cell }
        cell.backgroundColor = UIColor(white: 0.08, alpha: 1)
        cell.textLabel?.text = title(for: event)
        cell.textLabel?.textColor = event.id == currentEventID
            ? PTDashboardConfig.shared.appMainColor
            : .white
        cell.textLabel?.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        cell.detailTextLabel?.text = "\(formatDate(event.timestamp)) · \(String(format: "%.4f, %.4f", event.latitude, event.longitude))"
        cell.detailTextLabel?.textColor = .lightGray
        cell.accessoryType = event.id == currentEventID ? .checkmark : .none
        return cell
    }

    func tableView(_ tableView: UITableView,
                   didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let session, let player else { return }
        let event = session.events[indexPath.row]
        let elapsed = event.timestamp.timeIntervalSince(session.startTime)
        let progress = session.progress(for: elapsed)
        player.seek(progress: progress)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // MARK: - MAMapViewDelegate

    func mapView(_ mapView: MAMapView!, rendererFor overlay: MAOverlay!) -> MAOverlayRenderer! {
        guard let polyline = overlay as? MAPolyline else { return nil }
        let renderer = MAPolylineRenderer(polyline: polyline)
        renderer?.lineWidth = 5
        renderer?.strokeColor = PTDashboardConfig.shared.appMainColor
        return renderer
    }

    func mapView(_ mapView: MAMapView!, viewFor annotation: MAAnnotation!) -> MAAnnotationView! {
        if (annotation as AnyObject) === replayAnnotation {
            let identifier = "PTRideReplayPosition"
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MAPinAnnotationView)
                ?? MAPinAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            view?.annotation = annotation
            view?.pinColor = .red
            view?.animatesDrop = false
            view?.canShowCallout = false
            return view
        }

        guard let title = annotation.title as? String,
              title.hasPrefix("PTRideReplayEvent:") else { return nil }
        let identifier = "PTRideReplayEvent"
        let view = (mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MAPinAnnotationView)
            ?? MAPinAnnotationView(annotation: annotation, reuseIdentifier: identifier)
        view?.annotation = annotation
        view?.pinColor = title.hasSuffix("offRoad") ? .green : .purple
        view?.animatesDrop = false
        view?.canShowCallout = false
        return view
    }
}
