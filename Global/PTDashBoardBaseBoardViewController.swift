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

class PTDashBoardBaseBoardViewController: PTBaseViewController {

    let lrSpacing:CGFloat = 44
    let topSpacing:CGFloat = 44
    let bottomSpacing:CGFloat = CGFloat.kTabbarSaveAreaHeight + 44
    
    let speedometer = PTSpeedometerView(frame: .zero)
    let musicNowPlaying = PTNowPlayingView(frame: .zero)
    let compassRoller = PTCompassRollerView(frame: .zero)
    let leanAngleGauge = PTLeanAngleView() // 🌟 新增压弯表
    let mapView = PTMapView(frame: .zero)
    let tripStatsView = PTTripStatsView(frame: .zero)
    let gForceView = PTGForceView(frame: .zero)
    let crashOverlay = PTCrashWarningView()
    let bumpMeter = PTBumpMeterView()
    let pitchGauge = PTPitchView()
    
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

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        // Do any additional setup after loading the view.
        setupDashboardUI()
        
    startPootoolsEngines()
    }

    private func setupDashboardUI() {
        // 实例化你封装好的仪表盘视图

        self.view.addSubviews([mapView,speedometer,musicNowPlaying,leanAngleGauge,compassRoller,tripStatsView,gForceView,bumpMeter, pitchGauge,crashOverlay])
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
        speedometer.layoutIfNeeded()
        speedometer.viewCorner(radius: speedometer.bounds.size.height / 2)
        
        musicNowPlaying.snp.makeConstraints { make in
            make.top.bottom.width.equalTo(speedometer)
            make.centerX.equalTo(self.mapView.snp.right)
        }
        musicNowPlaying.layoutIfNeeded()
        musicNowPlaying.viewCorner(radius: musicNowPlaying.bounds.size.height / 2)

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
    }
    
    @MainActor private func startPootoolsEngines() {
        // 调用你 pootools 里的引擎
        PTLocationEngine.shared.startTracking()
        PTLocationEngine.shared.locationBlock = { [weak self] tripData in
            self?.speedometer.updateSpeed(tripData.speedKmh)
            self?.compassRoller.updateHeading(tripData.courseDegree)
            self?.speedometer.updateEnvironment(altitude: tripData.altitude, pressureKpa: nil)
            self?.tripStatsView.updateStats(with: tripData)
            PTMotion.shared.currentSpeedKmh = tripData.speedKmh
        }
        PTMotion.shared.startMotion()
        PTMotion.shared.motionBlock = { [weak self] motionData in
            self?.speedometer.updateEnvironment(altitude: nil, pressureKpa: motionData.pressure) // 再更新气压
            self?.gForceView.updateGForce(x: motionData.gForceX, y: motionData.gForceY)
            self?.leanAngleGauge.updateLean(current: motionData.roll, leftMax: motionData.maxLeftLean, rightMax: motionData.maxRightLean)
            self?.bumpMeter.updateBump(zForce: motionData.gForceZ)
            self?.pitchGauge.updatePitch(degrees: motionData.pitch)
            // 🌟处理机车事故警报 UI
            if motionData.isTipOverDetected {
                self?.showEmergencyOverlay(true) // 事故弹出全屏红色警告
            } else {
                self?.showEmergencyOverlay(false)
            }
        }
    }
    
    // 辅助方法：显示/隐藏摔车警告
    private func showEmergencyOverlay(_ show: Bool) {
        UIView.transition(with: crashOverlay, duration: 0.3, options: .transitionCrossDissolve, animations: {
            self.crashOverlay.isHidden = !show
        }, completion: nil)
    }
}
