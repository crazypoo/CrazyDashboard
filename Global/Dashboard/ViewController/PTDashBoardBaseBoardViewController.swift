//
//  PTDashBoardBaseBoardViewController.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 13/6/2026.
//

import UIKit
import PooTools
import SnapKit
import SwifterSwift
import CoreLocation
import CarPlay

public let PTCarPlayDidBecomeActiveNotification = NSNotification.Name("PTCarPlayDidBecomeActiveNotification")
public let PTCarPlayDidEnterBackgroundNotification = NSNotification.Name("PTCarPlayDidEnterBackgroundNotification")

@objcMembers
public class PTCarPlayManager: NSObject {
    
    /// 全局判断：当前设备是否已经成功连上 CarPlay 并激活了对应的 Scene
    public static var isCarPlayActive: Bool {
        // EN: A connected CarPlay scene is not necessarily rendering yet; use its activation state.
        // ES: Una escena de CarPlay conectada todavía puede no estar renderizando; usamos su estado de activación.
        // 中文：CarPlay 场景已连接不代表已经开始渲染，必须同时检查它的激活状态。
        UIApplication.shared.connectedScenes.contains { scene in
            guard scene.session.role == .carTemplateApplication else { return false }
            return scene.activationState == .foregroundActive ||
                scene.activationState == .foregroundInactive
        }
    }
}

class PTDashBoardBaseBoardViewController: PTMotoBaseViewController {

    private var blockObserverTokens: [NSObjectProtocol] = []

    lazy var dashBoard:PTDashBoardView = {
        let view = PTDashBoardView()
        view.musicNowPlaying.onLyricsTap = { [weak self] in
            self?.presentLyricsIfAllowed()
        }
        view.musicNowPlaying.onOnlineLyricsConsentRequired = { [weak self] in
            self?.requestOnlineLyricsConsent()
        }
        return view
    }()
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        PTRotationManager.shared.rotationToLandscapeRight()
        PTRotationManager.shared.isLockOrientationWhenDeviceOrientationDidChange = true
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // 视图即将消失（比如返回上一页）时：强制恢复为竖屏
        PTRotationManager.shared.rotationToPortrait()
        
        if let scene = SceneDelegate.sceneDelegate() as? SceneDelegate {
            scene.weatherOverlay.snp.remakeConstraints { make in
                make.edges.equalToSuperview()
            }
        }
        
