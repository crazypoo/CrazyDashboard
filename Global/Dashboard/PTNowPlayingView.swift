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

@objcMembers
public class PTMarqueeLabel: UIView {

    private let label = UILabel()

    // 🌟 核心修复 1：状态锁缓存，避免重复渲染
    private var lastText: String?
    private var lastWidth: CGFloat = 0

    public var text: String? {
        didSet {
            // 只有当文本真正发生改变时，才重置动画
            guard text != lastText else { return }
            lastText = text
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
        self.clipsToBounds = true
        addSubview(label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        // 🌟 核心修复 2：只有当 AutoLayout 计算出的真实宽度发生变化时，才触发动画
        if self.bounds.width != lastWidth {
            lastWidth = self.bounds.width
            triggerMarquee()
        }
    }

    private func triggerMarquee() {
        label.layer.removeAllAnimations()
        label.transform = .identity

        label.sizeToFit()
        let textWidth = label.bounds.width
        let viewWidth = self.bounds.width

        guard viewWidth > 0, let text = text, !text.isEmpty else { return }

        if textWidth > viewWidth {
            label.frame = CGRect(x: 0, y: 0, width: textWidth, height: self.bounds.height)
            label.textAlignment = .left

            let overstep = textWidth - viewWidth + 20
            let duration = TimeInterval(overstep) / 25.0

            UIView.animate(withDuration: duration,
                           delay: 1.5,
                           options: [.autoreverse, .repeat, .curveEaseInOut],
                           animations: {
                self.label.transform = CGAffineTransform(translationX: -overstep, y: 0)
            }, completion: nil)

        } else {
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
        view.setTitleFont(.appfont(size: 14,bold:true), state: .normal)
        view.setImage(UIImage(.bolt.circle).withTintColor(.white, renderingMode: .alwaysOriginal), state: .normal)
        view.isUserInteractionEnabled = false
        return view
    }()
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        setupNotifications()
        setupGestures() // 🌟 新增：初始化手势控制
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
    
    private func setupGestures() {
        // 🚨 必须开启用户交互，否则手势无效
        self.isUserInteractionEnabled = true
        artworkImageView.isUserInteractionEnabled = true
        
        // 1. 单击封面：播放/暂停
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handlePlayPauseTap))
        artworkImageView.addGestureRecognizer(tapGesture)
        
        // 2. 左滑：下一首 (Next Track)
        let swipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeLeft))
        swipeLeft.direction = .left
        self.addGestureRecognizer(swipeLeft)
        
