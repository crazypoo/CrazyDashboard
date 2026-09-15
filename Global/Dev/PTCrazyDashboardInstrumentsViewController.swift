//
//  PTCrazyDashboardInstrumentsViewController.swift
//  CrazyDashboard
//
//  EN: Presents the Build 59 read-only Instruments panels for developers.
//  ES: Presenta los paneles de Instruments de solo lectura de Build 59 para desarrolladores.
//  中文：为开发者展示 Build 59 的只读 Instruments 面板。
//

import UIKit
import PooTools
import SafeSFSymbols

@MainActor
class PTCrazyDashboardInstrumentsViewController: PTMotoBaseViewController {
    private let store: PTCrazyDashboardInstrumentsStore
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private var snapshotObserver: NSObjectProtocol?

    lazy var exportButton:PTBaseButton = {
        let view = PTBaseButton(type:.custom)
        view.setImage(UIImage(.square.andArrowUp).withTintColor(.white, renderingMode: .alwaysOriginal), for: .normal)
        view.bounds = .init(origin: .zero, size: .init(width: PTAppBaseConfig.share.navBarButtonSize, height: PTAppBaseConfig.share.navBarButtonSize))
        view.addActionHandlers(handler: { _ in
            self.exportTapped()
        })
        return view
    }()
    
    public convenience init() {
        self.init(store: PTCrazyDashboardInstrumentsStore.shared)
    }

