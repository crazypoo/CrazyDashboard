//
//  PTDiagnosticCenterViewController.swift
//  CrazyDashboard
//
//  EN: Read-only vehicle health report built on the existing telemetry and UDS services.
//  ES: Informe de salud del vehículo de solo lectura basado en los servicios existentes de telemetría y UDS.
//  中文：基于现有遥测和 UDS 服务的只读车辆健康报告页面。
//

import UIKit
import PooTools

// EN: The public diagnostic page never exposes raw write, fuzzing or flashing controls.
// ES: La página pública de diagnóstico nunca expone controles de escritura, fuzzing o flasheo.
// 中文：公开诊断页面不会暴露裸写入、Fuzz 或刷写控制。
@MainActor
final class PTDiagnosticCenterViewController: PTMotoBaseViewController {
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let reportTextView = UITextView()
    private let build68TextView = UITextView()
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let runButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private let exportButton = UIButton(type: .system)

    private var diagnosticTask: Task<Void, Never>?
    private var isObservingBuild68 = false

    override func viewDidLoad() {
        super.viewDidLoad()
        pt_Title = localized("obd_diagnostic_center")
        view.backgroundColor = .black
        configureView()
        PTBuild68DiagnosticCoordinator.shared.start()
        startObservingBuild68()
        appendReport(localized("obd_diagnostic_ready"))
        refreshBuild68Report()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startObservingBuild68()
        updateControls(isRunning: diagnosticTask != nil)
        refreshBuild68Report()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopObservingBuild68()
        diagnosticTask?.cancel()
    }

