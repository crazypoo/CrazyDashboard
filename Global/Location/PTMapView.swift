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
import MultipeerConnectivity
import AMapLocationKit

@objcMembers
class PTMapView: UIView, MAMapViewDelegate {
    
    var currentSpeedLimit:UInt8 = 0

    // 暴露出原生地图实例，方便你未来在外部直接添加大头针 (Annotations) 或划线 (Overlays)
    lazy var mapView:MAMapView = {
        let view = MAMapView()
        view.showsUserLocation = true
        view.userTrackingMode = .follow
        view.mapType = .standardNight
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
    
    private var peerAnnotations: [MCPeerID: PTPeerAnnotation] = [:]
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        
        NotificationCenter.default.addObserver(self, selector: #selector(handlePeerLocationUpdate(_:)), name: PTPeerLocationDidUpdateNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handlePeerLeave(_:)), name: PTPeerDidLeaveNetworkNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handlePeerAvatarUpdate(_:)), name: PTPeerAvatarDidUpdateNotification, object: nil)
        
        PTGCDManager.shared.delayOnMain(time: 0.55) {
            let flag = AMapLocationDataAvailableForCoordinate(PTLocationEngine.shared.lastLocation?.coordinate ?? .init(latitude: 0, longitude: 0))
            self.mapView.mapLanguage = flag ? 0 : 1
            self.mapView.mapType = .standardNight
            self.carPlayMapView.mapLanguage = flag ? 0 : 1
            self.carPlayMapView.mapType = .standardNight
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
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
        PTGlobalMapManager.shared.attachAMapView(to: self,delegate: self)
        PTGlobalMapManager.shared.attachDriveView(to: self,delegate: self)
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
    
    public func mapView(_ mapView: MAMapView!, viewFor annotation: MAAnnotation!) -> MAAnnotationView! {
        
        if let peerAnno = annotation as? PTPeerAnnotation {
            // 使用特定的 Identifier，确保不和导航系统的起点/终点大头针混淆
            let identifier = "PTCarPlayPeerAnnotationView"
            var view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
            
            if view == nil {
                view = MAAnnotationView(annotation: peerAnno, reuseIdentifier: identifier)
                view?.canShowCallout = true
            }
            
            view?.annotation = peerAnno
            
            // 🌟 8. 判定赋值图片
            if let customAvatar = peerAnno.avatarImage {
                view?.image = customAvatar.pt_toMapCircleAvatar()
            } else {
                view?.image = UIImage(named: "placeholder")?.pt_toMapCircleAvatar()
            }
            // 确保第一次渲染出来时，车头方向也是准的
            view?.transform = CGAffineTransform(rotationAngle: CGFloat(peerAnno.course * .pi / 180.0))
            
            return view
        }
        
        return nil // 如果不是队友的大头针，返回 nil，让高德地图用默认方式渲染其他东西
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

//MARK: MultipeerConnectivity
extension PTMapView {
    @objc private func handlePeerAvatarUpdate(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let peerID = userInfo["peerID"] as? MCPeerID,
              let avatarImage = userInfo["avatarImage"] as? UIImage else { return }
        
        if let existingAnno = peerAnnotations[peerID] {
            existingAnno.avatarImage = avatarImage
            
            DispatchQueue.main.async {
                let circularAvatar = avatarImage.pt_toMapCircleAvatar()
                // 同时更新手机专业模式地图和 CarPlay 地图的视图！
                if let mainView = self.mapView.view(for: existingAnno) {
                    mainView.image = circularAvatar
                }
                if let carPlayView = self.carPlayMapView.view(for: existingAnno) {
                    carPlayView.image = circularAvatar
                }
            }
        }
    }

    // MARK: - 队友地图位置同步 (支持双屏双重渲染)
    @objc private func handlePeerLocationUpdate(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let peerID = userInfo["peerID"] as? MCPeerID,
              let location = userInfo["location"] as? PTPeerLocation else { return }
        
        let coordinate = CLLocationCoordinate2D(latitude: location.lat, longitude: location.lon)
        
        if let existingAnno = peerAnnotations[peerID] {
            // 队友已存在，平滑更新坐标
            existingAnno.coordinate = coordinate
            existingAnno.course = location.course
            
            // 🚨 核心处理：遍历两块屏幕的地图，同时旋转它们的 UI 图标
            [self.mapView, self.carPlayMapView].forEach { map in
                if let annoView = map.view(for: existingAnno) {
                    UIView.animate(withDuration: 0.3) {
                        annoView.transform = CGAffineTransform(rotationAngle: CGFloat(location.course * .pi / 180.0))
                    }
                }
            }
        } else {
            // 新队友，创建大头针
            let newAnno = PTPeerAnnotation()
            newAnno.peerID = peerID
            newAnno.coordinate = coordinate
            newAnno.course = location.course
            newAnno.title = peerID.displayName
            
            peerAnnotations[peerID] = newAnno
            
            // 🚨 核心处理：同时将大头针投射到手机主地图和 CarPlay 地图上
            self.mapView.addAnnotation(newAnno)
            self.carPlayMapView.addAnnotation(newAnno)
        }
    }

    @objc private func handlePeerLeave(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let peerID = userInfo["peerID"] as? MCPeerID else { return }
        
        if let existingAnno = peerAnnotations[peerID] {
            // 队友掉线，同时从双屏地图上抹除
            self.mapView.removeAnnotation(existingAnno)
            self.carPlayMapView.removeAnnotation(existingAnno)
            peerAnnotations.removeValue(forKey: peerID)
        }
    }
}
