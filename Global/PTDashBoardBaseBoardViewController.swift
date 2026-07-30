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
        // 获取所有已连接的场景
        let connectedScenes = UIApplication.shared.connectedScenes
        
        // 查找是否存在角色为 CarPlay 模板的场景
        let carPlayScene = connectedScenes.first { scene in
            scene.session.role == .carTemplateApplication
        }
        
        // 如果找到了，说明 CarPlay 正在运行中
        return carPlayScene != nil
    }
}

class PTDashBoardBaseBoardViewController: PTMotoBaseViewController {

    lazy var dashBoard:PTDashBoardView = {
        let view = PTDashBoardView()
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

        NotificationCenter.default.addObserver(forName: UIScene.willConnectNotification, object: nil, queue: .main) { [weak self] notification in
            if let scene = notification.object as? UIScene, scene.session.role == .carTemplateApplication {
                PTNSLogConsole("🔗 CarPlay 刚刚连接！让手机界面做出反应")
                self?.updateMapModeForCarPlayConnection(isActive: true)
            }
        }
        
        NotificationCenter.default.addObserver(forName: UIScene.didDisconnectNotification, object: nil, queue: .main) { [weak self] notification in
            if let scene = notification.object as? UIScene, scene.session.role == .carTemplateApplication {
                PTNSLogConsole("🔌 CarPlay 刚刚断开！恢复手机界面")
                self?.updateMapModeForCarPlayConnection(isActive: false)
            }
        }
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
    
    override func viewControllerOrientation(_ orientationMask: UIInterfaceOrientationMask) {
        super.viewControllerOrientation(orientationMask)
        
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
        NotificationCenter.default.removeObserver(self)
    }
}
