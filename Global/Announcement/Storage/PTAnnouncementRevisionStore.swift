//
//  PTAnnouncementRevisionStore.swift
//  CrazyDashboard
//

import Foundation

public actor PTAnnouncementRevisionStore {
    public static let shared = PTAnnouncementRevisionStore()

    private let defaults: UserDefaults
    private let key = "CrazyDashboard.Announcement.Revisions"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func changedAnnouncements(
        from values: [PTAnnouncement],
        includeUnknown: Bool
    ) -> [PTAnnouncement] {
        let previous = revisions()
        var updated = previous
        var changed: [PTAnnouncement] = []

        for item in values {
            let old = previous[item.announcementID]
            if let old {
                if item.revision > old { changed.append(item) }
            } else if includeUnknown {
                changed.append(item)
            }
            updated[item.announcementID] = max(item.revision, old ?? 0)
        }

        defaults.set(updated, forKey: key)
        return changed
    }

    public func seed(_ values: [PTAnnouncement]) {
        var updated = revisions()
        for item in values {
            updated[item.announcementID] = max(
                item.revision,
                updated[item.announcementID] ?? 0
            )
        }
        defaults.set(updated, forKey: key)
    }

    private func revisions() -> [String: Int] {
        defaults.dictionary(forKey: key)?.reduce(into: [:]) { result, pair in
            if let number = pair.value as? NSNumber {
                result[pair.key] = number.intValue
            } else if let value = pair.value as? Int {
                result[pair.key] = value
            }
        } ?? [:]
    }
}
