//
//  PTIndicatorPanel.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 29/7/2026.
//

import UIKit
import SnapKit
import SafeSFSymbols
import SwifterSwift
import PooTools

@objcMembers
public class PTIndicatorPanel: PTDashboardBaseView {
    
    // MARK: - UI 组件 (指示灯图标)
    
    private let leftTurnIcon = UIImageView(image: UIImage(.arrow.left))
    private let lowBeamIcon = UIImageView(image: UIImage(.headlight.daytime))
    private let highBeamIcon = UIImageView(image: UIImage(.headlight.highBeamFill))
    private let tcsIcon = UIImageView(image: UIImage(.car._2Fill)) // 用车身带滑痕图标代替 TCS
    private let absIcon = UIImageView(image: UIImage(.abs.circleFill)) // ABS 专属图标
    private let kickstandIcon = UIImageView(image: UIImage(.exclamationmark.triangleFill)) // 边撑警告
    private let rightTurnIcon = UIImageView(image: UIImage(.arrow.right))
    private let tcsModeIcon = UIImageView(image: UIImage(.gauge.withDotsNeedle_0percent))
    private let backlightIcon = UIImageView(image: UIImage(.moon.fill))
    
    // 承载所有图标的横向容器
    private lazy var stackView: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [
            leftTurnIcon, lowBeamIcon, highBeamIcon, tcsIcon, tcsModeIcon, absIcon, kickstandIcon, backlightIcon, rightTurnIcon
        ])
        stack.axis = .horizontal
        stack.distribution = .fillEqually // 等距分布
        stack.alignment = .center
        stack.spacing = 2.adapter // 图标之间的间距
        return stack
    }()
    
    // MARK: - 初始化
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        resetAllIndicators() // 初始状态全部置灰关闭
        NotificationCenter.default.addObserver(self, selector: #selector(handleDataNotification), name: MotorcycleDATA2, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleDataNotification), name: MotorcycleCONTROL, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleDataNotification), name: MotorcycleABS, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleDataNotification), name: MotorcycleRawDataTCSShow, object: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - 布局设置
    private func setupUI() {
        self.backgroundColor = .clear // 背景透明
        
        // 统一设置图标的大小和渲染模式
        for icon in stackView.arrangedSubviews {
            guard let imageView = icon as? UIImageView else { continue }
            imageView.contentMode = .scaleAspectFit
            imageView.snp.makeConstraints { make in
                make.height.equalTo(imageView.snp.width)
            }
            
            // 🚨 光晕核心设置：允许阴影溢出边界
            imageView.layer.masksToBounds = false
        }
        
        addSubview(stackView)
        stackView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }
    
    // MARK: - 光晕开关核心引擎
    private func toggleGlow(for imageView: UIImageView, isOn: Bool, activeColor: UIColor) {
        if isOn {
            imageView.tintColor = activeColor
            
            // 开启光晕
            imageView.layer.shadowColor = activeColor.cgColor
            imageView.layer.shadowRadius = 8.0                // 光晕扩散的半径
            imageView.layer.shadowOpacity = 0.9               // 光晕的亮度
            imageView.layer.shadowOffset = .zero              // 保证四周均匀发光
        } else {
            imageView.tintColor = .darkGray // 熄灭时的暗灰色
            imageView.layer.shadowOpacity = 0.0 // 关闭光晕
        }
    }
    
    private func resetAllIndicators() {
        toggleGlow(for: leftTurnIcon, isOn: false, activeColor: .systemGreen)
        toggleGlow(for: rightTurnIcon, isOn: false, activeColor: .systemGreen)
        toggleGlow(for: lowBeamIcon, isOn: false, activeColor: .systemGreen)
        toggleGlow(for: highBeamIcon, isOn: false, activeColor: .systemBlue)
        toggleGlow(for: tcsIcon, isOn: false, activeColor: .systemOrange)
        toggleGlow(for: absIcon, isOn: false, activeColor: .systemYellow)
        toggleGlow(for: kickstandIcon, isOn: false, activeColor: .systemRed)
        
        // 默认让新增的模式图标处于灰色状态
        toggleGlow(for: tcsModeIcon, isOn: false, activeColor: .systemOrange)
        toggleGlow(for: backlightIcon, isOn: false, activeColor: .GoldColor)
    }
    
    // MARK: - 暴露给外部的更新接口    
    func updateControl(control: PTDashboardControl) {
        
        toggleGlow(for: leftTurnIcon, isOn: control.isLeftTurnOn, activeColor: .systemGreen)
        toggleGlow(for: rightTurnIcon, isOn: control.isRightTurnOn, activeColor: .systemGreen)
        toggleGlow(for: lowBeamIcon, isOn: control.isLowBeamOn, activeColor: .systemGreen)
        toggleGlow(for: highBeamIcon, isOn: control.isHighBeamOn, activeColor: .systemBlue)
        toggleGlow(for: tcsIcon, isOn: control.isTcsSystemReady, activeColor: .systemOrange)
        
        toggleGlow(for: tcsModeIcon, isOn: true, activeColor: .systemOrange)
        
        switch control.tcsMode {
        case .mode1:
            tcsModeIcon.image = UIImage(.gauge.withDotsNeedle_50percent)
        case .mode2:
            tcsModeIcon.image = UIImage(.gauge.withDotsNeedle_100percent)
        case .off:
            tcsModeIcon.image = UIImage(.gauge.withDotsNeedle_0percent)
        case .unknown:
            tcsModeIcon.image = UIImage(.gauge.withDotsNeedle_0percent)
        }
    }
    
    func updateData2(data2: PTDashboardData2) {
        
        toggleGlow(for: kickstandIcon, isOn: data2.isKickstandDown, activeColor: .systemRed)
        
         switch data2.backlightMode {
         case .led2:
             backlightIcon.image = UIImage(.sun.maxFill)
         case .led1:
             backlightIcon.image = UIImage(.sun.minFill)
         case .led0:
             backlightIcon.image = UIImage(.moon.fill)
         case .auto:
             backlightIcon.image = UIImage(.circle.lefthalfFilled)
         case .unknown:
             backlightIcon.image = UIImage(.moon.fill)
         }
         
        // 开启常亮光晕指示
        toggleGlow(for: backlightIcon, isOn: true, activeColor: .GoldColor)
    }
    
    func updateABS(abs: PTAbsStatus) {
        toggleGlow(for: absIcon, isOn: abs.isAbsLightOn, activeColor: .systemOrange)
    }
    
    func updateTCS(tcsShow: String) {
        toggleGlow(for: tcsIcon, isOn: tcsShow.bool ?? false, activeColor: .systemOrange)
    }
    
    @objc func handleDataNotification(_ notification: Notification) {
        if let data2 = notification.object as? PTDashboardData2 {
            DispatchQueue.main.async {
                self.updateData2(data2: data2)
            }
        }  else if let control = notification.object as? PTDashboardControl {
            // 3. 结合我们之前写的状态标签工具，更新到主线程的 UI 上
            DispatchQueue.main.async {
                self.updateTCS(tcsShow: control.isTcsSystemReady.string)
                self.updateControl(control: control)
            }
        } else if let abs = notification.object as? PTAbsStatus {
            DispatchQueue.main.async {
                self.updateABS(abs: abs)
            }
        } else if let tcsShow = notification.object as? String {
            updateTCS(tcsShow: tcsShow)
        }
    }

}
