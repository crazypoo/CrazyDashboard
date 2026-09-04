//
//  PTXP400BLEInboundReassembler.swift
//  CrazyDashboard
//
//  EN: Reassembles XP400 vehicle-to-iPhone TIO writes without owning transport state.
//  ES: Reensambla las escrituras TIO del vehículo al iPhone sin apropiarse del estado de transporte.
//  中文：重组 XP400 从仪表到 iPhone 的 TIO 写入数据，但不接管传输状态。
//

import Foundation

/// EN: The logical packet shape expected by each authentication or data phase.
/// ES: La forma lógica de paquete esperada por cada fase de autenticación o datos.
/// 中文：每个认证或数据阶段所期待的逻辑数据包类型。
public enum PTXP400BLEInboundPhase: Equatable, Sendable {
    case keyConfiguration
    case authenticationResponse
    case randomChallenge
    case connectionFrame
    case vehicleStatus
}

/// EN: A small state-aware assembler for writes that may be split, merged, duplicated, or malformed.
/// ES: Un ensamblador pequeño y consciente del estado para escrituras divididas, combinadas, duplicadas o malformadas.
/// 中文：一个按状态识别分片、合并、重复和非法写入的小型重组器。
public struct PTXP400BLEInboundReassembler: Sendable {
    /// EN: The caller should continue draining after `.dropped`; `.waiting` means more bytes are required.
    /// ES: El llamador debe seguir drenando después de `.dropped`; `.waiting` significa que faltan bytes.
    /// 中文：调用方收到 `.dropped` 后应继续排空，`.waiting` 表示还需要更多字节。
    public enum Result: Equatable, Sendable {
        case frame(Data)
        case dropped
        case waiting
    }

    private static let maximumBufferLength = 512
    private static let authenticationKeyBytes: [UInt8] = [0x00, 0x00, 0x22, 0x36]

    private var buffer = Data()
    private var lastDeliveredPhase: PTXP400BLEInboundPhase?
    private var lastDeliveredFrame: Data?

    public init() {}

    /// EN: The number of bytes waiting for a complete logical packet.
    /// ES: El número de bytes que esperan un paquete lógico completo.
    /// 中文：当前等待组成完整逻辑数据包的字节数。
    public var bufferedByteCount: Int {
        buffer.count
    }

    /// EN: Append one CoreBluetooth write and cap memory used by untrusted input.
    /// ES: Añade una escritura de CoreBluetooth y limita la memoria usada por datos no confiables.
    /// 中文：追加一次 CoreBluetooth 写入，并限制不可信输入占用的内存。
    public mutating func append(_ data: Data) {
        guard !data.isEmpty else { return }

        buffer.append(data)
        guard buffer.count > Self.maximumBufferLength else { return }

        let start = buffer.count - Self.maximumBufferLength
        buffer = buffer.subdata(in: start..<buffer.count)
    }

    /// EN: Drop partial data and duplicate history when a TIO session is restarted.
    /// ES: Descarta datos parciales y el historial de duplicados cuando se reinicia una sesión TIO.
    /// 中文：TIO 会话重启时清除残留分片和重复帧历史。
    public mutating func reset() {
        buffer.removeAll(keepingCapacity: true)
        lastDeliveredPhase = nil
        lastDeliveredFrame = nil
    }

    /// EN: Return one frame, one discarded candidate, or a request for more bytes.
    /// ES: Devuelve una trama, un candidato descartado o una solicitud de más bytes.
    /// 中文：返回一个完整帧、一个被丢弃的候选包，或等待更多字节。
    public mutating func nextFrame(for phase: PTXP400BLEInboundPhase) -> Result {
        guard !buffer.isEmpty else { return .waiting }

        // EN: Remove a complete duplicate from the immediately preceding handshake phase before length parsing.
        // ES: Elimina un duplicado completo de la fase de handshake inmediatamente anterior antes de analizar la longitud.
        // 中文：在按长度解析前，先丢弃紧邻前一个认证阶段的完整重复帧。
        if discardPreviousPhaseDuplicate(for: phase) {
            return .dropped
        }

        switch phase {
        case .keyConfiguration:
            return nextKeyConfigurationFrame()
        case .authenticationResponse, .randomChallenge:
            return nextRawTwentyByteFrame(for: phase)
        case .connectionFrame:
            return nextConnectionFrame()
        case .vehicleStatus:
            return nextVehicleStatusFrame()
        }
    }

