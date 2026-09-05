//
//  PTMotorcycleGarageViewController.swift
//  CrazyDashboard
//
//  EN: UIKit entry point for the multi-motorcycle garage.
//  ES: Entrada UIKit para el garaje de varias motocicletas.
//  中文：多车辆车库的 UIKit 入口。
//

import UIKit
import SnapKit
import PooTools

@MainActor
final class PTMotorcycleGarageViewController: PTMotoBaseViewController {
    private let store: PTMotorcycleGarageStore

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    private let vehicleNameLabel = UILabel()
    private let vehicleDetailsLabel = UILabel()
    private let vehicleVINLabel = UILabel()
    private let vehicleMileageLabel = UILabel()
    private let vehicleFuelProfileLabel = UILabel()
    private let tireSuspensionSummaryLabel = UILabel()
    private let refuelSummaryLabel = UILabel()

    private let maintenanceStatusLabel = UILabel()
    private let maintenanceRowsStack = UIStackView()
    private let diagnosticRowsStack = UIStackView()
    private let partsRowsStack = UIStackView()

    private let switchVehicleButton: UIButton
    private let addVehicleButton: UIButton
    private let deleteVehicleButton: UIButton
    private let editVehicleNameButton: UIButton
    private let editMileageButton: UIButton
    private let syncLiveDataButton: UIButton
    private let lidarMeasureButton: UIButton
    private let fuelProfileButton: UIButton
    private let maintenanceWarningButton: UIButton
    private let addMaintenanceButton: UIButton
    private let scanReceiptButton: UIButton
    private let addMaintenanceCalendarButton: UIButton
    private let alarmCenterButton: UIButton
    private let tireSuspensionButton: UIButton
    private let addRefuelButton: UIButton
    private let saveOBDButton: UIButton
    private let addPartButton: UIButton

