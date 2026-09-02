//
//  PTCANLabViewController.swift
//  CrazyDashboard
//
//  EN: Offline CAN capture history for riders, with live capture limited to the developer surface.
//  ES: Historial de capturas CAN sin conexión para pilotos; la captura en vivo queda limitada al área de desarrollador.
//  中文：面向骑手的离线 CAN 抓包历史，实时抓包只允许从开发者界面进入。
//

import UIKit
import PooTools
import SafeSFSymbols

@MainActor
enum PTCANLabMode {
    case publicHistory
    case developerCapture
}

@MainActor
final class PTCANLabViewController: PTMotoBaseViewController {
    private let mode: PTCANLabMode
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let statusLabel = UILabel()
    private let startButton = UIButton(type: .system)
    private let stopButton = UIButton(type: .system)
    private let markButton = UIButton(type: .system)
    private var files: [URL] = []
    private var comparisonFiles: [URL] = []
    private var captureTask: Task<Void, Never>?
    private var safetyObserver: NSObjectProtocol?

    lazy var reloadButton:PTBaseButton = {
        let view = PTBaseButton(type:.custom)
        view.setImage(UIImage(.arrow.clockwise).withTintColor(.white, renderingMode: .alwaysOriginal), for: .normal)
        view.bounds = .init(origin: .zero, size: .init(width: PTAppBaseConfig.share.navBarButtonSize, height: PTAppBaseConfig.share.navBarButtonSize))
        view.addActionHandlers(handler: { _ in
            self.reloadFiles()
        })
        return view
    }()
    
    init(mode: PTCANLabMode = .publicHistory) {
        self.mode = mode
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        pt_Title = localized(mode == .developerCapture ? "can_lab_developer_title" : "can_lab_title")
        configureTable()
        if mode == .developerCapture {
            configureCaptureControls()
            observeDeveloperSafetyState()
        }
        reloadFiles()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setCustomRightButtons(buttons: [reloadButton])
        reloadFiles()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if mode == .developerCapture, captureTask != nil {
            stopCapture()
        }
    }

    private func configureTable() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.tableFooterView = UIView(frame: .zero)
        tableView.backgroundColor = .clear
        view.addSubview(tableView)

