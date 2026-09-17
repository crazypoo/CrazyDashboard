//
//  PTMusicPlayerMode.swift
//  CrazyDashboard
//

import Foundation

public enum PTMusicPlayerMode: String, CaseIterable, Sendable {
    /// Controls the system Music app.
    case system

    /// Uses CrazyDashboard's independent ApplicationMusicPlayer queue.
    case application

    public var displayName: String {
        switch self {
        case .system:
            return "Apple Music"
        case .application:
            return "Riding Queue"
        }
    }
}
