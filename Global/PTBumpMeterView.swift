//
//  PTBumpMeterView.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 8/6/2026.
//

import UIKit
import SnapKit
import SwifterSwift

@objcMembers
public class PTBumpMeterView: UIView {
    
    private let titleLabel = UILabel()
    private let valueLabel = UILabel()
    private let progressBar = UIProgressView(progressViewStyle: .default)
    
    // 设定 ADV 减震的极限 G 值 (一般 2.0G 已经是巨大的跳跃/坑洞了)
    private let maxBumpGForce: Double = 2.0
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        titleLabel.text = PTDashboardConfig.languageFunc(text: "shake_value")
        titleLabel.textColor = .lightGray
        titleLabel.font = UIFont.systemFont(ofSize: 12, weight: .bold)
        
        valueLabel.text = "0.00"
        valueLabel.textColor = .white
        valueLabel.font = UIFont.systemFont(ofSize: 12, weight: .bold)
        valueLabel.textAlignment = .right
        
        progressBar.trackTintColor = UIColor.darkGray.withAlphaComponent(0.5)
        progressBar.progressTintColor = .systemGreen
        // 让进度条圆润一点
        progressBar.layer.cornerRadius = 3
        progressBar.clipsToBounds = true
        
        addSubviews([titleLabel, progressBar, valueLabel])
        
        titleLabel.snp.makeConstraints { make in
            make.left.centerY.equalToSuperview()
            make.width.equalTo(45)
        }
        
        valueLabel.snp.makeConstraints { make in
            make.right.centerY.equalToSuperview()
            make.width.equalTo(35)
        }
        
        progressBar.snp.makeConstraints { make in
            make.left.equalTo(titleLabel.snp.right).offset(5)
            make.right.equalTo(valueLabel.snp.left).offset(-5)
            make.centerY.equalToSuperview()
            make.height.equalTo(8) // 稍微加粗一点
        }
    }
    
    // 接收 PTMotion 的 Z 轴 G 值
    public func updateBump(zForce: Double) {
        // Z轴可能会有正负（向上抛起或向下砸），颠簸感看绝对值
        let absForce = abs(zForce)
        valueLabel.text = String(format: "%.2f", absForce)
        
        let progress = Float(min(absForce / maxBumpGForce, 1.0))
        progressBar.setProgress(progress, animated: true)
        
        // 智能情绪变色引擎
        if absForce < 0.5 {
            progressBar.progressTintColor = .systemGreen // 铺装路面，轻微震动
        } else if absForce < 1.2 {
            progressBar.progressTintColor = .systemOrange // 非铺装路面，碎石林道
        } else {
            progressBar.progressTintColor = .systemRed // 炮弹坑、飞坡落地！
        }
    }
}
