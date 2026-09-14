//
//  PTYMOBDVendorExtension.swift
//  PTSpeed
//
//  EN: Adds YMOBD probing and management to the shared ELM327 session.
//  ES: Añade detección y gestión YMOBD a la sesión ELM327 compartida.
//  中文：在共享 ELM327 会话上增加 YMOBD 探测和管理能力。
//

import Foundation

@MainActor
public final class PTYMOBDVendorExtension: PTELM327VendorExtension {
    public let identifier = "ymobd"

    public private(set) var versionInfo = PTYMOBDVersionInfo()
    public private(set) var capabilities = PTYMOBDCapabilities.unavailable
    public private(set) var latestFirmwareCheck: PTYMOBDFirmwareCheckResult?

    private let versionParser = PTYMOBDVersionParser()
    private let authenticator = PTYMOBDAuthenticator()

    public init() {}

    public func probe(session: PTELM327Session) async throws -> Bool {
        let response = try await session.execute(
            "AT+VERSION",
            priority: .high,
            classification: PTOBDCommandClassifierV2.classify("AT+VERSION"),
            extensionIdentifier: identifier
        )
        let parsed = versionParser.parse(response.raw)
        guard parsed.isYMOBD else {
            versionInfo = parsed
            capabilities = .unavailable
            await session.setVendorCapabilities(nil)
            return false
        }

        versionInfo = parsed
        var isOfficial = false
        if let auth = authenticator.makeAuthCommand(versionInfo: parsed) {
            let authResponse = try await session.execute(
                auth.command,
                priority: .high,
                classification: PTOBDCommandClassifierV2.classify(auth.command),
                extensionIdentifier: identifier
            )
            isOfficial = authenticator.verify(
                command: auth.command,
                response: authResponse.raw,
                challenge: auth.challenge
            )
        }

        let deviceType = parsed.deviceType.isEmpty ? parsed.deviceName : parsed.deviceType
        capabilities = PTYMOBDCapabilities(
            isOfficial: isOfficial,
            deviceType: deviceType.isEmpty ? nil : deviceType,
            supportsFirmwareCheck: isOfficial && !deviceType.isEmpty && !parsed.version.isEmpty,
            supportsFirmwareDownload: isOfficial && !deviceType.isEmpty && !parsed.version.isEmpty,
            supportsJieliOTA: isOfficial
        )
        await session.setVendorCapabilities(capabilities)
        return true
    }

    // EN: Keep the existing 19-step order as a data contract; execution stays in the shared ELM core.
    // ES: Conserva el orden existente de 19 pasos como contrato de datos; la ejecución queda en el núcleo ELM compartido.
    // 中文：保留现有 19 步顺序作为数据契约，具体执行仍由共享 ELM 核心负责。
    public var initializationCommands: [String] {
        PTYMOBDInitializer.defaultCommandQueue
    }

    public func checkLatestFirmware(
        using api: PTYMOBDFirmwareAPI,
        session: PTELM327Session
    ) async throws -> PTYMOBDFirmwareCheckResult {
        guard capabilities.supportsFirmwareCheck else {
            throw PTYMOBDFirmwareServiceError.notYMOBD
        }

        let atiResponse = try await session.execute(
            "ATI",
            priority: .high,
            classification: PTOBDCommandClassifierV2.classify("ATI"),
            extensionIdentifier: identifier
        )
        let deviceType = versionInfo.deviceType.isEmpty ? versionInfo.deviceName : versionInfo.deviceType
        guard !deviceType.isEmpty, !versionInfo.version.isEmpty else {
            throw PTYMOBDFirmwareServiceError.deviceTypeMissing
        }

        let request = PTYMOBDFirmwareCheckRequest(
            deviceType: deviceType,
            protocolType: PTYMOBDProtocolTypeResolver.resolve(atiResponse: atiResponse.raw),
            obdFirmwareVersion: versionInfo.version
        )
        let result = try await api.checkLatestFirmware(for: request)
        latestFirmwareCheck = result
        return result
    }

    public func prepareReadOnlyFirmware(
        using service: PTYMOBDFirmwareService,
        checkResult: PTYMOBDFirmwareCheckResult,
        allowSameVersion: Bool = false
    ) async throws -> PTYMOBDFirmwareReadOnlyResult {
        try await service.prepareReadOnlyFirmware(
            from: checkResult,
            allowSameVersion: allowSameVersion
        )
    }
}
