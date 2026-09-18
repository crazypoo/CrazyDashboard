//
//  PTMusicViewController.swift
//  CrazyDashboard
//

import UIKit
import Combine
import MusicKit
import PooTools
import SafeSFSymbols

@MainActor
class PTMusicViewController: PTMotoBaseViewController {

    private let modeControl = UISegmentedControl(
        items: [
            PTMusicPlayerMode.system.displayName,
            PTMusicPlayerMode.application.displayName
        ]
    )

    private let playerView = PTMusicPlayerView()
    private let permissionLabel = UILabel()
    private let authorizeButton = UIButton(type: .system)

    private let playbackManager = PTMusicPlaybackManager.shared
    private let authorizationManager = PTMusicAuthorizationManager.shared

    private var cancellables = Set<AnyCancellable>()

    lazy var searchButton:PTBaseButton = {
        let view = PTBaseButton(type: .custom)
        view.setImage(UIImage(.magnifyingglass), for: .normal)
        view.addActionHandlers(handler: { _ in
            self.openSearch()
        })
        view.bounds = .init(x: 0, y: 0, width: PTAppBaseConfig.share.navBarButtonSize, height: PTAppBaseConfig.share.navBarButtonSize)
        return view
    }()
    
    lazy var libButton:PTBaseButton = {
        let view = PTBaseButton(type: .custom)
        view.setImage(UIImage(.music.noteList), for: .normal)
        view.addActionHandlers(handler: { _ in
            self.openLibrary()
        })
        view.bounds = .init(x: 0, y: 0, width: PTAppBaseConfig.share.navBarButtonSize, height: PTAppBaseConfig.share.navBarButtonSize)
        return view
    }()
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setCustomRightButtons(buttons: [searchButton,libButton], buttonSpacing: CGFloat.GlobalItemSpacing)
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()

        pt_Title = NSLocalizedString("音乐", comment: "")
        view.backgroundColor = .black

        setupUI()
        bindState()
        bindActions()

