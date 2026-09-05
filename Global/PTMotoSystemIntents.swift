//
//  PTMotoSystemIntents.swift
//  CrazyDashboard
//
//  EN: System controls enqueue a typed, read-only destination for the foreground app.
//  ES: Los controles del sistema encolan un destino tipado y de solo lectura para la app en primer plano.
//  中文：系统控件为前台 App 排队一个类型安全的只读目标页面。
//

import AppIntents
import Foundation

// EN: AppEnum keeps system controls discoverable without exposing a custom URL scheme.
// ES: AppEnum mantiene los controles visibles sin exponer un esquema URL personalizado.
// 中文：使用 AppEnum 让系统控件可发现，同时不暴露自定义 URL Scheme。
@available(iOS 18.0, *)
public enum PTMotoSystemDestination: String, AppEnum, CaseIterable, Sendable {
    case hud
    case readiness
    case parking
    case alarms

    public static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("system_destination_type", table: "Localizable")
    )

    public static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .hud: DisplayRepresentation(
            title: LocalizedStringResource("system_destination_hud", table: "Localizable")
        ),
        .readiness: DisplayRepresentation(
            title: LocalizedStringResource("system_destination_readiness", table: "Localizable")
        ),
        .parking: DisplayRepresentation(
            title: LocalizedStringResource("system_destination_parking", table: "Localizable")
        ),
        .alarms: DisplayRepresentation(
            title: LocalizedStringResource("system_destination_alarms", table: "Localizable")
        )
    ]
}

// EN: The App Group entry is a one-shot hand-off and contains no vehicle command.
// ES: La entrada del App Group es una entrega de un solo uso y no contiene comandos del vehículo.
// 中文：App Group 中的记录只用于一次性页面交接，不包含任何车辆指令。
@available(iOS 18.0, *)
public enum PTMotoSystemRouteRequest {
    nonisolated private static let key = "pt_moto_system_route_request"
    nonisolated(unsafe) private static let defaults: UserDefaults =
        UserDefaults(suiteName: PTWidgetDataKeys.appGroupID) ?? .standard

    nonisolated public static func enqueue(_ destination: PTMotoSystemDestination) {
        defaults.set(destination.rawValue, forKey: key)
    }

    nonisolated public static func consume() -> PTMotoSystemDestination? {
        guard let rawValue = defaults.string(forKey: key),
              let destination = PTMotoSystemDestination(rawValue: rawValue) else {
            defaults.removeObject(forKey: key)
            return nil
        }
        defaults.removeObject(forKey: key)
        return destination
    }
}

// EN: OpenIntent lets the Widget control open the existing typed app route without a second navigation stack.
// ES: OpenIntent permite que el control del Widget abra la ruta tipada existente sin otra pila de navegación.
// 中文：OpenIntent 让 Widget 控件打开现有类型化路由，不建立第二套导航栈。
@available(iOS 18.0, *)
public struct PTMotoOpenDestinationIntent: OpenIntent {
    public static let title = LocalizedStringResource("system_destination_parameter", table: "Localizable")

    @Parameter(title: LocalizedStringResource("system_destination_parameter", table: "Localizable"))
    public var target: PTMotoSystemDestination

    public init() {
        target = .hud
    }

    public init(target: PTMotoSystemDestination) {
        self.target = target
    }

    public func perform() async throws -> some IntentResult {
        PTMotoSystemRouteRequest.enqueue(target)
        return .result()
    }
}
