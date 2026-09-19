//
//  PTFeedbackTelemetryLink.swift
//  CrazyDashboard
//
//  Feedback never starts / stops TelemetryResearch.
//  It only references an already-running anonymous session.
//

import Foundation

nonisolated public struct PTFeedbackTelemetryLinkSnapshot: Sendable, Equatable {
    public let sessionID: UUID
    public let sessionOffsetMilliseconds: Int64

    public init(
        sessionID: UUID,
        sessionOffsetMilliseconds: Int64
    ) {
        self.sessionID = sessionID
        self.sessionOffsetMilliseconds = max(
            0,
            sessionOffsetMilliseconds
        )
    }
}

nonisolated public enum PTFeedbackTelemetryLink {
    public static func currentLink() async
        -> PTFeedbackTelemetryLinkSnapshot? {
        guard let snapshot =
                await PTTelemetryResearchManager.shared.activeSessionSnapshot() else {
            return nil
        }

        return .init(
            sessionID: snapshot.sessionID,
            sessionOffsetMilliseconds:
                snapshot.elapsedMilliseconds
        )
    }

    /// Kept for source compatibility with Build 71 UI code.
    public static func currentSessionID() async -> UUID? {
        await currentLink()?.sessionID
    }
}
