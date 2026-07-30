//
//  PTMapView.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 8/6/2026.
//

import UIKit
import AMapNaviKit
import SnapKit
import PooTools
import SwifterSwift

@objcMembers
class PTMapView: UIView, MAMapViewDelegate {
    
    var currentSpeedLimit:UInt8 = 0

    // 暴露出原生地图实例，方便你未来在外部直接添加大头针 (Annotations) 或划线 (Overlays)
    lazy var mapView:MAMapView = {
        let view = MAMapView()
        view.showsUserLocation = true
        view.userTrackingMode = .follow
        view.mapType = .standardNight
        view.mapLanguage = PTDashboardConfig.appIsInChinese() ? 0 : 1
        view.userTrackingMode = .followWithHeading // 【灵魂属性】跟随车头方向，自动呈现 3D 导航视角
        view.showsCompass = false // 隐藏原生指南针，因为我们有 PTCompassRollerView
        view.showsScale = false
        view.isShowTraffic = true // 开启实时路况（会有红黄绿的拥堵提示，很实用）
        view.cameraDegree = 60
        view.logoEnable = false
        view.overrideUserInterfaceStyle = .dark // 强制暗黑模式
        view.delegate = self
        return view
    }()
    
    lazy var carPlayMapView:MAMapView = {
        let view = PTGlobalMapManager.shared.amapView
        view.userTrackingMode = .followWithHeading // 【灵魂属性】跟随车头方向，自动呈现 3D 导航视角
        view.showsCompass = false // 隐藏原生指南针，因为我们有 PTCompassRollerView
        view.showsScale = false
        view.isShowTraffic = true // 开启实时路况（会有红黄绿的拥堵提示，很实用）
        view.cameraDegree = 60
        view.logoEnable = false
        view.overrideUserInterfaceStyle = .dark // 强制暗黑模式
        view.delegate = self
        return view
    }()
    
    lazy var driveView: AMapNaviDriveView = {
        let view = PTGlobalMapManager.shared.driveView
        view.delegate = self
        view.isHidden = true
        return view
    }()

    // 用于标记是否已经完成了首次中心点放大
    private var isFirstLocationUpdate = true
    
    private let gradientMaskLayer = CAGradientLayer()
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - 生命周期绘图 (处理渐变和剔除 Logo)
    public override func layoutSubviews() {
        super.layoutSubviews()
        
        // 1. 设置渐变蒙版的大小
        gradientMaskLayer.frame = self.bounds
    }
    
    func setNormalMapView() {
        AMapNaviDriveManager.sharedInstance().delegate = nil
        AMapNaviDriveManager.sharedInstance().removeDataRepresentative(driveView)
        self.carPlayMapView.removeFromSuperview()
        self.driveView.removeFromSuperview()
        self.addSubview(self.mapView)
        self.mapView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }
    
    func setupNavView() {
        mapView.removeFromSuperview()
        PTGlobalMapManager.shared.attachAMapView(to: self)
        PTGlobalMapManager.shared.attachDriveView(to: self)
        self.carPlayMapView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        self.driveView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        self.setupNavDelegate()
    }
    
    private func setupUI() {
        setupGradientMask()
    }
    
    func setupNavDelegate() {
        AMapNaviDriveManager.sharedInstance().delegate = self
        AMapNaviDriveManager.sharedInstance().allowsBackgroundLocationUpdates = true
        AMapNaviDriveManager.sharedInstance().pausesLocationUpdatesAutomatically = false
        //将driveView添加为导航数据的Representative，使其可以接收到导航诱导数据
        AMapNaviDriveManager.sharedInstance().addDataRepresentative(driveView)
        AMapNaviDriveManager.sharedInstance().addDataRepresentative(self)
    }
    
    // MARK: - 边缘羽化渐变特效
    private func setupGradientMask() {
        // 配置渐变的颜色：透明 -> 纯黑 -> 纯黑 -> 透明
        // 在蒙版中，纯黑代表完全显示，透明代表完全不可见
        gradientMaskLayer.colors = [
            UIColor.clear.cgColor,
            UIColor.black.cgColor,
            UIColor.black.cgColor,
            UIColor.clear.cgColor
        ]
        
        // 配置渐变的位置：0.0 到 0.15 是左侧渐变，0.85 到 1.0 是右侧渐变
        gradientMaskLayer.locations = [0.0, 0.15, 0.85, 1.0]
        
        // 设置渐变方向：横向 (从左到右)
        gradientMaskLayer.startPoint = CGPoint(x: 0.0, y: 0.5)
        gradientMaskLayer.endPoint = CGPoint(x: 1.0, y: 0.5)
        
        // 将这个渐变层作为当前 View 的蒙版
        self.layer.mask = gradientMaskLayer
    }

    // MARK: - MKMapViewDelegate
    public func mapView(_ mapView: MAMapView!, didUpdate userLocation: MAUserLocation!, updatingLocation: Bool) {
        // 当首次获取到用户的 GPS 坐标时，给地图一个平滑的缩放动画
        if isFirstLocationUpdate, let _ = userLocation.location {
            isFirstLocationUpdate = false
            mapView.setZoomLevel(17.5, animated: true)
            mapView.setUserTrackingMode(.followWithHeading, animated: true)
        }
    }
}

