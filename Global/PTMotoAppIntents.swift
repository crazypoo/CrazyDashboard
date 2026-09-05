//
//  PTMotoAppIntents.swift
//  CrazyDashboard
//
//  EN: Siri and Shortcuts actions for read-only motorcycle status and deliberate navigation flows.
//  ES: Acciones de Siri y Atajos para el estado de la moto y flujos de navegación deliberados.
//  中文：为摩托车状态查询和明确触发的导航流程提供 Siri 与快捷指令动作。
//

import AppIntents
import Foundation
import PooTools

// EN: Keep App Intent text independent from UIKit so background status actions remain lightweight.
// ES: Mantén el texto de App Intents independiente de UIKit para que las acciones en segundo plano sean ligeras.
// 中文：让 App Intent 文案独立于 UIKit，保证后台状态操作保持轻量。
private enum PTAppIntentResources {
    nonisolated static func localized(_ key: String) -> String {
        String(
            localized: String.LocalizationValue(key),
            table: "Localizable",
            bundle: .main,
            locale: PTLanguage.share.locale
        )
    }

    nonisolated static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(
            format: localized(key),
            locale: PTLanguage.share.locale,
            arguments: arguments
        )
    }

    nonisolated static func dialog(_ value: String) -> IntentDialog {
        IntentDialog(stringLiteral: value)
    }

    nonisolated static func appGroupStatus() -> PTWidgetSharedStatus? {
        PTWidgetSharedStatus(
            defaults: UserDefaults(suiteName: PTWidgetDataKeys.appGroupID)
        )
    }

    nonisolated static func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = PTLanguage.share.locale
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    nonisolated static func hasParking(_ status: PTWidgetSharedStatus) -> Bool {
        let hasCoordinate = abs(status.parkedLat) > 0.000001 || abs(status.parkedLon) > 0.000001
        let hasAddress = !status.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && status.address != PTWidgetSharedStatus.placeholder.address
        return hasCoordinate || hasAddress
    }

    nonisolated static func vehicleStatusMessage(_ status: PTWidgetSharedStatus) -> String {
        let connectionKey = status.isConnected ? "ride_connected" : "ride_disconnected"
        let connection = localized(connectionKey)
        var lines = [
            format(
                "app_intent_vehicle_status_summary",
                connection,
                status.fuelLevel,
                status.tripKm
            ),
            format(
                "app_intent_vehicle_status_last_sync",
                formattedDate(status.lastUpdateTime)
            )
        ]

        if hasParking(status) {
            lines.append(format("app_intent_vehicle_status_parking", status.address))
            if abs(status.parkedLat) > 0.000001 || abs(status.parkedLon) > 0.000001 {
                lines.append(
                    format(
                        "app_intent_vehicle_status_coordinates",
                        status.parkedLat,
                        status.parkedLon
                    )
                )
            }
        }
        return lines.joined(separator: "\n")
    }

    nonisolated static func parkedLocationMessage(_ status: PTWidgetSharedStatus) -> String {
        var lines = [format("app_intent_parked_location_summary", status.address)]
        if abs(status.parkedLat) > 0.000001 || abs(status.parkedLon) > 0.000001 {
            lines.append(
                format(
                    "app_intent_vehicle_status_coordinates",
                    status.parkedLat,
                    status.parkedLon
                )
            )
        }
        return lines.joined(separator: "\n")
    }

    nonisolated static func routeMessage(
        result: PTRouteExecutionResult,
        startedKey: String,
        unavailableKey: String
    ) -> String {
        switch result {
        case .completed, .started:
            return localized(startedKey)
        case .unavailable, .rejected:
            return localized(unavailableKey)
        }
    }
}

// EN: These read-only intents use the Widget snapshot and never wake the BLE or OBD transport.
// ES: Estos intents de solo lectura usan la instantánea del Widget y nunca despiertan BLE ni OBD.
// 中文：这些只读 Intent 使用 Widget 快照，不会唤醒 BLE 或 OBD 传输层。
struct PTGetVehicleStatusIntent: AppIntent {
    static let title: LocalizedStringResource = LocalizedStringResource("app_intent_vehicle_status_title", table: "Localizable")
    static let description = IntentDescription(LocalizedStringResource("app_intent_vehicle_status_description", table: "Localizable"))
    static let openAppWhenRun = false

