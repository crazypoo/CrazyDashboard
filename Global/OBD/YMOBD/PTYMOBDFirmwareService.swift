//
//  PTYMOBDFirmwareService.swift
//  CrazyDashboard
//
//  EN: Coordinates read-only YMOBD version checks, download, and decryption.
//  ES: Coordina comprobaciones de versión, descarga y descifrado YMOBD de solo lectura.
//  中文：协调只读 YMOBD 版本检查、下载和解密流程。
//

import Foundation
import OSLog

public enum PTYMOBDFirmwareServiceError: Error, Equatable, LocalizedError, Sendable {
    case notYMOBD
    case deviceTypeMissing
    case firmwareVersionMissing
    case noUpdateAvailable
    case unsupportedPublicKeyVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .notYMOBD:
            return "当前适配器不是可识别的 YMOBD 设备"
        case .deviceTypeMissing:
            return "YMOBD 响应缺少设备型号"
        case .firmwareVersionMissing:
            return "YMOBD 响应缺少固件版本"
        case .noUpdateAvailable:
            return "当前没有可下载的更新固件"
        case let .unsupportedPublicKeyVersion(version):
            return "固件服务要求不支持的公钥版本（\(version)）"
        }
    }
}

public actor PTYMOBDFirmwareService {
    private let api: PTYMOBDFirmwareAPI
    private let versionParser = PTYMOBDVersionParser()
    private let logger = Logger(subsystem: "com.yd.PTSpeed", category: "YMOBD.FirmwareService")

    public init(api: PTYMOBDFirmwareAPI) {
        self.api = api
    }

    // EN: Use the existing exclusive read path so firmware inspection never races normal PID polling.
    // ES: Usa la ruta de lectura exclusiva existente para que la inspección nunca compita con el sondeo PID.
    // 中文：复用现有只读总线独占路径，避免固件检查与普通 PID 轮询竞争。
    public func checkConnectedAdapter() async throws -> PTYMOBDFirmwareCheckResult {
        let responses = try await PTAdvancedOBDCoordinator.shared.executeReadOnly {
            let version = try await PTMotoTelemetryManager.shared.sendRawCommandAsync("AT+VERSION")
            let ati = try await PTMotoTelemetryManager.shared.sendRawCommandAsync("ATI")
            return (version, ati)
        }

        let versionInfo = versionParser.parse(responses.0)
        guard versionInfo.isYMOBD else {
            throw PTYMOBDFirmwareServiceError.notYMOBD
        }
        return try await checkLatestFirmware(versionInfo: versionInfo, atiResponse: responses.1)
    }

    public func checkLatestFirmware(
        versionInfo: PTYMOBDVersionInfo,
        atiResponse: String
    ) async throws -> PTYMOBDFirmwareCheckResult {
        guard versionInfo.isYMOBD else {
            throw PTYMOBDFirmwareServiceError.notYMOBD
        }

        let deviceType = versionInfo.deviceType.isEmpty
            ? versionInfo.deviceName
            : versionInfo.deviceType
        guard !deviceType.isEmpty else {
            throw PTYMOBDFirmwareServiceError.deviceTypeMissing
        }
        guard !versionInfo.version.isEmpty else {
            throw PTYMOBDFirmwareServiceError.firmwareVersionMissing
        }

        let request = PTYMOBDFirmwareCheckRequest(
            deviceType: deviceType,
            protocolType: PTYMOBDProtocolTypeResolver.resolve(atiResponse: atiResponse),
            obdFirmwareVersion: versionInfo.version
        )
        return try await api.checkLatestFirmware(for: request)
    }

    // EN: Download and decrypt only; no OTA manager, RCSP command, or BLE write is reachable from this method.
    // ES: Solo descarga y descifra; ningún gestor OTA, comando RCSP ni escritura BLE es accesible desde este método.
    // 中文：这里只下载和解密，不会触达 OTA 管理器、RCSP 指令或 BLE 写入路径。
    public func prepareReadOnlyFirmware(
        from checkResult: PTYMOBDFirmwareCheckResult,
        allowSameVersion: Bool = false
    ) async throws -> PTYMOBDFirmwareReadOnlyResult {
        guard checkResult.metadata.isDownloadable else {
            throw PTYMOBDFirmwareResponseError.metadataMissing
        }
        guard allowSameVersion || checkResult.isUpdateAvailable else {
            throw PTYMOBDFirmwareServiceError.noUpdateAvailable
        }
        if let serverPublicKeyVersion = checkResult.metadata.publicKeyVersion,
           serverPublicKeyVersion != PTYMOBDFirmwareCrypto.publicKeyVersion {
            throw PTYMOBDFirmwareServiceError.unsupportedPublicKeyVersion(serverPublicKeyVersion)
        }

        let secret = try PTYMOBDFirmwareCrypto.createSecret()
        let encrypted = try await api.downloadEncryptedFirmware(
            firmwareFileUUID: checkResult.metadata.firmwareFileUUID,
            encryptKey: secret.encryptKey
        )
        let decrypted = try PTYMOBDFirmwareCrypto.decryptFirmware(
            encryptedData: encrypted.data,
            keyString: secret.keyString
        )
        let report = PTYMOBDFirmwareTransferReport(
            firmwareVersion: checkResult.metadata.firmwareVersion,
            firmwareFileUUID: checkResult.metadata.firmwareFileUUID,
            encryptedByteCount: encrypted.byteCount,
            encryptedSHA256: encrypted.sha256Hex,
            decryptedByteCount: decrypted.count,
            decryptedSHA256: PTYMOBDFirmwareCrypto.sha256Hex(decrypted),
            publicKeyVersion: secret.publicKeyVersion,
            publicKeyFingerprint: PTYMOBDFirmwareCrypto.publicKeyFingerprint
        )

        logger.info("YMOBD firmware dry-run prepared: version=\(report.firmwareVersion, privacy: .public), encryptedBytes=\(report.encryptedByteCount, privacy: .public), decryptedBytes=\(report.decryptedByteCount, privacy: .public), decryptedSHA256=\(report.decryptedSHA256, privacy: .public)")
        return PTYMOBDFirmwareReadOnlyResult(
            checkResult: checkResult,
            secret: secret,
            decryptedFirmware: decrypted,
            report: report
        )
    }
}
