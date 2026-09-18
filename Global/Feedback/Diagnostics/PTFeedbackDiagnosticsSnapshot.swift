//
//  PTFeedbackDiagnosticsSnapshot.swift
//  CrazyDashboard
//

import Foundation

nonisolated public struct PTFeedbackDiagnosticsSnapshot: Codable, Sendable, Equatable {
    /// Intentionally limited to low-risk coarse diagnostics.
    /// No UUID / VIN / MAC / GPS / route / account / email is permitted.
    public let values: [String: String]

    public init(values: [String: String]) {
        self.values = values
    }
}
