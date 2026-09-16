//
//  PTXP400SemanticEvidence.swift
//  CrazyDashboard
//
//  EN: Defines the evidence-first semantic layer for XP400 dashboard frames.
//  ES: Define la capa semántica basada en evidencia para las tramas del tablero XP400.
//  中文：定义基于证据的 XP400 仪表盘帧语义层。
//

import Foundation

// EN: Field roles prevent clocks, counters, padding, and sentinels from becoming false candidates.
// ES: Los roles evitan que relojes, contadores, relleno y centinelas se conviertan en candidatos falsos.
// 中文：字段角色防止时钟、计数器、填充和哨兵值被误判为候选信号。
public nonisolated enum PTXP400SemanticFieldRole: String, Codable, CaseIterable, Sendable {
    case semantic
    case provisional
    case counter
    case clock
    case flags
    case reserved
    case sentinel
    case padding
    case candidate
    case unknown
}

// EN: Quality states make unavailable and unconfirmed values explicit at the protocol boundary.
// ES: Los estados de calidad hacen explícitos los valores no disponibles y no confirmados en el límite del protocolo.
// 中文：质量状态在协议边界明确区分不可用值和未确认值。
public nonisolated enum PTXP400SemanticQuality: String, Codable, CaseIterable, Sendable {
    case confirmed
    case probable
    case experimental
    case unavailable
    case invalid
    case sentinel
}

// EN: Sentinel rules are deliberately local to a field; zero is not globally treated as missing.
// ES: Las reglas centinela son locales a cada campo; el cero no se considera ausente globalmente.
// 中文：哨兵规则只对具体字段生效，不把 0 全局视为缺失值。
public nonisolated enum PTXP400SentinelRule: Codable, Equatable, Sendable {
    case none
    case exact(UInt8)
    case allFF
    case allZero

    public func matches(_ data: Data) -> Bool {
        guard !data.isEmpty else { return false }
        switch self {
        case .none:
            return false
        case .exact(let value):
            return data.count == 1 && data.first == value
        case .allFF:
            return data.allSatisfy { $0 == 0xFF }
        case .allZero:
            return data.allSatisfy { $0 == 0x00 }
        }
    }
}

// EN: Describes a byte or bit range without claiming that every bit has been decoded.
// ES: Describe un rango de bytes o bits sin afirmar que cada bit esté decodificado.
// 中文：描述字节或位范围，但不声称所有位都已经解码。
public nonisolated struct PTXP400FieldDescriptor: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let byteIndex: Int
    public let byteLength: Int
    public let bitMask: UInt8
    public let role: PTXP400SemanticFieldRole
    public let unit: String?
    public let sentinelRule: PTXP400SentinelRule

    public init(
        id: String,
        byteIndex: Int,
        byteLength: Int = 1,
        bitMask: UInt8 = 0xFF,
        role: PTXP400SemanticFieldRole,
        unit: String? = nil,
        sentinelRule: PTXP400SentinelRule = .none
    ) {
        self.id = id
        self.byteIndex = byteIndex
        self.byteLength = max(byteLength, 1)
        self.bitMask = bitMask
        self.role = role
        self.unit = unit
        self.sentinelRule = sentinelRule
    }
}

// EN: A decoded field retains raw bytes, normalized display value, role, and confidence together.
// ES: Un campo decodificado conserva juntos los bytes brutos, el valor normalizado, el rol y la confianza.
// 中文：解码字段同时保留原始字节、规范值、角色和置信度。
public nonisolated struct PTXP400SemanticField: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let role: PTXP400SemanticFieldRole
    public let raw: Data
    public let normalizedValue: String?
    public let unit: String?
    public let availability: PTDashboardValueAvailability
    public let quality: PTXP400SemanticQuality
    public let confidence: Double

    public init(
        id: String,
        role: PTXP400SemanticFieldRole,
        raw: Data,
        normalizedValue: String?,
        unit: String? = nil,
        availability: PTDashboardValueAvailability,
        quality: PTXP400SemanticQuality,
        confidence: Double
    ) {
        self.id = id
        self.role = role
        self.raw = raw
        self.normalizedValue = normalizedValue
        self.unit = unit
        self.availability = availability
        self.quality = quality
        self.confidence = confidence.isFinite ? min(max(confidence, 0), 1) : 0
    }

    public var rawHex: String {
        raw.map { String(format: "%02X", $0) }.joined()
    }
}

