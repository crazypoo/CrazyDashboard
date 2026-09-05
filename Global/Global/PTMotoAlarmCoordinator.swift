//
//  PTMotoAlarmCoordinator.swift
//  CrazyDashboard
//
//  EN: Coordinates explicit motorcycle alarms without touching BLE, OBD or ride transport state.
//  ES: Coordina alarmas explícitas de la motocicleta sin tocar el estado de transporte BLE, OBD ni de la ruta.
//  中文：统一管理用户主动创建的摩托提醒，不接触 BLE、OBD 或行程传输状态。
//

import Foundation
import UserNotifications
import PooTools

#if canImport(AlarmKit)
import AlarmKit
import SwiftUI
#endif

@MainActor
public final class PTMotoAlarmCoordinator: NSObject {
    public static let shared = PTMotoAlarmCoordinator()
    public static let didChangeNotification = Notification.Name("PTMotoAlarmCoordinatorDidChange")

    private static let storageKey = "PTMotoAlarmRecords.v1"
    private static let notificationPrefix = "pt.moto.alarm."
    private static let minimumFixedLeadTime: TimeInterval = 60
    private static let minimumCountdown: TimeInterval = 60
    private static let maximumParkingCountdown: TimeInterval = 24 * 60 * 60
    private static let minimumRideBreakCountdown: TimeInterval = 15 * 60
    private static let maximumRideBreakCountdown: TimeInterval = 4 * 60 * 60

    public private(set) var records: [PTMotoAlarmRecord] = []
    public private(set) var capability: PTMotoAlarmCapability = .unavailable

    private var didBootstrap = false
    private var alarmUpdatesTask: Task<Void, Never>?
    private var garageObserver: NSObjectProtocol?

    private override init() {
        super.init()
    }

    deinit {
        alarmUpdatesTask?.cancel()
        if let garageObserver {
            NotificationCenter.default.removeObserver(garageObserver)
        }
    }

    // EN: Bootstrapping only restores and reconciles local records; it never prompts or schedules.
    // ES: La inicialización solo restaura y reconcilia registros locales; nunca solicita permisos ni programa alarmas.
    // 中文：启动只恢复并校准本地记录，绝不申请权限或创建提醒。
    public func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true
        records = loadRecords()
        garageObserver = NotificationCenter.default.addObserver(
            forName: PTMotorcycleGarageStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.reconcileGarageBindings()
                await self.refresh()
            }
        }

#if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            alarmUpdatesTask = Task { @MainActor [weak self] in
                guard let self else { return }
                for await alarms in AlarmManager.shared.alarmUpdates {
                    guard !Task.isCancelled else { break }
                    self.applyAlarmKitStates(alarms)
                }
            }
        }
#endif

        Task { @MainActor [weak self] in
            await self?.refresh()
        }
    }

    // EN: Authorization is requested only from a deliberate user action in the alarm center or Siri.
    // ES: La autorización solo se solicita tras una acción deliberada en el centro de alarmas o Siri.
    // 中文：权限只在提醒中心或 Siri 的明确操作后申请。
    public func requestAuthorization() async -> PTMotoAlarmCapability {
        bootstrap()

#if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            let state = AlarmManager.shared.authorizationState
            if state == .authorized {
                capability = .alarmKit
                return capability
            }

            if state == .notDetermined,
               let requestedState = try? await AlarmManager.shared.requestAuthorization(),
               requestedState == .authorized {
                capability = .alarmKit
                return capability
            }
        }
