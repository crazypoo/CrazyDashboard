//
//  PTOTAUpgradeViewController.swift
//  CrazyDashboard
//
//  UIKit P4 OTA screen: mandatory update policy, power warnings, progress,
//  reconnect/resume visibility, verified completion and log export.
//

import UIKit
import PooTools

@MainActor
class PTOTAUpgradeViewController: PTMotoBaseViewController {
    private enum Source {
        case prepared(PTYMOBDFirmwareReadOnlyResult)
        case recovery(PTOTAResumeCheckpoint)
    }

    private let source: Source
    private let checklist: PTDeveloperTestChecklist
    private let manager: PTJieliOTAManager
    private let configuration: PTOTAProductConfiguration

    private var upgradeTask: Task<Void, Never>?
    private var completedSuccessfully = false
    private var powerCanStart = true

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let badgeLabel = UILabel()
    private let versionLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let powerLabel = UILabel()
    private let stateLabel = UILabel()
    private let detailLabel = UILabel()
    private let percentageLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let startButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private let exportButton = UIButton(type: .system)

    public init(
        readOnlyResult: PTYMOBDFirmwareReadOnlyResult,
        checklist: PTDeveloperTestChecklist,
        configuration: PTOTAProductConfiguration = .default,
        manager: PTJieliOTAManager = .shared
    ) {
        self.source = .prepared(readOnlyResult)
        self.checklist = checklist
        self.configuration = configuration
        self.manager = manager
        super.init(nibName: nil, bundle: nil)
    }

    public init(
        resumeCheckpoint: PTOTAResumeCheckpoint,
        checklist: PTDeveloperTestChecklist,
        manager: PTJieliOTAManager = .shared
    ) {
        self.source = .recovery(resumeCheckpoint)
        self.checklist = checklist
        self.configuration = resumeCheckpoint.configuration
        self.manager = manager
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public static func resumeViewControllerIfAvailable(
        checklist: PTDeveloperTestChecklist,
        manager: PTJieliOTAManager = .shared
    ) async -> PTOTAUpgradeViewController? {
        guard let checkpoint = await manager.pendingResumeCheckpoint() else { return nil }
        return PTOTAUpgradeViewController(
            resumeCheckpoint: checkpoint,
            checklist: checklist,
            manager: manager
        )
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = "OBD 固件升级"
        view.backgroundColor = .systemBackground
        isModalInPresentation = configuration.isMandatoryUpdate
        configureNavigation()
        configureViews()
        configureContent()
        refreshPowerPreflight()
        render(state: manager.state, progress: manager.progress)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        manager.delegate = self
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        presentationController?.delegate = self
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if manager.delegate === self {
            manager.delegate = nil
        }
    }
}

private extension PTOTAUpgradeViewController {
    func configureNavigation() {
        if configuration.isMandatoryUpdate && !configuration.allowsCancelWhenMandatory {
            navigationItem.hidesBackButton = true
        }
    }

