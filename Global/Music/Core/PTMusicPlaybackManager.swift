//
//  PTMusicPlaybackManager.swift
//  CrazyDashboard
//

import Foundation
import Combine
import MusicKit

public enum PTMusicPlaybackError: LocalizedError {
    case emptyQueue

    public var errorDescription: String? {
        switch self {
        case .emptyQueue:
            return "没有可播放的音乐。"
        }
    }
}

@MainActor
public final class PTMusicPlaybackManager: ObservableObject {

    public static let shared = PTMusicPlaybackManager()

    public let systemPlayer = SystemMusicPlayer.shared
    public let applicationPlayer = ApplicationMusicPlayer.shared

    @Published public private(set) var mode: PTMusicPlayerMode = .system
    @Published public private(set) var snapshot: PTMusicPlaybackSnapshot = .empty(mode: .system)
    @Published public private(set) var lastErrorDescription: String?

    private var cancellables = Set<AnyCancellable>()
    private var progressTimer: AnyCancellable?

    private init() {
        bindPlayerObservers()
        refreshSnapshot()
    }

    public func setMode(_ newMode: PTMusicPlayerMode) {
        guard mode != newMode else { return }

        mode = newMode
        refreshSnapshot()
    }

    public func refresh() {
        refreshSnapshot()
    }

    public func play() async throws {
        do {
            try await activePlayer.play()
            lastErrorDescription = nil
            refreshSnapshot()
        } catch {
            lastErrorDescription = error.localizedDescription
            throw error
        }
    }

    public func pause() {
        activePlayer.pause()
        refreshSnapshot()
    }

    public func togglePlayPause() async throws {
        if snapshot.isPlaying {
            pause()
        } else {
            try await play()
        }
    }

    public func next() async throws {
        do {
            try await activePlayer.skipToNextEntry()
            lastErrorDescription = nil
            refreshSnapshot()
        } catch {
            lastErrorDescription = error.localizedDescription
            throw error
        }
    }

    public func previous() async throws {
        do {
            try await activePlayer.skipToPreviousEntry()
            lastErrorDescription = nil
            refreshSnapshot()
        } catch {
            lastErrorDescription = error.localizedDescription
            throw error
        }
    }

    public func seek(to seconds: TimeInterval) {
        let upperBound = snapshot.duration > 0 ? snapshot.duration : seconds
        activePlayer.playbackTime = min(max(seconds, 0), max(upperBound, 0))
        refreshSnapshot()
    }

    public func setShuffleEnabled(_ enabled: Bool) {
        activePlayer.state.shuffleMode = enabled ? .songs : .off
        refreshSnapshot()
    }

    public func setRepeatMode(_ repeatMode: PTMusicRepeatMode) {
        switch repeatMode {
        case .none:
            activePlayer.state.repeatMode = .none
        case .one:
            activePlayer.state.repeatMode = .one
        case .all:
            activePlayer.state.repeatMode = .all
        }

        refreshSnapshot()
    }

    public func cycleRepeatMode() {
        switch snapshot.repeatMode {
        case .none:
            setRepeatMode(.all)
        case .all:
            setRepeatMode(.one)
        case .one:
            setRepeatMode(.none)
        }
    }

    // MARK: - Play concrete music

    public func play(
        song: Song,
        mode preferredMode: PTMusicPlayerMode? = nil
    ) async throws {
        try await play(
            songs: [song],
            startingAt: song,
            mode: preferredMode
        )
    }

