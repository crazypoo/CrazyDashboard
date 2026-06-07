//
//  PTSpeedometerView.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 7/6/2026.
//

import UIKit

@objcMembers
public class PTSpeedometerView: UIView {
    
    private let needleView = UIView()
    private let speedLabel = UILabel()
    
    // 配置参数 (假设最高时速 160)
    public var maxSpeed: CGFloat = 160.0
    // 仪表盘起始角度和结束角度 (弧度)
    // -240度到+60度，刚好形成一个开口向下的圆弧
    private let startAngle: CGFloat = -.pi * 4 / 3
    private let endAngle: CGFloat = .pi / 3
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        self.backgroundColor = .clear
        
        // 1. 绘制速度数字
        speedLabel.frame = CGRect(x: 0, y: bounds.height / 2 - 20, width: bounds.width, height: 60)
        speedLabel.textAlignment = .center
        speedLabel.textColor = .white
        speedLabel.font = UIFont.boldSystemFont(ofSize: 50)
        speedLabel.text = "0"
        addSubview(speedLabel)
        
        // 2. 绘制指针
        let needleWidth: CGFloat = 4.0
        let needleHeight: CGFloat = bounds.height / 2.2
        needleView.frame = CGRect(x: bounds.width / 2 - needleWidth / 2,
                                  y: bounds.height / 2 - needleHeight,
                                  width: needleWidth,
                                  height: needleHeight)
        needleView.backgroundColor = .red
        needleView.layer.cornerRadius = needleWidth / 2
        
        // 【关键点】将指针的旋转锚点移到底部中心！
        needleView.layer.anchorPoint = CGPoint(x: 0.5, y: 1.0)
        // 调整 frame 以补偿锚点移动带来的位置偏移
        needleView.frame.origin.y += needleHeight / 2
        
        addSubview(needleView)
        
        // 初始位置归零
        updateSpeed(0, animated: false)
    }
    
    // 外部调用的更新速度方法
    public func updateSpeed(_ currentSpeed: CGFloat, animated: Bool = true) {
        // 限制最高速度，防止指针爆表
        let safeSpeed = min(max(currentSpeed, 0), maxSpeed)
        
        // 更新数字
        speedLabel.text = "\(Int(safeSpeed))"
        
        // 计算旋转角度
        let speedRatio = safeSpeed / maxSpeed
        let totalAngle = endAngle - startAngle
        let targetAngle = startAngle + (speedRatio * totalAngle)
        
        // 必须加上 pi/2 的偏移，因为 UIView 默认向上的角度是 -pi/2
        let rotationTransform = CGAffineTransform(rotationAngle: targetAngle + .pi / 2)
        
        if animated {
            UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut, animations: {
                self.needleView.transform = rotationTransform
            }, completion: nil)
        } else {
            needleView.transform = rotationTransform
        }
    }
}