#endif

        let notificationStatus = await PTNotificationCenter.authorizationStatus()
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral:
            capability = .notificationFallback
        case .notDetermined:
            let result = await PTNotificationCenter.requestAuthorizationAsync()
            capability = result.granted ? .notificationFallback : .unavailable
        case .denied:
            capability = .unavailable
        @unknown default:
            capability = .unavailable
        }
        return capability
    }

    public func scheduleDeparture(
        at date: Date,
        title: String? = nil,
        vehicleID: UUID? = nil
    ) async throws -> PTMotoAlarmRecord {
        let vehicleName = vehicleName(for: vehicleID)
        let fallbackTitle = [
            localized("alarm_departure_title"),
            vehicleName
        ].joined(separator: " · ")
        let displayTitle = normalizedTitle(
            title,
            fallback: fallbackTitle
        )
        return try await schedule(
            kind: .departure,
            timing: .fixed(date),
            title: displayTitle,
            vehicleID: vehicleID,
            maintenanceRecordID: nil
        )
    }

    public func scheduleMaintenance(
        recordID: UUID,
        vehicleID: UUID,
        at date: Date
    ) async throws -> PTMotoAlarmRecord {
        guard let vehicle = PTMotorcycleGarageStore.shared.vehicle(id: vehicleID),
              let record = vehicle.maintenanceRecords.first(where: { $0.id == recordID }) else {
            throw PTMotoAlarmError.notFound
        }
        let title = normalizedTitle(
            [
                localized("alarm_maintenance_title"),
                record.title
            ].joined(separator: " · "),
            fallback: localized("alarm_maintenance_title")
        )
        return try await schedule(
            kind: .maintenance,
            timing: .fixed(date),
            title: title,
            vehicleID: vehicleID,
            maintenanceRecordID: recordID
        )
    }

    public func startParkingTimer(
        duration: TimeInterval,
        vehicleID: UUID? = nil
    ) async throws -> PTMotoAlarmRecord {
        guard (Self.minimumCountdown...Self.maximumParkingCountdown).contains(duration), duration.isFinite else {
            throw PTMotoAlarmError.invalidDuration
        }
        return try await schedule(
            kind: .parking,
            timing: .countdown(startedAt: Date(), duration: duration),
            title: normalizedTitle(nil, fallback: localized("alarm_parking_title")),
            vehicleID: vehicleID,
            maintenanceRecordID: nil
        )
    }

    public func startRideBreakTimer(
        duration: TimeInterval,
        vehicleID: UUID? = nil
    ) async throws -> PTMotoAlarmRecord {
        guard (Self.minimumRideBreakCountdown...Self.maximumRideBreakCountdown).contains(duration), duration.isFinite else {
            throw PTMotoAlarmError.invalidDuration
        }
        return try await schedule(
            kind: .rideBreak,
            timing: .countdown(startedAt: Date(), duration: duration),
            title: normalizedTitle(nil, fallback: localized("alarm_ride_break_title")),
            vehicleID: vehicleID,
            maintenanceRecordID: nil
        )
    }

    public func pause(id: UUID) throws {
        guard let record = records.first(where: { $0.id == id }), record.delivery == .alarmKit, record.isCountdown else {
            throw PTMotoAlarmError.notSupported
        }
#if canImport(AlarmKit)
        guard #available(iOS 26.0, *) else { throw PTMotoAlarmError.notSupported }
        try AlarmManager.shared.pause(id: id)
        if let index = records.firstIndex(where: { $0.id == id }) {
            records[index].state = .paused
            persistAndNotify()
        }
#else
        throw PTMotoAlarmError.notSupported
#endif
    }

    public func resume(id: UUID) throws {
        guard let record = records.first(where: { $0.id == id }), record.delivery == .alarmKit, record.isCountdown else {
            throw PTMotoAlarmError.notSupported
        }
#if canImport(AlarmKit)
        guard #available(iOS 26.0, *) else { throw PTMotoAlarmError.notSupported }
        try AlarmManager.shared.resume(id: id)
        if let index = records.firstIndex(where: { $0.id == id }) {
            records[index].state = .countdown
            persistAndNotify()
        }
#else
        throw PTMotoAlarmError.notSupported
#endif
    }

    public func cancel(id: UUID) async {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        let record = records[index]
#if canImport(AlarmKit)
        if record.delivery == .alarmKit, #available(iOS 26.0, *) {
            if record.state == .alerting {
                try? AlarmManager.shared.stop(id: id)
            } else {
                try? AlarmManager.shared.cancel(id: id)
            }
        }
