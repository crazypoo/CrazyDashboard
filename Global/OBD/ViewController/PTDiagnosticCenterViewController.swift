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
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let runButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)

    private var diagnosticTask: Task<Void, Never>?

    override func viewDidLoad() {
        super.viewDidLoad()
        pt_Title = localized("obd_diagnostic_center")
        view.backgroundColor = .black
        configureView()
        appendReport(localized("obd_diagnostic_ready"))
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateControls(isRunning: diagnosticTask != nil)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        diagnosticTask?.cancel()
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

        progressView.progressTintColor = PTDashboardConfig.shared.appMainColor
        progressView.trackTintColor = UIColor(white: 0.25, alpha: 1)
        progressView.progress = 0

        configureButton(runButton, title: localized("obd_diagnostic_run"), color: PTDashboardConfig.shared.appMainColor)
        runButton.addTarget(self, action: #selector(runDiagnostic), for: .touchUpInside)
        configureButton(cancelButton, title: localized("button_cancel"), color: .systemOrange)
        cancelButton.addTarget(self, action: #selector(cancelDiagnostic), for: .touchUpInside)

        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)
        contentStack.addArrangedSubview(progressView)
        contentStack.addArrangedSubview(reportTextView)
        contentStack.addArrangedSubview(runButton)
        contentStack.addArrangedSubview(cancelButton)

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
            runButton.heightAnchor.constraint(equalToConstant: 44),
            cancelButton.heightAnchor.constraint(equalToConstant: 44)
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
                    failureReasons: failureReasons.isEmpty ? nil : failureReasons
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
