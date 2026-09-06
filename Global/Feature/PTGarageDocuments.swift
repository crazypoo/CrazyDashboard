//
//  PTGarageDocuments.swift
//  CrazyDashboard
//
//  EN: Local vehicle-document storage and a small UIKit browser for the garage.
//  ES: Almacenamiento local de documentos del vehículo y un navegador UIKit para el garaje.
//  中文：车辆资料的本地存储与车库资料浏览页面。
//

import UIKit
import UniformTypeIdentifiers
import VisionKit
import PooTools
import SafeSFSymbols
import SnapKit

nonisolated public enum PTGarageAttachmentKind: String, Codable, Sendable {
    case document
    case scan
}

nonisolated public struct PTGarageAttachment: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let vehicleID: UUID
    public let fileName: String
    public let localFileName: String
    public let kind: PTGarageAttachmentKind
    public let typeIdentifier: String
    public let byteCount: Int
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        vehicleID: UUID,
        fileName: String,
        localFileName: String,
        kind: PTGarageAttachmentKind,
        typeIdentifier: String,
        byteCount: Int,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.vehicleID = vehicleID
        self.fileName = fileName
        self.localFileName = localFileName
        self.kind = kind
        self.typeIdentifier = typeIdentifier
        self.byteCount = byteCount
        self.createdAt = createdAt
    }
}

nonisolated public enum PTGarageAttachmentError: Error, LocalizedError, Equatable, Sendable {
    case fileTooLarge(maximumBytes: Int)
    case emptyFile
    case storageUnavailable
    case attachmentNotFound

    public var errorDescription: String? {
        switch self {
        case let .fileTooLarge(maximumBytes):
            return "资料超过大小限制（\(maximumBytes) bytes）"
        case .emptyFile:
            return "资料文件为空"
        case .storageUnavailable:
            return "本地资料目录不可用"
        case .attachmentNotFound:
            return "找不到资料文件"
        }
    }
}

// EN: Keep binary attachments local; garage profiles and settings retain their existing iCloud path.
// ES: Mantiene los adjuntos binarios en el dispositivo; los perfiles conservan su ruta iCloud existente.
// 中文：二进制资料只保存在本机，车库档案和设置继续沿用现有 iCloud 路径。
@MainActor
public final class PTGarageAttachmentStore {
    public static let shared = PTGarageAttachmentStore()
    public static let maximumFileSize = 20 * 1024 * 1024

    private static let metadataKey = "PTGarageAttachmentStore.v1"
    private let userDefaults: UserDefaults
    private let fileManager: FileManager
    private let storageDirectory: URL
    public private(set) var attachments: [PTGarageAttachment]

    public init(
        userDefaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        storageDirectory: URL? = nil
    ) {
        self.userDefaults = userDefaults
        self.fileManager = fileManager
        self.storageDirectory = storageDirectory
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("PTGarageDocuments", isDirectory: true)
        self.attachments = []
        load()
        try? fileManager.createDirectory(at: self.storageDirectory, withIntermediateDirectories: true)
    }

    public func attachments(for vehicleID: UUID) -> [PTGarageAttachment] {
        attachments
            .filter { $0.vehicleID == vehicleID }
            .sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    public func importData(
        _ data: Data,
        fileName: String,
        vehicleID: UUID,
        kind: PTGarageAttachmentKind = .document,
        typeIdentifier: String? = nil
    ) throws -> PTGarageAttachment {
        guard !data.isEmpty else { throw PTGarageAttachmentError.emptyFile }
        guard data.count <= Self.maximumFileSize else {
            throw PTGarageAttachmentError.fileTooLarge(maximumBytes: Self.maximumFileSize)
        }
        try ensureStorageDirectory()

        let id = UUID()
        let cleanedName = Self.sanitizedFileName(fileName)
        let localFileName = "\(id.uuidString)-\(cleanedName)"
        let fileURL = storageDirectory.appendingPathComponent(localFileName)
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw PTGarageAttachmentError.storageUnavailable
        }

        let record = PTGarageAttachment(
            id: id,
            vehicleID: vehicleID,
            fileName: cleanedName,
            localFileName: localFileName,
            kind: kind,
            typeIdentifier: typeIdentifier
                ?? UTType(filenameExtension: fileURL.pathExtension)?.identifier
                ?? UTType.data.identifier,
            byteCount: data.count
        )
        attachments.append(record)
        persist()
        return record
    }

