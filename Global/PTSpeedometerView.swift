//
//  PTSpeedometerView.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 7/6/2026.
//

import UIKit
import SnapKit
import PooTools
import SwifterSwift

@objcMembers
public class PTSpeedometerView: UIView {
    
    // MARK: - 仪表盘方向枚举
    public enum Direction {
        case clockwise        // 顺时针 (起点右下)
        case counterClockwise // 逆时针 (起点左下)
    }
    
    // MARK: - 外部可配属性 (动态刷新)
    
    /// 仪表盘方向，修改后自动刷新布局和刻度
    public var direction: Direction = .clockwise {
        didSet { reloadAppearance() }
    }
    
    /// 满表时速
    public var maxSpeed: CGFloat = 300.0 {
        didSet { reloadAppearance() }
    }
    
    /// 刻度的数值步长 (决定显示多少个数字，例如 30 就是每隔 30 画一个主刻度)
    public var tickStep: CGFloat = 30.0 {
        didSet { reloadAppearance() }
    }
    
    /// 进度条颜色
    public var progressColor: UIColor = .systemRed {
        didSet { progressLayer.strokeColor = progressColor.cgColor }
    }
    
    /// 指针颜色
    public var needleColor: UIColor = .red {
        didSet { needleView.backgroundColor = needleColor }
    }
    
    // MARK: - UI 组件
    private let needleView = UIView()
    private let speedLabel = UILabel()
    public let unitLabel = UILabel()
    public let altitudeLabel = UILabel()
    public let pressureLabel = UILabel()
    
    private let trackLayer = CAShapeLayer()
    private let progressLayer = CAShapeLayer()
    private let scaleLayer = CALayer()
    
    // 内部状态
    private var currentSpeedRaw: CGFloat = 0
    private var previousSize: CGSize = .zero
    
    // MARK: - 角度体系动态计算
    private var arcStartAngle: CGFloat {
        return direction == .clockwise ? .pi / 4 : .pi * 3 / 4
    }
    
    private var arcEndAngle: CGFloat {
        return direction == .clockwise ? .pi * 7 / 4 : -.pi * 3 / 4
    }
    
    private let totalSweepAngle: CGFloat = .pi * 1.5 // 固定扫过 270 度
    
    // MARK: - 初始化
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        
        // 确保 bounds 已经有实际大小
        guard bounds.width > 0, bounds.height > 0 else { return }
        
