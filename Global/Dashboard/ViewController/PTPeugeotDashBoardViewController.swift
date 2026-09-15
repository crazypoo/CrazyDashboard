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

class PTPeugeotDashBoardViewController: PTMotoBaseViewController, PTVehicleTelemetryConsumer {

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
        view.unitLabel.text = RPMUnit
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
    private var lastUnifiedSpeedKmh: Double?

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        PTRotationManager.shared.rotationToLandscapeRight()
        PTRotationManager.shared.isLockOrientationWhenDeviceOrientationDidChange = true
        let telemetryBridge = PTVehicleTelemetryBridge.shared
        telemetryBridge.startIfNeeded()
        PTVehicleTelemetryConsumerHub.shared.register(self)
        let connectivity = PTVehicleConnectivityCoordinator.shared
        telemetryBridge.ingest(
            legacySnapshot: connectivity.telemetrySnapshot,
            connectionSnapshot: connectivity.snapshot
        )
        PTMotoTelemetryManager.shared.addDelegate(self)
        self.ledDashboard.speedLabel.isHidden = PTDashboardConfig.shared.naving
        self.ledDashboard.ledNavView.isHidden = !PTDashboardConfig.shared.naving
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        PTMotoTelemetryManager.shared.removeDelegate(self)
        PTVehicleTelemetryConsumerHub.shared.unregister(self)
        
        // 视图即将消失（比如返回上一页）时：强制恢复为竖屏
        if let coordinator = transitionCoordinator {
            coordinator.animate(alongsideTransition: { _ in
                // 跟随 pop 动画一起请求转回竖屏
                PTRotationManager.shared.rotationToPortrait()
            }, completion: { context in
                // 如果用户侧滑返回到一半又取消了（决定留在 B 界面）
                if context.isCancelled {
                    // 恢复横屏状态
                    PTRotationManager.shared.rotationToLandscapeRight()
                    PTRotationManager.shared.isLockOrientationWhenDeviceOrientationDidChange = true
                }
            })
        } else {
            // 如果没有动画（比如无动画 pop），直接转
            PTRotationManager.shared.rotationToPortrait()
        }

        if let scene = SceneDelegate.sceneDelegate() as? SceneDelegate {
            scene.weatherOverlay.snp.remakeConstraints { make in
                make.edges.equalToSuperview()
            }
        }
        
        if !PTDashboardConfig.shared.blueConnected {
            PTTripManager.shared.handleDisconnect()
        }
    }

    @MainActor deinit {
        PTMotoTelemetryManager.shared.removeDelegate(self)
        PTVehicleTelemetryConsumerHub.shared.unregister(self)
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
            make.width.equalToSuperview().multipliedBy(0.25)
            make.height.equalTo(self.speedometer.snp.width)
            make.bottom.equalToSuperview()
            make.left.equalToSuperview().inset(45)
        }
        speedometer.playStartupSweep(duration: 1.5)
        
        speedometerReversed.snp.makeConstraints { make in
            make.size.equalTo(self.speedometer)
            make.bottom.equalToSuperview()
            make.right.equalToSuperview()
        }
        speedometerReversed.playStartupSweep(duration: 1.5)
        
        ledDashboard.snp.makeConstraints { make in
            make.left.equalTo(self.speedometer.snp.right).offset(CGFloat.GlobalItemSpacing)
            make.right.equalTo(self.speedometerReversed.snp.left).offset(-CGFloat.GlobalItemSpacing)
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
            DispatchQueue.main.async {
                // EN: Keep unavailable Data1 fields visibly unavailable on the main dashboard.
                // ES: Mantén visibles como no disponibles los campos Data1 no disponibles en el tablero principal.
                // 中文：Data1 字段不可用时，在主仪表明确显示不可用。
                let unavailable = PTDashboardConfig.languageFunc(text: "ride_not_available")
                self.ledDashboard.odoLabel.text = data1.odometerAvailability.isAvailable
                    ? "\(String(format: "%.0f", data1.odoKm)) km"
                    : unavailable
                self.ledDashboard.leftFuelGauge.progress = data1.fuelLevelAvailability.isAvailable
                    ? CGFloat(data1.fuelLevelPct) / 100
                    : 0
                self.ledDashboard.consumptionLabel.text = data1.averageConsumptionAvailability.isAvailable
                    ? "✉️ \(data1.avgConsumptionLt) l/100"
                    : unavailable
                self.ledDashboard.tripLabel.text = data1.tripAvailability.isAvailable
                    ? "\(String(format: "%.1f", data1.tripKm)) km"
                    : unavailable
            }
        } else if let data1 = data as? PTDashboardData2 {
            DispatchQueue.main.async {
                let unavailable = PTDashboardConfig.languageFunc(text: "ride_not_available")
                self.tempValue = data1.outsideTemperatureAvailability.isAvailable
                    ? "\(data1.outsideTempC)"
                    : unavailable
                self.voltageValue = data1.batteryAvailability.isAvailable
                    ? "\(String(format: "%.1f", data1.batteryVolt))"
                    : unavailable
                self.outSideTemVoltageSet()
            }
        } else if let data1 = data as? PTDashboardData3 {
            DispatchQueue.main.async {
                let unavailable = PTDashboardConfig.languageFunc(text: "ride_not_available")
                self.ledDashboard.rangeLabel.text = data1.autonomyAvailability.isAvailable
                    ? "⛽️ \(String(format: "%.0f", data1.autonomyKm)) km"
                    : unavailable
            }
        } else if let control = data as? PTDashboardControl,!PTMotoTelemetryManager.shared.isConnected {
            // EN: RPM remains a dashboard-specific field; speed is rendered only by the unified resolver.
            // ES: Las RPM siguen siendo específicas del tablero; la velocidad solo la renderiza el resolvedor unificado.
            // 中文：转速仍由仪表专属路径处理，车速只由统一 Resolver 渲染。
            DispatchQueue.main.async {
                if control.engineRpmAvailability.isAvailable {
                    self.speedometerReversed.updateSpeed(CGFloat(control.engineRpm))
                    self.speedometerReversed.applyShiftLightLogic(currentRpm: control.engineRpm)
                } else {
                    // EN: Reset the RPM pointer and shift light instead of retaining a stale reading.
                    // ES: Restablece el indicador de RPM y la luz de cambio en vez de conservar una lectura obsoleta.
                    // 中文：转速不可用时重置指针和换挡灯，不保留旧读数。
                    self.speedometerReversed.updateSpeed(0)
                    self.speedometerReversed.applyShiftLightLogic(currentRpm: 0)
                }
            }
        }
    }
}

