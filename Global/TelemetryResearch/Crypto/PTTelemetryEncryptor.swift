//
//  PTTelemetryEncryptor.swift
//  PTSpeed
//
//  Crypto V1:
//  X25519 -> HKDF-SHA256 -> AES-GCM
//
//  CrazyDashboard-Telemetry decrypt.py must remain byte-for-byte compatible.
//

import CryptoKit
import Foundation

nonisolated public enum PTTelemetryCryptoError: Error, LocalizedError, Sendable {
    case invalidServerPublicKey
    case unableToCreatePayloadFile

    public var errorDescription: String? {
        switch self {
        case .invalidServerPublicKey:
            return "Telemetry Server Public Key 无效。"
        case .unableToCreatePayloadFile:
            return "无法创建 Telemetry 加密 Payload 文件。"
        }
    }
}

nonisolated public enum PTTelemetryEncryptor {

    public static func encrypt(
        _ payload: PTTelemetryUploadPayload,
        configuration: PTTelemetryConfiguration
    ) throws -> PTTelemetryEnvelope {

        guard let serverPublicKeyData = Data(
            base64Encoded:
                configuration.serverPublicKeyBase64
        ),
        serverPublicKeyData.count == 32 else {
            throw PTTelemetryCryptoError.invalidServerPublicKey
        }

        let serverPublicKey = try Curve25519
            .KeyAgreement
            .PublicKey(
                rawRepresentation:
                    serverPublicKeyData
            )

        let ephemeralPrivateKey = Curve25519
            .KeyAgreement
            .PrivateKey()

        let sharedSecret = try ephemeralPrivateKey
            .sharedSecretFromKeyAgreement(
                with: serverPublicKey
            )

        let symmetricKey = sharedSecret
            .hkdfDerivedSymmetricKey(
                using: SHA256.self,
                salt: Data(
                    PTTelemetryConfiguration
                        .hkdfSalt
                        .utf8
                ),
                sharedInfo: Data(
                    payload
                        .sessionID
                        .uuidString
                        .utf8
                ),
                outputByteCount: 32
            )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .sortedKeys
        ]

        let plaintext = try encoder.encode(
            payload
        )

        let sealedBox = try AES.GCM.seal(
            plaintext,
            using: symmetricKey
        )

        let ciphertext = sealedBox.ciphertext
        let nonce = Data(
            sealedBox.nonce
        )
        let tag = sealedBox.tag

        let temporaryDirectory = FileManager
            .default
            .temporaryDirectory
            .appendingPathComponent(
                "CrazyDashboardTelemetry",
                isDirectory: true
            )

        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )

        let payloadURL = temporaryDirectory
            .appendingPathComponent(
                "\(payload.sessionID.uuidString.lowercased()).bin"
            )

        do {
            try ciphertext.write(
                to: payloadURL,
                options: .atomic
            )
        } catch {
            throw PTTelemetryCryptoError
                .unableToCreatePayloadFile
        }

        let digest = SHA256.hash(
            data: ciphertext
        )

        let payloadHash = digest
            .map {
                String(
                    format: "%02x",
                    $0
                )
            }
            .joined()

        return PTTelemetryEnvelope(
            sessionID: payload.sessionID,
            appVersion: payload.app.version,
            appBuild: payload.app.build,
            vehicleFamily: payload.vehicle.family,
            ecuSoftware: payload.vehicle.ecuSoftware,
            dashboardFirmware:
                payload.vehicle.dashboardFirmware,
            sourceMask:
                payload.sourceMask.rawValue,
            eventCount:
                payload.events.count,
            ephemeralPublicKey:
                ephemeralPrivateKey
                    .publicKey
                    .rawRepresentation,
            nonce: nonce,
            tag: tag,
            payloadFileURL: payloadURL,
            payloadHash: payloadHash,
            payloadByteCount:
                Int64(
                    ciphertext.count
                )
        )
    }
}
