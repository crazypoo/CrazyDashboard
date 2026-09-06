//
//  PTRidePhotoGallery.swift
//  CrazyDashboard
//
//  EN: Privacy-friendly ride photos using PHPicker and app-private files.
//  ES: Fotos de ruta respetuosas con la privacidad mediante PHPicker y archivos privados de la app.
//  中文：使用 PHPicker 和 App 私有文件保存骑行照片，避免不必要的照片库权限。
//

import ImageIO
import PhotosUI
import UIKit
import UniformTypeIdentifiers
import PooTools

nonisolated public struct PTRidePhotoAttachment: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let tripID: String
    public let fileName: String
    public let localFileName: String
    public let byteCount: Int
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        tripID: String,
        fileName: String,
        localFileName: String,
        byteCount: Int,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.tripID = tripID
        self.fileName = fileName
        self.localFileName = localFileName
        self.byteCount = byteCount
        self.createdAt = createdAt
    }
}

nonisolated public enum PTRidePhotoError: Error, LocalizedError, Equatable, Sendable {
    case emptyFile
    case fileTooLarge(maximumBytes: Int)
    case storageUnavailable
    case photoNotFound

    public var errorDescription: String? {
        switch self {
        case .emptyFile:
            return "照片文件为空"
        case let .fileTooLarge(maximumBytes):
            return "照片超过大小限制（\(maximumBytes) bytes）"
        case .storageUnavailable:
            return "骑行照片目录不可用"
        case .photoNotFound:
            return "找不到骑行照片"
        }
    }
}

// EN: Photo files remain private to this device and are bounded to keep ride history responsive.
// ES: Las fotos permanecen privadas en este dispositivo y tienen un límite para mantener ágil el historial.
// 中文：照片只保存在本机私有目录，并设置大小和数量上限，避免拖慢行程历史。
@MainActor
public final class PTRidePhotoAttachmentStore {
    public static let shared = PTRidePhotoAttachmentStore()
    public static let maximumFileSize = 15 * 1024 * 1024
    public static let maximumRecordCount = 1_000

    private static let metadataKey = "PTRidePhotoAttachmentStore.v1"
    private let userDefaults: UserDefaults
    private let fileManager: FileManager
    private let storageDirectory: URL
    public private(set) var attachments: [PTRidePhotoAttachment]

    public init(
        userDefaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        storageDirectory: URL? = nil
    ) {
        self.userDefaults = userDefaults
        self.fileManager = fileManager
        self.storageDirectory = storageDirectory
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("PTRidePhotos", isDirectory: true)
        self.attachments = []
        load()
        try? fileManager.createDirectory(at: self.storageDirectory, withIntermediateDirectories: true)
    }

    public func attachments(for tripID: String) -> [PTRidePhotoAttachment] {
        attachments
            .filter { $0.tripID == tripID }
            .sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    public func add(
        data: Data,
        fileName: String,
        tripID: String
    ) throws -> PTRidePhotoAttachment {
        guard !data.isEmpty else { throw PTRidePhotoError.emptyFile }
        guard data.count <= Self.maximumFileSize else {
            throw PTRidePhotoError.fileTooLarge(maximumBytes: Self.maximumFileSize)
        }
        guard !tripID.isEmpty else { throw PTRidePhotoError.storageUnavailable }
        try ensureStorageDirectory()

        let id = UUID()
        let cleanedName = Self.sanitizedFileName(fileName)
        let localFileName = "\(id.uuidString)-\(cleanedName)"
        let fileURL = storageDirectory.appendingPathComponent(localFileName)
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw PTRidePhotoError.storageUnavailable
        }

        let attachment = PTRidePhotoAttachment(
            id: id,
            tripID: tripID,
            fileName: cleanedName,
            localFileName: localFileName,
            byteCount: data.count
        )
        attachments.append(attachment)
        trimIfNeeded()
        persist()
        return attachment
    }

