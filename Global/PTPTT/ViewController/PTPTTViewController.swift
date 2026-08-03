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
import MultipeerConnectivity

class PTPeerAvatarView: UIView {
    let peerID: MCPeerID
    private let nameLabel = UILabel()
    
    lazy var signalLabel:PTActionLayoutButton = {
        let view = PTActionLayoutButton()
        view.progressLayerBorderColor = .clear
        view.midSpacing = 0
        view.layoutStyle = .leftImageRightTitle
        view.imageSize = .init(width: 18, height: 18)
        view.setTitleColor(.white, state: .normal)
        view.setTitleFont(.appfont(size: 13), state: .normal)
        view.isUserInteractionEnabled = false
        return view
    }()
    
    init(peerID: MCPeerID) {
        self.peerID = peerID
        super.init(frame: .zero)
        
        backgroundColor = UIColor.white.withAlphaComponent(0.1)
        layer.cornerRadius = 25 // 50x50 的圆形
        
        // 截取名字的前两个字当头像显示
        let displayName = peerID.displayName
        nameLabel.text = String(displayName.prefix(2)).uppercased()
        nameLabel.textColor = .white
        nameLabel.font = .appfont(size: 16, bold: true)
        nameLabel.textAlignment = .center
        
        addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        addSubviews([signalLabel])
        signalLabel.snp.makeConstraints { make in
            make.top.left.right.equalToSuperview()
            make.height.equalTo(self.signalLabel.imageSize.height)
        }
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    // 控制光晕特效的方法
    func setSpeakingGlow(_ isSpeaking: Bool) {
        if isSpeaking {
            // 说话时：亮起绿色荧光，卡片稍微放大
            UIView.animate(withDuration: 0.2) {
                self.layer.shadowColor = UIColor.systemGreen.cgColor
                self.layer.shadowRadius = 12
                self.layer.shadowOpacity = 1.0
                self.layer.shadowOffset = .zero
                self.layer.masksToBounds = false
                self.transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
                self.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.3)
            }
        } else {
            // 不说话时：恢复原状
            UIView.animate(withDuration: 0.3) {
                self.layer.shadowOpacity = 0.0
                self.transform = .identity
                self.backgroundColor = UIColor.white.withAlphaComponent(0.1)
            }
        }
    }
}

class PTPTTViewController: PTMotoBaseViewController {

    private let peersScrollView = UIScrollView()
    private let peersStackView = UIStackView()
    // 追踪当前渲染在屏幕上的头像
    private var peerViews: [MCPeerID: PTPeerAvatarView] = [:]

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
             
    private lazy var modeSwitchButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle(PTDashboardConfig.languageFunc(text: "ptt_change_hand_free"), for: .normal)
        btn.setTitleColor(.white, for: .normal)
        btn.titleLabel?.font = .appfont(size: 16)
        btn.backgroundColor = .darkGray
        btn.layer.cornerRadius = 8
        btn.addTarget(self, action: #selector(togglePTTMode), for: .touchUpInside)
        return btn
    }()
    
    private lazy var powerButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle(PTDashboardConfig.languageFunc(text: "ptt_in"), for: .normal)
        btn.setTitleColor(.white, for: .normal)
        btn.titleLabel?.font = .appfont(size: 16, bold: true)
        btn.backgroundColor = PTDashboardConfig.shared.appMainColor
        btn.layer.cornerRadius = 8
        btn.addTarget(self, action: #selector(togglePower), for: .touchUpInside)
        return btn
    }()

    let tapButtonSize:CGFloat = 150.adapter
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setLeftButtons(views: [appLogo])
        
        self.connectFriend = PTLocalIntercomManager.shared.connectedPeersCount
        self.peersCountLabel.text = PTDashboardConfig.language(key: "ptt_ready_connect_count", self.connectFriend)
        self.peersCountLabel.textColor = self.connectFriend > 0 ? .systemGreen : .gray
        self.statusLabel.text = PTLocalIntercomManager.shared.currentStatusText
        