    public func fileURL(for attachment: PTGarageAttachment) -> URL? {
        guard attachments.contains(where: { $0.id == attachment.id }) else { return nil }
        let url = storageDirectory.appendingPathComponent(attachment.localFileName)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    public func delete(_ attachment: PTGarageAttachment) throws {
        guard let index = attachments.firstIndex(where: { $0.id == attachment.id }) else {
            throw PTGarageAttachmentError.attachmentNotFound
        }
        let url = storageDirectory.appendingPathComponent(attachment.localFileName)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        attachments.remove(at: index)
        persist()
    }
}

private extension PTGarageAttachmentStore {
    func load() {
        guard let data = userDefaults.data(forKey: Self.metadataKey),
              let values = try? JSONDecoder().decode([PTGarageAttachment].self, from: data) else {
            return
        }
        attachments = values.filter {
            fileManager.fileExists(atPath: storageDirectory.appendingPathComponent($0.localFileName).path)
        }
    }

    func persist() {
        guard let data = try? JSONEncoder().encode(attachments) else { return }
        userDefaults.set(data, forKey: Self.metadataKey)
    }

    func ensureStorageDirectory() throws {
        do {
            try fileManager.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        } catch {
            throw PTGarageAttachmentError.storageUnavailable
        }
    }

    static func sanitizedFileName(_ value: String) -> String {
        let name = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
        return String((name.isEmpty ? "vehicle-document" : name).prefix(120))
    }
}

// EN: The screen deliberately offers import and camera scan, while sharing only the selected local file.
// ES: La pantalla ofrece importación y escaneo, y solo comparte el archivo local elegido.
// 中文：页面提供导入和相机扫描，只分享用户选中的本地文件。
@MainActor
final class PTGarageDocumentsViewController: PTMotoBaseViewController,
                                              UIDocumentPickerDelegate,
                                              VNDocumentCameraViewControllerDelegate,
                                              UITableViewDataSource,
                                              UITableViewDelegate {
    private let vehicleID: UUID
    private let store: PTGarageAttachmentStore
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let emptyStateLabel = UILabel()

    lazy var addButton:PTBaseButton = {
        let view = PTBaseButton(type: .custom)
        view.setImage(UIImage(.plus.circle).withTintColor(.white, renderingMode: .alwaysOriginal), for: .normal)
        view.bounds = .init(origin: .zero, size: .init(width: PTAppBaseConfig.share.navBarButtonSize, height: PTAppBaseConfig.share.navBarButtonSize))
        view.addActionHandlers(handler: { _ in
            self.showAddMenu()
        })
        view.titleLabel?.accessibilityLabel = PTDashboardConfig.languageFunc(text: "garage_document_import")
        return view
    }()
    
    init(vehicleID: UUID, store: PTGarageAttachmentStore? = nil) {
        self.vehicleID = vehicleID
        self.store = store ?? PTGarageAttachmentStore.shared
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        pt_Title = PTDashboardConfig.languageFunc(text: "garage_documents")
        view.backgroundColor = .black
        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 64
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "PTGarageAttachmentCell")
        emptyStateLabel.text = PTDashboardConfig.languageFunc(text: "garage_document_empty")
        emptyStateLabel.textColor = .systemGray
        emptyStateLabel.textAlignment = .center
        emptyStateLabel.numberOfLines = 0
        emptyStateLabel.accessibilityIdentifier = "garageDocuments.emptyState"
        tableView.backgroundView = emptyStateLabel
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.top.equalToSuperview().inset(CGFloat.kNavBarHeight_Total)
        }
        updateEmptyState()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
        updateEmptyState()
        setCustomRightButtons(buttons: [addButton], buttonSpacing: CGFloat.GlobalItemSpacing)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        store.attachments(for: vehicleID).count
    }

    func tableView(_ tableView: UITableView,
                   cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "PTGarageAttachmentCell", for: indexPath)
        let attachment = store.attachments(for: vehicleID)[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = attachment.fileName
        content.secondaryText = "\(attachment.kind.rawValue) · \(Self.byteText(attachment.byteCount))"
        content.textProperties.color = .white
        content.secondaryTextProperties.color = .systemGray
        content.image = UIImage(systemName: attachment.kind == .scan ? "doc.text.viewfinder" : "doc.fill")
        content.imageProperties.tintColor = PTDashboardConfig.shared.appMainColor
        cell.contentConfiguration = content
        cell.backgroundColor = .clear
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let attachment = store.attachments(for: vehicleID)[indexPath.row]
        guard let url = store.fileURL(for: attachment) else {
            showMessage(PTDashboardConfig.languageFunc(text: "garage_document_failed"))
            return
        }
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.sourceView = tableView
            popover.sourceRect = tableView.rectForRow(at: indexPath)
        }
        present(controller, animated: true)
    }

    func tableView(_ tableView: UITableView,
                   trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath)
        -> UISwipeActionsConfiguration? {
        let action = UIContextualAction(style: .destructive,
                                        title: PTDashboardConfig.languageFunc(text: "garage_document_delete")) {
            [weak self] _, _, completion in
            guard let self else {
                completion(false)
                return
            }
            do {
                try self.store.delete(self.store.attachments(for: self.vehicleID)[indexPath.row])
                tableView.deleteRows(at: [indexPath], with: .automatic)
                self.updateEmptyState()
                completion(true)
            } catch {
                self.showMessage(error.localizedDescription)
                completion(false)
            }
        }
        return UISwipeActionsConfiguration(actions: [action])
    }

    @objc private func showAddMenu() {
        let alert = UIAlertController(
            title: PTDashboardConfig.languageFunc(text: "garage_documents"),
            message: nil,
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(
            title: PTDashboardConfig.languageFunc(text: "garage_document_import"),
            style: .default
        ) { [weak self] _ in self?.presentDocumentPicker() })
        if VNDocumentCameraViewController.isSupported {
            alert.addAction(UIAlertAction(
                title: PTDashboardConfig.languageFunc(text: "garage_document_scan"),
                style: .default
            ) { [weak self] _ in self?.presentDocumentScanner() })
        }
        alert.addAction(UIAlertAction(
            title: PTDashboardConfig.languageFunc(text: "button_cancel"),
            style: .cancel
        ))
        if let popover = alert.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItem
        }
        present(alert, animated: true)
    }

    private func presentDocumentPicker() {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.pdf, .image, .data],
            asCopy: true
        )
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    private func presentDocumentScanner() {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = self
        present(scanner, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController,
                        didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        let didAccess = url.startAccessingSecurityScopedResource()
        Task { @MainActor [weak self] in
            defer {
                if didAccess { url.stopAccessingSecurityScopedResource() }
            }
            do {
                let data = try await Task.detached(priority: .utility) {
                    try Data(contentsOf: url, options: .mappedIfSafe)
                }.value
                guard let self else { return }
                _ = try self.store.importData(
                    data,
                    fileName: url.lastPathComponent,
                    vehicleID: self.vehicleID,
                    typeIdentifier: UTType(filenameExtension: url.pathExtension)?.identifier
                )
                self.tableView.reloadData()
                self.updateEmptyState()
            } catch {
                self?.showMessage(error.localizedDescription)
            }
        }
    }

    func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                      didFinishWith scan: VNDocumentCameraScan) {
        dismiss(animated: true)
        guard scan.pageCount > 0 else { return }
        let images = (0..<scan.pageCount).compactMap { scan.imageOfPage(at: $0) }
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        let pdfData = renderer.pdfData { context in
            for image in images {
                context.beginPage()
                let pageRect = CGRect(x: 24, y: 24, width: 564, height: 744)
                let scale = min(pageRect.width / image.size.width, pageRect.height / image.size.height)
                let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                image.draw(in: CGRect(
                    x: pageRect.midX - size.width / 2,
                    y: pageRect.midY - size.height / 2,
                    width: size.width,
                    height: size.height
                ))
            }
        }
        do {
            _ = try store.importData(
                pdfData,
                fileName: "Vehicle-Scan-\(Self.fileDate()).pdf",
                vehicleID: vehicleID,
                kind: .scan,
                typeIdentifier: UTType.pdf.identifier
            )
            tableView.reloadData()
            updateEmptyState()
        } catch {
            showMessage(error.localizedDescription)
        }
    }

    func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
        dismiss(animated: true)
    }

    func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                      didFailWithError error: Error) {
        dismiss(animated: true)
        showMessage(error.localizedDescription)
    }
}

private extension PTGarageDocumentsViewController {
    static func byteText(_ value: Int) -> String {
        if value >= 1_048_576 { return String(format: "%.1f MB", Double(value) / 1_048_576) }
        return String(format: "%.1f KB", Double(value) / 1_024)
    }

    static func fileDate() -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
    }

    func showMessage(_ message: String) {
        let alert = UIAlertController(
            title: PTDashboardConfig.languageFunc(text: "alert_title"),
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(
            title: PTDashboardConfig.languageFunc(text: "button_confirm"),
            style: .default
        ))
        present(alert, animated: true)
    }

    // EN: Keep the empty state in the table background so it never becomes a fake attachment row.
    // ES: Mantiene el estado vacío en el fondo de la tabla para no convertirlo en una fila falsa.
    // 中文：将空状态放在表格背景中，避免它被误认为资料行。
    func updateEmptyState() {
        emptyStateLabel.isHidden = !store.attachments(for: vehicleID).isEmpty
    }
}
