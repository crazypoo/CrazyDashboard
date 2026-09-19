//
//  PTFeedbackAttachmentRepository.swift
//  CrazyDashboard
//

@preconcurrency import CloudKit
import Foundation

public actor PTFeedbackAttachmentRepository {
    public static let shared = PTFeedbackAttachmentRepository()
    public static let recordType = "FeedbackAttachmentEnvelope"

    private init() {}

    public func upload(
        _ envelope: PTFeedbackAttachmentEnvelope,
        configuration: PTFeedbackConfiguration
    ) async throws {
        let container = PTCloudKitContainerProvider.makeContainer(
            identifier: configuration.cloudKit.containerIdentifier
        )
        guard try await container.accountStatus() == .available else {
            throw PTFeedbackError.cloudAccountUnavailable
        }
        let recordID = CKRecord.ID(
            recordName: envelope.attachmentID.uuidString.lowercased()
        )
        let record = CKRecord(recordType: Self.recordType, recordID: recordID)
        record["attachmentID"] = envelope.attachmentID.uuidString.lowercased() as NSString
        record["feedbackID"] = envelope.feedbackID.uuidString.lowercased() as NSString
        record["kind"] = envelope.kind.rawValue as NSString
        record["mimeType"] = envelope.mimeType as NSString
        record["cryptoVersion"] = NSNumber(value: envelope.cryptoVersion)
        record["ephemeralPublicKey"] = envelope.ephemeralPublicKey as NSData
        record["nonce"] = envelope.nonce as NSData
        record["tag"] = envelope.tag as NSData
        record["payloadHash"] = envelope.payloadHash as NSString
        record["payloadByteCount"] = NSNumber(value: envelope.payloadByteCount)
        record["processed"] = NSNumber(value: 0)
        record["auditState"] = NSNumber(value: 0)
        record["createdAtEpochMs"] = NSNumber(
            value: Int64(Date().timeIntervalSince1970 * 1000)
        )
        record["payload"] = CKAsset(fileURL: envelope.payloadFileURL)
        do {
            _ = try await container.publicCloudDatabase.save(record)
        } catch let error as CKError where error.code == .serverRecordChanged {
            return
        }
    }
}
