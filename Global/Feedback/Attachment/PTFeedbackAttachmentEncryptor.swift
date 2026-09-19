//
//  PTFeedbackAttachmentEncryptor.swift
//  CrazyDashboard
//

import CryptoKit
import Foundation

nonisolated public enum PTFeedbackAttachmentEncryptor {
    private static let salt = "CrazyDashboardFeedbackAttachment-v1"

    public static func encrypt(
        _ draft: PTFeedbackAttachmentDraft,
        feedbackID: UUID,
        configuration: PTFeedbackConfiguration
    ) throws -> PTFeedbackAttachmentEnvelope {
        let maximum: Int
        switch draft.kind {
        case .screenshot: maximum = 2 * 1024 * 1024
        case .diagnostics: maximum = 512 * 1024
        case .sanitizedLog: maximum = 1024 * 1024
        }
        guard draft.data.count <= maximum else {
            throw PTFeedbackError.payloadTooLarge(draft.data.count)
        }
        guard let serverData = Data(base64Encoded: configuration.serverPublicKeyBase64) else {
            throw PTFeedbackError.missingConfiguration("Feedback attachment server key is invalid Base64.")
        }
        let serverKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: serverData)
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        let secret = try ephemeral.sharedSecretFromKeyAgreement(with: serverKey)
        let key = secret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(salt.utf8),
            sharedInfo: Data(draft.attachmentID.uuidString.lowercased().utf8),
            outputByteCount: 32
        )
        let sealed = try AES.GCM.seal(draft.data, using: key)
        let ciphertext = sealed.ciphertext
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CrazyDashboardFeedbackAttachments", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(
            draft.attachmentID.uuidString.lowercased() + ".bin"
        )
        try ciphertext.write(to: url, options: .atomic)
        let nonce = sealed.nonce.withUnsafeBytes { Data($0) }
        let hash = SHA256.hash(data: ciphertext)
            .map { String(format: "%02x", $0) }.joined()
        return .init(
            attachmentID: draft.attachmentID,
            feedbackID: feedbackID,
            kind: draft.kind,
            mimeType: draft.mimeType,
            cryptoVersion: 1,
            ephemeralPublicKey: ephemeral.publicKey.rawRepresentation,
            nonce: nonce,
            tag: sealed.tag,
            payloadHash: hash,
            payloadByteCount: ciphertext.count,
            payloadFileURL: url
        )
    }
}
