//
//  PTAnnouncementManager.swift
//  CrazyDashboard
//

import Foundation

extension Notification.Name {
    static let ptAnnouncementsDidChange = Notification.Name(
        "CrazyDashboard.PTAnnouncementsDidChange"
    )
}

public actor PTAnnouncementManager {
    public static let shared = PTAnnouncementManager()

    private let repository: PTAnnouncementRepository
    private let revisionStore: PTAnnouncementRevisionStore
    private var cache: [PTAnnouncement] = []

    public init(
        repository: PTAnnouncementRepository = .shared,
        revisionStore: PTAnnouncementRevisionStore = .shared
    ) {
        self.repository = repository
        self.revisionStore = revisionStore
    }

    public func configure(_ configuration: PTCloudKitConfiguration) async {
        await repository.configure(configuration)
    }

    public func announcements() -> [PTAnnouncement] { cache }

    @discardableResult
    public func refresh(includeUnknownAsChange: Bool) async throws -> [PTAnnouncement] {
        let remote = try await repository.fetchActive()
        let currentBuild = Int(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        ) ?? 0
        let now = Int64(Date().timeIntervalSince1970 * 1000)

        let filtered = remote.filter { item in
            if let min = item.minimumBuild, currentBuild < min { return false }
            if let max = item.maximumBuild, currentBuild > max { return false }
            if let expires = item.expiresAtEpochMilliseconds, expires <= now { return false }
            return true
        }.sorted {
            $0.publishedAtEpochMilliseconds > $1.publishedAtEpochMilliseconds
        }

        cache = filtered
        let changes = await revisionStore.changedAnnouncements(
            from: filtered,
            includeUnknown: includeUnknownAsChange
        )
        await MainActor.run {
            NotificationCenter.default.post(
                name: .ptAnnouncementsDidChange,
                object: nil
            )
        }
        return changes
    }
}