#endif
        if record.delivery == .notificationFallback {
            PTNotificationCenter.cancel(identifier: Self.notificationIdentifier(for: id))
        }
        records.remove(at: index)
        persistAndNotify()
    }

    public func refresh() async {
        bootstrap()
        await reconcileGarageBindings()
#if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            refreshAlarmKitRecords()
        }
#endif
        await refreshFallbackRecords()
    }

    // EN: Each scheduling operation commits local state only after the system accepts the request.
    // ES: Cada operación guarda el estado local solo después de que el sistema acepta la solicitud.
    // 中文：只有系统接受调度后，才提交本地提醒记录。
    private func schedule(
        kind: PTMotoAlarmKind,
        timing: PTMotoAlarmTiming,
        title: String,
        vehicleID: UUID?,
        maintenanceRecordID: UUID?
    ) async throws -> PTMotoAlarmRecord {
        bootstrap()
        try validate(timing: timing, title: title)

        let id = UUID()
        let pendingRecord = PTMotoAlarmRecord(
            id: id,
            kind: kind,
            timing: timing,
            title: title,
            vehicleID: vehicleID,
            maintenanceRecordID: maintenanceRecordID,
            delivery: .notificationFallback
        )

#if canImport(AlarmKit)
        if #available(iOS 26.0, *), await requestAlarmKitAuthorizationIfNeeded() {
            do {
                try await scheduleWithAlarmKit(pendingRecord)
                var committed = pendingRecord
                committed.delivery = .alarmKit
                commit(committed)
                capability = .alarmKit
                return committed
            } catch {
                PTNSLogConsole("⚠️ [系统提醒] AlarmKit 调度失败，回退普通通知：\(error.localizedDescription)")
            }
        }
#endif

        guard await ensureNotificationAuthorization() else {
            capability = .unavailable
            throw PTMotoAlarmError.notAuthorized
        }

        let result = await scheduleWithNotification(pendingRecord)
        if result != .scheduled {
            capability = .unavailable
            switch result {
            case .denied, .notDetermined:
                throw PTMotoAlarmError.notAuthorized
            case .failed(let reason):
                throw PTMotoAlarmError.schedulingFailed(reason)
            case .suppressed:
                throw PTMotoAlarmError.schedulingFailed("notification_suppressed")
            case .scheduled:
                break
            }
        }

        var committed = pendingRecord
        committed.delivery = .notificationFallback
        commit(committed)
        capability = .notificationFallback
        return committed
    }

    private func validate(timing: PTMotoAlarmTiming, title: String) throws {
        guard !title.isEmpty,
              title.count <= 80,
              title.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw PTMotoAlarmError.schedulingFailed("invalid_title")
        }

        switch timing {
        case .fixed(let date):
            guard date.timeIntervalSinceNow >= Self.minimumFixedLeadTime else {
                throw PTMotoAlarmError.invalidDate
            }
        case .countdown(let startedAt, let duration):
            guard startedAt.timeIntervalSinceNow <= 30,
                  duration.isFinite,
                  duration >= Self.minimumCountdown else {
                throw PTMotoAlarmError.invalidDuration
            }
        }
    }

    private func commit(_ record: PTMotoAlarmRecord) {
        records.removeAll { $0.id == record.id }
        records.append(record)
        records.sort { $0.fireDate < $1.fireDate }
        persistAndNotify()
    }

    private func normalizedTitle(_ title: String?, fallback: String) -> String {
        let value = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return String((value.isEmpty ? fallback : value).prefix(80))
    }

    private func vehicleName(for vehicleID: UUID?) -> String {
        let store = PTMotorcycleGarageStore.shared
        if let id = vehicleID ?? store.selectedVehicleID,
           let vehicle = store.vehicle(id: id) {
            return vehicle.name
        }
        return localized("garage_vehicle_default_name")
    }

    private func localized(_ key: String) -> String {
        PTDashboardConfig.languageFunc(text: key)
    }

    private func ensureNotificationAuthorization() async -> Bool {
        let status = await PTNotificationCenter.authorizationStatus()
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            let result = await PTNotificationCenter.requestAuthorizationAsync()
            return result.granted
        @unknown default:
            return false
        }
    }

