//
//  PTGlobalMapManager.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 29/7/2026.
//

import Foundation
import UIKit
import MapKit
import AMapNaviKit
import SnapKit

@objcMembers
public class PTGlobalMapManager: NSObject {
    
    public static let shared = PTGlobalMapManager()
    
    // 🌟 全局唯一的 2D 地图视图
    public lazy var amapView: MAMapView = {
        let view = MAMapView()
        view.showsUserLocation = true
        view.userTrackingMode = .follow
        view.mapType = .standardNight
        view.mapLanguage = PTDashboardConfig.appIsInChinese() ? 0 : 1
        return view
    }()
    
    // 🌟 全局唯一的 3D 导航视图
    public lazy var driveView: AMapNaviDriveView = {
        let view = AMapNaviDriveView()
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.showGreyAfterPass = true
        view.autoZoomMapLevel = true
        view.trackingMode = AMapNaviViewTrackingMode.carNorth
        view.mapViewModeType = AMapNaviViewMapModeType.night
        return view
    }()
    
    private override init() {
        super.init()
    }
    
    /// 将 2D 地图贴到指定的容器视图上
    public func attachAMapView(to container: UIView, delegate: MAMapViewDelegate?) {
        amapView.removeFromSuperview() // 从上一个界面的父视图中剥离
        container.addSubview(amapView)
        amapView.snp.remakeConstraints { make in
            make.edges.equalToSuperview()
        }
        amapView.delegate = delegate
    }
    
    /// 将 3D 导航视图贴到指定的容器视图上
    public func attachDriveView(to container: UIView, delegate: AMapNaviDriveViewDelegate?) {
        driveView.removeFromSuperview() // 从上一个界面的父视图中剥离
        container.addSubview(driveView)
        driveView.snp.remakeConstraints { make in
            make.edges.equalToSuperview()
        }
        driveView.delegate = delegate
    }
}
