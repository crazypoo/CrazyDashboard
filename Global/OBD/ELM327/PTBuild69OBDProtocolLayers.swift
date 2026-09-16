//
//  PTBuild69OBDProtocolLayers.swift
//  CrazyDashboard
//
//  EN: Separates ELM transport normalization, OBD-II parsing, and read-only UDS parsing.
//  ES: Separa la normalización del transporte ELM, el análisis OBD-II y el análisis UDS de solo lectura.
//  中文：分离 ELM 传输规范化、OBD-II 解析和只读 UDS 解析。
//

import Foundation

// EN: Keeps the adapter result independent from vehicle protocol semantics.
// ES: Mantiene el resultado del adaptador independiente de la semántica del vehículo.
// 中文：让适配器结果与车辆协议语义保持独立。
public nonisolated enum PTBuild69ELMTransportStatus: String, Codable, Equatable, Sendable {
    case positive
    case noData
    case unableToConnect
    case stopped
    case searching
    case error
}

// EN: One normalized ELM line retains an optional CAN header and declared DLC separately from data.
// ES: Cada línea ELM normalizada conserva por separado la cabecera CAN, el DLC declarado y los datos.
// 中文：每行规范化 ELM 数据分别保留 CAN Header、声明 DLC 和实际数据。
public nonisolated struct PTBuild69ELMFrame: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let rawLine: String
    public let canHeader: String?
    public let declaredDLC: Int?
    public let data: Data

    public init(id: UUID = UUID(), rawLine: String, canHeader: String?, declaredDLC: Int?, data: Data) {
        self.id = id
        self.rawLine = rawLine
        self.canHeader = canHeader
        self.declaredDLC = declaredDLC
        self.data = data
    }

    public var dataHex: String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

// EN: The normalized response is the only input required by the OBD-II and UDS parsers.
// ES: La respuesta normalizada es la única entrada necesaria para los analizadores OBD-II y UDS.
// 中文：OBD-II 和 UDS 解析器只接收规范化响应，避免重复处理 ELM 文本。
public nonisolated struct PTBuild69ELMResponse: Codable, Equatable, Sendable {
    public let raw: String
    public let status: PTBuild69ELMTransportStatus
    public let frames: [PTBuild69ELMFrame]

    public init(raw: String, status: PTBuild69ELMTransportStatus, frames: [PTBuild69ELMFrame]) {
        self.raw = raw
        self.status = status
        self.frames = frames
    }

    public var combinedData: Data {
        PTBuild69ELMNormalizer.reassembleISO15765(frames.map(\.data))
    }
}

