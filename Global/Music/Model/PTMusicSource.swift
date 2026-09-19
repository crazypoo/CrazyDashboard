//
//  PTMusicSource.swift
//  CrazyDashboard
//

import Foundation

public enum PTMusicSource: String, Hashable, Sendable {
    case systemPlayer
    case applicationPlayer
    case catalog
    case library
    case recentlyPlayed
}
