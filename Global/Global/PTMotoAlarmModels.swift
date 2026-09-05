//
//  PTMotoAlarmModels.swift
//  CrazyDashboard
//
//  EN: Small Sendable value types shared by the alarm coordinator and the widget extension.
//  ES: Tipos de valor Sendable pequeños compartidos por el coordinador de alarmas y la extensión de widgets.
//  中文：由提醒协调器和 Widget 扩展共享的小型 Sendable 值类型。
//

import Foundation

#if canImport(AlarmKit)
import AlarmKit
#endif

public enum PTMotoAlarmKind: String, Codable, CaseIterable, Sendable {
    case departure
    case maintenance
    case parking
    case rideBreak
}

public enum PTMotoAlarmTiming: Codable, Equatable, Sendable {
    case fixed(Date)
    case countdown(startedAt: Date, duration: TimeInterval)

    public nonisolated var fireDate: Date {
        switch self {
        case .fixed(let date):
            return date
        case .countdown(let startedAt, let duration):
            return startedAt.addingTimeInterval(duration)
        }
    }

    public var duration: TimeInterval? {
        guard case .countdown(_, let duration) = self else { return nil }
        return duration
    }
}

public enum PTMotoAlarmDelivery: String, Codable, Sendable {
    case alarmKit
    case notificationFallback
}

public enum PTMotoAlarmState: String, Codable, Sendable {
    case scheduled
    case countdown
    case paused
    case alerting
}

public enum PTMotoAlarmCapability: String, Codable, Sendable {
    case alarmKit
    case notificationFallback
    case unavailable
}

public enum PTMotoAlarmError: Error, Equatable, Sendable {
    case invalidDate
    case invalidDuration
    case notAuthorized
    case notSupported
    case notFound
    case schedulingFailed(String)
}

// EN: This record is intentionally local because AlarmKit identifiers and authorization are device-specific.
// ES: Este registro es local a propósito porque los identificadores y permisos de AlarmKit son propios del dispositivo.
// 中文：该记录刻意只保存在本机，因为 AlarmKit 标识符和权限都属于具体设备。
public struct PTMotoAlarmRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let kind: PTMotoAlarmKind
    public let timing: PTMotoAlarmTiming
    public let title: String
    public let vehicleID: UUID?
    public let maintenanceRecordID: UUID?
    public var delivery: PTMotoAlarmDelivery
    public var state: PTMotoAlarmState
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        kind: PTMotoAlarmKind,
        timing: PTMotoAlarmTiming,
        title: String,
        vehicleID: UUID? = nil,
        maintenanceRecordID: UUID? = nil,
        delivery: PTMotoAlarmDelivery,
        state: PTMotoAlarmState = .scheduled,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.timing = timing
        self.title = title
        self.vehicleID = vehicleID
        self.maintenanceRecordID = maintenanceRecordID
        self.delivery = delivery
        self.state = state
        self.createdAt = createdAt
    }

    public nonisolated var fireDate: Date { timing.fireDate }

    public var isCountdown: Bool {
        timing.duration != nil
    }
}

#if canImport(AlarmKit)
@available(iOS 26.0, *)
public struct PTMotoAlarmMetadata: AlarmMetadata {
    public let alarmID: UUID
    public let kind: PTMotoAlarmKind
    public let title: String
    public let vehicleName: String

    public init(
        alarmID: UUID,
        kind: PTMotoAlarmKind,
        title: String,
        vehicleName: String
    ) {
        self.alarmID = alarmID
        self.kind = kind
        self.title = title
        self.vehicleName = vehicleName
    }
}
#endif
