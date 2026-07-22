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
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        PTGCDManager.shared.delayOnMain(time: 0.35) {
            self.changeStatusBar(type: .Dark)
        }
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
        PTMOTOParkingManager.shared.saveCurrentLocationAsParkingSpot()
    }
    
    @MainActor deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
