//
//  PTTripStatsView.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 8/6/2026.
//

import UIKit
import SnapKit
import PooTools
import SwifterSwift
import SafeSFSymbols

@objcMembers
public class PTTripStatsView: UIView {
    
    // 使用 StackView 让文字横向整齐排列
    private let stackView = UIStackView()
    private let bottomStackView = UIStackView()

    // 各项数据的展示 Label
    private let timeLabel = UILabel()       // 当前时间
    private lazy var runTimeLabel = {
        let view = baseLabel(image: UIImage(.stopwatch.fill).withTintColor(.white, renderingMode: .alwaysOriginal))
        return view
    }()  // 运行时长
    private lazy var distanceLabel = {
        let view = baseLabel(image: UIImage(.road.lanes).withTintColor(.white, renderingMode: .alwaysOriginal))
        return view
    }()   // 总距离
    private lazy var avgSpeedLabel = {
        let view = baseLabel(image: UIImage(.brakesignal.dashed).withTintColor(.white, renderingMode: .alwaysOriginal))
        return view
    }()   // 平均速度
    private lazy var maxSpeedLabel = {
        let view = baseLabel(image: UIImage(.exclamationmark.brakesignal).withTintColor(.white, renderingMode: .alwaysOriginal))
        return view
    }()   // 最高速度
    private lazy var minSpeedLabel = {
        let view = baseLabel(image: UIImage(.brakesignal).withTintColor(.white, renderingMode: .alwaysOriginal))
        return view
    }()   // 最低速度
    
    private lazy var idleLabel = {
        let view = baseLabel(image: UIImage(.parkingsign.circle).withTintColor(.white, renderingMode: .alwaysOriginal))
        return view
    }()   // 怠速时间
    private lazy var bestLabel = {
        let view = baseLabel(image: UIImage(.hand.thumbsup).withTintColor(.white, renderingMode: .alwaysOriginal))
        return view
    }()   // 0_100时间
    
    private var clockTimer: Timer?
    private let dateFormatter = DateFormatter()
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        startClockTimer()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        clockTimer?.invalidate()
    }
    
    private func setupUI() {
        stackView.axis = .horizontal
        stackView.distribution = .equalSpacing // 自动等距散开
        stackView.alignment = .center
        
        bottomStackView.axis = .horizontal
        bottomStackView.distribution = .equalSpacing // 自动等距散开
        bottomStackView.alignment = .center
        
        addSubviews([timeLabel,stackView,bottomStackView])
        timeLabel.textAlignment = .center
        timeLabel.textColor = .white
        timeLabel.snp.makeConstraints { make in
            make.top.left.right.equalToSuperview()
            make.height.equalTo(24)
        }
        
        stackView.snp.makeConstraints { make in
            make.top.equalTo(self.timeLabel.snp.bottom)
            make.left.right.equalToSuperview().inset(15)
            make.height.equalTo(24)
        }
        
        bottomStackView.snp.makeConstraints { make in
            make.top.equalTo(self.stackView.snp.bottom)
            make.width.equalTo(150)
            make.centerX.equalToSuperview()
            make.height.equalTo(24)
        }
        
        // 配置所有 Label 基础样式并添加到 StackView
        let labels = [runTimeLabel, distanceLabel, avgSpeedLabel, maxSpeedLabel, minSpeedLabel]
        for label in labels {
            stackView.addArrangedSubview(label)
        }
        
        let labels_bottom = [idleLabel,bestLabel]
        for label in labels_bottom {
            bottomStackView.addArrangedSubview(label)
        }
        
        // 设置初始默认文本
        timeLabel.text = "--:--"
        runTimeLabel.setTitle("00:00:00", state: .normal)
        distanceLabel.setTitle("0.00 km", state: .normal)
        avgSpeedLabel.setTitle("0.00 km", state: .normal)
        maxSpeedLabel.setTitle("0.00 km", state: .normal)
        minSpeedLabel.setTitle("0.00 km", state: .normal)
        
        idleLabel.setTitle("00:00:00", state: .normal)
        bestLabel.setTitle("0s", state: .normal)

        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm" // 设置当前时间的格式
    }
    
    // MARK: - 独立时钟更新
    private func startClockTimer() {
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.timeLabel.text = self.dateFormatter.string(from: Date())
        }
        RunLoop.main.add(clockTimer!, forMode: .common)
        timeLabel.text = dateFormatter.string(from: Date()) // 立即触发一次
    }
    
    // MARK: - 外部数据灌入
    public func updateStats(with data: PTTripData) {
        // 1. 格式化运行时长 (时:分:秒)
        let totalSeconds = Int(data.runTime)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        runTimeLabel.setTitle(String(format: "%02d:%02d:%02d", hours, minutes, seconds), state: .normal)
        
        // 2. 格式化距离 (米转公里，保留两位小数)
        let distanceKm = data.totalDistance / 1000.0
        distanceLabel.setTitle(String(format: "%.2f km", distanceKm), state: .normal)

        // 3. 速度数据
        avgSpeedLabel.setTitle("\(Int(data.avgSpeed)) km/h", state: .normal)
        maxSpeedLabel.setTitle("\(Int(data.maxSpeed)) km/h", state: .normal)
        minSpeedLabel.setTitle("\(Int(data.minSpeed)) km/h", state: .normal)
        
        let totalSeconds_idle = Int(data.idleTime)
        let hours_idle = totalSeconds_idle / 3600
        let minutes_idle = (totalSeconds_idle % 3600) / 60
        let seconds_idle = totalSeconds_idle % 60
        idleLabel.setTitle(String(format: "%02d:%02d:%02d", hours_idle, minutes_idle, seconds_idle), state: .normal)

        bestLabel.setTitle("\(data.best0To100Time ?? 0)s", state: .normal)
    }
    
    private func baseLabel(image:UIImage) -> PTActionLayoutButton {
        let view = PTActionLayoutButton()
        view.layoutStyle = .leftImageRightTitle
        view.imageSize = .init(width: 16, height: 16)
        view.midSpacing = 5
        view.setTitleFont(UIFont.systemFont(ofSize: 13, weight: .medium), state: .normal)
        view.isUserInteractionEnabled = false
        view.setImage(image, state: .normal)
        view.setTitleColor(.white, state: .normal)
        view.progressLayerBorderColor = .clear
        return view
    }
}
