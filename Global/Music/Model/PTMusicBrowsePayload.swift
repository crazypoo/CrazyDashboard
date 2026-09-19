//
//  PTMusicBrowsePayload.swift
//  CrazyDashboard
//
//  English: One immutable payload replaces four independently-mutated arrays.
//  Español: Un único payload inmutable sustituye cuatro arrays mutados por separado.
//  中文：用一个不可变载荷替代四个彼此独立变化的数组。
//

import Foundation
import MusicKit

public enum PTMusicBrowsePayload: Sendable {
    case songs([Song])
    case albums([Album])
    case artists([Artist])
    case playlists([Playlist])

    public var count: Int {
        switch self {
        case .songs(let values):
            return values.count
        case .albums(let values):
            return values.count
        case .artists(let values):
            return values.count
        case .playlists(let values):
            return values.count
        }
    }

    public var category: PTMusicBrowseCategory {
        switch self {
        case .songs:
            return .songs
        case .albums:
            return .albums
        case .artists:
            return .artists
        case .playlists:
            return .playlists
        }
    }

    public func appending(_ next: PTMusicBrowsePayload) -> PTMusicBrowsePayload? {
        guard category == next.category else { return nil }

        switch (self, next) {
        case (.songs(let current), .songs(let values)):
            return .songs(current + values)
        case (.albums(let current), .albums(let values)):
            return .albums(current + values)
        case (.artists(let current), .artists(let values)):
            return .artists(current + values)
        case (.playlists(let current), .playlists(let values)):
            return .playlists(current + values)
        default:
            return nil
        }
    }
}

public struct PTMusicPageState: Equatable, Sendable {
    public let offset: Int
    public let pageSize: Int
    public let hasMore: Bool
    public let isLoadingNextPage: Bool

    public init(
        offset: Int = 0,
        pageSize: Int,
        hasMore: Bool = true,
        isLoadingNextPage: Bool = false
    ) {
        self.offset = offset
        self.pageSize = pageSize
        self.hasMore = hasMore
        self.isLoadingNextPage = isLoadingNextPage
    }

    public func loadingNextPage() -> PTMusicPageState {
        PTMusicPageState(
            offset: offset,
            pageSize: pageSize,
            hasMore: hasMore,
            isLoadingNextPage: true
        )
    }
}

public struct PTMusicBrowseCachePolicy: Sendable {
    public let libraryTTL: TimeInterval
    public let recentlyPlayedTTL: TimeInterval
    public let searchTTL: TimeInterval
    public let searchCacheLimit: Int

    public init(
        libraryTTL: TimeInterval = 120,
        recentlyPlayedTTL: TimeInterval = 45,
        searchTTL: TimeInterval = 60,
        searchCacheLimit: Int = 20
    ) {
        self.libraryTTL = max(0, libraryTTL)
        self.recentlyPlayedTTL = max(0, recentlyPlayedTTL)
        self.searchTTL = max(0, searchTTL)
        self.searchCacheLimit = max(0, searchCacheLimit)
    }

    public func ttl(for key: PTMusicQueryKey) -> TimeInterval {
        switch key.surface {
        case .search:
            return searchTTL
        case .library:
            return key.source == .recentlyPlayed
                ? recentlyPlayedTTL
                : libraryTTL
        case .collectionDetail:
            return libraryTTL
        }
    }
}
