//
//  PTMusicPlaybackSnapshot.swift
//  CrazyDashboard
//

import Foundation
import MusicKit

public enum PTMusicPlaybackStatus: String, Sendable {
    case stopped
    case playing
    case paused
    case interrupted
    case seekingForward
    case seekingBackward
    case unknown
}

public enum PTMusicRepeatMode: String, CaseIterable, Sendable {
    case none
    case one
    case all
}

public struct PTMusicPlaybackSnapshot: Equatable, Sendable {

    public let mode: PTMusicPlayerMode
    public let track: PTMusicTrack?
    public let currentTime: TimeInterval
    public let status: PTMusicPlaybackStatus
    public let shuffleEnabled: Bool
    public let repeatMode: PTMusicRepeatMode

    public init(
        mode: PTMusicPlayerMode,
        track: PTMusicTrack?,
        currentTime: TimeInterval,
        status: PTMusicPlaybackStatus,
        shuffleEnabled: Bool,
        repeatMode: PTMusicRepeatMode
    ) {
        self.mode = mode
        self.track = track
        self.currentTime = currentTime
        self.status = status
        self.shuffleEnabled = shuffleEnabled
        self.repeatMode = repeatMode
    }

    public static func empty(mode: PTMusicPlayerMode) -> Self {
        .init(
            mode: mode,
            track: nil,
            currentTime: 0,
            status: .stopped,
            shuffleEnabled: false,
            repeatMode: .none
        )
    }

    public var isPlaying: Bool {
        status == .playing
    }

    public var duration: TimeInterval {
        max(0, track?.duration ?? 0)
    }

    public var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    public var hasCurrentItem: Bool {
        track != nil
    }
}

extension PTMusicPlaybackStatus {

    init(_ status: MusicPlayer.PlaybackStatus) {
        switch status {
        case .stopped:
            self = .stopped
        case .playing:
            self = .playing
        case .paused:
            self = .paused
        case .interrupted:
            self = .interrupted
        case .seekingForward:
            self = .seekingForward
        case .seekingBackward:
            self = .seekingBackward
        @unknown default:
            self = .unknown
        }
    }
}