#if canImport(AlarmKit)
    @available(iOS 26.0, *)
    private func requestAlarmKitAuthorizationIfNeeded() async -> Bool {
        switch AlarmManager.shared.authorizationState {
        case .authorized:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await AlarmManager.shared.requestAuthorization()) == .authorized
        @unknown default:
            return false
        }
    }

    @available(iOS 26.0, *)
    private func scheduleWithAlarmKit(_ record: PTMotoAlarmRecord) async throws {
        let stopButton = AlarmButton(
            text: LocalizedStringResource("alarm_stop", table: "Localizable"),
            textColor: .white,
            systemImageName: "stop.circle"
        )
        let openButton = AlarmButton(
            text: LocalizedStringResource("alarm_open", table: "Localizable"),
            textColor: .white,
            systemImageName: "arrow.up.right"
        )
        let alertTitle = localizedAlarmResource(for: record.kind)
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = AlarmPresentation.Alert(
                title: alertTitle,
                secondaryButton: openButton,
                secondaryButtonBehavior: .custom
            )
        } else {
            alert = AlarmPresentation.Alert(
                title: alertTitle,
                stopButton: stopButton,
                secondaryButton: openButton,
                secondaryButtonBehavior: .custom
            )
        }

        let presentation: AlarmPresentation
        if record.isCountdown {
            let pauseButton = AlarmButton(
                text: LocalizedStringResource("alarm_pause", table: "Localizable"),
                textColor: .white,
                systemImageName: "pause.circle"
            )
            let resumeButton = AlarmButton(
                text: LocalizedStringResource("alarm_resume", table: "Localizable"),
                textColor: .white,
                systemImageName: "play.circle"
            )
            presentation = AlarmPresentation(
                alert: alert,
                countdown: AlarmPresentation.Countdown(
                    title: localizedAlarmResource(for: record.kind),
                    pauseButton: pauseButton
                ),
                paused: AlarmPresentation.Paused(
                    title: LocalizedStringResource("alarm_paused", table: "Localizable"),
                    resumeButton: resumeButton
                )
            )
        } else {
            presentation = AlarmPresentation(alert: alert)
        }

        let metadata = PTMotoAlarmMetadata(
            alarmID: record.id,
            kind: record.kind,
            title: record.title,
            vehicleName: vehicleName(for: record.vehicleID)
        )
        let attributes = AlarmAttributes<PTMotoAlarmMetadata>(
            presentation: presentation,
            metadata: metadata,
            tintColor: Color(red: 0.2, green: 0.6, blue: 1.0)
        )
        let stopIntent = PTStopMotoAlarmIntent(alarmID: record.id)
        let openIntent = PTOpenMotoAlarmIntent(alarmID: record.id)
        let configuration: AlarmManager.AlarmConfiguration<PTMotoAlarmMetadata>
        switch record.timing {
        case .fixed(let date):
            configuration = .alarm(
                schedule: .fixed(date),
                attributes: attributes,
                stopIntent: stopIntent,
                secondaryIntent: openIntent
            )
        case .countdown(_, let duration):
            configuration = .timer(
                duration: duration,
                attributes: attributes,
                stopIntent: stopIntent,
                secondaryIntent: openIntent
            )
        }
        _ = try await AlarmManager.shared.schedule(id: record.id, configuration: configuration)
    }

    @available(iOS 26.0, *)
    private func localizedAlarmResource(for kind: PTMotoAlarmKind) -> LocalizedStringResource {
        switch kind {
        case .departure:
            return LocalizedStringResource("alarm_departure_title", table: "Localizable")
        case .maintenance:
            return LocalizedStringResource("alarm_maintenance_title", table: "Localizable")
        case .parking:
            return LocalizedStringResource("alarm_parking_title", table: "Localizable")
        case .rideBreak:
            return LocalizedStringResource("alarm_ride_break_title", table: "Localizable")
        }
    }

    @available(iOS 26.0, *)
    private func refreshAlarmKitRecords() {
        guard let alarms = try? AlarmManager.shared.alarms else { return }
        applyAlarmKitStates(alarms)
    }

    @available(iOS 26.0, *)
    private func applyAlarmKitStates(_ alarms: [Alarm]) {
        let byID = Dictionary(uniqueKeysWithValues: alarms.map { ($0.id, $0) })
        var changed = false
        var removedIDs = Set<UUID>()
        for record in records where record.delivery == .alarmKit {
            guard let alarm = byID[record.id] else {
                removedIDs.insert(record.id)
                continue
            }
            let newState: PTMotoAlarmState
            switch alarm.state {
            case .scheduled:
                newState = .scheduled
            case .countdown:
                newState = .countdown
            case .paused:
                newState = .paused
            case .alerting:
                newState = .alerting
            @unknown default:
                newState = .scheduled
            }
            if let index = records.firstIndex(where: { $0.id == record.id }),
               records[index].state != newState {
                records[index].state = newState
                changed = true
            }
        }
        if !removedIDs.isEmpty {
            records.removeAll { removedIDs.contains($0.id) }
            changed = true
        }
        if changed {
            persistAndNotify()
        }
    }