        if mode == .developerCapture {
            tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 126, right: 0)
        }
        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func configureCaptureControls() {
        statusLabel.text = localized("can_lab_capture_idle")
        statusLabel.textColor = .secondaryLabel
        statusLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        statusLabel.numberOfLines = 2

        configure(button: startButton, title: localized("can_lab_capture_start"), color: .systemGreen)
        configure(button: stopButton, title: localized("can_lab_capture_stop"), color: .systemRed)
        configure(button: markButton, title: localized("can_lab_capture_mark"), color: .systemOrange)
        startButton.addTarget(self, action: #selector(startCapture), for: .touchUpInside)
        stopButton.addTarget(self, action: #selector(stopCapture), for: .touchUpInside)
        markButton.addTarget(self, action: #selector(markCaptureEvent), for: .touchUpInside)
        stopButton.isEnabled = false
        markButton.isEnabled = false

        let stack = UIStackView(arrangedSubviews: [statusLabel, startButton, stopButton, markButton])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.backgroundColor = .secondarySystemGroupedBackground
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            startButton.heightAnchor.constraint(equalToConstant: 36),
            stopButton.heightAnchor.constraint(equalToConstant: 36),
            markButton.heightAnchor.constraint(equalToConstant: 36)
        ])
    }

    private func configure(button: UIButton, title: String, color: UIColor) {
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = color.withAlphaComponent(0.85)
        button.layer.cornerRadius = 8
    }

    @objc private func reloadFiles() {
        files = PTCANCaptureStore.shared.allCaptureFiles()
        tableView.reloadData()
    }

    @objc private func startCapture() {
        guard mode == .developerCapture, captureTask == nil else { return }
        guard PTDeveloperSafetyGate.shared.authorize(.canCapture) else {
            statusLabel.text = localized("can_lab_capture_denied")
            return
        }
        let name = "XP400-\(Int(Date().timeIntervalSince1970))"
        statusLabel.text = localized("can_lab_capture_starting")
        updateCaptureControls(isCapturing: true)
        captureTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await PTMotoTelemetryManager.shared.startPTCANExperiment(name: name)
            guard !Task.isCancelled else { return }
            statusLabel.text = localized("can_lab_capture_running")
        }
    }

    @objc private func stopCapture() {
        stopActiveCapture(statusKey: nil)
    }

    // EN: Stop an active capture and preserve the reason when the safety gate revoked it.
    // ES: Detiene una captura activa y conserva el motivo cuando la puerta de seguridad la revoca.
    // 中文：停止活动抓包，并在安全门禁撤销时保留停止原因。
    private func stopActiveCapture(statusKey: String?) {
        guard mode == .developerCapture, captureTask != nil else { return }
        captureTask?.cancel()
        captureTask = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            let session = await PTMotoTelemetryManager.shared.stopPTCANExperiment()
            if let statusKey {
                statusLabel.text = localized(statusKey)
            } else {
                statusLabel.text = session == nil
                    ? localized("can_lab_capture_empty")
                    : localized("can_lab_capture_saved")
            }
            updateCaptureControls(isCapturing: false)
            reloadFiles()
        }
    }

    // EN: A gate reset stops only developer capture; public capture history remains available.
    // ES: Un reinicio de la puerta detiene solo la captura de desarrollador; el historial público sigue disponible.
    // 中文：门禁重置只停止开发者抓包，公开的历史浏览功能仍然可用。
    private func observeDeveloperSafetyState() {
        safetyObserver = NotificationCenter.default.addObserver(
            forName: PTDeveloperSafetyGate.stateDidChange,
            object: PTDeveloperSafetyGate.shared,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleDeveloperSafetyReset()
            }
        }
    }

    // EN: The next explicit developer action can start a fresh capture after re-authorization.
    // ES: La siguiente acción explícita de desarrollador puede iniciar una captura nueva tras reautorizar.
    // 中文：重新授权后，下一次明确的开发者操作可以开始新的抓包。
    private func handleDeveloperSafetyReset() {
        guard mode == .developerCapture, captureTask != nil else { return }
        guard !PTDeveloperSafetyGate.shared.isEnabled else { return }
        stopActiveCapture(statusKey: "can_lab_capture_stopped_safety")
    }

    @objc private func markCaptureEvent() {
        guard captureTask != nil else { return }
        let name = "manual-\(Date().formatted(date: .omitted, time: .standard))"
        if PTCANRecorder.shared.markEvent(name) != nil {
            statusLabel.text = localized("can_lab_capture_marked")
        }
    }

    private func updateCaptureControls(isCapturing: Bool) {
        startButton.isEnabled = !isCapturing
        stopButton.isEnabled = isCapturing
        markButton.isEnabled = isCapturing
        startButton.alpha = isCapturing ? 0.45 : 1
        stopButton.alpha = isCapturing ? 1 : 0.45
        markButton.alpha = isCapturing ? 1 : 0.45
    }

    private func presentActions(for fileURL: URL) {
        let alert = UIAlertController(
            title: fileURL.lastPathComponent,
            message: localized("can_lab_file_actions_hint"),
            preferredStyle: .actionSheet
        )
        if fileURL.pathExtension.lowercased() == "json" || fileURL.pathExtension.lowercased() == "jsonl" {
            alert.addAction(UIAlertAction(title: localized("can_lab_analyze"), style: .default) { [weak self] _ in
                self?.analyze(fileURL: fileURL)
            })
            alert.addAction(UIAlertAction(title: localized("can_lab_select_compare"), style: .default) { [weak self] _ in
                self?.toggleComparison(fileURL: fileURL)
            })
        }
        alert.addAction(UIAlertAction(title: localized("can_lab_share"), style: .default) { [weak self] _ in
            guard let self else { return }
            PTCANCaptureShare.present(from: self, fileURL: fileURL)
        })
        alert.addAction(UIAlertAction(title: localized("can_lab_delete"), style: .destructive) { [weak self] _ in
            self?.confirmDelete(fileURL: fileURL)
        })
        alert.addAction(UIAlertAction(title: localized("button_cancel"), style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        }
        present(alert, animated: true)
    }

    private func analyze(fileURL: URL) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let session = try await loadSession(fileURL: fileURL)
                let summaries = PTCANCaptureAnalyzer.summarize(session)
                var lines = [
                    "\(localized("can_lab_frames")): \(session.frameCount)",
                    "\(localized("can_lab_duration")): \(String(format: "%.1fs", session.duration))",
                    "\(localized("can_lab_events")): \(session.events.count)"
                ]
                lines.append(contentsOf: summaries.prefix(20).map {
                    "\($0.header) · \($0.frameCount) · \(String(format: "%.3fs", $0.averagePeriod ?? 0))"
                })
                lines.append("\n[\(localized("can_lab_candidates"))]")
                let candidates = PTCANCaptureAnalyzer.candidateSignals(session)
                if candidates.isEmpty {
                    lines.append(localized("can_lab_no_candidates"))
                } else {
                    lines.append(contentsOf: candidates.map {
                        "\($0.header) · \($0.frameCount) frames · \($0.payloadVariants) payloads · \(String(format: "%.3fs", $0.averagePeriod ?? 0))"
                    })
                }

                if !session.events.isEmpty {
                    lines.append("\n[\(localized("can_lab_event_analysis"))]")
                    for event in session.events.prefix(10) {
                        let analysis = PTCANEventAnalyzer.analyze(
                            session: session,
                            eventTimestamp: event.timestamp
                        )
                        let interestingIDs = analysis.interestingIDs.prefix(5).map(\.header)
                        if interestingIDs.isEmpty {
                            lines.append("\(event.name): \(localized("can_lab_event_no_changes"))")
                        } else {
                            lines.append("\(event.name): \(interestingIDs.joined(separator: ", "))")
                        }
                    }
                }
                showMessage(title: localized("can_lab_analysis"), message: lines.joined(separator: "\n"))
            } catch {
                showMessage(title: localized("can_lab_analysis"), message: error.localizedDescription)
            }
        }
    }

    private func loadSession(fileURL: URL) async throws -> PTCANCaptureSession {
        try await Task.detached(priority: .utility) {
            switch fileURL.pathExtension.lowercased() {
            case "json": return try PTCANCaptureStore.shared.loadJSON(from: fileURL)
            case "jsonl": return try PTCANCaptureStore.shared.loadJSONL(from: fileURL)
            default: throw PTCANCaptureReplayError.unsupportedFile
            }
        }.value
    }

    private func toggleComparison(fileURL: URL) {
        if let index = comparisonFiles.firstIndex(of: fileURL) {
            comparisonFiles.remove(at: index)
        } else if comparisonFiles.count < 2 {
            comparisonFiles.append(fileURL)
        } else {
            comparisonFiles = [comparisonFiles[1], fileURL]
        }
        if comparisonFiles.count == 2 {
            compareSelectedFiles()
        }
    }

    private func compareSelectedFiles() {
        guard comparisonFiles.count == 2 else { return }
        let selected = comparisonFiles
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let left = try await loadSession(fileURL: selected[0])
                let right = try await loadSession(fileURL: selected[1])
                let diff = PTCANCaptureAnalyzer.byteDiff(left: left, right: right)
                let lines = diff.prefix(40).map {
                    "\($0.header): \($0.changedByteCount) bytes / \($0.changedBitCount) bits"
                }
                showMessage(
                    title: localized("can_lab_compare"),
                    message: lines.isEmpty ? localized("can_lab_no_changes") : lines.joined(separator: "\n")
                )
            } catch {
                showMessage(title: localized("can_lab_compare"), message: error.localizedDescription)
            }
        }
    }

    private func confirmDelete(fileURL: URL) {
        let alert = UIAlertController(
            title: localized("can_lab_delete"),
            message: localized("can_lab_delete_hint"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: localized("can_lab_delete"), style: .destructive) { [weak self] _ in
            do {
                try PTCANCaptureStore.shared.delete(fileURL: fileURL)
                self?.comparisonFiles.removeAll { $0 == fileURL }
                self?.reloadFiles()
            } catch {
                self?.showMessage(title: self?.localized("can_lab_delete") ?? "", message: error.localizedDescription)
            }
        })
        alert.addAction(UIAlertAction(title: localized("button_cancel"), style: .cancel))
        present(alert, animated: true)
    }

    private func showMessage(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: localized("button_confirm"), style: .default))
        present(alert, animated: true)
    }

    private func localized(_ key: String) -> String {
        PTDashboardConfig.languageFunc(text: key)
    }

    @MainActor deinit {
        if let safetyObserver {
            NotificationCenter.default.removeObserver(safetyObserver)
        }
    }
}

extension PTCANLabViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        files.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "PTCANLabCell")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "PTCANLabCell")
        let fileURL = files[indexPath.row]
        let size = PTCANCaptureStore.shared.fileSize(at: fileURL)
        cell.textLabel?.text = fileURL.deletingPathExtension().lastPathComponent
        cell.detailTextLabel?.text = "\(fileURL.pathExtension.uppercased()) · \(size) B"
        cell.accessoryType = comparisonFiles.contains(fileURL) ? .checkmark : .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        presentActions(for: files[indexPath.row])
    }
}