// EN: Normalizes adapter text without deciding whether a payload is OBD-II or UDS.
// ES: Normaliza el texto del adaptador sin decidir si la carga es OBD-II o UDS.
// 中文：只规范化适配器文本，不判断 Payload 属于 OBD-II 还是 UDS。
public nonisolated enum PTBuild69ELMNormalizer {
    public static func normalize(raw: String, command: String? = nil) -> PTBuild69ELMResponse {
        let normalizedCommand = command.map(normalizedHex)
        let lines = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != ">" }

        let status: PTBuild69ELMTransportStatus
        let compact = raw.uppercased().filter { !$0.isWhitespace && $0 != "\r" && $0 != "\n" }
        if compact.contains("UNABLETOCONNECT") {
            status = .unableToConnect
        } else if compact.contains("NODATA") {
            status = .noData
        } else if compact.contains("STOPPED") {
            status = .stopped
        } else if compact.contains("SEARCHING") {
            status = .searching
        } else if compact.contains("ERROR") || compact == "?" || compact.hasSuffix("?") {
            status = .error
        } else {
            status = .positive
        }

        let frames = lines.compactMap { line -> PTBuild69ELMFrame? in
            guard normalizedCommand != normalizedHex(line) else { return nil }
            return parseLine(line)
        }
        return PTBuild69ELMResponse(raw: raw, status: status, frames: frames)
    }

    // EN: Parse a CAN header only when it is wider than one byte; never consume an ISO-TP PCI byte as DLC.
    // ES: Solo analiza una cabecera CAN cuando supera un byte; nunca consume un PCI ISO-TP como DLC.
    // 中文：仅当首 token 明确是多字节 CAN Header 时才解析，绝不把 ISO-TP PCI 字节误吃成 DLC。
    public static func parseLine(_ line: String) -> PTBuild69ELMFrame? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed != ">",
              !isAdapterStatusLine(trimmed) else {
            return nil
        }

        var tokens = trimmed
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return nil }

        if tokens.count == 1, tokens[0].count > 2 {
            guard tokens[0].allSatisfy(\.isHexDigit), tokens[0].count.isMultiple(of: 2) else { return nil }
            tokens = splitHexToken(tokens[0])
        }

        // EN: Reject echo and prose before filtering characters; silently deleting non-hex letters would turn "DATA" into byte DA.
        // ES: Rechaza ecos y texto antes de filtrar caracteres; borrar letras no hexadecimales convertiría "DATA" en el byte DA.
        // 中文：在过滤字符前拒绝回显和文本；静默删除非十六进制字母会把“DATA”误变成 DA 字节。
        guard tokens.allSatisfy({ $0.allSatisfy(\.isHexDigit) }) else { return nil }

        var header: String?
        if let first = tokens.first,
           (first.count == 3 || first.count == 8),
           UInt32(first, radix: 16).map({ $0 > 0xFF }) == true {
            header = first.uppercased()
            tokens.removeFirst()
        }

        var dlc: Int?
        if header != nil, let first = tokens.first, first.count == 1,
           let candidate = Int(first, radix: 16), candidate <= 8 {
            // An explicit one-character DLC is unambiguous. A two-character token such as 06 is kept as ISO-TP data.
            // Un DLC de un carácter es inequívoco. Un token de dos caracteres como 06 se conserva como dato ISO-TP.
            // 单字符 DLC 没有歧义；像 06 这样的双字符 Token 必须保留为 ISO-TP 数据。
            dlc = candidate
            tokens.removeFirst()
        }

        let byteTokens = tokens.flatMap(splitHexToken)
        guard !byteTokens.isEmpty,
              byteTokens.allSatisfy({ $0.count == 2 && UInt8($0, radix: 16) != nil }) else {
            return nil
        }
        let data = Data(byteTokens.compactMap { UInt8($0, radix: 16) })
        return PTBuild69ELMFrame(rawLine: line, canHeader: header, declaredDLC: dlc, data: data)
    }

    private static func isAdapterStatusLine(_ line: String) -> Bool {
        let normalized = line
            .uppercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".", with: "")
            .filter { !$0.isWhitespace }
        return normalized == "SEARCHING"
            || normalized == "NODATA"
            || normalized == "STOPPED"
            || normalized == "CANERROR"
            || normalized == "UNABLETOCONNECT"
            || normalized == "ERROR"
            || normalized == "?"
    }

    public static func reassembleISO15765(_ frames: [Data]) -> Data {
        guard let first = frames.first, let pci = first.first else { return Data() }
        switch pci & 0xF0 {
        case 0x00:
            let length = min(Int(pci & 0x0F), max(first.count - 1, 0))
            return Data(first.dropFirst().prefix(length))
        case 0x10:
            guard first.count >= 2 else { return Data() }
            let totalLength = (Int(pci & 0x0F) << 8) | Int(first[1])
            var output = Data(first.dropFirst(2))
            for frame in frames.dropFirst() where frame.first.map({ $0 & 0xF0 }) == 0x20 {
                output.append(contentsOf: frame.dropFirst())
                if output.count >= totalLength { break }
            }
            return Data(output.prefix(totalLength))
        default:
            return Data(frames.joined())
        }
    }

    public static func normalizedHex(_ value: String) -> String {
        value
            .uppercased()
            .filter { $0.isHexDigit }
    }

    private static func splitHexToken(_ value: String) -> [String] {
        let clean = value.uppercased().filter { $0.isHexDigit }
        guard !clean.isEmpty, clean.count.isMultiple(of: 2) else { return [] }
        var result: [String] = []
        var index = clean.startIndex
        while index < clean.endIndex {
            let next = clean.index(index, offsetBy: 2)
            result.append(String(clean[index..<next]))
            index = next
        }
        return result
    }
}

