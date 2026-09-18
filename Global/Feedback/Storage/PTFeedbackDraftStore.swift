//
//  PTFeedbackDraftStore.swift
//  CrazyDashboard
//
//  Optional local compose draft. Never synced to iCloud.
//

import Foundation

public actor PTFeedbackDraftStore {
    public static let shared = PTFeedbackDraftStore()

    private let defaults: UserDefaults
    private let key = "CrazyDashboard.Feedback.ComposeDraft"

    public init(
        defaults: UserDefaults = .standard
    ) {
        self.defaults = defaults
    }

    public func save(
        _ draft: PTFeedbackDraft
    ) {
        guard let data = try? JSONEncoder().encode(draft) else {
            return
        }

        defaults.set(
            data,
            forKey: key
        )
    }

    public func load() -> PTFeedbackDraft? {
        guard let data = defaults.data(
            forKey: key
        ) else {
            return nil
        }

        return try? JSONDecoder().decode(
            PTFeedbackDraft.self,
            from: data
        )
    }

    public func clear() {
        defaults.removeObject(
            forKey: key
        )
    }
}
