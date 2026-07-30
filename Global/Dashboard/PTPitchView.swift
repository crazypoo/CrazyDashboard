//
//  PTPitchView.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 8/6/2026.
//

import UIKit
import SnapKit
import SwifterSwift
import SafeSFSymbols
import PooTools

@objcMembers
public class PTPitchView: UIView {
    
    private let titleLabel = UILabel()
    private let angleLabel = UILabel()
    
    // 用于承载旋转动画的容器
    private let graphicsContainer = UIView()
    // 地平线
    private let groundLine = UIView()
    // 机车图标 (这里暂时用系统自行车代替，强烈建议你后续换成你的 ADV 侧面图)
    private let bikeIcon = UIImageView()
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        titleLabel.text = PTDashboardConfig.languageFunc(text: "vechicle_pitch")
        titleLabel.textColor = .lightGray
        titleLabel.font = .appfont(size: 12,bold:true)
        
        angleLabel.text = PTDashboardConfig.languageFunc(text: "pitch_normal")
        angleLabel.textColor = .white
        angleLabel.font = .appfont(size: 14)
        angleLabel.textAlignment = .right
        
        groundLine.backgroundColor = UIColor.white.withAlphaComponent(0.3)
        
        // ⚠️ 这里用了系统的自行车图标作为默认值，如果你有自己的透明背景机车图片，直接替换 image 即可
        bikeIcon.image = UIImage(.bicycle)
        bikeIcon.tintColor = .white
        bikeIcon.contentMode = .scaleAspectFit
        
        addSubviews([titleLabel, angleLabel, graphicsContainer])
        graphicsContainer.addSubviews([groundLine, bikeIcon])
        
        // MARK: - 布局
        titleLabel.snp.makeConstraints { make in
            make.left.top.equalToSuperview()
        }
        
        angleLabel.snp.makeConstraints { make in
            make.right.top.equalToSuperview()
        }
        
        // 留出下方空间专门做动画
        graphicsContainer.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(10)
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(40) // 动画区域高度
        }
        
        groundLine.snp.makeConstraints { make in
            make.centerY.equalToSuperview().offset(10) // 地平线偏下
            make.left.right.equalToSuperview()
            make.height.equalTo(2)
        }
        
        bikeIcon.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalTo(groundLine.snp.top) // 车轮贴着地平线
            make.width.equalTo(40)
            make.height.equalTo(30)
        }
    }
    
    // 接收 PTMotion 的 Pitch 角度
    public func updatePitch(degrees: Double) {
        // 1. 更新文字状态
        let intAngle = Int(degrees)
        if intAngle > 3 {
            angleLabel.text = PTDashboardConfig.language(key: "pitch_up", abs(intAngle))
            angleLabel.textColor = .systemRed
        } else if intAngle < -3 {
            angleLabel.text = PTDashboardConfig.language(key: "pitch_down", abs(intAngle))
            angleLabel.textColor = .systemOrange
        } else {
            angleLabel.text = PTDashboardConfig.languageFunc(text: "pitch_normal")
            angleLabel.textColor = .systemGreen
        }
        
        // 2. 执行绝美的物理动画
        // 将角度转换为弧度 Radian
        let radians = CGFloat(degrees * .pi / 180.0)
        
        // 假设机车车头朝右：
        // 上坡时 (Pitch 为正)，车头应该往上抬 (逆时针旋转)。在 iOS 坐标系里，负数代表逆时针。
        // 所以我们用 -radians
        UIView.animate(withDuration: 0.1, delay: 0, options: [.curveEaseOut], animations: {
            // 我们不仅仅旋转车身，同时连着地平线一起旋转，这才是真实车机的姿态仪效果！
            self.graphicsContainer.transform = CGAffineTransform(rotationAngle: -radians)
        }, completion: nil)
    }
}
