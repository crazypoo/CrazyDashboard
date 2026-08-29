//
//  ViewController.swift
//  PTSpeed
//
//  Created by 邓杰豪 on 8/6/2026.
//

import UIKit
import SnapKit
import SwifterSwift
import PooTools
import CarPlay
import AMapNaviKit

public let PTAppEnterBackgroundNotification = NSNotification.Name("PTAppEnterBackgroundNotification")
public let PTCarVCShowedNotification = NSNotification.Name("PTCarVCShowedNotification")

class ViewController: UIViewController {
    
    var currentSpeedLimit:UInt8 = 0

    private var blockObserverTokens: [NSObjectProtocol] = []

    lazy var dashBoard:PTDashBoardView = {
        let view = PTDashBoardView()
        return view
    }()
        
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.view.layoutIfNeeded()
        
        NotificationCenter.default.post(name: PTCarVCShowedNotification, object: nil)
        
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
                
        view.addSubviews([dashBoard])
        dashBoard.snp.makeConstraints { make in
            make.left.equalToSuperview().inset(50)
            make.top.bottom.right.equalToSuperview()
        }
        dashBoard.speedometer.playStartupSweep(duration: 1.5)

        if PTDashboardConfig.shared.naving,PTDashboardConfig.shared.blueConnected {
            updateMapModeForCarPlayConnection(isActive: false)
        } else {
            updateMapModeForCarPlayConnection(isActive: PTCarPlayManager.isCarPlayActive)
        }
        
        blockObserverTokens.append(NotificationCenter.default.addObserver(forName: UIScene.willConnectNotification, object: nil, queue: .main) { [weak self] notification in
            guard let scene = notification.object as? UIScene,
                  scene.session.role == .carTemplateApplication else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                PTNSLogConsole("🔗 CarPlay 刚刚连接！让手机界面做出反应")
                
                if PTDashboardConfig.shared.naving,PTDashboardConfig.shared.blueConnected {
                    updateMapModeForCarPlayConnection(isActive: false)
                } else {
                    updateMapModeForCarPlayConnection(isActive: PTCarPlayManager.isCarPlayActive)
                }
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
        
        NotificationCenter.default.addObserver(self, selector: #selector(carplayStopNav), name: PTCarPlayStopNavNotification, object: nil)
        
        if PTMotoUserDefaultStruct.MotoLinkedAPP,!PTDashboardConfig.shared.blueConnected {
            PTGCDManager.shared.delayOnMain(time: 3) {
                _ = PTVehicleConnectivityCoordinator.shared.restoreDashboardConnectionIfNeeded()
            }
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(navStart), name: PTCarPlayStarNavNotification, object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(checkCarplay), name: PTAppEnterBackgroundNotification, object: nil)
    }

    @MainActor deinit {
        blockObserverTokens.forEach { NotificationCenter.default.removeObserver($0) }
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc func checkCarplay() {
        navStart()
    }

    @objc func navStart() {
        if PTDashboardConfig.shared.naving,PTDashboardConfig.shared.blueConnected {
            self.updateMapModeForCarPlayConnection(isActive: false)
        } else {
            self.updateMapModeForCarPlayConnection(isActive: PTCarPlayManager.isCarPlayActive)
        }
    }
    
    @objc private func swallowTap() {
        // 这里什么都不需要做！
        // 它的唯一使命就是拦截点击，让底层的 CarPlay 系统收不到点击信号。
        // 系统收不到信号，顶部的原生导航栏（返回按钮）就永远不会隐藏了。
        PTNSLogConsole("🚗 [CarPlay] 背景点击被成功拦截，原生导航栏保持常驻。")
    }

    @objc func carplayStopNav() {
        AMapNaviDriveManager.sharedInstance().stopNavi()
        self.dashBoard.mapView.setNormalMapView()
    }
    
    func updateMapModeForCarPlayConnection(isActive: Bool) {
        if isActive {
            if PTDashboardConfig.shared.appInBackground,PTDashboardConfig.shared.naving,PTDashboardConfig.shared.blueConnected {
                self.dashBoard.mapView.setupNavView()
            } else {
                self.dashBoard.mapView.setNormalMapView()
            }
        } else {
            self.dashBoard.mapView.setNormalMapView()
        }
    }
}
