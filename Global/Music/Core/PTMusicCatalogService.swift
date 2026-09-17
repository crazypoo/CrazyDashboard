//
//  PTMusicCatalogService.swift
//  CrazyDashboard
//

import Foundation
import MusicKit

/// Dedicated actor for Apple Music catalog requests.
/// MusicKit result types (Song/Album/Artist/Playlist) are Sendable,
/// so callers can safely receive them across the actor boundary.
public actor PTMusicCatalogService {

    public static let shared = PTMusicCatalogService()

    public init() {}

    public func searchSongs(
        term: String,
        limit: Int = 25
    ) async throws -> [Song] {
        let keyword = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return [] }

        var request = MusicCatalogSearchRequest(
            term: keyword,
            types: [Song.self]
        )
        request.limit = max(1, limit)

        let response = try await request.response()
        return Array(response.songs)
    }

    public func searchAlbums(
        term: String,
        limit: Int = 25
    ) async throws -> [Album] {
        let keyword = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return [] }

        var request = MusicCatalogSearchRequest(
            term: keyword,
            types: [Album.self]
        )
        request.limit = max(1, limit)

        let response = try await request.response()
        return Array(response.albums)
    }

    public func searchArtists(
        term: String,
        limit: Int = 25
    ) async throws -> [Artist] {
        let keyword = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return [] }

        var request = MusicCatalogSearchRequest(
            term: keyword,
            types: [Artist.self]
        )
        request.limit = max(1, limit)

        let response = try await request.response()
        return Array(response.artists)
    }

    public func searchPlaylists(
        term: String,
        limit: Int = 25
    ) async throws -> [Playlist] {
        let keyword = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return [] }

        var request = MusicCatalogSearchRequest(
            term: keyword,
            types: [Playlist.self]
        )
        request.limit = max(1, limit)

        let response = try await request.response()
        return Array(response.playlists)
    }

    public func loadAlbum(_ album: Album) async throws -> Album {
        try await album.with(
            .tracks,
            preferredSource: .catalog
        )
    }

    public func loadPlaylist(_ playlist: Playlist) async throws -> Playlist {
        try await playlist.with(
            .tracks,
            preferredSource: .catalog
        )
    }

    public func loadArtist(_ artist: Artist) async throws -> Artist {
        try await artist.with(
            .albums,
            preferredSource: .catalog
        )
    }
}
