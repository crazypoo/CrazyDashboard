//
//  PTFeatureSuggestionManager.swift
//  CrazyDashboard
//

import Foundation

extension Notification.Name {
    static let ptFeatureSuggestionsDidChange = Notification.Name(
        "CrazyDashboard.PTFeatureSuggestionsDidChange"
    )
}

public actor PTFeatureSuggestionManager {
    public static let shared = PTFeatureSuggestionManager()

    private let repository: PTFeatureSuggestionRepository
    private var cache: [PTFeatureSuggestion] = []

    public init(repository: PTFeatureSuggestionRepository = .shared) {
        self.repository = repository
    }

    public func configure(_ configuration: PTCloudKitConfiguration) async {
        await repository.configure(configuration)
    }

    public func suggestions() -> [PTFeatureSuggestion] { cache }

    @discardableResult
    public func refresh() async throws -> [PTFeatureSuggestion] {
        let values = try await repository.fetchVisible().sorted {
            if $0.voteCount != $1.voteCount { return $0.voteCount > $1.voteCount }
            if $0.reportCount != $1.reportCount { return $0.reportCount > $1.reportCount }
            return $0.updatedAtEpochMilliseconds > $1.updatedAtEpochMilliseconds
        }
        cache = values
        await MainActor.run {
            NotificationCenter.default.post(
                name: .ptFeatureSuggestionsDidChange,
                object: nil
            )
        }
        return values
    }

    public func isVoted(suggestionID: String) async throws -> Bool {
        try await repository.isVoted(suggestionID: suggestionID)
    }

    public func setVoted(_ voted: Bool, suggestionID: String) async throws {
        try await repository.setVoted(voted, suggestionID: suggestionID)
        _ = try? await refresh()
    }
}
