//
//  PTMusicAuthorizationManager.swift
//  CrazyDashboard
//

import Foundation
import Combine
import MusicKit

@MainActor
public final class PTMusicAuthorizationManager: ObservableObject {

    public static let shared = PTMusicAuthorizationManager()

    @Published public private(set) var authorizationStatus: MusicAuthorization.Status
    @Published public private(set) var subscription: MusicSubscription?
    @Published public private(set) var lastErrorDescription: String?

    private var subscriptionUpdatesTask: Task<Void, Never>?

    private init() {
        authorizationStatus = MusicAuthorization.currentStatus
    }

    public var isAuthorized: Bool {
        authorizationStatus == .authorized
    }

    public var canPlayCatalogContent: Bool {
        subscription?.canPlayCatalogContent == true
    }

    public var canBecomeSubscriber: Bool {
        subscription?.canBecomeSubscriber == true
    }

    public var hasCloudLibraryEnabled: Bool {
        subscription?.hasCloudLibraryEnabled == true
    }

    public func refreshAuthorizationStatus() {
        authorizationStatus = MusicAuthorization.currentStatus
    }

    @discardableResult
    public func requestAuthorization() async -> MusicAuthorization.Status {
        let result = await MusicAuthorization.request()
        authorizationStatus = result

        if result == .authorized {
            await refreshSubscription()
            startObservingSubscriptionUpdates()
        }

        return result
    }

    public func refreshSubscription() async {
        guard isAuthorized else {
            subscription = nil
            return
        }

        do {
            subscription = try await MusicSubscription.current
            lastErrorDescription = nil
        } catch {
            lastErrorDescription = error.localizedDescription
        }
    }

    public func startObservingSubscriptionUpdates() {
        guard subscriptionUpdatesTask == nil else { return }

        subscriptionUpdatesTask = Task { [weak self] in
            for await update in MusicSubscription.subscriptionUpdates {
                guard !Task.isCancelled else { break }
                self?.subscription = update
                self?.lastErrorDescription = nil
            }
        }
    }

    public func stopObservingSubscriptionUpdates() {
        subscriptionUpdatesTask?.cancel()
        subscriptionUpdatesTask = nil
    }
}
