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
public class PTECUSnifferOverlay: PTDashboardBaseView {

    // EN: The developer surface can be collapsed without ending the foreground safety session.
    // ES: La superficie de desarrollador puede minimizarse sin terminar la sesión de seguridad en primer plano.
    // 中文：开发者界面可以收起，但不会结束当前前台安全会话。
    enum PresentationState: Equatable {
        case hidden
        case compact
        case expanded
    }

    private(set) var presentationState: PresentationState = .hidden
    
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
        view.text = PTDashboardConfig.languageFunc(text: "dev_sniffer_title")
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
        view.setTitle(PTDashboardConfig.languageFunc(text: "dev_collapse_overlay"), for: .normal)
        view.setTitleColor(.white, for: .normal)
        view.backgroundColor = .systemBlue.withAlphaComponent(0.8)
        view.layer.cornerRadius = 8
        view.addTarget(self, action: #selector(collapseSniffer), for: .touchUpInside)
        return view
    }()

    // EN: The explicit exit action is separate from merely hiding the console.
    // ES: La salida explícita está separada de ocultar solamente la consola.
    // 中文：显式退出操作与单纯收起控制台分开。
    private lazy var exitButton: UIButton = {
        let view = UIButton(type: .system)
        view.setTitle(PTDashboardConfig.languageFunc(text: "dev_exit_session"), for: .normal)
        view.setTitleColor(.white, for: .normal)
        view.backgroundColor = .systemRed.withAlphaComponent(0.8)
        view.layer.cornerRadius = 8
        view.addTarget(self, action: #selector(endDeveloperSession), for: .touchUpInside)
        return view
    }()

    // EN: The compact control is the only window area that remains interactive while the console is collapsed.
    // ES: El control compacto es la única zona de la ventana que sigue siendo interactiva al minimizar la consola.
    // 中文：控制台收起后，只有这个紧凑按钮保留窗口级交互。
    private lazy var compactButton: UIButton = {
        let view = UIButton(type: .system)
        view.setTitle("DEV", for: .normal)
        view.setTitleColor(.white, for: .normal)
        view.titleLabel?.font = .monospacedSystemFont(ofSize: 12, weight: .bold)
        view.layer.cornerRadius = 23
        view.layer.borderWidth = 1
        view.layer.borderColor = UIColor.white.withAlphaComponent(0.35).cgColor
        view.addTarget(self, action: #selector(expandSniffer), for: .touchUpInside)
        view.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handleCompactButtonPan(_:))))
        view.accessibilityIdentifier = "developer.compactButton"
        view.accessibilityTraits = .button
        return view
    }()
    
    private lazy var filterButton:UIButton = {
        let view = UIButton(type: .system)
        view.setTitle(PTDashboardConfig.languageFunc(text: "dev_filter_all"), for: .normal)
        view.setTitleColor(.white, for: .normal)
        view.backgroundColor = .systemBlue.withAlphaComponent(0.8)
        view.layer.cornerRadius = 8
        view.addTarget(self, action: #selector(toggleFilter), for: .touchUpInside)
        return view
    }()
    
    private lazy var exportButton: UIButton = {
        let view = UIButton(type: .system)
        view.setTitle(PTDashboardConfig.languageFunc(text: "dev_export_logs"), for: .normal)
        view.setTitleColor(.white, for: .normal)
        view.backgroundColor = .systemPurple.withAlphaComponent(0.8)
        view.layer.cornerRadius = 8
        view.addTarget(self, action: #selector(exportLogsAction), for: .touchUpInside)
        return view
    }()

    private lazy var highRiskLabel: UILabel = {
        let view = UILabel()
        view.text = PTDashboardConfig.languageFunc(text: "dev_high_risk_title")
        view.textColor = .systemOrange
        view.font = .appfont(size: 11, bold: true)
        return view
    }()

    private lazy var highRiskSwitch: UISwitch = {
        let view = UISwitch()
        view.onTintColor = .systemOrange
        view.addTarget(self, action: #selector(toggleHighRisk(_:)), for: .valueChanged)
        return view
    }()

    private lazy var findFunctionButton: UIButton = {
        let view = UIButton(type: .system)
        view.setTitle(PTDashboardConfig.languageFunc(text: "dev_find_command"), for: .normal)
        view.setTitleColor(.white, for: .normal)
        view.layer.cornerRadius = 8
        view.setBackgroundColor(color: .systemPurple.withAlphaComponent(0.8), forState: .normal)
        view.setBackgroundColor(color: .systemRed.withAlphaComponent(0.8), forState: .selected)
        view.addActionHandlers(handler: { [weak self] sender in
            guard let self else { return }
            if sender.isSelected {
                PTBluetoothServerManager.shared.stopAutomatedFuzzing()
            } else {
                guard PTDeveloperSafetyGate.shared.authorize(.didFuzz) else {
                    self.appendDeveloperLog("⛔️ 高风险开关未开启，未启动 Fuzz。")
                    return
                }
                PTBluetoothServerManager.shared.startAutomatedFuzzing()
            }
            sender.isSelected.toggle()
        })
        return view
    }()

    private lazy var developerToolsButton: UIButton = {
        let view = UIButton(type: .system)
        view.setTitle(PTDashboardConfig.languageFunc(text: "dev_advanced_tools"), for: .normal)
        view.setTitleColor(.white, for: .normal)
        view.backgroundColor = .systemTeal.withAlphaComponent(0.8)
        view.layer.cornerRadius = 8
        view.addTarget(self, action: #selector(showDeveloperTools), for: .touchUpInside)
        return view
    }()

    private var isFilterEnabled: Bool = false
    // 缓存池，避免高频刷新导致内存溢出
    private var rawLogs: [String] = []
    private let maxLogCount = 100
    
    // 🚨 性能优化新增：数据缓冲池与渲染定时器
    private var pendingLogs: [String] = []
    private var uiRefreshTimer: Timer?
    private var observerTokens: [NSObjectProtocol] = []
    private var compactButtonOffset = CGPoint.zero
    private var compactButtonDragStartOffset = CGPoint.zero

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
        // EN: Start fully hidden so creating the developer surface never blocks the ordinary dashboard.
        // ES: Empieza completamente oculta para que crear la superficie de desarrollador nunca bloquee el panel normal.
        // 中文：初始化时完全隐藏，确保创建开发者界面不会阻塞普通仪表盘。
        self.isHidden = true
        self.alpha = 0.0
        backgroundView.isHidden = true
        compactButton.isHidden = true
        
        // EN: The translucent background keeps the existing developer-console appearance.
        // ES: El fondo translúcido conserva la apariencia existente de consola de desarrollador.
        // 中文：半透明背景保留现有的开发者控制台风格。
        self.addSubview(backgroundView)
        backgroundView.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(PTAppBaseConfig.share.defaultViewSpace)
            make.top.equalToSuperview().inset(CGFloat.kNavBarHeight_Total + CGFloat.GlobalItemSpacing)
            make.bottom.equalToSuperview().inset(CGFloat.kTabbarHeight_Total + CGFloat.GlobalItemSpacing)
        }
        
        // 标题
        backgroundView.addSubviews([
            titleLabel, highRiskLabel, highRiskSwitch, closeButton, exitButton, developerToolsButton,
            filterButton, exportButton, findFunctionButton, logTextView
        ])
        addSubview(compactButton)
        titleLabel.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalToSuperview().inset(CGFloat.GlobalItemSpacing)
        }

        highRiskLabel.snp.makeConstraints { make in
            make.left.equalToSuperview().inset(PTAppBaseConfig.share.defaultViewSpace)
            make.top.equalTo(titleLabel.snp.bottom).offset(CGFloat.GlobalItemSpacing)
        }

        highRiskSwitch.snp.makeConstraints { make in
            make.right.equalToSuperview().inset(PTAppBaseConfig.share.defaultViewSpace)
            make.centerY.equalTo(highRiskLabel)
        }
        
        closeButton.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(PTAppBaseConfig.share.defaultViewSpace)
            make.height.equalTo(30)
            make.bottom.equalTo(exitButton.snp.top).offset(-CGFloat.GlobalItemSpacing)
        }

        exitButton.snp.makeConstraints { make in
            make.left.right.height.equalTo(closeButton)
            make.bottom.equalToSuperview().inset(CGFloat.GlobalItemSpacing)
        }
        
        filterButton.snp.makeConstraints { make in
            make.left.right.height.equalTo(self.closeButton)
            make.bottom.equalTo(self.developerToolsButton.snp.top).offset(-CGFloat.GlobalItemSpacing)
        }

        developerToolsButton.snp.makeConstraints { make in
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
            make.top.equalTo(self.highRiskSwitch.snp.bottom).offset(CGFloat.GlobalItemSpacing)
            make.bottom.equalTo(self.findFunctionButton.snp.top).offset(-CGFloat.GlobalItemSpacing)
        }

        compactButton.snp.makeConstraints { make in
            make.width.height.equalTo(46)
            make.trailing.equalTo(safeAreaLayoutGuide.snp.trailing).inset(12)
            make.bottom.equalTo(safeAreaLayoutGuide.snp.bottom).inset(12)
        }
        updateCompactButtonAppearance()
    }

    // EN: Let touches pass through every area not owned by the expanded console or compact button.
    // ES: Deja pasar los toques en todas las zonas que no pertenecen a la consola expandida o al botón compacto.
    // 中文：除展开控制台或紧凑按钮实际占用的区域外，其余触摸全部穿透。
    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        switch presentationState {
        case .hidden:
            return nil
        case .compact:
            let buttonPoint = compactButton.convert(point, from: self)
            guard compactButton.point(inside: buttonPoint, with: event) else { return nil }
            return compactButton.hitTest(buttonPoint, with: event)
        case .expanded:
            let backgroundPoint = backgroundView.convert(point, from: self)
            guard backgroundView.point(inside: backgroundPoint, with: event) else { return nil }
            let hitView = super.hitTest(point, with: event)
            return hitView === self ? nil : hitView
        }
    }

    // EN: Keep the compact developer control inside the safe area while it is dragged.
    // ES: Mantiene el control compacto de desarrollador dentro del área segura durante el arrastre.
    // 中文：拖动紧凑开发者按钮时，将其限制在安全区域内。
    @objc private func handleCompactButtonPan(_ gesture: UIPanGestureRecognizer) {
        guard presentationState == .compact else { return }
        switch gesture.state {
        case .began:
            compactButtonDragStartOffset = compactButtonOffset
        case .changed, .ended:
            let translation = gesture.translation(in: self)
            let proposedOffset = CGPoint(
                x: compactButtonDragStartOffset.x + translation.x,
                y: compactButtonDragStartOffset.y + translation.y
            )
            compactButtonOffset = clampedCompactButtonOffset(proposedOffset)
            compactButton.transform = CGAffineTransform(
                translationX: compactButtonOffset.x,
                y: compactButtonOffset.y
            )
            if gesture.state == .ended {
                compactButtonDragStartOffset = compactButtonOffset
            }
        case .cancelled, .failed:
            compactButtonOffset = clampedCompactButtonOffset(compactButtonDragStartOffset)
            compactButton.transform = CGAffineTransform(
                translationX: compactButtonOffset.x,
                y: compactButtonOffset.y
            )
        default:
            break
        }
    }

    // EN: Clamp the offset against the safe-area frame so the recovery control remains reachable.
    // ES: Limita el desplazamiento contra el marco del área segura para que el control de recuperación siga siendo accesible.
    // 中文：根据安全区域限制偏移，确保恢复按钮始终可访问。
    private func clampedCompactButtonOffset(_ offset: CGPoint) -> CGPoint {
        let safeFrame = safeAreaLayoutGuide.layoutFrame
        let baseCenter = compactButton.center
        let radius = compactButton.bounds.width / 2
        let minX = safeFrame.minX + radius - baseCenter.x
        let maxX = safeFrame.maxX - radius - baseCenter.x
        let minY = safeFrame.minY + radius - baseCenter.y
        let maxY = safeFrame.maxY - radius - baseCenter.y
        return CGPoint(
            x: min(max(offset.x, minX), maxX),
            y: min(max(offset.y, minY), maxY)
        )
    }
    
    // MARK: - 数据监听
    private func setupObservers() {
        PTBluetoothServerManager.shared.addDelegate(self)

        let safetyObserver = NotificationCenter.default.addObserver(
            forName: PTDeveloperSafetyGate.stateDidChange,
            object: PTDeveloperSafetyGate.shared,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleSafetyGateChange()
            }
        }
        observerTokens.append(safetyObserver)
    }
    
    // MARK: - 🚨 性能优化：定时批量刷新 UI
    private func startRefreshTimer() {
        stopRefreshTimer()
        // 每 0.2 秒 (5Hz) 批量更新一次 UI，既保证了视觉实时性，又解放了 CPU
        uiRefreshTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self else { return }
            PTGCDManager.shared.runOnMain {
                self.flushPendingLogsToUI()
            }
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

    /// EN: Expands the developer console without changing the current safety decision.
    /// ES: Expande la consola de desarrollador sin cambiar la decisión de seguridad actual.
    /// 中文：展开开发者控制台，但不改变当前安全门禁状态。
    public func showSniffer() {
        presentationState = .expanded
        PTMotoUserDefaultStruct.BleTestDataGet = true
        highRiskSwitch.isOn = PTDeveloperSafetyGate.shared.isEnabled
        self.isHidden = false
        backgroundView.isHidden = false
        compactButton.isHidden = true
        updateCompactButtonAppearance()
        startRefreshTimer()
        UIView.animate(withDuration: 0.3) {
            self.alpha = 1.0
        }
    }

    // EN: Collapse only the console; the foreground developer session stays authorized.
    // ES: Minimiza solo la consola; la sesión de desarrollador en primer plano sigue autorizada.
    // 中文：只收起控制台，当前前台开发者会话仍保持授权。
    @objc public func collapseSniffer() {
        guard presentationState != .hidden else { return }
        stopActiveFuzzing()
        stopRefreshTimer()
        presentationState = .compact
        PTMotoUserDefaultStruct.BleTestDataGet = true
        backgroundView.isHidden = true
        compactButton.isHidden = false
        isHidden = false
        alpha = 1.0
        updateCompactButtonAppearance()
    }

    // EN: The compact button reopens the console while the developer session is alive.
    // ES: El botón compacto vuelve a abrir la consola mientras la sesión de desarrollador siga activa.
    // 中文：开发者会话存续期间，紧凑按钮可以重新打开控制台。
    @objc private func expandSniffer() {
        showSniffer()
    }

    // EN: Explicit exit revokes authorization and removes the window-level developer surface.
    // ES: La salida explícita revoca la autorización y elimina la superficie de desarrollador de la ventana.
    // 中文：显式退出会撤销授权，并移除窗口级开发者界面。
    @objc public func endDeveloperSession() {
        stopActiveFuzzing()
        PTDeveloperSafetyGate.shared.disable(reason: .userDisabled)
        highRiskSwitch.setOn(false, animated: false)
        presentationState = .hidden
        PTMotoUserDefaultStruct.BleTestDataGet = false
        stopRefreshTimer()
        backgroundView.isHidden = true
        compactButton.isHidden = true
        UIView.animate(withDuration: 0.2, animations: {
            self.alpha = 0.0
        }) { _ in
            self.isHidden = true
            self.rawLogs.removeAll(keepingCapacity: true)
            self.pendingLogs.removeAll(keepingCapacity: true)
            self.logTextView.text = ""
        }
    }

    // EN: Preserve the legacy API as a full developer-session exit.
    // ES: Conserva la API heredada como salida completa de la sesión de desarrollador.
    // 中文：保留旧 API，并将其定义为完整退出开发者会话。
    @objc public func hideSniffer() {
        endDeveloperSession()
    }

    // EN: Stop work owned by the visible developer console before it is collapsed or revoked.
    // ES: Detiene el trabajo propio de la consola visible antes de minimizarla o revocar la autorización.
    // 中文：在收起或撤销授权前，停止由可见开发者控制台持有的任务。
    private func stopActiveFuzzing() {
        guard findFunctionButton.isSelected else { return }
        PTBluetoothServerManager.shared.stopAutomatedFuzzing()
        findFunctionButton.isSelected = false
    }

    // EN: Keep both pending and rendered logs bounded during long developer sessions.
    // ES: Mantiene limitados los registros pendientes y renderizados durante sesiones largas.
    // 中文：长时间开发者会话中同时限制待渲染和已渲染日志的容量。
    private func enqueueLog(_ message: String) {
        pendingLogs.append(message)
        if pendingLogs.count > maxLogCount {
            pendingLogs.removeFirst(pendingLogs.count - maxLogCount)
        }
    }

    // EN: Reflect the single safety gate in the compact control without exposing console details.
    // ES: Refleja la única puerta de seguridad en el control compacto sin exponer detalles de la consola.
    // 中文：在紧凑按钮上反映唯一安全门禁状态，但不暴露控制台细节。
    private func updateCompactButtonAppearance() {
        let isEnabled = PTDeveloperSafetyGate.shared.isEnabled
        compactButton.backgroundColor = (isEnabled ? UIColor.systemOrange : UIColor.systemTeal)
            .withAlphaComponent(0.9)
        compactButton.accessibilityLabel = PTDashboardConfig.languageFunc(text: "dev_compact_label")
        compactButton.accessibilityValue = PTDashboardConfig.languageFunc(
            text: isEnabled ? "dev_compact_high_risk_on" : "dev_compact_high_risk_off"
        )
    }

    // EN: Revoke active work on lifecycle or connection resets and keep the compact recovery control visible.
    // ES: Revoca el trabajo activo tras reinicios del ciclo de vida o de conexión y mantiene visible el control compacto de recuperación.
    // 中文：生命周期或连接重置时撤销活动任务，并保留紧凑恢复按钮。
    private func handleSafetyGateChange() {
        highRiskSwitch.setOn(PTDeveloperSafetyGate.shared.isEnabled, animated: true)
        updateCompactButtonAppearance()
        guard !PTDeveloperSafetyGate.shared.isEnabled else { return }

        stopActiveFuzzing()
        if presentationState == .expanded,
           PTDeveloperSafetyGate.shared.lastEvent?.rejection == .lifecycleReset {
            collapseSniffer()
        }
    }

    /// EN: Turning the switch off stops active fuzzing immediately.
    /// ES: Apagar el interruptor detiene el fuzzing activo de inmediato.
    /// 中文：关闭开关后立即停止正在运行的 Fuzz。
    @objc private func toggleHighRisk(_ sender: UISwitch) {
        PTDeveloperSafetyGate.shared.setEnabled(sender.isOn)
        guard !sender.isOn else {
            appendDeveloperLog("✅ 高风险开发者操作已开启，仅当前前台会话有效。")
            return
        }

        if findFunctionButton.isSelected {
            stopActiveFuzzing()
        }
        appendDeveloperLog("🛑 高风险开发者操作已关闭，后续调用将被拒绝。")
    }

    /// EN: Keeps safety decisions visible without depending on console output.
    /// ES: Mantiene visibles las decisiones de seguridad sin depender de la consola.
    /// 中文：把安全决策显示在面板中，不只依赖控制台输出。
    private func appendDeveloperLog(_ message: String) {
        enqueueLog("[Safety] \(message)")
    }

    // EN: Keep evidence browsing and firmware readiness in the existing developer surface.
    // ES: Mantiene la consulta de evidencia y la preparación de firmware en la superficie de desarrollador existente.
    // 中文：把证据浏览和固件准备检查集中到现有开发者面板。
    @objc private func showDeveloperTools() {
        guard let presenter = PTUtils.getCurrentVC() else { return }
        collapseSniffer()
        let alert = UIAlertController(
            title: PTDashboardConfig.languageFunc(text: "dev_advanced_tools"),
            message: PTDashboardConfig.languageFunc(text: "dev_advanced_tools_hint"),
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(
            title: PTDashboardConfig.languageFunc(text: "obd_evidence_title"),
            style: .default
        ) { _ in
            let controller = PTXP400EvidenceViewController()
            presenter.present(PTBaseNavControl(rootViewController: controller), animated: true)
        })
        alert.addAction(UIAlertAction(
            title: PTDashboardConfig.languageFunc(text: "can_lab_developer_title"),
            style: .default
        ) { _ in
            let controller = PTCANLabViewController(mode: .developerCapture)
            if let navigationController = presenter.navigationController {
                navigationController.pushViewController(controller, animated: true)
            } else {
                presenter.present(PTBaseNavControl(rootViewController: controller), animated: true)
            }
        })
        alert.addAction(UIAlertAction(
            title: PTDashboardConfig.languageFunc(text: "dev_firmware_preflight"),
            style: .default
        ) { [weak self] _ in
            self?.runFirmwarePreflight()
        })
        alert.addAction(UIAlertAction(
            title: PTDashboardConfig.languageFunc(text: "button_cancel"),
            style: .cancel
        ))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(
                x: presenter.view.bounds.midX,
                y: presenter.view.bounds.midY,
                width: 1,
                height: 1
            )
        }
        presenter.present(alert, animated: true)
    }

    private func runFirmwarePreflight() {
        guard let address = PTOBDDiagnosticAddress(tx: "7E0", rx: "7E8") else { return }
        let request = PTFirmwareUpgradeRequest(
            targetAddress: address,
            firmwareIdentifier: "dev-placeholder",
            byteCount: 0,
            sha256Hex: ""
        )
        let state = PTFirmwareUpgradeStateMachine.shared.prepare(
            request: request,
            checklist: .empty
        )
        appendDeveloperLog(
            "🧪 Firmware preflight: \(state.rawValue); blockers=\(PTFirmwareUpgradeStateMachine.shared.blockers.joined(separator: ","))"
        )
        let blockers = PTFirmwareUpgradeStateMachine.shared.blockers
        let blockerText = blockers.isEmpty ? "-" : blockers.joined(separator: ", ")
        let resultAlert = UIAlertController(
            title: PTDashboardConfig.languageFunc(text: "dev_firmware_preflight"),
            message: String(
                format: PTDashboardConfig.languageFunc(text: "dev_firmware_preflight_result"),
                state.rawValue,
                blockerText
            ),
            preferredStyle: .alert
        )
        resultAlert.addAction(UIAlertAction(
            title: PTDashboardConfig.languageFunc(text: "button_confirm"),
            style: .default
        ))
        PTUtils.getCurrentVC()?.present(resultAlert, animated: true)
    }
    
    @objc private func toggleFilter() {
        isFilterEnabled.toggle()
        if isFilterEnabled {
            filterButton.setTitle(PTDashboardConfig.languageFunc(text: "dev_filter_unknown"), for: .normal)
            filterButton.backgroundColor = .systemOrange.withAlphaComponent(0.8)
            // 开启过滤时，清空当前屏幕的杂乱数据
            rawLogs.removeAll()
            logTextView.text = ""
        } else {
            filterButton.setTitle(PTDashboardConfig.languageFunc(text: "dev_filter_all"), for: .normal)
            filterButton.backgroundColor = .systemBlue.withAlphaComponent(0.8)
        }
    }
        
    @MainActor deinit {
        stopRefreshTimer()
        PTBluetoothServerManager.shared.removeDelegate(self)
        observerTokens.forEach(NotificationCenter.default.removeObserver)
    }
    
    @objc private func exportLogsAction() {
        
        let actions = ["OBD","Dashboard","Menu"]
        UIAlertController.base_alertVC(title: PTDashboardConfig.languageFunc(text: "File"), titleColor: PTDashboardConfig.shared.appMainColor, titleFont: .appfont(size: 16),msg: PTDashboardConfig.languageFunc(text: "Get dev file"), okBtns: actions, cancelBtn: PTDashboardConfig.languageFunc(text: "button_cancel"), showIn: PTUtils.getCurrentVC(), cancelBtnColor: .systemBlue, doneBtnColors: [.systemBlue], moreBtn:  { index, title in
            switch index {
            case 0:
                self.textLogGet(fileName: "MotoOBDLog")
            case 1:
                self.textLogGet(fileName: "MotoHexLog")
            default:
                let files = PTCANCaptureStore.shared.allCaptureFiles()
                let map = files.map( { $0.lastPathComponent })
                UIAlertController.base_alertVC(title: PTDashboardConfig.languageFunc(text: "File"), titleColor: PTDashboardConfig.shared.appMainColor, titleFont: .appfont(size: 16),msg: PTDashboardConfig.languageFunc(text: "Get dev file"), okBtns: map, cancelBtn: PTDashboardConfig.languageFunc(text: "button_cancel"), showIn: PTUtils.getCurrentVC(), cancelBtnColor: .systemBlue, doneBtnColors: [.systemBlue], moreBtn:  { subIndex, subTitle in
                    if let currentVC = PTUtils.getCurrentVC() {
                        PTCANCaptureShare.present(from: currentVC, fileURL: files[subIndex])
                    }
                })
            }
        })
    }
    
    func textLogGet(fileName:String) {
        if !fileName.isEmpty {
            let logFiles = PTOBDLogger.shared.fetchAllLogFiles(prefix: fileName)
            
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
}

extension PTECUSnifferOverlay:PTBLEDashboardDelegate {
    func dashboardManager(_ manager: PTBluetoothServerManager, unknownData data: String) {
        Task { @MainActor [weak self] in
            guard let self, self.presentationState != .hidden else { return }
            // EN: Apply the filter and append on the main actor so UI state has one owner.
            // ES: Aplica el filtro y añade el registro en el actor principal para que el estado de UI tenga un único propietario.
            // 中文：在主 Actor 上执行过滤和追加，让 UI 状态只有一个所有者。
            if self.isFilterEnabled && data.contains("[已知]") {
                return
            }

            let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
            self.enqueueLog("[\(timestamp)] RX: \(data)")
        }
    }
}