// EN: The schema is an auditable map of field roles, not an executable write definition.
// ES: El esquema es un mapa auditable de roles, no una definición ejecutable de escritura.
// 中文：Schema 是可审计的字段角色映射，不是可执行的写入定义。
public nonisolated struct PTXP400FrameSchema: Codable, Equatable, Sendable, Identifiable {
    public let id: UInt8
    public let name: String
    public let payloadLength: Int
    public let fields: [PTXP400FieldDescriptor]

    public init(id: UInt8, name: String, payloadLength: Int, fields: [PTXP400FieldDescriptor]) {
        self.id = id
        self.name = name
        self.payloadLength = payloadLength
        self.fields = fields
    }

    public var identifier: UInt8 { id }

    public func field(_ key: String) -> PTXP400FieldDescriptor? {
        fields.first { $0.id == key }
    }

    public static let connection = PTXP400FrameSchema(
        id: PTXP400BLEProtocol.connectionFrameID,
        name: "CONNECTION",
        payloadLength: 12,
        fields: [PTXP400FieldDescriptor(id: "connection.serial", byteIndex: 0, byteLength: 12, role: .semantic)]
    )

    public static let data1 = PTXP400FrameSchema(
        id: PTXP400BLEProtocol.data1FrameID,
        name: "DATA1",
        payloadLength: 8,
        fields: [
            PTXP400FieldDescriptor(id: "data1.fuel", byteIndex: 0, role: .semantic, unit: "%", sentinelRule: .exact(0xFF)),
            PTXP400FieldDescriptor(id: "data1.fuelRelatedUnknown", byteIndex: 1, role: .candidate, sentinelRule: .exact(0xFF)),
            PTXP400FieldDescriptor(id: "data1.averageConsumption", byteIndex: 2, role: .semantic, unit: "L/100km", sentinelRule: .exact(0xFF)),
            PTXP400FieldDescriptor(id: "data1.trip", byteIndex: 3, byteLength: 2, role: .semantic, unit: "km", sentinelRule: .exact(0xFF)),
            PTXP400FieldDescriptor(id: "data1.odometer", byteIndex: 5, byteLength: 3, role: .semantic, unit: "km", sentinelRule: .allFF)
        ]
    )

    public static let data2 = PTXP400FrameSchema(
        id: PTXP400BLEProtocol.data2FrameID,
        name: "DATA2",
        payloadLength: 8,
        fields: [
            PTXP400FieldDescriptor(id: "data2.rtc.second", byteIndex: 0, bitMask: 0xFC, role: .clock),
            PTXP400FieldDescriptor(id: "data2.flags.byte0Low2", byteIndex: 0, bitMask: 0x03, role: .candidate),
            PTXP400FieldDescriptor(id: "data2.rtc.minute", byteIndex: 1, bitMask: 0xFC, role: .clock),
            PTXP400FieldDescriptor(id: "data2.engine.statusRaw", byteIndex: 1, bitMask: 0x03, role: .provisional, sentinelRule: .exact(0xFF)),
            PTXP400FieldDescriptor(id: "data2.rtc.hour", byteIndex: 2, bitMask: 0xF8, role: .clock),
            PTXP400FieldDescriptor(id: "data2.flags.byte2Low3", byteIndex: 2, bitMask: 0x07, role: .candidate),
            PTXP400FieldDescriptor(id: "data2.maintenance", byteIndex: 3, role: .provisional, unit: "km", sentinelRule: .exact(0xFF)),
            PTXP400FieldDescriptor(id: "data2.outsideTemperature", byteIndex: 4, role: .semantic, unit: "°C", sentinelRule: .exact(0xFF)),
            PTXP400FieldDescriptor(id: "data2.battery", byteIndex: 5, role: .semantic, unit: "V", sentinelRule: .exact(0xFF)),
            PTXP400FieldDescriptor(id: "data2.reserved6", byteIndex: 6, role: .reserved, sentinelRule: .exact(0xFF)),
            PTXP400FieldDescriptor(id: "data2.reserved7", byteIndex: 7, role: .reserved, sentinelRule: .exact(0xFF))
        ]
    )

    public static let data3 = PTXP400FrameSchema(
        id: PTXP400BLEProtocol.data3FrameID,
        name: "DATA3",
        payloadLength: 8,
        fields: [
            PTXP400FieldDescriptor(id: "data3.autonomy", byteIndex: 0, byteLength: 2, role: .semantic, unit: "km", sentinelRule: .allFF),
            PTXP400FieldDescriptor(id: "data3.configurationFlagsA", byteIndex: 2, role: .candidate, sentinelRule: .exact(0xFF)),
            PTXP400FieldDescriptor(id: "data3.maintenance", byteIndex: 3, byteLength: 2, role: .provisional, unit: "km", sentinelRule: .allFF),
            PTXP400FieldDescriptor(id: "data3.language", byteIndex: 5, role: .provisional, sentinelRule: .exact(0xFF)),
            PTXP400FieldDescriptor(id: "data3.configurationCandidate6", byteIndex: 6, role: .candidate, sentinelRule: .exact(0xFF)),
            PTXP400FieldDescriptor(id: "data3.configurationCandidate7", byteIndex: 7, role: .candidate, sentinelRule: .exact(0xFF))
        ]
    )

    public static let control = PTXP400FrameSchema(
        id: PTXP400BLEProtocol.controlFrameID,
        name: "CONTROL",
        payloadLength: 8,
        fields: [
            PTXP400FieldDescriptor(id: "control.rollingTick", byteIndex: 0, role: .counter),
            PTXP400FieldDescriptor(id: "control.turnBits", byteIndex: 1, bitMask: 0x50, role: .flags),
            PTXP400FieldDescriptor(id: "control.lightFlags", byteIndex: 2, bitMask: 0x51, role: .flags),
            PTXP400FieldDescriptor(id: "control.hazardCandidateBit2", byteIndex: 2, bitMask: 0x04, role: .candidate),
            PTXP400FieldDescriptor(id: "control.tcsMode", byteIndex: 3, bitMask: 0x0F, role: .semantic),
            PTXP400FieldDescriptor(id: "control.tcsStatusCandidateBit7", byteIndex: 3, bitMask: 0x80, role: .candidate),
            PTXP400FieldDescriptor(id: "control.rpm", byteIndex: 4, byteLength: 2, role: .semantic, unit: "rpm", sentinelRule: .allFF),
            PTXP400FieldDescriptor(id: "control.rearSpeed", byteIndex: 6, byteLength: 2, role: .semantic, unit: "km/h", sentinelRule: .allFF)
        ]
    )

    public static let abs = PTXP400FrameSchema(
        id: PTXP400BLEProtocol.absFrameID,
        name: "ABS",
        payloadLength: 8,
        fields: [
            PTXP400FieldDescriptor(id: "abs.frontSpeed", byteIndex: 0, byteLength: 2, role: .semantic, unit: "km/h", sentinelRule: .allFF),
            PTXP400FieldDescriptor(id: "abs.statusCandidate", byteIndex: 2, role: .candidate, sentinelRule: .exact(0xFF)),
            PTXP400FieldDescriptor(id: "abs.padding3to7", byteIndex: 3, role: .padding, sentinelRule: .allFF)
        ]
    )

    public static let all: [PTXP400FrameSchema] = [connection, data1, data2, data3, control, abs]

    public static func schema(for id: UInt8) -> PTXP400FrameSchema? {
        all.first { $0.id == id }
    }

    // EN: Known masks show only documented or explicitly provisional bits; candidates and reserved bytes stay unknown.
    // ES: Las máscaras conocidas muestran solo bits documentados o provisionales; candidatos y reservados quedan desconocidos.
    // 中文：已知掩码只显示文档或明确标记为临时语义的位，候选和保留字节仍保持未知。
    public func knownMask(for payload: Data) -> Data {
        var mask = Array(repeating: UInt8(0), count: payload.count)
        let knownRoles: Set<PTXP400SemanticFieldRole> = [.semantic, .provisional, .counter, .clock, .flags, .sentinel, .padding]
        for descriptor in fields where knownRoles.contains(descriptor.role) {
            guard descriptor.byteIndex < mask.count else { continue }
            let end = min(descriptor.byteIndex + descriptor.byteLength, mask.count)
            for index in descriptor.byteIndex..<end {
                mask[index] |= descriptor.bitMask
            }
        }
        return Data(mask)
    }

    public func unknownMask(for payload: Data) -> Data {
        let known = knownMask(for: payload)
        return Data(zip(payload, known).map { $0 & ~$1 })
    }
}

