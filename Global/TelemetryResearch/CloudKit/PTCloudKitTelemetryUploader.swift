//
//  PTCloudKitTelemetryUploader.swift
//  PTSpeed
//
//  CloudKit objects never leave this actor.
//
//  @preconcurrency is deliberately limited to this SDK boundary. It can be
//  removed once the deployment SDK's CloudKit annotations fully satisfy the
//  project's Swift 6 strict-concurrency test target.
//

@preconcurrency import CloudKit
import Foundation

nonisolated public enum PTTelemetryUploadError: Error, LocalizedError, Sendable {
    case iCloudUnavailable(Int)
    case missingPayloadFile

    public var errorDescription: String? {
        switch self {
        case .iCloudUnavailable(let rawStatus):
            return "iCloud 当前不可用于 Telemetry 上传，CKAccountStatus=\(rawStatus)。"
        case .missingPayloadFile:
            return "Telemetry 加密 Payload 文件不存在。"
        }
    }
}

public actor PTCloudKitTelemetryUploader {

    public static let shared = PTCloudKitTelemetryUploader()

    private init() {}

    public func accountStatus(
        containerIdentifier: String
    ) async throws -> CKAccountStatus {
        let container = CKContainer(
            identifier:
                containerIdentifier
        )

        return try await container
            .accountStatus()
    }

    public func upload(
        _ envelope: PTTelemetryEnvelope,
        containerIdentifier: String
    ) async throws {

        guard FileManager.default.fileExists(
            atPath:
                envelope.payloadFileURL.path
        ) else {
            throw PTTelemetryUploadError
                .missingPayloadFile
        }

        let container = CKContainer(
            identifier:
                containerIdentifier
        )

        let status = try await container
            .accountStatus()

        guard status == .available else {
            throw PTTelemetryUploadError
                .iCloudUnavailable(
                    status.rawValue
                )
        }

        let database =
            container.publicCloudDatabase

        let recordID = CKRecord.ID(
            recordName:
                envelope
                    .sessionID
                    .uuidString
                    .lowercased()
        )

        let record = CKRecord(
            recordType:
                PTTelemetryConfiguration
                    .cloudKitRecordType,
            recordID:
                recordID
        )

        record["schemaVersion"] = NSNumber(
            value:
                envelope.schemaVersion
        )

        record["sessionID"] =
            envelope.sessionID.uuidString
            as NSString

        record["appVersion"] =
            envelope.appVersion
            as NSString

        record["appBuild"] =
            envelope.appBuild
            as NSString

        record["vehicleFamily"] =
            envelope.vehicleFamily
            as NSString

        if let ecuSoftware =
            envelope.ecuSoftware,
           !ecuSoftware.isEmpty {
            record["ecuSoftware"] =
                ecuSoftware
                as NSString
        }

        if let dashboardFirmware =
            envelope.dashboardFirmware,
           !dashboardFirmware.isEmpty {
            record["dashboardFirmware"] =
                dashboardFirmware
                as NSString
        }

        record["sourceMask"] = NSNumber(
            value:
                envelope.sourceMask
        )

        record["eventCount"] = NSNumber(
            value:
                envelope.eventCount
        )

        record["cryptoVersion"] = NSNumber(
            value:
                envelope.cryptoVersion
        )

        record["ephemeralPublicKey"] =
            envelope.ephemeralPublicKey
            as NSData

        record["nonce"] =
            envelope.nonce
            as NSData

        record["tag"] =
            envelope.tag
            as NSData

        record["payloadHash"] =
            envelope.payloadHash
            as NSString

        record["payloadByteCount"] = NSNumber(
            value:
                envelope.payloadByteCount
        )

        record["processed"] = NSNumber(
            value: 0
        )

        record["payload"] = CKAsset(
            fileURL:
                envelope.payloadFileURL
        )

        do {
            _ = try await database.save(
                record
            )
        } catch let error as CKError
            where error.code
                == .serverRecordChanged {

            // Session IDs are random and immutable. If a retry finds the same
            // recordName already present, treat it as idempotent success.
            return
        }
    }
}
