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
        view.layoutManager.allowsNonContiguousLayout = true
        view.isScrollEnabled = true
        view.showsVerticalScrollIndicator = false
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
    
    private lazy var exportButton: UIButton = {
        let view = UIButton(type: .system)
        view.setTitle("导出日志 (Export)", for: .normal)
        view.setTitleColor(.white, for: .normal)
        view.backgroundColor = .systemPurple.withAlphaComponent(0.8)
        view.layer.cornerRadius = 8
        view.addTarget(self, action: #selector(exportLogsAction), for: .touchUpInside)
        return view
    }()

    private lazy var findFunctionButton: UIButton = {
        let view = UIButton(type: .system)
        view.setTitle("Find commond", for: .normal)
        view.setTitleColor(.white, for: .normal)
        view.layer.cornerRadius = 8
        view.setBackgroundColor(color: .systemPurple.withAlphaComponent(0.8), forState: .normal)
        view.setBackgroundColor(color: .systemRed.withAlphaComponent(0.8), forState: .selected)
        view.addActionHandlers(handler: { sender in
            if sender.isSelected {
                PTBluetoothServerManager.shared.stopAutomatedFuzzing()
            } else {
                PTBluetoothServerManager.shared.startAutomatedFuzzing()
            }
            sender.isSelected.toggle()
        })
        return view
    }()

    private var isFilterEnabled: Bool = false
    // 缓存池，避免高频刷新导致内存溢出
    private var rawLogs: [String] = []
    private let maxLogCount = 100
    
    // 🚨 性能优化新增：数据缓冲池与渲染定时器
    private var pendingLogs: [String] = []
    private var uiRefreshTimer: Timer?

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
        backgroundView.addSubviews([titleLabel,closeButton,filterButton,exportButton,findFunctionButton,logTextView])
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
        
        exportButton.snp.makeConstraints { make in
            make.left.right.height.equalTo(self.closeButton)
            make.bottom.equalTo(self.filterButton.snp.top).offset(-CGFloat.GlobalItemSpacing)
        }
        
        findFunctionButton.snp.makeConstraints { make in
            make.left.right.height.equalTo(self.closeButton)
            make.bottom.equalTo(self.exportButton.snp.top).offset(-CGFloat.GlobalItemSpacing)
        }
        
        logTextView.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(CGFloat.GlobalItemSpacing)
            make.top.equalTo(self.titleLabel.snp.bottom).offset(CGFloat.GlobalItemSpacing)
            make.bottom.equalTo(self.findFunctionButton.snp.top).offset(-CGFloat.GlobalItemSpacing)
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
                
                let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
                let newLog = "[\(timestamp)] RX: \(rawText)"
                
                // 🚨 只做极轻量的数组追加操作
                DispatchQueue.main.async {
                    guard !self.isHidden else { return }
                    self.pendingLogs.append(newLog)
                }
            }
        }
    }
    
    // MARK: - 🚨 性能优化：定时批量刷新 UI
    private func startRefreshTimer() {
        stopRefreshTimer()
        // 每 0.2 秒 (5Hz) 批量更新一次 UI，既保证了视觉实时性，又解放了 CPU
        uiRefreshTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            self.flushPendingLogsToUI()
        }
    }
    
    private func stopRefreshTimer() {
        uiRefreshTimer?.invalidate()
        uiRefreshTimer = nil
    }
    
    private func flushPendingLogsToUI() {
        guard !pendingLogs.isEmpty else { return }
        
        // 1. 将缓冲池的数据合并到主数组
        rawLogs.append(contentsOf: pendingLogs)
        pendingLogs.removeAll()
        
        // 2. 批量剔除溢出的旧数据
        if rawLogs.count > maxLogCount {
            rawLogs.removeFirst(rawLogs.count - maxLogCount)
        }
        
        // 3. 一次性更新 UI
        logTextView.text = rawLogs.joined(separator: "\n")
        
        // 4. 一次性滚动到底部
        if logTextView.text.count > 0 {
            let range = NSRange(location: logTextView.text.count - 1, length: 1)
            logTextView.scrollRangeToVisible(range)
        }
    }

    /// 动画展示嗅探器
    public func showSniffer() {
        guard self.isHidden else { return }
        self.isHidden = false
        startRefreshTimer()
        UIView.animate(withDuration: 0.3) {
            self.alpha = 1.0
        }
    }
    
    /// 动画隐藏嗅探器
    @objc public func hideSniffer() {
        stopRefreshTimer()
        UIView.animate(withDuration: 0.3, animations: {
            self.alpha = 0.0
        }) { _ in
            PTMotoUserDefaultStruct.BleTestDataGet = false
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
    
    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // 先调用系统的默认实现，找出当前点击的到底是哪个子视图
        let hitView = super.hitTest(point, with: event)
        
        // 如果点中的是我们这个全屏的透明底层容器自身，而不是里面的面板或按钮
        if hitView == self {
            // 返回 nil，让触摸事件直接穿透到后面的 Window 或 ViewController 上
            return nil
        }
        
        // 如果点中的是黑色的 backgroundView，或者是关闭/过滤按钮，就正常返回它，拦截触摸
        return hitView
    }
    
    @MainActor deinit {
        stopRefreshTimer()
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func exportLogsAction() {
        let logFiles = PTBluetoothServerManager.shared.fetchAllHexLogFiles()
        
        // 2. 提取最新的一份日志
        guard let latestLogURL = logFiles.first else {
            // 如果没有日志，给出友好的 UI 提示 (这里可以使用你封装的 PTProgressHUD)
            PTNSLogConsole("⚠️ [导出拦截] 当前沙盒中暂无十六进制日志文件。请先连接机车录制。")
            return
        }
        
        PTNSLogConsole("📦 [准备导出] 正在打包文件: \(latestLogURL.lastPathComponent)")
        
        // 初始化系统分享面板
        let activityVC = UIActivityViewController(activityItems: [latestLogURL], applicationActivities: nil)
        
        // 查找最顶层控制器以执行 Present 操作
        if let topVC = PTUtils.getCurrentVC() {
            // 兼容 iPad，防止崩溃（指定气泡弹出的源头）
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = self.exportButton
                popover.sourceRect = self.exportButton.bounds
            }
            
            topVC.present(activityVC, animated: true, completion: nil)
        }
    }
}

