//
//  PTLeanAngleView.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 8/6/2026.
//

import UIKit
import SnapKit
import SwifterSwift

@objcMembers
public class PTLeanAngleView: UIView {
    
    // MARK: - UI 控件
    private let currentAngleLabel = UILabel()
    private let maxLeftLabel = UILabel()
    private let maxRightLabel = UILabel()
    
    // 绘图图层
    private let trackLayer = CAShapeLayer()
    private let progressLayer = CAShapeLayer()
    private let centerTickLayer = CAShapeLayer()
    
    // 设定仪表的物理极限压弯角度 (比如 Moto GP 级别是 65 度，ADV 一般 50 度就极限了)
    private let maxDisplayAngle: Double = 60.0
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - 核心绘图：画一条完美的拱形抛物线
    public override func layoutSubviews() {
        super.layoutSubviews()
        
        guard bounds.width > 0 else { return }
        
        let path = UIBezierPath()
        // 起点：左下角
        path.move(to: CGPoint(x: 0, y: bounds.height))
        // 终点：右下角。 控制点：正上方，形成一个平滑的拱顶
        path.addQuadCurve(to: CGPoint(x: bounds.width, y: bounds.height),
                          controlPoint: CGPoint(x: bounds.width / 2, y: -bounds.height * 0.8))
        
        // 1. 底层暗灰色的轨道
        trackLayer.path = path.cgPath
        
        // 2. 顶层的高亮进度光条
        progressLayer.path = path.cgPath
        
        // 3. 画一个中央的垂直刻度线 (0度基准线)
        let tickPath = UIBezierPath()
        // 根据二次贝塞尔曲线的特性，最高点在正中央。我们算一下顶点大约在 Y的 10% 位置
        let topY = bounds.height * 0.1
        tickPath.move(to: CGPoint(x: bounds.width / 2, y: topY - 5))
        tickPath.addLine(to: CGPoint(x: bounds.width / 2, y: topY + 8))
        centerTickLayer.path = tickPath.cgPath
    }
    
    private func setupUI() {
        self.backgroundColor = .clear
        
        // 1. 配置暗色轨道层
        trackLayer.fillColor = UIColor.clear.cgColor
        trackLayer.strokeColor = UIColor.darkGray.withAlphaComponent(0.4).cgColor
        trackLayer.lineWidth = 6
        trackLayer.lineCap = .round
        layer.addSublayer(trackLayer)
        
        // 2. 配置高亮光条层
        progressLayer.fillColor = UIColor.clear.cgColor
        progressLayer.strokeColor = UIColor.systemOrange.cgColor // 默认橙色光条
        progressLayer.lineWidth = 6
        progressLayer.lineCap = .round
        // 初始状态下，Start 和 End 都设为 0.5（即隐藏在正中央）
        progressLayer.strokeStart = 0.5
        progressLayer.strokeEnd = 0.5
        layer.addSublayer(progressLayer)
        
        // 3. 配置中心基准线
        centerTickLayer.fillColor = UIColor.clear.cgColor
        centerTickLayer.strokeColor = UIColor.white.cgColor
        centerTickLayer.lineWidth = 2
        centerTickLayer.lineCap = .round
        layer.addSublayer(centerTickLayer)
        
        // 4. 文字标签配置
        currentAngleLabel.textColor = .white
        currentAngleLabel.font = UIFont.systemFont(ofSize: 22, weight: .bold)
        currentAngleLabel.textAlignment = .center
        currentAngleLabel.text = "0°"
        
        maxLeftLabel.textColor = .lightGray
        maxLeftLabel.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        maxLeftLabel.textAlignment = .left
        maxLeftLabel.text = "MAX L: 0°"
        
        maxRightLabel.textColor = .lightGray
        maxRightLabel.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        maxRightLabel.textAlignment = .right
        maxRightLabel.text = "MAX R: 0°"
        
        addSubviews([currentAngleLabel, maxLeftLabel, maxRightLabel])
        
        // MARK: - SnapKit 布局
        currentAngleLabel.snp.makeConstraints { make in
            // 把当前度数悬浮在拱形的最高点正下方
            make.centerX.equalToSuperview()
            make.bottom.equalToSuperview().offset(5)
        }
        
        maxLeftLabel.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(10)
            make.bottom.equalToSuperview()
        }
        
        maxRightLabel.snp.makeConstraints { make in
            make.right.equalToSuperview().inset(10)
            make.bottom.equalToSuperview()
        }
    }
    
    // MARK: - 核心联动：接收外界数据，驱动动画
    /// - Parameters:
    ///   - current: 当前倾角 (负数代表左倾，正数代表右倾)
    ///   - leftMax: 历史最大左倾 (绝对值)
    ///   - rightMax: 历史最大右倾 (绝对值)
    public func updateLean(current: Double, leftMax: Double, rightMax: Double) {
        
        // 1. 更新文字
        currentAngleLabel.text = "\(Int(abs(current)))°"
        maxLeftLabel.text = "MAX L: \(Int(leftMax))°"
        maxRightLabel.text = "MAX R: \(Int(rightMax))°"
        
        // 如果倾角超过 40 度 (非常危险/极限的动作)，文字和光条变红警告！
        let isExtreme = abs(current) >= 40.0
        let activeColor = isExtreme ? UIColor.systemRed.cgColor : UIColor.systemOrange.cgColor
        
        // 2. 计算光条范围 (利用 0.0 ~ 1.0 的比例)
        // 中央基准是 0.5。跨度占满半边 (60度) 相当于 0.5 的比例。
        let ratio = min(abs(current) / maxDisplayAngle, 1.0)
        let widthRatio = CGFloat(ratio * 0.5) // 实际要伸展的长度比例
        
        var targetStart: CGFloat = 0.5
        var targetEnd: CGFloat = 0.5
        
        if current < 0 {
            // 向左压弯：起点向左移动，终点死守 0.5 中央
            targetStart = 0.5 - widthRatio
            targetEnd = 0.5
        } else if current > 0 {
            // 向右压弯：起点死守 0.5 中央，终点向右延伸
            targetStart = 0.5
            targetEnd = 0.5 + widthRatio
        }
        
        // 3. 执行极度平滑的动画
        CATransaction.begin()
        // 设置动画时间与陀螺仪 30Hz (0.033秒) 的刷新率相近，达到零延迟的跟手感
        CATransaction.setAnimationDuration(0.1)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        
        progressLayer.strokeColor = activeColor
        currentAngleLabel.textColor = isExtreme ? .systemRed : .white
        
        progressLayer.strokeStart = targetStart
        progressLayer.strokeEnd = targetEnd
        
        CATransaction.commit()
    }
}