// EN: DTC status distinguishes an empty confirmed list from unsupported, missing, and invalid replies.
// ES: El estado DTC distingue una lista confirmada vacía de respuestas no soportadas, ausentes o inválidas.
// 中文：DTC 状态区分已确认无故障、不支持、无数据和非法响应。
public nonisolated enum PTBuild69DTCObservationStatus: Codable, Equatable, Sendable {
    case confirmedNone
    case values([String])
    case unsupported
    case noData
    case invalid
    case notQueried
}

// EN: Represents a read-only OBD-II positive response with its exact service byte.
// ES: Representa una respuesta OBD-II positiva de solo lectura con su byte de servicio exacto.
// 中文：表示带有原始服务字节的只读 OBD-II 正响应。
public nonisolated struct PTBuild69OBD2Response: Codable, Equatable, Sendable {
    public let commandMode: UInt8
    public let positiveService: UInt8?
    public let payload: Data
    public let rawResponse: String
    public let dtcStatus: PTBuild69DTCObservationStatus

    public init(commandMode: UInt8, positiveService: UInt8?, payload: Data, rawResponse: String, dtcStatus: PTBuild69DTCObservationStatus = .notQueried) {
        self.commandMode = commandMode
        self.positiveService = positiveService
        self.payload = payload
        self.rawResponse = rawResponse
        self.dtcStatus = dtcStatus
    }

    public var isPositive: Bool { positiveService == commandMode &+ 0x40 }
}

// EN: Parses OBD-II services by the command mode, so 42/43/47 cannot be confused with UDS 62.
// ES: Analiza los servicios OBD-II por modo de comando para no confundir 42/43/47 con UDS 62.
// 中文：根据命令 Mode 解析 OBD-II 服务，避免将 42/43/47 误判为 UDS 62。
public nonisolated enum PTBuild69OBD2Parser {
    public static func parse(command: String?, response: PTBuild69ELMResponse) -> PTBuild69OBD2Response? {
        let commandBytes = bytes(command)
        guard let mode = commandBytes.first else { return nil }
        let data = response.combinedData
        let expected = mode &+ 0x40
        let serviceIndex = data.firstIndex(of: expected)
        let positiveService = serviceIndex.map { data[$0] }
        let payload = serviceIndex.map { Data(data.dropFirst(data.distance(from: data.startIndex, to: $0) + 1)) } ?? Data()
        let dtcStatus: PTBuild69DTCObservationStatus
        if mode == 0x03 || mode == 0x07 || mode == 0x0A {
            dtcStatus = parseDTC(mode: mode, positive: positiveService != nil, payload: payload, status: response.status)
        } else if response.status == .noData {
            dtcStatus = .noData
        } else {
            dtcStatus = .notQueried
        }
        return PTBuild69OBD2Response(
            commandMode: mode,
            positiveService: positiveService,
            payload: payload,
            rawResponse: response.raw,
            dtcStatus: dtcStatus
        )
    }

    private static func parseDTC(mode: UInt8, positive: Bool, payload: Data, status: PTBuild69ELMTransportStatus) -> PTBuild69DTCObservationStatus {
        guard status == .positive else { return status == .noData ? .noData : .invalid }
        guard positive else { return .unsupported }
        // EN: ELM responses can include one trailing non-DTC padding byte; parse complete pairs and retain the positive status.
        // ES: Las respuestas ELM pueden incluir un byte final de relleno; analiza pares completos y conserva el estado positivo.
        // 中文：ELM 响应可能包含一个尾部非 DTC 填充字节；解析完整字节对，同时保留正响应状态。
        let completePayloadLength = payload.count - payload.count % 2
        guard completePayloadLength >= 2 else { return .invalid }
        let codes = stride(from: 0, to: completePayloadLength, by: 2).compactMap { offset -> String? in
            let high = payload[payload.index(payload.startIndex, offsetBy: offset)]
            let low = payload[payload.index(payload.startIndex, offsetBy: offset + 1)]
            guard high != 0 || low != 0 else { return nil }
            let prefix: String
            switch high >> 6 {
            case 0: prefix = "P"
            case 1: prefix = "C"
            case 2: prefix = "B"
            default: prefix = "U"
            }
            let digit1 = (high >> 4) & 0x03
            let digit2 = high & 0x0F
            return "\(prefix)\(digit1)\(String(format: "%X", digit2))\(String(format: "%X", low >> 4))\(String(format: "%X", low & 0x0F))"
        }
        return codes.isEmpty ? .confirmedNone : .values(codes)
    }

    private static func bytes(_ value: String?) -> [UInt8] {
        guard let value else { return [] }
        let clean = PTBuild69ELMNormalizer.normalizedHex(value)
        guard clean.count.isMultiple(of: 2) else { return [] }
        return stride(from: 0, to: clean.count, by: 2).compactMap { index in
            let start = clean.index(clean.startIndex, offsetBy: index)
            let end = clean.index(start, offsetBy: 2)
            return UInt8(clean[start..<end], radix: 16)
        }
    }
}