extension PTPeugeotDashBoardViewController {
    func vehicleTelemetryDidUpdate(_ snapshot: PTUnifiedVehicleTelemetrySnapshot) {
        let projection = PTVehicleTelemetryProjections.dashboard(from: snapshot)
        let unavailable = PTDashboardConfig.languageFunc(text: "ride_not_available")
        if let speed = projection.speedKmh {
            lastUnifiedSpeedKmh = speed
            ledDashboard.speedLabel.text = String(format: "%.0f", PTDashboardConfig.shared.appShowMileage(speed))
            speedometer.updateSpeed(
                CGFloat(PTDashboardConfig.shared.appShowMileage(speed)),
                animated: snapshot.mode == .live
            )
        } else if lastUnifiedSpeedKmh != nil {
            // EN: Clear an expired unified speed instead of retaining a direct BLE/OBD value.
            // ES: Limpia una velocidad unificada caducada en vez de conservar un valor directo BLE/OBD.
            // 中文：统一车速过期时清除旧的 BLE/OBD 数值，避免残留显示。
            lastUnifiedSpeedKmh = nil
            ledDashboard.speedLabel.text = unavailable
            speedometer.updateSpeed(0, animated: false)
        }
    }
}

extension PTPeugeotDashBoardViewController:PTMotoTelemetryDelegate {
    func telemetryManager(_ manager: PTMotoTelemetryManager, didUpdateMeasurements measurements: [String : Any]) {
        if let data = measurements[OBDCommand.mode1(.coolantTemp).properties.command] as? Double {
            self.ledDashboard.rightTempGauge.progress = CGFloat(data) / 120
        }
        
        if let rpm = measurements[OBDCommand.mode1(.rpm).properties.command] as? Double {
            self.speedometerReversed.updateSpeed(CGFloat(rpm))
            self.speedometerReversed.applyShiftLightLogic(currentRpm: Int(rpm))
        }
    }
}

extension PTPeugeotDashBoardViewController {
    func outSideTemVoltageSet() {
        // EN: Append units only to available values so the unavailable marker stays readable.
        // ES: Añade unidades solo a los valores disponibles para que el marcador no disponible siga siendo legible.
        // 中文：只给有效值追加单位，保证不可用标记清晰可读。
        let unavailable = PTDashboardConfig.languageFunc(text: "ride_not_available")
        let temperature = tempValue == unavailable ? tempValue : "\(tempValue)°C"
        let voltage = voltageValue == unavailable ? voltageValue : "\(voltageValue)V"
        ledDashboard.tempVoltageLabel.text = "🌡 \(temperature)\n🔋 \(voltage)"
    }
}
