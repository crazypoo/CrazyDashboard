//
//  PTMotoAlarmCenterViewController.swift
//  CrazyDashboard
//
//  EN: A small explicit alarm center for departure, maintenance, parking and ride breaks.
//  ES: Un centro pequeño y explícito para salida, mantenimiento, estacionamiento y descansos.
//  中文：用于出发、保养、停车和骑行休息提醒的简洁主动式提醒中心。
//

import UIKit
import PooTools
import SnapKit
import SwifterSwift

@MainActor
final class PTMotoAlarmCenterViewController: PTMotoBaseViewController {
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let store = PTMotoAlarmCoordinator.shared

    var highlightedAlarmID: UUID?

    init(highlightedAlarmID: UUID? = nil) {
        self.highlightedAlarmID = highlightedAlarmID
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        pt_Title = localized("alarm_center_title")
        view.backgroundColor = .black
        configureLayout()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAlarmChange),
            name: PTMotoAlarmCoordinator.didChangeNotification,
            object: nil
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        store.bootstrap()
        refreshContent()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        highlightedAlarmID = nil
    }

    @objc private func handleAlarmChange() {
        refreshContent()
    }

    func refreshContent() {
        guard isViewLoaded else { return }
        contentStack.arrangedSubviews.forEach {
            contentStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let capabilityText: String
        switch store.capability {
        case .alarmKit:
            capabilityText = localized("alarm_capability_alarmkit")
        case .notificationFallback:
            capabilityText = localized("alarm_capability_notification")
        case .unavailable:
            capabilityText = localized("alarm_capability_unavailable")
        }
        let permissionButton = makeButton(
            title: localized("alarm_request_permission"),
            color: PTDashboardConfig.shared.appMainColor
        ) { [weak self] in
            guard let self else { return }
            Task { @MainActor [weak self] in
                _ = await self?.store.requestAuthorization()
                self?.refreshContent()
            }
        }
        contentStack.addArrangedSubview(makeCard(
            title: localized("alarm_capability_title"),
            body: capabilityText,
            buttons: [permissionButton]
        ))

        let actionButtons = [
            makeButton(title: localized("alarm_add_departure"), color: PTDashboardConfig.shared.appMainColor) { [weak self] in
                self?.presentDeparturePicker()
            },
            makeButton(title: localized("alarm_add_parking"), color: .systemOrange) { [weak self] in
                self?.presentDurationOptions(kind: .parking)
            },
            makeButton(title: localized("alarm_add_ride_break"), color: .systemGreen) { [weak self] in
                self?.presentDurationOptions(kind: .rideBreak)
            }
        ]
        contentStack.addArrangedSubview(makeCard(
            title: localized("alarm_actions_title"),
            body: localized("alarm_actions_hint"),
            buttons: actionButtons
        ))

        let vehicle = PTMotorcycleGarageStore.shared.currentVehicle
        let maintenanceButtons = (vehicle?.maintenanceRecords ?? []).prefix(20).map { record in
            let existing = store.records.first { $0.maintenanceRecordID == record.id }
            return makeButton(
                title: existing == nil
                    ? localized("alarm_set_maintenance")
                    : localized("alarm_cancel_maintenance"),
                color: existing == nil ? .systemOrange : .systemRed
            ) { [weak self] in
                guard let self else { return }
                if let existing {
                    Task { @MainActor [weak self] in
                        await self?.store.cancel(id: existing.id)
                        self?.refreshContent()
                    }
                } else if let vehicle {
                    self.presentMaintenancePicker(record: record, vehicle: vehicle)
                }
            }
        }
        let maintenanceBody: String
        if let vehicle, !vehicle.maintenanceRecords.isEmpty {
            maintenanceBody = vehicle.maintenanceRecords.prefix(20).map { record in
                let date = record.dueDate.map { formattedDate($0) } ?? localized("alarm_no_due_date")
                return "\(record.title) · \(date)"
            }.joined(separator: "\n")
        } else {
            maintenanceBody = localized("alarm_no_maintenance_records")
        }
        contentStack.addArrangedSubview(makeCard(
            title: localized("alarm_maintenance_title"),
            body: maintenanceBody,
            buttons: maintenanceButtons
        ))

        if store.records.isEmpty {
            contentStack.addArrangedSubview(makeCard(
                title: localized("alarm_scheduled_title"),
                body: localized("alarm_no_scheduled")
            ))
        } else {
            for record in store.records {
                contentStack.addArrangedSubview(makeAlarmCard(record))
            }
        }
    }

    private func configureLayout() {
        contentStack.axis = .vertical
        contentStack.spacing = 12
        contentStack.alignment = .fill

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])
    }

    private func makeAlarmCard(_ record: PTMotoAlarmRecord) -> UIView {
        let vehicleName = record.vehicleID.flatMap { PTMotorcycleGarageStore.shared.vehicle(id: $0)?.name }
            ?? localized("garage_vehicle_default_name")
        let delivery = record.delivery == .alarmKit
            ? localized("alarm_delivery_alarmkit")
            : localized("alarm_delivery_notification")
        let state = localized("alarm_state_\(record.state.rawValue)")
        let body = [
            vehicleName,
            "\(localized("alarm_delivery_label")): \(delivery)",
            "\(localized("alarm_state_label")): \(state)",
            "\(localized("alarm_time_label")): \(formattedDate(record.fireDate))"
        ].joined(separator: "\n")

        var buttons: [UIButton] = []
        if record.delivery == .alarmKit, record.isCountdown {
            let canResume = record.state == .paused
            buttons.append(makeButton(
                title: localized(canResume ? "alarm_resume" : "alarm_pause"),
                color: PTDashboardConfig.shared.appMainColor
            ) { [weak self] in
                do {
                    if canResume {
                        try self?.store.resume(id: record.id)
                    } else {
                        try self?.store.pause(id: record.id)
                    }
                    self?.refreshContent()
                } catch {
                    self?.showError(error)
                }
            })
        }
        buttons.append(makeButton(
            title: localized("alarm_cancel"),
            color: .systemRed
        ) { [weak self] in
            Task { @MainActor [weak self] in
                await self?.store.cancel(id: record.id)
                self?.refreshContent()
            }
        })

        let card = makeCard(title: record.title, body: body, buttons: buttons)
        if highlightedAlarmID == record.id {
            card.layer.borderColor = UIColor.systemYellow.cgColor
            card.layer.borderWidth = 2
        }
        return card
    }

    private func presentDeparturePicker() {
        presentDatePicker(
            initialDate: Date().addingTimeInterval(60 * 60),
            titleFieldEnabled: true
        ) { [weak self] date, title in
            Task { @MainActor [weak self] in
                do {
                    _ = try await self?.store.scheduleDeparture(at: date, title: title)
                    self?.refreshContent()
                } catch {
                    self?.showError(error)
                }
            }
        }
    }

    private func presentMaintenancePicker(
        record: PTGarageMaintenanceRecord,
        vehicle: PTMotorcycleProfile
    ) {
        let initialDate = record.dueDate ?? Date().addingTimeInterval(24 * 60 * 60)
        presentDatePicker(initialDate: initialDate, titleFieldEnabled: false) { [weak self] date, _ in
            Task { @MainActor [weak self] in
                do {
                    _ = try await self?.store.scheduleMaintenance(
                        recordID: record.id,
                        vehicleID: vehicle.id,
                        at: date
                    )
                    self?.refreshContent()
                } catch {
                    self?.showError(error)
                }
            }
        }
    }

    private func presentDatePicker(
        initialDate: Date,
        titleFieldEnabled: Bool,
        onSelect: @escaping @MainActor (Date, String?) -> Void
    ) {
        let picker = PTMotoAlarmDatePickerViewController(
            initialDate: initialDate,
            titleFieldEnabled: titleFieldEnabled,
            onSelect: onSelect
        )
        let navigationController = UINavigationController(rootViewController: picker)
        navigationController.modalPresentationStyle = .pageSheet
        present(navigationController, animated: true)
    }

    private func presentDurationOptions(kind: PTMotoAlarmKind) {
        let title = kind == .parking
            ? localized("alarm_parking_title")
            : localized("alarm_ride_break_title")
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)
        let presets = kind == .parking ? [30, 60, 120] : [60, 90, 120]
        for minutes in presets {
            alert.addAction(UIAlertAction(
                title: PTDashboardConfig.language(key: "alarm_duration_minutes", minutes),
                style: .default
            ) { [weak self] _ in
                self?.startTimer(kind: kind, minutes: minutes)
            })
        }
        alert.addAction(UIAlertAction(title: localized("alarm_custom_minutes"), style: .default) { [weak self] _ in
            self?.presentCustomDuration(kind: kind)
        })
        alert.addAction(UIAlertAction(title: localized("button_cancel"), style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = view.bounds
        }
        present(alert, animated: true)
    }

    private func presentCustomDuration(kind: PTMotoAlarmKind) {
        let alert = UIAlertController(
            title: localized("alarm_custom_minutes"),
            message: localized("alarm_custom_minutes_hint"),
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.keyboardType = .numberPad
            field.placeholder = "90"
        }
        alert.addAction(UIAlertAction(title: localized("button_cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: localized("button_confirm"), style: .default) { [weak self, weak alert] _ in
            guard let minutes = Int(alert?.textFields?.first?.text ?? "") else {
                self?.showError(PTMotoAlarmError.invalidDuration)
                return
            }
            self?.startTimer(kind: kind, minutes: minutes)
        })
        present(alert, animated: true)
    }

    private func startTimer(kind: PTMotoAlarmKind, minutes: Int) {
        Task { @MainActor [weak self] in
            do {
                if kind == .parking {
                    _ = try await self?.store.startParkingTimer(duration: TimeInterval(minutes * 60))
                } else {
                    _ = try await self?.store.startRideBreakTimer(duration: TimeInterval(minutes * 60))
                }
                self?.refreshContent()
            } catch {
                self?.showError(error)
            }
        }
    }

    private func makeCard(title: String, body: String? = nil, buttons: [UIButton] = []) -> UIView {
        let card = UIView()
        card.backgroundColor = UIColor(white: 0.1, alpha: 1)
        card.layer.cornerRadius = 14
        card.layer.borderWidth = 1
        card.layer.borderColor = PTDashboardConfig.shared.appMainColor.withAlphaComponent(0.35).cgColor

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14)
        ])

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textColor = PTDashboardConfig.shared.appMainColor
        titleLabel.font = .monospacedSystemFont(ofSize: 16, weight: .bold)
        titleLabel.numberOfLines = 0
        stack.addArrangedSubview(titleLabel)

        if let body, !body.isEmpty {
            let bodyLabel = UILabel()
            bodyLabel.text = body
            bodyLabel.textColor = .systemGray2
            bodyLabel.font = .systemFont(ofSize: 14)
            bodyLabel.numberOfLines = 0
            stack.addArrangedSubview(bodyLabel)
        }
        buttons.forEach { stack.addArrangedSubview($0) }
        return card
    }

    private func makeButton(
        title: String,
        color: UIColor,
        action: @escaping @MainActor () -> Void
    ) -> UIButton {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.baseBackgroundColor = color
        configuration.baseForegroundColor = .white
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 9, leading: 12, bottom: 9, trailing: 12)
        button.configuration = configuration
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        button.titleLabel?.numberOfLines = 0
        button.addAction(UIAction { _ in
            Task { @MainActor in action() }
        }, for: .touchUpInside)
        return button
    }

    private func localized(_ key: String) -> String {
        PTDashboardConfig.languageFunc(text: key)
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    private func showError(_ error: Error) {
        let key: String
        switch error as? PTMotoAlarmError {
        case .invalidDate:
            key = "alarm_invalid_date"
        case .invalidDuration:
            key = "alarm_invalid_duration"
        case .notAuthorized:
            key = "alarm_not_authorized"
        case .notSupported:
            key = "alarm_not_supported"
        case .notFound:
            key = "alarm_not_found"
        default:
            key = "alarm_schedule_failed"
        }
        let alert = UIAlertController(
            title: localized("alarm_center_title"),
            message: localized(key),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: localized("button_confirm"), style: .default))
        present(alert, animated: true)
    }
}

