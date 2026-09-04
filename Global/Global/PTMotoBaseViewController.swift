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
        // EN: Subscribe while visible and avoid retaining page delegates after navigation.
        // ES: Suscribimos mientras la página está visible y evitamos conservar delegados al navegar.
        // 中文：仅在页面可见时订阅，离开页面后不保留页面代理。
        PTBluetoothServerManager.shared.addDelegate(self)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.changeStatusBar(type: .Dark)
        PTBluetoothServerManager.shared.removeDelegate(self)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        PTGCDManager.shared.delayOnMain(time: 0.35) {
            self.changeStatusBar(type: .Dark)
        }
    }
        
    override func viewDidLoad() {
        super.viewDidLoad()
        
        PTBluetoothServerManager.shared.addDelegate(self)
    }
    
    open func handleMotorcycleDisconnect() {
        // EN: Connection side effects are centralized in PTVehicleConnectivityCoordinator.
        // ES: Los efectos secundarios de conexión se centralizan en PTVehicleConnectivityCoordinator.
        // 中文：连接断开副作用统一由 PTVehicleConnectivityCoordinator 处理。
    }
    
    open func handleMotorcycleConnect() { }
    
    open func handleMotorcycleData(data:Any?) {}
    
    @MainActor deinit {
        PTBluetoothServerManager.shared.removeDelegate(self)
        NotificationCenter.default.removeObserver(self)
    }
}

extension PTMotoBaseViewController:PTBLEDashboardDelegate {
    func dashboardManager(_ manager: PTBluetoothServerManager, didChangeConnectionState isConnected: Bool) {
        if isConnected {
            handleMotorcycleConnect()
        } else {
            handleMotorcycleDisconnect()
        }
    }
    
    func dashboardManager(_ manager: PTBluetoothServerManager, dashboardData data: Any?) {
        handleMotorcycleData(data: data)
    }
}
