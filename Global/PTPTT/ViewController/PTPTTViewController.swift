//
//  PTPTTViewController.swift
//  PTSpeed
//
//  Created by 邓杰豪 on 30/7/2026.
//

import UIKit
import PooTools
import SwifterSwift
import SnapKit

class PTPTTViewController: PTMotoBaseViewController {

    private var connectFriend:Int = 0
    // MARK: - UI 组件
    private let statusLabel = UILabel()
    private let peersCountLabel = UILabel()
    private let pttButton = UIButton(type: .custom) // 巨大的 PTT 对讲按钮
    
    // 震动反馈引擎，提升按键真实感
    private let hapticGenerator = UIImpactFeedbackGenerator(style: .heavy)
    
    lazy var appLogo:UIImageView = {
        let view = UIImageView()
        view.image = UIImage(named: "app_inside_logo")
        view.bounds = .init(origin: .zero, size: .init(width: 108.adapter, height: PTAppBaseConfig.share.navBarButtonSize))
        view.contentMode = .scaleAspectFit
        view.clipsToBounds = false
        return view
    }()
                                    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setLeftButtons(views: [appLogo])
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        
        // 设置代理，接收底层状态回调
        PTLocalIntercomManager.shared.delegate = self
    }
    
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // 界面出现时，自动开启局域网搜索
        PTLocalIntercomManager.shared.startOfflineIntercom()
    }
    
    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // 界面消失时关闭，省电
        PTLocalIntercomManager.shared.stopOfflineIntercom()
    }
    
    // MARK: - UI 布局设置 (SnapKit)
    private func setupUI() {
        view.backgroundColor = .black // 极客暗黑风
        
        // 1. 状态文本
        statusLabel.text = PTDashboardConfig.languageFunc(text: "ptt_ready_connect")
        statusLabel.textColor = .white
        statusLabel.font = .appfont(size: 20,bold:true)
        statusLabel.textAlignment = .center
        view.addSubview(statusLabel)
        
        statusLabel.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(60)
            make.centerX.equalToSuperview()
        }
        
        // 2. 附近车友数量
        peersCountLabel.text = PTDashboardConfig.language(key: "ptt_ready_connect_count", self.connectFriend)
        peersCountLabel.textColor = .systemGreen
        peersCountLabel.font = .appfont(size: 14,bold: true)
        view.addSubview(peersCountLabel)
        
        peersCountLabel.snp.makeConstraints { make in
            make.top.equalTo(statusLabel.snp.bottom).offset(10)
            make.centerX.equalToSuperview()
        }
        
        // 3. 巨大的 PTT 按键
        pttButton.backgroundColor = .systemOrange
        pttButton.setTitle(PTDashboardConfig.languageFunc(text: "ptt_push"), for: .normal)
        pttButton.titleLabel?.font = .appfont(size: 28,bold: true)
        pttButton.setTitleColor(.white, for: .normal)
        pttButton.layer.cornerRadius = 75 // 变圆
        
        // 🚨 核心交互：绑定按下和松开的事件
        pttButton.addTarget(self, action: #selector(pttButtonTouchDown), for: .touchDown)
        pttButton.addTarget(self, action: #selector(pttButtonTouchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        
        view.addSubview(pttButton)
        pttButton.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.height.equalTo(150) // 150x150 的巨型圆钮
        }
        
        pt_observerLanguage {
            if self.vcDidLoad {
                self.statusLabel.text = PTDashboardConfig.languageFunc(text: "ptt_ready_connect")
                self.peersCountLabel.text = PTDashboardConfig.language(key: "ptt_ready_connect_count", self.connectFriend)
                self.pttButton.setTitle(PTDashboardConfig.languageFunc(text: "ptt_push"), for: .normal)
            }
        }
        vcDidLoad = true
    }
    
    // MARK: - 按键交互逻辑
    @objc private func pttButtonTouchDown() {
        hapticGenerator.impactOccurred() // 物理震动反馈
        
        // 视觉缩小动画，模拟真实按压
        UIView.animate(withDuration: 0.1) {
            self.pttButton.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
            self.pttButton.backgroundColor = .systemRed // 说话时变红
            self.pttButton.setTitle(PTDashboardConfig.languageFunc(text: "ptt_release"), for: .normal)
        }
        
        // 触发底层引擎说话
        PTLocalIntercomManager.shared.startTalking()
    }
    
    @objc private func pttButtonTouchUp() {
        // 视觉恢复动画
        UIView.animate(withDuration: 0.2, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.5, options: .curveEaseInOut) {
            self.pttButton.transform = .identity
            self.pttButton.backgroundColor = .systemOrange
            self.pttButton.setTitle(PTDashboardConfig.languageFunc(text: "ptt_push"), for: .normal)
        }
        
        // 触发底层引擎停止
        PTLocalIntercomManager.shared.stopTalking()
    }
}

extension PTPTTViewController: PTLocalIntercomDelegate {
    
    public func intercomManager(_ manager: PTLocalIntercomManager, didChangeStatus status: String) {
        // 确保在主线程更新 UI
        DispatchQueue.main.async {
            self.statusLabel.text = status
        }
    }
    
    public func intercomManager(_ manager: PTLocalIntercomManager, didUpdatePeers count: Int) {
        DispatchQueue.main.async {
            self.connectFriend = count
            self.peersCountLabel.text = PTDashboardConfig.language(key: "ptt_ready_connect_count", count)
            self.peersCountLabel.textColor = count > 0 ? .systemGreen : .gray
        }
    }
}