#endif

    private func scheduleWithNotification(_ record: PTMotoAlarmRecord) async -> PTNotificationDeliveryResult {
        let trigger: UNNotificationTrigger
        switch record.timing {
        case .fixed(let date):
            let components = Calendar.current.dateComponents(
                [.calendar, .year, .month, .day, .hour, .minute, .second],
                from: date
            )
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        case .countdown(_, let duration):
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(duration, 1), repeats: false)
        }

        let request = PTNotificationRequest(
            kind: .alarm,
            title: localizedTitle(for: record.kind),
            body: record.title,
            identifier: Self.notificationIdentifier(for: record.id),
            categoryIdentifier: PTNotificationCenter.alarmCategoryIdentifier,
            userInfo: [
                "pt_notification_kind": PTAppNotificationKind.alarm.rawValue,
                "pt_alarm_id": record.id.uuidString
            ],
            trigger: trigger
        )
        return await PTNotificationCenter.scheduleAsync(request)
    }

    private func localizedTitle(for kind: PTMotoAlarmKind) -> String {
        switch kind {
        case .departure:
            return localized("alarm_departure_title")
        case .maintenance:
            return localized("alarm_maintenance_title")
        case .parking:
            return localized("alarm_parking_title")
        case .rideBreak:
            return localized("alarm_ride_break_title")
        }
    }

    private func reconcileGarageBindings() async {
        let vehicles = PTMotorcycleGarageStore.shared.vehicles
        let vehicleIDs = Set(vehicles.map(\.id))
        let maintenanceIDs = Set(vehicles.flatMap { $0.maintenanceRecords.map(\.id) })
        let orphanIDs = records.compactMap { record -> UUID? in
            if let vehicleID = record.vehicleID, !vehicleIDs.contains(vehicleID) {
                return record.id
            }
            if let maintenanceRecordID = record.maintenanceRecordID, !maintenanceIDs.contains(maintenanceRecordID) {
                return record.id
            }
            return nil
        }
        for id in orphanIDs {
            await cancel(id: id)
        }
    }

    private func refreshFallbackRecords() async {
        let pendingIDs = await PTNotificationCenter.pendingIdentifiers()
        let staleIDs = records.filter {
            $0.delivery == .notificationFallback && !pendingIDs.contains(Self.notificationIdentifier(for: $0.id))
        }.map(\.id)
        guard !staleIDs.isEmpty else { return }
        records.removeAll { staleIDs.contains($0.id) }
        persistAndNotify()
    }

    private func loadRecords() -> [PTMotoAlarmRecord] {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let records = try? JSONDecoder().decode([PTMotoAlarmRecord].self, from: data) else {
            return []
        }
        return records
            .filter { !$0.title.isEmpty && $0.title.count <= 80 }
            .sorted { $0.fireDate < $1.fireDate }
    }

    private func persistAndNotify() {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    private static func notificationIdentifier(for id: UUID) -> String {
        notificationPrefix + id.uuidString
    }
}