    init(store: PTMotorcycleGarageStore? = nil) {
        self.store = store ?? PTMotorcycleGarageStore.shared
        self.switchVehicleButton = Self.makeActionButton(titleKey: "garage_switch_vehicle")
        self.addVehicleButton = Self.makeActionButton(titleKey: "garage_add_vehicle")
        self.deleteVehicleButton = Self.makeActionButton(titleKey: "garage_delete_vehicle", color: .systemRed)
        self.editVehicleNameButton = Self.makeActionButton(titleKey: "garage_edit_vehicle_name")
        self.editMileageButton = Self.makeActionButton(titleKey: "garage_edit_mileage")
        self.syncLiveDataButton = Self.makeActionButton(titleKey: "garage_sync_live_data")
        self.lidarMeasureButton = Self.makeActionButton(titleKey: "garage_lidar_measure")
        self.fuelProfileButton = Self.makeActionButton(titleKey: "garage_set_fuel_profile")
        self.maintenanceWarningButton = Self.makeActionButton(titleKey: "garage_set_maintenance_warning")
        self.addMaintenanceButton = Self.makeActionButton(titleKey: "garage_add_maintenance")
        self.scanReceiptButton = Self.makeActionButton(titleKey: "garage_receipt_scan")
        self.addMaintenanceCalendarButton = Self.makeActionButton(titleKey: "garage_add_to_calendar")
        self.alarmCenterButton = Self.makeActionButton(titleKey: "alarm_center_title", color: .systemOrange)
        self.tireSuspensionButton = Self.makeActionButton(titleKey: "garage_edit_tire_suspension")
        self.addRefuelButton = Self.makeActionButton(titleKey: "garage_add_refuel")
        self.saveOBDButton = Self.makeActionButton(titleKey: "garage_save_obd_snapshot")
        self.addPartButton = Self.makeActionButton(titleKey: "garage_add_part")
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        pt_Title = localized("garage_title")
        view.backgroundColor = .black
        configureLabels()
        configureStacks()
        configureActions()
        configureLayout()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(garageDidChange),
            name: PTMotorcycleGarageStore.didChangeNotification,
            object: store
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(garageDashboardSyncDidChange),
            name: PTVehicleConnectivityCoordinator.dashboardGarageSyncDidChange,
            object: nil
        )
        refreshUI()
    }

    private func configureLabels() {
        [vehicleNameLabel, vehicleDetailsLabel, vehicleVINLabel, vehicleMileageLabel, vehicleFuelProfileLabel].forEach {
            $0.numberOfLines = 0
            $0.textColor = .white
        }
        [tireSuspensionSummaryLabel, refuelSummaryLabel].forEach {
            $0.numberOfLines = 0
            $0.textColor = .systemGray2
            $0.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        }
        vehicleNameLabel.font = .systemFont(ofSize: 22, weight: .bold)
        vehicleDetailsLabel.font = .systemFont(ofSize: 14, weight: .regular)
        vehicleDetailsLabel.textColor = .systemGray
        vehicleVINLabel.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        vehicleVINLabel.textColor = .systemGray2
        vehicleMileageLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        vehicleMileageLabel.textColor = PTDashboardConfig.shared.appMainColor
        vehicleFuelProfileLabel.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        vehicleFuelProfileLabel.textColor = .systemGray2
        maintenanceStatusLabel.numberOfLines = 0
        maintenanceStatusLabel.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        maintenanceStatusLabel.textColor = .systemGray2
    }

    private func configureStacks() {
        [maintenanceRowsStack, diagnosticRowsStack, partsRowsStack].forEach {
            $0.axis = .vertical
            $0.spacing = 8
            $0.alignment = .fill
        }
        contentStack.axis = .vertical
        contentStack.spacing = 12
        contentStack.alignment = .fill
    }

    private func configureActions() {
        switchVehicleButton.addTarget(self, action: #selector(showVehiclePicker), for: .touchUpInside)
        addVehicleButton.addTarget(self, action: #selector(showAddVehicleForm), for: .touchUpInside)
        deleteVehicleButton.addTarget(self, action: #selector(confirmDeleteVehicle), for: .touchUpInside)
        editVehicleNameButton.addTarget(self, action: #selector(showVehicleNameForm), for: .touchUpInside)
        editMileageButton.addTarget(self, action: #selector(showMileageForm), for: .touchUpInside)
        syncLiveDataButton.addTarget(self, action: #selector(syncLiveData), for: .touchUpInside)
        lidarMeasureButton.addTarget(self, action: #selector(openLiDARGarageMeasure), for: .touchUpInside)
        fuelProfileButton.addTarget(self, action: #selector(showFuelProfileForm), for: .touchUpInside)
        maintenanceWarningButton.addTarget(self, action: #selector(showMaintenanceWarningForm), for: .touchUpInside)
        addMaintenanceButton.addTarget(self, action: #selector(showMaintenanceForm), for: .touchUpInside)
        scanReceiptButton.addTarget(self, action: #selector(openReceiptScanner), for: .touchUpInside)
        addMaintenanceCalendarButton.addTarget(self, action: #selector(addMaintenanceToCalendar), for: .touchUpInside)
        alarmCenterButton.addTarget(self, action: #selector(openAlarmCenter), for: .touchUpInside)
        tireSuspensionButton.addTarget(self, action: #selector(showTireSuspensionForm), for: .touchUpInside)
        addRefuelButton.addTarget(self, action: #selector(showRefuelForm), for: .touchUpInside)
        saveOBDButton.addTarget(self, action: #selector(saveCurrentOBDSnapshot), for: .touchUpInside)
        addPartButton.addTarget(self, action: #selector(showPartForm), for: .touchUpInside)
    }

    private func configureLayout() {
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false

        let vehicleBody = UIStackView(arrangedSubviews: [
            vehicleNameLabel,
            vehicleDetailsLabel,
            vehicleVINLabel,
            vehicleMileageLabel,
            vehicleFuelProfileLabel,
            makeButtonRow([switchVehicleButton, addVehicleButton, deleteVehicleButton]),
            makeButtonRow([editVehicleNameButton, editMileageButton, syncLiveDataButton]),
            makeButtonRow([lidarMeasureButton]),
            fuelProfileButton
        ])
        vehicleBody.axis = .vertical
        vehicleBody.spacing = 8

        let maintenanceActionRows = UIStackView(arrangedSubviews: [
            makeButtonRow([maintenanceWarningButton, addMaintenanceButton, scanReceiptButton]),
            makeButtonRow([addMaintenanceCalendarButton, alarmCenterButton])
        ])
        maintenanceActionRows.axis = .vertical
        maintenanceActionRows.spacing = 8
        let maintenanceBody = UIStackView(arrangedSubviews: [maintenanceStatusLabel, maintenanceRowsStack, maintenanceActionRows])
        maintenanceBody.axis = .vertical
        maintenanceBody.spacing = 10
        let tireBody = UIStackView(arrangedSubviews: [tireSuspensionSummaryLabel, makeButtonRow([tireSuspensionButton, addRefuelButton]), refuelSummaryLabel])
        tireBody.axis = .vertical
        tireBody.spacing = 10
        let diagnosticBody = makeSectionBody(rows: diagnosticRowsStack, action: saveOBDButton)
        let partsBody = makeSectionBody(rows: partsRowsStack, action: addPartButton)

        contentStack.addArrangedSubview(makeCard(title: localized("garage_current_vehicle"), body: vehicleBody))
        contentStack.addArrangedSubview(makeCard(title: localized("garage_maintenance"), body: maintenanceBody))
        contentStack.addArrangedSubview(makeCard(title: localized("garage_tire_suspension"), body: tireBody))
        contentStack.addArrangedSubview(makeCard(title: localized("garage_diagnostics"), body: diagnosticBody))
        contentStack.addArrangedSubview(makeCard(title: localized("garage_parts"), body: partsBody))

        scrollView.snp.makeConstraints { make in
            make.edges.equalTo(view.safeAreaLayoutGuide)
        }
        contentStack.snp.makeConstraints { make in
            make.top.bottom.equalToSuperview().inset(16)
            make.leading.trailing.equalToSuperview().inset(16)
            make.width.equalTo(scrollView.snp.width).offset(-32)
        }
    }

    private func makeSectionBody(rows: UIStackView, action: UIButton) -> UIStackView {
        let body = UIStackView(arrangedSubviews: [rows, action])
        body.axis = .vertical
        body.spacing = 10
        return body
    }

    private func makeCard(title: String, body: UIView) -> UIView {
        let card = UIView()
        card.backgroundColor = UIColor.white.withAlphaComponent(0.09)
        card.layer.cornerRadius = 14
        card.layer.masksToBounds = true

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textColor = PTDashboardConfig.shared.appMainColor
        titleLabel.font = .systemFont(ofSize: 17, weight: .bold)
        card.addSubview(titleLabel)
        card.addSubview(body)

        titleLabel.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview().inset(16)
        }
        body.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(12)
            make.leading.trailing.bottom.equalToSuperview().inset(16)
        }
        return card
    }

    private func makeButtonRow(_ buttons: [UIButton]) -> UIStackView {
        let row = UIStackView(arrangedSubviews: buttons)
        row.axis = .horizontal
        row.spacing = 8
        row.distribution = .fillEqually
        return row
    }

    private func refreshUI() {
        guard let vehicle = store.currentVehicle else {
            vehicleNameLabel.text = localized("garage_no_vehicle")
            vehicleDetailsLabel.text = nil
            vehicleVINLabel.text = nil
            vehicleMileageLabel.text = nil
            maintenanceStatusLabel.text = nil
            refreshRows()
            return
        }

        vehicleNameLabel.text = vehicle.name
        let detailParts = [vehicle.brand, vehicle.model, vehicle.year.map(String.init)]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        var details = detailParts
        if let serialNumber = vehicle.dashboardSerialNumber {
            details.append("\(localized("garage_dashboard_identity")): \(serialNumber)")
        } else if let identifier = vehicle.dashboardBLEIdentifier {
            details.append("\(localized("garage_dashboard_identity")): \(identifier.uuidString.suffix(8))")
        }
        vehicleDetailsLabel.text = details.isEmpty
            ? localized("garage_no_vehicle_details")
            : details.joined(separator: " · ")
        vehicleVINLabel.text = "\(localized("garage_vin")): \(vehicle.vin.isEmpty ? localized("garage_no_vin") : vehicle.vin)"
        let liveSnapshot = liveDashboardSnapshot(for: vehicle)
        let displayedOdometer = displayedOdometer(for: vehicle, liveSnapshot: liveSnapshot)
        vehicleMileageLabel.text = "\(localized("garage_mileage")): \(formattedMileage(displayedOdometer))"
        if let capacity = vehicle.tankCapacityLiters {
            let reserve = vehicle.reserveFuelPercent ?? 10
            vehicleFuelProfileLabel.text = "\(localized("garage_fuel_profile")): \(String(format: "%.1f L", capacity)) · \(localized("garage_fuel_reserve")): \(reserve)%"
        } else {
            vehicleFuelProfileLabel.text = "\(localized("garage_fuel_profile")): \(localized("garage_not_set"))"
        }
        tireSuspensionSummaryLabel.text = tireSummary(for: vehicle)
        refuelSummaryLabel.text = refuelSummary(for: vehicle)
        refreshMaintenanceStatus()
        refreshRows()
    }

    override func handleMotorcycleData(data: Any?) {
        super.handleMotorcycleData(data: data)
        refreshUI()
    }

    override func handleMotorcycleConnect() {
        super.handleMotorcycleConnect()
        refreshUI()
    }

    override func handleMotorcycleDisconnect() {
        super.handleMotorcycleDisconnect()
        refreshUI()
    }

    private func refreshMaintenanceStatus() {
        guard let vehicle = store.currentVehicle else { return }
        let thresholdKm = Int(store.currentMaintenanceWarningDistanceKm.rounded())
        let coordinator = PTVehicleConnectivityCoordinator.shared
        let isBoundLiveVehicle = coordinator.dashboardDataIsBoundToSelectedVehicle
            && coordinator.dashboardGarageVehicleID == vehicle.id
        let liveSnapshot = isBoundLiveVehicle ? coordinator.dashboardLiveSnapshot : nil
        let distanceKm = liveSnapshot?.maintenanceDistanceKm ?? vehicle.dashboardMaintenanceDistanceKm
        let maintenanceFlag = liveSnapshot?.maintenanceFlag ?? vehicle.dashboardMaintenanceFlag
        let advice = PTRideMaintenanceAdvisor.advise(
            distanceToMaintenanceKm: distanceKm,
            rawMaintenanceFlag: maintenanceFlag,
            warningThresholdKm: thresholdKm
        )
        let remaining = distanceKm.map { distance in
            distance > 0 ? formattedMileage(Double(distance)) : localized("ride_not_available")
        } ?? localized("ride_not_available")
        let status: String
        switch advice.state {
        case .normal:
            status = localized("maintenance_state_normal")
            maintenanceStatusLabel.textColor = .systemGreen
        case .dueSoon:
            status = localized("maintenance_state_due_soon")
            maintenanceStatusLabel.textColor = .systemOrange
        case .required:
            status = localized("maintenance_state_required")
            maintenanceStatusLabel.textColor = .systemRed
        case .unknown:
            status = localized("maintenance_state_unknown")
            maintenanceStatusLabel.textColor = .systemGray2
        }
        maintenanceStatusLabel.text = [
            "\(localized("garage_maintenance_warning_distance")): \(formattedMileage(Double(thresholdKm)))",
            "\(localized("garage_maintenance_remaining")): \(remaining)",
            "\(localized("garage_maintenance_status")): \(status)",
            syncStatusDescription(
                vehicle: vehicle,
                coordinator: coordinator,
                isBoundLiveVehicle: isBoundLiveVehicle
            )
        ].joined(separator: "\n")
    }

    private func tireSummary(for vehicle: PTMotorcycleProfile) -> String {
        guard let profile = vehicle.tireSuspensionProfile else {
            return localized("garage_tire_suspension_not_set")
        }
        let frontName = [profile.frontTireBrand, profile.frontTireModel, profile.frontTireSize]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let rearName = [profile.rearTireBrand, profile.rearTireModel, profile.rearTireSize]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let front = frontName.isEmpty ? "-" : frontName
        let rear = rearName.isEmpty ? "-" : rearName
        let frontPressure = profile.coldFrontPressure.map { String(format: "%.2f %@", $0, profile.pressureUnit) } ?? "-"
        let rearPressure = profile.coldRearPressure.map { String(format: "%.2f %@", $0, profile.pressureUnit) } ?? "-"
        var lines = [
            "\(localized("garage_front_tire")): \(front) · \(localized("garage_rear_tire")): \(rear)",
            "\(localized("garage_cold_pressure")): \(frontPressure) / \(rearPressure)"
        ]
        let hotFront = profile.hotFrontPressure.map { String(format: "%.2f %@", $0, profile.pressureUnit) } ?? "-"
        let hotRear = profile.hotRearPressure.map { String(format: "%.2f %@", $0, profile.pressureUnit) } ?? "-"
        if profile.hotFrontPressure != nil || profile.hotRearPressure != nil {
            lines.append("\(localized("garage_hot_pressure")): \(hotFront) / \(hotRear)")
        }
        if let odometerKm = profile.odometerKm {
            lines.append("\(localized("garage_observation_mileage")): \(formattedMileage(odometerKm))")
        }
        if !profile.loadScenario.isEmpty {
            lines.append("\(localized("garage_load_scenario")): \(profile.loadScenario)")
        }
        if !profile.notes.isEmpty {
            lines.append("\(localized("garage_notes")): \(profile.notes)")
        }
        return lines.joined(separator: "\n")
    }

    private func refuelSummary(for vehicle: PTMotorcycleProfile) -> String {
        guard let records = vehicle.refuelRecords, !records.isEmpty else {
            return localized("garage_refuel_empty")
        }
        guard let economy = PTFuelRangeCalculator.weightedConsumption(from: records) else {
            return "\(localized("garage_refuel_count")): \(records.count) · \(localized("garage_refuel_need_two_full"))"
        }
        return "\(localized("garage_refuel_count")): \(records.count) · \(localized("garage_fuel_economy")): \(String(format: "%.2f L/100 km", economy.litersPer100Km))"
    }

    private func liveDashboardSnapshot(for vehicle: PTMotorcycleProfile) -> PTGarageDashboardSnapshot? {
        let coordinator = PTVehicleConnectivityCoordinator.shared
        if coordinator.dashboardDataIsBoundToSelectedVehicle,
           coordinator.dashboardGarageVehicleID == vehicle.id,
           let snapshot = coordinator.dashboardLiveSnapshot {
            return snapshot
        }

        guard vehicle.id == store.selectedVehicleID,
              coordinator.snapshot.dashboard.transport == .dashboardMock,
              (coordinator.snapshot.dashboard.state == .connecting
                || coordinator.snapshot.dashboard.state == .connected),
              let data1 = PTBluetoothServerManager.shared.latestData1,
              data1.odometerAvailability.isAvailable else {
            return nil
        }
        return PTGarageDashboardSnapshot(odometerKm: data1.odoKm, source: .mock)
    }

    private func displayedOdometer(
        for vehicle: PTMotorcycleProfile,
        liveSnapshot: PTGarageDashboardSnapshot?
    ) -> Double {
        guard let liveSnapshot, let liveOdometer = liveSnapshot.odometerKm else {
            return vehicle.odometerKm
        }

        switch liveSnapshot.source {
        case .mock:
            guard vehicle.odometerKm == 0
                    || vehicle.odometerSource == .mock
                    || vehicle.isLegacyMockOdometer else {
                return vehicle.odometerKm
            }
            return liveOdometer
        case .dashboard:
            if vehicle.odometerSource == nil || vehicle.odometerSource == .mock {
                return liveOdometer
            }
            return max(vehicle.odometerKm, liveOdometer)
        }
    }

    private func refreshRows() {
        removeRows(from: maintenanceRowsStack)
        removeRows(from: diagnosticRowsStack)
        removeRows(from: partsRowsStack)

        guard let vehicle = store.currentVehicle else { return }

        if vehicle.maintenanceRecords.isEmpty {
            maintenanceRowsStack.addArrangedSubview(makeEmptyRow(key: "garage_no_maintenance"))
        } else {
            vehicle.maintenanceRecords.forEach {
                maintenanceRowsStack.addArrangedSubview(makeMaintenanceRow($0, vehicle: vehicle))
            }
        }

        if vehicle.diagnosticReports.isEmpty {
            diagnosticRowsStack.addArrangedSubview(makeEmptyRow(key: "garage_no_diagnostic"))
        } else {
            vehicle.diagnosticReports.forEach { diagnosticRowsStack.addArrangedSubview(makeDiagnosticRow($0)) }
        }

        if vehicle.parts.isEmpty {
            partsRowsStack.addArrangedSubview(makeEmptyRow(key: "garage_no_parts"))
        } else {
            vehicle.parts.forEach { partsRowsStack.addArrangedSubview(makePartRow($0)) }
        }
    }

    private func removeRows(from stack: UIStackView) {
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
    }

    private func makeEmptyRow(key: String) -> UILabel {
        let label = UILabel()
        label.text = localized(key)
        label.textColor = .systemGray
        label.font = .systemFont(ofSize: 14)
        label.numberOfLines = 0
        return label
    }

    private func makeMaintenanceRow(
        _ record: PTGarageMaintenanceRecord,
        vehicle: PTMotorcycleProfile
    ) -> UIView {
        let detail = [
            "\(localized("garage_mileage")): \(formattedMileage(record.mileageKm))",
            formattedDate(record.completedAt),
            record.nextDueMileageKm.map { "\(localized("garage_next_due")): \(formattedMileage($0))" },
            record.dueDate.map { "\(localized("garage_due_date")): \(formattedDate($0))" }
        ].compactMap { $0 }.joined(separator: " · ")
        var detailWithCost = detail
        if let cost = record.cost {
            detailWithCost += " · \(localized("garage_cost")): \(String(format: "%.2f", cost))\(record.currency.map { " \($0)" } ?? "")"
        }
        let associatedParts = record.associatedPartIDs.compactMap { partID in
            vehicle.parts.first(where: { $0.id == partID })?.name
        }
        if !associatedParts.isEmpty {
            detailWithCost += " · \(localized("garage_parts")): \(associatedParts.joined(separator: ", "))"
        }
        let notes = record.notes.isEmpty ? nil : record.notes
        return makeRecordRow(
            title: record.title,
            detail: detailWithCost,
            notes: notes,
            deleteHandler: { [weak self] in
                self?.store.removeMaintenance(id: record.id)
            }
        )
    }

    private func syncStatusDescription(
        vehicle: PTMotorcycleProfile,
        coordinator: PTVehicleConnectivityCoordinator,
        isBoundLiveVehicle: Bool
    ) -> String {
        if coordinator.dashboardIdentityIsConflicted {
            return localized("garage_sync_identity_conflict")
        }
        if let boundVehicleID = coordinator.dashboardGarageVehicleID,
           boundVehicleID != vehicle.id {
            return localized("garage_sync_other_vehicle")
        }
        if isBoundLiveVehicle {
            return localized("garage_sync_auto_active")
        }
        if let lastSync = vehicle.lastDashboardSyncAt {
            return "\(localized("garage_sync_last_update")): \(formattedDate(lastSync))"
        }
        return localized("garage_sync_waiting")
    }

    private func makeDiagnosticRow(_ report: PTGarageDiagnosticReport) -> UIView {
        var details = [formattedDate(report.capturedAt)]
        if !report.protocolName.isEmpty { details.append(report.protocolName) }
        if !report.ecuVersion.isEmpty { details.append("ECU: \(report.ecuVersion)") }
        if !report.vin.isEmpty { details.append("VIN: \(report.vin)") }
        if !report.didResults.isEmpty {
            details.append("DID \(report.successfulDIDCount)/\(report.didResults.count)")
        }
        if let confirmedDTCs = report.confirmedDTCs, !confirmedDTCs.isEmpty {
            details.append("DTC \(confirmedDTCs.count)")
        }
        if let mode6Results = report.mode6Results, !mode6Results.isEmpty {
            details.append("Mode 6 \(mode6Results.count)")
        }
        if let freezeFrame = report.freezeFrame, !freezeFrame.isEmpty {
            details.append("Freeze Frame \(freezeFrame.count)")
        }
        let notes = [
            report.adapterName.isEmpty ? nil : report.adapterName,
            report.failureReasons?.isEmpty == false ? "⚠️ \(report.failureReasons!.joined(separator: "; "))" : nil
        ].compactMap { $0 }.joined(separator: "\n")
        return makeRecordRow(
            title: localized("garage_obd_report"),
            detail: details.joined(separator: " · "),
            notes: notes.isEmpty ? nil : notes,
            deleteHandler: { [weak self] in
                self?.store.removeDiagnosticReport(id: report.id)
            }
        )
    }

    private func makePartRow(_ record: PTGaragePartRecord) -> UIView {
        var details = [formattedDate(record.installedAt)]
        if !record.partNumber.isEmpty { details.insert(record.partNumber, at: 0) }
        if let mileage = record.mileageKm { details.append("\(localized("garage_mileage")): \(formattedMileage(mileage))") }
        return makeRecordRow(
            title: record.name,
            detail: details.joined(separator: " · "),
            notes: record.notes.isEmpty ? nil : record.notes,
            deleteHandler: { [weak self] in
                self?.store.removePart(id: record.id)
            }
        )
    }

    private func makeRecordRow(
        title: String,
        detail: String,
        notes: String?,
        deleteHandler: @escaping () -> Void
    ) -> UIView {
        let row = UIStackView()
        row.axis = .vertical
        row.spacing = 3
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        row.backgroundColor = UIColor.black.withAlphaComponent(0.18)
        row.layer.cornerRadius = 8

        let titleRow = UIStackView()
        titleRow.axis = .horizontal
        titleRow.alignment = .center
        titleRow.spacing = 8

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.numberOfLines = 0

        let deleteButton = UIButton(type: .system)
        deleteButton.setTitle("×", for: .normal)
        deleteButton.setTitleColor(.systemRed, for: .normal)
        deleteButton.titleLabel?.font = .systemFont(ofSize: 22, weight: .bold)
        deleteButton.setContentHuggingPriority(.required, for: .horizontal)
        deleteButton.addAction(UIAction { _ in deleteHandler() }, for: .touchUpInside)
        deleteButton.accessibilityLabel = localized("garage_delete")

        titleRow.addArrangedSubview(titleLabel)
        titleRow.addArrangedSubview(deleteButton)
        row.addArrangedSubview(titleRow)

        let detailLabel = UILabel()
        detailLabel.text = detail
        detailLabel.textColor = .systemGray2
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.numberOfLines = 0
        row.addArrangedSubview(detailLabel)

        if let notes, !notes.isEmpty {
            let notesLabel = UILabel()
            notesLabel.text = notes
            notesLabel.textColor = .systemGray
            notesLabel.font = .systemFont(ofSize: 12)
            notesLabel.numberOfLines = 0
            row.addArrangedSubview(notesLabel)
        }
        return row
    }

    @objc private func garageDidChange() {
        refreshUI()
    }

    @objc private func garageDashboardSyncDidChange() {
        refreshUI()
    }

    // EN: Keep alarm scheduling in its dedicated center so garage records remain the source of vehicle data.
    // ES: Mantiene la programación en su centro dedicado para que los registros del garaje sigan siendo la fuente de datos.
    // 中文：提醒安排统一进入独立中心，车库记录仍只负责车辆数据。
    @objc private func openAlarmCenter() {
        safePushViewController(PTMotoAlarmCenterViewController())
    }

    // EN: Receipt OCR creates an editable draft and never saves until the rider confirms it.
    // ES: El OCR del recibo crea un borrador editable y nunca guarda hasta que el piloto lo confirma.
    // 中文：单据 OCR 只创建可编辑草稿，必须由骑手确认后才保存。
    @objc private func openReceiptScanner() {
        safePushViewController(PTGarageReceiptScanViewController(store: store))
    }

    // EN: Calendar export is an explicit action for the next maintenance item only.
    // ES: La exportación al calendario es una acción explícita y solo usa el próximo mantenimiento.
    // 中文：日历导出必须由用户主动触发，并且只使用下一条保养记录。
    @objc private func addMaintenanceToCalendar() {
        guard let vehicle = store.currentVehicle else {
            showMessage(localized("garage_no_vehicle"))
            return
        }
        guard let record = vehicle.maintenanceRecords
            .filter({ $0.dueDate != nil })
            .sorted(by: { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) })
            .first else {
            showMessage(localized("calendar_no_due_date"))
            return
        }
        PTMotoCalendarManager.shared.presentMaintenanceReminder(
            record: record,
            vehicleName: vehicle.name,
            from: self
        )
    }

    @objc private func showVehiclePicker() {
        let alert = UIAlertController(
            title: localized("garage_switch_vehicle"),
            message: nil,
            preferredStyle: .actionSheet
        )
        for vehicle in store.vehicles {
            let title = vehicle.id == store.selectedVehicleID ? "✓ \(vehicle.name)" : vehicle.name
            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                guard let self else { return }
                _ = self.store.selectVehicle(id: vehicle.id)
            })
        }
        alert.addAction(UIAlertAction(title: localized("button_cancel"), style: .cancel))
        configurePopover(for: alert, sourceView: switchVehicleButton)
        present(alert, animated: true)
    }

    @objc private func showAddVehicleForm() {
        let alert = UIAlertController(
            title: localized("garage_add_vehicle"),
            message: localized("garage_vehicle_form_hint"),
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = self.localized("garage_vehicle_name")
            let nickname = PTMotoUserDefaultStruct.PTTCustomUserName
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !nickname.isEmpty {
                field.text = nickname
            }
        }
        alert.addTextField { $0.placeholder = self.localized("garage_brand") }
        alert.addTextField { $0.placeholder = self.localized("garage_model") }
        alert.addTextField { $0.placeholder = self.localized("garage_year") ; $0.keyboardType = .numberPad }
        alert.addTextField { $0.placeholder = self.localized("garage_vin") }
        alert.addTextField { $0.placeholder = self.localized("garage_initial_mileage") ; $0.keyboardType = .decimalPad }
        alert.addAction(UIAlertAction(title: localized("button_cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: localized("button_confirm"), style: .default) { [weak self, weak alert] _ in
            guard let self, let alert else { return }
            let values = alert.textFields?.map { $0.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" } ?? []
            let initialMileage = values.count > 5 ? Double(values[5].replacingOccurrences(of: ",", with: ".")) ?? 0 : 0
            let year = values.count > 3 ? Int(values[3]) : nil
            guard values.count > 0,
                  let profile = self.store.createVehicle(
                    name: values[0],
                    brand: values.count > 1 ? values[1] : "",
                    model: values.count > 2 ? values[2] : "",
                    year: year,
                    vin: values.count > 4 ? values[4] : "",
                    odometerKm: initialMileage
                  ) else {
                self.showMessage(localized("garage_invalid_input"))
                return
            }
            _ = self.store.selectVehicle(id: profile.id)
        })
        present(alert, animated: true)
    }

    @objc private func confirmDeleteVehicle() {
        guard store.vehicles.count > 1 else {
            showMessage(localized("garage_keep_one_vehicle"))
            return
        }
        let alert = UIAlertController(
            title: localized("garage_delete_vehicle"),
            message: store.currentVehicle?.name,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: localized("button_cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: localized("garage_delete"), style: .destructive) { [weak self] _ in
            guard let self, let id = self.store.currentVehicle?.id else { return }
            _ = self.store.deleteVehicle(id: id)
        })
        present(alert, animated: true)
    }

    @objc private func showVehicleNameForm() {
        let alert = UIAlertController(
            title: localized("garage_edit_vehicle_name"),
            message: localized("garage_vehicle_name_form_hint"),
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.text = self.store.currentVehicle?.name
            field.placeholder = self.localized("garage_vehicle_name")
        }
        alert.addAction(UIAlertAction(title: localized("button_cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: localized("button_confirm"), style: .default) { [weak self, weak alert] _ in
            guard let self,
                  let name = alert?.textFields?.first?.text,
                  self.store.updateVehicleName(name) else {
                self?.showMessage(self?.localized("garage_invalid_input") ?? "")
                return
            }
        })
        present(alert, animated: true)
    }

    @objc private func showMileageForm() {
        let alert = UIAlertController(
            title: localized("garage_edit_mileage"),
            message: localized("garage_mileage_form_hint"),
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.keyboardType = .decimalPad
            field.text = self.store.currentVehicle.map { String(format: "%.2f", $0.odometerKm) }
        }
        alert.addAction(UIAlertAction(title: localized("button_cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: localized("button_confirm"), style: .default) { [weak self, weak alert] _ in
            guard let self, let text = alert?.textFields?.first?.text,
                  let value = Double(text.replacingOccurrences(of: ",", with: ".")),
                  self.store.updateOdometer(value) else {
                self?.showMessage(self?.localized("garage_invalid_input") ?? "")
                return
            }
        })
        present(alert, animated: true)
    }

    @objc private func syncLiveData() {
        let coordinator = PTVehicleConnectivityCoordinator.shared
        if (coordinator.dashboardNeedsGarageVehicleAssociation || coordinator.dashboardIdentityIsConflicted),
           coordinator.dashboardConnectionIdentity?.isUsable == true {
            presentDashboardAssociationPrompt(titleKey: "garage_sync_identity_conflict")
            return
        }
        if let boundVehicleID = coordinator.dashboardGarageVehicleID,
           boundVehicleID != store.selectedVehicleID {
            presentDashboardAssociationPrompt(titleKey: "garage_sync_other_vehicle")
            return
        }

        let dashboardResult = coordinator.syncCurrentGarageVehicleNow()
        let didSaveOBD = store.saveCurrentOBDSnapshot() != nil
        store.syncGarageToICloud()

        if didSaveOBD {
            switch dashboardResult {
            case .identityConflict, .vehicleNotFound:
                showMessage(
                    "\(localized("garage_sync_success"))\n\(localized("garage_sync_identity_conflict"))"
                )
            default:
                showMessage(localized("garage_sync_success"))
            }
            return
        }

        switch dashboardResult {
        case .updated:
            showMessage(localized("garage_sync_success"))
        case .unchanged:
            showMessage(localized("garage_sync_latest"))
        case .unavailable:
            showMessage(localized("garage_no_live_data"))
        case .identityConflict, .vehicleNotFound:
            showMessage(localized("garage_sync_identity_conflict"))
        }
    }

    // EN: Open the explicit garage LiDAR measurement tool without starting a vehicle command.
    // ES: Abre la herramienta explícita de medición LiDAR del garaje sin iniciar comandos del vehículo.
    // 中文：打开用户主动使用的车库 LiDAR 测距工具，不发送任何车辆指令。
    @objc private func openLiDARGarageMeasure() {
        navigationController?.pushViewController(
            PTLiDARAssistViewController(mode: .garageMeasure),
            animated: true
        )
    }

    // EN: Keep explicit dashboard reassignment behind one confirmation alert.
    // ES: Mantén la reasignación explícita del tablero detrás de una única confirmación.
    // 中文：所有显式仪表重新关联都必须经过一次确认弹窗。
    private func presentDashboardAssociationPrompt(titleKey: String) {
        let alert = UIAlertController(
            title: localized(titleKey),
            message: localized("garage_bind_dashboard_hint"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: localized("button_cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: localized("garage_bind_dashboard"), style: .default) { [weak self] _ in
            guard let self else { return }
            if PTVehicleConnectivityCoordinator.shared.associateCurrentDashboardWithSelectedVehicle() {
                self.showMessage(self.localized("garage_bind_success"))
            } else {
                self.showMessage(self.localized("garage_sync_identity_conflict"))
            }
        })
        present(alert, animated: true)
    }

    @objc private func showMaintenanceWarningForm() {
        let alert = UIAlertController(
            title: localized("garage_set_maintenance_warning"),
            message: localized("garage_maintenance_warning_form_hint"),
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.keyboardType = .decimalPad
            field.text = PTDashboardConfig.shared.appShowMileageValueString(
                self.store.currentMaintenanceWarningDistanceKm
            )
        }
        alert.addAction(UIAlertAction(title: localized("button_cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: localized("button_confirm"), style: .default) { [weak self, weak alert] _ in
            guard let self,
                  let text = alert?.textFields?.first?.text,
                  let displayedDistance = Self.optionalDouble(text),
                  displayedDistance.isFinite else {
                self?.showMessage(self?.localized("garage_invalid_input") ?? "")
                return
            }

            let distanceKm = PTDashboardConfig.shared.appUniIsMetric
                ? displayedDistance
                : displayedDistance / kmToMilOffset
            guard self.store.updateMaintenanceWarningDistance(distanceKm) else {
                self.showMessage(self.localized("garage_invalid_input"))
                return
            }
            self.refreshUI()
        })
        present(alert, animated: true)
    }

    @objc private func showMaintenanceForm() {
        let alert = UIAlertController(
            title: localized("garage_add_maintenance"),
            message: localized("garage_maintenance_form_hint"),
            preferredStyle: .alert
        )
        alert.addTextField { $0.placeholder = self.localized("garage_maintenance_title") }
        alert.addTextField { field in
            field.placeholder = self.localized("garage_mileage_optional")
            field.keyboardType = .decimalPad
        }
        alert.addTextField { field in
            field.placeholder = self.localized("garage_next_due")
            field.keyboardType = .decimalPad
        }
        alert.addTextField { $0.placeholder = self.localized("garage_due_date_optional") }
        alert.addTextField { field in
            field.placeholder = self.localized("garage_cost_optional")
            field.keyboardType = .decimalPad
        }
        alert.addTextField { $0.placeholder = self.localized("garage_currency_optional") }
        alert.addTextField { $0.placeholder = self.localized("garage_notes") }
        alert.addTextField { $0.placeholder = self.localized("garage_associated_parts") }
        alert.addAction(UIAlertAction(title: localized("button_cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: localized("button_confirm"), style: .default) { [weak self, weak alert] _ in
            guard let self, let alert else { return }
            let values = alert.textFields?.map { $0.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" } ?? []
            let mileage = Self.optionalDouble(values[safe: 1])
            let nextDue = Self.optionalDouble(values[safe: 2])
            let dueDateText = values[safe: 3] ?? ""
            let dueDate = Self.optionalDate(dueDateText)
            let cost = Self.optionalDouble(values[safe: 4])
            let associatedNames = Set(
                (values[safe: 7] ?? "")
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                    .filter { !$0.isEmpty }
            )
            let associatedPartIDs = self.store.currentVehicle?.parts.compactMap { part in
                associatedNames.contains(part.name.lowercased()) ? part.id : nil
            } ?? []
            let isDueDateValid = dueDateText.isEmpty || dueDate != nil
            guard !values.isEmpty,
                  isDueDateValid,
                  self.store.addMaintenance(
                    title: values[0],
                    mileageKm: mileage,
                    nextDueMileageKm: nextDue,
                    notes: values[safe: 6] ?? "",
                    cost: cost,
                    currency: values[safe: 5],
                    dueDate: dueDate,
                    associatedPartIDs: associatedPartIDs
                  ) != nil else {
                self.showMessage(localized("garage_invalid_input"))
                return
            }
        })
        present(alert, animated: true)
    }

    // EN: Present one scrollable editor so every observation field remains editable on iPhone.
    // ES: Presenta un editor desplazable para que todos los campos de observación sigan siendo editables en iPhone.
    // 中文：使用可滚动编辑页，确保 iPhone 上所有观察字段都可以编辑。
    @objc private func showTireSuspensionForm() {
        let editor = PTGarageTireSuspensionEditorViewController(
            profile: store.currentVehicle?.tireSuspensionProfile
        )
        editor.onSave = { [weak self] profile in
            _ = self?.store.updateTireSuspensionProfile(profile)
        }
        let navigationController = UINavigationController(rootViewController: editor)
        navigationController.modalPresentationStyle = .pageSheet
        present(navigationController, animated: true)
    }

    @objc private func showRefuelForm() {
        let alert = UIAlertController(
            title: localized("garage_add_refuel"),
            message: localized("garage_refuel_hint"),
            preferredStyle: .alert
        )
        let currentMileage = store.currentVehicle?.odometerKm ?? 0
        alert.addTextField { field in
            field.placeholder = self.localized("garage_mileage")
            field.keyboardType = .decimalPad
            field.text = String(format: "%.1f", currentMileage)
        }
        alert.addTextField { field in
            field.placeholder = self.localized("garage_refuel_liters")
            field.keyboardType = .decimalPad
        }
        alert.addTextField { field in
            field.placeholder = self.localized("garage_cost_optional")
            field.keyboardType = .decimalPad
        }
        alert.addTextField { $0.placeholder = self.localized("garage_refuel_full_tank") }
        alert.addAction(UIAlertAction(title: localized("button_cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: localized("button_confirm"), style: .default) { [weak self, weak alert] _ in
            guard let self, let fields = alert?.textFields,
                  let mileage = Self.optionalDouble(fields[safe: 0]?.text),
                  let liters = Self.optionalDouble(fields[safe: 1]?.text),
                  let record = self.store.addRefuel(
                    odometerKm: mileage,
                    liters: liters,
                    amount: Self.optionalDouble(fields[safe: 2]?.text),
                    isFullTank: (fields[safe: 3]?.text ?? "").lowercased() == "1"
                  ) else {
                self?.showMessage(self?.localized("garage_invalid_input") ?? "")
                return
            }
            _ = record
        })
        present(alert, animated: true)
    }

    // EN: Let each motorcycle own its tank capacity and reserve threshold for a bounded range estimate.
    // ES: Permite que cada motocicleta conserve su capacidad y reserva para una estimación limitada.
    // 中文：让每辆摩托车独立保存油箱容量和预留油量，用于有边界的续航估算。
    @objc private func showFuelProfileForm() {
        let alert = UIAlertController(
            title: localized("garage_set_fuel_profile"),
            message: localized("garage_fuel_profile_hint"),
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = self.localized("garage_tank_capacity")
            field.keyboardType = .decimalPad
            if let value = self.store.currentVehicle?.tankCapacityLiters {
                field.text = String(format: "%.1f", value)
            }
        }
        alert.addTextField { field in
            field.placeholder = self.localized("garage_fuel_reserve")
            field.keyboardType = .numberPad
            if let value = self.store.currentVehicle?.reserveFuelPercent {
                field.text = String(value)
            }
        }
        alert.addAction(UIAlertAction(title: localized("button_cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: localized("button_confirm"), style: .default) { [weak self, weak alert] _ in
            guard let self, let fields = alert?.textFields, fields.count == 2 else { return }
            let capacityText = fields[0].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let reserveText = fields[1].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let capacity = capacityText.isEmpty ? nil : Self.optionalDouble(capacityText.replacingOccurrences(of: ",", with: "."))
            let reserve = reserveText.isEmpty ? nil : Int(reserveText)
            guard self.store.updateFuelProfile(
                tankCapacityLiters: capacity,
                reserveFuelPercent: reserve
            ) else {
                self.showMessage(self.localized("garage_invalid_input"))
                return
            }
            self.refreshUI()
        })
        present(alert, animated: true)
    }

    @objc private func saveCurrentOBDSnapshot() {
        if store.saveCurrentOBDSnapshot() != nil {
            showMessage(localized("garage_saved"))
        } else {
            showMessage(localized("garage_obd_unavailable"))
        }
    }

    @objc private func showPartForm() {
        let alert = UIAlertController(
            title: localized("garage_add_part"),
            message: nil,
            preferredStyle: .alert
        )
        alert.addTextField { $0.placeholder = self.localized("garage_part_name") }
        alert.addTextField { $0.placeholder = self.localized("garage_part_number") }
        alert.addTextField { field in
            field.placeholder = self.localized("garage_mileage_optional")
            field.keyboardType = .decimalPad
        }
        alert.addTextField { $0.placeholder = self.localized("garage_notes") }
        alert.addAction(UIAlertAction(title: localized("button_cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: localized("button_confirm"), style: .default) { [weak self, weak alert] _ in
            guard let self, let alert else { return }
            let values = alert.textFields?.map { $0.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" } ?? []
            guard !values.isEmpty,
                  self.store.addPart(
                    name: values[0],
                    partNumber: values[safe: 1] ?? "",
                    mileageKm: Self.optionalDouble(values[safe: 2]),
                    notes: values[safe: 3] ?? ""
                  ) != nil else {
                self.showMessage(localized("garage_invalid_input"))
                return
            }
        })
        present(alert, animated: true)
    }

    private func configurePopover(for alert: UIAlertController, sourceView: UIView) {
        guard let popover = alert.popoverPresentationController else { return }
        popover.sourceView = sourceView
        popover.sourceRect = sourceView.bounds
    }

    private func showMessage(_ message: String) {
        let alert = UIAlertController(title: localized("garage_title"), message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: localized("button_confirm"), style: .default))
        present(alert, animated: true)
    }

    private func localized(_ key: String) -> String {
        PTDashboardConfig.languageFunc(text: key)
    }

    private func formattedMileage(_ kilometers: Double) -> String {
        "\(PTDashboardConfig.shared.appShowMileageValueString(kilometers))\(PTDashboardConfig.shared.appShowUniLabel)"
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    private static func optionalDouble(_ value: String?) -> Double? {
        guard let value, !value.isEmpty else { return nil }
        return Double(value.replacingOccurrences(of: ",", with: "."))
    }

    // EN: Maintenance due dates use an unambiguous ISO calendar date in the compact form.
    // ES: Las fechas de vencimiento usan una fecha de calendario ISO inequívoca en el formulario compacto.
    // 中文：紧凑表单中的保养到期日使用明确的 ISO 日历日期格式。
    private static func optionalDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.date(from: value)
    }

    private static func makeActionButton(titleKey: String, color: UIColor? = nil) -> UIButton {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.filled()
        configuration.title = PTDashboardConfig.languageFunc(text: titleKey)
        configuration.baseForegroundColor = .white
        configuration.baseBackgroundColor = color ?? PTDashboardConfig.shared.appMainColor
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)
        button.configuration = configuration
        button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        button.layer.cornerRadius = 8
        button.layer.masksToBounds = true
        button.titleLabel?.numberOfLines = 2
        button.titleLabel?.textAlignment = .center
        return button
    }
}

// EN: The editor keeps the complete tire and suspension profile in one scrollable, read-only-safe form.
// ES: El editor conserva el perfil completo de neumáticos y suspensión en un formulario desplazable y seguro.
// 中文：编辑器用一个可滚动表单保存完整的轮胎与悬挂档案，并保持只记录观察值。
@MainActor
private final class PTGarageTireSuspensionEditorViewController: UIViewController {
    var onSave: ((PTGarageTireSuspensionProfile) -> Void)?

    private let profile: PTGarageTireSuspensionProfile?
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let pressureUnitControl = UISegmentedControl(items: ["bar", "kPa", "psi"])
    private let notesView = UITextView()
    private var fields: [String: UITextField] = [:]

    init(profile: PTGarageTireSuspensionProfile?) {
        self.profile = profile
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = localized("garage_edit_tire_suspension")
        view.backgroundColor = .black
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancel)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .save,
            target: self,
            action: #selector(save)
        )
        configureLayout()
        populateProfile()
    }

    private func configureLayout() {
        contentStack.axis = .vertical
        contentStack.spacing = 18
        contentStack.alignment = .fill

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32)
        ])

        contentStack.addArrangedSubview(makeHintLabel())
        addSection(
            titleKey: "garage_tire_details",
            fields: [
                ("frontTireBrand", "garage_tire_front_brand", .default),
                ("frontTireModel", "garage_tire_front_model", .default),
                ("frontTireSize", "garage_front_tire_size", .default),
                ("rearTireBrand", "garage_tire_rear_brand", .default),
                ("rearTireModel", "garage_tire_rear_model", .default),
                ("rearTireSize", "garage_rear_tire_size", .default)
            ]
        )
        addSection(
            titleKey: "garage_pressure_observations",
            fields: [
                ("coldFrontPressure", "garage_front_pressure", .decimalPad),
                ("coldRearPressure", "garage_rear_pressure", .decimalPad),
                ("hotFrontPressure", "garage_hot_front_pressure", .decimalPad),
                ("hotRearPressure", "garage_hot_rear_pressure", .decimalPad)
            ]
        )
        addUnitSection()
        addSection(
            titleKey: "garage_suspension_settings",
            fields: [
                ("loadScenario", "garage_load_scenario", .default),
                ("frontPreload", "garage_front_preload", .default),
                ("frontRebound", "garage_front_rebound", .default),
                ("frontCompression", "garage_front_compression", .default),
                ("rearPreload", "garage_rear_preload", .default),
                ("rearRebound", "garage_rear_rebound", .default),
                ("rearCompression", "garage_rear_compression", .default)
            ]
        )
        addObservationSection()
    }

    private func addSection(
        titleKey: String,
        fields definitions: [(String, String, UIKeyboardType)]
    ) {
        let section = UIStackView()
        section.axis = .vertical
        section.spacing = 8
        section.addArrangedSubview(makeSectionTitle(localized(titleKey)))
        for (key, placeholderKey, keyboardType) in definitions {
            let field = UITextField()
            field.placeholder = localized(placeholderKey)
            field.textColor = .white
            field.tintColor = PTDashboardConfig.shared.appMainColor
            field.keyboardType = keyboardType
            field.autocorrectionType = .no
            field.backgroundColor = UIColor.white.withAlphaComponent(0.09)
            field.layer.cornerRadius = 8
            field.layer.masksToBounds = true
            field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 1))
            field.leftViewMode = .always
            field.heightAnchor.constraint(equalToConstant: 44).isActive = true
            fields[key] = field
            section.addArrangedSubview(field)
        }
        contentStack.addArrangedSubview(section)
    }

    private func addUnitSection() {
        let section = UIStackView()
        section.axis = .vertical
        section.spacing = 8
        section.addArrangedSubview(makeSectionTitle(localized("garage_pressure_unit")))
        pressureUnitControl.selectedSegmentIndex = 0
        pressureUnitControl.selectedSegmentTintColor = PTDashboardConfig.shared.appMainColor
        section.addArrangedSubview(pressureUnitControl)
        contentStack.addArrangedSubview(section)
    }

    private func addObservationSection() {
        let section = UIStackView()
        section.axis = .vertical
        section.spacing = 8
        section.addArrangedSubview(makeSectionTitle(localized("garage_observations")))

        let mileageField = UITextField()
        mileageField.placeholder = localized("garage_observation_mileage")
        mileageField.textColor = .white
        mileageField.tintColor = PTDashboardConfig.shared.appMainColor
        mileageField.keyboardType = .decimalPad
        mileageField.autocorrectionType = .no
        mileageField.backgroundColor = UIColor.white.withAlphaComponent(0.09)
        mileageField.layer.cornerRadius = 8
        mileageField.layer.masksToBounds = true
        mileageField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 1))
        mileageField.leftViewMode = .always
        mileageField.heightAnchor.constraint(equalToConstant: 44).isActive = true
        fields["odometerKm"] = mileageField
        section.addArrangedSubview(mileageField)

        section.addArrangedSubview(makeSectionTitle(localized("garage_notes")))
        notesView.textColor = .white
        notesView.tintColor = PTDashboardConfig.shared.appMainColor
        notesView.font = .systemFont(ofSize: 16)
        notesView.backgroundColor = UIColor.white.withAlphaComponent(0.09)
        notesView.layer.cornerRadius = 8
        notesView.layer.masksToBounds = true
        notesView.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        notesView.heightAnchor.constraint(equalToConstant: 110).isActive = true
        notesView.accessibilityLabel = localized("garage_notes")
        section.addArrangedSubview(notesView)
        contentStack.addArrangedSubview(section)
    }

    private func makeHintLabel() -> UILabel {
        let label = UILabel()
        label.text = localized("garage_tire_suspension_hint")
        label.textColor = .systemGray2
        label.font = .systemFont(ofSize: 13)
        label.numberOfLines = 0
        return label
    }

    private func makeSectionTitle(_ title: String) -> UILabel {
        let label = UILabel()
        label.text = title
        label.textColor = PTDashboardConfig.shared.appMainColor
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        return label
    }

    private func populateProfile() {
        guard let profile else { return }
        fields["frontTireBrand"]?.text = profile.frontTireBrand
        fields["frontTireModel"]?.text = profile.frontTireModel
        fields["frontTireSize"]?.text = profile.frontTireSize
        fields["rearTireBrand"]?.text = profile.rearTireBrand
        fields["rearTireModel"]?.text = profile.rearTireModel
        fields["rearTireSize"]?.text = profile.rearTireSize
        fields["coldFrontPressure"]?.text = formatted(profile.coldFrontPressure)
        fields["coldRearPressure"]?.text = formatted(profile.coldRearPressure)
        fields["hotFrontPressure"]?.text = formatted(profile.hotFrontPressure)
        fields["hotRearPressure"]?.text = formatted(profile.hotRearPressure)
        fields["loadScenario"]?.text = profile.loadScenario
        fields["frontPreload"]?.text = profile.frontPreload
        fields["frontRebound"]?.text = profile.frontRebound
        fields["frontCompression"]?.text = profile.frontCompression
        fields["rearPreload"]?.text = profile.rearPreload
        fields["rearRebound"]?.text = profile.rearRebound
        fields["rearCompression"]?.text = profile.rearCompression
        fields["odometerKm"]?.text = formatted(profile.odometerKm)
        notesView.text = profile.notes
        pressureUnitControl.selectedSegmentIndex = ["bar", "kPa", "psi"].firstIndex(of: profile.pressureUnit) ?? 0
    }

    @objc private func cancel() {
        dismiss(animated: true)
    }

    @objc private func save() {
        let pressureValues = [
            parseOptionalDouble("coldFrontPressure", range: 0.1...200),
            parseOptionalDouble("coldRearPressure", range: 0.1...200),
            parseOptionalDouble("hotFrontPressure", range: 0.1...200),
            parseOptionalDouble("hotRearPressure", range: 0.1...200)
        ]
        let mileage = parseOptionalDouble("odometerKm", range: 0...2_000_000)
        guard pressureValues.allSatisfy({ $0.isValid }), mileage.isValid else {
            showInvalidInput()
            return
        }

        let profile = PTGarageTireSuspensionProfile(
            frontTireBrand: text("frontTireBrand"),
            frontTireModel: text("frontTireModel"),
            frontTireSize: text("frontTireSize"),
            rearTireBrand: text("rearTireBrand"),
            rearTireModel: text("rearTireModel"),
            rearTireSize: text("rearTireSize"),
            coldFrontPressure: pressureValues[0].value,
            coldRearPressure: pressureValues[1].value,
            hotFrontPressure: pressureValues[2].value,
            hotRearPressure: pressureValues[3].value,
            pressureUnit: ["bar", "kPa", "psi"][max(0, pressureUnitControl.selectedSegmentIndex)],
            loadScenario: text("loadScenario"),
            frontPreload: text("frontPreload"),
            frontRebound: text("frontRebound"),
            frontCompression: text("frontCompression"),
            rearPreload: text("rearPreload"),
            rearRebound: text("rearRebound"),
            rearCompression: text("rearCompression"),
            odometerKm: mileage.value,
            notes: notesView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        onSave?(profile)
        dismiss(animated: true)
    }

    private func text(_ key: String) -> String {
        fields[key]?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func formatted(_ value: Double?) -> String {
        value.map { String(format: "%.2f", $0) } ?? ""
    }

    private func parseOptionalDouble(
        _ key: String,
        range: ClosedRange<Double>
    ) -> (value: Double?, isValid: Bool) {
        let rawValue = text(key)
        guard !rawValue.isEmpty else { return (nil, true) }
        let value = Double(rawValue.replacingOccurrences(of: ",", with: "."))
        guard let value, value.isFinite, range.contains(value) else {
            return (nil, false)
        }
        return (value, true)
    }

    private func showInvalidInput() {
        let alert = UIAlertController(
            title: localized("garage_invalid_input"),
            message: localized("garage_tire_suspension_hint"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: localized("button_confirm"), style: .default))
        present(alert, animated: true)
    }

    private func localized(_ key: String) -> String {
        PTDashboardConfig.languageFunc(text: key)
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