        // 🚨 核心修复：只有当视图的实际尺寸发生变化时，才重新渲染底层 Layer 和路径
        if previousSize != bounds.size {
            previousSize = bounds.size
            
            // 同步更新 CAShapeLayer 和基础 Layer 的 frame，防止它们越界或原点错误
            trackLayer.frame = bounds
            progressLayer.frame = bounds
            scaleLayer.frame = bounds
            
            // 重新计算并绘制圆弧和刻度
            reloadAppearance()
        }
    }
    
    // MARK: - 基础 UI 设置
    private func setupUI() {
        self.backgroundColor = UIColor.black.withAlphaComponent(0.6)

        // 1. 轨道层
        trackLayer.fillColor = UIColor.clear.cgColor
        trackLayer.strokeColor = UIColor.darkGray.withAlphaComponent(0.5).cgColor
        trackLayer.lineWidth = 8
        trackLayer.lineCap = .round
        layer.addSublayer(trackLayer)
        
        // 2. 进度层
        progressLayer.fillColor = UIColor.clear.cgColor
        progressLayer.strokeColor = progressColor.cgColor
        progressLayer.lineWidth = 8
        progressLayer.lineCap = .round
        progressLayer.strokeEnd = 0
        layer.addSublayer(progressLayer)
        
        layer.addSublayer(scaleLayer)

        // 3. 数字标签
        speedLabel.textAlignment = .center
        speedLabel.textColor = .white
        speedLabel.font = UIFont.boldSystemFont(ofSize: 55)
        speedLabel.text = "0"
        
        unitLabel.textAlignment = .center
        unitLabel.textColor = .lightGray
        unitLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        unitLabel.text = "km/h"
        
        altitudeLabel.textColor = .white
        altitudeLabel.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        altitudeLabel.text = "海拔: -- m"
        
        pressureLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        pressureLabel.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        pressureLabel.text = "气压: -- hPa"
        
        addSubviews([speedLabel, unitLabel, altitudeLabel, pressureLabel])
        
        speedLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.centerY.equalToSuperview().offset(-10)
        }
        
        unitLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(speedLabel.snp.bottom).offset(-5)
        }

        // 4. 指针
        needleView.backgroundColor = needleColor
        needleView.layer.cornerRadius = 2
        needleView.layer.anchorPoint = CGPoint(x: 0.5, y: 1.0)
        addSubview(needleView)
        
        needleView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.equalTo(4)
            make.height.equalTo(100) // 稍后会在 reloadAppearance 中更新高度
        }
    }
    
    // MARK: - 核心重绘引擎
    /// 清理并根据当前属性重新渲染轨道、刻度和布局
    public func reloadAppearance() {
        guard bounds.width > 0 else { return }
        
        let center = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
        let radius = bounds.width / 2 - 20
        
        // 1. 重新绘制轨道圆弧
        let isClockwise = (direction == .clockwise)
        let path = UIBezierPath(arcCenter: center,
                                radius: radius,
                                startAngle: arcStartAngle,
                                endAngle: arcEndAngle,
                                clockwise: isClockwise)
        
        trackLayer.path = path.cgPath
        progressLayer.path = path.cgPath
        
        // 2. 清空旧刻度并重新渲染新刻度
        scaleLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        drawScaleMarks(center: center, radius: radius)
        
        // 3. 动态调整副标签 (海拔/气压) 的位置和对齐方式
        altitudeLabel.textAlignment = isClockwise ? .right : .left
        pressureLabel.textAlignment = isClockwise ? .right : .left
        
        altitudeLabel.snp.remakeConstraints { make in
            make.centerY.equalToSuperview()
            if isClockwise {
                make.left.equalTo(speedLabel.snp.right).offset(5)
                make.right.equalToSuperview().inset(5)
            } else {
                make.right.equalTo(speedLabel.snp.left).offset(-5)
                make.left.equalToSuperview().inset(5)
            }
        }
        
        pressureLabel.snp.remakeConstraints { make in
            make.left.right.equalTo(altitudeLabel)
            make.top.equalTo(altitudeLabel.snp.bottom).offset(4)
        }
        
        // 4. 修正指针高度
        needleView.snp.updateConstraints { make in
            make.height.equalTo(radius - 5)
        }
        
        // 5. 保持当前速度的指针位置正确
        updateSpeed(currentSpeedRaw, animated: false)
    }
    
    // MARK: - 绘制刻度
    private func drawScaleMarks(center: CGPoint, radius: CGFloat) {
        let safeStep = tickStep > 0 ? tickStep : 10.0
        let tickCount = Int(maxSpeed / safeStep)
        
        for i in 0...tickCount {
            let currentSpeed = CGFloat(i) * safeStep
            let speedRatio = currentSpeed / maxSpeed
            
            let angle: CGFloat
            if direction == .clockwise {
                angle = arcStartAngle + (speedRatio * totalSweepAngle)
            } else {
                angle = arcStartAngle - (speedRatio * totalSweepAngle)
            }
            
            let isMajorTick = (i % 3 == 0) || i == tickCount
            let tickLength: CGFloat = isMajorTick ? 14.0 : 6.0
            
            let outerPoint = CGPoint(x: center.x + radius * cos(angle),
                                     y: center.y + radius * sin(angle))
            let innerPoint = CGPoint(x: center.x + (radius - tickLength) * cos(angle),
                                     y: center.y + (radius - tickLength) * sin(angle))
            
            let tickPath = UIBezierPath()
            tickPath.move(to: outerPoint)
            tickPath.addLine(to: innerPoint)
            
            let tickLayer = CAShapeLayer()
            tickLayer.path = tickPath.cgPath
            tickLayer.strokeColor = isMajorTick ? UIColor.white.cgColor : UIColor.lightGray.cgColor
            tickLayer.lineWidth = isMajorTick ? 2.5 : 1.5
            scaleLayer.addSublayer(tickLayer)
            
            // 绘制文字 (只在主刻度绘制)
            if isMajorTick {
                let textRadius = radius - tickLength - 22
                let textCenter = CGPoint(x: center.x + textRadius * cos(angle),
                                         y: center.y + textRadius * sin(angle))
                
                let textLayer = CATextLayer()
                
                // 🚨 核心优化：智能数值换算器
                // 如果满表数值 >= 1000，刻度盘自动除以 1000 显示 (例如 12000 -> 12)
                let displayValue: Int
                if maxSpeed >= 1000 {
                    displayValue = Int(currentSpeed) / 1000
                } else {
                    displayValue = Int(currentSpeed)
                }
                
                textLayer.string = "\(displayValue)"
                textLayer.font = UIFont.systemFont(ofSize: 14, weight: .bold)
                textLayer.fontSize = 14
                textLayer.foregroundColor = UIColor.white.cgColor
                textLayer.alignmentMode = .center
                textLayer.contentsScale = UIScreen.main.scale
                
                // 文本框宽度可以恢复到 36，因为除以 1000 后，最大的数字也就是两位数 (如 12)
                let textWidth: CGFloat = 36
                let textHeight: CGFloat = 16
                textLayer.frame = CGRect(x: textCenter.x - textWidth/2,
                                         y: textCenter.y - textHeight/2,
                                         width: textWidth, height: textHeight)
                
                scaleLayer.addSublayer(textLayer)
            }
        }
    }

    // MARK: - 更新数据
    public func updateSpeed(_ currentSpeed: CGFloat, animated: Bool = true) {
        currentSpeedRaw = currentSpeed
        let safeSpeed = min(max(currentSpeed, 0), maxSpeed)
        speedLabel.text = "\(Int(safeSpeed))"
        
        let speedRatio = safeSpeed / maxSpeed
        let targetAngle: CGFloat
        
        if direction == .clockwise {
            targetAngle = arcStartAngle + (speedRatio * totalSweepAngle)
        } else {
            targetAngle = arcStartAngle - (speedRatio * totalSweepAngle)
        }
        
        let rotationTransform = CGAffineTransform(rotationAngle: targetAngle + .pi / 2)
        
        if animated {
            UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut, animations: {
                self.needleView.transform = rotationTransform
            }, completion: nil)
            self.progressLayer.strokeEnd = speedRatio
        } else {
            needleView.transform = rotationTransform
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.progressLayer.strokeEnd = speedRatio
            CATransaction.commit()
        }
    }
    
    public func updateEnvironment(altitude: Double?, pressureKpa: Double?) {
        if let alt = altitude {
            self.altitudeLabel.text = PTDashboardConfig.language(key: "elevation_value", Int(alt))
        }
        
        if let kpa = pressureKpa, kpa > 0 {
            let hpa = kpa * 10.0
            self.pressureLabel.text = PTDashboardConfig.language(key: "hpa_value", hpa)
        }
    }
}
