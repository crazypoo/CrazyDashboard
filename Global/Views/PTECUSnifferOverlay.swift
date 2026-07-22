//
//  PTECUSnifferOverlay.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 23/7/2026.
//

import UIKit
import Foundation
import PooTools

/// ECU 原始数据嗅探器视图 (开发者模式专属)
@MainActor
public class PTECUSnifferOverlay: UIView {
    
    // MARK: - UI 组件
    private let backgroundView = UIView()
    private let titleLabel = UILabel()
    private let logTextView = UITextView()
    private let closeButton = UIButton(type: .system)
    
    private let filterButton = UIButton(type: .system)
    private var isFilterEnabled: Bool = false
    // 缓存池，避免高频刷新导致内存溢出
    private var rawLogs: [String] = []
    private let maxLogCount = 100
    
    // MARK: - 初始化
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        setupObservers()
    }
    
    required init?(coder: CodingKey) {
        fatalError("init(coder:) has not been implemented")
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - 布局与样式设计
    private func setupUI() {
        // 🚨 核心原则：初始化时所有容器必须处于完全隐藏状态，绝不干扰主 UI
        self.isHidden = true
        self.alpha = 0.0
        
        // 配置半透明背景，呈现极客控制台风格
        backgroundView.backgroundColor = UIColor.black.withAlphaComponent(0.85)
        backgroundView.layer.cornerRadius = 12
        backgroundView.layer.borderWidth = 1
        backgroundView.layer.borderColor = UIColor.systemGreen.withAlphaComponent(0.5).cgColor
        backgroundView.clipsToBounds = true
        self.addSubview(backgroundView)
        
        // 布局 (如果你项目中使用了 SnapKit，可替换为 snp.makeConstraints)
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: self.topAnchor, constant: 40),
            backgroundView.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 20),
            backgroundView.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -20),
            backgroundView.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -40)
        ])
        
        // 标题
        titleLabel.text = "⚡️ ECU RAW DATA SNIFFER (DEV MODE)"
        titleLabel.textColor = .systemGreen
        titleLabel.font = .boldSystemFont(ofSize: 14)
        titleLabel.textAlignment = .center
        backgroundView.addSubview(titleLabel)
        
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: 10),
            titleLabel.centerXAnchor.constraint(equalTo: backgroundView.centerXAnchor)
        ])
        
        // 文本输出框
        logTextView.backgroundColor = .clear
        logTextView.textColor = .systemGreen
        logTextView.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        logTextView.isEditable = false
        logTextView.layoutManager.allowsNonContiguousLayout = false // 优化大文本渲染性能
        backgroundView.addSubview(logTextView)
        
        logTextView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            logTextView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            logTextView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 10),
            logTextView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -10),
            logTextView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor, constant: -50)
        ])
        
        // 关闭按钮
        closeButton.setTitle("关闭开发者模式", for: .normal)
        closeButton.setTitleColor(.white, for: .normal)
        closeButton.backgroundColor = .systemRed.withAlphaComponent(0.8)
        closeButton.layer.cornerRadius = 8
        closeButton.addTarget(self, action: #selector(hideSniffer), for: .touchUpInside)
        backgroundView.addSubview(closeButton)
        
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            closeButton.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor, constant: -10),
            closeButton.centerXAnchor.constraint(equalTo: backgroundView.centerXAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 150),
            closeButton.heightAnchor.constraint(equalToConstant: 30)
        ])
        
        // 🚨 新增：降噪过滤按钮
        filterButton.setTitle("已显示全部 (点击过滤已知)", for: .normal)
        filterButton.setTitleColor(.white, for: .normal)
        filterButton.backgroundColor = .systemBlue.withAlphaComponent(0.8)
        filterButton.layer.cornerRadius = 8
        filterButton.addTarget(self, action: #selector(toggleFilter), for: .touchUpInside)
        backgroundView.addSubview(filterButton)
        
        filterButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            filterButton.bottomAnchor.constraint(equalTo: closeButton.topAnchor, constant: -10),
            filterButton.centerXAnchor.constraint(equalTo: backgroundView.centerXAnchor),
            filterButton.widthAnchor.constraint(equalToConstant: 220),
            filterButton.heightAnchor.constraint(equalToConstant: 30)
        ])
    }
    
    // MARK: - 数据监听
    private func setupObservers() {
        NotificationCenter.default.addObserver(forName: MotorcycleRawDataReceived, object: nil, queue: .main) { [weak self] notification in
            guard let self = self, !self.isHidden, let rawText = notification.object as? String else { return }
            
            // 🚨 核心逻辑：如果开启了过滤，且数据包含 "[已知]"，则直接丢弃不显示
            if self.isFilterEnabled && rawText.contains("[已知]") {
                return
            }
            
            self.appendLog(rawText)
        }
    }
    
    // MARK: - 交互与动画控制
    /// 追加日志并自动滚动到底部
    private func appendLog(_ text: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let newLog = "[\(timestamp)] RX: \(text)"
        
        rawLogs.append(newLog)
        if rawLogs.count > maxLogCount {
            rawLogs.removeFirst()
        }
        
        logTextView.text = rawLogs.joined(separator: "\n")
        
        // 滚动到最新一行
        let range = NSRange(location: logTextView.text.count - 1, length: 1)
        logTextView.scrollRangeToVisible(range)
    }
    
    /// 动画展示嗅探器
    public func showSniffer() {
        guard self.isHidden else { return }
        self.isHidden = false
        UIView.animate(withDuration: 0.3) {
            self.alpha = 1.0
        }
    }
    
    /// 动画隐藏嗅探器
    @objc public func hideSniffer() {
        UIView.animate(withDuration: 0.3, animations: {
            self.alpha = 0.0
        }) { _ in
            self.isHidden = true
            // 隐藏后清空日志以释放内存
            self.rawLogs.removeAll()
            self.logTextView.text = ""
        }
    }
    
    @objc private func toggleFilter() {
        isFilterEnabled.toggle()
        if isFilterEnabled {
            filterButton.setTitle("已开启降噪 (仅显示未知帧)", for: .normal)
            filterButton.backgroundColor = .systemOrange.withAlphaComponent(0.8)
            // 开启过滤时，清空当前屏幕的杂乱数据
            rawLogs.removeAll()
            logTextView.text = ""
        } else {
            filterButton.setTitle("已显示全部 (点击过滤已知)", for: .normal)
            filterButton.backgroundColor = .systemBlue.withAlphaComponent(0.8)
        }
    }
}
