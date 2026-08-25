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
        
    private var carplayDisplayLink: CADisplayLink?
    
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
                PTBluetoothServerManager.shared.startBaseStationAndScan()
            }
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(navStart), name: PTCarPlayStarNavNotification, object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(checkCarplay), name: PTAppEnterBackgroundNotification, object: nil)
    }

    @MainActor deinit {
        blockObserverTokens.forEach { NotificationCenter.default.removeObserver($0) }
        carplayDisplayLink?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc func checkCarplay() {
        carplayDisplayLink?.invalidate()
        carplayDisplayLink = nil
        setupCarPlayHeartbeat()
        navStart()
    }
    
    private func setupCarPlayHeartbeat() {
        // 确保当前是在 CarPlay 环境，并且成功获取到了车机的屏幕对象 (不是手机屏幕)
        guard PTCarPlayManager.isCarPlayActive, let carScreen = self.view.window?.screen else { return }
        
        // 清理旧心跳
        carplayDisplayLink?.invalidate()
        
        // 🌟 核心魔法：将新的心跳【强行绑定在车机屏幕上】！
        // 这样哪怕手机黑屏，只要车机屏幕亮着，这个起搏器就会以每秒 60 次的频率永远跳动！
        carplayDisplayLink = carScreen.displayLink(withTarget: self, selector: #selector(forceDriveViewRender))
        carplayDisplayLink?.add(to: .main, forMode: .common)
        
        PTNSLogConsole("💓 [CarPlay] 车机独立渲染心跳已绑定，无惧手机息屏！")
    }
    
    @objc private func forceDriveViewRender() {
        // 每次心跳跳动，都不停地鞭策高德地图底层进行强制渲染
        if PTDashboardConfig.shared.naving {
            self.dashBoard.mapView.driveView.setNeedsDisplay()
        }
    }
    
    @objc func navStart() {
        if PTDashboardConfig.shared.naving,PTDashboardConfig.shared.blueConnected {
            self.updateMapModeForCarPlayConnection(isActive: false)
        } else {
            self.updateMapModeForCarPlayConnection(isActive: PTCarPlayManager.isCarPlayActive)
            setupCarPlayHeartbeat()
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