        Task { @MainActor [weak self] in
            await PTMusicCoordinator.shared.bootstrap(
                requestAuthorizationIfNeeded: true
            )
            self?.updateAuthorizationUI()
        }
    }

    private func setupUI() {
        modeControl.translatesAutoresizingMaskIntoConstraints = false
        modeControl.selectedSegmentIndex = playbackManager.mode == .system ? 0 : 1
        modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)

        permissionLabel.translatesAutoresizingMaskIntoConstraints = false
        permissionLabel.textAlignment = .center
        permissionLabel.textColor = .secondaryLabel
        permissionLabel.numberOfLines = 0
        permissionLabel.isHidden = true

        authorizeButton.translatesAutoresizingMaskIntoConstraints = false
        authorizeButton.configuration = .filled()
        authorizeButton.configuration?.title = NSLocalizedString("允许访问 Apple Music", comment: "")
        authorizeButton.addTarget(self, action: #selector(authorizeTapped), for: .touchUpInside)
        authorizeButton.isHidden = true

        let authorizationStack = UIStackView(
            arrangedSubviews: [permissionLabel, authorizeButton]
        )
        authorizationStack.translatesAutoresizingMaskIntoConstraints = false
        authorizationStack.axis = .vertical
        authorizationStack.alignment = .center
        authorizationStack.spacing = 12

        playerView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(modeControl)
        view.addSubview(playerView)
        view.addSubview(authorizationStack)

        NSLayoutConstraint.activate([
            modeControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            modeControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            modeControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            playerView.topAnchor.constraint(equalTo: modeControl.bottomAnchor, constant: 8),
            playerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            playerView.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor),

            authorizationStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            authorizationStack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            authorizationStack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 28),
            authorizationStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -28)
        ])

        updateAuthorizationUI()
    }

    private func bindState() {
        playbackManager.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in
                self?.playerView.render(snapshot)
                self?.modeControl.selectedSegmentIndex = snapshot.mode == .system ? 0 : 1
            }
            .store(in: &cancellables)

        authorizationManager.$authorizationStatus
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateAuthorizationUI()
            }
            .store(in: &cancellables)
    }

    private func bindActions() {
        playerView.onPlayPause = { [weak self] in
            self?.performPlaybackAction {
                try await PTMusicPlaybackManager.shared.togglePlayPause()
            }
        }

        playerView.onPrevious = { [weak self] in
            self?.performPlaybackAction {
                try await PTMusicPlaybackManager.shared.previous()
            }
        }

        playerView.onNext = { [weak self] in
            self?.performPlaybackAction {
                try await PTMusicPlaybackManager.shared.next()
            }
        }

        playerView.onShuffle = {
            let manager = PTMusicPlaybackManager.shared
            manager.setShuffleEnabled(!manager.snapshot.shuffleEnabled)
        }

        playerView.onRepeat = {
            PTMusicPlaybackManager.shared.cycleRepeatMode()
        }

        playerView.onSeek = { seconds in
            PTMusicPlaybackManager.shared.seek(to: seconds)
        }
    }

    private func updateAuthorizationUI() {
        let status = authorizationManager.authorizationStatus

        switch status {
        case .authorized:
            permissionLabel.isHidden = true
            authorizeButton.isHidden = true
            playerView.isHidden = false
            navigationItem.rightBarButtonItems?.forEach { $0.isEnabled = true }

        case .notDetermined:
            permissionLabel.text = NSLocalizedString(
                "需要 Apple Music 权限才能访问音乐资料库和目录。",
                comment: ""
            )
            permissionLabel.isHidden = false
            authorizeButton.isHidden = false
            playerView.isHidden = true
            navigationItem.rightBarButtonItems?.forEach { $0.isEnabled = false }

        case .denied:
            permissionLabel.text = NSLocalizedString(
                "Apple Music 权限已关闭，请前往系统设置重新允许。",
                comment: ""
            )
            permissionLabel.isHidden = false
            authorizeButton.configuration?.title = NSLocalizedString("打开设置", comment: "")
            authorizeButton.isHidden = false
            playerView.isHidden = true
            navigationItem.rightBarButtonItems?.forEach { $0.isEnabled = false }

        case .restricted:
            permissionLabel.text = NSLocalizedString(
                "当前设备限制了 Apple Music 访问。",
                comment: ""
            )
            permissionLabel.isHidden = false
            authorizeButton.isHidden = true
            playerView.isHidden = true
            navigationItem.rightBarButtonItems?.forEach { $0.isEnabled = false }

        @unknown default:
            permissionLabel.text = NSLocalizedString(
                "Apple Music 当前不可用。",
                comment: ""
            )
            permissionLabel.isHidden = false
            authorizeButton.isHidden = true
            playerView.isHidden = true
            navigationItem.rightBarButtonItems?.forEach { $0.isEnabled = false }
        }
    }

    @objc private func authorizeTapped() {
        if authorizationManager.authorizationStatus == .denied {
            guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
                return
            }

            UIApplication.shared.open(settingsURL)
            return
        }

        Task { @MainActor [weak self] in
            _ = await self?.authorizationManager.requestAuthorization()
            self?.updateAuthorizationUI()
        }
    }

    @objc private func modeChanged() {
        let mode: PTMusicPlayerMode = modeControl.selectedSegmentIndex == 0
            ? .system
            : .application

        playbackManager.setMode(mode)
    }

    @objc private func openSearch() {
        navigationController?.pushViewController(
            PTMusicSearchViewController(),
            animated: true
        )
    }

    @objc private func openLibrary() {
        navigationController?.pushViewController(
            PTMusicLibraryViewController(),
            animated: true
        )
    }

    private func performPlaybackAction(
        _ operation: @escaping @MainActor () async throws -> Void
    ) {
        Task { @MainActor [weak self] in
            do {
                try await operation()
            } catch {
                self?.showError(error.localizedDescription)
            }
        }
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(
            title: NSLocalizedString("Apple Music", comment: ""),
            message: message,
            preferredStyle: .alert
        )

        alert.addAction(
            UIAlertAction(
                title: NSLocalizedString("确定", comment: ""),
                style: .default
            )
        )

        present(alert, animated: true)
    }
}
