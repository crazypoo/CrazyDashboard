//
//  PTMusicRouter.swift
//  CrazyDashboard
//

import UIKit

@MainActor
public enum PTMusicRouter {

    public static func openPlayer(
        from presenter: UIViewController,
        animated: Bool = true
    ) {
        push(
            PTMusicViewController(),
            from: presenter,
            animated: animated
        )
    }

    public static func openSearch(
        from presenter: UIViewController,
        animated: Bool = true
    ) {
        push(
            PTMusicSearchViewController(),
            from: presenter,
            animated: animated
        )
    }

    public static func openLibrary(
        from presenter: UIViewController,
        animated: Bool = true
    ) {
        push(
            PTMusicLibraryViewController(),
            from: presenter,
            animated: animated
        )
    }

    private static func push(
        _ viewController: UIViewController,
        from presenter: UIViewController,
        animated: Bool
    ) {
        if let navigationController = navigationController(from: presenter) {
            navigationController.pushViewController(
                viewController,
                animated: animated
            )
            return
        }

        let navigationController = UINavigationController(
            rootViewController: viewController
        )
        navigationController.modalPresentationStyle = .fullScreen
        presenter.present(navigationController, animated: animated)
    }

    private static func navigationController(
        from viewController: UIViewController
    ) -> UINavigationController? {
        if let navigationController = viewController as? UINavigationController {
            return navigationController
        }

        if let navigationController = viewController.navigationController {
            return navigationController
        }

        if let presented = viewController.presentedViewController {
            return navigationController(from: presented)
        }

        if let tabBarController = viewController as? UITabBarController,
           let selected = tabBarController.selectedViewController {
            return navigationController(from: selected)
        }

        return nil
    }
}