    public func play(
        songs: [Song],
        startingAt: Song? = nil,
        mode preferredMode: PTMusicPlayerMode? = nil
    ) async throws {
        guard !songs.isEmpty else {
            throw PTMusicPlaybackError.emptyQueue
        }

        if let preferredMode {
            setMode(preferredMode)
        }

        let startingSong = startingAt ?? songs.first

        do {
            switch mode {
            case .system:
                systemPlayer.queue = MusicPlayer.Queue(
                    for: songs,
                    startingAt: startingSong
                )
                try await systemPlayer.prepareToPlay()
                try await systemPlayer.play()

            case .application:
                applicationPlayer.queue = ApplicationMusicPlayer.Queue(
                    for: songs,
                    startingAt: startingSong
                )
                try await applicationPlayer.prepareToPlay()
                try await applicationPlayer.play()
            }

            lastErrorDescription = nil
            refreshSnapshot()
        } catch {
            lastErrorDescription = error.localizedDescription
            throw error
        }
    }


public func play(
    track: Track,
    mode preferredMode: PTMusicPlayerMode? = nil
) async throws {
    try await play(
        tracks: [track],
        startingAt: track,
        mode: preferredMode
    )
}

public func play(
    tracks: [Track],
    startingAt: Track? = nil,
    mode preferredMode: PTMusicPlayerMode? = nil
) async throws {
    guard !tracks.isEmpty else {
        throw PTMusicPlaybackError.emptyQueue
    }

    if let preferredMode {
        setMode(preferredMode)
    }

    let startingTrack = startingAt ?? tracks.first

    do {
        switch mode {
        case .system:
            systemPlayer.queue = MusicPlayer.Queue(
                for: tracks,
                startingAt: startingTrack
            )
            try await systemPlayer.prepareToPlay()
            try await systemPlayer.play()

        case .application:
            applicationPlayer.queue = ApplicationMusicPlayer.Queue(
                for: tracks,
                startingAt: startingTrack
            )
            try await applicationPlayer.prepareToPlay()
            try await applicationPlayer.play()
        }

        lastErrorDescription = nil
        refreshSnapshot()
    } catch {
        lastErrorDescription = error.localizedDescription
        throw error
    }
}

    /// Appends a song to CrazyDashboard's independent Riding Queue.
    /// This intentionally does not mutate the SystemMusicPlayer queue.
    public func appendToRidingQueue(_ song: Song) async throws {
        do {
            try await applicationPlayer.queue.insert(song, position: .tail)
            lastErrorDescription = nil

            if mode == .application {
                refreshSnapshot()
            }
        } catch {
            lastErrorDescription = error.localizedDescription
            throw error
        }
    }

    public func playNextInRidingQueue(_ song: Song) async throws {
        do {
            try await applicationPlayer.queue.insert(song, position: .afterCurrentEntry)
            lastErrorDescription = nil

            if mode == .application {
                refreshSnapshot()
            }
        } catch {
            lastErrorDescription = error.localizedDescription
            throw error
        }
    }

    // MARK: - Snapshot

    private var activePlayer: MusicPlayer {
        switch mode {
        case .system:
            return systemPlayer
        case .application:
            return applicationPlayer
        }
    }

    private var activeEntry: MusicPlayer.Queue.Entry? {
        switch mode {
        case .system:
            return systemPlayer.queue.currentEntry
        case .application:
            return applicationPlayer.queue.currentEntry
        }
    }

    private func refreshSnapshot() {
        let player = activePlayer
        let state = player.state

        let track = activeEntry.map {
            PTMusicTrack(
                entry: $0,
                source: mode == .system ? .systemPlayer : .applicationPlayer
            )
        }

        let repeatMode: PTMusicRepeatMode
        switch state.repeatMode ?? .none {
        case .one:
            repeatMode = .one
        case .all:
            repeatMode = .all
        case .none:
            repeatMode = .none
        @unknown default:
            repeatMode = .none
        }

        snapshot = PTMusicPlaybackSnapshot(
            mode: mode,
            track: track,
            currentTime: max(0, player.playbackTime),
            status: PTMusicPlaybackStatus(state.playbackStatus),
            shuffleEnabled: state.shuffleMode == .songs,
            repeatMode: repeatMode
        )

        updateProgressTimerIfNeeded()
    }

    // MARK: - Observation

    private func bindPlayerObservers() {
        systemPlayer.state.objectWillChange
            .sink { [weak self] _ in
                self?.scheduleSnapshotRefresh()
            }
            .store(in: &cancellables)

        systemPlayer.queue.objectWillChange
            .sink { [weak self] _ in
                self?.scheduleSnapshotRefresh()
            }
            .store(in: &cancellables)

        applicationPlayer.state.objectWillChange
            .sink { [weak self] _ in
                self?.scheduleSnapshotRefresh()
            }
            .store(in: &cancellables)

        applicationPlayer.queue.objectWillChange
            .sink { [weak self] _ in
                self?.scheduleSnapshotRefresh()
            }
            .store(in: &cancellables)
    }

    private func scheduleSnapshotRefresh() {
        /*
         objectWillChange is delivered before the observable value mutates.
         Yield once so we read the post-change MusicKit state.
        */
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.refreshSnapshot()
        }
    }

    private func updateProgressTimerIfNeeded() {
        if snapshot.isPlaying {
            guard progressTimer == nil else { return }

            progressTimer = Timer.publish(
                every: 0.5,
                on: .main,
                in: .common
            )
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshSnapshot()
            }
        } else {
            progressTimer?.cancel()
            progressTimer = nil
        }
    }
}
