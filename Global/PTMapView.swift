//
//  PTMapView.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 8/6/2026.
//

import UIKit
import MapKit
import SnapKit

@objcMembers
public class PTMapView: UIView, MKMapViewDelegate {
    
    // 暴露出原生地图实例，方便你未来在外部直接添加大头针 (Annotations) 或划线 (Overlays)
    public let mapView = MKMapView()
    
    // 用于标记是否已经完成了首次中心点放大
    private var isFirstLocationUpdate = true
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        // 1. 添加地图并使用 SnapKit 撑满当前 View
        addSubview(mapView)
        mapView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        // 2. 核心属性配置：极客仪表盘模式
        mapView.showsUserLocation = true // 显示当前位置的蓝点/车标
        mapView.userTrackingMode = .followWithHeading // 【灵魂属性】跟随车头方向，自动呈现 3D 导航视角
        
        // 3. 隐藏原生多余的 UI，保持界面纯粹
        mapView.showsCompass = false // 隐藏原生指南针，因为我们有 PTCompassRollerView
        mapView.showsScale = false
        mapView.showsTraffic = true // 开启实时路况（会有红黄绿的拥堵提示，很实用）
        mapView.showsBuildings = true // 显示 3D 建筑物模型
        
        // 4. 样式配置：强制科技感
        mapView.mapType = .mutedStandard // 颜色更暗淡柔和，不会喧宾夺主
        mapView.overrideUserInterfaceStyle = .dark // 强制暗黑模式

        mapView.delegate = self
    }
    
    // MARK: - 进阶功能：手动定位聚焦
    // MapKit 通常会自动处理定位和视角跟随，但你可以用这个方法强制地图飞到某个坐标
    public func focus(on location: CLLocation, zoomLevelMeters: CLLocationDistance = 300, animated: Bool = true) {
        let region = MKCoordinateRegion(center: location.coordinate,
                                        latitudinalMeters: zoomLevelMeters,
                                        longitudinalMeters: zoomLevelMeters)
        mapView.setRegion(region, animated: animated)
    }
    
    // MARK: - MKMapViewDelegate
    
    public func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
        // 当首次获取到用户的 GPS 坐标时，给地图一个平滑的缩放动画
        if isFirstLocationUpdate, let location = userLocation.location {
            isFirstLocationUpdate = false
            // 设定视角高度为 300 米
            focus(on: location, zoomLevelMeters: 300, animated: true)
            // 再次确保追踪模式是 3D 车头向上
            mapView.setUserTrackingMode(.followWithHeading, animated: true)
        }
    }
}
