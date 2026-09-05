//
//  PTMotoAlarmControlIntents.swift
//  CrazyDashboard
//
//  EN: Small system intents for AlarmKit countdown controls shared by the app and widget extension.
//  ES: Intents de sistema pequeños para los controles de cuenta atrás de AlarmKit compartidos por la app y el widget.
//  中文：由主 App 和 Widget 扩展共享的 AlarmKit 倒计时控制 Intent。
//

import AppIntents

#if canImport(AlarmKit)
import AlarmKit
#endif

#if canImport(AlarmKit)
@available(iOS 26.0, *)
public struct PTStopMotoAlarmIntent: LiveActivityIntent {
    public static let title = LocalizedStringResource("alarm_stop", table: "Localizable")
    public static let openAppWhenRun = false

    @Parameter(title: LocalizedStringResource("app_intent_alarm_id_parameter", table: "Localizable"))
    public var alarmID: String

    public init(alarmID: UUID) {
        self.alarmID = alarmID.uuidString
    }

    public init() {
        self.alarmID = ""
    }

    public func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: alarmID) else { return .result() }
        try AlarmManager.shared.stop(id: id)
        return .result()
    }
}

@available(iOS 26.0, *)
public struct PTPauseMotoAlarmIntent: LiveActivityIntent {
    public static let title = LocalizedStringResource("alarm_pause", table: "Localizable")
    public static let openAppWhenRun = false

    @Parameter(title: LocalizedStringResource("app_intent_alarm_id_parameter", table: "Localizable"))
    public var alarmID: String

    public init(alarmID: UUID) {
        self.alarmID = alarmID.uuidString
    }

    public init() {
        self.alarmID = ""
    }

    public func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: alarmID) else { return .result() }
        try AlarmManager.shared.pause(id: id)
        return .result()
    }
}

@available(iOS 26.0, *)
public struct PTResumeMotoAlarmIntent: LiveActivityIntent {
    public static let title = LocalizedStringResource("alarm_resume", table: "Localizable")
    public static let openAppWhenRun = false

    @Parameter(title: LocalizedStringResource("app_intent_alarm_id_parameter", table: "Localizable"))
    public var alarmID: String

    public init(alarmID: UUID) {
        self.alarmID = alarmID.uuidString
    }

    public init() {
        self.alarmID = ""
    }

    public func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: alarmID) else { return .result() }
        try AlarmManager.shared.resume(id: id)
        return .result()
    }
}
#endif