    public init(store: PTCrazyDashboardInstrumentsStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        pt_Title = localized("dev_instruments_title", fallback: "CrazyDashboard Instruments")
        view.backgroundColor = .black
        configureLayout()
        snapshotObserver = NotificationCenter.default.addObserver(
            forName: PTCrazyDashboardInstrumentsStore.snapshotDidChange,
            object: store,
            queue: .main
        ) { [weak self] notification in
            guard let snapshot = notification.userInfo?["snapshot"] as? PTCrazyDashboardInstrumentSnapshot else { return }
            Task { @MainActor [weak self] in
                self?.render(snapshot)
            }
        }
        render(store.snapshot)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        store.start()
        render(store.snapshot)
        setCustomRightButtons(buttons: [exportButton])
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if let snapshotObserver {
            NotificationCenter.default.removeObserver(snapshotObserver)
        }
    }
    
    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        store.stop()
    }

    private func configureLayout() {
        scrollView.alwaysBounceVertical = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        stackView.axis = .vertical
        stackView.spacing = 12
        stackView.alignment = .fill
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32)
        ])
    }

    private func render(_ snapshot: PTCrazyDashboardInstrumentSnapshot) {
        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        addPanel(
            title: "Overview",
            body: [
                "Read-only: \(snapshot.system.isReadOnly ? "yes" : "no")",
                "XP400 BLE: \(snapshot.xp400BLE.isConnected ? "connected" : "disconnected")",
                "OBD/ELM: \(snapshot.obd.isConnected ? "connected" : "disconnected")",
                "YMOBD: \(snapshot.ymobdAdapter.isOfficialYMOBD ? "detected" : "not detected")",
                "Telemetry mode: \(snapshot.telemetry.mode)"
            ].joined(separator: "\n")
        )
        addPanel(title: "XP400 BLE", body: formatBLE(snapshot.xp400BLE))
        addPanel(title: "OBD / ELM", body: formatOBD(snapshot.obd))
        addPanel(title: "YMOBD Adapter", body: formatAdapter(snapshot.ymobdAdapter))
        if snapshot.adapterOTA.isVisible {
            addPanel(title: "Jieli OTA", body: formatOTA(snapshot.adapterOTA), accent: .systemOrange)
        }
        addPanel(title: "CAN Monitor", body: formatCAN(snapshot.can))
        addPanel(title: "Vehicle Telemetry", body: formatTelemetry(snapshot.telemetry))
        addPanel(title: "GPS", body: formatGPS(snapshot.gps))
        addPanel(title: "Motion", body: formatMotion(snapshot.motion))
        addPanel(title: "System", body: formatSystem(snapshot.system))
        addPanel(title: "Timeline", body: formatTimeline(store.timeline))
    }

    private func addPanel(title: String, body: String, accent: UIColor = .systemBlue) {
        let panel = UIView()
        panel.backgroundColor = .secondarySystemGroupedBackground
        panel.layer.cornerRadius = 12
        panel.layer.borderWidth = 1
        panel.layer.borderColor = accent.withAlphaComponent(0.35).cgColor

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = accent

        let bodyLabel = UILabel()
        bodyLabel.text = body
        bodyLabel.numberOfLines = 0
        bodyLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        bodyLabel.textColor = .label
        bodyLabel.lineBreakMode = .byWordWrapping

        let content = UIStackView(arrangedSubviews: [titleLabel, bodyLabel])
        content.axis = .vertical
        content.spacing = 8
        content.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 14),
            content.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -14),
            content.topAnchor.constraint(equalTo: panel.topAnchor, constant: 12),
            content.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -12)
        ])
        stackView.addArrangedSubview(panel)
    }

    private func formatBLE(_ metrics: PTCrazyDashboardXP400BLEMetrics) -> String {
        [
            "state: \(metrics.isConnected ? "connected" : "disconnected") / \(metrics.lifecycle)",
            "session: \(metrics.sessionID?.uuidString ?? "—")",
            "generation: \(metrics.generation.map(String.init) ?? "—")",
            "auth: \(metrics.isAuthenticated ? "authenticated" : "not authenticated")",
            "TIO: \(metrics.isTioSubscribed ? "subscribed" : "not subscribed")",
            "credits: send=\(metrics.sendCredits), local=\(metrics.localCredits)",
            "send queue: \(metrics.queueDepth) / sending=\(metrics.isSending)",
            "RX/s: \(rate(metrics.rxPerSecond))",
            "TX/s: \(rate(metrics.txPerSecond)) [\(metrics.txRateAvailability)]",
            "reconnects: \(metrics.reconnectCount)",
            "telemetry signals: \(metrics.telemetrySignalCount)"
        ].joined(separator: "\n")
    }

    private func formatOBD(_ metrics: PTCrazyDashboardOBDMetrics) -> String {
        [
            "state: \(metrics.elmState)",
            "transport: \(metrics.transport)",
            "polling: \(metrics.isPolling ? "running" : "stopped")",
            "command queue: \(metrics.commandQueueDepth.map(String.init) ?? "—") [\(metrics.commandQueueAvailability)]",
            "current lease: \(metrics.currentLease)",
            "PID/s: \(rate(metrics.pidPerSecond))",
            "RTT: \(milliseconds(metrics.rttMilliseconds))",
            "CAN monitor: \(metrics.canMonitorState)",
            "UDS: \(metrics.udsState)",
            "error: \(metrics.lastError ?? "—")"
        ].joined(separator: "\n")
    }

    private func formatAdapter(_ metrics: PTCrazyDashboardAdapterMetrics) -> String {
        [
            "vendor: \(metrics.vendor ?? "—")",
            "model: \(metrics.model ?? "—")",
            "firmware: \(metrics.firmwareVersion ?? "—")",
            "identifier suffix: \(metrics.identifierSuffix ?? "—")",
            "transport: \(metrics.transport)",
            "auth: \(metrics.authentication)",
            "mode: \(metrics.mode)",
            "capabilities: \(metrics.capabilities.joined(separator: ", "))"
        ].joined(separator: "\n")
    }

    private func formatOTA(_ metrics: PTCrazyDashboardOTAMetrics) -> String {
        [
            "SDK: \(metrics.sdkVersion)",
            "state: \(metrics.state)",
            "progress: \(Int(metrics.progress * 100))% (\(metrics.completedBytes)/\(metrics.totalBytes) bytes)",
            "resume: \(metrics.resumeState)",
            "reconnects: \(metrics.reconnectCount)",
            "current: \(metrics.currentFirmwareVersion ?? "—")",
            "target: \(metrics.targetFirmwareVersion ?? "—")",
            "version verified: \(metrics.versionVerified.map { $0 ? "yes" : "no" } ?? "pending")",
            "error: \(metrics.error ?? "—")"
        ].joined(separator: "\n")
    }

    private func formatCAN(_ metrics: PTCrazyDashboardCANMetrics) -> String {
        [
            "state: \(metrics.state)",
            "FPS: \(rate(metrics.framesPerSecond))",
            "total frames: \(metrics.totalFrameCount)",
            "retained: \(metrics.retainedFrameCount)",
            "dropped: \(metrics.droppedFrameCount)",
            "headers: \(metrics.headers.isEmpty ? "—" : metrics.headers.joined(separator: ", "))"
        ].joined(separator: "\n")
    }

    private func formatTelemetry(_ metrics: PTCrazyDashboardTelemetryMetrics) -> String {
        [
            "mode: \(metrics.mode)",
            "signals: \(metrics.valueCount)",
            "synthetic/replay: \(metrics.containsSyntheticData ? "yes" : "no")",
            "names: \(metrics.signalNames.isEmpty ? "—" : metrics.signalNames.joined(separator: ", "))",
            "updated: \(date(metrics.updatedAt))"
        ].joined(separator: "\n")
    }

    private func formatGPS(_ metrics: PTCrazyDashboardGPSMetrics) -> String {
        [
            "tracking: \(metrics.isTracking ? "yes" : "no")",
            "horizontal accuracy: \(metrics.horizontalAccuracyMeters.map { String(format: "%.1f m", $0) } ?? "—")"
        ].joined(separator: "\n")
    }

    private func formatMotion(_ metrics: PTCrazyDashboardMotionMetrics) -> String {
        [
            "source: \(metrics.source)",
            "sample rate: \(rate(metrics.sampleRateHz))",
            "roll/pitch/yaw: \(String(format: "%.1f / %.1f / %.1f", metrics.roll, metrics.pitch, metrics.yaw))°",
            "g-force: \(String(format: "%.2f / %.2f / %.2f", metrics.gForceX, metrics.gForceY, metrics.gForceZ))"
        ].joined(separator: "\n")
    }

    private func formatSystem(_ metrics: PTCrazyDashboardSystemMetrics) -> String {
        [
            "app: \(metrics.appVersion) (\(metrics.buildVersion))",
            "read-only: \(metrics.isReadOnly ? "yes" : "no")",
            "replay active: \(metrics.isReplayActive ? "yes" : "no")",
            "generated: \(date(metrics.generatedAt))"
        ].joined(separator: "\n")
    }

    private func formatTimeline(_ events: [PTCrazyDashboardInstrumentTimelineEvent]) -> String {
        guard !events.isEmpty else { return "No instrument events yet." }
        return events.suffix(24).reversed().map { event in
            let detail = event.detail.map { " — \($0)" } ?? ""
            return "\(date(event.timestamp)) [\(event.domain.rawValue)] \(event.name)\(detail)"
        }.joined(separator: "\n")
    }

    @objc private func exportTapped() {
        let alert = UIAlertController(
            title: "Export Instruments",
            message: "Export the bounded read-only snapshot and timeline.",
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: "JSON", style: .default) { [weak self] _ in
            self?.exportJSON()
        })
        alert.addAction(UIAlertAction(title: "CSV Timeline", style: .default) { [weak self] _ in
            self?.exportCSV()
        })
        alert.addAction(UIAlertAction(title: localized("button_cancel", fallback: "Cancel"), style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItem
        }
        present(alert, animated: true)
    }

    private func exportJSON() {
        do {
            presentShare(url: try store.exportJSONURL())
        } catch {
            presentError(error)
        }
    }

    private func exportCSV() {
        do {
            presentShare(url: try store.exportCSVURL())
        } catch {
            presentError(error)
        }
    }

    private func presentShare(url: URL) {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItem
        }
        present(controller, animated: true)
    }

    private func presentError(_ error: Error) {
        let alert = UIAlertController(title: "Export failed", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: localized("button_confirm", fallback: "OK"), style: .default))
        present(alert, animated: true)
    }

    private func date(_ value: Date) -> String {
        ISO8601DateFormatter().string(from: value)
    }

    private func rate(_ value: Double?) -> String {
        value.map { String(format: "%.2f/s", $0) } ?? "—"
    }

    private func milliseconds(_ value: Double?) -> String {
        value.map { String(format: "%.1f ms", $0) } ?? "—"
    }

    private func localized(_ key: String, fallback: String) -> String {
        let value = PTDashboardConfig.languageFunc(text: key)
        return value == key ? fallback : value
    }
}
