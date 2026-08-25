//
//  PTUDSDiagnosticService.swift
//  PTSpeed
//
//  Read-only UDS/ECU diagnostics built on top of the stable OBD transport.
//

import Foundation

public enum PTOBDDiagnosticError: Error, Equatable, Sendable {
    case disconnected
    case invalidAddress
    case invalidDID
    case invalidMemoryAddress
    case invalidReadSize
    case negativeResponse(service: String, code: String)
    case noData
    case cancelled
}

extension PTOBDDiagnosticError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .disconnected:
            return "OBD is not connected."
        case .invalidAddress:
            return "The ECU address is invalid."
        case .invalidDID:
            return "The DID must be four hexadecimal characters."
        case .invalidMemoryAddress:
            return "The memory address must be eight hexadecimal characters."
        case .invalidReadSize:
            return "The read size must be between 1 and 256 bytes."
        case let .negativeResponse(service, code):
            return "ECU rejected service \(service) with code \(code)."
        case .noData:
            return "The ECU returned no data."
        case .cancelled:
            return "The diagnostic operation was cancelled."
        }
    }
}

public enum PTOBDReadStatus: String, Codable, Sendable {
    case success
    case negativeResponse
    case noData
    case invalidResponse
}

public struct PTOBDIDReadResult: Codable, Sendable {
    public let address: PTOBDDiagnosticAddress
    public let did: String
    public let rawResponse: String
    public let payloadHex: String?
    public let decodedText: String?
    public let status: PTOBDReadStatus
    public let negativeResponseCode: String?

    public init(address: PTOBDDiagnosticAddress,
                did: String,
                rawResponse: String,
                payloadHex: String?,
                decodedText: String?,
                status: PTOBDReadStatus,
                negativeResponseCode: String? = nil) {
        self.address = address
        self.did = did
        self.rawResponse = rawResponse
        self.payloadHex = payloadHex
        self.decodedText = decodedText
        self.status = status
        self.negativeResponseCode = negativeResponseCode
    }
}

public struct PTOBDECUNode: Codable, Hashable, Sendable {
    public let address: PTOBDDiagnosticAddress
    public let rawResponse: String

    public init(address: PTOBDDiagnosticAddress, rawResponse: String) {
        self.address = address
        self.rawResponse = rawResponse
    }
}

public struct PTOBDRawReadResult: Codable, Sendable {
    public let address: PTOBDDiagnosticAddress
    public let command: String
    public let rawResponse: String
    public let payloadHex: String?
    public let status: PTOBDReadStatus
    public let negativeResponseCode: String?

    public init(address: PTOBDDiagnosticAddress,
                command: String,
                rawResponse: String,
                payloadHex: String?,
                status: PTOBDReadStatus,
                negativeResponseCode: String? = nil) {
        self.address = address
        self.command = command
        self.rawResponse = rawResponse
        self.payloadHex = payloadHex
        self.status = status
        self.negativeResponseCode = negativeResponseCode
    }
}

public struct PTOBDNodeDumpReport: Codable, Sendable {
    public let address: PTOBDDiagnosticAddress
    public let results: [PTOBDIDReadResult]
    public let failureReason: String?

    public init(address: PTOBDDiagnosticAddress,
                results: [PTOBDIDReadResult] = [],
                failureReason: String? = nil) {
        self.address = address
        self.results = results
        self.failureReason = failureReason
    }
}

public struct PTOBDFullVehicleDumpReport: Codable, Sendable {
    public let startedAt: Date
    public let endedAt: Date
    public let nodes: [PTOBDNodeDumpReport]
    public let cancelled: Bool

    public init(startedAt: Date,
                endedAt: Date,
                nodes: [PTOBDNodeDumpReport],
                cancelled: Bool) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.nodes = nodes
        self.cancelled = cancelled
    }

    public var successfulReadCount: Int {
        nodes.reduce(0) { partialResult, node in
            partialResult + node.results.filter { $0.status == .success }.count
        }
    }
}

public final class PTAdvancedOBDCoordinator {
    public static let shared = PTAdvancedOBDCoordinator()

    private init() {}

