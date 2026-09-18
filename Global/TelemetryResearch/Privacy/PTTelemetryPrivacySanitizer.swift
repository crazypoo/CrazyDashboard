//
//  PTTelemetryPrivacySanitizer.swift
//  PTSpeed
//
//  Privacy policy: default deny.
//  Only the narrow upload payload is produced.
//

import Foundation

nonisolated public enum PTTelemetryPrivacyError: Error, LocalizedError, Sendable {
    case emptyAfterSanitization

    public var errorDescription: String? {
        switch self {
        case .emptyAfterSanitization:
            return "Telemetry Session 脱敏后没有可上传的协议事件。"
        }
    }
}

nonisolated public enum PTTelemetryPrivacySanitizer {

    private static let forbiddenOBDCommands = [
        "0902",       // VIN
        "AT+CRYPT",   // YMOBD authentication material
        "AT+SETCRYPT"
    ]

    private static let vinResponseMarkers = [
        "4902",
        "62F190"
    ]

    public static func makeUploadPayload(
        from session: PTTelemetrySession
    ) throws -> PTTelemetryUploadPayload {

        let safeVehicle = sanitizeVehicle(
            session.vehicle
        )

        let events = session.events.compactMap {
            event -> PTTelemetryUploadPayload.Event? in

            sanitizeEvent(
                event,
                sessionStartNanoseconds:
                    session.startedMonotonicNanoseconds
            )
        }

        guard !events.isEmpty else {
            throw PTTelemetryPrivacyError.emptyAfterSanitization
        }

        return PTTelemetryUploadPayload(
            sessionID: session.id,
            app: .init(
                version: bounded(
                    session.app.version,
                    limit: 64
                ),
                build: bounded(
                    session.app.build,
                    limit: 64
                )
            ),
            vehicle: safeVehicle,
            events: events
        )
    }
}

private extension PTTelemetryPrivacySanitizer {

    static func sanitizeVehicle(
        _ vehicle: PTTelemetryVehicleContext
    ) -> PTTelemetryUploadPayload.VehicleInfo {

        let family = safeMetadata(
            vehicle.family,
            limit: 128
        ) ?? "unknown"

        return .init(
            family: family,
            dashboardFirmware: safeMetadata(
                vehicle.dashboardFirmware,
                limit: 128
            ),
            ecuSoftware: safeMetadata(
                vehicle.ecuSoftware,
                limit: 128
            )
        )
    }

    static func sanitizeEvent(
        _ event: PTTelemetryEvent,
        sessionStartNanoseconds: UInt64
    ) -> PTTelemetryUploadPayload.Event? {

        let relativeNanoseconds: UInt64

        if event.monotonicNanoseconds >= sessionStartNanoseconds {
            relativeNanoseconds =
                event.monotonicNanoseconds
                - sessionStartNanoseconds
        } else {
            relativeNanoseconds = 0
        }

        let offset =
            Double(relativeNanoseconds)
            / 1_000_000_000

        switch event.source {

        case .dashboardBLE:
            guard let value = sanitizeDashboardFrame(
                event.value
            ) else {
                return nil
            }

            return .init(
                offset: offset,
                source: .dashboardBLE,
                kind: event.kind.rawValue,
                value: value
            )

        case .obd:
            guard let value = sanitizeOBD(
                event.value,
                kind: event.kind
            ) else {
                return nil
            }

            return .init(
                offset: offset,
                source: .obd,
                kind: event.kind.rawValue,
                value: value
            )

        case .can:
            guard let value = sanitizeCAN(
                event.value
            ) else {
                return nil
            }

            return .init(
                offset: offset,
                source: .can,
                kind: "frame",
                value: value
            )

        case .marker:
            guard let value = sanitizeMarker(
                event.value
            ) else {
                return nil
            }

            return .init(
                offset: offset,
                source: .marker,
                kind: "marker",
                value: value
            )
        }
    }

    static func sanitizeDashboardFrame(
        _ value: String
    ) -> String? {
        let compact = compactHex(
            value
        )

        guard !compact.isEmpty else {
            return nil
        }

        // Current XP400 protocol code extracts a connection serial from
        // frame ID 0x01, so that entire frame is excluded from research uploads.
        if let bytes = hexBytes(
            compact
        ),
        bytes.count >= 2,
        bytes[1] == 0x01 {
            return nil
        }

        return bounded(
            compact,
            limit: 4_096
        )
    }

