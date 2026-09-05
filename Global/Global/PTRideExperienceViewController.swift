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
import SafeSFSymbols

final class PTRideExperienceViewController: PTMotoBaseViewController {
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    private let dashboardValueLabel = UILabel()
    private let obdValueLabel = UILabel()
    private let pttValueLabel = UILabel()
    private let fuelValueLabel = UILabel()
    private let tripValueLabel = UILabel()
    private let rangeValueLabel = UILabel()
    private let readinessValueLabel = UILabel()
    private let maintenanceValueLabel = UILabel()
    private let parkingValueLabel = UILabel()
    private let updatedValueLabel = UILabel()
    private let storyValueLabel = UILabel()
    private let groupSafetyValueLabel = UILabel()
    private let blackBoxValueLabel = UILabel()
    private var blackBoxClipCount = 0
    private var narrativeTask: Task<Void, Never>?

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

    // EN: Narrative generation is user-triggered and remains a read-only presentation feature.
    // ES: La generación narrativa la solicita el usuario y sigue siendo una función de presentación de solo lectura.
    // 中文：骑行文字总结必须由用户主动触发，并且只用于只读展示。
    private lazy var narrativeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle(PTDashboardConfig.languageFunc(text: "ride_story_generate"), for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        button.backgroundColor = PTDashboardConfig.shared.appMainColor
        button.layer.cornerRadius = 12
        button.addTarget(self, action: #selector(generateRideNarrative), for: .touchUpInside)
        return button
    }()

    // EN: Translation is kept in the ride center so repair and group messages are easy to reach.
    // ES: La traducción permanece en el centro de conducción para acceder fácilmente a mensajes de reparación y grupo.
    // 中文：把翻译入口放在骑行中心，方便处理维修和车友沟通文本。
    private lazy var translationButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle(PTDashboardConfig.languageFunc(text: "translation_open"), for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        button.backgroundColor = UIColor.systemIndigo.withAlphaComponent(0.9)
        button.layer.cornerRadius = 12
        button.addTarget(self, action: #selector(openTranslation), for: .touchUpInside)
        return button
    }()
    
    lazy var centerButton:PTBaseButton = {
        let view = PTBaseButton(type:.custom)
        view.titleLabel?.font = .appfont(size: 16,bold: true)
        view.setTitleColor(.white, for: .normal)
        view.setTitle(PTDashboardConfig.languageFunc(text: "ride_safety_center"), for: .normal)
        view.bounds = .init(origin: .zero, size: .init(width: view.sizeFor().width + 20, height: PTAppBaseConfig.share.navBarButtonSize))
        view.addActionHandlers(handler: { _ in
            self.openSafetyCenter()
        })
        return view
    }()
    
    lazy var exportButton:PTBaseButton = {
        let view = PTBaseButton(type:.custom)
        view.setImage(UIImage(.shared.withYouCircleFill).withTintColor(.white, renderingMode: .alwaysOriginal), for: .normal)
        view.bounds = .init(origin: .zero, size: .init(width: PTAppBaseConfig.share.navBarButtonSize, height: PTAppBaseConfig.share.navBarButtonSize))
        view.accessibilityLabel = PTDashboardConfig.languageFunc(text: "ride_black_box_export")
        view.addActionHandlers(handler: { sender in
            self.exportBlackBox()
        })
        return view
    }()

    // EN: Open the explicit reminder center from the ride cockpit.
    // ES: Abre el centro de recordatorios explícito desde el cockpit de conducción.
    // 中文：从骑行中心打开主动式提醒中心。
    lazy var alarmButton: PTBaseButton = {
        let view = PTBaseButton(type: .custom)
        view.setImage(UIImage(.bell.badgeFill).withTintColor(.white, renderingMode: .alwaysOriginal), for: .normal)
        view.tintColor = .white
        view.bounds = .init(
            origin: .zero,
            size: .init(
                width: PTAppBaseConfig.share.navBarButtonSize,
                height: PTAppBaseConfig.share.navBarButtonSize
            )
        )
        view.accessibilityLabel = PTDashboardConfig.languageFunc(text: "alarm_center_title")
        view.addActionHandlers { [weak self] _ in
            self?.openAlarmCenter()
        }
        return view
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        pt_Title = PTDashboardConfig.languageFunc(text: "ride_center")
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
            selector: #selector(handleRideStateChange),
            name: PTMotorcycleGarageStore.didChangeNotification,
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
        setCustomRightButtons(
            buttons: [exportButton, centerButton, alarmButton],
            buttonSpacing: CGFloat.GlobalItemSpacing
        )
        refreshSummary()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        PTRideGroupSafetyCoordinator.shared.stop()
        narrativeTask?.cancel()
        narrativeTask = nil
        narrativeButton.isEnabled = true
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
        safePushViewController(controller)
    }

    // EN: Alarm creation is a foreground user action and never starts from a telemetry update.
    // ES: La creación de alarmas es una acción explícita en primer plano y nunca nace de una actualización de telemetría.
    // 中文：提醒只能由前台用户主动创建，不会因遥测更新自动生成。
    @objc private func openAlarmCenter() {
        safePushViewController(PTMotoAlarmCenterViewController())
    }

    private func configureLabels() {
        let labels = [
            dashboardValueLabel, obdValueLabel, pttValueLabel, fuelValueLabel,
            tripValueLabel, rangeValueLabel, maintenanceValueLabel,
            readinessValueLabel,
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
            make.left.right.equalToSuperview().inset(16)
            make.top.equalToSuperview().inset(CGFloat.kNavBarHeight_Total)
            make.bottom.equalToSuperview().inset(16)
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
                (PTDashboardConfig.languageFunc(text: "ride_readiness"), readinessValueLabel),
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
        contentStack.addArrangedSubview(narrativeButton)
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
        contentStack.addArrangedSubview(translationButton)
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
        let isDashboardConnected = vehicle.isDashboardConnected
        let warningDistanceKm = Int(PTMotorcycleGarageStore.shared.currentMaintenanceWarningDistanceKm.rounded())
        let liveData1 = dashboardManager.latestData1
        let liveData2 = dashboardManager.latestData2
        let liveData3 = dashboardManager.latestData3
        let liveConsumption = liveData1.flatMap {
            $0.averageConsumptionAvailability.isAvailable ? $0.avgConsumptionLt : nil
        }
        let historyConsumption = PTRideRangeEstimator.weightedConsumption(
            from: PTTripManager.shared.tripHistory
        )
        let usableLiveConsumption = liveConsumption.flatMap { (1...15).contains($0) ? $0 : nil }
        let rangeConsumption = usableLiveConsumption ?? historyConsumption?.litersPer100Km
        let rangeSource: PTRideRangeSource? = usableLiveConsumption != nil
            ? .liveConsumption
            : (historyConsumption == nil ? nil : .rideHistory)
        let profile = PTMotorcycleGarageStore.shared.currentVehicle
        let summary = PTRideExperienceSummary(
            vehicle: vehicle,
            fuelLevelPercent: liveData1.flatMap {
                $0.fuelLevelAvailability.isAvailable ? $0.fuelLevelPct : nil
            } ?? widgetStatus.fuelLevel,
            tripKm: liveData1.flatMap {
                $0.tripAvailability.isAvailable ? $0.tripKm : nil
            } ?? widgetStatus.tripKm,
            odometerKm: liveData1.flatMap {
                $0.odometerAvailability.isAvailable ? $0.odoKm : nil
            },
            averageConsumptionLitersPer100Km: rangeConsumption,
            dashboardAutonomyKm: liveData3.flatMap {
                $0.autonomyAvailability.isAvailable ? $0.autonomyKm : nil
            },
            batteryVoltage: liveData2.flatMap {
                $0.batteryAvailability.isAvailable ? $0.batteryVolt : nil
            },
            outsideTemperatureCelsius: liveData2.flatMap {
                $0.outsideTemperatureAvailability.isAvailable ? $0.outsideTempC : nil
            },
            maintenanceDistanceKm: isDashboardConnected ? liveData3.flatMap {
                $0.maintenanceDistanceAvailability.isAvailable ? $0.distToMaintenance : nil
            } : nil,
            maintenanceFlag: isDashboardConnected ? liveData2.flatMap {
                $0.maintenanceAvailability.isAvailable ? $0.maintenance : nil
            } : nil,
            maintenanceWarningDistanceKm: warningDistanceKm,
            parkedLatitude: widgetStatus.parkedLat,
            parkedLongitude: widgetStatus.parkedLon,
            parkedAddress: widgetStatus.address,
            pttPeerCount: PTLocalIntercomManager.shared.connectedPeersCount,
            tankCapacityLiters: profile?.tankCapacityLiters,
            reserveFuelPercent: profile?.reserveFuelPercent,
            rangeConsumptionSource: rangeSource,
            updatedAt: max(vehicle.updatedAt, widgetStatus.lastUpdateTime)
        )
        let readiness = PTRideReadinessEvaluator.evaluate(
            vehicleName: profile?.name ?? "XP400 GT",
            vehicle: summary.vehicle,
            fuelLevelPercent: summary.fuelLevelPercent,
            rangeEstimate: summary.rangeEstimate,
            batteryVoltage: summary.batteryVoltage,
            maintenanceAdvice: summary.maintenanceAdvice,
            pttPeerCount: summary.pttPeerCount,
            pttLocationSharingEnabled: PTLocalIntercomManager.shared.locationSharingEnabled,
            dataUpdatedAt: summary.updatedAt
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
            let suffix = range.source == .dashboard ? "" : " *"
            rangeValueLabel.text = "\(value)\(PTDashboardConfig.shared.appShowUniLabel)\(suffix)"
        } else {
            rangeValueLabel.text = PTDashboardConfig.languageFunc(text: "ride_not_available")
        }
        readinessValueLabel.text = readinessDescription(readiness)
        PTWatchConnectivityManager.shared.update(readiness: readiness)
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

    // EN: Use aggregate trip facts only; this action never reads or writes BLE/OBD state.
    // ES: Usa solo hechos agregados del viaje; esta acción nunca lee ni escribe el estado BLE/OBD.
    // 中文：只传递骑行聚合数据，该操作不会读写 BLE/OBD 状态。
    @objc private func generateRideNarrative() {
        guard let report = PTTripManager.shared.tripHistory.first else {
            showMessage(PTDashboardConfig.languageFunc(text: "ride_story_empty"))
            return
        }

        narrativeTask?.cancel()
        narrativeButton.isEnabled = false
        narrativeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let summary = PTRideStoryBuilder.make(from: report)
            let narrative = await PTRideNarrativeService.shared.makeNarrative(for: summary)
            guard !Task.isCancelled else { return }
            self.narrativeButton.isEnabled = true
            self.showMessage(narrative)
        }
    }

    @objc private func openTranslation() {
        safePushViewController(PTMotoTranslationViewController())
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

    // EN: Export only stored black-box clips; this action never reads from or writes to the vehicle.
    // ES: Exporta solo clips de la caja negra ya guardados; nunca lee ni escribe en el vehículo.
    // 中文：只导出已经保存的黑匣子片段，不读取也不写入车辆。
    @objc private func exportBlackBox() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let clips = try await PTRideBlackBoxStore.shared.load()
                guard !clips.isEmpty else {
                    showMessage(PTDashboardConfig.languageFunc(text: "ride_black_box_no_data"))
                    return
                }

                let alert = UIAlertController(
                    title: PTDashboardConfig.languageFunc(text: "ride_black_box_export"),
                    message: PTDashboardConfig.languageFunc(text: "ride_black_box_export_hint"),
                    preferredStyle: .actionSheet
                )
                let formats: [(PTRideBlackBoxExportFormat, String)] = [
                    (.json, "ride_black_box_export_json"),
                    (.csv, "ride_black_box_export_csv"),
                    (.gpx, "ride_black_box_export_gpx")
                ]
                formats.forEach { format, key in
                    alert.addAction(UIAlertAction(
                        title: PTDashboardConfig.languageFunc(text: key),
                        style: .default
                    ) { [weak self] _ in
                        self?.shareBlackBox(clips: clips, format: format)
                    })
                }
                alert.addAction(UIAlertAction(
                    title: PTDashboardConfig.languageFunc(text: "button_cancel"),
                    style: .cancel
                ))
                if let popover = alert.popoverPresentationController {
                    popover.sourceView = view
                    popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
                }
                present(alert, animated: true)
            } catch {
                showMessage(error.localizedDescription)
            }
        }
    }

    // EN: Generate the share file off the main thread so a large capture cannot block the ride screen.
    // ES: Genera el archivo para compartir fuera del hilo principal para no bloquear la pantalla de conducción.
    // 中文：在后台生成分享文件，避免大抓包阻塞骑行页面。
    private func shareBlackBox(
        clips: [PTRideBlackBoxClip],
        format: PTRideBlackBoxExportFormat
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let fileURL = try await Task.detached(priority: .utility) {
                    let data = try PTRideBlackBoxExporter.data(for: clips, format: format)
                    let fileURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("PTSpeed-BlackBox-\(UUID().uuidString).\(format.fileExtension)")
                    try data.write(to: fileURL, options: .atomic)
                    return fileURL
                }.value

                let activity = UIActivityViewController(
                    activityItems: [fileURL],
                    applicationActivities: nil
                )
                if let popover = activity.popoverPresentationController {
                    popover.sourceView = view
                    popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
                }
                present(activity, animated: true)
            } catch {
                showMessage(error.localizedDescription)
            }
        }
    }

    private func showMessage(_ message: String) {
        let alert = UIAlertController(
            title: PTDashboardConfig.languageFunc(text: "alert_title"),
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(
            title: PTDashboardConfig.languageFunc(text: "button_confirm"),
            style: .default
        ))
        present(alert, animated: true)
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
            return PTDashboardConfig.language(
                key: "maintenance_warning_msg",
                formattedMaintenanceDistance(distance)
            )
        case .normal:
            guard let distance = advice.distanceToMaintenanceKm else { return "-" }
            return formattedMaintenanceDistance(distance)
        case .unknown:
            return PTDashboardConfig.languageFunc(text: "ride_not_available")
        }
    }

    // EN: Present readiness as a compact localized summary while keeping the underlying issues structured.
    // ES: Presenta la preparación como un resumen localizado y compacto, manteniendo los problemas estructurados.
    // 中文：以紧凑的本地化摘要展示准备度，同时保留结构化问题列表。
    private func readinessDescription(_ report: PTRideReadinessReport) -> String {
        let stateKey: String
        switch report.state {
        case .ready: stateKey = "ride_readiness_ready"
        case .attention: stateKey = "ride_readiness_attention"
        case .unavailable: stateKey = "ride_readiness_unavailable"
        }
        guard !report.issues.isEmpty else {
            return PTDashboardConfig.languageFunc(text: stateKey)
        }
        let issueKeys = report.issues.prefix(2).map { issue -> String in
            switch issue {
            case .dashboardDisconnected: return "ride_readiness_issue_dashboard"
            case .obdDisconnected: return "ride_readiness_issue_obd"
            case .lowFuel: return "ride_readiness_issue_fuel"
            case .rangeUnavailable: return "ride_readiness_issue_range"
            case .maintenanceRequired: return "ride_readiness_issue_maintenance"
            case .batteryLow: return "ride_readiness_issue_battery"
            case .staleData: return "ride_readiness_issue_stale"
            case .pttLocationSharingDisabled: return "ride_readiness_issue_ptt"
            }
        }
        let issueText = issueKeys.map { PTDashboardConfig.languageFunc(text: $0) }.joined(separator: "、")
        return "\(PTDashboardConfig.languageFunc(text: stateKey))\n\(issueText)"
    }

    private func formattedMaintenanceDistance(_ distanceKm: Int) -> String {
        PTDashboardConfig.shared.appShowMileageValueString(Double(distanceKm))
            + PTDashboardConfig.shared.appShowUniLabel
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
