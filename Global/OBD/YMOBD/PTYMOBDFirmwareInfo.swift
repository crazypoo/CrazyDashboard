//
//  PTYMOBDFirmwareInfo.swift
//  CrazyDashboard
//
//  EN: Read-only YMOBD firmware metadata and version models.
//  ES: Modelos de metadatos y versiones de firmware YMOBD de solo lectura.
//  中文：只读 YMOBD 固件元数据与版本模型。
//

import Foundation

public enum PTYMOBDProtocolTypeResolver {
    // EN: YMOBD v2.1 uses protocol type 7; other adapters use the documented type 9.
    // ES: YMOBD v2.1 usa el tipo de protocolo 7; los demás adaptadores usan el tipo 9 documentado.
    // 中文：YMOBD v2.1 使用协议类型 7，其余适配器使用文档规定的类型 9。
    public static func resolve(atiResponse: String) -> Int {
        atiResponse.localizedCaseInsensitiveContains("v2.1") ? 7 : 9
    }
}

public struct PTYMOBDFirmwareCheckRequest: Codable, Equatable, Sendable {
    public let deviceType: String
    public let protocolType: Int
    public let obdFirmwareVersion: String

    public init(deviceType: String, protocolType: Int, obdFirmwareVersion: String) {
        self.deviceType = deviceType.trimmingCharacters(in: .whitespacesAndNewlines)
        self.protocolType = protocolType
        self.obdFirmwareVersion = obdFirmwareVersion.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var isValid: Bool {
        !deviceType.isEmpty
            && (protocolType == 7 || protocolType == 9)
            && !obdFirmwareVersion.isEmpty
    }
}

public struct PTYMOBDFirmwareMetadata: Codable, Equatable, Sendable {
    public let firmwareVersion: String
    public let firmwareDescription: String
    public let firmwareFileUUID: String
    public let publicKeyVersion: Int?
    public let fileSize: Int?
    public let declaredSHA256: String?

    public init(
        firmwareVersion: String,
        firmwareDescription: String = "",
        firmwareFileUUID: String,
        publicKeyVersion: Int? = nil,
        fileSize: Int? = nil,
        declaredSHA256: String? = nil
    ) {
        self.firmwareVersion = firmwareVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        self.firmwareDescription = firmwareDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        self.firmwareFileUUID = firmwareFileUUID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.publicKeyVersion = publicKeyVersion
        self.fileSize = fileSize
        self.declaredSHA256 = declaredSHA256?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    public var isDownloadable: Bool {
        !firmwareVersion.isEmpty && !firmwareFileUUID.isEmpty
    }
}

public enum PTYMOBDFirmwareResponseError: Error, Equatable, LocalizedError, Sendable {
    case invalidJSON
    case metadataMissing

    public var errorDescription: String? {
        switch self {
        case .invalidJSON:
            return "固件服务返回的 JSON 无效"
        case .metadataMissing:
            return "固件服务返回中缺少版本或文件标识"
        }
    }
}

public enum PTYMOBDFirmwareResponseDecoder {
    // EN: Decode both flat and nested server envelopes without binding the app to one backend wrapper.
    // ES: Decodifica respuestas planas y anidadas sin acoplar la app a un único envoltorio del servidor.
    // 中文：同时解析扁平和嵌套服务响应，避免把 App 绑定到单一种服务包装结构。
    public static func decodeMetadata(from data: Data) throws -> PTYMOBDFirmwareMetadata {
        let root: Any
        do {
            root = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw PTYMOBDFirmwareResponseError.invalidJSON
        }

        var pending: [(Any, Int)] = [(root, 0)]
        while let (value, depth) = pending.popLast() {
            guard depth <= 5 else { continue }

            if let dictionary = value as? [String: Any] {
                let normalized = Dictionary(
                    dictionary.map { (normalizeKey($0.key), $0.value) },
                    uniquingKeysWith: { first, _ in first }
                )

                let version = stringValue(normalized["firmwareversion"])
                    ?? stringValue(normalized["version"])
                let fileUUID = stringValue(normalized["firmwarefileuuid"])
                    ?? stringValue(normalized["firmwarefileid"])
                    ?? stringValue(normalized["fileuuid"])
                    ?? stringValue(normalized["uuid"])

                if let version, let fileUUID, !version.isEmpty, !fileUUID.isEmpty {
                    return PTYMOBDFirmwareMetadata(
                        firmwareVersion: version,
                        firmwareDescription: stringValue(normalized["firmwaredesc"])
                            ?? stringValue(normalized["firmwaredescription"])
                            ?? stringValue(normalized["description"])
                            ?? "",
                        firmwareFileUUID: fileUUID,
                        publicKeyVersion: integerValue(normalized["pubkeyver"])
                            ?? integerValue(normalized["publickeyversion"]),
                        fileSize: integerValue(normalized["filesize"])
                            ?? integerValue(normalized["firmwaresize"]),
                        declaredSHA256: stringValue(normalized["sha256"])
                            ?? stringValue(normalized["firmwaresizehash"])
                    )
                }

                for child in dictionary.values {
                    if child is [String: Any] || child is [Any] {
                        pending.append((child, depth + 1))
                    }
                }
            } else if let array = value as? [Any] {
                for child in array where child is [String: Any] || child is [Any] {
                    pending.append((child, depth + 1))
                }
            }
        }

        throw PTYMOBDFirmwareResponseError.metadataMissing
    }
}

public struct PTYMOBDFirmwareCheckResult: Equatable, Sendable {
    public let request: PTYMOBDFirmwareCheckRequest
    public let metadata: PTYMOBDFirmwareMetadata