// EN: Frame Inspector exposes byte-level provenance without turning an unknown bit into a semantic claim.
// ES: Frame Inspector expone la procedencia por byte sin convertir un bit desconocido en una afirmación semántica.
// 中文：Frame Inspector 提供逐字节来源信息，不会把未知位变成语义结论。
public nonisolated struct PTXP400FrameInspectorByte: Codable, Equatable, Sendable, Identifiable {
    public let index: Int
    public let rawValue: UInt8
    public let knownMask: UInt8
    public let unknownMask: UInt8
    public let fieldIDs: [String]
    public let roles: [PTXP400SemanticFieldRole]

    public var id: Int { index }

    public init(index: Int, rawValue: UInt8, knownMask: UInt8, unknownMask: UInt8, fieldIDs: [String], roles: [PTXP400SemanticFieldRole]) {
        self.index = index
        self.rawValue = rawValue
        self.knownMask = knownMask
        self.unknownMask = unknownMask
        self.fieldIDs = fieldIDs
        self.roles = roles
    }
}

public nonisolated struct PTXP400FrameInspection: Codable, Equatable, Sendable {
    public let frameID: UInt8
    public let name: String
    public let payloadHex: String
    public let knownMaskHex: String
    public let unknownMaskHex: String
    public let bytes: [PTXP400FrameInspectorByte]

    public init(frameID: UInt8, name: String, payloadHex: String, knownMaskHex: String, unknownMaskHex: String, bytes: [PTXP400FrameInspectorByte]) {
        self.frameID = frameID
        self.name = name
        self.payloadHex = payloadHex
        self.knownMaskHex = knownMaskHex
        self.unknownMaskHex = unknownMaskHex
        self.bytes = bytes
    }
}

