//
//  PTTelemetryRecorder.swift
//  PTSpeed
//
//  Passive capture only.
//  It observes the existing PTOBDLogger streams and never sends BLE/OBD/CAN commands.
//

import Foundation

public actor PTTelemetryRecorder {

    public static let shared = PTTelemetryRecorder()

    private enum LoggerChannel: Sendable {
        case dashboard
        case obd
    }

    private var activeSession: PTTelemetrySession?
    private var maximumEventsPerSession = 50_000
    private var maximumEventValueLength = 4_096

    private var observersInstalled = false
    private var motoObserverToken: UUID?
    private var obdObserverToken: UUID?

    private init() {}

    public var isRecording: Bool {
        activeSession != nil
    }

    public func installObserversIfNeeded() async {
        guard !observersInstalled else {
            return
        }

        observersInstalled = true

        let tokens: (UUID, UUID) = await MainActor.run {
            let moto = PTOBDLogger.moto.addObserver { entry in
                Task {
                    await PTTelemetryRecorder.shared.ingest(
                        entry,
                        channel: .dashboard
                    )
                }
            }

            let obd = PTOBDLogger.obd.addObserver { entry in
                Task {
                    await PTTelemetryRecorder.shared.ingest(
                        entry,
                        channel: .obd
                    )
                }
            }

            return (moto, obd)
        }

        motoObserverToken = tokens.0
        obdObserverToken = tokens.1
    }

    @discardableResult
    public func start(
        vehicle: PTTelemetryVehicleContext,
        configuration: PTTelemetryConfiguration
    ) async -> UUID {
        await installObserversIfNeeded()

        maximumEventsPerSession = configuration.maximumEventsPerSession
        maximumEventValueLength = configuration.maximumEventValueLength

        let session = PTTelemetrySession(
            vehicle: vehicle
        )

        activeSession = session
        return session.id
    }

    public func stop() -> PTTelemetrySession? {
        defer {
            activeSession = nil
        }

        return activeSession
    }

    public func cancel() {
        activeSession = nil
    }

    public func recordMarker(
        kind: PTTelemetryMarkerKind,
        value: String
    ) {
        append(
            PTTelemetryEvent(
                source: .marker,
                kind: .marker,
                value: "\(kind.rawValue)=\(value)"
            )
        )
    }

    private func ingest(
        _ entry: PTOBDLogEntry,
        channel: LoggerChannel
    ) {
        guard activeSession != nil else {
            return
        }

        switch channel {
        case .dashboard:
            guard let parsed = Self.parseDashboard(
                entry.message
            ) else {
                return
            }

            append(
                PTTelemetryEvent(
                    monotonicNanoseconds: entry.monotonicNanoseconds,
                    source: .dashboardBLE,
                    kind: parsed.kind,
                    value: parsed.value
                )
            )

        case .obd:
            guard let parsed = Self.parseOBD(
                entry.message
            ) else {
                return
            }

            append(
                PTTelemetryEvent(
                    monotonicNanoseconds: entry.monotonicNanoseconds,
                    source: parsed.source,
                    kind: parsed.kind,
                    value: parsed.value
                )
            )
        }
    }

    private func append(
        _ event: PTTelemetryEvent
    ) {
        guard var session = activeSession else {
            return
        }

        guard session.events.count < maximumEventsPerSession else {
            session.droppedEventCount += 1
            activeSession = session
            return
        }

        let boundedValue = String(
            event.value.prefix(
                maximumEventValueLength
            )
        )

        session.events.append(
            PTTelemetryEvent(
                monotonicNanoseconds: event.monotonicNanoseconds,
                source: event.source,
                kind: event.kind,
                value: boundedValue
            )
        )

        activeSession = session
    }
}

private extension PTTelemetryRecorder {

    struct ParsedLog: Sendable {
        let source: PTTelemetrySource
        let kind: PTTelemetryEventKind
        let value: String
    }

    static func parseDashboard(
        _ message: String
    ) -> ParsedLog? {
        if let value = value(
            after: "[原始包] 收到帧数据: ",
            in: message
        ), !value.isEmpty {
            return ParsedLog(
                source: .dashboardBLE,
                kind: .frameRX,
                value: compactHexIfPossible(
                    value
                )
            )
        }

        if let value = value(
            after: "[发送包] 正在发射指令: ",
            in: message
        ), !value.isEmpty {
            return ParsedLog(
                source: .dashboardBLE,
                kind: .frameTX,
                value: compactHexIfPossible(
                    value
                )
            )
        }

        return nil
    }

    static func parseOBD(
        _ message: String
    ) -> ParsedLog? {
        if let value = value(
            after: "[嗅探抓包] 截获报文: ",
            in: message
        ), !value.isEmpty {
            return ParsedLog(
                source: .can,
                kind: .frame,
                value: value
            )
        }

        if let value = value(
            after: "[TX Async] 响应超时: ",
            in: message
        ) {
            return ParsedLog(
                source: .obd,
                kind: .timeout,
                value: cleanCommand(
                    value
                )
            )
        }

        if let value = value(
            after: "[TX Async] ",
            in: message
        ), !value.isEmpty {
            return ParsedLog(
                source: .obd,
                kind: .command,
                value: cleanCommand(
                    value
                )
            )
        }

        if let value = value(
            after: "[TX Init",
            in: message
        ),
        let command = valueAfterClosingBracket(
            value
        ),
        !command.isEmpty {
            return ParsedLog(
                source: .obd,
                kind: .command,
                value: cleanCommand(
                    command
                )
            )
        }

        if message.contains("[RX "),
           message.contains(" Async] 抛出上层: "),
           let value = value(
               after: "] 抛出上层: ",
               in: message
           ) {
            return ParsedLog(
                source: .obd,
                kind: .response,
                value: value
            )
        }

        if message.contains("[RX "),
           message.contains(" Init] 消化: "),
           let value = value(
               after: "] 消化: ",
               in: message
           ) {
            return ParsedLog(
                source: .obd,
                kind: .response,
                value: value
            )
        }

        if message.contains("[物理连接断开]") ||
            message.contains("发送失败") {
            return ParsedLog(
                source: .obd,
                kind: .transportError,
                value: String(
                    message.prefix(512)
                )
            )
        }

        return nil
    }

    static func value(
        after marker: String,
        in message: String
    ) -> String? {
        guard let range = message.range(
            of: marker
        ) else {
            return nil
        }

        return String(
            message[range.upperBound...]
        )
        .trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        .replacingOccurrences(
            of: "\\r",
            with: ""
        )
    }

    static func valueAfterClosingBracket(
        _ value: String
    ) -> String? {
        guard let range = value.range(
            of: "] "
        ) else {
            return nil
        }

        return String(
            value[range.upperBound...]
        )
        .trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }

    static func cleanCommand(
        _ value: String
    ) -> String {
        value
            .replacingOccurrences(
                of: "\\r",
                with: ""
            )
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .uppercased()
    }

    static func compactHexIfPossible(
        _ value: String
    ) -> String {
        let clean = value
            .filter {
                !$0.isWhitespace
            }
            .uppercased()

        guard !clean.isEmpty,
              clean.count.isMultiple(of: 2),
              clean.allSatisfy(\.isHexDigit) else {
            return value
        }

        return clean
    }
}