    public init(request: PTYMOBDFirmwareCheckRequest, metadata: PTYMOBDFirmwareMetadata) {
        self.request = request
        self.metadata = metadata
    }

    public var isUpdateAvailable: Bool {
        PTYMOBDFirmwareVersionComparator.isNewer(
            metadata.firmwareVersion,
            than: request.obdFirmwareVersion
        )
    }
}

public enum PTYMOBDFirmwareVersionComparator {
    // EN: Compare numeric version components so V1.2 and 1.2.0 are treated as equal.
    // ES: Compara componentes numéricos para que V1.2 y 1.2.0 se consideren iguales.
    // 中文：比较版本中的数字组件，让 V1.2 与 1.2.0 视为相同版本。
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let candidateParts = numericParts(candidate)
        let currentParts = numericParts(current)

        if !candidateParts.isEmpty || !currentParts.isEmpty {
            let count = max(candidateParts.count, currentParts.count)
            for index in 0..<count {
                let candidateValue = index < candidateParts.count ? candidateParts[index] : 0
                let currentValue = index < currentParts.count ? currentParts[index] : 0
                if candidateValue != currentValue {
                    return candidateValue > currentValue
                }
            }
            return false
        }

        let normalizedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let normalizedCurrent = current.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return normalizedCandidate > normalizedCurrent
    }

    private static func numericParts(_ value: String) -> [Int] {
        var parts: [Int] = []
        var buffer = ""

        func flush() {
            if let number = Int(buffer) {
                parts.append(number)
            }
            buffer.removeAll(keepingCapacity: true)
        }

        for scalar in value.unicodeScalars {
            if CharacterSet.decimalDigits.contains(scalar) {
                buffer.unicodeScalars.append(scalar)
            } else {
                flush()
            }
        }
        flush()
        return parts
    }
}

public struct PTYMOBDFirmwareTransferReport: Codable, Equatable, Sendable {
    public let firmwareVersion: String
    public let firmwareFileUUID: String
    public let encryptedByteCount: Int
    public let encryptedSHA256: String
    public let decryptedByteCount: Int
    public let decryptedSHA256: String
    public let publicKeyVersion: Int
    public let publicKeyFingerprint: String
    public let generatedAt: Date

    public init(
        firmwareVersion: String,
        firmwareFileUUID: String,
        encryptedByteCount: Int,
        encryptedSHA256: String,
        decryptedByteCount: Int,
        decryptedSHA256: String,
        publicKeyVersion: Int,
        publicKeyFingerprint: String,
        generatedAt: Date = Date()
    ) {
        self.firmwareVersion = firmwareVersion
        self.firmwareFileUUID = firmwareFileUUID
        self.encryptedByteCount = encryptedByteCount
        self.encryptedSHA256 = encryptedSHA256.uppercased()
        self.decryptedByteCount = decryptedByteCount
        self.decryptedSHA256 = decryptedSHA256.uppercased()
        self.publicKeyVersion = publicKeyVersion
        self.publicKeyFingerprint = publicKeyFingerprint.lowercased()
        self.generatedAt = generatedAt
    }
}

// EN: Keep decrypted bytes in memory for the next verified integration step, never in a persisted session.
// ES: Mantiene los bytes descifrados en memoria para la siguiente integración verificada, nunca en una sesión persistida.
// 中文：解密后的字节只保留在内存中供后续验证接入使用，不写入持久化会话。
public struct PTYMOBDFirmwareReadOnlyResult: Sendable {
    public let checkResult: PTYMOBDFirmwareCheckResult
    public let secret: PTYMOBDFirmwareSecret
    public let decryptedFirmware: Data
    public let report: PTYMOBDFirmwareTransferReport

    public init(
        checkResult: PTYMOBDFirmwareCheckResult,
        secret: PTYMOBDFirmwareSecret,
        decryptedFirmware: Data,
        report: PTYMOBDFirmwareTransferReport
    ) {
        self.checkResult = checkResult
        self.secret = secret
        self.decryptedFirmware = decryptedFirmware
        self.report = report
    }
}

private extension PTYMOBDFirmwareResponseDecoder {
    static func normalizeKey(_ key: String) -> String {
        key.lowercased().filter { $0 != " " && $0 != "_" && $0 != "-" }
    }

    static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    static func integerValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let string = stringValue(value) { return Int(string) }
        return nil
    }
}
