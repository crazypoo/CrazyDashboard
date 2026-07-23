//
//  PTECUSnifferOverlay.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 23/7/2026.
//

import UIKit
import Foundation
import PooTools
import SnapKit
import SwifterSwift

/// ECU 原始数据嗅探器视图 (开发者模式专属)
@MainActor
public class PTECUSnifferOverlay: UIView {
    
    // MARK: - UI 组件
    private lazy var backgroundView:UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.85)
        view.layer.cornerRadius = 12
        view.layer.borderWidth = 1
        view.layer.borderColor = UIColor.systemGreen.withAlphaComponent(0.5).cgColor
        view.clipsToBounds = true
        return view
    }()
    private lazy var titleLabel:UILabel = {
        let view = UILabel()
        view.text = "⚡️ ECU RAW DATA SNIFFER (DEV MODE)"
        view.textColor = .systemGreen
        view.font = .appfont(size: 14,bold: true)
        view.textAlignment = .center
        return view
    }()
    private lazy var logTextView:UITextView = {
        let view = UITextView()
        view.backgroundColor = .clear
        view.textColor = .systemGreen
        view.font = .appfont(size: 11)
        view.isEditable = false
        view.layoutManager.allowsNonContiguousLayout = false // 优化大文本渲染性能
        return view
    }()
    private lazy var closeButton:UIButton = {
        let view = UIButton(type: .system)
        view.setTitle("关闭开发者模式", for: .normal)
        view.setTitleColor(.white, for: .normal)
        view.backgroundColor = .systemRed.withAlphaComponent(0.8)
        view.layer.cornerRadius = 8
        view.addTarget(self, action: #selector(hideSniffer), for: .touchUpInside)
        return view
    }()
    
    private lazy var filterButton:UIButton = {
        let view = UIButton(type: .system)
        view.setTitle("已显示全部 (点击过滤已知)", for: .normal)
        view.setTitleColor(.white, for: .normal)
        view.backgroundColor = .systemBlue.withAlphaComponent(0.8)
        view.layer.cornerRadius = 8
        view.addTarget(self, action: #selector(toggleFilter), for: .touchUpInside)
        return view
    }()
    
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
        self.addSubview(backgroundView)
        backgroundView.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(PTAppBaseConfig.share.defaultViewSpace)
            make.top.equalToSuperview().inset(CGFloat.kNavBarHeight_Total + CGFloat.GlobalItemSpacing)
            make.bottom.equalToSuperview().inset(CGFloat.kTabbarHeight_Total + CGFloat.GlobalItemSpacing)
        }
        
        // 标题
        backgroundView.addSubviews([titleLabel,closeButton,filterButton,logTextView])
        titleLabel.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalToSuperview().inset(CGFloat.GlobalItemSpacing)
        }
        
        closeButton.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(PTAppBaseConfig.share.defaultViewSpace)
            make.height.equalTo(30)
            make.bottom.equalToSuperview().inset(CGFloat.GlobalItemSpacing)
        }
        
        filterButton.snp.makeConstraints { make in
            make.left.right.height.equalTo(self.closeButton)
            make.bottom.equalTo(self.closeButton.snp.top).offset(-CGFloat.GlobalItemSpacing)
        }
        
        logTextView.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(CGFloat.GlobalItemSpacing)
            make.top.equalTo(self.titleLabel.snp.bottom).offset(CGFloat.GlobalItemSpacing)
            make.bottom.equalTo(self.filterButton.snp.top).offset(-CGFloat.GlobalItemSpacing)
        }
    }
    
    // MARK: - 数据监听
    private func setupObservers() {
        NotificationCenter.default.addObserver(forName: MotorcycleRawDataReceived, object: nil, queue: .main) { [weak self] notification in
            guard let self = self, !self.isHidden, let rawText = notification.object as? String else { return }
            PTGCDManager.shared.runOnMain {
                // 🚨 核心逻辑：如果开启了过滤，且数据包含 "[已知]"，则直接丢弃不显示
                if self.isFilterEnabled && rawText.contains("[已知]") {
                    return
                }
                
                self.appendLog(rawText)
            }
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
