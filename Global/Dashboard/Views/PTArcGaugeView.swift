//
//  PTArcGaugeView.swift
//  PTSpeed
//
//  Created by 邓杰豪 on 14/8/2026.
//

import UIKit
import SnapKit
import SwifterSwift
import SafeSFSymbols
import PooTools

public enum PTGaugeType {
    case fuel        // 左侧：油量表
    case temperature // 右侧：水温表
}

// MARK: - 逼真复刻版：机甲风分段式弧形仪表盘 (绝对自适应修复版)
public class PTArcGaugeView: UIView {
    
    private let trackLayer = CAShapeLayer()
    private let dangerTrackLayer = CAShapeLayer()
    private let progressLayer = CAShapeLayer()
    private let tickLayer = CAShapeLayer()
    private let textContainerLayer = CALayer()
    
    public let type: PTGaugeType
    
    public var progress: CGFloat = 0.0 {
        didSet {
            let safeProgress = max(0.0, min(1.0, progress))
            progressLayer.strokeEnd = safeProgress
        }
    }
    
    private let tickLabels: [String]
    
    public init(type: PTGaugeType) {
        self.type = type
        if type == .fuel {
            self.tickLabels = ["0", "1/2", "1"]
        } else {
            self.tickLabels = ["50", "90", "130"]
        }
        super.init(frame: .zero)
        setupLayers()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupLayers() {
        trackLayer.fillColor = UIColor.clear.cgColor
        trackLayer.strokeColor = UIColor.darkGray.withAlphaComponent(0.4).cgColor
        trackLayer.lineWidth = 14.0
        trackLayer.lineDashPattern = [6, 2] // 虚线机甲风
        layer.addSublayer(trackLayer)
        
        dangerTrackLayer.fillColor = UIColor.clear.cgColor
        dangerTrackLayer.strokeColor = UIColor.systemRed.withAlphaComponent(0.6).cgColor
        dangerTrackLayer.lineWidth = 14.0
        dangerTrackLayer.lineDashPattern = [6, 2]
        layer.addSublayer(dangerTrackLayer)
        
        progressLayer.fillColor = UIColor.clear.cgColor
        progressLayer.strokeColor = UIColor.white.cgColor
        progressLayer.lineWidth = 14.0
        progressLayer.lineDashPattern = [6, 2]
        progressLayer.strokeEnd = 0.0
        layer.addSublayer(progressLayer)
        
        tickLayer.fillColor = UIColor.clear.cgColor
        tickLayer.strokeColor = UIColor.lightGray.cgColor
        tickLayer.lineWidth = 2.0
        layer.addSublayer(tickLayer)
        
        layer.addSublayer(textContainerLayer)
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        
        let w = self.bounds.width
        let h = self.bounds.height
        // 防止初始 bounds 为 0 时计算崩溃
        guard w > 0, h > 0 else { return }
        
        // 🌟 1. 弦高定理求完美半径
        // 确保圆弧绝对贴合 width 和 height 组成的矩形，一像素都不会溢出
        let radius = (h * h) / (8.0 * w) + (w / 2.0)
        let isLeft = (type == .fuel)
        
        // 🌟 2. 动态求圆心
        let centerX = isLeft ? radius : (w - radius)
        let centerY = h / 2.0
        let centerPoint = CGPoint(x: centerX, y: centerY)
        
        // 🌟 3. 终极修复：精确提取端点相对圆心的坐标，拒绝拍脑袋定角度
        let endPointX = isLeft ? w : 0
        let dx = endPointX - centerX
        let dyBottom = h - centerY  // 下端点 y 偏移
        let dyTop = 0 - centerY     // 上端点 y 偏移
        
        // 🌟 4. 绝对精准的起止角度
        let startAngle = atan2(dyBottom, dx)
        var endAngle = atan2(dyTop, dx)
        let isClockwise = isLeft
        
        // 保证左侧顺时针绘制时，终点角度在数值上大于起点角度
        if isLeft && endAngle < startAngle {
            endAngle += 2 * .pi
        }
        
        // --- 绘制主轨道 ---
        let mainPath = UIBezierPath(arcCenter: centerPoint, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: isClockwise)
        trackLayer.path = mainPath.cgPath
        progressLayer.path = mainPath.cgPath
        
        // 进度对应的角度插值函数
        func angle(at progress: CGFloat) -> CGFloat {
            if isClockwise {
                return startAngle + (endAngle - startAngle) * progress
            } else {
                return startAngle - (startAngle - endAngle) * progress
            }
        }
        
        // --- 绘制红线警示区 ---
        // 左侧油量表底部 15% 是红线；右侧水温表顶部 15% 是红线
        let dangerStart: CGFloat = isLeft ? angle(at: 0.0) : angle(at: 0.85)
        let dangerEnd: CGFloat = isLeft ? angle(at: 0.15) : angle(at: 1.0)
        
        let dangerPath = UIBezierPath(arcCenter: centerPoint, radius: radius, startAngle: dangerStart, endAngle: dangerEnd, clockwise: isClockwise)
        dangerTrackLayer.path = dangerPath.cgPath
        
        // --- 绘制内侧刻度和数字 ---
        tickLayer.path = nil
        textContainerLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        let tickPath = UIBezierPath()
        
        // 刻度线基于半径向内收缩
        let tickStartRadius = radius - 12
        let tickEndRadius = radius - 20
        let textRadius = radius - 36
        
        for i in 0..<tickLabels.count {
            let progressRatio = CGFloat(i) / CGFloat(tickLabels.count - 1)
            let currentAngle = angle(at: progressRatio)
            
            // 刻度线坐标计算
            let startX = centerX + tickStartRadius * cos(currentAngle)
            let startY = centerY + tickStartRadius * sin(currentAngle)
            let endX = centerX + tickEndRadius * cos(currentAngle)
            let endY = centerY + tickEndRadius * sin(currentAngle)
            
            tickPath.move(to: CGPoint(x: startX, y: startY))
            tickPath.addLine(to: CGPoint(x: endX, y: endY))
            
            // 文字标签坐标计算
            let textX = centerX + textRadius * cos(currentAngle)
            let textY = centerY + textRadius * sin(currentAngle)
            
            let textLayer = CATextLayer()
            textLayer.string = tickLabels[i]
            textLayer.fontSize = 11
            textLayer.font = UIFont.boldSystemFont(ofSize: 11)
            textLayer.foregroundColor = UIColor.white.cgColor
            textLayer.alignmentMode = .center
            textLayer.contentsScale = UIScreen.main.scale
            
            textLayer.frame = CGRect(x: textX - 15, y: textY - 7, width: 30, height: 14)
            textContainerLayer.addSublayer(textLayer)
        }
        
        tickLayer.path = tickPath.cgPath
    }
}
