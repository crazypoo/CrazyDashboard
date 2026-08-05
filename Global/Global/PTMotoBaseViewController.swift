//
//  PTMotoBaseViewController.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 22/7/2026.
//

import UIKit
import PooTools

class PTMotoBaseViewController: PTBaseViewController {

    var vcDidLoad:Bool = false
    
    open override func preferredNavigationBarStyle() -> PTNavigationBarStyle {
        return .solid(.clear)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.changeStatusBar(type: .Dark)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.changeStatusBar(type: .Dark)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        PTGCDManager.shared.delayOnMain(time: 0.35) {
            self.changeStatusBar(type: .Dark)
        }
    }
        
    override func viewDidLoad() {
        super.viewDidLoad()
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleMotorcycleDisconnect), name: MotorcycleDisconnected, object: nil)
    }
    
    func handleMotorcycleDisconnect() {
        PTLocationEngine.shared.switchEngineMode(to: .antiTheft)
        PTLocationEngine.shared.forceUpdateWidgetOnDisconnect()
        PTMOTOParkingManager.shared.saveCurrentLocationAsParkingSpot()
    }
    
    @MainActor deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
