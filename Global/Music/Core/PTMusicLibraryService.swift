//
//  PTMusicLibraryService.swift
//  CrazyDashboard
//

import Foundation
import MusicKit

/// Dedicated actor for the user's Apple Music library.
/// Keep library/catalog I/O out of UIKit and dashboard refresh callbacks.
public actor PTMusicLibraryService {

    public static let shared = PTMusicLibraryService()

    public init() {}

    public func songs(limit: Int = 100, offset: Int = 0) async throws -> [Song] {
        var request = MusicLibraryRequest<Song>()
        request.limit = max(0, limit)
        request.offset = max(0, offset)

        let response = try await request.response()
        return Array(response.items)
    }

    public func albums(limit: Int = 100, offset: Int = 0) async throws -> [Album] {
        var request = MusicLibraryRequest<Album>()
        request.limit = max(0, limit)
        request.offset = max(0, offset)

        let response = try await request.response()
        return Array(response.items)
    }

    public func artists(limit: Int = 100, offset: Int = 0) async throws -> [Artist] {
        var request = MusicLibraryRequest<Artist>()
        request.limit = max(0, limit)
        request.offset = max(0, offset)

        let response = try await request.response()
        return Array(response.items)
    }

    public func playlists(limit: Int = 100, offset: Int = 0) async throws -> [Playlist] {
        var request = MusicLibraryRequest<Playlist>()
        request.limit = max(0, limit)
        request.offset = max(0, offset)

        let response = try await request.response()
        return Array(response.items)
    }

    public func searchSongs(
        term: String,
        limit: Int = 50
    ) async throws -> [Song] {
        let keyword = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return [] }

        var request = MusicLibrarySearchRequest(
            term: keyword,
            types: [Song.self]
        )
        request.limit = max(1, limit)

        let response = try await request.response()
        return Array(response.songs)
    }

    public func recentlyPlayedSongs(limit: Int = 20) async throws -> [Song] {
        var request = MusicRecentlyPlayedRequest<Song>()
        request.limit = max(1, limit)

        let response = try await request.response()
        return Array(response.items)
    }

    public func searchAlbums(
        term: String,
        limit: Int = 50
    ) async throws -> [Album] {
        let keyword = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return [] }

        var request = MusicLibrarySearchRequest(
            term: keyword,
            types: [Album.self]
        )
        request.limit = max(1, limit)

        let response = try await request.response()
        return Array(response.albums)
    }

    public func searchArtists(
        term: String,
        limit: Int = 50
    ) async throws -> [Artist] {
        let keyword = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return [] }

        var request = MusicLibrarySearchRequest(
            term: keyword,
            types: [Artist.self]
        )
        request.limit = max(1, limit)

        let response = try await request.response()
        return Array(response.artists)
    }

    public func searchPlaylists(
        term: String,
        limit: Int = 50
    ) async throws -> [Playlist] {
        let keyword = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return [] }

        var request = MusicLibrarySearchRequest(
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
            preferredSource: .library
        )
    }

    public func loadPlaylist(_ playlist: Playlist) async throws -> Playlist {
        try await playlist.with(
            .tracks,
            preferredSource: .library
        )
    }

    public func loadArtist(_ artist: Artist) async throws -> Artist {
        try await artist.with(
            .albums,
            preferredSource: .library
        )
    }
}
