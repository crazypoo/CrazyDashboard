//
//  PTOBDSessionTrace.swift
//  PTSpeed
//
//  EN: Correlates transport, ELM, adapter, OTA, and operation identifiers.
//  ES: Correlaciona identificadores de transporte, ELM, adaptador, OTA y operación.
//  中文：关联传输、ELM、适配器、OTA 和操作级会话标识。
//

import Foundation
import OSLog

nonisolated public struct PTOBDSessionIdentifiers: Codable, Equatable, Sendable {
    public let appRunID: UUID
    public let obdTransportSessionID: UUID
    public let elmSessionID: UUID
    public let adapterSessionID: UUID
    public let otaSessionID: UUID
    public let operationID: UUID
    public let vehicleRideID: UUID?

    public init(
        appRunID: UUID = UUID(),
        obdTransportSessionID: UUID = UUID(),
        elmSessionID: UUID = UUID(),
        adapterSessionID: UUID = UUID(),
        otaSessionID: UUID = UUID(),
        operationID: UUID = UUID(),
        vehicleRideID: UUID? = nil
    ) {
        self.appRunID = appRunID
        self.obdTransportSessionID = obdTransportSessionID
        self.elmSessionID = elmSessionID
        self.adapterSessionID = adapterSessionID
        self.otaSessionID = otaSessionID
        self.operationID = operationID
        self.vehicleRideID = vehicleRideID
    }
}

nonisolated public struct PTOBDSessionTraceEvent: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let name: String
    public let identifiers: PTOBDSessionIdentifiers
    public let metadata: [String: String]

    public init(
        timestamp: Date = Date(),
        name: String,
        identifiers: PTOBDSessionIdentifiers,
        metadata: [String: String] = [:]
    ) {
        self.timestamp = timestamp
        self.name = name
        self.identifiers = identifiers
        self.metadata = metadata
    }
}

nonisolated public struct PTOBDSessionTraceSnapshot: Codable, Equatable, Sendable {
    public let identifiers: PTOBDSessionIdentifiers?
    public let events: [PTOBDSessionTraceEvent]

    public init(
        identifiers: PTOBDSessionIdentifiers?,
        events: [PTOBDSessionTraceEvent]
    ) {
        self.identifiers = identifiers
        self.events = events
    }
}

public actor PTOBDSessionTrace {
    public static let shared = PTOBDSessionTrace()

    private let maximumEventCount: Int
    private let logger = Logger(subsystem: "com.yd.PTSpeed", category: "OBD.Session")
    private var identifiers: PTOBDSessionIdentifiers?
    private var events: [PTOBDSessionTraceEvent] = []

    public init(maximumEventCount: Int = 256) {
        self.maximumEventCount = max(1, maximumEventCount)
    }

    public func begin(vehicleRideID: UUID? = nil) -> PTOBDSessionIdentifiers {
        let newIdentifiers = PTOBDSessionIdentifiers(vehicleRideID: vehicleRideID)
        identifiers = newIdentifiers
        events.removeAll(keepingCapacity: true)
        return newIdentifiers
    }

    public func record(
        name: String,
        metadata: [String: String] = [:]
    ) {
        guard let identifiers else { return }
        let event = PTOBDSessionTraceEvent(
            name: name,
            identifiers: identifiers,
            metadata: metadata
        )
        events.append(event)
        if events.count > maximumEventCount {
            events.removeFirst(events.count - maximumEventCount)
        }
        logger.debug("OBD session event: \(name, privacy: .public)")
    }

    public func attachOTAIdentifier(_ otaSessionID: UUID = UUID()) {
        guard let current = identifiers else { return }
        identifiers = PTOBDSessionIdentifiers(
            appRunID: current.appRunID,
            obdTransportSessionID: current.obdTransportSessionID,
            elmSessionID: current.elmSessionID,
            adapterSessionID: current.adapterSessionID,
            otaSessionID: otaSessionID,
            operationID: current.operationID,
            vehicleRideID: current.vehicleRideID
        )
    }

    public func snapshot() -> PTOBDSessionTraceSnapshot {
        PTOBDSessionTraceSnapshot(identifiers: identifiers, events: events)
    }

    public func reset() {
        identifiers = nil
        events.removeAll(keepingCapacity: false)
    }
}
