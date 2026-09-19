//
//  PTFeedbackStatusStore.swift
//  CrazyDashboard
//

import Foundation

public actor PTFeedbackStatusStore {
    public static let shared = PTFeedbackStatusStore()

    private let fileManager: FileManager
    private let fileURL: URL
    private var cache: [UUID: PTFeedbackLocalRecord]?

    public init(
        fileManager: FileManager = .default,
        fileURL: URL? = nil
    ) {
        self.fileManager = fileManager

        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? fileManager.temporaryDirectory

            self.fileURL = base
                .appendingPathComponent(
                    "CrazyDashboard",
                    isDirectory: true
                )
                .appendingPathComponent(
                    "Feedback",
                    isDirectory: true
                )
                .appendingPathComponent(
                    "status.json"
                )
        }
    }

    public func upsert(
        _ record: PTFeedbackLocalRecord
    ) throws {
        var values = try load()
        values[record.feedbackID] = record
        cache = values
        try persist(values)
    }

    public func records() throws -> [PTFeedbackLocalRecord] {
        try load().values.sorted {
            $0.createdAt > $1.createdAt
        }
    }

    public func feedbackIDs() throws -> [UUID] {
        Array(try load().keys)
    }

    public func apply(
        _ remote: [PTFeedbackRemoteStatus]
    ) throws {
        _ = try applyAndCollectChanges(remote)
    }

    /// Applies CloudKit as source-of-truth and returns only genuinely newer
    /// local-visible state transitions. Push/local notification code uses this
    /// to avoid duplicate alerts when CloudKit coalesces or replays signals.
    public func applyAndCollectChanges(
        _ remote: [PTFeedbackRemoteStatus]
    ) throws -> [PTFeedbackStatusChange] {
        var values = try load()
        var changes: [PTFeedbackStatusChange] = []

        for status in remote {
            guard var local = values[status.feedbackID] else {
                continue
            }

            guard status.statusRevision > local.statusRevision else {
                continue
            }

            let previousStatus = local.status
            let previousRevision = local.statusRevision
            let previousIssueNumber = local.issueNumber
            let previousResolutionBuild = local.resolutionBuild

            local.status = status.status
            local.statusRevision = status.statusRevision
            local.issueNumber = status.issueNumber
            local.resolutionBuild = status.resolutionBuild
            values[status.feedbackID] = local

            if previousStatus != local.status
                || previousIssueNumber != local.issueNumber
                || previousResolutionBuild != local.resolutionBuild {
                changes.append(
                    .init(
                        feedbackID: local.feedbackID,
                        previousStatus: previousStatus,
                        previousRevision: previousRevision,
                        current: local
                    )
                )
            }
        }

        cache = values
        try persist(values)
        return changes
    }

    public func removeAll() {
        cache = [:]
        try? fileManager.removeItem(at: fileURL)
    }

    private func load() throws -> [UUID: PTFeedbackLocalRecord] {
        if let cache {
            return cache
        }

        guard fileManager.fileExists(atPath: fileURL.path) else {
            cache = [:]
            return [:]
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let records = try JSONDecoder().decode(
                [PTFeedbackLocalRecord].self,
                from: data
            )
            let values = Dictionary(
                uniqueKeysWithValues: records.map {
                    ($0.feedbackID, $0)
                }
            )
            cache = values
            return values
        } catch {
            throw PTFeedbackError.storageFailure(
                error.localizedDescription
            )
        }
    }

    private func persist(
        _ values: [UUID: PTFeedbackLocalRecord]
    ) throws {
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let records = values.values.sorted {
                $0.createdAt < $1.createdAt
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(records)
            try data.write(
                to: fileURL,
                options: .atomic
            )
        } catch {
            throw PTFeedbackError.storageFailure(
                error.localizedDescription
            )
        }
    }
}
