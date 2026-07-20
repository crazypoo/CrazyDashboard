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
    
    private let needleView = UIView()
    private let speedLabel = UILabel()
    public let unitLabel = UILabel() // 显示 km/h
    
    public let altitudeLabel = UILabel()
    public let pressureLabel = UILabel()
    
    // 满表时速
    public var maxSpeed: CGFloat = 300.0
    
    // MARK: - 角度体系 (更新：起点右下角，顺时针 270 度)
    // 45度 (π/4) 作为起点 (右下角)
    // 顺时针走过 270度 (1.5π) 后，终点落在 315度 (7π/4，右上角)
    private let arcStartAngle: CGFloat = .pi / 4
    private let arcEndAngle: CGFloat = .pi * 7 / 4
    
    private let trackLayer = CAShapeLayer()
    private let progressLayer = CAShapeLayer()
    private let scaleLayer = CALayer()
    
    private var isScaleDrawn = false

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        
        guard bounds.width > 0, !isScaleDrawn else { return }
        isScaleDrawn = true
        
        let center = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
        let radius = bounds.width / 2 - 20
        
        // 1. 画背景圆弧 (顺时针)
        let path = UIBezierPath(arcCenter: center,
                                radius: radius,
                                startAngle: arcStartAngle,
                                endAngle: arcEndAngle,
                                clockwise: true) // 保持顺时针
        
        trackLayer.path = path.cgPath
        progressLayer.path = path.cgPath
        
        // 2. 渲染刻度
        drawScaleMarks(center: center, radius: radius)
        
        // 3. 修正指针高度
        needleView.snp.updateConstraints { make in
            make.height.equalTo(radius - 5)
        }
    }

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
        progressLayer.strokeColor = UIColor.systemRed.cgColor
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
        altitudeLabel.textAlignment = .right
        altitudeLabel.text = "海拔: -- m"
        
        pressureLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        pressureLabel.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        pressureLabel.textAlignment = .right
        pressureLabel.text = "气压: -- hPa"
        addSubviews([speedLabel,unitLabel,altitudeLabel,pressureLabel])
        
        speedLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.centerY.equalToSuperview().offset(-10)
        }
        
        unitLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(speedLabel.snp.bottom).offset(-5)
        }
        
        altitudeLabel.snp.makeConstraints { make in
            make.left.equalTo(self.speedLabel.snp.right).offset(5)
            make.right.equalToSuperview().inset(5)
            make.centerY.equalToSuperview()
        }
        
        pressureLabel.snp.makeConstraints { make in
            make.left.right.equalTo(altitudeLabel)
            make.top.equalTo(altitudeLabel.snp.bottom).offset(4)
        }

        // 4. 指针
        needleView.backgroundColor = .red
        needleView.layer.cornerRadius = 2
        needleView.layer.anchorPoint = CGPoint(x: 0.5, y: 1.0)
        addSubview(needleView)
        
        needleView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.equalTo(4)
            make.height.equalTo(100) // 占位高度
        }
        
        updateSpeed(0, animated: false)
    }
    
    // MARK: - 绘制刻度
    private func drawScaleMarks(center: CGPoint, radius: CGFloat) {
        let totalAngle = arcEndAngle - arcStartAngle
        let step: CGFloat = 10.0
        let tickCount = Int(maxSpeed / step)
        
        for i in 0...tickCount {
            let currentSpeed = CGFloat(i) * step
            let speedRatio = currentSpeed / maxSpeed
            let angle = arcStartAngle + (speedRatio * totalAngle)
            
            let isMajorTick = Int(currentSpeed) % 30 == 0
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
            
            if Int(currentSpeed) % 60 == 0 || Int(currentSpeed) == 0 {
                let textRadius = radius - tickLength - 16
                let textCenter = CGPoint(x: center.x + textRadius * cos(angle),
                                         y: center.y + textRadius * sin(angle))
                
                let textLayer = CATextLayer()
                textLayer.string = "\(Int(currentSpeed))"
                textLayer.font = UIFont.systemFont(ofSize: 14, weight: .bold)
                textLayer.fontSize = 14
                textLayer.foregroundColor = UIColor.white.cgColor
                textLayer.alignmentMode = .center
                textLayer.contentsScale = UIScreen.main.scale
                
                let textWidth: CGFloat = 36
                let textHeight: CGFloat = 16
                textLayer.frame = CGRect(x: textCenter.x - textWidth/2,
                                         y: textCenter.y - textHeight/2,
                                         width: textWidth, height: textHeight)
                
                scaleLayer.addSublayer(textLayer)
            }
        }
    }
    
    public func updateSpeed(_ currentSpeed: CGFloat, animated: Bool = true) {
        let safeSpeed = min(max(currentSpeed, 0), maxSpeed)
        speedLabel.text = "\(Int(safeSpeed))"
        
        let speedRatio = safeSpeed / maxSpeed
        let totalAngle = arcEndAngle - arcStartAngle
        let targetAngle = arcStartAngle + (speedRatio * totalAngle)
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
        // 1. 更新绝对海拔 (如果是 nil 则不更新)
        if let alt = altitude {
            self.altitudeLabel.text = "海拔: \(Int(alt)) m"
        }
        
        // 2. 更新气压 (苹果单位是 kPa，乘以 10 变成常用的百帕 hPa)
        if let kpa = pressureKpa, kpa > 0 {
            let hpa = kpa * 10.0
            self.pressureLabel.text = String(format: "气压: %.1f hPa", hpa)
        }
    }
}

@objcMembers
public class PTReversedSpeedometerView: UIView {
    
    private let needleView = UIView()
    private let speedLabel = UILabel()
    public let unitLabel = UILabel()
    
