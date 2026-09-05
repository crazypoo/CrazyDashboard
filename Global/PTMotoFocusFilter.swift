//
//  PTMotoFocusFilter.swift
//  CrazyDashboard
//
//  EN: Riding Focus preferences shared by the app and the system Focus filter.
//  ES: Preferencias de Focus de conducción compartidas por la app y el filtro Focus del sistema.
//  中文：App 与系统专注模式筛选条件共用的骑行显示偏好。
//

import AppIntents
import Foundation

// EN: Store only the presentation preference; Focus never starts transport work.
// ES: Guarda solo la preferencia de presentación; Focus nunca inicia el transporte.
// 中文：这里只保存界面偏好，专注模式绝不会启动车辆传输。
public enum PTMotoFocusDisplayPreferences {
    nonisolated public static let didChangeNotification = Notification.Name("PTMotoFocusDisplayPreferencesDidChange")

    nonisolated private static let compactDisplayKey = "pt_moto_focus_compact_display"
    nonisolated(unsafe) private static let defaults: UserDefaults =
        UserDefaults(suiteName: PTWidgetDataKeys.appGroupID) ?? .standard

    nonisolated public static var isCompactDisplay: Bool {
        defaults.bool(forKey: compactDisplayKey)
    }

    nonisolated public static func setCompactDisplay(_ enabled: Bool) {
        defaults.set(enabled, forKey: compactDisplayKey)
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }
}

// EN: This filter keeps the ride cockpit compact while preserving critical live values.
// ES: Este filtro mantiene compacto el cockpit y conserva los valores críticos en vivo.
// 中文：该筛选条件压缩骑行座舱，同时保留关键实时数据。
@available(iOS 17.0, *)
public struct PTRidingFocusFilterIntent: SetFocusFilterIntent {
    public static let title = LocalizedStringResource("focus_riding_title", table: "Localizable")
    public static let description = IntentDescription(
        LocalizedStringResource("focus_riding_description", table: "Localizable")
    )

    @Parameter(
        title: LocalizedStringResource("focus_riding_compact_parameter", table: "Localizable"),
        default: false
    )
    public var compactDisplay: Bool

    public init() {
        compactDisplay = PTMotoFocusDisplayPreferences.isCompactDisplay
    }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: LocalizedStringResource("focus_riding_title", table: "Localizable"),
            subtitle: LocalizedStringResource("focus_riding_description", table: "Localizable")
        )
    }

    public var appContext: FocusFilterAppContext {
        FocusFilterAppContext(
            notificationFilterPredicate: NSPredicate(value: true),
            targetContentIdentifierPrefix: "com.yd.PTSpeed.riding"
        )
    }

    public func perform() async throws -> some IntentResult {
        PTMotoFocusDisplayPreferences.setCompactDisplay(compactDisplay)
        return .result()
    }
}