    func configureViews() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.alignment = .fill

        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 20),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -28)
        ])

        badgeLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        badgeLabel.textAlignment = .center
        badgeLabel.layer.cornerRadius = 8
        badgeLabel.layer.masksToBounds = true
        badgeLabel.heightAnchor.constraint(equalToConstant: 30).isActive = true

        versionLabel.font = .systemFont(ofSize: 22, weight: .bold)
        versionLabel.numberOfLines = 0

        descriptionLabel.font = .systemFont(ofSize: 15)
        descriptionLabel.textColor = .secondaryLabel
        descriptionLabel.numberOfLines = 0

        powerLabel.font = .systemFont(ofSize: 14, weight: .medium)
        powerLabel.numberOfLines = 0
        powerLabel.layer.cornerRadius = 12
        powerLabel.layer.masksToBounds = true

        stateLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        stateLabel.numberOfLines = 0

        detailLabel.font = .systemFont(ofSize: 14)
        detailLabel.textColor = .secondaryLabel
        detailLabel.numberOfLines = 0

        percentageLabel.font = .monospacedDigitSystemFont(ofSize: 28, weight: .bold)
        percentageLabel.textAlignment = .right

        progressView.progress = 0
        progressView.heightAnchor.constraint(equalToConstant: 8).isActive = true

        var startConfig = UIButton.Configuration.filled()
        startConfig.cornerStyle = .large
        startConfig.baseForegroundColor = .white
        startConfig.title = sourceStartTitle
        startButton.configuration = startConfig
        startButton.heightAnchor.constraint(equalToConstant: 52).isActive = true
        startButton.addTarget(self, action: #selector(startTapped), for: .touchUpInside)

        var cancelConfig = UIButton.Configuration.tinted()
        cancelConfig.cornerStyle = .large
        cancelConfig.title = "取消升级"
        cancelButton.configuration = cancelConfig
        cancelButton.heightAnchor.constraint(equalToConstant: 46).isActive = true
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        var exportConfig = UIButton.Configuration.plain()
        exportConfig.title = "导出 OTA 日志"
        exportButton.configuration = exportConfig
        exportButton.heightAnchor.constraint(equalToConstant: 44).isActive = true
        exportButton.addTarget(self, action: #selector(exportTapped), for: .touchUpInside)

        let progressHeader = UIStackView(arrangedSubviews: [stateLabel, percentageLabel])
        progressHeader.axis = .horizontal
        progressHeader.alignment = .firstBaseline
        progressHeader.spacing = 12
        stateLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        percentageLabel.setContentHuggingPriority(.required, for: .horizontal)

        [
            badgeLabel,
            versionLabel,
            descriptionLabel,
            powerLabel,
            progressHeader,
            progressView,
            detailLabel,
            startButton,
            cancelButton,
            exportButton
        ].forEach { contentStack.addArrangedSubview($0) }
    }

    func configureContent() {
        let current: String
        let target: String
        let description: String
        let isRecovery: Bool

        switch source {
        case let .prepared(result):
            current = result.checkResult.request.obdFirmwareVersion
            target = result.checkResult.metadata.firmwareVersion
            description = result.checkResult.metadata.firmwareDescription
            isRecovery = false
        case let .recovery(checkpoint):
            current = checkpoint.session.oldFirmwareVersion
            target = checkpoint.session.targetFirmwareVersion
            description = checkpoint.metadata.firmwareDescription
            isRecovery = true
        }

        if configuration.isMandatoryUpdate {
            badgeLabel.text = "  必须升级  "
            badgeLabel.textColor = .systemRed
            badgeLabel.backgroundColor = .systemRed.withAlphaComponent(0.12)
        } else if isRecovery {
            badgeLabel.text = "  检测到未完成升级  "
            badgeLabel.textColor = .systemOrange
            badgeLabel.backgroundColor = .systemOrange.withAlphaComponent(0.12)
        } else {
            badgeLabel.text = "  可用固件更新  "
            badgeLabel.textColor = .systemBlue
            badgeLabel.backgroundColor = .systemBlue.withAlphaComponent(0.12)
        }

        versionLabel.text = "\(current)  →  \(target)"
        descriptionLabel.text = description.isEmpty
            ? "升级期间请保持 OBD 适配器与车辆供电稳定，不要退出 App、断开蓝牙或启动其他 OBD 操作。"
            : description + "\n\n升级期间请保持 OBD 适配器与车辆供电稳定，不要退出 App、断开蓝牙或启动其他 OBD 操作。"

        cancelButton.isHidden = configuration.isMandatoryUpdate && !configuration.allowsCancelWhenMandatory
        exportButton.isEnabled = false
    }

    func refreshPowerPreflight() {
        let report = PTOTAPowerPreflight.evaluate(configuration: configuration)
        var lines: [String] = []
        lines.append("手机电量：\(report.snapshot.batteryPercentageText)")
        lines.append("供电状态：\(powerSourceText(report.snapshot.source))")
        if !report.blockers.isEmpty {
            lines.append(contentsOf: report.blockers.map { "⛔️ \($0)" })
        }
        if !report.warnings.isEmpty {
            lines.append(contentsOf: report.warnings.map { "⚠️ \($0)" })
        }
        powerCanStart = report.canStartOTA
        powerLabel.text = "  " + lines.joined(separator: "\n  ") + "  "
        powerLabel.textColor = report.canStartOTA ? .label : .systemRed
        powerLabel.backgroundColor = (report.canStartOTA ? UIColor.systemOrange : UIColor.systemRed)
            .withAlphaComponent(0.10)
        startButton.isEnabled = powerCanStart && !manager.isRunning && !completedSuccessfully
    }

    var sourceStartTitle: String {
        switch source {
        case .prepared:
            return configuration.isMandatoryUpdate ? "开始必须升级" : "开始升级"
        case .recovery:
            return "恢复升级"
        }
    }

    func powerSourceText(_ source: PTOTAPowerSource) -> String {
        switch source {
        case .unknown: return "未知"
        case .battery: return "电池供电"
        case .charging: return "正在充电"
        case .full: return "外接电源 / 已充满"
        }
    }

    func stateText(_ state: PTOTAState) -> String {
        switch state {
        case .idle: return "等待开始"
        case .checking: return "执行升级前检查"
        case .downloading: return "下载固件"
        case .decrypting: return "解密固件"
        case .preparing: return "准备 Jieli OTA"
        case .ready: return "OTA 已就绪"
        case .verifying: return "设备校验中"
        case .upgrading: return "正在升级"
        case .reconnecting: return "OTA 设备重连中"
        case .verifyingVersion: return "复核固件版本"
        case .completed: return "升级完成"
        case .failed: return "升级失败"
        case .cancelled: return "升级已取消"
        }
    }

    func render(state: PTOTAState, progress: PTOTAProgress) {
        stateLabel.text = stateText(state)
        let percentage = min(max(progress.fractionCompleted, 0), 1)
        percentageLabel.text = "\(Int((percentage * 100).rounded()))%"
        progressView.setProgress(Float(percentage), animated: true)
        detailLabel.text = progress.detail ?? " "

        let running = manager.isRunning
        startButton.isEnabled = powerCanStart && !running && !completedSuccessfully
        if running {
            startButton.configuration?.showsActivityIndicator = true
        } else {
            startButton.configuration?.showsActivityIndicator = false
            startButton.configuration?.title = sourceStartTitle
        }

        cancelButton.isEnabled = running
            && (!manager.isMandatoryUpgrade || configuration.allowsCancelWhenMandatory)
        exportButton.isEnabled = manager.currentSession != nil

        if manager.isMandatoryUpgrade {
            badgeLabel.text = "  必须升级  "
            badgeLabel.textColor = .systemRed
            badgeLabel.backgroundColor = .systemRed.withAlphaComponent(0.12)
        }

        if manager.isMandatoryUpgrade && !configuration.allowsCancelWhenMandatory {
            isModalInPresentation = !completedSuccessfully
            navigationItem.hidesBackButton = !completedSuccessfully
            cancelButton.isHidden = true
        }
    }

    @objc func startTapped() {
        refreshPowerPreflight()
        let report = PTOTAPowerPreflight.evaluate(configuration: configuration)
        guard report.canStartOTA else {
            presentMessage(title: "暂时不能升级", message: report.blockers.joined(separator: "\n"))
            return
        }

        let title = sourceStartTitle
        let message = "升级过程中会暂停普通 OBD polling，并切换到 Jieli RCSP OTA。请确认车辆/适配器供电稳定，升级完成且 AT+VERSION 验证成功前不要主动断开。"
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "返回", style: .cancel))
        alert.addAction(UIAlertAction(title: title, style: .destructive) { [weak self] _ in
            self?.beginUpgrade()
        })
        present(alert, animated: true)
    }

    func beginUpgrade() {
        guard upgradeTask == nil, !manager.isRunning else { return }
        startButton.isEnabled = false
        startButton.configuration?.showsActivityIndicator = true

        upgradeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.upgradeTask = nil
                self.startButton.configuration?.showsActivityIndicator = false
            }
            do {
                switch self.source {
                case let .prepared(result):
                    _ = try await self.manager.start(
                        readOnlyResult: result,
                        checklist: self.checklist,
                        explicitlyConfirmed: true,
                        productConfiguration: self.configuration
                    )
                case .recovery:
                    _ = try await self.manager.resumeInterruptedUpgrade(
                        checklist: self.checklist,
                        explicitlyConfirmed: true
                    )
                }
            } catch {
                // Delegate callbacks render the detailed failure state. This is only a fallback.
                if self.manager.lastError == nil {
                    self.presentMessage(title: "升级失败", message: error.localizedDescription)
                }
            }
        }
    }

    @objc func cancelTapped() {
        guard manager.isRunning else { return }
        if manager.isMandatoryUpgrade && !configuration.allowsCancelWhenMandatory {
            presentMessage(title: "必须升级", message: "当前升级策略不允许在 OTA 过程中主动取消。")
            return
        }
        let alert = UIAlertController(
            title: "取消升级？",
            message: "只有在 SDK 允许取消的阶段才会安全停止。不要通过关闭蓝牙或强杀 App 代替取消。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "继续升级", style: .cancel))
        alert.addAction(UIAlertAction(title: "取消 OTA", style: .destructive) { [weak self] _ in
            self?.manager.cancel()
        })
        present(alert, animated: true)
    }

    @objc func exportTapped() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let url: URL
                switch self.source {
                case .prepared:
                    url = try await self.manager.exportCurrentLogURL()
                case let .recovery(checkpoint):
                    url = try await self.manager.exportLogURL(for: checkpoint.session.id)
                }
                let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                if let popover = controller.popoverPresentationController {
                    popover.sourceView = self.exportButton
                    popover.sourceRect = self.exportButton.bounds
                }
                self.present(controller, animated: true)
            } catch {
                self.presentMessage(title: "无法导出日志", message: error.localizedDescription)
            }
        }
    }

    func presentMessage(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
}