@MainActor
private final class PTMotoAlarmDatePickerViewController: UIViewController {
    private let initialDate: Date
    private let titleFieldEnabled: Bool
    private let onSelect: @MainActor (Date, String?) -> Void
    private let datePicker = UIDatePicker()
    private let titleField = UITextField()

    init(
        initialDate: Date,
        titleFieldEnabled: Bool,
        onSelect: @escaping @MainActor (Date, String?) -> Void
    ) {
        self.initialDate = initialDate
        self.titleFieldEnabled = titleFieldEnabled
        self.onSelect = onSelect
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = localized("alarm_choose_time")
        view.backgroundColor = .black
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: localized("button_cancel"),
            style: .plain,
            target: self,
            action: #selector(cancel)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: localized("button_confirm"),
            style: .done,
            target: self,
            action: #selector(confirm)
        )

        datePicker.datePickerMode = .dateAndTime
        datePicker.preferredDatePickerStyle = .wheels
        datePicker.minimumDate = Date(timeIntervalSinceNow: 60)
        datePicker.date = max(initialDate, datePicker.minimumDate ?? Date())
        datePicker.translatesAutoresizingMaskIntoConstraints = false

        titleField.placeholder = localized("alarm_departure_title_optional")
        titleField.textColor = .white
        titleField.tintColor = PTDashboardConfig.shared.appMainColor
        titleField.borderStyle = .roundedRect
        titleField.isHidden = !titleFieldEnabled
        titleField.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [datePicker, titleField])
        stack.axis = .vertical
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24)
        ])
    }

    @objc private func cancel() {
        dismiss(animated: true)
    }

    @objc private func confirm() {
        let title = titleField.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        dismiss(animated: true) { [date = datePicker.date, title, onSelect] in
            onSelect(date, title)
        }
    }

    private func localized(_ key: String) -> String {
        PTDashboardConfig.languageFunc(text: key)
    }
}
