//
//  PTTelemetryUploadQueue.swift
//  PTSpeed
//

import Foundation

public actor PTTelemetryUploadQueue {

    public static let shared = PTTelemetryUploadQueue()

    private struct QueuedItem: Codable, Sendable {
        let schemaVersion: Int
        let cryptoVersion: Int
        let sessionID: UUID

        let appVersion: String
        let appBuild: String

        let vehicleFamily: String
        let ecuSoftware: String?
        let dashboardFirmware: String?

        let sourceMask: Int64
        let eventCount: Int

        let ephemeralPublicKey: Data
        let nonce: Data
        let tag: Data

        let payloadFileName: String
        let payloadHash: String
        let payloadByteCount: Int64

        let createdAt: Date
        var retryCount: Int
        var lastError: String?
    }

    private let fileManager: FileManager
    private let queueDirectory: URL

    public init(
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager

        let root = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first
        ?? fileManager.temporaryDirectory

        self.queueDirectory = root
            .appendingPathComponent(
                "CrazyDashboard",
                isDirectory: true
            )
            .appendingPathComponent(
                "TelemetryResearch",
                isDirectory: true
            )
            .appendingPathComponent(
                "Queue",
                isDirectory: true
            )
    }

    @discardableResult
    public func enqueue(
        _ envelope: PTTelemetryEnvelope
    ) throws -> UUID {

        try ensureDirectory()

        let payloadFileName =
            "\(envelope.sessionID.uuidString.lowercased()).bin"

        let destinationPayloadURL =
            queueDirectory
            .appendingPathComponent(
                payloadFileName
            )

        if fileManager.fileExists(
            atPath:
                destinationPayloadURL.path
        ) {
            try fileManager.removeItem(
                at: destinationPayloadURL
            )
        }

        try fileManager.copyItem(
            at: envelope.payloadFileURL,
            to: destinationPayloadURL
        )

        let item = QueuedItem(
            schemaVersion:
                envelope.schemaVersion,
            cryptoVersion:
                envelope.cryptoVersion,
            sessionID:
                envelope.sessionID,
            appVersion:
                envelope.appVersion,
            appBuild:
                envelope.appBuild,
            vehicleFamily:
                envelope.vehicleFamily,
            ecuSoftware:
                envelope.ecuSoftware,
            dashboardFirmware:
                envelope.dashboardFirmware,
            sourceMask:
                envelope.sourceMask,
            eventCount:
                envelope.eventCount,
            ephemeralPublicKey:
                envelope.ephemeralPublicKey,
            nonce:
                envelope.nonce,
            tag:
                envelope.tag,
            payloadFileName:
                payloadFileName,
            payloadHash:
                envelope.payloadHash,
            payloadByteCount:
                envelope.payloadByteCount,
            createdAt:
                Date(),
            retryCount:
                0,
            lastError:
                nil
        )

        try write(
            item,
            to: metadataURL(
                sessionID:
                    envelope.sessionID
            )
        )

        return envelope.sessionID
    }

    public func pending(
        limit: Int = 20
    ) -> [PTTelemetryEnvelope] {

        guard let files = try? fileManager
            .contentsOfDirectory(
                at: queueDirectory,
                includingPropertiesForKeys: [
                    .creationDateKey
                ],
                options: [
                    .skipsHiddenFiles
                ]
            ) else {
            return []
        }

        let metadataFiles = files
            .filter {
                $0.pathExtension == "json"
            }
            .sorted {
                let lhs = (
                    try? $0.resourceValues(
                        forKeys: [
                            .creationDateKey
                        ]
                    ).creationDate
                )
                ?? .distantPast

                let rhs = (
                    try? $1.resourceValues(
                        forKeys: [
                            .creationDateKey
                        ]
                    ).creationDate
                )
                ?? .distantPast

                return lhs < rhs
            }

        return metadataFiles
            .prefix(
                max(
                    0,
                    limit
                )
            )
            .compactMap { url in
                guard let data = try? Data(
                    contentsOf: url
                ),
                let item = try? decoder.decode(
                    QueuedItem.self,
                    from: data
                ) else {
                    return nil
                }

                let payloadURL =
                    queueDirectory
                    .appendingPathComponent(
                        item.payloadFileName
                    )

                guard fileManager.fileExists(
                    atPath:
                        payloadURL.path
                ) else {
                    return nil
                }

                return PTTelemetryEnvelope(
                    schemaVersion:
                        item.schemaVersion,
                    cryptoVersion:
                        item.cryptoVersion,
                    sessionID:
                        item.sessionID,
                    appVersion:
                        item.appVersion,
                    appBuild:
                        item.appBuild,
                    vehicleFamily:
                        item.vehicleFamily,
                    ecuSoftware:
                        item.ecuSoftware,
                    dashboardFirmware:
                        item.dashboardFirmware,
                    sourceMask:
                        item.sourceMask,
                    eventCount:
                        item.eventCount,
                    ephemeralPublicKey:
                        item.ephemeralPublicKey,
                    nonce:
                        item.nonce,
                    tag:
                        item.tag,
                    payloadFileURL:
                        payloadURL,
                    payloadHash:
                        item.payloadHash,
                    payloadByteCount:
                        item.payloadByteCount
                )
            }
    }

    public func pendingCount() -> Int {
        guard let files = try? fileManager
            .contentsOfDirectory(
                at: queueDirectory,
                includingPropertiesForKeys:
                    nil,
                options: [
                    .skipsHiddenFiles
                ]
            ) else {
            return 0
        }

        return files.filter {
            $0.pathExtension == "json"
        }.count
    }

    public func markUploaded(
        sessionID: UUID
    ) {
        try? fileManager.removeItem(
            at: metadataURL(
                sessionID: sessionID
            )
        )

        try? fileManager.removeItem(
            at: payloadURL(
                sessionID: sessionID
            )
        )
    }

    public func markFailed(
        sessionID: UUID,
        error: Error
    ) {
        let url = metadataURL(
            sessionID: sessionID
        )

        guard let data = try? Data(
            contentsOf: url
        ),
        var item = try? decoder.decode(
            QueuedItem.self,
            from: data
        ) else {
            return
        }

        item.retryCount += 1
        item.lastError = String(
            error.localizedDescription
                .prefix(512)
        )

        try? write(
            item,
            to: url
        )
    }

    public func purgeAll() {
        try? fileManager.removeItem(
            at: queueDirectory
        )

        try? ensureDirectory()
    }
}

private extension PTTelemetryUploadQueue {

    var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [
            .sortedKeys
        ]
        return encoder
    }

    var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func ensureDirectory() throws {
        try fileManager.createDirectory(
            at: queueDirectory,
            withIntermediateDirectories: true
        )
    }

    func metadataURL(
        sessionID: UUID
    ) -> URL {
        queueDirectory
            .appendingPathComponent(
                "\(sessionID.uuidString.lowercased()).json"
            )
    }

    func payloadURL(
        sessionID: UUID
    ) -> URL {
        queueDirectory
            .appendingPathComponent(
                "\(sessionID.uuidString.lowercased()).bin"
            )
    }

    func write<T: Encodable>(
        _ value: T,
        to url: URL
    ) throws {
        try ensureDirectory()

        let data = try encoder.encode(
            value
        )

        try data.write(
            to: url,
            options: .atomic
        )
    }
}