public nonisolated enum PTXP400FrameInspector {
    public static func inspect(frame: PTXP400SemanticFrame) -> PTXP400FrameInspection {
        let schema = PTXP400FrameSchema.schema(for: frame.id)
        let known = schema?.knownMask(for: frame.rawPayload) ?? Data(repeating: 0, count: frame.rawPayload.count)
        let unknown = schema?.unknownMask(for: frame.rawPayload) ?? Data(frame.rawPayload)
        let bytes = frame.rawPayload.enumerated().map { index, value in
            let fields = frame.fields.filter { field in
                schema?.field(field.id).map { descriptor in
                    index >= descriptor.byteIndex && index < descriptor.byteIndex + descriptor.byteLength
                } ?? false
            }
            return PTXP400FrameInspectorByte(
                index: index,
                rawValue: value,
                knownMask: known[index],
                unknownMask: unknown[index],
                fieldIDs: fields.map(\.id),
                roles: fields.map(\.role)
            )
        }
        func hex(_ data: Data) -> String { data.map { String(format: "%02X", $0) }.joined() }
        return PTXP400FrameInspection(
            frameID: frame.id,
            name: frame.name,
            payloadHex: hex(frame.rawPayload),
            knownMaskHex: hex(known),
            unknownMaskHex: hex(unknown),
            bytes: bytes
        )
    }
}

// EN: A semantic frame is a read-only projection; the original payload remains available for replay.
// ES: Una trama semántica es una proyección de solo lectura; la carga original queda disponible para replay.
// 中文：语义帧是只读投影，原始 Payload 仍然保留用于回放。
public nonisolated struct PTXP400SemanticFrame: Codable, Equatable, Sendable, Identifiable {
    public let id: UInt8
    public let name: String
    public let rawPayload: Data
    public let fields: [PTXP400SemanticField]

    public init(id: UInt8, name: String, rawPayload: Data, fields: [PTXP400SemanticField]) {
        self.id = id
        self.name = name
        self.rawPayload = rawPayload
        self.fields = fields
    }

    public var identifier: UInt8 { id }

    public var candidateFields: [PTXP400SemanticField] {
        fields.filter { $0.role == .candidate || $0.role == .unknown }
    }

    public var summary: String {
        let values = fields.compactMap { field -> String? in
            guard let normalizedValue = field.normalizedValue else { return nil }
            return "\(field.id)=\(normalizedValue)"
        }
        return "\(name) " + values.joined(separator: ", ")
    }
}

