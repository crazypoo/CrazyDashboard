// EN: Parse optional YMOBD metadata without changing the generic ELM327 transport.
// ES: Analiza metadatos YMOBD opcionales sin cambiar el transporte ELM327 genérico.
// 中文：解析可选的 YMOBD 元数据，不改变通用 ELM327 传输层。

import Foundation

nonisolated public struct PTYMOBDVersionInfo: Equatable, Sendable {
    public let company: String
    public let version: String
    public let deviceType: String
    public let deviceName: String
    public let deviceMac: String
    public let interfaceName: String
    public let customerID: String
    public let crypt: String

    // EN: YMOBD is identified only by its device-specific fields, never by a version string alone.
    // ES: YMOBD se identifica solo por sus campos específicos del dispositivo, nunca solo por la versión.
    // 中文：只有出现设备专属字段才认定为 YMOBD，单独的版本号不能作为依据。
    public let isYMOBD: Bool

    public init(
        company: String = "",
        version: String = "",
        deviceType: String = "",
        deviceName: String = "",
        deviceMac: String = "",
        interfaceName: String = "",
        customerID: String = "",
        crypt: String = "",
        isYMOBD: Bool = false
    ) {
        self.company = company
        self.version = version
        self.deviceType = deviceType
        self.deviceName = deviceName
        self.deviceMac = deviceMac
        self.interfaceName = interfaceName
        self.customerID = customerID
        self.crypt = crypt
        self.isYMOBD = isYMOBD
    }
}

nonisolated public struct PTYMOBDVersionParser: Sendable {
    public init() {}

    public func parse(_ response: String) -> PTYMOBDVersionInfo {
        let lines = response
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let company = lines.first { !$0.uppercased().hasPrefix("AT+VERSION") } ?? ""
        var version = ""
        var deviceType = ""
        var deviceName = ""
        var deviceMac = ""
        var interfaceName = ""
        var customerID = ""
        var crypt = ""
        var isYMOBD = false

        for line in lines {
            guard let separator = line.firstIndex(where: { $0 == ":" || $0 == "=" }) else { continue }

            let rawKey = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
            let valueStart = line.index(after: separator)
            let value = String(line[valueStart...]).trimmingCharacters(in: .whitespaces)

            switch normalizeKey(rawKey) {
            case "version":
                version = value
            case "devicetype":
                isYMOBD = true
                deviceType = value
            case "devicename":
                isYMOBD = true
                deviceName = value
            case "devicemac":
                isYMOBD = true
                deviceMac = value.uppercased()
            case "interface", "interfase":
                isYMOBD = true
                interfaceName = value
            case "custid":
                isYMOBD = true
                customerID = value
            case "crypt":
                isYMOBD = true
                let rawCrypt = value.lowercased().hasPrefix("0x") ? String(value.dropFirst(2)) : value
                let normalizedCrypt = rawCrypt.filter { "0123456789abcdefABCDEF".contains($0) }.uppercased()
                crypt = normalizedCrypt.count <= 8 ? normalizedCrypt : ""
            default:
                continue
            }
        }

        return PTYMOBDVersionInfo(
            company: company,
            version: version,
            deviceType: deviceType,
            deviceName: deviceName,
            deviceMac: deviceMac,
            interfaceName: interfaceName,
            customerID: customerID,
            crypt: crypt,
            isYMOBD: isYMOBD
        )
    }

    private func normalizeKey(_ key: String) -> String {
        key.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
