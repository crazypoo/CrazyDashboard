//
//  PTMusicTrack.swift
//  CrazyDashboard
//

import Foundation
import MusicKit

public struct PTMusicTrack: Identifiable, Hashable, Sendable {

    public let id: String
    public let title: String
    public let artist: String
    public let albumTitle: String?
    public let duration: TimeInterval?
    public let artwork: Artwork?
    public let source: PTMusicSource

    public init(
        id: String,
        title: String,
        artist: String,
        albumTitle: String? = nil,
        duration: TimeInterval? = nil,
        artwork: Artwork? = nil,
        source: PTMusicSource
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.albumTitle = albumTitle
        self.duration = duration
        self.artwork = artwork
        self.source = source
    }

    public init(song: Song, source: PTMusicSource) {
        self.init(
            id: song.id.rawValue,
            title: song.title,
            artist: song.artistName,
            albumTitle: song.albumTitle,
            duration: song.duration,
            artwork: song.artwork,
            source: source
        )
    }

    public init(musicVideo: MusicVideo, source: PTMusicSource) {
        self.init(
            id: musicVideo.id.rawValue,
            title: musicVideo.title,
            artist: musicVideo.artistName,
            albumTitle: musicVideo.albumTitle,
            duration: musicVideo.duration,
            artwork: musicVideo.artwork,
            source: source
        )
    }


    public init(track: Track, source: PTMusicSource) {
        self.init(
            id: track.id.rawValue,
            title: track.title,
            artist: track.artistName,
            albumTitle: track.albumTitle,
            duration: track.duration,
            artwork: track.artwork,
            source: source
        )
    }

    public init(entry: MusicPlayer.Queue.Entry, source: PTMusicSource) {
        if let item = entry.item {
            switch item {
            case .song(let song):
                self.init(song: song, source: source)
                return

            case .musicVideo(let musicVideo):
                self.init(musicVideo: musicVideo, source: source)
                return
            }
        }

        let duration: TimeInterval?
        if let startTime = entry.startTime, let endTime = entry.endTime {
            duration = max(0, endTime - startTime)
        } else {
            duration = nil
        }

        self.init(
            id: entry.id,
            title: entry.title,
            artist: entry.subtitle ?? "",
            albumTitle: nil,
            duration: duration,
            artwork: entry.artwork,
            source: source
        )
    }
}