    public func fileURL(for attachment: PTRidePhotoAttachment) -> URL? {
        guard attachments.contains(where: { $0.id == attachment.id }) else { return nil }
        let url = storageDirectory.appendingPathComponent(attachment.localFileName)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    public func delete(_ attachment: PTRidePhotoAttachment) throws {
        guard let index = attachments.firstIndex(where: { $0.id == attachment.id }) else {
            throw PTRidePhotoError.photoNotFound
        }
        let url = storageDirectory.appendingPathComponent(attachment.localFileName)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        attachments.remove(at: index)
        persist()
    }
}

private extension PTRidePhotoAttachmentStore {
    func load() {
        guard let data = userDefaults.data(forKey: Self.metadataKey),
              let values = try? JSONDecoder().decode([PTRidePhotoAttachment].self, from: data) else {
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

    func trimIfNeeded() {
        guard attachments.count > Self.maximumRecordCount else { return }
        let sorted = attachments.sorted { $0.createdAt < $1.createdAt }
        let removeCount = attachments.count - Self.maximumRecordCount
        for attachment in sorted.prefix(removeCount) {
            let url = storageDirectory.appendingPathComponent(attachment.localFileName)
            try? fileManager.removeItem(at: url)
        }
        let ids = Set(sorted.prefix(removeCount).map(\.id))
        attachments.removeAll { ids.contains($0.id) }
    }

    func ensureStorageDirectory() throws {
        do {
            try fileManager.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        } catch {
            throw PTRidePhotoError.storageUnavailable
        }
    }

    static func sanitizedFileName(_ value: String) -> String {
        let name = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
        let fallback = "ride-photo.jpg"
        return String((name.isEmpty ? fallback : name).prefix(120))
    }
}

// EN: Downsample selected images before writing them to avoid preserving multi-megapixel originals.
// ES: Reduce las imágenes seleccionadas antes de guardarlas para no conservar originales enormes.
// 中文：写入前先缩小照片，避免保存过大的多像素原图。
nonisolated private enum PTRidePhotoCodec {
    static func normalizedJPEG(data: Data) -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return data }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2_048
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return data
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return data
        }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.84] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return data }
        return output as Data
    }
}

