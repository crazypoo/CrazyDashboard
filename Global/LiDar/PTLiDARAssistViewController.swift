//
//  PTLiDARAssistViewController.swift
//  PTSpeed
//
//  EN: A focused, read-only LiDAR HUD for low-speed riding assistance and garage measurements.
//  ES: HUD LiDAR de solo lectura para asistencia a baja velocidad y mediciones del garaje.
//  中文：面向低速骑行辅助和车库测距的专用只读 LiDAR 界面。
//

import ARKit
import CoreLocation
import UIKit
import PooTools
import SnapKit

@MainActor
final class PTLiDARAssistViewController: PTMotoBaseViewController {
    private let initialMode: PTLiDARAssistMode
    private let lidarManager: PTLiDARCollisionManager

    private let sceneView = ARSCNView(frame: .zero)
    private let modeControl = UISegmentedControl(items: [
        PTDashboardConfig.languageFunc(text: "lidar_mode_mounted"),
        PTDashboardConfig.languageFunc(text: "lidar_mode_garage")
    ])
    private let stateLabel = UILabel()
    private let speedLabel = UILabel()
    private let hintLabel = UILabel()
    private let warningLabel = UILabel()
    private let readingsStack = UIStackView()
    private let startButton = UIButton(type: .system)
    private let freezeButton = UIButton(type: .system)
    private let saveButton = UIButton(type: .system)

    private var zoneLabels: [PTLiDARZone: UILabel] = [:]
    private var latestSnapshot: PTLiDARProximitySnapshot?
    private var frozenSnapshot: PTLiDARProximitySnapshot?
    private var obdSpeedTimer: Timer?
    private var lastHapticAt = Date.distantPast

    init(mode: PTLiDARAssistMode = .mountedLowSpeed, manager: PTLiDARCollisionManager = .shared) {
        self.initialMode = mode
        self.lidarManager = manager
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        pt_Title = localized("lidar_title")
        view.backgroundColor = .black
        lidarManager.delegate = self
        configureUI()
        configureObservers()
        setSelectedMode(initialMode)
        render(snapshot: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        lidarManager.delegate = self
        obdSpeedTimer?.invalidate()
        obdSpeedTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            let obdManager = PTMotoTelemetryManager.shared
            guard obdManager.isConnected else { return }
            self.lidarManager.updateSpeedSample(
                PTLiDARSpeedSample(speedKmh: max(0, obdManager.currentSpeed), source: .obd)
            )
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        obdSpeedTimer?.invalidate()
        obdSpeedTimer = nil
        // EN: LiDAR is foreground-only and never keeps the camera alive after leaving this page.
        // ES: LiDAR solo funciona en primer plano y nunca mantiene la cámara al salir de esta página.
        // 中文：LiDAR 仅前台运行，离开页面后绝不继续占用摄像头。
        lidarManager.stop()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let orientation = view.window?.windowScene?.interfaceOrientation ?? .portrait
        lidarManager.updateProjection(orientation: orientation, viewportSize: sceneView.bounds.size)
    }

    override func handleMotorcycleData(data: Any?) {
        super.handleMotorcycleData(data: data)
        guard let control = data as? PTDashboardControl,
              control.vehicleSpeedAvailability.isAvailable else { return }
        lidarManager.updateSpeedSample(
            PTLiDARSpeedSample(speedKmh: max(0, control.vehicleSpeedKmh), source: .dashboard)
        )
    }

    override func handleMotorcycleDisconnect() {
        super.handleMotorcycleDisconnect()
        render(snapshot: latestSnapshot)
    }

    private func configureUI() {
        sceneView.backgroundColor = UIColor(white: 0.04, alpha: 1)
        sceneView.scene = SCNScene()
        // EN: Render the exact session owned by the coordinator; never create a second camera session.
        // ES: Renderiza la sesión exacta del coordinador; nunca crees una segunda sesión de cámara.
        // 中文：渲染协调器持有的同一个会话，绝不创建第二个摄像头会话。
        sceneView.session = lidarManager.arSession
        sceneView.automaticallyUpdatesLighting = false
        sceneView.isUserInteractionEnabled = false
        view.addSubview(sceneView)
        sceneView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        let shadeView = UIView()
        shadeView.backgroundColor = UIColor.black.withAlphaComponent(0.42)
        view.addSubview(shadeView)
        shadeView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        [stateLabel, speedLabel, hintLabel, warningLabel].forEach {
            $0.textColor = .white
            $0.numberOfLines = 0
        }
        stateLabel.font = .systemFont(ofSize: 20, weight: .bold)
        speedLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        speedLabel.textColor = .systemGray2
        hintLabel.font = .systemFont(ofSize: 13, weight: .regular)
        hintLabel.textColor = .systemGray2
        warningLabel.font = .systemFont(ofSize: 17, weight: .bold)
        warningLabel.textAlignment = .center

        modeControl.selectedSegmentTintColor = PTDashboardConfig.shared.appMainColor
        modeControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)
        modeControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)

