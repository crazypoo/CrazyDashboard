//
//  PTFeedbackUploadQueue.swift
//  CrazyDashboard
//
//  Durable encrypted queue. Plaintext feedback is never written here.
//

import Foundation

public actor PTFeedbackUploadQueue {
    public static let shared = PTFeedbackUploadQueue()

    private struct StoredEnvelope: Codable, Sendable {
        let schemaVersion: Int
        let feedbackID: UUID
        let appBuild: String
        let cryptoVersion: Int
        let ephemeralPublicKey: Data
        let nonce: Data
        let tag: Data
        let payloadHash: String
        let payloadByteCount: Int
        let payloadFileName: String
        let createdAt: Date
        var retryCount: Int
        var lastError: String?
    }

    private let fileManager: FileManager
    private let directoryURL: URL

    public init(
        fileManager: FileManager = .default,
        directoryURL: URL? = nil
    ) {
        self.fileManager = fileManager

        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let base = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? fileManager.temporaryDirectory

            self.directoryURL = base
                .appendingPathComponent(
                    "CrazyDashboard",
                    isDirectory: true
                )
                .appendingPathComponent(
                    "Feedback",
                    isDirectory: true
                )
                .appendingPathComponent(
                    "Queue",
                    isDirectory: true
                )
        }
    }

    @discardableResult
    public func enqueue(
        _ envelope: PTFeedbackEnvelope
    ) throws -> UUID {
        try ensureDirectory()

        let id = envelope.feedbackID
        let baseName = id.uuidString.lowercased()
        let payloadName = "\(baseName).bin"
        let metadataURL = directoryURL.appendingPathComponent(
            "\(baseName).json"
        )
        let queuePayloadURL = directoryURL.appendingPathComponent(
            payloadName
        )

        if fileManager.fileExists(atPath: queuePayloadURL.path) {
            try? fileManager.removeItem(at: queuePayloadURL)
        }

        try fileManager.copyItem(
            at: envelope.payloadFileURL,
            to: queuePayloadURL
        )

        let stored = StoredEnvelope(
            schemaVersion: envelope.schemaVersion,
            feedbackID: id,
            appBuild: envelope.appBuild,
            cryptoVersion: envelope.cryptoVersion,
            ephemeralPublicKey: envelope.ephemeralPublicKey,
            nonce: envelope.nonce,
            tag: envelope.tag,
            payloadHash: envelope.payloadHash,
            payloadByteCount: envelope.payloadByteCount,
            payloadFileName: payloadName,
            createdAt: Date(),
            retryCount: 0,
            lastError: nil
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(stored)
        try data.write(to: metadataURL, options: .atomic)

        return id
    }

    public func pending(
        limit: Int
    ) -> [PTFeedbackEnvelope] {
        guard let files = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        let decoder = JSONDecoder()

        let stored = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> StoredEnvelope? in
                guard let data = try? Data(contentsOf: url),
                      let item = try? decoder.decode(
                        StoredEnvelope.self,
                        from: data
                      ) else {
                    return nil
                }
                return item
            }
            .sorted { $0.createdAt < $1.createdAt }
            .prefix(max(1, limit))

        return stored.compactMap { item in
            let payloadURL = directoryURL.appendingPathComponent(
                item.payloadFileName
            )

            guard fileManager.fileExists(
                atPath: payloadURL.path
            ) else {
                return nil
            }

            return PTFeedbackEnvelope(
                schemaVersion: item.schemaVersion,
                feedbackID: item.feedbackID,
                appBuild: item.appBuild,
                cryptoVersion: item.cryptoVersion,
                ephemeralPublicKey: item.ephemeralPublicKey,
                nonce: item.nonce,
                tag: item.tag,
                payloadHash: item.payloadHash,
                payloadByteCount: item.payloadByteCount,
                payloadFileURL: payloadURL
            )
        }
    }

    public func markUploaded(
        feedbackID: UUID
    ) {
        let baseName = feedbackID.uuidString.lowercased()
        try? fileManager.removeItem(
            at: directoryURL.appendingPathComponent("\(baseName).json")
        )
        try? fileManager.removeItem(
            at: directoryURL.appendingPathComponent("\(baseName).bin")
        )
    }

    public func markFailed(
        feedbackID: UUID,
        error: Error
    ) {
        let baseName = feedbackID.uuidString.lowercased()
        let metadataURL = directoryURL.appendingPathComponent(
            "\(baseName).json"
        )

        guard let data = try? Data(contentsOf: metadataURL),
              var stored = try? JSONDecoder().decode(
                StoredEnvelope.self,
                from: data
              ) else {
            return
        }

        stored.retryCount += 1
        stored.lastError = String(
            describing: error
        ).prefix(500).description

        guard let updated = try? JSONEncoder().encode(stored) else {
            return
        }

        try? updated.write(
            to: metadataURL,
            options: .atomic
        )
    }

    public func pendingCount() -> Int {
        guard let files = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        ) else {
            return 0
        }

        return files.filter {
            $0.pathExtension == "json"
        }.count
    }

    public func purgeAll() {
        try? fileManager.removeItem(
            at: directoryURL
        )
    }

    private func ensureDirectory() throws {
        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            throw PTFeedbackError.storageFailure(
                error.localizedDescription
            )
        }
    }
}
