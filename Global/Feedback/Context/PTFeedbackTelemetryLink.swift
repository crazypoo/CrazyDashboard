//
//  PTFeedbackTelemetryLink.swift
//  CrazyDashboard
//
//  Feedback never starts / stops TelemetryResearch.
//  It can only reference an already-running anonymous session.
//

import Foundation

nonisolated public enum PTFeedbackTelemetryLink {
    public static func currentSessionID() async -> UUID? {
        let state = await PTTelemetryResearchManager.shared.currentState()

        switch state {
        case .recording(let sessionID),
             .preparingUpload(let sessionID):
            return sessionID
        case .idle, .uploading:
            return nil
        }
    }
}