    public let altitudeLabel = UILabel()
    public let pressureLabel = UILabel()
    
    // 满表时速
    public var maxSpeed: CGFloat = 300.0
    
    // MARK: - 角度体系 (更新：起点左下角，逆时针 270 度)
    // 135度 (3π/4) 作为起点 (左下角)
    // 逆时针走过 270度 (1.5π) 后，终点落在 225度 (-3π/4 或 5π/4，左上角)
    private let arcStartAngle: CGFloat = .pi * 3 / 4
    private let arcEndAngle: CGFloat = -.pi * 3 / 4
    // 扫过的总角度固定为 270 度 (1.5π)
    private let totalSweepAngle: CGFloat = .pi * 1.5
    
    private let trackLayer = CAShapeLayer()
    private let progressLayer = CAShapeLayer()
    private let scaleLayer = CALayer()
    
    private var isScaleDrawn = false

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        
        guard bounds.width > 0, !isScaleDrawn else { return }
        isScaleDrawn = true
        
        let center = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
        let radius = bounds.width / 2 - 20
        
        // 1. 画背景圆弧 (注意：clockwise 改为了 false，即逆时针)
        let path = UIBezierPath(arcCenter: center,
                                radius: radius,
                                startAngle: arcStartAngle,
                                endAngle: arcEndAngle,
                                clockwise: false)
        
        trackLayer.path = path.cgPath
        progressLayer.path = path.cgPath
        
        // 2. 渲染刻度
        drawScaleMarks(center: center, radius: radius)
        
        // 3. 修正指针高度
        needleView.snp.updateConstraints { make in
            make.height.equalTo(radius - 5)
        }
    }

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
        progressLayer.strokeColor = UIColor.systemRed.cgColor
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
        
        // 💡 修改点：为了配合左侧开口，文本对齐方式改为居左
        altitudeLabel.textColor = .white
        altitudeLabel.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        altitudeLabel.textAlignment = .left
        altitudeLabel.text = "海拔: -- m"
        
        pressureLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        pressureLabel.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        pressureLabel.textAlignment = .left
        pressureLabel.text = "气压: -- hPa"
        
        addSubviews([speedLabel,unitLabel,altitudeLabel,pressureLabel])
        
        speedLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.centerY.equalToSuperview().offset(-10)
        }
        
        unitLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(speedLabel.snp.bottom).offset(-5)
        }
        
        // 💡 修改点：将副标签移到了速度标签的左侧，填补左侧开口的空白
        altitudeLabel.snp.makeConstraints { make in
            make.right.equalTo(self.speedLabel.snp.left).offset(-5)
            make.left.equalToSuperview().inset(5)
            make.centerY.equalToSuperview()
        }
        
        pressureLabel.snp.makeConstraints { make in
            make.left.right.equalTo(altitudeLabel)
            make.top.equalTo(altitudeLabel.snp.bottom).offset(4)
        }

        // 4. 指针
        needleView.backgroundColor = .red
        needleView.layer.cornerRadius = 2
        needleView.layer.anchorPoint = CGPoint(x: 0.5, y: 1.0)
        addSubview(needleView)
        
        needleView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.equalTo(4)
            make.height.equalTo(100) // 占位高度
        }
        
        updateSpeed(0, animated: false)
    }
    
    // MARK: - 绘制刻度
    private func drawScaleMarks(center: CGPoint, radius: CGFloat) {
        let step: CGFloat = maxSpeed > 1000 ? 1000.0 : 10.0
        let tickCount = Int(maxSpeed / step)
        
        for i in 0...tickCount {
            let currentSpeed = CGFloat(i) * step
            let speedRatio = currentSpeed / maxSpeed
            
            // 💡 修改点：逆时针方向，角度应该递减，所以用 arcStartAngle 减去偏移量
            let angle = arcStartAngle - (speedRatio * totalSweepAngle)
            
            let isMajorTick = Int(currentSpeed) % 30 == 0
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
            
            if Int(currentSpeed) % 60 == 0 || Int(currentSpeed) == 0 {
                let textRadius = radius - tickLength - 16
                let textCenter = CGPoint(x: center.x + textRadius * cos(angle),
                                         y: center.y + textRadius * sin(angle))
                
                let textLayer = CATextLayer()
                textLayer.string = "\(Int(currentSpeed))"
                textLayer.font = UIFont.systemFont(ofSize: 14, weight: .bold)
                textLayer.fontSize = 14
                textLayer.foregroundColor = UIColor.white.cgColor
                textLayer.alignmentMode = .center
                textLayer.contentsScale = UIScreen.main.scale
                
                let textWidth: CGFloat = 36
                let textHeight: CGFloat = 16
                textLayer.frame = CGRect(x: textCenter.x - textWidth/2,
                                         y: textCenter.y - textHeight/2,
                                         width: textWidth, height: textHeight)
                
                scaleLayer.addSublayer(textLayer)
            }
        }
    }
    
    public func updateSpeed(_ currentSpeed: CGFloat, animated: Bool = true) {
        let safeSpeed = min(max(currentSpeed, 0), maxSpeed)
        speedLabel.text = "\(Int(safeSpeed))"
        
        let speedRatio = safeSpeed / maxSpeed
        // 💡 修改点：逆时针方向，计算目标角度时使用减法
        let targetAngle = arcStartAngle - (speedRatio * totalSweepAngle)
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
            self.altitudeLabel.text = "海拔: \(Int(alt)) m"
        }
        
        if let kpa = pressureKpa, kpa > 0 {
            let hpa = kpa * 10.0
            self.pressureLabel.text = String(format: "气压: %.1f hPa", hpa)
        }
    }
}
