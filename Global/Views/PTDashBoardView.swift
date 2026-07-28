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

class PTDashBoardView: UIView {
    
    let lrSpacing:CGFloat = 44
    let topSpacing:CGFloat = 44
    let bottomSpacing:CGFloat = CGFloat.kTabbarSaveAreaHeight + 44
    
    lazy var speedometer:PTSpeedometerView = {
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
    let leanAngleGauge = PTLeanAngleView() // 🌟 新增压弯表
    let mapView = PTMapView(frame: .zero)
    let tripStatsView = PTTripStatsView(frame: .zero)
    let gForceView = PTGForceView(frame: .zero)
    let crashOverlay = PTCrashWarningView()
    let bumpMeter = PTBumpMeterView()
    let pitchGauge = PTPitchView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        
        setupDashboardUI()
        if PTMotion.shared.motionStarted {
            motionBlockSet()
        }
        
        PTTripManager.shared.liveStatsBlock = { [weak self] tripStats in
            self?.tripStatsView.updateStats(with: tripStats)
        }
        startPootoolsEngines()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func motionSet(motionData:PTMotionData) {
        self.speedometer.updateEnvironment(altitude: nil, pressureKpa: motionData.pressure) // 再更新气压
        self.gForceView.updateGForce(x: motionData.gForceX, y: motionData.gForceY)
        self.leanAngleGauge.updateLean(current: motionData.roll, leftMax: motionData.maxLeftLean, rightMax: motionData.maxRightLean)
        self.bumpMeter.updateBump(zForce: motionData.gForceZ)
        self.pitchGauge.updatePitch(degrees: motionData.pitch)
        // 🌟处理机车事故警报 UI
        if motionData.isTipOverDetected {
            self.showEmergencyOverlay(true) // 事故弹出全屏红色警告
        } else {
            self.showEmergencyOverlay(false)
        }
    }
        
    @objc private func handleLocationUpdate(_ notification: Notification) {
        guard let tripData = notification.object as? PTTripData else { return }
        
        self.speedometer.updateSpeed(PTDashboardConfig.shared.appShowMileage(PTMotion.shared.currentSpeedKmh))
        self.compassRoller.updateHeading(tripData.courseDegree)
        self.speedometer.updateEnvironment(altitude: tripData.altitude, pressureKpa: nil)
    }

    private func setupDashboardUI() {
        // 实例化你封装好的仪表盘视图

        self.addSubviews([mapView,speedometer,musicNowPlaying,leanAngleGauge,compassRoller,tripStatsView,gForceView,bumpMeter, pitchGauge,crashOverlay])
        mapView.snp.makeConstraints { make in
            make.top.equalToSuperview().inset(10)
            make.bottom.equalToSuperview().inset(10)
            make.width.equalToSuperview().multipliedBy(0.65)
            make.centerX.equalToSuperview()
        }
        
        speedometer.snp.makeConstraints { make in
            make.top.equalTo(self.mapView.snp.top).offset(44)
            make.bottom.equalTo(self.mapView.snp.bottom).offset(-64)
            make.width.equalTo(self.speedometer.snp.height)
            make.centerX.equalTo(self.mapView.snp.left)
        }
        
        musicNowPlaying.snp.makeConstraints { make in
            make.top.bottom.width.equalTo(speedometer)
            make.centerX.equalTo(self.mapView.snp.right)
        }

        leanAngleGauge.snp.makeConstraints { make in
            make.bottom.equalTo(self.mapView)
            make.left.equalTo(speedometer.snp.right).offset(10)
            make.right.equalTo(musicNowPlaying.snp.left).offset(-10)
            make.height.equalTo(35)
        }
        
        compassRoller.snp.makeConstraints { make in
            make.left.right.equalTo(leanAngleGauge)
            make.bottom.equalTo(self.leanAngleGauge.snp.top)
            make.height.equalTo(54)
        }
        
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
        
        bumpMeter.snp.makeConstraints { make in
            make.left.right.equalTo(compassRoller)
            make.bottom.equalTo(compassRoller.snp.top)
            make.height.equalTo(20)
        }

        pitchGauge.snp.makeConstraints { make in
            make.right.equalTo(gForceView)
            make.bottom.equalTo(self.mapView)
            make.height.equalTo(64)
            make.width.equalTo(170)
        }
        
        crashOverlay.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        crashOverlay.isHidden = true // 初始隐藏
        PTGCDManager.shared.delayOnMain(time: 0.1) {
            self.speedometer.layoutIfNeeded()
            self.speedometer.viewCorner(radius: self.speedometer.bounds.size.height / 2)
            self.musicNowPlaying.layoutIfNeeded()
            self.musicNowPlaying.viewCorner(radius: self.musicNowPlaying.bounds.size.height / 2)
        }
    }
    
    @MainActor private func startPootoolsEngines() {
        PTLocationEngine.shared.switchEngineMode(to: .riding)
        if !PTLocationEngine.shared.isTracking {
            PTLocationEngine.shared.startTracking()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(handleLocationUpdate(_:)), name: PTLocationEngineDidUpdate, object: nil)
        
        if !PTMotion.shared.motionStarted {
            PTMotion.shared.startMotion()
            PTMotion.shared.calibrateZeroPoint()
            motionBlockSet()
        }
    }
    
    // 辅助方法：显示/隐藏摔车警告
    private func showEmergencyOverlay(_ show: Bool) {
        UIView.transition(with: crashOverlay, duration: 0.3, options: .transitionCrossDissolve, animations: {
            self.crashOverlay.isHidden = !show
        }, completion: nil)
    }

    func motionBlockSet() {
        PTMotion.shared.motionBlock = { [weak self] motionData in
            self?.motionSet(motionData: motionData)
        }
    }
}