        let header = UIStackView(arrangedSubviews: [stateLabel, speedLabel, hintLabel])
        header.axis = .vertical
        header.spacing = 5
        header.backgroundColor = UIColor(white: 0.08, alpha: 0.88)
        header.isLayoutMarginsRelativeArrangement = true
        header.layoutMargins = UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        header.layer.cornerRadius = 14
        view.addSubview(header)
        header.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(12)
            make.leading.trailing.equalToSuperview().inset(16)
        }

        view.addSubview(modeControl)
        modeControl.snp.makeConstraints { make in
            make.top.equalTo(header.snp.bottom).offset(10)
            make.leading.trailing.equalTo(header)
            make.height.equalTo(34)
        }

        readingsStack.axis = .horizontal
        readingsStack.spacing = 8
        readingsStack.distribution = .fillEqually
        view.addSubview(readingsStack)
        readingsStack.snp.makeConstraints { make in
            make.top.equalTo(modeControl.snp.bottom).offset(12)
            make.leading.trailing.equalTo(header)
            make.height.equalTo(88)
        }
        for zone in PTLiDARZone.allCases {
            let card = makeZoneCard(zone)
            readingsStack.addArrangedSubview(card)
        }

        warningLabel.backgroundColor = UIColor.black.withAlphaComponent(0.68)
        warningLabel.layer.cornerRadius = 12
        warningLabel.layer.masksToBounds = true
        view.addSubview(warningLabel)
        warningLabel.snp.makeConstraints { make in
            make.top.equalTo(readingsStack.snp.bottom).offset(12)
            make.leading.trailing.equalTo(header)
            make.height.greaterThanOrEqualTo(44)
        }

        startButton.setTitle(localized("lidar_start"), for: .normal)
        freezeButton.setTitle(localized("lidar_freeze"), for: .normal)
        saveButton.setTitle(localized("lidar_save"), for: .normal)
        [startButton, freezeButton, saveButton].forEach {
            $0.setTitleColor(.white, for: .normal)
            $0.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
            $0.backgroundColor = PTDashboardConfig.shared.appMainColor
            $0.layer.cornerRadius = 10
            $0.heightAnchor.constraint(equalToConstant: 44).isActive = true
        }
        freezeButton.backgroundColor = .systemGray
        saveButton.backgroundColor = .systemGreen
        startButton.addTarget(self, action: #selector(startOrResume), for: .touchUpInside)
        freezeButton.addTarget(self, action: #selector(toggleFreeze), for: .touchUpInside)
        saveButton.addTarget(self, action: #selector(saveMeasurement), for: .touchUpInside)

        let controls = UIStackView(arrangedSubviews: [startButton, freezeButton, saveButton])
        controls.axis = .horizontal
        controls.spacing = 8
        controls.distribution = .fillEqually
        view.addSubview(controls)
        controls.snp.makeConstraints { make in
            make.leading.trailing.equalTo(header)
            make.bottom.equalTo(view.safeAreaLayoutGuide).inset(16)
        }
    }

    private func makeZoneCard(_ zone: PTLiDARZone) -> UIView {
        let card = UIView()
        card.backgroundColor = UIColor(white: 0.08, alpha: 0.92)
        card.layer.cornerRadius = 12
        let title = UILabel()
        title.text = localized("lidar_zone_\(zone.rawValue)")
        title.textColor = .systemGray2
        title.font = .systemFont(ofSize: 12, weight: .medium)
        title.textAlignment = .center
        let value = UILabel()
        value.text = "--"
        value.textColor = .white
        value.font = .monospacedDigitSystemFont(ofSize: 18, weight: .bold)
        value.textAlignment = .center
        value.adjustsFontSizeToFitWidth = true
        value.minimumScaleFactor = 0.7
        let stack = UIStackView(arrangedSubviews: [title, value])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.distribution = .fillEqually
        card.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(8)
        }
        zoneLabels[zone] = value
        return card
    }

    private func configureObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(locationDidUpdate(_:)),
            name: PTLocationEngineDidUpdate,
            object: nil
        )
    }

    private func setSelectedMode(_ mode: PTLiDARAssistMode) {
        modeControl.selectedSegmentIndex = mode == .mountedLowSpeed ? 0 : 1
        hintLabel.text = localized(mode == .mountedLowSpeed ? "lidar_mounted_hint" : "lidar_garage_hint")
    }

    @objc private func modeChanged() {
        let mode: PTLiDARAssistMode = modeControl.selectedSegmentIndex == 0 ? .mountedLowSpeed : .garageMeasure
        if lidarManager.isRunning { lidarManager.stop() }
        setSelectedMode(mode)
        latestSnapshot = nil
        frozenSnapshot = nil
        render(snapshot: nil)
    }

    @objc private func startOrResume() {
        if lidarManager.isRunning {
            stopScanning()
            return
        }

        let mode: PTLiDARAssistMode = modeControl.selectedSegmentIndex == 0 ? .mountedLowSpeed : .garageMeasure
        if lidarManager.state == .interrupted {
            lidarManager.resumeAfterSystemInterruption()
            return
        }
        let result = lidarManager.start(mode: mode)
        switch result {
        case .cameraPermissionDenied:
            showMessage(localized("lidar_camera_permission_denied"))
        case .unsupported:
            showMessage(localized("lidar_unsupported"))
        case .failed(let message):
            showMessage(message)
        default:
            break
        }
        updateControls()
    }

    @objc private func toggleFreeze() {
        if frozenSnapshot == nil {
            frozenSnapshot = latestSnapshot
            freezeButton.setTitle(localized("lidar_unfreeze"), for: .normal)
        } else {
            frozenSnapshot = nil
            freezeButton.setTitle(localized("lidar_freeze"), for: .normal)
            render(snapshot: latestSnapshot)
        }
    }

    @objc private func saveMeasurement() {
        guard let snapshot = frozenSnapshot ?? latestSnapshot else {
            showMessage(localized("lidar_no_measurement"))
            return
        }
        let alert = UIAlertController(title: localized("lidar_save"), message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = self.localized("lidar_note_placeholder")
        }
        alert.addAction(UIAlertAction(title: localized("button_cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: localized("button_confirm"), style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            let note = alert?.textFields?.first?.text ?? ""
            let measurement = PTLiDARMeasurementStore.shared.save(
                snapshot: snapshot,
                vehicleID: PTMotorcycleGarageStore.shared.selectedVehicleID,
                note: note
            )
            guard measurement != nil else {
                self.showMessage(self.localized("lidar_no_measurement"))
                return
            }
            if snapshot.mode == .mountedLowSpeed, PTTripManager.shared.isRecordingRide {
                _ = PTTripManager.shared.markCurrentRideEvent(title: self.localized("lidar_ride_event"))
            }
            self.showMessage(self.localized("lidar_saved"))
        })
        present(alert, animated: true)
    }

    @objc private func locationDidUpdate(_ notification: Notification) {
        guard let tripData = notification.object as? PTTripData,
              let location = tripData.currentLocation,
              location.speed.isFinite,
              location.speed >= 0 else { return }
        lidarManager.updateSpeedSample(
            PTLiDARSpeedSample(speedKmh: location.speed * 3.6, source: .gps)
        )
    }

    private func render(snapshot: PTLiDARProximitySnapshot?) {
        let displaySnapshot = frozenSnapshot ?? snapshot
        latestSnapshot = snapshot ?? latestSnapshot
        if let displaySnapshot {
            for zone in PTLiDARZone.allCases {
                let reading = displaySnapshot.reading(for: zone)
                zoneLabels[zone]?.text = reading?.distanceMeters.map { String(format: "%.2f m", $0) } ?? "--"
                zoneLabels[zone]?.textColor = color(for: reading?.alertLevel ?? .none)
            }
            let speedText = displaySnapshot.speedKmh.map { String(format: "%.1f km/h · %@", $0, displaySnapshot.speedSource?.rawValue ?? "") } ?? localized("lidar_speed_unavailable")
            speedLabel.text = speedText
            stateLabel.text = localized("lidar_state_\(lidarManager.state.rawValue)")
            let canWarn = frozenSnapshot != nil || lidarManager.state == .armed || lidarManager.state == .running
            warningLabel.text = canWarn && displaySnapshot.readings.contains(where: { $0.alertLevel == .critical })
                ? localized("lidar_critical_warning")
                : canWarn && displaySnapshot.readings.contains(where: { $0.alertLevel == .warning })
                    ? localized("lidar_warning")
                    : localized("lidar_clear")
        } else {
            for zone in PTLiDARZone.allCases {
                zoneLabels[zone]?.text = "--"
                zoneLabels[zone]?.textColor = .white
            }
            speedLabel.text = localized("lidar_speed_unavailable")
            stateLabel.text = localized("lidar_state_idle")
            warningLabel.text = localized("lidar_ready")
        }
        updateControls()
    }

    private func updateControls() {
        let running = lidarManager.isRunning
        startButton.setTitle(
            lidarManager.state == .interrupted ? localized("lidar_resume") : running ? localized("lidar_stop") : localized("lidar_start"),
            for: .normal
        )
        freezeButton.isEnabled = latestSnapshot != nil
        saveButton.isEnabled = frozenSnapshot != nil || latestSnapshot != nil
    }

    @objc private func stopScanning() {
        lidarManager.stop()
        latestSnapshot = nil
        frozenSnapshot = nil
        render(snapshot: nil)
    }

    private func color(for level: PTLiDARAlertLevel) -> UIColor {
        switch level {
        case .none: return .white
        case .warning: return .systemOrange
        case .critical: return .systemRed
        }
    }

    private func showMessage(_ message: String) {
        let alert = UIAlertController(title: localized("lidar_title"), message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: localized("button_confirm"), style: .default))
        present(alert, animated: true)
    }

    private func localized(_ key: String) -> String {
        PTDashboardConfig.languageFunc(text: key)
    }
}

extension PTLiDARAssistViewController: PTLiDARCollisionDelegate {
    func lidarManager(_ manager: PTLiDARCollisionManager, didUpdateDistances left: Float, center: Float, right: Float) {}

    func lidarManager(_ manager: PTLiDARCollisionManager, didUpdate snapshot: PTLiDARProximitySnapshot) {
        render(snapshot: snapshot)
    }

    func lidarManager(_ manager: PTLiDARCollisionManager, didChangeState state: PTLiDARRunState, reason: PTLiDARStandbyReason) {
        if state == .permissionDenied {
            showMessage(localized("lidar_camera_permission_denied"))
        }
        render(snapshot: latestSnapshot)
    }

    func lidarManager(_ manager: PTLiDARCollisionManager, didTriggerWarningIn zones: [PTLiDARZone]) {
        let now = Date()
        guard now.timeIntervalSince(lastHapticAt) >= 1 else { return }
        lastHapticAt = now
        let hasCritical = zones.contains { latestSnapshot?.reading(for: $0)?.alertLevel == .critical }
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(hasCritical ? .error : .warning)
    }
}
