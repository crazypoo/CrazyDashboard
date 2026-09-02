//
//  PTUDSDiagnosticService.swift
//  PTSpeed
//
//  Read-only UDS/ECU diagnostics built on top of the stable OBD transport.
//

import Foundation

nonisolated public enum PTOBDDiagnosticError: Error, Equatable, Sendable {
    case disconnected
    case invalidAddress
    case invalidDID
    case invalidMemoryAddress
    case invalidReadSize
    case batchLimitExceeded
    case invalidBatchPolicy
    case timeout
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
        case .batchLimitExceeded:
            return "The diagnostic batch exceeds the permitted read limit."
        case .invalidBatchPolicy:
            return "The diagnostic batch policy is invalid."
        case .timeout:
            return "The ECU response exceeded the diagnostic timeout."
        case let .negativeResponse(service, code):
            return "ECU rejected service \(service) with code \(code)."
        case .noData:
            return "The ECU returned no data."
        case .cancelled:
            return "The diagnostic operation was cancelled."
        }
    }
}

/// EN: Bounds for one read-only DID batch; they prevent accidental long bus occupation.
/// ES: Límites de un lote DID de solo lectura; evitan ocupar el bus durante demasiado tiempo.
/// 中文：单次只读 DID 批量读取的边界，防止意外长时间占用总线。
nonisolated public struct PTOBDReadBatchPolicy: Sendable {
    public let maximumDIDs: Int
    public let requestTimeout: TimeInterval
    public let maximumDuration: TimeInterval
    public let interRequestDelayNanoseconds: UInt64

    public init(
        maximumDIDs: Int,
        requestTimeout: TimeInterval,
        maximumDuration: TimeInterval,
        interRequestDelayNanoseconds: UInt64
    ) {
        self.maximumDIDs = maximumDIDs
        self.requestTimeout = requestTimeout
        self.maximumDuration = maximumDuration
        self.interRequestDelayNanoseconds = interRequestDelayNanoseconds
    }

    public static let standard = PTOBDReadBatchPolicy(
        maximumDIDs: 16,
        requestTimeout: 8,
        maximumDuration: 60,
        interRequestDelayNanoseconds: 100_000_000
    )

    public static let developer = PTOBDReadBatchPolicy(
        maximumDIDs: 128,
        requestTimeout: 8,
        maximumDuration: 120,
        interRequestDelayNanoseconds: 150_000_000
    )

    fileprivate var isValid: Bool {
        maximumDIDs > 0 &&
        requestTimeout > 0 &&
        maximumDuration >= requestTimeout
    }
}

/// EN: Only entries with evidence may be exposed to the ordinary UI.
/// ES: Solo las entradas con evidencia pueden exponerse a la UI normal.
/// 中文：只有已有证据的项目才能暴露给普通 UI。
nonisolated public enum PTOBDReadOnlyCatalog {
    // EN: Keep the read-only DID allowlist in the evidence catalog so callers have one source of truth.
    // ES: Mantiene la lista de DIDs de solo lectura en el catálogo de evidencia para tener una única fuente.
    // 中文：只读 DID 白名单统一由证据目录维护，避免出现第二份真相源。
    public static var confirmedDIDs: [String] {
        PTXP400InstructionCatalog.confirmedDIDs
    }
}

nonisolated public enum PTOBDReadStatus: String, Codable, Sendable {
    case success
    case negativeResponse
    case noData
    case invalidResponse
}

// EN: Standard negative-response metadata keeps the raw NRC and a readable explanation together.
// ES: Los metadatos de respuesta negativa conservan el NRC original y una explicación legible.
// 中文：标准否定响应模型同时保存原始 NRC 和可读说明。
nonisolated public struct PTOBDNegativeResponse: Codable, Equatable, Sendable {
    public let service: String
    public let code: String
    public let description: String

    public init(service: String, code: String, description: String) {
        self.service = service
        self.code = code
        self.description = description
    }
}