// EN: UDS negative-response details remain separate from transport errors and positive DID data.
// ES: Los detalles de respuesta negativa UDS permanecen separados de errores de transporte y datos DID positivos.
// 中文：UDS 否定响应详情与传输错误、DID 正响应数据分离保存。
public nonisolated struct PTBuild69UDSNegativeResponse: Codable, Equatable, Sendable {
    public let requestedService: UInt8
    public let negativeResponseCode: UInt8

    public init(requestedService: UInt8, negativeResponseCode: UInt8) {
        self.requestedService = requestedService
        self.negativeResponseCode = negativeResponseCode
    }

    public var serviceHex: String { String(format: "%02X", requestedService) }
    public var codeHex: String { String(format: "%02X", negativeResponseCode) }
}

// EN: A UDS response exposes the DID and raw payload but never creates a write command.
// ES: Una respuesta UDS expone el DID y la carga bruta, pero nunca crea un comando de escritura.
// 中文：UDS 响应暴露 DID 和原始数据，但绝不会生成写入命令。
public nonisolated struct PTBuild69UDSResponse: Codable, Equatable, Sendable {
    public let requestedService: UInt8
    public let positiveService: UInt8?
    public let did: String?
    public let payload: Data
    public let rawResponse: String
    public let negativeResponse: PTBuild69UDSNegativeResponse?

    public init(requestedService: UInt8, positiveService: UInt8?, did: String?, payload: Data, rawResponse: String, negativeResponse: PTBuild69UDSNegativeResponse?) {
        self.requestedService = requestedService
        self.positiveService = positiveService
        self.did = did
        self.payload = payload
        self.rawResponse = rawResponse
        self.negativeResponse = negativeResponse
    }

    public var isPositive: Bool { negativeResponse == nil && positiveService == requestedService &+ 0x40 }
}

