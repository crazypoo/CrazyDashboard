//
//  PTCloudKitFeedbackRepository.swift
//  CrazyDashboard
//  Build75: developer reply fields are fetched together with statusRevision.
//

@preconcurrency import CloudKit
import Foundation

public actor PTCloudKitFeedbackRepository {
    public static let shared = PTCloudKitFeedbackRepository()

    private init() {}

    public func upload(
        _ envelope: PTFeedbackEnvelope,
        configuration: PTFeedbackConfiguration
    ) async throws {
        guard FileManager.default.fileExists(atPath: envelope.payloadFileURL.path) else {
            throw PTFeedbackError.storageFailure("加密反馈文件不存在。")
        }

        let container = PTCloudKitContainerProvider.makeContainer(
            identifier: configuration.cloudKit.containerIdentifier
        )
        let accountStatus = try await container.accountStatus()
        guard accountStatus == .available else {
            throw PTFeedbackError.cloudAccountUnavailable
        }

        let database = container.publicCloudDatabase
        let recordID = CKRecord.ID(recordName: envelope.feedbackID.uuidString.lowercased())
        let record = CKRecord(recordType: PTFeedbackConfiguration.recordType, recordID: recordID)

        record["schemaVersion"] = NSNumber(value: envelope.schemaVersion)
        record["feedbackID"] = envelope.feedbackID.uuidString.lowercased() as NSString
        record["appBuild"] = envelope.appBuild as NSString
        record["cryptoVersion"] = NSNumber(value: envelope.cryptoVersion)
        record["ephemeralPublicKey"] = envelope.ephemeralPublicKey as NSData
        record["nonce"] = envelope.nonce as NSData
        record["tag"] = envelope.tag as NSData
        record["payloadHash"] = envelope.payloadHash as NSString
        record["payloadByteCount"] = NSNumber(value: envelope.payloadByteCount)
        record["processed"] = NSNumber(value: 0)
        record["triageState"] = NSNumber(value: PTFeedbackStatus.submitted.rawValue)
        record["statusRevision"] = NSNumber(value: 0)
        record["payload"] = CKAsset(fileURL: envelope.payloadFileURL)

        do {
            _ = try await database.save(record)
        } catch let error as CKError where error.code == .serverRecordChanged {
            return
        }
    }

    public func fetchStatuses(
        feedbackIDs: [UUID],
        configuration: PTFeedbackConfiguration
    ) async throws -> [PTFeedbackRemoteStatus] {
        guard !feedbackIDs.isEmpty else { return [] }

        let container = PTCloudKitContainerProvider.makeContainer(
            identifier: configuration.cloudKit.containerIdentifier
        )
        let accountStatus = try await container.accountStatus()
        guard accountStatus == .available else {
            throw PTFeedbackError.cloudAccountUnavailable
        }

        let database = container.publicCloudDatabase
        var output: [PTFeedbackRemoteStatus] = []
        output.reserveCapacity(feedbackIDs.count)

        // Exact record IDs only. The client still never enumerates other users' feedback.
        for id in feedbackIDs {
            try Task.checkCancellation()
            let recordID = CKRecord.ID(recordName: id.uuidString.lowercased())

            do {
                let record = try await database.record(for: recordID)
                guard let stateNumber = record["triageState"] as? NSNumber,
                      let state = PTFeedbackStatus(rawValue: stateNumber.intValue) else {
                    continue
                }

                let revision = (record["statusRevision"] as? NSNumber)?.intValue ?? 0
                let issueNumber = (record["issueNumber"] as? NSNumber)?.intValue
                let resolutionBuild = Self.string(record["resolutionBuild"])
                let developerReplyZH = Self.string(record["developerReplyZH"])
                let developerReplyEN = Self.string(record["developerReplyEN"])
                let developerReplyES = Self.string(record["developerReplyES"])
                let replyUpdatedAt = (record["developerReplyUpdatedAtEpochMs"] as? NSNumber)?.int64Value

                output.append(
                    .init(
                        feedbackID: id,
                        status: state,
                        statusRevision: revision,
                        issueNumber: issueNumber,
                        resolutionBuild: resolutionBuild,
                        developerReplyZH: developerReplyZH,
                        developerReplyEN: developerReplyEN,
                        developerReplyES: developerReplyES,
                        developerReplyUpdatedAtEpochMilliseconds: replyUpdatedAt
                    )
                )
            } catch let error as CKError where error.code == .unknownItem {
                continue
            }
        }

        return output
    }

    private static func string(_ value: Any?) -> String? {
        if let value = value as? NSString { return value as String }
        if let value = value as? String { return value }
        return nil
    }
}