nonisolated public struct PTOBDIDReadResult: Codable, Sendable {
    public let address: PTOBDDiagnosticAddress
    public let did: String
    public let rawResponse: String
    public let payloadHex: String?
    public let decodedText: String?
    public let status: PTOBDReadStatus
    public let negativeResponseCode: String?
    public let negativeResponse: PTOBDNegativeResponse?

    public init(address: PTOBDDiagnosticAddress,
                did: String,
                rawResponse: String,
                payloadHex: String?,
                decodedText: String?,
                status: PTOBDReadStatus,
                negativeResponseCode: String? = nil,
                negativeResponse: PTOBDNegativeResponse? = nil) {
        self.address = address
        self.did = did
        self.rawResponse = rawResponse
        self.payloadHex = payloadHex
        self.decodedText = decodedText
        self.status = status
        self.negativeResponseCode = negativeResponseCode
        self.negativeResponse = negativeResponse
    }
}

nonisolated public struct PTOBDECUNode: Codable, Hashable, Sendable {
    public let address: PTOBDDiagnosticAddress
    public let rawResponse: String

    public init(address: PTOBDDiagnosticAddress, rawResponse: String) {
        self.address = address
        self.rawResponse = rawResponse
    }
}

nonisolated public struct PTOBDRawReadResult: Codable, Sendable {
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

nonisolated public struct PTOBDNodeDumpReport: Codable, Sendable {
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

nonisolated public struct PTOBDFullVehicleDumpReport: Codable, Sendable {
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

// EN: The actor serializes advanced reads while the stable telemetry manager remains the only transport owner.
// ES: El actor serializa las lecturas avanzadas mientras el gestor de telemetría estable sigue siendo el único dueño del transporte.
// 中文：该 actor 串行化高级只读任务，稳定遥测管理器仍然是唯一的传输层所有者。
public actor PTAdvancedOBDCoordinator {
    public static let shared = PTAdvancedOBDCoordinator()

    private var isExecuting = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    private init() {}

    // EN: Waiters are queued before suspension so actor reentrancy cannot overlap two exclusive bus operations.
    // ES: Las esperas se encolan antes de suspenderse para que la reentrancia del actor no solape dos operaciones exclusivas.
    // 中文：在挂起前先排队，避免 actor 重入导致两个总线独占任务重叠。
    private func acquire() async {
        guard isExecuting else {
            isExecuting = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        if waiters.isEmpty {
            isExecuting = false
        } else {
            waiters.removeFirst().resume()
        }
    }

    /// EN: Executes one read-only operation while the existing telemetry polling task is suspended by the stable manager.
    /// ES: Ejecuta una operación de solo lectura mientras el gestor estable suspende el sondeo de telemetría.
    /// 中文：在稳定管理器暂停遥测轮询期间执行一个只读任务。
    public func executeReadOnly<T>(
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        await acquire()
        defer { release() }

        guard await PTMotoTelemetryManager.shared.isConnected else {
            throw PTOBDDiagnosticError.disconnected
        }
        try Task.checkCancellation()

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

nonisolated public final class PTUDSReadService {
    public static let shared = PTUDSReadService()

    private init() {}

    /// EN: Pure parsing entry point for reports and unit tests; it never sends vehicle commands.
    /// ES: Entrada de análisis puro para informes y pruebas; no envía comandos al vehículo.
    /// 中文：纯解析入口，供报告生成和单元测试复用，不会发送任何车辆指令。
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

        let response = try await PTAdvancedOBDCoordinator.shared.executeReadOnly {
            await PTMotoTelemetryManager.shared.fetchProprietaryData(
                header: address.tx,
                receiveAddress: address.rx,
                udsCommand: "22\(did)"
            )
        }
        let decodedText = await MainActor.run {
            PTMultiFrameParser.parseLongString(response: response)
        }

        return Self.makeDIDResult(
            address: address,
            did: did,
            response: response,
            decodedText: decodedText
        )
    }

    public func readDIDs(
        address: PTOBDDiagnosticAddress,
        dids: [String],
        policy: PTOBDReadBatchPolicy = .standard,
        progress: (@MainActor @Sendable (Int, Int, PTOBDIDReadResult) -> Void)? = nil
    ) async throws -> [PTOBDIDReadResult] {
        let normalizedDIDs = try dids.map(Self.normalizeDID)

        guard !normalizedDIDs.isEmpty else {
            return []
        }

        guard policy.isValid else {
            throw PTOBDDiagnosticError.invalidBatchPolicy
        }

        guard normalizedDIDs.count <= policy.maximumDIDs else {
            throw PTOBDDiagnosticError.batchLimitExceeded
        }

        let responses = try await PTAdvancedOBDCoordinator.shared.executeReadOnly {
            let batchStartedAt = Date()
            var responses: [(String, String)] = []
            responses.reserveCapacity(normalizedDIDs.count)

            for (index, did) in normalizedDIDs.enumerated() {
                try Task.checkCancellation()

                guard Date().timeIntervalSince(batchStartedAt) <= policy.maximumDuration else {
                    throw PTOBDDiagnosticError.timeout
                }

                let requestStartedAt = Date()
                let response = await PTMotoTelemetryManager.shared.fetchProprietaryData(
                    header: address.tx,
                    receiveAddress: address.rx,
                    udsCommand: "22\(did)"
                )

                guard Date().timeIntervalSince(requestStartedAt) <= policy.requestTimeout else {
                    throw PTOBDDiagnosticError.timeout
                }

                responses.append((did, response))

                if policy.interRequestDelayNanoseconds > 0,
                   index + 1 < normalizedDIDs.count {
                    try await Task.sleep(nanoseconds: policy.interRequestDelayNanoseconds)
                }
            }

            return responses
        }

        var results: [PTOBDIDReadResult] = []
        results.reserveCapacity(responses.count)
        for (index, item) in responses.enumerated() {
            try Task.checkCancellation()
            let decodedText = await MainActor.run {
                PTMultiFrameParser.parseLongString(response: item.1)
            }
            let result = Self.makeDIDResult(
                address: address,
                did: item.0,
                response: item.1,
                decodedText: decodedText
            )
            results.append(result)
            await progress?(index + 1, normalizedDIDs.count, result)
        }

        return results
    }

    public func readVIN(
        address: PTOBDDiagnosticAddress
    ) async throws -> String? {
        let result = try await readDID(address: address, did: "F190")

        guard result.status == .success else {
            return nil
        }

        let value = result.decodedText ?? result.payloadHex
        if value != nil {
            await MainActor.run {
                _ = PTMotorcycleGarageStore.shared.updatePreferredDiagnosticAddress(address)
            }
        }
        return value
    }

    // EN: These wrappers place legacy read-only telemetry calls under the same exclusive gate as UDS DID reads.
    // ES: Estos adaptadores colocan las lecturas heredadas de solo lectura bajo la misma puerta exclusiva que los DID UDS.
    // 中文：这些适配器让旧的只读遥测读取与 UDS DID 读取共用同一个总线独占门禁。
    public func readConfirmedDTCs() async throws -> [String: [PTTroubleCode]] {
        try await PTAdvancedOBDCoordinator.shared.executeReadOnly {
            await PTMotoTelemetryManager.shared.getConfirmedDTCs()
        }
    }

    public func readMode6Reports() async throws -> [PTMode6Data] {
        try await PTAdvancedOBDCoordinator.shared.executeReadOnly {
            let commands = await PTMotoTelemetryManager.shared.scanSupportedMode6Commands()
            return await PTMotoTelemetryManager.shared.fetchMode6TestReports(for: commands)
        }
    }

    public func readEngineSpeedFreezeFrame() async throws -> Double? {
        try await PTAdvancedOBDCoordinator.shared.executeReadOnly {
            await PTMotoTelemetryManager.shared.getFreezeFrameData(forPID: "0C")
        }
    }

    // EN: The ordinary UI can read only the confirmed DID catalog using the selected vehicle's address.
    // ES: La UI normal solo puede leer el catálogo DID confirmado usando la dirección del vehículo seleccionado.
    // 中文：普通 UI 只能使用当前车辆地址读取已确认 DID 白名单。
    @MainActor
    public func readConfirmedDIDsForCurrentVehicle(
        policy: PTOBDReadBatchPolicy = .standard,
        progress: (@MainActor @Sendable (Int, Int, PTOBDIDReadResult) -> Void)? = nil
    ) async throws -> [PTOBDIDReadResult] {
        let address = PTMotorcycleGarageStore.shared.currentVehicle?.preferredDiagnosticAddress
            ?? PTOBDDiagnosticAddress(tx: "7E0", rx: "7E8")!
        return try await readDIDs(
            address: address,
            dids: PTOBDReadOnlyCatalog.confirmedDIDs,
            policy: policy,
            progress: progress
        )
    }

    public func scanECUNodes(
        range: ClosedRange<UInt16> = 0x700...0x7DF,
        delayNanoseconds: UInt64 = 10_000_000,
        progress: (@MainActor @Sendable (Int, Int) -> Void)? = nil
    ) async throws -> [PTOBDECUNode] {
        guard !range.isEmpty else {
            return []
        }

        // EN: Keep the generated response IDs inside the physical 11-bit CAN range.
        // ES: Mantiene los IDs de respuesta generados dentro del rango físico CAN de 11 bits.
        // 中文：确保生成的响应 ID 始终处于物理 11-bit CAN 范围内。
        guard range.upperBound <= 0x7F7,
              range.count <= 256 else {
            throw PTOBDDiagnosticError.invalidAddress
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

            let clean = Self.normalizedUDSResponseHex(response)
            let upperResponse = response.uppercased()
            let negativeResponseCode = Self.negativeResponseCode(in: response, service: 0x23)
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
    nonisolated static func normalizeDID(_ value: String) throws -> String {
        let did = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        guard did.count == 4,
              did.allSatisfy({ "0123456789ABCDEF".contains($0) }) else {
            throw PTOBDDiagnosticError.invalidDID
        }

        return did
    }

    nonisolated static func normalizeMemoryAddress(_ value: String) throws -> String {
        let address = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        guard address.count == 8,
              address.allSatisfy({ "0123456789ABCDEF".contains($0) }) else {
            throw PTOBDDiagnosticError.invalidMemoryAddress
        }

        return address
    }

    // EN: Normalize ELM327 lines into UDS bytes without treating a CAN header or DLC as application payload.
    // ES: Normaliza las líneas ELM327 a bytes UDS sin tratar el encabezado CAN ni el DLC como carga útil.
    // 中文：把 ELM327 行规范化为 UDS 字节，避免将 CAN Header 或 DLC 误当成业务 Payload。
    nonisolated static func normalizedUDSResponseHex(_ response: String) -> String {
        response
            .components(separatedBy: .newlines)
            .map(normalizedUDSLineHex)
            .joined()
    }

    nonisolated static func normalizedUDSLineHex(_ line: String) -> String {
        let tokens = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !tokens.isEmpty else { return "" }

        if let headerLength = canHeaderLength(for: tokens[0]) {
            let clean = tokens[0].uppercased()
            return normalizedCANBytes(hexBytes(String(clean.dropFirst(headerLength))))
        }

        if isCANHeaderToken(tokens[0]) {
            if tokens.count > 1 {
                let bytes = tokens.dropFirst().compactMap(hexByte)
                return normalizedCANBytes(bytes)
            }
            return ""
        }

        return tokens
            .filter { token in
                let value = token.uppercased()
                return value.count >= 2 && value.count.isMultiple(of: 2) &&
                    value.allSatisfy { "0123456789ABCDEF".contains($0) }
            }
            .map { $0.uppercased() }
            .joined()
    }

    nonisolated static func isCANHeaderToken(_ value: String) -> Bool {
        let clean = value.uppercased()
        guard clean.allSatisfy({ "0123456789ABCDEF".contains($0) }) else { return false }
        if clean.count == 8 {
            return clean.hasPrefix("18D") || clean.hasPrefix("18C")
        }
        guard clean.count == 3, let numeric = UInt16(clean, radix: 16) else { return false }
        return numeric <= 0x7FF
    }

    nonisolated static func canHeaderLength(for value: String) -> Int? {
        let clean = value.uppercased()
        if clean.count > 8, clean.hasPrefix("18D") || clean.hasPrefix("18C") {
            return 8
        }
        if clean.count > 3, clean.hasPrefix("7E") || clean.hasPrefix("7F") {
            return 3
        }
        return nil
    }

    nonisolated static func hexByte(_ value: String) -> UInt8? {
        guard value.count == 2,
              value.allSatisfy({ "0123456789ABCDEFabcdef".contains($0) }) else {
            return nil
        }
        return UInt8(value, radix: 16)
    }

    nonisolated static func normalizedCANBytes(_ input: [UInt8]) -> String {
        var bytes = input
        if bytes.count >= 2, bytes[0] <= 8, bytes[1] >= 0x40 {
            bytes.removeFirst()
        }

        if let first = bytes.first {
            switch first >> 4 {
            case 0, 2:
                bytes.removeFirst()
            case 1:
                if bytes.count >= 2 {
                    bytes.removeFirst(2)
                }
            default:
                break
            }
        }

        return bytes.map { String(format: "%02X", $0) }.joined()
    }

    nonisolated static func cleanHex(_ value: String) -> String {
        value.uppercased().filter { "0123456789ABCDEF".contains($0) }
    }

    nonisolated static func hexBytes(_ value: String) -> [UInt8] {
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

    nonisolated static func containsByteSequence(_ sequence: [UInt8], in response: String) -> Bool {
        let bytes = hexBytes(normalizedUDSResponseHex(response))
        guard !sequence.isEmpty, bytes.count >= sequence.count else {
            return false
        }

        return (0...(bytes.count - sequence.count)).contains { index in
            Array(bytes[index..<(index + sequence.count)]) == sequence
        }
    }

    nonisolated static func negativeResponseCode(in response: String, service: UInt8) -> String? {
        let bytes = hexBytes(normalizedUDSResponseHex(response))
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

    nonisolated static func payload(after marker: String, in value: String) -> String? {
        guard let range = value.range(of: marker) else {
            return nil
        }

        let payload = String(value[range.upperBound...])
        return payload.isEmpty ? nil : payload
    }

    nonisolated static func isPositive(_ response: String, service: String) -> Bool {
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

    nonisolated static func makeDIDResult(
        address: PTOBDDiagnosticAddress,
        did: String,
        response: String,
        decodedText: String? = nil
    ) -> PTOBDIDReadResult {
        let clean = normalizedUDSResponseHex(response)
        let positiveMarker = "62\(did)"

        let didBytes = hexBytes(did)
        if didBytes.count == 2,
           containsByteSequence([0x62] + didBytes, in: response),
           let payload = payload(after: positiveMarker, in: clean) {
            let parsedText = decodedText?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? printableASCII(from: payload)
            return PTOBDIDReadResult(
                address: address,
                did: did,
                rawResponse: response,
                payloadHex: payload,
                decodedText: parsedText?.isEmpty == false ? parsedText : nil,
                status: .success,
                negativeResponse: nil
            )
        }

        if let code = negativeResponseCode(in: response, service: 0x22) {
            return PTOBDIDReadResult(
                address: address,
                did: did,
                rawResponse: response,
                payloadHex: nil,
                decodedText: nil,
                status: .negativeResponse,
                negativeResponseCode: code,
                negativeResponse: PTOBDNegativeResponse(
                    service: "22",
                    code: code,
                    description: negativeResponseDescription(code)
                )
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

    nonisolated static func negativeResponseDescription(_ code: String) -> String {
        switch code.uppercased() {
        case "10": return "General reject"
        case "11": return "Service not supported"
        case "12": return "Sub-function not supported"
        case "13": return "Incorrect message length or format"
        case "21": return "Busy, repeat request"
        case "22": return "Conditions not correct"
        case "24": return "Request sequence error"
        case "31": return "Request out of range"
        case "33": return "Security access denied"
        case "35": return "Invalid key"
        case "78": return "Response pending"
        default: return "Unknown negative response"
        }
    }

    nonisolated static func printableASCII(from hex: String) -> String? {
        let text = hexBytes(hex).compactMap { byte -> Character? in
            guard (32...126).contains(byte) else { return nil }
            return Character(UnicodeScalar(byte))
        }
        let value = String(text).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