// EN: Decodes confirmed fields and labels every unresolved byte instead of inventing a value.
// ES: Decodifica los campos confirmados y etiqueta cada byte no resuelto sin inventar valores.
// 中文：解码已确认字段，并为所有未解析字节标记角色，不凭空生成数值。
public nonisolated enum PTXP400SemanticDecoder {
    static func decode(frame: PTXP400TelemetryFrame) -> PTXP400SemanticFrame? {
        decode(frameID: frame.id, payload: frame.payload)
    }

    public static func decode(frameID: UInt8, payload: Data) -> PTXP400SemanticFrame? {
        guard let schema = PTXP400FrameSchema.schema(for: frameID), payload.count == schema.payloadLength else {
            return nil
        }

        switch frameID {
        case PTXP400BLEProtocol.connectionFrameID:
            let value = String(bytes: payload, encoding: .ascii)
            return frame(id: frameID, name: schema.name, payload: payload, fields: [
                make("connection.serial", role: .semantic, raw: payload, normalized: value, unit: nil, quality: value == nil ? .invalid : .confirmed, confidence: value == nil ? 0 : 1)
            ])

        case PTXP400BLEProtocol.data1FrameID:
            let bytes = [UInt8](payload)
            let trip = UInt16(bytes[3]) << 8 | UInt16(bytes[4])
            let odometer = UInt32(bytes[5]) << 16 | UInt32(bytes[6]) << 8 | UInt32(bytes[7])
            return frame(id: frameID, name: schema.name, payload: payload, fields: [
                make("data1.fuel", role: .semantic, raw: Data([bytes[0]]), normalized: bytes[0] == 0xFF ? nil : "\(min(max(Int(round(Double(bytes[0]) * 0.3937)), 0), 100))", unit: "%", quality: bytes[0] == 0xFF ? .unavailable : .confirmed, confidence: bytes[0] == 0xFF ? 0 : 1),
                make("data1.fuelRelatedUnknown", role: .candidate, raw: Data([bytes[1]]), normalized: bytes[1] == 0xFF ? nil : "\(bytes[1])", unit: nil, quality: bytes[1] == 0xFF ? .sentinel : .experimental, confidence: bytes[1] == 0xFF ? 0 : 0.3),
                make("data1.averageConsumption", role: .semantic, raw: Data([bytes[2]]), normalized: bytes[2] == 0xFF ? nil : String(format: "%.1f", Double(bytes[2]) * 0.1), unit: "L/100km", quality: bytes[2] == 0xFF ? .unavailable : .confirmed, confidence: bytes[2] == 0xFF ? 0 : 1),
                make("data1.trip", role: .semantic, raw: Data([bytes[3], bytes[4]]), normalized: trip == UInt16.max ? nil : String(format: "%.1f", Double(trip) * 0.1), unit: "km", quality: trip == UInt16.max ? .unavailable : .confirmed, confidence: trip == UInt16.max ? 0 : 1),
                make("data1.odometer", role: .semantic, raw: Data([bytes[5], bytes[6], bytes[7]]), normalized: odometer == 0xFF_FFFF ? nil : String(format: "%.1f", Double(odometer) * 0.1), unit: "km", quality: odometer == 0xFF_FFFF ? .unavailable : .confirmed, confidence: odometer == 0xFF_FFFF ? 0 : 1)
            ])

        case PTXP400BLEProtocol.data2FrameID:
            let bytes = [UInt8](payload)
            let clock = PTDashboardClock(hour: bytes[2] >> 3, minute: bytes[1] >> 2, second: bytes[0] >> 2)
            let clockQuality: PTXP400SemanticQuality = clock.isValid ? .confirmed : .invalid
            let engineUnavailable = bytes[1] == 0xFF
            return frame(id: frameID, name: schema.name, payload: payload, fields: [
                make("data2.rtc.second", role: .clock, raw: Data([bytes[0]]), normalized: clock.isValid ? "\(clock.second)" : nil, unit: "s", quality: clockQuality, confidence: clock.isValid ? 1 : 0),
                make("data2.flags.byte0Low2", role: .candidate, raw: Data([bytes[0] & 0x03]), normalized: "\(bytes[0] & 0x03)", unit: nil, quality: .experimental, confidence: 0.2),
                make("data2.rtc.minute", role: .clock, raw: Data([bytes[1]]), normalized: clock.isValid ? "\(clock.minute)" : nil, unit: "min", quality: clockQuality, confidence: clock.isValid ? 1 : 0),
                make("data2.engine.statusRaw", role: .provisional, raw: Data([bytes[1]]), normalized: engineUnavailable ? nil : "\(bytes[1] & 0x03)", unit: nil, quality: engineUnavailable ? .unavailable : .probable, confidence: engineUnavailable ? 0 : 0.7),
                make("data2.rtc.hour", role: .clock, raw: Data([bytes[2]]), normalized: clock.isValid ? "\(clock.hour)" : nil, unit: "h", quality: clockQuality, confidence: clock.isValid ? 1 : 0),
                make("data2.flags.byte2Low3", role: .candidate, raw: Data([bytes[2] & 0x07]), normalized: "\(bytes[2] & 0x07)", unit: nil, quality: .experimental, confidence: 0.2),
                make("data2.maintenance", role: .provisional, raw: Data([bytes[3]]), normalized: bytes[3] == 0xFF ? nil : "\(bytes[3])", unit: "km", quality: bytes[3] == 0xFF ? .unavailable : .probable, confidence: bytes[3] == 0xFF ? 0 : 0.7),
                make("data2.outsideTemperature", role: .semantic, raw: Data([bytes[4]]), normalized: bytes[4] == 0xFF ? nil : "\(Int(bytes[4]) - 50)", unit: "°C", quality: bytes[4] == 0xFF ? .unavailable : .confirmed, confidence: bytes[4] == 0xFF ? 0 : 1),
                make("data2.battery", role: .semantic, raw: Data([bytes[5]]), normalized: bytes[5] == 0xFF ? nil : String(format: "%.1f", Double(bytes[5]) * 0.1), unit: "V", quality: bytes[5] == 0xFF ? .unavailable : .confirmed, confidence: bytes[5] == 0xFF ? 0 : 1),
                make("data2.reserved6", role: .reserved, raw: Data([bytes[6]]), normalized: nil, unit: nil, quality: bytes[6] == 0xFF ? .sentinel : .experimental, confidence: 0),
                make("data2.reserved7", role: .reserved, raw: Data([bytes[7]]), normalized: nil, unit: nil, quality: bytes[7] == 0xFF ? .sentinel : .experimental, confidence: 0)
            ])

        case PTXP400BLEProtocol.data3FrameID:
            let bytes = [UInt8](payload)
            let autonomy = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
            let maintenance = UInt16(bytes[3]) << 8 | UInt16(bytes[4])
            return frame(id: frameID, name: schema.name, payload: payload, fields: [
                make("data3.autonomy", role: .semantic, raw: Data([bytes[0], bytes[1]]), normalized: autonomy == UInt16.max ? nil : String(format: "%.1f", Double(autonomy) * 0.1), unit: "km", quality: autonomy == UInt16.max ? .unavailable : .confirmed, confidence: autonomy == UInt16.max ? 0 : 1),
                make("data3.configurationFlagsA", role: .candidate, raw: Data([bytes[2]]), normalized: bytes[2] == 0xFF ? nil : "\(bytes[2])", unit: nil, quality: bytes[2] == 0xFF ? .sentinel : .experimental, confidence: bytes[2] == 0xFF ? 0 : 0.3),
                make("data3.maintenance", role: .provisional, raw: Data([bytes[3], bytes[4]]), normalized: maintenance == UInt16.max ? nil : "\(maintenance)", unit: "km", quality: maintenance == UInt16.max ? .unavailable : .probable, confidence: maintenance == UInt16.max ? 0 : 0.7),
                make("data3.language", role: .provisional, raw: Data([bytes[5]]), normalized: bytes[5] == 0xFF ? nil : "\(bytes[5])", unit: nil, quality: bytes[5] == 0xFF ? .sentinel : .experimental, confidence: bytes[5] == 0xFF ? 0 : 0.4),
                make("data3.configurationCandidate6", role: .candidate, raw: Data([bytes[6]]), normalized: bytes[6] == 0xFF ? nil : "\(bytes[6])", unit: nil, quality: bytes[6] == 0xFF ? .sentinel : .experimental, confidence: bytes[6] == 0xFF ? 0 : 0.3),
                make("data3.configurationCandidate7", role: .candidate, raw: Data([bytes[7]]), normalized: bytes[7] == 0xFF ? nil : "\(bytes[7])", unit: nil, quality: bytes[7] == 0xFF ? .sentinel : .experimental, confidence: bytes[7] == 0xFF ? 0 : 0.3)
            ])

        case PTXP400BLEProtocol.controlFrameID:
            let bytes = [UInt8](payload)
            let rpm = UInt16(bytes[4]) << 8 | UInt16(bytes[5])
            let rearSpeed = UInt16(bytes[6]) << 8 | UInt16(bytes[7])
            let tcsRaw = bytes[3] & 0x0F
            return frame(id: frameID, name: schema.name, payload: payload, fields: [
                make("control.rollingTick", role: .counter, raw: Data([bytes[0]]), normalized: "\(bytes[0])", unit: nil, quality: .confirmed, confidence: 1),
                make("control.turnBits", role: .flags, raw: Data([bytes[1] & 0x50]), normalized: "0x\(String(format: "%02X", bytes[1] & 0x50))", unit: nil, quality: .confirmed, confidence: 1),
                make("control.lightFlags", role: .flags, raw: Data([bytes[2] & 0x51]), normalized: "0x\(String(format: "%02X", bytes[2] & 0x51))", unit: nil, quality: .probable, confidence: 0.8),
                make("control.hazardCandidateBit2", role: .candidate, raw: Data([bytes[2] & 0x04]), normalized: "\((bytes[2] & 0x04) >> 2)", unit: nil, quality: .experimental, confidence: 0.2),
                make("control.tcsMode", role: .semantic, raw: Data([tcsRaw]), normalized: "\(tcsRaw)", unit: nil, quality: .probable, confidence: 0.8),
                make("control.tcsStatusCandidateBit7", role: .candidate, raw: Data([bytes[3] & 0x80]), normalized: "\((bytes[3] & 0x80) >> 7)", unit: nil, quality: .experimental, confidence: 0.2),
                make("control.rpm", role: .semantic, raw: Data([bytes[4], bytes[5]]), normalized: rpm == UInt16.max ? nil : "\(Int(Double(rpm) * 0.25))", unit: "rpm", quality: rpm == UInt16.max ? .unavailable : .confirmed, confidence: rpm == UInt16.max ? 0 : 1),
                make("control.rearSpeed", role: .semantic, raw: Data([bytes[6], bytes[7]]), normalized: rearSpeed == UInt16.max ? nil : String(format: "%.2f", Double(rearSpeed) * 0.01), unit: "km/h", quality: rearSpeed == UInt16.max ? .unavailable : .confirmed, confidence: rearSpeed == UInt16.max ? 0 : 1)
            ])

        case PTXP400BLEProtocol.absFrameID:
            let bytes = [UInt8](payload)
            let frontSpeed = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
            let padding = Data(bytes[3...7])
            return frame(id: frameID, name: schema.name, payload: payload, fields: [
                make("abs.frontSpeed", role: .semantic, raw: Data([bytes[0], bytes[1]]), normalized: frontSpeed == UInt16.max ? nil : String(format: "%.2f", Double(frontSpeed) * 0.01), unit: "km/h", quality: frontSpeed == UInt16.max ? .unavailable : .confirmed, confidence: frontSpeed == UInt16.max ? 0 : 1),
                make("abs.statusCandidate", role: .candidate, raw: Data([bytes[2]]), normalized: bytes[2] == 0xFF ? nil : "\(bytes[2])", unit: nil, quality: bytes[2] == 0xFF ? .sentinel : .experimental, confidence: bytes[2] == 0xFF ? 0 : 0.25),
                make("abs.padding3to7", role: .padding, raw: padding, normalized: nil, unit: nil, quality: padding.allSatisfy { $0 == 0xFF } ? .sentinel : .experimental, confidence: 0)
            ])

        default:
            return nil
        }
    }

    private static func frame(id: UInt8, name: String, payload: Data, fields: [PTXP400SemanticField]) -> PTXP400SemanticFrame {
        PTXP400SemanticFrame(id: id, name: name, rawPayload: payload, fields: fields)
    }

    private static func make(
        _ id: String,
        role: PTXP400SemanticFieldRole,
        raw: Data,
        normalized: String?,
        unit: String?,
        quality: PTXP400SemanticQuality,
        confidence: Double
    ) -> PTXP400SemanticField {
        let availability: PTDashboardValueAvailability = quality == .unavailable || quality == .invalid || quality == .sentinel ? .unavailable : .available
        return PTXP400SemanticField(
            id: id,
            role: role,
            raw: raw,
            normalizedValue: normalized,
            unit: unit,
            availability: availability,
            quality: quality,
            confidence: confidence
        )
    }
}

