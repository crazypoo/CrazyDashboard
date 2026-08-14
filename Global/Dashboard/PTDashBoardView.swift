//
//  PTDashBoardView.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 28/7/2026.
//

import UIKit
import PooTools
import SwifterSwift
import SnapKit
import SafeSFSymbols

class PTDashBoardView: UIView {
    
    let lrSpacing: CGFloat = 44
    let topSpacing: CGFloat = 44
    let bottomSpacing: CGFloat = CGFloat.kTabbarSaveAreaHeight + 44
    
    // MARK: - UI 组件声明
    lazy var speedometer: PTSpeedometerView = {
        let view = PTSpeedometerView()
        view.progressColor = PTDashboardConfig.shared.appMainColor
        view.needleColor = PTDashboardConfig.shared.appMainColor
        view.maxSpeed = PTDashboardConfig.shared.appUniIsMetric ? 180 : 110
        view.unitLabel.text = PTDashboardConfig.shared.appShowUniLabel
        view.direction = .clockwise
        view.tickStep = 10
        view.majorTickStep = 30
        return view
    }()
    
    let musicNowPlaying = PTNowPlayingView(frame: .zero)
    let compassRoller = PTCompassRollerView(frame: .zero)
    let leanAngleGauge = PTLeanAngleView()
    let mapView = PTMapView(frame: .zero)
    let tripStatsView = PTTripStatsView(frame: .zero)
    let gForceView = PTGForceView(frame: .zero)
    let crashOverlay = PTCrashWarningView()
    let bumpMeter = PTBumpMeterView()
    let pitchGauge = PTPitchView()
    
    lazy var lightControl: PTIndicatorPanel = {
        let view = PTIndicatorPanel()
        view.isHidden = !PTDashboardConfig.shared.blueConnected
        return view
    }()
    
    private lazy var resetMotionButton: PTBaseButton = {
        let view = PTBaseButton(type: .system)
        view.setImage(UIImage(.figure.walkMotion).withTintColor(.white, renderingMode: .alwaysOriginal), for: .normal)
        view.addActionHandlers(handler: { _ in
            PTNSLogConsole("1123123123123123")
            PTMotion.shared.calibrateZeroPoint()
            PTMotion.shared.resetLeanAngles()
        })
        return view
    }()

    // MARK: - 生命周期
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        setupDashboardUI()
        
        PTTripManager.shared.liveStatsBlock = { [weak self] tripStats in
            self?.tripStatsView.updateStats(with: tripStats)
        }
        startPootoolsEngines()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        // 当系统计算完真实的 AutoLayout bounds 后，这里会被自动调用。
        // 无论屏幕如何旋转、如何缩放，圆角永远是绝对精准的圆形。
        let speedRadius = speedometer.bounds.size.height / 2
        if speedRadius > 0 {
            speedometer.layer.cornerRadius = speedRadius
            speedometer.clipsToBounds = true
        }
        