    @available(iOS 26.0, *)
    static let supportedModes: IntentModes = [.background]

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard let status = PTAppIntentResources.appGroupStatus() else {
            let message = PTAppIntentResources.localized("app_intent_vehicle_status_unavailable")
            return .result(value: message, dialog: PTAppIntentResources.dialog(message))
        }

        let message = PTAppIntentResources.vehicleStatusMessage(status)
        return .result(value: message, dialog: PTAppIntentResources.dialog(message))
    }
}

struct PTGetParkedLocationIntent: AppIntent {
    static let title: LocalizedStringResource = LocalizedStringResource("app_intent_parked_location_title", table: "Localizable")
    static let description = IntentDescription(LocalizedStringResource("app_intent_parked_location_description", table: "Localizable"))
    static let openAppWhenRun = false

    @available(iOS 26.0, *)
    static let supportedModes: IntentModes = [.background]

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard let status = PTAppIntentResources.appGroupStatus(),
              PTAppIntentResources.hasParking(status) else {
            let message = PTAppIntentResources.localized("app_intent_parked_location_unavailable")
            return .result(value: message, dialog: PTAppIntentResources.dialog(message))
        }

        let message = PTAppIntentResources.parkedLocationMessage(status)
        return .result(value: message, dialog: PTAppIntentResources.dialog(message))
    }
}

// EN: Marking a ride event changes only the local ride black box and does not send a vehicle command.
// ES: Marcar un evento solo cambia la caja negra local y no envía comandos al vehículo.
// 中文：标记行程事件只修改本地黑匣子，不向车辆发送任何指令。
struct PTMarkRideEventIntent: AppIntent {
    static let title: LocalizedStringResource = LocalizedStringResource("app_intent_mark_ride_event_title", table: "Localizable")
    static let description = IntentDescription(LocalizedStringResource("app_intent_mark_ride_event_description", table: "Localizable"))
    static let openAppWhenRun = false

    @available(iOS 26.0, *)
    static let supportedModes: IntentModes = [.background]

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let didSave = await MainActor.run {
            PTTripManager.shared.markCurrentRideEvent()
        }
        let key = didSave ? "ride_mark_event_saved" : "ride_mark_event_unavailable"
        let message = PTAppIntentResources.localized(key)
        return .result(dialog: PTAppIntentResources.dialog(message))
    }
}

// EN: UI and navigation intents explicitly request the foreground so their scene is available.
// ES: Los intents de UI y navegación solicitan explícitamente el primer plano para disponer de su escena.
// 中文：UI 与导航 Intent 明确要求前台执行，以确保目标场景可用。
struct PTOpenHUDIntent: AppIntent {
    static let title: LocalizedStringResource = LocalizedStringResource("app_intent_open_hud_title", table: "Localizable")
    static let description = IntentDescription(LocalizedStringResource("app_intent_open_hud_description", table: "Localizable"))
    static let openAppWhenRun = true

    @available(iOS 26.0, *)
    static let supportedModes: IntentModes = [.foreground(.immediate)]

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = await MainActor.run {
            PTRoutingManager.shared.execute(action: .openHUD)
        }
        let message = PTAppIntentResources.routeMessage(
            result: result,
            startedKey: "app_intent_hud_opened",
            unavailableKey: "ride_not_available"
        )
        return .result(dialog: PTAppIntentResources.dialog(message))
    }
}

struct PTNavigateToDestinationIntent: AppIntent {
    static let title: LocalizedStringResource = LocalizedStringResource("app_intent_navigate_title", table: "Localizable")
    static let description = IntentDescription(LocalizedStringResource("app_intent_navigate_description", table: "Localizable"))
    static let openAppWhenRun = true

    @Parameter(title: LocalizedStringResource("app_intent_destination_parameter", table: "Localizable"))
    var destination: String

    @available(iOS 26.0, *)
    static let supportedModes: IntentModes = [.foreground(.immediate)]

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let cleanedDestination = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedDestination.isEmpty else {
            let message = PTAppIntentResources.localized("app_intent_destination_required")
            return .result(dialog: PTAppIntentResources.dialog(message))
        }