// EN: The anchor records dashboard RTC, rolling tick, host monotonic time, and host wall time without extrapolating a date.
// ES: El ancla registra RTC, contador, tiempo monótono del host y hora civil sin extrapolar una fecha.
// 中文：锚点记录仪表 RTC、滚动计数、主机单调时间和墙上时间，但不擅自推算日期。
public nonisolated struct PTXP400DashboardClockAnchorSample: Codable, Equatable, Sendable {
    public let clock: PTDashboardClock
    public let dashboardTick: UInt8?
    public let monotonicNanoseconds: UInt64
    public let hostDate: Date
    public let tickDelta: Int?
    public let tickPeriodNanoseconds: UInt64?
    public let droppedTickCount: Int
    public let wrapDetected: Bool

    public init(clock: PTDashboardClock, dashboardTick: UInt8?, monotonicNanoseconds: UInt64, hostDate: Date, tickDelta: Int? = nil, tickPeriodNanoseconds: UInt64? = nil, droppedTickCount: Int = 0, wrapDetected: Bool = false) {
        self.clock = clock
        self.dashboardTick = dashboardTick
        self.monotonicNanoseconds = monotonicNanoseconds
        self.hostDate = hostDate
        self.tickDelta = tickDelta
        self.tickPeriodNanoseconds = tickPeriodNanoseconds
        self.droppedTickCount = max(droppedTickCount, 0)
        self.wrapDetected = wrapDetected
    }
}

