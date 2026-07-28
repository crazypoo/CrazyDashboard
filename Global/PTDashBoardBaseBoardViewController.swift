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

class PTDashBoardBaseBoardViewController: PTMotoBaseViewController {

    lazy var dashBoard:PTDashBoardView = {
        let view = PTDashBoardView()
        return view
    }()
    
    open override func preferredNavigationBarStyle() -> PTNavigationBarStyle {
        return .solid(.clear)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        PTRotationManager.shared.rotationToLandscapeRight()
        PTRotationManager.shared.isLockOrientationWhenDeviceOrientationDidChange = true
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // 视图即将消失（比如返回上一页）时：强制恢复为竖屏
        PTRotationManager.shared.rotationToPortrait()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        // Do any additional setup after loading the view.
    }
    
    override func viewControllerOrientation(_ orientationMask: UIInterfaceOrientationMask) {
        super.viewControllerOrientation(orientationMask)
        
        view.addSubviews([dashBoard])
        dashBoard.snp.makeConstraints { make in
            make.edges.equalToSuperview()
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