        updateUIState()
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
        updateUIState()
    }
    
    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // 界面消失时关闭，省电
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
            make.top.equalToSuperview().inset(CGFloat.kNavBarHeight_Total + CGFloat.GlobalItemSpacing)
            make.left.right.equalToSuperview().inset(PTAppBaseConfig.share.defaultViewSpace)
            make.centerX.equalToSuperview()
        }
        
        // 2. 附近车友数量
        peersCountLabel.text = PTDashboardConfig.language(key: "ptt_ready_connect_count", self.connectFriend)
        peersCountLabel.textColor = .systemGreen
        peersCountLabel.textAlignment = .center
        peersCountLabel.font = .appfont(size: 14,bold: true)
        view.addSubview(peersCountLabel)
        
        peersCountLabel.snp.makeConstraints { make in
            make.top.equalTo(statusLabel.snp.bottom).offset(CGFloat.GlobalItemSpacing)
            make.left.right.equalTo(self.statusLabel)
        }
        
        peersScrollView.showsHorizontalScrollIndicator = false
        view.addSubview(peersScrollView)
        
        peersStackView.axis = .horizontal
        peersStackView.spacing = 20
        peersStackView.alignment = .center
        peersScrollView.addSubview(peersStackView)
        
        peersScrollView.snp.makeConstraints { make in
            make.top.equalTo(peersCountLabel.snp.bottom).offset(20)
            make.left.right.equalToSuperview().inset(PTAppBaseConfig.share.defaultViewSpace)
            make.height.equalTo(70) // 容纳发光动画的高度
        }
        
        peersStackView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.height.equalToSuperview()
        }

        // 3. 巨大的 PTT 按键
        pttButton.backgroundColor = .systemOrange
        pttButton.setTitle(PTDashboardConfig.languageFunc(text: "ptt_push"), for: .normal)
        pttButton.titleLabel?.font = .appfont(size: 28,bold: true)
        pttButton.setTitleColor(.white, for: .normal)
        pttButton.layer.cornerRadius = tapButtonSize / 2 // 变圆
        
        // 🚨 核心交互：绑定按下和松开的事件
        pttButton.addTarget(self, action: #selector(pttButtonTouchDown), for: .touchDown)
        pttButton.addTarget(self, action: #selector(pttButtonTouchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        
        view.addSubview(pttButton)
        pttButton.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(peersScrollView.snp.bottom).offset(CGFloat.GlobalItemSpacing * 3)
            make.width.height.equalTo(tapButtonSize)
        }
        
        view.addSubview(modeSwitchButton)
        modeSwitchButton.snp.makeConstraints { make in
            make.top.equalTo(pttButton.snp.bottom).offset(40)
            make.centerX.equalToSuperview()
            make.left.right.equalToSuperview().inset(PTAppBaseConfig.share.defaultViewSpace)
            make.height.equalTo(44)
        }

        view.addSubview(powerButton)
        powerButton.snp.makeConstraints { make in
            make.top.equalTo(modeSwitchButton.snp.bottom).offset(20)
            make.centerX.equalToSuperview()
            make.left.right.height.equalTo(self.modeSwitchButton)
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
    
    @objc private func togglePTTMode() {
        let isCurrentlyHandsFree = PTLocalIntercomManager.shared.isHandsFreeMode
        
        // 翻转状态
        let willBeHandsFree = !isCurrentlyHandsFree
        PTLocalIntercomManager.shared.toggleHandsFreeMode(isOn: willBeHandsFree)
        
        if willBeHandsFree {
            // 进入免提模式
            modeSwitchButton.setTitle(PTDashboardConfig.languageFunc(text: "ptt_change_ptt"), for: .normal)
            modeSwitchButton.backgroundColor = .systemGreen
            
            // 禁用大圆钮（因为已经免提了）
            pttButton.isEnabled = false
            pttButton.backgroundColor = .systemGray
            pttButton.setTitle(PTDashboardConfig.languageFunc(text: "ptt_hand_free_listening"), for: .normal)
        } else {
            // 恢复按键对讲模式
            modeSwitchButton.setTitle(PTDashboardConfig.languageFunc(text: "ptt_change_hand_free"), for: .normal)
            modeSwitchButton.backgroundColor = .darkGray
            
            pttButton.isEnabled = true
            pttButton.backgroundColor = .systemOrange
            pttButton.setTitle(PTDashboardConfig.languageFunc(text: "ptt_push"), for: .normal)
        }
    }
    
    @objc private func togglePower() {
        if PTLocalIntercomManager.shared.isRunning {
            // 主动关机
            PTLocalIntercomManager.shared.stopOfflineIntercom()
        } else {
            // 主动开机
            PTLocalIntercomManager.shared.startOfflineIntercom()
        }
        updateUIState()
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
    
    private func updateUIState() {
        let isRunning = PTLocalIntercomManager.shared.isRunning
        let isHandsFree = PTLocalIntercomManager.shared.isHandsFreeMode
        
        if isRunning {
            powerButton.setTitle(PTDashboardConfig.languageFunc(text: "ptt_out"), for: .normal)
            powerButton.backgroundColor = .systemRed
            modeSwitchButton.isHidden = false
            pttButton.isHidden = false
            
            // 恢复免提状态下的 UI
            if isHandsFree {
                modeSwitchButton.setTitle(PTDashboardConfig.languageFunc(text: "ptt_change_ptt"), for: .normal)
                modeSwitchButton.backgroundColor = .systemGreen
                pttButton.isEnabled = false
                pttButton.backgroundColor = .systemGray
                pttButton.setTitle(PTDashboardConfig.languageFunc(text: "ptt_hand_free_listening"), for: .normal)
            } else {
                modeSwitchButton.setTitle(PTDashboardConfig.languageFunc(text: "ptt_change_hand_free"), for: .normal)
                modeSwitchButton.backgroundColor = .darkGray
                pttButton.isEnabled = true
                pttButton.backgroundColor = .systemOrange
                pttButton.setTitle(PTDashboardConfig.languageFunc(text: "ptt_push"), for: .normal)
            }
        } else {
            // 引擎没开，禁用这些按钮
            powerButton.setTitle(PTDashboardConfig.languageFunc(text: "ptt_in"), for: .normal)
            powerButton.backgroundColor = PTDashboardConfig.shared.appMainColor
            modeSwitchButton.isHidden = true
            pttButton.isHidden = true
        }
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
    
    public func intercomManager(_ manager: PTLocalIntercomManager, didUpdatePeerList peers: [MCPeerID]) {
        DispatchQueue.main.async {
            // 清理旧的头像
            self.peersStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
            self.peerViews.removeAll()
            
            // 为每一个车友生成一个新的圆形头像
            for peer in peers {
                let avatar = PTPeerAvatarView(peerID: peer)
                avatar.snp.makeConstraints { make in
                    make.width.height.equalTo(50) // 头像基础大小
                }
                self.peersStackView.addArrangedSubview(avatar)
                self.peerViews[peer] = avatar
            }
        }
    }
    
    public func intercomManager(_ manager: PTLocalIntercomManager, speakingPeersChanged speakingPeers: [MCPeerID]) {
        DispatchQueue.main.async {
            let speakingSet = Set(speakingPeers)
            
            for (peer, avatarView) in self.peerViews {
                let isSpeaking = speakingSet.contains(peer)
                // 开/关发光动画
                avatarView.setSpeakingGlow(isSpeaking)
            }
        }
    }
    
    public func intercomManager(_ manager: PTLocalIntercomManager, localUserIsSpeaking: Bool) {
        DispatchQueue.main.async {
            if localUserIsSpeaking {
                // 🗣️ 正在说话：为 PTT 按钮添加向外发散的强烈光晕
                UIView.animate(withDuration: 0.2) {
                    // 使用鲜艳的颜色作为光晕（如果是按压状态本身是红色，用红色阴影会非常有冲击力）
                    self.pttButton.layer.shadowColor = UIColor.systemRed.cgColor
                    self.pttButton.layer.shadowRadius = 25    // 光晕扩散的范围
                    self.pttButton.layer.shadowOpacity = 1.0  // 光晕的亮度 (0.0 ~ 1.0)
                    self.pttButton.layer.shadowOffset = .zero // 居中发散，不偏移
                    self.pttButton.layer.masksToBounds = false // 🚨 核心：允许阴影渲染到按钮外部
                }
            } else {
                // 🔇 停止说话：平滑地收起光晕
                UIView.animate(withDuration: 0.3) {
                    self.pttButton.layer.shadowOpacity = 0.0
                }
            }
        }
    }
    
    public func intercomManager(_ manager: PTLocalIntercomManager, didUpdateNetworkStatusFor peer: MCPeerID, latency: Int, signal: PTNetworkSignalLevel) {
        // 假设你有一个字典存储了每个车友的卡片视图：peerViews[peer]
        guard let avatarView = peerViews[peer] else { return }
        avatarView.signalLabel.setTitle("\(latency)ms", state: .normal)
        // 2. 根据信号强弱改变图标的颜色
        switch signal {
        case .strong:
            avatarView.signalLabel.setTitleColor(.systemGreen, state: .normal)
            avatarView.signalLabel.setImage(UIImage(systemName: "wifi", withConfiguration: UIImage.SymbolConfiguration(weight: .bold)), state: .normal)
        case .normal:
            avatarView.signalLabel.setTitleColor(.systemYellow, state: .normal)
            avatarView.signalLabel.setImage(UIImage(systemName: "wifi", withConfiguration: UIImage.SymbolConfiguration(weight: .regular)), state: .normal)
        case .weak:
            avatarView.signalLabel.setTitleColor(.systemRed, state: .normal)
            avatarView.signalLabel.setImage(UIImage(systemName: "wifi.exclamationmark"), state: .normal)
        }
    }
}