extension PTMapView:AMapNaviDriveManagerDelegate {
    func driveManager(_ driveManager: AMapNaviDriveManager, didStartNavi naviMode: AMapNaviMode) {
        self.driveView.isHidden = false
    }
    
    func driveManager(_ driveManager: AMapNaviDriveManager, didStopNavi isStopped: Bool) {
        self.driveView.isHidden = isStopped
    }
        
    func driveManager(onArrivedDestination driveManager: AMapNaviDriveManager) {
        self.driveViewCloseButtonClicked(self.driveView)
    }
    
    func driveManagerDidEndEmulatorNavi(_ driveManager: AMapNaviDriveManager) {
        self.driveViewCloseButtonClicked(self.driveView)
    }
    
    func driveManager(_ driveManager: AMapNaviDriveManager, error: Error) {
        let error = error as NSError
        PTNSLogConsole("error:{%d - %@}", error.code, error.localizedDescription)
    }
    
    func driveManager(_ driveManager: AMapNaviDriveManager, onCalculateRouteFailure error: Error) {
        let error = error as NSError
        PTNSLogConsole("CalculateRouteFailure:{%d - %@}", error.code, error.localizedDescription)
    }

    func driveManager(onCalculateRouteSuccess driveManager: AMapNaviDriveManager) {
        //算路成功后显示路径
//        showNaviRoutes()
    }
    
    func driveManager(_ driveManager: AMapNaviDriveManager, postRouteNotification notifyData: AMapNaviRouteNotifyData) {
        PTNSLogConsole(">>>>>>>>>>>>>>>>\(String(describing: notifyData.roadName))")
    }
            
    func driveManager(_ manager: AMapNaviDriveManager?, onUpdateNaviSpeedLimitSection speed: Int) {
        PTNSLogConsole(">>>>>>>>>>>>>>>>>>>>>>>>>>>>\(speed)")
        self.currentSpeedLimit = UInt8(speed)
    }
    
    func driveManagerIsNaviSoundPlaying(_ driveManager: AMapNaviDriveManager) -> Bool {
        return SpeechSynthesizer.Shared.isSpeaking()
    }
    
    func driveManager(_ driveManager: AMapNaviDriveManager, playNaviSound soundString: String, soundStringType: AMapNaviSoundType) {
        if !PTMotoUserDefaultStruct.NavMute {
            SpeechSynthesizer.Shared.speak(soundString)
        }
    }
            
    func driveManager(_ driveManager: AMapNaviDriveManager, onCalculateRouteSuccessWith type: AMapNaviRoutePlanType) {
        PTBluetoothServerManager.shared.sendWelcomeMessage(next: "Rerouting...", title: "",nextManeuver: PTManeuverMap.rerouting)
    }
        
    func driveManager(_ driveManager: AMapNaviDriveManager, update gpsSignalStrength: AMapNaviGPSSignalStrength) {
        switch gpsSignalStrength {
        case .smartPos:
            break
        default:
            PTBluetoothServerManager.shared.sendWelcomeMessage(next: "Searching GPS...", title: "",nextManeuver: PTManeuverMap.noGPS)
        }
    }
}

extension PTMapView : AMapNaviDriveViewDelegate {
        
    func driveViewCloseButtonClicked(_ driveView: AMapNaviDriveView) {
        //停止导航
        AMapNaviDriveManager.sharedInstance().stopNavi()
        AMapNaviDriveManager.sharedInstance().removeDataRepresentative(driveView)
        self.driveView.isHidden = true
        PTDashboardConfig.shared.naving = false
        PTLiveActivityManager.shared.stopNavigationActivity()
    }
    
    func driveView(_ view: AMapNaviDriveView, didChangeTo state: AMapNaviDriveViewState) { }
}

extension PTMapView:AMapNaviDriveDataRepresentable {
         
    func driveManager(_ driveManager: AMapNaviDriveManager, updateCruiseElecCameraInfos cameraInfos: [AMapNaviTrafficFacilityInfo]) {
        if let firstCamera = cameraInfos.first {
            // cameraSpeed 通常代表该路段限速，为 0 时表示无限速或未知
            if firstCamera.limitSpeed > 0 {
                self.currentSpeedLimit = UInt8(firstCamera.limitSpeed)
            }
        }
    }
    
    func driveManager(_ driveManager: AMapNaviDriveManager, update cameraInfos: [AMapNaviCameraInfo]?) {
        if let firstCamera = cameraInfos?.first {
            // cameraSpeed 通常代表该路段限速，为 0 时表示无限速或未知
            if firstCamera.cameraSpeed > 0 {
                self.currentSpeedLimit = UInt8(firstCamera.cameraSpeed)
            }
        }
    }
    
    func driveManager(_ driveManager: AMapNaviDriveManager, update naviInfo: AMapNaviInfo?) {
        guard let naviInfo = naviInfo else {
            return
        }
        PTNSLogConsole("\(naviInfo)")
        self.driveView.isHidden = false
        PTMotoDashBoardNavFunction.sendNavDataToDashboard(naviInfo: naviInfo, currentSpeedLimit: self.currentSpeedLimit)
    }
}
