//
//  PTFeedbackModels.swift
//  CrazyDashboard
//

import Foundation

nonisolated public enum PTFeedbackCategory: String, Codable, Sendable, CaseIterable {
    case bug
    case suggestion
    case usability
    case localization
    case compatibility
    case protocolResearch
    case other
}

nonisolated public enum PTFeedbackModule: String, Codable, Sendable, CaseIterable {
    case app
    case xp400Dashboard
    case obd
    case ymobd
    case navigation
    case carPlay
    case watch
    case widget
    case music
    case ride
    case mock
    case cloud
    case protocolResearch
    case other
}

nonisolated public enum PTFeedbackStatus: Int, Codable, Sendable, CaseIterable {
    case submitted = 0
    case accepted = 10
    case grouped = 20
    case reviewing = 30
    case published = 40
    case planned = 50
    case resolved = 60
    case declined = 70
    case duplicate = 80
    case rejected = 90
}

nonisolated public struct PTFeedbackDraft: Codable, Sendable, Equatable {
    public let feedbackID: UUID
    public var category: PTFeedbackCategory
    public var module: PTFeedbackModule
    public var title: String
    public var body: String
    public var includeDiagnostics: Bool
    public var linkCurrentTelemetrySession: Bool

    public init(
        feedbackID: UUID = UUID(),
        category: PTFeedbackCategory = .bug,
        module: PTFeedbackModule = .app,
        title: String = "",
        body: String = "",
        includeDiagnostics: Bool = true,
        linkCurrentTelemetrySession: Bool = false
    ) {
        self.feedbackID = feedbackID
        self.category = category
        self.module = module
        self.title = title
        self.body = body
        self.includeDiagnostics = includeDiagnostics
        self.linkCurrentTelemetrySession = linkCurrentTelemetrySession
    }
}

nonisolated public struct PTFeedbackLocalRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID { feedbackID }

    public let feedbackID: UUID
    public let category: PTFeedbackCategory
    public let module: PTFeedbackModule
    public let title: String
    public let bodyPreview: String
    public let createdAt: Date
    public var status: PTFeedbackStatus
    public var statusRevision: Int
    public var issueNumber: Int?
    public var resolutionBuild: String?

    public init(
        feedbackID: UUID,
        category: PTFeedbackCategory,
        module: PTFeedbackModule,
        title: String,
        bodyPreview: String,
        createdAt: Date = Date(),
        status: PTFeedbackStatus = .submitted,
        statusRevision: Int = 0,
        issueNumber: Int? = nil,
        resolutionBuild: String? = nil
    ) {
        self.feedbackID = feedbackID
        self.category = category
        self.module = module
        self.title = title
        self.bodyPreview = bodyPreview
        self.createdAt = createdAt
        self.status = status
        self.statusRevision = statusRevision
        self.issueNumber = issueNumber
        self.resolutionBuild = resolutionBuild
    }
}

nonisolated public struct PTFeedbackRemoteStatus: Codable, Sendable, Equatable {
    public let feedbackID: UUID
    public let status: PTFeedbackStatus
    public let statusRevision: Int
    public let issueNumber: Int?
    public let resolutionBuild: String?

    public init(
        feedbackID: UUID,
        status: PTFeedbackStatus,
        statusRevision: Int,
        issueNumber: Int?,
        resolutionBuild: String?
    ) {
        self.feedbackID = feedbackID
        self.status = status
        self.statusRevision = statusRevision
        self.issueNumber = issueNumber
        self.resolutionBuild = resolutionBuild
    }
}


nonisolated public struct PTFeedbackStatusChange: Sendable, Equatable {
    public let feedbackID: UUID
    public let previousStatus: PTFeedbackStatus
    public let previousRevision: Int
    public let current: PTFeedbackLocalRecord

    public init(
        feedbackID: UUID,
        previousStatus: PTFeedbackStatus,
        previousRevision: Int,
        current: PTFeedbackLocalRecord
    ) {
        self.feedbackID = feedbackID
        self.previousStatus = previousStatus
        self.previousRevision = previousRevision
        self.current = current
    }
}

nonisolated public struct PTFeedbackSubmissionResult: Sendable, Equatable {
    public let feedbackID: UUID
    public let uploadedImmediately: Bool

    public init(
        feedbackID: UUID,
        uploadedImmediately: Bool
    ) {
        self.feedbackID = feedbackID
        self.uploadedImmediately = uploadedImmediately
    }
}

nonisolated public enum PTFeedbackError: Error, LocalizedError, Sendable {
    case missingConfiguration(String)
    case invalidTitle
    case invalidBody
    case payloadTooLarge(Int)
    case encryptionFailed
    case cloudAccountUnavailable
    case cloudRecordMalformed
    case storageFailure(String)

    public var errorDescription: String? {
        switch self {
        case .missingConfiguration(let message):
            return message
        case .invalidTitle:
            return "反馈标题不能为空，且不能超过允许长度。"
        case .invalidBody:
            return "反馈内容不能为空，且不能超过允许长度。"
        case .payloadTooLarge(let bytes):
            return "反馈加密前数据过大（\(bytes) bytes）。"
        case .encryptionFailed:
            return "反馈加密失败。"
        case .cloudAccountUnavailable:
            return "当前 iCloud 账号不可用于提交反馈。"
        case .cloudRecordMalformed:
            return "CloudKit 返回的反馈状态格式不正确。"
        case .storageFailure(let message):
            return "反馈本地存储失败：\(message)"
        }
    }
}