extension PTOTAUpgradeViewController: PTJieliOTAManagerDelegate {
    public func jieliOTAManager(
        _ manager: PTJieliOTAManager,
        didChange state: PTOTAState,
        progress: PTOTAProgress
    ) {
        render(state: state, progress: progress)
    }

    public func jieliOTAManager(
        _ manager: PTJieliOTAManager,
        didFinish result: PTOTAExecutionResult
    ) {
        completedSuccessfully = result.finalState == .completed && result.versionVerified
        render(state: result.finalState, progress: manager.progress)

        guard completedSuccessfully else {
            presentMessage(
                title: "升级尚未验证",
                message: "Jieli OTA 已结束，但 AT+VERSION 尚未确认目标版本。"
            )
            return
        }

        let message = "已重新连接普通 YMOBD，并确认固件版本为 \(result.session.targetFirmwareVersion)。"
        presentMessage(title: "升级成功", message: message)
    }

    public func jieliOTAManager(
        _ manager: PTJieliOTAManager,
        didFail error: PTJieliOTAManagerError
    ) {
        render(state: manager.state, progress: manager.progress)
        startButton.isEnabled = powerCanStart
        exportButton.isEnabled = manager.currentSession != nil
        presentMessage(title: "升级失败", message: error.localizedDescription)
    }
}

extension PTOTAUpgradeViewController {
    public func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
        if completedSuccessfully { return true }
        if manager.isRunning { return false }
        return !configuration.isMandatoryUpdate || configuration.allowsCancelWhenMandatory
    }
}
