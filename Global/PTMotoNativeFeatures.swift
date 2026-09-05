//
//  PTMotoNativeFeatures.swift
//  CrazyDashboard
//
//  EN: Small adapters for Calendar and Spotlight; neither adapter touches vehicle transport.
//  ES: Adaptadores pequeños para Calendario y Spotlight; ninguno toca el transporte del vehículo.
//  中文：日历和 Spotlight 的轻量适配层，两个适配器都不会触碰车辆传输层。
//

import UIKit
import EventKit
import EventKitUI
@preconcurrency import CoreSpotlight
import UniformTypeIdentifiers
import PooTools

// EN: Spotlight identifiers contain only local record IDs and are safe to route back into the app.
// ES: Los identificadores de Spotlight solo contienen IDs locales y se pueden enrutar de forma segura a la app.
// 中文：Spotlight 标识符只包含本地记录 ID，可以安全地路由回 App。
public enum PTMotoSpotlightDestination: Equatable, Sendable {
    case vehicle(UUID)
    case roadbook(UUID)
    case ride(String)
}

public enum PTMotoSpotlightIdentifier {
    nonisolated public static let domain = "com.yd.PTSpeed.records"

    nonisolated public static func vehicle(_ id: UUID) -> String {
        "vehicle:\(id.uuidString)"
    }

    nonisolated public static func roadbook(_ id: UUID) -> String {
        "roadbook:\(id.uuidString)"
    }

    nonisolated public static func ride(_ id: String) -> String {
        "ride:\(id)"
    }

    // EN: Parsing is deliberately strict so malformed Spotlight data cannot select a vehicle.
    // ES: El análisis es deliberadamente estricto para que datos malformados no seleccionen un vehículo.
    // 中文：解析故意保持严格，避免错误的 Spotlight 数据选中车辆。
    nonisolated public static func destination(for identifier: String) -> PTMotoSpotlightDestination? {
        let components = identifier.split(separator: ":", maxSplits: 1).map(String.init)
        guard components.count == 2, !components[1].isEmpty else { return nil }

        switch components[0].lowercased() {
        case "vehicle":
            return UUID(uuidString: components[1]).map(PTMotoSpotlightDestination.vehicle)
        case "roadbook":
            return UUID(uuidString: components[1]).map(PTMotoSpotlightDestination.roadbook)
        case "ride":
            return PTMotoSpotlightDestination.ride(components[1])
        default:
            return nil
        }
    }
}

// EN: Calendar uses write-only access and lets EventKit's editor provide the final user confirmation.
// ES: Calendario usa acceso de solo escritura y deja que el editor de EventKit pida la confirmación final.
// 中文：日历只申请写入权限，并由 EventKit 编辑器完成最终确认。
@MainActor
public final class PTMotoCalendarManager: NSObject, EKEventEditViewDelegate {
    public static let shared = PTMotoCalendarManager()

    private let eventStore = EKEventStore()

    private override init() {
        super.init()
    }

    public func presentMaintenanceReminder(
        record: PTGarageMaintenanceRecord,
        vehicleName: String,
        from presenter: UIViewController
    ) {
        let startDate = record.dueDate ?? record.completedAt
        presentEvent(
            title: "\(vehicleName) · \(record.title)",
            startDate: startDate,
            duration: 60 * 60,
            notes: record.notes,
            from: presenter
        )
    }

    public func presentRoadbookReminder(
        roadbook: PTRoadbook,
        from presenter: UIViewController
    ) {
        let defaultStart = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        presentEvent(
            title: roadbook.name,
            startDate: defaultStart,
            duration: 2 * 60 * 60,
            notes: PTDashboardConfig.language(
                key: "calendar_roadbook_notes",
                roadbook.waypoints.count
            ),
            from: presenter
        )
    }

    private func presentEvent(
        title: String,
        startDate: Date,
        duration: TimeInterval,
        notes: String,
        from presenter: UIViewController
    ) {
        requestWriteAccess { [weak self, weak presenter] granted in
            guard let self, let presenter else { return }
            guard granted else {
                self.presentAccessAlert(from: presenter)
                return
            }

            guard let calendar = self.eventStore.defaultCalendarForNewEvents else {
                self.presentMessage(
                    PTDashboardConfig.languageFunc(text: "calendar_no_calendar"),
                    from: presenter
                )
                return
            }

            let event = EKEvent(eventStore: self.eventStore)
            event.title = title
            event.startDate = startDate
            event.endDate = startDate.addingTimeInterval(duration)
            event.notes = notes.isEmpty ? nil : notes
            event.calendar = calendar

            let editor = EKEventEditViewController()
            editor.eventStore = self.eventStore
            editor.event = event
            editor.editViewDelegate = self
            presenter.present(editor, animated: true)
        }
    }

