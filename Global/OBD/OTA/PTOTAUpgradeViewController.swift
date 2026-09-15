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
    private enum ChecklistItem: CaseIterable {
        case vehicleStationary
        case targetIdentityVerified
        case protocolEvidenceAvailable
        case adapterCapabilityVerified
        case originalBackupVerified
        case stablePowerAvailable
        case recoveryPathAvailable
        case firmwareCompatibilityVerified

        var titleKey: String {
            switch self {
            case .vehicleStationary: return "ota_checklist_stationary"
            case .targetIdentityVerified: return "ota_checklist_target_identity"
            case .protocolEvidenceAvailable: return "ota_checklist_protocol_evidence"
            case .adapterCapabilityVerified: return "ota_checklist_adapter_capability"
            case .originalBackupVerified: return "ota_checklist_original_backup"
            case .stablePowerAvailable: return "ota_checklist_stable_power"
            case .recoveryPathAvailable: return "ota_checklist_recovery"
            case .firmwareCompatibilityVerified: return "ota_checklist_firmware_compatibility"
            }
        }
    }

    private enum Source {
        case prepared(PTYMOBDFirmwareReadOnlyResult)
        case recovery(PTOTAResumeCheckpoint)
    }

    private let source: Source
    private var checklist: PTDeveloperTestChecklist
    private let manager: PTJieliOTAManager
    private let configuration: PTOTAProductConfiguration
    private var preflightResult: PTDeveloperTestPreflightResult

    private var upgradeTask: Task<Void, Never>?
    private var completedSuccessfully = false
    private var powerCanStart = true

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let badgeLabel = UILabel()
    private let versionLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let checklistTitleLabel = UILabel()
    private let checklistStack = UIStackView()
    private var checklistSwitches: [UISwitch] = []
    private let preflightLabel = UILabel()
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
        configuration: PTOTAProductConfiguration,
        manager: PTJieliOTAManager
    ) {
        self.source = .prepared(readOnlyResult)
        self.checklist = checklist
        self.configuration = configuration
        self.manager = manager
        self.preflightResult = PTDeveloperTestPreflight.evaluate(level: .firmware, checklist: checklist)
        super.init(nibName: nil, bundle: nil)
    }

    // EN: Keep the public convenience API while resolving the main-actor singleton inside the main actor.
    // ES: Conserva la API pública de conveniencia y resuelve el singleton del actor principal dentro del actor principal.
    // 中文：保留公开便捷 API，并在主线程隔离域内解析单例，避免默认参数跨隔离访问。
    public convenience init(
        readOnlyResult: PTYMOBDFirmwareReadOnlyResult,
        checklist: PTDeveloperTestChecklist,
        configuration: PTOTAProductConfiguration = .default
    ) {
        self.init(
            readOnlyResult: readOnlyResult,
            checklist: checklist,
            configuration: configuration,
            manager: .shared
        )
    }

    public init(
        resumeCheckpoint: PTOTAResumeCheckpoint,
        checklist: PTDeveloperTestChecklist,
        manager: PTJieliOTAManager
    ) {
        self.source = .recovery(resumeCheckpoint)
        self.checklist = checklist
        self.configuration = resumeCheckpoint.configuration
        self.manager = manager
        self.preflightResult = PTDeveloperTestPreflight.evaluate(level: .firmware, checklist: checklist)
        super.init(nibName: nil, bundle: nil)
    }

    // EN: The recovery convenience initializer follows the same isolated singleton rule as the prepared flow.
    // ES: El inicializador de recuperación aplica la misma regla del singleton aislado que el flujo preparado.
    // 中文：恢复便捷初始化器与已准备流程使用相同的主线程单例规则。
    public convenience init(
        resumeCheckpoint: PTOTAResumeCheckpoint,
        checklist: PTDeveloperTestChecklist
    ) {
        self.init(
            resumeCheckpoint: resumeCheckpoint,
            checklist: checklist,
            manager: .shared
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public static func resumeViewControllerIfAvailable(
        checklist: PTDeveloperTestChecklist,
        manager: PTJieliOTAManager
    ) async -> PTOTAUpgradeViewController? {
        guard let checkpoint = await manager.pendingResumeCheckpoint() else { return nil }
        return PTOTAUpgradeViewController(
            resumeCheckpoint: checkpoint,
            checklist: checklist,
            manager: manager
        )
    }

    public static func resumeViewControllerIfAvailable(
        checklist: PTDeveloperTestChecklist
    ) async -> PTOTAUpgradeViewController? {
        await resumeViewControllerIfAvailable(
            checklist: checklist,
            manager: .shared
        )
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = localized("ota_upgrade_title")
        view.backgroundColor = .black
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
        if isViewLoaded {
            refreshPowerPreflight()
            render(state: manager.state, progress: manager.progress)
        }
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

    // EN: Stop the UI task when the controller leaves the hierarchy; the manager remains the owner of OTA cleanup.
    // ES: Detiene la tarea de UI cuando el controlador sale de la jerarquía; el gestor conserva la limpieza de OTA.
    // 中文：控制器离开层级时停止界面任务，OTA 清理仍由管理器负责。
    @MainActor deinit {
        upgradeTask?.cancel()
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

        checklistTitleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        checklistTitleLabel.text = localized("ota_checklist_title")
        checklistStack.axis = .vertical
        checklistStack.spacing = 8
        checklistStack.alignment = .fill
        configureChecklistViews()

        preflightLabel.font = .systemFont(ofSize: 14, weight: .medium)
        preflightLabel.numberOfLines = 0
        preflightLabel.layer.cornerRadius = 12
        preflightLabel.layer.masksToBounds = true

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
        cancelConfig.title = localized("ota_cancel_upgrade")
        cancelButton.configuration = cancelConfig
        cancelButton.heightAnchor.constraint(equalToConstant: 46).isActive = true
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        var exportConfig = UIButton.Configuration.plain()
        exportConfig.title = localized("ota_export_log")
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
            checklistTitleLabel,
            checklistStack,
            preflightLabel,
            powerLabel,
            progressHeader,
            progressView,
            detailLabel,
            startButton,
            cancelButton,
            exportButton
        ].forEach { contentStack.addArrangedSubview($0) }
    }

    // EN: Let the developer confirm each firmware prerequisite without weakening the shared preflight evaluator.
    // ES: Permite al desarrollador confirmar cada requisito sin debilitar el evaluador común de preparación.
    // 中文：允许开发者逐项确认固件前置条件，但不削弱统一的前置检查器。
    func configureChecklistViews() {
        for item in ChecklistItem.allCases {
            let row = UIStackView()
            row.axis = .horizontal
            row.alignment = .center
            row.spacing = 12

            let label = UILabel()
            label.font = .systemFont(ofSize: 14)
            label.textColor = .secondaryLabel
            label.numberOfLines = 0
            label.text = localized(item.titleKey)

            let toggle = UISwitch()
            toggle.isOn = checklistValue(for: item)
            toggle.accessibilityLabel = label.text
            toggle.addTarget(self, action: #selector(checklistChanged(_:)), for: .valueChanged)
            checklistSwitches.append(toggle)

            row.addArrangedSubview(label)
            row.addArrangedSubview(toggle)
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            toggle.setContentHuggingPriority(.required, for: .horizontal)
            checklistStack.addArrangedSubview(row)
        }
    }

    private func checklistValue(for item: ChecklistItem) -> Bool {
        switch item {
        case .vehicleStationary: return checklist.vehicleStationary
        case .targetIdentityVerified: return checklist.targetIdentityVerified
        case .protocolEvidenceAvailable: return checklist.protocolEvidenceAvailable
        case .adapterCapabilityVerified: return checklist.adapterCapabilityVerified
        case .originalBackupVerified: return checklist.originalBackupVerified
        case .stablePowerAvailable: return checklist.stablePowerAvailable
        case .recoveryPathAvailable: return checklist.recoveryPathAvailable
        case .firmwareCompatibilityVerified: return checklist.firmwareCompatibilityVerified
        }
    }

    @objc func checklistChanged(_ sender: UISwitch) {
        guard let index = checklistSwitches.firstIndex(where: { $0 === sender }) else { return }
        var values = checklistSwitches.map(\.isOn)
        values[index] = sender.isOn
        checklist = PTDeveloperTestChecklist(
            vehicleStationary: values[0],
            targetIdentityVerified: values[1],
            originalBackupVerified: values[4],
            protocolEvidenceAvailable: values[2],
            adapterCapabilityVerified: values[3],
            stablePowerAvailable: values[5],
            recoveryPathAvailable: values[6],
            firmwareCompatibilityVerified: values[7],
            seedKeySourceAvailable: checklist.seedKeySourceAvailable
        )
        preflightResult = PTDeveloperTestPreflight.evaluate(
            level: .firmware,
            checklist: checklist
        )
        refreshPreflight()
        render(state: manager.state, progress: manager.progress)
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
            badgeLabel.text = "  \(localized("ota_required_badge"))  "
            badgeLabel.textColor = .systemRed
            badgeLabel.backgroundColor = .systemRed.withAlphaComponent(0.12)
        } else if isRecovery {
            badgeLabel.text = "  \(localized("ota_recovery_badge"))  "
            badgeLabel.textColor = .systemOrange
            badgeLabel.backgroundColor = .systemOrange.withAlphaComponent(0.12)
        } else {
            badgeLabel.text = "  \(localized("ota_available_badge"))  "
            badgeLabel.textColor = .systemBlue
            badgeLabel.backgroundColor = .systemBlue.withAlphaComponent(0.12)
        }

        versionLabel.text = "\(current)  →  \(target)"
        descriptionLabel.text = description.isEmpty
            ? localized("ota_description_default")
            : description + "\n\n" + localized("ota_description_default")

        cancelButton.isHidden = configuration.isMandatoryUpdate && !configuration.allowsCancelWhenMandatory
        exportButton.isEnabled = false
    }

    func refreshPowerPreflight() {
        let report = PTOTAPowerPreflight.evaluate(configuration: configuration)
        var lines: [String] = []
        lines.append("\(localized("ota_power_battery"))：\(report.snapshot.batteryPercentageText)")
        lines.append("\(localized("ota_power_source"))：\(powerSourceText(report.snapshot.source))")
        if !report.blockers.isEmpty {
            lines.append("⛔️ \(localized("ota_power_blocked"))")
        }
        if !report.warnings.isEmpty {
            lines.append("⚠️ \(localized("ota_power_warning"))")
        }
        powerCanStart = report.canStartOTA
        powerLabel.text = "  " + lines.joined(separator: "\n  ") + "  "
        powerLabel.textColor = report.canStartOTA ? .label : .systemRed
        powerLabel.backgroundColor = (report.canStartOTA ? UIColor.systemOrange : UIColor.systemRed)
            .withAlphaComponent(0.10)
        refreshPreflight()
        startButton.isEnabled = canStartUpgrade
    }

    var sourceStartTitle: String {
        switch source {
        case .prepared:
            return configuration.isMandatoryUpdate
                ? localized("ota_start_mandatory")
                : localized("ota_start")
        case .recovery:
            return localized("ota_resume")
        }
    }

    func powerSourceText(_ source: PTOTAPowerSource) -> String {
        switch source {
        case .unknown: return localized("ota_power_unknown")
        case .battery: return localized("ota_power_battery_only")
        case .charging: return localized("ota_power_charging")
        case .full: return localized("ota_power_full")
        }
    }

    func stateText(_ state: PTOTAState) -> String {
        switch state {
        case .idle: return localized("ota_state_waiting")
        case .checking: return localized("ota_state_checking")
        case .downloading: return localized("ota_state_downloading")
        case .decrypting: return localized("ota_state_decrypting")
        case .preparing: return localized("ota_state_preparing")
        case .ready: return localized("ota_state_ready")
        case .verifying: return localized("ota_state_verifying")
        case .upgrading: return localized("ota_state_upgrading")
        case .reconnecting: return localized("ota_state_reconnecting")
        case .verifyingVersion: return localized("ota_state_verifying_version")
        case .completed: return localized("ota_state_completed")
        case .failed: return localized("ota_state_failed")
        case .cancelled: return localized("ota_state_cancelled")
        }
    }

    var canStartUpgrade: Bool {
        preflightResult.isReady
            && PTDeveloperSafetyGate.shared.isEnabled
            && powerCanStart
            && !manager.isRunning
            && !completedSuccessfully
    }

    func localized(_ key: String) -> String {
        PTDashboardConfig.languageFunc(text: key)
    }

    func refreshPreflight() {
        let gateEnabled = PTDeveloperSafetyGate.shared.isEnabled
        var lines: [String] = []
        if !preflightResult.isReady {
            lines.append(localized("ota_preflight_blocked"))
            lines.append(contentsOf: preflightResult.blockers.map { "• \(localizedBlocker($0))" })
            preflightLabel.textColor = .systemRed
            preflightLabel.backgroundColor = UIColor.systemRed.withAlphaComponent(0.10)
        } else if !gateEnabled {
            lines.append(localized("ota_gate_disabled"))
            preflightLabel.textColor = .systemOrange
            preflightLabel.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.10)
        } else {
            lines.append(localized("ota_preflight_ready"))
            preflightLabel.textColor = .systemGreen
            preflightLabel.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.10)
        }
        preflightLabel.text = "  " + lines.joined(separator: "\n  ") + "  "
    }

    func localizedBlocker(_ blocker: String) -> String {
        switch blocker {
        case "vehicleNotStationary": return localized("ota_blocker_vehicle_stationary")
        case "targetIdentityNotVerified": return localized("ota_blocker_target_identity")
        case "protocolEvidenceMissing": return localized("ota_blocker_protocol_evidence")
        case "adapterCapabilityNotVerified": return localized("ota_blocker_adapter_capability")
        case "recoveryPathMissing": return localized("ota_blocker_recovery")
        case "originalFirmwareNotVerified": return localized("ota_blocker_original_backup")
        case "stablePowerMissing": return localized("ota_blocker_stable_power")
        case "firmwareCompatibilityNotVerified": return localized("ota_blocker_firmware_compatibility")
        default: return blocker
        }
    }

    func render(state: PTOTAState, progress: PTOTAProgress) {
        stateLabel.text = stateText(state)
        let percentage = min(max(progress.fractionCompleted, 0), 1)
        percentageLabel.text = "\(Int((percentage * 100).rounded()))%"
        progressView.setProgress(Float(percentage), animated: true)
        detailLabel.text = progress.detail ?? " "

        let running = manager.isRunning
        startButton.isEnabled = canStartUpgrade && !running
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
            badgeLabel.text = "  \(localized("ota_required_badge"))  "
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
        guard PTDeveloperSafetyGate.shared.isEnabled else {
            presentMessage(title: localized("ota_preflight_title"), message: localized("ota_gate_disabled"))
            return
        }
        guard preflightResult.isReady else {
            presentMessage(
                title: localized("ota_preflight_title"),
                message: preflightResult.blockers.map { localizedBlocker($0) }.joined(separator: "\n")
            )
            return
        }
        let report = PTOTAPowerPreflight.evaluate(configuration: configuration)
        guard report.canStartOTA else {
            presentMessage(title: localized("ota_cannot_start"), message: localized("ota_power_blocked"))
            return
        }

        let title = sourceStartTitle
        let message = localized("ota_confirmation_message")
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: localized("ota_back"), style: .cancel))
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
                    self.presentMessage(title: localized("ota_failure"), message: error.localizedDescription)
                }
            }
        }
    }

    @objc func cancelTapped() {
        guard manager.isRunning else { return }
        if manager.isMandatoryUpgrade && !configuration.allowsCancelWhenMandatory {
            presentMessage(title: localized("ota_required_badge"), message: localized("ota_cancel_blocked"))
            return
        }
        let alert = UIAlertController(
            title: localized("ota_cancel_title"),
            message: localized("ota_cancel_message"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: localized("ota_continue"), style: .cancel))
        alert.addAction(UIAlertAction(title: localized("ota_cancel_action"), style: .destructive) { [weak self] _ in
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
                self.presentMessage(title: localized("ota_export_failed"), message: error.localizedDescription)
            }
        }
    }

    func presentMessage(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: localized("button_confirm"), style: .default))
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
                title: localized("ota_unverified_title"),
                message: localized("ota_unverified_message")
            )
            return
        }

        let message = "已重新连接普通 YMOBD，并确认固件版本为 \(result.session.targetFirmwareVersion)。"
        presentMessage(title: localized("ota_success_title"), message: message)
    }

    public func jieliOTAManager(
        _ manager: PTJieliOTAManager,
        didFail error: PTJieliOTAManagerError
    ) {
        render(state: manager.state, progress: manager.progress)
        startButton.isEnabled = canStartUpgrade
        exportButton.isEnabled = manager.currentSession != nil
        presentMessage(title: localized("ota_failure"), message: error.localizedDescription)
    }
}

extension PTOTAUpgradeViewController {
    public func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
        if completedSuccessfully { return true }
        if manager.isRunning { return false }
        return !configuration.isMandatoryUpdate || configuration.allowsCancelWhenMandatory
    }
}
