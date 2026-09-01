//
//  PTRideExperienceViewController.swift
//  CrazyDashboard
//
//  EN: Read-only ride cockpit for vehicle, range, maintenance, parking and PTT status.
//  ES: Cockpit de conducción de solo lectura para el vehículo, autonomía, mantenimiento, estacionamiento y PTT.
//  中文：只读骑行座舱，集中展示车辆、续航、保养、停车和 PTT 状态。
//

import UIKit
import SnapKit
import PooTools

final class PTRideExperienceViewController: PTMotoBaseViewController {
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    private let dashboardValueLabel = UILabel()
    private let obdValueLabel = UILabel()
    private let pttValueLabel = UILabel()
    private let fuelValueLabel = UILabel()
    private let tripValueLabel = UILabel()
    private let rangeValueLabel = UILabel()
    private let maintenanceValueLabel = UILabel()
    private let parkingValueLabel = UILabel()
    private let updatedValueLabel = UILabel()
    private let storyValueLabel = UILabel()
    private let groupSafetyValueLabel = UILabel()
    private let blackBoxValueLabel = UILabel()
    private var blackBoxClipCount = 0

    private lazy var markBlackBoxButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle(PTDashboardConfig.languageFunc(text: "ride_mark_event"), for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        button.backgroundColor = PTDashboardConfig.shared.appMainColor
        button.layer.cornerRadius = 12
        button.addTarget(self, action: #selector(markBlackBoxEvent), for: .touchUpInside)
        return button
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = PTDashboardConfig.languageFunc(text: "ride_center")
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: PTDashboardConfig.languageFunc(text: "ride_safety_center"),
            style: .plain,
            target: self,
            action: #selector(openSafetyCenter)
        )
        view.backgroundColor = .black
        configureLabels()
        configureLayout()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRideStateChange),
            name: PTVehicleConnectivityCoordinator.snapshotDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRideStateChange),
            name: PTIntercomGlobalStatusChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRideStateChange),
            name: MotorcycleTripHistoryLoaded,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRideStateChange),
            name: PTRideGroupSafetyCoordinator.snapshotDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBlackBoxUpdate),
            name: PTRideBlackBoxUpdated,
            object: nil
        )
        PTRideGroupSafetyCoordinator.shared.start()
        loadBlackBoxClips()
        refreshSummary()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        PTRideGroupSafetyCoordinator.shared.start()
        refreshSummary()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        PTRideGroupSafetyCoordinator.shared.stop()
    }

    override func handleMotorcycleConnect() {
        super.handleMotorcycleConnect()
        refreshSummary()
    }

    override func handleMotorcycleDisconnect() {
        super.handleMotorcycleDisconnect()
        refreshSummary()
    }

    override func handleMotorcycleData(data: Any?) {
        refreshSummary()
    }

    @objc private func handleRideStateChange() {
        refreshSummary()
    }

    @objc private func handleBlackBoxUpdate() {
        loadBlackBoxClips()
    }

    // EN: Keep the safety tools adjacent to the ride summary without coupling them to vehicle transport.
    // ES: Mantiene las herramientas de seguridad junto al resumen sin acoplarlas al transporte del vehículo.
    // 中文：把安全工具放在骑行摘要旁边，但不与车辆传输层耦合。
    @objc private func openSafetyCenter() {
        let controller = PTRideSafetyViewController()
        present(UINavigationController(rootViewController: controller), animated: true)
    }

    private func configureLabels() {
        let labels = [
            dashboardValueLabel, obdValueLabel, pttValueLabel, fuelValueLabel,
            tripValueLabel, rangeValueLabel, maintenanceValueLabel,
            parkingValueLabel, updatedValueLabel, storyValueLabel,
            groupSafetyValueLabel, blackBoxValueLabel
        ]
        labels.forEach {
            $0.textColor = .white
            $0.font = UIFont.monospacedSystemFont(ofSize: 15, weight: .medium)
            $0.textAlignment = .right
            $0.numberOfLines = 2
            $0.setContentCompressionResistancePriority(.required, for: .vertical)
        }
    }

    private func configureLayout() {
        contentStack.axis = .vertical
        contentStack.spacing = 12
        contentStack.alignment = .fill

        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.snp.makeConstraints { make in
            make.edges.equalTo(view.safeAreaLayoutGuide).inset(16)
        }
        contentStack.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.width.equalTo(scrollView.frameLayoutGuide)
        }

        contentStack.addArrangedSubview(makeSection(
            title: PTDashboardConfig.languageFunc(text: "ride_connection"),
            rows: [
                (PTDashboardConfig.languageFunc(text: "ride_dashboard"), dashboardValueLabel),
                ("OBD", obdValueLabel),
                ("PTT", pttValueLabel)
            ]
        ))
        contentStack.addArrangedSubview(makeSection(
            title: PTDashboardConfig.languageFunc(text: "ride_status"),
            rows: [
                (PTDashboardConfig.languageFunc(text: "casa_card_oil"), fuelValueLabel),
                (PTDashboardConfig.languageFunc(text: "casa_card_little_trip"), tripValueLabel),
                (PTDashboardConfig.languageFunc(text: "ride_range"), rangeValueLabel),
                (PTDashboardConfig.languageFunc(text: "casa_dist_to_maintenance"), maintenanceValueLabel)
            ]
        ))
        contentStack.addArrangedSubview(makeSection(
            title: PTDashboardConfig.languageFunc(text: "ride_parking"),
            rows: [("", parkingValueLabel)]
        ))
        contentStack.addArrangedSubview(makeSection(
            title: PTDashboardConfig.languageFunc(text: "ride_story"),
            rows: [("", storyValueLabel)]
        ))
        contentStack.addArrangedSubview(makeSection(
            title: PTDashboardConfig.languageFunc(text: "ride_group_safety"),
            rows: [("", groupSafetyValueLabel)]
        ))
        contentStack.addArrangedSubview(makeSection(
            title: PTDashboardConfig.languageFunc(text: "ride_black_box"),
            rows: [("", blackBoxValueLabel)]
        ))
        contentStack.addArrangedSubview(markBlackBoxButton)
        contentStack.addArrangedSubview(makeSection(
            title: PTDashboardConfig.languageFunc(text: "ride_last_sync"),
            rows: [("", updatedValueLabel)]
        ))
    }

    private func makeSection(title: String, rows: [(String, UILabel)]) -> UIView {
        let card = UIView()
        card.backgroundColor = UIColor(white: 0.1, alpha: 1)
        card.layer.cornerRadius = 14
        card.layer.borderColor = PTDashboardConfig.shared.appMainColor.withAlphaComponent(0.35).cgColor
        card.layer.borderWidth = 1

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 10
        card.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(14)
        }

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textColor = PTDashboardConfig.shared.appMainColor
        titleLabel.font = UIFont.monospacedSystemFont(ofSize: 16, weight: .bold)
        stack.addArrangedSubview(titleLabel)

        for (rowTitle, valueLabel) in rows {
            let row = UIStackView()
            row.axis = .horizontal
            row.alignment = .top
            row.spacing = 8
            let nameLabel = UILabel()
            nameLabel.text = rowTitle
            nameLabel.textColor = .lightGray
            nameLabel.font = UIFont.systemFont(ofSize: 14, weight: .regular)
            nameLabel.numberOfLines = 2
            row.addArrangedSubview(nameLabel)
            row.addArrangedSubview(valueLabel)
            nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
            valueLabel.setContentHuggingPriority(.required, for: .horizontal)
            stack.addArrangedSubview(row)
        }
        return card
    }

    private func refreshSummary() {
        let dashboardManager = PTBluetoothServerManager.shared
        let widgetStatus = PTWidgetSharedStatus.read(
            from: UserDefaults(suiteName: PTWidgetDataKeys.appGroupID)
        )
        let vehicle = PTVehicleConnectivityCoordinator.shared.snapshot
        let summary = PTRideExperienceSummary(
            vehicle: vehicle,
            fuelLevelPercent: dashboardManager.latestData1?.fuelLevelPct ?? widgetStatus.fuelLevel,
            tripKm: dashboardManager.latestData1?.tripKm ?? widgetStatus.tripKm,
            odometerKm: dashboardManager.latestData1?.odoKm,
            averageConsumptionLitersPer100Km: dashboardManager.latestData1?.avgConsumptionLt,
            dashboardAutonomyKm: dashboardManager.latestData3?.autonomyKm,
            batteryVoltage: dashboardManager.latestData2?.batteryVolt,
            outsideTemperatureCelsius: dashboardManager.latestData2?.outsideTempC,
            maintenanceDistanceKm: dashboardManager.latestData3?.distToMaintenance,
            maintenanceFlag: dashboardManager.latestData2?.maintenance,
            parkedLatitude: widgetStatus.parkedLat,
            parkedLongitude: widgetStatus.parkedLon,
            parkedAddress: widgetStatus.address,
            pttPeerCount: PTLocalIntercomManager.shared.connectedPeersCount,
            updatedAt: max(vehicle.updatedAt, widgetStatus.lastUpdateTime)
        )

        dashboardValueLabel.text = linkDescription(summary.vehicle.dashboard)
        obdValueLabel.text = linkDescription(summary.vehicle.obd)
        pttValueLabel.text = summary.pttPeerCount > 0
            ? PTDashboardConfig.language(key: "ride_ptt_members", summary.pttPeerCount)
            : PTDashboardConfig.languageFunc(text: "ride_ptt_none")

        fuelValueLabel.text = summary.fuelLevelPercent.map { "\($0)%" } ?? "-"
        tripValueLabel.text = summary.tripKm.map {
            "\(PTDashboardConfig.shared.appShowMileageValueString($0))\(PTDashboardConfig.shared.appShowUniLabel)"
        } ?? "-"
        if let range = summary.rangeEstimate {
            let value = PTDashboardConfig.shared.appShowMileageValueString(range.remainingKm)
            rangeValueLabel.text = range.source == .dashboard ?
                "\(value)\(PTDashboardConfig.shared.appShowUniLabel)" :
                "\(value)\(PTDashboardConfig.shared.appShowUniLabel) *"
        } else {
            rangeValueLabel.text = PTDashboardConfig.languageFunc(text: "ride_not_available")
        }
        maintenanceValueLabel.text = maintenanceDescription(summary.maintenanceAdvice)
        storyValueLabel.text = storyDescription(for: PTTripManager.shared.tripHistory.first)
        groupSafetyValueLabel.text = groupSafetyDescription(PTRideGroupSafetyCoordinator.shared.snapshot)
        blackBoxValueLabel.text = blackBoxClipCount > 0
            ? PTDashboardConfig.language(key: "ride_black_box_count", blackBoxClipCount)
            : PTDashboardConfig.languageFunc(text: "ride_black_box_empty")
        markBlackBoxButton.isEnabled = PTTripManager.shared.isRecordingRide
        markBlackBoxButton.alpha = markBlackBoxButton.isEnabled ? 1 : 0.45

        if summary.parkedLatitude != 0 || summary.parkedLongitude != 0 {
            let coordinate = String(format: "%.5f, %.5f", summary.parkedLatitude, summary.parkedLongitude)
            parkingValueLabel.text = summary.parkedAddress == PTWidgetSharedStatus.placeholder.address
                ? coordinate
                : "\(summary.parkedAddress)\n\(coordinate)"
        } else {
            parkingValueLabel.text = PTDashboardConfig.languageFunc(text: "ride_no_parking")
        }
        updatedValueLabel.text = formattedDate(summary.updatedAt)
    }

    private func storyDescription(for trip: PTTripReport?) -> String {
        guard let trip else {
            return PTDashboardConfig.languageFunc(text: "ride_story_empty")
        }
        let story = PTRideStoryBuilder.make(from: trip)
        let unit = PTDashboardConfig.shared.appShowUniLabel
        let distance = PTDashboardConfig.shared.appShowMileageValueString(story.distanceKm) + unit
        let speed = PTDashboardConfig.shared.appShowMileageValueString(story.averageSpeedKmh) + unit + "/h"
        let elevation = PTDashboardConfig.language(
            key: "ride_story_elevation",
            Int(story.elevationGainMeters.rounded()),
            Int(story.elevationLossMeters.rounded())
        )
        return [
            PTDashboardConfig.language(key: "ride_story_distance", distance),
            PTDashboardConfig.language(key: "ride_story_speed", speed),
            PTDashboardConfig.language(key: "ride_story_events", story.eventCount),
            PTDashboardConfig.language(
                key: "ride_story_lean",
                String(format: "%.1f", story.maximumLeanAngle)
            ),
            elevation
        ].joined(separator: "\n")
    }

    private func groupSafetyDescription(_ safety: PTRideGroupSafetySnapshot) -> String {
        guard safety.isGroupActive else {
            return PTDashboardConfig.languageFunc(text: "ride_group_none")
        }
        if !safety.hasAlert {
            return PTDashboardConfig.language(key: "ride_group_ok", safety.peers.count)
        }

        var descriptions: [String] = []
        if safety.stalePeerCount > 0 {
            descriptions.append(PTDashboardConfig.language(key: "ride_group_stale", safety.stalePeerCount))
        }
        if safety.tooFarPeerCount > 0 {
            descriptions.append(PTDashboardConfig.language(key: "ride_group_far", safety.tooFarPeerCount))
        }
        if safety.noLocationPeerCount > 0 {
            descriptions.append(PTDashboardConfig.language(key: "ride_group_unknown", safety.noLocationPeerCount))
        }
        return descriptions.joined(separator: "\n")
    }

    private func loadBlackBoxClips() {
        Task { [weak self] in
            guard let clips = try? await PTRideBlackBoxStore.shared.load() else { return }
            self?.blackBoxClipCount = clips.count
            self?.refreshSummary()
        }
    }

    @objc private func markBlackBoxEvent() {
        let title = PTDashboardConfig.languageFunc(text: "ride_manual_event")
        guard PTTripManager.shared.markCurrentRideEvent(title: title) else {
            PTProgressHUD.show(text: PTDashboardConfig.languageFunc(text: "ride_mark_event_unavailable"))
            return
        }
        PTProgressHUD.show(text: PTDashboardConfig.languageFunc(text: "ride_mark_event_saved"))
    }

    private func linkDescription(_ link: PTVehicleLinkSnapshot) -> String {
        let statusKey: String
        switch link.state {
        case .connected: statusKey = "ride_connected"
        case .connecting: statusKey = "ride_connecting"
        case .failed: statusKey = "ride_failed"
        case .disconnected: statusKey = "ride_disconnected"
        case .idle: statusKey = "ride_idle"
        }
        return PTDashboardConfig.languageFunc(text: statusKey)
    }

    private func maintenanceDescription(_ advice: PTRideMaintenanceAdvice) -> String {
        switch advice.state {
        case .required:
            return PTDashboardConfig.languageFunc(text: "maintenance_need")
        case .dueSoon:
            guard let distance = advice.distanceToMaintenanceKm else {
                return PTDashboardConfig.languageFunc(text: "maintenance_warning_title")
            }
            return PTDashboardConfig.language(key: "maintenance_warning_msg", distance)
        case .normal:
            guard let distance = advice.distanceToMaintenanceKm else { return "-" }
            return "\(distance)\(PTDashboardConfig.shared.appShowUniLabel)"
        case .unknown:
            return PTDashboardConfig.languageFunc(text: "ride_not_available")
        }
    }

    private func formattedDate(_ date: Date) -> String {
        guard date != .distantPast else {
            return PTDashboardConfig.languageFunc(text: "ride_not_available")
        }
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

}
