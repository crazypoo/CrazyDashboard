//
//  PTGForceView.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 8/6/2026.
//

import UIKit
import SnapKit
import SwifterSwift

@objcMembers
public class PTGForceView: UIView {
    
    private let crosshair = UIView()
    private let xLabel = UILabel()
    private let yLabel = UILabel()
    
    // 球的活动半径 (准星最大移动像素)
    private let maxRadius: CGFloat = 50.0
    
    // G 值量程 (比如最大显示 1.5G)
    private let maxGForce: Double = 1.5
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        self.layer.cornerRadius = self.bounds.width / 2
    }
    
    private func setupUI() {
        self.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        self.layer.borderWidth = 2
        self.layer.borderColor = UIColor.darkGray.cgColor
        
        // 画十字底纹
        let vLine = UIView()
        vLine.backgroundColor = UIColor.darkGray.withAlphaComponent(0.5)
        let hLine = UIView()
        hLine.backgroundColor = UIColor.darkGray.withAlphaComponent(0.5)
        addSubviews([vLine, hLine])
        
        vLine.snp.makeConstraints { make in
            make.centerX.top.bottom.equalToSuperview()
            make.width.equalTo(1)
        }
        hLine.snp.makeConstraints { make in
            make.centerY.left.right.equalToSuperview()
            make.height.equalTo(1)
        }
        
        // 动态准星 (红点)
        crosshair.backgroundColor = .systemRed
        crosshair.layer.cornerRadius = 8
        crosshair.layer.shadowColor = UIColor.red.cgColor
        crosshair.layer.shadowRadius = 5
        crosshair.layer.shadowOpacity = 0.8
        addSubview(crosshair)
        
        crosshair.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.height.equalTo(16)
        }
    }
    
    // 外部高频调用：传入 X 和 Y 的 G值 (如 0.5, -0.8)
    public func updateGForce(x: Double, y: Double) {
        // 限制在最大量程内
        let safeX = min(max(x, -maxGForce), maxGForce)
        let safeY = min(max(y, -maxGForce), maxGForce)
        
        // 将 G 值比例映射为像素偏移量
        let offsetX = CGFloat(safeX / maxGForce) * maxRadius
        // 注意：iOS 坐标系 Y 轴向下是正，但我们希望加速 (G值为正) 时红点往后拽 (向下偏移)
        let offsetY = CGFloat(-safeY / maxGForce) * maxRadius
        
        // 由于是 30Hz 高频调用，无需 UIView.animate，直接改变 transform 就能获得极致丝滑
        crosshair.transform = CGAffineTransform(translationX: offsetX, y: offsetY)
    }
}