    private func requestWriteAccess(completion: @escaping @MainActor (Bool) -> Void) {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .writeOnly:
            completion(true)
        case .notDetermined:
            eventStore.requestWriteOnlyAccessToEvents { granted, _ in
                Task { @MainActor in
                    completion(granted)
                }
            }
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }

    private func presentAccessAlert(from presenter: UIViewController) {
        let alert = UIAlertController(
            title: PTDashboardConfig.languageFunc(text: "calendar_access_title"),
            message: PTDashboardConfig.languageFunc(text: "calendar_access_message"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(
            title: PTDashboardConfig.languageFunc(text: "button_cancel"),
            style: .cancel
        ))
        alert.addAction(UIAlertAction(
            title: PTDashboardConfig.languageFunc(text: "calendar_open_settings"),
            style: .default
        ) { _ in
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        })
        presenter.present(alert, animated: true)
    }

    private func presentMessage(_ message: String, from presenter: UIViewController) {
        let alert = UIAlertController(
            title: PTDashboardConfig.languageFunc(text: "alert_title"),
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(
            title: PTDashboardConfig.languageFunc(text: "button_confirm"),
            style: .default
        ))
        presenter.present(alert, animated: true)
    }

    // EN: EventKit owns saving; this delegate only closes its confirmation editor.
    // ES: EventKit se encarga de guardar; este delegado solo cierra su editor de confirmación.
    // 中文：保存由 EventKit 完成，代理只负责关闭确认编辑器。
    public func eventEditViewController(
        _ controller: EKEventEditViewController,
        didCompleteWith action: EKEventEditViewAction
    ) {
        controller.dismiss(animated: true)
    }
}

// EN: Index only useful local records; private vehicle identifiers and exact parking coordinates stay out.
// ES: Solo indexa registros locales útiles; los identificadores privados y coordenadas exactas quedan fuera.
// 中文：只索引有用的本地记录，车辆私密标识和精确停车坐标不会进入 Spotlight。
@MainActor
public final class PTMotoSpotlightIndexer: NSObject {
    public static let shared = PTMotoSpotlightIndexer()

    private static let enabledKey = "pt_moto_spotlight_enabled"
    private let index = CSSearchableIndex.default()
    // EN: Coalesce bursts of route updates and invalidate callbacks from an older indexing pass.
    // ES: Agrupa los cambios rápidos de ruta e invalida las devoluciones de una indexación anterior.
    // 中文：合并连续的路线更新，并使旧索引任务的回调失效。
    private var reindexTask: Task<Void, Never>?
    private var reindexGeneration = 0

