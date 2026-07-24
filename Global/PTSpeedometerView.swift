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

/// 赛道风格专属仪表盘指针
public class PTNeedleView: UIView {
    
    // MARK: - 属性
    public var needleColor: UIColor = .red {
        didSet { shapeLayer.fillColor = needleColor.cgColor }
    }
    
    private let shapeLayer = CAShapeLayer()
    
    // MARK: - 初始化
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    private func setupUI() {
        self.backgroundColor = .clear // 必须透明，否则会有矩形黑边
        shapeLayer.fillColor = needleColor.cgColor
        // 抗锯齿优化，确保指针边缘在旋转时依然锐利
        shapeLayer.contentsScale = UIScreen.main.scale
        layer.addSublayer(shapeLayer)
    }
    
    // MARK: - 核心路径绘制
    public override func layoutSubviews() {
        super.layoutSubviews()
        shapeLayer.frame = bounds
        
        let width = bounds.width
        let height = bounds.height
        let baseRadius = width / 2.0 // 底座圆的半径等于视图宽度的一半
        
        // 底座圆心坐标 (位于视图底部，向上偏移一个半径的距离)
        let baseCenter = CGPoint(x: width / 2.0, y: height - baseRadius)
        // 针尖坐标 (位于视图顶部正中央)
        let topPoint = CGPoint(x: width / 2.0, y: 0)
        
        let path = UIBezierPath()
        
        // 1. 画底部圆弧 (从右侧 0 度画到左侧 180 度，绕过底部)
        // 注意：iOS 坐标系 Y 轴朝下，所以顺时针 (clockwise: true) 是从右往下再到左
        path.addArc(withCenter: baseCenter,
                    radius: baseRadius,
                    startAngle: 0,
                    endAngle: .pi,
                    clockwise: true)
        
        // 2. 从左侧边缘连接到顶部针尖
        path.addLine(to: topPoint)
        
        // 3. 闭合路径 (系统会自动从针尖连回起始的右侧边缘)
        path.close()
        
        shapeLayer.path = path.cgPath
    }
}

@objcMembers
public class PTSpeedometerView: UIView {
    
    // MARK: - 🚨 仪表盘方向枚举 (已扩展 4 种方向)
    public enum Direction {
        case clockwise          // 开口在右 (起点右下，顺时针)
        case counterClockwise   // 开口在左 (起点左下，逆时针)
        case bottomOpening      // 开口在下 (起点左下，顺时针跨越顶部)
        case topOpening         // 开口在上 (起点左上，逆时针跨越底部)
    }
    
    // MARK: - 新增：指针与刻度的扫略方向控制
    public enum SweepDirection {
        case standard // 标准方向 (按设定好的物理轨迹扫略)
        case reversed // 镜像反向 (起点与终点对调，常用于右侧对称表盘)
    }

    // MARK: - 外部可配属性 (动态刷新)
    
    /// 指针和刻度的扫略方向，修改后自动刷新
    public var sweepDirection: SweepDirection = .standard {
        didSet { reloadAppearance() }
    }

    // MARK: - 🚨 核心魔法：动态轨迹转换器
        
    /// 实际绘制的起始角度
    private var actualStartAngle: CGFloat {
        return sweepDirection == .standard ? arcStartAngle : arcEndAngle
    }
    
    /// 实际绘制的结束角度
    private var actualEndAngle: CGFloat {
        return sweepDirection == .standard ? arcEndAngle : arcStartAngle
    }
    
    /// 实际的指针行进方向 (顺时针/逆时针)
    private var actualIsClockwise: Bool {
        return sweepDirection == .standard ? isClockwiseDrawing : !isClockwiseDrawing
    }

    /// 仪表盘方向，修改后自动刷新布局和刻度
    public var direction: Direction = .clockwise {
        didSet { reloadAppearance() }
    }
    
    public enum GaugeType {
        case speedometer // 速度盘 (纯色刻度)
        case tachometer  // 转速盘 (支持红区警示色)
    }
    
    /// 当前仪表盘的作用类型
    public var gaugeType: GaugeType = .speedometer {
        didSet { reloadAppearance() }
    }
    
    /// 转速红区数值范围 (仅当 gaugeType 为 .tachometer 时生效)
    public var redlineRange: ClosedRange<CGFloat> = 9000...10000 {
        didSet { reloadAppearance() }
    }
    