    private mutating func nextKeyConfigurationFrame() -> Result {
        let marker = Self.authenticationKeyBytes

        if buffer.count < marker.count {
            guard buffer.elementsEqual(marker.prefix(buffer.count)) else {
                return resynchronizeToKeyMarker(marker)
            }
            return .waiting
        }

        guard buffer.starts(with: marker) else {
            return resynchronizeToKeyMarker(marker)
        }

        // EN: The vehicle's key/configuration packet is fixed at 15 bytes and has no generic length envelope.
        // ES: El paquete de clave/configuración del vehículo tiene 15 bytes fijos y no usa una envoltura genérica de longitud.
        // 中文：仪表的 Key/Configuration 包固定为 15 字节，不使用通用长度封装。
        guard buffer.count >= PTXP400BLEProtocol.authenticationKeyConfigurationFrameLength else {
            return .waiting
        }

        return deliver(
            Data(buffer.prefix(PTXP400BLEProtocol.authenticationKeyConfigurationFrameLength)),
            phase: .keyConfiguration
        )
    }

    private mutating func nextRawTwentyByteFrame(for phase: PTXP400BLEInboundPhase) -> Result {
        // EN: ponytail: Raw 20-byte authentication packets have no wire delimiter, so this phase can only use exact length boundaries.
        // ES: ponytail: Los paquetes de autenticación de 20 bytes no tienen delimitador de cable, por lo que esta fase solo puede usar límites de longitud exactos.
        // 中文：ponytail：原始 20 字节认证包没有线协议分隔符，因此此阶段只能依赖严格的长度边界。
        guard buffer.count >= PTXP400BLEProtocol.authenticationChallengeLength else { return .waiting }
        return deliver(Data(buffer.prefix(PTXP400BLEProtocol.authenticationChallengeLength)), phase: phase)
    }

    private mutating func nextConnectionFrame() -> Result {
        if let alignmentResult = alignToPreamble() {
            return alignmentResult
        }

        guard buffer.count >= PTXP400BLEProtocol.connectionFrameLength else {
            return .waiting
        }

        let candidate = Data(buffer.prefix(PTXP400BLEProtocol.connectionFrameLength))
        guard PTXP400BLEProtocol.connectionSerial(in: candidate) != nil else {
            return resynchronizeAfterInvalidFramedCandidate()
        }

        return deliver(candidate, phase: .connectionFrame)
    }

    private mutating func nextVehicleStatusFrame() -> Result {
        if let alignmentResult = alignToPreamble() {
            return alignmentResult
        }

        let bytes = [UInt8](buffer)
        guard bytes.count >= 2 else { return .waiting }

        let frameLength: Int
        switch bytes[1] {
        case PTXP400BLEProtocol.connectionFrameID:
            // EN: Keep post-authentication connection/heartbeat frames compatible with the existing dashboard parser.
            // ES: Mantén compatibles las tramas de conexión/latido posteriores a la autenticación con el analizador actual.
            // 中文：认证后的连接/心跳帧继续兼容现有仪表解析器。
            frameLength = PTXP400BLEProtocol.connectionFrameLength
        case PTXP400BLEProtocol.data1FrameID...PTXP400BLEProtocol.absFrameID:
            frameLength = PTXP400BLEProtocol.vehicleStatusFrameLength
        default:
            return resynchronizeAfterInvalidFramedCandidate()
        }

        guard buffer.count >= frameLength else { return .waiting }

        let candidate = Data(buffer.prefix(frameLength))
        let isValid = frameLength == PTXP400BLEProtocol.connectionFrameLength
            ? PTXP400BLEProtocol.connectionSerial(in: candidate) != nil
            : PTXP400BLEProtocol.isVehicleStatusFrame(candidate)

        guard isValid else {
            return resynchronizeAfterInvalidFramedCandidate()
        }

        return deliver(candidate, phase: .vehicleStatus)
    }

