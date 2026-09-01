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

    private let maintenanceRowsStack = UIStackView()
    private let diagnosticRowsStack = UIStackView()
    private let partsRowsStack = UIStackView()

    private let switchVehicleButton: UIButton
    private let addVehicleButton: UIButton
    private let deleteVehicleButton: UIButton
    private let editMileageButton: UIButton
    private let syncLiveDataButton: UIButton
    private let addMaintenanceButton: UIButton
    private let saveOBDButton: UIButton
    private let addPartButton: UIButton

    init(store: PTMotorcycleGarageStore? = nil) {
        self.store = store ?? PTMotorcycleGarageStore.shared
        self.switchVehicleButton = Self.makeActionButton(titleKey: "garage_switch_vehicle")
        self.addVehicleButton = Self.makeActionButton(titleKey: "garage_add_vehicle")
        self.deleteVehicleButton = Self.makeActionButton(titleKey: "garage_delete_vehicle", color: .systemRed)
        self.editMileageButton = Self.makeActionButton(titleKey: "garage_edit_mileage")
        self.syncLiveDataButton = Self.makeActionButton(titleKey: "garage_sync_live_data")
        self.addMaintenanceButton = Self.makeActionButton(titleKey: "garage_add_maintenance")
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
        refreshUI()
    }

    private func configureLabels() {
        [vehicleNameLabel, vehicleDetailsLabel, vehicleVINLabel, vehicleMileageLabel].forEach {
            $0.numberOfLines = 0
            $0.textColor = .white
        }
        vehicleNameLabel.font = .systemFont(ofSize: 22, weight: .bold)
        vehicleDetailsLabel.font = .systemFont(ofSize: 14, weight: .regular)
        vehicleDetailsLabel.textColor = .systemGray
        vehicleVINLabel.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        vehicleVINLabel.textColor = .systemGray2
        vehicleMileageLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        vehicleMileageLabel.textColor = PTDashboardConfig.shared.appMainColor
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
        editMileageButton.addTarget(self, action: #selector(showMileageForm), for: .touchUpInside)
        syncLiveDataButton.addTarget(self, action: #selector(syncLiveData), for: .touchUpInside)
        addMaintenanceButton.addTarget(self, action: #selector(showMaintenanceForm), for: .touchUpInside)
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
            makeButtonRow([switchVehicleButton, addVehicleButton, deleteVehicleButton]),
            makeButtonRow([editMileageButton, syncLiveDataButton])
        ])
        vehicleBody.axis = .vertical
        vehicleBody.spacing = 8

        let maintenanceBody = makeSectionBody(rows: maintenanceRowsStack, action: addMaintenanceButton)
        let diagnosticBody = makeSectionBody(rows: diagnosticRowsStack, action: saveOBDButton)
        let partsBody = makeSectionBody(rows: partsRowsStack, action: addPartButton)

        contentStack.addArrangedSubview(makeCard(title: localized("garage_current_vehicle"), body: vehicleBody))
        contentStack.addArrangedSubview(makeCard(title: localized("garage_maintenance"), body: maintenanceBody))
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
            refreshRows()
            return
        }

        vehicleNameLabel.text = vehicle.name
        let detailParts = [vehicle.brand, vehicle.model, vehicle.year.map(String.init)]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        vehicleDetailsLabel.text = detailParts.isEmpty
            ? localized("garage_no_vehicle_details")
            : detailParts.joined(separator: " · ")
        vehicleVINLabel.text = "\(localized("garage_vin")): \(vehicle.vin.isEmpty ? localized("garage_no_vin") : vehicle.vin)"
        vehicleMileageLabel.text = "\(localized("garage_mileage")): \(formattedMileage(vehicle.odometerKm))"
        refreshRows()
    }

    private func refreshRows() {
        removeRows(from: maintenanceRowsStack)
        removeRows(from: diagnosticRowsStack)
        removeRows(from: partsRowsStack)

        guard let vehicle = store.currentVehicle else { return }

        if vehicle.maintenanceRecords.isEmpty {
            maintenanceRowsStack.addArrangedSubview(makeEmptyRow(key: "garage_no_maintenance"))
        } else {
            vehicle.maintenanceRecords.forEach { maintenanceRowsStack.addArrangedSubview(makeMaintenanceRow($0)) }
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

    private func makeMaintenanceRow(_ record: PTGarageMaintenanceRecord) -> UIView {
        let detail = [
            "\(localized("garage_mileage")): \(formattedMileage(record.mileageKm))",
            formattedDate(record.completedAt),
            record.nextDueMileageKm.map { "\(localized("garage_next_due")): \(formattedMileage($0))" }
        ].compactMap { $0 }.joined(separator: " · ")
        let notes = record.notes.isEmpty ? nil : record.notes
        return makeRecordRow(
            title: record.title,
            detail: detail,
            notes: notes,
            deleteHandler: { [weak self] in
                self?.store.removeMaintenance(id: record.id)
            }
        )
    }

    private func makeDiagnosticRow(_ report: PTGarageDiagnosticReport) -> UIView {
        var details = [formattedDate(report.capturedAt)]
        if !report.protocolName.isEmpty { details.append(report.protocolName) }
        if !report.ecuVersion.isEmpty { details.append("ECU: \(report.ecuVersion)") }
        if !report.vin.isEmpty { details.append("VIN: \(report.vin)") }
        if !report.didResults.isEmpty {
            details.append("DID \(report.successfulDIDCount)/\(report.didResults.count)")
        }
        return makeRecordRow(
            title: localized("garage_obd_report"),
            detail: details.joined(separator: " · "),
            notes: report.adapterName.isEmpty ? nil : report.adapterName,
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
        alert.addTextField { $0.placeholder = self.localized("garage_vehicle_name") }
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
        if store.syncCurrentVehicleFromLiveData() {
            showMessage(localized("garage_sync_success"))
        } else {
            showMessage(localized("garage_no_live_data"))
        }
    }

    @objc private func showMaintenanceForm() {
        let alert = UIAlertController(
            title: localized("garage_add_maintenance"),
            message: nil,
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
        alert.addTextField { $0.placeholder = self.localized("garage_notes") }
        alert.addAction(UIAlertAction(title: localized("button_cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: localized("button_confirm"), style: .default) { [weak self, weak alert] _ in
            guard let self, let alert else { return }
            let values = alert.textFields?.map { $0.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" } ?? []
            let mileage = Self.optionalDouble(values[safe: 1])
            let nextDue = Self.optionalDouble(values[safe: 2])
            guard !values.isEmpty,
                  self.store.addMaintenance(
                    title: values[0],
                    mileageKm: mileage,
                    nextDueMileageKm: nextDue,
                    notes: values[safe: 3] ?? ""
                  ) != nil else {
                self.showMessage(localized("garage_invalid_input"))
                return
            }
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

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