        let result = await MainActor.run {
            PTRoutingManager.shared.execute(
                action: .navigateTo(destination: cleanedDestination)
            )
        }
        let message: String
        switch result {
        case .completed, .started:
            message = PTAppIntentResources.format(
                "app_intent_navigation_started",
                cleanedDestination
            )
        case .unavailable, .rejected:
            message = PTAppIntentResources.localized("app_intent_navigation_unavailable")
        }
        return .result(dialog: PTAppIntentResources.dialog(message))
    }
}

struct PTFindFuelStationIntent: AppIntent {
    static let title: LocalizedStringResource = LocalizedStringResource("app_intent_find_fuel_title", table: "Localizable")
    static let description = IntentDescription(LocalizedStringResource("app_intent_find_fuel_description", table: "Localizable"))
    static let openAppWhenRun = true

    @available(iOS 26.0, *)
    static let supportedModes: IntentModes = [.foreground(.immediate)]

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = await MainActor.run {
            PTRoutingManager.shared.execute(action: .confirmGasStationRoute)
        }
        let message = PTAppIntentResources.routeMessage(
            result: result,
            startedKey: "app_intent_fuel_search_started",
            unavailableKey: "ride_not_available"
        )
        return .result(dialog: PTAppIntentResources.dialog(message))
    }
}

// EN: Alarm actions stay explicit and use the same coordinator as the alarm center.
// ES: Las acciones de alarma siguen siendo explícitas y usan el mismo coordinador que el centro de alarmas.
// 中文：闹钟操作必须由用户明确触发，并与提醒中心使用同一个协调器。
struct PTOpenMotoAlarmIntent: LiveActivityIntent {
    static let title = LocalizedStringResource("app_intent_alarm_open_title", table: "Localizable")
    static let openAppWhenRun = true

    @Parameter(title: LocalizedStringResource("app_intent_alarm_id_parameter", table: "Localizable"))
    var alarmID: String

    init(alarmID: UUID) {
        self.alarmID = alarmID.uuidString
    }

    init() {
        alarmID = ""
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let id = UUID(uuidString: alarmID)
        let result = await MainActor.run {
            PTRoutingManager.shared.execute(action: .openAlarmCenter(id: id))
        }
        let key = result.succeeded ? "alarm_opened" : "alarm_open_unavailable"
        let message = PTAppIntentResources.localized(key)
        return .result(dialog: PTAppIntentResources.dialog(message))
    }
}

enum PTMotoTimerIntentKind: String, AppEnum, Sendable {
    case parking
    case rideBreak

    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("app_intent_timer_type", table: "Localizable")
    )
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .parking: DisplayRepresentation(
            title: LocalizedStringResource("app_intent_timer_parking", table: "Localizable")
        ),
        .rideBreak: DisplayRepresentation(
            title: LocalizedStringResource("app_intent_timer_ride_break", table: "Localizable")
        )
    ]
}

struct PTStartRideTimerIntent: AppIntent {
    static let title = LocalizedStringResource("app_intent_timer_title", table: "Localizable")
    static let description = IntentDescription(
        LocalizedStringResource("app_intent_timer_description", table: "Localizable")
    )
    static let openAppWhenRun = false

    @Parameter(
        title: LocalizedStringResource("app_intent_timer_type_parameter", table: "Localizable"),
        default: PTMotoTimerIntentKind.rideBreak
    )
    var kind: PTMotoTimerIntentKind

    @Parameter(
        title: LocalizedStringResource("app_intent_timer_minutes_parameter", table: "Localizable"),
        default: 90
    )
    var minutes: Int

    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            let record: PTMotoAlarmRecord
            switch kind {
            case .parking:
                record = try await PTMotoAlarmCoordinator.shared.startParkingTimer(
                    duration: TimeInterval(minutes * 60)
                )
            case .rideBreak:
                record = try await PTMotoAlarmCoordinator.shared.startRideBreakTimer(
                    duration: TimeInterval(minutes * 60)
                )
            }
            let message = PTAppIntentResources.format(
                "alarm_timer_started",
                record.title,
                minutes
            )
            return .result(dialog: PTAppIntentResources.dialog(message))
        } catch {
            let message = PTAppIntentResources.localized("alarm_schedule_failed")
            return .result(dialog: PTAppIntentResources.dialog(message))
        }
    }
}

