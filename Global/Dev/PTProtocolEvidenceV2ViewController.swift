//
//  PTProtocolEvidenceV2ViewController.swift
//  CrazyDashboard
//
//  EN: Presents Build 60 protocol evidence as a read-only, source-aware developer report.
//  ES: Presenta la evidencia de protocolo de Build 60 como un informe de desarrollador de solo lectura y consciente de su fuente.
//  中文：以只读、带来源信息的开发者报告形式展示 Build 60 协议证据。
//

import UIKit
import PooTools
import SafeSFSymbols

@MainActor
class PTProtocolEvidenceV2ViewController: PTMotoBaseViewController {
    private let store: PTProtocolEvidenceV2Store
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private var refreshTask: Task<Void, Never>?

    lazy var reloadButton:PTBaseButton = {
        let view = PTBaseButton(type:.custom)
        view.setImage(UIImage(.arrow.clockwise).withTintColor(.white, renderingMode: .alwaysOriginal), for: .normal)
        view.bounds = .init(origin: .zero, size: .init(width: PTAppBaseConfig.share.navBarButtonSize, height: PTAppBaseConfig.share.navBarButtonSize))
        view.addActionHandlers(handler: { _ in
            self.refreshTapped()
        })
        return view
    }()
    
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
        self.init(store: PTProtocolEvidenceV2Store.shared)
    }

    public init(store: PTProtocolEvidenceV2Store) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        pt_Title = localized("dev_protocol_evidence_v2_title", fallback: "Protocol Evidence 2.0")
        view.backgroundColor = .black
        configureLayout()
        render()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshEvidence()
        setCustomRightButtons(buttons: [exportButton,reloadButton], buttonSpacing: CGFloat.GlobalItemSpacing)
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func configureLayout() {
        scrollView.alwaysBounceVertical = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        stackView.axis = .vertical
        stackView.spacing = 12
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

    private func refreshEvidence() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await store.refresh()
            guard !Task.isCancelled else { return }
            render()
        }
    }

    @objc private func refreshTapped() {
        refreshEvidence()
    }

    private func render() {
        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let domainCounts = PTProtocolEvidenceDomain.allCases.map { domain in
            "\(domain.rawValue): \(store.records(for: domain).count)"
        }.joined(separator: "\n")
        let currentCorrelation = store.correlation()
        let passport = store.passport()

        addPanel(
            title: "Overview",
            body: [
                "Read-only evidence: yes",
                "Records: \(store.records.count)",
                "CAN candidates: \(store.canCandidates.count)",
                "Vehicle source domains: XP400 BLE, OBD, CAN, UDS",
                "Adapter maintenance is excluded from vehicle correlation"
            ].joined(separator: "\n"),
            accent: .systemBlue
        )
        let usage = store.storageUsage()
        let databaseState = store.databaseStatus.message.map { "(store.databaseStatus.state.rawValue): \($0)" }
            ?? store.databaseStatus.state.rawValue
        addPanel(
            title: "Storage",
            body: [
                "Database: \(formatBytes(usage.evidenceDatabaseBytes))",
                "Trace: \(formatBytes(usage.traceBytes))",
                "CAN Capture: \(formatBytes(usage.canCaptureBytes))",
                "Instrument Export: \(formatBytes(usage.instrumentExportBytes))",
                "Total: \(formatBytes(usage.totalBytes))",
                "State: \(databaseState)",
                "Migration completed: \(store.databaseStatus.migrationCompleted ? "yes" : "no")"
            ].joined(separator: "\n"),
            accent: .systemBrown
        )
        addPanel(title: "Evidence Domains", body: domainCounts, accent: .systemTeal)
        addPanel(title: "CAN Discovery", body: formatCANCandidates(), accent: .systemOrange)
        addPanel(title: "Cross-source Correlation", body: formatCorrelation(currentCorrelation), accent: .systemGreen)
        addPanel(
            title: localized("dev_protocol_evidence_build69", fallback: "Build 69 Semantic Evidence"),
            body: formatBuild69Evidence(),
            footer: "Read-only semantic evidence; candidates and anomalies are not executable commands.",
            accent: .systemCyan
        )
        addPanel(title: "Vehicle Passport", body: formatPassport(passport, adapter: false), accent: .systemIndigo)
        addPanel(
            title: "Diagnostic Adapter",
            body: formatPassport(passport, adapter: true),
            footer: "YMOBD firmware belongs to the adapter only; it is not XP400 firmware.",
            accent: .systemPurple
        )
        addPanel(title: "Capture Templates", body: formatTemplates(), accent: .systemPink)
    }

    private func formatCANCandidates() -> String {
        guard !store.canCandidates.isEmpty else {
            return "No candidate yet. Mark one reversible event during a passive CAN capture."
        }
        return store.canCandidates.prefix(12).map { candidate in
            let bytes = candidate.changedByteIndexes.map(String.init).joined(separator: ",")
            let bits = candidate.changedBits.map(String.init).joined(separator: ",")
            return [
                "\(candidate.header): bytes=[\(bytes)] bits=[\(bits)]",
                "score=\(candidate.score), confidence=\(formatConfidence(candidate.confidence)), source=\(candidate.source.rawValue)",
                "before=\(candidate.dominantBeforePayload ?? "—") after=\(candidate.dominantAfterPayload ?? "—")",
                "\(date(candidate.timestamp)) · \(candidate.note)"
            ].joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    private func formatCorrelation(_ report: PTProtocolEvidenceCorrelationReport) -> String {
        let sourceLine = report.sources.map(\.rawValue).joined(separator: ", ")
        let entries = report.entries.suffix(20).map { entry in
            "\(entry.source.rawValue) / \(entry.domain?.rawValue ?? "—") · \(formatConfidence(entry.confidence)) · \(entry.summary)"
        }
        return [
            "Window: \(date(report.startedAt)) → \(date(report.endedAt))",
            "Sources: \(sourceLine.isEmpty ? "—" : sourceLine)",
            entries.isEmpty ? "No vehicle evidence in the current window." : entries.joined(separator: "\n")
        ].joined(separator: "\n")
    }

    private func formatPassport(_ passport: PTVehiclePassport, adapter: Bool) -> String {
        let fields = adapter ? passport.adapterFields : passport.vehicleFields
        guard !fields.isEmpty else { return "—" }
        return fields.map { field in
            "\(field.key): \(field.displayValue) [source=\(field.source.rawValue), time=\(date(field.timestamp)), confidence=\(formatConfidence(field.confidence))]"
        }.joined(separator: "\n")
    }

    private func formatTemplates() -> String {
        PTProtocolEvidenceCaptureTemplateCatalog.templates.map { template in
            let safety = template.readOnly ? "read-only" : "not read-only"
            let marker = template.requiresUserMarker ? "marker required" : "marker optional"
            return "\(template.id.rawValue) · \(template.domain.rawValue) · \(safety) · \(marker)\n\(template.purpose)"
        }.joined(separator: "\n\n")
    }

    // EN: Group Build 69 output by semantic quality and show the latest frame masks for protocol research.
    // ES: Agrupa la salida de Build 69 por calidad semántica y muestra las máscaras de la última trama para investigación.
    // 中文：按语义质量分组展示 Build 69 结果，并显示最新帧掩码供协议研究使用。
    private func formatBuild69Evidence() -> String {
        let build69Store = PTBuild69EvidenceStore.shared
        guard !build69Store.results.isEmpty else {
            return "No Build 69 semantic evidence yet. Start a passive dashboard session."
        }
        let fields = build69Store.results.flatMap(\.fieldObservations)
        let qualityCounts = PTXP400SemanticQuality.allCases.map { quality in
            "\(quality.rawValue)=\(fields.filter { $0.quality == quality }.count)"
        }.joined(separator: " · ")
        let roleCounts = PTXP400SemanticFieldRole.allCases.map { role in
            "\(role.rawValue)=\(fields.filter { $0.role == role }.count)"
        }.joined(separator: " · ")
        let candidates = build69Store.results
            .flatMap(\.candidates)
            .sorted { $0.score.total > $1.score.total }
            .prefix(8)
            .map { "\($0.fieldKey) score=\(String(format: "%.2f", $0.score.total)) samples=\($0.sampleCount)" }
        let anomalies = build69Store.results
            .flatMap(\.anomalies)
            .suffix(8)
            .map { "\($0.severity.rawValue): \($0.message)" }
        let latestInspector = build69Store.results.last.map { PTXP400FrameInspector.inspect(frame: $0.frame) }
        let inspectorLines = latestInspector.map { inspection in
            let bytes = inspection.bytes.map {
                let roles = $0.roles.map(\.rawValue).joined(separator: "/")
                return String(format: "%02d | %02X | known=%02X unknown=%02X | %@", $0.index, $0.rawValue, $0.knownMask, $0.unknownMask, roles.isEmpty ? "unknown" : roles)
            }.joined(separator: "\n")
            return "Latest: ID=0x\(String(format: "%02X", inspection.frameID)) \(inspection.name)\nknownMask=\(inspection.knownMaskHex) unknownMask=\(inspection.unknownMaskHex)\n\(bytes)"
        } ?? "Latest frame: —"
        return [
            "Results: \(build69Store.results.count) · markers=\(build69Store.markers.count)",
            "Quality: \(qualityCounts)",
            "Roles: \(roleCounts)",
            "Top candidates: \(candidates.isEmpty ? "—" : candidates.joined(separator: "; "))",
            "Recent anomalies: \(anomalies.isEmpty ? "—" : anomalies.joined(separator: "; "))",
            inspectorLines
        ].joined(separator: "\n")
    }

    // EN: Keep storage formatting at the UI boundary so the model remains numeric and testable.
    // ES: Mantiene el formato del almacenamiento en la frontera de UI para que el modelo siga siendo numérico y comprobable.
    // 中文：把空间格式化留在 UI 边界，模型继续保持数值化和可测试。
    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func addPanel(title: String, body: String, footer: String? = nil, accent: UIColor) {
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
        bodyLabel.lineBreakMode = .byCharWrapping

        var arrangedSubviews: [UIView] = [titleLabel, bodyLabel]
        if let footer {
            let footerLabel = UILabel()
            footerLabel.text = footer
            footerLabel.numberOfLines = 0
            footerLabel.font = .preferredFont(forTextStyle: .footnote)
            footerLabel.textColor = .secondaryLabel
            arrangedSubviews.append(footerLabel)
        }

        let content = UIStackView(arrangedSubviews: arrangedSubviews)
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

    @objc private func exportTapped() {
        let alert = UIAlertController(title: "Export Protocol Evidence", message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "JSON", style: .default) { [weak self] _ in
            self?.exportJSON()
        })
        alert.addAction(UIAlertAction(title: "CSV", style: .default) { [weak self] _ in
            self?.exportCSV()
        })
        alert.addAction(UIAlertAction(title: "Build 69 JSON", style: .default) { [weak self] _ in
            self?.exportBuild69JSON()
        })
        alert.addAction(UIAlertAction(title: "Build 69 CSV", style: .default) { [weak self] _ in
            self?.exportBuild69CSV()
        })
        alert.addAction(UIAlertAction(title: localized("button_cancel", fallback: "Cancel"), style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItems?.first
        }
        present(alert, animated: true)
    }

    private func exportJSON() {
        do {
            presentShare(try store.exportJSONURL())
        } catch {
            presentError(error)
        }
    }

    private func exportCSV() {
        do {
            presentShare(try store.exportCSVURL())
        } catch {
            presentError(error)
        }
    }

    private func exportBuild69JSON() {
        do {
            let data = try store.exportBuild69JSONData()
            presentShare(try writeExport(data: data, filename: "crazydashboard-protocol-evidence-v3.json"))
        } catch {
            presentError(error)
        }
    }

    private func exportBuild69CSV() {
        do {
            let data = store.exportBuild69CSVData()
            presentShare(try writeExport(data: data, filename: "crazydashboard-protocol-evidence-v3.csv"))
        } catch {
            presentError(error)
        }
    }

    private func writeExport(data: Data, filename: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }

    private func presentShare(_ url: URL) {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItems?.first
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

    private func formatConfidence(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func localized(_ key: String, fallback: String) -> String {
        let value = PTDashboardConfig.languageFunc(text: key)
        return value == key ? fallback : value
    }
}