    private mutating func discardPreviousPhaseDuplicate(for phase: PTXP400BLEInboundPhase) -> Bool {
        guard previousPhase(for: phase) == lastDeliveredPhase,
              let lastDeliveredFrame,
              buffer.count >= lastDeliveredFrame.count,
              buffer.prefix(lastDeliveredFrame.count).elementsEqual(lastDeliveredFrame) else {
            return false
        }

        buffer.removeFirst(lastDeliveredFrame.count)
        return true
    }

    private func previousPhase(for phase: PTXP400BLEInboundPhase) -> PTXP400BLEInboundPhase? {
        switch phase {
        case .keyConfiguration:
            return nil
        case .authenticationResponse:
            return .keyConfiguration
        case .randomChallenge:
            return .authenticationResponse
        case .connectionFrame:
            return .randomChallenge
        case .vehicleStatus:
            return .connectionFrame
        }
    }

    private mutating func deliver(_ frame: Data, phase: PTXP400BLEInboundPhase) -> Result {
        guard !frame.isEmpty, buffer.count >= frame.count else { return .waiting }

        buffer.removeFirst(frame.count)
        lastDeliveredPhase = phase
        lastDeliveredFrame = frame
        return .frame(frame)
    }

    private mutating func resynchronizeToKeyMarker(_ marker: [UInt8]) -> Result {
        if let offset = firstIndex(of: marker) {
            buffer.removeFirst(offset)
            return .dropped
        }

        let bytes = [UInt8](buffer)
        let keepCount = longestSuffixPrefixLength(bytes, matching: marker)
        let dropCount = buffer.count - keepCount
        guard dropCount > 0 else { return .waiting }

        buffer.removeFirst(dropCount)
        return .dropped
    }

    private mutating func alignToPreamble() -> Result? {
        guard buffer.first != PTXP400BLEProtocol.preamble else { return nil }

        if let offset = firstByteIndex(PTXP400BLEProtocol.preamble, startingAt: 1) {
            buffer.removeFirst(offset)
        } else if buffer.last == PTXP400BLEProtocol.preamble {
            buffer = Data([PTXP400BLEProtocol.preamble])
        } else {
            buffer.removeAll(keepingCapacity: true)
        }

        return .dropped
    }

    private mutating func resynchronizeAfterInvalidFramedCandidate() -> Result {
        if let offset = firstByteIndex(PTXP400BLEProtocol.preamble, startingAt: 1) {
            buffer.removeFirst(offset)
        } else if buffer.last == PTXP400BLEProtocol.preamble {
            buffer = Data([PTXP400BLEProtocol.preamble])
        } else {
            buffer.removeAll(keepingCapacity: true)
        }

        return .dropped
    }

    private func firstIndex(of pattern: [UInt8]) -> Int? {
        let bytes = [UInt8](buffer)
        guard !pattern.isEmpty, bytes.count >= pattern.count else { return nil }

        let lastStart = bytes.count - pattern.count
        for index in 0...lastStart where bytes[index..<(index + pattern.count)].elementsEqual(pattern) {
            return index
        }
        return nil
    }

    private func firstByteIndex(_ byte: UInt8, startingAt start: Int) -> Int? {
        let bytes = [UInt8](buffer)
        guard start >= 0, start < bytes.count else { return nil }

        for index in start..<bytes.count where bytes[index] == byte {
            return index
        }
        return nil
    }

    private func longestSuffixPrefixLength(_ bytes: [UInt8], matching pattern: [UInt8]) -> Int {
        guard pattern.count > 1 else { return 0 }

        let maximumLength = min(bytes.count, pattern.count - 1)
        guard maximumLength > 0 else { return 0 }

        for length in stride(from: maximumLength, through: 1, by: -1) {
            if bytes.suffix(length).elementsEqual(pattern.prefix(length)) {
                return length
            }
        }
        return 0
    }
}