// EN: Parses UDS positive 0x40+n and negative 0x7F responses, including 0x62 DID reads.
// ES: Analiza respuestas UDS positivas 0x40+n y negativas 0x7F, incluidas lecturas DID 0x62.
// 中文：解析 UDS 的 0x40+n 正响应和 0x7F 否定响应，包括 0x62 DID 读取。
public nonisolated enum PTBuild69UDSParser {
    public static func parse(command: String?, response: PTBuild69ELMResponse) -> PTBuild69UDSResponse? {
        guard let requestService = bytes(command).first else { return nil }
        let data = response.combinedData
        // EN: A negative response is valid only when 0x7F is the first normalized service byte.
        // ES: Una respuesta negativa solo es válida cuando 0x7F es el primer byte de servicio normalizado.
        // 中文：只有规范化服务数据的第一个字节是 0x7F 时，才认定为 UDS 否定响应。
        if data.first == 0x7F, data.count >= 3 {
            let service = data[data.index(after: data.startIndex)]
            let code = data[data.index(data.startIndex, offsetBy: 2)]
            return PTBuild69UDSResponse(
                requestedService: requestService,
                positiveService: nil,
                did: nil,
                payload: Data(),
                rawResponse: response.raw,
                negativeResponse: PTBuild69UDSNegativeResponse(requestedService: service, negativeResponseCode: code)
            )
        }

        let expected = requestService &+ 0x40
        guard let serviceIndex = data.firstIndex(of: expected) else {
            return PTBuild69UDSResponse(requestedService: requestService, positiveService: nil, did: nil, payload: Data(), rawResponse: response.raw, negativeResponse: nil)
        }
        let afterService = data.index(after: serviceIndex)
        let remaining = Data(data[afterService...])
        let did: String?
        let payload: Data
        if expected == 0x62, remaining.count >= 2 {
            did = String(format: "%02X%02X", remaining[remaining.startIndex], remaining[remaining.index(after: remaining.startIndex)])
            payload = Data(remaining.dropFirst(2))
        } else {
            did = nil
            payload = remaining
        }
        return PTBuild69UDSResponse(requestedService: requestService, positiveService: expected, did: did, payload: payload, rawResponse: response.raw, negativeResponse: nil)
    }

    private static func bytes(_ value: String?) -> [UInt8] {
        guard let value else { return [] }
        let clean = PTBuild69ELMNormalizer.normalizedHex(value)
        guard clean.count.isMultiple(of: 2) else { return [] }
        return stride(from: 0, to: clean.count, by: 2).compactMap { index in
            let start = clean.index(clean.startIndex, offsetBy: index)
            let end = clean.index(start, offsetBy: 2)
            return UInt8(clean[start..<end], radix: 16)
        }
    }
}

// EN: The router is read-only and reports the protocol layer chosen for every response.
// ES: El enrutador es de solo lectura e informa de la capa elegida para cada respuesta.
// 中文：路由器只读，并报告每个响应最终归属的协议层。
public nonisolated enum PTBuild69ProtocolLayer: String, Codable, Equatable, Sendable {
    case elmTransport
    case obd2
    case uds
    case unknown
}

public nonisolated enum PTBuild69RoutedResponse: Sendable {
    case obd2(PTBuild69OBD2Response)
    case uds(PTBuild69UDSResponse)
    case transport(PTBuild69ELMResponse)
    case unknown(PTBuild69ELMResponse)

    public var layer: PTBuild69ProtocolLayer {
        switch self {
        case .obd2: return .obd2
        case .uds: return .uds
        case .transport: return .elmTransport
        case .unknown: return .unknown
        }
    }
}

public nonisolated enum PTBuild69ProtocolRouter {
    public static func route(command: String?, rawResponse: String) -> PTBuild69RoutedResponse {
        let normalized = PTBuild69ELMNormalizer.normalize(raw: rawResponse, command: command)
        guard normalized.status == .positive else { return .transport(normalized) }
        let commandBytes = command.map(PTBuild69ELMNormalizer.normalizedHex).flatMap(bytes) ?? []
        let responseBytes = normalized.combinedData
        let requestService = commandBytes.first
        let knownUDSServices: Set<UInt8> = [0x10, 0x11, 0x14, 0x19, 0x22, 0x23, 0x27, 0x2E, 0x31, 0x34, 0x36, 0x37]
        let looksUDS = requestService.map(knownUDSServices.contains) == true
            || (responseBytes.contains(0x7F) && requestService.map { $0 > 0x0A } == true)
        if looksUDS, let uds = PTBuild69UDSParser.parse(command: command, response: normalized) {
            return .uds(uds)
        }
        if let obd2 = PTBuild69OBD2Parser.parse(command: command, response: normalized) {
            return .obd2(obd2)
        }
        return .unknown(normalized)
    }

    private static func bytes(_ value: String) -> [UInt8] {
        guard value.count.isMultiple(of: 2) else { return [] }
        return stride(from: 0, to: value.count, by: 2).compactMap { index in
            let start = value.index(value.startIndex, offsetBy: index)
            let end = value.index(start, offsetBy: 2)
            return UInt8(value[start..<end], radix: 16)
        }
    }
}