    /// 刻度文字的默认颜色
    public var scaleTextColor: UIColor = .white {
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
    
    public var majorTickStep: CGFloat = 10.0 {
        didSet { reloadAppearance() }
    }

    /// 进度条颜色
    public var progressColor: UIColor = .systemRed {
        didSet { progressLayer.strokeColor = progressColor.cgColor }
    }
    
    /// 指针颜色
    public var needleColor: UIColor = .red {
        didSet { needleView.needleColor = needleColor }
    }
    
    // MARK: - UI 组件
    private let needleView = PTNeedleView()
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
    
    // MARK: - 🚨 角度体系动态计算
    
    /// 统一判断当前方向是否为顺时针绘制
    private var isClockwiseDrawing: Bool {
        return direction == .clockwise || direction == .bottomOpening
    }
    
    /// 计算圆弧起点
    private var arcStartAngle: CGFloat {
        switch direction {
        case .clockwise:          return .pi / 4       // 45° (右下)
        case .counterClockwise:   return .pi * 3 / 4   // 135° (左下)
        case .bottomOpening:      return .pi * 3 / 4   // 135° (左下)
        case .topOpening:         return .pi * 5 / 4   // 225° (左上)
        }
    }
    
    /// 计算圆弧终点
    private var arcEndAngle: CGFloat {
        switch direction {
        case .clockwise:          return .pi * 7 / 4   // 315° (右上)
        case .counterClockwise:   return -.pi * 3 / 4  // -135° (左上)
        case .bottomOpening:      return .pi / 4       // 45° (右下)
        case .topOpening:         return -.pi / 4      // -45° (右上)
        }
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
        
        if previousSize != bounds.size {
            previousSize = bounds.size
            
            // 同步更新 CAShapeLayer 和基础 Layer 的 frame
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
        speedLabel.font = .appfont(size: 55)
        speedLabel.text = "0"
        
        unitLabel.textAlignment = .center
        unitLabel.textColor = .lightGray
        unitLabel.font = .appfont(size: 14)
        unitLabel.text = "km/h"
        
        altitudeLabel.textColor = .white
        altitudeLabel.font = .appfont(size: 13)
        altitudeLabel.text = "海拔: -- m"
        
        pressureLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        pressureLabel.font = .appfont(size: 13)
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
        needleView.needleColor = needleColor
        needleView.layer.anchorPoint = CGPoint(x: 0.5, y: 0.94)
        addSubview(needleView)
        
        needleView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.equalTo(12)
            make.height.equalTo(100)
        }
    }
    
    // MARK: - 核心重绘引擎
    public func reloadAppearance() {
        guard bounds.width > 0 else { return }
        
        let center = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
        let radius = bounds.width / 2 - 20
        
        // 1. 重新绘制轨道圆弧 (🚨 使用 isClockwiseDrawing)
        let path = UIBezierPath(arcCenter: center,
                                radius: radius,
                                startAngle: actualStartAngle,
                                endAngle: actualEndAngle,
                                clockwise: actualIsClockwise)
        
        trackLayer.path = path.cgPath
        progressLayer.path = path.cgPath
        
        // 2. 清空旧刻度并重新渲染新刻度
        scaleLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        drawScaleMarks(center: center, radius: radius)
        
        // 3. 动态调整副标签 (海拔/气压) 的位置和对齐方式 (🚨 使用 isClockwiseDrawing)
        altitudeLabel.textAlignment = isClockwiseDrawing ? .right : .left
        pressureLabel.textAlignment = isClockwiseDrawing ? .right : .left
        
        altitudeLabel.snp.remakeConstraints { make in
            make.centerY.equalToSuperview()
            if isClockwiseDrawing {
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
        
        let safeMajorStep = majorTickStep > 0 ? majorTickStep : safeStep
        
        for i in 0...tickCount {
            let currentSpeed = CGFloat(i) * safeStep
            let speedRatio = currentSpeed / maxSpeed
            
            // 计算刻度角度 (依赖是否顺时针)
            let angle: CGFloat
            if actualIsClockwise {
                angle = actualStartAngle + (speedRatio * totalSweepAngle)
            } else {
                angle = actualStartAngle - (speedRatio * totalSweepAngle)
            }
            
            // 只要能被 1000 整除，或者是满表最后一格，就是主刻度
            let isThousandMark = currentSpeed.truncatingRemainder(dividingBy: safeMajorStep) == 0
            let isMajorTick = isThousandMark || i == tickCount
            
            // 🚨 统一判断：当前刻度是否属于红区警示范围
            let isRedline = (gaugeType == .tachometer && redlineRange.contains(currentSpeed))
            
            // 主副刻度的长度区分
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
            
            // 🚨 核心改动 1：刻度线颜色逻辑
            if isRedline {
                // 如果是红区，线条统一染红（副刻度使用稍微带点透明度的红色以保持层次感）
                tickLayer.strokeColor = isMajorTick ? UIColor.systemRed.cgColor : UIColor.systemRed.withAlphaComponent(0.6).cgColor
            } else {
                // 正常区域，主刻度白，副刻度灰
                tickLayer.strokeColor = isMajorTick ? UIColor.white.cgColor : UIColor.lightGray.cgColor
            }
            
            tickLayer.lineWidth = isMajorTick ? 2.5 : 1.5
            scaleLayer.addSublayer(tickLayer)
            
            // 绘制文字 (只在主刻度绘制)
            if isMajorTick {
                let textRadius = radius - tickLength - 22
                let textCenter = CGPoint(x: center.x + textRadius * cos(angle),
                                         y: center.y + textRadius * sin(angle))
                
                let textLayer = CATextLayer()
                
                // 更智能的数值换算器：保留小数点支持
                let displayValue: String
                if maxSpeed >= 1000 {
                    let scaled = currentSpeed / 1000.0
                    if scaled.truncatingRemainder(dividingBy: 1) == 0 {
                        displayValue = String(format: "%.0f", scaled)
                    } else {
                        displayValue = String(format: "%.1f", scaled)
                    }
                } else {
                    displayValue = "\(Int(currentSpeed))"
                }
                
                textLayer.string = displayValue
                textLayer.font = UIFont.appfont(size: 14)
                textLayer.fontSize = UIFont.appfont(size: 14).pointSize
                
                // 🚨 核心改动 2：复用 isRedline 判断文字颜色
                if isRedline {
                    textLayer.foregroundColor = UIColor.systemRed.cgColor
                } else {
                    textLayer.foregroundColor = scaleTextColor.cgColor
                }
                
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

    // MARK: - 更新数据
    public func updateSpeed(_ currentSpeed: CGFloat, animated: Bool = true) {
        currentSpeedRaw = currentSpeed
        let safeSpeed = min(max(currentSpeed, 0), maxSpeed)
        speedLabel.text = "\(Int(safeSpeed))"
        
        let speedRatio = safeSpeed / maxSpeed
        
        // 🚨 修正目标角度计算
        let targetAngle: CGFloat
        if actualIsClockwise {
            targetAngle = actualStartAngle + (speedRatio * totalSweepAngle)
        } else {
            targetAngle = actualStartAngle - (speedRatio * totalSweepAngle)
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

extension PTSpeedometerView {
    
    // MARK: - 动态换挡/红区提示引擎
    
    public func applyShiftLightLogic(currentRpm: Int,
                                     redlineRpm: Int = 8000,
                                     normalColor: UIColor = .systemBlue,
                                     warningColor: UIColor = .systemRed) {
        
        let isInRedline = currentRpm >= redlineRpm
        
        let targetColor = isInRedline ? warningColor : normalColor
        if self.progressColor != targetColor {
            self.progressColor = targetColor
        }
        
        if isInRedline {
            startRedlineFlashing()
        } else {
            stopRedlineFlashing()
        }
    }
    
    private func startRedlineFlashing() {
        guard unitLabel.layer.animation(forKey: "redlineFlash") == nil else { return }
        
        let flash = CABasicAnimation(keyPath: "opacity")
        flash.fromValue = 1.0
        flash.toValue = 0.2
        flash.duration = 0.15
        flash.autoreverses = true
        flash.repeatCount = .infinity
        
        speedLabel.layer.add(flash, forKey: "redlineFlash")
        unitLabel.layer.add(flash, forKey: "redlineFlash")
    }
    
    private func stopRedlineFlashing() {
        speedLabel.layer.removeAnimation(forKey: "redlineFlash")
        unitLabel.layer.removeAnimation(forKey: "redlineFlash")
        speedLabel.alpha = 1.0
        unitLabel.alpha = 1.0
    }
}