        // 3. 右滑：上一首 (Previous Track)
        let swipeRight = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeRight))
        swipeRight.direction = .right
        self.addGestureRecognizer(swipeRight)
    }
    
    // MARK: - 音乐控制逻辑
    @objc private func handlePlayPauseTap() {
        if musicPlayer.playbackState == .playing {
            musicPlayer.pause()
        } else {
            // 系统播放器如果没有队列可能会播放失败，保险起见调用 play
            musicPlayer.play()
        }
        provideVisualFeedback()
    }
    
    @objc private func handleSwipeLeft() {
        musicPlayer.skipToNextItem()
        provideVisualFeedback()
    }
    
    @objc private func handleSwipeRight() {
        // 如果当前歌曲播放超过 3 秒，调用上一首通常是回到本首开头；
        // 如果想强制回上一首，可以调用两次，但这里我们使用系统默认行为
        musicPlayer.skipToPreviousItem()
        provideVisualFeedback()
    }
    
    private func provideVisualFeedback() {
        // 让封面瞬间变暗再恢复，模拟实体按键被按下的顿挫感
        UIView.animate(withDuration: 0.1, delay: 0, options: .curveEaseOut, animations: {
            self.artworkImageView.alpha = 0.4
            self.artworkImageView.transform = CGAffineTransform(scaleX: 0.95, y: 0.95) // 极其轻微的缩放
        }) { _ in
            UIView.animate(withDuration: 0.15, delay: 0, options: .curveEaseIn, animations: {
                self.artworkImageView.alpha = 1.0
                self.artworkImageView.transform = .identity
            }, completion: nil)
        }
    }

    // MARK: - 生命周期绘图 (当视图大小确定时绘制圆弧)
    public override func layoutSubviews() {
        super.layoutSubviews()
        let center = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
        let radius = bounds.width / 2 - 4
        let startAngle = CGFloat.pi * 3 / 4
        let endAngle = -CGFloat.pi * 3 / 4
        let path = UIBezierPath(arcCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        trackLayer.path = path.cgPath
        progressLayer.path = path.cgPath
    }

    private func setupUI() {
        self.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        
        trackLayer.fillColor = UIColor.clear.cgColor
        trackLayer.strokeColor = UIColor.darkGray.withAlphaComponent(0.5).cgColor
        trackLayer.lineWidth = 10
        trackLayer.lineCap = .round
        layer.addSublayer(trackLayer)

        progressLayer.fillColor = UIColor.clear.cgColor
        progressLayer.strokeColor = PTDashboardConfig.shared.appMainColor.cgColor
        progressLayer.lineWidth = 10
        progressLayer.lineCap = .round
        progressLayer.strokeEnd = 0
        layer.addSublayer(progressLayer)

        artworkImageView.layer.cornerRadius = 10
        artworkImageView.clipsToBounds = true
        artworkImageView.contentMode = .scaleAspectFill
        artworkImageView.backgroundColor = .darkGray

        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.font = .appfont(size: 18, bold: true)
        titleLabel.text = PTDashboardConfig.languageFunc(text: "music_not_play")

        artistLabel.textColor = .lightGray
        artistLabel.textAlignment = .center
        artistLabel.font = .appfont(size: 14)
        artistLabel.text = "--"

        timeLabel.textColor = .lightGray
        timeLabel.textAlignment = .center
        timeLabel.font = .appfont(size: 12, bold: true) // 稍微加粗，与电池字体形成呼应
        timeLabel.text = "-00:00"

        addSubviews([artworkImageView, titleLabel, artistLabel, timeLabel, batteryLevel])

        // 🌟 核心排版优化：完美的中心十字布局

        // 1. 专辑封面：绝对居中，占据 40% 的宽度，让四周有充裕的呼吸感
        artworkImageView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.height.equalToSuperview().multipliedBy(0.40)
        }

        // 2. 歌名：紧贴封面顶部，左右预留防裁切边距
        titleLabel.snp.makeConstraints { make in
            make.bottom.equalTo(artworkImageView.snp.top).offset(-10)
            make.left.right.equalToSuperview().inset(30)
            make.height.equalTo(24)
        }

        // 3. 歌手：紧贴封面底部，与歌名保持绝对对称
        artistLabel.snp.makeConstraints { make in
            make.top.equalTo(artworkImageView.snp.bottom).offset(10)
            make.left.right.equalToSuperview().inset(30)
            make.height.equalTo(18)
        }

        // 4. 电量与时间：分居封面左右两侧，垂直居中
        batteryLevel.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.right.equalTo(artworkImageView.snp.left).offset(-4)
            make.width.equalTo(44)
            make.height.equalTo(44)
        }

        timeLabel.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.left.equalTo(artworkImageView.snp.right).offset(4)
            make.right.equalToSuperview().inset(12)
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
                self.titleLabel.text = item.title ?? PTDashboardConfig.languageFunc(text: "music_unknow_music")
                self.artistLabel.text = item.artist ?? PTDashboardConfig.languageFunc(text: "music_unknow_artist")
                // 提取专辑封面图片
                self.fetchArtwork(for: item)
                self.updateProgress()
            } else {
                self.titleLabel.text = PTDashboardConfig.languageFunc(text: "music_not_play")
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