// EN: Rolling tick arithmetic is modulo 256, so wrap-around is a normal forward transition.
// ES: La aritmética del contador es módulo 256, por lo que el desbordamiento es una transición normal.
// 中文：滚动计数使用 256 取模，因此从 FF 回到 00 属于正常前进。
public nonisolated struct PTXP400RollingTick: Codable, Equatable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public func delta(from previous: PTXP400RollingTick) -> Int {
        Int(rawValue &- previous.rawValue)
    }

    public static func moduloDelta(from previous: UInt8, to current: UInt8) -> Int {
        Int(current &- previous)
    }
}

// EN: This actor serializes clock anchors while keeping transport callbacks non-blocking.
// ES: Este actor serializa las anclas del reloj y mantiene no bloqueadas las callbacks de transporte.
// 中文：该 actor 串行化时钟锚点，同时保证传输回调不被阻塞。
public actor PTXP400DashboardClockAnchor {
    public static let shared = PTXP400DashboardClockAnchor()
    private var latestSample: PTXP400DashboardClockAnchorSample?
    private var previousTick: UInt8?
    private var previousMonotonicNanoseconds: UInt64?

    public init() {}

    public func ingest(
        clock: PTDashboardClock,
        dashboardTick: UInt8?,
        monotonicNanoseconds: UInt64,
        hostDate: Date = Date()
    ) -> PTXP400DashboardClockAnchorSample {
        let tickDelta: Int?
        let tickPeriodNanoseconds: UInt64?
        let droppedTickCount: Int
        let wrapDetected: Bool
        if let previousTick = previousTick, let dashboardTick {
            let delta = PTXP400RollingTick.moduloDelta(from: previousTick, to: dashboardTick)
            tickDelta = delta
            wrapDetected = dashboardTick < previousTick
            if let previousMonotonicNanoseconds, monotonicNanoseconds > previousMonotonicNanoseconds, delta > 0 {
                tickPeriodNanoseconds = (monotonicNanoseconds - previousMonotonicNanoseconds) / UInt64(delta)
            } else {
                tickPeriodNanoseconds = nil
            }
            // EN: A five-count step is the observed nominal cadence; larger integral steps expose dropped frames.
            // ES: Un paso de cinco es la cadencia nominal observada; pasos enteros mayores exponen tramas perdidas.
            // 中文：基于当前观测，5 是名义步长；更大的整数步长用于暴露丢帧。
            droppedTickCount = delta >= 5 && delta.isMultiple(of: 5) ? max(delta / 5 - 1, 0) : 0
        } else {
            tickDelta = nil
            tickPeriodNanoseconds = nil
            droppedTickCount = 0
            wrapDetected = false
        }
        let sample = PTXP400DashboardClockAnchorSample(
            clock: clock,
            dashboardTick: dashboardTick,
            monotonicNanoseconds: monotonicNanoseconds,
            hostDate: hostDate,
            tickDelta: tickDelta,
            tickPeriodNanoseconds: tickPeriodNanoseconds,
            droppedTickCount: droppedTickCount,
            wrapDetected: wrapDetected
        )
        latestSample = sample
        previousTick = dashboardTick
        previousMonotonicNanoseconds = monotonicNanoseconds > 0 ? monotonicNanoseconds : previousMonotonicNanoseconds
        return sample
    }

    public func latest() -> PTXP400DashboardClockAnchorSample? {
        latestSample
    }

    public func reset() {
        latestSample = nil
        previousTick = nil
        previousMonotonicNanoseconds = nil
    }
}

// EN: Classifies the one-byte status poll before the framed-envelope validator runs.
// ES: Clasifica el sondeo de estado de un byte antes de validar la envoltura enmarcada.
// 中文：在包络校验前先识别单字节状态轮询。
public nonisolated enum PTXP400OutboundPacketKind: String, Codable, Sendable {
    case statusPoll
    case knownFramed
    case unknownFramed
    case malformed
}

public nonisolated enum PTXP400OutboundPacketClassifier {
    public static let statusPoll = PTXP400BLEProtocol.statusPollCommand

    public static func classify(_ data: Data) -> PTXP400OutboundPacketKind {
        if data == statusPoll { return .statusPoll }
        guard PTXP400BLEProtocol.isValidOutboundFrame(data) else { return .malformed }
        let id = data.count > 1 ? data[1] : 0
        switch id {
        case PTXP400BLEProtocol.navigationFrameID,
             PTXP400BLEProtocol.configurationFrameID,
             0x08:
            return .knownFramed
        default:
            return .unknownFramed
        }
    }
}
