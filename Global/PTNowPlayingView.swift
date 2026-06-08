//
//  PTNowPlayingView.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 7/6/2026.
//

import UIKit
import MediaPlayer
import SnapKit 
import SwifterSwift
import PooTools
import SafeSFSymbols

import UIKit

@objcMembers
public class PTMarqueeLabel: UIView {

    private let label = UILabel()

    // 暴露核心的 Label 属性，方便外部设置
    public var text: String? {
        didSet {
            label.text = text
            triggerMarquee()
        }
    }

    public var textColor: UIColor = .white {
        didSet { label.textColor = textColor }
    }

    public var font: UIFont = UIFont.systemFont(ofSize: 14) {
        didSet { label.font = font }
    }

    public var textAlignment: NSTextAlignment = .center {
        didSet { label.textAlignment = textAlignment }
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        self.clipsToBounds = true // 核心：超出的文字直接裁切掉
        addSubview(label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // 当 Auto Layout 确定了父视图宽度后，重新计算是否需要滚动
    public override func layoutSubviews() {
        super.layoutSubviews()
        triggerMarquee()
    }

    private func triggerMarquee() {
        // 每次触发前，先重置之前的状态和动画
        label.layer.removeAllAnimations()
        label.transform = .identity

        // 让 label 自动计算出其实际所需的宽度
        label.sizeToFit()
        let textWidth = label.bounds.width
        let viewWidth = self.bounds.width

        guard viewWidth > 0, let text = text, !text.isEmpty else { return }

        if textWidth > viewWidth {
            // 🌟 文本超长，启动乒乓跑马灯
            // 设定 frame，高度撑满，宽度等于文字真实宽度
            label.frame = CGRect(x: 0, y: 0, width: textWidth, height: self.bounds.height)
            label.textAlignment = .left // 跑马灯时强制左对齐，视觉更合理

            let overstep = textWidth - viewWidth + 20 // 多留 20pt 的缓冲空间，不会贴得太死

            // 智能速度控制：每 25pt 滚动 1 秒，保证不论字数多少，滚动速度始终一致
            let duration = TimeInterval(overstep) / 25.0

            UIView.animate(withDuration: duration,
                           delay: 1.5, // 等待 1.5 秒让用户看清开头，再开始滚
                           options: [.autoreverse, .repeat, .curveEaseInOut], // 乒乓来回、无限重复、平滑加减速
                           animations: {
                // 向左移动超出的距离
                self.label.transform = CGAffineTransform(translationX: -overstep, y: 0)
            }, completion: nil)

        } else {
            // 🌟 文本够短，乖乖按原样对齐显示
            label.frame = self.bounds
            label.textAlignment = self.textAlignment
        }
    }
}

@objcMembers
public class PTNowPlayingView: UIView {
    
    private let artworkImageView = UIImageView()
    private let titleLabel = PTMarqueeLabel()
    private let artistLabel = PTMarqueeLabel()
    private let timeLabel = UILabel()
    // 获取系统的音乐播放器
    private let musicPlayer = MPMusicPlayerController.systemMusicPlayer
    
    private var progressTimer: Timer?
    
    private let trackLayer = CAShapeLayer()
    private let progressLayer = CAShapeLayer()

    private lazy var batteryLevel = {
        let view = PTActionLayoutButton()
        view.layoutStyle = .upImageDownTitle
        view.imageSize = .init(width: 24, height: 24)
        view.midSpacing = 0
        view.setTitleColor(.white, state: .normal)
        view.setTitleFont(UIFont.systemFont(ofSize: 14), state: .normal)
        view.setImage(UIImage(.bolt.circle).withTintColor(.white, renderingMode: .alwaysOriginal), state: .normal)
        view.isUserInteractionEnabled = false
        return view
    }()
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        setupNotifications()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        // 记得结束监听并移除通知
        musicPlayer.endGeneratingPlaybackNotifications()
        NotificationCenter.default.removeObserver(self)
        stopTimer()
    }
    
    // MARK: - 生命周期绘图 (当视图大小确定时绘制圆弧)
    public override func layoutSubviews() {
        super.layoutSubviews()
        
        let center = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
        let radius = bounds.width / 2 - 4
        
        // 1. 起点：7点半位置 (135度 -> 3π/4)
        let startAngle = CGFloat.pi * 3 / 4
        
        // 2. 终点：逆时针减去 270度后，停在 10点半位置 (-135度 -> -3π/4)
        let endAngle = -CGFloat.pi * 3 / 4
        
        // 3. 画出路径：clockwise 设为 false (逆时针)
        let path = UIBezierPath(arcCenter: center,
                                radius: radius,
                                startAngle: startAngle,
                                endAngle: endAngle,
                                clockwise: false) // 逆时针！
        
        trackLayer.path = path.cgPath
        progressLayer.path = path.cgPath
    }

    private func setupUI() {
        self.backgroundColor = UIColor.black.withAlphaComponent(0.6)
                
        trackLayer.fillColor = UIColor.clear.cgColor
        trackLayer.strokeColor = UIColor.darkGray.withAlphaComponent(0.5).cgColor
        trackLayer.lineWidth = 10
        trackLayer.lineCap = .round // 让线段的两端是圆角
        layer.addSublayer(trackLayer)
        
        // 2. 设置进度层 (红色的高亮线)
        progressLayer.fillColor = UIColor.clear.cgColor
        progressLayer.strokeColor = UIColor.systemRed.cgColor // 匹配你截图里的红色
        progressLayer.lineWidth = 10
        progressLayer.lineCap = .round
        progressLayer.strokeEnd = 0 // 初始进度为 0
        layer.addSublayer(progressLayer)

        // 1. 专辑封面
        artworkImageView.layer.cornerRadius = 10
        artworkImageView.clipsToBounds = true
        artworkImageView.contentMode = .scaleAspectFill
        artworkImageView.backgroundColor = .darkGray // 占位色
        
        // 2. 歌名
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.font = UIFont.boldSystemFont(ofSize: 18)
        titleLabel.text = "暂无播放"
        
        // 3. 歌手
        artistLabel.textColor = .lightGray
        artistLabel.textAlignment = .center
        artistLabel.font = UIFont.systemFont(ofSize: 14)
        artistLabel.text = "--"
        
        timeLabel.textColor = .lightGray
        timeLabel.textAlignment = .center
        timeLabel.font = UIFont.systemFont(ofSize: 12)
        timeLabel.text = "-00:00"

        addSubviews([artworkImageView,titleLabel,artistLabel,timeLabel,batteryLevel])

        // MARK: - SnapKit 布局
        
        artworkImageView.snp.makeConstraints { make in
            make.width.equalToSuperview().multipliedBy(0.5)
            make.centerY.centerX.equalToSuperview()
            make.height.equalTo(self.artworkImageView.snp.width)
        }
        
        titleLabel.snp.makeConstraints { make in
            // 顶部挨着封面的底部，往下偏移 15
            make.bottom.equalTo(artworkImageView.snp.top).offset(-8)
            // 左右留白 10，防止文字太长贴边
            make.left.right.equalToSuperview().inset(50)
            make.height.equalTo(24)
        }
        
        artistLabel.snp.makeConstraints { make in
            // 顶部挨着歌名的底部，往下偏移 5
            make.top.equalTo(artworkImageView.snp.bottom).offset(8)
            make.left.right.height.equalTo(self.titleLabel)
        }
        
        timeLabel.snp.makeConstraints { make in
            // 时间显示在进度条下方
            make.left.equalTo(self.artworkImageView.snp.right).offset(2)
            make.right.equalToSuperview().inset(5)
            make.centerY.equalTo(self.artworkImageView)
        }
        
        batteryLevel.snp.makeConstraints { make in
            make.left.equalToSuperview().inset(5)
            make.right.equalTo(self.artworkImageView.snp.left).offset(-2)
            make.height.equalTo(40)
            make.centerY.equalTo(self.artworkImageView)
        }
    }
    
    private func setupNotifications() {
        // 开启系统播放通知
        musicPlayer.beginGeneratingPlaybackNotifications()
        UIDevice.current.isBatteryMonitoringEnabled = true
        // 监听电量百分比变化 (通常是每掉 1% 触发一次)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(updateBatteryInfo),
                                               name: UIDevice.batteryLevelDidChangeNotification,
                                               object: nil)
        
        // 监听充电状态变化 (插拔充电线时触发)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(updateBatteryInfo),
                                               name: UIDevice.batteryStateDidChangeNotification,
                                               object: nil)
        // 监听切歌事件
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(updateNowPlayingInfo),
                                               name: .MPMusicPlayerControllerNowPlayingItemDidChange,
                                               object: musicPlayer)
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(playbackStateDidChange),
                                               name: .MPMusicPlayerControllerPlaybackStateDidChange,
                                               object: musicPlayer)
        // 首次初始化时手动拉取一次
        updateNowPlayingInfo()
        playbackStateDidChange()
        updateBatteryInfo() // 🌟 初始化时获取一次电池状态
    }
    
    @objc private func updateBatteryInfo() {
        // 为了避免 DeviceKit 的版本差异，直接用原生 UIDevice 获取更稳妥
        let state = UIDevice.current.batteryState
        let level = UIDevice.current.batteryLevel
        
        // level 是 0.0 到 1.0 的浮点数，转换为 0 到 100 的整数
        // 如果模拟器获取不到电量，level 会是 -1.0
        let percentage = level >= 0 ? Int(level * 100) : 0
        let levelText = level >= 0 ? "\(percentage)%" : "--%"
        
        batteryLevel.setTitle(levelText, state: .normal)
        
        // 根据状态智能切换图标和颜色
        switch state {
        case .charging, .full:
            // 正在充电或充满：显示实心闪电，系统绿色
            let chargingImage = UIImage(.bolt.circle).withTintColor(.systemGreen, renderingMode: .alwaysOriginal)
            batteryLevel.setImage(chargingImage, state: .normal)
            batteryLevel.setTitleColor(.systemGreen, state: .normal)
            
        case .unplugged:
            // 未插电：检查是否低电量 (< 20%)
            let isLowPower = percentage <= 20
            let color: UIColor = isLowPower ? .systemRed : .white
            
            // 未插电用空心图标，低电量时变红
            let unpluggedImage = UIImage(.bolt.circle).withTintColor(color, renderingMode: .alwaysOriginal)
            batteryLevel.setImage(unpluggedImage, state: .normal)
            batteryLevel.setTitleColor(color, state: .normal)
            
        case .unknown:
            // 模拟器或无法获取状态
            let unknownImage = UIImage(.bolt.circle).withTintColor(.lightGray, renderingMode: .alwaysOriginal)
            batteryLevel.setImage(unknownImage, state: .normal)
            batteryLevel.setTitleColor(.lightGray, state: .normal)
            
        @unknown default:
            break
        }
    }

    @objc private func updateNowPlayingInfo() {
        // 必须切回主线程更新 UI
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if let item = self.musicPlayer.nowPlayingItem {
                self.titleLabel.text = item.title ?? "未知歌曲"
                self.artistLabel.text = item.artist ?? "未知歌手"
                // 提取专辑封面图片
                self.fetchArtwork(for: item)
                self.updateProgress()
            } else {
                self.titleLabel.text = "暂无播放"
                self.artistLabel.text = "--"
                self.artworkImageView.image = nil
                self.progressLayer.strokeEnd = 0
                self.timeLabel.text = "-00:00" // 修改这里：归零状态
            }
        }
    }
    
    // MARK: - 增强版封面获取器
    private func fetchArtwork(for item: MPMediaItem) {
        // 每次切歌先给个默认色/占位图，防止上一首歌的封面残留
        self.artworkImageView.backgroundColor = .darkGray
        
        guard let artwork = item.artwork else {
            self.artworkImageView.image = nil
            return
        }
        
        // 1. 第一波尝试：拿 300x300，如果拿不到，尝试拿原始大小
        let targetSize = CGSize(width: 300, height: 300)
        if let image = artwork.image(at: targetSize) ?? artwork.image(at: artwork.bounds.size) {
            self.artworkImageView.image = image
        } else {
            // 2. 第二波尝试 (核心黑科技)：
            // 如果走到这里，说明是流媒体歌曲，系统抛出了通知但图片还在解码。
            // 我们给它 0.5 秒的缓冲时间再次拉取。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self else { return }
                
                // 确保在这 0.5 秒内用户没有再次切歌 (比对当前的播放对象)
                guard self.musicPlayer.nowPlayingItem == item else { return }
                
                if let delayedArtwork = self.musicPlayer.nowPlayingItem?.artwork,
                   let delayedImage = delayedArtwork.image(at: targetSize) ?? delayedArtwork.image(at: delayedArtwork.bounds.size) {
                    
                    // 加上一个平滑的渐现动画，让封面的出现不那么突兀
                    UIView.transition(with: self.artworkImageView,
                                      duration: 0.3,
                                      options: .transitionCrossDissolve,
                                      animations: {
                                          self.artworkImageView.image = delayedImage
                                      }, completion: nil)
                } else {
                    self.artworkImageView.image = nil
                }
            }
        }
    }

    @objc private func playbackStateDidChange() {
        // 根据当前的播放状态决定是否启动定时器
        if musicPlayer.playbackState == .playing {
            startTimer()
        } else {
            stopTimer()
        }
    }
    
    // MARK: - 进度条与时间计算核心逻辑
        
    private func startTimer() {
        stopTimer() // 防止重复创建
        // 每 0.5 秒刷新一次进度条，保证流畅度
        progressTimer = Timer.scheduledTimer(timeInterval: 0.5, target: self, selector: #selector(updateProgress), userInfo: nil, repeats: true)
        RunLoop.main.add(progressTimer!, forMode: .common)
    }
    
    private func stopTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
    
    @objc private func updateProgress() {
        guard let item = musicPlayer.nowPlayingItem else { return }
                
        let duration = item.playbackDuration
        let currentPlaybackTime = musicPlayer.currentPlaybackTime
        guard duration > 0 else { return }
        
        let progress = CGFloat(currentPlaybackTime / duration)
        let remainingTime = duration - currentPlaybackTime
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // 更新 CAShapeLayer 的进度，系统自带极其平滑的过渡动画！
            self.progressLayer.strokeEnd = progress
            self.timeLabel.text = "-\(self.formatTime(remainingTime))"
        }
    }
    
    // MARK: - 辅助方法：将秒数格式化为 分:秒
    private func formatTime(_ timeInSeconds: TimeInterval) -> String {
        // 防止出现负数或非数字的异常情况
        guard !timeInSeconds.isNaN && timeInSeconds >= 0 else { return "00:00" }
        
        let totalSeconds = Int(timeInSeconds)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        
        // 格式化为 00:00
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