    static func sanitizeOBD(
        _ value: String,
        kind: PTTelemetryEventKind
    ) -> String? {

        let trimmed = value
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !trimmed.isEmpty else {
            return nil
        }

        let upper = trimmed.uppercased()

        let commandLike = upper
            .replacingOccurrences(
                of: "\\R",
                with: ""
            )
            .filter {
                !$0.isWhitespace
            }

        if kind == .command ||
            kind == .timeout {
            if forbiddenOBDCommands.contains(
                where: {
                    commandLike.hasPrefix(
                        $0
                    )
                }
            ) {
                return nil
            }
        }

        let hex = upper.filter(
            \.isHexDigit
        )

        if vinResponseMarkers.contains(
            where: {
                hex.contains(
                    $0
                )
            }
        ) {
            return nil
        }

        if containsSensitiveText(
            trimmed
        ) {
            return nil
        }

        if !hex.isEmpty,
           hex.count.isMultiple(of: 2),
           upper.allSatisfy({
               $0.isHexDigit
               || $0.isWhitespace
               || $0 == "\r"
               || $0 == "\n"
               || $0 == ">"
           }) {
            return bounded(
                hex,
                limit: 4_096
            )
        }

        return bounded(
            trimmed,
            limit: 4_096
        )
    }

    static func sanitizeCAN(
        _ value: String
    ) -> String? {
        let trimmed = value
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !trimmed.isEmpty,
              !containsSensitiveText(
                  trimmed
              ) else {
            return nil
        }

        return bounded(
            trimmed,
            limit: 4_096
        )
    }

    static func sanitizeMarker(
        _ value: String
    ) -> String? {
        let trimmed = value
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !trimmed.isEmpty,
              !containsSensitiveText(
                  trimmed
              ) else {
            return nil
        }

        return bounded(
            trimmed,
            limit: 256
        )
    }

    static func safeMetadata(
        _ value: String?,
        limit: Int
    ) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !trimmed.isEmpty,
              !containsSensitiveText(
                  trimmed
              ),
              !looksLikeVIN(
                  trimmed
              ) else {
            return nil
        }

        return bounded(
            trimmed,
            limit: limit
        )
    }

    static func containsSensitiveText(
        _ value: String
    ) -> Bool {
        let lower = value.lowercased()

        if lower.contains("@") &&
            lower.contains(".") {
            return true
        }

        let macPattern =
            #"(?i)\b(?:[0-9a-f]{2}[:-]){5}[0-9a-f]{2}\b"#

        if value.range(
            of: macPattern,
            options: .regularExpression
        ) != nil {
            return true
        }

        return false
    }

    static func looksLikeVIN(
        _ value: String
    ) -> Bool {
        let normalized = value
            .uppercased()
            .filter {
                $0.isLetter ||
                $0.isNumber
            }

        guard normalized.count == 17 else {
            return false
        }

        let pattern =
            #"^[A-HJ-NPR-Z0-9]{17}$"#

        return normalized.range(
            of: pattern,
            options: .regularExpression
        ) != nil
    }

    static func compactHex(
        _ value: String
    ) -> String {
        let clean = value
            .filter {
                !$0.isWhitespace
                && $0 != ":"
                && $0 != "-"
            }
            .uppercased()

        guard !clean.isEmpty,
              clean.count.isMultiple(of: 2),
              clean.allSatisfy(
                  \.isHexDigit
              ) else {
            return value.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        }

        return clean
    }

    static func hexBytes(
        _ value: String
    ) -> [UInt8]? {
        let clean = value.filter(
            \.isHexDigit
        )

        guard clean.count.isMultiple(
            of: 2
        ) else {
            return nil
        }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(
            clean.count / 2
        )

        var index = clean.startIndex

        while index < clean.endIndex {
            let next = clean.index(
                index,
                offsetBy: 2
            )

            guard let byte = UInt8(
                clean[index..<next],
                radix: 16
            ) else {
                return nil
            }

            bytes.append(
                byte
            )

            index = next
        }

        return bytes
    }

    static func bounded(
        _ value: String,
        limit: Int
    ) -> String {
        String(
            value.prefix(
                max(
                    1,
                    limit
                )
            )
        )
    }
}
