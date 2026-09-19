//
//  PTAnnouncementRepository.swift
//  CrazyDashboard
//

@preconcurrency import CloudKit
import Foundation

public actor PTAnnouncementRepository {
    public static let shared = PTAnnouncementRepository()
    public static let recordType = "Announcement"

    private var configuration: PTCloudKitConfiguration?

    private init() {}

    public func configure(_ configuration: PTCloudKitConfiguration) {
        self.configuration = configuration
    }

    public func fetchActive() async throws -> [PTAnnouncement] {
        guard let configuration else { return [] }
        let container = PTCloudKitContainerProvider.makeContainer(
            identifier: configuration.containerIdentifier
        )
        let database = container.publicCloudDatabase
        let query = CKQuery(
            recordType: Self.recordType,
            predicate: NSPredicate(format: "isActive == %d", 1)
        )

        let response = try await database.records(
            matching: query,
            desiredKeys: [
                "announcementID", "revision", "level",
                "titleZH", "titleEN", "titleES",
                "bodyZH", "bodyEN", "bodyES",
                "minimumBuild", "maximumBuild",
                "publishedAtEpochMs", "expiresAtEpochMs", "isActive"
            ],
            resultsLimit: 100
        )

        return response.matchResults.compactMap { _, result in
            guard case .success(let record) = result else { return nil }
            return Self.makeAnnouncement(record)
        }
    }

    private static func makeAnnouncement(_ record: CKRecord) -> PTAnnouncement? {
        guard
            let id = record["announcementID"] as? String,
            let revision = (record["revision"] as? NSNumber)?.intValue,
            let levelRaw = (record["level"] as? NSNumber)?.intValue,
            let level = PTAnnouncementLevel(rawValue: levelRaw),
            let published = (record["publishedAtEpochMs"] as? NSNumber)?.int64Value
        else { return nil }

        return PTAnnouncement(
            announcementID: id,
            revision: revision,
            level: level,
            titleZH: record["titleZH"] as? String ?? "",
            titleEN: record["titleEN"] as? String ?? "",
            titleES: record["titleES"] as? String ?? "",
            bodyZH: record["bodyZH"] as? String ?? "",
            bodyEN: record["bodyEN"] as? String ?? "",
            bodyES: record["bodyES"] as? String ?? "",
            minimumBuild: (record["minimumBuild"] as? NSNumber)?.intValue,
            maximumBuild: (record["maximumBuild"] as? NSNumber)?.intValue,
            publishedAtEpochMilliseconds: published,
            expiresAtEpochMilliseconds: (record["expiresAtEpochMs"] as? NSNumber)?.int64Value
        )
    }
}