        let musicRadius = musicNowPlaying.bounds.size.height / 2
        if musicRadius > 0 {
            musicNowPlaying.layer.cornerRadius = musicRadius
            musicNowPlaying.clipsToBounds = true
        }
    }
    
    // MARK: - 数据绑定
    func motionSet(motionData: PTMotionData) {
        self.speedometer.updateEnvironment(altitude: nil, pressureKpa: motionData.pressure)
        self.gForceView.updateGForce(x: motionData.gForceX, y: motionData.gForceY)
        self.leanAngleGauge.updateLean(current: motionData.roll, leftMax: motionData.maxLeftLean, rightMax: motionData.maxRightLean)
        self.bumpMeter.updateBump(zForce: motionData.gForceZ)
        self.pitchGauge.updatePitch(degrees: motionData.pitch)
        
        // 处理机车事故警报 UI
        showEmergencyOverlay(motionData.isTipOverDetected)
    }
        
    @objc private func handleLocationUpdate(_ notification: Notification) {
        guard let tripData = notification.object as? PTTripData else { return }
                
        self.speedometer.updateSpeed(PTDashboardConfig.shared.appShowMileage(PTMotion.shared.currentSpeedKmh))
        self.compassRoller.updateHeading(tripData.courseDegree)
        self.speedometer.updateEnvironment(altitude: tripData.altitude, pressureKpa: nil)
    }

    // MARK: - UI 排版
    private func setupDashboardUI() {
        
        // 1. 底层：地图
        // 2. 中层：各种仪表盘
        // 3. 顶层：警告图层
        self.addSubviews([mapView,
                          speedometer, musicNowPlaying, leanAngleGauge, compassRoller,
                          tripStatsView, gForceView,resetMotionButton, bumpMeter, pitchGauge, lightControl,
                          crashOverlay])
        
        // --- 1. 背景层 ---
        mapView.snp.makeConstraints { make in
            make.top.bottom.equalToSuperview().inset(10)
            make.width.equalToSuperview().multipliedBy(0.85)
            make.centerX.equalToSuperview()
        }
        
        // --- 2. 左右主力表盘 ---
        speedometer.snp.makeConstraints { make in
            make.top.equalTo(self.mapView).offset(44)
            make.bottom.equalTo(self.mapView).offset(-64)
            make.width.equalTo(speedometer.snp.height) // 保持 1:1 正圆形
            make.left.equalToSuperview().inset(CGFloat.GlobalItemSpacing / 2)
        }
        
        musicNowPlaying.snp.makeConstraints { make in
            make.top.bottom.width.equalTo(speedometer)
            make.right.equalToSuperview().inset(CGFloat.GlobalItemSpacing / 2)
        }

        // --- 3. 顶部信息栏 ---
        tripStatsView.snp.makeConstraints { make in
            make.top.equalTo(self.mapView)
            make.left.equalTo(self.speedometer.snp.centerX).offset(20)
            make.right.equalTo(self.musicNowPlaying.snp.centerX).offset(-20)
            make.height.equalTo(72)
        }
        
        gForceView.snp.makeConstraints { make in
            make.right.equalTo(self.musicNowPlaying)
            make.top.equalTo(self.mapView)
            make.width.height.equalTo(64)
        }
        
        resetMotionButton.snp.makeConstraints { make in
            make.right.equalTo(self.gForceView)
            make.top.equalTo(self.gForceView.snp.bottom).offset(CGFloat.GlobalItemSpacing)
            make.size.equalTo(PTAppBaseConfig.share.navBarButtonSize)
        }
        
        // --- 4. 中轴线组件 (由下至上堆叠) ---
        // 压弯倾角仪
        leanAngleGauge.snp.makeConstraints { make in
            make.bottom.equalTo(self.mapView)
            make.left.equalTo(speedometer.snp.right).offset(10)
            make.right.equalTo(musicNowPlaying.snp.left).offset(-10)
            make.height.equalTo(35)
        }
        
        // 罗盘
        compassRoller.snp.makeConstraints { make in
            make.left.right.equalTo(leanAngleGauge)
            make.bottom.equalTo(self.leanAngleGauge.snp.top)
            make.height.equalTo(54)
        }
        
        // 颠簸仪
        bumpMeter.snp.makeConstraints { make in
            make.left.right.equalTo(compassRoller)
            make.bottom.equalTo(compassRoller.snp.top)
            make.height.equalTo(20)
        }

        // --- 5. 底部两侧组件 ---
        pitchGauge.snp.makeConstraints { make in
            make.right.equalTo(gForceView)
            make.bottom.equalTo(self.mapView)
            make.height.equalTo(64)
            make.left.greaterThanOrEqualTo(compassRoller.snp.right).offset(CGFloat.GlobalItemSpacing) // 🌟 优化：使用柔性约束，防止与中央罗盘重叠
            make.centerX.equalTo(self.musicNowPlaying)
        }
        
        lightControl.snp.makeConstraints { make in
            make.height.bottom.equalTo(self.pitchGauge)
            make.left.equalTo(self.speedometer)
            make.right.lessThanOrEqualTo(compassRoller.snp.left).offset(-CGFloat.GlobalItemSpacing) // 🌟 优化：使用柔性约束
            make.centerX.equalTo(self.speedometer)

        }
        
        // --- 6. 顶层事故警报 ---
        crashOverlay.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        crashOverlay.isHidden = true
    }
    
    // MARK: - 引擎管理
    @MainActor private func startPootoolsEngines() {
        PTLocationEngine.shared.switchEngineMode(to: .riding)
        if !PTLocationEngine.shared.isTracking {
            PTLocationEngine.shared.startTracking()
        }
        if !PTDashboardConfig.shared.blueConnected {
            PTMotion.shared.calibrateZeroPoint()
            PTTripManager.shared.handleConnect()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(handleLocationUpdate(_:)), name: PTLocationEngineDidUpdate, object: nil)
        PTMotion.shared.addDelegate(self)
        
        PTBluetoothServerManager.shared.addDelegate(self)
    }
        
    private func showEmergencyOverlay(_ show: Bool) {
        // 防止重复触发动画，影响性能
        guard crashOverlay.isHidden == show else { return }
        
        UIView.transition(with: crashOverlay, duration: 0.3, options: .transitionCrossDissolve, animations: {
            self.crashOverlay.isHidden = !show
        }, completion: nil)
    }
    
    @objc func handleAuthSuccess() {
        PTDashboardConfig.shared.blueConnected = true
        lightControl.isHidden = false
        speedometer.playStartupSweep(duration: 1.5)
        PTMOTOParkingManager.shared.clearParkingSpot()
    }
    
    @objc func handleMotorcycleDisconnect() {
        speedometer.resetToZeroWithAnimation()
        PTLocationEngine.shared.switchEngineMode(to: .antiTheft)
        PTLocationEngine.shared.forceUpdateWidgetOnDisconnect()
        PTMOTOParkingManager.shared.saveCurrentLocationAsParkingSpot()
    }
}

extension PTDashBoardView : PTMotionDelegate {
    func motionManager(_ manager: PTMotion, didUpdateData data: PTMotionData) {
        self.motionSet(motionData: data)
    }
}

extension PTDashBoardView:PTBLEDashboardDelegate {
    func dashboardManager(_ manager: PTBluetoothServerManager, didChangeConnectionState isConnected: Bool) {
        if isConnected {
            handleAuthSuccess()
        } else {
            handleMotorcycleDisconnect()
        }
    }
}
