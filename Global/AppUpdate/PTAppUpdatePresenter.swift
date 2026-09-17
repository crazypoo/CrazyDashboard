//
//  PTAppUpdatePresenter.swift
//  PTSpeed
//
//  Created by 邓杰豪 on 17/9/2026.
//

import UIKit
import PooTools

@MainActor
final class PTAppUpdatePresenter {

    static let shared = PTAppUpdatePresenter()

    private var isPresenting = false

    private init() {}

    // MARK: - Public

    func present(_ result: PTAppUpdateResult) {
        switch result {

        case .latest,
             .unavailable:
            return

        case .optional(let manifest):
            presentOptionalUpdate(manifest)

        case .required(let manifest):
            presentRequiredUpdate(manifest)
        }
    }

    // MARK: - Optional

    private func presentOptionalUpdate(
        _ manifest: PTAppUpdateManifest
    ) {
        guard !isPresenting else { return }

        isPresenting = true

        let title = updateTitle(
            required: false
        )

        let message = updateMessage(
            manifest: manifest,
            required: false
        )

        let alert = makeAlert(
            title: title,
            message: message,
            required: false,
            manifest: manifest
        )

        presentAlert(alert)
    }

    // MARK: - Required

    private func presentRequiredUpdate(
        _ manifest: PTAppUpdateManifest
    ) {
        guard !isPresenting else { return }

        isPresenting = true

        let title = updateTitle(
            required: true
        )

        let message = updateMessage(
            manifest: manifest,
            required: true
        )

        let alert = makeAlert(
            title: title,
            message: message,
            required: true,
            manifest: manifest
        )

        presentAlert(alert)
    }

    // MARK: - Alert

    private func makeAlert(
        title: String,
        message: String,
        required: Bool,
        manifest: PTAppUpdateManifest
    ) -> UIAlertController {

        let alert = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .alert
        )

        if !required {

            let later = UIAlertAction(
                title: "稍后",
                style: .cancel
            ) { [weak self] _ in

                self?.isPresenting = false
            }

            alert.addAction(later)
        }

        let update = UIAlertAction(
            title: "前往 TestFlight",
            style: .default
        ) { [weak self] _ in

            guard let self else { return }

            self.isPresenting = false

            self.openTestFlight(
                manifest
            )
        }

        alert.addAction(update)

        alert.preferredAction = update

        return alert
    }

    // MARK: - Present

    private func presentAlert(
        _ alert: UIAlertController
    ) {
        guard let controller = topViewController() else {
            isPresenting = false
            return
        }

        guard controller.presentedViewController == nil
                || controller.presentedViewController is UIAlertController == false
        else {
            isPresenting = false
            return
        }

        controller.present(
            alert,
            animated: true
        )
    }

    // MARK: - TestFlight

    private func openTestFlight(
        _ manifest: PTAppUpdateManifest
    ) {
        guard
            let value = manifest.testFlight.url,
            !value.isEmpty,
            let url = URL(string: value)
        else {
            return
        }

        UIApplication.shared.open(
            url,
            options: [:]
        )
    }

    // MARK: - Content

    private func updateTitle(
        required: Bool
    ) -> String {
        required
            ? "需要更新 CrazyDashboard"
            : "发现新版本"
    }

    private func updateMessage(
        manifest: PTAppUpdateManifest,
        required: Bool
    ) -> String {

        var values = [String]()

        let current = PTAppVersion.current

        values.append(
            "当前版本：\(current.version) (\(current.build))"
        )

        values.append(
            "最新版本：\(manifest.latest.version) (\(manifest.latest.build))"
        )

        if required,
           let minimum = manifest.policy.minimumSupported {

            values.append(
                "最低支持：\(minimum.version) (\(minimum.build))"
            )
        }

        if let notes = preferredReleaseNotes(
            from: manifest
        ) {
            values.append("")
            values.append("更新内容")
            values.append(notes)
        }

        if required {
            values.append("")
            values.append(
                "当前版本已停止支持，请更新后继续使用。"
            )
        }

        return values.joined(
            separator: "\n"
        )
    }

    // MARK: - Release Notes

    private func preferredReleaseNotes(
        from manifest: PTAppUpdateManifest
    ) -> String? {

        guard !manifest.releaseNotes.isEmpty else {
            return nil
        }

        let preferredLanguages =
            Locale.preferredLanguages

        for language in preferredLanguages {

            if let exact =
                manifest.releaseNotes[language],
               !exact.isEmpty {

                return normalizeReleaseNotes(
                    exact
                )
            }

            let languageCode =
                language
                .split(separator: "-")
                .first
                .map(String.init)

            guard let languageCode else {
                continue
            }

            if let match = manifest.releaseNotes.first(
                where: {
                    $0.key.hasPrefix(languageCode)
                        && !$0.value.isEmpty
                }
            ) {
                return normalizeReleaseNotes(
                    match.value
                )
            }
        }

        if let english =
            manifest.releaseNotes["en-US"]
            ?? manifest.releaseNotes["en"] {

            return normalizeReleaseNotes(
                english
            )
        }

        if let first =
            manifest.releaseNotes.values.first {

            return normalizeReleaseNotes(
                first
            )
        }

        return nil
    }

    private func normalizeReleaseNotes(
        _ value: String
    ) -> String {

        let text = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !text.isEmpty else {
            return text
        }

        // TestFlight What's New 如果本身已经分行，
        // 保持原格式。
        return text
    }

    // MARK: - Top VC

    private func topViewController(
        from controller: UIViewController? = nil
    ) -> UIViewController? {

        let root: UIViewController?

        if let controller {
            root = controller
        } else {
            root = UIApplication.shared
                .connectedScenes
                .compactMap {
                    $0 as? UIWindowScene
                }
                .filter {
                    $0.activationState == .foregroundActive
                }
                .flatMap {
                    $0.windows
                }
                .first(
                    where: {
                        $0.isKeyWindow
                    }
                )?
                .rootViewController
        }

        guard let root else {
            return nil
        }

        if let presented =
            root.presentedViewController {

            return topViewController(
                from: presented
            )
        }

        if let navigation =
            root as? UINavigationController {

            return topViewController(
                from: navigation.visibleViewController
            )
        }

        if let tabBar =
            root as? UITabBarController {

            return topViewController(
                from: tabBar.selectedViewController
            )
        }

        return root
    }
}