    private override init() {
        super.init()
        UserDefaults.standard.register(defaults: [Self.enabledKey: true])
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scheduleReindex),
            name: PTMotorcycleGarageStore.didChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scheduleReindex),
            name: MotorcycleTripReportGenerated,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scheduleReindex),
            name: MotorcycleTripHistoryLoaded,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scheduleReindex),
            name: PTRoadbookLibraryDidChange,
            object: nil
        )
    }

    public var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.enabledKey) }
        set {
            reindexGeneration &+= 1
            reindexTask?.cancel()
            reindexTask = nil
            UserDefaults.standard.set(newValue, forKey: Self.enabledKey)
            if newValue {
                reindexAll()
            } else {
                deleteAll()
            }
        }
    }

    public func bootstrap() {
        guard isEnabled else { return }
        reindexAll()
        Task { @MainActor [weak self] in
            _ = try? await PTCustomRouteManager.shared.loadRoadbooks()
            self?.scheduleReindex()
        }
    }

    // EN: Delay indexing briefly so navigation heartbeats never trigger a full index rebuild.
    // ES: Retrasa brevemente la indexación para que los latidos de navegación no reconstruyan todo el índice.
    // 中文：短暂延迟索引，确保导航心跳不会触发整库重建。
    @objc public func scheduleReindex() {
        guard isEnabled else { return }
        reindexGeneration &+= 1
        let generation = reindexGeneration
        reindexTask?.cancel()
        reindexTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled,
                  let self,
                  self.isEnabled,
                  generation == self.reindexGeneration else { return }
            self.reindexAll(generation: generation)
        }
    }

    public func reindexAll() {
        reindexGeneration &+= 1
        reindexTask?.cancel()
        reindexTask = nil
        reindexAll(generation: reindexGeneration)
    }

    private func reindexAll(generation: Int) {
        guard isEnabled, CSSearchableIndex.isIndexingAvailable() else { return }
        let items = makeItems()
        let searchableIndex = index
        searchableIndex.deleteSearchableItems(withDomainIdentifiers: [PTMotoSpotlightIdentifier.domain]) { [weak self] error in
            let errorDescription = error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self, self.isEnabled, generation == self.reindexGeneration else { return }
                if let errorDescription {
                    PTNSLogConsole("⚠️ [Spotlight] 清理旧索引失败: \(errorDescription)")
                    return
                }
                guard !items.isEmpty else { return }
                searchableIndex.indexSearchableItems(items) { [weak self] error in
                    let errorDescription = error?.localizedDescription
                    Task { @MainActor [weak self] in
                        guard let self, self.isEnabled, generation == self.reindexGeneration else { return }
                        if let errorDescription {
                            PTNSLogConsole("⚠️ [Spotlight] 写入索引失败: \(errorDescription)")
                        }
                    }
                }
            }
        }
    }

    public func deleteAll() {
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        index.deleteSearchableItems(withDomainIdentifiers: [PTMotoSpotlightIdentifier.domain]) { [weak self] error in
            let errorDescription = error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self, !self.isEnabled else { return }
                if let errorDescription {
                    PTNSLogConsole("⚠️ [Spotlight] 删除索引失败: \(errorDescription)")
                }
            }
        }
    }

    private func makeItems() -> [CSSearchableItem] {
        let vehicleItems = PTMotorcycleGarageStore.shared.vehicles.map { vehicle in
            let modelName = [vehicle.brand, vehicle.model].filter { !$0.isEmpty }.joined(separator: " ")
            let description = modelName.isEmpty
                ? PTDashboardConfig.languageFunc(text: "spotlight_vehicle_record")
                : modelName
            return makeItem(
                identifier: PTMotoSpotlightIdentifier.vehicle(vehicle.id),
                title: vehicle.name,
                description: description,
                keywords: [vehicle.name, vehicle.brand, vehicle.model].filter { !$0.isEmpty }
            )
        }

        let roadbookItems = PTCustomRouteManager.shared.roadbooks.map { roadbook in
            makeItem(
                identifier: PTMotoSpotlightIdentifier.roadbook(roadbook.id),
                title: roadbook.name,
                description: PTDashboardConfig.language(
                    key: "spotlight_roadbook_description",
                    roadbook.waypoints.count
                ),
                keywords: [roadbook.name, PTDashboardConfig.languageFunc(text: "roadbook_title")]
            )
        }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = PTLanguage.share.locale
        dateFormatter.dateStyle = .medium
        let rideItems = PTTripManager.shared.tripHistory.prefix(20).map { report in
            let story = PTRideStoryBuilder.make(from: report)
            let date = dateFormatter.string(from: story.startTime)
            return makeItem(
                identifier: PTMotoSpotlightIdentifier.ride(report.id),
                title: PTDashboardConfig.language(key: "spotlight_ride_title", date),
                description: PTDashboardConfig.language(
                    key: "spotlight_ride_description",
                    PTDashboardConfig.shared.appShowMileageValueString(story.distanceKm),
                    story.durationMinutes
                ),
                keywords: [
                    PTDashboardConfig.languageFunc(text: "ride_center"),
                    date
                ]
            )
        }

        return vehicleItems + roadbookItems + rideItems
    }

    private func makeItem(
        identifier: String,
        title: String,
        description: String,
        keywords: [String]
    ) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: UTType.item)
        attributes.title = title
        attributes.contentDescription = description
        attributes.keywords = keywords
        return CSSearchableItem(
            uniqueIdentifier: identifier,
            domainIdentifier: PTMotoSpotlightIdentifier.domain,
            attributeSet: attributes
        )
    }
}