// EN: The gallery uses PHPicker so the user grants access only to selected photos.
// ES: La galería usa PHPicker para que el usuario conceda acceso solo a las fotos seleccionadas.
// 中文：相册使用 PHPicker，用户只授权所选照片，不申请全部照片权限。
@MainActor
final class PTRidePhotoGalleryViewController: PTMotoBaseViewController,
                                              PHPickerViewControllerDelegate,
                                              UITableViewDataSource,
                                              UITableViewDelegate {
    private let tripID: String
    private let store: PTRidePhotoAttachmentStore
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let emptyStateLabel = UILabel()

    init(tripID: String, store: PTRidePhotoAttachmentStore? = nil) {
        self.tripID = tripID
        self.store = store ?? PTRidePhotoAttachmentStore.shared
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        pt_Title = PTDashboardConfig.languageFunc(text: "ride_replay_photos")
        view.backgroundColor = .black
        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 76
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "PTRidePhotoCell")
        emptyStateLabel.text = PTDashboardConfig.languageFunc(text: "ride_photo_empty")
        emptyStateLabel.textColor = .systemGray
        emptyStateLabel.textAlignment = .center
        emptyStateLabel.numberOfLines = 0
        emptyStateLabel.accessibilityIdentifier = "ridePhotos.emptyState"
        tableView.backgroundView = emptyStateLabel
        view.addSubview(tableView)
        tableView.frame = view.bounds
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(addPhotos)
        )
        navigationItem.rightBarButtonItem?.accessibilityLabel =
            PTDashboardConfig.languageFunc(text: "ride_photo_add")
        updateEmptyState()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
        updateEmptyState()
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        store.attachments(for: tripID).count
    }

    func tableView(_ tableView: UITableView,
                   cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "PTRidePhotoCell", for: indexPath)
        let attachment = store.attachments(for: tripID)[indexPath.row]
        cell.accessibilityIdentifier = attachment.id.uuidString
        var content = cell.defaultContentConfiguration()
        content.text = attachment.fileName
        content.secondaryText = Self.byteText(attachment.byteCount)
        content.textProperties.color = .white
        content.secondaryTextProperties.color = .systemGray
        content.image = UIImage(systemName: "photo.fill")
        content.imageProperties.tintColor = PTDashboardConfig.shared.appMainColor
        cell.contentConfiguration = content
        cell.backgroundColor = .clear

        if let url = store.fileURL(for: attachment) {
            Task { @MainActor [weak cell] in
                let data = try? await Task.detached(priority: .utility) {
                    try Data(contentsOf: url, options: .mappedIfSafe)
                }.value
                guard let cell,
                      cell.accessibilityIdentifier == attachment.id.uuidString,
                      let data,
                      let decodedImage = UIImage(data: data),
                      let image = await decodedImage.byPreparingThumbnail(ofSize: CGSize(width: 56, height: 56)) else {
                    return
                }
                var updated = cell.defaultContentConfiguration()
                updated.text = attachment.fileName
                updated.secondaryText = Self.byteText(attachment.byteCount)
                updated.textProperties.color = .white
                updated.secondaryTextProperties.color = .systemGray
                updated.image = image
                cell.contentConfiguration = updated
            }
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let attachment = store.attachments(for: tripID)[indexPath.row]
        guard let url = store.fileURL(for: attachment) else { return }
        navigationController?.pushViewController(
            PTRidePhotoPreviewViewController(title: attachment.fileName, fileURL: url),
            animated: true
        )
    }

    func tableView(_ tableView: UITableView,
                   trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath)
        -> UISwipeActionsConfiguration? {
        let action = UIContextualAction(
            style: .destructive,
            title: PTDashboardConfig.languageFunc(text: "garage_document_delete")
        ) { [weak self] _, _, completion in
            guard let self else {
                completion(false)
                return
            }
            do {
                try self.store.delete(self.store.attachments(for: self.tripID)[indexPath.row])
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

    @objc private func addPhotos() {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 20
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        dismiss(animated: true)
        guard !results.isEmpty else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            for result in results {
                do {
                    let data = try await Self.loadData(from: result.itemProvider)
                    let normalizedData = await Task.detached(priority: .utility) {
                        PTRidePhotoCodec.normalizedJPEG(data: data)
                    }.value
                    _ = try self.store.add(
                        data: normalizedData,
                        fileName: "Ride-\(UUID().uuidString.prefix(8)).jpg",
                        tripID: self.tripID
                    )
                } catch {
                    self.showMessage(error.localizedDescription)
                    break
                }
            }
            self.tableView.reloadData()
            self.updateEmptyState()
        }
    }
}

private extension PTRidePhotoGalleryViewController {
    static func loadData(from provider: NSItemProvider) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: PTRidePhotoError.emptyFile)
                }
            }
        }
    }

    static func byteText(_ value: Int) -> String {
        if value >= 1_048_576 { return String(format: "%.1f MB", Double(value) / 1_048_576) }
        return String(format: "%.1f KB", Double(value) / 1_024)
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

    // EN: Keep the empty state outside the data source so photo cells remain real files only.
    // ES: Mantiene el estado vacío fuera del origen de datos para que las celdas representen solo archivos reales.
    // 中文：将空状态放在数据源之外，确保照片单元格只代表真实文件。
    func updateEmptyState() {
        emptyStateLabel.isHidden = !store.attachments(for: tripID).isEmpty
    }
}

@MainActor
private final class PTRidePhotoPreviewViewController: PTMotoBaseViewController {
    private let fileURL: URL
    private let imageView = UIImageView()

    init(title: String, fileURL: URL) {
        self.fileURL = fileURL
        super.init(nibName: nil, bundle: nil)
        pt_Title = title
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.image = UIImage(contentsOfFile: fileURL.path)
        view.addSubview(imageView)
        imageView.frame = view.bounds.insetBy(dx: 16, dy: 16)
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }
}
