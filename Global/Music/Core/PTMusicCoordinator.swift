//
//  PTMusicCoordinator.swift
//  CrazyDashboard
//

import Foundation
import UIKit
import Combine
import MusicKit

@MainActor
public final class PTMusicCoordinator {

    public static let shared = PTMusicCoordinator()

    public let authorizationManager: PTMusicAuthorizationManager
    public let playbackManager: PTMusicPlaybackManager

    private var cancellables = Set<AnyCancellable>()
    private var isBootstrapped = false

    private init(
        authorizationManager: PTMusicAuthorizationManager,
        playbackManager: PTMusicPlaybackManager
    ) {
        self.authorizationManager = authorizationManager
        self.playbackManager = playbackManager
        installLifecycleObservers()
    }

    private convenience init() {
        self.init(
            authorizationManager: PTMusicAuthorizationManager.shared,
            playbackManager: PTMusicPlaybackManager.shared
        )
    }

    /// Call once from app startup, or lazily when the Music screen is opened.
    ///
    /// Pass `requestAuthorizationIfNeeded: false` at app startup if you don't
    /// want a permission prompt before the user enters the Music feature.
    public func bootstrap(
        requestAuthorizationIfNeeded: Bool = false
    ) async {
        authorizationManager.refreshAuthorizationStatus()

        if authorizationManager.authorizationStatus == .notDetermined,
           requestAuthorizationIfNeeded {
            _ = await authorizationManager.requestAuthorization()
        }

        if authorizationManager.isAuthorized {
            await authorizationManager.refreshSubscription()
            authorizationManager.startObservingSubscriptionUpdates()
        }

        playbackManager.refresh()
        isBootstrapped = true
    }

    public func refresh() async {
        authorizationManager.refreshAuthorizationStatus()

        if authorizationManager.isAuthorized {
            await authorizationManager.refreshSubscription()
            authorizationManager.startObservingSubscriptionUpdates()
        }

        playbackManager.refresh()
    }

    public func sceneWillEnterForeground() {
        Task { @MainActor [weak self] in
            await self?.refresh()
        }
    }

    public func sceneDidEnterBackground() {
        // SystemMusicPlayer continues independently.
        // Do not stop it here.
    }

    private func installLifecycleObservers() {
        NotificationCenter.default.publisher(
            for: UIApplication.didBecomeActiveNotification
        )
        .sink { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isBootstrapped else { return }
                await self.refresh()
            }
        }
        .store(in: &cancellables)
    }
}