struct PTScheduleDepartureAlarmIntent: AppIntent {
    static let title = LocalizedStringResource("app_intent_departure_title", table: "Localizable")
    static let description = IntentDescription(
        LocalizedStringResource("app_intent_departure_description", table: "Localizable")
    )
    static let openAppWhenRun = false

    @Parameter(
        title: LocalizedStringResource("app_intent_departure_time_parameter", table: "Localizable")
    )
    var date: Date

    @Parameter(
        title: LocalizedStringResource("app_intent_reminder_title_parameter", table: "Localizable"),
        default: ""
    )
    var title: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            let record = try await PTMotoAlarmCoordinator.shared.scheduleDeparture(
                at: date,
                title: title.isEmpty ? nil : title
            )
            let message = PTAppIntentResources.format(
                "alarm_departure_scheduled",
                PTAppIntentResources.formattedDate(record.fireDate)
            )
            return .result(dialog: PTAppIntentResources.dialog(message))
        } catch {
            let message = PTAppIntentResources.localized("alarm_schedule_failed")
            return .result(dialog: PTAppIntentResources.dialog(message))
        }
    }
}

// EN: Keep the curated list short; all individual App Intents remain available in the Shortcuts editor.
// ES: Mantén corta la lista seleccionada; todos los App Intents siguen disponibles en el editor de Atajos.
// 中文：精选快捷指令列表保持精简；所有 App Intent 仍可在快捷指令编辑器中使用。
struct PTMotoAppShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PTGetVehicleStatusIntent(),
            phrases: [
                "Check my vehicle status in \(.applicationName)",
                "Check my motorcycle in \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource("app_intent_vehicle_status_title", table: "Localizable"),
            systemImageName: "motorcycle"
        )
        AppShortcut(
            intent: PTGetParkedLocationIntent(),
            phrases: [
                "Find my parked motorcycle in \(.applicationName)",
                "Where is my motorcycle in \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource("app_intent_parked_location_title", table: "Localizable"),
            systemImageName: "mappin.and.ellipse"
        )
        AppShortcut(
            intent: PTMarkRideEventIntent(),
            phrases: [
                "Mark this ride in \(.applicationName)",
                "Mark a ride event in \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource("app_intent_mark_ride_event_title", table: "Localizable"),
            systemImageName: "flag.fill"
        )
        AppShortcut(
            intent: PTOpenHUDIntent(),
            phrases: [
                "Open the riding HUD in \(.applicationName)",
                "Show my riding dashboard in \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource("app_intent_open_hud_title", table: "Localizable"),
            systemImageName: "rectangle.inset.filled"
        )
        AppShortcut(
            intent: PTNavigateToDestinationIntent(),
            phrases: [
                "Navigate with \(.applicationName)",
                "Start a motorcycle route in \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource("app_intent_navigate_title", table: "Localizable"),
            systemImageName: "arrow.triangle.turn.up.right.diamond.fill"
        )
        AppShortcut(
            intent: PTFindFuelStationIntent(),
            phrases: [
                "Find a gas station in \(.applicationName)",
                "Find fuel for my motorcycle in \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource("app_intent_find_fuel_title", table: "Localizable"),
            systemImageName: "fuelpump.fill"
        )
        AppShortcut(
            intent: PTStartRideTimerIntent(),
            phrases: [
                "Start a motorcycle timer in \(.applicationName)",
                "Set a ride break timer in \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource("app_intent_timer_short_title", table: "Localizable"),
            systemImageName: "timer"
        )
        AppShortcut(
            intent: PTScheduleDepartureAlarmIntent(),
            phrases: [
                "Remind me when to leave on my motorcycle in \(.applicationName)",
                "Schedule a motorcycle departure in \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource("app_intent_departure_short_title", table: "Localizable"),
            systemImageName: "flag.checkered"
        )
    }
}
