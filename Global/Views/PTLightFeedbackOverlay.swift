//
//  PTLightFeedbackOverlay.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 24/7/2026.
//

import UIKit
import Foundation
import SnapKit

@MainActor
public class PTLightFeedbackOverlay: UIView {
    
    // MARK: - UI 组件 (4 个色块)
    private let leftTurnView = UIView()
    private let rightTurnView = UIView()
    private let highBeamView = UIView()
    private let lowBeamView = UIView()
    
    // 常量定义
    private let activeAlpha: CGFloat = 0.2
    
    // MARK: - 初始化
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        setupObservers()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - 🚨 核心：穿透所有点击事件
    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // 永远返回 nil，告诉系统：“我不处理任何触摸，请传给底下的视图”
        return nil
    }
    
    // MARK: - 布局设置
    private func setupUI() {
        self.backgroundColor = .clear
        
        // 1. 左转向 (左半屏，橙色)
        leftTurnView.backgroundColor = .systemOrange
        leftTurnView.alpha = 0
        leftTurnView.isHidden = true
        self.addSubview(leftTurnView)
        
        // 2. 右转向 (右半屏，橙色)
        rightTurnView.backgroundColor = .systemOrange
        rightTurnView.alpha = 0
        rightTurnView.isHidden = true
        self.addSubview(rightTurnView)
        
        // 3. 远光灯 (上半屏，蓝色)
        highBeamView.backgroundColor = .systemBlue
        highBeamView.alpha = 0
        highBeamView.isHidden = true
        self.addSubview(highBeamView)
        
        // 4. 近光灯 (下半屏，绿色)
        lowBeamView.backgroundColor = .systemGreen
        lowBeamView.alpha = 0
        lowBeamView.isHidden = true
        self.addSubview(lowBeamView)
        
        // 使用 SnapKit 约束
        leftTurnView.snp.makeConstraints { make in
            make.top.bottom.left.equalToSuperview()
            make.width.equalToSuperview().multipliedBy(0.5) // 宽度占一半
        }
        
        rightTurnView.snp.makeConstraints { make in
            make.top.bottom.right.equalToSuperview()
            make.width.equalToSuperview().multipliedBy(0.5) // 宽度占一半
        }
        
        highBeamView.snp.makeConstraints { make in
            make.top.left.right.equalToSuperview()
            make.height.equalToSuperview().multipliedBy(0.5) // 高度占一半
        }
        
        lowBeamView.snp.makeConstraints { make in
            make.bottom.left.right.equalToSuperview()
            make.height.equalToSuperview().multipliedBy(0.5) // 高度占一半
        }
    }
    
    // MARK: - 数据监听
    private func setupObservers() {
        // 监听蓝牙数据解析后发出的广播
        NotificationCenter.default.addObserver(self, selector: #selector(handleControlData(_:)), name: MotorcycleCONTROL, object: nil)
    }
    
    @objc private func handleControlData(_ notification: Notification) {
        guard let control = notification.object as? PTDashboardControl else { return }
        
        // 切换常亮组状态
        setSolidState(view: highBeamView, isOn: control.isHighBeamOn)
        setSolidState(view: lowBeamView, isOn: control.isLowBeamOn)
        
        // 切换闪烁组状态
        setBlinkingState(view: leftTurnView, isBlinking: control.isLeftTurnOn)
        setBlinkingState(view: rightTurnView, isBlinking: control.isRightTurnOn)
    }
    
    // MARK: - 动画控制引擎
    
    /// 设置常亮状态 (针对远光、近光)
    private func setSolidState(view: UIView, isOn: Bool) {
        if isOn {
            view.isHidden = false
            view.alpha = activeAlpha
        } else {
            view.isHidden = true
            view.alpha = 0
        }
    }
    
    /// 设置一秒闪烁动画 (针对转向灯)
    private func setBlinkingState(view: UIView, isBlinking: Bool) {
        if isBlinking {
            // 如果已经在执行闪烁动画，就不重复添加
            guard view.layer.animation(forKey: "blinkAnimation") == nil else { return }
            
            view.isHidden = false
            view.alpha = 0 // 初始状态为透明
            
            // 0.5s 淡入 + 0.5s 淡出 (反转) = 完美的 1 秒周期
            UIView.animate(withDuration: 0.5,
                           delay: 0,
                           options: [.repeat, .autoreverse, .allowUserInteraction, .curveEaseInOut],
                           animations: {
                view.alpha = self.activeAlpha
            }, completion: nil)
            
            // 给动画打个标签，防止重复添加
            view.layer.add(CAAnimation(), forKey: "blinkAnimation")
            
        } else {
            // 关闭转向灯时，移除所有动画并隐藏
            view.layer.removeAllAnimations()
            view.layer.removeAnimation(forKey: "blinkAnimation")
            view.isHidden = true
            view.alpha = 0
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
