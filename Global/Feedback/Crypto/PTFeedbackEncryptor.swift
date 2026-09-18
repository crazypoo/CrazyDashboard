//
//  PTFeedbackEncryptor.swift
//  CrazyDashboard
//
//  X25519 -> HKDF-SHA256 -> AES-GCM.
//  Only ciphertext is written to disk / CloudKit.
//

import CryptoKit
import Foundation

nonisolated public enum PTFeedbackEncryptor {
    public static func encrypt(
        _ payload: PTFeedbackUploadPayload,
        configuration: PTFeedbackConfiguration
    ) throws -> PTFeedbackEnvelope {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        let plaintext = try encoder.encode(payload)

        guard plaintext.count <= configuration.maximumPayloadBytes else {
            throw PTFeedbackError.payloadTooLarge(plaintext.count)
        }

        guard let serverKeyData = Data(
            base64Encoded: configuration.serverPublicKeyBase64
        ) else {
            throw PTFeedbackError.missingConfiguration(
                "PTFeedbackServerPublicKeyBase64 不是有效 Base64。"
            )
        }

        let serverPublicKey: Curve25519.KeyAgreement.PublicKey
        do {
            serverPublicKey = try .init(
                rawRepresentation: serverKeyData
            )
        } catch {
            throw PTFeedbackError.missingConfiguration(
                "PTFeedbackServerPublicKeyBase64 不是有效 X25519 公钥。"
            )
        }

        do {
            let ephemeralPrivateKey = Curve25519.KeyAgreement.PrivateKey()
            let sharedSecret = try ephemeralPrivateKey.sharedSecretFromKeyAgreement(
                with: serverPublicKey
            )

            let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
                using: SHA256.self,
                salt: Data(
                    PTFeedbackConfiguration.hkdfSalt.utf8
                ),
                sharedInfo: Data(
                    payload.feedbackID.uuidString.lowercased().utf8
                ),
                outputByteCount: 32
            )

            let sealed = try AES.GCM.seal(
                plaintext,
                using: symmetricKey
            )

            let ciphertext = sealed.ciphertext

            let tempRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "CrazyDashboardFeedback",
                    isDirectory: true
                )

            try FileManager.default.createDirectory(
                at: tempRoot,
                withIntermediateDirectories: true
            )

            let fileURL = tempRoot.appendingPathComponent(
                "\(payload.feedbackID.uuidString.lowercased()).bin"
            )

            try ciphertext.write(
                to: fileURL,
                options: .atomic
            )

            let nonce = sealed.nonce.withUnsafeBytes {
                Data($0)
            }

            let hash = SHA256.hash(data: ciphertext)
                .map { String(format: "%02x", $0) }
                .joined()

            return .init(
                schemaVersion: PTFeedbackConfiguration.envelopeSchemaVersion,
                feedbackID: payload.feedbackID,
                appBuild: payload.app.build,
                cryptoVersion: PTFeedbackConfiguration.cryptoVersion,
                ephemeralPublicKey: ephemeralPrivateKey.publicKey.rawRepresentation,
                nonce: nonce,
                tag: sealed.tag,
                payloadHash: hash,
                payloadByteCount: ciphertext.count,
                payloadFileURL: fileURL
            )
        } catch let error as PTFeedbackError {
            throw error
        } catch {
            throw PTFeedbackError.encryptionFailed
        }
    }
}
