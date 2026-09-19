//
//  PTMusicBrowseCategory.swift
//  CrazyDashboard
//

import Foundation
import MusicKit

public enum PTMusicBrowseCategory: Int, CaseIterable, Hashable, Sendable {
    case songs
    case albums
    case artists
    case playlists

    public var title: String {
        switch self {
        case .songs:
            return NSLocalizedString("歌曲", comment: "")
        case .albums:
            return NSLocalizedString("专辑", comment: "")
        case .artists:
            return NSLocalizedString("歌手", comment: "")
        case .playlists:
            return NSLocalizedString("歌单", comment: "")
        }
    }
}

extension PTMusicSource {
    var musicPropertySource: MusicPropertySource {
        switch self {
        case .library:
            return .library
        case .systemPlayer, .applicationPlayer, .catalog, .recentlyPlayed:
            return .catalog
        }
    }
}