    /// Executes one read-only operation while the existing telemetry polling
    /// task is suspended by the stable manager implementation.
    public func executeReadOnly<T>(
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        guard PTMotoTelemetryManager.shared.isConnected else {
            throw PTOBDDiagnosticError.disconnected
        }

        return try await withCheckedThrowingContinuation { continuation in
            Task {
                await PTMotoTelemetryManager.shared.performExclusiveTask {
                    do {
                        continuation.resume(returning: try await operation())
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
}

public final class PTUDSReadService {
    public static let shared = PTUDSReadService()

    private init() {}

    /// 纯解析入口，供报告生成和单元测试复用，不会发送任何车辆指令。
    /// Entrada de análisis puro para informes y pruebas; no envía comandos al vehículo.
    public static func parseDIDResponse(
        address: PTOBDDiagnosticAddress,
        did: String,
        response: String
    ) throws -> PTOBDIDReadResult {
        let normalizedDID = try normalizeDID(did)
        return makeDIDResult(address: address, did: normalizedDID, response: response)
    }

    public func readDID(
        address: PTOBDDiagnosticAddress,
        did: String
    ) async throws -> PTOBDIDReadResult {
        let did = try Self.normalizeDID(did)

        return try await PTAdvancedOBDCoordinator.shared.executeReadOnly {
            let response = await PTMotoTelemetryManager.shared.fetchProprietaryData(
                header: address.tx,
                receiveAddress: address.rx,
                udsCommand: "22\(did)"
            )

            return Self.makeDIDResult(
                address: address,
                did: did,
                response: response
            )
        }
    }

    public func readDIDs(
        address: PTOBDDiagnosticAddress,
        dids: [String],
        progress: (@MainActor @Sendable (Int, Int, PTOBDIDReadResult) -> Void)? = nil
    ) async throws -> [PTOBDIDReadResult] {
        let normalizedDIDs = try dids.map(Self.normalizeDID)

        guard !normalizedDIDs.isEmpty else {
            return []
        }

        return try await PTAdvancedOBDCoordinator.shared.executeReadOnly {
            var results: [PTOBDIDReadResult] = []
            results.reserveCapacity(normalizedDIDs.count)

            for (index, did) in normalizedDIDs.enumerated() {
                try Task.checkCancellation()

                let response = await PTMotoTelemetryManager.shared.fetchProprietaryData(
                    header: address.tx,
                    receiveAddress: address.rx,
                    udsCommand: "22\(did)"
                )

                let result = Self.makeDIDResult(
                    address: address,
                    did: did,
                    response: response
                )
                results.append(result)
                await progress?(index + 1, normalizedDIDs.count, result)
            }

            return results
        }
    }

    public func readVIN(
        address: PTOBDDiagnosticAddress
    ) async throws -> String? {
        let result = try await readDID(address: address, did: "F190")

        guard result.status == .success else {
            return nil
        }

        return result.decodedText ?? result.payloadHex
    }

    public func scanECUNodes(
        range: ClosedRange<UInt16> = 0x700...0x7DF,
        delayNanoseconds: UInt64 = 10_000_000,
        progress: (@MainActor @Sendable (Int, Int) -> Void)? = nil
    ) async throws -> [PTOBDECUNode] {
        guard !range.isEmpty else {
            return []
        }

        let addresses = Array(range)

        return try await PTAdvancedOBDCoordinator.shared.executeReadOnly {
            var nodes: [PTOBDECUNode] = []

            for (index, value) in addresses.enumerated() {
                try Task.checkCancellation()

                let tx = String(format: "%03X", value)
                let rx = String(format: "%03X", value + 8)

                guard let address = PTOBDDiagnosticAddress(tx: tx, rx: rx) else {
                    await progress?(index + 1, addresses.count)
                    continue
                }

                let response = await PTMotoTelemetryManager.shared.fetchProprietaryData(
                    header: address.tx,
                    receiveAddress: address.rx,
                    udsCommand: "1001"
                )

                if Self.isPositive(response, service: "10") {
                    nodes.append(PTOBDECUNode(address: address, rawResponse: response))
                }

                await progress?(index + 1, addresses.count)

                if delayNanoseconds > 0 {
                    try await Task.sleep(nanoseconds: delayNanoseconds)
                }
            }

            return nodes
        }
    }

    public func scanDashboardNodes(
        progress: (@MainActor @Sendable (Int, Int) -> Void)? = nil
    ) async throws -> [PTOBDECUNode] {
        let addresses = Array(0xA0...0xDF)

        return try await PTAdvancedOBDCoordinator.shared.executeReadOnly {
            var nodes: [PTOBDECUNode] = []

            for (index, offset) in addresses.enumerated() {
                try Task.checkCancellation()

                let tx = String(format: "7%02X", offset)
                let rx = String(format: "7%02X", offset + 8)

                guard let address = PTOBDDiagnosticAddress(tx: tx, rx: rx) else {
                    await progress?(index + 1, addresses.count)
                    continue
                }

                let response = await PTMotoTelemetryManager.shared.fetchProprietaryData(
                    header: address.tx,
                    receiveAddress: address.rx,
                    udsCommand: "3E00"
                )

                if Self.isPositive(response, service: "7E") {
                    nodes.append(PTOBDECUNode(address: address, rawResponse: response))
                }

                await progress?(index + 1, addresses.count)

                try await Task.sleep(nanoseconds: 20_000_000)
            }

            return nodes
        }
    }

    public func readMemory(
        address: PTOBDDiagnosticAddress,
        memoryAddress: String,
        readSize: UInt16
    ) async throws -> PTOBDRawReadResult {
        let normalizedAddress = try Self.normalizeMemoryAddress(memoryAddress)

        guard (1...256).contains(Int(readSize)) else {
            throw PTOBDDiagnosticError.invalidReadSize
        }

        let command = "2324\(normalizedAddress)\(String(format: "%04X", readSize))"

        return try await PTAdvancedOBDCoordinator.shared.executeReadOnly {
            let response = await PTMotoTelemetryManager.shared.fetchProprietaryData(
                header: address.tx,
                receiveAddress: address.rx,
                udsCommand: command
            )

            let clean = Self.cleanHex(response)
            let upperResponse = response.uppercased()
            let negativeResponseCode = Self.negativeResponseCode(in: clean, service: 0x23)
            let payload = Self.payload(after: "63", in: clean)
            let status: PTOBDReadStatus

            if payload != nil {
                status = .success
            } else if negativeResponseCode != nil {
                status = .negativeResponse
            } else if clean.isEmpty || upperResponse.contains("NODATA") || upperResponse.contains("NO DATA") {
                status = .noData
            } else {
                status = .invalidResponse
            }

            return PTOBDRawReadResult(
                address: address,
                command: command,
                rawResponse: response,
                payloadHex: payload,
                status: status,
                negativeResponseCode: negativeResponseCode
            )
        }
    }
}

private extension PTUDSReadService {
    static func normalizeDID(_ value: String) throws -> String {
        let did = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        guard did.count == 4,
              did.allSatisfy({ "0123456789ABCDEF".contains($0) }) else {
            throw PTOBDDiagnosticError.invalidDID
        }

        return did
    }

    static func normalizeMemoryAddress(_ value: String) throws -> String {
        let address = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        guard address.count == 8,
              address.allSatisfy({ "0123456789ABCDEF".contains($0) }) else {
            throw PTOBDDiagnosticError.invalidMemoryAddress
        }

        return address
    }

    static func cleanHex(_ value: String) -> String {
        value.uppercased().filter { "0123456789ABCDEF".contains($0) }
    }

    static func hexBytes(_ value: String) -> [UInt8] {
        let clean = cleanHex(value)
        guard clean.count.isMultiple(of: 2) else {
            return []
        }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(clean.count / 2)
        var index = clean.startIndex

        while index < clean.endIndex {
            let nextIndex = clean.index(index, offsetBy: 2)
            guard let byte = UInt8(clean[index..<nextIndex], radix: 16) else {
                return []
            }
            bytes.append(byte)
            index = nextIndex
        }

        return bytes
    }

    static func containsByteSequence(_ sequence: [UInt8], in response: String) -> Bool {
        let bytes = hexBytes(response)
        guard !sequence.isEmpty, bytes.count >= sequence.count else {
            return false
        }

        return (0...(bytes.count - sequence.count)).contains { index in
            Array(bytes[index..<(index + sequence.count)]) == sequence
        }
    }

    static func negativeResponseCode(in response: String, service: UInt8) -> String? {
        let bytes = hexBytes(response)
        guard bytes.count >= 3 else {
            return nil
        }

        for index in 0..<(bytes.count - 2) {
            guard bytes[index] == 0x7F, bytes[index + 1] == service else {
                continue
            }
            return String(format: "%02X", bytes[index + 2])
        }

        return nil
    }

    static func payload(after marker: String, in value: String) -> String? {
        guard let range = value.range(of: marker) else {
            return nil
        }

        let payload = String(value[range.upperBound...])
        return payload.isEmpty ? nil : payload
    }

    static func isPositive(_ response: String, service: String) -> Bool {
        switch service {
        case "10":
            return containsByteSequence([0x50, 0x01], in: response)
        case "7E":
            return containsByteSequence([0x7E, 0x00], in: response)
        default:
            guard let serviceByte = UInt8(service, radix: 16) else {
                return false
            }
            return containsByteSequence([serviceByte], in: response)
        }
    }

    static func makeDIDResult(
        address: PTOBDDiagnosticAddress,
        did: String,
        response: String
    ) -> PTOBDIDReadResult {
        let clean = cleanHex(response)
        let positiveMarker = "62\(did)"

        let didBytes = hexBytes(did)
        if didBytes.count == 2,
           containsByteSequence([0x62] + didBytes, in: response),
           let payload = payload(after: positiveMarker, in: clean) {
            let decodedText = PTMultiFrameParser.parseLongString(response: response)
            return PTOBDIDReadResult(
                address: address,
                did: did,
                rawResponse: response,
                payloadHex: payload,
                decodedText: decodedText.isEmpty ? nil : decodedText,
                status: .success
            )
        }

        if let code = negativeResponseCode(in: clean, service: 0x22) {
            return PTOBDIDReadResult(
                address: address,
                did: did,
                rawResponse: response,
                payloadHex: nil,
                decodedText: nil,
                status: .negativeResponse,
                negativeResponseCode: code
            )
        }

        let status: PTOBDReadStatus
        let upperResponse = response.uppercased()
        if clean.isEmpty || upperResponse.contains("NODATA") || upperResponse.contains("NO DATA") {
            status = .noData
        } else {
            status = .invalidResponse
        }

        return PTOBDIDReadResult(
            address: address,
            did: did,
            rawResponse: response,
            payloadHex: nil,
            decodedText: nil,
            status: status
        )
    }
}
