//
//  PTAnnouncementModels.swift
//  CrazyDashboard
//

import Foundation

nonisolated public enum PTAnnouncementLevel: Int, Codable, Sendable, CaseIterable {
    case info = 0
    case important = 10
    case critical = 20
}

nonisolated public struct PTAnnouncement: Codable, Sendable, Equatable, Identifiable {
    public var id: String { announcementID }

    public let announcementID: String
    public let revision: Int
    public let level: PTAnnouncementLevel
    public let titleZH: String
    public let titleEN: String
    public let titleES: String
    public let bodyZH: String
    public let bodyEN: String
    public let bodyES: String
    public let minimumBuild: Int?
    public let maximumBuild: Int?
    public let publishedAtEpochMilliseconds: Int64
    public let expiresAtEpochMilliseconds: Int64?

    public init(
        announcementID: String,
        revision: Int,
        level: PTAnnouncementLevel,
        titleZH: String,
        titleEN: String,
        titleES: String,
        bodyZH: String,
        bodyEN: String,
        bodyES: String,
        minimumBuild: Int?,
        maximumBuild: Int?,
        publishedAtEpochMilliseconds: Int64,
        expiresAtEpochMilliseconds: Int64?
    ) {
        self.announcementID = announcementID
        self.revision = revision
        self.level = level
        self.titleZH = titleZH
        self.titleEN = titleEN
        self.titleES = titleES
        self.bodyZH = bodyZH
        self.bodyEN = bodyEN
        self.bodyES = bodyES
        self.minimumBuild = minimumBuild
        self.maximumBuild = maximumBuild
        self.publishedAtEpochMilliseconds = publishedAtEpochMilliseconds
        self.expiresAtEpochMilliseconds = expiresAtEpochMilliseconds
    }

    public func localizedTitle(languageIdentifier: String) -> String {
        let value = languageIdentifier.lowercased()
        if value.hasPrefix("zh") { return titleZH.isEmpty ? titleEN : titleZH }
        if value.hasPrefix("es") { return titleES.isEmpty ? titleEN : titleES }
        return titleEN.isEmpty ? titleZH : titleEN
    }

    public func localizedBody(languageIdentifier: String) -> String {
        let value = languageIdentifier.lowercased()
        if value.hasPrefix("zh") { return bodyZH.isEmpty ? bodyEN : bodyZH }
        if value.hasPrefix("es") { return bodyES.isEmpty ? bodyEN : bodyES }
        return bodyEN.isEmpty ? bodyZH : bodyEN
    }
}

nonisolated public enum PTFeatureSuggestionState: Int, Codable, Sendable, CaseIterable {
    case reviewing = 30
    case published = 40
    case planned = 50
    case resolved = 60
    case declined = 70
}

nonisolated public struct PTFeatureSuggestion: Codable, Sendable, Equatable, Identifiable {
    public var id: String { suggestionID }

    public let suggestionID: String
    public let title: String
    public let summary: String
    public let module: String
    public let state: PTFeatureSuggestionState
    public let voteCount: Int
    public let reportCount: Int
    public let issueNumber: Int?
    public let isVotingOpen: Bool
    public let revision: Int
    public let updatedAtEpochMilliseconds: Int64

    public init(
        suggestionID: String,
        title: String,
        summary: String,
        module: String,
        state: PTFeatureSuggestionState,
        voteCount: Int,
        reportCount: Int,
        issueNumber: Int?,
        isVotingOpen: Bool,
        revision: Int,
        updatedAtEpochMilliseconds: Int64
    ) {
        self.suggestionID = suggestionID
        self.title = title
        self.summary = summary
        self.module = module
        self.state = state
        self.voteCount = voteCount
        self.reportCount = reportCount
        self.issueNumber = issueNumber
        self.isVotingOpen = isVotingOpen
        self.revision = revision
        self.updatedAtEpochMilliseconds = updatedAtEpochMilliseconds
    }
}
