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
        
        // 2. 强行隐藏苹果 Logo 和 Legal 文字 (仅限个人极客项目，上架会被拒！)
        for subview in mapView.subviews {
            let className = String(describing: type(of: subview))
            // 苹果 Logo 通常是一个内部的 ImageView，Legal 通常是内部的 Label
            if className.contains("ImageView") || className.contains("Label") {
                subview.isHidden = true
            }
        }
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
        
        setupGradientMask()
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
    
    public func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
        // 当首次获取到用户的 GPS 坐标时，给地图一个平滑的缩放动画
        if isFirstLocationUpdate, let _ = userLocation.location {
            isFirstLocationUpdate = false
            let zoomRange = MKMapView.CameraZoomRange(
                            minCenterCoordinateDistance: 250,
                            maxCenterCoordinateDistance: 250
                        )
            mapView.setCameraZoomRange(zoomRange, animated: true)
            mapView.setUserTrackingMode(.followWithHeading, animated: true)
        }
    }
}
