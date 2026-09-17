//
//  PTMusicModuleBootstrap.swift
//  CrazyDashboard
//
//  Optional tiny bridge for SceneDelegate/App startup.
//

import Foundation

@MainActor
public enum PTMusicModuleBootstrap {

    /// Call after the app's root UI has been created.
    /// Does not show the Music permission prompt.
    public static func start() {
        Task { @MainActor in
            await PTMusicCoordinator.shared.bootstrap(
                requestAuthorizationIfNeeded: false
            )
        }
    }

    public static func sceneWillEnterForeground() {
        PTMusicCoordinator.shared.sceneWillEnterForeground()
    }

    public static func sceneDidEnterBackground() {
        PTMusicCoordinator.shared.sceneDidEnterBackground()
    }
}