        if !PTDashboardConfig.shared.blueConnected {
            PTTripManager.shared.handleDisconnect()
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
                
        NotificationCenter.default.addObserver(self, selector: #selector(carplayIsInBackground), name: PTCarPlayDidEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(carplayIsNotInBackground), name: PTCarPlayDidBecomeActiveNotification, object: nil)

        blockObserverTokens.append(NotificationCenter.default.addObserver(forName: UIScene.willConnectNotification, object: nil, queue: .main) { [weak self] notification in
            guard let scene = notification.object as? UIScene,
                  scene.session.role == .carTemplateApplication else { return }
            Task { @MainActor [weak self] in
                PTNSLogConsole("🔗 CarPlay 刚刚连接！让手机界面做出反应")
                self?.updateMapModeForCarPlayConnection(isActive: true)
            }
        })
        
        blockObserverTokens.append(NotificationCenter.default.addObserver(forName: UIScene.didDisconnectNotification, object: nil, queue: .main) { [weak self] notification in
            guard let scene = notification.object as? UIScene,
                  scene.session.role == .carTemplateApplication else { return }
            Task { @MainActor [weak self] in
                PTNSLogConsole("🔌 CarPlay 刚刚断开！恢复手机界面")
                self?.updateMapModeForCarPlayConnection(isActive: false)
            }
        })
    }
    
    func carplayIsInBackground() {
        updateMapModeForCarPlayConnection(isActive: false)
    }
    
    func carplayIsNotInBackground() {
        updateMapModeForCarPlayConnection(isActive: true)
    }
    
    private func updateMapModeForCarPlayConnection(isActive: Bool) {
        if isActive {
            self.dashBoard.mapView.setNormalMapView()
        } else {
            self.dashBoard.mapView.setupNavView()
        }
    }

    private func requestOnlineLyricsConsent() {
        let alert = UIAlertController(
            title: PTDashboardConfig.languageFunc(text: "lyrics_online_title"),
            message: PTDashboardConfig.languageFunc(text: "lyrics_online_consent"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(
            title: PTDashboardConfig.languageFunc(text: "button_cancel"),
            style: .cancel
        ) { _ in
            PTLyricsSettings.setOnlineLookupEnabled(false)
        })
        alert.addAction(UIAlertAction(
            title: PTDashboardConfig.languageFunc(text: "lyrics_online_enable"),
            style: .default
        ) { [weak self] _ in
            PTLyricsSettings.setOnlineLookupEnabled(true)
            self?.dashBoard.musicNowPlaying.reloadLyrics()
        })
        present(alert, animated: true)
    }

    private func presentLyricsIfAllowed() {
        guard let snapshot = dashBoard.musicNowPlaying.currentTrackSnapshot else {
            presentLyricsMessage(key: "lyrics_no_match")
            return
        }
        guard let document = dashBoard.musicNowPlaying.currentLyricsDocument else {
            let messageKey: String
            switch dashBoard.musicNowPlaying.lyricsState {
            case .loading: messageKey = "lyrics_loading"
            case .permissionDenied: messageKey = "lyrics_permission_denied"
            case .onlineLookupDisabled: messageKey = "lyrics_online_disabled"
            case .failed: messageKey = "lyrics_unavailable"
            default: messageKey = "lyrics_no_match"
            }
            presentLyricsMessage(key: messageKey)
            return
        }
        guard canPresentFullLyrics() else {
            presentLyricsMessage(key: "lyrics_park_before_viewing")
            return
        }
        guard presentedViewController == nil else { return }

        let lyricsViewController = PTLyricsViewController(
            snapshot: snapshot,
            document: document,
            artwork: dashBoard.musicNowPlaying.currentArtwork
        )
        lyricsViewController.isFullLyricsAllowed = { [weak self] in
            self?.canPresentFullLyrics() ?? false
        }
        present(lyricsViewController, animated: true)
    }

    private func presentLyricsMessage(key: String) {
        let alert = UIAlertController(
            title: PTDashboardConfig.languageFunc(text: "lyrics_title"),
            message: PTDashboardConfig.languageFunc(text: key),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(
            title: PTDashboardConfig.languageFunc(text: "button_confirm"),
            style: .default
        ))
        present(alert, animated: true)
    }

    private func canPresentFullLyrics() -> Bool {
        let motionSpeed = PTMotion.shared.currentSpeedKmh
        guard motionSpeed.isFinite, motionSpeed >= 0, motionSpeed <= 2 else { return false }

        let vehicleSnapshot = PTVehicleConnectivityCoordinator.shared.snapshot
        let hasActiveRideContext = vehicleSnapshot.isDashboardConnected ||
            vehicleSnapshot.isOBDConnected ||
            PTTripManager.shared.isRecordingRide ||
            PTNavigationSessionCoordinator.shared.isSessionActive
        guard hasActiveRideContext else { return true }

        guard PTLocationEngine.shared.isTracking,
              let location = PTLocationEngine.shared.lastLocation else {
            return false
        }
        let age = Date().timeIntervalSince(location.timestamp)
        guard age >= 0, age <= 5 else { return false }
        guard location.speed.isFinite, location.speed >= 0 else { return false }
        return location.speed * 3.6 <= 2
    }

    override func viewControllerOrientation(_ orientationMask: UIInterfaceOrientationMask) {
        super.viewControllerOrientation(orientationMask)
        
        if let scene = SceneDelegate.sceneDelegate() as? SceneDelegate {
            scene.weatherOverlay.snp.remakeConstraints { make in
                make.edges.equalToSuperview()
            }
        }
        
        view.addSubviews([dashBoard])
        dashBoard.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        PTGCDManager.shared.delayOnMain(time: 0.35) {
            self.updateMapModeForCarPlayConnection(isActive: PTCarPlayManager.isCarPlayActive)
        }
        switch orientationMask {
        case .landscapeRight:
            dashBoard.speedometer.snp.remakeConstraints { make in
                make.left.equalToSuperview().inset(CGFloat.statusBarHeight())
                make.top.equalTo(self.dashBoard.mapView.snp.top).offset(44)
                make.bottom.equalTo(self.dashBoard.mapView.snp.bottom).offset(-64)
                make.width.equalTo(self.dashBoard.speedometer.snp.height)
            }
            
            dashBoard.musicNowPlaying.snp.remakeConstraints { make in
                make.top.bottom.width.equalTo(self.dashBoard.speedometer)
                make.right.equalToSuperview()
            }
        default:
            break
        }
        
        if !vcDidLoad {
            dashBoard.speedometer.playStartupSweep(duration: 1.5)
            vcDidLoad = true
        }
    }
            
    @MainActor deinit {
        blockObserverTokens.forEach { NotificationCenter.default.removeObserver($0) }
        NotificationCenter.default.removeObserver(self)
    }    
}
