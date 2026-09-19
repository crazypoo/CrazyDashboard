//
//  PTFeatureSuggestionRepository.swift
//  CrazyDashboard
//

@preconcurrency import CloudKit
import CryptoKit
import Foundation

public actor PTFeatureSuggestionRepository {
    public static let shared = PTFeatureSuggestionRepository()
    public static let recordType = "FeatureSuggestion"
    public static let voteRecordType = "FeedbackVote"

    private var configuration: PTCloudKitConfiguration?

    private init() {}

    public func configure(_ configuration: PTCloudKitConfiguration) {
        self.configuration = configuration
    }

    public func fetchVisible() async throws -> [PTFeatureSuggestion] {
        guard let configuration else { return [] }
        let container = PTCloudKitContainerProvider.makeContainer(
            identifier: configuration.containerIdentifier
        )
        let database = container.publicCloudDatabase
        let query = CKQuery(
            recordType: Self.recordType,
            predicate: NSPredicate(format: "isVisible == %d", 1)
        )
        let response = try await database.records(
            matching: query,
            desiredKeys: [
                "suggestionID", "title", "summary", "module", "state",
                "voteCount", "reportCount", "issueNumber", "isVotingOpen",
                "revision", "updatedAtEpochMs", "isVisible"
            ],
            resultsLimit: 100
        )

        return response.matchResults.compactMap { _, result in
            guard case .success(let record) = result else { return nil }
            return Self.makeSuggestion(record)
        }
    }

    public func isVoted(suggestionID: String) async throws -> Bool {
        guard let (database, recordID) = try await voteContext(suggestionID: suggestionID) else {
            return false
        }
        do {
            _ = try await database.record(for: recordID)
            return true
        } catch let error as CKError where error.code == .unknownItem {
            return false
        }
    }

    public func setVoted(_ voted: Bool, suggestionID: String) async throws {
        guard let (database, recordID) = try await voteContext(suggestionID: suggestionID) else {
            throw PTFeedbackError.cloudAccountUnavailable
        }

        if voted {
            let record = CKRecord(recordType: Self.voteRecordType, recordID: recordID)
            record["suggestionID"] = suggestionID as NSString
            record["value"] = NSNumber(value: 1)
            record["createdAtEpochMs"] = NSNumber(
                value: Int64(Date().timeIntervalSince1970 * 1000)
            )
            do {
                _ = try await database.save(record)
            } catch let error as CKError where error.code == .serverRecordChanged {
                return
            }
        } else {
            do {
                _ = try await database.deleteRecord(withID: recordID)
            } catch let error as CKError where error.code == .unknownItem {
                return
            }
        }
    }

    private func voteContext(
        suggestionID: String
    ) async throws -> (CKDatabase, CKRecord.ID)? {
        guard let configuration else { return nil }
        let container = PTCloudKitContainerProvider.makeContainer(
            identifier: configuration.containerIdentifier
        )
        guard try await container.accountStatus() == .available else { return nil }
        let userRecordID = try await container.userRecordID()
        let material = Data(
            (userRecordID.recordName + "|" + suggestionID + "|CrazyDashboardVote-v1").utf8
        )
        let digest = SHA256.hash(data: material)
            .map { String(format: "%02x", $0) }
            .joined()
        let recordID = CKRecord.ID(
            recordName: "vote.\(suggestionID).\(digest)"
        )
        return (container.publicCloudDatabase, recordID)
    }

    private static func makeSuggestion(_ record: CKRecord) -> PTFeatureSuggestion? {
        guard
            let id = record["suggestionID"] as? String,
            let title = record["title"] as? String,
            let summary = record["summary"] as? String,
            let module = record["module"] as? String,
            let stateRaw = (record["state"] as? NSNumber)?.intValue,
            let state = PTFeatureSuggestionState(rawValue: stateRaw)
        else { return nil }

        return PTFeatureSuggestion(
            suggestionID: id,
            title: title,
            summary: summary,
            module: module,
            state: state,
            voteCount: (record["voteCount"] as? NSNumber)?.intValue ?? 0,
            reportCount: (record["reportCount"] as? NSNumber)?.intValue ?? 0,
            issueNumber: (record["issueNumber"] as? NSNumber)?.intValue,
            isVotingOpen: ((record["isVotingOpen"] as? NSNumber)?.intValue ?? 0) == 1,
            revision: (record["revision"] as? NSNumber)?.intValue ?? 0,
            updatedAtEpochMilliseconds: (record["updatedAtEpochMs"] as? NSNumber)?.int64Value ?? 0
        )
    }
}