    // EN: Observe Build 68 only while this screen is visible to avoid a stale UIKit observer.
    // ES: Observa Build 68 solo mientras esta pantalla está visible para evitar un observador UIKit obsoleto.
    // 中文：仅在页面可见时监听 Build 68，避免 UIKit 遗留观察者。
    private func startObservingBuild68() {
        guard !isObservingBuild68 else { return }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(build68DidChange),
            name: PTBuild68DiagnosticCoordinator.didChange,
            object: PTBuild68DiagnosticCoordinator.shared
        )
        isObservingBuild68 = true
    }

    // EN: Remove the observer before leaving the screen; the coordinator continues collecting safely.
    // ES: Elimina el observador antes de salir de la pantalla; el coordinador continúa recopilando de forma segura.
    // 中文：离开页面前移除观察者，协调器仍可安全继续收集数据。
    private func stopObservingBuild68() {
        guard isObservingBuild68 else { return }
        NotificationCenter.default.removeObserver(
            self,
            name: PTBuild68DiagnosticCoordinator.didChange,
            object: PTBuild68DiagnosticCoordinator.shared
        )
        isObservingBuild68 = false
    }

    private func configureView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false

        contentStack.axis = .vertical
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        reportTextView.translatesAutoresizingMaskIntoConstraints = false
        reportTextView.isEditable = false
        reportTextView.isScrollEnabled = false
        reportTextView.backgroundColor = UIColor(white: 0.1, alpha: 1)
        reportTextView.textColor = .white
        reportTextView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        reportTextView.layer.cornerRadius = 14
        reportTextView.textContainerInset = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)

        build68TextView.translatesAutoresizingMaskIntoConstraints = false
        build68TextView.isEditable = false
        build68TextView.isScrollEnabled = false
        build68TextView.backgroundColor = UIColor(white: 0.08, alpha: 1)
        build68TextView.textColor = .systemTeal
        build68TextView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        build68TextView.layer.cornerRadius = 14
        build68TextView.textContainerInset = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)

        progressView.progressTintColor = PTDashboardConfig.shared.appMainColor
        progressView.trackTintColor = UIColor(white: 0.25, alpha: 1)
        progressView.progress = 0

        configureButton(runButton, title: localized("obd_diagnostic_run"), color: PTDashboardConfig.shared.appMainColor)
        runButton.addTarget(self, action: #selector(runDiagnostic), for: .touchUpInside)
        configureButton(cancelButton, title: localized("button_cancel"), color: .systemOrange)
        cancelButton.addTarget(self, action: #selector(cancelDiagnostic), for: .touchUpInside)
        configureButton(exportButton, title: localized("can_lab_share"), color: .systemBlue)
        exportButton.addTarget(self, action: #selector(exportLatestReport), for: .touchUpInside)

        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)
        contentStack.addArrangedSubview(progressView)
        contentStack.addArrangedSubview(reportTextView)
        contentStack.addArrangedSubview(build68TextView)
        contentStack.addArrangedSubview(runButton)
        contentStack.addArrangedSubview(cancelButton)
        contentStack.addArrangedSubview(exportButton)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            reportTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: 300),
            build68TextView.heightAnchor.constraint(greaterThanOrEqualToConstant: 220),
            runButton.heightAnchor.constraint(equalToConstant: 44),
            cancelButton.heightAnchor.constraint(equalToConstant: 44),
            exportButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func configureButton(_ button: UIButton, title: String, color: UIColor) {
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = color.withAlphaComponent(0.85)
        button.layer.cornerRadius = 10
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
    }

    @objc private func runDiagnostic() {
        guard diagnosticTask == nil else { return }
        guard PTMotoTelemetryManager.shared.isConnected else {
            appendReport(localized("obd_diagnostic_disconnected"))
            return
        }

        reportTextView.text = ""
        progressView.progress = 0
        updateControls(isRunning: true)

        diagnosticTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var failureReasons: [String] = []
            do {
                appendReport(localized("obd_diagnostic_started"))
                try Task.checkCancellation()

                let dtcs: [String: [PTTroubleCode]]
                do {
                    dtcs = try await PTUDSReadService.shared.readConfirmedDTCs()
                } catch {
                    dtcs = [:]
                    failureReasons.append("DTC: \(error.localizedDescription)")
                }
                let dtcLines = formatDTCs(dtcs)
                appendSection(title: localized("obd_diagnostic_dtcs"), lines: dtcLines)
                progressView.progress = 0.2

                try Task.checkCancellation()
                let mode6Reports: [PTMode6Data]
                do {
                    mode6Reports = try await PTUDSReadService.shared.readMode6Reports()
                } catch {
                    mode6Reports = []
                    failureReasons.append("Mode 6: \(error.localizedDescription)")
                }
                let mode6Lines = mode6Reports.map {
                    "\($0.componentName): \($0.formattedValue) [\($0.isPassed ? "PASS" : "CHECK")]"
                }
                appendSection(
                    title: localized("obd_diagnostic_mode6"),
                    lines: mode6Lines.isEmpty ? [localized("obd_diagnostic_no_data")] : mode6Lines
                )
                progressView.progress = 0.45

                try Task.checkCancellation()
                let didResults: [PTOBDIDReadResult]
                do {
                    didResults = try await PTUDSReadService.shared.readConfirmedDIDsForCurrentVehicle(
                        progress: { [weak self] current, total, result in
                            guard let self else { return }
                            self.appendReport("DID \(result.did) · \(current)/\(total) · \(result.status.rawValue)")
                        }
                    )
                } catch {
                    didResults = []
                    failureReasons.append("DID: \(error.localizedDescription)")
                }
                let didLines = didResults.map { result in
                    let value = result.decodedText ?? result.payloadHex ?? result.negativeResponse?.description ?? result.rawResponse
                    return "DID \(result.did): \(result.status.rawValue) · \(value)"
                }
                appendSection(
                    title: localized("obd_diagnostic_dids"),
                    lines: didLines.isEmpty ? [localized("obd_diagnostic_no_data")] : didLines
                )
                _ = PTXP400InstructionEvidenceStore.shared.record(
                    results: didResults,
                    source: "diagnostic-center"
                )
                progressView.progress = 0.7

                try Task.checkCancellation()
                var freezeFrameLines: [String] = []
                if !dtcs.isEmpty {
                    do {
                        if let engineSpeed = try await PTUDSReadService.shared.readEngineSpeedFreezeFrame() {
                            freezeFrameLines = ["PID 0C · RPM: \(String(format: "%.0f", engineSpeed))"]
                        } else {
                            failureReasons.append(localized("obd_diagnostic_freeze_frame_unavailable"))
                        }
                    } catch {
                        failureReasons.append("Freeze Frame: \(error.localizedDescription)")
                    }
                } else {
                    freezeFrameLines = [localized("obd_diagnostic_no_dtc_freeze_frame")]
                }
                appendSection(title: localized("obd_diagnostic_freeze_frame"), lines: freezeFrameLines)
                progressView.progress = 0.85

                let info = PTMotoTelemetryManager.shared.obdInfo
                let telemetry = PTVehicleConnectivityCoordinator.shared.telemetrySnapshot
                let battery = PTVehicleConnectivityCoordinator.shared.batteryHealthSummary
                let wheel = PTVehicleConnectivityCoordinator.shared.wheelSpeedConsistency
                let connectionQuality = PTVehicleConnectionQualityEvaluator.evaluate(snapshot: telemetry)
                let healthLines = makeHealthLines(
                    battery: battery.observationCount > 0 ? battery : nil,
                    wheel: wheel.state == .unavailable ? nil : wheel,
                    connectionQuality: connectionQuality
                )
                appendSection(title: localized("obd_diagnostic_health"), lines: healthLines)
                let fingerprint = PTECUReadOnlyFingerprint(
                    ecuVersion: info.ecuVersion.isEmpty ? nil : info.ecuVersion,
                    cvn: info.cvn.isEmpty ? nil : info.cvn,
                    protocolName: info.atdpName.description.isEmpty ? nil : info.atdpName.description,
                    confirmedDIDs: didResults
                        .filter { $0.status == .success }
                        .map(\.did)
                )
                appendSection(
                    title: localized("obd_diagnostic_fingerprint"),
                    lines: makeFingerprintLines(fingerprint)
                )
                try Task.checkCancellation()
                do {
                    _ = try await PTBuild68DiagnosticCoordinator.shared.runManualReadOnlyDiagnostic()
                    refreshBuild68Report()
                } catch {
                    failureReasons.append("Build 68: \(error.localizedDescription)")
                }
                let report = PTGarageDiagnosticReport(
                    vin: info.vin,
                    ecuVersion: info.ecuVersion,
                    cvn: info.cvn,
                    protocolName: info.atdpName.description,
                    adapterName: info.moudleInfo.deviceName,
                    supportedCommandCount: info.supportCommand.count,
                    didResults: didResults.map { PTGarageDIDRecord(result: $0) },
                    confirmedDTCs: dtcLines,
                    mode6Results: mode6Lines,
                    freezeFrame: freezeFrameLines.isEmpty ? nil : freezeFrameLines,
                    failureReasons: failureReasons.isEmpty ? nil : failureReasons,
                    batteryHealthSummary: battery.observationCount > 0 ? battery : nil,
                    wheelSpeedConsistency: wheel.state == .unavailable ? nil : wheel,
                    connectionQuality: connectionQuality,
                    ecuFingerprint: fingerprint,
                    build68Session: PTBuild68DiagnosticCoordinator.shared.latestSession
                )
                if PTMotorcycleGarageStore.shared.addDiagnosticReport(report) {
                    appendReport(localized("obd_diagnostic_saved"))
                    if !dtcs.isEmpty {
                        let request = PTNotificationRequest(
                            kind: .diagnostic,
                            title: localized("obd_diagnostic_notification_title"),
                            body: localized("obd_diagnostic_notification_body"),
                            identifier: "pt.notification.diagnostic.dtc",
                            deduplicationKey: "diagnostic-dtc",
                            cooldown: 7 * 24 * 60 * 60,
                            categoryIdentifier: PTNotificationCenter.diagnosticCategoryIdentifier,
                            userInfo: ["pt_notification_kind": PTAppNotificationKind.diagnostic.rawValue]
                        )
                        PTNotificationCenter.schedule(request)
                    }
                } else {
                    failureReasons.append(localized("obd_diagnostic_save_failed"))
                }
                progressView.progress = 1
                appendSection(
                    title: localized("obd_diagnostic_failures"),
                    lines: failureReasons.isEmpty ? [localized("obd_diagnostic_none")] : failureReasons
                )
                appendReport(localized("obd_diagnostic_finished"))
            } catch is CancellationError {
                appendReport(localized("obd_diagnostic_cancelled"))
            } catch {
                appendReport("❌ \(error.localizedDescription)")
            }

            diagnosticTask = nil
            updateControls(isRunning: false)
        }
    }

    @objc private func cancelDiagnostic() {
        diagnosticTask?.cancel()
    }

    @objc private func build68DidChange() {
        refreshBuild68Report()
    }

    @objc private func exportLatestReport() {
        let alert = UIAlertController(
            title: localized("can_lab_share"),
            message: nil,
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: "JSON", style: .default) { [weak self] _ in
            self?.shareLatestReport(format: .json)
        })
        alert.addAction(UIAlertAction(title: "CSV", style: .default) { [weak self] _ in
            self?.shareLatestReport(format: .csv)
        })
        alert.addAction(UIAlertAction(title: "Build 68 JSON", style: .default) { [weak self] _ in
            self?.shareLatestBuild68Evidence()
        })
        alert.addAction(UIAlertAction(title: localized("button_cancel"), style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = exportButton
            popover.sourceRect = exportButton.bounds
        }
        present(alert, animated: true)
    }

    // EN: Offer both structured JSON and spreadsheet-friendly CSV for the latest redacted report.
    // ES: Ofrece JSON estructurado y CSV compatible con hojas de cálculo para el último informe anonimizado.
    // 中文：为最新的脱敏报告提供结构化 JSON 和便于表格处理的 CSV 两种导出格式。
    private func shareLatestReport(format: PTRideSafetyExportFormat) {
        do {
            guard let url = try PTMotorcycleGarageStore.shared.exportLatestDiagnosticReportURL(format: format) else {
                appendReport(localized("obd_diagnostic_no_data"))
                return
            }
            let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            if let popover = activity.popoverPresentationController {
                popover.sourceView = exportButton
                popover.sourceRect = exportButton.bounds
            }
            present(activity, animated: true)
        } catch {
            appendReport("❌ \(error.localizedDescription)")
        }
    }

    // EN: Share the dedicated redacted Build 68 session document when a deep-read session exists.
    // ES: Comparte el documento específico y redactado de Build 68 cuando existe una sesión profunda.
    // 中文：存在深度读取会话时，分享专用的 Build 68 脱敏文档。
    private func shareLatestBuild68Evidence() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                guard let url = try await PTBuild68EvidenceStore.shared.exportLatestURL() else {
                    appendReport(localized("obd_diagnostic_no_data"))
                    return
                }
                let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                if let popover = activity.popoverPresentationController {
                    popover.sourceView = exportButton
                    popover.sourceRect = exportButton.bounds
                }
                present(activity, animated: true)
            } catch {
                appendReport("❌ (error.localizedDescription)")
            }
        }
    }

    private func updateControls(isRunning: Bool) {
        runButton.isEnabled = !isRunning
        cancelButton.isEnabled = isRunning
        runButton.alpha = isRunning ? 0.45 : 1
        cancelButton.alpha = isRunning ? 1 : 0.45
    }

    private func appendSection(title: String, lines: [String]) {
        appendReport("\n[\(title)]\n\(lines.joined(separator: "\n"))")
    }

    private func appendReport(_ text: String) {
        if reportTextView.text.isEmpty {
            reportTextView.text = text
        } else {
            reportTextView.text += "\n" + text
        }
        reportTextView.scrollRangeToVisible(NSRange(location: max(reportTextView.text.count - 1, 0), length: 1))
    }

    private func makeHealthLines(
        battery: PTBatteryHealthSummary?,
        wheel: PTWheelSpeedConsistencyResult?,
        connectionQuality: PTVehicleConnectionQuality
    ) -> [String] {
        var lines = [
            "\(localized("obd_diagnostic_connection")): \(localized("obd_diagnostic_connection_\(connectionQuality.rawValue)"))"
        ]
        if let battery {
            if let resting = battery.restingMedianVoltage {
                lines.append("\(localized("obd_diagnostic_battery_resting")): \(String(format: "%.2f V", resting))")
            }
            if let cranking = battery.crankingMinimumVoltage {
                lines.append("\(localized("obd_diagnostic_battery_cranking_min")): \(String(format: "%.2f V", cranking))")
            }
            if let running = battery.runningMedianVoltage {
                lines.append("\(localized("obd_diagnostic_battery_running")): \(String(format: "%.2f V", running))")
            }
            lines.append("\(localized("obd_diagnostic_battery_confidence")): \(String(format: "%.0f%%", battery.confidence * 100))")
        } else {
            lines.append("\(localized("obd_diagnostic_battery")): \(localized("obd_diagnostic_no_data"))")
        }
        if let wheel {
            lines.append(
                "\(localized("obd_diagnostic_wheel_speed")): "
                    + "\(localized("obd_diagnostic_wheel_\(wheel.state.rawValue)")) · "
                    + "\(String(format: "%.1f%%", wheel.absoluteRatio * 100))"
            )
        } else {
            lines.append("\(localized("obd_diagnostic_wheel_speed")): \(localized("obd_diagnostic_no_data"))")
        }
        return lines
    }

    // EN: The Build 68 panel shows bounded read-only evidence without exposing raw credentials or security material.
    // ES: El panel de Build 68 muestra evidencia de solo lectura limitada sin exponer credenciales ni material de seguridad.
    // 中文：Build 68 面板展示有界只读证据，不暴露认证凭据或安全材料。
    private func refreshBuild68Report() {
        let noData = localized("obd_diagnostic_no_data")
        guard let session = PTBuild68DiagnosticCoordinator.shared.latestSession else {
            build68TextView.text = "Build 68 · \(localized("obd_diagnostic_read_only"))\n\(noData)"
            return
        }

        var lines = [
            "Build 68 · \(localized("obd_diagnostic_read_only"))",
            "Capability: \(session.capability.supportedPIDs.count) PID · Mode 06: \(session.capability.mode06Masks.count) page · Mode 09: \(session.capability.mode09PIDs.count) PID"
        ]
        if let monitor = session.monitorStatus {
            lines.append("0101: MIL=\(monitor.isMILOn ? "ON" : "OFF") · DTC=\(monitor.confirmedDTCCount)")
        }
        if session.troubleCodes.isEmpty {
            lines.append("DTC: \(localized("obd_diagnostic_no_dtc"))")
        } else {
            lines.append("DTC: " + session.troubleCodes.map { "\($0.source.rawValue)=\($0.code)" }.joined(separator: ", "))
        }
        if let freeze = session.freezeFrame {
            let values = [
                freeze.engineRPM.map { "RPM=\(String(format: "%.0f", $0))" },
                freeze.vehicleSpeed.map { "Speed=\(String(format: "%.0f", $0))" },
                freeze.coolantTemperature.map { "Coolant=\(String(format: "%.1f", $0))°C" },
                freeze.manifoldPressure.map { "MAP=\(String(format: "%.0f", $0))" }
            ].compactMap { $0 }
            lines.append("Freeze Frame: \(values.isEmpty ? noData : values.joined(separator: " · "))")
        } else {
            lines.append("Freeze Frame: \(noData)")
        }
        if let ecu = session.electronicControlUnit {
            lines.append("ECU: \(ecu.ecuName ?? noData) · RX=0x\(String(format: "%03X", ecu.rxAddress))")
            if let fingerprint = ecu.fingerprint {
                lines.append("Fingerprint: \(fingerprint.prefix(16))…")
            }
            if !ecu.calibrationRecords.isEmpty {
                lines.append("CALID/CVN: \(ecu.calibrationRecords.map { "\($0.calibrationID)/\($0.cvn ?? "—")" }.joined(separator: ", "))")
            }
        }
        let voltage = [
            session.voltage.controlModuleVoltage.map { "PID42=\(String(format: "%.2f", $0))V" },
            session.voltage.adapterVoltage.map { "ATRV=\(String(format: "%.2f", $0))V" }
        ].compactMap { $0 }
        if !voltage.isEmpty {
            lines.append("Voltage: \(voltage.joined(separator: " · "))\(session.voltage.hasDiscrepancy ? " · discrepancy" : "")")
        }
        if let throttle = session.throttle.percent {
            lines.append("Throttle: \(String(format: "%.1f", throttle))% [\(throttleSourceLabel(session.throttle.source))]")
        }
        if let engine = session.engineSession, let runtime = engine.engineRuntimeAtConnect {
            lines.append("Engine runtime: \(String(format: "%.0f", runtime))s · start=\(engine.engineStartedAt?.formatted(date: .omitted, time: .shortened) ?? noData)")
        }
        lines.append("Raw read results: \(session.rawCommandResults.count) · PID runtime states: \(session.pidRuntime.count)")
        build68TextView.text = lines.joined(separator: "\n")
    }

    private func throttleSourceLabel(_ source: PTBuild68ThrottleSource?) -> String {
        switch source {
        case .relative: return "0145"
        case .absolute: return "0111"
        case .xp400Candidate: return "XP400"
        case nil: return "—"
        }
    }

    // EN: Fingerprint output is read-only and deliberately excludes VIN and raw security material.
    // ES: La huella es de solo lectura y excluye deliberadamente el VIN y el material de seguridad sin procesar.
    // 中文：指纹输出只读，并刻意排除 VIN 与原始安全材料。
    private func makeFingerprintLines(_ fingerprint: PTECUReadOnlyFingerprint) -> [String] {
        let noData = localized("obd_diagnostic_no_data")
        let dids = fingerprint.confirmedDIDs.isEmpty
            ? noData
            : fingerprint.confirmedDIDs.joined(separator: ", ")
        return [
            "\(localized("obd_diagnostic_ecu_version")): \(fingerprint.ecuVersion ?? noData)",
            "\(localized("obd_diagnostic_cvn")): \(fingerprint.cvn ?? noData)",
            "\(localized("obd_diagnostic_protocol")): \(fingerprint.protocolName ?? noData)",
            "\(localized("obd_diagnostic_confirmed_dids")): \(dids)",
            "\(localized("obd_diagnostic_bootloader")): \(localized("obd_diagnostic_read_only"))",
            "\(localized("obd_diagnostic_calibration")): \(localized("obd_diagnostic_read_only"))"
        ]
    }

    private func formatDTCs(_ values: [String: [PTTroubleCode]]) -> [String] {
        let lines = values.keys.sorted().flatMap { key in
            (values[key] ?? []).map {
                "\(key) · \($0.code): \($0.description) [\($0.severity.rawValue)]"
            }
        }
        return lines.isEmpty ? [localized("obd_diagnostic_no_dtc")] : lines
    }

    private func localized(_ key: String) -> String {
        PTDashboardConfig.languageFunc(text: key)
    }
}
