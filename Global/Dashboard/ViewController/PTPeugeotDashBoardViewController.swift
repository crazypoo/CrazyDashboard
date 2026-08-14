//
//  PTPeugeotDashBoardViewController.swift
//  PTSpeed
//
//  Created by 邓杰豪 on 14/8/2026.
//

import UIKit
import PooTools
import SnapKit
import SwifterSwift

class PTPeugeotDashBoardViewController: PTMotoBaseViewController {

    lazy var speedometer:PTSpeedometerView = {
        let view = PTSpeedometerView(frame: .zero)
        view.gaugeType = .speedometer
        view.direction = .bottomOpening
        view.sweepDirection = .standard
        view.altitudeLabel.isHidden = true
        view.pressureLabel.isHidden = true
        view.unitLabel.text = PTDashboardConfig.shared.appShowUniLabel
        view.maxSpeed = PTDashboardConfig.shared.appUniIsMetric ? 180 : 110
        view.tickStep = 5
        view.progressColor = PTDashboardConfig.shared.appMainColor
        view.needleColor = PTDashboardConfig.shared.appMainColor
        view.majorTickStep = 20
        return view
    }()

    lazy var speedometerReversed:PTSpeedometerView = {
        let view = PTSpeedometerView(frame: .zero)
        view.gaugeType = .tachometer
        view.direction = .bottomOpening
        view.sweepDirection = .reversed
        view.altitudeLabel.isHidden = true
        view.pressureLabel.isHidden = true
        view.unitLabel.text = "x1000 r/min"
        view.maxSpeed = 10000
        view.tickStep = 500
        view.majorTickStep = 1000
        view.progressColor = PTDashboardConfig.shared.appMainColor
        view.needleColor = PTDashboardConfig.shared.appMainColor
        view.redlineRange = 9000...10000
        return view
    }()
    
    lazy var ledDashboard:PTPeugeotLEDDashBoard = {
        let view = PTPeugeotLEDDashBoard()
        return view
    }()
    
    lazy var lightControl: PTIndicatorPanel = {
        let view = PTIndicatorPanel()
        return view
    }()
    
    var tempValue:String = "0"
    var voltageValue:String = "0.0"

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
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
    }
    
    override func viewControllerOrientation(_ orientationMask: UIInterfaceOrientationMask) {
        super.viewControllerOrientation(orientationMask)
        
        if let scene = SceneDelegate.sceneDelegate() as? SceneDelegate {
            scene.weatherOverlay.snp.remakeConstraints { make in
                make.edges.equalToSuperview()
            }
        }
        
        view.addSubviews([speedometer,speedometerReversed,ledDashboard,lightControl])
        speedometer.snp.makeConstraints { make in
            make.width.equalToSuperview().multipliedBy(0.28)
            make.height.equalTo(self.speedometer.snp.width)
            make.bottom.equalToSuperview()
            make.left.equalToSuperview().inset(50)
        }
        speedometer.playStartupSweep(duration: 1.5)
        
        speedometerReversed.snp.makeConstraints { make in
            make.size.equalTo(self.speedometer)
            make.bottom.equalToSuperview()
            make.right.equalToSuperview()
        }
        speedometerReversed.playStartupSweep(duration: 1.5)
        
        ledDashboard.snp.makeConstraints { make in
            make.left.equalTo(self.speedometer.snp.right)
            make.right.equalTo(self.speedometerReversed.snp.left)
            make.top.equalToSuperview()
            make.bottom.equalTo(self.speedometer.snp.centerY)
        }
        outSideTemVoltageSet()
        
        lightControl.snp.makeConstraints { make in
            make.left.right.equalTo(self.ledDashboard)
            make.top.equalTo(self.ledDashboard.snp.bottom)
            make.height.equalTo(44)
        }
                
        PTMotoTelemetryManager.shared.addDelegate(self)
    }
    
    
    override func handleMotorcycleData(data: Any?) {
        if let data1 = data as? PTDashboardData1 {
            let fuelLevelPct = data1.fuelLevelPct
            let odoKm = data1.odoKm
            let avgConsumptionLt = data1.avgConsumptionLt
            let tripKm = data1.tripKm
            DispatchQueue.main.async {
                self.ledDashboard.odoLabel.text = "\(String(format: "%.0f", odoKm)) km"
                self.ledDashboard.leftFuelGauge.progress = CGFloat(fuelLevelPct) / 100
                self.ledDashboard.consumptionLabel.text = "✉️ \(avgConsumptionLt) l/100"
                self.ledDashboard.tripLabel.text = "\(String(format: "%.1f", tripKm)) km"
            }
        } else if let data1 = data as? PTDashboardData2 {
            let outsideTempC = data1.outsideTempC
            DispatchQueue.main.async {
                self.tempValue = "\(outsideTempC)"
                self.outSideTemVoltageSet()
            }
        } else if let data1 = data as? PTDashboardData3 {
            let autonomyKm = data1.autonomyKm
            DispatchQueue.main.async {
                self.ledDashboard.rangeLabel.text = "⛽️ \(String(format: "%.0f", autonomyKm)) km"
            }
        } else if let control = data as? PTDashboardControl {
            let vehicleSpeedKmh = control.vehicleSpeedKmh
            let engineRpm = control.engineRpm

            // 💡 车速和转速驱动的是 CoreAnimation 动画指针（PTSpeedometerView），本身不会闪烁，直接驱动即可
            DispatchQueue.main.async {
                self.speedometer.updateSpeed(vehicleSpeedKmh)
                self.speedometerReversed.updateSpeed(CGFloat(engineRpm))
                self.speedometerReversed.applyShiftLightLogic(currentRpm: engineRpm)
            }
        }
    }
}

extension PTPeugeotDashBoardViewController:PTMotoTelemetryDelegate {
    func telemetryManager(_ manager: PTMotoTelemetryManager, didUpdateMeasurements measurements: [String : Any]) {
        if let data = measurements[OBDCommand.mode1(.coolantTemp).properties.command] as? Double {
            self.ledDashboard.rightTempGauge.progress = CGFloat(data) / 120
        } else if let voltageData = measurements[OBDCommand.mode1(.controlModuleVoltage).properties.command] {
            self.voltageValue = "\(voltageData)"
            outSideTemVoltageSet()
        }
    }
}

extension PTPeugeotDashBoardViewController {
    func outSideTemVoltageSet() {
        ledDashboard.tempVoltageLabel.text = "🌡 \(self.tempValue)°C\n🔋 \(voltageValue)V"
    }
}
