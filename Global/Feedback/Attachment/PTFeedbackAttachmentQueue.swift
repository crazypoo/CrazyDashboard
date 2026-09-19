//
//  PTFeedbackAttachmentQueue.swift
//  CrazyDashboard
//

import Foundation

public actor PTFeedbackAttachmentQueue {
    public static let shared = PTFeedbackAttachmentQueue()

    private struct Stored: Codable, Sendable {
        let attachmentID: UUID
        let feedbackID: UUID
        let kind: PTFeedbackAttachmentKind
        let mimeType: String
        let cryptoVersion: Int
        let ephemeralPublicKey: Data
        let nonce: Data
        let tag: Data
        let payloadHash: String
        let payloadByteCount: Int
        let fileName: String
        let createdAt: Date
    }

    private let fm = FileManager.default
    private let directory: URL

    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fm.temporaryDirectory
            self.directory = base
                .appendingPathComponent("CrazyDashboard", isDirectory: true)
                .appendingPathComponent("Feedback", isDirectory: true)
                .appendingPathComponent("AttachmentQueue", isDirectory: true)
        }
    }

    public func enqueue(_ envelope: PTFeedbackAttachmentEnvelope) throws {
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let base = envelope.attachmentID.uuidString.lowercased()
        let fileName = base + ".bin"
        let target = directory.appendingPathComponent(fileName)
        try? fm.removeItem(at: target)
        try fm.copyItem(at: envelope.payloadFileURL, to: target)
        let stored = Stored(
            attachmentID: envelope.attachmentID,
            feedbackID: envelope.feedbackID,
            kind: envelope.kind,
            mimeType: envelope.mimeType,
            cryptoVersion: envelope.cryptoVersion,
            ephemeralPublicKey: envelope.ephemeralPublicKey,
            nonce: envelope.nonce,
            tag: envelope.tag,
            payloadHash: envelope.payloadHash,
            payloadByteCount: envelope.payloadByteCount,
            fileName: fileName,
            createdAt: Date()
        )
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(stored).write(
            to: directory.appendingPathComponent(base + ".json"),
            options: .atomic
        )
    }

    public func pending(limit: Int = 8) -> [PTFeedbackAttachmentEnvelope] {
        guard let urls = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        let decoder = JSONDecoder()
        let values = urls.filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(Stored.self, from: Data(contentsOf: $0)) }
            .sorted { $0.createdAt < $1.createdAt }
            .prefix(max(1, limit))
        return values.compactMap { item in
            let file = directory.appendingPathComponent(item.fileName)
            guard fm.fileExists(atPath: file.path) else { return nil }
            return .init(
                attachmentID: item.attachmentID,
                feedbackID: item.feedbackID,
                kind: item.kind,
                mimeType: item.mimeType,
                cryptoVersion: item.cryptoVersion,
                ephemeralPublicKey: item.ephemeralPublicKey,
                nonce: item.nonce,
                tag: item.tag,
                payloadHash: item.payloadHash,
                payloadByteCount: item.payloadByteCount,
                payloadFileURL: file
            )
        }
    }

    public func remove(attachmentID: UUID) {
        let base = attachmentID.uuidString.lowercased()
        try? fm.removeItem(at: directory.appendingPathComponent(base + ".json"))
        try? fm.removeItem(at: directory.appendingPathComponent(base + ".bin"))
    }

    public func pendingCount() -> Int {
        (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.count) ?? 0
    }
}
